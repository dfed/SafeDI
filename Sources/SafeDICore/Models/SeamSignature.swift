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
		public init(property: Property, declaringType: TypeDescription, declarationLocation: Dependency.DeclarationLocation?, access: AccessLevel, accessIsCappedByInitializer: Bool, aliasProperty: Property? = nil) {
			self.property = property
			self.declaringType = declaringType
			self.declarationLocation = declarationLocation
			self.access = access
			self.accessIsCappedByInitializer = accessIsCappedByInitializer
			self.aliasProperty = aliasProperty
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
		/// The access of the initializer that declares the receive, which bounds how widely the parameter's type is
		/// visible.
		public let access: AccessLevel
		/// What to widen for the receive to be passed at a wider access: the initializer that declares it, when its
		/// effective access is narrower than its type's, else the type or the type enclosing it, which caps it.
		public let accessIsCappedByInitializer: Bool
	}

	/// A parameter of the generated initializer.
	public struct Parameter: Sendable {
		public init(property: Property, isPassThrough: Bool, access: AccessLevel, tierAccess: AccessLevel? = nil, defaultsToNil: Bool, receivers: [Receiver] = []) {
			self.property = property
			self.isPassThrough = isPassThrough
			self.access = access
			self.tierAccess = tierAccess ?? access
			self.defaultsToNil = defaultsToNil
			self.receivers = receivers
		}

		/// The parameter's label and type. A pass-through that some receiver in the tree requires has the type the
		/// receiver declares – the optional type it is declared with where every receiver that requires it declares
		/// it optional, since the property the caller's tree declares may be optional too; one every receiver
		/// receives only if available has the optional form of that type, and defaults to `nil`.
		public let property: Property
		/// Whether the parameter passes a property the tree receives from outside the seam, rather than one of the
		/// seam's own `@Received` or `@Forwarded` properties.
		public let isPassThrough: Bool
		/// The widest access level among the initializers of the types that declare the receives the parameter
		/// fulfills, which bounds how widely the parameter's type is visible. Uncapped, so a seam reached through
		/// another passes the parameter on at the access its receivers prove (`SeamCall.parameters`), whatever the
		/// inner seam's type's access.
		public let access: AccessLevel
		/// The access that decides which tiers take the parameter and the guard: `access`, capped at the seam's
		/// type, since no tier is wider than the type. A tier of the generated initializer takes the parameter only
		/// when the tier's level is no wider.
		public let tierAccess: AccessLevel

		/// Whether the generated initializer defaults the parameter to `nil`: a pass-through every receiver receives
		/// only if available. A pass-through some receiver requires has no default, optional type or not.
		public let defaultsToNil: Bool
		/// The receives inside the seam's tree a pass-through fulfills, in tree order, each with the access that
		/// bounds it, so a seam that passes the parameter on names the receiver that caps it, not this seam, when a
		/// tier of its own cannot take it. Empty for one of the seam's own properties, which its own initializer
		/// receives.
		public let receivers: [Receiver]
	}

	public init(seamType: TypeDescription, parameters: [Parameter], tiers: [AccessLevel]) {
		self.seamType = seamType
		self.parameters = parameters
		self.tiers = tiers
	}

	/// The seam's concrete type.
	public let seamType: TypeDescription
	/// The parameters of the narrowest tier, which takes every one: the seam's own `@Received` and `@Forwarded`
	/// properties in declaration order, then the pass-throughs in label order.
	public let parameters: [Parameter]
	/// The access level of each generated initializer, widest first. Each tier but the narrowest omits every
	/// parameter whose `tierAccess` is narrower than the tier and calls the next narrower tier; the narrowest tier
	/// builds the tree and calls the seam's own initializer, which may be narrower than it: Swift checks a member's
	/// signature against its access, never its body.
	public let tiers: [AccessLevel]

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
			public let accessIsCappedByInitializer: Bool
		}

		public let parameters: [Parameter]
		public let tiers: [AccessLevel]
	}

	public var settledContent: SettledContent {
		SettledContent(
			parameters: parameters.map { parameter in
				SettledContent.Parameter(
					property: parameter.property,
					isPassThrough: parameter.isPassThrough,
					access: parameter.access,
					tierAccess: parameter.tierAccess,
					defaultsToNil: parameter.defaultsToNil,
					receivers: Set(parameter.receivers.map { receiver in
						SettledContent.Receiver(property: receiver.property, declaringType: receiver.declaringType, access: receiver.access, accessIsCappedByInitializer: receiver.accessIsCappedByInitializer)
					}),
				)
			},
			tiers: tiers,
		)
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
	public init(parameters: [SeamSignature.Parameter], guardTypeName: String, carriesPluginComment: Bool, receiversCappingTier: [Instantiable] = [], unreachableTierIsReported: Bool = false) {
		self.parameters = parameters
		self.guardTypeName = guardTypeName
		self.carriesPluginComment = carriesPluginComment
		self.receiversCappingTier = receiversCappingTier
		self.unreachableTierIsReported = unreachableTierIsReported
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
	/// When the caller's module can reach no tier, the types whose initializers receive a required parameter of the
	/// tier called at a level the caller cannot reach: a wider tier would omit the parameter, so they must widen with
	/// the seam's own initializer. Empty when the caller reaches the tier.
	public let receiversCappingTier: [Instantiable]
	/// Whether the caller's module reaches no tier of the call and the check of every construction is certain to
	/// report a declaration whose widening makes a tier reachable: the leaf's initializer is the seam's own, which
	/// fails the requirement as every tier does, or every receiver capping the tier fails the requirement its own
	/// module puts on the caller. A seam whose tree makes such a call takes the call's parameters as pass-throughs
	/// but reports no omission of its own for them: the report is the one the tree built inline gets. `false` where
	/// the caller reaches a tier, where the check may pass a capping receiver – one whose module's package the caller
	/// cannot tell from its own, which `package` access is assumed to reach, or one the caller's declarations lack –
	/// and where the caller runs no check: the omission is then reported as any other receive's is.
	public let unreachableTierIsReported: Bool
}

/// What a run of `generate` tells the dependency tree generator about the seams among the declarations it reads.
public struct SeamResolution: Sendable {
	/// A seam declared in another module, which that module's run of `generate` generated the initializer of.
	public struct ForeignSeam: Sendable {
		public init(declaringModule: ModuleIdentity, missingDependencyModuleName: String? = nil, visibleInstantiables: [TypeDescription: Instantiable], callCarriesPluginComment: Bool) {
			self.declaringModule = declaringModule
			self.missingDependencyModuleName = missingDependencyModuleName
			self.visibleInstantiables = visibleInstantiables
			self.callCarriesPluginComment = callCarriesPluginComment
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
	}

	public init(currentModule: ModuleIdentity, generatedSeams: Set<TypeDescription>, foreignSeams: [TypeDescription: ForeignSeam], callersComputeFromTargetGraph: Bool = false, callersVisibleInstantiables: [TypeDescription: Instantiable]? = nil) {
		self.currentModule = currentModule
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

extension Instantiable {
	/// The comment a generated call to a seam carries where SafeDI cannot know that the seam's module generated the
	/// initializer it calls. See `SeamCall.carriesPluginComment`.
	public static func seamCallPluginComment(for seamType: TypeDescription) -> String {
		"// If this line does not compile, add the SafeDI plugin to the target that declares \(seamType.asSource)."
	}
}
