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

public struct Instantiable: Codable, Hashable, Sendable {
	// MARK: Initialization

	public init(
		instantiableType: TypeDescription,
		isRoot: Bool,
		generatesDependencyTree: Bool = false,
		initializer: Initializer?,
		otherInitializers: [Initializer] = [],
		additionalInstantiables: [TypeDescription]?,
		dependencies: [Dependency],
		declarationType: DeclarationType,
		access: AccessDeclaration,
		enclosingTypeAccess: [AccessDeclaration] = [],
		enclosingExtensionAccess: AccessDeclaration? = nil,
		generatedInitializerAttributes: String = "",
		mockAttributes: String = "",
		generateMock: MockGeneration = .none,
		mockGenerationArgumentRange: Dependency.SourceRange? = nil,
		mockOnly: Bool = false,
		mockInitializer: Initializer? = nil,
		mockReturnType: TypeDescription? = nil,
		customMockName: String? = nil,
		mockDeclarationLocation: Dependency.DeclarationLocation? = nil,
		mockDeclarationAccess: AccessDeclaration? = nil,
		mockDeclarationModuleName: String? = nil,
		mockDeclarationPackageName: String? = nil,
		declarationLocation: Dependency.DeclarationLocation? = nil,
		moduleName: String? = nil,
		packageName: String? = nil,
		conformanceListNamesSendable: Bool = false,
		conformanceListNamesOtherTypes: Bool = false,
	) {
		storage = Storage(Fields(
			instantiableTypes: [instantiableType] + (additionalInstantiables ?? []),
			sourceFilePath: nil,
			declarationLocation: declarationLocation,
			rarelySetFields: RarelySetFieldsBox(holding: RarelySetFields(
				enclosingExtensionAccess: enclosingExtensionAccess,
				mockGenerationArgumentRange: mockGenerationArgumentRange,
				mockInitializer: mockInitializer,
				mockReturnType: mockReturnType,
				customMockName: customMockName,
				mockDeclarationLocation: mockDeclarationLocation,
				mockDeclarationAccess: mockDeclarationAccess,
				mockDeclarationModuleName: mockDeclarationModuleName,
				mockDeclarationPackageName: mockDeclarationPackageName,
			)),
			isRoot: isRoot,
			generatesDependencyTree: generatesDependencyTree,
			initializer: initializer,
			otherInitializers: otherInitializers,
			dependencies: dependencies,
			declarationType: declarationType,
			access: access,
			enclosingTypeAccess: enclosingTypeAccess,
			generatedInitializerAttributes: generatedInitializerAttributes,
			mockAttributes: mockAttributes,
			generateMock: generateMock,
			mockOnly: mockOnly,
			moduleName: moduleName,
			packageName: packageName,
			conformanceListNamesSendable: conformanceListNamesSendable,
			conformanceListNamesOtherTypes: conformanceListNamesOtherTypes,
		))
	}

	// MARK: Public

	/// The types that can be fulfilled with this Instantiable.
	public private(set) var instantiableTypes: [TypeDescription] {
		get { storage.fields.instantiableTypes }
		set { updateFields { $0.instantiableTypes = newValue } }
	}

	/// The concrete type that fulfills `instantiableTypes`.
	public var concreteInstantiable: TypeDescription {
		instantiableTypes[0]
	}

	/// Whether the instantiable type is a root of a dependency graph.
	public var isRoot: Bool {
		storage.fields.isRoot
	}

	/// Whether SafeDI generates the type's dependency tree in the module that declares it, as an initializer that
	/// takes what the tree needs from outside as parameters, which every other tree calls instead of building the
	/// tree again. Never `true` together with `isRoot` or `mockOnly`, and never on an extension: the macro rejects
	/// each.
	public var generatesDependencyTree: Bool {
		storage.fields.generatesDependencyTree
	}

	/// A memberwise initializer for the concrete instantiable type.
	/// If `nil`, the Instantiable type is incorrectly configured.
	public private(set) var initializer: Initializer? {
		get { storage.fields.initializer }
		set { updateFields { $0.initializer = newValue } }
	}

	/// The type declaration's initializers other than `initializer`, in declaration order, which SafeDI never
	/// constructs the type with. An initializer SafeDI generates for the type must not redeclare one of them. Empty
	/// for an extension-based instantiable.
	public private(set) var otherInitializers: [Initializer] {
		get { storage.fields.otherInitializers }
		set { updateFields { $0.otherInitializers = newValue } }
	}

	/// The ordered dependencies of this Instantiable.
	public private(set) var dependencies: [Dependency] {
		get { storage.fields.dependencies }
		set { updateFields { $0.dependencies = newValue } }
	}

	/// The declaration type of the Instantiable’s concrete type.
	public var declarationType: DeclarationType {
		storage.fields.declarationType
	}

