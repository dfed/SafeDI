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
/// generated code calls, which keep it apart from the plain initializer people call, which a module generates only
/// when its configuration sets `generatePlainDependencyTreeInitializers`: labels name no type and no availability, so a
/// stale call that writes the right labels still compiles without the enum. Nothing a signature holds depends on that
/// setting, so no caller reads another module's.
///
/// The signature and its parameters and receivers carry diagnostic payload – where each receive is declared – so none
/// is `Equatable`: a comparison for meaning goes through a projection that states what it compares, `callShape` for
/// what a call depends on and `settledContent` for what settling a module's seams solves for.
public struct SeamSignature: Sendable {
	/// A receive inside a seam's tree that a pass-through parameter fulfills: what a seam that passes the parameter
	/// on reports when a tier of its own cannot take it.
	public struct Receiver: Codable, Sendable {
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
	public struct NestedSeamCall: Codable, Sendable {
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
	public struct Parameter: Codable, Sendable {
		/// A value holding each stored property as given, which a module info file reads back.
		public init(storing property: Property, isPassThrough: Bool, access: AccessLevel, accessCause: TypeAccessProof.Cause?, tierAccess: AccessLevel, isOnlyIfAvailable: Bool, requiredThroughAlias: Bool, receivers: [Receiver], nestedSeamCall: NestedSeamCall?, deferral: Deferral, internalName: String, otherInitializerArgumentsAccess: AccessLevel) {
			self.property = property
			self.isPassThrough = isPassThrough
			self.access = access
			self.accessCause = accessCause
			self.tierAccess = tierAccess
			self.isOnlyIfAvailable = isOnlyIfAvailable
			self.requiredThroughAlias = requiredThroughAlias
			self.receivers = receivers
			self.nestedSeamCall = nestedSeamCall
			self.deferral = deferral
			self.internalName = internalName
			self.otherInitializerArgumentsAccess = otherInitializerArgumentsAccess
		}

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
		/// read it inline, when a receiver is first built. The plain initializer for people, when the seam's module
		/// generates one, takes every parameter by value (`plainSpelling`), so a call cannot capture its caller.
		public let deferral: Deferral
		/// The name the generated initializer binds a deferred parameter's autoclosure to: `__safeDI_<label>`, renamed
		/// past every builder function name in the seam's tree, which would shadow it. Unused for a parameter taken by
		/// value.
		public let internalName: String

		/// How the generated initializer takes a parameter.
		public enum Deferral: Codable, Hashable, Sendable {
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

		/// The parameter as a tier's plain initializer declares it: by value, under its label alone. An underscored name
		/// would keep the initializer out of the module's symbol graph, which is what documentation is generated from. No
		/// parameter has a default, so every call passes every one.
		func plainSpelling(amongTypesDeclaredEscaping typesDeclaredEscaping: Set<TypeDescription>) -> String {
			// The closure of the initializer only generated code calls captures a deferred parameter, so a function type is
			// `@escaping` here even though that initializer takes it behind an `@autoclosure`.
			property.functionParameterSource(amongTypesDeclaredEscaping: typesDeclaredEscaping)
		}

