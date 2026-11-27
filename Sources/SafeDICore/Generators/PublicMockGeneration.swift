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

// What a module needs to generate the public mocks of its `@Instantiable(generateMock: .public)` types, beyond what
// an internal mock needs: the access of each parameter and member, proven from the declarations (`TypeAccessProof`),
// the module-level configuration structs the public mocks of a module share, and the construction functions that
// resolve a type's default-valued parameters where the type's own declaration resolves them.

/// What a module's public mocks read from the module as a whole.
struct PublicMockContext: Sendable {
	/// The proof of every type's access over the module's declaration map, which every public mock of the module reads.
	let proof: TypeAccessProof
	/// The comment the module's public mocks' file carries, naming the types their `public` declarations name that SafeDI
	/// reads no declaration of, or `nil` when the run writes none (`SeamResolution.carriesUnreadTypeComment`).
	let unreadTypeComment: UnreadTypeComment?
	/// The module that declares each concrete type, where it is known.
	let moduleNameByType: [TypeDescription: String]
	/// The module the mocks are generated in, when it is known.
	let moduleName: String?
	/// The name of each concrete type's module-level configuration struct (`configurationTypeNames(of:moduleName:)`).
	let configurationTypeNameByType: [TypeDescription: String]
	/// For each `generateMock: .public` type declared inside an extension, the declarations of the extended type that
	/// bound it (`DependencyTreeGenerator.extendedTypeAccessNeeds(of:in:)`), which a public mock needs to be `public`.
	let extendedTypeAccessNeedsByType: [TypeDescription: [AccessNeed]]

	/// The access with which a declaration can name every type in `types`: the narrowest proof among them, a type with
	/// no entry resolved to its plain declaration in the module the mocks are generated in and otherwise read from
	/// `admittedModules`, and the cause of the narrowest.
	func access(ofTypes types: [TypeDescription], admittedModules: Set<String?>) -> TypeAccessProof.ParameterAccess {
		var narrowest = TypeAccessProof.ParameterAccess(level: .public, cause: nil)
		for type in types {
			// The mocks are generated in the module whose files the proof's `isOwnFile` names as its own: a context computed
			// for another module's public mock names none.
			let access = proof.access(ofParameterTyped: type, mentionedFrom: .generatedCode(ofModuleNamed: moduleName, isRunsOwnModule: true), admittedModules: admittedModules)
			if access.level < narrowest.level {
				narrowest = access
			}
		}
		return narrowest
	}

	/// The names of the module-level configuration structs of `concreteTypes`: `__safeDI_<Module>_<Type>_MockConfiguration`,
	/// with each type spelled by `asIdentifier`, or `__safeDI_<Type>_MockConfiguration` when the module is unknown. Two
	/// types whose names collide are named apart by trailing underscores, in sorted type order.
	static func configurationTypeNames(of concreteTypes: some Sequence<TypeDescription>, moduleName: String?) -> [TypeDescription: String] {
		var names = [TypeDescription: String]()
		var takenStems = Set<String>()
		for type in Set(concreteTypes).sorted() {
			var stem = "\(ReservedName.builderFunctionNamePrefix)\(moduleName.map { "\($0)_" } ?? "")\(type.asIdentifier)"
			while takenStems.contains(stem) {
				stem += "_"
			}
			takenStems.insert(stem)
			names[type] = "\(stem)_MockConfiguration"
		}
		return names
	}

	/// The name of the module-level function that forwards to `type`'s provider of the default of `label`, which a
	/// public declaration's default argument can name without naming `type`.
	func forwarderName(of type: TypeDescription, label: String) -> String {
		let configurationTypeName = configurationTypeNameByType[type] ?? "\(ReservedName.builderFunctionNamePrefix)\(type.asIdentifier)_MockConfiguration"
		let stem = configurationTypeName.dropLast("_MockConfiguration".count)
		return "\(stem)_mockDefault_\(label)".spelledAsJoinedIdentifier
	}

	/// The name of the static method in a type's extension that evaluates the default of `label` for its configuration.
	static func providerName(label: String) -> String {
		"\(ReservedName.builderFunctionNamePrefix)mockDefault_\(label)".spelledAsJoinedIdentifier
	}

	/// The name of the static method in a public mock's type's extension that evaluates the default of `label` of the
	/// type's own construction, apart from `providerName(label:)`, which the type's configuration declares when the type
	/// is also built in a public mock's tree.
	static func rootProviderName(label: String) -> String {
		"\(ReservedName.builderFunctionNamePrefix)publicMockDefault_\(label)".spelledAsJoinedIdentifier
	}
}

/// A stored member of a generated public struct (`SafeDIOverrides`, or a module-level configuration), with the
/// access its types allow.
struct PublicStructMember {
	/// The member's name, which is also its initializer parameter's label.
	let name: String
	/// The member's stored type.
	let typeSource: String
	/// The type of the initializer parameter that sets it, which an autoclosure parameter spells otherwise.
	let parameterTypeSource: String
	/// The member's access: the narrowest its types are proven at.
	let access: AccessLevel
	/// The default of the initializer parameter that sets it.
	let defaultExpression: String
	/// What an initializer that does not take the member assigns it.
	let omittedValue: String
	/// Whether the initializer parameter has no argument label.
	let isUnlabeled: Bool
	/// The member's documentation comment, when it has one.
	let documentation: String?

	/// The type the struct's storage (`ConfigurationStorage`) takes the member as: its stored type, or, where the
	/// initializer takes the member as an `@autoclosure` of its stored function type, that type `@escaping`.
	var storageParameterTypeSource: String {
		parameterTypeSource == typeSource ? typeSource : "@escaping \(typeSource)"
	}
}

extension ScopeGenerator {
	/// The access levels at which a public struct with `members` has an initializer, widest first: `public`, which may
	/// take no member, and each narrower level a member has.
	static func publicInitializerLevels(of members: [PublicStructMember]) -> [AccessLevel] {
		[.public] + Set(members.map(\.access)).filter { $0 < .public }.sorted(by: >)
	}

	/// The initializers and members of a public struct, indented by `indent`: one initializer per level of
	/// `publicInitializerLevels(of:)`, each taking every member at or above its level, in member order, and setting
	/// each member it omits to its `omittedValue`. The members are in the struct's storage (`ConfigurationStorage`),
	/// which is not `Sendable`, since a public struct is not `Sendable` unless it declares it, which none of these does.
	static func publicStructBody(members: [PublicStructMember], indent: String) -> [String] {
		// A mock's `SafeDIOverrides` whose only member was a closure its call cannot be handed keeps its initializer.
		guard !members.isEmpty else { return ["\(indent)public init() {}"] }
		let memberIndent = "\(indent)\(standardIndent)"
		let storage = ConfigurationStorage(fields: members.map { member in
			ConfigurationStorage.Field(
				name: member.name,
				typeSource: member.typeSource,
				parameterTypeSource: member.storageParameterTypeSource,
				accessPrefix: member.access == .internal ? "" : "\(member.access.spelledOnGeneratedDeclaration) ",
				documentation: member.documentation,
				isProvenSendable: false,
			)
		})
		var lines = [String]()
		for level in publicInitializerLevels(of: members) {
			let takenMembers = members.filter { $0.access >= level }
			let levelPrefix = level == .internal ? "" : "\(level.spelledOnGeneratedDeclaration) "
			if takenMembers.isEmpty {
				lines.append("\(indent)\(levelPrefix)init() {")
			} else {
				lines.append("\(indent)\(levelPrefix)init(")
				lines.append(takenMembers.map { member in
					"\(memberIndent)\(member.isUnlabeled ? "_ " : "")\(member.name): \(member.parameterTypeSource) = \(member.defaultExpression)"
				}.joined(separator: ",\n"))
				lines.append("\(indent)) {")
			}
			lines.append(contentsOf: storage.initialization(
				to: members.map { $0.access >= level ? $0.name : $0.omittedValue },
				indent: memberIndent,
			))
			lines.append("\(indent)}")
			lines.append("")
		}
		// A public struct always has a member: a module-level configuration has its builder, and a public mock declares its
		// `SafeDIOverrides` only for a tree with a node.
		lines.append(contentsOf: storage.readers(indent: indent))
		lines.append("")
		lines.append(contentsOf: storage.declarations(indent: indent))
		return lines
	}

	/// A member holding a default-valued parameter's value of `valueType`. A struct a `@Sendable` builder function reads
	/// holds a `@Sendable` closure that returns the value, which its initializer takes as an autoclosure, so that the
	/// function captures no value whose type may not be `Sendable`.
	static func publicDefaultMember(
		name: String,
		valueType: TypeDescription,
		access: AccessLevel,
		defaultExpression: String,
		omittedValue: String,
		requiresSendable: Bool,
		documentation: String,
	) -> PublicStructMember {
		if requiresSendable {
			PublicStructMember(
				name: name,
				typeSource: "@Sendable () -> \(valueType.asSource)",
				parameterTypeSource: "@autoclosure @escaping @Sendable () -> \(valueType.asSource)",
				access: access,
				defaultExpression: autoclosureDefault(defaultExpression),
				omittedValue: "{ \(omittedValue) }",
				isUnlabeled: false,
				documentation: documentation,
			)
		} else {
			PublicStructMember(
				name: name,
				typeSource: valueType.asSource,
				parameterTypeSource: valueType.asSource,
				access: access,
				defaultExpression: defaultExpression,
				omittedValue: omittedValue,
				isUnlabeled: false,
				documentation: documentation,
			)
		}
	}
}

extension ScopeGenerator {
	/// The nodes at a mock root's level that the mock builds for dependencies the mocked type's tree receives, which a
	/// public mock takes as parameters that default to `nil`: every node but those of the mocked type's own
	/// `@Instantiated` dependencies, including one the mock builds as the `LazilyInstantiated` its tree receives.
	static func publicMockPromotedNodes(of instantiable: Instantiable, in nodes: [MockTreeNames.PropertyNode]) -> [MockTreeNames.PropertyNode] {
		let ownProperties = Set(instantiable.dependencies.lazy.filter { dependency in
			switch dependency.source {
			case .instantiated:
				true
			case .received, .aliased, .forwarded:
				false
			}
		}.map(\.property))
		return nodes.filter { node in
			!ownProperties.contains(node.property)
				&& !(node.property.propertyType.isLazilyInstantiated && node.property.typeDescription.lazilyInstantiatedInstanceType.map {
					ownProperties.contains(Property(label: node.property.label, typeDescription: $0))
				} ?? false)
		}
	}

	/// The parameter a public mock takes for a node it builds for a received dependency: the node's value, optional. A
	/// lazily instantiated node is taken as the wrapper its tree receives, as the type's initializer takes it, so a caller
	/// hands its own wrapper and nothing is built until the tree reads it.
	// D1 lane hook (lane C): read from the node's property, whose label and type the node's are, which the mock lowering
	// names too.
	static func publicMockParameterProperty(of property: Property) -> Property {
		Property(label: property.label, typeDescription: .optional(property.typeDescription.unwrapped))
	}
}

/// How the body of a public mock differs from an internal mock's, passed down its tree.
struct PublicMockEmission: Sendable {
	/// For each node at the mock root's level that the mock builds for a received dependency, the parameter that
	/// holds a value its caller passed instead, by the node's property. Empty beneath the mock root's level.
	let promotedParameterNames: [Property: String]
	/// What the module's public mocks share.
	let context: PublicMockContext
	/// The concrete types whose configurations a `@Sendable` builder function reads, which hold each default as a
	/// `@Sendable` closure.
	let sendableConfigurationTypeNames: Set<String>
}

extension ScopeGenerator {
	/// An expression that evaluates to the value the caller passed as `parameterName`, when it passed one, and
	/// otherwise to `construction`, which may be an `if` expression itself.
	static func passing(_ parameterName: String, orBuilding construction: String) -> String {
		if construction.hasPrefix("if ") {
			"if let \(parameterName) { \(parameterName) } else \(construction)"
		} else {
			"if let \(parameterName) { \(parameterName) } else { \(construction) }"
		}
	}
}

