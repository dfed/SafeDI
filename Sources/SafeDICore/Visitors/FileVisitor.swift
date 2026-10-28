// Distributed under the MIT License
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import SwiftSyntax

/// A syntax visitor that can read an entire file.
public final class FileVisitor: SyntaxVisitor {
	// MARK: Initialization

	/// - Parameters:
	///   - conditionalCompilationEvaluator: Decides which clauses of each `#if` block are scanned. Defaults to no active conditions, which scans platform-conditioned blocks and skips blocks guarded by bare conditions.
	///   - sourceLocationConverter: A converter for the tree being walked. When provided, each declaration records where it begins.
	public init(
		conditionalCompilationEvaluator: ConditionalCompilationEvaluator = ConditionalCompilationEvaluator(activeCompilationConditions: []),
		sourceLocationConverter: SourceLocationConverter? = nil,
	) {
		self.conditionalCompilationEvaluator = conditionalCompilationEvaluator
		self.sourceLocationConverter = sourceLocationConverter
		super.init(viewMode: .sourceAccurate)
	}

	// MARK: SyntaxVisitor

	public override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
		// A protocol is no superclass, and a conforming type's lookup finds its associated types and type aliases only
		// when no type of the name is in scope at all.
		recordType(named: node.name.text, kind: .protocolType, modifiers: node.modifiers, attributes: node.attributes)
		return .skipChildren
	}

	public override func visit(_: MacroExpansionDeclSyntax) -> SyntaxVisitorContinueKind {
		// A freestanding macro among a type's members may declare member types SafeDI cannot see, whichever clause holds
		// it. A type declared in a trailing closure of a freestanding macro is local to the closure.
		if let parentPath, isParentTypeSpelledAsPath {
			nestedTypeDeclarations.record(.unseenMembers(ofTypeAt: parentPath))
		}
		return .skipChildren
	}

	public override func visit(_: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
		.skipChildren
	}

	public override func visit(_: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
		.skipChildren
	}

	public override func visit(_: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind {
		// A type declared in a body is local to it, not nested in the enclosing type.
		.skipChildren
	}

	public override func visit(_: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
		// A type declared in a body is local to it, not nested in the enclosing type.
		.skipChildren
	}

	public override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
		let importStatement = node.asImportStatement
		imports.append(importStatement)
		if importOnlyBlockDepth == 0 {
			// An import outside every block that guards only imports is selected the same way for mock code.
			mockImports.append(importStatement)
			if case let .imports(importStatements) = importSegments.last {
				importSegments[importSegments.count - 1] = .imports(importStatements + [importStatement])
			} else {
				importSegments.append(.imports([importStatement]))
			}
		}
		return .skipChildren
	}

	public override func visit(_: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
		.skipChildren
	}

	public override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
		recordType(named: node.name.text, kind: .typeAlias, modifiers: node.modifiers, attributes: node.attributes)
		return .skipChildren
	}

	public override func visit(_ node: IfConfigDeclSyntax) -> SyntaxVisitorContinueKind {
		// The block's declarations in every clause, including those of nested blocks, which this visitor
		// reaches again only in the clauses it scans.
		let (content, blockOutputFileDeclarations) = node.safeDIContentAmongDeclarations()
		outputFileDeclarations.formUnion(blockOutputFileDeclarations)
		let scannable = conditionalCompilationEvaluator.scannableClauses(in: node, guarding: content)
		record(scannable.decisions)
		if scannable.isCompilerDetermined {
			// The compiler may compile any of these clauses, so what they declare may not exist.
			compilerDeterminedClauses.formUnion(scannable.clauses.map(\.id))
		} else if content == .mockOnly {
			// A clause selected only because the mock condition is assumed active may not exist where production
			// code compiles.
			let productionClauses = Set(conditionalCompilationEvaluator.scannableClauses(in: node, guarding: .production).clauses.map(\.id))
			compilerDeterminedClauses.formUnion(scannable.clauses.map(\.id).filter { !productionClauses.contains($0) })
		}
		// The selection decides which declarations `nestedTypeDeclarations` records as existing, which may decide
		// generated code. Each declaration records the conditions and decisions of the blocks enclosing it, and
		// those in the clauses not selected are recorded as absent, with the same conditions and decisions.
		let blockConditions = DeclarationConditions(
			consultedCompilationConditions: scannable.consultedConditions,
			// A block guarding SafeDI content already reports the decisions its selection rests on, which for mock-only
			// content leave out the mock condition, as the code that reads them compiles only where it is active.
			conditionalCompilationDecisions: content == .none ? scannable.evaluatedDecisions : scannable.decisions,
		)
		let selectedClauses = Set(scannable.clauses.map(\.id))
		for clause in node.clauses {
			if selectedClauses.contains(clause.id) {
				clauseConditions[clause.id] = blockConditions
			} else if let elements = clause.elements {
				let absentDeclarationRecorder = AbsentDeclarationRecorder(
					parentType: parentType,
					conditions: declarationConditions.adding(blockConditions),
				)
				absentDeclarationRecorder.walk(elements)
				nestedTypeDeclarations.formUnion(absentDeclarationRecorder.declarations)
			}
		}
		if importOnlyBlockDepth > 0 {
			// The enclosing block's source, which `importSegments` holds, contains this block too.
			importOnlyBlockDepth += 1
			importOnlyConsultedCompilationConditions.formUnion(scannable.consultedConditions)
		} else if content == .none, !node.hasError, node.containsImport {
			// This block decides nothing but which imports this visitor finds, which
			// ``ImportSegment/conditionalImports(source:)`` lets a caller decide again without the file.
			importOnlyBlockDepth = 1
			importSegments.append(.conditionalImports(source: node.trimmedDescription))
			importOnlyConsultedCompilationConditions.formUnion(scannable.consultedConditions)
			// Generated mock code compiles only where the mock condition is active, so its imports are
			// selected as a block guarding mock-only declarations is. Blocks nested in the selected
			// clauses are selected the same way.
			let mockScannable = conditionalCompilationEvaluator.scannableClauses(in: node, guarding: .mockOnly)
			let mockClauseVisitor = FileVisitor(conditionalCompilationEvaluator: conditionalCompilationEvaluator)
			for elements in mockScannable.clauses.compactMap(\.elements) {
				mockClauseVisitor.walk(elements)
			}
			mockImports.append(contentsOf: mockClauseVisitor.mockImports)
			importOnlyConsultedCompilationConditions.formUnion(mockScannable.consultedConditions)
			importOnlyConsultedCompilationConditions.formUnion(mockClauseVisitor.importOnlyConsultedCompilationConditions)
		} else if content != .none || node.hasError {
			// A block guarding nothing SafeDI scans for still decides which syntax errors this visitor finds.
			consultedCompilationConditions.formUnion(scannable.consultedConditions)
		}
		return .visitChildren
	}

	public override func visitPost(_: IfConfigDeclSyntax) {
		if importOnlyBlockDepth > 0 {
			importOnlyBlockDepth -= 1
		}
	}

	public override func visit(_ node: IfConfigClauseSyntax) -> SyntaxVisitorContinueKind {
		// Only the clauses the conditions select are scanned, and each has its block's conditions.
		guard let conditions = clauseConditions[node.id] else { return .skipChildren }
		if compilerDeterminedClauses.contains(node.id) {
			compilerDeterminedClauseDepth += 1
		}
		declarationConditionsStack.append(declarationConditions)
		declarationConditions = declarationConditions.adding(conditions)
		return .visitChildren
	}

	public override func visitPost(_ node: IfConfigClauseSyntax) {
		guard clauseConditions[node.id] != nil else { return }
		if compilerDeterminedClauses.contains(node.id) {
			compilerDeterminedClauseDepth -= 1
		}
		declarationConditions = declarationConditionsStack.removeLast()
	}

	public override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
		visitDecl(node)
	}

	public override func visitPost(_: ClassDeclSyntax) {
		exitType()
	}

	public override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
		visitDecl(node)
	}

	public override func visitPost(_: ActorDeclSyntax) {
		exitType()
	}

	public override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
		visitDecl(node)
	}

	public override func visitPost(_: StructDeclSyntax) {
		exitType()
	}

	public override func visit(_ node: MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind {
		if parentType == nil, node.macroName.text == SafeDIConfigurationVisitor.macroName {
			var configuration = SafeDIConfigurationVisitor.extractConfiguration(from: node)
			configuration.declarationLocation = sourceLocationConverter?.declarationLocation(for: node.positionAfterSkippingLeadingTrivia)
			configurations.append(configuration)
			outputFileDeclarations.record(configuration)
		}
		return .skipChildren
	}

	public override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
		// Enums can't be instantiable because they can't have `let` properties.
		// However, they can have nested types within them that are instantiable.
		let access = recordType(
			named: node.name.text,
			kind: .otherType,
			modifiers: node.modifiers,
			attributes: node.attributes,
			genericParameterClause: node.genericParameterClause,
		)
		enterTypeNamed(node.name.text, access: access)
		return .visitChildren
	}

	public override func visitPost(_: EnumDeclSyntax) {
		exitType()
	}

	public override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
		// Lookup from inside an extension searches the type it extends and that type's members, but none of the
		// types that enclose it.
		unsearchedEnclosingTypeCount = max((node.extendedType.typeDescription.namePath?.count ?? 0) - 1, 0)
		let instantiableVisitor = InstantiableVisitor(
			declarationType: .extensionDecl,
			parentType: nil,
			conditionalCompilation: .evaluate(conditionalCompilationEvaluator),
			sourceLocationConverter: sourceLocationConverter,
			unsearchedEnclosingTypeCount: unsearchedEnclosingTypeCount,
		)
		instantiableVisitor.walk(node)
		for instantiable in instantiableVisitor.instantiables {
			instantiables.append(instantiable)
		}
		record(instantiableVisitor.conditionalCompilationDecisions)
		consultedCompilationConditions.formUnion(instantiableVisitor.consultedCompilationConditions)
		// Recorded from the attribute, whether or not an `instantiate()` method the members' `#if` blocks
		// may skip produced an instantiable. SafeDI never treats an extension as a root.
		outputFileDeclarations.recordInstantiable(isRoot: false, generatesMock: instantiableVisitor.generateMock)

		// Extensions are always top-level.
		parentType = node.extendedType.typeDescription
		let extendedTypeNamePath = node.extendedType.typeDescription.namePath
		parentPath = extendedTypeNamePath?.joined(separator: ".")
		extendedTypePath = parentPath
		isParentTypeSpelledAsPath = extendedTypeNamePath != nil
		if let parentPath, node.attributes.hasUnrecognizedAttribute {
			// An attached macro may add members to the type the extension extends.
			nestedTypeDeclarations.record(.unseenMembers(ofTypeAt: parentPath))
		}
		// A member's access defaults to the extension's, and the extended type's own access, declared elsewhere,
		// does not limit it here.
		let extensionAccess = node.modifiers.access
		accessStack = [extensionAccess ?? .exported]
		defaultMemberAccess = extensionAccess ?? .module

		// Continue to find child types.
		return .visitChildren
	}

	public override func visitPost(_: ExtensionDeclSyntax) {
		// Extensions are always top-level.
		parentType = nil
		parentPath = nil
		extendedTypePath = nil
		isParentTypeSpelledAsPath = true
		unsearchedEnclosingTypeCount = 0
		accessStack = []
		defaultMemberAccess = .module
	}

	// SwiftSyntax 602 and prior could not recover from certain parse errors, causing the remainder
	// of a file to be unparseable. This led to SafeDI emitting bogus "missing type" errors before
	// the compiler had a chance to surface the real build error. Detecting unexpected nodes and
	// bailing out avoids this class of false-positive diagnostics.
	public override func visit(_: UnexpectedNodesSyntax) -> SyntaxVisitorContinueKind {
		encounteredUnexpectedNodesSyntax = true
		return .skipChildren
	}

	// MARK: Public

	/// The imports generated dependency-tree code needs: those in the clauses the evaluator selects.
	public private(set) var imports = [ImportStatement]()
	/// The imports generated mock code needs. Generated mock code compiles only where the evaluator's
	/// mock condition is active, so each `#if` block that guards only imports is evaluated as if that
	/// condition were active, as a block that guards mock-only declarations is.
	public private(set) var mockImports = [ImportStatement]()
	public private(set) var instantiables = [Instantiable]()
	public private(set) var configurations = [SafeDIConfiguration]()
	public private(set) var encounteredUnexpectedNodesSyntax = false
	/// How each `#if` condition that guards SafeDI declarations was evaluated, in source order.
	public private(set) var conditionalCompilationDecisions = [ConditionalCompilationDecision]()
	/// Every bare condition whose value decided what this visitor found, except imports in `#if` blocks
	/// that guard nothing else this visitor reports. Walking the same file with any evaluator that gives
	/// each of these conditions the same value finds the same declarations, configurations, syntax
	/// errors, and decisions, and the imports `importSegments` describe.
	public private(set) var consultedCompilationConditions = Set<String>()
	/// The file's imports in source order, with each `#if` block that guards nothing but imports and
	/// other code SafeDI ignores kept as source, so its imports can be found again with another evaluator.
	public private(set) var importSegments = [ImportSegment]()
	/// Every bare condition whose value decided which imports the `#if` blocks in `importSegments` hold,
	/// in `imports` or in `mockImports`.
	public private(set) var importOnlyConsultedCompilationConditions = Set<String>()
	/// The declarations that decide which files SafeDI generates, found in every clause of every `#if`
	/// block. They depend on no condition, so walking the file with any evaluator finds the same.
	public private(set) var outputFileDeclarations = OutputFileDeclarations()
	/// The types declared inside other types or extensions, in the clauses the evaluator selects. Types declared in
	/// function, initializer, accessor, or subscript bodies are local, not nested, and are not recorded.
	public private(set) var nestedTypeDeclarations = NestedTypeDeclarations()

	/// A run of a file's imports.
	public enum ImportSegment: Codable, Hashable, Sendable {
		/// Imports outside any `#if` block that guards only imports.
		case imports([ImportStatement])
		/// An `#if` block that guards only imports and code SafeDI ignores.
		case conditionalImports(source: String)
	}

	// MARK: Private

	private var parentType: TypeDescription?
	/// The effective access of each type enclosing the walk, innermost last.
	private var accessStack = [NestedTypeDeclaration.Access]()
	/// The access a declaration without an access modifier has where the walk is.
	private var defaultMemberAccess = NestedTypeDeclaration.Access.module
	/// The selected `#if` clauses that only the compiler and destination decide between.
	private var compilerDeterminedClauses = Set<SyntaxIdentifier>()
	/// How many of those clauses enclose the walk.
	private var compilerDeterminedClauseDepth = 0
	/// The conditions and decisions of each selected clause's block, which only the selected clauses have.
	private var clauseConditions = [SyntaxIdentifier: DeclarationConditions]()
	/// The conditions and decisions of the blocks enclosing the walk.
	private var declarationConditions = DeclarationConditions()
	private var declarationConditionsStack = [DeclarationConditions]()
	/// How many of `parentType`'s outermost types unqualified lookup does not search, which is nonzero inside an
	/// extension of a nested type.
	private var unsearchedEnclosingTypeCount = 0
	private let conditionalCompilationEvaluator: ConditionalCompilationEvaluator
	private let sourceLocationConverter: SourceLocationConverter?
	/// The `#if` clauses the evaluator selected for scanning.
	/// How many `#if` blocks deep the walk is inside a block that `importSegments` holds as source.
	private var importOnlyBlockDepth = 0

	private func visitDecl(_ node: some ConcreteDeclSyntaxProtocol) -> SyntaxVisitorContinueKind {
		let instantiableVisitor = InstantiableVisitor(
			declarationType: .concreteDecl,
			parentType: parentType,
			conditionalCompilation: .evaluate(conditionalCompilationEvaluator),
			sourceLocationConverter: sourceLocationConverter,
			unsearchedEnclosingTypeCount: unsearchedEnclosingTypeCount,
		)
		instantiableVisitor.walk(node)
		for instantiable in instantiableVisitor.instantiables {
			instantiables.append(instantiable)
		}
		record(instantiableVisitor.conditionalCompilationDecisions)
		consultedCompilationConditions.formUnion(instantiableVisitor.consultedCompilationConditions)
		outputFileDeclarations.recordInstantiable(isRoot: instantiableVisitor.isRoot, generatesMock: instantiableVisitor.generateMock)

		let access = recordType(
			named: node.name.text,
			kind: node.declType == .classType ? .classType : .otherType,
			modifiers: node.modifiers,
			attributes: node.attributes,
			// Only a class has a superclass, which its inheritance clause names first, and SafeDI treats an actor's as it
			// does a class's.
			superclassCandidate: node.declType.mayHaveSuperclass ? node.inheritanceClause?.superclassCandidate : nil,
			genericParameterClause: node.genericParameterClause,
		)
		// Keep track of how nested we are.
		enterTypeNamed(node.name.text, access: access)

		// Continue to find child types.
		return .visitChildren
	}

	/// The path of a type named `name` declared where the walk is, or `nil` inside an extension of a type that is
	/// not spelled as a path of names, such as `[Int]`.
	private func path(ofTypeNamed name: String) -> String? {
		guard isParentTypeSpelledAsPath else { return nil }
		return parentPath.map { $0 + "." + name.withoutBackticks } ?? name.withoutBackticks
	}

	/// Records a type declaration and its generic parameters.
	/// - Returns: The declaration's effective access.
	@discardableResult
	private func recordType(
		named name: String,
		kind: NestedTypeDeclaration.Kind,
		modifiers: DeclModifierListSyntax,
		attributes: AttributeListSyntax,
		superclassCandidate: String? = nil,
		genericParameterClause: GenericParameterClauseSyntax? = nil,
	) -> NestedTypeDeclaration.Access {
		let access = min(modifiers.access ?? defaultMemberAccess, accessStack.last ?? .exported)
		guard let path = path(ofTypeNamed: name) else { return access }
		nestedTypeDeclarations.record(NestedTypeDeclaration(
			path: path,
			kind: kind,
			access: access,
			superclassCandidate: superclassCandidate,
			hasUnrecognizedAttribute: attributes.hasUnrecognizedAttribute,
			extendedTypePath: extendedTypePath,
			isCompilerDetermined: compilerDeterminedClauseDepth > 0,
			consultedCompilationConditions: declarationConditions.sortedConsultedCompilationConditions,
			conditionalCompilationDecisions: declarationConditions.conditionalCompilationDecisions,
		))
		// Building an empty parameter list for a type without generic parameters would allocate a syntax tree.
		for genericParameter in genericParameterClause.map({ Array($0.parameters) }) ?? [] {
			nestedTypeDeclarations.record(NestedTypeDeclaration(
				path: path + "." + genericParameter.name.text.withoutBackticks,
				kind: .genericParameter,
				access: access,
				extendedTypePath: extendedTypePath,
				isCompilerDetermined: compilerDeterminedClauseDepth > 0,
				consultedCompilationConditions: declarationConditions.sortedConsultedCompilationConditions,
				conditionalCompilationDecisions: declarationConditions.conditionalCompilationDecisions,
			))
		}
		return access
	}

	private func enterTypeNamed(_ name: String, access: NestedTypeDeclaration.Access) {
		parentPathStack.append(parentPath)
		parentPath = path(ofTypeNamed: name)
		if let parentType {
			self.parentType = .nested(name: name, parentType: parentType)
		} else {
			parentType = .simple(name: name)
		}
		accessStack.append(access)
		// A member of a type is `internal` unless it says otherwise, whatever an enclosing extension says.
		defaultMemberAccessStack.append(defaultMemberAccess)
		defaultMemberAccess = .module
	}

	private func exitType() {
		parentType = parentType?.popNested
		parentPath = parentPathStack.removeLast()
		accessStack.removeLast()
		defaultMemberAccess = defaultMemberAccessStack.removeLast()
	}

	/// The default member access outside each type the walk is in, innermost last.
	private var defaultMemberAccessStack = [NestedTypeDeclaration.Access]()
	/// `parentType`'s path, joined once rather than for every declaration recorded.
	private var parentPath: String?
	/// The path the extension the walk is in spells its extended type with, or `nil` outside an extension.
	private var extendedTypePath: String?
	private var parentPathStack = [String?]()
	/// Whether `parentType` is spelled as a path of names, which it is unless the walk is inside an extension of a
	/// type such as `[Int]`.
	private var isParentTypeSpelledAsPath = true

	/// Records each decision once, even when both this visitor and an `InstantiableVisitor` walk the block.
	private func record(_ decisions: [ConditionalCompilationDecision]) {
		for decision in decisions where !conditionalCompilationDecisions.contains(decision) {
			conditionalCompilationDecisions.append(decision)
		}
	}
}

