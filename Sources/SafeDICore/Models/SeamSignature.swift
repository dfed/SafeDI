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

/// The initializer SafeDI generates for a seam: a type declared with `generateDependencyTree: true`, whose
/// dependency tree the module that declares it generates, and which every other tree calls instead of building the
/// tree again.
///
/// The signature is computed from the seam's declaration, its tree, and the declarations the seam's module can see,
/// by the seam's module and by every module that calls the seam alike, so the generated call matches the generated
/// initializer. `guardTypeName` names an empty enum the seam's module generates beside the initializer and every
/// generated call refers to, so two computations that disagree fail to compile at the call rather than pass `nil`
/// where a value was expected.
///
/// The signature and its parameters and receivers carry diagnostic payload – where each receive is declared – so none
/// is `Equatable`: a comparison for meaning goes through a projection that states what it compares, `callShape` for
/// what a call depends on and `settledContent` for what settling a module's seams solves for.
public struct SeamSignature: Sendable {
	/// A receive inside a seam's tree that a pass-through parameter fulfills: what a seam that passes the parameter
	/// on reports when a tier of its own cannot take it.
	public struct Receiver: Sendable {
		public init(property: Property, declaringType: TypeDescription, declarationLocation: Dependency.DeclarationLocation?, access: AccessLevel, aliasProperty: Property? = nil, isInstantiateMethodParameter: Bool = false) {
			self.property = property
			self.declaringType = declaringType
			self.declarationLocation = declarationLocation
			self.access = access
			self.aliasProperty = aliasProperty
			self.isInstantiateMethodParameter = isInstantiateMethodParameter
		}

		/// The property the receive takes from outside the seam: the received property, or an alias's fulfilling
		/// property.
		public let property: Property
		/// The alias's own property, when the receive is an alias's fulfilling property, or `nil` for a `@Received`
		/// declaration: a seam that passes the parameter on reports a read of it as the alias or receive it is. In
		/// memory only, as the whole signature is: each module computes a seam's signature from the declarations it
		/// reads, and module info carries no signature.
		public let aliasProperty: Property?
		/// The type that declares the receive.
		public let declaringType: TypeDescription
		public let declarationLocation: Dependency.DeclarationLocation?
		/// The access the proof gives the parameter that passes the receive, over the declarations the signature is
		/// computed from: what a caller can pass it at.
		public let access: AccessLevel
		/// Whether the receive is a parameter of an extension's `instantiate(…)` method, which is always required: it
		/// has no only-if-available form.
		public let isInstantiateMethodParameter: Bool
	}

	/// The call of a nested seam's tier that omits a parameter on no tier of the seam whose tree makes the call, which
	/// an error about a caller holding a value for that parameter names.
	public struct NestedSeamCall: Sendable {
		public init(seamType: TypeDescription, seamModuleName: String?, tier: AccessLevel, requirement: AccessRequirement, callerModuleName: String?, parameterTierAccess: AccessLevel?, receivingTypes: [TypeDescription]) {
			self.seamType = seamType
			self.seamModuleName = seamModuleName
			self.tier = tier
			self.requirement = requirement
			self.callerModuleName = callerModuleName
			self.parameterTierAccess = parameterTierAccess
			self.receivingTypes = receivingTypes
		}

		/// The nested seam's concrete type.
		public let seamType: TypeDescription
		/// The module that declares the nested seam, as far as SafeDI knows it.
		public let seamModuleName: String?
		/// The level of the nested seam's tier the call reaches.
		public let tier: AccessLevel
		/// What the module that makes the call needs of the nested seam's declarations.
		public let requirement: AccessRequirement
		/// The module that makes the call, as far as SafeDI knows it.
		public let callerModuleName: String?
		/// The level of the nested seam's tier that takes the parameter, or `nil` when none of its tiers does.
		public let parameterTierAccess: AccessLevel?
		/// The types inside the nested seam that receive the parameter, in tree order, each once.
		public let receivingTypes: [TypeDescription]
	}

	/// A parameter of the generated initializer.
	public struct Parameter: Sendable {
		public init(property: Property, isPassThrough: Bool, access: AccessLevel, tierAccess: AccessLevel? = nil, defaultsToNil: Bool, receivers: [Receiver] = [], accessCause: TypeAccessProof.Cause? = nil, nestedSeamCall: NestedSeamCall? = nil, otherInitializerArgumentsAccess: AccessLevel = .public) {
			self.property = property
			self.isPassThrough = isPassThrough
			self.access = access
			self.tierAccess = tierAccess ?? access
			self.defaultsToNil = defaultsToNil
			self.receivers = receivers
			self.accessCause = accessCause
			self.nestedSeamCall = nestedSeamCall
			self.otherInitializerArgumentsAccess = otherInitializerArgumentsAccess
		}