	/// The access spelled on the declaration this Instantiable was found on: the type declaration, or, for an
	/// extension-based Instantiable, the extension, whose members default to it (`fileprivate` for a `private`
	/// extension). Its level is `internal` when the declaration spells none. An extension's `instantiate()` records the
	/// access spelled on the method itself in `initializer`, so the method's effective access is derived later from
	/// both. A hand-written mock method may be declared in another declaration that is merged into this one, so the
	/// access of the declaration that declares it is `mockDeclarationAccess`, and the access spelled on the method
	/// itself is on `mockInitializer`.
	public var access: AccessDeclaration {
		storage.fields.access
	}

	/// The access spelled on each class, actor, struct, and enum declaration in the file that encloses the declaration
	/// this Instantiable was found on, outermost first. Each caps the declaration's effective access. Empty when no
	/// type declaration encloses it, which is always the case for an extension-based Instantiable, whose own `access`
	/// is the extension's.
	public var enclosingTypeAccess: [AccessDeclaration] {
		storage.fields.enclosingTypeAccess
	}

	/// The access spelled on the extension that encloses the declaration this Instantiable was found on, if one does.
	/// An extension is declared at file scope, so it can only be outermost. Unlike an enclosing type, it caps nothing:
	/// it is only the default access of the one declaration directly inside it – the first entry of
	/// `enclosingTypeAccess`, or this declaration when that list is empty – when that declaration spells no access
	/// modifier (its `modifierRange` is `nil`), with `fileprivate` as a `private` extension's default. The extended
	/// type's own access is declared elsewhere and unknown to the tool. `nil` for an extension-based Instantiable, whose
	/// own `access` is the extension's.
	public var enclosingExtensionAccess: AccessDeclaration? {
		rarelySetFields?.fields.enclosingExtensionAccess
	}

	/// Attributes to add to the initializers SafeDI generates for this type (e.g. `"@MainActor"`) – a root's `init()`,
	/// and each tier of a type with `generateDependencyTree: true`: the macro's
	/// `generatedAttributes` when it is given, else its `generatedInitializerAttributes`. The declaration's own: a
	/// `mockOnly` declaration merged into this one contributes none, as for `mockAttributes`.
	public var generatedInitializerAttributes: String {
		storage.fields.generatedInitializerAttributes
	}

	/// Attributes to add to the generated `mock()` method (e.g. `"@MainActor"`): the macro's `generatedAttributes` when
	/// it is given, else its `mockAttributes`. The declaration's own: a `mockOnly` declaration merged into this one,
	/// whose hand-written mock the generated `mock()` calls, contributes none.
	public var mockAttributes: String {
		storage.fields.mockAttributes
	}

	/// Whether to generate a `mock()` method for this type, and with what access: the `generateMock:` argument.
	public var generateMock: MockGeneration {
		storage.fields.generateMock
	}

	/// Whether a `mock()` method is generated for this type, with any access.
	public var generatesMock: Bool {
		generateMock.generatesMock
	}

	/// The range of the `generateMock:` argument's value in the file of `declarationLocation`, where a diagnostic about
	/// the requested mock points and its fix-its edit. `nil` when the declaration spells no `generateMock:` argument.
	public var mockGenerationArgumentRange: Dependency.SourceRange? {
		rarelySetFields?.fields.mockGenerationArgumentRange
	}

	/// Where a diagnostic about the requested mock points: the `generateMock:` argument's value, else the declaration.
	public var mockGenerationArgumentLocation: Dependency.DeclarationLocation? {
		declarationLocation.map { declarationLocation in
			// A range read without its positions is reported at the declaration, which only a run that reads them then
			// prints (`SourceDiagnostic.printsPositionStoredElsewhere`).
			guard case let .here(startLine, startColumn, _, _) = mockGenerationArgumentRange?.placement else { return declarationLocation }
			return Dependency.DeclarationLocation(filePath: declarationLocation.filePath, line: startLine, column: startColumn)
		}
	}

	/// Whether this declaration exists solely for mock generation (user provides a hand-written mock method).
	/// When `true`, no `init`/`instantiate()` or `Instantiable` conformance is required.
	public var mockOnly: Bool {
		storage.fields.mockOnly
	}

	/// A user-defined `static func mock(...)` method, if one exists.
	/// When present, mock generation calls this method instead of `init` or `instantiate`.
	public var mockInitializer: Initializer? {
		get { rarelySetFields?.fields.mockInitializer }
		set { updateRarelySetFields { $0.mockInitializer = newValue } }
	}

	/// The return type of the user-defined `mock()` method, if one exists.
	/// Used to determine whether to use the mock method or fall through to `init` based on the property type.
	public var mockReturnType: TypeDescription? {
		get { rarelySetFields?.fields.mockReturnType }
		set { updateRarelySetFields { $0.mockReturnType = newValue } }
	}

