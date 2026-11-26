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

/// What a module that calls another module's public mock (`generateMock: .public`) reads of the mock's plan: the
/// parameters of its tiers, its guard, its builders and the receivers a diagnostic about an omitted parameter notes.
/// The module that generates the mock computes it once and its module info file carries it
/// (`StoredPublicMockPlans`), beside the signatures of its seams, so a module above reads it rather than building the
/// mock's whole tree again. A module that computes a plan itself (the SwiftPM plugin's target graph) reads it through
/// this same type, so no caller reads of a plan what a file does not store.
public struct StoredPublicMockPlan: Codable, Sendable {
	public init(
		mockedType: TypeDescription,
		parameters: [Parameter],
		noTierParameters: [Parameter],
		tiers: [AccessLevel],
		guardTypeName: String,
		holes: [SeamSignature.Hole],
		builders: [SeamSignature.Builder],
		scopeEnums: [SeamSignature.ScopeEnum],
		places: SeamSignature.Places = SeamSignature.Places(levels: [], cases: []),
		caseIndexByHole: [Int] = [],
		receivers: [Receiver],
		typesDeclaredEscaping: [TypeDescription],
	) {
		self.mockedType = mockedType
		self.parameters = parameters
		self.noTierParameters = noTierParameters
		self.tiers = tiers
		self.guardTypeName = guardTypeName
		self.holes = holes
		self.builders = builders
		self.scopeEnums = scopeEnums
		self.places = places
		self.caseIndexByHole = caseIndexByHole
		self.receivers = receivers
		self.typesDeclaredEscaping = typesDeclaredEscaping
	}

	/// The type whose public mock the plan is of.
	public let mockedType: TypeDescription
	/// The parameters of the narrowest tier, which takes every parameter, in signature order.
	public let parameters: [Parameter]
	/// The parameters on no tier, which a caller's leaf declares as it declares an omitted parameter.
	public let noTierParameters: [Parameter]
	/// The tiers, widest first.
	public let tiers: [AccessLevel]
	/// The empty enum every call names, whose name hashes the signature.
	public let guardTypeName: String
	/// Every place the builders `mock()` takes reach, in the order they reach them.
	public let holes: [SeamSignature.Hole]
	/// The builders `mock()` takes.
	public let builders: [SeamSignature.Builder]
	/// Every enum the builders reach.
	public let scopeEnums: [SeamSignature.ScopeEnum]
	/// The mock's place graph by case, beside `holes` while readers move to it; empty unless the place graph is drafted
	/// (`SeamSignature.places`).
	public let places: SeamSignature.Places
	/// The case of each of `holes` in `places`, -1 for a place a call passes up; empty where `places` is.
	public let caseIndexByHole: [Int]
	/// The declarations in the mock's tree that receive a parameter a tier can omit – one narrower than `public`, or on
	/// no tier – in tree order, which the error about a value such a tier drops notes. No other receiver is read.
	public let receivers: [Receiver]
	/// The types of the parameters that the mock's tree declares `@escaping`, sorted.
	public let typesDeclaredEscaping: [TypeDescription]

	/// The parameters the tier at `tier` takes, under that tier's names.
	func parameters(ofTier tier: AccessLevel) -> [Parameter] {
		parameters.filter { $0.access >= tier }.map { $0.atTier(tier) }
	}

	/// `receivers`, by the label of the dependency each receives.
	var receiversByLabel: [String: [Receiver]] {
		Dictionary(grouping: receivers) { $0.dependency.property.label }
	}

	/// A parameter of a public mock's `mock()`, as a caller reads it.
	public struct Parameter: Codable, Sendable {
		public init(
			name: String,
			narrowerTierNames: [AccessLevel: String],
			type: TypeDescription,
			access: AccessLevel,
			accessCause: TypeAccessProof.Cause?,
			nestedOmission: NestedOmission?,
			role: Role,
			isBuiltWhenNil: Bool,
			builtWrapper: Property?,
			builder: SeamSignature.Builder?,
		) {
			self.name = name
			self.narrowerTierNames = narrowerTierNames
			self.type = type
			self.access = access
			self.accessCause = accessCause
			self.nestedOmission = nestedOmission
			self.role = role
			self.isBuiltWhenNil = isBuiltWhenNil
			self.builtWrapper = builtWrapper
			self.builder = builder
		}