extension IfConfigDeclSyntax {
	/// Whether any clause holds an import, which `FileVisitor` reports even when nothing SafeDI scans for is inside.
	fileprivate var containsImport: Bool {
		tokens(viewMode: .sourceAccurate).contains { $0.tokenKind == .keyword(.import) }
	}
}

extension InheritanceClauseSyntax {
	/// The first type this clause names, spelled as a path without backticks, or an empty string for one not spelled
	/// as a path of names, or with generic arguments.
	fileprivate var superclassCandidate: String? {
		inheritedTypes.first.map(\.type.superclassCandidate)
	}
}

extension TypeSyntax {
	/// This type, the first an inheritance clause names, spelled as a path without backticks, or an empty string for
	/// one not spelled as a path of names, or with generic arguments.
	fileprivate var superclassCandidate: String {
		let firstType = self
		// `@unchecked Sendable` and the like name protocols, whatever their attributes.
		let type = firstType.as(AttributedTypeSyntax.self)?.baseType ?? firstType
		guard type.is(IdentifierTypeSyntax.self) || type.is(MemberTypeSyntax.self),
		      let namePath = type.typeDescription.namePath,
		      // A generic class's arguments, on any name in the path.
		      !type.tokens(viewMode: .sourceAccurate).contains(where: { $0.tokenKind == .leftAngle })
		else { return "" }
		return namePath.joined(separator: ".")
	}
}