	/// The name of the user's custom mock method. With `generateMock`, the generated `mock()` calls
	/// through to this method. With `mockOnly`, SafeDI uses this method as the mock provider.
	public var customMockName: String? {
		rarelySetFields?.fields.customMockName
	}

	/// Where the user-defined mock method begins in source: its first attribute or modifier. Travels with
	/// `mockInitializer` when a `mockOnly` declaration's mock is merged into a production entry, so diagnostics
	/// about the hand-written mock point at the method rather than at the production declaration.
	public var mockDeclarationLocation: Dependency.DeclarationLocation? {
		get { rarelySetFields?.fields.mockDeclarationLocation }
		set { updateRarelySetFields { $0.mockDeclarationLocation = newValue } }
	}

	/// The access spelled on the declaration that declares the user-defined mock method: the declaration this
	/// Instantiable was found on (the type, or the `@Instantiable` extension), or a `mockOnly` extension merged into it,
	/// whose members default to it (`fileprivate` for a `private` extension). Travels with `mockInitializer` when a
	/// `mockOnly` declaration's mock is merged into a production entry. `nil` when there is no user-defined mock.
	public var mockDeclarationAccess: AccessDeclaration? {
		get { rarelySetFields?.fields.mockDeclarationAccess }
		set { updateRarelySetFields { $0.mockDeclarationAccess = newValue } }
	}

	/// The module that declares the user-defined mock method, as `moduleName` names a module, or `nil` when there is no
	/// user-defined mock or SafeDITool does not know the module. A `mockOnly` declaration in a module of its own, such as
	/// a test-support module, declares a mock the production declaration's module does not, so this travels with
	/// `mockInitializer` when that declaration's mock is merged into a production entry.
	public var mockDeclarationModuleName: String? {
		get { rarelySetFields?.fields.mockDeclarationModuleName }
		set { updateRarelySetFields { $0.mockDeclarationModuleName = newValue } }
	}

	/// The package of the module that declares the user-defined mock method, as `packageName` names a package, or `nil`
	/// when there is no user-defined mock or SafeDITool does not know the package. Travels with `mockInitializer` as
	/// `mockDeclarationModuleName` does.
	public var mockDeclarationPackageName: String? {
		get { rarelySetFields?.fields.mockDeclarationPackageName }
		set { updateRarelySetFields { $0.mockDeclarationPackageName = newValue } }
	}

	/// The module that declares this Instantiable: the name the compiler gives the module that compiles the declaration's
	/// file. `nil` when SafeDITool does not know it, which is always the case for a declaration the visitors just walked:
	/// SafeDITool records it when it reads a module, from what the build system tells it. `query` records instead the
	/// name it gives an included module, which can be several path components (`Home/Sources`) and need not be the
	/// compiler's, so nothing may compare a name `query` records with one a build recorded: it serves only to group a
	/// query's declarations by module.
	public var moduleName: String? {
		get { storage.fields.moduleName }
		set { updateFields { $0.moduleName = newValue } }
	}

	/// The package of the module that declares this Instantiable, which decides where a `package` declaration is visible:
	/// the name a build system hands the compiler as `-package-name`, or, under SwiftPM, the package's identity, of which
	/// `-package-name` carries the C99-mangled form (`swift-syntax` becomes `swift_syntax`), so a diagnostic that names
	/// the package must mangle it. `nil` when SafeDITool does not know it, as for `moduleName`.
	public var packageName: String? {
		get { storage.fields.packageName }
		set { updateFields { $0.packageName = newValue } }
	}

	/// Returns a copy of this Instantiable with mock-related fields replaced by those from `mockProvider`.
	/// Used when merging a production `@Instantiable` with a `mockOnly` declaration for the same type.
	public func mergedWithMockProvider(_ mockProvider: Instantiable) -> Instantiable {
		var merged = self
		let mockProviderFields = mockProvider.rarelySetFields?.fields ?? RarelySetFields()
		merged.updateRarelySetFields { fields in
			fields.mockInitializer = mockProviderFields.mockInitializer
			fields.mockReturnType = mockProviderFields.mockReturnType
			fields.customMockName = mockProviderFields.customMockName
			fields.mockDeclarationLocation = mockProviderFields.mockDeclarationLocation
			fields.mockDeclarationAccess = mockProviderFields.mockDeclarationAccess
			fields.mockDeclarationModuleName = mockProviderFields.mockDeclarationModuleName
			fields.mockDeclarationPackageName = mockProviderFields.mockDeclarationPackageName
		}
		return merged
	}

	/// This declaration without its hand-written mock, as production builds the type: with `init` or `instantiate()`.
	public var withoutHandWrittenMock: Instantiable {
		var instantiable = self
		instantiable.updateRarelySetFields { fields in
			fields.mockInitializer = nil
			fields.mockReturnType = nil
			fields.customMockName = nil
			fields.mockDeclarationLocation = nil
			fields.mockDeclarationAccess = nil
			fields.mockDeclarationModuleName = nil
			fields.mockDeclarationPackageName = nil
		}
		return instantiable
	}