/// A parameter of a public mock's `mock()`, which every tier at or narrower than its access takes.
struct PublicMockParameter: Sendable {
	/// How a parameter defaults, which a call depends on and the guard hashes.
	enum DefaultKind: String, Sendable {
		/// The caller must pass it.
		case none
		/// `nil`, meaning "build it as the mock does" or "the declaration's default".
		case nilValue = "nil"
		/// An expression the declaration wrote, kept as written (a magic literal).
		case expression
		/// A provider's value: the declaration's default, evaluated where the declaration resolves it.
		case provider
		/// A builder that returns `nil`, for a builder of places instantiated only if available, whose type is optional: the
		/// value production gives a place nothing fulfills.
		case nilBuilder
	}

	/// The parameter's name, which is also its argument label: the widest tier's that takes it.
	var name: String
	/// For a builder, the name each narrower tier takes it under, where it differs from `name`
	/// (`SeamSignature.Builder.narrowerTierLabels`).
	var narrowerTierNames = [AccessLevel: String]()
	/// The parameter's type as the signature spells it.
	let type: TypeDescription
	/// The parameter's type as the signature spells it, `@escaping` and `@autoclosure` included.
	let typeSource: String
	/// For a builder, the type the signature spells without `any`, which the function that spells `typeSource` makes, so that
	/// nothing can be emitted and not hashed. `nil` for a parameter whose `type` spells it.
	var typeWithoutAny: TypeDescription?
	/// The default, as source after ` = `, or `nil` for none.
	let defaultSource: String?
	let defaultKind: DefaultKind
	/// The narrowest access its types are proven at, which is the narrowest tier that takes it.
	let access: AccessLevel
	/// How the narrowest of its types is proven, when that is narrower than `public`.
	var accessCause: TypeAccessProof.Cause?
	/// For a parameter on no tier (`PublicMockPlan.noTierParameters`), the call in the mock's tree of another module's
	/// public mock whose tier omits it.
	var nestedOmission: NestedOmission?

	typealias NestedOmission = StoredPublicMockPlan.NestedOmission

	/// What the parameter stands for, which decides what a mock tree that calls the public mock passes for it.
	var role: Role
	/// For a received dependency taken as `T? = nil`, whether the mock builds it when passed `nil`, rather than passing
	/// `nil` on to the receivers in its tree, which receive it only if available.
	var isBuiltWhenNil = false
	/// For a dependency the mock builds when passed `nil` as a `LazilyInstantiated` or `SendableLazilyInstantiated`,
	/// taken by value, the wrapper it builds, which a calling mock that can build it builds in its place, as the inline
	/// mock would, and passes the instance of.
	var builtWrapper: Property?
	/// For a builder, the builder, whose places a module calling the mock that sees a type that fulfills them fills.
	var builder: SeamSignature.Builder?
	/// For a builder, the first place it reaches, whose property's type the builder returns.
	var hole: SeamSignature.Hole?
	/// For an optional builder (`Role.optionalBuilder`), the name `__safeDI_mock` takes it under, apart from every name the
	/// mock's tree and its fills declare, and the builders of the calls whose places it builds.
	var internalName: String?
	var filledCallBuilders = [ScopeGenerator.MockRootParameters.SeamMockBuilder.FilledCallBuilder]()
	/// For an optional builder, the hole type and family whose places it builds, which a place of a public mock the tree
	/// builds inline reads it for (`ScopeGenerator.holeBuildersByInlinePlace(in:buildersByFamily:foreignPublicMocks:)`).
	var optionalBuilderFamily: ScopeGenerator.MockRootParameters.SeamMockBuilder.Family?
	/// The lines that document the parameter above each tier that takes it
	/// (`MockRootParameters.UncoveredParameter.sharedValueDocumentation`).
	var sharedValueDocumentation = [String]()

	/// For an optional builder joined to a required one, the required builder's enum (`Role.optionalBuilder`).
	var joinedBuilder: SeamSignature.ScopeEnum.Key? {
		if case let .optionalBuilder(joinedBuilder) = role {
			joinedBuilder
		} else {
			nil
		}
	}

	/// The name the tier at `tier` takes the parameter under.
	func name(inTier tier: AccessLevel) -> String {
		narrowerTierNames[tier] ?? name
	}

	/// The parameter as the tier at `tier` takes it, under that tier's name.
	func atTier(_ tier: AccessLevel) -> PublicMockParameter {
		var parameter = self
		parameter.name = name(inTier: tier)
		parameter.narrowerTierNames = [:]
		parameter.builder = builder?.atTier(tier)
		parameter.hole = hole?.atTier(tier)
		if case let .received(property, isRequired) = role, builder != nil {
			parameter.role = .received(Property(label: parameter.name, typeDescription: property.typeDescription), isRequired: isRequired)
		}
		return parameter
	}

	typealias Role = StoredPublicMockPlan.Role
}

/// What a public mock (`generateMock: .public`) generates beyond an internal mock's body.
struct PublicMockPlan: Sendable {
	/// The parameters of the narrowest tier, which takes every parameter, in signature order.
	let parameters: [PublicMockParameter]
	/// The parameters on no tier: what only the calls of other modules' public mocks in the tree receive, which every
	/// such call's tier omits. No tier takes them and the guard hashes none, but a caller's leaf declares them as it
	/// declares an omitted parameter, so that a caller holding a value for one is told the mock would drop it.
	var noTierParameters = [PublicMockParameter]()
	/// The tiers, widest first: `public`, then each narrower access a parameter has.
	let tiers: [AccessLevel]
	/// The empty enum every call names, whose name hashes the signature.
	let guardTypeName: String
	/// The static methods in the mocked type's extension that evaluate its own optional-typed defaults.
	let providerDeclarations: [String]
	/// The lines that resolve each parameter taken as `T? = nil` in place of a non-optional default, before the tree.
	let defaultResolutions: [String]
	/// The parameter each node at the mock root's level built for a received dependency is passed by.
	let promotedParameterNames: [Property: String]
	/// Every place the builders `mock()` takes reach, in the order they reach them: the mock's own, and those the calls of
	/// other modules' public mocks in its tree pass up.
	var holes = [SeamSignature.Hole]()
	/// The builders `mock()` takes, as a seam takes them (`DependencyTreeGenerator.shapedBuilders`).
	var builders = [SeamSignature.Builder]()
	/// Every enum the builders reach: the mock's own, then those their cases hold.
	var scopeEnums = [SeamSignature.ScopeEnum]()
	/// The mock's place graph, while the tests observe it, and each of `holes`' case in it: -1 for a place a call passes up.
	var places = SeamSignature.Places(levels: [], cases: [])
	var caseIndexByHole = [Int]()

	/// The parameters the tier at `tier` takes, under that tier's names.
	func parameters(ofTier tier: AccessLevel) -> [PublicMockParameter] {
		parameters.filter { $0.access >= tier }.map { $0.atTier(tier) }
	}
}

extension ScopeGenerator {
	/// The plan of the public mock of `instantiable`, a mock root with `parameters`, named by `parameterNames`.
	static func publicMockPlan(
		of instantiable: Instantiable,
		parameters: MockRootParameters,
		parameterNames: MockRootParameterNames,
		context: PublicMockContext,
	) -> PublicMockPlan {
		let treePropertyNodes = parameters.treeNames.propertyNodes
		let rootPropertyNodes = treePropertyNodes.filter { $0.parentIndex == nil }
		var plan = publicMockPlan(
			of: instantiable,
			forwardedDependencies: parameters.forwardedDependencies,
			forwardedDefaults: parameters.forwardedParameterDefaults,
			rootDefaultParameters: parameters.rootDefaultParameters,
			flatReceivedParameters: zip(parameters.flatReceivedProperties, parameterNames.flatReceivedNames).map { (property: $0, name: $1) },
			flatReceivedParameterMockDefaults: parameters.flatReceivedParameterMockDefaults,
			flatUncoveredParameters: parameters.flatUncoveredParameters,
			// D1 lane hook (lane C): a promoted node is passed as its property, which the mock lowering can name too.
			promotedNodes: publicMockPromotedNodes(of: instantiable, in: rootPropertyNodes).map { node in
				(property: node.property, name: disambiguatedLabel(for: node.property, labelMap: parameters.rootLabelMap))
			},
			onlyIfAvailableOverrides: parameterNames.onlyIfAvailableOverrides,
			wrapperParameterByInstance: parameters.publicMockWrapperParameterByInstance,
			treePropertyNodes: treePropertyNodes,
			builders: parameters.mockBuilders,
			// A public mock takes each property received only if available as a parameter, so only the tree's nodes make
			// a `SafeDIOverrides`.
			hasOverrides: !rootPropertyNodes.isEmpty,
			typesDeclaredEscaping: parameters.typesDeclaredEscaping,
			receiverModulesByLabel: receiverModules(in: parameters.treeNames.propertyNodes, context: context),
			context: context,
		)
		plan.noTierParameters = noTierParameters(in: treePropertyNodes, leftOut: parameters.receivedOnlyByPublicMockCallsLeftOut)
		return plan
	}

	/// The parameters on no tier of a public mock whose tree's nodes are `nodes` (`MockTreeNames.propertyNodes`; see
	/// `PublicMockPlan.noTierParameters`): each property of `leftOut` that a call of another module's public mock in the tree
	/// omits, once per label, in tree order.
	private static func noTierParameters(in nodes: [MockTreeNames.PropertyNode], leftOut: Set<Property>) -> [PublicMockParameter] {
		guard !leftOut.isEmpty else { return [] }
		var noTierParameters = [PublicMockParameter]()
		var labels = Set<String>()
		for node in nodes {
			// A node's call, then the calls the trees of the fills it passes make, depth first.
			var publicMockCalls = [PublicMockCall]()
			if let publicMockCall = node.generator.publicMockCall {
				publicMockCalls.append(publicMockCall)
			}
			if node.generator.fillsABuilder {
				publicMockCalls += ScopeGenerator.publicMockCallsInFills(of: node.generator)
			}
			for publicMockCall in publicMockCalls {
				for parameter in publicMockCall.omittedParameters {
					guard case let .received(property, _) = parameter.role,
					      leftOut.contains(property),
					      labels.insert(property.label).inserted
					else { continue }
					var noTierParameter = PublicMockParameter(
						name: property.label,
						type: property.typeDescription,
						typeSource: property.typeDescription.asSource,
						defaultSource: "nil",
						defaultKind: .nilValue,
						access: parameter.access,
						accessCause: parameter.accessCause,
						role: .received(property, isRequired: false),
					)
					noTierParameter.nestedOmission = parameter.nestedOmission ?? PublicMockParameter.NestedOmission(
						type: publicMockCall.type,
						tier: publicMockCall.tier,
						parameterAccess: parameter.access,
						declaringModule: publicMockCall.declaringModule,
						callerModule: publicMockCall.callerModule,
						requirement: publicMockCall.requirement,
						receivers: (publicMockCall.receiversByLabel[property.label] ?? []).filter { receiver in
							receiver.dependency.property.label == property.label && receiver.dependency.source.isReceived
						},
					)
					noTierParameters.append(noTierParameter)
				}
			}
		}
		return noTierParameters
	}

