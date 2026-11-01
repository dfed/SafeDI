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

import SwiftDiagnostics
import SwiftSyntax

public final class InstantiableVisitor: SyntaxVisitor {
	// MARK: Initialization

	/// - Parameters:
	///   - declarationType: The kind of declaration this visitor walks.
	///   - parentType: The type enclosing the walked declaration, if any.
	///   - enclosingTypeAccess: The access of each type declaration enclosing the walked declaration in its file,
	///     outermost first.
	///   - enclosingExtensionAccess: The access of the extension enclosing the walked declaration, if one does.
	///   - conditionalCompilation: How `#if` blocks among the declaration's members are scanned. The macro scans every clause because the compiler has already selected the active one; SafeDITool evaluates them.
	///   - sourceLocationConverter: A converter for the tree being walked. When provided, the declaration and each dependency record where they begin.
	public init(
		declarationType: DeclarationType,
		parentType: TypeDescription? = nil,
		enclosingTypeAccess: [AccessDeclaration] = [],
		enclosingExtensionAccess: AccessDeclaration? = nil,
		conditionalCompilation: ConditionalCompilationHandling = .scanAllClauses,
		sourceLocationConverter: SourceLocationConverter? = nil,
	) {
		self.declarationType = declarationType
		self.parentType = parentType
		self.enclosingTypeAccess = enclosingTypeAccess
		self.enclosingExtensionAccess = enclosingExtensionAccess
		self.conditionalCompilation = conditionalCompilation
		self.sourceLocationConverter = sourceLocationConverter
		super.init(viewMode: .sourceAccurate)
	}

	// MARK: SyntaxVisitor

	public override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
		guard declarationType.isTypeDefinition,
		      node.modifiers.staticModifier == nil
		else {
			return .skipChildren
		}
		// Check attributes and extract dependency source.
		let dependencySources = node.attributes.dependencySources
		if dependencySources.count > 1 {
			diagnostics.append(Diagnostic(
				node: node.attributes,
				error: FixableInstantiableError.dependencyHasTooManyAttributes,
				changes: [
					.replace(
						oldNode: Syntax(node.attributes),
						newNode: Syntax(dependencySources[0].attribute),
					),
				],
			))
		}
		guard case let (dependencySource, dependencyAttribute)? = dependencySources.first else {
			// This dependency is not part of the DI system.
			// If this variable declaration is missing a binding and is non-optional, we need a custom initializer.
			let patterns = node
				.bindings
				.filter {
					$0.accessorBlock == nil
						&& !$0.isOptionalOrInitialized
				}
				.map(\.pattern)
			uninitializedNonOptionalPropertyNames += patterns
				.compactMap(IdentifierPatternSyntax.init)
				.map(\.identifier.text)
				+ patterns
				.compactMap(TuplePatternSyntax.init)
				.map(\.trimmedDescription)
			return .skipChildren
		}

		// An alias's fulfilling property is named in generated code, where it is assigned to the alias.
		if let fulfilledByDependencyNamed = dependencyAttribute.fulfilledByDependencyNamed,
		   let fulfillingPropertyName = dependencyAttribute.fulfillingPropertyName,
		   let reservation = ReservedName(reserving: fulfillingPropertyName)
		{
			diagnose(fulfillingPropertyName, reservedAs: reservation, at: fulfilledByDependencyNamed)
		}

		// A fix-it rewrites the whole attribute, so its range is recorded only when there are no arguments to discard.
		let bareAttributeRange: Dependency.SourceRange? = if dependencyAttribute.arguments == nil {
			sourceRange(of: dependencyAttribute)
		} else {
			nil
		}