extension AttributeListSyntax {
	/// Whether any of these attributes is not one of `NestedTypeDeclaration.recognizedAttributeNames`, which an
	/// attribute in an `#if` clause is not either.
	fileprivate var hasUnrecognizedAttribute: Bool {
		contains { element in
			element.as(AttributeSyntax.self).map { !NestedTypeDeclaration.recognizedAttributeNames.contains($0.attributeName.trimmedDescription) } ?? true
		}
	}
}

extension DeclModifierListSyntax {
	/// The access level these modifiers give a declaration, or `nil` when they name none.
	fileprivate var access: NestedTypeDeclaration.Access? {
		lazy.compactMap { modifier -> NestedTypeDeclaration.Access? in
			switch modifier.name.tokenKind {
			case .keyword(.private), .keyword(.fileprivate):
				.file
			case .keyword(.internal):
				.module
			case .keyword(.package):
				.package
			case .keyword(.public), .keyword(.open):
				.exported
			default:
				nil
			}
		}.first
	}
}

/// The conditions and decisions of the `#if` blocks enclosing a declaration, which decided whether it exists.
private struct DeclarationConditions {
	init() {
		consultedCompilationConditions = []
		conditionalCompilationDecisions = []
	}

	init(consultedCompilationConditions: Set<String>, conditionalCompilationDecisions: [ConditionalCompilationDecision]) {
		self.consultedCompilationConditions = consultedCompilationConditions
		self.conditionalCompilationDecisions = conditionalCompilationDecisions
	}