	/// The plan of a public mock of `instantiable` whose internal mock would take the given parameters.
	/// - Parameters:
	///   - forwardedDefaults: The default an internal mock gives each forwarded parameter, by label.
	///   - flatReceivedParameterMockDefaults: The hand-written mock an internal mock defaults each of
	///     `flatReceivedParameters` to, which a public mock takes as `T? = nil` too.
	///   - wrapperParameterByInstance: The wrapper the mock takes in place of each of `flatReceivedParameters` or of the
	///     properties `onlyIfAvailableOverrides` receive (`MockRootParameters.publicMockWrapperParameterByInstance`).
	///   - hasOverrides: Whether the mock has a `SafeDIOverrides`. The mocked type's own optional-typed defaults are
	///     parameters of `mock()` that default to their providers either way, as an internal mock's are, so that neither the
	///     type's isolation nor whether it builds anything moves one.
	static func publicMockPlan(
		of instantiable: Instantiable,
		forwardedDependencies: [Dependency],
		forwardedDefaults: [String: ForwardedParameterDefault],
		rootDefaultParameters: [MockRootParameters.RootDefaultParameter],
		flatReceivedParameters: [(property: Property, name: String)],
		flatReceivedParameterMockDefaults: [Property: FlatParameterMockDefault],
		flatUncoveredParameters: [MockRootParameters.UncoveredParameter],
		promotedNodes: [(property: Property, name: String)],
		onlyIfAvailableOverrides: [OnlyIfAvailableOverride],
		wrapperParameterByInstance: [Property: Property],
		treePropertyNodes: [MockTreeNames.PropertyNode],
		builders shapedBuilders: DependencyTreeGenerator.ShapedBuilders?,
		hasOverrides: Bool,
		typesDeclaredEscaping: Set<TypeDescription>,
		receiverModulesByLabel: [String: Set<String?>],
		// D1 lane hook (lane C): and the families its calls fill, with the names the narrowest tier's body declares.
		filledFamilies givenFilledFamilies: (families: [ScopeGenerator.FilledFamily], namesInBody: Set<String>)? = nil,
		context: PublicMockContext,
	) -> PublicMockPlan {
		let typeName = instantiable.concreteInstantiable.asSource
		// The cause of each access computed, by type and receive label, which a parameter of that access records.
		var accessCauses = [String: TypeAccessProof.Cause]()
		func access(of type: TypeDescription, receivedAs label: String?) -> AccessLevel {
			let access = publicMockParameterAccess(ofType: type, receivedAs: label, mockedType: instantiable, receiverModulesByLabel: receiverModulesByLabel, context: context)
			accessCauses["\(label ?? ""):\(type.asSource)"] = access.cause
			return access.level
		}
		func cause(of type: TypeDescription, receivedAs label: String?) -> TypeAccessProof.Cause? {
			accessCauses["\(label ?? ""):\(type.asSource)"]
		}
		var leadingParameters = [PublicMockParameter]()
		var defaultResolutions = [String]()
		var providerDeclarations = [String]()
		let bodyIndent = "\(standardIndent)\(standardIndent)"
		/// The parameter of a default-valued `type` taken as `T? = nil`, resolved in the body to the default, whose access
		/// is `type`'s.
		func optionalParameter(named name: String, type: TypeDescription, resolvedTo expression: String, role: PublicMockParameter.Role) -> PublicMockParameter {
			defaultResolutions.append("\(bodyIndent)let \(name) = \(name) ?? (\(expression))")
			let optionalType = TypeDescription.optional(type)
			return PublicMockParameter(name: name, type: optionalType, typeSource: optionalType.asSource, defaultSource: "nil", defaultKind: .nilValue, access: access(of: type, receivedAs: nil), role: role)
		}
		// A provider is evaluated as a default of `mock()`, and is declared in the extension `mock()` is declared in, spelled
		// with exactly `mock()`'s attributes, so it has `mock()`'s isolation: the type's, whether spelled or taken from a
		// conformance or a superclass, unless `mockAttributes` states another. SafeDI reads no isolation itself.
		let mockAttributesPrefix = instantiable.mockAttributes.isEmpty ? "" : "\(instantiable.mockAttributes) "
		/// The provider of an optional-typed default, and how a declaration names it.
		func provider(named label: String, type: TypeDescription, access: AccessLevel, expression: String) -> String {
			let isPublic = access == .public
			providerDeclarations.append("\(standardIndent)\(isPublic ? "@usableFromInline " : "")\(mockAttributesPrefix)static func \(PublicMockContext.rootProviderName(label: label))() -> \(type.asSource) { \(expression) }")
			return "\(typeName).\(PublicMockContext.rootProviderName(label: label))()"
		}

		for dependency in forwardedDependencies {
			let property = dependency.property
			if let forwardedDefault = forwardedDefaults[property.label] {
				if property.typeDescription.isOptional, case let .constructionDefault(expression) = forwardedDefault {
					let providerCall = provider(named: property.label, type: property.typeDescription, access: access(of: property.typeDescription, receivedAs: nil), expression: expression)
					leadingParameters.append(PublicMockParameter(name: property.label, type: property.typeDescription, typeSource: property.typeDescription.asSource, defaultSource: providerCall, defaultKind: .provider, access: access(of: property.typeDescription, receivedAs: nil), role: .forwarded(property)))
				} else {
					leadingParameters.append(optionalParameter(named: property.label, type: property.typeDescription.strippingEscaping, resolvedTo: forwardedDefault.expression, role: .forwarded(property)))
				}
			} else {
				leadingParameters.append(PublicMockParameter(name: property.label, type: property.typeDescription, typeSource: property.typeDescription.asFunctionParameter(amongTypesDeclaredEscaping: typesDeclaredEscaping).asSource, defaultSource: nil, defaultKind: .none, access: access(of: property.typeDescription, receivedAs: nil), role: .forwarded(property)))
			}
		}
		for rootDefault in rootDefaultParameters {
			let type = rootDefault.typeDescription
			let typeAccess = access(of: type, receivedAs: nil)
			if rootDefault.defaultExpression.hasPrefix("#") {
				// A magic literal is evaluated where the parameter is declared, so the parameter keeps it.
				leadingParameters.append(PublicMockParameter(name: rootDefault.label, type: type, typeSource: rootDefault.typeSource, defaultSource: rootDefault.defaultExpression, defaultKind: .expression, access: typeAccess, role: .constructionDefault))
			} else if let valueType = type.autoclosureValueType {
				// An `@autoclosure` parameter is taken as a closure that returns the value, which defaults to a closure
				// that evaluates the default in this module, and the construction calls it (`generateReturnArgumentList`).
				leadingParameters.append(optionalParameter(
					named: rootDefault.label,
					type: MockLowering.closureTaken(forAutoclosureReturning: valueType, isSendable: MockLowering.isSendableAutoclosure(type)),
					resolvedTo: "{ \(rootDefault.defaultExpression) }",
					role: .constructionDefault,
				))
			} else if type.isOptional {
				// A parameter of `mock()` with the declaration's default, as an internal mock takes it, never a field of
				// `SafeDIOverrides`, so that the type's isolation and whether it builds anything never move it.
				let isNilLiteral = rootDefault.defaultExpression == "nil"
				let providerCall = isNilLiteral ? "nil" : provider(named: rootDefault.label, type: type, access: typeAccess, expression: rootDefault.defaultExpression)
				leadingParameters.append(PublicMockParameter(name: rootDefault.label, type: type, typeSource: type.asSource, defaultSource: providerCall, defaultKind: isNilLiteral ? .nilValue : .provider, access: typeAccess, role: .constructionDefault))
			} else {
				leadingParameters.append(optionalParameter(named: rootDefault.label, type: type, resolvedTo: rootDefault.defaultExpression, role: .constructionDefault))
			}
		}
		for (instanceProperty, name) in flatReceivedParameters {
			// A value the tree receives lazily is taken as the wrapper it receives (`ScopeGenerator.publicMockWrapperParameters`).
			let wrapper = wrapperParameterByInstance[instanceProperty]
			let property = wrapper ?? instanceProperty
			if let mockDefault = flatReceivedParameterMockDefaults[instanceProperty] {
				// The mock builds the dependency with the hand-written mock when passed `nil`, as an internal mock defaults it,
				// and a wrapper's only when the tree reads it.
				let defaultExpression = wrapper.map { "\($0.typeDescription.unwrapped.spelledForConstruction) { \(mockDefault.expression) }" } ?? mockDefault.expression
				defaultResolutions.append("\(bodyIndent)let \(name) = \(name) ?? (\(defaultExpression))")
				let optionalProperty = Property(label: property.label, typeDescription: .optional(property.typeDescription))
				leadingParameters.append(PublicMockParameter(name: name, type: optionalProperty.typeDescription, typeSource: optionalProperty.typeDescription.asSource, defaultSource: "nil", defaultKind: .nilValue, access: access(of: optionalProperty.typeDescription, receivedAs: property.label), accessCause: cause(of: optionalProperty.typeDescription, receivedAs: property.label), role: .received(optionalProperty, isRequired: false), isBuiltWhenNil: true, builtWrapper: wrapper))
			} else {
				leadingParameters.append(PublicMockParameter(name: name, type: property.typeDescription, typeSource: property.typeDescription.asFunctionParameter(amongTypesDeclaredEscaping: typesDeclaredEscaping).asSource, defaultSource: nil, defaultKind: .none, access: access(of: property.typeDescription, receivedAs: property.label), role: .received(property, isRequired: true)))
			}
		}
		for uncovered in flatUncoveredParameters {
			let typeSource = uncovered.isSendableAutoclosure ? "@autoclosure @escaping @Sendable () -> \(uncovered.typeSource)" : uncovered.typeSource
			leadingParameters.append(PublicMockParameter(name: uncovered.label, type: uncovered.property.typeDescription, typeSource: typeSource, defaultSource: nil, defaultKind: .none, access: access(of: uncovered.property.typeDescription, receivedAs: uncovered.property.label), role: .received(uncovered.property, isRequired: true), sharedValueDocumentation: uncovered.sharedValueDocumentation))
		}
		// Each builder, required, in builder order, as a seam takes it: what fills a place takes the values in scope at its
		// site, and a call of another module's public mock hands up the places it does not fill. The tree calls each builder
		// by the name the sites and calls call it by, bound before anything else.
		let holes = shapedBuilders?.holes ?? []
		let builders = shapedBuilders?.builders ?? []
		for builder in builders {
			// The type of the builder a person writes, without `@escaping`, which a caller's leaf receives it as: an internal caller
			// that passes the builder's places up takes it so, and hands the call its struct (`.init(__safeDI_noScope:)`).
			let functionType = builder.readableParameterType.strippingEscaping
			// A builder of places instantiated only if available defaults to one that returns `nil`, as production binds a
			// place nothing fulfills, so only a test of the code that runs when an application declares the type passes one.
			let buildsOptional = builder.enumKey.holeType.builtType.isOptional
			leadingParameters.append(PublicMockParameter(
				name: builder.label,
				type: functionType,
				typeSource: builder.parameterType.asSource,
				typeWithoutAny: builder.parameterTypeWithoutAny,
				defaultSource: buildsOptional ? ReservedName.nilBuilderSource : nil,
				defaultKind: buildsOptional ? .nilBuilder : .none,
				access: builder.tierAccess,
				accessCause: builder.accessCause,
				role: .received(Property(label: builder.label, typeDescription: functionType), isRequired: true),
				builder: builder,
				hole: holes.first { shapedBuilders?.builderBySite[$0.site]?.label == builder.label },
			))
			leadingParameters[leadingParameters.count - 1].narrowerTierNames = builder.narrowerTierLabels
		}

		// The received dependencies the mock builds and those received only if available, each `T? = nil`, by name.
		var promotedParameterNames = [Property: String]()
		var optionalReceivedParameters = [PublicMockParameter]()
		// A promoted `LazilyInstantiated` is taken as the wrapper under its label, unless another parameter takes that name: a
		// default-valued or forwarded parameter of the mocked type, or another promoted dependency, such as another
		// `LazilyInstantiated` of the label, which takes its label too. It then takes the name its binding is named apart by.
		let leadingParameterNames = Set(leadingParameters.map(\.name))
		func labelOrName(of property: Property, named name: String) -> String {
			property.propertyType.isLazilyInstantiated ? property.label : name
		}
		var promotedParameterCountByName = [String: Int]()
		for (property, name) in promotedNodes {
			promotedParameterCountByName[labelOrName(of: property, named: name), default: 0] += 1
		}
		for (property, name) in promotedNodes {
			let parameterProperty = publicMockParameterProperty(of: property)
			let preferredName = labelOrName(of: property, named: name)
			let parameterName = leadingParameterNames.contains(preferredName) || promotedParameterCountByName[preferredName, default: 0] > 1 ? name : preferredName
			promotedParameterNames[property] = parameterName
			optionalReceivedParameters.append(PublicMockParameter(name: parameterName, type: parameterProperty.typeDescription, typeSource: parameterProperty.typeDescription.asSource, defaultSource: "nil", defaultKind: .nilValue, access: access(of: parameterProperty.typeDescription, receivedAs: property.label), accessCause: cause(of: parameterProperty.typeDescription, receivedAs: property.label), role: .received(parameterProperty, isRequired: false), isBuiltWhenNil: true, builtWrapper: property.propertyType.isLazilyInstantiated ? property : nil))
		}
		// A dependency the mock passes on to a call of another module's public mock that builds it when passed `nil`, which
		// this module cannot construct and so does not promote, is built when this mock is passed `nil` too: by each such
		// call. A module that calls this mock and can construct the dependency then builds it once, as it does for a
		// dependency this mock builds itself (M8.8b). Only an only-if-available override reads it, so a mock without one,
		// as most are, walks no fill here.
		var wrapperBuiltByCallsWhenNil = [Property: Property?]()
		for node in treePropertyNodes where !onlyIfAvailableOverrides.isEmpty {
			var publicMockCalls = [PublicMockCall]()
			if let publicMockCall = node.generator.publicMockCall {
				publicMockCalls.append(publicMockCall)
			}
			if node.generator.fillsABuilder {
				publicMockCalls += ScopeGenerator.publicMockCallsInFills(of: node.generator)
			}
			for publicMockCall in publicMockCalls {
				for parameter in publicMockCall.passedParameters where parameter.isBuiltWhenNil && parameter.dependency.source == .received(onlyIfAvailable: true) {
					// A call that builds the wrapper decides the wrapper, whichever call the tree reaches first.
					let property = parameter.dependency.property.asUnwrappedProperty
					if let builtWrapper = parameter.builtWrapper {
						wrapperBuiltByCallsWhenNil[property] = .some(builtWrapper)
					} else if wrapperBuiltByCallsWhenNil[property] == nil {
						wrapperBuiltByCallsWhenNil[property] = .some(nil)
					}
				}
			}
		}
		for onlyIfAvailableOverride in onlyIfAvailableOverrides {
			// A value the tree receives lazily is taken as the wrapper it receives (`ScopeGenerator.publicMockWrapperParameters`).
			let type = wrapperParameterByInstance[onlyIfAvailableOverride.receivedProperty].map { TypeDescription.optional($0.typeDescription.unwrapped) } ?? onlyIfAvailableOverride.typeDescription
			let builtWrapper = wrapperBuiltByCallsWhenNil[onlyIfAvailableOverride.receivedProperty.asUnwrappedProperty]
			optionalReceivedParameters.append(PublicMockParameter(name: onlyIfAvailableOverride.name, type: type, typeSource: type.asSource, defaultSource: "nil", defaultKind: .nilValue, access: access(of: type, receivedAs: onlyIfAvailableOverride.receivedProperty.label), accessCause: cause(of: type, receivedAs: onlyIfAvailableOverride.receivedProperty.label), role: .received(Property(label: onlyIfAvailableOverride.receivedProperty.label, typeDescription: type), isRequired: false), isBuiltWhenNil: builtWrapper != nil, builtWrapper: builtWrapper ?? nil))
		}
		optionalReceivedParameters.sort { ($0.name, $0.typeSource) < ($1.name, $1.typeSource) }

		// The optional builders follow the required ones, so that no required builder's position moves.
		let optionalBuilders = publicMockOptionalBuilders(
			treePropertyNodes: treePropertyNodes,
			filledFamilies: givenFilledFamilies,
			requiredBuilders: builders,
			otherParameters: (leadingParameters + optionalReceivedParameters).map { (label: $0.name, access: $0.access) }
				+ (hasOverrides ? [(label: ReservedName.mockOverridesParameterName, access: AccessLevel.public)] : []),
			widestTier: .public,
			access: { access(of: $0, receivedAs: nil) },
		)
		var parameters = leadingParameters + optionalBuilders + optionalReceivedParameters
		if hasOverrides {
			let overridesType = TypeDescription.simple(name: ReservedName.mockOverridesTypeName)
			parameters.append(PublicMockParameter(name: ReservedName.mockOverridesParameterName, type: overridesType, typeSource: overridesType.asSource, defaultSource: ".init()", defaultKind: .expression, access: .public, role: .overrides))
		}
		let tiers = [AccessLevel.public] + Set(parameters.map(\.access)).filter { $0 < .public }.sorted(by: >)
		var hash = SeamSignatureHash()
		for parameter in parameters {
			hash.combine(parameter.name)
			// Only where a narrower tier takes a builder under another name, so every other mock hashes what it always hashed.
			for tierName in SeamSignature.CallShape.TierLabel.sorted(parameter.narrowerTierNames) {
				hash.combine("\(tierName.tier.spelledOnGeneratedDeclaration) \(tierName.label)")
			}
			hash.combine((parameter.typeWithoutAny ?? parameter.type.withoutAny).asSource)
			hash.combine(parameter.access.spelledOnGeneratedDeclaration)
			hash.combine(parameter.defaultKind.rawValue)
		}
		// After every parameter, the builders among them and every enum they reach, as a seam hashes them.
		SeamSignature.combine(scopeEnums: SeamSignature.scopeEnumShapes(of: shapedBuilders?.scopeEnums ?? [], holes: holes), hashesLabelsBoundLater: true, into: &hash)
		var plan = PublicMockPlan(
			parameters: parameters,
			tiers: tiers,
			guardTypeName: "\(ReservedName.builderFunctionNamePrefix)\(instantiable.concreteInstantiable.asIdentifier)_mock_\(hash.hexadecimal)",
			providerDeclarations: providerDeclarations,
			defaultResolutions: defaultResolutions,
			promotedParameterNames: promotedParameterNames,
		)
		plan.holes = holes
		plan.builders = builders
		plan.scopeEnums = shapedBuilders?.scopeEnums ?? []
		if let shapedBuilders, !shapedBuilders.places.cases.isEmpty {
			plan.places = shapedBuilders.places
			plan.caseIndexByHole = holes.map { shapedBuilders.caseIndexBySite[$0.site] ?? -1 }
		}
		return plan
	}

