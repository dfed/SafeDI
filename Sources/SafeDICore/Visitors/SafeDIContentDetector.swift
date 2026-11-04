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

	/// What SafeDI would learn from this block among type declarations, the declarations in every one of its clauses
	/// that decide which files SafeDI generates, and the outermost names of the types that are not `@Instantiable` it
	/// declares in any of its clauses, including those of the blocks nested in it. All come from one walk of the block.
	/// - Parameters:
	///   - enclosingType: The type whose members the block is among, if any, which encloses the types the block
	///     declares.
	///   - enclosingTypeAccess: The access of each type declaration enclosing the block in its file, outermost first.
	///   - extendedType: The type the extension the block is in extends, if it is in one.
	///   - enclosingExtensionAccess: The access of the extension the block is in, if it is in one.
	///   - sourceLocationConverter: A converter for the tree the block is in, with which each declaration records where
	///     it begins.
	func safeDIContentAmongDeclarations(
		enclosedBy enclosingType: TypeDescription?,
		enclosingTypeAccess: [AccessDeclaration] = [],
		inExtensionOf extendedType: TypeDescription?,
		enclosingExtensionAccess: AccessDeclaration? = nil,
		sourceLocationConverter: SourceLocationConverter? = nil,
	) -> (content: SafeDIContent, outputFileDeclarations: OutputFileDeclarations, plainTypeNames: PlainTypeNamesInAnyClause) {
		let detector = SafeDIContentDetector(
			context: .declarations,
			enclosingType: enclosingType,
			enclosingTypeAccess: enclosingTypeAccess,
			extendedType: extendedType,
			enclosingExtensionAccess: enclosingExtensionAccess,
			sourceLocationConverter: sourceLocationConverter,
		)
		detector.walk(self)
		return (detector.content, detector.outputFileDeclarations, detector.plainTypeNames)
	}
}

/// The plain types an `#if` block declares in any of its clauses, including those of the blocks nested in it: the
/// declarations a walk of the block could record under some evaluation of its conditions.
struct PlainTypeNamesInAnyClause {
	/// Each type whose chain is a chain of names, as deciding whether a read resolves to it needs.
	private(set) var declaredTypes = Set<GuardedPlainTypeNames.DeclaredType>()
	/// Whether the block declares no plain type a mention can name, in any clause.
	var isEmpty: Bool {
		declaredTypes.isEmpty
	}

	/// Records `declaration`, unless it is declared inside an extension of a type spelled otherwise than by a name
	/// (`extension [Int] { … }`), which no mention names by its chain.
	mutating func record(_ declaration: PlainTypeDeclaration) {
		if let outermostName = declaration.typeDescription.outermostTypeName {
			// The type's own name: the last of its chain of names, or the outermost when nothing encloses it.
			let name = if case let .nested(name, _, _) = declaration.typeDescription {
				name
			} else {
				outermostName
			}
			declaredTypes.insert(GuardedPlainTypeNames.DeclaredType(
				name: name,
				outermostName: outermostName,
				level: TypeAccessProof.normalized(declaration.levelBeforeExtendedTypeCap),
			))
		}
	}

	/// The types, with the selection of the block's clauses: `decisions`, and the conditions it consulted.
	func guarded(by scannable: ScannableClauses) -> GuardedPlainTypeNames {
		GuardedPlainTypeNames(decisions: scannable.decisions, consultedConditions: scannable.consultedConditions.sorted(), declaredTypes: declaredTypes.sorted())
	}
}