		// Check the bindings.
		for binding in node.bindings {
			// Check that each variable has no initializer.
			if let initializer = binding.initializer {
				var bindingWithoutInitializer = binding
				bindingWithoutInitializer.initializer = nil
				diagnostics.append(Diagnostic(
					node: node,
					error: FixableInstantiableError.dependencyHasInitializer(
						propertyName: binding.pattern.trimmedDescription,
						initializer: initializer.trimmedDescription,
					),
					changes: [
						.replace(
							oldNode: Syntax(binding),
							newNode: Syntax(bindingWithoutInitializer),
						),
					],
				))
			}

			if let identifier = IdentifierPatternSyntax(binding.pattern)?.identifier,
			   let type = binding.typeAnnotation?.type
			{
				if let reservation = ReservedName(reserving: identifier.text) {
					diagnose(identifier.text, reservedAs: reservation, at: identifier)
				}
				dependencies.append(
					Dependency(
						property: Property(
							label: identifier.text.spelledAsIdentifier,
							typeDescription: type.typeDescription,
						),
						source: dependencySource,
						declarationLocation: declarationLocation(of: node),
						identifierRange: sourceRange(of: identifier),
						typeAnnotationRange: sourceRange(of: type),
						bareAttributeRange: bareAttributeRange,
					),
				)
			}
		}

