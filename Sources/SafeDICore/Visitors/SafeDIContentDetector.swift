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

/// What SafeDI would learn from the declarations inside an `#if` block.
enum SafeDIContent: Int, Comparable {
	/// Nothing SafeDI scans for.
	case none
	/// Declarations that feed mock generation only: `mockOnly` types and hand-written mock methods.
	case mockOnly
	/// Declarations that feed the dependency tree.
	case production

	static func < (lhs: Self, rhs: Self) -> Bool {
		lhs.rawValue < rhs.rawValue
	}
}

/// Where an `#if` block sits, which determines which declarations inside it matter.
enum SafeDIContentContext {
	/// Among type declarations, where `@Instantiable` types and `#SafeDIConfiguration` matter.
	case declarations
	/// Among the members of one `@Instantiable` declaration, where dependencies, initializers,
	/// and mock methods matter. Nested types are scanned separately among the declarations.
	case members(InstantiableMembers)

	struct InstantiableMembers {
		let construction: Construction
		/// Whether every member only feeds mock generation.
		let isMockOnly: Bool
		let customMockName: String?

		/// How SafeDI constructs the declared type, which determines which methods and initializers matter.
		enum Construction {
			/// An extension, whose `instantiate()` method constructs the type. SafeDI never scans its initializers.
			case instantiateMethod
			/// A type definition, which SafeDI constructs with the first initializer that fulfills its dependencies.
			case initializer(ConstructionInitializerCandidates)
		}
	}
}

/// Determines which initializers of an `@Instantiable` type definition SafeDI could select for
/// construction under some evaluation of the `#if` blocks among its members.
///
/// SafeDI selects the first initializer, in source order, that fulfills the dependencies it scanned.
/// A guarded initializer changes neither that selection nor the generated call when no evaluation
/// lets it be selected: either it fulfills the dependencies of no evaluation, or an initializer
/// outside every `#if` block precedes it and fulfills the dependencies of every evaluation.
/// Evaluations are bounded without evaluating any condition: every evaluation scans the dependencies
/// declared outside `#if` blocks, and none scans more than those declared in every clause.
final class ConstructionInitializerCandidates {
	// MARK: Initialization

	init(declaration: some ConcreteDeclSyntaxProtocol) {
		self.declaration = declaration
	}

	// MARK: Internal

	/// Whether `node`, an initializer inside an `#if` block, could be the initializer SafeDI selects.
	func couldSelect(_ node: InitializerDeclSyntax) -> Bool {
		let isPrecededByInitializerSelectableInEveryEvaluation = firstInitializerSelectableInEveryEvaluationPosition.map { $0 < node.position } ?? false
		return !isPrecededByInitializerSelectableInEveryEvaluation
			&& Initializer(node).couldBeValid(forFulfillingEvery: guaranteedDependencies, amongPossible: possibleDependencies)
	}

	// MARK: Private

	private let declaration: any ConcreteDeclSyntaxProtocol

	/// The dependencies declared in every clause of every `#if` block, in source order. Each evaluation scans a subsequence of these.
	private lazy var possibleDependencies: [Dependency] = {
		let visitor = InstantiableVisitor(declarationType: .concreteDecl, conditionalCompilation: .scanAllClauses)
		visitor.walk(declaration)
		return visitor.dependencies
	}()

	/// The dependencies declared outside every `#if` block, which every evaluation scans.
	private lazy var guaranteedDependencies: [Dependency] = {
		var unconditionalDeclaration = declaration
		unconditionalDeclaration.memberBlock.members = declaration.memberBlock.members.filter { !$0.decl.is(IfConfigDeclSyntax.self) }
		let visitor = InstantiableVisitor(declarationType: .concreteDecl, conditionalCompilation: .scanAllClauses)
		visitor.walk(unconditionalDeclaration)
		return visitor.dependencies
	}()

	/// Where the first initializer outside every `#if` block that fulfills the dependencies of every evaluation begins.
	///
	/// Fulfilling both bounds suffices: each argument without a default binds to a guaranteed
	/// dependency, which every evaluation has, and because an evaluation's dependencies are a
	/// subsequence of the possible ones, each of them is bound by the argument that binds it among the possible ones.
	private lazy var firstInitializerSelectableInEveryEvaluationPosition: AbsolutePosition? = declaration
		.memberBlock
		.members
		.lazy
		.compactMap { $0.decl.as(InitializerDeclSyntax.self) }
		.first {
			let initializer = Initializer($0)
			return initializer.isValid(forFulfilling: self.guaranteedDependencies)
				&& initializer.isValid(forFulfilling: self.possibleDependencies)
		}?
		.position
}

extension IfConfigDeclSyntax {
	func safeDIContent(in context: SafeDIContentContext) -> SafeDIContent {
		let detector = SafeDIContentDetector(context: context)
		detector.walk(self)
		return detector.content
	}

