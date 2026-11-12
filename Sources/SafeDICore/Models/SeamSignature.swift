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
/// where a value was expected. That is a different job from the `__safeDI_`-prefixed labels of the initializer only
/// generated code calls, which keep it apart from the plain initializer people call: labels name no type and no
/// availability, so a stale call that writes the right labels still compiles without the enum.
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
		public init(property: Property, isPassThrough: Bool, access: AccessLevel, tierAccess: AccessLevel? = nil, isOnlyIfAvailable: Bool, requiredThroughAlias: Bool = false, deferral: Deferral = .none, internalName: String? = nil, receivers: [Receiver] = [], accessCause: TypeAccessProof.Cause? = nil, nestedSeamCall: NestedSeamCall? = nil, otherInitializerArgumentsAccess: AccessLevel = .public) {
			self.property = property
			self.isPassThrough = isPassThrough
			self.access = access
			self.tierAccess = tierAccess ?? access
			self.isOnlyIfAvailable = isOnlyIfAvailable
			self.requiredThroughAlias = isOnlyIfAvailable && requiredThroughAlias
			self.deferral = deferral
			self.internalName = internalName ?? ScopeGenerator.functionName(toBuildPropertyNamed: property.label)
			self.receivers = receivers
			self.accessCause = accessCause
			self.nestedSeamCall = nestedSeamCall
			self.otherInitializerArgumentsAccess = otherInitializerArgumentsAccess
		}

		/// The parameter's label and type. A pass-through that some receiver in the tree requires has the type the
		/// receiver declares – the optional type it is declared with where every receiver that requires it declares
		/// it optional, since the property the caller's tree declares may be optional too; one every receiver
		/// receives only if available has the optional form of that type. No parameter has a default, so every call
		/// writes every argument.
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

		/// Whether the parameter is received only if available: a pass-through every receiver receives only if
		/// available, or the seam's own `@Received(onlyIfAvailable: true)` property, which a generated caller passes
		/// `nil` where its tree holds nothing, and a wider tier passes `nil` where it omits the parameter. A
		/// pass-through some receiver requires, an own required `@Received` and an own `@Forwarded` are not, optional
		/// type or not: a caller must hold a value for each.
		public let isOnlyIfAvailable: Bool
		/// Whether a receiver in the seam's tree requires an `onlyIfAvailable` alias that is bound from this pass-through,
		/// which is received only if available: the alias is `nil` where the caller holds nothing, but where the caller
		/// builds the property, it builds it before calling the seam, as it would build it before the receiver's tree
		/// inline. Never `true` for a parameter that is not received only if available, which every caller passes.
		public let requiredThroughAlias: Bool
		/// The receives inside the seam's tree that a pass-through fulfills, in tree order, each with the access the
		/// proof gives the parameter; a seam that passes the parameter on names them in its notes, and admits their
		/// modules' mentions to the proof. Empty for one of the seam's own properties, which its own initializer
		/// receives.
		public let receivers: [Receiver]
		/// For a parameter on no tier (`SeamSignature.noTierParameters`), the nested seam call that omits it, else `nil`.
		public let nestedSeamCall: NestedSeamCall?
		/// Whether the initializer only generated code calls takes the parameter by value or defers it: a by-value
		/// pass-through – a constant, or its optional form – is taken as an `@autoclosure`, which the narrowest tier's body
		/// holds in a `LazilyInstantiated` under the parameter's label, so the tree reads the caller's value where it would
		/// read it inline, when a receiver is first built. A tier that defers a parameter has a second initializer for
		/// people, which takes every parameter by value (`plainSpelling`), so a call cannot capture its caller.
		public let deferral: Deferral
		/// The name the generated initializer binds a deferred parameter's autoclosure to: `__safeDI_<label>`, renamed
		/// past every builder function name in the seam's tree, which would shadow it. Unused for a parameter taken by
		/// value.
		public let internalName: String

		/// How the generated initializer takes a parameter.
		public enum Deferral: Hashable, Sendable {
			/// Taken by value, as spelled.
			case none
			/// Taken by generated code as `@autoclosure @escaping () -> T`, held in a `LazilyInstantiated<T>` the tree reads
			/// where it reads the label; `@Sendable`, held in a `SendableLazilyInstantiated<T>`, when a `@Sendable` function
			/// inside the seam's tree reads it, or a nested seam takes it `@Sendable`.
			case deferred(isSendable: Bool)
		}

		/// Whether the initializer only generated code calls takes the parameter as an `@autoclosure`.
		public var isDeferred: Bool {
			deferral != .none
		}

		/// The type a deferred parameter's autoclosure returns and its `LazilyInstantiated` holds: the parameter's type,
		/// with an implicitly unwrapped optional spelled as its optional form, which an autoclosure's return type and a
		/// generic argument cannot spell, and whose instance a receiver of the implicitly unwrapped type accepts.
		public var deferredValueType: TypeDescription {
			if case let .implicitlyUnwrappedOptional(wrappedType) = property.typeDescription {
				.optional(wrappedType)
			} else {
				property.typeDescription
			}
		}

		/// The parameter as the plain initializer of a tier that defers a parameter, or the one initializer of a tier that
		/// defers none, declares it: by value, under its label alone. An underscored name would keep the initializer out of
		/// the module's symbol graph, which is what documentation is generated from. No parameter has a default, so every
		/// call passes every one.
		func plainSpelling(amongTypesDeclaredEscaping typesDeclaredEscaping: Set<TypeDescription>) -> String {
			switch deferral {
			case .none:
				property.asFunctionParameterSyntax(amongTypesDeclaredEscaping: typesDeclaredEscaping).description
			case .deferred:
				// The closure of the initializer only generated code calls captures this parameter, so a function type is
				// `@escaping` here even though that initializer takes it behind an `@autoclosure`.
				Property(label: property.label, typeDescription: deferredValueType).asFunctionParameterSyntax(amongTypesDeclaredEscaping: typesDeclaredEscaping).description
			}
		}

		/// The parameter as the initializer only generated code calls declares it: under `generatedOnlyArgumentLabel`, a
		/// deferred parameter as an `@autoclosure` bound to `internalName`, which a call passes `nil` for where it holds
		/// nothing.
		func generatedOnlySpelling(amongTypesDeclaredEscaping typesDeclaredEscaping: Set<TypeDescription>) -> String {
			switch deferral {
			case .none:
				"\(generatedOnlyArgumentLabel) \(property.asFunctionParameterSyntax(amongTypesDeclaredEscaping: typesDeclaredEscaping).description)"
			case let .deferred(isSendable):
				"\(internalName == generatedOnlyArgumentLabel ? internalName : "\(generatedOnlyArgumentLabel) \(internalName)"): @autoclosure @escaping\(isSendable ? " @Sendable" : "") () -> \(deferredValueType.asSource)"
			}
		}

		/// The argument label of the initializer only generated code calls (`ReservedName.seamGeneratedOnlyArgumentLabel(of:)`).
		public var generatedOnlyArgumentLabel: String {
			ReservedName.seamGeneratedOnlyArgumentLabel(of: property.label)
		}

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
			public init(property: Property, access: AccessLevel, accessCause: TypeAccessProof.Cause? = nil, declaringType: TypeDescription, declarationLocation: Dependency.DeclarationLocation?, isReceivedOnlyIfAvailable: Bool = false, deferral: Parameter.Deferral = .none) {
				self.property = property
				self.deferral = deferral
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
			/// How the seam takes the parameter the field is bound from (`SeamSignature.Parameter.deferral`): `.none` for a
			/// field bound from a declaration inside the seam's tree, or from a parameter taken by value. The seam's tree
			/// holds a deferred parameter in a `LazilyInstantiated` (`SendableLazilyInstantiated` when `@Sendable`), which
			/// it hands the struct, so the value is created when a fill first reads the field, as inline.
			public let deferral: Parameter.Deferral

			/// Whether the field is bound from a deferred parameter (`SeamSignature.Parameter.isDeferred`).
			public var isDeferredParameter: Bool {
				deferral != .none
			}

			/// The type of the `LazilyInstantiated` (or `SendableLazilyInstantiated`) a deferred parameter's field holds,
			/// or `nil` for a field held by value: the parameter's type, an implicitly unwrapped optional spelled as its
			/// optional form, as the seam's tree holds it (`SeamSignature.Parameter.deferredValueType`).
			public var memoType: TypeDescription? {
				guard case let .deferred(isSendable) = deferral else { return nil }
				let valueType: TypeDescription = if case let .implicitlyUnwrappedOptional(wrappedType) = property.typeDescription {
					.optional(wrappedType)
				} else {
					property.typeDescription
				}
				return .simple(name: isSendable ? Dependency.sendableLazilyInstantiatedType : Dependency.lazilyInstantiatedType, generics: [valueType])
			}

			/// The name of the stored property that holds a deferred parameter's memo inside the struct, beside the field's
			/// own name, which the struct reads the memo's instance through.
			var memoName: String {
				ScopeGenerator.functionName(toBuildPropertyNamed: property.label)
			}
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
				/// It is the scope on the site's path, still being built, or the hole itself.
				case other
				/// `seam`, declared in `module`, binds it in its tree on a path to a call of the seam whose hole `seam` passes up:
				/// inline, a receive of its label would read it, and `seam`'s caller, which fills the builder, does not hold it.
				case boundByPassingUpSeam(seam: TypeDescription, module: ModuleIdentity)
			}

			public let property: Property
			public let declaringType: TypeDescription
			public let declarationLocation: Dependency.DeclarationLocation?
			/// The property of the scope on the site's path that the declaration's scope builds before it, or `nil`.
			public let builtAfter: Property?
			public let reason: Reason
		}

		/// A type on the way from the seam that takes a hole's builder to the hole's owner, with the module that declares it.
		public struct PathType: Sendable {
			public init(type: TypeDescription, moduleName: String?) {
				self.type = type
				self.moduleName = moduleName
			}

			public let type: TypeDescription
			public let moduleName: String?
		}

		public init(
			ownerType: TypeDescription,
			declaringModuleNames: [String],
			property: Property,
			instantiatedType: TypeDescription,
			declarationLocation: Dependency.DeclarationLocation?,
			erasedToConcreteExistential: Bool,
			sitePath: [Property],
			declaredSitePath: [DeclaredProperty],
			fillPropertyStack: [Property],
			builderLabel: String,
			internalName: String,
			scopeSeamType: TypeDescription,
			scopeSeamModule: ModuleIdentity,
			typesToOwner: [PathType],
			scopeTypeName: String,
			stages: [[Field]],
			stageBoundaries: [StageBoundary],
			tierAccess: AccessLevel,
			accessCause: TypeAccessProof.Cause? = nil,
			uncarriedDeclarations: [UncarriedDeclaration],
			innerSeamType: TypeDescription? = nil,
			passedUpRoute: [DeclaredProperty] = [],
			isSendable: Bool = false,
		) {
			self.ownerType = ownerType
			self.declaringModuleNames = declaringModuleNames
			self.property = property
			self.instantiatedType = instantiatedType
			self.declarationLocation = declarationLocation
			self.erasedToConcreteExistential = erasedToConcreteExistential
			self.sitePath = sitePath
			self.declaredSitePath = declaredSitePath
			self.fillPropertyStack = fillPropertyStack
			self.builderLabel = builderLabel
			self.internalName = internalName
			self.scopeSeamType = scopeSeamType
			self.scopeSeamModule = scopeSeamModule
			self.typesToOwner = typesToOwner
			self.scopeTypeName = scopeTypeName
			self.stages = stages
			self.stageBoundaries = stageBoundaries
			self.tierAccess = tierAccess
			self.accessCause = accessCause
			self.uncarriedDeclarations = uncarriedDeclarations
			self.innerSeamType = innerSeamType
			self.passedUpRoute = passedUpRoute
			self.isSendable = isSendable
		}

		/// The type whose `@Instantiated` property the site builds.
		public let ownerType: TypeDescription
		/// The module of the seam whose tree holds the site, when it also declares the owner and no seam passes the site up,
		/// which a spelling of the property's type or of the fulfiller's `@Forwarded` property may qualify a type with, since
		/// the fulfiller is in another module. Empty otherwise: generated code respells the property's type in every module on
		/// the way to the fill, where a bare name may mean a type of that module, which its `.safedi` records only if a
		/// declaration of that module mentions it.
		public let declaringModuleNames: [String]
		/// The property the site builds, as its owner declares it: the builder returns its type without its wrapper
		/// (`builtType`).
		public let property: Property
		/// The type a declaration must fulfill to fill the builder: the property's instantiated type, or the type an
		/// erased property names with `fulfilledByType:`.
		public let instantiatedType: TypeDescription
		/// Where the owner declares the property.
		public let declarationLocation: Dependency.DeclarationLocation?
		/// Whether the property is `erasedToConcreteExistential`, which a fill wraps the fulfilling type in.
		public let erasedToConcreteExistential: Bool
		/// The properties from the root of the tree that holds the site down to the owner's property, outermost first:
		/// the site's identity in that tree, which generated names are made from. Inside a fill of a passed-up hole it holds
		/// a stand-in for the seam that holds that hole (`pathBeforePropertyInItsFill`), no declaration, so a diagnostic
		/// prints `declaredSitePath` instead.
		public let sitePath: [Property]
		/// The properties the code declares from the root of the tree that holds the site down to the owner's property,
		/// outermost first, inside a fill of a passed-up hole through the calls that passed it up.
		public let declaredSitePath: [DeclaredProperty]
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
		/// The module that declares `scopeSeamType`, which a module the hole reaches through a view knows only from here.
		public let scopeSeamModule: ModuleIdentity
		/// The types from the seam that takes this builder, itself excluded, to the hole's owner, outermost first: for a
		/// passed-up hole, every seam it passes through on the way to `scopeSeamType`. Empty when that seam owns the hole.
		/// Each type's module is a fact of the hole, so no order among modules decides which one a diagnostic names.
		public let typesToOwner: [PathType]
		/// The name of the scope struct, or, for a staged builder, of the enum holding one struct per stage.
		public let scopeTypeName: String
		/// The fields of each stage's struct: one stage, unless `@Sendable` functions lie between the seam and the site,
		/// each of which starts another.
		public let stages: [[Field]]
		/// Where each stage after the first starts: each `@Sendable` function between the seam and the site, outermost first.
		public let stageBoundaries: [StageBoundary]
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
		/// When this seam passes the hole up, the properties from its root to the call of the seam whose tree holds the
		/// site, through the calls of every seam between, outermost first; empty for a site of this seam's own tree.
		public let passedUpRoute: [DeclaredProperty]
		/// Whether the builder is `@Sendable`: the seam's tree passes it on from inside a `@Sendable` function, which
		/// captures it.
		public let isSendable: Bool

		/// A property on the way to a site, the type that declares it, and where, when that is known. For a property of a
		/// protocol's fulfiller, the type is the fulfiller, which the property's type does not name.
		public struct DeclaredProperty: Sendable {
			public init(property: Property, declaringType: TypeDescription?, declarationLocation: Dependency.DeclarationLocation?) {
				self.property = property
				self.declaringType = declaringType
				self.declarationLocation = declarationLocation
			}

			public let property: Property
			public let declaringType: TypeDescription?
			public let declarationLocation: Dependency.DeclarationLocation?
		}

		/// A `@Sendable` function between a seam and a site of its tree, which starts a stage of the site's builder: the seam
		/// calls the stage before it just before declaring the function.
		public struct StageBoundary: Sendable {
			public init(pathLength: Int, fillStageIndex: Int? = nil) {
				self.pathLength = pathLength
				self.fillStageIndex = fillStageIndex
			}

			/// How much of the site's path leads to the property the function builds.
			public let pathLength: Int
			/// For a function of a fill the seam's tree generates for a seam it calls, its stage among the fill's stages, or
			/// `nil` for a builder function.
			public let fillStageIndex: Int?
		}

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

		/// What the path of a site inside a fill of this hole holds before the hole's property, in the tree of the seam whose
		/// call the fill is passed to: the seam that holds the hole, when the seam called passes it up, and the properties
		/// from that seam's root to the hole's owner. One call's holes can share a property, and each has a fill of its own.
		var pathBeforePropertyInItsFill: [Property] {
			(innerSeamType == nil ? [] : [Property(label: scopeSeamType.asIdentifier, typeDescription: scopeSeamType)]) + sitePath.dropLast()
		}

		/// What `declaredSitePath` holds before the hole's property for a site inside a fill of this hole: the calls that
		/// passed the hole up, and the properties from the root of the seam that holds it to the hole's owner.
		var declaredPathBeforePropertyInItsFill: [DeclaredProperty] {
			passedUpRoute + declaredSitePath.dropLast()
		}

		/// What the builder returns: the property's declared type without its wrapper, which the tree that holds the site
		/// builds around the builder.
		public var builtType: TypeDescription {
			property.typeDescription.builtTypeOfWrapper
		}

		/// The value an instantiator hands the builder, which the builder's last stage takes as its second argument, or
		/// `nil` when the property is no instantiator, or is one spelled as forwarding `()` or `Void`.
		public var forwardedType: TypeDescription? {
			property.typeDescription.forwardedTypeOfWrapper
		}

		/// The label the initializer only generated code calls takes the builder under
		/// (`ReservedName.seamGeneratedOnlyArgumentLabel(of:)`).
		public var generatedOnlyArgumentLabel: String {
			ReservedName.seamGeneratedOnlyArgumentLabel(of: builderLabel)
		}

		/// This hole as a call of a public mock takes its builder: under `parameterName`, the name the called mock gives
		/// the builder's parameter, which a mock that passes up the builders of several holes of one label names apart.
		func takenUnder(parameterName: String) -> Hole {
			Hole(
				ownerType: ownerType,
				declaringModuleNames: declaringModuleNames,
				property: property,
				instantiatedType: instantiatedType,
				declarationLocation: declarationLocation,
				erasedToConcreteExistential: erasedToConcreteExistential,
				sitePath: sitePath,
				declaredSitePath: declaredSitePath,
				fillPropertyStack: fillPropertyStack,
				builderLabel: parameterName,
				internalName: internalName,
				scopeSeamType: scopeSeamType,
				scopeSeamModule: scopeSeamModule,
				typesToOwner: typesToOwner,
				scopeTypeName: scopeTypeName,
				stages: stages,
				stageBoundaries: stageBoundaries,
				tierAccess: tierAccess,
				accessCause: accessCause,
				uncarriedDeclarations: uncarriedDeclarations,
				innerSeamType: innerSeamType,
				passedUpRoute: passedUpRoute,
				isSendable: isSendable,
			)
		}

		/// The name of the struct of the stage at `stageIndex` of a staged builder: `Outer`, `Inner`, `Inner2`, and so on. The
		/// structs are nested side by side, where a field's type that begins with one's name would resolve to it, so an
		/// underscore is appended while a field's type begins with the name.
		public func stageName(at stageIndex: Int) -> String {
			Self.stageName(at: stageIndex, of: stages)
		}

		/// The name of the function the stage at `stageIndex` is, for a builder or fill named `functionName`: that name for
		/// the first stage, whose function it is, and that name joined with the stage's for a later one.
		public func stageFunctionName(at stageIndex: Int, ofFunctionNamed functionName: String) -> String {
			Self.stageFunctionName(at: stageIndex, of: stages, ofFunctionNamed: functionName)
		}

		/// `stageFunctionName(at:ofFunctionNamed:)` of a hole with `stages`.
		static func stageFunctionName(at stageIndex: Int, of stages: [[Field]], ofFunctionNamed functionName: String) -> String {
			stageIndex == 0 ? functionName : "\(functionName)_\(stageName(at: stageIndex, of: stages))".spelledAsJoinedIdentifier
		}

		private static func stageName(at stageIndex: Int, of stages: [[Field]]) -> String {
			let namedTypes = Set(stages.joined().flatMap { TypeAccessProof.mentionedTypes(in: $0.property.typeDescription).compactMap(\.outermostTypeName) })
			var name = stageIndex == 0 ? "Outer" : stageIndex == 1 ? "Inner" : "Inner\(stageIndex)"
			while namedTypes.contains(name) {
				name += "_"
			}
			return name
		}

		/// The type of the struct the stage at `stageIndex` is handed, qualified by `seamType` when it is given.
		public func stageStructType(at stageIndex: Int, qualifiedBy seamType: TypeDescription?) -> TypeDescription {
			let scopeType: TypeDescription = if let seamType {
				.nested(name: scopeTypeName, parentType: seamType, generics: [])
			} else {
				.simple(name: scopeTypeName, generics: [])
			}
			return stages.count == 1 ? scopeType : .nested(name: stageName(at: stageIndex), parentType: scopeType, generics: [])
		}

		/// The type of the function the stage at `stageIndex` is: it takes that stage's struct and returns the next
		/// stage's `@Sendable` function, or, at the last stage, also takes the value an instantiator forwards and returns
		/// the type the property builds.
		public func stageFunctionType(at stageIndex: Int, qualifiedBy seamType: TypeDescription?) -> TypeDescription {
			stageFunctionType(at: stageIndex, qualifiedBy: seamType, spelledWithoutAny: false)
		}

		/// The builder parameter's type, `@escaping`, with its scope type qualified by `seamType` when it is given.
		public func builderType(qualifiedBy seamType: TypeDescription?) -> TypeDescription {
			builderType(qualifiedBy: seamType, spelledWithoutAny: false)
		}

		/// `builderType(qualifiedBy:)`, spelled without `any` at every depth, which the guard hashes.
		var builderTypeWithoutAny: TypeDescription {
			builderType(qualifiedBy: scopeSeamType, spelledWithoutAny: true).withoutAny
		}

		private func builderType(qualifiedBy seamType: TypeDescription?, spelledWithoutAny: Bool) -> TypeDescription {
			let functionType = stageFunctionType(at: 0, qualifiedBy: seamType, spelledWithoutAny: spelledWithoutAny)
			return (isSendable ? functionType.asSendableFunction : functionType).asFunctionParameter
		}

		/// `stageFunctionType(at:qualifiedBy:)`, built from the last stage out. Each later stage is held as its spelling, so
		/// that the type has no more depth than one stage however many there are: `@Sendable` functions on a path can be as
		/// many as the module has types, and a walk of a `TypeDescription` recurses per level.
		private func stageFunctionType(at stageIndex: Int, qualifiedBy seamType: TypeDescription?, spelledWithoutAny: Bool) -> TypeDescription {
			func spelled(_ type: TypeDescription) -> TypeDescription {
				spelledWithoutAny ? type.withoutAny : type
			}
			let lastStageIndex = stages.count - 1
			let lastStageStruct = stageStructType(at: lastStageIndex, qualifiedBy: seamType)
			var functionType = property.typeDescription.seamBuilderTypeOfWrapper(takingScope: lastStageStruct)
				?? .closure(arguments: [lastStageStruct] + (forwardedType.map { [$0] } ?? []), isAsync: false, doesThrow: false, returnType: builtType)
			for earlierStageIndex in (stageIndex..<lastStageIndex).reversed() {
				functionType = .closure(
					arguments: [stageStructType(at: earlierStageIndex, qualifiedBy: seamType)],
					isAsync: false,
					doesThrow: false,
					returnType: .unknown(text: spelled(functionType.asSendableFunction).asSource),
				)
			}
			return functionType
		}
	}

	public init(seamType: TypeDescription, parameters: [Parameter], tiers: [AccessLevel], noTierParameters: [Parameter] = [], holes: [Hole] = [], typesDeclaredEscaping: Set<TypeDescription> = []) {
		self.seamType = seamType
		self.parameters = parameters
		self.tiers = tiers
		self.noTierParameters = noTierParameters
		self.holes = holes
		self.typesDeclaredEscaping = typesDeclaredEscaping
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
	/// holding a value for one would have it dropped, which is reported at the caller. Each is received only if
	/// available, takes no part in the guard or a call's shape, and is never in scope inside the seam's own tree, which
	/// passes the nested seam `nil` for it, as the tier it calls does.
	public let noTierParameters: [Parameter]

	/// The types of `parameters` that the seam's tree declares `@escaping` (`ScopeGenerator.typesDeclaredEscaping`): a
	/// tree that calls the seam has no scopes for what is beneath it, so `SeamCall.typesDeclaredEscaping` hands them to
	/// it. No call depends on them, since Swift accepts the same arguments either way, so neither the call shape nor the
	/// guard holds them.
	public let typesDeclaredEscaping: Set<TypeDescription>

	/// The parameters the tier at `level` takes.
	public func parameters(ofTierAt level: AccessLevel) -> [Parameter] {
		parameters.filter { $0.tierAccess >= level }
	}

	/// Whether a tier that takes `parameters` has an initializer only generated code calls beside its plain one: it
	/// defers one of them.
	public static func tierHasGeneratedOnlyInitializer(taking parameters: [Parameter]) -> Bool {
		parameters.contains(where: \.isDeferred)
	}

	/// What a call of the generated initializer depends on: each parameter's label, type spelled without `any`, tier
	/// access, whether it is received only if available, whether it is deferred and `@Sendable` (`deferral`), and
	/// whether the caller builds it first (`requiredThroughAlias`), and the tiers. Two signatures with one call shape generate the same guard and the same
	/// calls, whatever their receivers and uncapped access. The guard hashes the parameters' fields and not the tiers:
	/// both sides derive the tiers from the parameters' tier accesses, which it hashes, and from the level of the seam's
	/// own initializer, which both read from the seam's declaration.
	public struct CallShape: Hashable, Sendable {
		public struct Parameter: Hashable, Sendable {
			public init(_ parameter: SeamSignature.Parameter) {
				label = parameter.property.label
				type = parameter.property.typeDescription.withoutAny.asSource
				tierAccess = parameter.tierAccess
				isOnlyIfAvailable = parameter.isOnlyIfAvailable
				requiredThroughAlias = parameter.requiredThroughAlias
				deferral = parameter.deferral
			}

			public let label: String
			public let type: String
			public let tierAccess: AccessLevel
			public let isOnlyIfAvailable: Bool
			public let requiredThroughAlias: Bool
			public let deferral: SeamSignature.Parameter.Deferral
		}

		/// A builder the call passes: its label, its type spelled without `any`, its tier access, and each field of
		/// each stage's struct – label, type spelled without `any`, and access – in stage and field order.
		public struct Hole: Hashable, Sendable {
			public init(_ hole: SeamSignature.Hole) {
				builderLabel = hole.builderLabel
				type = hole.builderTypeWithoutAny.asSource
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
	/// access, tier access and whether it is received only if available – with its receivers as a set, the tiers, and
	/// the types its tree declares `@escaping`.
	/// Never the receivers' order, which a seam's tree meets differently on every pass when it carries the receivers of
	/// a seam that carries its own, nor where a receive is declared, which a diagnostic reads and the declaring type and
	/// property already decide.
	public struct SettledContent: Hashable, Sendable {
		public struct Parameter: Hashable, Sendable {
			public let property: Property
			public let isPassThrough: Bool
			public let access: AccessLevel
			public let tierAccess: AccessLevel
			public let isOnlyIfAvailable: Bool
			public let requiredThroughAlias: Bool
			public let deferral: SeamSignature.Parameter.Deferral
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
		public let typesDeclaredEscaping: Set<TypeDescription>
	}

	public var settledContent: SettledContent {
		func settledContent(of parameters: [Parameter]) -> [SettledContent.Parameter] {
			parameters.map { parameter in
				SettledContent.Parameter(
					property: parameter.property,
					isPassThrough: parameter.isPassThrough,
					access: parameter.access,
					tierAccess: parameter.tierAccess,
					isOnlyIfAvailable: parameter.isOnlyIfAvailable,
					requiredThroughAlias: parameter.requiredThroughAlias,
					deferral: parameter.deferral,
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
			typesDeclaredEscaping: typesDeclaredEscaping,
		)
	}

	/// The name of the empty enum the seam's module generates in an extension of the seam, which every generated
	/// call refers to. It hashes each parameter's fields of `callShape` – label, type spelled without `any` (as the
	/// compiler and `TypeDescription ==` treat `any P` and `P` as one type), tier access, whether it is received only
	/// if available, whether it is deferred and `@Sendable`, and whether it is required through an alias – so a call generated from another computation of the
	/// signature names an enum the seam's module did not generate. The receivers are not hashed: they name
	/// declarations, and change nothing a call passes.
	public var guardTypeName: String {
		var hash = SeamSignatureHash()
		for parameter in callShape.parameters {
			hash.combine(parameter.label)
			hash.combine(parameter.type)
			hash.combine(parameter.tierAccess.spelledOnGeneratedDeclaration)
			// The flag's hash input is spelled as the default the generated initializer once gave the parameter: another
			// spelling would rename every guard of a seam with a parameter received only if available.
			hash.combine(parameter.isOnlyIfAvailable ? "= nil" : "")
			// The deferral only where the parameter is deferred, so a seam that takes every parameter by value hashes what it
			// always hashed.
			if case let .deferred(isSendable) = parameter.deferral {
				hash.combine(isSendable ? "deferred @Sendable" : "deferred")
			}
			// Only where it is set, so a seam without it hashes what it always hashed, and a caller that computed the
			// signature without it names an enum the seam's module did not generate.
			if parameter.requiredThroughAlias {
				hash.combine("required through alias")
			}
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
/// the comment the call carries saying what to do when it does not compile. A seam whose module SafeDI does not know
/// is built inline and gets no call.
public struct SeamCall: Sendable {
	/// The properties of the parameters a receiver in the seam's tree requires through an `onlyIfAvailable` alias
	/// (`SeamSignature.Parameter.requiredThroughAlias`), which the calling tree builds before the call where it builds
	/// them, as it would build them before the receiver's tree inline.
	public var requiredThroughAliasProperties: Set<Property> {
		Set(parameters.filter(\.requiredThroughAlias).map(\.property))
	}

	public init(
		parameters: [SeamSignature.Parameter],
		holes: [SeamSignature.Hole] = [],
		guardTypeName: String,
		comment: SeamCallComment,
		unreachableTierIsReported: Bool = false,
		omittedParameters: [SeamSignature.Parameter] = [],
		noTierParameters: [SeamSignature.Parameter] = [],
		typesDeclaredEscaping: Set<TypeDescription> = [],
		tier: AccessLevel = .internal,
		requirement: AccessRequirement = .internal,
		seamModuleName: String? = nil,
		callerModuleName: String? = nil,
		seamPackageName: String? = nil,
		callerPackageName: String? = nil,
	) {
		self.parameters = parameters
		self.holes = holes
		self.guardTypeName = guardTypeName
		self.comment = comment
		self.unreachableTierIsReported = unreachableTierIsReported
		self.omittedParameters = omittedParameters
		self.noTierParameters = noTierParameters
		self.typesDeclaredEscaping = typesDeclaredEscaping
		self.tier = tier
		self.requirement = requirement
		self.seamModuleName = seamModuleName
		self.callerModuleName = callerModuleName
		self.seamPackageName = seamPackageName
		self.callerPackageName = callerPackageName
	}

	/// The parameters of the tier the call passes, each at the access it was received at inside the seam, which a
	/// seam that reaches this one passes on at that access.
	public let parameters: [SeamSignature.Parameter]
	/// The holes whose builders the call passes, in builder-label order: every tier takes every builder.
	public let holes: [SeamSignature.Hole]
	/// The `SeamSignature.guardTypeName` of the signature the call was generated from.
	public let guardTypeName: String
	/// Whether the call is of the initializer only generated code calls, under its prefixed labels: the tier defers a
	/// parameter, so a `LazilyInstantiated` the caller holds is created when the seam's tree first reads it.
	public var callsGeneratedOnlyInitializer: Bool {
		SeamSignature.tierHasGeneratedOnlyInitializer(taking: parameters)
	}

	/// The comment the call carries saying what to do when it does not compile.
	public let comment: SeamCallComment
	/// The parameters of the seam's signature the called tier does not take, which the call passes `nil` for: a caller
	/// whose tree holds a value for one is reported, since built inline the tree would hand the value on.
	public let omittedParameters: [SeamSignature.Parameter]
	/// The seam's parameters on no tier (`SeamSignature.noTierParameters`), which the call passes `nil` for too.
	public let noTierParameters: [SeamSignature.Parameter]
	/// `SeamSignature.typesDeclaredEscaping` of the seam called.
	public let typesDeclaredEscaping: Set<TypeDescription>
	/// The level of the tier called.
	public let tier: AccessLevel
	/// What the calling module needs of the seam's declarations.
	public let requirement: AccessRequirement
	/// The module that declares the seam, as far as SafeDI knows it.
	public let seamModuleName: String?
	/// The module that makes the call, as far as SafeDI knows it.
	public let callerModuleName: String?
	/// The package of the module that declares the seam, as SafeDI is told it.
	public let seamPackageName: String?
	/// The package of the module that makes the call, as SafeDI is told it.
	public let callerPackageName: String?
	/// Whether the caller's module reaches no tier of the call and the check of every construction is certain to
	/// report the declaration whose widening makes a tier reachable: the seam's type, or a type enclosing it, which
	/// every tier's access is capped at, fails the requirement the caller's module puts on it. A seam whose tree makes
	/// such a call takes the call's parameters as pass-throughs but reports no omission of its own for them: the
	/// report is the type's. `false` where the caller reaches a tier and where the caller runs no check: the omission is
	/// then reported as any other receive's is.
	public let unreachableTierIsReported: Bool
}

/// What a run of `generate` tells the dependency tree generator about the seams among the declarations it reads.
public struct SeamResolution: Sendable {
	/// A seam declared in another module, which that module's run of `generate` generated the initializer of.
	public struct ForeignSeam: Sendable {
		public init(declaringModule: ModuleIdentity, visibleInstantiables: [TypeDescription: Instantiable], visiblePlainTypeDeclarations: [PlainTypeDeclaration], callComment: SeamCallComment, declaringModuleMockCondition: MockCondition? = nil) {
			self.declaringModule = declaringModule
			self.visibleInstantiables = visibleInstantiables
			self.visiblePlainTypeDeclarations = visiblePlainTypeDeclarations
			self.callComment = callComment
			self.declaringModuleMockCondition = declaringModuleMockCondition
		}

		/// The module that declares the seam, whose name is known: a seam whose module is unknown is built inline.
		public let declaringModule: ModuleIdentity
		/// The declarations the seam's module can see, resolved as `generate` resolves them, from which the seam's
		/// signature is computed exactly as that module computed it. The seams of one module share one map.
		public let visibleInstantiables: [TypeDescription: Instantiable]
		/// The plain type declarations of the modules whose declarations `visibleInstantiables` holds, which prove the
		/// access of the types the seam's parameters name as they prove it in the seam's module.
		public let visiblePlainTypeDeclarations: [PlainTypeDeclaration]
		/// See `SeamCall.comment`.
		public let callComment: SeamCallComment
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
		public init(declaringModule: ModuleIdentity, visibleInstantiables: [TypeDescription: Instantiable], visiblePlainTypeDeclarations: [PlainTypeDeclaration], callComment: SeamCallComment, declaringModuleMockCondition: MockCondition) {
			self.declaringModule = declaringModule
			self.visibleInstantiables = visibleInstantiables
			self.visiblePlainTypeDeclarations = visiblePlainTypeDeclarations
			self.callComment = callComment
			self.declaringModuleMockCondition = declaringModuleMockCondition
		}

		/// The module that declares the type, whose name is known: a type whose module is unknown is built inline.
		public let declaringModule: ModuleIdentity
		/// The declarations the declaring module can see, resolved as `generate` resolves them, from which the public
		/// mock's signature is computed exactly as that module computed it.
		public let visibleInstantiables: [TypeDescription: Instantiable]
		/// See `ForeignSeam.visiblePlainTypeDeclarations`.
		public let visiblePlainTypeDeclarations: [PlainTypeDeclaration]
		/// See `SeamCall.comment`.
		public let callComment: SeamCallComment
		/// The condition the declaring module generates its mocks under: its configuration's, `DEBUG` without one, read
		/// from its module info or, under the target graph, from the configuration in a file the graph attributes to it.
		public let declaringModuleMockCondition: MockCondition
	}

	public init(currentModule: ModuleIdentity, currentModuleMockCondition: MockCondition = MockCondition("DEBUG"), generatedSeams: Set<TypeDescription>, foreignSeams: [TypeDescription: ForeignSeam], foreignPublicMocks: [TypeDescription: ForeignPublicMock] = [:], foreignDeclarationsSeenByModule: [String: ForeignDeclarations]? = nil, callersComputeFromTargetGraph: Bool = false, callersVisibleInstantiables: [TypeDescription: Instantiable]? = nil, callersVisiblePlainTypeDeclarations: [PlainTypeDeclaration] = [], carriesUnreadTypeComment: Bool = false) {
		self.carriesUnreadTypeComment = carriesUnreadTypeComment
		self.foreignDeclarationsSeenByModule = foreignDeclarationsSeenByModule
		self.currentModule = currentModule
		self.currentModuleMockCondition = currentModuleMockCondition
		self.generatedSeams = generatedSeams
		self.foreignSeams = foreignSeams
		self.foreignPublicMocks = foreignPublicMocks
		self.callersComputeFromTargetGraph = callersComputeFromTargetGraph
		self.callersVisibleInstantiables = callersVisibleInstantiables
		self.callersVisiblePlainTypeDeclarations = callersVisiblePlainTypeDeclarations
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
	/// The seams other modules declare, by concrete type: under a build system that runs `generate` once per module,
	/// those of the modules whose `.safedi` this run was given, never those it reads only in their views, which
	/// `foreignDeclarationsSeenByModule` holds; under the plugin's target graph, those of every module the graph lists. A
	/// seam declared with `generateDependencyTree: true` that is in neither set – one whose module SafeDI does not know:
	/// declared in a directory a `#SafeDIConfiguration` adds, or in a file no target of the plugin's graph lists – has
	/// no set of declarations its signature could be computed from, so every tree builds it inline, as any other type.
	public let foreignSeams: [TypeDescription: ForeignSeam]
	/// The `generateMock: .public` types other modules declare, by concrete type, read from the same modules as
	/// `foreignSeams`. One whose module SafeDI does not know is in neither this map nor the module's own files, and
	/// every mock tree builds it inline, as any other type.
	public let foreignPublicMocks: [TypeDescription: ForeignPublicMock]
	/// Under a build system that runs `generate` once per module, the seams and public mocks each module whose
	/// signatures a nested computation computes sees among the modules it depends on, by that module's name, read from
	/// the views the `.safedi` files carry; `nil` under the plugin's target graph, where `foreignSeams` and
	/// `foreignPublicMocks` hold every module's. A seam or public mock only a view holds is never in the global maps,
	/// which this module's own trees read by type: a type of this module's that shares its name is never taken for it.
	public let foreignDeclarationsSeenByModule: [String: ForeignDeclarations]?

	/// The seams and public mocks a module sees among the modules it depends on, by concrete type.
	public struct ForeignDeclarations: Sendable {
		public init(seams: [TypeDescription: ForeignSeam], publicMocks: [TypeDescription: ForeignPublicMock]) {
			self.seams = seams
			self.publicMocks = publicMocks
		}

		public let seams: [TypeDescription: ForeignSeam]
		public let publicMocks: [TypeDescription: ForeignPublicMock]
	}

	/// The seams and public mocks a nested computation of the signatures of `moduleName`'s seams and public mocks reads,
	/// which are those that module's own run read: from the views under a build system that runs `generate` once per
	/// module, and from the global maps under the target graph.
	public func foreignDeclarations(seenByModuleNamed moduleName: String) -> ForeignDeclarations {
		if let foreignDeclarationsSeenByModule {
			foreignDeclarationsSeenByModule[moduleName] ?? ForeignDeclarations(seams: [:], publicMocks: [:])
		} else {
			ForeignDeclarations(seams: foreignSeams, publicMocks: foreignPublicMocks)
		}
	}

	/// This resolution as a nested computation of the signatures of `moduleName`'s seams reads it: with the seams and
	/// public mocks that module's own run read in place of this module's.
	public func resolution(seenByModuleNamed moduleName: String) -> SeamResolution {
		let foreignDeclarations = foreignDeclarations(seenByModuleNamed: moduleName)
		return SeamResolution(
			currentModule: currentModule,
			currentModuleMockCondition: currentModuleMockCondition,
			generatedSeams: generatedSeams,
			foreignSeams: foreignDeclarations.seams,
			foreignPublicMocks: foreignDeclarations.publicMocks,
			foreignDeclarationsSeenByModule: foreignDeclarationsSeenByModule,
			callersComputeFromTargetGraph: callersComputeFromTargetGraph,
			callersVisibleInstantiables: callersVisibleInstantiables,
			callersVisiblePlainTypeDeclarations: callersVisiblePlainTypeDeclarations,
			carriesUnreadTypeComment: carriesUnreadTypeComment,
		)
	}

	/// Whether the modules that call this module's seams compute their signatures from the build system's target
	/// graph, which lists the files of each target: under the SwiftPM plugin, every seam's tree must then reach only
	/// declarations the graph attributes to a module, since a caller cannot see a declaration in a directory this
	/// module's `#SafeDIConfiguration` adds, and its call would name an enum the seam's module did not generate.
	public let callersComputeFromTargetGraph: Bool
	/// The declarations the modules that call this module's seams see, resolved as `generate` resolves them, when
	/// they differ from what this run sees, else `nil`: under the target graph, the files the graph attributes to
	/// this module and the modules it depends on, without the directories this module's `#SafeDIConfiguration` adds.
	/// Under a build system that runs `generate` once per module the callers see exactly what this run reads, every
	/// module info naming its module, so this is `nil` there. A seam this module generates whose signature,
	/// computed over these declarations, differs from the one computed over what this run sees is an error at the
	/// seam: the callers' calls would not match the initializer. `nil` too when this module's name is unknown, since
	/// every caller then builds its seams inline and computes no signature.
	public let callersVisibleInstantiables: [TypeDescription: Instantiable]?
	/// The plain type declarations of the modules whose declarations `callersVisibleInstantiables` holds, each with the
	/// module that declares it: a declaration whose module SafeDI does not know is one the callers cannot see.
	public let callersVisiblePlainTypeDeclarations: [PlainTypeDeclaration]

	/// Whether the code this run generates names, in a comment, the types its `public` declarations name that no
	/// declaration it reads declares, which it counts as `public` (`UnreadTypeComment`): a run that is no build tool
	/// plugin's, under Bazel, Tuist or a custom script, which reads only the modules whose module info it is given, so a
	/// `package` type of a first-party module that does not run SafeDI is one of them. A plugin's run reads every
	/// first-party module, and the types it does not read are another package's or a binary target's, which `package`
	/// access does not reach.
	public let carriesUnreadTypeComment: Bool

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

/// The comment a generated call of another module's seam or public mock carries on the line that names the enum the
/// declaring module generated beside the initializer or mock, saying what to do when that line does not compile.
public enum SeamCallComment: Hashable, Sendable {
	/// No comment: the call is of a seam this module declares, whose code this run generates.
	case noComment
	/// The SwiftPM plugin's: it cannot tell whether a dependency target applies the plugin, so the comment says to add
	/// the plugin to the target that declares the type.
	case plugin
	/// A run that read the declaring module's `.safedi` file, which that module's run of `generate` wrote beside the code
	/// it generated: the line fails to compile only when that code is not compiled into the module, so the comment says
	/// how each integration that writes module info compiles it in.
	case moduleInfo(declaringModuleName: String)

	/// The comment for a call of `type`'s seam or public mock, or `nil` for `noComment`.
	public func text(for type: TypeDescription) -> String? {
		switch self {
		case .noComment:
			nil
		case .plugin:
			"// If this line does not compile, add the SafeDI plugin to the target that declares \(type.asSource)."
		case let .moduleInfo(declaringModuleName):
			"// If this line does not compile, compile the code SafeDI generates for module \(declaringModuleName) into \(declaringModuleName): under Bazel, add \(declaringModuleName)'s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes."
		}
	}

	/// `text(for:)` after a space, to end the line with, or an empty string for `noComment`.
	func lineEnd(for type: TypeDescription) -> String {
		text(for: type).map { " \($0)" } ?? ""
	}
}
