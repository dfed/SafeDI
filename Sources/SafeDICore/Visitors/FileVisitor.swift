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
		// A protocol declares no type SafeDI scans for, but its declaration proves its access, as any plain type's does.
		// Its body declares nothing SafeDI reads: a type nested in it counts as the protocol does (`TypeAccessProof`).
		recordPlainTypeDeclaration(
			typeDefined(named: node.name.text),
			access: node.modifiers.access(introducedBy: node.protocolKeyword, sourceLocationConverter: sourceLocationConverter),
			isInstantiable: false,
		)
		return .skipChildren
	}

	public override func visit(_: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
		.skipChildren
	}

	public override func visit(_: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
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
		// A typealias declares no type SafeDI scans for, but its declaration proves its access, as any plain type's does:
		// Swift caps a typealias at its underlying type's access, so the level it spells is what other code can name.
		recordPlainTypeDeclaration(
			typeDefined(named: node.name.text),
			access: node.modifiers.access(introducedBy: node.typealiasKeyword, sourceLocationConverter: sourceLocationConverter),
			isInstantiable: false,
		)
		return .skipChildren
	}

	public override func visit(_ node: IfConfigDeclSyntax) -> SyntaxVisitorContinueKind {
		// The block's declarations in every clause, including those of nested blocks, which this visitor
		// reaches again only in the clauses it scans.
		let (content, blockOutputFileDeclarations, plainTypeNames) = node.safeDIContentAmongDeclarations(
			enclosedBy: parentType,
			enclosingTypeAccess: enclosingTypeAccess,
			inExtensionOf: enclosingExtendedType,
			enclosingExtensionAccess: enclosingExtensionAccess,
			sourceLocationConverter: sourceLocationConverter,
		)
		outputFileDeclarations.formUnion(blockOutputFileDeclarations)
		// A plain type declaration is recorded from the clauses this visitor scans, which the conditions select as they
		// select a block guarding production declarations. A block that also guards mock-only declarations keeps the
		// selection that forces the mock condition active, so a plain type declared there is read under the mock condition,
		// for production code too: a production declaration that names it is generated for the clause the mock condition
		// selects, which the compiler checks where the condition is inactive.
		let declaresPlainType = !plainTypeNames.isEmpty
		let scannable = conditionalCompilationEvaluator.scannableClauses(in: node, guarding: content == .none && declaresPlainType ? .production : content)
		activeIfConfigClauses.formUnion(scannable.clauses.map(\.id))
		if content == .none {
			// The conditions decide which plain declarations this visitor records, and the decisions matter, only when the
			// module keeps a declaration the block could hold, which it decides once every file is walked.
			if declaresPlainType, !scannable.consultedConditions.isEmpty {
				plainTypeDeclarationDecisions.append(plainTypeNames.guarded(by: scannable))
			}
		} else {
			record(scannable.decisions)
		}
		if importOnlyBlockDepth > 0 {
			// The enclosing block's source, which `importSegments` holds, contains this block too.
			importOnlyBlockDepth += 1
			importOnlyConsultedCompilationConditions.formUnion(scannable.consultedConditions)
		} else if content == .none, !node.hasError, node.containsImport {
			// This block decides nothing but which imports this visitor finds, and which plain declarations it records,
			// which ``ImportSegment/conditionalImports(source:)`` lets a caller decide again without the file for the
			// imports.
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
		activeIfConfigClauses.contains(node.id) ? .visitChildren : .skipChildren
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
		enterType(
			typeDefined(named: node.name.text),
			access: node.modifiers.access(introducedBy: node.enumKeyword, sourceLocationConverter: sourceLocationConverter),
			isInstantiable: node.attributes.instantiableMacro != nil,
		)
		return .visitChildren
	}

	public override func visitPost(_: EnumDeclSyntax) {
		exitType()
	}

	public override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
		let instantiableVisitor = InstantiableVisitor(
			declarationType: .extensionDecl,
			parentType: nil,
			conditionalCompilation: .evaluate(conditionalCompilationEvaluator),
			sourceLocationConverter: sourceLocationConverter,
		)
		instantiableVisitor.walk(node)
		for instantiable in instantiableVisitor.instantiables {
			instantiables.append(instantiable)
		}
		record(instantiableVisitor.conditionalCompilationDecisions)
		consultedCompilationConditions.formUnion(instantiableVisitor.consultedCompilationConditions)
		// Recorded from the attribute, whether or not an `instantiate()` method the members' `#if` blocks
		// may skip produced an instantiable. SafeDI never treats an extension as a root, nor generates its
		// dependency tree.
		if node.attributes.instantiableMacro != nil {
			outputFileDeclarations.recordInstantiable(
				named: node.extendedType.typeDescription.asSource,
				inExtensionOf: node.extendedType.typeDescription,
				isRoot: false,
				generatesDependencyTree: false,
				generatesMock: instantiableVisitor.generateMock.generatesMock,
			)
		}

		// Extensions are always top-level.
		parentType = node.extendedType.typeDescription
		enclosingExtendedType = node.extendedType.typeDescription
		enclosingExtensionAccess = node.modifiers.access(introducedBy: node.extensionKeyword, sourceLocationConverter: sourceLocationConverter)

		// Continue to find child types.
		return .visitChildren
	}

	public override func visitPost(_: ExtensionDeclSyntax) {
		// Extensions are always top-level.
		parentType = nil
		enclosingExtendedType = nil
		enclosingExtensionAccess = nil
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
	/// How the conditions of each `#if` block that guards nothing else SafeDI reads but declares a plain type in some
	/// clause were evaluated, with the conditions the selection consulted and the types the block declares, in source
	/// order. Which of them decide what the module reads, and which decisions generated code asserts, depends on which
	/// declarations the module keeps, which the module decides.
	public private(set) var plainTypeDeclarationDecisions = [GuardedPlainTypeNames]()
	/// Every bare condition whose value decided what this visitor found, except imports in `#if` blocks
	/// that guard nothing else this visitor reports, and plain type declarations in `#if` blocks that guard nothing else
	/// SafeDI reads, whose blocks' conditions `plainTypeDeclarationDecisions` holds. Walking the same file with any
	/// evaluator that gives each of these conditions the same value finds the same declarations, configurations, syntax
	/// errors, and decisions, the imports `importSegments` describe, and the plain type declarations outside such blocks
	/// and in each such block whose conditions are given the same value.
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
	/// Every `struct`, `class`, `actor`, `enum`, `protocol`, and `typealias` declaration that is not `@Instantiable`, outside
	/// every `#if` block or in a clause this visitor scans, directly inside an extension or not, in source order. The
	/// conditions of each block that declares one in any clause are among `consultedCompilationConditions`, or, for a
	/// block that guards nothing else SafeDI reads, among its entry of `plainTypeDeclarationDecisions`.
	public private(set) var plainTypeDeclarations = [PlainTypeDeclaration]()

	/// A run of a file's imports.
	public enum ImportSegment: Codable, Hashable, Sendable {
		/// Imports outside any `#if` block that guards only imports.
		case imports([ImportStatement])
		/// An `#if` block that guards only imports and code SafeDI ignores.
		case conditionalImports(source: String)
	}

	// MARK: Private

	private var parentType: TypeDescription?
	/// The access of each type declaration enclosing the walk's position, outermost first.
	private var enclosingTypeAccess = [AccessDeclaration]()
	/// The access of the extension enclosing the walk's position, if one does.
	private var enclosingExtensionAccess: AccessDeclaration?
	/// The type the extension enclosing the walk's position extends, if one does.
	private var enclosingExtendedType: TypeDescription?
	private let conditionalCompilationEvaluator: ConditionalCompilationEvaluator
	private let sourceLocationConverter: SourceLocationConverter?
	/// The `#if` clauses the evaluator selected for scanning.
	private var activeIfConfigClauses = Set<SyntaxIdentifier>()
	/// How many `#if` blocks deep the walk is inside a block that `importSegments` holds as source.
	private var importOnlyBlockDepth = 0

	private func visitDecl(_ node: some ConcreteDeclSyntaxProtocol) -> SyntaxVisitorContinueKind {
		let instantiableVisitor = InstantiableVisitor(
			declarationType: .concreteDecl,
			parentType: parentType,
			enclosingTypeAccess: enclosingTypeAccess,
			enclosingExtensionAccess: enclosingExtensionAccess,
			conditionalCompilation: .evaluate(conditionalCompilationEvaluator),
			sourceLocationConverter: sourceLocationConverter,
		)
		instantiableVisitor.walk(node)
		for instantiable in instantiableVisitor.instantiables {
			instantiables.append(instantiable)
		}
		record(instantiableVisitor.conditionalCompilationDecisions)
		consultedCompilationConditions.formUnion(instantiableVisitor.consultedCompilationConditions)
		let definedType = typeDefined(named: node.name.text)
		if node.attributes.instantiableMacro != nil {
			outputFileDeclarations.recordInstantiable(
				named: definedType.asSource,
				inExtensionOf: enclosingExtendedType,
				isRoot: instantiableVisitor.isRoot,
				generatesDependencyTree: instantiableVisitor.generatesDependencyTree,
				generatesMock: instantiableVisitor.generateMock.generatesMock,
			)
		}

		// Keep track of how nested we are.
		enterType(
			definedType,
			access: node.modifiers.access(introducedBy: node.keyword, sourceLocationConverter: sourceLocationConverter),
			isInstantiable: node.attributes.instantiableMacro != nil,
		)

		// Continue to find child types.
		return .visitChildren
	}

	/// Makes `type`, which a type definition with `access` defines, the type whose members the walk visits, and
	/// records it among `plainTypeDeclarations` when it is not `@Instantiable`.
	private func enterType(_ type: TypeDescription, access: AccessDeclaration, isInstantiable: Bool) {
		recordPlainTypeDeclaration(type, access: access, isInstantiable: isInstantiable)
		parentType = type
		enclosingTypeAccess.append(access)
	}

	/// Records `type`, which a declaration with `access` declares, among `plainTypeDeclarations` when it is not
	/// `@Instantiable`.
	private func recordPlainTypeDeclaration(_ type: TypeDescription, access: AccessDeclaration, isInstantiable: Bool) {
		if !isInstantiable {
			plainTypeDeclarations.append(PlainTypeDeclaration(
				typeDescription: type,
				access: access,
				enclosingTypeAccess: enclosingTypeAccess,
				enclosingExtensionAccess: enclosingExtensionAccess,
			))
		}
	}

	/// The type a type definition named `name` defines among the members of `parentType`.
	private func typeDefined(named name: String) -> TypeDescription {
		if let parentType {
			.nested(name: name, parentType: parentType)
		} else {
			.simple(name: name)
		}
	}

	private func exitType() {
		parentType = parentType?.popNested
		enclosingTypeAccess.removeLast()
	}

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