	/// The dependencies `handWrittenMock`, this type's hand-written mock, is not passed. A generated mock passes
	/// a dependency to the argument that shares its label, so these are the dependencies whose label no argument
	/// has. A mock method declared with the type takes every dependency, so only one merged in from a `mockOnly`
	/// declaration leaves any out. A `@Forwarded` dependency is never left out: it is an argument of the type's
	/// `Instantiator` whatever the mock method does with it.
	public func dependenciesNotPassed(to handWrittenMock: Initializer) -> [Dependency] {
		let argumentLabels = Set(handWrittenMock.arguments.map(\.innerLabel))
		return dependencies.filter { $0.source != .forwarded && !argumentLabels.contains($0.property.label) }
	}

	/// Each type a member of the declaration spells, which `distinguished(asFulfilling:replacingMentions:fulfillingInstantiationsOf:)`
	/// replaces wherever it sits inside them.
	public var typesMembersSpell: [TypeDescription] {
		var types = [TypeDescription]()
		for dependency in dependencies {
			types.append(dependency.property.typeDescription)
			switch dependency.source {
			case let .instantiated(fulfillingTypeDescription, _):
				if let fulfillingTypeDescription {
					types.append(fulfillingTypeDescription)
				}
			case let .aliased(fulfillingProperty, _, _):
				types.append(fulfillingProperty.typeDescription)
			case .forwarded, .received:
				break
			}
		}
		for memberInitializer in [initializer, mockInitializer].compactMap(\.self) + otherInitializers {
			types.append(contentsOf: memberInitializer.arguments.map(\.typeDescription))
		}
		if let mockReturnType {
			types.append(mockReturnType)
		}
		return types
	}

	/// Returns a copy of this Instantiable that fulfills `instantiableTypes` in place of the types it fulfills, its first
	/// entry remaining the concrete type, with each type `mentions` holds replaced wherever a member of the declaration
	/// spells it, and each dependency that instantiates a type `instantiations` holds fulfilled by the type it holds there,
	/// its property and everything else spelled as written. See `declaredName`.
	public func distinguished(
		asFulfilling instantiableTypes: [TypeDescription],
		replacingMentions mentions: [TypeDescription: TypeDescription],
		fulfillingInstantiationsOf instantiations: [TypeDescription: TypeDescription],
	) -> Instantiable {
		func replacedType(_ typeDescription: TypeDescription) -> TypeDescription {
			typeDescription.replacingTypes(mentions) ?? typeDescription
		}
		func replacedArgument(_ argument: Initializer.Argument) -> Initializer.Argument {
			argument.typeDescription.replacingTypes(mentions).map(argument.withUpdatedTypeDescription) ?? argument
		}
		var instantiable = self
		if instantiableTypes[0] != concreteInstantiable {
			instantiable.declaredName = concreteInstantiable
		}
		instantiable.instantiableTypes = instantiableTypes
		instantiable.dependencies = dependencies.map { dependency in
			let source: Dependency.Source = switch dependency.source {
			case let .instantiated(fulfillingTypeDescription, erasedToConcreteExistential):
				.instantiated(
					fulfillingTypeDescription: instantiations[dependency.asInstantiatedType] ?? fulfillingTypeDescription.map(replacedType),
					erasedToConcreteExistential: erasedToConcreteExistential,
				)
			case let .aliased(fulfillingProperty, erasedToConcreteExistential, onlyIfAvailable):
				.aliased(
					fulfillingProperty: fulfillingProperty.withUpdatedTypeDescription(replacedType(fulfillingProperty.typeDescription)),
					erasedToConcreteExistential: erasedToConcreteExistential,
					onlyIfAvailable: onlyIfAvailable,
				)
			case .forwarded, .received:
				dependency.source
			}
			return Dependency(
				property: dependency.property.withUpdatedTypeDescription(replacedType(dependency.property.typeDescription)),
				source: source,
				declarationLocation: dependency.declarationLocation,
				identifierRange: dependency.identifierRange,
				typeAnnotationRange: dependency.typeAnnotationRange,
				bareAttributeRange: dependency.bareAttributeRange,
			)
		}
		instantiable.initializer = initializer?.mapArguments(replacedArgument)
		instantiable.otherInitializers = otherInitializers.compactMap { $0.mapArguments(replacedArgument) }
		instantiable.mockInitializer = mockInitializer?.mapArguments(replacedArgument)
		instantiable.mockReturnType = mockReturnType.map(replacedType)
		return instantiable
	}

	/// Returns a copy of this Instantiable that declares only the dependencies `isKept` accepts.
	public func keepingDependencies(where isKept: (Dependency) -> Bool) -> Instantiable {
		var instantiable = self
		instantiable.dependencies = dependencies.filter(isKept)
		return instantiable
	}