	/// The builders a public mock whose tree's nodes are `treePropertyNodes` takes optional (`PublicMockParameter.Role.optionalBuilder`), one
	/// per hole type and family its calls of other modules' public mocks fill, in the sorted order of the properties a call
	/// would receive each as (`ScopeGenerator.filledFamilies(of:)`). Each tier labels one as it would label a builder of its
	/// hole type it took required (`TierNames.label(ofStem:isSendable:)`), from the stems of every hole type of the mock's
	/// builders, unless those would rename a required builder's stem, when the optional builders' hole types are named apart
	/// among themselves; a label a parameter of the tier has takes `_`. Each is as visible as the type it builds.
	static func publicMockOptionalBuilders(
		treePropertyNodes: [MockTreeNames.PropertyNode],
		// D1 lane hook (lane C): the mock lowering hands the families and the body's names.
		filledFamilies givenFilledFamilies: (families: [FilledFamily], namesInBody: Set<String>)? = nil,
		requiredBuilders: [SeamSignature.Builder],
		otherParameters: [(label: String, access: AccessLevel)],
		widestTier: AccessLevel,
		access: (TypeDescription) -> AccessLevel,
	) -> [PublicMockParameter] {
		let fillPlaces = givenFilledFamilies == nil ? fillPlaces(in: treePropertyNodes) : (declaredLabels: [], calls: [])
		let filledFamilies = givenFilledFamilies?.families ?? filledFamilies(of: fillPlaces.calls)
		guard !filledFamilies.isEmpty else { return [] }
		let requiredHoleTypes = requiredBuilders.map(\.enumKey.holeType).uniqued().sorted { lhs, rhs in
			let lhsKey: (String, String) = (lhs.instantiatedType.asSource, lhs.builtType.asSource)
			let rhsKey: (String, String) = (rhs.instantiatedType.asSource, rhs.builtType.asSource)
			return lhsKey < rhsKey
		}
		let requiredStems = DependencyTreeGenerator.stems(of: requiredHoleTypes)
		let optionalStems = stemsOfOptionalBuilders(
			of: filledFamilies.map { ($0.family.holeType, $0.receivedProperty) },
			besideOwnHoleTypes: requiredHoleTypes,
			passedUpHoleTypes: [],
			requiredStems: requiredStems,
		)
		// The names the narrowest tier's function takes the builders under, apart from every name its body declares.
		var namesInBody = Set<String>(otherParameters.map(\.label))
		namesInBody.formUnion(requiredBuilders.map(\.internalName))
		namesInBody.formUnion(fillPlaces.declaredLabels)
		namesInBody.formUnion(givenFilledFamilies?.namesInBody ?? [])
		for node in treePropertyNodes {
			namesInBody.insert(functionName(toBuildPropertyNamed: node.property.label))
			namesInBody.formUnion(node.instantiable.dependencies.map(\.property.label))
		}
		var internalNames = GeneratedNameAllocator(reserving: namesInBody)
		var claimedLabels = [(label: String, access: AccessLevel)]()
		var parameters = [PublicMockParameter]()
		for filled in filledFamilies {
			let type = TypeDescription.optional(MockRootParameters.SeamMockBuilder.parameterType(ofPlaceProperties: filled.placeProperties, in: filled.family).strippingEscaping)
			let parameterAccess = access(type)
			let stem = optionalStems[filled.family.holeType, default: ""]
			var labeledParameters = otherParameters
			labeledParameters.append(contentsOf: claimedLabels)
			var narrowerAccesses = Set<AccessLevel>(labeledParameters.map(\.access))
			narrowerAccesses.insert(parameterAccess)
			var tiers = [widestTier]
			tiers.append(contentsOf: narrowerAccesses.filter { $0 < widestTier }.sorted(by: >))
			var labels = [(tier: AccessLevel, label: String)]()
			for tier in tiers where tier <= parameterAccess {
				let parameterLabels = Set<String>(labeledParameters.filter { $0.access >= tier }.map(\.label))
				let tierNames = DependencyTreeGenerator.TierNames(tier: tier, parameterLabels: parameterLabels)
				labels.append((tier: tier, label: tierNames.label(ofStem: stem, isSendable: filled.family.isSendable)))
			}
			let label = labels.first?.label ?? stem
			claimedLabels.append((label, parameterAccess))
			let joinedBuilder = requiredBuilders.first { $0.enumKey.holeType == filled.family.holeType && $0.enumKey.isSendable == filled.family.isSendable }?.enumKey
			var parameter = PublicMockParameter(
				name: label,
				type: type,
				typeSource: type.asSource,
				defaultSource: "nil",
				defaultKind: .nilValue,
				access: parameterAccess,
				role: .optionalBuilder(joinedBuilder: joinedBuilder),
			)
			for (tier, tierLabel) in labels.dropFirst() where tierLabel != label {
				parameter.narrowerTierNames[tier] = tierLabel
			}
			parameter.internalName = internalNames.claim(functionName(toBuildPropertyNamed: label))
			parameter.filledCallBuilders = filled.callBuilders
			parameter.optionalBuilderFamily = filled.family
			parameters.append(parameter)
		}
		return parameters
	}

	/// How visible a public mock's parameter of `type` is: as visible as the narrowest type it names, as the declarations of
	/// the mocked type's module prove it, and, for a dependency the tree receives as `label`, those of the modules of the
	/// types that receive it (`receiverModulesByLabel`, from `receiverModules(in:context:)`).
	static func publicMockParameterAccess(
		ofType type: TypeDescription,
		receivedAs label: String?,
		mockedType: Instantiable,
		receiverModulesByLabel: [String: Set<String?>],
		context: PublicMockContext,
	) -> TypeAccessProof.ParameterAccess {
		let ownModules: Set<String?> = [context.moduleName, mockedType.moduleName]
		let admittedModules = ownModules.union(label.map { receiverModulesByLabel[$0, default: []] } ?? [])
		return context.access(ofTypes: [type], admittedModules: admittedModules)
	}