private final class SafeDIContentDetector: SyntaxVisitor {
	/// - Parameters:
	///   - enclosingType: The type whose members the walked block is among, if any.
	///   - extendedType: The type the extension the walked block is in extends, if it is in one.
	///   - enclosingTypeAccess: The access of each type declaration enclosing the walked block in its file.
	///   - enclosingExtensionAccess: The access of the extension the walked block is in, if it is in one.
	///   - sourceLocationConverter: A converter for the tree the walked block is in.
	init(
		context: SafeDIContentContext,
		enclosingType: TypeDescription? = nil,
		enclosingTypeAccess: [AccessDeclaration] = [],
		extendedType: TypeDescription? = nil,
		enclosingExtensionAccess: AccessDeclaration? = nil,
		sourceLocationConverter: SourceLocationConverter? = nil,
	) {
		self.context = context
		self.enclosingType = enclosingType
		self.enclosingTypeAccess = enclosingTypeAccess
		self.extendedType = extendedType
		self.enclosingExtensionAccess = enclosingExtensionAccess
		self.sourceLocationConverter = sourceLocationConverter
		super.init(viewMode: .sourceAccurate)
	}

	private(set) var content = SafeDIContent.none
	/// The declarations among type declarations, in every clause, that decide which files SafeDI generates.
	private(set) var outputFileDeclarations = OutputFileDeclarations()
	/// Among type declarations, the outermost names of the `struct`, `class`, `actor`, `enum`, `protocol`, and `typealias`
	/// declarations that are not `@Instantiable`, in every clause.
	private(set) var plainTypeNames = PlainTypeNamesInAnyClause()