	/// Whether the user-defined mock() method's return type is compatible with the given property type.
	/// Returns `true` when the mock returns the concrete type, `Self`, or the exact property type.
	/// Returns `false` when there is no mock method.
	public func mockReturnTypeIsCompatible(withPropertyType propertyType: TypeDescription) -> Bool {
		guard let mockReturnType else { return false }
		return mockReturnType == propertyType
			|| mockReturnType == concreteInstantiable
			|| mockReturnType == .simple(name: "Self", generics: [])
	}

	/// The type a call of the user-defined mock method returns, as code outside the declaration spells it: the concrete
	/// type where the method returns it or `Self`, else the additional type it returns. The same whatever property the call
	/// builds, so code that every build of the type shares (the `mock()` it calls through to, a public mock's construction
	/// function) returns it, and each build converts it to its property's type. `nil` when there is no mock method.
	public var mockCallReturnType: TypeDescription? {
		guard let mockReturnType else { return nil }
		return mockReturnTypeIsCompatible(withPropertyType: concreteInstantiable) ? concreteInstantiable : mockReturnType
	}

	/// Whether an `#if` block whose condition names something only the compiler decides – a platform condition such as
	/// `os(iOS)` or `canImport(UIKit)`, or a feature flag such as `$Macros` – encloses the declaration. SafeDI reads
	/// every clause of such a block, so a type declared once in each clause is declared more than once in what SafeDI
	/// reads, though only once in what the compiler compiles. Syntax alone decides it, so it is the same whatever
	/// conditions the file is walked with: a walk that reaches the declaration at all records the same value, which keeps
	/// scan's cache sound without any condition joining `consultedCompilationConditions`.
	public var isInsideCompilerDecidedBlock: Bool {
		get { storage.fields.isInsideCompilerDecidedBlock }
		set { updateFields { $0.isInsideCompilerDecidedBlock = newValue } }
	}

	/// Whether the type’s declaration lists `Sendable` among what it conforms to, which requires each stored property
	/// to be of a `Sendable` type. `@unchecked Sendable` is not counted, since it accepts a property of any type.
	public var conformanceListNamesSendable: Bool {
		get { storage.fields.conformanceListNamesSendable }
		set { updateFields { $0.conformanceListNamesSendable = newValue } }
	}

	/// Whether the type’s declaration lists a type besides `Instantiable` and a counted `Sendable`, such as a protocol
	/// or `@unchecked Sendable`, which may or may not make the type `Sendable`: only that type’s declaration says, and a
	/// module’s generation may not read it. Advice that depends on whether the type is `Sendable` names both forms.
	public var conformanceListNamesOtherTypes: Bool {
		get { storage.fields.conformanceListNamesOtherTypes }
		set { updateFields { $0.conformanceListNamesOtherTypes = newValue } }
	}

	/// The labels of the dependencies the declaration's members declare in the `#if` clauses SafeDITool's evaluation did
	/// not select, in source order, each once, with the first such clause that declares it: what a hand-written mock may
	/// take that this build's declaration does not declare. Empty where every clause is read, as the macro reads them.
	/// Only blocks whose clauses guard SafeDI content are skipped, and their conditions are consulted, so scan's cache
	/// of it is sound.
	public var dependencyLabelsInUnselectedClauses: [DependencyLabelInUnselectedClause] {
		get { storage.fields.dependencyLabelsInUnselectedClauses }
		set { updateFields { $0.dependencyLabelsInUnselectedClauses = newValue } }
	}

	/// The labels of `dependencies` declared inside an `#if` block, in declaration order: those a hand-written mock moved
	/// into another clause may not find. Covered by the same consulted conditions as `dependencyLabelsInUnselectedClauses`.
	public var dependencyLabelsInsideConditionalBlocks: [String] {
		get { storage.fields.dependencyLabelsInsideConditionalBlocks }
		set { updateFields { $0.dependencyLabelsInsideConditionalBlocks = newValue } }
	}

	/// A dependency label a member declares in an `#if` clause SafeDITool's evaluation did not select, with that clause.
	public struct DependencyLabelInUnselectedClause: Codable, Hashable, Sendable {
		public init(label: String, clause: String, clauseLocation: Dependency.DeclarationLocation?, isDeclaredDirectlyInClause: Bool) {
			self.label = label
			self.clause = clause
			self.clauseLocation = clauseLocation
			self.isDeclaredDirectlyInClause = isDeclaredDirectlyInClause
		}

		/// The label, as a dependency's property spells it.
		public let label: String
		/// The clause's directive and condition as written, such as `#if FEATURE`, `#elseif OTHER` or `#else`: the
		/// outermost clause around the declaration that the evaluation did not select.
		public let clause: String
		/// Where the clause's directive begins, or `nil` for a declaration a module info file carries without positions.
		public let clauseLocation: Dependency.DeclarationLocation?
		/// Whether the dependency is declared in the clause itself, rather than in a block nested in it, so that a
		/// hand-written mock moved into the clause finds it wherever the clause is compiled.
		public let isDeclaredDirectlyInClause: Bool
	}