	/// The modules that declare a receiver of each label in the tree of `nodes` (`MockTreeNames.propertyNodes`): a type
	/// whose declaration receives a dependency of that label, required or only if available. A type with no entry is
	/// proven by the mentions of the mocked type's module and of these modules.
	static func receiverModules(in nodes: [MockTreeNames.PropertyNode], context: PublicMockContext) -> [String: Set<String?>] {
		var modulesByLabel = [String: Set<String?>]()
		for node in nodes {
			let moduleName = context.moduleNameByType[node.instantiable.concreteInstantiable]
			for dependency in node.instantiable.dependencies {
				switch dependency.source {
				case .received:
					modulesByLabel[dependency.property.label, default: []].insert(moduleName)
				case let .aliased(fulfillingProperty, _, _):
					modulesByLabel[fulfillingProperty.label, default: []].insert(moduleName)
				case .instantiated, .forwarded:
					break
				}
			}
		}
		return modulesByLabel
	}

	/// The tiers of a public mock: the `mock()` of each tier of `plan`, widest first, all carrying `attributesPrefix`, each
	/// followed by the tier's `__safeDI_mock`, which `mock()` calls and which only generated code calls otherwise. The
	/// narrowest tier's `__safeDI_mock` body is `narrowestBody`; each wider tier's calls the next narrower one's, passing
	/// every parameter it takes and `nil` for each it omits, so the call names a label only the narrower tier has. The
	/// `public` tier is marked for `unreadTypeComment`, when there is one.
	static func publicMockTiers(
		of plan: PublicMockPlan,
		typeName: String,
		returnType: String,
		attributesPrefix: String,
		narrowestBody: [String],
		unreadTypeComment: UnreadTypeComment?,
	) -> [String] {
		let indent = standardIndent
		let bodyIndent = "\(indent)\(indent)"
		var lines = [String]()
		for (index, tier) in plan.tiers.enumerated() {
			let parameters = plan.parameters(ofTier: tier)
			// The `public` tier is marked for the file's comment when it names a type SafeDI reads no declaration of: what a
			// builder returns, and the value of every other parameter but the overrides, whose type the mock declares.
			if tier == .public, let marker = unreadTypeComment?.markerLine(
				namedBy: parameters.compactMap { parameter in
					if let hole = parameter.hole {
						hole.property.typeDescription
					} else if parameter.name == ReservedName.mockOverridesParameterName {
						nil
					} else {
						parameter.type
					}
				},
				indent: indent,
			) {
				lines.append(marker)
			}
			lines.append(contentsOf: parameters.flatMap(\.sharedValueDocumentation).map { "\(indent)\($0)" })
			let accessPrefix = "\(indent)\(attributesPrefix)\(tier == .internal ? "" : "\(tier.spelledOnGeneratedDeclaration) ")"
			// Every tier is a pair: `mock()`, which code people write calls, calls the tier's function only generated code calls,
			// which builds the tree, or forwards to the next narrower tier's. Generated code calls only the latter, so no call
			// SafeDI generates reaches a function meant for people. Where the tier takes a builder struct, `mock()` takes each
			// such builder as a closure that takes nothing and wraps it in the struct.
			let takesBuilderStruct = parameters.contains { $0.builder?.takesBuilderStruct == true }
			/// The lines that declare the tier's function named `functionName`, each parameter spelled by `spelling`.
			func appendSignature(functionName: String, omittingJoinedBuilders: Bool = false, takesBuilderStructs: Bool = false, spelling: (PublicMockParameter) -> String) {
				let declarationPrefix = "\(accessPrefix)static func \(functionName)("
				// `mock()` takes no parameter of its own for an optional builder joined to a required one, which it passes on.
				let parameters = omittingJoinedBuilders ? parameters.filter { $0.joinedBuilder == nil } : parameters
				// Only the `public` tier can take nothing, when every parameter is narrower: each narrower tier takes a parameter
				// of its own level.
				if parameters.isEmpty {
					lines.append("\(declarationPrefix)) -> \(returnType) {")
				} else {
					lines.append(declarationPrefix)
					lines.append(parameters.map { parameter in
						// The function only generated code calls takes a builder's struct, so its default is the struct of the builder
						// `mock()` defaults to.
						let defaultSource = takesBuilderStructs && parameter.defaultKind == .nilBuilder
							? ".init(\(ReservedName.noScopeArgumentLabel): \(ReservedName.nilBuilderSource))"
							: parameter.defaultSource
						return "\(bodyIndent)\(spelling(parameter))\(defaultSource.map { " = \($0)" } ?? "")"
					}.joined(separator: ",\n"))
					lines.append("\(indent)) -> \(returnType) {")
				}
			}
			appendSignature(functionName: InstantiableVisitor.mockMethodName, omittingJoinedBuilders: true) { parameter in
				if let builder = parameter.builder, builder.takesBuilderStruct {
					"\(parameter.name.spelledAsArgumentLabel): \(builder.readableParameterType.asSource)"
				} else {
					"\(parameter.name.spelledAsArgumentLabel): \(parameter.typeSource)"
				}
			}
			let arguments = parameters.map { parameter in
				let value = if parameter.builder?.takesBuilderStruct == true {
					".init(\(ReservedName.noScopeArgumentLabel): \(parameter.name))"
				} else if let joinedBuilder = parameter.joinedBuilder, let required = parameters.first(where: { $0.builder?.enumKey == joinedBuilder }) {
					required.name
				} else {
					parameter.name
				}
				return "\(parameter.name.spelledAsArgumentLabel): \(value)"
			}
			lines.append("\(bodyIndent)\(typeName).\(ReservedName.publicMockFunctionName)(\(arguments.joined(separator: ", ")))")
			lines.append("\(indent)}")
			lines.append("")
			lines.append("\(indent)/// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.")
			appendSignature(functionName: ReservedName.publicMockFunctionName, takesBuilderStructs: true) { parameter in
				if let builder = parameter.builder, builder.takesBuilderStruct {
					"\(parameter.name.spelledAsArgumentLabel) \(builder.internalName): \(parameter.typeSource)"
				} else if let internalName = parameter.internalName {
					"\(parameter.name.spelledAsArgumentLabel) \(internalName): \(parameter.typeSource)"
				} else {
					"\(parameter.name.spelledAsArgumentLabel): \(parameter.typeSource)"
				}
			}
			if index == plan.tiers.count - 1 {
				lines.append(contentsOf: narrowestBody)
			} else {
				// An omitted parameter that defaults to a provider is passed the provider's value, the declaration's
				// default, which `nil` would replace. A builder can take another name in the narrower tier, and a builder
				// struct is passed by the name the function takes it under.
				let narrowerTier = plan.tiers[index + 1]
				let arguments = plan.parameters.filter { $0.access >= narrowerTier }.map { parameter in
					let value = if parameter.access >= tier, takesBuilderStruct, let builder = parameter.builder, builder.takesBuilderStruct {
						builder.internalName
					} else if parameter.access >= tier, let internalName = parameter.internalName {
						internalName
					} else if parameter.access >= tier {
						parameter.name(inTier: tier)
					} else if parameter.defaultKind == .provider, let defaultSource = parameter.defaultSource {
						defaultSource
					} else {
						"nil"
					}
					return "\(parameter.name(inTier: narrowerTier).spelledAsArgumentLabel): \(value)"
				}
				lines.append("\(bodyIndent)\(typeName).\(ReservedName.publicMockFunctionName)(\(arguments.joined(separator: ", ")))")
			}
			lines.append("\(indent)}")
			if index < plan.tiers.count - 1 {
				lines.append("")
			}
		}
		return lines
	}
}

/// Why the public mock of a `generateMock: .public` type cannot be generated, reported at its `generateMock:` argument.
struct PublicMockFinding: Hashable, Sendable {
	let sourceDiagnostics: [SourceDiagnostic]

	/// A required parameter of the mock is narrower than `public`, so the `public` tier cannot take it.
	struct OmittedRequiredParameter {
		/// How the mock takes the parameter.
		enum Kind {
			/// The mocked type forwards it.
			case forwarded
			/// A type in the mocked type's tree receives it, which the mock cannot build.
			case received
			/// A type in the mocked type's tree instantiates it, which no declaration the module sees fulfills.
			case instantiated
			/// The builder of a hole of the mocked type's tree, which returns the hole's property.
			case builder(SeamSignature.Hole)
		}

		let property: Property
		let kind: Kind
		let level: AccessLevel
		/// How the parameter's narrowest type is proven, which a type narrower than `public` always has.
		let cause: TypeAccessProof.Cause
		/// The declarations in the tree that receive or instantiate the parameter, in tree order.
		let receivers: [(declaringType: TypeDescription, dependency: Dependency)]
	}

	/// `generateMock: .public` on a type a narrower enclosing type keeps from being `public`.
	static func narrowerEnclosingType(of instantiable: Instantiable, enclosingTypeName: String, enclosingLevel: AccessLevel) -> PublicMockFinding {
		let typeName = instantiable.concreteInstantiable.asSource
		let level = enclosingLevel.spelledOnGeneratedDeclaration
		return PublicMockFinding(sourceDiagnostics: [
			SourceDiagnostic(
				severity: .error,
				location: instantiable.mockGenerationArgumentLocation,
				message: "`\(typeName)` cannot have a public mock because `\(enclosingTypeName)` is `\(level)`. Make `\(enclosingTypeName)` `public`, or use `generateMock: .internal`.",
				fixIts: instantiable.mockGenerationArgumentRange.map { [SourceDiagnostic.FixIt(range: $0, replacement: ".internal")] } ?? [],
			),
		])
	}

	/// `generateMock: .public` on a type narrower than `public`, which the macro rejects (`publicMockRequiresPublicType`)
	/// once it expands: a plain error at the declaration, with no fix-it, which the macro keeps for the IDE.
	static func typeTheMacroRejects(_ instantiable: Instantiable, level: AccessLevel) -> PublicMockFinding {
		let typeName = instantiable.concreteInstantiable.asSource
		return PublicMockFinding(sourceDiagnostics: [
			SourceDiagnostic(
				severity: .error,
				location: instantiable.declarationLocation,
				message: "`\(typeName)` is `\(level.spelling)` and declares `generateMock: .public`. The @\(InstantiableVisitor.macroName) macro rejects that: `generateMock: .public` requires a `public` or `open` type. Declare `\(typeName)` `public`, or use `generateMock: .internal`.",
			),
		])
	}

	/// The modules that call the public mock of `instantiable` compute its signature from declarations that leave out
	/// `declaration`, which a directory this module's configuration adds declares, so their calls would not match the mock.
	static func callersCannotSee(_ declaration: TypeDescription, of instantiable: Instantiable) -> PublicMockFinding {
		let typeName = instantiable.concreteInstantiable.asSource
		let declarationName = declaration.asSource
		let message = "SafeDI cannot generate the public mock of `\(typeName)`: its signature depends on `\(declarationName)`, which is declared in a directory this module’s `#SafeDIConfiguration` adds, and the modules that call the mock cannot see that declaration, so their calls would not match the mock. Declare `\(declarationName)` in a file of this module, or of a module it depends on."
		return PublicMockFinding(sourceDiagnostics: [
			SourceDiagnostic(severity: .error, location: instantiable.mockGenerationArgumentLocation, message: message),
		])
	}

	/// The callers of `instantiable`'s public mock compute its signature without `declaration`, a plain declaration in a
	/// directory this module's configuration adds that proves a parameter's type narrower than `public`, which they would
	/// count as `public`: reported at the declaration.
	static func callersCannotSeePlainDeclaration(_ declaration: PlainTypeDeclaration, of instantiable: Instantiable) -> PublicMockFinding {
		let typeName = "`\(instantiable.concreteInstantiable.asSource)`"
		let declarationName = "`\(declaration.typeDescription.asSource)`"
		let message = "SafeDI cannot generate the public mock of \(typeName): it takes its parameters at the access this declaration of \(declarationName) proves, which is in a directory this module’s `#SafeDIConfiguration` adds, and the modules that call the mock cannot see it, so they would count \(declarationName) as `public`, and their calls would not match the mock. Declare \(declarationName) in a file of this module, or of a module it depends on."
		return PublicMockFinding(sourceDiagnostics: [
			SourceDiagnostic(severity: .error, location: declaration.access.declarationStartLocation ?? instantiable.mockGenerationArgumentLocation, message: message),
		])
	}