		/// The parameter's label and type. A pass-through that some receiver in the tree requires has the type the
		/// receiver declares – the optional type it is declared with where every receiver that requires it declares
		/// it optional, since the property the caller's tree declares may be optional too; one every receiver
		/// receives only if available has the optional form of that type, and defaults to `nil`.
		public let property: Property
		/// Whether the parameter passes a property the tree receives from outside the seam, rather than one of the
		/// seam's own `@Received` or `@Forwarded` properties.
		public let isPassThrough: Bool
		/// How visible the parameter's type is, as far as SafeDI can prove it from the declarations the signature is
		/// computed from (`TypeAccessProof`): the narrowest proof among the types it names. Uncapped by the seam's
		/// type, so a seam reached through another, whose computation proves the parameter again over its own
		/// declarations, can tell what its own tiers can take.
		public let access: AccessLevel
		/// How the narrowest type the parameter names is proven, which a diagnostic explains, or `nil` when every type it
		/// names is `public`.
		public let accessCause: TypeAccessProof.Cause?
		/// The access that decides which tiers take the parameter and the guard: `access`, capped at the seam's
		/// type, since no tier is wider than the type. A tier of the generated initializer takes the parameter only
		/// when the tier's level is no wider.
		public let tierAccess: AccessLevel

		/// Whether the generated initializer defaults the parameter to `nil`: a pass-through every receiver receives
		/// only if available, or the seam's own `@Received(onlyIfAvailable: true)` property. A pass-through some
		/// receiver requires, an own required `@Received` and an own `@Forwarded` have no default, optional type or
		/// not.
		public let defaultsToNil: Bool
		/// The receives inside the seam's tree a pass-through fulfills, in tree order, each with the access that
		/// bounds it, so a seam that passes the parameter on names the receiver that caps it, not this seam, when a
		/// tier of its own cannot take it. Empty for one of the seam's own properties, which its own initializer
		/// receives.
		public let receivers: [Receiver]
		/// For a parameter on no tier (`SeamSignature.noTierParameters`), the nested seam call that omits it, else `nil`.
		public let nestedSeamCall: NestedSeamCall?
		/// For one of the seam's own properties, the narrowest access the declarations prove for the types of the seam's
		/// own initializer's other arguments: widening that initializer makes it more visible only up to that access, so a
		/// remedy offers it only for a level no wider. `public` for a pass-through.
		public let otherInitializerArgumentsAccess: AccessLevel
	}

	public init(seamType: TypeDescription, parameters: [Parameter], tiers: [AccessLevel], noTierParameters: [Parameter] = []) {
		self.seamType = seamType
		self.parameters = parameters
		self.tiers = tiers
		self.noTierParameters = noTierParameters
	}

	/// The seam's concrete type.
	public let seamType: TypeDescription
	/// The parameters of the narrowest tier, which takes every one: the seam's own `@Received` and `@Forwarded`
	/// properties in declaration order, then the pass-throughs in label order.
	public let parameters: [Parameter]
	/// The access level of each generated initializer, widest first: the widest is at the seam type's effective
	/// access, as its enclosing types limit it, and each narrower one at a narrower `tierAccess` among the parameters.
	/// Each tier but the narrowest omits every parameter whose `tierAccess` is narrower than the tier and calls the
	/// next narrower tier; the narrowest tier builds the tree and calls the seam's own initializer, which may be
	/// narrower than it: Swift checks a member's signature against its access, never its body.
	public let tiers: [AccessLevel]

	/// The properties the seam's tree receives only through a nested seam's call that omits them – a tier of that seam
	/// that does not take them, or a parameter on none of its tiers – which no tier of this seam takes either: a caller
	/// holding a value for one would have it dropped, which is reported at the caller. Each defaults to `nil`, takes no
	/// part in the guard or a call's shape, and is never in scope inside the seam's own tree, which passes the nested
	/// seam `nil` for it, as the tier it calls does.
	public let noTierParameters: [Parameter]

	/// The parameters the tier at `level` takes.
	public func parameters(ofTierAt level: AccessLevel) -> [Parameter] {
		parameters.filter { $0.tierAccess >= level }
	}