	/// The name the declaring module gives this declaration's concrete type, when the run that read it spells the type
	/// with the module's name, as `ModA.Store`, because another module also declares a type of that name and the module the
	/// run looks from cannot name this one (`distinguishingTypesUnnameable(from:among:plainTypeDeclarations:modulesRead:)`).
	/// `nil` otherwise. Never recorded in a `.safedi` file or scan's cache: it describes one run's view of the declaration.
	public var declaredName: TypeDescription? {
		get { rarelySetFields?.fields.declaredName }
		set { updateRarelySetFields { $0.declaredName = newValue } }
	}

	/// The path to the source file that declared this Instantiable, as the build system supplied it.
	/// `scan` rewrites it to a project-relative form so cached module info matches manifest entries;
	/// `declarationLocation.filePath` keeps the path exactly as parsed for diagnostics.
	public var sourceFilePath: String? {
		get { storage.fields.sourceFilePath }
		set { updateFields { $0.sourceFilePath = newValue } }
	}

	/// Where the decorated declaration begins in source: its first attribute, as for `Dependency.declarationLocation`.
	/// `nil` only when the declaration was parsed without a file context – macro expansion walks a detached
	/// declaration – and such values never reach the dependency tree generator, which only consumes
	/// instantiables that `SafeDITool` parsed from files.
	public var declarationLocation: Dependency.DeclarationLocation? {
		storage.fields.declarationLocation
	}

	// MARK: Rarely set fields

	/// The fields few declarations set – a hand-written mock's, an enclosing extension's access, a `generateMock:`
	/// argument's range, a name a run distinguishes the type by – behind one reference, `nil` while every one is `nil`:
	/// a module's declarations are held at once, and storing these in every `Instantiable` more than doubled its size.
	private var rarelySetFields: RarelySetFieldsBox? {
		storage.fields.rarelySetFields
	}

	/// Sets the rarely set fields to what `update` makes of them, keeping no box while every one is `nil`.
	private mutating func updateRarelySetFields(_ update: (inout RarelySetFields) -> Void) {
		var fields = rarelySetFields?.fields ?? RarelySetFields()
		update(&fields)
		updateFields { $0.rarelySetFields = RarelySetFieldsBox(holding: fields) }
	}

	// MARK: Storage

	/// Every stored field, behind one reference (`Storage`): an `Instantiable` is copied into and out of scopes, records
	/// and signatures many times per type, and copying the fields themselves retained and released each of them.
	private var storage: Storage

	/// Sets the fields to what `update` makes of them, in a new `Storage`, which is never changed once made.
	private mutating func updateFields(_ update: (inout Fields) -> Void) {
		var fields = storage.fields
		update(&fields)
		storage = Storage(fields)
	}

	/// The fields an `Instantiable` stores, which `Storage` holds.
	private struct Fields: Hashable, Sendable {
		var instantiableTypes: [TypeDescription]
		var sourceFilePath: String?
		var declarationLocation: Dependency.DeclarationLocation?
		var rarelySetFields: RarelySetFieldsBox?
		var isRoot: Bool
		var generatesDependencyTree: Bool
		var initializer: Initializer?
		var otherInitializers: [Initializer]
		var dependencies: [Dependency]
		var declarationType: DeclarationType
		var access: AccessDeclaration
		var enclosingTypeAccess: [AccessDeclaration]
		var generatedInitializerAttributes: String
		var mockAttributes: String
		var generateMock: MockGeneration
		var mockOnly: Bool
		var moduleName: String?
		var packageName: String?
		var isInsideCompilerDecidedBlock = false
		var conformanceListNamesSendable: Bool
		var conformanceListNamesOtherTypes: Bool
		var dependencyLabelsInUnselectedClauses = [DependencyLabelInUnselectedClause]()
		var dependencyLabelsInsideConditionalBlocks = [String]()
	}

	/// `Fields` behind a reference, compared and hashed by its fields, so an `Instantiable` equals another exactly when it
	/// did with the fields stored inline.
	private final class Storage: Hashable, Sendable {
		init(_ fields: Fields) {
			self.fields = fields
		}

		let fields: Fields

		static func == (lhs: Storage, rhs: Storage) -> Bool {
			lhs === rhs || lhs.fields == rhs.fields
		}

		func hash(into hasher: inout Hasher) {
			hasher.combine(fields)
		}
	}

	private struct RarelySetFields: Hashable, Sendable {
		var enclosingExtensionAccess: AccessDeclaration?
		var mockGenerationArgumentRange: Dependency.SourceRange?
		var mockInitializer: Initializer?
		var mockReturnType: TypeDescription?
		var customMockName: String?
		var mockDeclarationLocation: Dependency.DeclarationLocation?
		var mockDeclarationAccess: AccessDeclaration?
		var mockDeclarationModuleName: String?
		var mockDeclarationPackageName: String?
		var declaredName: TypeDescription?
	}