	/// `holeDependency`, a hole of `instantiable` the mock builds with a builder `mock()` takes, shares its label with
	/// `receive`, which the mock binds beside it, so the mock cannot hand the builders `mock()` is passed the right value of
	/// the label (`ScopeGenerator.publicMockHoleSiteBoundApartFinding`). Reported at the hole's declaration, with a note at
	/// the receive. The one remedy renames the hole, which is local to `instantiable`: renaming the receive would
	/// mean renaming the declaration that production hands it too.
	static func holeSiteBoundApart(_ holeDependency: Dependency, receive: (receivingType: TypeDescription, receivedProperty: Property, declarationLocation: Dependency.DeclarationLocation?), of instantiable: Instantiable) -> PublicMockFinding {
		let typeName = "`\(instantiable.concreteInstantiable.asSource)`"
		let hole = "`\(holeDependency.property.asSource)`"
		let receivedProperty = "`\(receive.receivedProperty.asSource)`"
		let message = "SafeDI cannot generate the public mock of \(typeName): the mock builds \(hole), which \(typeName) instantiates, with a builder `mock()` is passed, and `\(receive.receivingType.asSource)` receives \(receivedProperty) with the same label, so the mock holds two values labeled `\(holeDependency.property.label)` and cannot hand `\(holeDependency.property.label)` to the builder `mock()` is passed. Declare \(hole) on \(typeName) under another label to fix."
		return PublicMockFinding(sourceDiagnostics: [
			SourceDiagnostic(severity: .error, location: holeDependency.declarationLocation, message: message),
			SourceDiagnostic(severity: .note, location: receive.declarationLocation, message: "\(receivedProperty) is received here"),
		])
	}

	/// `holeDependency`, a hole of `instantiable` the mock builds with a builder `mock()` takes, has a label that no type in
	/// the mock's tree receives but that equals a name SafeDI generates for another value of the mock (a sibling or a flat
	/// parameter named apart, the binding of a `LazilyInstantiated` the mock wraps), which the mock binds beside it, so it
	/// cannot hand the builders `mock()` is passed the hole's value under its label
	/// (`ScopeGenerator.publicMockHoleSiteBoundApartFinding`). Reported at the hole's declaration, with no note, since no
	/// declaration receives the label. The one remedy renames the hole, as `holeSiteBoundApart`'s does.
	static func holeSiteBoundApartFromGeneratedName(_ holeDependency: Dependency, of instantiable: Instantiable) -> PublicMockFinding {
		let typeName = "`\(instantiable.concreteInstantiable.asSource)`"
		let hole = "`\(holeDependency.property.asSource)`"
		let label = "`\(holeDependency.property.label)`"
		let message = "SafeDI cannot generate the public mock of \(typeName): the mock builds \(hole), which \(typeName) instantiates, with a builder `mock()` is passed, and cannot hand \(label) to the builder `mock()` is passed, because SafeDI names another value of the mock \(label). Declare \(hole) on \(typeName) under another label to fix."
		return PublicMockFinding(sourceDiagnostics: [
			SourceDiagnostic(severity: .error, location: holeDependency.declarationLocation, message: message),
		])
	}

	/// `publicTierOmitsRequiredParameter`: the `public` tier the mock requires cannot take `parameter`.
	static func omittedRequiredParameter(_ parameter: OmittedRequiredParameter, of instantiable: Instantiable) -> PublicMockFinding {
		let typeName = "`\(instantiable.concreteInstantiable.asSource)`"
		let receiverNames = parameter.receivers.map(\.declaringType).uniqued().map { "`\($0.asSource)`" }
		// A lone receiver that receives the parameter through an alias of it, which names the alias.
		let aliasReceiver = parameter.receivers.count == 1 ? parameter.receivers.first.flatMap { receiver in
			receiver.dependency.source.fulfillingProperty.map { _ in (declaringType: receiver.declaringType, aliasProperty: receiver.dependency.property) }
		} : nil
		let receivedTaker = if let aliasReceiver {
			"which the initializer of `\(aliasReceiver.declaringType.asSource)` receives through its alias `\(aliasReceiver.aliasProperty.label)` (`fulfilledByDependencyNamed: \"\(parameter.property.label)\"`)"
		} else if receiverNames.count > 1 {
			"which the initializers of \(receiverNames.joinedAsList) receive"
		} else {
			"which the initializer of \(receiverNames.first ?? typeName) receives"
		}
		let taker = switch parameter.kind {
		case .forwarded:
			"which \(typeName) forwards"
		case .received:
			receivedTaker
		case .instantiated:
			"which \(receiverNames.first ?? typeName) instantiates and no `@Instantiable` declaration this module sees fulfills"
		case let .builder(hole):
			// A public mock's builder takes a place of its shaped signature, which has its case nested by type (`enumPlace`). The
			// case is named alone, never qualified by its enum, since a diagnostic names no generated type.
			"whose member `\(hole.enumPlace?.caseName ?? hole.property.label)` builds `\(hole.builtType.asSource)` for the hole `\(hole.property.label)`"
		}
		let parameterName = if case let .builder(hole) = parameter.kind {
			hole.builderLabel
		} else {
			parameter.property.asSource
		}
		let causeText = SeamAccessExplanation.causeSentence(parameter.cause, receivers: [])
		var remedies = SeamAccessExplanation.causeRemedies(parameter.cause, neededLevel: .public)
		switch parameter.kind {
		case .forwarded where parameter.cause.leavesOutMockOnlyMockOfType:
			remedies.append("give `\(parameter.cause.type.asSource)` a `mockOnly` mock")
		case .received:
			remedies.append("receive \(aliasReceiver.map { "`\($0.aliasProperty.label)`" } ?? "it") with `onlyIfAvailable: true` and an optional type")
		case .forwarded, .instantiated:
			break
		case let .builder(hole):
			// A stub the mock builds in place of taking the builder, which production never sees.
			let holeType = hole.property.typeDescription.asInstantiatedType.withoutAny.asSource
			let module = instantiable.moduleName.map { "module `\($0)`" } ?? "this module"
			remedies.append("declare in \(module), or a module it depends on, a `mockOnly` `@\(InstantiableVisitor.macroName)` type that fulfills `\(holeType)` (`@\(InstantiableVisitor.macroName)(fulfillingAdditionalTypes: [\(holeType).self], mockOnly: true)`), which the mock builds instead of taking `\(hole.builderLabel)`, leaving production’s hole as it is")
		}
		if case let .signatures(_, _, provers, _) = parameter.cause {
			// The members that prove the type, by name, each of which proves it at the level it spells.
			for prover in provers where prover.cap == nil {
				remedies.append("make \(prover.name) `public`")
			}
		}
		remedies.append("use `generateMock: .internal`")
		let message = "SafeDI cannot generate the public mock of \(typeName): its `public` tier, which `generateMock: .public` requires, cannot take `\(parameterName)`, \(taker), and cannot pass `nil` for it, since it is required. \(causeText) \(SeamAccessExplanation.joined(remedies))"
		let verb = switch parameter.kind {
		case .instantiated, .builder:
			"instantiates"
		case .forwarded, .received:
			"receives"
		}
		var sourceDiagnostics = [SourceDiagnostic(severity: .error, location: instantiable.mockGenerationArgumentLocation, message: message)]
			+ SeamAccessExplanation.declarationNotes(for: parameter.cause, neededLevel: .public)
		for receiver in parameter.receivers {
			sourceDiagnostics.append(SourceDiagnostic(
				severity: .note,
				location: receiver.dependency.declarationLocation,
				message: "`\(receiver.declaringType.asSource)` \(verb) `\(receiver.dependency.property.asSource)` here.",
			))
		}
		return PublicMockFinding(sourceDiagnostics: sourceDiagnostics)
	}
}

extension ScopeGenerator {
	/// What keeps `instantiable`'s public mock from being generated, from the parameters this mock root's `mock()`
	/// takes: a narrower enclosing type, and each required parameter narrower than `public`. A public mock's tiers are
	/// otherwise always generated, so this decides whether one root can be generated, which the query reports too.
	/// - Parameter mockDefaults: The hand-written mock a flat parameter of each type defaults to, which the mock then
	///   takes as `T? = nil`.
	func publicMockFindings(of instantiable: Instantiable, context: PublicMockContext, mockDefaults: [TypeDescription: FlatParameterMockDefault]) async -> [PublicMockFinding] {
		// The type's own declaration, the types enclosing it in its file and, for a type declared inside an extension,
		// the declarations of the type the extension extends that SafeDI records, outermost first, each with its own
		// level. The macro requires the type itself to be `public` or `open`, or directly inside a `public extension`, but
		// `generate` runs before the macro expands, so a narrower type gets a plain error that points at the macro's rule.
		// Otherwise only an enclosing type can make it narrower, and the innermost such type is the one to name.
		var narrowerEnclosingType: (type: TypeDescription, level: AccessLevel)?
		for accessNeed in context.extendedTypeAccessNeedsByType[instantiable.concreteInstantiable, default: []] + instantiable.accessNeeds(constructingWithMockMethod: false) {
			switch accessNeed.declaration {
			case let .type(type), let .extensionDeclaringType(type):
				guard AccessLevel.normalized(accessNeed.level) < .public else { continue }
				if type == instantiable.concreteInstantiable {
					return [PublicMockFinding.typeTheMacroRejects(instantiable, level: accessNeed.level)]
				} else {
					narrowerEnclosingType = (type, accessNeed.level)
				}
			case .member, .extensionDeclaringMember:
				continue
			}
		}
		if let narrowerEnclosingType {
			return [PublicMockFinding.narrowerEnclosingType(of: instantiable, enclosingTypeName: narrowerEnclosingType.type.asSource, enclosingLevel: narrowerEnclosingType.level)]
		}
		let parameters = mockRootParameters(instantiable: instantiable, mockDefaults: mockDefaults)
		let ownModules: Set<String?> = [context.moduleName, instantiable.moduleName]
		let receiverModulesByLabel = Self.receiverModules(in: parameters.treeNames.propertyNodes, context: context)
		let treeReceivers = Self.treeReceivers(in: parameters.treeNames.propertyNodes, mockedType: instantiable)
		var omittedParameters = [PublicMockFinding.OmittedRequiredParameter]()
		func check(_ property: Property, kind: PublicMockFinding.OmittedRequiredParameter.Kind) {
			let isForwarded = if case .forwarded = kind {
				true
			} else {
				false
			}
			let admittedModules = isForwarded ? ownModules : ownModules.union(receiverModulesByLabel[property.label, default: []])
			let access = context.access(ofTypes: [property.typeDescription], admittedModules: admittedModules)
			guard access.level < .public, let cause = access.cause else { return }
			omittedParameters.append(PublicMockFinding.OmittedRequiredParameter(
				property: property,
				kind: kind,
				level: access.level,
				cause: cause,
				// An alias receives the property it is fulfilled by.
				receivers: isForwarded ? [] : treeReceivers.filter { ($0.dependency.source.fulfillingProperty ?? $0.dependency.property).label == property.label },
			))
		}
		// A parameter with a default is taken as `T? = nil`, which a tier that cannot take it passes.
		for dependency in parameters.forwardedDependencies where parameters.forwardedParameterDefaults[dependency.property.label] == nil {
			check(dependency.property, kind: .forwarded)
		}
		for property in parameters.flatReceivedProperties where parameters.flatReceivedParameterMockDefaults[property] == nil {
			check(property, kind: .received)
		}
		for uncovered in parameters.flatUncoveredParameters {
			check(uncovered.property, kind: .instantiated)
		}
		// A builder is as visible as the places it builds, proven as a seam's builder is, and reported once per declaration
		// of a place's property, however many places build it.
		var reportedDeclarations = Set<String>()
		for hole in parameters.mockBuilders?.holes ?? [] where hole.tierAccess < .public {
			guard let cause = hole.accessCause,
			      reportedDeclarations.insert("\(hole.ownerType.asSource) \(hole.property.asSource)").inserted
			else { continue }
			omittedParameters.append(PublicMockFinding.OmittedRequiredParameter(
				property: hole.property,
				kind: .builder(hole),
				level: hole.tierAccess,
				cause: cause,
				receivers: [(declaringType: hole.ownerType, dependency: Dependency(property: hole.property, source: .instantiated(fulfillingTypeDescription: nil, erasedToConcreteExistential: hole.erasedToConcreteExistential), declarationLocation: hole.declarationLocation))],
			))
		}
		var findings = omittedParameters.map { PublicMockFinding.omittedRequiredParameter($0, of: instantiable) }
		if let holeSiteBoundApartFinding = publicMockHoleSiteBoundApartFinding(of: instantiable, parameters: parameters) {
			findings.append(holeSiteBoundApartFinding)
		}
		return findings
	}