	/// What a call of the generated initializer depends on: each parameter's label, type spelled without `any`, tier
	/// access and whether it defaults to `nil`, and the tiers. Two signatures with one call shape generate the same
	/// guard and the same calls, whatever their receivers and uncapped access. The guard hashes the parameters' fields
	/// and not the tiers: both sides derive the tiers from the parameters' tier accesses, which it hashes, and from the
	/// level of the seam's own initializer, which both read from the seam's declaration.
	public struct CallShape: Hashable, Sendable {
		public struct Parameter: Hashable, Sendable {
			public init(_ parameter: SeamSignature.Parameter) {
				label = parameter.property.label
				type = parameter.property.typeDescription.withoutAny.asSource
				tierAccess = parameter.tierAccess
				defaultsToNil = parameter.defaultsToNil
			}

			public let label: String
			public let type: String
			public let tierAccess: AccessLevel
			public let defaultsToNil: Bool
		}

		public let parameters: [Parameter]
		public let tiers: [AccessLevel]
	}

	public var callShape: CallShape {
		CallShape(parameters: parameters.map(CallShape.Parameter.init), tiers: tiers)
	}

	/// What settling a module's seams solves for: each parameter – its property, whether it is a pass-through, its
	/// access, tier access and default – with its receivers as a set, and the tiers. Never the receivers' order, which
	/// a seam's tree meets differently on every pass when it carries the receivers of a seam that carries its own,
	/// nor where a receive is declared, which a diagnostic reads and the declaring type and property already decide.
	public struct SettledContent: Hashable, Sendable {
		public struct Parameter: Hashable, Sendable {
			public let property: Property
			public let isPassThrough: Bool
			public let access: AccessLevel
			public let tierAccess: AccessLevel
			public let defaultsToNil: Bool
			public let receivers: Set<Receiver>
		}

		public struct Receiver: Hashable, Sendable {
			public let property: Property
			public let declaringType: TypeDescription
			public let access: AccessLevel
		}

		public let parameters: [Parameter]
		public let tiers: [AccessLevel]
		public let noTierParameters: [Parameter]
	}

	public var settledContent: SettledContent {
		func settledContent(of parameters: [Parameter]) -> [SettledContent.Parameter] {
			parameters.map { parameter in
				SettledContent.Parameter(
					property: parameter.property,
					isPassThrough: parameter.isPassThrough,
					access: parameter.access,
					tierAccess: parameter.tierAccess,
					defaultsToNil: parameter.defaultsToNil,
					receivers: Set(parameter.receivers.map { receiver in
						SettledContent.Receiver(property: receiver.property, declaringType: receiver.declaringType, access: receiver.access)
					}),
				)
			}
		}
		return SettledContent(parameters: settledContent(of: parameters), tiers: tiers, noTierParameters: settledContent(of: noTierParameters))
	}

	/// The name of the empty enum the seam's module generates in an extension of the seam, which every generated
	/// call refers to. It hashes each parameter's fields of `callShape` – label, type spelled without `any` (as the
	/// compiler and `TypeDescription ==` treat `any P` and `P` as one type), tier access, and whether it defaults to
	/// `nil` – so a call generated from another computation of the signature names an enum the seam's module did not
	/// generate. The receivers are not hashed: they name declarations, and change nothing a call passes.
	public var guardTypeName: String {
		var hash = SeamSignatureHash()
		for parameter in callShape.parameters {
			hash.combine(parameter.label)
			hash.combine(parameter.type)
			hash.combine(parameter.tierAccess.spelledOnGeneratedDeclaration)
			hash.combine(parameter.defaultsToNil ? "= nil" : "")
		}
		return "\(ReservedName.builderFunctionNamePrefix)\(seamType.asIdentifier)_\(hash.hexadecimal)"
	}
}

/// A 64-bit FNV-1a hash, which is the same on every platform and in every process, unlike `Hasher`, which Swift
/// seeds per process.
struct SeamSignatureHash {
	private(set) var value: UInt64 = 0xCBF29CE484222325

	mutating func combine(_ text: String) {
		for byte in text.utf8 {
			value ^= UInt64(byte)
			value = value &* 0x00000100000001B3
		}
		// A separator, so that `ab` then `c` differs from `a` then `bc`.
		value ^= 0xFF
		value = value &* 0x00000100000001B3
	}

	/// The hash as sixteen uppercase hexadecimal digits.
	var hexadecimal: String {
		let digits = String(value, radix: 16, uppercase: true)
		return String(repeating: "0", count: 16 - digits.count) + digits
	}
}