	override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
		visitTypeDeclaration(node.attributes, declaring: typeDefined(named: node.name.text), access: node.modifiers.access(introducedBy: node.classKeyword, sourceLocationConverter: sourceLocationConverter), isTypeDefinition: true)
	}

	override func visitPost(_: ClassDeclSyntax) {
		exitType()
	}

	override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
		visitTypeDeclaration(node.attributes, declaring: typeDefined(named: node.name.text), access: node.modifiers.access(introducedBy: node.actorKeyword, sourceLocationConverter: sourceLocationConverter), isTypeDefinition: true)
	}

	override func visitPost(_: ActorDeclSyntax) {
		exitType()
	}

	override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
		visitTypeDeclaration(node.attributes, declaring: typeDefined(named: node.name.text), access: node.modifiers.access(introducedBy: node.structKeyword, sourceLocationConverter: sourceLocationConverter), isTypeDefinition: true)
	}

	override func visitPost(_: StructDeclSyntax) {
		exitType()
	}

	override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
		// Extensions are always top-level, so a block that declares one is in none, and the types declared directly
		// inside it are enclosed by no type declaration of the file.
		extendedType = node.extendedType.typeDescription
		enclosingExtensionAccess = node.modifiers.access(introducedBy: node.extensionKeyword, sourceLocationConverter: sourceLocationConverter)
		return visitTypeDeclaration(node.attributes, declaring: node.extendedType.typeDescription, access: nil, isTypeDefinition: false)
	}

	override func visitPost(_: ExtensionDeclSyntax) {
		extendedType = nil
		enclosingExtensionAccess = nil
		exitType()
	}

	override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
		let declaredType = typeDefined(named: node.name.text)
		let access = node.modifiers.access(introducedBy: node.enumKeyword, sourceLocationConverter: sourceLocationConverter)
		recordPlainTypeDeclaration(declaredType, access: access, isInstantiable: node.attributes.instantiableMacro != nil)
		enterType(declaredType, access: access)
		return switch context {
		case .declarations:
			// Enums can nest instantiable types.
			.visitChildren
		case .members:
			.skipChildren
		}
	}

	override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
		// A protocol's body declares nothing SafeDI reads.
		recordPlainTypeDeclaration(
			typeDefined(named: node.name.text),
			access: node.modifiers.access(introducedBy: node.protocolKeyword, sourceLocationConverter: sourceLocationConverter),
			isInstantiable: false,
		)
		return .skipChildren
	}

	override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
		recordPlainTypeDeclaration(
			typeDefined(named: node.name.text),
			access: node.modifiers.access(introducedBy: node.typealiasKeyword, sourceLocationConverter: sourceLocationConverter),
			isInstantiable: false,
		)
		return .skipChildren
	}

	override func visitPost(_: EnumDeclSyntax) {
		exitType()
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
	private let sourceLocationConverter: SourceLocationConverter?
	/// The type whose members the walk is among, if any, which encloses the types declared there.
	private var enclosingType: TypeDescription?
	/// The access of each type declaration enclosing the walk's position in its file, outermost first.
	private var enclosingTypeAccess: [AccessDeclaration]
	/// The enclosing type and the access of each enclosing type declaration of each declaration the walk is inside,
	/// innermost last.
	private var outerEnclosingTypes = [(type: TypeDescription?, access: [AccessDeclaration])]()
	/// The type the extension the walk is inside extends, if it is inside one.
	private var extendedType: TypeDescription?
	/// The access of the extension the walk is inside, if it is inside one.
	private var enclosingExtensionAccess: AccessDeclaration?

	/// - Parameters:
	///   - declaredType: The type the declaration declares, which encloses the types among its members.
	///   - access: The access the declaration spells, or `nil` for an extension, which encloses its members in no type
	///     declaration of the file.
	///   - isTypeDefinition: Whether the declaration defines a type, which only a type definition
	///     can make a root, or a type whose dependency tree SafeDI generates: SafeDI never treats an
	///     `@Instantiable` extension as either.
	private func visitTypeDeclaration(_ attributes: AttributeListSyntax, declaring declaredType: TypeDescription, access: AccessDeclaration?, isTypeDefinition: Bool) -> SyntaxVisitorContinueKind {
		if let access {
			recordPlainTypeDeclaration(declaredType, access: access, isInstantiable: attributes.instantiableMacro != nil)
		}
		enterType(declaredType, access: access)
		switch context {
		case .declarations:
			if let instantiableMacro = attributes.instantiableMacro {
				record(instantiableMacro.mockOnlyValue ? .mockOnly : .production)
				outputFileDeclarations.recordInstantiable(
					named: declaredType.asSource,
					inExtensionOf: extendedType,
					isRoot: isTypeDefinition && instantiableMacro.isRootValue,
					generatesDependencyTree: isTypeDefinition && instantiableMacro.generatesDependencyTreeValue,
					generatesMock: instantiableMacro.generateMockValue,
				)
			}
			// Nested types may be instantiable too.
			return .visitChildren
		case .members:
			return .skipChildren
		}
	}

	/// The type a type definition named `name` defines among the members of the enclosing type, as `FileVisitor` names it.
	private func typeDefined(named name: String) -> TypeDescription {
		if let enclosingType {
			.nested(name: name, parentType: enclosingType)
		} else {
			.simple(name: name)
		}
	}

	/// Makes `type`, declared with `access`, the enclosing type until the declaration that declares it ends. An extension,
	/// whose `access` is `nil`, is enclosed by no type declaration of the file.
	private func enterType(_ type: TypeDescription, access: AccessDeclaration?) {
		outerEnclosingTypes.append((enclosingType, enclosingTypeAccess))
		enclosingType = type
		if let access {
			enclosingTypeAccess.append(access)
		} else {
			enclosingTypeAccess = []
		}
	}

	/// Restores the enclosing type of the declaration that just ended.
	private func exitType() {
		(enclosingType, enclosingTypeAccess) = outerEnclosingTypes.removeLast()
	}

	/// Records the outermost name of `type`, which a declaration with `access` declares, among `plainTypeNames` when it is
	/// not `@Instantiable` and the walk is among type declarations.
	private func recordPlainTypeDeclaration(_ type: TypeDescription, access: AccessDeclaration, isInstantiable: Bool) {
		guard case .declarations = context, !isInstantiable else { return }
		plainTypeNames.record(PlainTypeDeclaration(
			typeDescription: type,
			access: access,
			enclosingTypeAccess: enclosingTypeAccess,
			enclosingExtensionAccess: enclosingExtensionAccess,
		))
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