	/// A site of a hole of the mocked type that the mock would bind apart from its label (`renamingAliases`), because a type
	/// in the tree of a dependency the mocked type receives receives the label in a form the hole's declaration does not
	/// provide. The mock hands the builders `mock()` is passed the values the mocked type holds by their labels, and would
	/// hold two under this one, so it cannot hand the right one: to the builder of another place, or to the site's own
	/// builder, whose values can hold one built from the site. Every such site is rejected, whatever else the mock holds and
	/// in whichever order the mocked type declares it, so `renamingAliases` never binds a site apart. The sites bound apart
	/// are the ones `generateMockRootCode` binds apart: both read `mockRootTopLevelNames`, which decides it by names alone,
	/// so the finding never depends on finding a receive of the label. The first such hole in the mocked type's declaration
	/// order is reported, with a note at the first receive of its label the hole does not provide, in the order the mock's
	/// tree first receives its dependencies; where no type receives the label, which then equals a name SafeDI generates for
	/// another value of the mock, the error names that value instead, with no note.
	///
	/// A deliberate gap: an internal mock, and a listed type's, takes such a dependency as a parameter under its label and
	/// has no site, so it accepts the shape (`renamingAliases` says so too).
	private func publicMockHoleSiteBoundApartFinding(of instantiable: Instantiable, parameters: MockRootParameters) -> PublicMockFinding? {
		let namesAliasesAreBoundApartFrom = Self.mockRootTopLevelNames(of: parameters, parameterNames: Self.mockRootParameterNames(of: parameters)).namesAliasesAreBoundApartFrom
		var boundApartHoleLabels = Set<String>()
		for property in parameters.treeNames.rootHoleSiteProperties where namesAliasesAreBoundApartFrom.contains(property.label) {
			boundApartHoleLabels.insert(property.label)
		}
		guard let holeDependency = instantiable.dependencies.first(where: { boundApartHoleLabels.contains($0.property.label) }) else { return nil }
		if let receive = firstReceive(ofLabelOf: holeDependency.property) {
			return PublicMockFinding.holeSiteBoundApart(holeDependency, receive: receive, of: instantiable)
		} else {
			return PublicMockFinding.holeSiteBoundApartFromGeneratedName(holeDependency, of: instantiable)
		}
	}

	/// The first receive of `holeProperty`'s label in this mock root's tree that a declaration of `holeProperty` does not
	/// provide, in the order the mock's tree first receives its dependencies (`inOrderTheMockTreeFirstReceives`): the trees
	/// of the mocked type's own children, then those of the dependencies the mock promotes, each depth first, every type's
	/// dependencies in declaration order before its children's trees, up to a type that declares the label itself.
	private func firstReceive(ofLabelOf holeProperty: Property) -> (receivingType: TypeDescription, receivedProperty: Property, declarationLocation: Dependency.DeclarationLocation?)? {
		let declaredProperties: Set<Property> = [holeProperty, holeProperty.asValidatedForDependencyCycles]
		/// The property a dependency receives from the types above it: the fulfilling property of an alias, the declared
		/// property of a receive, and `nil` for a property the type declares.
		func receivedProperty(of dependency: Dependency) -> Property? {
			switch dependency.source {
			case .received:
				dependency.property
			case let .aliased(fulfillingProperty, _, _):
				fulfillingProperty
			case .instantiated, .forwarded:
				nil
			}
		}
		/// The generators among `generators` that build a type, last first, since the stack walks its last element next.
		func typesToWalk(among generators: [ScopeGenerator]) -> [(generator: ScopeGenerator, instantiable: Instantiable)] {
			generators.reversed().compactMap { generator in generator.builtInstantiable.map { (generator: generator, instantiable: $0) } }
		}
		var receive: (receivingType: TypeDescription, receivedProperty: Property, declarationLocation: Dependency.DeclarationLocation?)?
		// A stack of its own, since a mock tree can be as deep as the module has types.
		var typesLeftToWalk = typesToWalk(among: children)
		while receive == nil, let typeToWalk = typesLeftToWalk.popLast() {
			let builtInstantiable = typeToWalk.instantiable
			if let dependency = builtInstantiable.dependencies.first(where: { dependency in
				receivedProperty(of: dependency).map { property in
					property.label == holeProperty.label && !Self.provides(property, declaredProperties: declaredProperties, forwardedProperties: [])
				} ?? false
			}), let property = receivedProperty(of: dependency) {
				receive = (builtInstantiable.concreteInstantiable, property, dependency.declarationLocation)
			} else if !builtInstantiable.dependencies.contains(where: { !$0.source.isReceived && $0.property.label == holeProperty.label }) {
				// A type that declares the label itself is what the types it builds receive under it.
				typesLeftToWalk += typesToWalk(among: typeToWalk.generator.children)
			}
		}
		return receive
	}

	/// The declarations in the tree of `nodes` (`MockTreeNames.propertyNodes`) that receive or instantiate a dependency, by
	/// its label, in tree order: the mocked type's own first.
	static func receivers(in nodes: [MockTreeNames.PropertyNode], mockedType: Instantiable) -> [String: [(declaringType: TypeDescription, dependency: Dependency)]] {
		Dictionary(grouping: treeReceivers(in: nodes, mockedType: mockedType)) { $0.dependency.property.label }
	}

	/// Each dependency a declaration in the tree of `nodes` (`MockTreeNames.propertyNodes`, each before its children)
	/// declares, with that declaration, in tree order: the mocked type's own first. A tree has a node per path, each of
	/// which lists its type's dependencies again, so each declaration is kept once, where the tree first reaches it, as a
	/// seam's receivers are (`DependencyTreeGenerator.receivers(in:of:instantiables:)`): a diagnostic names it once, and
	/// the list never follows the number of paths.
	static func treeReceivers(in nodes: [MockTreeNames.PropertyNode], mockedType: Instantiable) -> [(declaringType: TypeDescription, dependency: Dependency)] {
		var receivers = mockedType.dependencies.map { (declaringType: mockedType.concreteInstantiable, dependency: $0) }
		var declarations = Set(receivers.map { TreeReceiverDeclaration(declaringType: $0.declaringType, dependency: $0.dependency) })
		for node in nodes {
			let declaringType = node.instantiable.concreteInstantiable
			for dependency in node.instantiable.dependencies
				where declarations.insert(TreeReceiverDeclaration(declaringType: declaringType, dependency: dependency)).inserted
			{
				receivers.append((declaringType: declaringType, dependency: dependency))
			}
		}
		return receivers
	}

	/// A declaration of a dependency in a mock's tree, as `treeReceivers(in:mockedType:)` keeps it once. A declaration read
	/// from another module's info carries no location, so the source is part of it too: two declarations of one type and
	/// property that differ only in how the value reaches them stay two receivers, and which one is kept never follows
	/// the order of the walk.
	private struct TreeReceiverDeclaration: Hashable {
		init(declaringType: TypeDescription, dependency: Dependency) {
			self.declaringType = declaringType
			declarationLocation = dependency.declarationLocation
			property = dependency.property
			source = dependency.source
		}

		let declaringType: TypeDescription
		let declarationLocation: Dependency.DeclarationLocation?
		let property: Property
		let source: Dependency.Source
	}
}

/// The plan of a public mock a module computed for one of its own types, as another module's mock tree reads it to
/// call the mock.
struct OwnPublicMockPlan: Sendable {
	/// The mocked type's declaration, as the mock root is built from it.
	let instantiable: Instantiable
	let plan: PublicMockPlan
	/// The declarations in the mock's tree that receive each label, in tree order, which a diagnostic notes.
	let receiversByLabel: [String: [(declaringType: TypeDescription, dependency: Dependency)]]
	/// `ScopeGenerator.typesDeclaredEscaping` of the mock root.
	let typesDeclaredEscaping: Set<TypeDescription>
}

extension StoredPublicMockPlan {
	/// What a module that calls the mock reads of `ownPlan`.
	init(_ ownPlan: OwnPublicMockPlan) {
		let parameters = ownPlan.plan.parameters.map(Parameter.init)
		let noTierParameters = ownPlan.plan.noTierParameters.map(Parameter.init)
		// A tier omits only a received parameter narrower than `public`, or one on no tier.
		var omittableLabels = Set<String>()
		for parameter in parameters + noTierParameters {
			guard case let .received(property, _) = parameter.role, parameter.access < .public || parameter.nestedOmission != nil else { continue }
			omittableLabels.insert(property.label)
		}
		// A tree has a node per path, each of which lists its type's dependencies again, and a diagnostic names each
		// declaration once, so each declaration's receive is kept once: a plan's size never follows the number of paths.
		var receivers = [Receiver]()
		if !omittableLabels.isEmpty {
			var receives = Set<Receive>()
			for label in ownPlan.receiversByLabel.keys.sorted() where omittableLabels.contains(label) {
				for receiver in ownPlan.receiversByLabel[label, default: []]
					where receiver.dependency.source.isReceived
					&& receives.insert(Receive(declaringType: receiver.declaringType, property: receiver.dependency.property, source: receiver.dependency.source)).inserted
				{
					receivers.append(Receiver(declaringType: receiver.declaringType, dependency: receiver.dependency))
				}
			}
		}
		let parameterTypes = Set(parameters.map(\.type))
		self.init(
			mockedType: ownPlan.instantiable.concreteInstantiable,
			parameters: parameters,
			noTierParameters: noTierParameters,
			tiers: ownPlan.plan.tiers,
			guardTypeName: ownPlan.plan.guardTypeName,
			holes: ownPlan.plan.holes,
			builders: ownPlan.plan.builders,
			scopeEnums: ownPlan.plan.scopeEnums,
			places: ownPlan.plan.places,
			caseIndexByHole: ownPlan.plan.caseIndexByHole,
			receivers: receivers,
			typesDeclaredEscaping: ownPlan.typesDeclaredEscaping.filter(parameterTypes.contains).sorted(),
		)
	}
}

extension StoredPublicMockPlan {
	/// What tells one declaration's receive of a dependency from another's, without where it is declared.
	private struct Receive: Hashable {
		let declaringType: TypeDescription
		let property: Property
		let source: Dependency.Source
	}
}

extension StoredPublicMockPlan.Parameter {
	/// What a module that calls the mock reads of `parameter`.
	init(_ parameter: PublicMockParameter) {
		self.init(
			name: parameter.name,
			narrowerTierNames: parameter.narrowerTierNames,
			type: parameter.type,
			access: parameter.access,
			accessCause: parameter.accessCause,
			nestedOmission: parameter.nestedOmission,
			role: parameter.role,
			isBuiltWhenNil: parameter.isBuiltWhenNil,
			builtWrapper: parameter.builtWrapper,
			builder: parameter.builder,
		)
	}
}

