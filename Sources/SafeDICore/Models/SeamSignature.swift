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

	/// A build site in the seam's tree of an `@Instantiated` property whose type no production `@Instantiable`
	/// declaration the seam's module can see fulfills, or one an inner seam's tree holds that this seam passes up: the
	/// generated initializer takes a builder for it, which a caller that can see a fulfilling declaration fills. Each
	/// site is its own hole, with its own builder and scope struct, never grouped with another site of the property.
	public struct Hole: Sendable {
		/// A value in scope at the site, which the scope struct the builder is handed carries.
		public struct Field: Sendable {
			public init(property: Property, access: AccessLevel, accessCause: TypeAccessProof.Cause? = nil, declaringType: TypeDescription, declarationLocation: Dependency.DeclarationLocation?, isReceivedOnlyIfAvailable: Bool = false) {
				self.property = property
				self.access = access
				self.accessCause = accessCause
				self.declaringType = declaringType
				self.declarationLocation = declarationLocation
				self.isReceivedOnlyIfAvailable = isReceivedOnlyIfAvailable
			}

			/// The value's label and the type of its declaration.
			public let property: Property
			/// The access the struct declares the field at: as visible as the narrowest type the field names, as the
			/// declarations the signature is computed from prove it (`TypeAccessProof`), capped at the seam's type.
			public let access: AccessLevel
			/// How the narrowest type the field names is proven, which a diagnostic explains, or `nil` when every type it
			/// names is `public`.
			public let accessCause: TypeAccessProof.Cause?
			/// The type whose declaration of the value the field carries: for a parameter that passes a receive through
			/// the seam, the first type in the tree that receives it.
			public let declaringType: TypeDescription
			public let declarationLocation: Dependency.DeclarationLocation?
			/// Whether the field passes through a parameter the seam's tree receives only if available, so a caller
			/// may pass `nil` for it.
			public let isReceivedOnlyIfAvailable: Bool
		}

		/// A declaration on the site's path whose label a fill cannot read from the scope struct: the nearest declaration
		/// of its label is bound after the site. A fill whose tree receives such a label is an error, since inline the
		/// receive reads that declaration.
		public struct UncarriedDeclaration: Sendable {
			public init(property: Property, declaringType: TypeDescription, declarationLocation: Dependency.DeclarationLocation?, builtAfter: Property?, reason: Reason) {
				self.property = property
				self.declaringType = declaringType
				self.declarationLocation = declarationLocation
				self.builtAfter = builtAfter
				self.reason = reason
			}

			/// Why the declaration is bound after the site.
			public enum Reason: Sendable {
				/// Its type receives `builtAfter`, the scope on the site's path, only if available.
				case receivesPathScopeOnlyIfAvailable(type: TypeDescription)
				/// Its type requires `carrier`, a sibling that holds another site.
				case requiresOtherCarrier(type: TypeDescription, carrier: Property)
				/// It is the scope on the site's path, still being built, the hole itself, or an alias not created there.
				case other
				/// `seam`'s tree binds it on a path to a call of the seam whose hole `seam` passes up: inline, a receive
				/// of its label would read it, and `seam`'s caller, which fills the builder, does not hold it.
				case boundByPassingUpSeam(seam: TypeDescription)
			}

			public let property: Property
			public let declaringType: TypeDescription
			public let declarationLocation: Dependency.DeclarationLocation?
			/// The property of the scope on the site's path that the declaration's scope builds before it, or `nil`.
			public let builtAfter: Property?
			public let reason: Reason
		}

		public init(
			ownerType: TypeDescription,
			property: Property,
			instantiatedType: TypeDescription,
			declarationLocation: Dependency.DeclarationLocation?,
			erasedToConcreteExistential: Bool,
			sitePath: [Property],
			sitePathDeclarationLocations: [Dependency.DeclarationLocation?],
			fillPropertyStack: [Property],
			builderLabel: String,
			internalName: String,
			scopeSeamType: TypeDescription,
			scopeTypeName: String,
			stages: [[Field]],
			stageBoundaryDepths: [Int],
			tierAccess: AccessLevel,
			accessCause: TypeAccessProof.Cause? = nil,
			uncarriedDeclarations: [UncarriedDeclaration],
			innerSeamType: TypeDescription? = nil,
			isSendable: Bool = false,
		) {
			self.ownerType = ownerType
			self.property = property
			self.instantiatedType = instantiatedType
			self.declarationLocation = declarationLocation
			self.erasedToConcreteExistential = erasedToConcreteExistential
			self.sitePath = sitePath
			self.sitePathDeclarationLocations = sitePathDeclarationLocations
			self.fillPropertyStack = fillPropertyStack
			self.builderLabel = builderLabel
			self.internalName = internalName
			self.scopeSeamType = scopeSeamType
			self.scopeTypeName = scopeTypeName
			self.stages = stages
			self.stageBoundaryDepths = stageBoundaryDepths
			self.tierAccess = tierAccess
			self.accessCause = accessCause
			self.uncarriedDeclarations = uncarriedDeclarations
			self.innerSeamType = innerSeamType
			self.isSendable = isSendable
		}

		/// The type whose `@Instantiated` property the site builds.
		public let ownerType: TypeDescription
		/// The property the site builds, as its owner declares it: the builder returns its type.
		public let property: Property
		/// The type a declaration must fulfill to fill the builder: the property's instantiated type, or the type an
		/// erased property names with `fulfilledByType:`.
		public let instantiatedType: TypeDescription
		/// Where the owner declares the property.
		public let declarationLocation: Dependency.DeclarationLocation?
		/// Whether the property is `erasedToConcreteExistential`, which a fill wraps the fulfilling type in.
		public let erasedToConcreteExistential: Bool
		/// The properties from the root of the tree that holds the site down to the owner's property, outermost first:
		/// the site's identity in that tree.
		public let sitePath: [Property]
		/// Where each property of `sitePath` is declared, by the type that builds it.
		public let sitePathDeclarationLocations: [Dependency.DeclarationLocation?]
		/// The stack a fill builds the property's tree with: the properties from the root of the seam whose tree holds
		/// the site to the owner's property, innermost first, each lazily instantiated one preceded by its instance, as
		/// `Scope.createScopeGenerator` stacks them.
		public let fillPropertyStack: [Property]
		/// The label the generated initializer takes the builder under.
		public let builderLabel: String
		/// The name the generated initializer binds the builder to.
		public let internalName: String
		/// The seam whose extension declares the scope struct: this seam, or the inner seam a passed-up hole is from.
		public let scopeSeamType: TypeDescription
		/// The name of the scope struct, or, for a staged builder, of the enum holding one struct per stage.
		public let scopeTypeName: String
		/// The fields of each stage's struct: one stage, unless `@Sendable` builder functions lie between the seam and
		/// the site, each of which starts another.
		public let stages: [[Field]]
		/// The length of the site's path at each `@Sendable` builder function between the seam and the site, outermost
		/// first: the path of the property whose builder function it is.
		public let stageBoundaryDepths: [Int]
		/// The access each tier that takes the builder must have no more than: the builder's type is as visible as the
		/// narrowest type it names – the scope struct at the access of the seam that declares it, and the property's type
		/// as the declarations the signature is computed from prove it (`TypeAccessProof`) – capped at the seam's type.
		public let tierAccess: AccessLevel
		/// How the narrowest type the builder's type names is proven, which a diagnostic explains, or `nil` when every
		/// type it names is `public`.
		public let accessCause: TypeAccessProof.Cause?
		/// The declarations on the site's path a fill cannot read from the scope struct.
		public let uncarriedDeclarations: [UncarriedDeclaration]
		/// The seam the tree calls that presented the hole first, when this one passes it up, or `nil` for a site of this
		/// seam's own tree.
		public let innerSeamType: TypeDescription?
		/// Whether the builder is `@Sendable`: the seam's tree passes it on from inside a `@Sendable` builder function,
		/// which captures it.
		public let isSendable: Bool

		/// What identifies a hole: its site, by the seam whose tree holds it and its path there, which a passed-up hole
		/// keeps. A seam takes one builder per site, whatever route presents it.
		public struct Site: Hashable, Sendable {
			public let seamType: TypeDescription
			public let path: [Property]
		}

		/// The hole's site.
		public var site: Site {
			Site(seamType: scopeSeamType, path: sitePath)
		}

		/// The name of the struct of the stage at `stageIndex`, or `nil` for an unstaged builder.
		public static func stageName(at stageIndex: Int) -> String {
			stageIndex == 0 ? "Outer" : stageIndex == 1 ? "Inner" : "Inner\(stageIndex)"
		}

		/// The type of the struct the stage at `stageIndex` is handed, qualified by `seamType` when it is given.
		public func stageStructType(at stageIndex: Int, qualifiedBy seamType: TypeDescription?) -> TypeDescription {
			let scopeType: TypeDescription = if let seamType {
				.nested(name: scopeTypeName, parentType: seamType, generics: [])
			} else {
				.simple(name: scopeTypeName, generics: [])
			}
			return stages.count == 1 ? scopeType : .nested(name: Self.stageName(at: stageIndex), parentType: scopeType, generics: [])
		}

		/// The type of the function the stage at `stageIndex` is: it takes that stage's struct and returns the next
		/// stage's `@Sendable` function, or the property's type at the last stage.
		public func stageFunctionType(at stageIndex: Int, qualifiedBy seamType: TypeDescription?) -> TypeDescription {
			let returnType: TypeDescription = if stageIndex + 1 < stages.count {
				.attributed(stageFunctionType(at: stageIndex + 1, qualifiedBy: seamType), specifiers: [], attributes: ["Sendable"])
			} else {
				property.typeDescription
			}
			return .closure(arguments: [stageStructType(at: stageIndex, qualifiedBy: seamType)], isAsync: false, doesThrow: false, returnType: returnType)
		}

		/// The builder parameter's type, `@escaping`, with its scope type qualified by `seamType` when it is given.
		public func builderType(qualifiedBy seamType: TypeDescription?) -> TypeDescription {
			.attributed(stageFunctionType(at: 0, qualifiedBy: seamType), specifiers: [], attributes: isSendable ? ["escaping", "Sendable"] : ["escaping"])
		}
	}

	public init(seamType: TypeDescription, parameters: [Parameter], tiers: [AccessLevel], noTierParameters: [Parameter] = [], holes: [Hole] = []) {
		self.seamType = seamType
		self.parameters = parameters
		self.tiers = tiers
		self.noTierParameters = noTierParameters
		self.holes = holes
	}

	/// The seam's concrete type.
	public let seamType: TypeDescription
	/// The parameters of the narrowest tier, which takes every one: the seam's own `@Received` and `@Forwarded`
	/// properties in declaration order, then the pass-throughs in label order.
	public let parameters: [Parameter]
	/// The holes the generated initializer takes a builder for, in builder-label order, after every parameter and on
	/// every tier. Kept apart from `parameters`, so a builder is never receivable in the seam's own tree.
	public let holes: [Hole]
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

		/// A builder the call passes: its label, its type spelled without `any`, its tier access, and each field of
		/// each stage's struct – label, type spelled without `any`, and access – in stage and field order.
		public struct Hole: Hashable, Sendable {
			public init(_ hole: SeamSignature.Hole) {
				builderLabel = hole.builderLabel
				type = hole.builderType(qualifiedBy: hole.scopeSeamType).withoutAny.asSource
				tierAccess = hole.tierAccess
				fields = hole.stages.map { stage in
					stage.map { Field(label: $0.property.label, type: $0.property.typeDescription.withoutAny.asSource, access: $0.access) }
				}
			}

			public struct Field: Hashable, Sendable {
				public let label: String
				public let type: String
				public let access: AccessLevel
			}

			public let builderLabel: String
			public let type: String
			public let tierAccess: AccessLevel
			public let fields: [[Field]]
		}

		public let parameters: [Parameter]
		public let holes: [Hole]
		public let tiers: [AccessLevel]
	}

	public var callShape: CallShape {
		CallShape(parameters: parameters.map(CallShape.Parameter.init), holes: holes.map(CallShape.Hole.init), tiers: tiers)
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

		/// A hole's call shape, which a hole that changes changes what the seam's callers and the seams that pass it up
		/// compute, and the labels of its uncarried declarations, which only accumulate where a seam's tree reaches the
		/// seam again and hands the builder back.
		public struct Hole: Hashable, Sendable {
			public let callShape: CallShape.Hole
			public let uncarriedLabels: Set<String>
		}

		public let parameters: [Parameter]
		public let holes: [Hole]
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
		return SettledContent(
			parameters: settledContent(of: parameters),
			holes: holes.map { SettledContent.Hole(callShape: CallShape.Hole($0), uncarriedLabels: Set($0.uncarriedDeclarations.map(\.property.label))) },
			tiers: tiers,
			noTierParameters: settledContent(of: noTierParameters),
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
		// Each builder after every parameter, so a seam without one hashes what it always hashed. A field is hashed,
		// since a caller that computed the struct without it would resolve the label from its own scope instead.
		for hole in callShape.holes {
			hash.combine(hole.builderLabel)
			hash.combine(hole.type)
			hash.combine(hole.tierAccess.spelledOnGeneratedDeclaration)
			for field in hole.fields.joined() {
				hash.combine(field.label)
				hash.combine(field.type)
				hash.combine(field.access.spelledOnGeneratedDeclaration)
			}
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
		holes: [SeamSignature.Hole] = [],
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
		self.holes = holes
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
	/// The holes whose builders the call passes, in builder-label order: every tier takes every builder.
	public let holes: [SeamSignature.Hole]
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

	/// A type another module declares with `generateMock: .public`, whose `mock()` that module's run of `generate`
	/// generated, and which a mock tree of this module calls where it cannot build the type's tree itself.
	public struct ForeignPublicMock: Sendable {
		public init(declaringModule: ModuleIdentity, missingDependencyModuleName: String? = nil, visibleInstantiables: [TypeDescription: Instantiable], callCarriesPluginComment: Bool, declaringModuleMockCondition: MockCondition) {
			self.declaringModule = declaringModule
			self.missingDependencyModuleName = missingDependencyModuleName
			self.visibleInstantiables = visibleInstantiables
			self.callCarriesPluginComment = callCarriesPluginComment
			self.declaringModuleMockCondition = declaringModuleMockCondition
		}

		/// The module that declares the type, whose name is known: a type whose module is unknown is built inline.
		public let declaringModule: ModuleIdentity
		/// See `ForeignSeam.missingDependencyModuleName`.
		public let missingDependencyModuleName: String?
		/// The declarations the declaring module can see, resolved as `generate` resolves them, from which the public
		/// mock's signature is computed exactly as that module computed it.
		public let visibleInstantiables: [TypeDescription: Instantiable]
		/// See `SeamCall.carriesPluginComment`.
		public let callCarriesPluginComment: Bool
		/// The condition the declaring module generates its mocks under: its configuration's, `DEBUG` without one, read
		/// from its module info or, under the target graph, from the configuration in a file the graph attributes to it.
		public let declaringModuleMockCondition: MockCondition
	}

	public init(currentModule: ModuleIdentity, currentModuleMockCondition: MockCondition = MockCondition("DEBUG"), generatedSeams: Set<TypeDescription>, foreignSeams: [TypeDescription: ForeignSeam], foreignPublicMocks: [TypeDescription: ForeignPublicMock] = [:], callersComputeFromTargetGraph: Bool = false, callersVisibleInstantiables: [TypeDescription: Instantiable]? = nil) {
		self.currentModule = currentModule
		self.currentModuleMockCondition = currentModuleMockCondition
		self.generatedSeams = generatedSeams
		self.foreignSeams = foreignSeams
		self.foreignPublicMocks = foreignPublicMocks
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
	/// The `generateMock: .public` types other modules declare, by concrete type. One whose module SafeDI does not know
	/// is in neither this map nor the module's own files, and every mock tree builds it inline, as any other type.
	public let foreignPublicMocks: [TypeDescription: ForeignPublicMock]
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