		return .skipChildren
	}

	public override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
		guard declarationType.isTypeDefinition else {
			return .skipChildren
		}
		let initializer = Initializer(node, sourceLocationConverter: sourceLocationConverter)
		initializers.append(initializer)
		initializerSyntaxes.append(node)
		return .skipChildren
	}

	public override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
		visitDecl(node)
	}

	public override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
		visitDecl(node)
	}

	public override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
		visitDecl(node)
	}

	public override func visit(_: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
		.skipChildren
	}

	public override func visit(_: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
		.skipChildren
	}

	public override func visit(_ node: IfConfigDeclSyntax) -> SyntaxVisitorContinueKind {
		if case let .evaluate(evaluator) = conditionalCompilation {
			// Members of a declaration without `@Instantiable` are never scanned, so nothing inside matters.
			let content: SafeDIContent = if let instantiableConstruction {
				node.safeDIContent(in: .members(.init(
					construction: instantiableConstruction,
					isMockOnly: mockOnly,
					customMockName: customMockName,
				)))
			} else {
				.none
			}
			let scannable = evaluator.scannableClauses(in: node, guarding: content)
			activeIfConfigClauses.formUnion(scannable.clauses.map(\.id))
			conditionalCompilationDecisions.append(contentsOf: scannable.decisions)
			// Members that SafeDI does not scan for change nothing this visitor reports to SafeDITool,
			// which is also why no decision about them is asserted.
			if content != .none {
				consultedCompilationConditions.formUnion(scannable.consultedConditions)
			}
		}
		return .visitChildren
	}

	public override func visit(_ node: IfConfigClauseSyntax) -> SyntaxVisitorContinueKind {
		switch conditionalCompilation {
		case .scanAllClauses:
			.visitChildren
		case .evaluate:
			activeIfConfigClauses.contains(node.id) ? .visitChildren : .skipChildren
		}
	}

	public override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
		instantiableType = node.extendedType.typeDescription
		instantiableDeclarationLocation = declarationLocation(of: node)
		instantiableAccess = node.modifiers.access(introducedBy: node.extensionKeyword, sourceLocationConverter: sourceLocationConverter)
		if let instantiableMacro = node.attributes.instantiableMacro {
			instantiableConstruction = .instantiateMethod
			processAttributes(node.attributes, on: instantiableMacro)
		}

		return .visitChildren
	}

	public override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
		// Detect existing static/class func mock(...) methods.
		// When customMockName is set, detect by that name; otherwise detect "mock".
		let mockMethodName = customMockName ?? Self.mockMethodName
		let isStaticOrClass = node.modifiers.contains(where: { $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class) })
		if node.name.text == mockMethodName, isStaticOrClass {
			if mockFunctionSyntax != nil {
				// Already found one mock() method — this is a duplicate.
				duplicateMockFunctionSyntaxes.append(node)
			} else {
				mockInitializer = Initializer(node, sourceLocationConverter: sourceLocationConverter)
				mockReturnType = node.signature.returnClause?.type.typeDescription
				mockDeclarationLocation = declarationLocation(of: node)
				mockDeclarationAccess = instantiableAccess
				mockFunctionSyntax = node
			}
		}
		// When customMockName is set, also detect a literal "mock" method — it would
		// conflict with the generated mock().
		if customMockName != nil, node.name.text == Self.mockMethodName, isStaticOrClass {
			conflictingMockFunctionSyntax = node
		}

		guard declarationType.isExtension else {
			return .skipChildren
		}
		guard node.name.text == Self.instantiateMethodName else {
			// We don't care about this method.
			return .skipChildren
		}

		if let returnClause = node.signature.returnClause,
		   returnClause.type.typeDescription.strippingGenerics != instantiableType?.strippingGenerics,
		   let instantiableType
		{
			var modifiedSignature = node.signature
			modifiedSignature.returnClause = ReturnClauseSyntax(
				arrow: .arrowToken(
					leadingTrivia: returnClause.arrow.leadingTrivia,
					trailingTrivia: returnClause.arrow.trailingTrivia,
				),
				type: IdentifierTypeSyntax(
					leadingTrivia: node.signature.leadingTrivia,
					name: .identifier(instantiableType.strippingGenerics.asSource),
					trailingTrivia: node.signature.trailingTrivia,
				),
			)
			diagnostics.append(Diagnostic(
				node: node,
				error: FixableInstantiableError.incorrectReturnType(typeName: instantiableType.strippingGenerics.asSource),
				changes: [
					.replace(
						oldNode: Syntax(node.signature),
						newNode: Syntax(modifiedSignature),
					),
				],
			))
		}

		let initializer = Initializer(node, sourceLocationConverter: sourceLocationConverter)
		if let instantiableType = node.signature.returnClause?.type.typeDescription {
			// Each parameter without a default value is a dependency named by its inner name. Its argument label
			// binds nothing. A parameter with a default value is not a dependency, as for an initializer: the
			// generated call leaves it out, so its default applies, and a generated mock offers it as an override.
			let dependencyParameters = zip(initializer.arguments, node.signature.parameterClause.parameters).filter { argument, _ in
				!argument.hasDefaultValue
			}
			for name in dependencyParameters.lazy.map({ $0.1.secondName ?? $0.1.firstName }) {
				if let reservation = ReservedName(reserving: name.text) {
					diagnose(name.text, reservedAs: reservation, at: name)
				}
			}
			let dependencies = dependencyParameters.map { argument, parameter in
				Dependency(
					property: argument.asProperty,
					source: .received(onlyIfAvailable: false),
					declarationLocation: declarationLocation(of: parameter),
					// The dependency's label is the inner name, so that is the token a rename fix-it replaces.
					identifierRange: sourceRange(of: parameter.secondName ?? parameter.firstName),
					typeAnnotationRange: sourceRange(of: parameter.type),
				)
			}
			extensionInstantiables.append(.init(
				instantiableType: instantiableType,
				isRoot: false,
				initializer: initializer,
				additionalInstantiables: additionalInstantiables,
				dependencies: dependencies,
				declarationType: .extensionType,
				access: instantiableAccess,
				enclosingTypeAccess: enclosingTypeAccess,
				enclosingExtensionAccess: enclosingExtensionAccess,
				generatedInitializerAttributes: generatedInitializerAttributes,
				mockAttributes: mockAttributes,
				generateMock: generateMock,
				mockOnly: mockOnly,
				mockInitializer: mockInitializer,
				mockReturnType: mockReturnType,
				customMockName: customMockName,
				mockDeclarationLocation: mockDeclarationLocation,
				mockDeclarationAccess: mockDeclarationAccess,
				declarationLocation: instantiableDeclarationLocation,
			))
			instantiateFunctions.append(InstantiateFunction(syntax: node, initializer: initializer, dependencies: dependencies))
		}

		if node.modifiers.staticModifier == nil {
			var modifiedNode = node
			let staticModifier = DeclModifierSyntax(name: .keyword(.static), trailingTrivia: .space)
			if node.modifiers.isEmpty {
				// The modifier takes the place of the keyword it precedes.
				modifiedNode.modifiers = [staticModifier.with(\.leadingTrivia, node.funcKeyword.leadingTrivia)]
				modifiedNode.funcKeyword.leadingTrivia = []
			} else {
				modifiedNode.modifiers.append(staticModifier)
			}
			diagnostics.append(Diagnostic(
				node: node,
				error: FixableInstantiableError.instantiateMethodNotStatic,
				changes: [
					.replace(
						oldNode: Syntax(node),
						newNode: Syntax(modifiedNode),
					),
				],
			))
		}
		// Any other access can suit the code that calls the method; SafeDITool checks that code, which it generates.
		if let (modifiedNode, accessLevel) = node.removingPrivateOrFilePrivateModifier(keyword: \.funcKeyword) {
			diagnostics.append(Diagnostic(
				node: node,
				error: FixableInstantiableError.privateOrFilePrivateInstantiateMethod(accessLevel),
				changes: [
					.replace(
						oldNode: Syntax(node),
						newNode: Syntax(modifiedNode),
					),
				],
			))
		}
		if initializer.isAsync || initializer.doesThrow {
			var modifiedSignature = node.signature
			modifiedSignature.effectSpecifiers = nil
			diagnostics.append(Diagnostic(
				node: node,
				error: FixableInstantiableError.disallowedEffectSpecifiers,
				changes: [
					.replace(
						oldNode: Syntax(node.signature),
						newNode: Syntax(modifiedSignature),
					),
				],
			))
		}
		if initializer.hasGenericParameter {
			var modifiedNode = node
			modifiedNode.genericParameterClause = nil
			diagnostics.append(Diagnostic(
				node: node,
				error: FixableInstantiableError.disallowedGenericParameter,
				changes: [
					.replace(
						oldNode: Syntax(node),
						newNode: Syntax(modifiedNode),
					),
				],
			))
		}
		if initializer.hasGenericWhereClause {
			var modifiedNode = node
			modifiedNode.genericWhereClause = nil
			diagnostics.append(Diagnostic(
				node: node,
				error: FixableInstantiableError.disallowedGenericWhereClause,
				changes: [
					.replace(
						oldNode: Syntax(node),
						newNode: Syntax(modifiedNode),
					),
				],
			))
		}

		return .skipChildren
	}

	// MARK: Public

	public private(set) var isRoot = false
	public private(set) var dependencies = [Dependency]()
	public private(set) var initializers = [Initializer]()
	/// The declaration of each of `initializers`, at the same position. Two initializers can be equal – the same
	/// signature in two clauses of an `#if` block – so a declaration is found by position, never by value.
	public private(set) var initializerSyntaxes = [InitializerDeclSyntax]()
	public private(set) var instantiableType: TypeDescription?
	public private(set) var additionalInstantiables: [TypeDescription]?
	public private(set) var generatedInitializerAttributes = ""
	public private(set) var mockAttributes = ""
	public private(set) var generateMock: Bool = false
	public private(set) var mockOnly: Bool = false
	public private(set) var customMockName: String?
	public private(set) var mockInitializer: Initializer?
	public private(set) var mockReturnType: TypeDescription?
	public private(set) var mockFunctionSyntax: FunctionDeclSyntax?
	/// Where `mockFunctionSyntax` begins, recorded when the declaration is visited with a converter.
	public private(set) var mockDeclarationLocation: Dependency.DeclarationLocation?
	/// The access of the declaration that declares `mockFunctionSyntax`, recorded when the mock method is visited.
	public private(set) var mockDeclarationAccess: AccessDeclaration?
	public private(set) var duplicateMockFunctionSyntaxes = [FunctionDeclSyntax]()
	/// The `instantiate(…)` methods of an extension that declare a return type, in source order.
	public private(set) var instantiateFunctions = [InstantiateFunction]()

	/// An extension's `instantiate(…)` method, with the dependencies it takes.
	public struct InstantiateFunction {
		public let syntax: FunctionDeclSyntax
		public let initializer: Initializer
		/// The parameters without default values.
		public let dependencies: [Dependency]
	}

	public private(set) var conflictingMockFunctionSyntax: FunctionDeclSyntax?
	public private(set) var diagnostics = [Diagnostic]()
	public private(set) var uninitializedNonOptionalPropertyNames = [String]()
	/// How each `#if` condition that guards members SafeDI scans was evaluated, in source order.
	public private(set) var conditionalCompilationDecisions = [ConditionalCompilationDecision]()
	/// Every bare condition whose value decided which members SafeDI scans.
	public private(set) var consultedCompilationConditions = Set<String>()

	/// The initializer SafeDI selects for construction — the first in source
	/// order that fulfills this type's dependencies. `Instantiable.initializer`
	/// is populated from this, and mock generation emits construction code
	/// against this initializer's signature. Validation that only matters for
	/// the path SafeDI actually uses (e.g., diagnosing `Self.*` in default
	/// expressions) should gate on this initializer rather than walking
	/// `initializers`, which would false-positive on unused overloads.
	public var canonicalConstructionInitializer: Initializer? {
		initializers.first(where: { $0.isValid(forFulfilling: dependencies) })
	}

	public static let macroName = "Instantiable"
	public static let instantiateMethodName = "instantiate"
	public static let mockMethodName = "mock"

	public func walk(_ node: some ConcreteDeclSyntaxProtocol) {
		super.walk(node)
	}

	public func walk(_ node: ExtensionDeclSyntax) {
		super.walk(node)
	}

	// MARK: DeclarationType

	public enum DeclarationType {
		/// A concrete type declaration.
		case concreteDecl
		/// An extension declaration.
		case extensionDecl

		var isTypeDefinition: Bool {
			switch self {
			case .concreteDecl:
				true
			case .extensionDecl:
				false
			}
		}

		var isExtension: Bool {
			switch self {
			case .concreteDecl:
				false
			case .extensionDecl:
				true
			}
		}
	}

	public var instantiables: [Instantiable] {
		switch declarationType {
		case .concreteDecl:
			if let instantiableType, let instantiableDeclarationType {
				[
					Instantiable(
						instantiableType: instantiableType,
						isRoot: isRoot,
						initializer: canonicalConstructionInitializer,
						additionalInstantiables: additionalInstantiables,
						dependencies: dependencies,
						declarationType: instantiableDeclarationType.asDeclarationType,
						access: instantiableAccess,
						enclosingTypeAccess: enclosingTypeAccess,
						enclosingExtensionAccess: enclosingExtensionAccess,
						generatedInitializerAttributes: generatedInitializerAttributes,
						mockAttributes: mockAttributes,
						generateMock: generateMock,
						mockOnly: mockOnly,
						mockInitializer: mockInitializer,
						mockReturnType: mockReturnType,
						customMockName: customMockName,
						mockDeclarationLocation: mockDeclarationLocation,
						mockDeclarationAccess: mockDeclarationAccess,
						declarationLocation: instantiableDeclarationLocation,
					),
				]
			} else {
				[]
			}
		case .extensionDecl:
			if extensionInstantiables.isEmpty, mockOnly, let mockReturnType {
				// mockOnly extensions without instantiate() still produce an Instantiable
				// so the type is registered in the mock scope map. Use the extended
				// type (instantiableType) as the concrete type — not mockReturnType,
				// which may be a protocol from fulfillingAdditionalTypes.
				[
					Instantiable(
						instantiableType: instantiableType ?? mockReturnType,
						isRoot: isRoot,
						initializer: nil,
						additionalInstantiables: additionalInstantiables,
						dependencies: [],
						declarationType: .extensionType,
						access: instantiableAccess,
						enclosingTypeAccess: enclosingTypeAccess,
						enclosingExtensionAccess: enclosingExtensionAccess,
						generatedInitializerAttributes: generatedInitializerAttributes,
						mockAttributes: mockAttributes,
						generateMock: generateMock,
						mockOnly: mockOnly,
						mockInitializer: mockInitializer,
						mockReturnType: mockReturnType,
						customMockName: customMockName,
						mockDeclarationLocation: mockDeclarationLocation,
						mockDeclarationAccess: mockDeclarationAccess,
						declarationLocation: instantiableDeclarationLocation,
					),
				]
			} else {
				// mockInitializer may be set after extensionInstantiables are built
				// (visit order depends on source order). Patch it in here.
				extensionInstantiables.map { instantiable in
					guard instantiable.mockInitializer == nil, let mockInitializer else {
						return instantiable
					}
					var patched = instantiable
					patched.mockInitializer = mockInitializer
					patched.mockReturnType = mockReturnType
					patched.mockDeclarationLocation = mockDeclarationLocation
					patched.mockDeclarationAccess = mockDeclarationAccess
					return patched
				}
			}
		}
	}

	// MARK: Private

	/// How the walked declaration constructs its type, set once the declaration is found to carry
	/// `@Instantiable`, which is when its members matter.
	private var instantiableConstruction: SafeDIContentContext.InstantiableMembers.Construction?
	private var instantiableDeclarationType: ConcreteDeclType?

	private var extensionInstantiables = [Instantiable]()

	private let declarationType: DeclarationType
	private let parentType: TypeDescription?
	private let enclosingTypeAccess: [AccessDeclaration]
	private let enclosingExtensionAccess: AccessDeclaration?
	private let conditionalCompilation: ConditionalCompilationHandling
	private let sourceLocationConverter: SourceLocationConverter?
	/// The `#if` clauses the evaluator selected for scanning.
	private var activeIfConfigClauses = Set<SyntaxIdentifier>()

	/// The location of the decorated declaration, recorded when the declaration is visited with a converter.
	private var instantiableDeclarationLocation: Dependency.DeclarationLocation?
	/// The access the decorated type declaration or extension spells, recorded when it is visited, before any
	/// instantiable or mock method is found in it.
	private var instantiableAccess = AccessDeclaration(level: .internal)

	/// Reports that `name`, which generated code binds or refers to, collides with `reservation`.
	/// No fix-it is offered: SafeDI matches dependencies by label, so a new name could fulfill, or be fulfilled
	/// by, a different dependency without any error, and nothing this visitor sees can rule that out.
	private func diagnose(_ name: String, reservedAs reservation: ReservedName, at node: some SyntaxProtocol) {
		diagnostics.append(Diagnostic(
			node: node,
			message: FixableInstantiableError.reservedName(name: name, reservation: reservation).diagnostic,
		))
	}

	/// Where `node` begins after its leading trivia – its first attribute for a decorated declaration – or `nil` without a converter.
	private func declarationLocation(of node: some SyntaxProtocol) -> Dependency.DeclarationLocation? {
		sourceLocationConverter.map { sourceLocationConverter in
			sourceLocationConverter.declarationLocation(for: node.positionAfterSkippingLeadingTrivia)
		}
	}

	/// The range of `node`’s text, excluding its leading and trailing trivia, or `nil` without a converter.
	private func sourceRange(of node: some SyntaxProtocol) -> Dependency.SourceRange? {
		sourceLocationConverter.map { sourceLocationConverter in
			sourceLocationConverter.sourceRange(of: node)
		}
	}

	private func visitDecl(_ node: some ConcreteDeclSyntaxProtocol) -> SyntaxVisitorContinueKind {
		let nodeDeclarationType: TypeDescription = if let parentType {
			.nested(
				name: node.name.text,
				parentType: parentType,
			)
		} else {
			.simple(name: node.name.text)
		}
		guard declarationType.isTypeDefinition else {
			return .skipChildren
		}
		guard let macro = node.attributes.instantiableMacro else {
			// Not an instantiable type. We do not care.
			return .skipChildren
		}
		guard instantiableConstruction == nil else {
			return .skipChildren
		}
		instantiableConstruction = .initializer(ConstructionInitializerCandidates(declaration: node))
		instantiableDeclarationType = node.declType
		instantiableDeclarationLocation = declarationLocation(of: node)

		instantiableType = nodeDeclarationType
		processAttributes(node.attributes, on: macro)
		processModifiers(on: node)
		instantiableAccess = node.modifiers.access(introducedBy: node.keyword, sourceLocationConverter: sourceLocationConverter)

		return .visitChildren
	}

	private func processAttributes(_: AttributeListSyntax, on macro: AttributeSyntax) {
		func processIsRoot() {
			isRoot = macro.isRootValue
		}
		func processFulfillingAdditionalTypesParameter() {
			guard let fulfillingAdditionalTypesExpression = macro.fulfillingAdditionalTypes,
			      let fulfillingAdditionalTypesArray = ArrayExprSyntax(fulfillingAdditionalTypesExpression)
			else {
				// Nothing to do here.
				return
			}

			additionalInstantiables = fulfillingAdditionalTypesArray
				.elements
				.map(\.expression.typeDescription.asInstantiatedType)
		}
		func processGeneratedAttributes() {
			if let generatedAttributes = macro.generatedAttributesValue {
				generatedInitializerAttributes = generatedAttributes
				mockAttributes = generatedAttributes
			} else {
				generatedInitializerAttributes = macro.generatedInitializerAttributesValue
				mockAttributes = macro.mockAttributesValue
			}
		}
		func processGenerateMock() {
			generateMock = macro.generateMockValue
		}
		func processMockOnly() {
			mockOnly = macro.mockOnlyValue
		}
		func processCustomMockName() {
			customMockName = macro.customMockNameValue
		}

		processIsRoot()
		processFulfillingAdditionalTypesParameter()
		processGeneratedAttributes()
		processGenerateMock()
		processMockOnly()
		processCustomMockName()
	}

	/// Reports a `private` or `fileprivate` type, which the code SafeDI generates in another file can never construct.
	/// Any other access can suit the code that constructs the type; SafeDITool checks that code, which it generates.
	private func processModifiers(on node: some ConcreteDeclSyntaxProtocol) {
		if let (modifiedNode, accessLevel) = node.removingPrivateOrFilePrivateModifier(keyword: \.keyword) {
			diagnostics.append(Diagnostic(
				node: node,
				error: FixableInstantiableError.privateOrFilePrivateType(accessLevel),
				changes: [
					.replace(
						oldNode: Syntax(node),
						newNode: Syntax(modifiedNode),
					),
				],
			))
		}
	}
}

// MARK: - SourceLocationConverter

extension SourceLocationConverter {
	func declarationLocation(for position: AbsolutePosition) -> Dependency.DeclarationLocation {
		let location = location(for: position)
		return Dependency.DeclarationLocation(filePath: location.file, line: location.line, column: location.column)
	}

	/// The range of `node`’s text, excluding its leading and trailing trivia.
	func sourceRange(of node: some SyntaxProtocol) -> Dependency.SourceRange {
		let start = location(for: node.positionAfterSkippingLeadingTrivia)
		let end = location(for: node.endPositionBeforeTrailingTrivia)
		return Dependency.SourceRange(
			startLine: start.line,
			startColumn: start.column,
			endLine: end.line,
			endColumn: end.column,
		)
	}
}