/// How a mock tree calls the public mock another module generated for a type the tree cannot build itself (see
/// `Scope.publicMockCall`). The tree's scope for the type is a leaf that declares the mock's whole signature: each
/// parameter of the tier the call reaches as the dependency it stands for – a forwarded property, or a received one,
/// required or only if available – and each parameter that tier omits as a receive only if available, which the call
/// never passes but which orders the leaf among its siblings, as the receivers the mock builds would be ordered.
struct PublicMockCall: Sendable {
	/// The type whose mock the call calls.
	let type: TypeDescription
	/// The tier the call reaches: the narrowest the calling module can reach.
	let tier: AccessLevel
	/// The parameters of `tier` that stand for a dependency, in signature order, which the call passes by name.
	let passedParameters: [PassedParameter]
	/// The parameters `tier` omits, which the call passes `nil` for by leaving them out.
	let omittedParameters: [StoredPublicMockPlan.Parameter]
	/// Whether the mock takes `safeDIOverrides`, which the call passes the calling mock's entry for the type.
	let takesOverrides: Bool
	/// The enum the call names, whose name hashes the mock's signature.
	let guardTypeName: String
	/// See `SeamCall.comment`.
	let comment: SeamCallComment
	/// The module that declares the type and generated its mock.
	let declaringModule: ModuleIdentity
	/// The module whose mock tree makes the call.
	let callerModule: ModuleIdentity
	/// What the calling module needs of the declaring module's declarations.
	let requirement: AccessRequirement
	/// The condition the declaring module generates its mocks under, and the calling module's.
	let declaringModuleMockCondition: MockCondition
	let callerModuleMockCondition: MockCondition

	/// Whether the calling module's mocks can call the mock: the two modules generate their mocks under one condition,
	/// spelled the same, or the declaring module's mocks are unconditional.
	var mockConditionsAgree: Bool {
		Self.mockConditionsAgree(declaringModuleMockCondition: declaringModuleMockCondition, callerModuleMockCondition: callerModuleMockCondition)
	}

	/// Whether a module whose mocks generate under `callerModuleMockCondition` can call a mock its declaring module
	/// generates under `declaringModuleMockCondition` (`mockConditionsAgree`).
	static func mockConditionsAgree(declaringModuleMockCondition: MockCondition, callerModuleMockCondition: MockCondition) -> Bool {
		declaringModuleMockCondition.conditionalCompilation == nil || declaringModuleMockCondition == callerModuleMockCondition
	}

	/// The declarations in the public mock's tree that receive each label a tier can omit, which a diagnostic notes
	/// (`StoredPublicMockPlan.receivers`).
	let receiversByLabel: [String: [StoredPublicMockPlan.Receiver]]
	/// The places the call fills (`DependencyTreeGenerator.holesFilled(byCallsOf:in:)`), each
	/// with a fill on every route; the call passes every other place up.
	var filledHoles = [SeamSignature.Hole]()
	/// The types of the passed parameters that the mock's tree declares `@escaping` (`ScopeGenerator.typesDeclaredEscaping`).
	/// The calling tree's scope for the type is a leaf, with no scopes for that tree, so a function the calling tree
	/// declares with such a parameter learns the name here.
	let typesDeclaredEscaping: Set<TypeDescription>
	/// The builders the call passes, built once with the call: its `holes` are every place the mock's builders reach, in the
	/// order they reach them (`PublicMockPlan.holes`), since the mock fills every place of a hole type of each call it makes
	/// or none, and its builders reach a called mock's places only where it passes them up; its `builders` the builders the
	/// mock takes (`PublicMockPlan.builders`); and its `scopeEnums` every enum they reach (`PublicMockPlan.scopeEnums`).
	let calledBuilders: CalledBuilders

	/// Every place the mock's builders reach (see `calledBuilders`).
	var holes: [SeamSignature.Hole] {
		calledBuilders.holes
	}

	/// The builders the mock takes.
	var builders: [SeamSignature.Builder] {
		calledBuilders.builders
	}

	/// The function the call calls: the one only generated code calls, `__safeDI_mock`, which every tier of every public mock
	/// declares beside its `mock()`. Generated code never calls a function meant for code people write in another module.
	var functionName: String {
		ReservedName.publicMockFunctionName
	}

	/// The builders a caller that fills `filledHoles` passes up, as the leaf receives them: each whose routes reach a place
	/// the caller does not fill (`CalledBuilders.routesReachOnly(_:by:)`).
	var passedUpBuilders: [SeamSignature.Builder] {
		let calledBuilders = calledBuilders
		let filledSites = calledBuilders.siteNumbers(of: Set(filledHoles.map(\.site)))
		return builders.filter { !calledBuilders.routesReachOnly(filledSites, by: $0) }
	}

	/// Whether the leaf that makes the call receives `property` as a builder it passes up, which an internal mock takes as a
	/// parameter of its own (`MockLowering.RootSignature.passedUpBuilders`).
	func passesUpBuilder(receivedAs property: Property) -> Bool {
		passedParameters.contains { $0.builder != nil && $0.dependency.property == property }
	}
}

extension PublicMockCall {
	/// A parameter of the called tier that stands for a dependency: the mocked type's forwarded property, or a dependency
	/// its tree receives, which the leaf declares as it is passed.
	struct PassedParameter: Sendable {
		/// The parameter's name, its argument label.
		let name: String
		/// The parameter's type.
		let type: TypeDescription
		/// The dependency the leaf declares for it.
		let dependency: Dependency
		/// Whether the called mock builds the dependency when the call passes `nil` (`PublicMockParameter.isBuiltWhenNil`).
		let isBuiltWhenNil: Bool
		/// The wrapper the called mock builds when the call passes `nil`, for a lazily instantiated dependency it takes by
		/// value (`PublicMockParameter.builtWrapper`).
		var builtWrapper: Property?
		/// For a builder, the builder (`PublicMockParameter.builder`).
		let builder: SeamSignature.Builder?
	}

	/// The line before the call that names the mock's guard enum, so that a call generated from another signature
	/// than the mock's fails to compile there, with a comment saying what to do then.
	func guardLine(for concreteType: TypeDescription) -> String {
		"_ = \(concreteType.asSource).\(guardTypeName).self\(comment.lineEnd(for: concreteType))"
	}
}

extension ScopeGenerator.PublicMockTierOmission {
	/// `leafTierOmitsProvidedValue`: the error at the provider, with a note at each receiver of the parameter in the
	/// public mock's tree, worded by row 4b's formatter for a seam's omitted parameter.
	var sourceDiagnostics: [SourceDiagnostic] {
		let call = publicMockCall
		func name(_ type: TypeDescription) -> String {
			"`\(type.asSource)`"
		}
		let label = "`\(receivedProperty.label)`"
		let receivers = parameter.nestedOmission?.receivers ?? (call.receiversByLabel[receivedProperty.label] ?? []).filter { receiver in
			receiver.dependency.property.label == receivedProperty.label && receiver.dependency.source.isReceived
		}
		let receiverNames = receivers.map(\.declaringType).uniqued().map(name).joinedAsList
		let callerModule = call.callerModule.moduleName.map { "module `\($0)`" } ?? "this module"
		let caller = call.requirement == .packageUnverified ? "\(callerModule), which SafeDI cannot tell is in the same package," : callerModule
		let declaringModule = call.declaringModule.moduleName.map { " in module `\($0)`" } ?? ""
		let type = name(call.type)
		// A parameter on no tier needs the level of the call in the mock's tree that omits it.
		let neededLevel = AccessLevel.level(satisfying: parameter.nestedOmission?.requirement ?? call.requirement)
		let causeText = parameter.accessCause.map { " " + SeamAccessExplanation.causeSentence($0, receivers: receivers.map { SeamAccessExplanation.Receiver(declaringType: $0.declaringType, aliasProperty: nil, isInstantiateMethodParameter: false) }) } ?? ""
		var remedies = [String]()
		// A caller that needs `public` across a module SafeDI is told no package of needs only `package` if that module
		// belongs in the other's package, which reaches the parameter on a `package` tier and which the parameter's
		// `package` tier makes the likelier fix, so that remedy comes first. A parameter on no tier is omitted by a call
		// in the mock's tree, whose modules this call does not decide.
		if parameter.nestedOmission == nil, let packageNameRemedy = ModuleIdentity.packageNameRemedy(emitter: call.callerModule, declarer: call.declaringModule, declaredLevel: parameter.access) {
			remedies.append(packageNameRemedy)
		}
		let unverifiedPackage = call.requirement == .packageUnverified ? ", or `public` if the two modules are in different packages" : ""
		if case let .signatures(_, _, provers, _)? = parameter.accessCause, let first = provers.first, first.cap == nil {
			remedies.append("widen \(first.name) to `\(neededLevel.spelledOnGeneratedDeclaration)`\(unverifiedPackage)")
		}
		remedies += SeamAccessExplanation.causeRemedies(parameter.accessCause, neededLevel: neededLevel)
		remedies.append("stop providing \(label) on this path")
		let what: String
		if let nested = parameter.nestedOmission {
			// No tier takes the parameter: a call in the mock's tree omits it.
			let nestedCallerModule = nested.callerModule.moduleName.map { "module `\($0)`" } ?? "this module"
			let nestedCaller = nested.requirement == .packageUnverified ? "\(nestedCallerModule), which SafeDI cannot tell is in the same package," : nestedCallerModule
			let nestedReceiverNames = nested.receivers.map(\.declaringType).uniqued().map(name).joinedAsList
			what = "no mock SafeDI generated for \(type) takes it: \(type)’s mock tree calls the `\(nested.tier.spelledOnGeneratedDeclaration)` mock SafeDI generated for \(name(nested.type))\(nested.declaringModule.moduleName.map { " in module `\($0)`" } ?? ""), the narrowest one \(nestedCaller) can call, which takes \(label) only on its `\(nested.parameterAccess.spelledOnGeneratedDeclaration)` tier, so calling it would pass `nil` to \(nestedReceiverNames.isEmpty ? name(nested.type) : nestedReceiverNames), which the inline mock would hand \(label)."
		} else {
			what = "the `\(call.tier.spelledOnGeneratedDeclaration)` mock SafeDI generated for \(type)\(declaringModule), the narrowest one \(caller) can call, does not take it: `\(call.type.asSource).mock` takes \(label) only on its `\(parameter.access.spelledOnGeneratedDeclaration)` tier, so this call would pass `nil` to \(receiverNames.isEmpty ? type : receiverNames), which the inline mock would hand \(label)."
		}
		// A fill's field is the value the called mock hands the fill, which the called mock's tree built or its own `mock()`
		// was handed: the type does not provide it.
		let provider = providerIsHandedToFill
			? "\(name(providerDeclaringType))’s mock hands this fill `\(providerProperty.asSource)`"
			: "\(name(providerDeclaringType)) provides `\(providerProperty.asSource)`"
		let message = "\(provider), but \(what)\(causeText) \(SeamAccessExplanation.joined(remedies))"
		return [SourceDiagnostic(severity: .error, location: providerDeclarationLocation, message: message)]
			+ SeamAccessExplanation.declarationNotes(for: parameter.accessCause, neededLevel: neededLevel)
			+ receivers.map { receiver in
				SourceDiagnostic(
					severity: .note,
					location: receiver.dependency.declarationLocation,
					message: "`\(receiver.declaringType.asSource)` receives `\(receiver.dependency.property.asSource)` here.",
				)
			}
	}
}

extension ScopeGenerator {
	/// A call of another module's public mock, in a mock tree, that the calling module's mock condition does not reach.
	struct PublicMockCallUnderOtherMockCondition: Sendable {
		let publicMockCall: PublicMockCall
		/// The dependency that leads to the call.
		let referenceLocation: Dependency.DeclarationLocation?

		var sourceDiagnostic: SourceDiagnostic {
			func spelling(of mockCondition: MockCondition) -> String {
				mockCondition.conditionalCompilation.map { "compile under `#if \($0)`" } ?? "compile unconditionally"
			}
			let declaringCondition = publicMockCall.declaringModuleMockCondition.conditionalCompilation.map { "`#if \($0)`" } ?? "no condition"
			let declaringModule = publicMockCall.declaringModule.moduleName.map { "`\($0)`" } ?? "its module"
			return SourceDiagnostic(
				severity: .error,
				location: referenceLocation,
				message: "`\(publicMockCall.type.asSource).mock()` is generated under \(declaringCondition) in \(declaringModule), but this module’s mocks \(spelling(of: publicMockCall.callerModuleMockCondition)). Give both modules one `mockConditionalCompilation`.",
			)
		}
	}
}