/// How a tree that reaches a seam calls it: the parameters of the tier it calls, the enum the call refers to, and
/// the comment the call carries under the SwiftPM plugin, which cannot know that the seam's module generated the
/// initializer. A seam whose module SafeDI does not know is built inline and gets no call.
public struct SeamCall: Sendable {
	public init(
		parameters: [SeamSignature.Parameter],
		guardTypeName: String,
		carriesPluginComment: Bool,
		unreachableTierIsReported: Bool = false,
		omittedParameters: [SeamSignature.Parameter] = [],
		noTierParameters: [SeamSignature.Parameter] = [],
		tier: AccessLevel = .internal,
		requirement: AccessRequirement = .internal,
		seamModuleName: String? = nil,
		callerModuleName: String? = nil,
	) {
		self.parameters = parameters
		self.guardTypeName = guardTypeName
		self.carriesPluginComment = carriesPluginComment
		self.unreachableTierIsReported = unreachableTierIsReported
		self.omittedParameters = omittedParameters
		self.noTierParameters = noTierParameters
		self.tier = tier
		self.requirement = requirement
		self.seamModuleName = seamModuleName
		self.callerModuleName = callerModuleName
	}

	/// The parameters of the tier the call passes, each at the access it was received at inside the seam, which a
	/// seam that reaches this one passes on at that access.
	public let parameters: [SeamSignature.Parameter]
	/// The `SeamSignature.guardTypeName` of the signature the call was generated from.
	public let guardTypeName: String
	/// Whether the call carries a comment saying what to do when it does not compile. Under the SwiftPM plugin,
	/// which cannot tell whether a dependency target applies the plugin, every call to another module's seam carries
	/// it, saying to add the plugin to the target that declares the seam. A module read from a `.safedi` file ran
	/// `generate`, which generated the initializer, so a call to its seam carries none.
	public let carriesPluginComment: Bool
	/// The parameters of the seam's signature the called tier does not take, which the call passes `nil` for: a caller
	/// whose tree holds a value for one is reported, since built inline the tree would hand the value on.
	public let omittedParameters: [SeamSignature.Parameter]
	/// The seam's parameters on no tier (`SeamSignature.noTierParameters`), which the call passes `nil` for too.
	public let noTierParameters: [SeamSignature.Parameter]
	/// The level of the tier called.
	public let tier: AccessLevel
	/// What the calling module needs of the seam's declarations.
	public let requirement: AccessRequirement
	/// The module that declares the seam, as far as SafeDI knows it.
	public let seamModuleName: String?
	/// The module that makes the call, as far as SafeDI knows it.
	public let callerModuleName: String?
	/// Whether the caller's module reaches no tier of the call and the check of every construction is certain to
	/// report the declaration whose widening makes a tier reachable: the seam's type, or a type enclosing it, which
	/// every tier's access is capped at, fails the requirement the caller's module puts on it. A seam whose tree makes
	/// such a call takes the call's parameters as pass-throughs but reports no omission of its own for them: the
	/// report is the type's. `false` where the caller reaches a tier, where the check may pass the type – one whose
	/// module's package the caller cannot tell from its own, which `package` access is assumed to reach – and where the
	/// caller runs no check: the omission is then reported as any other receive's is.
	public let unreachableTierIsReported: Bool
}

/// What a run of `generate` tells the dependency tree generator about the seams among the declarations it reads.
public struct SeamResolution: Sendable {
	/// A seam declared in another module, which that module's run of `generate` generated the initializer of.
	public struct ForeignSeam: Sendable {
		public init(declaringModule: ModuleIdentity, missingDependencyModuleName: String? = nil, visibleInstantiables: [TypeDescription: Instantiable], callCarriesPluginComment: Bool, declaringModuleMockCondition: MockCondition? = nil) {
			self.declaringModule = declaringModule
			self.missingDependencyModuleName = missingDependencyModuleName
			self.visibleInstantiables = visibleInstantiables
			self.callCarriesPluginComment = callCarriesPluginComment
			self.declaringModuleMockCondition = declaringModuleMockCondition
		}

		/// The module that declares the seam, whose name is known: a seam whose module is unknown is built inline.
		public let declaringModule: ModuleIdentity
		/// The name of a module the declaring module depends on whose declarations this run was not given, or `nil`
		/// when every one was: a seam's signature is computed from what its module sees, so a reached seam of a
		/// module with one missing is an error, while an unreached one is not.
		public let missingDependencyModuleName: String?
		/// The declarations the seam's module can see, resolved as `generate` resolves them, from which the seam's
		/// signature is computed exactly as that module computed it. The seams of one module share one map.
		public let visibleInstantiables: [TypeDescription: Instantiable]
		/// See `SeamCall.carriesPluginComment`.
		public let callCarriesPluginComment: Bool
		/// The mock condition of the seam's module, when this run read that module's files under its own mock condition,
		/// as it does under the SwiftPM plugin's target graph: `visibleInstantiables` then holds the module's mock-only
		/// declarations as this run's condition selects them, which is how the module reads them only when the two
		/// conditions are spelled the same. `nil` when this run read the module's module info, which holds its
		/// declarations as the module read them.
		public let declaringModuleMockCondition: MockCondition?
	}

