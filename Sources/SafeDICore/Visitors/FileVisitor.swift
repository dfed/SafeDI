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
		recordType(named: node.name.text)
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
		recordType(named: node.name.text)
		return .skipChildren
	}

	public override func visit(_ node: IfConfigDeclSyntax) -> SyntaxVisitorContinueKind {
		// The block's declarations in every clause, including those of nested blocks, which this visitor
		// reaches again only in the clauses it scans.
		let (content, blockOutputFileDeclarations, declaredTypeNames) = node.safeDIContentAmongDeclarations()
		outputFileDeclarations.formUnion(blockOutputFileDeclarations)
		let scannable = conditionalCompilationEvaluator.scannableClauses(in: node, guarding: content)
		activeIfConfigClauses.formUnion(scannable.clauses.map(\.id))
		record(scannable.decisions)
		if !declaredTypeNames.isEmpty, !scannable.consultedConditions.isEmpty {
			// The selection decides which of these names `nestedTypeDeclarations` records.
			conditionallyDeclaredTypes.append(ConditionallyDeclaredTypes(
				names: declaredTypeNames,
				consultedCompilationConditions: scannable.consultedConditions,
			))
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
		recordType(named: node.name.text, genericParameterClause: node.genericParameterClause)
		enterTypeNamed(node.name.text)
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

		// Continue to find child types.
		return .visitChildren
	}

	public override func visitPost(_: ExtensionDeclSyntax) {
		// Extensions are always top-level.
		parentType = nil
		unsearchedEnclosingTypeCount = 0
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
	/// The types and generic parameters that `#if` blocks declare in any clause, with the conditions that decided
	/// which of them `nestedTypeDeclarations` records. Once the lookups SafeDI makes are known, the conditions of
	/// a block that declares a name a lookup asks for are consulted conditions, and those of other blocks decide
	/// nothing SafeDI keeps.
	public private(set) var conditionallyDeclaredTypes = [ConditionallyDeclaredTypes]()

	/// A run of a file's imports.
	public enum ImportSegment: Codable, Hashable, Sendable {
		/// Imports outside any `#if` block that guards only imports.
		case imports([ImportStatement])
		/// An `#if` block that guards only imports and code SafeDI ignores.
		case conditionalImports(source: String)
	}

	// MARK: Private

	private var parentType: TypeDescription?
	/// How many of `parentType`'s outermost types unqualified lookup does not search, which is nonzero inside an
	/// extension of a nested type.
	private var unsearchedEnclosingTypeCount = 0
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

		recordType(named: node.name.text, genericParameterClause: node.genericParameterClause)
		// Keep track of how nested we are.
		enterTypeNamed(node.name.text)

		// Continue to find child types.
		return .visitChildren
	}

	/// Records a type declaration, which is nested when it is inside a type or an extension.
	private func recordType(named name: String, genericParameterClause: GenericParameterClauseSyntax? = nil) {
		nestedTypeDeclarations.recordType(
			named: name,
			genericParameterNames: genericParameterClause?.parameters.map(\.name.text) ?? [],
			within: parentType,
		)
	}

	private func enterTypeNamed(_ name: String) {
		if let parentType {
			self.parentType = .nested(name: name, parentType: parentType)
		} else {
			parentType = .simple(name: name)
		}
	}

	private func exitType() {
		parentType = parentType?.popNested
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