		/// The parameter as the initializer only generated code calls declares it: under `generatedOnlyArgumentLabel`, a
		/// deferred parameter as an `@autoclosure` bound to `internalName`, which a call passes `nil` for where it holds
		/// nothing.
		func generatedOnlySpelling(amongTypesDeclaredEscaping typesDeclaredEscaping: Set<TypeDescription>) -> String {
			switch deferral {
			case .none:
				"\(generatedOnlyArgumentLabel) \(property.functionParameterSource(amongTypesDeclaredEscaping: typesDeclaredEscaping))"
			case let .deferred(isSendable):
				"\(internalName == generatedOnlyArgumentLabel ? internalName : "\(generatedOnlyArgumentLabel) \(internalName)"): @autoclosure @escaping\(isSendable ? " @Sendable" : "") () -> \(property.typeDescription.asSource)"
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
	public struct Hole: Codable, Sendable {
		/// A value holding each stored property as given, which a module info file reads back.
		public init(storing ownerType: TypeDescription, declaringModuleNames: [String], property: Property, instantiatedType: TypeDescription, declarationLocation: Dependency.DeclarationLocation?, erasedToConcreteExistential: Bool, sitePath: [Property], declaredSitePath: [DeclaredProperty], fillPropertyStack: [Property], fillConcreteTypeStack: [TypeDescription], builderLabel: String, narrowerTierBuilderLabels: [AccessLevel: String], internalName: String, scopeSeamType: TypeDescription, scopeSeamModule: ModuleIdentity, typesToOwner: [PathType], scopeTypeName: String, enumPlace: EnumPlace?, wrapperFunctionName: String?, fields: [Field], tierAccess: AccessLevel, accessCause: TypeAccessProof.Cause?, uncarriedDeclarations: [UncarriedDeclaration], cycleReentryDeclarations: [CycleReentryDeclaration], reenteringCallDeclarations: [ReenteringCallDeclaration], reenteringPlaceFields: [ReenteringPlaceField], declarationsHiddenByFields: [DeclarationHiddenByField], innerSeamType: TypeDescription?, passedUpRoute: [DeclaredProperty], isSendable: Bool) {
			storage = Storage(Fields(storing: ownerType, declaringModuleNames: declaringModuleNames, property: property, instantiatedType: instantiatedType, declarationLocation: declarationLocation, erasedToConcreteExistential: erasedToConcreteExistential, sitePath: sitePath, declaredSitePath: declaredSitePath, fillPropertyStack: fillPropertyStack, fillConcreteTypeStack: fillConcreteTypeStack, builderLabel: builderLabel, narrowerTierBuilderLabels: narrowerTierBuilderLabels, internalName: internalName, scopeSeamType: scopeSeamType, scopeSeamModule: scopeSeamModule, typesToOwner: typesToOwner, scopeTypeName: scopeTypeName, enumPlace: enumPlace, wrapperFunctionName: wrapperFunctionName, fields: fields, tierAccess: tierAccess, accessCause: accessCause, uncarriedDeclarations: uncarriedDeclarations, cycleReentryDeclarations: cycleReentryDeclarations, reenteringCallDeclarations: reenteringCallDeclarations, reenteringPlaceFields: reenteringPlaceFields, declarationsHiddenByFields: declarationsHiddenByFields, innerSeamType: innerSeamType, passedUpRoute: passedUpRoute, isSendable: isSendable))
		}

		/// A value in scope at the site, which the scope struct the builder is handed carries.
		public struct Field: Codable, Sendable {
			public init(property: Property, access: AccessLevel, accessCause: TypeAccessProof.Cause? = nil, declaringType: TypeDescription, declarationLocation: Dependency.DeclarationLocation?, isReceivedOnlyIfAvailable: Bool = false, parameterTakingType: TypeDescription? = nil, deferral: Parameter.Deferral = .none, bindsMemo: Bool = false, isSeamParameter: Bool = false, isBoundByPublicMockRoot: Bool = false, seamParameterOrigin: SeamParameterOrigin? = nil) {
				self.property = property
				self.isBoundByPublicMockRoot = isBoundByPublicMockRoot
				self.bindsMemo = bindsMemo
				self.deferral = deferral
				self.isSeamParameter = isSeamParameter
				self.access = access
				self.accessCause = accessCause
				self.declaringType = declaringType
				self.declarationLocation = declarationLocation
				self.isReceivedOnlyIfAvailable = isReceivedOnlyIfAvailable
				self.parameterTakingType = parameterTakingType
				self.seamParameterOrigin = seamParameterOrigin
			}

			/// What a field bound from a parameter of a seam says about that parameter: which seam it is and where it is
			/// declared, whether the parameter passes a receive through or is the seam's own property, and the receives in
			/// its tree the parameter passes its value to (the seam's own receive, for its own property). The seam is the one
			/// whose tree holds the site, or, for a field a fill on the site's path binds from the struct of a seam it fills,
			/// that seam, whose parameter the field still is. A fill whose tree receives the label in a form no one parameter
			/// takes together with the parameter's gives that seam's tree the label in two forms, which the seam reports
			/// where it sees both.
			public struct SeamParameterOrigin: Codable, Sendable {
				public init(seamType: TypeDescription, seamDeclarationLocation: Dependency.DeclarationLocation?, isPassThrough: Bool, receivers: [Receiver]) {
					self.seamType = seamType
					self.seamDeclarationLocation = seamDeclarationLocation
					self.isPassThrough = isPassThrough
					self.receivers = receivers
				}

				/// The origin of `parameter`, a parameter of `seam` that a fill's reader is told `declaringType` declares at
				/// `declarationLocation`: the seam's own property is received by the seam itself, where it declares it. `receivers`,
				/// where given, are the declarations that receive the parameter's form instead, as a public mock's root level
				/// records them.
				init(of parameter: Parameter, of seam: Instantiable, declaringType: TypeDescription, declarationLocation: Dependency.DeclarationLocation?, receivers: [Receiver]? = nil) {
					self.init(
						seamType: seam.concreteInstantiable,
						seamDeclarationLocation: seam.declarationLocation,
						isPassThrough: parameter.isPassThrough,
						receivers: receivers ?? (parameter.receivers.isEmpty
							? [Receiver(property: parameter.property, declaringType: declaringType, declarationLocation: declarationLocation, access: parameter.access)]
							: parameter.receivers),
					)
				}

				public let seamType: TypeDescription
				public let seamDeclarationLocation: Dependency.DeclarationLocation?
				public let isPassThrough: Bool
				public let receivers: [Receiver]
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
			/// the seam, the first type in the tree that receives it, and for a parameter of a builder function a lazy cycle
			/// closes on, the first type in the function's body that receives it.
			public let declaringType: TypeDescription
			public let declarationLocation: Dependency.DeclarationLocation?
			/// Whether the field passes through a parameter the seam's tree receives only if available, so a caller
			/// may pass `nil` for it.
			public let isReceivedOnlyIfAvailable: Bool
			/// For a parameter of a builder function a lazy cycle closes on (`CycleParameter`), the type whose builder
			/// function takes it, else `nil`.
			public let parameterTakingType: TypeDescription?
			/// How the seam takes the parameter the field is bound from (`SeamSignature.Parameter.deferral`): `.none` for a
			/// field bound from a declaration inside the seam's tree, or from a parameter taken by value. The seam's tree
			/// holds a deferred parameter in a `LazilyInstantiated` (`SendableLazilyInstantiated` when `@Sendable`), which
			/// it hands the struct, so the value is created when a fill first reads the field, as inline.
			public let deferral: Parameter.Deferral
			/// Whether a fill that reads this deferred parameter's field from the struct binds its memo, read under `memoName`,
			/// whose instance the fill's tree reads where it reads the value. The field keeps its own property, which decides
			/// what it satisfies.
			public let bindsMemo: Bool
			/// Whether the field is bound from a parameter of the seam, which the seam's caller passes: a call that opens the
			/// seam again inside a fill passes it the nearest declaration of its label there, which a place of the seam opened
			/// again carries too.
			public let isSeamParameter: Bool
			/// Whether the field is bound by a public mock's root, before its tree, from a value it receives: a parameter of
			/// `mock()`, or a received dependency the mock builds where its caller passes `nil`. A call of the mock from another
			/// module's generated mock hands it such a value from the caller's scope, whose own declaration a fill then reads
			/// (`Scope`'s `callersOwnLabels(amongLabelsOf:at:reading:handedFrom:by:)`).
			public let isBoundByPublicMockRoot: Bool
			/// For a field bound from a parameter of a seam, or a value a public mock's root level binds from what it receives
			/// (`isBoundByPublicMockRoot`), that parameter's receives and the seam's or mocked type's declaration; `nil` for a
			/// field bound from a declaration inside the tree.
			public let seamParameterOrigin: SeamParameterOrigin?

			/// Whether the field is bound from a deferred parameter (`SeamSignature.Parameter.isDeferred`).
			public var isDeferredParameter: Bool {
				deferral != .none
			}

			/// The type of the `LazilyInstantiated` (or `SendableLazilyInstantiated`) a deferred parameter's field holds,
			/// or `nil` for a field held by value: a wrapper of the parameter's type, as the seam's tree holds it.
			public var memoType: TypeDescription? {
				guard case let .deferred(isSendable) = deferral else { return nil }
				return .simple(name: isSendable ? Dependency.sendableLazilyInstantiatedType : Dependency.lazilyInstantiatedType, generics: [property.typeDescription])
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
		public struct UncarriedDeclaration: Codable, Sendable {
			/// A value holding each stored property as given, which a module info file reads back.
			public init(storing property: Property, declaringType: TypeDescription, declarationLocation: Dependency.DeclarationLocation?, parameterTakingType: TypeDescription?, builtAfter: Property?, reason: Reason, isBoundFromCallersArgument: Bool, isBuildableAboveSeam: Bool, labelsHeldAboveSeam: Set<String>, placesInTree: [Site], holdsPlaceFilledElsewhere: Bool) {
				self.property = property
				self.declaringType = declaringType
				self.declarationLocation = declarationLocation
				self.parameterTakingType = parameterTakingType
				self.builtAfter = builtAfter
				self.reason = reason
				self.isBoundFromCallersArgument = isBoundFromCallersArgument
				self.isBuildableAboveSeam = isBuildableAboveSeam
				self.labelsHeldAboveSeam = labelsHeldAboveSeam
				self.placesInTree = placesInTree
				self.holdsPlaceFilledElsewhere = holdsPlaceFilledElsewhere
			}

			public init(property: Property, declaringType: TypeDescription, declarationLocation: Dependency.DeclarationLocation?, parameterTakingType: TypeDescription? = nil, builtAfter: Property?, reason: Reason, isBoundFromCallersArgument: Bool = false) {
				self.property = property
				self.declaringType = declaringType
				self.declarationLocation = declarationLocation
				self.parameterTakingType = parameterTakingType
				self.builtAfter = builtAfter
				self.reason = reason
				self.isBoundFromCallersArgument = isBoundFromCallersArgument
			}

			/// Why the declaration is bound after the site.
			public enum Reason: Codable, Sendable {
				/// Its type receives `builtAfter`, the scope on the site's path, only if available.
				case receivesPathScopeOnlyIfAvailable(type: TypeDescription)
				/// Its type requires `carrier`, a sibling that holds another site.
				case requiresOtherCarrier(type: TypeDescription, carrier: Property)
				/// It is an instantiator on the site's path, still being built where the site is: the hole itself, or the
				/// property of a scope on the path.
				case instantiatorBuildingSite
				/// Any other reason: a scope on the site's path that is no instantiator, still being built, the hole itself where
				/// it is no instantiator, or a declaration bound after the site.
				case other
				/// `seam`, declared in `module`, binds it in its tree on a path to a call that presents `place`, whose builder
				/// `seam` passes up: inline, a receive of its label would read it, and `seam`'s caller, which fills the builder,
				/// does not hold it.
				case boundByPassingUpSeam(seam: TypeDescription, module: ModuleIdentity, place: PresentedPlace)
				/// It is bound outside the innermost `@Sendable` function that builds the site – `functionProperty`'s, of the kind
				/// `function` says – and a place is handed only what that function binds. `isForwarded` says the declaring type
				/// forwards it. Where it is a parameter of a builder function a lazy cycle closes on, `cycleParameter` says whose,
				/// and what the cycle passes it. Where the declaring type, the seam or a type in its tree, receives it under an
				/// alias, `alias` says what fulfills it.
				case boundOutsideSendableFunction(functionProperty: Property, function: SendableFunction, isForwarded: Bool, cycleParameter: CycleParameterOrigin?, alias: AliasOrigin?)
			}

			/// The `@Sendable` function a place is built inside, which decides whether a value can be forwarded into it.
			public enum SendableFunction: Codable, Sendable {
				/// The builder function of an instantiator, which builds `builtType` and takes its forwarded properties.
				case instantiator(builtType: TypeDescription)
				/// The builder function of a `SendableLazilyInstantiated`, which builds `builtType`, and would take its forwarded
				/// properties as an instantiator: a lazy wrapper is handed none.
				case sendableLazyWrapper(builtType: TypeDescription)
				/// A function no forwarded value can reach: a `@Sendable` fill, whose fulfiller takes what the hole's type, which
				/// another module declares, forwards; the `Sendable` wrapper the place is held in; or the builder function of a
				/// value built by value, which a cycle makes `@Sendable`, where a forwarded property would need an instantiator the
				/// cycle cannot build by value.
				case other
			}

			/// An alias that binds a label to another property than the one of its own label: `fulfillingProperty`, the
			/// caller's where `isSeams`, the seam's own alias, and otherwise a property of the seam's tree.
			public struct AliasOrigin: Codable, Sendable {
				public init(fulfillingProperty: Property, isSeams: Bool) {
					self.fulfillingProperty = fulfillingProperty
					self.isSeams = isSeams
				}

				public let fulfillingProperty: Property
				public let isSeams: Bool
			}

			/// A parameter of the builder function of `takingType` that a lazy cycle closes on: a cycle inside `takingType`'s
			/// tree passes it the `property` that `declaringType` declares, or forwards where `isForwarded`, at
			/// `declarationLocation`.
			public struct CycleParameterOrigin: Codable, Sendable {
				public init(takingType: TypeDescription, property: Property, declaringType: TypeDescription, declarationLocation: Dependency.DeclarationLocation?, isForwarded: Bool) {
					self.takingType = takingType
					self.property = property
					self.declaringType = declaringType
					self.declarationLocation = declarationLocation
					self.isForwarded = isForwarded
				}

				public let takingType: TypeDescription
				public let property: Property
				public let declaringType: TypeDescription
				public let declarationLocation: Dependency.DeclarationLocation?
				public let isForwarded: Bool
			}

			/// The place a call presents whose builder a seam passes up, which a message about a declaration bound on the path
			/// to that call names: a place inside a fill inherits what the place the fill fills does not carry.
			public struct PresentedPlace: Codable, Sendable {
				/// A value holding each stored property as given, which a module info file reads back.
				public init(storing seamType: TypeDescription, ownerType: TypeDescription, property: Property, instantiatedType: TypeDescription, builderLabel: String, caseName: String?, isBuiltBySendableBuilder: Bool) {
					self.seamType = seamType
					self.ownerType = ownerType
					self.property = property
					self.instantiatedType = instantiatedType
					self.builderLabel = builderLabel
					self.caseName = caseName
					self.isBuiltBySendableBuilder = isBuiltBySendableBuilder
				}

				init(_ hole: Hole) {
					seamType = hole.scopeSeamType
					ownerType = hole.ownerType
					property = hole.property
					instantiatedType = hole.instantiatedType
					builderLabel = hole.builderLabel
					caseName = hole.enumPlace?.caseName
					isBuiltBySendableBuilder = hole.enumPlace?.isBuiltBySendableBuilder ?? false
				}

				/// The seam whose tree holds the place.
				public let seamType: TypeDescription
				public let ownerType: TypeDescription
				public let property: Property
				public let instantiatedType: TypeDescription
				/// The label of the builder the place's seam takes, and the name of the place's case in that builder's enum, if it has
				/// one, unqualified: a diagnostic names no generated type.
				public let builderLabel: String
				public let caseName: String?
				/// Whether a `@Sendable` function builds the place, which is then handed only what that function binds.
				public let isBuiltBySendableBuilder: Bool

				/// Whether this is `hole`'s own place as a call presents it, by whichever seam presents it (a seam's call of itself, or
				/// of a seam that passes the place back, as in a cycle of seams), rather than another place a declaration reaches it
				/// through, such as the hole of a fill on its path. Two places of one owner type and property count as one, so a
				/// declaration that could be either is judged as the place's own.
				func isPresentation(of hole: Hole) -> Bool {
					ownerType == hole.ownerType && property == hole.property
				}
			}

			public let property: Property
			public let declaringType: TypeDescription
			public let declarationLocation: Dependency.DeclarationLocation?
			/// For a parameter of a builder function a lazy cycle closes on (`CycleParameter`), the type whose builder
			/// function takes it, else `nil`: `declaringType` is then the first type in the function's body that receives it.
			public let parameterTakingType: TypeDescription?
			/// The property of the scope on the site's path that the declaration's scope builds before it, or `nil`.
			public let builtAfter: Property?
			public let reason: Reason
			/// Whether it is a received value a public mock binds at its root from the optional parameter its caller passes
			/// its own nearest declaration of the label to: a fill of the call reads the caller's declaration where the caller
			/// binds this declaration's form, which is then the value the mock binds (`Scope.fillUnderConstruction`). A seam or
			/// public mock that calls the mock and passes the place up keeps it so: the mock binds what that type's tree passes
			/// it, which is the passing type's own caller's where nothing on the path to the call declares the label, and a
			/// declaration on that path is reported where the place is filled (`boundByPassingUpSeam`).
			public let isBoundFromCallersArgument: Bool
			/// Whether the seam's tree instantiates it with a tree that receives only labels a type above the seam would hold
			/// for it (`labelsHeldAboveSeam`), so that such a type could build it and the seam receive it instead. Where that
			/// tree holds places, whose fills the seam's module does not see, the module that fills them keeps it only where
			/// each place's fill receives only those labels too (`resolvingBuildabilityAboveSeam(fillsOfCall:)`).
			public internal(set) var isBuildableAboveSeam = false
			/// Where `isBuildableAboveSeam`, the labels a type above the seam would hold for the declaration's tree: those the
			/// seam receives from its caller, and the declaration's own, which that type would then declare.
			public internal(set) var labelsHeldAboveSeam = Set<String>()
			/// Where `isBuildableAboveSeam`, the sites of the places the declaration's tree holds or passes up.
			public internal(set) var placesInTree = [Site]()
			/// Whether a module whose fill the reading module does not see fills one of `placesInTree`
			/// (`resolvingBuildabilityAboveSeam(fillsOfCall:)`), so that no remedy moves the declaration.
			public internal(set) var holdsPlaceFilledElsewhere = false
		}

		/// A declaration a cycle in the seam's tree hands the site's owner when it builds it again: the site lies in the body
		/// of a builder function a cycle-closing scope calls, and a scope between that function and the cycle-closing scope
		/// declares the label, while the label's nearest declaration at the site is outside the function. Inline, the type
		/// built again receives that declaration through the function's parameter; a fill, which reads the scope struct or
		/// the caller's scope, reads the same value at every level of the cycle.
		public struct CycleReentryDeclaration: Codable, Sendable {
			public init(property: Property, declaringType: TypeDescription, declarationLocation: Dependency.DeclarationLocation?, parameterTakingType: TypeDescription?, closedOnProperty: Property, closedOnBuiltType: TypeDescription, closedOnDeclaringType: TypeDescription, reenteringType: TypeDescription) {
				self.property = property
				self.declaringType = declaringType
				self.declarationLocation = declarationLocation
				self.parameterTakingType = parameterTakingType
				self.closedOnProperty = closedOnProperty
				self.closedOnBuiltType = closedOnBuiltType
				self.closedOnDeclaringType = closedOnDeclaringType
				self.reenteringType = reenteringType
			}

			/// The declaration between the function and the cycle-closing scope, or, where a scope between takes the label as
			/// a parameter of a builder function a cycle nested inside closes on, the declaration that cycle passes it.
			public let property: Property
			public let declaringType: TypeDescription
			public let declarationLocation: Dependency.DeclarationLocation?
			/// The type whose builder function takes the label as a parameter between the function and the cycle-closing
			/// scope, when a cycle nested inside passes it `property`, or `nil` when `declaringType` is between itself.
			public let parameterTakingType: TypeDescription?
			/// The property whose builder function the cycle closes on, the concrete type it builds, which an erased instantiator's
			/// type does not name, and the type that declares it.
			public let closedOnProperty: Property
			public let closedOnBuiltType: TypeDescription
			public let closedOnDeclaringType: TypeDescription
			/// The type that instantiates `closedOnProperty` again, closing the cycle.
			public let reenteringType: TypeDescription
		}

		/// A declaration on the path from the root of a fill of the seam call whose tree holds this place, inside another fill
		/// of that call, to a call inside it that builds the filled seam again and passes the fill on: inline, a receive of its
		/// label beneath the place would read it on the route through that call, while the module that fills this place
		/// hands the one fill the value of the outer call. Recorded by the seam whose call fills the place built again, for a
		/// label the visible build rejects a read of (`declarationBoundOnPathToReenteringCall`): one the fill built again holds
		/// no field of, nor any scope between that fill's root and the place declares. A field of the label bound above the
		/// seam call does not lift it, a deliberate loss of a shape inline builds correctly, until each route is handed its own
		/// value.
		public struct ReenteringCallDeclaration: Codable, Sendable {
			public init(property: Property, declaringType: TypeDescription, declarationLocation: Dependency.DeclarationLocation?, pathPlace: UncarriedDeclaration.PresentedPlace, callingType: TypeDescription, callProperty: Property, calledSeam: TypeDescription, reenteredPlace: UncarriedDeclaration.PresentedPlace, reenteredSeamModule: ModuleIdentity, fillingModule: ModuleIdentity) {
				self.property = property
				self.declaringType = declaringType
				self.declarationLocation = declarationLocation
				self.pathPlace = pathPlace
				self.callingType = callingType
				self.callProperty = callProperty
				self.calledSeam = calledSeam
				self.reenteredPlace = reenteredPlace
				self.reenteredSeamModule = reenteredSeamModule
				self.fillingModule = fillingModule
			}

			/// The declaration, by the type that declares it, and where.
			public let property: Property
			public let declaringType: TypeDescription
			public let declarationLocation: Dependency.DeclarationLocation?
			/// The place whose fill's tree holds the path.
			public let pathPlace: UncarriedDeclaration.PresentedPlace
			/// The type whose scope makes the call, the property it builds the seam under, and the seam it calls: the filled seam,
			/// or a seam that builds it again, such as one that passes its place up, which the message names as written.
			public let callingType: TypeDescription
			public let callProperty: Property
			public let calledSeam: TypeDescription
			/// The place of the fill the call is passed, which holds this place, and the module of its seam.
			public let reenteredPlace: UncarriedDeclaration.PresentedPlace
			public let reenteredSeamModule: ModuleIdentity
			/// The module that fills `reenteredPlace`: the module of the seam whose call the fills are.
			public let fillingModule: ModuleIdentity
		}

		/// A field, not bound from a seam parameter, of the place whose fill makes a call that builds the filled seam again and
		/// passes a fill of the same seam call on, with that call: inline, the seam built again sits beneath that place, so a
		/// read of the label the passed fill makes from the caller's scope finds the field.
		public struct FieldOfReenteringPlace: Codable, Sendable {
			public init(field: Field, reenteringPlace: UncarriedDeclaration.PresentedPlace, callProperty: Property, calledSeam: TypeDescription) {
				self.field = field
				self.reenteringPlace = reenteringPlace
				self.callProperty = callProperty
				self.calledSeam = calledSeam
			}

			public let field: Field
			/// The place whose fill makes the call.
			public let reenteringPlace: UncarriedDeclaration.PresentedPlace
			/// The property the call builds the seam under, and the seam it calls: the filled seam, or a seam that builds it
			/// again, such as one that passes its place up, which the message names as written.
			public let callProperty: Property
			public let calledSeam: TypeDescription
		}

		/// A field of a place whose fill builds the filled seam again (`FieldOfReenteringPlace`), recorded on a place inside the
		/// fill that call is passed, which a caller fills: by the seam whose call fills the place built again, for a label the
		/// visible build rejects a read of from the caller's scope (`fieldOfReenteringPlace`), one the fill built again holds no
		/// field, cycle re-entry or uncarried declaration of, that no scope between that fill's root and the place declares, and
		/// that no declaration on the path to the call hides (`ReenteringCallDeclaration`, which the visible build reports
		/// first). A field of the label bound above the seam call does not lift it, as for `ReenteringCallDeclaration`.
		public struct ReenteringPlaceField: Codable, Sendable {
			public init(carried: FieldOfReenteringPlace, reenteredPlace: UncarriedDeclaration.PresentedPlace, reenteredSeamModule: ModuleIdentity, fillingModule: ModuleIdentity) {
				self.carried = carried
				self.reenteredPlace = reenteredPlace
				self.reenteredSeamModule = reenteredSeamModule
				self.fillingModule = fillingModule
			}

			public let carried: FieldOfReenteringPlace
			/// The place of the fill the call is passed, which holds this place, and the module of its seam.
			public let reenteredPlace: UncarriedDeclaration.PresentedPlace
			public let reenteredSeamModule: ModuleIdentity
			/// The module that fills `reenteredPlace`: the module of the seam whose call the fills are.
			public let fillingModule: ModuleIdentity
		}

		/// A declaration on the site's path that a fill's field of its label hides, where that field is a parameter of the seam
		/// whose values struct carries it: a seam on the route to the place, or the seam whose tree holds the fill, declares the
		/// label above its call of the seam that receives it, and the fill of the place the called seam passes up binds the
		/// struct's field, nearer the place. Inline, a receive of the declaration's form beneath the place reads the declaration;
		/// the struct carries only the field, so a fill of this place that reads that form finds no value of the declaration's
		/// (`declarationHiddenByField`). Kept apart from `uncarriedDeclarations`, which a field of the same label lifts.
		public struct DeclarationHiddenByField: Codable, Sendable {
			public init(property: Property, declaringType: TypeDescription, declarationLocation: Dependency.DeclarationLocation?, calledSeam: TypeDescription, receivingSeam: TypeDescription) {
				self.property = property
				self.declaringType = declaringType
				self.declarationLocation = declarationLocation
				self.calledSeam = calledSeam
				self.receivingSeam = receivingSeam
			}

			public let property: Property
			public let declaringType: TypeDescription
			public let declarationLocation: Dependency.DeclarationLocation?
			/// The seam `declaringType` calls on the route to the place, which the message names as written.
			public let calledSeam: TypeDescription
			/// The seam whose parameter the field that hides the declaration is.
			public let receivingSeam: TypeDescription
		}

		/// A type on the way from the seam that takes a hole's builder to the hole's owner, with the module that declares it.
		public struct PathType: Codable, Sendable {
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
			fillConcreteTypeStack: [TypeDescription],
			builderLabel: String,
			internalName: String,
			scopeSeamType: TypeDescription,
			scopeSeamModule: ModuleIdentity,
			typesToOwner: [PathType],
			scopeTypeName: String,
			fields: [Field],
			tierAccess: AccessLevel,
			accessCause: TypeAccessProof.Cause? = nil,
			uncarriedDeclarations: [UncarriedDeclaration],
			cycleReentryDeclarations: [CycleReentryDeclaration],
			innerSeamType: TypeDescription? = nil,
			passedUpRoute: [DeclaredProperty] = [],
			isSendable: Bool = false,
			enumPlace: EnumPlace? = nil,
		) {
			storage = Storage(Fields(
				ownerType: ownerType,
				declaringModuleNames: declaringModuleNames,
				property: property,
				instantiatedType: instantiatedType,
				declarationLocation: declarationLocation,
				erasedToConcreteExistential: erasedToConcreteExistential,
				sitePath: sitePath,
				declaredSitePath: declaredSitePath,
				fillPropertyStack: fillPropertyStack,
				fillConcreteTypeStack: fillConcreteTypeStack,
				builderLabel: builderLabel,
				internalName: internalName,
				scopeSeamType: scopeSeamType,
				scopeSeamModule: scopeSeamModule,
				typesToOwner: typesToOwner,
				scopeTypeName: scopeTypeName,
				fields: fields,
				tierAccess: tierAccess,
				accessCause: accessCause,
				uncarriedDeclarations: uncarriedDeclarations,
				cycleReentryDeclarations: cycleReentryDeclarations,
				innerSeamType: innerSeamType,
				passedUpRoute: passedUpRoute,
				isSendable: isSendable,
				enumPlace: enumPlace,
			))
		}

		/// Every stored property of a hole, held once behind `Storage`, so that a copy of a hole retains one reference rather than
		/// each of its many fields: shaping, emitting and storing builders copies holes many times over.
		fileprivate struct Fields: Codable, Sendable {
			init(storing ownerType: TypeDescription, declaringModuleNames: [String], property: Property, instantiatedType: TypeDescription, declarationLocation: Dependency.DeclarationLocation?, erasedToConcreteExistential: Bool, sitePath: [Property], declaredSitePath: [DeclaredProperty], fillPropertyStack: [Property], fillConcreteTypeStack: [TypeDescription], builderLabel: String, narrowerTierBuilderLabels: [AccessLevel: String], internalName: String, scopeSeamType: TypeDescription, scopeSeamModule: ModuleIdentity, typesToOwner: [PathType], scopeTypeName: String, enumPlace: EnumPlace?, wrapperFunctionName: String?, fields: [Field], tierAccess: AccessLevel, accessCause: TypeAccessProof.Cause?, uncarriedDeclarations: [UncarriedDeclaration], cycleReentryDeclarations: [CycleReentryDeclaration], reenteringCallDeclarations: [ReenteringCallDeclaration], reenteringPlaceFields: [ReenteringPlaceField], declarationsHiddenByFields: [DeclarationHiddenByField], innerSeamType: TypeDescription?, passedUpRoute: [DeclaredProperty], isSendable: Bool) {
				self.ownerType = ownerType
				self.declaringModuleNames = declaringModuleNames
				self.property = property
				self.instantiatedType = instantiatedType
				self.declarationLocation = declarationLocation
				self.erasedToConcreteExistential = erasedToConcreteExistential
				self.sitePath = sitePath
				self.declaredSitePath = declaredSitePath
				self.fillPropertyStack = fillPropertyStack
				self.fillConcreteTypeStack = fillConcreteTypeStack
				self.builderLabel = builderLabel
				self.narrowerTierBuilderLabels = narrowerTierBuilderLabels
				self.internalName = internalName
				self.scopeSeamType = scopeSeamType
				self.scopeSeamModule = scopeSeamModule
				self.typesToOwner = typesToOwner
				self.scopeTypeName = scopeTypeName
				self.enumPlace = enumPlace
				self.wrapperFunctionName = wrapperFunctionName
				self.fields = fields
				self.tierAccess = tierAccess
				self.accessCause = accessCause
				self.uncarriedDeclarations = uncarriedDeclarations
				self.cycleReentryDeclarations = cycleReentryDeclarations
				self.reenteringCallDeclarations = reenteringCallDeclarations
				self.reenteringPlaceFields = reenteringPlaceFields
				self.declarationsHiddenByFields = declarationsHiddenByFields
				self.innerSeamType = innerSeamType
				self.passedUpRoute = passedUpRoute
				self.isSendable = isSendable
			}

			init(
				ownerType: TypeDescription,
				declaringModuleNames: [String],
				property: Property,
				instantiatedType: TypeDescription,
				declarationLocation: Dependency.DeclarationLocation?,
				erasedToConcreteExistential: Bool,
				sitePath: [Property],
				declaredSitePath: [DeclaredProperty],
				fillPropertyStack: [Property],
				fillConcreteTypeStack: [TypeDescription],
				builderLabel: String,
				internalName: String,
				scopeSeamType: TypeDescription,
				scopeSeamModule: ModuleIdentity,
				typesToOwner: [PathType],
				scopeTypeName: String,
				fields: [Field],
				tierAccess: AccessLevel,
				accessCause: TypeAccessProof.Cause? = nil,
				uncarriedDeclarations: [UncarriedDeclaration],
				cycleReentryDeclarations: [CycleReentryDeclaration],
				innerSeamType: TypeDescription? = nil,
				passedUpRoute: [DeclaredProperty] = [],
				isSendable: Bool = false,
				enumPlace: EnumPlace? = nil,
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
				self.fillConcreteTypeStack = fillConcreteTypeStack
				self.builderLabel = builderLabel
				self.internalName = internalName
				self.scopeSeamType = scopeSeamType
				self.scopeSeamModule = scopeSeamModule
				self.typesToOwner = typesToOwner
				self.scopeTypeName = scopeTypeName
				self.fields = fields
				self.tierAccess = tierAccess
				self.accessCause = accessCause
				self.uncarriedDeclarations = uncarriedDeclarations
				self.cycleReentryDeclarations = cycleReentryDeclarations
				self.innerSeamType = innerSeamType
				self.passedUpRoute = passedUpRoute
				self.isSendable = isSendable
				self.enumPlace = enumPlace
			}

			/// The type whose `@Instantiated` property the site builds.
			let ownerType: TypeDescription
			/// The module of the seam whose tree holds the site, when it also declares the owner and no seam passes the site up,
			/// which a spelling of the property's type or of the fulfiller's `@Forwarded` property may qualify a type with, since
			/// the fulfiller is in another module. Empty otherwise: generated code spells the property's type in the module that
			/// generates the fill, where a bare name may mean a type of that module, which its `.safedi` records only if a
			/// declaration of that module mentions it.
			let declaringModuleNames: [String]
			/// The property the site builds, as its owner declares it: the builder returns its type without its wrapper
			/// (`builtType`).
			let property: Property
			/// The type a declaration must fulfill to fill the builder: the property's instantiated type, or the type an
			/// erased property names with `fulfilledByType:`.
			let instantiatedType: TypeDescription
			/// Where the owner declares the property.
			let declarationLocation: Dependency.DeclarationLocation?
			/// Whether the property is `erasedToConcreteExistential`, which a fill wraps the fulfilling type in.
			let erasedToConcreteExistential: Bool
			/// The properties from the root of the tree that holds the site down to the owner's property, outermost first:
			/// the site's identity in that tree, which generated names are made from. Inside a fill of a passed-up hole it holds
			/// a stand-in for the seam that holds that hole (`pathBeforePropertyInItsFill`), no declaration, so a diagnostic
			/// prints `declaredSitePath` instead.
			let sitePath: [Property]
			/// The properties the code declares from the root of the tree that holds the site down to the owner's property,
			/// outermost first, inside a fill of a passed-up hole through the calls that passed it up.
			let declaredSitePath: [DeclaredProperty]
			/// The stack a fill builds the property's tree with: the properties from the root of the seam whose tree holds
			/// the site to the owner's property, innermost first, each lazily instantiated one preceded by its instance, as
			/// `Scope.createScopeGenerator` stacks them.
			let fillPropertyStack: [Property]
			/// The concrete type each entry of `fillPropertyStack` is built for, beside it: a fill's scope closes a cycle only where it
			/// repeats an entry of the same property built for the same concrete type, as inline's does.
			let fillConcreteTypeStack: [TypeDescription]
			/// The label the generated initializer takes the place's builder under: for a place in a seam's plain scope enum, that
			/// enum's builder's label.
			var builderLabel: String
			/// The label each narrower tier takes the place's builder under, where it differs from `builderLabel`
			/// (`Builder.narrowerTierLabels`).
			var narrowerTierBuilderLabels = [AccessLevel: String]()
			/// The name the generated initializer binds the builder to.
			var internalName: String
			/// The seam whose extension declares the scope struct: this seam, or the inner seam a passed-up hole is from.
			let scopeSeamType: TypeDescription
			/// The module that declares `scopeSeamType`, which a module the hole reaches through a view knows only from here.
			let scopeSeamModule: ModuleIdentity
			/// The types from the seam that takes this builder, itself excluded, to the hole's owner, outermost first: for a
			/// passed-up hole, every seam it passes through on the way to `scopeSeamType`. Empty when that seam owns the hole.
			/// Each type's module is a fact of the hole, so no order among modules decides which one a diagnostic names.
			let typesToOwner: [PathType]
			/// The name of the enum whose case the place is (`enumPlace`), or, before the builders are shaped, a name made from the
			/// place's owner and property.
			var scopeTypeName: String
			/// Where a scope enum of the seam or the public mock carries this place, once its builders are shaped.
			var enumPlace: EnumPlace?
			/// The name of the function that builds the wrapper this place is held in, or `nil` for one held by value and for a
			/// public mock's, whose function the generator names (see `SeamBuilderNames`).
			var wrapperFunctionName: String?
			/// The values a fill of the place can read from what its builder is handed: the nearest declaration of each label on
			/// the site's path that is bound before the site, inside the innermost `@Sendable` function that builds the site where
			/// one does. The seam's parameters are no field of a place built in a `@Sendable` function: a fill reads them from the
			/// caller's own scope.
			let fields: [Field]
			/// The access each tier that takes the builder must have no more than: the builder's type is as visible as the
			/// narrowest type it names – the scope struct at the access of the seam that declares it, and the property's type
			/// as the declarations the signature is computed from prove it (`TypeAccessProof`) – capped at the seam's type.
			let tierAccess: AccessLevel
			/// How the narrowest type the builder's type names is proven, which a diagnostic explains, or `nil` when every
			/// type it names is `public`.
			let accessCause: TypeAccessProof.Cause?
			/// The declarations on the site's path a fill cannot read from the scope struct.
			var uncarriedDeclarations: [UncarriedDeclaration]
			/// The declarations a cycle in the tree of the seam that holds the site hands the site's owner when it builds it
			/// again, which a fill cannot read, the first of each label.
			let cycleReentryDeclarations: [CycleReentryDeclaration]
			/// The declarations on the paths to calls inside fills of the seam call whose tree holds the place that build the
			/// filled seam again, which a fill of this place cannot read (see `ReenteringCallDeclaration`), every path's, in the
			/// order of their declarations. A copy a seam passes up keeps them all.
			var reenteringCallDeclarations = [ReenteringCallDeclaration]()
			/// The fields of places whose fills build the filled seam again that a fill of this place cannot read in their place
			/// (see `ReenteringPlaceField`), every place's, in the order of their declarations. A copy a seam passes up keeps them all.
			var reenteringPlaceFields = [ReenteringPlaceField]()
			/// The declarations on the site's path that a fill's field of their label hides (see `DeclarationHiddenByField`), each
			/// label once, the declaration the field hides. A copy a seam passes up keeps them.
			var declarationsHiddenByFields = [DeclarationHiddenByField]()
			/// The seam the tree calls that presented the hole first, when this one passes it up, or `nil` for a site of this
			/// seam's own tree.
			let innerSeamType: TypeDescription?
			/// When this seam passes the hole up, the properties from its root to the call of the seam whose tree holds the
			/// site, through the calls of every seam between, outermost first; empty for a site of this seam's own tree.
			var passedUpRoute: [DeclaredProperty]
			/// Whether the builder is `@Sendable`: the seam's tree passes it on from inside a `@Sendable` function, which
			/// captures it.
			var isSendable: Bool
		}

		/// The immutable holder of a hole's fields, which every copy of the hole shares until one of them sets a field.
		private final class Storage: Sendable {
			init(_ fields: Fields) {
				self.fields = fields
			}

			let fields: Fields
		}

		private var storage: Storage

		public init(from decoder: any Decoder) throws {
			storage = try Storage(Fields(from: decoder))
		}

		public func encode(to encoder: any Encoder) throws {
			try storage.fields.encode(to: encoder)
		}

		/// The type whose `@Instantiated` property the site builds.
		public var ownerType: TypeDescription {
			storage.fields.ownerType
		}

		/// The module of the seam whose tree holds the site, when it also declares the owner and no seam passes the site up,
		/// which a spelling of the property's type or of the fulfiller's `@Forwarded` property may qualify a type with, since
		/// the fulfiller is in another module. Empty otherwise: generated code spells the property's type in the module that
		/// generates the fill, where a bare name may mean a type of that module, which its `.safedi` records only if a
		/// declaration of that module mentions it.
		public var declaringModuleNames: [String] {
			storage.fields.declaringModuleNames
		}

		/// The property the site builds, as its owner declares it: the builder returns its type without its wrapper
		/// (`builtType`).
		public var property: Property {
			storage.fields.property
		}

		/// The type a declaration must fulfill to fill the builder: the property's instantiated type, or the type an
		/// erased property names with `fulfilledByType:`.
		public var instantiatedType: TypeDescription {
			storage.fields.instantiatedType
		}

		/// Where the owner declares the property.
		public var declarationLocation: Dependency.DeclarationLocation? {
			storage.fields.declarationLocation
		}

		/// Whether the property is `erasedToConcreteExistential`, which a fill wraps the fulfilling type in.
		public var erasedToConcreteExistential: Bool {
			storage.fields.erasedToConcreteExistential
		}

		/// The properties from the root of the tree that holds the site down to the owner's property, outermost first:
		/// the site's identity in that tree, which generated names are made from. Inside a fill of a passed-up hole it holds
		/// a stand-in for the seam that holds that hole (`pathBeforePropertyInItsFill`), no declaration, so a diagnostic
		/// prints `declaredSitePath` instead.
		public var sitePath: [Property] {
			storage.fields.sitePath
		}

		/// The properties the code declares from the root of the tree that holds the site down to the owner's property,
		/// outermost first, inside a fill of a passed-up hole through the calls that passed it up.
		public var declaredSitePath: [DeclaredProperty] {
			storage.fields.declaredSitePath
		}

		/// The stack a fill builds the property's tree with: the properties from the root of the seam whose tree holds
		/// the site to the owner's property, innermost first, each lazily instantiated one preceded by its instance, as
		/// `Scope.createScopeGenerator` stacks them.
		public var fillPropertyStack: [Property] {
			storage.fields.fillPropertyStack
		}

		/// How many declarations of the path this place's fill is built beneath lie beneath `declaration`, which a scope of
		/// the fill's tree closes a cycle on: `0` when it is the property whose type declares the hole, and `nil` when the path
		/// holds no such declaration. A lazily instantiated declaration's instance is its own entry of the stack, and no
		/// declaration. A scope closes on the innermost entry of its property and concrete type, which is the innermost one
		/// that equals the declaration closed on.
		func fillPathDeclarationsBeneath(_ declaration: ScopeGenerator.BuiltDeclaration) -> Int? {
			let propertyStack = fillPropertyStack
			let concreteTypeStack = fillConcreteTypeStack
			return propertyStack.indices.first { propertyStack[$0] == declaration.property && concreteTypeStack[$0] == declaration.concreteType }.map { declarationIndex in
				propertyStack[..<declarationIndex].indices.count { propertyStack[$0 + 1].asLazilyInstantiatedInstanceProperty != propertyStack[$0] }
			}
		}

		/// The concrete type each entry of `fillPropertyStack` is built for, beside it: a fill's scope closes a cycle only where it
		/// repeats an entry of the same property built for the same concrete type, as inline's does.
		public var fillConcreteTypeStack: [TypeDescription] {
			storage.fields.fillConcreteTypeStack
		}

		/// The label the generated initializer takes the place's builder under: for a place in a seam's plain scope enum, that
		/// enum's builder's label.
		public internal(set) var builderLabel: String {
			get { storage.fields.builderLabel }
			set {
				var fields = storage.fields
				fields.builderLabel = newValue
				storage = Storage(fields)
			}
		}

		/// The label each narrower tier takes the place's builder under, where it differs from `builderLabel`
		/// (`Builder.narrowerTierLabels`).
		public internal(set) var narrowerTierBuilderLabels: [AccessLevel: String] {
			get { storage.fields.narrowerTierBuilderLabels }
			set {
				var fields = storage.fields
				fields.narrowerTierBuilderLabels = newValue
				storage = Storage(fields)
			}
		}

		/// The name the generated initializer binds the builder to.
		public internal(set) var internalName: String {
			get { storage.fields.internalName }
			set {
				var fields = storage.fields
				fields.internalName = newValue
				storage = Storage(fields)
			}
		}

		/// The seam whose extension declares the scope struct: this seam, or the inner seam a passed-up hole is from.
		public var scopeSeamType: TypeDescription {
			storage.fields.scopeSeamType
		}

		/// The module that declares `scopeSeamType`, which a module the hole reaches through a view knows only from here.
		public var scopeSeamModule: ModuleIdentity {
			storage.fields.scopeSeamModule
		}

		/// The types from the seam that takes this builder, itself excluded, to the hole's owner, outermost first: for a
		/// passed-up hole, every seam it passes through on the way to `scopeSeamType`. Empty when that seam owns the hole.
		/// Each type's module is a fact of the hole, so no order among modules decides which one a diagnostic names.
		public var typesToOwner: [PathType] {
			storage.fields.typesToOwner
		}

		/// The name of the enum whose case the place is (`enumPlace`), or, before the builders are shaped, a name made from the
		/// place's owner and property.
		public internal(set) var scopeTypeName: String {
			get { storage.fields.scopeTypeName }
			set {
				var fields = storage.fields
				fields.scopeTypeName = newValue
				storage = Storage(fields)
			}
		}

		/// Where a scope enum of the seam or the public mock carries this place, once its builders are shaped.
		public internal(set) var enumPlace: EnumPlace? {
			get { storage.fields.enumPlace }
			set {
				var fields = storage.fields
				fields.enumPlace = newValue
				storage = Storage(fields)
			}
		}

		/// The name of the function that builds the wrapper this place is held in, or `nil` for one held by value and for a
		/// public mock's, whose function the generator names (see `SeamBuilderNames`).
		public internal(set) var wrapperFunctionName: String? {
			get { storage.fields.wrapperFunctionName }
			set {
				var fields = storage.fields
				fields.wrapperFunctionName = newValue
				storage = Storage(fields)
			}
		}

		/// The values a fill of the place can read from what its builder is handed: the nearest declaration of each label on
		/// the site's path that is bound before the site, inside the innermost `@Sendable` function that builds the site where
		/// one does. The seam's parameters are no field of a place built in a `@Sendable` function: a fill reads them from the
		/// caller's own scope.
		public var fields: [Field] {
			storage.fields.fields
		}

		/// The access each tier that takes the builder must have no more than: the builder's type is as visible as the
		/// narrowest type it names – the scope struct at the access of the seam that declares it, and the property's type
		/// as the declarations the signature is computed from prove it (`TypeAccessProof`) – capped at the seam's type.
		public var tierAccess: AccessLevel {
			storage.fields.tierAccess
		}

		/// How the narrowest type the builder's type names is proven, which a diagnostic explains, or `nil` when every
		/// type it names is `public`.
		public var accessCause: TypeAccessProof.Cause? {
			storage.fields.accessCause
		}

		/// The declarations on the site's path a fill cannot read from the scope struct.
		public internal(set) var uncarriedDeclarations: [UncarriedDeclaration] {
			get { storage.fields.uncarriedDeclarations }
			set {
				var fields = storage.fields
				fields.uncarriedDeclarations = newValue
				storage = Storage(fields)
			}
		}

		/// The declarations a cycle in the tree of the seam that holds the site hands the site's owner when it builds it
		/// again, which a fill cannot read, the first of each label.
		public var cycleReentryDeclarations: [CycleReentryDeclaration] {
			storage.fields.cycleReentryDeclarations
		}

		/// The declarations on the paths to calls inside fills of the seam call whose tree holds the place that build the
		/// filled seam again, which a fill of this place cannot read (see `ReenteringCallDeclaration`), every path's, in the
		/// order of their declarations. A copy a seam passes up keeps them all.
		public internal(set) var reenteringCallDeclarations: [ReenteringCallDeclaration] {
			get { storage.fields.reenteringCallDeclarations }
			set {
				var fields = storage.fields
				fields.reenteringCallDeclarations = newValue
				storage = Storage(fields)
			}
		}

		/// The fields of places whose fills build the filled seam again that a fill of this place cannot read in their place
		/// (see `ReenteringPlaceField`), every place's, in the order of their declarations. A copy a seam passes up keeps them all.
		public internal(set) var reenteringPlaceFields: [ReenteringPlaceField] {
			get { storage.fields.reenteringPlaceFields }
			set {
				var fields = storage.fields
				fields.reenteringPlaceFields = newValue
				storage = Storage(fields)
			}
		}

		/// The declarations on the site's path that a fill's field of their label hides (see `DeclarationHiddenByField`), each
		/// label once, the declaration the field hides. A copy a seam passes up keeps them.
		public internal(set) var declarationsHiddenByFields: [DeclarationHiddenByField] {
			get { storage.fields.declarationsHiddenByFields }
			set {
				var fields = storage.fields
				fields.declarationsHiddenByFields = newValue
				storage = Storage(fields)
			}
		}

		/// The seam the tree calls that presented the hole first, when this one passes it up, or `nil` for a site of this
		/// seam's own tree.
		public var innerSeamType: TypeDescription? {
			storage.fields.innerSeamType
		}

		/// When this seam passes the hole up, the properties from its root to the call of the seam whose tree holds the
		/// site, through the calls of every seam between, outermost first; empty for a site of this seam's own tree.
		public internal(set) var passedUpRoute: [DeclaredProperty] {
			get { storage.fields.passedUpRoute }
			set {
				var fields = storage.fields
				fields.passedUpRoute = newValue
				storage = Storage(fields)
			}
		}

		/// Whether the builder is `@Sendable`: the seam's tree passes it on from inside a `@Sendable` function, which
		/// captures it.
		public internal(set) var isSendable: Bool {
			get { storage.fields.isSendable }
			set {
				var fields = storage.fields
				fields.isSendable = newValue
				storage = Storage(fields)
			}
		}

		/// Where a scope enum carries a place.
		public struct EnumPlace: Codable, Sendable {
			public init(nestedByTypeIn enumTypeName: String, rootEnumTypeName: String?, caseName: String, valuesTypeName: String?, memberValuesTypeName: String? = nil, isBuiltBySendableBuilder: Bool, route: [RouteStep], values: [Field]) {
				self.enumTypeName = enumTypeName
				self.caseName = caseName
				self.valuesTypeName = valuesTypeName
				self.memberValuesTypeName = memberValuesTypeName
				self.isBuiltBySendableBuilder = isBuiltBySendableBuilder
				self.rootEnumTypeName = rootEnumTypeName
				self.route = route
				self.values = values
			}

			public let enumTypeName: String
			/// The case's name, spelled as Swift requires.
			public let caseName: String
			/// The name of the case's payload struct, or `nil` for a case of a `@Sendable` enum, which carries no values: a place
			/// held in a `Sendable` wrapper.
			public let valuesTypeName: String?
			/// The name of the struct the place's member takes where its enum declares a builder struct: the payload struct's,
			/// or the empty `Sendable` struct of a case of a `@Sendable` enum (`ScopeEnum.Case.memberValuesTypeName`); `nil`
			/// where the enum declares none, and the seam's tree hands the builder the case.
			public let memberValuesTypeName: String?
			/// The name of the root enum `enumTypeName` is nested in, or `nil` where the place's case is the root enum's own.
			public let rootEnumTypeName: String?
			/// The cases that lead from the root enum to the place's own, outermost first: each wraps the next.
			public let route: [RouteStep]
			/// What the place's owner binds before the property: the fields of the case's payload.
			public let values: [Field]

			/// Whether the place is built inside a `@Sendable` function, which the `@Sendable` builder builds: its route starts
			/// at the `@Sendable` root enum, whatever enum its own case is in.
			public let isBuiltBySendableBuilder: Bool

			/// The type of the enum whose case the place is, qualified by `seamType` when it is given.
			func enumType(qualifiedBy seamType: TypeDescription?) -> TypeDescription {
				let rootType: TypeDescription = if let seamType {
					.nested(name: rootEnumTypeName ?? enumTypeName, parentType: seamType, generics: [])
				} else {
					.simple(name: rootEnumTypeName ?? enumTypeName, generics: [])
				}
				if rootEnumTypeName == nil {
					return rootType
				} else {
					return .nested(name: enumTypeName, parentType: rootType, generics: [])
				}
			}
		}

		/// A case on the way from a root enum nested by type to a place, which wraps the next: its name, and what it carries
		/// before the value it wraps.
		public struct RouteStep: Codable, Sendable {
			public init(caseName: String, values: Values?, innerScope: InnerScope? = nil, leadsIntoFill: Bool = false, member: Member? = nil) {
				self.caseName = caseName
				self.values = values
				self.innerScope = innerScope
				self.leadsIntoFill = leadsIntoFill
				self.member = member
			}

			public let caseName: String
			/// The case's payload, or `nil` for a case of a `@Sendable` enum, which carries no values: a place is handed only
			/// what the innermost `@Sendable` function that builds it binds.
			public let values: Values?
			/// For a case of a call whose fill builds a type that leads to the place (`ScopeEnum.Case.Kind.fill`), the scope value
			/// the inner seam handed the fill, which the case carries after its payload; `nil` for every other case, and for such
			/// a case of a `@Sendable` enum that a `@Sendable` function inside the fill leads through, which carries no value
			/// bound outside that function.
			public let innerScope: InnerScope?
			/// Whether the case is a call's for a builder it fills, which leads into what the fill builds.
			public let leadsIntoFill: Bool
			/// The call of the case's member of the enum's builder struct the seam's tree makes, whose result the next step's
			/// call, or the place's, is made on.
			public let member: Member?

			/// The call of a case's member on a route: the name the seam's tree binds the struct it returns under, the type of
			/// the struct it is handed, as the seam's extension spells it, that struct's fields, the type of the struct it
			/// returns, the builder struct of the enum the case holds, the path of the property the call is made for, and
			/// whether it is made at the top of that property's own builder function rather than just before it: a member of a
			/// `@Sendable` enum whose property is built in a `@Sendable` function, since what it returns can be a plain struct,
			/// which that function could not capture.
			public struct Member: Codable, Sendable {
				public init(bindingName: String, valuesType: TypeDescription, fields: [Field], levelType: TypeDescription, bindingPathLength: Int, isCalledInsideFunction: Bool) {
					self.bindingName = bindingName
					self.valuesType = valuesType
					self.fields = fields
					self.levelType = levelType
					self.bindingPathLength = bindingPathLength
					self.isCalledInsideFunction = isCalledInsideFunction
				}

				public let bindingName: String
				public let valuesType: TypeDescription
				public let fields: [Field]
				public let levelType: TypeDescription
				/// How many properties of the path of the place or call the route leads to, from the seam's root, lead to the
				/// property the call is made for. A length, not the path: a route holds a step per level, so a path per step
				/// would grow with the square of the place's depth.
				public let bindingPathLength: Int
				public let isCalledInsideFunction: Bool

				/// The path, from the seam's root, of the property the call is made for, on the route to the place or call at
				/// `sitePath`.
				public func bindingPath(onRouteTo sitePath: [Property]) -> [Property] {
					Array(sitePath.prefix(bindingPathLength))
				}
			}

			/// A case's payload on a route: the name the seam's tree binds it under, before the case's property is built, the
			/// type of its struct, as the seam's extension spells it, and its fields, what the case's type binds before its
			/// property.
			public struct Values: Codable, Sendable {
				public init(bindingName: String, type: TypeDescription, fields: [Field]) {
					self.bindingName = bindingName
					self.type = type
					self.fields = fields
				}

				public let bindingName: String
				public let type: TypeDescription
				public let fields: [Field]
			}

			/// The scope value an inner seam hands a fill its caller declares, as a place inside the fill's tree reads it: the
			/// call's path, the inner seam's root enum the builder the fill is passed for is handed, and the name of the
			/// parameter the fill, and each dispatcher that leads to it, take the value under.
			public struct InnerScope: Codable, Sendable {
				public init(callPathLength: Int, innerKey: ScopeEnum.Key, enumType: TypeDescription, builderLabel: String, name: String) {
					self.callPathLength = callPathLength
					self.innerKey = innerKey
					self.enumType = enumType
					self.builderLabel = builderLabel
					self.name = name
				}

				/// How many properties of the path of the place or call the route leads to, from the seam's root, lead to the
				/// call (`Member.bindingPathLength` says why a length).
				public let callPathLength: Int
				public let innerKey: ScopeEnum.Key
				public let enumType: TypeDescription
				/// The label of the builder the fill is passed for, which the name is made from.
				public let builderLabel: String
				public let name: String

				/// The call's path, from the seam's root, on the route to the place or call at `sitePath`.
				public func callPath(onRouteTo sitePath: [Property]) -> [Property] {
					Array(sitePath.prefix(callPathLength))
				}
			}

			/// The step with its payload bound under `bindingName`, and its inner scope named `innerScopeName`; with its member
			/// call bound under `memberBindingName` where that is given, and with no member call where it is not.
			func named(_ bindingName: String?, innerScopeName: String? = nil, memberBindingName: String? = nil) -> RouteStep {
				RouteStep(
					caseName: caseName,
					values: values.map { Values(bindingName: bindingName ?? $0.bindingName, type: $0.type, fields: $0.fields) },
					innerScope: innerScope.map { InnerScope(callPathLength: $0.callPathLength, innerKey: $0.innerKey, enumType: $0.enumType, builderLabel: $0.builderLabel, name: innerScopeName ?? $0.name) },
					leadsIntoFill: leadsIntoFill,
					member: memberBindingName.flatMap { name in
						member.map { Member(bindingName: name, valuesType: $0.valuesType, fields: $0.fields, levelType: $0.levelType, bindingPathLength: $0.bindingPathLength, isCalledInsideFunction: $0.isCalledInsideFunction) }
					},
				)
			}
		}

		/// What a seam takes one builder of per family: the type a declaration must fulfill and the type the builder returns,
		/// spelled canonically, so `Box<any P>` and `Box<P>`, or `P & Q` and `Q & P`, are one hole type.
		public var holeType: HoleType {
			HoleType(instantiatedType: instantiatedType.spelledCanonically, builtType: builtType.spelledCanonically)
		}

		/// The label the tier at `tier` takes the place's builder under.
		func builderLabel(inTierAt tier: AccessLevel) -> String {
			narrowerTierBuilderLabels[tier] ?? builderLabel
		}

		/// The place as the tier at `tier` takes its builder, which a call of that tier passes by `builderLabel`.
		func atTier(_ tier: AccessLevel) -> Hole {
			var hole = self
			hole.builderLabel = builderLabel(inTierAt: tier)
			hole.narrowerTierBuilderLabels = [:]
			return hole
		}

		/// A property on the way to a site, the type that declares it, and where, when that is known. For a property of a
		/// protocol's fulfiller, the type is the fulfiller, which the property's type does not name.
		public struct DeclaredProperty: Codable, Sendable {
			public init(property: Property, declaringType: TypeDescription?, declarationLocation: Dependency.DeclarationLocation?) {
				self.property = property
				self.declaringType = declaringType
				self.declarationLocation = declarationLocation
			}

			public let property: Property
			public let declaringType: TypeDescription?
			public let declarationLocation: Dependency.DeclarationLocation?
		}

		/// What identifies a hole: its site, by the seam whose tree holds it and its path there, which a passed-up hole
		/// keeps. A seam takes one builder per site, whatever route presents it.
		public struct Site: Codable, Hashable, Sendable {
			public init(seamType: TypeDescription, path: [Property]) {
				self.seamType = seamType
				self.path = path
			}

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

		/// The value an instantiator hands the builder, which the place's case carries after its values, or
		/// `nil` when the property is no instantiator, or is one spelled as forwarding `()` or `Void`.
		public var forwardedType: TypeDescription? {
			property.typeDescription.forwardedTypeOfWrapper
		}

		/// The type of the payload struct the place's case carries, qualified by `seamType` when it is given, or `nil` for a
		/// case that carries no values: a place held in a `Sendable` wrapper, in a `@Sendable` enum.
		public func valuesType(qualifiedBy seamType: TypeDescription?) -> TypeDescription? {
			guard let enumPlace, let valuesTypeName = enumPlace.valuesTypeName else { return nil }
			return .nested(name: valuesTypeName, parentType: enumPlace.enumType(qualifiedBy: seamType), generics: [])
		}
	}

	public init(seamType: TypeDescription, parameters: [Parameter], tiers: [AccessLevel], noTierParameters: [Parameter] = [], holes: [Hole] = [], builders: [Builder] = [], scopeEnums: [ScopeEnum] = [], callRoutes: [CallRoute] = [], typesDeclaredEscaping: Set<TypeDescription> = []) {
		self.seamType = seamType
		self.parameters = parameters
		self.tiers = tiers
		self.noTierParameters = noTierParameters
		self.holes = holes
		self.builders = builders
		self.scopeEnums = scopeEnums
		self.callRoutes = callRoutes
		self.typesDeclaredEscaping = typesDeclaredEscaping
		callShape = Self.callShape(parameters: parameters, holes: holes, builders: builders, scopeEnums: scopeEnums, tiers: tiers)
		guardTypeName = Self.guardTypeName(of: seamType, callShape: callShape)
	}

	/// How the seam's tree hands an inner seam's enum up from a call whose case is in an enum nested by type: the call's path,
	/// the inner enum, the cases that lead from the root enum to the call's case, and the values the call's owner binds
	/// before it, which the closure the call passes builds.
	public struct CallRoute: Codable, Sendable {
		public init(sitePath: [Property], innerKey: ScopeEnum.Key, rootKey: ScopeEnum.Key, route: [Hole.RouteStep], caseName: String, memberValuesType: TypeDescription? = nil, handsFillLevelStruct: Bool = false, reentersEnclosingFill: Bool = false) {
			self.sitePath = sitePath
			self.innerKey = innerKey
			self.rootKey = rootKey
			self.route = route
			self.caseName = caseName
			self.memberValuesType = memberValuesType
			self.handsFillLevelStruct = handsFillLevelStruct
			self.reentersEnclosingFill = reentersEnclosingFill
		}

		/// The properties from the seam's root to the call's property.
		public let sitePath: [Property]
		public let innerKey: ScopeEnum.Key
		/// The root enum whose builder takes the inner enum.
		public let rootKey: ScopeEnum.Key
		public let route: [Hole.RouteStep]
		/// The call's own case, which holds the inner enum and nothing else.
		public let caseName: String
		/// Where the call's enum declares a builder struct, the type of the empty struct the call's own member takes, as the
		/// seam's extension spells it: the call passes the inner seam the struct that member returns. `nil` where the enum
		/// declares none.
		public let memberValuesType: TypeDescription?
		/// Whether the call is the fulfiller of a fill whose case `route` ends on: it is handed the struct of the fill's own level,
		/// which the fill is handed, and has no case of its own (`caseName` is empty).
		public let handsFillLevelStruct: Bool
		/// Whether the call, inside a fill, re-enters an enclosing call's fill by name, for the builder whose root enum is
		/// `innerKey`'s: the member of the case `route` ends on returns the called seam's struct, which the call hands that
		/// call's level function, under the name of the fill's parameter it stands for (`SeamHoles.carriedStruct`). It has no
		/// case of its own (`caseName` is empty) and hands up nothing.
		public let reentersEnclosingFill: Bool
	}

	/// How the seam's tree hands each inner seam's enum up from a call whose case is in an enum nested by type. Read by the
	/// seam's own generation, never by a call, so neither the call shape nor the guard holds it.
	public let callRoutes: [CallRoute]

	/// The seam's concrete type.
	public let seamType: TypeDescription
	/// The parameters of the narrowest tier, which takes every one: the seam's own `@Received` and `@Forwarded`
	/// properties in declaration order, then the pass-throughs in label order.
	public let parameters: [Parameter]
	/// Every place the seam's generated initializer's builders reach: the seam's own and each inner seam's it passes up, one
	/// per site. In the order the builders reach them. Kept apart from `parameters`, so a builder is never receivable in the
	/// seam's own tree.
	public let holes: [Hole]
	/// The builders the generated initializer takes, after every parameter and on every tier: per hole type in label order,
	/// a plain builder over its enum, then a `@Sendable` builder over its enum.
	public let builders: [Builder]
	/// This seam's scope enums, then every enum their cases reach, each once.
	public internal(set) var scopeEnums: [ScopeEnum] {
		didSet {
			callShape = Self.callShape(parameters: parameters, holes: holes, builders: builders, scopeEnums: scopeEnums, tiers: tiers)
			guardTypeName = Self.guardTypeName(of: seamType, callShape: callShape)
		}
	}

	/// What a seam takes one builder of per family (see `Hole.holeType`).
	public struct HoleType: Codable, Hashable, Sendable {
		public init(instantiatedType: TypeDescription, builtType: TypeDescription) {
			self.instantiatedType = instantiatedType
			self.builtType = builtType
		}

		public let instantiatedType: TypeDescription
		public let builtType: TypeDescription
	}

	/// The enum a family's builder of one hole type is handed: which place of the seam, or which inner seam, wants a value.
	///
	/// A seam's or a public mock's plain enum is nested by type: the root enum, `SafeDIScope_<Stem>` or `SafeDIMockScope_<Stem>`,
	/// describes what the seam or the mocked type itself builds, and each other type of its tree that leads to a place has
	/// an enum of its own, `<Type>_Scope`, nested in the root. A case is a property of the type its enum describes – a place,
	/// a property that builds a type with an enum, a call of an inner seam or another module's public mock, or such a call
	/// and a builder it fills with a type whose tree leads to a place – and carries what that type binds before the property
	/// (`Case.values`).
	public struct ScopeEnum: Codable, Sendable {
		public struct Key: Codable, Hashable, Sendable {
			public init(seamType: TypeDescription, holeType: HoleType, isSendable: Bool, describedType: TypeDescription? = nil) {
				self.seamType = seamType
				self.holeType = holeType
				self.isSendable = isSendable
				self.describedType = describedType
			}

			public let seamType: TypeDescription
			public let holeType: HoleType
			public let isSendable: Bool
			/// The type of the seam's tree whose enum this is, or `nil` for a root enum, which a builder is handed.
			public let describedType: TypeDescription?

			/// The key's spelling, which orders the enums a guard hashes.
			var spelling: String {
				"\(seamType.asSource) \(holeType.instantiatedType.asSource) \(holeType.builtType.asSource) \(isSendable ? "@Sendable" : "plain")" + (describedType.map { " \($0.asSource)" } ?? "")
			}
		}

		/// What the type an enum nested by type describes binds before a case's property: its `@Forwarded` properties, then
		/// the children it builds before the property, and, for the seam itself, its parameters first. The case's payload
		/// struct holds them.
		public struct Values: Codable, Sendable {
			public init(typeName: String, fields: [Hole.Field], labelsBoundLater: Set<String> = []) {
				self.typeName = typeName
				self.fields = fields
				self.labelsBoundLater = labelsBoundLater
			}

			public let typeName: String
			public let fields: [Hole.Field]
			/// The labels the type declares that it binds from the case's property on, the property's own among them: none is
			/// a field, and each hides every farther declaration of its label from the places beneath the property, as Swift's
			/// lookup would. A public mock's caller reads no value of such a label from a type further out, so whether it fills
			/// or passes a place up depends on them: a public mock's guard hashes them (`CallShape.ScopeEnum.Case`). A seam's
			/// caller reads none, and a seam's guard leaves them out.
			public let labelsBoundLater: Set<String>
		}

		public struct Case: Codable, Sendable {
			public init(name: String, kind: Kind, values: Values? = nil, memberValuesTypeName: String? = nil) {
				self.name = name
				self.kind = kind
				self.values = values
				self.memberValuesTypeName = memberValuesTypeName ?? values?.typeName
			}

			/// The case of each field as given, as a module info file stores it.
			public init(storing name: String, kind: Kind, values: Values?, memberValuesTypeName: String?) {
				self.name = name
				self.kind = kind
				self.values = values
				self.memberValuesTypeName = memberValuesTypeName
			}

			public enum Kind: Codable, Sendable {
				/// A place of the enum's seam: every site at which the type the enum describes builds the property, in the order
				/// the builders reach them.
				case place(sites: [Hole.Site])
				/// A property that builds the type whose enum, `enumKey`'s, the case holds, of the type `enumType` as the seam's
				/// extension spells it: a root enum where the type is the seam's, which a public mock's tree builds again inline.
				case nested(enumKey: Key, enumType: TypeDescription, isIndirect: Bool)
				/// A call of a seam whose enum the case holds.
				case inner(enumKey: Key, enumType: TypeDescription, isIndirect: Bool)
				/// A call of a seam, one of whose builders the seam's tree fills with a type whose tree leads to a place: one case
				/// per call and builder filled. It holds the scope value the inner seam handed the
				/// fill, of the type `innerEnumType` of the inner seam's root enum `innerKey` – or no such value, where
				/// `innerEnumType` is `nil`: a `@Sendable` function inside the fill leads to the place – then the enum of the
				/// fill's type, `enumKey`'s, of the type `enumType` as the seam's extension spells it.
				case fill(innerKey: Key, innerEnumType: TypeDescription?, enumKey: Key, enumType: TypeDescription, isIndirect: Bool)
			}

			/// Whether a seam's carrier holds the case's child carrier as a `let`: a nested level whose member is handed no value,
			/// outside every loop of levels (`isIndirect`, which the cases carry once every seam of the module settles, loops
			/// through other seams' carriers included), so forming it once where the parent is formed ends and captures
			/// nothing; a `Sendable` carrier holds only a `Sendable` child.
			public func isLetChildOfCarrier(inSendableEnum: Bool) -> Bool {
				switch kind {
				case let .nested(enumKey, _, isIndirect), let .inner(enumKey, _, isIndirect):
					!isIndirect && (values?.fields.isEmpty ?? true) && (!inSendableEnum || enumKey.isSendable)
				case .place, .fill:
					false
				}
			}

			public let name: String
			public internal(set) var kind: Kind
			/// What the type the enum describes binds before the case's property; `nil` for a case of a `@Sendable` enum.
			public let values: Values?
			/// The name of the struct the member of the case in the enum's builder struct takes: the payload struct's, or, for a
			/// case of a `@Sendable` enum, which carries no values, an empty `Sendable` struct's, named apart as a payload struct
			/// is.
			public let memberValuesTypeName: String?
		}

		public init(key: Key, typeName: String, rootTypeName: String? = nil, builderLabel: String, cases: [Case], takesValuesPositionally: Bool = false) {
			self.key = key
			self.typeName = typeName
			self.rootTypeName = rootTypeName
			self.builderLabel = builderLabel
			self.cases = cases
			self.takesValuesPositionally = takesValuesPositionally
		}

		public let key: Key
		public let typeName: String
		/// The name of the root enum this one is nested in, or `nil` for a root enum.
		public let rootTypeName: String?
		/// The label of the builder this enum is handed to, which names its dispatcher.
		public let builderLabel: String
		public internal(set) var cases: [Case]
		/// Whether this carrier enum's level hands its members their values positionally rather than in run structs: decided
		/// once, by the seam's own module (`SeamCarrierValues.positionalLevels(of:memberAccess:)`), and recorded here, so a
		/// caller reads the decision and never computes it again. `false` for every other enum.
		public internal(set) var takesValuesPositionally: Bool
		/// The enum's type, as a module that does not declare it spells it: qualified by the seam's type, through the root
		/// enum.
		var type: TypeDescription {
			let rootType: TypeDescription = .nested(name: rootTypeName ?? typeName, parentType: key.seamType, generics: [])
			if rootTypeName == nil {
				return rootType
			} else {
				return .nested(name: typeName, parentType: rootType, generics: [])
			}
		}

		/// The key of the enum `enumCase` holds, or `nil` for a place.
		/// The type of the enum `enumCase` holds, as the seam's extension spells it, or `nil` for a place's case.
		static func heldEnumType(of enumCase: Case) -> TypeDescription? {
			switch enumCase.kind {
			case .place:
				nil
			case let .nested(_, enumType, _),
			     let .inner(_, enumType, _),
			     let .fill(_, _, _, enumType, _):
				enumType
			}
		}

		static func heldKey(of enumCase: Case) -> Key? {
			switch enumCase.kind {
			case .place:
				nil
			case let .nested(enumKey, _, _),
			     let .inner(enumKey, _, _),
			     let .fill(_, _, enumKey, _, _):
				enumKey
			}
		}

		/// The key of the inner seam's root enum whose value `enumCase` carries, for a case of a call whose fill leads to a
		/// place: the enum a reader of the inner seam's levels walks. `nil` for every other case.
		static func carriedInnerKey(of enumCase: Case) -> Key? {
			if case let .fill(innerKey, innerEnumType, _, _, _) = enumCase.kind, innerEnumType != nil {
				innerKey
			} else {
				nil
			}
		}

		/// The sites of the places the enum of `key` reaches among `enumsByKey`, its own and those of the enums its cases hold,
		/// each once, found with an explicit stack: cases can recurse.
		static func sitesReached(from key: Key, in enumsByKey: [Key: ScopeEnum]) -> Set<Hole.Site> {
			var sites = Set<Hole.Site>()
			var visitedKeys = Set<Key>()
			var keysToVisit = [key]
			while let visitedKey = keysToVisit.popLast() {
				guard visitedKeys.insert(visitedKey).inserted, let scopeEnum = enumsByKey[visitedKey] else { continue }
				for enumCase in scopeEnum.cases {
					switch enumCase.kind {
					case let .place(placeSites):
						sites.formUnion(placeSites)
					case let .nested(innerKey, _, _),
					     let .inner(innerKey, _, _),
					     let .fill(_, _, innerKey, _, _):
						keysToVisit.append(innerKey)
					}
				}
			}
			return sites
		}
	}

	/// A builder of the generated initializer, over a root scope enum.
	public struct Builder: Codable, Sendable {
		public init(enumKey: ScopeEnum.Key, label: String, internalName: String, parameterType: TypeDescription, readableParameterType: TypeDescription, takesBuilderStruct: Bool, tierAccess: AccessLevel, accessCause: TypeAccessProof.Cause?, narrowingInnerSeam: TypeDescription?, narrowerTierLabels: [AccessLevel: String] = [:]) {
			self.enumKey = enumKey
			self.label = label
			self.internalName = internalName
			self.parameterType = parameterType
			parameterTypeWithoutAny = parameterType.withoutAny
			self.readableParameterType = readableParameterType
			self.takesBuilderStruct = takesBuilderStruct
			self.tierAccess = tierAccess
			self.accessCause = accessCause
			self.narrowingInnerSeam = narrowingInnerSeam
			self.narrowerTierLabels = narrowerTierLabels
		}

		/// The key of the root enum the builder is handed.
		public let enumKey: ScopeEnum.Key
		/// The label the widest tier takes the builder under.
		public let label: String
		public let internalName: String
		/// The parameter's type, as the initializer only generated code calls spells it: the root enum's builder struct.
		public let parameterType: TypeDescription
		/// `parameterType` without `any` at every depth, which the guard hashes: made by the same function, so nothing can be
		/// emitted and not hashed.
		public let parameterTypeWithoutAny: TypeDescription
		/// The parameter's type, as the initializer people call spells it, which a diagnostic names: the builder a person
		/// writes, from which the readable initializer makes the builder struct (`init(__safeDI_noScope:)`).
		public let readableParameterType: TypeDescription
		/// Whether the generated-only initializer takes the root enum's builder struct: every builder's does.
		public let takesBuilderStruct: Bool
		/// The access each tier that takes the builder must have no more than: the narrowest of what its type names.
		public let tierAccess: AccessLevel
		/// How the narrowest type the builder's type names is proven, or `nil` when every type it names is `public`.
		public let accessCause: TypeAccessProof.Cause?
		/// The inner seam whose enum narrows the builder, or `nil` when a place does.
		public let narrowingInnerSeam: TypeDescription?
		/// The label each narrower tier takes the builder under, where it differs from `label`: each tier names its builders
		/// apart from its own parameters and those of the tiers wider than it, so a narrower parameter never renames a wider
		/// tier's builder.
		public internal(set) var narrowerTierLabels = [AccessLevel: String]()

		/// The label the initializer only generated code calls takes the builder under.
		public var generatedOnlyArgumentLabel: String {
			ReservedName.seamGeneratedOnlyArgumentLabel(of: label)
		}

		/// The label the tier at `tier` takes the builder under.
		func label(inTierAt tier: AccessLevel) -> String {
			narrowerTierLabels[tier] ?? label
		}

		/// The label the initializer only generated code calls at `tier` takes the builder under.
		func generatedOnlyArgumentLabel(inTierAt tier: AccessLevel) -> String {
			ReservedName.seamGeneratedOnlyArgumentLabel(of: label(inTierAt: tier))
		}

		/// The builder as the tier at `tier` takes it, which a call of that tier passes by `label`.
		func atTier(_ tier: AccessLevel) -> Builder {
			Builder(
				enumKey: enumKey,
				label: label(inTierAt: tier),
				internalName: internalName,
				parameterType: parameterType,
				readableParameterType: readableParameterType,
				takesBuilderStruct: takesBuilderStruct,
				tierAccess: tierAccess,
				accessCause: accessCause,
				narrowingInnerSeam: narrowingInnerSeam,
			)
		}
	}

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

		/// A place a builder the call passes reaches: the builder's label, the place's tier access, and each of its fields –
		/// label, type spelled without `any`, and access – in field order.
		public struct Hole: Hashable, Sendable {
			public init(_ hole: SeamSignature.Hole) {
				builderLabel = hole.builderLabel
				narrowerTierBuilderLabels = TierLabel.sorted(hole.narrowerTierBuilderLabels)
				tierAccess = hole.tierAccess
				fields = hole.fields.map { Field(label: $0.property.label, type: $0.property.typeDescription.withoutAny.asSource, access: $0.access) }
			}

			public struct Field: Hashable, Sendable {
				public let label: String
				public let type: String
				public let access: AccessLevel
			}

			public let builderLabel: String
			public let narrowerTierBuilderLabels: [TierLabel]
			public let tierAccess: AccessLevel
			public let fields: [Field]
		}

		/// A label a narrower tier takes a builder under, where it differs from the widest tier's.
		public struct TierLabel: Hashable, Sendable {
			public let tier: AccessLevel
			public let label: String

			/// `labels`, widest tier first.
			static func sorted(_ labels: [AccessLevel: String]) -> [TierLabel] {
				labels.map { TierLabel(tier: $0.key, label: $0.value) }.sorted { $0.tier > $1.tier }
			}
		}

		/// A builder the initializer takes: its label, the type its signature spells without `any`, and its tier access.
		public struct Builder: Hashable, Sendable {
			public init(_ builder: SeamSignature.Builder) {
				label = builder.label
				narrowerTierLabels = TierLabel.sorted(builder.narrowerTierLabels)
				type = builder.parameterTypeWithoutAny.asSource
				tierAccess = builder.tierAccess
			}

			public let label: String
			public let narrowerTierLabels: [TierLabel]
			public let type: String
			public let tierAccess: AccessLevel
		}

		/// A scope enum, by its key: each case's name, and what the case carries.
		public struct ScopeEnum: Hashable, Sendable {
			public struct Case: Hashable, Sendable {
				public let name: String
				/// The key of the enum the case holds, or the values and forwarded type of the place it builds.
				public let payload: String
				/// The labels the case's type binds from the case's property on (`ScopeEnum.Values.labelsBoundLater`), sorted.
				public let labelsBoundLater: [String]
			}

			public let key: String
			public let typeName: String
			public let cases: [Case]
		}

		public let parameters: [Parameter]
		public let holes: [Hole]
		public let builders: [Builder]
		public let scopeEnums: [ScopeEnum]
		public let tiers: [AccessLevel]
	}

	/// Computed once per signature, since every tree that reaches the seam reads it, and its guard, from each pass's signature.
	public private(set) var callShape: CallShape

	private static func callShape(parameters: [Parameter], holes: [Hole], builders: [Builder], scopeEnums: [ScopeEnum], tiers: [AccessLevel]) -> CallShape {
		CallShape(
			parameters: parameters.map(CallShape.Parameter.init),
			holes: holes.map(CallShape.Hole.init),
			builders: builders.map(CallShape.Builder.init),
			scopeEnums: scopeEnumShapes(of: scopeEnums, holes: holes),
			tiers: tiers,
		)
	}

	/// What a call depends on of `scopeEnums`, whose own cases build `holes`: each enum by its key's spelling, in that
	/// order, with each case's name and payload – the fields and forwarded type of the place it builds, or the key of the
	/// enum it holds.
	static func scopeEnumShapes(of scopeEnums: [ScopeEnum], holes: [Hole]) -> [CallShape.ScopeEnum] {
		let holesBySite = Dictionary(holes.map { ($0.site, $0) }, uniquingKeysWith: { first, _ in first })
		func spelled(_ fields: some Sequence<Hole.Field>) -> [String] {
			fields.map { "\($0.property.label): \($0.property.typeDescription.withoutAny.asSource) \($0.access.spelledOnGeneratedDeclaration)" }
		}
		// The payload struct of a case nested by type is named, and its fields listed, first.
		func valuesPayload(of enumCase: ScopeEnum.Case) -> [String] {
			enumCase.values.map { [$0.typeName] + spelled($0.fields) } ?? []
		}
		func payload(of enumCase: ScopeEnum.Case) -> String {
			switch enumCase.kind {
			case let .place(sites):
				// Every site of a place builds one property, so each forwards one type.
				let forwardedType = sites.first.flatMap { holesBySite[$0] }?.forwardedType
				return (valuesPayload(of: enumCase) + [forwardedType?.withoutAny.asSource ?? ""]).joined(separator: ", ")
			case let .nested(enumKey, _, _),
			     let .inner(enumKey, _, _):
				return (valuesPayload(of: enumCase) + [enumKey.spelling]).joined(separator: ", ")
			case let .fill(innerKey, innerEnumType, enumKey, _, _):
				// The inner seam's root enum only where the case carries its value.
				var payload = valuesPayload(of: enumCase)
				if innerEnumType != nil {
					payload.append("inner \(innerKey.spelling)")
				}
				payload.append(enumKey.spelling)
				return payload.joined(separator: ", ")
			}
		}
		// Each key spelled once, then sorted by its spelling.
		return scopeEnums.map { (spelling: $0.key.spelling, scopeEnum: $0) }.sorted { $0.spelling < $1.spelling }.map { spelling, scopeEnum in
			CallShape.ScopeEnum(key: spelling, typeName: scopeEnum.typeName, cases: scopeEnum.cases.map { CallShape.ScopeEnum.Case(name: $0.name, payload: payload(of: $0), labelsBoundLater: $0.values?.labelsBoundLater.sorted() ?? []) })
		}
	}

	/// Hashes into `hash`, after a signature's builders, every enum they reach: each case's payload, its fields included,
	/// since a caller that computed a payload without a field would resolve the label from its own scope instead. A seam's
	/// guard and a public mock's guard both end with it.
	/// - Parameter hashesLabelsBoundLater: Whether each case's `labelsBoundLater` is hashed too: a public mock's caller
	///   decides from them whether a route fills a place or passes it up, so a caller that computed them otherwise would
	///   take another set of builders. A seam's caller reads none.
	static func combine(scopeEnums: [CallShape.ScopeEnum], hashesLabelsBoundLater: Bool = false, into hash: inout SeamSignatureHash) {
		for scopeEnum in scopeEnums {
			hash.combine(scopeEnum.key)
			hash.combine(scopeEnum.typeName)
			for enumCase in scopeEnum.cases {
				hash.combine(enumCase.name)
				hash.combine(enumCase.payload)
				if hashesLabelsBoundLater {
					// Counted first, so the labels end where the next case begins.
					hash.combine("\(enumCase.labelsBoundLater.count)")
					for label in enumCase.labelsBoundLater {
						hash.combine(label)
					}
				}
			}
		}
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
		/// compute, and the labels of its uncarried, cycle re-entry and re-entering call declarations and re-entering place fields, which only accumulate
		/// where a seam's tree reaches the seam again and hands the builder back.
		public struct Hole: Hashable, Sendable {
			public let callShape: CallShape.Hole
			public let uncarriedLabels: Set<String>
			public let cycleReentryLabels: Set<String>
			public let reenteringCallLabels: Set<String>
			public let reenteringPlaceFieldLabels: Set<String>
		}

		public let parameters: [Parameter]
		public let holes: [Hole]
		public let builders: [CallShape.Builder]
		public let scopeEnums: [CallShape.ScopeEnum]
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
		let callShape = callShape
		return SettledContent(
			parameters: settledContent(of: parameters),
			holes: holes.map { SettledContent.Hole(callShape: CallShape.Hole($0), uncarriedLabels: Set($0.uncarriedDeclarations.map(\.property.label)), cycleReentryLabels: Set($0.cycleReentryDeclarations.map(\.property.label)), reenteringCallLabels: Set($0.reenteringCallDeclarations.map(\.property.label)), reenteringPlaceFieldLabels: Set($0.reenteringPlaceFields.map(\.carried.field.property.label))) },
			builders: callShape.builders,
			scopeEnums: callShape.scopeEnums,
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
	public private(set) var guardTypeName: String

	private static func guardTypeName(of seamType: TypeDescription, callShape: CallShape) -> String {
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
		// Each builder after every parameter, so a seam without one hashes what it always hashed: the label, the type the
		// signature spells, attributes included, and the tier access. Then every enum the builders reach.
		for builder in callShape.builders {
			hash.combine(builder.label)
			hash.combine(builder.type)
			hash.combine(builder.tierAccess.spelledOnGeneratedDeclaration)
			// Only where a narrower tier takes the builder under another label, so every other seam hashes what it always hashed.
			for tierLabel in builder.narrowerTierLabels {
				hash.combine("\(tierLabel.tier.spelledOnGeneratedDeclaration) \(tierLabel.label)")
			}
		}
		combine(scopeEnums: callShape.scopeEnums, into: &hash)
		return "\(ReservedName.builderFunctionNamePrefix)\(seamType.asIdentifier)_\(hash.hexadecimal)".spelledAsJoinedIdentifier
	}
}

extension SeamSignature: Codable {
	public init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		try self.init(
			seamType: container.decode(TypeDescription.self, forKey: .seamType),
			parameters: container.decode([Parameter].self, forKey: .parameters),
			tiers: container.decode([AccessLevel].self, forKey: .tiers),
			noTierParameters: container.decode([Parameter].self, forKey: .noTierParameters),
			holes: container.decode([Hole].self, forKey: .holes),
			builders: container.decode([Builder].self, forKey: .builders),
			scopeEnums: container.decode([ScopeEnum].self, forKey: .scopeEnums),
			callRoutes: container.decode([CallRoute].self, forKey: .callRoutes),
			typesDeclaredEscaping: container.decode(Set<TypeDescription>.self, forKey: .typesDeclaredEscaping),
		)
	}

	public func encode(to encoder: any Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(seamType, forKey: .seamType)
		try container.encode(parameters, forKey: .parameters)
		try container.encode(tiers, forKey: .tiers)
		try container.encode(noTierParameters, forKey: .noTierParameters)
		try container.encode(holes, forKey: .holes)
		try container.encode(builders, forKey: .builders)
		try container.encode(scopeEnums, forKey: .scopeEnums)
		try container.encode(callRoutes, forKey: .callRoutes)
		try container.encode(typesDeclaredEscaping.sorted(), forKey: .typesDeclaredEscaping)
	}

	/// The fields a signature is written as: `callShape` and `guardTypeName` are computed from them.
	private enum CodingKeys: String, CodingKey {
		case seamType
		case parameters
		case tiers
		case noTierParameters
		case holes
		case builders
		case scopeEnums
		case callRoutes
		case typesDeclaredEscaping
	}
}

/// A seam's signature as the run of `generate` of the module that declares it computed it, which the module's module
/// info file carries so that a module calling the seam reads the signature rather than computes it again.
// A synthesized `Codable` conformance writes a set's elements, and a dictionary whose keys are not strings, in hash order,
// which changes between runs. The conformances in this module call these overloads instead, so that `SafeDITool dump` prints
// a seam signature the same on every run. Each writes what the synthesized conformance reads back.
extension KeyedEncodingContainer {
	mutating func encode(_ labels: Set<String>, forKey key: Key) throws {
		try encode(labels.sorted(), forKey: key)
	}

	/// Writes the labels widest tier first, each tier followed by its label, as a dictionary writes its pairs.
	mutating func encode(_ labelsByTier: [AccessLevel: String], forKey key: Key) throws {
		var container = nestedUnkeyedContainer(forKey: key)
		for (tier, label) in labelsByTier.sorted(by: { $0.key > $1.key }) {
			try container.encode(tier)
			try container.encode(label)
		}
	}
}

/// The signatures a module info file carries of the seams of one module, read only when a run reaches one of those seams:
/// a module's file carries those of every seam it declares, and a run reaches the seams of few of the modules it reads.
public struct StoredSeamSignatures: Sendable {
	/// - Parameter read: Returns the signatures, as `SafeDITool` decodes them from the module info file.
	public init(read: @escaping @Sendable () throws -> [StoredSeamSignature]) {
		self.read = read
	}

	/// The signatures, each of one seam, decoded each time this is called.
	public let read: @Sendable () throws -> [StoredSeamSignature]
}

public struct StoredSeamSignature: Codable, Sendable {
	public init(seamType: TypeDescription, signature: SeamSignature?) {
		self.seamType = seamType
		self.signature = signature
	}

	/// The seam, as its module's run names it.
	public let seamType: TypeDescription
	/// The seam's signature, or `nil` for a seam whose generated signature equals its own initializer's (see
	/// `ScopeGenerator.SeamRoot`), which every tree builds with that initializer.
	public let signature: SeamSignature?
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
		builders: [SeamSignature.Builder] = [],
		scopeEnums: [SeamSignature.ScopeEnum] = [],
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
		calledBuilders = CalledBuilders(holes: holes, builders: builders, scopeEnums: scopeEnums)
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
	/// Every place the call's builders reach, in the order they reach them: every tier takes every builder.
	public var holes: [SeamSignature.Hole] {
		calledBuilders.holes
	}

	/// The `SeamSignature.guardTypeName` of the signature the call was generated from.
	public let guardTypeName: String
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

	/// The builders the call passes, built once with the call.
	let calledBuilders: CalledBuilders
}

/// The builders a call passes another module's seam or public mock: the builders, every enum they reach, and every place
/// they reach, in the order they reach them, which the calling module fills or passes up.
struct CalledBuilders: Sendable {
	init(holes: [SeamSignature.Hole], builders: [SeamSignature.Builder], scopeEnums: [SeamSignature.ScopeEnum]) {
		self.holes = holes
		self.builders = builders
		self.scopeEnums = scopeEnums
		var holeBySite = [SeamSignature.Hole.Site: SeamSignature.Hole]()
		for hole in holes where holeBySite[hole.site] == nil {
			holeBySite[hole.site] = hole
		}
		self.holeBySite = holeBySite
		let enumsByKey = Dictionary(scopeEnums.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
		self.enumsByKey = enumsByKey
		carrierValuesBySeam = SeamCarrierValues.bySeam(of: scopeEnums)
		let reach = SiteReach(holes: holes, scopeEnums: scopeEnums, holeBySite: holeBySite)
		self.reach = reach
		// The builders of each hole type, in builder order, so each hole asks only its own type's.
		var builderKeysByHoleType = [SeamSignature.HoleType: [SeamSignature.ScopeEnum.Key]]()
		for builder in builders {
			builderKeysByHoleType[builder.enumKey.holeType, default: []].append(builder.enumKey)
		}
		var builderKeyByReachedPlace = [ReachedPlace: SeamSignature.ScopeEnum.Key]()
		for (index, hole) in holes.enumerated() {
			let place = ReachedPlace(site: hole.site, holeType: hole.holeType)
			if builderKeyByReachedPlace[place] == nil, let key = builderKeysByHoleType[hole.holeType]?.first(where: { reach.reaches(holeAt: index, from: $0) }) {
				builderKeyByReachedPlace[place] = key
			}
		}
		self.builderKeyByReachedPlace = builderKeyByReachedPlace
	}

	let holes: [SeamSignature.Hole]
	let builders: [SeamSignature.Builder]
	let scopeEnums: [SeamSignature.ScopeEnum]
	/// Each enum by its key.
	let enumsByKey: [SeamSignature.ScopeEnum.Key: SeamSignature.ScopeEnum]
	/// How each seam's carriers among the enums hand a level's values (`SeamCarrierValues`), by seam; a seam none of whose
	/// levels is cut into runs has no entry.
	let carrierValuesBySeam: [TypeDescription: SeamCarrierValues]

	/// How a fill of `hole`'s place takes its case's values, where the case is a seam's carrier's.
	func carrierUse(ofPlace hole: SeamSignature.Hole) -> SeamCarrierValues.Use? {
		guard let enumPlace = hole.enumPlace, !enumPlace.values.isEmpty, let values = carrierValuesBySeam[hole.scopeSeamType], let level = SeamCarrierValues.level(ofEnum: enumPlace.enumType(qualifiedBy: nil)) else { return nil }
		return values.use(ofLevel: level, count: enumPlace.values.count)
	}

	/// How a member of `scopeEnum`, a carrier's, takes `count` values, or `nil` where it takes them positionally.
	func carrierUse(ofEnum scopeEnum: SeamSignature.ScopeEnum, count: Int) -> SeamCarrierValues.Use? {
		guard count > 0, let values = carrierValuesBySeam[scopeEnum.key.seamType], let level = SeamCarrierValues.level(ofEnum: scopeEnum.type) else { return nil }
		return values.use(ofLevel: level, count: count)
	}

	/// The enum key of the first builder of `hole`'s hole type, in builder order, whose enum reaches `hole`'s site, or `nil`
	/// where none does: found once for the call, never once for each fill that asks.
	func keyOfFirstBuilderReaching(_ hole: SeamSignature.Hole) -> SeamSignature.ScopeEnum.Key? {
		builderKeyByReachedPlace[ReachedPlace(site: hole.site, holeType: hole.holeType)]
	}

	/// A site a builder of a hole type reaches.
	private struct ReachedPlace: Hashable {
		let site: SeamSignature.Hole.Site
		let holeType: SeamSignature.HoleType
	}

	/// Each site and hole type, the enum key of the first builder of the hole type, in builder order, whose enum reaches it.
	private let builderKeyByReachedPlace: [ReachedPlace: SeamSignature.ScopeEnum.Key]

	/// The holes of `builder`'s hole type whose sites its enum reaches (`SeamSignature.ScopeEnum.sitesReached(from:in:)` over
	/// `enumsByKey`), in hole order: a bit test per hole, never a walk.
	func holesOfItsHoleTypeReached(by builder: SeamSignature.Builder) -> [SeamSignature.Hole] {
		holes.indices.compactMap { index in
			let hole = holes[index]
			return hole.holeType == builder.enumKey.holeType && reach.reaches(holeAt: index, from: builder.enumKey) ? hole : nil
		}
	}

	/// Whether the enum of `key` reaches a site of `sites`, of those on the routes of the root enum of `rootKey` where one
	/// is given (`sites(_:onRoutesOf:holeBySite:)`).
	func reaches(anyOf sites: SiteNumbers, from key: SeamSignature.ScopeEnum.Key, onRoutesOf rootKey: SeamSignature.ScopeEnum.Key?) -> Bool {
		reach.reaches(anyOf: sites.bits, from: key, onRoutesOf: rootKey)
	}

	/// Whether every site the enum of `key` reaches is one of `sites`, of those on the routes of the root enum of `rootKey`
	/// where one is given (`sites(_:onRoutesOf:holeBySite:)`).
	func reachesOnly(_ sites: SiteNumbers, from key: SeamSignature.ScopeEnum.Key, onRoutesOf rootKey: SeamSignature.ScopeEnum.Key?) -> Bool {
		reach.reachesOnly(sites.bits, from: key, onRoutesOf: rootKey)
	}

	/// Whether every site `builder`'s routes reach is one of `sites`: of the sites its enum reaches, a place of the called
	/// seam's own inside a `@Sendable` function only where the builder is the `@Sendable` one, and every other place of its
	/// own only where it is not (`SeamSignature.Hole.EnumPlace.isBuiltBySendableBuilder`). The plain and the `@Sendable` root
	/// enum of a hole type hold the same enums nested by type, so each reaches the other's places through them, which no
	/// value of it leads to. A place the seam passes up from a seam it calls is in that seam's enums, which either root may
	/// hold.
	func routesReachOnly(_ sites: SiteNumbers, by builder: SeamSignature.Builder) -> Bool {
		reachesOnly(sites, from: builder.enumKey, onRoutesOf: builder.enumKey)
	}

	/// `sites` as numbers of the call's sites, for asking what an enum reaches of them: built once for each set that is
	/// asked about, never once for each enum asked. A site no hole or enum of the call holds has no number, and no enum of
	/// the call reaches it.
	func siteNumbers(of sites: Set<SeamSignature.Hole.Site>) -> SiteNumbers {
		var bits = SiteBits(count: reach.siteCount)
		for site in sites {
			if let number = reach.number(of: site) {
				bits.insert(number)
			}
		}
		return SiteNumbers(bits: bits)
	}

	/// A set of a call's sites, by their numbers (`siteNumbers(of:)`).
	struct SiteNumbers {
		fileprivate let bits: SiteBits
	}

	/// A set of a call's site numbers, one bit per site, so that what an enum reaches costs a bit per site the call has,
	/// and asking whether it reaches any or only sites of a set is a pass over words.
	fileprivate struct SiteBits: Sendable {
		init(count: Int) {
			words = [UInt64](repeating: 0, count: (count + 63) / 64)
		}

		fileprivate private(set) var words: [UInt64]

		mutating func insert(_ number: Int) {
			words[number / 64] |= 1 << UInt64(number % 64)
		}

		func contains(_ number: Int) -> Bool {
			words[number / 64] & (1 << UInt64(number % 64)) != 0
		}
	}

	/// What each enum of the call reaches, found once for the call, which every construction of a place that makes it
	/// shares, never once for each dispatcher, builder argument or route that asks. Sites are numbered, so that what an enum
	/// reaches is a set of bits rather than a set of sites, whose paths each insertion would hash. It is held for as long as
	/// the call's leaf scope lives, which is the whole run: a number per site, and a bit per site for each enum and for
	/// each seam and family whose builder builds places, so a call with `E` enums, `H` holes, `S` sites and `F` such seams
	/// and families holds `S + H` numbers and `(E + F) × S` bits.
	private let reach: SiteReach

	/// The sites a call's enums reach, numbered.
	private struct SiteReach: Sendable {
		init(
			holes: [SeamSignature.Hole],
			scopeEnums: [SeamSignature.ScopeEnum],
			holeBySite: [SeamSignature.Hole.Site: SeamSignature.Hole],
		) {
			// Each site once, in the order the holes and then the enums' places name them.
			var numberBySite = [SeamSignature.Hole.Site: Int]()
			var sites = [SeamSignature.Hole.Site]()
			func number(of site: SeamSignature.Hole.Site) -> Int {
				if let number = numberBySite[site] {
					return number
				} else {
					numberBySite[site] = sites.count
					sites.append(site)
					return sites.count - 1
				}
			}
			siteNumberByHoleIndex = holes.map { number(of: $0.site) }
			// Each enum numbered too, the first of each key, as `enumsByKey` keeps it, so the walk below hashes no key.
			var enumNumberByKey = [SeamSignature.ScopeEnum.Key: Int]()
			var firstEnums = [SeamSignature.ScopeEnum]()
			for scopeEnum in scopeEnums where enumNumberByKey[scopeEnum.key] == nil {
				enumNumberByKey[scopeEnum.key] = firstEnums.count
				firstEnums.append(scopeEnum)
			}
			var ownSiteNumbers = [[Int]]()
			var heldEnumNumbers = [[Int]]()
			for scopeEnum in firstEnums {
				var ownNumbers = [Int]()
				var heldNumbers = [Int]()
				for enumCase in scopeEnum.cases {
					switch enumCase.kind {
					case let .place(placeSites):
						ownNumbers += placeSites.map(number(of:))
					case let .nested(innerKey, _, _),
					     let .inner(innerKey, _, _),
					     let .fill(_, _, innerKey, _, _):
						// A key of no enum of the call reaches nothing.
						if let heldNumber = enumNumberByKey[innerKey] {
							heldNumbers.append(heldNumber)
						}
					}
				}
				ownSiteNumbers.append(ownNumbers)
				heldEnumNumbers.append(heldNumbers)
			}
			self.numberBySite = numberBySite
			siteCount = sites.count
			// Each enum's sites, as `SeamSignature.ScopeEnum.sitesReached(from:in:)` finds them, with an explicit stack: cases
			// can recurse. Each enum is marked with the number of the enum whose walk reached it, so each is taken once per
			// walk without a set.
			var enumVisitedBy = [Int](repeating: -1, count: firstEnums.count)
			var reachedBitsByKey = [SeamSignature.ScopeEnum.Key: SiteBits]()
			for (start, scopeEnum) in firstEnums.enumerated() {
				var reachedBits = SiteBits(count: sites.count)
				enumVisitedBy[start] = start
				var enumsToVisit = [start]
				while let visited = enumsToVisit.popLast() {
					for number in ownSiteNumbers[visited] {
						reachedBits.insert(number)
					}
					for held in heldEnumNumbers[visited] where enumVisitedBy[held] != start {
						enumVisitedBy[held] = start
						enumsToVisit.append(held)
					}
				}
				reachedBitsByKey[scopeEnum.key] = reachedBits
			}
			self.reachedBitsByKey = reachedBitsByKey
			noSites = SiteBits(count: sites.count)
			// The sites a root enum's routes leave out (`CalledBuilders.sites(_:onRoutesOf:holeBySite:)`): each place of a seam's
			// own that the other family's builder builds. Keyed by the seam and the family that builds the place, so the root key
			// of any builder finds exactly its own, and a seam with no place of a family leaves out nothing.
			var offRoutesBitsBySeamFamily = [SeamFamily: SiteBits]()
			for (number, site) in sites.enumerated() {
				if let hole = holeBySite[site], let enumPlace = hole.enumPlace {
					offRoutesBitsBySeamFamily[SeamFamily(seamType: hole.scopeSeamType, isBuiltBySendableBuilder: enumPlace.isBuiltBySendableBuilder), default: SiteBits(count: sites.count)].insert(number)
				}
			}
			self.offRoutesBitsBySeamFamily = offRoutesBitsBySeamFamily
		}

		let siteCount: Int

		func number(of site: SeamSignature.Hole.Site) -> Int? {
			numberBySite[site]
		}

		/// Whether the enum of `key` reaches the site of the call's hole at `index`.
		func reaches(holeAt index: Int, from key: SeamSignature.ScopeEnum.Key) -> Bool {
			reachedBits(from: key).contains(siteNumberByHoleIndex[index])
		}

		/// Whether the enum of `key` reaches a site of `sites`, of those on the routes of `rootKey`'s root enum where given.
		func reaches(anyOf sites: SiteBits, from key: SeamSignature.ScopeEnum.Key, onRoutesOf rootKey: SeamSignature.ScopeEnum.Key?) -> Bool {
			let reachedBits = reachedBits(from: key)
			let offRoutesBits = offRoutesBits(of: rootKey)
			return reachedBits.words.indices.contains { reachedBits.words[$0] & ~offRoutesBits.words[$0] & sites.words[$0] != 0 }
		}

		/// Whether every site the enum of `key` reaches is one of `sites`, of those on the routes of `rootKey`'s root enum
		/// where given.
		func reachesOnly(_ sites: SiteBits, from key: SeamSignature.ScopeEnum.Key, onRoutesOf rootKey: SeamSignature.ScopeEnum.Key?) -> Bool {
			let reachedBits = reachedBits(from: key)
			let offRoutesBits = offRoutesBits(of: rootKey)
			return !reachedBits.words.indices.contains { reachedBits.words[$0] & ~offRoutesBits.words[$0] & ~sites.words[$0] != 0 }
		}

		/// The sites the enum of `key` reaches: none for a key of no enum of the call, as
		/// `SeamSignature.ScopeEnum.sitesReached(from:in:)` finds none, so every question about it is answered as about an
		/// enum that reaches nothing.
		private func reachedBits(from key: SeamSignature.ScopeEnum.Key) -> SiteBits {
			reachedBitsByKey[key, default: noSites]
		}

		/// The sites the routes of `rootKey`'s root enum leave out: the places of its seam's own that the other family's
		/// builder builds, none where its seam has no such place, and none where no root key is given.
		private func offRoutesBits(of rootKey: SeamSignature.ScopeEnum.Key?) -> SiteBits {
			guard let rootKey else { return noSites }
			return offRoutesBitsBySeamFamily[SeamFamily(seamType: rootKey.seamType, isBuiltBySendableBuilder: !rootKey.isSendable), default: noSites]
		}

		/// A seam and a family of its builders, plain or `@Sendable`.
		private struct SeamFamily: Hashable {
			let seamType: TypeDescription
			let isBuiltBySendableBuilder: Bool
		}

		private let numberBySite: [SeamSignature.Hole.Site: Int]
		/// The number of each hole's site, by the hole's index in the call's holes.
		private let siteNumberByHoleIndex: [Int]
		private let reachedBitsByKey: [SeamSignature.ScopeEnum.Key: SiteBits]
		/// No site, as many words as any set of the call's sites.
		private let noSites: SiteBits
		private let offRoutesBitsBySeamFamily: [SeamFamily: SiteBits]
	}

	/// Each hole by its site, the first of `holes` at a site: found once for the call, never once for each builder whose
	/// routes are asked for, which grew a call's construction with the square of its hole types.
	let holeBySite: [SeamSignature.Hole.Site: SeamSignature.Hole]

	/// The sites of `sites` that a route from the root enum of `rootKey` reaches (see `routesReachOnly(_:by:)`).
	static func sites(_ sites: Set<SeamSignature.Hole.Site>, onRoutesOf rootKey: SeamSignature.ScopeEnum.Key, holeBySite: [SeamSignature.Hole.Site: SeamSignature.Hole]) -> Set<SeamSignature.Hole.Site> {
		sites.filter { site in
			guard let hole = holeBySite[site], hole.scopeSeamType == rootKey.seamType, let enumPlace = hole.enumPlace else { return true }
			return enumPlace.isBuiltBySendableBuilder == rootKey.isSendable
		}
	}
}

/// What a run of `generate` tells the dependency tree generator about the seams among the declarations it reads.
public struct SeamResolution: Sendable {
	/// A seam declared in another module, which that module's run of `generate` generated the initializer of.
	public struct ForeignSeam: Sendable {
		public init(declaringModule: ModuleIdentity, visibleDeclarations: @escaping @Sendable () throws -> VisibleDeclarations, callComment: SeamCallComment, declaringModuleMockCondition: MockCondition? = nil, storedSignatures: StoredSeamSignatures? = nil) {
			self.declaringModule = declaringModule
			self.visibleDeclarations = visibleDeclarations
			self.callComment = callComment
			self.declaringModuleMockCondition = declaringModuleMockCondition
			self.storedSignatures = storedSignatures
		}

		/// The module that declares the seam, whose name is known: a seam whose module is unknown is built inline.
		public let declaringModule: ModuleIdentity
		/// Resolves the declarations the seam's module can see, as `generate` resolves them, from which the seam's
		/// signature is computed exactly as that module computed it: called only for a module whose seams a tree
		/// reaches and that carries no signatures of them, once per module, since the seams of one module share them.
		public let visibleDeclarations: @Sendable () throws -> VisibleDeclarations
		/// See `SeamCall.comment`.
		public let callComment: SeamCallComment
		/// The mock condition of the seam's module, when this run read that module's files under its own mock condition,
		/// as it does under the SwiftPM plugin's target graph: `visibleDeclarations` then holds the module's mock-only
		/// declarations as this run's condition selects them, which is how the module reads them only when the two
		/// conditions are spelled the same. `nil` when this run read the module's module info, which holds its
		/// declarations as the module read them.
		public let declaringModuleMockCondition: MockCondition?
		/// The signatures of the seams of the seam's module as that module's run computed them, among which the module
		/// info this run read them from carries this seam's; `nil` when it carries none of this seam, and when this run
		/// read the module's files, under the SwiftPM plugin's target graph. Every seam of one module holds the same.
		public let storedSignatures: StoredSeamSignatures?
	}

	/// Whether a foreign seam carries the signature its module's run stored.
	public var readsStoredSignature: Bool {
		foreignSeams.values.contains { $0.storedSignatures != nil }
			|| foreignPublicMocks.values.contains { $0.storedPlans != nil }
			|| (foreignDeclarationsSeenByModule ?? [:]).values.contains { declarations in
				declarations.seams.values.contains { $0.storedSignatures != nil } || declarations.publicMocks.values.contains { $0.storedPlans != nil }
			}
	}

	/// The declarations a module sees.
	public struct VisibleDeclarations: Sendable {
		public init(instantiables: [TypeDescription: Instantiable], plainTypeDeclarations: [PlainTypeDeclaration]) {
			self.instantiables = instantiables
			self.plainTypeDeclarations = plainTypeDeclarations
		}

		/// The declarations, resolved as `generate` resolves them.
		public let instantiables: [TypeDescription: Instantiable]
		/// The plain type declarations of the modules whose declarations `instantiables` holds, which prove the access
		/// of the types a seam's parameters name as they prove it in the seam's module.
		public let plainTypeDeclarations: [PlainTypeDeclaration]
	}

	/// A type another module declares with `generateMock: .public`, whose `mock()` that module's run of `generate`
	/// generated, and which a mock tree of this module calls where it cannot build the type's tree itself.
	public struct ForeignPublicMock: Sendable {
		public init(declaringModule: ModuleIdentity, visibleDeclarations: @escaping @Sendable () throws -> VisibleDeclarations, callComment: SeamCallComment, declaringModuleMockCondition: MockCondition, storedPlans: StoredPublicMockPlans? = nil) {
			self.declaringModule = declaringModule
			self.visibleDeclarations = visibleDeclarations
			self.callComment = callComment
			self.declaringModuleMockCondition = declaringModuleMockCondition
			self.storedPlans = storedPlans
		}

		/// The module that declares the type, whose name is known: a type whose module is unknown is built inline.
		public let declaringModule: ModuleIdentity
		/// Resolves the declarations the declaring module can see, as `generate` resolves them, from which the public
		/// mock's signature is computed exactly as that module computed it: called only for a module whose public mock a
		/// plan needs.
		public let visibleDeclarations: @Sendable () throws -> VisibleDeclarations
		/// See `SeamCall.comment`.
		public let callComment: SeamCallComment
		/// The condition the declaring module generates its mocks under: its configuration's, `DEBUG` without one, read
		/// from its module info or, under the target graph, from the configuration in a file the graph attributes to it.
		public let declaringModuleMockCondition: MockCondition
		/// The plans of the public mocks of the type's module as that module's run computed them, among which the module
		/// info this run read them from carries this type's; `nil` when it carries none of this type, and when this run
		/// read the module's files, under the SwiftPM plugin's target graph. Every public mock of one module holds the
		/// same.
		public let storedPlans: StoredPublicMockPlans?
	}

	public init(currentModule: ModuleIdentity, currentModuleMockCondition: MockCondition = MockCondition("DEBUG"), generatedSeams: Set<TypeDescription>, foreignSeams: [TypeDescription: ForeignSeam], foreignPublicMocks: [TypeDescription: ForeignPublicMock] = [:], foreignDeclarationsSeenByModule: [String: ForeignDeclarations]? = nil, callersComputeFromTargetGraph: Bool = false, callersVisibleInstantiables: [TypeDescription: Instantiable]? = nil, callersVisiblePlainTypeDeclarations: [PlainTypeDeclaration] = [], carriesUnreadTypeComment: Bool = false, generatesPlainDependencyTreeInitializers: Bool = false) {
		self.carriesUnreadTypeComment = carriesUnreadTypeComment
		self.generatesPlainDependencyTreeInitializers = generatesPlainDependencyTreeInitializers
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
	/// Whether each tier of the seams this module generates has a plain initializer for people beside the one generated
	/// code calls: what this module's own `#SafeDIConfiguration` sets as `generatePlainDependencyTreeInitializers`.
	/// Generated calls never call the plain initializer, so no signature, call or guard depends on this, and a nested
	/// resolution, which computes another module's seams, does not carry it. Only the check that rejects a hand-written
	/// initializer callable with a tier's readable labels reads it, in the computation of this module's own seams.
	public let generatesPlainDependencyTreeInitializers: Bool

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
			"// If this line does not compile, compile the code SafeDI generates for module \(declaringModuleName) into \(declaringModuleName): under Bazel, add \(declaringModuleName)’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes."
		}
	}

	/// `text(for:)` after a space, to end the line with, or an empty string for `noComment`.
	func lineEnd(for type: TypeDescription) -> String {
		text(for: type).map { " \($0)" } ?? ""
	}
}

// MARK: - CustomReflectable

/// Reflects each stored field of a hole under its own name, as when each was stored in the struct rather than in `Storage`.
extension SeamSignature.Hole: CustomReflectable {
	public var customMirror: Mirror {
		Mirror(self, children: Mirror(reflecting: storage.fields).children, displayStyle: .struct)
	}
}