	/// `RarelySetFields` behind a reference, compared and hashed by its fields, so an `Instantiable` equals another
	/// exactly when it did with the fields stored inline.
	private final class RarelySetFieldsBox: Hashable, Sendable {
		/// A box of `fields`, or `nil` when every field is `nil`, so that two instantiables that set none are equal.
		init?(holding fields: RarelySetFields) {
			guard fields != RarelySetFields() else { return nil }
			self.fields = fields
		}

		let fields: RarelySetFields

		static func == (lhs: RarelySetFieldsBox, rhs: RarelySetFieldsBox) -> Bool {
			lhs.fields == rhs.fields
		}

		func hash(into hasher: inout Hasher) {
			hasher.combine(fields)
		}
	}

	/// The type of declaration where this Instantiable was defined.
	public enum DeclarationType: Codable, Hashable, Sendable {
		case classType
		case actorType
		case structType
		case extensionType

		public var isExtension: Bool {
			switch self {
			case .extensionType:
				true
			case .actorType, .classType, .structType:
				false
			}
		}
	}
}

extension [Instantiable] {
	/// Orders instantiables by source file path while keeping each file's declarations in
	/// the order they appear in that file. Parsing runs in parallel, so without this the
	/// order in which instantiables reach `resolveSafeDIFulfilledTypes` would depend on
	/// which file finished parsing first. Sorted once per parsed module; serialized
	/// module info keeps the order, so consumers never need to sort again.
	public func sortedByDeclaration() -> [Instantiable] {
		enumerated()
			.sorted { lhs, rhs in
				(lhs.element.sourceFilePath ?? "", lhs.offset) < (rhs.element.sourceFilePath ?? "", rhs.offset)
			}
			.map(\.element)
	}
}

// MARK: - Codable

/// What `dump` prints: every field under its own name, as when each was stored in the struct, the rarely set ones included.
extension Instantiable {
	private enum CodingKeys: String, CodingKey {
		case instantiableTypes
		case isRoot
		case generatesDependencyTree
		case initializer
		case otherInitializers
		case dependencies
		case declarationType
		case access
		case enclosingTypeAccess
		case enclosingExtensionAccess
		case generatedInitializerAttributes
		case mockAttributes
		case generateMock
		case mockGenerationArgumentRange
		case mockOnly
		case mockInitializer
		case mockReturnType
		case customMockName
		case mockDeclarationLocation
		case mockDeclarationAccess
		case mockDeclarationModuleName
		case mockDeclarationPackageName
		case moduleName
		case packageName
		case isInsideCompilerDecidedBlock
		case conformanceListNamesSendable
		case conformanceListNamesOtherTypes
		case dependencyLabelsInUnselectedClauses
		case dependencyLabelsInsideConditionalBlocks
		case declaredName
		case sourceFilePath
		case declarationLocation
	}