	let consultedCompilationConditions: Set<String>
	let conditionalCompilationDecisions: [ConditionalCompilationDecision]
	/// `consultedCompilationConditions`, sorted once rather than for every declaration recorded.
	private(set) lazy var sortedConsultedCompilationConditions = consultedCompilationConditions.sorted()

	func adding(_ other: DeclarationConditions) -> DeclarationConditions {
		DeclarationConditions(
			consultedCompilationConditions: consultedCompilationConditions.union(other.consultedCompilationConditions),
			conditionalCompilationDecisions: conditionalCompilationDecisions + other.conditionalCompilationDecisions.filter { !conditionalCompilationDecisions.contains($0) },
		)
	}
}

/// Records the types an `#if` clause the conditions did not select declares, as absent declarations.
private final class AbsentDeclarationRecorder: SyntaxVisitor {
	init(parentType: TypeDescription?, conditions: DeclarationConditions) {
		self.parentType = parentType
		self.conditions = conditions
		super.init(viewMode: .sourceAccurate)
	}

	private(set) var declarations = NestedTypeDeclarations()

	override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
		enterType(named: node.name.text, kind: .classType, genericParameterClause: node.genericParameterClause)
	}

	override func visitPost(_: ClassDeclSyntax) {
		parentType = parentType?.popNested
	}

	override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
		enterType(named: node.name.text, kind: .otherType, genericParameterClause: node.genericParameterClause)
	}

	override func visitPost(_: StructDeclSyntax) {
		parentType = parentType?.popNested
	}

	override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
		enterType(named: node.name.text, kind: .otherType, genericParameterClause: node.genericParameterClause)
	}

	override func visitPost(_: EnumDeclSyntax) {
		parentType = parentType?.popNested
	}

	override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
		enterType(named: node.name.text, kind: .otherType, genericParameterClause: node.genericParameterClause)
	}

	override func visitPost(_: ActorDeclSyntax) {
		parentType = parentType?.popNested
	}

	override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
		if let path = path(ofTypeNamed: node.name.text) {
			record(path: path, kind: .protocolType)
		}
		return .skipChildren
	}

	override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
		if let path = path(ofTypeNamed: node.name.text) {
			record(path: path, kind: .typeAlias)
		}
		return .skipChildren
	}

	override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
		parentType = node.extendedType.typeDescription
		extendedTypePath = parentType?.namePath?.joined(separator: ".")
		if let extendedTypePath, node.attributes.hasUnrecognizedAttribute {
			declarations.record(.unseenMembers(ofTypeAt: extendedTypePath))
		}
		return .visitChildren
	}

	override func visitPost(_: ExtensionDeclSyntax) {
		parentType = nil
		extendedTypePath = nil
	}

	override func visit(_: MacroExpansionDeclSyntax) -> SyntaxVisitorContinueKind {
		if let parentPath = parentType?.namePath?.joined(separator: ".") {
			declarations.record(.unseenMembers(ofTypeAt: parentPath))
		}
		return .skipChildren
	}

	override func visit(_: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
		.skipChildren
	}

	override func visit(_: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
		.skipChildren
	}

	override func visit(_: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
		.skipChildren
	}

	private var parentType: TypeDescription?
	private var extendedTypePath: String?
	private var conditions: DeclarationConditions

	private func path(ofTypeNamed name: String) -> String? {
		if let parentType {
			parentType.namePath.map { ($0 + [name.withoutBackticks]).joined(separator: ".") }
		} else {
			name.withoutBackticks
		}
	}

	private func enterType(named name: String, kind: NestedTypeDeclaration.Kind, genericParameterClause: GenericParameterClauseSyntax?) -> SyntaxVisitorContinueKind {
		if let path = path(ofTypeNamed: name) {
			record(path: path, kind: kind)
			// Building an empty parameter list for a type without generic parameters would allocate a syntax tree.
			for genericParameter in genericParameterClause.map({ Array($0.parameters) }) ?? [] {
				record(path: path + "." + genericParameter.name.text.withoutBackticks, kind: .genericParameter)
			}
		}
		parentType = parentType.map { .nested(name: name, parentType: $0) } ?? .simple(name: name)
		return .visitChildren
	}

	private func record(path: String, kind: NestedTypeDeclaration.Kind) {
		declarations.record(NestedTypeDeclaration(
			path: path,
			kind: kind,
			access: .module,
			extendedTypePath: extendedTypePath,
			isAbsent: true,
			consultedCompilationConditions: conditions.sortedConsultedCompilationConditions,
			conditionalCompilationDecisions: conditions.conditionalCompilationDecisions,
		))
	}
}