		/// The parameter's name, which is also its argument label: the widest tier's that takes it.
		public let name: String
		/// For a builder, the name each narrower tier takes it under, where it differs from `name`.
		public let narrowerTierNames: [AccessLevel: String]
		/// The parameter's type as the signature spells it.
		public let type: TypeDescription
		/// The narrowest access its types are proven at, which is the narrowest tier that takes it.
		public let access: AccessLevel
		/// How the narrowest of its types is proven, when that is narrower than `public`.
		public let accessCause: TypeAccessProof.Cause?
		/// For a parameter on no tier, the call in the mock's tree of another module's public mock whose tier omits it.
		public let nestedOmission: NestedOmission?
		/// What the parameter stands for.
		public let role: Role
		/// For a received dependency taken as `T? = nil`, whether the mock builds it when passed `nil`.
		public let isBuiltWhenNil: Bool
		/// For a dependency the mock builds when passed `nil` as a lazily instantiated wrapper, taken by value, the wrapper.
		public let builtWrapper: Property?
		/// For a builder, the builder.
		public let builder: SeamSignature.Builder?

		/// The parameter as the tier at `tier` takes it, under that tier's name.
		func atTier(_ tier: AccessLevel) -> Parameter {
			let tierName = narrowerTierNames[tier] ?? name
			let tierRole: Role = if case let .received(property, isRequired) = role, builder != nil {
				.received(Property(label: tierName, typeDescription: property.typeDescription), isRequired: isRequired)
			} else {
				role
			}
			return Parameter(
				name: tierName,
				narrowerTierNames: [:],
				type: type,
				access: access,
				accessCause: accessCause,
				nestedOmission: nestedOmission,
				role: tierRole,
				isBuiltWhenNil: isBuiltWhenNil,
				builtWrapper: builtWrapper,
				builder: builder?.atTier(tier),
			)
		}
	}

	/// What a parameter of a public mock stands for, which decides what a mock tree that calls the public mock passes
	/// for it.
	public enum Role: Codable, Sendable {
		/// The mocked type's `@Forwarded` property, which a caller building the type with an `Instantiator` is handed.
		case forwarded(Property)
		/// A default-valued parameter of the type's construction, which a calling mock tree never passes.
		case constructionDefault
		/// A dependency the mocked type's tree receives, received as `property`: required where the mock cannot build
		/// it, and otherwise taken as `T? = nil`, which the mock builds when `nil`.
		case received(Property, isRequired: Bool)
		/// The `SafeDIOverrides` of the mock's tree.
		case overrides
		/// A builder the mock takes optional, `= nil`, for the places of one hole type and family its calls of other modules'
		/// public mocks fill (`ScopeGenerator.FilledCall`), which replaces those fills where it is passed. Where the mock also
		/// takes a builder of the family for places it passes up (`joinedBuilder`, that builder's enum), `mock()` passes that
		/// builder on to it and takes no parameter of its own for it, so that one builder a person writes serves every place.
		/// A generated caller never passes it: the called mock's own fills build the places.
		case optionalBuilder(joinedBuilder: SeamSignature.ScopeEnum.Key?)
	}

	/// A call of another module's public mock, in a public mock's tree, whose tier omits a parameter that nothing else
	/// in the tree receives, so that no tier of the public mock takes it.
	public struct NestedOmission: Codable, Sendable {
		public init(
			type: TypeDescription,
			tier: AccessLevel,
			parameterAccess: AccessLevel,
			declaringModule: ModuleIdentity,
			callerModule: ModuleIdentity,
			requirement: AccessRequirement,
			receivers: [Receiver],
		) {
			self.type = type
			self.tier = tier
			self.parameterAccess = parameterAccess
			self.declaringModule = declaringModule
			self.callerModule = callerModule
			self.requirement = requirement
			self.receivers = receivers
		}

		/// The type whose public mock the call calls.
		public let type: TypeDescription
		/// The tier the call reaches.
		public let tier: AccessLevel
		/// The tier of the called mock that takes the parameter.
		public let parameterAccess: AccessLevel
		public let declaringModule: ModuleIdentity
		public let callerModule: ModuleIdentity
		public let requirement: AccessRequirement
		/// The declarations in the called mock's tree that receive the parameter.
		public let receivers: [Receiver]
	}

	/// A declaration in a public mock's tree that receives a dependency.
	public struct Receiver: Codable, Sendable {
		public init(declaringType: TypeDescription, dependency: Dependency) {
			self.declaringType = declaringType
			self.dependency = dependency
		}

		public let declaringType: TypeDescription
		public let dependency: Dependency
	}
}

/// The plans a module info file carries of the public mocks its module declares, read when a run first calls one of
/// them.
public struct StoredPublicMockPlans: Sendable {
	public init(compilesGeneratedMocks: Bool, read: @escaping @Sendable () throws -> [StoredPublicMockPlan]) {
		self.compilesGeneratedMocks = compilesGeneratedMocks
		self.read = read
	}

	/// Whether the run that computed the plans compiled the mocks it generated, which a plan depends on: a run that
	/// differs in it computes the plans itself.
	public let compilesGeneratedMocks: Bool
	/// Decodes the plans, which throws only for a file a SafeDITool wrote malformed.
	public let read: @Sendable () throws -> [StoredPublicMockPlan]
}