	public init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		storage = try Storage(Fields(
			instantiableTypes: container.decode([TypeDescription].self, forKey: .instantiableTypes),
			sourceFilePath: container.decodeIfPresent(String.self, forKey: .sourceFilePath),
			declarationLocation: container.decodeIfPresent(Dependency.DeclarationLocation.self, forKey: .declarationLocation),
			rarelySetFields: RarelySetFieldsBox(holding: RarelySetFields(
				enclosingExtensionAccess: container.decodeIfPresent(AccessDeclaration.self, forKey: .enclosingExtensionAccess),
				mockGenerationArgumentRange: container.decodeIfPresent(Dependency.SourceRange.self, forKey: .mockGenerationArgumentRange),
				mockInitializer: container.decodeIfPresent(Initializer.self, forKey: .mockInitializer),
				mockReturnType: container.decodeIfPresent(TypeDescription.self, forKey: .mockReturnType),
				customMockName: container.decodeIfPresent(String.self, forKey: .customMockName),
				mockDeclarationLocation: container.decodeIfPresent(Dependency.DeclarationLocation.self, forKey: .mockDeclarationLocation),
				mockDeclarationAccess: container.decodeIfPresent(AccessDeclaration.self, forKey: .mockDeclarationAccess),
				mockDeclarationModuleName: container.decodeIfPresent(String.self, forKey: .mockDeclarationModuleName),
				mockDeclarationPackageName: container.decodeIfPresent(String.self, forKey: .mockDeclarationPackageName),
				declaredName: container.decodeIfPresent(TypeDescription.self, forKey: .declaredName),
			)),
			isRoot: container.decode(Bool.self, forKey: .isRoot),
			generatesDependencyTree: container.decode(Bool.self, forKey: .generatesDependencyTree),
			initializer: container.decodeIfPresent(Initializer.self, forKey: .initializer),
			otherInitializers: container.decode([Initializer].self, forKey: .otherInitializers),
			dependencies: container.decode([Dependency].self, forKey: .dependencies),
			declarationType: container.decode(DeclarationType.self, forKey: .declarationType),
			access: container.decode(AccessDeclaration.self, forKey: .access),
			enclosingTypeAccess: container.decode([AccessDeclaration].self, forKey: .enclosingTypeAccess),
			generatedInitializerAttributes: container.decode(String.self, forKey: .generatedInitializerAttributes),
			mockAttributes: container.decode(String.self, forKey: .mockAttributes),
			generateMock: container.decode(MockGeneration.self, forKey: .generateMock),
			mockOnly: container.decode(Bool.self, forKey: .mockOnly),
			moduleName: container.decodeIfPresent(String.self, forKey: .moduleName),
			packageName: container.decodeIfPresent(String.self, forKey: .packageName),
			isInsideCompilerDecidedBlock: container.decode(Bool.self, forKey: .isInsideCompilerDecidedBlock),
			conformanceListNamesSendable: container.decodeIfPresent(Bool.self, forKey: .conformanceListNamesSendable) ?? false,
			conformanceListNamesOtherTypes: container.decodeIfPresent(Bool.self, forKey: .conformanceListNamesOtherTypes) ?? false,
			dependencyLabelsInUnselectedClauses: container.decode([DependencyLabelInUnselectedClause].self, forKey: .dependencyLabelsInUnselectedClauses),
			dependencyLabelsInsideConditionalBlocks: container.decode([String].self, forKey: .dependencyLabelsInsideConditionalBlocks),
		))
	}

	public func encode(to encoder: any Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(instantiableTypes, forKey: .instantiableTypes)
		try container.encode(isRoot, forKey: .isRoot)
		try container.encode(generatesDependencyTree, forKey: .generatesDependencyTree)
		try container.encodeIfPresent(initializer, forKey: .initializer)
		try container.encode(otherInitializers, forKey: .otherInitializers)
		try container.encode(dependencies, forKey: .dependencies)
		try container.encode(declarationType, forKey: .declarationType)
		try container.encode(access, forKey: .access)
		try container.encode(enclosingTypeAccess, forKey: .enclosingTypeAccess)
		try container.encodeIfPresent(enclosingExtensionAccess, forKey: .enclosingExtensionAccess)
		try container.encode(generatedInitializerAttributes, forKey: .generatedInitializerAttributes)
		try container.encode(mockAttributes, forKey: .mockAttributes)
		try container.encode(generateMock, forKey: .generateMock)
		try container.encodeIfPresent(mockGenerationArgumentRange, forKey: .mockGenerationArgumentRange)
		try container.encode(mockOnly, forKey: .mockOnly)
		try container.encodeIfPresent(mockInitializer, forKey: .mockInitializer)
		try container.encodeIfPresent(mockReturnType, forKey: .mockReturnType)
		try container.encodeIfPresent(customMockName, forKey: .customMockName)
		try container.encodeIfPresent(mockDeclarationLocation, forKey: .mockDeclarationLocation)
		try container.encodeIfPresent(mockDeclarationAccess, forKey: .mockDeclarationAccess)
		try container.encodeIfPresent(mockDeclarationModuleName, forKey: .mockDeclarationModuleName)
		try container.encodeIfPresent(mockDeclarationPackageName, forKey: .mockDeclarationPackageName)
		try container.encodeIfPresent(moduleName, forKey: .moduleName)
		try container.encodeIfPresent(packageName, forKey: .packageName)
		try container.encode(isInsideCompilerDecidedBlock, forKey: .isInsideCompilerDecidedBlock)
		// Written only when set, as the conformance lists of most declarations name neither.
		if conformanceListNamesSendable {
			try container.encode(conformanceListNamesSendable, forKey: .conformanceListNamesSendable)
		}
		if conformanceListNamesOtherTypes {
			try container.encode(conformanceListNamesOtherTypes, forKey: .conformanceListNamesOtherTypes)
		}
		try container.encode(dependencyLabelsInUnselectedClauses, forKey: .dependencyLabelsInUnselectedClauses)
		try container.encode(dependencyLabelsInsideConditionalBlocks, forKey: .dependencyLabelsInsideConditionalBlocks)
		try container.encodeIfPresent(declaredName, forKey: .declaredName)
		try container.encodeIfPresent(sourceFilePath, forKey: .sourceFilePath)
		try container.encodeIfPresent(declarationLocation, forKey: .declarationLocation)
	}
}

// MARK: - CustomReflectable

/// Reflects each stored field under its own name, as when each was stored in the struct rather than in `Storage`.
extension Instantiable: CustomReflectable {
	public var customMirror: Mirror {
		Mirror(self, children: Mirror(reflecting: storage.fields).children, displayStyle: .struct)
	}
}