	/// What SafeDI would learn from this block among type declarations, the declarations in every one of its
	/// clauses that decide which files SafeDI generates, and the names of the types and generic parameters every
	/// clause declares, which decide what `NestedTypeDeclarations` records for the block. All come from one walk of
	/// the block.
	func safeDIContentAmongDeclarations() -> (content: SafeDIContent, outputFileDeclarations: OutputFileDeclarations, declaredTypeNames: Set<String>) {
		let detector = SafeDIContentDetector(context: .declarations)
		detector.walk(self)
		return (detector.content, detector.outputFileDeclarations, detector.declaredTypeNames)
	}
}

private final class SafeDIContentDetector: SyntaxVisitor {
	init(context: SafeDIContentContext) {
		self.context = context
		super.init(viewMode: .sourceAccurate)
	}

	private(set) var content = SafeDIContent.none
	/// The declarations among type declarations, in every clause, that decide which files SafeDI generates.
	private(set) var outputFileDeclarations = OutputFileDeclarations()
	/// The name of every type, and of every generic parameter of a type, that any clause declares among type
	/// declarations, without backticks.
	private(set) var declaredTypeNames = Set<String>()

	override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
		recordTypeDeclaration(named: node.name, genericParameterClause: node.genericParameterClause)
		return visitTypeDeclaration(node.attributes, isTypeDefinition: true)
	}

	override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
		recordTypeDeclaration(named: node.name, genericParameterClause: node.genericParameterClause)
		return visitTypeDeclaration(node.attributes, isTypeDefinition: true)
	}

	override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
		recordTypeDeclaration(named: node.name, genericParameterClause: node.genericParameterClause)
		return visitTypeDeclaration(node.attributes, isTypeDefinition: true)
	}

	override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
		visitTypeDeclaration(node.attributes, isTypeDefinition: false)
	}

	override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
		recordTypeDeclaration(named: node.name, genericParameterClause: node.genericParameterClause)
		switch context {
		case .declarations:
			// Enums can nest instantiable types.
			return .visitChildren
		case .members:
			return .skipChildren
		}
	}

	override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
		recordTypeDeclaration(named: node.name, genericParameterClause: nil)
		return .skipChildren
	}

	override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
		recordTypeDeclaration(named: node.name, genericParameterClause: nil)
		return .skipChildren
	}

	override func visit(_ node: MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind {
		if case .declarations = context, node.macroName.text == SafeDIConfigurationVisitor.macroName {
			record(.production)
			outputFileDeclarations.record(SafeDIConfigurationVisitor.extractConfiguration(from: node))
		}
		return .skipChildren
	}

	override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
		if case .members = context,
		   node.modifiers.staticModifier == nil,
		   !node.attributes.dependencySources.isEmpty
		{
			record(.production)
		}
		return .skipChildren
	}

	override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
		if case let .members(members) = context,
		   case let .initializer(candidates) = members.construction,
		   candidates.couldSelect(node)
		{
			record(.production)
		}
		return .skipChildren
	}

	override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
		if case let .members(members) = context {
			let isStaticOrClass = node.modifiers.contains { $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class) }
			let mockMethodNames = [InstantiableVisitor.mockMethodName, members.customMockName].compactMap(\.self)
			if isStaticOrClass, mockMethodNames.contains(node.name.text) {
				record(.mockOnly)
			} else if case .instantiateMethod = members.construction, node.name.text == InstantiableVisitor.instantiateMethodName {
				record(.production)
			}
		}
		return .skipChildren
	}

	// MARK: Private

	private let context: SafeDIContentContext
	/// Records a type declaration among type declarations.
	private func recordTypeDeclaration(named name: TokenSyntax, genericParameterClause: GenericParameterClauseSyntax?) {
		guard case .declarations = context else { return }
		declaredTypeNames.insert(name.text.withoutBackticks)
		for genericParameter in genericParameterClause?.parameters ?? [] {
			declaredTypeNames.insert(genericParameter.name.text.withoutBackticks)
		}
	}

	/// - Parameter isTypeDefinition: Whether the declaration defines a type, which only a type definition
	///   can make a root: SafeDI never treats an `@Instantiable` extension as one.
	private func visitTypeDeclaration(_ attributes: AttributeListSyntax, isTypeDefinition: Bool) -> SyntaxVisitorContinueKind {
		switch context {
		case .declarations:
			if let instantiableMacro = attributes.instantiableMacro {
				record(instantiableMacro.mockOnlyValue ? .mockOnly : .production)
				outputFileDeclarations.recordInstantiable(
					isRoot: isTypeDefinition && instantiableMacro.isRootValue,
					generatesMock: instantiableMacro.generateMockValue,
				)
			}
			// Nested types may be instantiable too.
			return .visitChildren
		case .members:
			return .skipChildren
		}
	}

	private func record(_ found: SafeDIContent) {
		let foundInContext: SafeDIContent = switch context {
		case let .members(members) where members.isMockOnly:
			// Every member of a `mockOnly` declaration only feeds mock generation.
			min(found, .mockOnly)
		case .declarations, .members:
			found
		}
		content = max(content, foundInContext)
	}
}