	public init(currentModule: ModuleIdentity, currentModuleMockCondition: MockCondition = MockCondition("DEBUG"), generatedSeams: Set<TypeDescription>, foreignSeams: [TypeDescription: ForeignSeam], callersComputeFromTargetGraph: Bool = false, callersVisibleInstantiables: [TypeDescription: Instantiable]? = nil) {
		self.currentModule = currentModule
		self.currentModuleMockCondition = currentModuleMockCondition
		self.generatedSeams = generatedSeams
		self.foreignSeams = foreignSeams
		self.callersComputeFromTargetGraph = callersComputeFromTargetGraph
		self.callersVisibleInstantiables = callersVisibleInstantiables
	}

	/// No seam is treated as one: every type is built inline, as before seams existed.
	public static let none = SeamResolution(currentModule: ModuleIdentity(moduleName: nil, packageName: nil), generatedSeams: [], foreignSeams: [:])

	/// The module `generate` generates code for, as far as it is known, which decides which tier of a foreign seam's
	/// generated initializer its trees call.
	public let currentModule: ModuleIdentity
	/// The mock condition of the module `generate` generates code for, under which it read every file it parsed.
	public let currentModuleMockCondition: MockCondition
	/// The concrete types of the seams the module's own files declare, whose initializers this run generates.
	public let generatedSeams: Set<TypeDescription>
	/// The seams other modules declare, by concrete type. A seam declared with `generateDependencyTree: true` that is
	/// in neither set – one whose module SafeDI does not know: declared in a directory a `#SafeDIConfiguration` adds,
	/// in a `.safedi` written without `--module-name`, or in a file no target of the plugin's graph lists – has no
	/// set of declarations its signature could be computed from, so every tree builds it inline, as any other type.
	public let foreignSeams: [TypeDescription: ForeignSeam]
	/// Whether the modules that call this module's seams compute their signatures from the build system's target
	/// graph, which lists the files of each target: under the SwiftPM plugin, every seam's tree must then reach only
	/// declarations the graph attributes to a module, since a caller cannot see a declaration in a directory this
	/// module's `#SafeDIConfiguration` adds, and its call would name an enum the seam's module did not generate.
	public let callersComputeFromTargetGraph: Bool
	/// The declarations the modules that call this module's seams see, resolved as `generate` resolves them, when
	/// they differ from what this run sees, else `nil`: this module's own files and the modules its module info
	/// names, without a dependent module info that names no module (one generated without `--module-name`), or,
	/// under the target graph, the files the graph attributes to this module and the modules it depends on, without
	/// the directories this module's `#SafeDIConfiguration` adds. A seam this module generates whose signature,
	/// computed over these declarations, differs from the one computed over what this run sees is an error at the
	/// seam: the callers' calls would not match the initializer. `nil` too when this module's name is unknown, since
	/// every caller then builds its seams inline and computes no signature.
	public let callersVisibleInstantiables: [TypeDescription: Instantiable]?

	/// Whether any seam is treated as one, which is when the dependency tree generator builds a second map of scopes.
	public var isEmpty: Bool {
		generatedSeams.isEmpty && foreignSeams.isEmpty
	}
}

/// The condition a module guards its generated mocks and its mock-only declarations with: its
/// `#SafeDIConfiguration(mockConditionalCompilation:)`, `DEBUG` for a module that declares no configuration.
public struct MockCondition: Hashable, Sendable {
	public init(_ conditionalCompilation: String?) {
		self.conditionalCompilation = conditionalCompilation
	}

	/// The condition, or `nil` for a module whose mocks no condition guards.
	public let conditionalCompilation: String?
}

extension Instantiable {
	/// The comment a generated call to a seam carries where SafeDI cannot know that the seam's module generated the
	/// initializer it calls. See `SeamCall.carriesPluginComment`.
	public static func seamCallPluginComment(for seamType: TypeDescription) -> String {
		"// If this line does not compile, add the SafeDI plugin to the target that declares \(seamType.asSource)."
	}
}
