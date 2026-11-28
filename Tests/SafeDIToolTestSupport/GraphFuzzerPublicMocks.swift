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

import Foundation
import Testing

// MARK: - Draw features

/// The shapes `GraphFuzzerPublicMockDraw` draws, read from a fixture's source (`GraphFuzzerPublicMockDraw.drawFeatures(of:)`),
/// so that a draw that stops landing fails
/// `publicMockCorpus_drawsEachShapeInThePinnedNumberOfGraphs_whenFixturesAreGeneratedWithoutTheTool` rather than a review.
enum GraphFuzzerPublicMockDrawFeature: String, CaseIterable, Comparable {
	/// Both consumer modules: `FuzzApp`, in the declaring module's package, and `FuzzOther`, in another.
	case bothConsumerModules
	/// Only the consumer module in the declaring module's package.
	case samePackageConsumerModuleOnly
	/// Only the consumer module in another package.
	case otherPackageConsumerModuleOnly
	/// Declarations of the declaring module moved beneath it, into the modules that only the declaring module and the
	/// module beneath it list, so that a consumer computes a public mock's signature from the declaring module's view
	/// (`GraphFuzzerSeamDependencyDraw`).
	case seamDependency
	/// A chain of public mocks two modules deep beneath the declaring module, `ChainLink` and `ChainBase`
	/// (`GraphFuzzerSeamDependencyDraw.chainPercent`).
	case seamDependencyChain
	/// One, two, or three types declared with `generateMock: .public`.
	case onePublicMockType
	case twoPublicMockTypes
	case threePublicMockTypes
	/// A `.public` type whose initializer is `package`, or spells no access level.
	case packageInitializer
	case internalInitializer
	/// A type in a `.public` type's tree declared `package` or with no access level.
	case narrowerTreeType
	/// A parameter type of each proof source: an `@Instantiable` type, whose own declaration is its exact entry.
	case instantiableParameterType
	/// A plain type only `package` initializers take as a dependency.
	case plainTypeOnlyPackageInitializersTake
	/// A plain type a `public` initializer elsewhere in the module takes as a dependency.
	case plainTypePublicInitializerTakes
	/// A plain type only default-valued arguments name, labeled or not: no mention.
	case plainTypeOnlyDefaultArgumentsName
	/// An allow-listed type, spelled plainly or `Swift.`-qualified.
	case allowlistedParameterType
	case qualifiedAllowlistedParameterType
	/// An `@Instantiable` type declared in an extension of a namespace enum that spells no access level, `public`, or
	/// `package`: a non-exact entry.
	case namespaceExtensionUnspelled
	case namespaceExtensionPublic
	case namespaceExtensionPackage
	/// The namespace enum `Space` declared in a file of its own that holds no SafeDI marker, which `scan` reads because an
	/// `@Instantiable` type an extension of it holds is declared elsewhere.
	case namespaceInMarkerFreeFile
	/// `Dock`, the namespace of the holders a consumer may hold, declared `package`, so that only a consumer in the
	/// declaring module's package can name a holder, and the public tier omits it.
	case dockPackage
	/// `Dock` declared `public` inside a platform-conditioned `#if` block, every clause of which SafeDI reads as it reads a
	/// declaration outside every block, so that `Dock` is exactly `public` and the public tier takes the holder.
	case dockInsidePlatformBlock
	/// An `@Instantiable` type declared in an extension of an `@Instantiable` type of the module: an exact entry.
	case typeInExtensionOfInstantiable
	/// A value of a type no declaration SafeDI reads declares, received only if available in a leaf's tree, which SafeDI
	/// counts as `public` (decision 54).
	case unreadParameterType
	/// An extension-based `@Instantiable` type.
	case extensionBasedInstantiable
	/// A required parameter of a type narrower than `public`, which the public tier cannot take.
	case requiredParameterNarrowerThanPublic
	/// A protocol slot whose mock is a fake: a class in a file with no SafeDI content, extended by a `mockOnly`
	/// extension; the extension spelled `package`, the class declared with no access level.
	case protocolSlotFilledByFake
	case fakeExtensionPackage
	case fakeTypeInternal
	/// The fake's `mock` with a defaulted parameter, and with one whose label names a dependency of the slot's production type.
	case fakeMockDefaultedParameter
	case fakeMockDependencyBoundParameter
	/// A `.public` type with `customMockName`.
	case customMockName
	/// A consumer building a `Sendable` wrapper above the leaf, whose type builds the leaf and what the leaf receives.
	case sendableWrapperAboveLeaf
	/// A consumer receiving a `.public` type, or instantiating it.
	case consumerReceivesLeaf
	case consumerInstantiatesLeaf
	/// A consumer declared with `generateMock: .public`, and one that leaves `theme`, which its leaf's tree receives, unprovided.
	case publicConsumer
	case publicConsumerLeavesLeafLabelUnprovided
	/// A consumer holding a value its leaf's tree receives only if available, a holder nested in `Dock`. The tier the
	/// consumer reaches takes it: SafeDI reads `Dock`'s declaration wherever it is, and a consumer in another package
	/// holds no holder of a `package` `Dock`. The name is from when an unread `Dock` made the tier omit it.
	case consumerHoldsOmittedValue
	/// The holder's shapes: received rather than instantiated, declared before or after the leaf, a holder type that
	/// receives the leaf only if available, lazily instantiated, or built under a `@Sendable` builder.
	case holderlessOmittedValue
	case omittedValueProviderBeforeLeaf
	case omittedValueProviderAfterLeaf
	case omittedValueProviderAndLeafReceiveEachOther
	case lazilyInstantiatedOmittedValueProvider
	case omittedValueProviderUnderSendableBuilder
	/// Two leaves receiving a dependency a consumer in another package cannot name, which that consumer reaches both of.
	case twoLeavesReceiveUnnameableDependency
	/// A lazily received label beside an only-if-available by-value receive of it.
	case lazilyReceivedLabelWithOnlyIfAvailableByValueReceive
	/// A consumer holding the wrapper of a label its leaf receives lazily.
	case consumerHoldsLazilyInstantiatedWrapper
	/// Default-valued parameters: optional-typed of a public, a `package`, or an unproven type, non-optional, and a closure.
	case optionalDefaultOfPublicType
	case optionalDefaultOfPackageType
	case optionalDefaultOfUnprovenType
	case nonOptionalDefault
	case closureDefault
	/// A `.public` type on no actor that builds a dependency, so that its mock has a `SafeDIOverrides`, and that takes an
	/// optional-typed default-valued parameter, which its `mock()` takes as an internal mock does
	/// (`GraphFuzzerFixture.publicMockTypesTakingOwnOptionalName`).
	case ownOptionalDefaultOnNonisolatedTypeThatBuilds
	/// A child's default naming its own static member.
	case childDefaultNamingOwnStaticMember
	/// A `@MainActor` child with an isolated or a `nonisolated` initializer, and an isolated one that spells `@MainActor`
	/// itself, which the public mock's construction function mirrors.
	case mainActorChildIsolatedInitializer
	case mainActorChildNonisolatedInitializer
	case mainActorChildInitializerSpellsIsolation
	/// A child whose only default-valued parameter is of a type narrower than `public`.
	case allNonPublicConfiguration
	/// A `mockConditionalCompilation` that differs between the declaring module and a consuming one, and the declaring
	/// module's configuration in a file of its own named `SafeDIConfiguration.swift`.
	case mockConditionDiffers
	case declaringModuleConfigurationFile
	/// R15's spellings of the value `spelled<index>`.
	case spelledPlain
	case spelledClosure
	case spelledSendableClosure
	case spelledOptionalClosure
	case spelledTuple
	case spelledExistential
	case spelledNested
	case spelledGeneric
	case spelledTypealias
	/// R15's property kinds the spelled value is drawn as: the leaf's forwarded, required or only-if-available
	/// property, its non-optional or optional default, its child's default, and a value every consumer forwards.
	case spelledForwarded
	case spelledRequiredReceive
	case spelledOnlyIfAvailableReceive
	case spelledNonOptionalDefault
	case spelledOptionalDefault
	case spelledChildDefault
	case spelledConsumerPasses
	/// G1 (M8.19, M8.20b): a consumer instantiating a leaf through an erasure, as a constant, an `ErasedInstantiator`, or a
	/// `SendableErasedInstantiator`, the leaf conforming to a protocol its module declares, whose eraser is a public struct.
	case erasedConstantLeaf
	case erasedInstantiatorLeaf
	case sendableErasedInstantiatorLeaf
	/// R7: the `.public` type `T6`, whose tree instantiates a hole – a type no declaration of its module fulfills – on
	/// itself, or beneath an `Instantiator`, a `LazilyInstantiated`, or a `Sendable` wrapper of a type it instantiates.
	case holeOnPublicMockType
	case holeBeneathInstantiator
	case holeBeneathLazilyInstantiated
	case holeBeneathSendableWrapper
	/// On a stream of its own (`publicMockReceivedHoleHostRandomSeedMask`): `HoleHost` received by `HoleReceiver`, a type
	/// `T6` instantiates – as itself, through an `Instantiator`, or through a `SendableInstantiator` – so that `T6`'s mock
	/// promotes it to its root, and the hole's place is beneath a dependency `T6` does not declare (the adopter's M2).
	case holeHostReceivedByValue
	case holeHostReceivedThroughInstantiator
	case holeHostReceivedThroughSendableInstantiator
	/// The hole declared as `Instantiator<Hole>`, whose type conforms to `Instantiable` by hand, as `any HoleProtocol`, or
	/// as an erasure of `HoleFill`, which only a consumer module may declare, to `AnyHole`: a constant or an
	/// `ErasedInstantiator`.
	case holeDeclaredAsInstantiator
	case holeDeclaredAsExistential
	case holeDeclaredAsErasedConstant
	case holeDeclaredAsErasedInstantiator
	/// An `ErasedInstantiator` hole that forwards `holeTicket: Int`, which `HoleFill` forwards: a place whose wrapper forwards a
	/// value to its builder.
	case holeForwardsValue
	/// `T6` instantiating a `package` type, or a public one, before the hole, which the hole's scope struct holds as fields.
	case holeScopeHoldsPackageValue
	case holeScopeHoldsPublicValue
	/// The hand-written caller of `T6`'s public mock, in the other package's consumer module or in the same package's.
	case holeCallerInOtherPackage
	case holeCallerInSamePackage
	/// A consumer reaching `T6` in a module that declares an `@Instantiable` type fulfilling the hole, and one in a module
	/// that declares none, which `GraphFuzzerPublicMockDraw.drawsHoleConsumers` alone draws.
	case consumerReachesHoleTypeWithFill
	case consumerReachesHoleTypeWithoutFill
	/// The fulfilling type receiving `holeContext`, which `T6` binds before the hole, so that a field of its scope struct
	/// holds it; receiving `holeExtra`, which no field holds; and instantiating `Instantiator<T6>`, a fully lazy cycle
	/// back through the fill.
	case holeFillReceivesField
	case holeFillReceivesNonField
	case holeFillClosesLazyCycle
	/// On the root-level stream: `T6`'s mock binding `holeSession`, which it cannot build, and `holeToken`, received only if
	/// available, before its tree, which its root level holds, and a fill reading one or both there; `T6` receiving
	/// `holeSession` lazily, whose wrapper its root level holds, and a fill reading the wrapper; and `T6`'s tree receiving
	/// `holeSession` in two forms, which its mock names apart, and a fill reading the form `HoleHost`'s level binds again.
	case holeRootLevelHoldsValues
	case holeFillReceivesRootLevelValue
	case holeRootLevelHoldsWrapper
	case holeFillReceivesRootLevelWrapper
	case holeRootReceivesLabelInTwoForms
	case holeFillReceivesFormBoundAgain
	/// On the call-shape stream: a consumer receiving the lazily instantiated `analytics` its leaf receives (EOU-1); a
	/// consumer reaching `T6` under a second label, `t6Second` (D530-1); and a `mockOnly` fake fulfilling `T6`'s
	/// existential hole beside `HoleFill`, or alone (D530-2).
	case consumerReceivesLazilyInstantiatedWrapper
	case consumerReachesHoleTypeUnderTwoLabels
	/// On a stream of its own: a consumer reaching `T6` instantiates `T6Twin` too, a second public mock whose tree holds the
	/// same hole.
	case consumerReachesHoleTypeThroughTwoPublicMocks
	case holeFakeBesideFill
	case holeFakeAlone
	/// On a stream of its own: `HoleHost` building itself again through `HoleLoop`, a loop around `T6`'s hole.
	case holeInsideLoop
	/// `HoleLoop` declaring `holeContext` again, so a fill that reads it gets the nearest level's value inline and the
	/// public mock rejects the graph (`declarationBoundOnCycleReentry`).
	case holeLoopDeclaresContextAgain
	/// Seed 157's shape, read from the draw: a consumer module that cannot build `T6` inline – the construction `T6`'s mock
	/// uses, its `customMock` where it names one and else its initializer, is `internal`, or `package` and the module is in
	/// the other package – calls `T6`'s public mock and declares the fill, which reads the `holeContext` `T6` binds outside
	/// the `@Sendable` function that builds `holeHost: SendableLazilyInstantiated<HoleHost>`, with the hole declared
	/// `Instantiator<Hole>` on `HoleHost` inside a `HoleLoop` that does not declare `holeContext` again. The calling mock
	/// reports its production twin's error (`boundOutsideSendableFunction`, contract rule 7), where a consumer that builds
	/// `T6` inline reads `holeContext` as the known-right path does.
	case holeFillReadsContextBoundOutsideSendableFunction
	/// On a stream of its own (`publicMockHoleAttributesRandomSeedMask`): `T6` spelling `mockAttributes: "@MainActor"`; and
	/// `T6` naming a hand-written `customMock` that `T6Deck`, another `.public` type of its module, builds it with, once
	/// where `T6` instantiates nothing but its hole, so that neither function of its mock takes `safeDIOverrides`.
	case holeMockIsolatedToMainActor
	case holeHandWrittenMockBuiltInPublicMock
	case holeHandWrittenMockTakesNoOverrides
	/// On a stream of its own (`publicMockSelfBuildRandomSeedMask`), the shape #702 fixed: `SelfNode`, a `.public` type
	/// with a place of `SelfApi`, builds itself again through an instantiator of itself, through `SelfStep`, which it
	/// builds, or, in a graph whose types are all `Sendable`, through a `SendableInstantiator`; its place is on it or
	/// beneath it on `SelfPart`; it now and then binds `selfToken` before the place, which the fill reads; and
	/// `SelfScreen`, a mocked consumer, calls its public mock, filling the place with `SelfLive` or passing it up.
	case selfBuildingPublicMock
	case selfBuildingPublicMockThroughStep
	case selfBuildingPublicMockThroughSendableInstantiator
	case selfBuildingPublicMockPlaceBeneath
	case selfBuildingPublicMockFillReadsToken
	case selfBuildingPublicMockPassedUp
	/// On a stream of its own (`publicMockSelfReceivesBuilderRandomSeedMask`): a type of `SelfNode`'s tree receives the builder
	/// of `SelfNode` rather than instantiating it – `SelfStep`, `SelfPart`, which holds the place, or `SelfLink`, which holds
	/// none – so that `SelfNode`'s mock promotes the builder to its root, and the places of the `SelfNode` it builds are
	/// beneath a dependency `SelfNode` does not declare (the adopter's M2: `SelfPart` receiving a `SendableInstantiator`).
	case selfBuildingPublicMockReceivesBuilder
	/// On a stream of its own (`publicMockPlaceInFillRandomSeedMask`), a place inside a public mock's fill:
	/// `PlaceInFillOuter`, a `.public` type of the declaring module, builds `PlaceInFillInner`, a `.public` type of the
	/// module beneath it whose place of `PlaceInFillService` the declaring module fills with `PlaceInFillDefault`,
	/// which holds a place of `PlaceInFillGadget` that only a consumer module fills (`PlaceInFillLive`) or passes up.
	/// Now and then `PlaceInFillInner` also builds `PlaceInFillInnerScreen` through an instantiator that forwards
	/// `placeInFillId`, with a place of its own, which the fill reads only if available, and `PlaceInFillOuter` binds
	/// `placeInFillTag` before it, which the fill reads.
	case placeInsidePublicMockFill
	case placeInsidePublicMockFillFilledByConsumer
	case placeInsidePublicMockFillPassedUp
	case placeInsidePublicMockFillOnForwardingRoute
	case placeInsidePublicMockFillReadsOuterValue
	case placeInsidePublicMockFillReadsForwardedValue
	/// `PlaceInFillDefault` also instantiates the builders of `PlaceInFillLoopA` and `PlaceInFillLoopB`, each of which
	/// receives the other's and holds a place of `PlaceInFillGadget`: a loop of builders inside the fill, whose members'
	/// payloads a public mock binds in a `let` each, where a seam's tree holds them in one box.
	case placeInsidePublicMockFillHoldsLoopOfBuilders
	/// On a stream of its own (`publicMockRetentionRandomSeedMask`), the shape the retention oracle judges a calling mock's
	/// fill by: `RetainHome`, a `.public` type of the declaring module, binds `retainNavigator` and then builds
	/// `RetainDetail` through an instantiator, beneath which `RetainLeaf` holds a place of `RetainApi`; `RetainApp`, a mocked
	/// consumer, builds `RetainHome`, and `RetainLive` beside it fills the place, now and then reading `retainNavigator`.
	case retentionPublicMockValueBeforeBuilder
	/// `RetainLeaf` is built through an instantiator rather than by value.
	case retentionPublicMockValueBeforeBuilderLeafThroughInstantiator
	/// `RetainLive`, the fill, reads `retainNavigator`, which the known-right path then keeps alive too.
	case retentionPublicMockValueBeforeBuilderFillReadsValue
	/// On a stream of its own (`publicMockSharedConstructionRandomSeedMask`), a type a module's public mocks build two ways:
	/// `ShareService`, which fulfills `ShareApi`, has a hand-written mock that returns `ShareApi` and takes its
	/// initializer's parameters, and the public mocks of `ShareHolderA` and `ShareHolderB` hold it as `ShareApi`, built
	/// with that mock, and as itself or erased to `AnyShareApi`, built with its initializer or `instantiate(…)` method, so
	/// that the module declares both of its construction functions.
	case sharedConstructionPublicMock
	/// `ShareService` is declared by an extension, whose `customMockName` method returns `ShareApi`, rather than by a class
	/// with a `mockOnly` extension's `mock()`.
	case sharedConstructionPublicMockExtensionBased
	/// The holder built without the hand-written mock holds `ShareService` erased to `AnyShareApi`.
	case sharedConstructionPublicMockErased
	/// `ShareHolderA` holds both properties, and no `ShareHolderB` is declared.
	case sharedConstructionPublicMockOneHolder
	/// `ShareHolderA`, whose public mock sorts first, holds the property built without the hand-written mock.
	case sharedConstructionPublicMockWithoutMockFirst
	/// The holders are in a consumer module, and `ShareRoot`, a `.public` type of the declaring module, holds `ShareApi`,
	/// so that the declaring module declares an internal `__safeDI_mock` of its own.
	case sharedConstructionPublicMockBesideDeclaringModulesOwn
	/// The holders are in the declaring module.
	case sharedConstructionPublicMockInDeclaringModule
	/// `ShareService`'s `mockOnly` mock, which takes one more optional default than its initializer, builds `ShareApi`
	/// only beneath a cycle edge, in `ShareTicker`, which `ShareService` builds through an instantiator.
	case sharedConstructionPublicMockBeneathCycleEdge
	/// On a stream of its own (`publicMockKeywordLabelRandomSeedMask`), labels that the generated configurations declare
	/// as members, spelled as keywords: `KeywordHome`, a `.public` type of the declaring module, builds `KeywordKind` under
	/// `Type` and `KeywordHolder` under `Protocol`, and `KeywordHolder` builds `KeywordKind` under `Self` and `init` and
	/// takes a default-valued `default`; `KeywordApp`, a mocked consumer, builds `KeywordHome` under `Type`, so that its
	/// overrides and the public mock's, and the module-level configuration of `KeywordHolder`, declare keyword members.
	case keywordLabeledPublicMock
	/// `KeywordApp` also builds `KeywordLocal`, a type of its own module that builds `KeywordKind` under `Protocol`, so that
	/// an internal `SafeDIMockConfiguration` declares a keyword member too.
	case keywordLabeledPublicMockBesideInternalConfiguration

	/// On a stream of its own (`publicMockOverrideClosureRandomSeedMask`), a call of a public mock that takes no
	/// `SafeDIOverrides`, whose node's override member is a closure: `OverriddenScreen`, a mocked consumer, builds
	/// `OverriddenDetail`, a `.public` type of the declaring module that builds nothing but places. The call cannot hand the
	/// closure a builder a person writes, and the consumer's overrides then hold no member for it, where a `.public` consumer
	/// passes a place up (S1), or where its fill of the `OverriddenPlace1Api` place reads the call's other place or a value the
	/// called mock renames (S2); every other call keeps the member (`GraphFuzzerToolRuns.publicMockOverrideClosureFailure`).
	case overrideClosureCall
	case overrideClosureCallPublicCallerPassesPlaceUp
	case overrideClosureCallFillReadsCalledMocksOtherPlace
	case overrideClosureCallFillReadsValueCalledMockRenames
	/// A call the draw keeps the member for; one whose internal consumer passes a place up; and one whose fill reads the
	/// value the call passes the called mock under the fill's label.
	case overrideClosureCallCanHand
	case overrideClosureCallInternalCallerPassesPlaceUp
	case overrideClosureCallFillReadsCalledMocksParameter
	/// A call whose fill reads the session `OverriddenScreen` builds, which `OverriddenDetail` does not receive: the consumer
	/// fills the place where its production twin does (contract rule 7), and a function over that fill reads the session the
	/// consumer holds, which the override closure can be handed.
	case overrideClosureCallFillReadsConsumersValue
	/// `OverriddenDetail` holds its `OverriddenPlace1Api` place as `ErasedInstantiator<(), any OverriddenPlace1Api>`, filled
	/// by `OverriddenPlace1Live`, so a call that can hand the override closure a builder hands it the builder of a place that
	/// forwards nothing, `() -> any OverriddenPlace1Api`, as the called `mock()` takes it; the oracle compiles a closure that
	/// passes it on (`GraphFuzzerOracle.addingOverrideClosureCallers(to:of:)`).
	case overrideClosureCallPlaceIsErasedInstantiator
	/// On a stream of its own (`publicMockPromotedHoleRandomSeedMask`), a place beneath a received dependency a public mock
	/// promotes to its root lazily: `PromoteNode`, a `.public` type, builds `PromoteLeaf`, which receives `PromoteOther`, the
	/// holder of a place of `PromoteApi`, through a `LazilyInstantiated` or a `SendableLazilyInstantiated` that nothing in
	/// `PromoteNode`'s tree provides, so the mock builds it at its root, and the place is a place of the mock's like any other
	/// (adopter M2). `PromoteScreen`, a mocked consumer, builds `PromoteNode`, and `PromoteLive` fills the place, or nothing
	/// does and its mock takes the builder.
	case promotedHolePublicMock
	case promotedHolePublicMockLazily
	case promotedHolePublicMockSendableLazily
	case promotedHolePublicMockPassedUp
	case promotedHolePublicMockPublicConsumer

	/// On a stream of its own (`publicMockOuterFulfillerRandomSeedMask`), a dependency two public mocks of a module beneath
	/// build when passed `nil`, which the module between cannot construct and the calling module can
	/// (`drawFulfillerOnlyCallingModuleCanBuild`).
	case outerFulfillerPublicMockCall

	/// On a stream of its own (`publicMockUnbuildableValueRandomSeedMask`), a value a consumer's mock cannot build, passed to
	/// the public mock it calls: `UnbuildableScreen`, a mocked consumer, instantiates `unbuildableFilter`, of a plain type, and
	/// `UnbuildableService`, a `.public` type of the declaring module beneath which `UnbuildableCache` receives it only if
	/// available.
	case unbuildableValuePublicMockCall
	/// The value is of a public class, which every tier takes.
	case unbuildableValuePublicMockCallPublicTier
	/// The consumer is in another package and the value is of `[3 of Int]`, which SafeDI proves `package`: the public tier
	/// the consumer calls omits it, which the tool reports (`leafTierOmitsProvidedValue`) rather than passing `nil`, so no
	/// graph of this shape is accepted.
	case unbuildableValuePublicMockCallTierOmits
	/// On a stream of its own (`publicMockHoleLabelRandomSeedMask`), a hole whose label a promoted sibling receives as another
	/// type: `LabelHome`, a `.public` type, instantiates `labelGadget` of a type no declaration fulfills, and receives
	/// `labelPanelBuilder`, whose `LabelPanel` receives `labelGadget: Instantiator<LabelWidget>`, so that the public mock would
	/// bind the hole's value under a name of its own, which the tool rejects (`publicMockHoleSiteBoundApartFinding`), so no
	/// graph of this shape is accepted. The hole is held as itself, or as one of the wrappers below.
	case holeLabelReceivedByPromotedSibling
	case holeLabelReceivedByPromotedSiblingHeldInInstantiator
	case holeLabelReceivedByPromotedSiblingHeldInLazilyInstantiated
	/// The hole is labeled `labelGadget_lazilyInstantiated`, the name SafeDI generates for the `LazilyInstantiated` it wraps
	/// around the value `LabelPanel` receives as `labelGadget: LazilyInstantiated<LabelWidget>`, so that no type receives
	/// the hole's label and the tool names the generated value instead.
	case holeLabelReceivedByPromotedSiblingEqualsGeneratedName
	/// On a stream of its own (`publicMockCarrierOrderRandomSeedMask`), a holder of one of a public mock's places declared
	/// before a sibling that holds none: `CarrierHome`, a `.public` type of the declaring module, declares `carrierStore`,
	/// `carrierCart`, which receives it, and before them, or between them, the holder of a place of `CarrierApi`. The mock
	/// builds the holder after its siblings, so that the place's scope struct carries them, and its `SafeDIOverrides` takes
	/// them in declaration order all the same (`GraphFuzzerToolRuns.publicMockOverridesOrderFailure`). `CarrierApp`, a mocked
	/// consumer, builds `CarrierHome`, and `CarrierLive` fills the place.
	case carrierBeforeSibling
	/// The holder is declared between `carrierStore` and `carrierCart`, rather than before both.
	case carrierBeforeSiblingBetweenSiblings
	/// The holder is `CarrierBanner`, a seam of the declaring module whose tree holds the place, rather than `CarrierPart`,
	/// whose own property is the place.
	case carrierBeforeSiblingThroughSameModuleSeam
	/// `CarrierShelf`, a type `CarrierHome` builds, declares the three, so that `CarrierShelf`'s module-level configuration,
	/// which `CarrierHome`'s overrides nest, takes them in declaration order.
	case carrierBeforeSiblingBeneathConfiguredChild
	/// `CarrierLocal`, a type of the declaring module with an internal mock, builds `CarrierShelf` too, so that `CarrierShelf`'s
	/// internal `SafeDIMockConfiguration` takes the three in declaration order, as its module-level configuration does.
	case carrierBeforeSiblingBeneathInternallyConfiguredChild
	/// On a stream of its own (`publicMockWrapperReadByValueRandomSeedMask`), a value a public mock takes as the wrapper its
	/// tree receives that its tree also reads by value: `WrapNode`, a `.public` type of the declaring module, which cannot
	/// build `WrapSession`, receives it and builds `WrapReader`, which receives it in the other form, one of them as a
	/// `LazilyInstantiated` or, in a `Sendable` graph, now and then a `SendableLazilyInstantiated`, and the other by value.
	/// `WrapScreen`, a mocked consumer, builds the wrapper and `WrapNode`, whose public mock it hands the wrapper.
	case wrapperReadByValuePublicMock
	/// `WrapNode` itself receives the value by value, and `WrapReader` the wrapper.
	case wrapperReadByValuePublicMockMockedTypeReadsValue
	/// `WrapNode` itself receives the value by value only if available, and `WrapReader` the wrapper.
	case wrapperReadByValuePublicMockMockedTypeReadsValueOnlyIfAvailable
	/// `WrapNode` receives the wrapper, and `WrapReader` the value by value.
	case wrapperReadByValuePublicMockTreeReadsValue
	/// The wrapper is a `SendableLazilyInstantiated`.
	case wrapperReadByValuePublicMockSendably
	/// `WrapNode` builds `WrapReader` through an `Instantiator`.
	case wrapperReadByValuePublicMockReaderThroughInstantiator
	/// On a stream of its own (`publicMockValueFormsRandomSeedMask`), one value received in several forms beside a call of
	/// a public mock that takes it: `FormScreen`, a mocked consumer, builds `FormCache`, a `.public` type of the declaring
	/// module that receives `formSession` by value, only if available or lazily, and one to three siblings, each receiving
	/// it by value, only if available, through either wrapper kind (the `Sendable` one only in a `Sendable` graph),
	/// through an optional wrapper only if available, renamed, or as another type.
	case valueFormsBesidePublicMockCall
	/// `FormSession` is a plain class no module builds, so that the consumer's mock takes it too.
	case valueFormsBesidePublicMockCallUnbuildableValue
	/// `FormScreen`'s mock is `.public`.
	case valueFormsBesidePublicMockCallPublicConsumer
	/// `FormScreen` builds `FormHolder`, which builds `FormCache` and itself again through an instantiator, an edge
	/// `cycleEdges` prunes.
	case valueFormsBesidePublicMockCallBeneathCycleEdge
	/// `FormCache` receives the value only if available.
	case valueFormsBesidePublicMockCallCalledTakesOptional
	/// Two siblings receive the value through two wrapper forms: a `LazilyInstantiated` beside a
	/// `SendableLazilyInstantiated`, or a wrapper beside an optional wrapper.
	case valueFormsBesidePublicMockCallTwoWrapperForms
	/// A sibling renames the value.
	case valueFormsBesidePublicMockCallRenamed
	/// `FormScreen` itself receives the value too.
	case valueFormsBesidePublicMockCallConsumerReceivesValue
	/// `FormScreen` also builds `FormBadge`, a `.public` type that takes nothing, whose public mock builds nothing but itself.
	case valueFormsBesidePublicMockCallEmptyPublicMock
	/// A type receives the label as `FormMark`, another type than the value's, so that the mock names the two apart.
	case valueFormsBesidePublicMockCallLabelOfAnotherType
	/// `FormCache` builds `FormCacheEntry`, which receives the label in a form of its own.
	case valueFormsBesidePublicMockCallCalledTreeReceivesValue
	/// `FormScreen`'s public mock receives an optional wrapper of the value only if available beside a sibling that
	/// receives the label as `FormMark`, so that it names the wrapper apart by its type.
	case valueFormsBesidePublicMockCallPublicOptionalWrapperBesideOtherType
	/// On a stream of its own (`publicMockOptionalPlaceRandomSeedMask`), a place a public mock's tree instantiates only if
	/// available, which no declaration of its module fulfills, so that the public mock takes a builder for it that returns
	/// the optional: `OptionalNode`, a `.public` type of the declaring module, holds `optionalApi: (any OptionalApi)?`, or
	/// `OptionalLeaf`, which it builds, does. `OptionalScreen`, a mocked consumer, builds `OptionalNode`, and `OptionalLive`
	/// beside it fulfills `OptionalApi`, so that its mock fills each place, or nothing does and its mock passes the builder up.
	case optionalPlacePublicMock
	/// `OptionalLeaf`, beneath `OptionalNode`, holds the place.
	case optionalPlacePublicMockOnLeaf
	/// `OptionalNode` builds `OptionalLeaf` through a `SendableInstantiator`, so that the place is built inside a `@Sendable`
	/// function.
	case optionalPlacePublicMockSendably
	/// A type beneath the holder receives the place's value only if available.
	case optionalPlacePublicMockReceived
	/// No declaration fulfills `OptionalApi`, so that the consumer's mock takes the builder and passes it up.
	case optionalPlacePublicMockPassedUp
	/// `OptionalScreen`'s mock is `.public`.
	case optionalPlacePublicMockPublicConsumer

	/// On a stream of its own (`publicMockTwinRandomSeedMask`), twins over a shared screen beneath a public mock
	/// (`drawTwinsPublicMock`), one case per `TwinShape` it draws.
	case twinsPublicMock
	case twinsPublicMockValueFirst
	case twinsPublicMockWrapperFirst
	case twinsPublicMockSendableWrapper
	case twinsPublicMockScreenReceivesOnlyIfAvailable
	case twinsPublicMockScreenBuildsPanel
	case twinsPublicMockFirstThroughInstantiator
	case twinsPublicMockTopOpensSecond

	/// The feature of the public mock corpus that `shape` is, where it draws the shape.
	static func twinsPublicMock(_ shape: TwinShape) -> GraphFuzzerPublicMockDrawFeature? {
		switch shape {
		case .drawn: .twinsPublicMock
		case .valueFirst: .twinsPublicMockValueFirst
		case .wrapperFirst: .twinsPublicMockWrapperFirst
		case .sendableWrapper: .twinsPublicMockSendableWrapper
		case .screenReceivesOnlyIfAvailable: .twinsPublicMockScreenReceivesOnlyIfAvailable
		case .screenBuildsPanel: .twinsPublicMockScreenBuildsPanel
		case .firstThroughInstantiator: .twinsPublicMockFirstThroughInstantiator
		case .topOpensSecond: .twinsPublicMockTopOpensSecond
		case .inSeam, .themeInSameForm, .themeInMixedForms, .themeInMixedFormsInsideSendableBuilder: nil
		}
	}

	/// The shapes of `overrideClosureCall` whose call can hand an override closure no builder a person writes, so that the
	/// consumer's overrides hold no member for it.
	static let overrideClosureCannotHandShapes: Set<GraphFuzzerPublicMockDrawFeature> = [.overrideClosureCallPublicCallerPassesPlaceUp, .overrideClosureCallFillReadsCalledMocksOtherPlace, .overrideClosureCallFillReadsValueCalledMockRenames]

	/// Whether one of the gating draws (`selfBuildingPublicMock…`, `placeInsidePublicMockFill…`,
	/// `retentionPublicMockValueBeforeBuilder…`, `sharedConstructionPublicMock…`, `keywordLabeledPublicMock…`,
	/// `overrideClosure…`, `promotedHolePublicMock…`, `unbuildableValuePublicMockCall…`, `carrierBeforeSibling…`,
	/// `wrapperReadByValuePublicMock…`, `valueFormsBesidePublicMockCall…`, `optionalPlacePublicMock…`,
	/// `outerFulfillerPublicMockCall`, `twinsPublicMock…`, and `T6`'s mock isolated to the main
	/// actor or built with its hand-written mock in another public mock) draws this shape, whose count in accepted graphs the
	/// public mock corpus pins too (`acceptedPublicMockDrawFeatureCounts`), at least ten each.
	/// `unbuildableValuePublicMockCallTierOmits` is not one: the tool rejects every graph of it, which
	/// `publicMockCorpusOmittedValueGraphCount` counts. Nor is `holeLabelReceivedByPromotedSibling…`, whose every graph the
	/// tool rejects too, with the first of `GraphFuzzerOracle.publicMockOnlyErrorMarkers`.
	var isCountedWhenAccepted: Bool {
		rawValue.hasPrefix("selfBuildingPublicMock") || rawValue.hasPrefix("placeInsidePublicMockFill") || isRetentionShape
			|| rawValue.hasPrefix("sharedConstructionPublicMock") || rawValue.hasPrefix("keywordLabeledPublicMock")
			|| rawValue.hasPrefix("overrideClosureCall") || rawValue.hasPrefix("promotedHolePublicMock")
			|| rawValue.hasPrefix("unbuildableValuePublicMockCall") && self != .unbuildableValuePublicMockCallTierOmits
			|| rawValue.hasPrefix("carrierBeforeSibling")
			|| rawValue.hasPrefix("wrapperReadByValuePublicMock")
			|| rawValue.hasPrefix("valueFormsBesidePublicMockCall")
			|| rawValue.hasPrefix("optionalPlacePublicMock")
			|| rawValue.hasPrefix("outerFulfillerPublicMockCall")
			|| rawValue.hasPrefix("twinsPublicMock")
			|| self == .holeMockIsolatedToMainActor || self == .holeHandWrittenMockBuiltInPublicMock
			|| self == .ownOptionalDefaultOnNonisolatedTypeThatBuilds
	}

	/// Whether the retention oracle's gating draw (`retentionPublicMockValueBeforeBuilder…`) draws this shape, whose
	/// graphs gate only where the retention oracle judged them.
	var isRetentionShape: Bool {
		rawValue.hasPrefix("retentionPublicMockValueBeforeBuilder")
	}

	static func < (lhs: GraphFuzzerPublicMockDrawFeature, rhs: GraphFuzzerPublicMockDrawFeature) -> Bool {
		lhs.rawValue < rhs.rawValue
	}
}

/// What the generated code of a graph the tool accepts shows, read from it, never from the draw (section 6's output
/// features). `publicMockCorpusOutputFeatureMinimumShares` pins each one the corpus shows; the consumer's call of a public
/// mock (`consumerCall`, `consumerPassesInstance`) needs the consumer side.
/// That no generated internal mock takes a `LazilyInstantiated` parameter for a receive is `wrapperParameterFailure`, an
/// oracle every graph of every corpus passes.
enum GraphFuzzerPublicMockOutputFeature: String, CaseIterable, Comparable {
	/// A `public static func mock(`, and a second and a third tier of one type's mock.
	case publicTier
	case secondTier
	case thirdTier
	/// A module-level configuration, `__safeDI_<Module>_…_MockConfiguration`.
	case moduleConfiguration
	/// A configuration whose `public init() {` takes nothing.
	case allNonPublicConfiguration
	/// A construction function, `__safeDI_init(` or `__safeDI_mock(`, and one isolated to the main actor.
	case constructionFunction
	case isolatedConstruction
	/// A non-optional default rewritten as `?? (`.
	case defaultRewritten
	/// A configuration's module-level forwarder of a default's provider, `@usableFromInline nonisolated func
	/// __safeDI_<Module>_<Type>_mockDefault_<label>()`, not a public mock's own provider in its type's extension.
	case forwardedProvider
	/// A consumer's call of a `.public` type's mock, in a module other than the type's.
	case consumerCall
	/// A consumer's leaf call passing `.instance`, which only the gap "A lazy value a public mock takes" leaves
	/// (`public-mock-builders.md`) and no smoke graph shows, so it has no minimum share.
	case consumerPassesInstance
	/// A parameter of a public mock's `mock()` that takes the `LazilyInstantiated` or `SendableLazilyInstantiated` its tree
	/// receives, `analytics: LazilyInstantiated<Analytics>`, in the declaring module's file.
	case publicMockTakesWrapper
	/// A consumer's `SafeDIOverrides` entry typed `(@Sendable () -> `.
	case consumerSendableFactory
	/// A consumer's mock building a `.public` type inline, with its initializer or its `customMockName` method.
	case consumerInline
	/// A `SafeDIMockConfiguration` struct nested in a configured type, as today's mocks generate.
	case configurationStruct
	/// A consumer's call of a `.public` type's mock wrapped in its eraser, `AnyT<i>(T<i>.mock(`, and an inline
	/// construction wrapped in it.
	case consumerErasedCall
	case consumerErasedInline
	/// A public mock taking a builder for a hole, `<label>Builder: @escaping (…SafeDIMockScope_…`, and a `@Sendable` one,
	/// `<label>SendableBuilder: @escaping @Sendable (…SafeDISendableMockScope_…`, in the declaring module.
	case holeBuilder
	case sendableHoleBuilder
	/// Generated code building `HoleLoop`, the loop around `T6`'s hole, `let holeLoopBuilder = …`
	/// (`GraphFuzzerPublicMockDrawFeature.holeInsideLoop`).
	case holeLoopBuilder
	/// A consumer's mock filling a called public mock's places with functions of its own (`func __safeDI_…(_ scope:
	/// …MockScope_…`, a fill or a dispatcher), a fill that calls the public mock again with the fill around it (a fully
	/// lazy cycle), and a consumer's mock taking a builder and passing it up.
	case consumerFillsHole
	case consumerFillReentersPublicMock
	case consumerPassesHoleBuilderUp
	/// The comment naming a type the file's `public` declarations name that SafeDI reads no declaration of, which it counts
	/// as `public` (`GraphFuzzerPublicMockDrawFeature.unreadParameterType`).
	case unreadTypeComment
	/// A public mock's function only generated code calls, `static func __safeDI_mock(`, which every tier declares beside its
	/// `mock()`, taking a builder struct.
	case generatedOnlyMockFunction
	/// That function isolated to the main actor, `@MainActor public static func __safeDI_mock(`
	/// (`GraphFuzzerPublicMockDrawFeature.holeMockIsolatedToMainActor`).
	case isolatedGeneratedOnlyMockFunction
	/// A type whose extensions declare both that function and the construction function of one name, which takes
	/// `safeDIBuilder:` (`GraphFuzzerPublicMockDrawFeature.holeHandWrittenMockBuiltInPublicMock`).
	case generatedOnlyMockFunctionBesideConstructionFunction
	/// A consumer's call of a public mock's function only generated code calls passing the struct its level functions
	/// return, `<label>: __safeDI_<…>()`.
	case consumerPassesLevelFunctionsStruct
	/// A consumer's call of a public mock's function only generated code calls that passes a place up without handing any
	/// written code a scope: a level function's struct over the caller's own as `up`, `.init(__safeDI_noScope: <builder>)`,
	/// or a member of the caller's own struct.
	case consumerPassesPlaceUpWithoutScope
	/// `HoleLoop`'s generated code (`holeLoopBuilder`) in a graph whose `T6` takes the builder struct for its hole type.
	case holeLoopBuilderOfBuilderStruct
	/// A consumer's call of the function only generated code calls of a `.public` type's mock that has two tiers or more
	/// and takes no builder struct, whose wider tiers forward to the narrower ones' functions only generated code calls,
	/// never to their `mock()`.
	case consumerCallsTieredMockWithoutBuilderStruct

	static func < (lhs: GraphFuzzerPublicMockOutputFeature, rhs: GraphFuzzerPublicMockOutputFeature) -> Bool {
		lhs.rawValue < rhs.rawValue
	}
}

/// A spelling of R15's type-spelling axis: the type of the value `spelled<index>` that `GraphFuzzerPublicMockDraw` draws on
/// its spelling stream. R15's tenth spelling, another module's type, needs a module below the declaring one, which the
/// draw does not have.
enum GraphFuzzerPublicMockSpelling: CaseIterable {
	case plain
	case closure
	case sendableClosure
	case optionalClosure
	case tuple
	case existential
	case nested
	case generic
	case `typealias`

	/// The spelled type in a graph whose names begin with `prefix`.
	func spelledType(prefix: String) -> String {
		switch self {
		case .plain:
			"\(prefix)SpellValue"
		case .closure:
			"() -> Void"
		case .sendableClosure:
			"@Sendable () -> Void"
		case .optionalClosure:
			"(() -> Void)?"
		case .tuple:
			"(onTap: () -> Void, count: Int)"
		case .existential:
			"any \(prefix)SpellProtocol"
		case .nested:
			"\(prefix)SpellOuter.Item"
		case .generic:
			"Result<\(prefix)SpellValue, any Error>"
		case .typealias:
			"\(prefix)SpellIdentifier"
		}
	}

	/// A value of the spelled type.
	func sampleExpression(prefix: String) -> String {
		switch self {
		case .plain:
			"\(prefix)SpellValue()"
		case .closure, .sendableClosure, .optionalClosure:
			"{}"
		case .tuple:
			"(onTap: {}, count: 1)"
		case .existential:
			"\(prefix)SpellConformer()"
		case .nested:
			"\(prefix)SpellOuter.Item()"
		case .generic:
			".success(\(prefix)SpellValue())"
		case .typealias:
			"\"id\""
		}
	}

	var drawFeature: GraphFuzzerPublicMockDrawFeature {
		switch self {
		case .plain: .spelledPlain
		case .closure: .spelledClosure
		case .sendableClosure: .spelledSendableClosure
		case .optionalClosure: .spelledOptionalClosure
		case .tuple: .spelledTuple
		case .existential: .spelledExistential
		case .nested: .spelledNested
		case .generic: .spelledGeneric
		case .typealias: .spelledTypealias
		}
	}

	/// The spelling of `type`, a type `spelledType(prefix:)` returned or its optional form, read back: an optional closure
	/// is itself, rather than the closure's optional form.
	static func spelling(ofType type: String, prefix: String) -> GraphFuzzerPublicMockSpelling? {
		allCases.first { $0.spelledType(prefix: prefix) == type }
			?? allCases.first { GraphFuzzerSpelling.optionalForm(of: $0.spelledType(prefix: prefix)) == type }
	}
}

// MARK: - Draw

/// The graph the `generateMockPublic` generator feature draws for a seed: a declaring module, `FuzzFeature` in package
/// `shop`, with one to three types declared `generateMock: .public` and their trees, and one or two consuming modules –
/// `FuzzApp` in the same package, `FuzzOther` in package `other` – whose mocked types reach them. It draws from streams
/// of its own (`publicMockRandomSeedMask`, and `publicMockSpellingRandomSeedMask` for R15's spellings) and replaces the
/// graph `GraphFuzzerGenerator` draws without the feature, so the base and seam corpora are drawn as before and every
/// finding of this corpus is the feature's.
///
/// Types are named after indices the rename-invariance oracle reverses: the `.public` types `T0` to `T2`, their
/// children `T3` to `T5`, the `.public` type `T6` whose tree holds a hole (and `T6Twin`, whose tree holds the same one,
/// renamed with it), and the consumers `T7` (same package), `T8`
/// (another package) and `T9` (a type a `Sendable` wrapper builds), each held under the label `t<index>`, and the eraser
/// `AnyT<index>` of a leaf a consumer reaches through an erasure, held under `anyT<index>`; the helper types keep their
/// names.
struct GraphFuzzerPublicMockDraw {
	/// - Parameters:
	///   - omitsSecondHolePlace: Whether the draw leaves out `secondHolePlace`, drawing the rest as with it.
	///   - builderSurfaceEdit: The edit the hole draw makes to `T6`'s hole after every roll, for the builder surface's checks.
	///   - omitsDrawsOlderReleasesReject: Whether the draw leaves out `drawOptionalPlacePublicMock`, whose
	///     `@Instantiated(onlyIfAvailable: true)` 2.3.0 rejects, for release acceptance; it draws from a stream of its own,
	///     so the rest is drawn as with it.
	init(seed: UInt64, omitsSecondHolePlace: Bool = false, builderSurfaceEdit: GraphFuzzerBuilderSurfaceEdit? = nil, omitsDrawsOlderReleasesReject: Bool = false) {
		self.omitsSecondHolePlace = omitsSecondHolePlace
		self.builderSurfaceEdit = builderSurfaceEdit
		prefix = GraphFuzzerFixture.typeNamePrefix(forSeed: seed)
		var random = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.publicMockRandomSeedMask)
		var spellingRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.publicMockSpellingRandomSeedMask)
		var requiredParameterRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.publicMockRequiredParameterRandomSeedMask)
		var isolationSpellingRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.publicMockIsolationSpellingRandomSeedMask)
		var erasureRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.publicMockErasureRandomSeedMask)
		var holeRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.publicMockHoleRandomSeedMask)
		var callShapeRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.publicMockCallShapeRandomSeedMask)
		var namespaceRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.publicMockNamespaceRandomSeedMask)
		var unreadTypeRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.publicMockUnreadTypeRandomSeedMask)
		var seamDependencyRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ GraphFuzzerSeamDependencyDraw.publicMockRandomSeedMask)
		var secondCalledMockRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.publicMockSecondCalledMockRandomSeedMask)
		var rootLevelRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.publicMockRootLevelRandomSeedMask)
		var holeLoopRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.publicMockHoleLoopRandomSeedMask)
		var holeForwardingRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.publicMockHoleForwardingRandomSeedMask)
		var holeAttributesRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.publicMockHoleAttributesRandomSeedMask)
		var receivedHoleHostRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.publicMockReceivedHoleHostRandomSeedMask)
		var sendableWrapperRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.publicMockSendableWrapperRandomSeedMask)
		var sendableAutoclosureRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.publicMockSendableAutoclosureRandomSeedMask)
		drawsSendableAutoclosureDefault = sendableAutoclosureRandom.percentChance(20)
		drawsHoleForwardingValue = holeForwardingRandom.percentChance(60)
		drawsHoleMockOnMainActor = holeAttributesRandom.percentChance(25)
		drawsHoleHandWrittenMock = holeAttributesRandom.percentChance(30)
		draw(
			random: &random,
			spellingRandom: &spellingRandom,
			requiredParameterRandom: &requiredParameterRandom,
			isolationSpellingRandom: &isolationSpellingRandom,
			erasureRandom: &erasureRandom,
			holeRandom: &holeRandom,
			callShapeRandom: &callShapeRandom,
			namespaceRandom: &namespaceRandom,
			unreadTypeRandom: &unreadTypeRandom,
			seamDependencyRandom: &seamDependencyRandom,
			secondCalledMockRandom: &secondCalledMockRandom,
			rootLevelRandom: &rootLevelRandom,
			holeLoopRandom: &holeLoopRandom,
			receivedHoleHostRandom: &receivedHoleHostRandom,
			sendableWrapperRandom: &sendableWrapperRandom,
		)
		// Which files move beneath the declaring module: decided after the rest of the draw, from a stream of its own, so
		// that a graph without it is drawn as before. Each file is read as the drawn graph writes it.
		let rendering = Rendering(prefix: prefix, storesEveryParameter: false, isKnownRight: false)
		let units = files.map { file in
			// A configuration file is found by its name, which `SafeDIConfiguration.swift` must keep in its own module.
			GraphFuzzerSeamDependencyDraw.Unit(module: file.module, source: file.declarations.map { $0(rendering) }.joined(separator: "\n\n"), mayMove: file.fileName?.hasSuffix("SafeDIConfiguration.swift") != true)
		}
		for (index, destination) in zip(files.indices, GraphFuzzerSeamDependencyDraw.destinations(of: units, typeNamePrefix: prefix, percent: GraphFuzzerSeamDependencyDraw.drawPercent, random: &seamDependencyRandom)) {
			if let destination {
				files[index].module = destination
			}
		}
		// The gating draws, each on a stream of its own and after the files that move beneath the declaring module have moved,
		// so that a graph without them is drawn, and moved, as before.
		var selfBuildRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.publicMockSelfBuildRandomSeedMask)
		var selfReceivesBuilderRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.publicMockSelfReceivesBuilderRandomSeedMask)
		drawSelfBuildingPublicMock(random: &selfBuildRandom, receivesBuilderRandom: &selfReceivesBuilderRandom)
		var placeInFillRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.publicMockPlaceInFillRandomSeedMask)
		drawPlaceInsidePublicMockFill(random: &placeInFillRandom)
		var retentionRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.publicMockRetentionRandomSeedMask)
		drawRetentionPublicMock(random: &retentionRandom)
		var sharedConstructionRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.publicMockSharedConstructionRandomSeedMask)
		drawSharedConstructionPublicMock(random: &sharedConstructionRandom)
		var keywordLabelRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.publicMockKeywordLabelRandomSeedMask)
		drawKeywordLabeledPublicMock(random: &keywordLabelRandom)
		var overrideClosureRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.publicMockOverrideClosureRandomSeedMask)
		drawOverrideClosurePublicMockCall(random: &overrideClosureRandom)
		var promotedHoleRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.publicMockPromotedHoleRandomSeedMask)
		drawPromotedHolePublicMock(random: &promotedHoleRandom)
		var unbuildableValueRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.publicMockUnbuildableValueRandomSeedMask)
		drawUnbuildableValuePassedToPublicMock(random: &unbuildableValueRandom)
		var holeLabelRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.publicMockHoleLabelRandomSeedMask)
		drawHoleLabelReceivedByPromotedSibling(random: &holeLabelRandom)
		var carrierOrderRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.publicMockCarrierOrderRandomSeedMask)
		drawCarrierBeforeSiblingPublicMock(random: &carrierOrderRandom)
		var wrapperReadByValueRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.publicMockWrapperReadByValueRandomSeedMask)
		drawWrapperReadByValuePublicMock(random: &wrapperReadByValueRandom)
		var valueFormsRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.publicMockValueFormsRandomSeedMask)
		drawValueFormsBesidePublicMockCall(random: &valueFormsRandom)
		if !omitsDrawsOlderReleasesReject {
			var optionalPlaceRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.publicMockOptionalPlaceRandomSeedMask)
			drawOptionalPlacePublicMock(random: &optionalPlaceRandom)
		}
		var outerFulfillerRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.publicMockOuterFulfillerRandomSeedMask)
		drawFulfillerOnlyCallingModuleCanBuild(random: &outerFulfillerRandom)
		var twinRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.publicMockTwinRandomSeedMask)
		drawTwinsPublicMock(random: &twinRandom)
	}

	/// The files of the graph, each beginning with its module's marker: as drawn, or, for the known-right path of the
	/// value differential, with every declaration `public` and every `generateMock: .public` turned into `true`.
	/// - Parameter storingEveryParameter: Whether each type stores every default-valued parameter it takes, and each class
	///   a creation stamp, as `GraphFuzzerGenerator.fixture(forSeed:storingEveryParameter:)` describes.
	func swiftFileContent(storingEveryParameter: Bool, isKnownRight: Bool) -> [String] {
		let rendering = Rendering(prefix: prefix, storesEveryParameter: storingEveryParameter, isKnownRight: isKnownRight)
		let presentModules = Set(files.map(\.module))
		let contents = files.map { file in
			var lines = [GraphFuzzerModule.marker + file.module.name]
			if let fileName = file.fileName {
				lines.append(GraphFuzzerFixture.fileNameMarker + fileName)
			}
			lines += file.module.dependencies.filter(presentModules.contains).map { "import \($0.name)" }
			return lines.joined(separator: "\n") + "\n\n" + file.declarations.map { $0(rendering) }.joined(separator: "\n\n") + "\n"
		}
		guard storingEveryParameter else { return contents }
		// The creation stamps' counter, in the first file of the module every other module imports.
		let counterIndex = GraphFuzzerSeamDependencyDraw.creationStampCounterIndex(in: contents)
		return GraphFuzzerSeamDependencyDraw.addingCreationStampCounterImports(to: contents).enumerated().map { index, content in
			index == counterIndex ? content + "\n" + DifferentialValueCreationStamp.counterDeclaration(named: rendering.counterName) + "\n" : content
		}
	}

	/// The access the draw gave each type narrower than `public` – its spelled level capped by the types and extensions
	/// enclosing it – by the name the fixture spells it with (`S1_Space.S1_Shelf` for a nested type): the ground truth
	/// the access oracle checks generated declarations against. Every other type the graph declares is `public`.
	private(set) var typeAccess = [String: GraphFuzzerGenerator.AccessLevel]()
	/// The label that gives the graph its second place of the hole, which the name-stability oracle leaves out: `t6Twin`, under
	/// which a consumer reaching `T6` instantiates `T6Twin`, a second public mock whose tree holds the same hole, or else
	/// `t6Second`, under which it reaches `T6` a second time (D530-1), or `nil`.
	private(set) var secondHolePlace: String?
	private let omitsSecondHolePlace: Bool
	/// Whether every type of the graph is `Sendable`, which alone may build a type inside a `@Sendable` builder.
	private var isSendableGraph = false
	private let builderSurfaceEdit: GraphFuzzerBuilderSurfaceEdit?
	/// Whether an `ErasedInstantiator` hole forwards `holeTicket: Int`, which `HoleFill` forwards.
	private var drawsHoleForwardingValue = false
	/// Whether each leaf takes a `@Sendable` `@autoclosure` with a default, which its public mock takes as an optional
	/// `@Sendable` closure and a mock that builds the leaf in its tree reads before the construction.
	private var drawsSendableAutoclosureDefault = false
	/// Whether `T6` spells `mockAttributes: "@MainActor"`, and whether it names a hand-written `customMock` that `T6Deck`
	/// builds it with (`publicMockHoleAttributesRandomSeedMask`).
	private var drawsHoleMockOnMainActor = false
	private var drawsHoleHandWrittenMock = false
	/// Whether the hole is an `ErasedInstantiator` that forwards `holeTicket: Int` (`drawsHoleForwardingValue`).
	private var holeForwardsValue = false
	/// Whether the draw made `builderSurfaceEdit`: the graph has the hole spelling the edit changes.
	private(set) var appliesBuilderSurfaceEdit = false
	/// `T6`'s hole's place where it is beneath a lazy wrapper or forwards a value, which the builder surface's floors count
	/// (`GraphFuzzerGenerator.drawnHolePlaces(forSeed:features:)`).
	private(set) var drawnHolePlaces = [GraphFuzzerDrawnHolePlace]()

	static let publicMockRandomSeedMask: UInt64 = 0x7075626C69636D6B
	static let publicMockSpellingRandomSeedMask: UInt64 = 0x7075626D6B73706C
	/// Draws only whether a parameter of a plain type narrower than its type's own access is required, which the public
	/// tier then cannot take (`publicTierOmitsRequiredParameter`): rolls added after the rest of the draw was pinned, so
	/// that its other shapes are drawn as before, about one graph in sixteen drawing the error.
	static let publicMockRequiredParameterRandomSeedMask: UInt64 = 0x7075626D6B726571
	/// Draws only whether an isolated initializer of a `@MainActor` child spells `@MainActor` itself, which the public
	/// mock's construction function mirrors, rather than taking it from its type: a roll added after the rest of the draw
	/// was pinned, so that its other shapes are drawn as before.
	static let publicMockIsolationSpellingRandomSeedMask: UInt64 = 0x7075626D6B69736F
	/// Draws only whether a consumer reaches a leaf it instantiates through an erasure, and which (G1: M8.19, M8.20b): rolls
	/// added after the rest of the draw was pinned, so that its other shapes are drawn as before.
	static let publicMockErasureRandomSeedMask: UInt64 = 0x7075626D6B657261
	/// Draws only the `.public` type `T6` whose tree holds a hole (R7), its hand-written caller, and – when
	/// `drawsHoleConsumers` is on – the consumers that reach it: rolls added after the rest of the draw was pinned, so that
	/// its other shapes are drawn as before.
	static let publicMockHoleRandomSeedMask: UInt64 = 0x7075626D6B686F6C
	/// Draws only where the namespaces `Space` and `Dock` are declared and how visible `Dock` is: `Space` in a file of its
	/// own that holds no SafeDI marker half the time, and `Dock` `package` three times in ten and, in seven of twenty,
	/// `public` inside a platform-conditioned `#if` block. Rolls added after the rest of the draw was pinned, so that its
	/// other shapes are drawn as before.
	static let publicMockNamespaceRandomSeedMask: UInt64 = 0x7075626D6B6E7370
	/// Draws only whether a leaf's child receives, only if available, a value of a type no declaration SafeDI reads
	/// declares – the standard library's `StaticString`, which the list of standard types leaves out, by value, in an
	/// array, in a tuple, or the nested `Unicode.Scalar` – which SafeDI counts as `public`, so that the public tier takes
	/// it and a run without a target graph names it in the comment (decision 54). Rolls added after the rest of the draw
	/// was pinned, so that its other shapes are drawn as before.
	static let publicMockUnreadTypeRandomSeedMask: UInt64 = 0x7075626D6B756E72
	/// Whether consumers reach `T6`, some in a module that declares an `@Instantiable` type fulfilling its hole, whose
	/// generated mock fills the builder, and some in one that does not, whose mock takes the builder and passes it on.
	/// Off, `T6` is called only by its hand-written caller, so the corpus checks the declaring side alone. Its rolls are
	/// drawn on the hole stream, after `T6`'s own, so turning it off moves no other shape.
	static let drawsHoleConsumers = true
	/// Draws only the shapes of how a consumer calls a public mock that the button-up review added: a consumer that
	/// receives the lazily instantiated `analytics` its leaf receives rather than instantiating it (EOU-1), one that reaches
	/// `T6` under a second label (D530-1), and a `mockOnly` fake that fulfills `T6`'s existential hole beside the fill or
	/// alone (D530-2): rolls added after the rest of the draw was pinned, so that its other shapes are drawn as before.
	static let publicMockCallShapeRandomSeedMask: UInt64 = 0x7075626D6B63616C
	/// Draws only whether the consumers that reach `T6` also instantiate `T6Twin`, a second `.public` type whose tree holds
	/// the same hole as `T6`'s, so that a consumer calls two public mocks of one hole type: a roll added after the rest of
	/// the draw was pinned, so that its other shapes are drawn as before.
	static let publicMockSecondCalledMockRandomSeedMask: UInt64 = 0x7075626D6B74776E
	/// Draws only what `T6`'s mock binds before its tree that a fill in a consumer module reads from the root level of
	/// `T6`'s enums (`RootLevelShape`): rolls added after the rest of the draw was pinned, so that its other shapes are drawn
	/// as before.
	static let publicMockRootLevelRandomSeedMask: UInt64 = 0x7075626D6B726F6F
	/// Draws only whether `HoleHost` builds itself again through `HoleLoop`, a loop around `T6`'s hole, and whether
	/// `HoleLoop` declares `holeContext` again: a roll added after the rest of the draw was pinned, so that its other
	/// shapes are drawn as before.
	static let publicMockHoleLoopRandomSeedMask: UInt64 = 0x7075626D6B6C6F70
	/// Draws only the shape #702 fixed, a `.public` type that builds itself again with a place beneath
	/// (`drawSelfBuildingPublicMock`): rolls added after the rest of the draw was pinned, so that its other shapes are
	/// drawn as before.
	static let publicMockSelfBuildRandomSeedMask: UInt64 = 0x7075626D6B73656C
	/// Draws only whether the shape #702 fixed has a type in `SelfNode`'s tree receive the builder of `SelfNode` rather than
	/// instantiate it (`drawSelfBuildingPublicMock`): a roll added after the rest of the draw was pinned, so that its other
	/// shapes are drawn as before.
	static let publicMockSelfReceivesBuilderRandomSeedMask: UInt64 = 0x7075626D6B737865
	/// Draws only whether `T6` builds `HoleReceiver`, which receives `HoleHost`, rather than building `HoleHost` itself:
	/// rolls added after the rest of the draw was pinned, so that its other shapes are drawn as before.
	static let publicMockReceivedHoleHostRandomSeedMask: UInt64 = 0x7075626D6B727A6B
	/// Draws only a place inside a public mock's fill (`drawPlaceInsidePublicMockFill`): rolls added after the rest of the
	/// draw was pinned, so that its other shapes are drawn as before.
	static let publicMockPlaceInFillRandomSeedMask: UInt64 = 0x7075626D6B706966
	/// Draws only the retention oracle's shape (`drawRetentionPublicMock`): rolls added after the rest of the draw was
	/// pinned, so that its other shapes are drawn as before.
	static let publicMockRetentionRandomSeedMask: UInt64 = 0x7075626D6B726574
	/// Draws only a call of a public mock whose override member is a closure (`drawOverrideClosurePublicMockCall`): rolls
	/// added after the rest of the draw was pinned, so that its other shapes are drawn as before.
	static let publicMockOverrideClosureRandomSeedMask: UInt64 = 0x7075626D6B6F7663
	/// Draws only a value a consumer's mock cannot build, passed to the public mock it calls
	/// (`drawUnbuildableValuePassedToPublicMock`): rolls added after the rest of the draw was pinned, so that its other
	/// shapes are drawn as before.
	static let publicMockUnbuildableValueRandomSeedMask: UInt64 = 0x7075626D6B756276
	/// Draws only a hole whose label a promoted sibling receives as another type (`drawHoleLabelReceivedByPromotedSibling`):
	/// rolls added after the rest of the draw was pinned, so that its other shapes are drawn as before.
	static let publicMockHoleLabelRandomSeedMask: UInt64 = 0x7075626D6B686C62
	/// Draws only a holder of a place declared before a sibling that holds none (`drawCarrierBeforeSiblingPublicMock`): rolls
	/// added after the rest of the draw was pinned, so that its other shapes are drawn as before.
	static let publicMockCarrierOrderRandomSeedMask: UInt64 = 0x7075626D6B636F72
	/// Draws only a value a public mock takes as the wrapper its tree receives that its tree, or the mocked type itself, also
	/// reads by value (`drawWrapperReadByValuePublicMock`): rolls added after the rest of the draw was pinned, so that its
	/// other shapes are drawn as before.
	static let publicMockWrapperReadByValueRandomSeedMask: UInt64 = 0x7075626D6B777276
	/// Draws only one value received in several forms beside a call of a public mock that takes it
	/// (`drawValueFormsBesidePublicMockCall`): rolls added after the rest of the draw was pinned, so that its other shapes
	/// are drawn as before.
	static let publicMockValueFormsRandomSeedMask: UInt64 = 0x7075626D6B76666D
	/// Draws only a dependency public mocks of a module beneath build when passed `nil`, which the module between cannot
	/// construct and the calling module can (`drawFulfillerOnlyCallingModuleCanBuild`): rolls added after the rest of the
	/// draw was pinned, so that its other shapes are drawn as before.
	static let publicMockOuterFulfillerRandomSeedMask: UInt64 = 0x7075626D6B6F6666
	/// Draws only twins beneath a public mock (`drawTwinsPublicMock`): rolls added after the rest of the draw was pinned, so
	/// that its other shapes are drawn as before.
	static let publicMockTwinRandomSeedMask: UInt64 = 0x7075626D6B747764
	/// Draws only whether a `Sendable` graph the main stream draws without a `Sendable` wrapper above a leaf (`T9`) draws one
	/// anyway, and in which consumer module, so that a consumer's overrides hold a `@Sendable` factory
	/// (`GraphFuzzerPublicMockOutputFeature.consumerSendableFactory`) in a share of the accepted graphs that clears its floor
	/// with margin: rolls added after the rest of the draw was pinned, so that its other shapes are drawn as before.
	static let publicMockSendableWrapperRandomSeedMask: UInt64 = 0x7075626D6B737772
	/// Draws only whether the leaves take `pollInterval: @autoclosure @escaping @Sendable () -> Int = 3`
	/// (`drawsSendableAutoclosureDefault`): a roll added after the rest of the draw was pinned, so that its other shapes
	/// are drawn as before.
	static let publicMockSendableAutoclosureRandomSeedMask: UInt64 = 0x7075626D6B736163
	/// Draws only whether an `ErasedInstantiator` hole forwards a value, `holeTicket: Int`, which `HoleFill` forwards
	/// (`holeForwardsValue`): a roll added after the rest of the draw was pinned, so that its other shapes are drawn as
	/// before.
	static let publicMockHoleForwardingRandomSeedMask: UInt64 = 0x7075626D6B667764
	/// Draws only a type a module's public mocks build two ways (`drawSharedConstructionPublicMock`): rolls added after the
	/// rest of the draw was pinned, so that its other shapes are drawn as before.
	static let publicMockSharedConstructionRandomSeedMask: UInt64 = 0x7075626D6B736863
	/// Draws only labels the generated configurations declare as members, spelled as keywords
	/// (`drawKeywordLabeledPublicMock`): rolls added after the rest of the draw was pinned, so that its other shapes are
	/// drawn as before.
	static let publicMockKeywordLabelRandomSeedMask: UInt64 = 0x7075626D6B6B6579
	/// Draws only how `T6` declares its mock beyond its tree: whether it spells `mockAttributes: "@MainActor"`, so that both
	/// functions of its mock are isolated to the main actor, and whether it names a hand-written `customMock` that
	/// `T6Deck`, another `.public` type of its module, builds it with, so that its mock declares the function only generated
	/// code calls beside the construction function of one name: rolls added after the rest of the draw was pinned, so that
	/// its other shapes are drawn as before.
	static let publicMockHoleAttributesRandomSeedMask: UInt64 = 0x7075626D6B617472
	/// Draws only a place beneath a received dependency a public mock promotes to its root (`drawPromotedHolePublicMock`):
	/// rolls added after the rest of the draw was pinned, so that its other shapes are drawn as before.
	static let publicMockPromotedHoleRandomSeedMask: UInt64 = 0x7075626D6B70726F
	/// Draws only a place a public mock's tree instantiates only if available (`drawOptionalPlacePublicMock`): rolls added
	/// after the rest of the draw was pinned, so that its other shapes are drawn as before.
	static let publicMockOptionalPlaceRandomSeedMask: UInt64 = 0x7075626D6B6F7074
	/// What begins the comment in `T6`'s file that holds its hand-written caller's call, after the caller's module:
	/// `// publicMockCaller in FuzzOther: S1_T6.mock(s1_HoleBuilder: …)`. `GraphFuzzerOracle.addingPublicMockCallers` reads it.
	static let publicMockCallerMarker = "// publicMockCaller in "

	// MARK: Model

	fileprivate typealias AccessLevel = GraphFuzzerGenerator.AccessLevel

	/// How the files are written: as drawn, or for the known-right path.
	fileprivate struct Rendering {
		let prefix: String
		let storesEveryParameter: Bool
		let isKnownRight: Bool

		/// The modifier a declaration of `access` spells: `public ` on the known-right path.
		func modifier(_ access: AccessLevel) -> String {
			isKnownRight ? "public " : access.modifier
		}

		/// The modifier an extension spells, `nil` for none: none on the known-right path, whose members spell `public`.
		func extensionModifier(_ access: AccessLevel?) -> String {
			guard !isKnownRight, let access else { return "" }
			return access.modifier
		}

		var counterName: String {
			"\(prefix)CreationStamp"
		}
	}

	/// A decorated property.
	fileprivate struct Property {
		let attribute: String
		let label: String
		let type: String
	}

	/// A default-valued parameter, which is not a dependency.
	fileprivate struct DefaultParameter {
		/// `_` for an unlabeled parameter.
		var argumentLabel: String?
		let name: String
		let type: String
		let defaultValue: String
		/// Whether the parameter is an `@autoclosure` of `type`, a function type, which a type that stores every
		/// parameter stores as that function.
		var isAutoclosure = false
	}

	/// An `@Instantiable` class.
	fileprivate struct InstantiableClass {
		let name: String
		var access = AccessLevel.public
		/// The initializer's spelled access before the types it names cap it, or `nil` for the type's.
		var initializerAccess: AccessLevel?
		var arguments = [String]()
		/// `generateMock:`'s argument, `true` or `.public`, which the known-right path spells `true`.
		var mockGeneration: String?
		/// The access of a `customMockName` method, `customMock`, when the type has one.
		var customMockAccess: AccessLevel?
		var isMainActor = false
		var initializerIsNonisolated = false
		/// Whether the initializer spells the `@MainActor` its type has.
		var initializerSpellsMainActor = false
		var properties = [Property]()
		var defaults = [DefaultParameter]()
		var conformances = [String]()
		/// Static members, each spelled at the narrower of its access and the initializer's (`nonisolated` in a
		/// `@MainActor` type): `static let defaultCapacity = 10`.
		var staticMembers = [(access: AccessLevel, declaration: String)]()
		/// The narrowest access of the types the initializer names, which caps it so that the fixture compiles.
		var narrowestNamedAccess = AccessLevel.public

		mutating func names(_ access: AccessLevel) {
			narrowestNamedAccess = min(narrowestNamedAccess, access)
		}

		mutating func add(_ property: Property) {
			guard !properties.contains(where: { $0.label == property.label }) else { return }
			properties.append(property)
		}
	}

	fileprivate struct File {
		var module: GraphFuzzerModule
		/// The file's name, for a file whose name `GraphFuzzerFixture.fileNames` should not read from its first
		/// `@Instantiable` type: one declaring none, or a configuration.
		var fileName: String?
		var declarations: [(Rendering) -> String]
	}

	private let prefix: String
	private var files = [File]()

	private func name(_ suffix: String) -> String {
		"\(prefix)\(suffix)"
	}

	// MARK: Drawing

	/// What the draw decided about one `.public` type.
	private struct Leaf {
		var declaration: InstantiableClass
		var child: InstantiableClass
		var receivesAnalyticsLazily = false
		var receivesTheme = false
		/// The holder its tree receives only if available, which a consumer may hold: `holder<index>: Dock.Holder<index>`.
		var holder: (label: String, type: String)?
		/// The spelled value it receives that every consumer forwards.
		var spelledConsumerValue: (label: String, type: String)?
		/// Whether the leaf forwards a property, so that a consumer must receive it rather than instantiate it.
		var forwards = false
		/// Whether a consumer's mock would hand the leaf a spelled value that is not `Sendable`, which a `@Sendable` builder
		/// could not capture.
		var receivesNonSendableSpelledValue = false
	}

	/// How `T6`'s hole is declared: as the class `Hole`, as `Instantiator<Hole>`, as `any HoleProtocol`, or as an erasure
	/// of `HoleFill` to `AnyHole`, a constant or an `ErasedInstantiator`.
	private enum HoleSpelling {
		case plain
		case instantiator
		case existential
		case erasedConstant
		case erasedInstantiator

		/// Whether the hole is a builder, held under `holeBuilder`.
		var isLazy: Bool {
			switch self {
			case .plain, .existential, .erasedConstant: false
			case .instantiator, .erasedInstantiator: true
			}
		}

		/// Whether the declaring module declares `HoleProtocol` and its conformer `HoleConformer`.
		var declaresProtocol: Bool {
			switch self {
			case .plain, .instantiator: false
			case .existential, .erasedConstant, .erasedInstantiator: true
			}
		}
	}

	/// What the type a consumer module declares to fulfill `T6`'s hole depends on: nothing; `holeContext`, a field of the
	/// hole's scope struct when `T6` binds it; `holeExtra`, which no field holds, so that its caller passes the builder up;
	/// or `Instantiator<T6>`, which it instantiates, closing a fully lazy cycle back through the fill.
	private enum HoleFillDependency {
		case none
		case field
		case nonField
		case lazyCycle
	}

	/// What `T6`'s mock binds before its tree, on the root-level stream: nothing beyond the draw's other shapes; `holeSession`,
	/// of a type that conforms to `Instantiable` by hand, which the declaring module cannot build and each consumer module
	/// reaching `T6` builds through an extension of its own, and `holeToken`, received only if available, which each such
	/// consumer instantiates, both of which `T6`'s root level holds – `holeSession` received as itself or as a
	/// `LazilyInstantiated`, whose wrapper the root level holds, which each such consumer instantiates; or `holeSession`
	/// received in two forms – `HoleHost` as
	/// `HoleSession`, and `HoleSibling`, which `T6` instantiates, as `HoleDraft` – which `T6`'s mock names apart, so that its
	/// root level holds neither and `HoleHost`'s level binds its form again.
	private enum RootLevelShape {
		case none
		case values
		case labelInTwoForms
	}

	/// Where `T6`'s tree instantiates its hole: on `T6`; on the type `HoleHost` that `T6` instantiates as a wrapper; or on
	/// `HoleHost` that `HoleReceiver`, a type `T6` instantiates, receives – as itself, or as a wrapper – so that `T6`'s mock
	/// promotes `HoleHost` to its root, a dependency `T6` itself does not declare.
	private enum HolePosition {
		case direct
		case instantiator
		case lazilyInstantiated
		case sendableInstantiator
		case sendableLazilyInstantiated
		case receivedByValue
		case receivedInstantiator
		case receivedSendableInstantiator

		var wrapperName: String {
			switch self {
			case .direct, .receivedByValue: ""
			case .instantiator, .receivedInstantiator: "Instantiator"
			case .lazilyInstantiated: "LazilyInstantiated"
			case .sendableInstantiator, .receivedSendableInstantiator: "SendableInstantiator"
			case .sendableLazilyInstantiated: "SendableLazilyInstantiated"
			}
		}

		/// The type the host is held as: `HoleHost` itself, or its wrapper.
		func hostType(_ hostName: String) -> String {
			wrapperName.isEmpty ? hostName : "\(wrapperName)<\(hostName)>"
		}

		/// The label `T6`, or `HoleReceiver`, holds the host under.
		var hostLabel: String {
			switch self {
			case .direct, .lazilyInstantiated, .sendableLazilyInstantiated, .receivedByValue: "holeHost"
			case .instantiator, .sendableInstantiator, .receivedInstantiator, .receivedSendableInstantiator: "holeHostBuilder"
			}
		}

		/// Whether the hole is built inside a `@Sendable` builder function, whose place the public mock's `@Sendable` builder builds.
		var isSendable: Bool {
			switch self {
			case .direct, .instantiator, .lazilyInstantiated, .receivedByValue, .receivedInstantiator: false
			case .sendableInstantiator, .sendableLazilyInstantiated, .receivedSendableInstantiator: true
			}
		}

		/// Whether `HoleReceiver` receives the host, which `T6`'s mock then promotes to its root.
		var isReceived: Bool {
			switch self {
			case .direct, .instantiator, .lazilyInstantiated, .sendableInstantiator, .sendableLazilyInstantiated: false
			case .receivedByValue, .receivedInstantiator, .receivedSendableInstantiator: true
			}
		}
	}

	private mutating func draw(
		random: inout GraphFuzzerRandomNumberGenerator,
		spellingRandom: inout GraphFuzzerRandomNumberGenerator,
		requiredParameterRandom: inout GraphFuzzerRandomNumberGenerator,
		isolationSpellingRandom: inout GraphFuzzerRandomNumberGenerator,
		erasureRandom: inout GraphFuzzerRandomNumberGenerator,
		holeRandom: inout GraphFuzzerRandomNumberGenerator,
		callShapeRandom: inout GraphFuzzerRandomNumberGenerator,
		namespaceRandom: inout GraphFuzzerRandomNumberGenerator,
		unreadTypeRandom: inout GraphFuzzerRandomNumberGenerator,
		seamDependencyRandom: inout GraphFuzzerRandomNumberGenerator,
		secondCalledMockRandom: inout GraphFuzzerRandomNumberGenerator,
		rootLevelRandom: inout GraphFuzzerRandomNumberGenerator,
		holeLoopRandom: inout GraphFuzzerRandomNumberGenerator,
		receivedHoleHostRandom: inout GraphFuzzerRandomNumberGenerator,
		sendableWrapperRandom: inout GraphFuzzerRandomNumberGenerator,
	) {
		// Both rolls are made in every graph, so the stream is consumed the same way whatever the rest of the draw.
		let declaresSpaceInFileOfItsOwn = namespaceRandom.percentChance(50)
		let dockRoll = namespaceRandom.integer(in: 0...99)
		let dockAccess: AccessLevel = dockRoll < 30 ? .package : .public
		// Half the other graphs declare the `public` `Dock` inside a platform-conditioned `#if` block, every clause of which
		// SafeDI reads, so that `Dock` is exactly `public`, as outside every block.
		let declaresDockInsidePlatformBlock = dockRoll >= 65
		let moduleRoll = random.integer(in: 0...9)
		let consumerModules: [GraphFuzzerModule] = moduleRoll < 4 ? [.samePackageCaller, .otherPackageCaller] : moduleRoll < 7 ? [.samePackageCaller] : [.otherPackageCaller]
		let leafCount = random.integer(in: 1...3)
		// Some graphs are `Sendable` throughout, which alone may build a leaf inside a `@Sendable` builder.
		let isSendableGraph = random.percentChance(35)
		self.isSendableGraph = isSendableGraph
		let conformances = isSendableGraph ? ["@unchecked Sendable"] : []

		var declaringFiles = [File]()
		var helperFiles = [File]()
		var plainDeclarations = [(Rendering) -> String]()
		var defaultMembers = [(access: AccessLevel, declaration: String)]()
		var declared = Set<String>()
		func register(_ typeName: String, _ access: AccessLevel) {
			if access < .public {
				typeAccess[typeName] = access
			}
		}
		/// A plain class, `Sendable` – it holds nothing – so that a static default of its type is concurrency-safe.
		func plainClass(_ typeName: String, access: AccessLevel, conformances extraConformances: [String] = []) -> (Rendering) -> String {
			{ rendering in
				let inheritance = (extraConformances + ["Sendable"]).joined(separator: ", ")
				return "\(rendering.modifier(access))final class \(typeName)\(inheritance.isEmpty ? "" : ": \(inheritance)") {\n\t\(rendering.modifier(access))init() {}\n}"
			}
		}
		func instantiableClass(_ suffix: String, access: AccessLevel = .public) -> InstantiableClass {
			register(name(suffix), access)
			return InstantiableClass(name: name(suffix), access: access, conformances: conformances)
		}
		/// Declares the plain class `suffix` once, beside the defaults, and returns its name.
		func plain(_ suffix: String, access: AccessLevel) -> String {
			if declared.insert(suffix).inserted {
				register(name(suffix), access)
				plainDeclarations.append(plainClass(name(suffix), access: access))
			}
			return name(suffix)
		}
		/// Declares the `@Instantiable` class `suffix` once, in a file of its own, and returns its name.
		func instantiable(_ suffix: String, access: AccessLevel = .public) -> String {
			if declared.insert(suffix).inserted {
				helperFiles.append(File(module: .seamModule, declarations: [Self.renderer(of: instantiableClass(suffix, access: access))]))
			}
			return name(suffix)
		}
		func received(_ label: String, _ type: String, onlyIfAvailable: Bool) -> Property {
			onlyIfAvailable
				? Property(attribute: "@Received(onlyIfAvailable: true)", label: label, type: GraphFuzzerSpelling.optionalForm(of: type))
				: Property(attribute: "@Received", label: label, type: type)
		}
		/// The declaration nested in an extension's body.
		func indented(_ source: String) -> String {
			source.split(separator: "\n", omittingEmptySubsequences: false).map { $0.isEmpty ? "" : "\t" + $0 }.joined(separator: "\n")
		}
		let defaultsName = name("Defaults")
		let loggerName = name("Logger")
		let dockName = name("Dock")

		var leaves = [Leaf]()
		for leafIndex in 0..<leafCount {
			var declaration = instantiableClass("T\(leafIndex)")
			declaration.mockGeneration = ".public"
			let initializerRoll = random.integer(in: 0...7)
			declaration.initializerAccess = initializerRoll < 4 ? .package : initializerRoll == 4 ? .internal : .public
			if random.percentChance(20) {
				declaration.customMockAccess = random.element(of: [.internal, .package, .public])
			}
			// A child, narrower than public three times in four.
			let childAccessRoll = random.integer(in: 0...3)
			let childAccess: AccessLevel = childAccessRoll < 2 ? .package : childAccessRoll == 2 ? .internal : .public
			var child = instantiableClass("T\(3 + leafIndex)", access: childAccess)
			if random.percentChance(10) {
				child.isMainActor = true
				// An isolated initializer makes the leaf, and every consumer of it, isolated too. A `nonisolated` one can
				// store only `Sendable` values, which only a `Sendable` graph's types are.
				child.initializerIsNonisolated = isSendableGraph && random.percentChance(50)
				declaration.isMainActor = !child.initializerIsNonisolated
				// An isolated initializer spells `@MainActor` half the time, else takes it from its type.
				child.initializerSpellsMainActor = !child.initializerIsNonisolated && isolationSpellingRandom.percentChance(50)
			}
			if random.percentChance(20) {
				// A configuration whose only member is of a package type.
				let policyName = plain("Policy", access: .package)
				defaultMembers.append((.package, "static let policy: \(policyName)? = \(policyName)()"))
				child.defaults.append(DefaultParameter(name: "policy", type: "\(policyName)?", defaultValue: "\(defaultsName).policy"))
				child.names(.package)
			} else if random.percentChance(35) {
				// The child's own static member as its default.
				child.defaults.append(DefaultParameter(name: "capacity", type: "Int", defaultValue: "defaultCapacity"))
				child.staticMembers.append((childAccess, "static let defaultCapacity = 10"))
			}
			var leaf = Leaf(declaration: declaration, child: child)

			// What the leaf's tree receives.
			if random.percentChance(50) {
				let analyticsName = instantiable("Analytics")
				leaf.receivesAnalyticsLazily = true
				leaf.declaration.add(Property(attribute: "@Received", label: "analytics", type: "LazilyInstantiated<\(analyticsName)>"))
				if random.percentChance(25) {
					leaf.child.add(received("analytics", analyticsName, onlyIfAvailable: true))
				}
			}
			if random.percentChance(50) {
				let themeName = instantiable("Theme")
				leaf.receivesTheme = true
				if random.percentChance(50) {
					leaf.declaration.add(received("theme", themeName, onlyIfAvailable: true))
				} else {
					leaf.child.add(received("theme", themeName, onlyIfAvailable: true))
				}
			}
			// A protocol slot, whose mock is a fake.
			if random.percentChance(50) {
				leaf.declaration.add(Property(attribute: "@Instantiated", label: "logger", type: "any \(loggerName)"))
				if declared.insert("Logger").inserted {
					declareLogger(random: &random, isSendableGraph: isSendableGraph, conformances: conformances, into: &helperFiles)
				}
			}
			// The parameter types, each of a proof source, on the leaf or its child.
			for _ in 0..<random.integer(in: 0...2) {
				let isOnlyIfAvailable = random.percentChance(40)
				let onLeaf = random.percentChance(50)
				var property: Property
				var namedAccess = AccessLevel.public
				switch random.integer(in: 0...7) {
				case 0:
					// An `@Instantiable` type, proven by its own declaration.
					property = received("session", instantiable("Session", access: .package), onlyIfAvailable: isOnlyIfAvailable)
					namedAccess = .package
				case 1:
					// A plain public type only package initializers take as a dependency.
					// Required one time in ten, which no public tier can take.
					property = received("token", plain("Token", access: .public), onlyIfAvailable: !requiredParameterRandom.percentChance(10))
					namedAccess = .package
				case 2:
					// A plain public type a public initializer elsewhere in the module takes as a dependency.
					let badgeName = plain("Badge", access: .public)
					if declared.insert("BadgeHolder").inserted {
						var holder = instantiableClass("BadgeHolder")
						holder.properties = [Property(attribute: "@Received", label: "badge", type: badgeName)]
						helperFiles.append(File(module: .seamModule, declarations: [Self.renderer(of: holder)]))
					}
					property = received("badge", badgeName, onlyIfAvailable: isOnlyIfAvailable)
				case 3:
					// An allow-listed type, now and then `Swift.`-qualified.
					property = received("count", random.element(of: ["Int", "String", "Bool", "Swift.Int", "Swift.String"]), onlyIfAvailable: isOnlyIfAvailable)
				case 4:
					// An `@Instantiable` type in an extension of a namespace enum, the extension spelling `public`, `package`,
					// or no access level.
					let namespaceName = name("Space")
					let shelfName = "\(namespaceName).\(name("Shelf"))"
					if declared.insert("Space").inserted {
						let namespaceAccess: AccessLevel = random.percentChance(60) ? .public : .package
						let extensionRoll = random.integer(in: 0...2)
						let extensionAccess: AccessLevel? = extensionRoll == 0 ? nil : min(extensionRoll == 1 ? .public : .package, namespaceAccess)
						// In a spelled extension the member spells nothing; in an unspelled one it spells `public`.
						let memberAccess: AccessLevel = extensionAccess == nil ? .public : .internal
						register(namespaceName, namespaceAccess)
						register(shelfName, min(extensionAccess ?? memberAccess, namespaceAccess))
						var shelf = InstantiableClass(name: name("Shelf"), access: memberAccess, conformances: conformances)
						shelf.initializerAccess = memberAccess
						let shelfDeclaration = shelf
						let namespaceDeclaration = { (rendering: Rendering) in "\(rendering.modifier(namespaceAccess))enum \(namespaceName) {}" }
						let extensionDeclaration = { (rendering: Rendering) in
							"\(rendering.extensionModifier(extensionAccess))extension \(namespaceName) {\n\(indented(Self.render(shelfDeclaration, rendering: rendering)))\n}"
						}
						if declaresSpaceInFileOfItsOwn {
							// A file that holds no SafeDI marker, which `scan` reads because the extension extends its type.
							helperFiles.append(File(module: .seamModule, fileName: "\(namespaceName).swift", declarations: [namespaceDeclaration]))
							helperFiles.append(File(module: .seamModule, declarations: [extensionDeclaration]))
						} else {
							helperFiles.append(File(module: .seamModule, declarations: [namespaceDeclaration, extensionDeclaration]))
						}
					}
					property = received("shelf", shelfName, onlyIfAvailable: isOnlyIfAvailable)
					namedAccess = typeAccess[shelfName] ?? .public
				case 5:
					// An `@Instantiable` type declared in an extension of the child, an `@Instantiable` type of the module.
					let pinName = name("Pin\(leafIndex)")
					let qualifiedName = "\(leaf.child.name).\(pinName)"
					if declared.insert("Pin\(leafIndex)").inserted {
						register(qualifiedName, childAccess)
						var pin = InstantiableClass(name: pinName, conformances: conformances)
						pin.initializerAccess = .public
						let pinDeclaration = pin
						let childName = leaf.child.name
						helperFiles.append(File(module: .seamModule, declarations: [{ rendering in
							"extension \(childName) {\n\(indented(Self.render(pinDeclaration, rendering: rendering)))\n}"
						}]))
					}
					property = received("pin\(leafIndex)", qualifiedName, onlyIfAvailable: isOnlyIfAvailable)
					namedAccess = childAccess
				case 6:
					// An extension-based `@Instantiable` type.
					let clockName = name("Clock")
					if declared.insert("Clock").inserted {
						let clockAccess: AccessLevel = random.percentChance(70) ? .public : .package
						register(clockName, clockAccess)
						let clockClass = plainClass(clockName, access: clockAccess)
						helperFiles.append(File(module: .seamModule, declarations: [
							{ rendering in
								"@Instantiable\nextension \(clockName): Instantiable {\n\t\(rendering.modifier(clockAccess))static func instantiate() -> \(clockName) {\n\t\t\(clockName)()\n\t}\n}"
							},
							clockClass,
						]))
					}
					property = received("clock", clockName, onlyIfAvailable: isOnlyIfAvailable)
					namedAccess = typeAccess[clockName] ?? .public
				default:
					// A parameter narrower than public, a package plain type: required, which no public tier can take, one
					// time in five, else only if available, which a `package` tier beside the public one takes
					// (`GraphFuzzerPublicMockOutputFeature.secondTier`).
					property = received("seal", plain("Seal", access: .package), onlyIfAvailable: !requiredParameterRandom.percentChance(20))
					namedAccess = .package
				}
				if onLeaf {
					guard !leaf.declaration.properties.contains(where: { $0.label == property.label }) else { continue }
					leaf.declaration.add(property)
					leaf.declaration.names(namedAccess)
				} else {
					guard !leaf.child.properties.contains(where: { $0.label == property.label }) else { continue }
					leaf.child.add(property)
					leaf.child.names(namedAccess)
				}
			}
			// The leaf's default-valued parameters.
			if random.percentChance(50) {
				switch random.integer(in: 0...2) {
				case 0:
					defaultMembers.append((.public, "static let name: String? = \"service\""))
					leaf.declaration.defaults.append(DefaultParameter(name: "name", type: "String?", defaultValue: "\(defaultsName).name"))
				case 1:
					let policyName = plain("Policy", access: .package)
					defaultMembers.append((.package, "static let policy: \(policyName)? = \(policyName)()"))
					leaf.declaration.defaults.append(DefaultParameter(name: "policy", type: "\(policyName)?", defaultValue: "\(defaultsName).policy"))
					leaf.declaration.names(.package)
				default:
					// An unproven type: public, named only by a default-valued argument, now and then an unlabeled one.
					let tagName = plain("Tag", access: .public)
					defaultMembers.append((.public, "static let tag: \(tagName)? = \(tagName)()"))
					leaf.declaration.defaults.append(DefaultParameter(argumentLabel: random.percentChance(30) ? "_" : nil, name: "tag", type: "\(tagName)?", defaultValue: "\(defaultsName).tag"))
				}
			}
			if random.percentChance(50) {
				leaf.declaration.defaults.append(DefaultParameter(name: "retries", type: "Int", defaultValue: "3"))
			}
			if random.percentChance(12) {
				leaf.declaration.defaults.append(DefaultParameter(name: "onTap", type: isSendableGraph ? "@Sendable () -> Void" : "() -> Void", defaultValue: "{}"))
			}
			if drawsSendableAutoclosureDefault {
				leaf.declaration.defaults.append(DefaultParameter(name: "pollInterval", type: "@Sendable () -> Int", defaultValue: "3", isAutoclosure: true))
			}
			// A value the leaf's tree receives only if available that a consumer may hold: a public type declared in an
			// extension of the namespace `Dock` that spells no access level, which `Dock`'s declaration caps: a `package`
			// `Dock` makes it `package`, so the public tier omits it.
			if random.percentChance(30) {
				let holderName = name("Holder\(leafIndex)")
				let qualifiedName = "\(dockName).\(holderName)"
				// A `package` `Dock` caps the holder, which only a module of the declaring module's package can name.
				register(dockName, dockAccess)
				register(qualifiedName, min(.public, dockAccess))
				leaf.holder = ("holder\(leafIndex)", qualifiedName)
				var holder = InstantiableClass(name: holderName, conformances: conformances)
				holder.initializerAccess = .public
				if random.percentChance(30) {
					// The holder receives its leaf only if available, as the leaf's tree receives it.
					holder.properties = [received("t\(leafIndex)", leaf.declaration.name, onlyIfAvailable: true)]
				}
				let holderDeclaration = holder
				helperFiles.append(File(module: .seamModule, declarations: [{ rendering in
					"extension \(dockName) {\n\(indented(Self.render(holderDeclaration, rendering: rendering)))\n}"
				}]))
				if declared.insert("Dock").inserted {
					plainDeclarations.append { rendering in
						let declaration = "\(rendering.modifier(dockAccess))enum \(dockName) {}"
						return declaresDockInsidePlatformBlock ? "#if canImport(Foundation)\n\(declaration)\n#endif" : declaration
					}
				}
				leaf.child.add(received(leaf.holder?.label ?? "", qualifiedName, onlyIfAvailable: true))
				leaf.child.initializerAccess = min(leaf.child.initializerAccess ?? childAccess, .package)
			}
			// R15's spelling axis, on its own stream.
			if spellingRandom.percentChance(60) {
				let spelling = spellingRandom.element(of: GraphFuzzerPublicMockSpelling.allCases)
				declareSpellingHelpers(of: spelling, isSendable: isSendableGraph, into: &plainDeclarations, declared: &declared)
				let type = spelling.spelledType(prefix: prefix)
				let label = "spelled\(leafIndex)"
				let isSendableSpelling = isSendableGraph && ![GraphFuzzerPublicMockSpelling.closure, .optionalClosure, .tuple].contains(spelling)
				let kindRoll = spellingRandom.integer(in: 0...6)
				// What a consumer's mock hands the leaf from outside a `@Sendable` builder: a received or forwarded value.
				leaf.receivesNonSendableSpelledValue = !isSendableSpelling && [0, 1, 2, 6].contains(kindRoll)
				switch kindRoll {
				case 0:
					leaf.declaration.add(Property(attribute: "@Forwarded", label: label, type: type))
					leaf.forwards = true
				case 1:
					leaf.declaration.add(Property(attribute: "@Received", label: label, type: type))
				case 2:
					leaf.declaration.add(received(label, type, onlyIfAvailable: true))
				case 3:
					leaf.declaration.defaults.append(DefaultParameter(name: label, type: type, defaultValue: spelling.sampleExpression(prefix: prefix)))
				case 4:
					leaf.declaration.defaults.append(DefaultParameter(name: label, type: GraphFuzzerSpelling.optionalForm(of: type), defaultValue: "nil"))
				case 5 where !leaf.child.initializerIsNonisolated:
					leaf.child.defaults.append(DefaultParameter(name: label, type: type, defaultValue: spelling.sampleExpression(prefix: prefix)))
				case 5:
					// A `nonisolated` initializer of a `@MainActor` type cannot store a closure, which is not `Sendable`.
					leaf.declaration.defaults.append(DefaultParameter(name: label, type: type, defaultValue: spelling.sampleExpression(prefix: prefix)))
				default:
					// A value every consumer forwards and passes the leaf.
					leaf.declaration.add(Property(attribute: "@Received", label: label, type: type))
					leaf.spelledConsumerValue = (label, type)
				}
			}
			// A value of a type no declaration SafeDI reads declares, on its own stream.
			if unreadTypeRandom.percentChance(15) {
				let unreadType = unreadTypeRandom.element(of: ["StaticString", "[StaticString]", "(StaticString, Int)", "Unicode.Scalar"])
				leaf.child.add(received("unread\(leafIndex)", unreadType, onlyIfAvailable: true))
			}
			leaf.declaration.properties.insert(Property(attribute: "@Instantiated", label: "t\(3 + leafIndex)", type: leaf.child.name), at: 0)
			leaf.declaration.names(childAccess)
			leaves.append(leaf)
		}

		// M8.9b: two leaves that receive a package dependency, both reached by the consumer in another package.
		let twoLeavesReceiveSession = leafCount > 1 && consumerModules.contains(.otherPackageCaller) && random.percentChance(10)
		if twoLeavesReceiveSession {
			let sessionName = instantiable("Session", access: .package)
			for index in 0..<2 where !leaves[index].declaration.properties.contains(where: { $0.label == "session" }) {
				leaves[index].declaration.add(Property(attribute: "@Received", label: "session", type: sessionName))
				leaves[index].declaration.names(.package)
			}
		}
		for leaf in leaves {
			declaringFiles.append(File(module: .seamModule, declarations: [Self.renderer(of: leaf.child)]))
			declaringFiles.append(File(module: .seamModule, declarations: [Self.renderer(of: leaf.declaration)]))
		}

		// R7, on the hole stream: the `.public` type `T6`, whose tree instantiates a hole – a type no declaration of the
		// module fulfills, proven `public` by a public initializer that takes it (`HoleProver`) – on itself, or on a type
		// it builds beneath an `Instantiator`, a `LazilyInstantiated`, or a `Sendable` wrapper (`HoleHost`), or that a type it
		// builds receives (`HoleReceiver`), as itself, an `Instantiator` or a `SendableInstantiator`. The hole is
		// declared as the public class `Hole`, as `Instantiator<Hole>` (the class then conforming to `Instantiable` by
		// hand), as `any HoleProtocol`, or as an erasure of the type `HoleFill`, which only a consumer module may declare,
		// to the eraser `AnyHole`, a constant or an `ErasedInstantiator` – the last always on `T6`, so that a fill that
		// builds `T6` again through an `Instantiator` closes a fully lazy cycle. Before the hole `T6` now and then binds a
		// `package` value and a public one (`holeContext`), which the hole's scope struct holds as fields. A hand-written
		// caller in a consumer module – the other package's when there is one – calls its public mock with a builder that
		// ignores the scope it is handed (`publicMockCallerMarker`).
		let callerModule = consumerModules.contains(.otherPackageCaller) ? GraphFuzzerModule.otherPackageCaller : .samePackageCaller
		var holeLeaf: (declaration: InstantiableClass, spelling: HoleSpelling, position: HolePosition)?
		var rootLevelShape = RootLevelShape.none
		/// The type `T6` receives `holeSession` as on the root-level stream's `.values`: `HoleSession`, or its `LazilyInstantiated`.
		var rootLevelSessionType = ""
		/// The index in `declaringFiles` of `T6`'s file, which declares `T6Twin` too when a consumer reaches it.
		var holeLeafFileIndex: Int?
		/// Whether `HoleHost` builds itself again through `HoleLoop`, a loop around `T6`'s hole.
		var drawsHoleLoop = false
		/// Whether `T6` spells `mockAttributes: "@MainActor"`, so that each consumer reaching it is isolated to the main actor.
		var holeMockIsMainActor = false
		if holeRandom.percentChance(40) {
			let holeName = name("Hole")
			let protocolName = name("HoleProtocol")
			let conformerName = name("HoleConformer")
			let erasedName = name("AnyHole")
			let fillName = name("HoleFill")
			let spelling: HoleSpelling = switch holeRandom.integer(in: 0...9) {
			case 0..<3: .plain
			case 3: .instantiator
			case 4, 5: .existential
			case 6, 7: .erasedConstant
			default: .erasedInstantiator
			}
			// On `T6` half the time, else beneath a wrapper: a `Sendable` one only in a graph whose types are all `Sendable`,
			// which alone may build a type inside a `@Sendable` builder.
			let positionRoll = holeRandom.integer(in: 0...11)
			let drawnPosition: HolePosition = switch positionRoll {
			case _ where spelling == .erasedInstantiator: .direct
			case 0..<6: .direct
			case 6, 7: .instantiator
			case 8, 9: .lazilyInstantiated
			case 10: isSendableGraph ? .sendableInstantiator : .instantiator
			default: isSendableGraph ? .sendableLazilyInstantiated : .lazilyInstantiated
			}
			// On a stream of its own, half the graphs whose hole is beneath `HoleHost` have `T6` build `HoleReceiver`, which
			// receives `HoleHost` – as itself three times in ten, through an `Instantiator`, or, half the time in a graph whose
			// types are all `Sendable`, through a `SendableInstantiator` – so that `T6`'s mock promotes `HoleHost` to its root,
			// and the hole's place is beneath a dependency `T6` does not declare (the adopter's M2).
			let receivesHostRoll = receivedHoleHostRandom.integer(in: 0...99)
			let receivedFormRoll = receivedHoleHostRandom.integer(in: 0...9)
			let position: HolePosition = if drawnPosition != .direct, receivesHostRoll < 50 {
				if receivedFormRoll < 3 {
					.receivedByValue
				} else if receivedFormRoll < 5 || !isSendableGraph {
					.receivedInstantiator
				} else {
					.receivedSendableInstantiator
				}
			} else {
				drawnPosition
			}
			let holeLabel = spelling.isLazy ? "holeBuilder" : "hole"
			if spelling.declaresProtocol {
				plainDeclarations.append { rendering in "\(rendering.modifier(.public))protocol \(protocolName)\(isSendableGraph ? ": Sendable" : "") {}" }
				plainDeclarations.append(plainClass(conformerName, access: .public, conformances: [protocolName]))
			}
			let holeType: String
			let value: String
			var attribute = "@Instantiated"
			switch spelling {
			case .plain:
				holeType = holeName
				value = "\(holeName)()"
				plainDeclarations.append(plainClass(holeName, access: .public))
			case .instantiator:
				holeType = "Instantiator<\(holeName)>"
				value = "\(holeName)()"
				plainDeclarations.append(plainClass(holeName, access: .public, conformances: ["Instantiable"]))
			case .existential:
				holeType = "any \(protocolName)"
				value = "\(conformerName)()"
			case .erasedConstant, .erasedInstantiator:
				holeForwardsValue = spelling == .erasedInstantiator && drawsHoleForwardingValue
				holeType = spelling == .erasedConstant ? erasedName : "ErasedInstantiator<\(holeForwardsValue ? "Int" : "()"), \(erasedName)>"
				value = "\(erasedName)(\(conformerName)())"
				attribute = "@Instantiated(fulfilledByType: \"\(fillName)\", erasedToConcreteExistential: true)"
				plainDeclarations.append { rendering in
					[
						"\(rendering.modifier(.public))struct \(erasedName): \(protocolName) {",
						"\t\(rendering.modifier(.public))init(_ value: any \(protocolName)) {",
						"\t\tself.value = value",
						"\t}",
						"",
						"\t\(rendering.modifier(.public))let value: any \(protocolName)",
						"}",
					].joined(separator: "\n")
				}
			}
			// The proof: a public initializer, which no tree reaches, that takes the hole's type, the class an
			// `Instantiator` wraps, or the eraser.
			let provenType = switch spelling {
			case .plain, .instantiator: holeName
			case .existential: holeType
			case .erasedConstant, .erasedInstantiator: erasedName
			}
			var prover = instantiableClass("HoleProver")
			prover.properties = [Property(attribute: "@Received", label: "hole", type: provenType)]
			// The hole's place beneath a lazy wrapper, through `HoleHost`, and its place forwarding a value, each built by the
			// builder that returns the proven type.
			if [.lazilyInstantiated, .sendableLazilyInstantiated].contains(position) {
				drawnHolePlaces.append(GraphFuzzerDrawnHolePlace(kind: .lazy, returnedTypeName: GraphFuzzerDrawnHolePlace.typeName(provenType)))
			}
			if holeForwardsValue {
				drawnHolePlaces.append(GraphFuzzerDrawnHolePlace(kind: .forwarding, returnedTypeName: erasedName))
			}
			// On the root-level stream: one label in two forms needs `HoleHost`, outside every `@Sendable` function, whose place
			// a fill can read a value of a level from.
			let sessionName = name("HoleSession")
			let draftName = name("HoleDraft")
			let hostIsPlain = position != .direct && !position.isSendable
			// A fifth to three tenths of the graphs draw none, so that fills reading nothing and consumers without the providers
			// below stay in the corpus while each shape meets its floor: one label in two forms only where the host is plain.
			let rootLevelRoll = rootLevelRandom.integer(in: 0...9)
			rootLevelShape = if hostIsPlain {
				rootLevelRoll < 2 ? .none : rootLevelRoll < 3 ? .values : .labelInTwoForms
			} else {
				rootLevelRoll < 3 ? .none : .values
			}
			// `holeSession` received lazily: `T6`'s mock takes the wrapper, which its root level holds.
			rootLevelSessionType = rootLevelShape == .values && rootLevelRandom.percentChance(50) ? "LazilyInstantiated<\(sessionName)>" : sessionName
			// The types `T6`'s mock cannot build conform to `Instantiable` by hand, proven `public` by `HoleProver`'s initializer.
			switch rootLevelShape {
			case .none:
				break
			case .values:
				plainDeclarations.append(plainClass(sessionName, access: .public, conformances: ["Instantiable"]))
				prover.properties.append(Property(attribute: "@Received", label: "holeSessionProof", type: sessionName))
			case .labelInTwoForms:
				plainDeclarations.append(plainClass(sessionName, access: .public, conformances: ["Instantiable"]))
				plainDeclarations.append(plainClass(draftName, access: .public, conformances: ["Instantiable"]))
				prover.properties.append(Property(attribute: "@Received", label: "holeSessionProof", type: sessionName))
				prover.properties.append(Property(attribute: "@Received", label: "holeDraftProof", type: draftName))
			}
			helperFiles.append(File(module: .seamModule, declarations: [Self.renderer(of: prover)]))

			var declaration = instantiableClass("T6")
			declaration.mockGeneration = ".public"
			let initializerRoll = holeRandom.integer(in: 0...7)
			declaration.initializerAccess = initializerRoll < 4 ? .package : initializerRoll == 4 ? .internal : .public
			if holeRandom.percentChance(30) {
				declaration.add(Property(attribute: "@Instantiated", label: "session", type: instantiable("Session", access: .package)))
				declaration.names(.package)
			}
			// On a stream of its own: whether a loop goes around a hole on `HoleHost`, in whose graphs `T6` always binds
			// `holeContext`, which `HoleLoop` may declare again. The hole stream's roll is made either way.
			drawsHoleLoop = position != .direct && holeLoopRandom.percentChance(70)
			if holeRandom.percentChance(40) || drawsHoleLoop {
				declaration.add(Property(attribute: "@Instantiated", label: "holeContext", type: instantiable("HoleContext")))
			}
			// The builder surface's edit (`GraphFuzzerBuilderSurfaceEdit`), which draws nothing, so the graph is drawn as without it.
			var holeProperties = [Property(attribute: attribute, label: holeLabel, type: holeType)]
			if builderSurfaceEdit == .sendableInstantiatorPlaceMovedToPlainPlace, spelling == .instantiator {
				// The place a plain `Hole` on `HoleSurfaceHost`, which a `SendableInstantiator` builds, so that the place is still
				// built in a `@Sendable` function.
				var surfaceHost = instantiableClass("HoleSurfaceHost")
				surfaceHost.properties = [Property(attribute: attribute, label: "hole", type: holeName)]
				declaringFiles.append(File(module: .seamModule, declarations: [Self.renderer(of: surfaceHost)]))
				holeProperties = [Property(attribute: "@Instantiated", label: "holeSurfaceHostBuilder", type: "SendableInstantiator<\(surfaceHost.name)>")]
				appliesBuilderSurfaceEdit = true
			} else if let builderSurfaceEdit, let edited = Self.holeProperties(editedBy: builderSurfaceEdit, attribute: attribute, label: holeLabel, type: holeType, spelling: spelling, holeName: holeName, erasedName: erasedName, protocolName: protocolName, isSendableGraph: isSendableGraph) {
				holeProperties = edited.properties
				plainDeclarations += edited.declarations
				appliesBuilderSurfaceEdit = true
			}
			switch rootLevelShape {
			case .none:
				break
			case .values:
				declaration.add(Property(attribute: "@Received", label: "holeSession", type: rootLevelSessionType))
				declaration.add(Property(attribute: "@Received(onlyIfAvailable: true)", label: "holeToken", type: "\(instantiable("HoleToken"))?"))
			case .labelInTwoForms:
				var sibling = instantiableClass("HoleSibling")
				sibling.properties = [Property(attribute: "@Received", label: "holeSession", type: draftName)]
				declaringFiles.append(File(module: .seamModule, declarations: [Self.renderer(of: sibling)]))
				declaration.add(Property(attribute: "@Instantiated", label: "holeSibling", type: sibling.name))
			}
			switch position {
			case .direct:
				holeProperties.forEach { declaration.add($0) }
			case .instantiator, .lazilyInstantiated, .sendableInstantiator, .sendableLazilyInstantiated, .receivedByValue, .receivedInstantiator, .receivedSendableInstantiator:
				let hostAccess: AccessLevel = holeRandom.percentChance(50) ? .public : .package
				var host = instantiableClass("HoleHost", access: hostAccess)
				host.properties = holeProperties
				if rootLevelShape == .labelInTwoForms {
					host.properties.insert(Property(attribute: "@Received", label: "holeSession", type: sessionName), at: 0)
				}
				// On a stream of its own: a loop around the hole, `HoleHost` building `HoleLoop` through the kind of builder that
				// builds `HoleHost` (an `Instantiator` where `HoleReceiver` receives `HoleHost` itself), and `HoleLoop` building
				// `HoleHost` again under the label and wrapper `T6` builds it, or `HoleReceiver` receives it, with, so
				// that the loop closes on `HoleHost`, whose builder function holds the hole's scope values. Half the time
				// `HoleLoop` declares `holeContext` again, which `T6` binds, so that a fill reading it would read `T6`'s at
				// every level of the loop, where inline it reads the nearest `HoleLoop`'s: the public mock reports
				// `declarationBoundOnCycleReentry`, as a seam does. Otherwise it declares `holeLoopMark`, which nothing reads, so
				// that a fill reading `holeContext` reads `T6`'s at every level inline too.
				if drawsHoleLoop {
					var loop = instantiableClass("HoleLoop", access: hostAccess)
					let declaresContextAgain = holeLoopRandom.percentChance(50)
					loop.properties = [
						declaresContextAgain
							? Property(attribute: "@Instantiated", label: "holeContext", type: instantiable("HoleContext"))
							: Property(attribute: "@Instantiated", label: "holeLoopMark", type: instantiable("HoleLoopMark")),
						Property(attribute: "@Instantiated", label: position.hostLabel, type: position.hostType(host.name)),
					]
					host.add(Property(attribute: "@Instantiated", label: "holeLoopBuilder", type: "\(position.isSendable ? "SendableInstantiator" : "Instantiator")<\(loop.name)>"))
					declaringFiles.append(File(module: .seamModule, declarations: [Self.renderer(of: loop)]))
				}
				if position.isReceived {
					// `HoleReceiver`, which `T6` instantiates, receives the host, so that `T6`'s mock promotes it to its root.
					var receiver = instantiableClass("HoleReceiver", access: hostAccess)
					receiver.properties = [Property(attribute: "@Received", label: position.hostLabel, type: position.hostType(host.name))]
					declaration.add(Property(attribute: "@Instantiated", label: "holeReceiver", type: receiver.name))
					declaringFiles.append(File(module: .seamModule, declarations: [Self.renderer(of: receiver)]))
				} else {
					declaration.add(Property(attribute: "@Instantiated", label: position.hostLabel, type: position.hostType(host.name)))
				}
				declaration.names(hostAccess)
				declaringFiles.append(File(module: .seamModule, declarations: [Self.renderer(of: host)]))
			}
			// The call: a builder named by the type the hole instantiates, `<type, leading capitals lowered>Builder`, followed by
			// `_<returned type>` where the hole returns another type, handed an enum of the places, whose case carries an
			// `Instantiator`'s forwarded value; or, for a place built inside a `@Sendable` builder function, the `@Sendable`
			// builder, `<…>SendableBuilder`, handed the `@Sendable` enum. It returns the plain value.
			let enumBuilderLabel = switch spelling {
			case .plain, .instantiator: Self.builderLabel(ofTypeNamed: holeName)
			case .existential: Self.builderLabel(ofTypeNamed: protocolName)
			case .erasedConstant, .erasedInstantiator: "\(Self.builderLabel(ofTypeNamed: fillName).dropLast("Builder".count))_\(erasedName)Builder"
			}
			// What the mock takes before its builders that it cannot build: `holeSession`, as the wrapper `T6` receives it lazily,
			// or both its forms, named apart and ordered by type.
			let leadingArguments = switch rootLevelShape {
			case .none: ""
			case .values: rootLevelSessionType == sessionName ? "holeSession: \(sessionName)(), " : "holeSession: LazilyInstantiated { \(sessionName)() }, "
			case .labelInTwoForms: "holeSession_\(draftName): \(draftName)(), holeSession_\(sessionName): \(sessionName)(), "
			}
			let call = if position.isSendable {
				"\(declaration.name).mock(\(leadingArguments)\(enumBuilderLabel.dropLast("Builder".count))SendableBuilder: { _ in \(value) })"
			} else {
				"\(declaration.name).mock(\(leadingArguments)\(enumBuilderLabel): { _ in \(value) })"
			}
			// On a stream of its own: `T6`'s mock isolated to the main actor through `mockAttributes`, so that each consumer that
			// reaches it is isolated to the main actor too; and a hand-written `customMock` that `T6Deck`, another `.public`
			// type of `T6`'s module, builds `T6` with, so that `T6`'s mock declares the function only generated code calls
			// beside the construction function of one name, which `T6Deck`'s mock calls.
			holeMockIsMainActor = drawsHoleMockOnMainActor
			if holeMockIsMainActor {
				declaration.arguments.append("mockAttributes: \"@MainActor\"")
			}
			if drawsHoleHandWrittenMock {
				declaration.customMockAccess = .public
			}
			let holeDeclaration = declaration
			holeLeafFileIndex = declaringFiles.count
			var holeFileDeclarations: [(Rendering) -> String] = [
				Self.renderer(of: holeDeclaration),
				{ _ in "\(Self.publicMockCallerMarker)\(callerModule.name): \(call)" },
			]
			if drawsHoleHandWrittenMock {
				var deck = instantiableClass("T6Deck")
				deck.mockGeneration = ".public"
				deck.initializerAccess = .internal
				deck.properties = [Property(attribute: "@Instantiated", label: "t6", type: holeDeclaration.name)]
				holeFileDeclarations.append(Self.renderer(of: deck))
			}
			declaringFiles.append(File(module: .seamModule, declarations: holeFileDeclarations))
			holeLeaf = (declaration, spelling, position)
		}

		// On a stream of its own, made in every graph: whether each consumer that reaches `T6` instantiates `T6Twin` too, a
		// second `.public` type declared in `T6`'s file with `T6`'s properties, so that its tree holds the same hole, and a
		// consumer calls two public mocks of one hole type. It is the graph's second place of the hole, which the
		// name-stability oracle leaves out: a consumer whose mock passes both mocks' places up names the builders it takes
		// for them apart, after each called type, so adding it renames the first (a known issue). It names `T6Twin` only in
		// `T6`'s file, which the consumer names already, so the files that move beneath the declaring module move without
		// it too.
		let drawsSecondCalledMock = secondCalledMockRandom.percentChance(20)
		var consumerReachesSecondCalledMock = false
		// The consumers: `T7` in the same package, `T8` in another, each reaching one leaf, or both of M8.9b's.
		var consumerFiles = [File]()
		// Seven in ten `Sendable` graphs draw the wrapper on the main stream, and, on a stream of its own whose two rolls are made
		// in every graph, three in five of the rest draw it too (`publicMockSendableWrapperRandomSeedMask`).
		let drawsWrapperBesideMainStream = sendableWrapperRandom.percentChance(60)
		let wrapperModuleRoll = sendableWrapperRandom.integer(in: 0...1)
		let wrapperModule: GraphFuzzerModule? = if isSendableGraph, random.percentChance(70) {
			random.element(of: consumerModules)
		} else if isSendableGraph, drawsWrapperBesideMainStream {
			consumerModules[wrapperModuleRoll % consumerModules.count]
		} else {
			nil
		}
		for module in consumerModules {
			let consumerIndex = module == .samePackageCaller ? 7 : 8
			var consumer = instantiableClass("T\(consumerIndex)")
			let isPublicConsumer = random.percentChance(25)
			consumer.mockGeneration = isPublicConsumer ? ".public" : "true"
			let leafIndices = twoLeavesReceiveSession && module == .otherPackageCaller ? [0, 1] : [random.integer(in: 0...(leafCount - 1))]
			let reachedLeaves = leafIndices.map { leaves[$0] }
			consumer.isMainActor = reachedLeaves.contains { $0.declaration.isMainActor }
			var leafProperties = [Property]()
			var providers = [Property]()
			var providersFirst = false
			for (leafIndex, leaf) in zip(leafIndices, reachedLeaves) {
				let receivesLeaf = leaf.forwards || random.percentChance(50)
				leafProperties.append(Property(attribute: receivesLeaf ? "@Received" : "@Instantiated", label: "t\(leafIndex)", type: leaf.declaration.name))
				if leaf.receivesAnalyticsLazily, random.percentChance(50) {
					// EOU-1, on the call-shape stream: now and then the consumer receives the wrapper rather than instantiating
					// it, so its mock builds it at its root and hands each leaf call its instance – but not in the module of
					// the `Sendable` wrapper, whose `@Sendable` builder could not capture a wrapper received from outside it.
					let receivesWrapper = wrapperModule != module && callShapeRandom.percentChance(40)
					providers.append(Property(attribute: receivesWrapper ? "@Received" : "@Instantiated", label: "analytics", type: "LazilyInstantiated<\(name("Analytics"))>"))
				}
				// A public consumer leaves `theme` unprovided half the time.
				if leaf.receivesTheme, !(isPublicConsumer && random.percentChance(50)), random.percentChance(60) {
					providers.append(Property(attribute: "@Instantiated", label: "theme", type: name("Theme")))
				}
				if let spelled = leaf.spelledConsumerValue {
					providers.append(Property(attribute: "@Forwarded", label: spelled.label, type: spelled.type))
				}
				if let holder = leaf.holder, random.percentChance(55) {
					let provider = switch random.integer(in: 0...3) {
					case 0:
						Property(attribute: "@Received", label: holder.label, type: holder.type)
					case 1:
						Property(attribute: "@Instantiated", label: holder.label, type: "LazilyInstantiated<\(holder.type)>")
					default:
						Property(attribute: "@Instantiated", label: holder.label, type: holder.type)
					}
					providersFirst = random.percentChance(50)
					// A consumer in another package cannot name a holder of a `package` `Dock`, so its declaration would not
					// compile: it holds none. The rolls are made either way, so the rest of the draw is as before.
					if dockAccess == .public || module == .samePackageCaller {
						providers.append(provider)
						// A holder of a `package` `Dock` caps the initializer that takes it.
						consumer.names(dockAccess)
					}
				}
			}
			var uniqueProviders = [Property]()
			for provider in providers where !uniqueProviders.contains(where: { $0.label == provider.label }) {
				uniqueProviders.append(provider)
			}
			// G1, on the erasure stream: a leaf the consumer instantiates, reached through an erasure as a constant, an
			// `ErasedInstantiator`, or – where nothing the leaf's tree is handed from outside a `@Sendable` builder would keep
			// it from compiling: a graph whose types are all `Sendable`, no main actor, no value that is not `Sendable`, no
			// lazily instantiated dependency – a `SendableErasedInstantiator`. A main-actor leaf is erased as a constant
			// only, since its builder function would be isolated.
			for (propertyIndex, (leafIndex, leaf)) in zip(leafProperties.indices, zip(leafIndices, reachedLeaves)) where leafProperties[propertyIndex].attribute == "@Instantiated" {
				guard erasureRandom.percentChance(35) else { continue }
				let erasedName = name("AnyT\(leafIndex)")
				let attribute = "@Instantiated(fulfilledByType: \"\(leaf.declaration.name)\", erasedToConcreteExistential: true)"
				let canBuildInSendableFunction = isSendableGraph
					&& !leaf.declaration.isMainActor
					&& !leaf.receivesNonSendableSpelledValue
					&& !leaf.receivesAnalyticsLazily
					&& !uniqueProviders.contains { $0.type.hasPrefix("LazilyInstantiated<") && $0.label == leaf.holder?.label }
				let kindRoll = erasureRandom.integer(in: 0...9)
				leafProperties[propertyIndex] = if kindRoll < 4 || leaf.declaration.isMainActor {
					Property(attribute: attribute, label: "anyT\(leafIndex)", type: erasedName)
				} else if kindRoll < 6 || !canBuildInSendableFunction {
					Property(attribute: attribute, label: "anyT\(leafIndex)Builder", type: "ErasedInstantiator<(), \(erasedName)>")
				} else {
					Property(attribute: attribute, label: "anyT\(leafIndex)Builder", type: "SendableErasedInstantiator<(), \(erasedName)>")
				}
				// The protocol the leaf conforms to, which its module declares, and the eraser, a public struct that holds
				// what it erases, so that the value differential sees through it.
				if declared.insert("AnyT\(leafIndex)").inserted {
					let protocolName = name("T\(leafIndex)Protocol")
					let leafName = leaf.declaration.name
					plainDeclarations.append { rendering in
						[
							"\(rendering.modifier(.public))protocol \(protocolName)\(isSendableGraph ? ": Sendable" : "") {}",
							"",
							"extension \(leafName): \(protocolName) {}",
							"",
							"\(rendering.modifier(.public))struct \(erasedName): \(protocolName) {",
							"\t\(rendering.modifier(.public))init(_ value: any \(protocolName)) {",
							"\t\tself.value = value",
							"\t}",
							"",
							"\t\(rendering.modifier(.public))let value: any \(protocolName)",
							"}",
						].joined(separator: "\n")
					}
				}
			}
			// R7's consumers, on the hole stream: a consumer reaching `T6`, in a module that declares an `@Instantiable` type
			// fulfilling the hole – which receives nothing, a field of the hole's scope struct, a value no field holds, or
			// closes a fully lazy cycle back through the fill by instantiating `Instantiator<T6>` – or in one that declares
			// none. One module per graph declares it, since two would conform the hole's class to `Instantiable` twice in the
			// value differential's executable.
			var holeFulfillerDeclarations = [(Rendering) -> String]()
			var rootLevelExtensions = [(Rendering) -> String]()
			if Self.drawsHoleConsumers, let holeLeaf, holeRandom.percentChance(60) {
				leafProperties.append(Property(attribute: holeRandom.percentChance(50) ? "@Received" : "@Instantiated", label: "t6", type: holeLeaf.declaration.name))
				// A consumer calls a mock isolated to the main actor from its own, which is isolated to it as its type is.
				if holeMockIsMainActor {
					consumer.isMainActor = true
				}
				// On the root-level stream: the consumer's module builds what `T6`'s mock cannot through extensions of its own,
				// which add no conformance, so that two modules may declare them; the consumer instantiates `holeSession` and
				// `holeToken`, or, where `T6`'s tree receives `holeSession` in two forms, which no one scope can hold, neither,
				// and its mock builds each form.
				let extendedTypes: [String] = switch rootLevelShape {
				case .none: []
				case .values: [name("HoleSession")]
				case .labelInTwoForms: [name("HoleDraft"), name("HoleSession")]
				}
				if rootLevelShape == .values {
					uniqueProviders.append(Property(attribute: "@Instantiated", label: "holeSession", type: rootLevelSessionType))
					uniqueProviders.append(Property(attribute: "@Instantiated", label: "holeToken", type: name("HoleToken")))
				}
				for extendedType in extendedTypes {
					rootLevelExtensions.append { rendering in
						"@Instantiable(conformsElsewhere: true)\nextension \(extendedType) {\n\t\(rendering.modifier(.public))static func instantiate() -> \(extendedType) {\n\t\t\(extendedType)()\n\t}\n}"
					}
				}
				if drawsSecondCalledMock {
					consumerReachesSecondCalledMock = true
					secondHolePlace = "t6Twin"
					if !omitsSecondHolePlace {
						leafProperties.append(Property(attribute: "@Instantiated", label: "t6Twin", type: name("T6Twin")))
					}
				}
				// D530-1, on the call-shape stream: now and then the consumer instantiates `T6` under a second label too, so its
				// mock calls `T6`'s mock twice, each call with fills of its own.
				// It is the graph's second place of the hole, unless `T6Twin` is, which the name-stability oracle leaves out: two
				// calls of one mock take one builder, so the place adds a case and renames nothing. It names `T6` as the first
				// call does, so the files that move beneath the declaring module move without it too.
				if callShapeRandom.percentChance(30) {
					if secondHolePlace == nil {
						secondHolePlace = "t6Second"
					}
					if !omitsSecondHolePlace || secondHolePlace != "t6Second" {
						leafProperties.append(Property(attribute: "@Instantiated", label: "t6Second", type: holeLeaf.declaration.name))
					}
				}
				if !declared.contains("HoleFill"), holeRandom.percentChance(50) {
					declared.insert("HoleFill")
					let holeName = name("Hole")
					let extraName = name("HoleExtra")
					let canCloseLazyCycle = holeLeaf.spelling == .erasedInstantiator && holeLeaf.position == .direct
					let bindsContext = holeLeaf.declaration.properties.contains { $0.label == "holeContext" }
					let dependencyRoll = holeRandom.integer(in: 0...9)
					// A fill receiving `holeContext` where `T6` binds none receives a value no field holds, as `holeExtra` is.
					let drawnDependency: HoleFillDependency = if canCloseLazyCycle, holeRandom.percentChance(50) {
						.lazyCycle
					} else if dependencyRoll < (bindsContext ? 3 : 5) {
						.none
					} else if bindsContext ? dependencyRoll < 8 : dependencyRoll >= 8 {
						.field
					} else {
						.nonField
					}
					// On the loop's stream: a fill under a loop around the hole mostly reads `holeContext`, which `HoleLoop`
					// declares again or not. A lazy cycle through the fill needs the hole on `T6`, which no loop goes around.
					let dependency: HoleFillDependency = drawsHoleLoop && holeLoopRandom.percentChance(80) ? .field : drawnDependency
					var dependencies: [Property] = switch dependency {
					case .none: []
					case .field: [Property(attribute: "@Received", label: "holeContext", type: instantiable("HoleContext"))]
					case .nonField: [Property(attribute: "@Received", label: "holeExtra", type: extraName)]
					case .lazyCycle: [Property(attribute: "@Instantiated", label: "t6Builder", type: "Instantiator<\(holeLeaf.declaration.name)>")]
					}
					// On the root-level stream: a fill that reads nothing else its place's levels do not hold reads what `T6`'s root
					// level holds – `holeSession`, as `T6` receives it, `holeToken` only if available, or both – or, for one label in
					// two forms, the form `HoleHost`'s level binds again. A place built inside a `@Sendable` function is handed none of
					// it. A fill declared as an extension's `instantiate(…)` reads `holeSession` alone. No fill reads the instance of a
					// `holeSession` `T6` receives lazily: the draw predates `T6`'s mock taking the wrapper, which a fill now reads as
					// inline does.
					let isExtensionFill = holeLeaf.spelling == .plain || holeLeaf.spelling == .instantiator
					if !holeLeaf.position.isSendable, dependency == .none || dependency == .field && bindsContext {
						let holeSession = Property(attribute: "@Received", label: "holeSession", type: rootLevelShape == .values ? rootLevelSessionType : name("HoleSession"))
						switch rootLevelShape {
						case .none:
							break
						case .values:
							let readRoll = rootLevelRandom.integer(in: 0...2)
							if readRoll != 1 || isExtensionFill {
								dependencies.append(holeSession)
							}
							if readRoll != 0, !isExtensionFill {
								dependencies.append(Property(attribute: "@Received(onlyIfAvailable: true)", label: "holeToken", type: "\(name("HoleToken"))?"))
							}
						case .labelInTwoForms:
							dependencies.append(holeSession)
						}
					}
					if dependency == .nonField {
						holeFulfillerDeclarations.append(Self.renderer(of: instantiableClass("HoleExtra")))
					}
					let parameters = dependencies.map { "\($0.label): \($0.type)" }.joined(separator: ", ")
					switch holeLeaf.spelling {
					case .plain:
						// A conformance in another package is retroactive; in the hole's own package it is not.
						let retroactive = module == .otherPackageCaller ? "@retroactive " : ""
						holeFulfillerDeclarations.append { rendering in
							"@Instantiable\nextension \(holeName): \(retroactive)Instantiable {\n\t\(rendering.modifier(.public))static func instantiate(\(parameters)) -> \(holeName) {\n\t\t\(holeName)()\n\t}\n}"
						}
					case .instantiator:
						holeFulfillerDeclarations.append { rendering in
							"@Instantiable(conformsElsewhere: true)\nextension \(holeName) {\n\t\(rendering.modifier(.public))static func instantiate(\(parameters)) -> \(holeName) {\n\t\t\(holeName)()\n\t}\n}"
						}
					case .existential, .erasedConstant, .erasedInstantiator:
						var fill = instantiableClass("HoleFill")
						if holeLeaf.spelling == .existential {
							fill.arguments = ["fulfillingAdditionalTypes: [\(name("HoleProtocol")).self]"]
						}
						fill.conformances = [name("HoleProtocol")] + conformances
						fill.properties = dependencies
						if holeForwardsValue {
							fill.properties.insert(Property(attribute: "@Forwarded", label: "holeTicket", type: "Int"), at: 0)
						}
						// D530-2, on the call-shape stream: now and then a `mockOnly` fake fulfills the existential hole too,
						// which a mock builds in place of `HoleFill` – the inline mock, and so the fill – or alone, so that only
						// mocks fill the hole.
						let fakeRoll = holeLeaf.spelling == .existential && dependency != .lazyCycle ? callShapeRandom.integer(in: 0...9) : 9
						if !(3..<6).contains(fakeRoll) {
							holeFulfillerDeclarations.insert(Self.renderer(of: fill), at: 0)
						}
						if fakeRoll < 6 {
							let protocolName = name("HoleProtocol")
							let fakeName = name("HoleFake")
							holeFulfillerDeclarations.append { rendering in
								[
									"@Instantiable(fulfillingAdditionalTypes: [\(protocolName).self], mockOnly: true)",
									"\(rendering.modifier(.public))final class \(fakeName): \(protocolName) {",
									"\t\(rendering.modifier(.public))init() {}",
									"",
									"\t\(rendering.modifier(.public))static func mock() -> \(fakeName) {",
									"\t\t\(fakeName)()",
									"\t}",
									"}",
								].joined(separator: "\n")
							}
						}
					}
				}
			}
			var declarations = [(Rendering) -> String]()
			let canWrap = !consumer.isMainActor && !reachedLeaves.contains { $0.forwards || $0.receivesNonSendableSpelledValue || $0.declaration.isMainActor }
			if wrapperModule == module, canWrap {
				// A `Sendable` wrapper above the leaf, whose type builds the leaf and what the consumer would provide, and
				// always the lazily instantiated dependency the leaf receives, which no `@Sendable` builder can capture.
				if reachedLeaves.contains(where: \.receivesAnalyticsLazily), !uniqueProviders.contains(where: { $0.label == "analytics" }) {
					uniqueProviders.append(Property(attribute: "@Instantiated", label: "analytics", type: "LazilyInstantiated<\(name("Analytics"))>"))
				}
				var builtType = instantiableClass("T9")
				builtType.names(consumer.narrowestNamedAccess)
				builtType.properties = (providersFirst ? uniqueProviders + leafProperties : leafProperties + uniqueProviders).map { property in
					property.attribute == "@Received" && property.label.hasPrefix("t") ? Property(attribute: "@Instantiated", label: property.label, type: property.type) : property
				}
				consumer.properties = [Property(attribute: "@Instantiated", label: "t9Builder", type: "SendableInstantiator<\(builtType.name)>")]
				declarations.append(Self.renderer(of: consumer))
				declarations.append(Self.renderer(of: builtType))
			} else {
				consumer.properties = providersFirst ? uniqueProviders + leafProperties : leafProperties + uniqueProviders
				declarations.append(Self.renderer(of: consumer))
			}
			declarations += rootLevelExtensions
			consumerFiles.append(File(module: module, declarations: declarations))
			if !holeFulfillerDeclarations.isEmpty {
				consumerFiles.append(File(module: module, fileName: "\(prefix)HoleFill.swift", declarations: holeFulfillerDeclarations))
			}
		}

		// `T6Twin`, beside `T6` in its file, declared whether or not the consumers instantiate it.
		if consumerReachesSecondCalledMock, let holeLeaf, let holeLeafFileIndex {
			var twin = instantiableClass("T6Twin")
			twin.mockGeneration = holeLeaf.declaration.mockGeneration
			twin.initializerAccess = holeLeaf.declaration.initializerAccess
			twin.properties = holeLeaf.declaration.properties
			twin.narrowestNamedAccess = holeLeaf.declaration.narrowestNamedAccess
			declaringFiles[holeLeafFileIndex].declarations.insert(Self.renderer(of: twin), at: 1)
		}

		// The spelled values' named types proven `public` by a public initializer no tree reaches, as `BadgeHolder`
		// proves `Badge`: a spelled value is drawn to reach the public tier, whatever the leaf's initializer spells.
		let spellingProofs = [
			("SpellValue", Property(attribute: "@Received", label: "spellValue", type: name("SpellValue"))),
			("SpellProtocol", Property(attribute: "@Received", label: "spellProtocol", type: "any \(name("SpellProtocol"))")),
			("SpellOuter", Property(attribute: "@Received", label: "spellItem", type: "\(name("SpellOuter")).Item")),
			("SpellIdentifier", Property(attribute: "@Received", label: "spellIdentifier", type: name("SpellIdentifier"))),
			("SpellResult", Property(attribute: "@Received", label: "spellResult", type: "Result<\(name("SpellValue")), any Error>")),
		].filter { declared.contains($0.0) }.map(\.1)
		if !spellingProofs.isEmpty {
			var prover = instantiableClass("SpellProver")
			prover.properties = spellingProofs
			helperFiles.append(File(module: .seamModule, declarations: [Self.renderer(of: prover)]))
		}

		// The defaults and plain types, in a file with no SafeDI content.
		if !defaultMembers.isEmpty {
			var seen = Set<String>()
			let members = defaultMembers.filter { seen.insert($0.declaration).inserted }
			register(defaultsName, .public)
			plainDeclarations.insert({ rendering in
				"\(rendering.modifier(.public))enum \(defaultsName) {\n" + members.map { "\t\(rendering.modifier($0.access))\($0.declaration)" }.joined(separator: "\n") + "\n}"
			}, at: 0)
		}
		var plainFiles = plainDeclarations.isEmpty ? [] : [File(module: .seamModule, fileName: "\(prefix)Plain.swift", declarations: plainDeclarations)]
		// A differing mock condition, `nil` on one side and the default on the other: the declaring module's own, in its
		// `SafeDIConfiguration.swift` half the time, else beside its plain types, or a consumer module's.
		var configurationFiles = [File]()
		if random.percentChance(10) {
			let configuration: (Rendering) -> String = { _ in "#SafeDIConfiguration(mockConditionalCompilation: nil)" }
			if random.percentChance(50) {
				if random.percentChance(50) {
					configurationFiles.append(File(module: .seamModule, fileName: "\(prefix)Configuration/SafeDIConfiguration.swift", declarations: [configuration]))
				} else if plainFiles.isEmpty {
					plainFiles = [File(module: .seamModule, fileName: "\(prefix)Plain.swift", declarations: [configuration])]
				} else {
					plainFiles[0].declarations.append(configuration)
				}
			} else {
				configurationFiles.append(File(module: random.element(of: consumerModules), fileName: "\(prefix)Configuration/SafeDIConfiguration.swift", declarations: [configuration]))
			}
		}
		files = plainFiles + helperFiles + declaringFiles
			+ configurationFiles.filter { $0.module == .seamModule }
			+ consumerFiles
			+ configurationFiles.filter { $0.module != .seamModule }

		// On a stream of its own, a chain of public mocks beneath the declaring module, as
		// `GraphFuzzerSeamDependencyDraw.chainPercent` describes: a leaf a consumer instantiates, and so calls the public
		// mock of, and that no consumer or mock builds itself, instantiates `ChainLink`, which instantiates `ChainBase`,
		// each with an `internal` initializer, so that the leaf's mock calls `ChainLink`'s, which calls `ChainBase`'s, which
		// builds `ChainLeaf`, and a consumer computes each plan level by level through the declaring module's view.
		if seamDependencyRandom.percentChance(GraphFuzzerSeamDependencyDraw.chainPercent) {
			let rendering = Rendering(prefix: prefix, storesEveryParameter: false, isKnownRight: false)
			let units = files.map { file in
				GraphFuzzerSeamDependencyDraw.Unit(module: file.module, source: file.declarations.map { $0(rendering) }.joined(separator: "\n\n"), mayMove: false)
			}
			let analysis = GraphFuzzerSeamDependencyDraw.Analysis(units: units, typeNamePrefix: prefix)
			// A consumer that can call a leaf's initializer – one in the declaring module's package, of a `package` or `public`
			// initializer, or any consumer of a `public` one – may build the leaf's tree itself, which it could not under the
			// module-info flow, where it reads no type of the modules beneath the declaring module.
			let eligibleLeafIndices = leaves.indices.filter { leafIndex in
				let leaf = leaves[leafIndex].declaration
				let initializerAccess = min(leaf.initializerAccess ?? leaf.access, leaf.narrowestNamedAccess, leaf.access)
				let consumingModules = Set(units.indices.filter { units[$0].module.isCaller && analysis.referencedNames[$0].contains(leaf.name) }.map { units[$0].module })
				return !analysis.inlineNames.contains(leaf.name)
					&& !analysis.namesMocksReach.contains(leaf.name)
					&& !consumingModules.isEmpty
					&& (initializerAccess == .internal || initializerAccess == .package && !consumingModules.contains(.samePackageCaller))
			}
			if !eligibleLeafIndices.isEmpty {
				let leafIndex = seamDependencyRandom.element(of: eligibleLeafIndices)
				let tokenName = name(GraphFuzzerSeamDependencyDraw.chainTokenSuffix)
				let chainLeafName = name(GraphFuzzerSeamDependencyDraw.chainLeafSuffix)
				let baseName = name(GraphFuzzerSeamDependencyDraw.chainBaseSuffix)
				let linkName = name(GraphFuzzerSeamDependencyDraw.chainLinkSuffix)
				var chainLeaf = InstantiableClass(name: chainLeafName, conformances: conformances)
				chainLeaf.properties = [received("chainToken", tokenName, onlyIfAvailable: true)]
				var base = InstantiableClass(name: baseName, initializerAccess: .internal, conformances: conformances)
				base.mockGeneration = ".public"
				base.properties = [Property(attribute: "@Instantiated", label: "chainLeaf", type: chainLeafName)]
				var link = InstantiableClass(name: linkName, initializerAccess: .internal, conformances: conformances)
				link.mockGeneration = ".public"
				link.properties = [Property(attribute: "@Instantiated", label: "chainBase", type: baseName)]
				var leafDeclaration = leaves[leafIndex].declaration
				leafDeclaration.add(Property(attribute: "@Instantiated", label: "chainLink", type: linkName))
				if let fileIndex = analysis.declaringUnitIndices[leafDeclaration.name]?.first {
					files[fileIndex].declarations = [Self.renderer(of: leafDeclaration)]
					files.insert(contentsOf: [
						File(module: .seamDependency, declarations: [Self.renderer(of: link)]),
						File(module: .seamDependencyBase, declarations: [Self.renderer(of: base)]),
						File(module: .seamDependencyLeaf, declarations: [Self.renderer(of: chainLeaf), plainClass(tokenName, access: .public)]),
					], at: fileIndex + 1)
				}
			}
		}
	}

	// MARK: Gating draws

	/// The modules of the graph that call the declaring module, in dependency order.
	private var consumerModules: [GraphFuzzerModule] {
		GraphFuzzerModule.allCases.filter { module in module.isCaller && files.contains { $0.module == module } }
	}

	/// Whether a module of the graph sets `mockConditionalCompilation: nil`, under which a consumer's mock cannot call a
	/// public mock generated under another condition: the gating draws stay out of such a graph, so that they reject no
	/// graph the rest of the draw has the tool accept.
	private var hasDifferingMockCondition: Bool {
		let rendering = Rendering(prefix: prefix, storesEveryParameter: false, isKnownRight: false)
		return files.contains { file in file.declarations.contains { $0(rendering).contains("mockConditionalCompilation: nil") } }
	}

	/// A protocol of the graph's, `Sendable` in a graph whose types all are, so that a type built inside a `@Sendable`
	/// builder can hold one.
	private func protocolDeclaration(_ protocolName: String) -> (Rendering) -> String {
		let isSendableGraph = isSendableGraph
		return { rendering in "\(rendering.modifier(.public))protocol \(protocolName)\(isSendableGraph ? ": Sendable" : "") {}" }
	}

	/// The shape #702 fixed, in two graphs in five: `SelfNode`, a `.public` type of the declaring module with a place of `SelfApi`,
	/// which no declaration of its module fulfills, builds itself again – through `Instantiator<SelfNode>`, through
	/// `SelfStep`, a type it builds that instantiates it, or, in a graph whose types are all `Sendable`, through a
	/// `SendableInstantiator` – so that its public mock's case on the way back to it holds its own enum. Its place is on it,
	/// or beneath it on `SelfPart`; now and then it binds `selfToken` before the place, which the fill reads. `SelfScreen`,
	/// a mocked consumer in one consumer module, builds it, and `SelfLive` beside it fills the place, or, one draw in five,
	/// nothing does and its mock takes the builder. On a stream of its own, half the time a type of `SelfNode`'s tree
	/// receives the builder rather than instantiating it – `SelfStep` on its route, else `SelfPart` where it holds the place
	/// and otherwise `SelfLink`, a type `SelfNode` builds that holds none – which `SelfNode`'s mock promotes to its root,
	/// and a hand-written caller in the consumer module calls `SelfNode`'s public mock with a builder for each family of
	/// the place's function, as `T6`'s caller does. Every roll is made before any is read.
	private mutating func drawSelfBuildingPublicMock(random: inout GraphFuzzerRandomNumberGenerator, receivesBuilderRandom: inout GraphFuzzerRandomNumberGenerator) {
		let drawsShape = random.percentChance(40)
		let routeRoll = random.integer(in: 0...99)
		let placeBeneath = random.percentChance(30)
		let bindsToken = random.percentChance(40)
		let fillReadsToken = random.percentChance(60)
		let passesUp = random.percentChance(20)
		let initializerRoll = random.integer(in: 0...7)
		let consumerModuleRoll = random.integer(in: 0...1)
		let receivesBuilder = receivesBuilderRandom.percentChance(50)
		let consumerModules = consumerModules
		guard drawsShape, !consumerModules.isEmpty, !hasDifferingMockCondition else { return }
		let consumerModule = consumerModules[consumerModuleRoll % consumerModules.count]
		let conformances = isSendableGraph ? ["@unchecked Sendable"] : []
		let apiName = name("SelfApi")
		let nodeName = name("SelfNode")
		let tokenName = name("SelfToken")
		var declaringModuleDeclarations = [protocolDeclaration(apiName)]
		var node = InstantiableClass(name: nodeName, conformances: conformances)
		node.mockGeneration = ".public"
		node.initializerAccess = initializerRoll < 4 ? .package : initializerRoll == 4 ? .internal : .public
		if bindsToken {
			node.properties.append(Property(attribute: "@Instantiated", label: "selfToken", type: tokenName))
			declaringModuleDeclarations.append(Self.renderer(of: InstantiableClass(name: tokenName, conformances: conformances)))
		}
		let routesThroughStep = (55..<80).contains(routeRoll)
		let builderType = routeRoll >= 80 && isSendableGraph ? "SendableInstantiator<\(nodeName)>" : "Instantiator<\(nodeName)>"
		// The builder of `SelfNode`, instantiated by `SelfNode` or `SelfStep`, or received by the type that holds it.
		let builder = Property(attribute: receivesBuilder ? "@Received" : "@Instantiated", label: "selfNodeBuilder", type: builderType)
		let place = Property(attribute: "@Instantiated", label: "selfApi", type: "any \(apiName)")
		if placeBeneath {
			var part = InstantiableClass(name: name("SelfPart"), conformances: conformances)
			part.properties = [place]
			if receivesBuilder, !routesThroughStep {
				part.properties.append(builder)
			}
			node.properties.append(Property(attribute: "@Instantiated", label: "selfPart", type: part.name))
			declaringModuleDeclarations.append(Self.renderer(of: part))
		} else {
			node.properties.append(place)
		}
		if routesThroughStep {
			var step = InstantiableClass(name: name("SelfStep"), conformances: conformances)
			step.properties = [builder]
			node.properties.append(Property(attribute: "@Instantiated", label: "selfStep", type: step.name))
			declaringModuleDeclarations.append(Self.renderer(of: step))
		} else if !receivesBuilder {
			node.properties.append(builder)
		} else if !placeBeneath {
			var link = InstantiableClass(name: name("SelfLink"), conformances: conformances)
			link.properties = [builder]
			node.properties.append(Property(attribute: "@Instantiated", label: "selfLink", type: link.name))
			declaringModuleDeclarations.append(Self.renderer(of: link))
		}
		declaringModuleDeclarations.insert(Self.renderer(of: node), at: 1)
		if receivesBuilder {
			// The hand-written caller, in the consumer module, with a builder that ignores its scope for the place's plain
			// family and, where `SelfNode` is built again inside a `@Sendable` function, its `@Sendable` one; the builder's
			// value is `SelfStub`, a plain class of the declaring module that conforms to `SelfApi`.
			let stubName = name("SelfStub")
			declaringModuleDeclarations.append { rendering in
				"\(rendering.modifier(.public))final class \(stubName): \(([apiName] + conformances).joined(separator: ", ")) {\n\t\(rendering.modifier(.public))init() {}\n}"
			}
			let builderLabel = Self.builderLabel(ofTypeNamed: apiName)
			var builders = ["\(builderLabel): { _ in \(stubName)() }"]
			if builderType.hasPrefix("Sendable") {
				builders.append("\(builderLabel.dropLast("Builder".count))SendableBuilder: { _ in \(stubName)() }")
			}
			let call = "\(nodeName).mock(\(builders.joined(separator: ", ")))"
			declaringModuleDeclarations.append { _ in "\(Self.publicMockCallerMarker)\(consumerModule.name): \(call)" }
		}
		var screen = InstantiableClass(name: name("SelfScreen"), conformances: conformances)
		screen.mockGeneration = "true"
		screen.properties = [Property(attribute: "@Instantiated", label: "selfNode", type: nodeName)]
		var consumerDeclarations = [Self.renderer(of: screen)]
		if !passesUp {
			var live = InstantiableClass(name: name("SelfLive"), conformances: [apiName] + conformances)
			live.arguments = ["fulfillingAdditionalTypes: [\(apiName).self]"]
			if bindsToken, fillReadsToken {
				live.properties = [Property(attribute: "@Received", label: "selfToken", type: tokenName)]
			}
			consumerDeclarations.append(Self.renderer(of: live))
		}
		files.append(File(module: .seamModule, declarations: declaringModuleDeclarations))
		files.append(File(module: consumerModule, declarations: consumerDeclarations))
	}

	/// A place inside a public mock's fill, in two graphs in five: `PlaceInFillInner`, a `.public` type of the module
	/// beneath the declaring module (`FuzzSession`), whose initializer is `internal` seven times in ten and otherwise
	/// `package`, holds a place of `PlaceInFillService`; `PlaceInFillOuter`, a `.public` type of the declaring module
	/// with an `internal` initializer, builds it, so that its public mock calls `PlaceInFillInner`'s, or builds its
	/// tree inline, and fills the place with `PlaceInFillDefault`, whose place of `PlaceInFillGadget` the declaring
	/// module cannot fill: the place inside the fill. `PlaceInFillApp`, a mocked consumer, builds `PlaceInFillOuter`,
	/// and `PlaceInFillLive` beside it fills that place, or, one draw in four, nothing does and its mock takes the
	/// builder. Now and then `PlaceInFillInner` also builds `PlaceInFillInnerScreen` through an instantiator that
	/// forwards `placeInFillId`, with a place of its own, which the fill reads only if available, and
	/// `PlaceInFillOuter` binds `placeInFillTag` before `PlaceInFillInner`, which the fill reads. Seven draws in twenty,
	/// `PlaceInFillDefault` also instantiates the builders of `PlaceInFillLoopA` and `PlaceInFillLoopB`, which receive each
	/// other's and each hold a place of `PlaceInFillGadget`: a loop of builders inside the fill. Every roll is made before
	/// any is read.
	private mutating func drawPlaceInsidePublicMockFill(random: inout GraphFuzzerRandomNumberGenerator) {
		let drawsShape = random.percentChance(40)
		let drawsScreen = random.percentChance(40)
		let bindsTag = random.percentChance(50)
		let fillReadsTag = random.percentChance(60)
		let fillReadsIdentifier = random.percentChance(60)
		let fillsInConsumer = random.percentChance(75)
		let innerInitializerRoll = random.integer(in: 0...9)
		let consumerModuleRoll = random.integer(in: 0...1)
		let fillHoldsLoop = random.percentChance(35)
		let consumerModules = consumerModules
		guard drawsShape, !consumerModules.isEmpty, !hasDifferingMockCondition else { return }
		let consumerModule = consumerModules[consumerModuleRoll % consumerModules.count]
		let conformances = isSendableGraph ? ["@unchecked Sendable"] : []
		let serviceName = name("PlaceInFillService")
		let gadgetName = name("PlaceInFillGadget")
		let tagName = name("PlaceInFillTag")
		let place = Property(attribute: "@Instantiated", label: "placeInFillService", type: "any \(serviceName)")
		var inner = InstantiableClass(name: name("PlaceInFillInner"), conformances: conformances)
		inner.mockGeneration = ".public"
		inner.initializerAccess = innerInitializerRoll < 7 ? .internal : .package
		inner.properties = [place]
		var innerDeclarations = [protocolDeclaration(serviceName)]
		if drawsScreen {
			var screen = InstantiableClass(name: name("PlaceInFillInnerScreen"), conformances: conformances)
			screen.properties = [Property(attribute: "@Forwarded", label: "placeInFillId", type: "Int"), place]
			inner.properties.append(Property(attribute: "@Instantiated", label: "placeInFillInnerScreenBuilder", type: "Instantiator<\(screen.name)>"))
			innerDeclarations.append(Self.renderer(of: screen))
		}
		innerDeclarations.insert(Self.renderer(of: inner), at: 1)
		var fill = InstantiableClass(name: name("PlaceInFillDefault"), conformances: [serviceName] + conformances)
		fill.arguments = ["fulfillingAdditionalTypes: [\(serviceName).self]"]
		fill.properties = [Property(attribute: "@Instantiated", label: "placeInFillGadget", type: "any \(gadgetName)")]
		var outer = InstantiableClass(name: name("PlaceInFillOuter"), conformances: conformances)
		outer.mockGeneration = ".public"
		outer.initializerAccess = .internal
		var declaringModuleDeclarations = [protocolDeclaration(gadgetName)]
		if bindsTag {
			outer.properties.append(Property(attribute: "@Instantiated", label: "placeInFillTag", type: tagName))
			declaringModuleDeclarations.append(Self.renderer(of: InstantiableClass(name: tagName, conformances: conformances)))
		}
		outer.properties.append(Property(attribute: "@Instantiated", label: "placeInFillInner", type: inner.name))
		declaringModuleDeclarations.insert(Self.renderer(of: outer), at: 1)
		if fillHoldsLoop {
			var loopA = InstantiableClass(name: name("PlaceInFillLoopA"), conformances: conformances)
			var loopB = InstantiableClass(name: name("PlaceInFillLoopB"), conformances: conformances)
			let loopABuilder = Property(attribute: "@Instantiated", label: "placeInFillLoopABuilder", type: "Instantiator<\(loopA.name)>")
			let loopBBuilder = Property(attribute: "@Instantiated", label: "placeInFillLoopBBuilder", type: "Instantiator<\(loopB.name)>")
			fill.properties += [loopABuilder, loopBBuilder]
			loopA.properties = [fill.properties[0], Property(attribute: "@Received", label: loopBBuilder.label, type: loopBBuilder.type)]
			loopB.properties = [fill.properties[0], Property(attribute: "@Received", label: loopABuilder.label, type: loopABuilder.type)]
			declaringModuleDeclarations += [Self.renderer(of: loopA), Self.renderer(of: loopB)]
		}
		declaringModuleDeclarations.append(Self.renderer(of: fill))
		var app = InstantiableClass(name: name("PlaceInFillApp"), conformances: conformances)
		app.mockGeneration = "true"
		app.properties = [Property(attribute: "@Instantiated", label: "placeInFillOuter", type: outer.name)]
		var consumerDeclarations = [Self.renderer(of: app)]
		if fillsInConsumer {
			var live = InstantiableClass(name: name("PlaceInFillLive"), conformances: [gadgetName] + conformances)
			live.arguments = ["fulfillingAdditionalTypes: [\(gadgetName).self]"]
			if bindsTag, fillReadsTag {
				live.properties.append(Property(attribute: "@Received", label: "placeInFillTag", type: tagName))
			}
			if drawsScreen, fillReadsIdentifier {
				live.properties.append(Property(attribute: "@Received(onlyIfAvailable: true)", label: "placeInFillId", type: "Int?"))
			}
			consumerDeclarations.append(Self.renderer(of: live))
		}
		files.append(File(module: .seamDependency, declarations: innerDeclarations))
		files.append(File(module: .seamModule, declarations: declaringModuleDeclarations))
		files.append(File(module: consumerModule, declarations: consumerDeclarations))
	}

	/// Labels the generated configurations declare as members, spelled as keywords, in three graphs in ten:
	/// `KeywordHome`, a `.public` type of the declaring module, builds `KeywordKind` under `Type` and `KeywordHolder` under
	/// `Protocol`, and `KeywordHolder` builds `KeywordKind` under `Self` and `init` and takes a default-valued `default`.
	/// `KeywordApp`, a mocked consumer in one consumer module, builds `KeywordHome` under `Type`, so that its mock calls
	/// `KeywordHome`'s public mock, and, two draws in five, `KeywordLocal`, a type of its own module that builds
	/// `KeywordKind` under `Protocol`. So `KeywordApp`'s overrides, `KeywordHome`'s public overrides, `KeywordHolder`'s
	/// module-level configuration and `KeywordLocal`'s internal configuration each declare a keyword member, which Swift
	/// rejects written bare for `Type` and `Protocol`. Never `self`, which the fixture's initializer would take as the name of
	/// a parameter that hides the instance it assigns to. Every roll is made before any is read.
	private mutating func drawKeywordLabeledPublicMock(random: inout GraphFuzzerRandomNumberGenerator) {
		let drawsShape = random.percentChance(30)
		let buildsLocal = random.percentChance(40)
		let consumerModuleRoll = random.integer(in: 0...1)
		let consumerModules = consumerModules
		guard drawsShape, !consumerModules.isEmpty, !hasDifferingMockCondition else { return }
		let consumerModule = consumerModules[consumerModuleRoll % consumerModules.count]
		let conformances = isSendableGraph ? ["@unchecked Sendable"] : []
		let kind = InstantiableClass(name: name("KeywordKind"), conformances: conformances)
		var holder = InstantiableClass(name: name("KeywordHolder"), conformances: conformances)
		holder.properties = [
			Property(attribute: "@Instantiated", label: "`Self`", type: kind.name),
			Property(attribute: "@Instantiated", label: "`init`", type: kind.name),
		]
		holder.defaults = [DefaultParameter(name: "`default`", type: "Int", defaultValue: "1")]
		var home = InstantiableClass(name: name("KeywordHome"), conformances: conformances)
		home.mockGeneration = ".public"
		// An `internal` initializer, which no consumer module can call, so that a consumer's mock calls the public mock.
		home.initializerAccess = .internal
		home.properties = [
			Property(attribute: "@Instantiated", label: "`Type`", type: kind.name),
			Property(attribute: "@Instantiated", label: "`Protocol`", type: holder.name),
		]
		var app = InstantiableClass(name: name("KeywordApp"), conformances: conformances)
		app.mockGeneration = "true"
		app.properties = [Property(attribute: "@Instantiated", label: "`Type`", type: home.name)]
		var consumerDeclarations = [Self.renderer(of: app)]
		if buildsLocal {
			var local = InstantiableClass(name: name("KeywordLocal"), conformances: conformances)
			local.properties = [Property(attribute: "@Instantiated", label: "`Protocol`", type: kind.name)]
			app.properties.append(Property(attribute: "@Instantiated", label: "keywordLocal", type: local.name))
			consumerDeclarations = [Self.renderer(of: app), Self.renderer(of: local)]
		}
		files.append(File(module: .seamModule, declarations: [Self.renderer(of: home), Self.renderer(of: holder), Self.renderer(of: kind)]))
		files.append(File(module: consumerModule, declarations: consumerDeclarations))
	}

	/// The retention oracle's shape, in three graphs in twenty: `RetainHome`, a `.public` type of the declaring module
	/// with an `internal` initializer, binds `retainNavigator` and then builds `RetainDetail` through an
	/// `Instantiator`, beneath which `RetainLeaf`, built by value or through an `Instantiator`, holds a place of
	/// `RetainApi`, which no declaration of the declaring module fulfills. `RetainApp`, a mocked consumer in one
	/// consumer module, builds `RetainHome`, so that its mock calls `RetainHome`'s public mock, and `RetainLive` beside
	/// it fills the place, 35 times in 100 reading `retainNavigator`. Nothing else beneath `RetainDetail` reads
	/// `retainNavigator`, so once `RetainApp`'s mock is released, the known-right path, which builds the tree inline,
	/// keeps none alive, whatever holds `RetainDetail`'s builder; a calling mock's fill that captures the levels of its
	/// places keeps it alive. Every roll is made before any is read.
	private mutating func drawRetentionPublicMock(random: inout GraphFuzzerRandomNumberGenerator) {
		let drawsShape = random.percentChance(15)
		let leafThroughInstantiator = random.percentChance(50)
		let fillReadsNavigator = random.percentChance(35)
		let consumerModuleRoll = random.integer(in: 0...1)
		let consumerModules = consumerModules
		guard drawsShape, !consumerModules.isEmpty, !hasDifferingMockCondition else { return }
		let consumerModule = consumerModules[consumerModuleRoll % consumerModules.count]
		let conformances = isSendableGraph ? ["@unchecked Sendable"] : []
		let apiName = name("RetainApi")
		let navigator = InstantiableClass(name: name("RetainNavigator"), conformances: conformances)
		var leaf = InstantiableClass(name: name("RetainLeaf"), conformances: conformances)
		leaf.properties = [Property(attribute: "@Instantiated", label: "retainApi", type: "any \(apiName)")]
		var detail = InstantiableClass(name: name("RetainDetail"), conformances: conformances)
		detail.properties = [
			leafThroughInstantiator
				? Property(attribute: "@Instantiated", label: "retainLeafBuilder", type: "Instantiator<\(leaf.name)>")
				: Property(attribute: "@Instantiated", label: "retainLeaf", type: leaf.name),
		]
		var home = InstantiableClass(name: name("RetainHome"), conformances: conformances)
		home.mockGeneration = ".public"
		// An `internal` initializer, which no consumer module can call, so that a consumer's mock calls the public mock.
		home.initializerAccess = .internal
		home.properties = [
			Property(attribute: "@Instantiated", label: "retainNavigator", type: navigator.name),
			Property(attribute: "@Instantiated", label: "retainDetailBuilder", type: "Instantiator<\(detail.name)>"),
		]
		var app = InstantiableClass(name: name("RetainApp"), conformances: conformances)
		app.mockGeneration = "true"
		app.properties = [Property(attribute: "@Instantiated", label: "retainHome", type: home.name)]
		var live = InstantiableClass(name: name("RetainLive"), conformances: [apiName] + conformances)
		live.arguments = ["fulfillingAdditionalTypes: [\(apiName).self]"]
		if fillReadsNavigator {
			live.properties = [Property(attribute: "@Received", label: "retainNavigator", type: navigator.name)]
		}
		files.append(File(module: .seamModule, declarations: [protocolDeclaration(apiName), Self.renderer(of: home), Self.renderer(of: navigator), Self.renderer(of: detail), Self.renderer(of: leaf)]))
		files.append(File(module: consumerModule, declarations: [Self.renderer(of: app), Self.renderer(of: live)]))
	}

	/// A type a module's public mocks build two ways, in three graphs in ten: `ShareService`, which fulfills `ShareApi`, is
	/// declared by a class whose `mockOnly` extension's `mock()` returns `ShareApi`, or, two times in five, by an extension
	/// whose `customMockName` method does; the hand-written mock takes the parameters of the initializer or of
	/// `instantiate(…)`: a `String` default, and half the time an optional one, which a provider evaluates. The public mocks
	/// of `ShareHolderA` and `ShareHolderB` hold it as `ShareApi`, built with the hand-written mock, and as itself or, two
	/// times in five, erased to `AnyShareApi`, built without it. Which holder holds which is rolled, so that either sorts
	/// first, and one draw in four `ShareHolderA` holds both. The holders are in a consumer module, or one draw in four in
	/// the declaring module; in a consumer module, two times in five `ShareRoot`, a `.public` type of the declaring module,
	/// holds `ShareApi` too, so that the declaring module declares an internal `__safeDI_mock` of its own. Two times in five
	/// a class's draw instead builds the hand-written mock only beneath a cycle edge: `ShareService` instantiates
	/// `Instantiator<ShareTicker>`, `ShareTicker` holds `ShareApi`, the `mockOnly` `mock()`, which returns `ShareStub`, takes
	/// one more optional default than the initializer, `shareMood`, and `ShareHolderA` alone holds `ShareService`, as
	/// itself or erased, so that the mock is built only where it reads no overrides. Every roll is made before any is read.
	private mutating func drawSharedConstructionPublicMock(random: inout GraphFuzzerRandomNumberGenerator) {
		let drawsShape = random.percentChance(30)
		let isExtensionBased = random.percentChance(40)
		let hasOptionalDefault = random.percentChance(50)
		let isErased = random.percentChance(40)
		let hasOneHolder = random.percentChance(25)
		let withoutMockFirst = random.percentChance(50)
		let inDeclaringModule = random.percentChance(25)
		let besideDeclaringModulesOwn = random.percentChance(40)
		let consumerModuleRoll = random.integer(in: 0...1)
		let cycleEdgeRoll = random.percentChance(40)
		let consumerModules = consumerModules
		guard drawsShape, !hasDifferingMockCondition else { return }
		let isBeneathCycleEdge = cycleEdgeRoll && !isExtensionBased
		let holderModule = inDeclaringModule || consumerModules.isEmpty ? GraphFuzzerModule.seamModule : consumerModules[consumerModuleRoll % consumerModules.count]
		let conformances = isSendableGraph ? ["@unchecked Sendable"] : []
		let apiName = name("ShareApi")
		let serviceName = name("ShareService")
		let erasedName = name("AnyShareApi")
		var defaults = [DefaultParameter(name: "shareName", type: "String", defaultValue: "\"share\"")]
		if hasOptionalDefault {
			defaults.append(DefaultParameter(name: "shareTone", type: "String?", defaultValue: "\"loud\""))
		}
		let parameters = defaults.map { "\($0.name): \($0.type) = \($0.defaultValue)" }.joined(separator: ", ")
		var declaringModuleDeclarations = [protocolDeclaration(apiName)]
		if isExtensionBased {
			let inheritance = ([apiName] + conformances).joined(separator: ", ")
			declaringModuleDeclarations.append { rendering in
				"\(rendering.modifier(.public))final class \(serviceName): \(inheritance) {\n\t\(rendering.modifier(.public))init() {}\n}"
			}
			declaringModuleDeclarations.append { rendering in
				[
					"@Instantiable(fulfillingAdditionalTypes: [\(apiName).self], generateMock: true, customMockName: \"customMock\")",
					"extension \(serviceName): Instantiable {",
					"\t\(rendering.modifier(.public))static func instantiate(\(parameters)) -> \(serviceName) {",
					"\t\t\(serviceName)()",
					"\t}",
					"",
					"\t\(rendering.modifier(.public))static func customMock(\(parameters)) -> \(apiName) {",
					"\t\t\(serviceName)()",
					"\t}",
					"}",
				].joined(separator: "\n")
			}
		} else if isBeneathCycleEdge {
			let tickerName = name("ShareTicker")
			let stubName = name("ShareStub")
			var service = InstantiableClass(name: serviceName, conformances: [apiName] + conformances)
			service.arguments = ["fulfillingAdditionalTypes: [\(apiName).self]"]
			service.properties = [Property(attribute: "@Instantiated", label: "shareTickerBuilder", type: "Instantiator<\(tickerName)>")]
			service.defaults = defaults
			var ticker = InstantiableClass(name: tickerName, conformances: conformances)
			ticker.properties = [Property(attribute: "@Instantiated", label: "shareApi", type: apiName)]
			let mockParameters = parameters + ", shareMood: String? = \"calm\""
			declaringModuleDeclarations.append(Self.renderer(of: service))
			declaringModuleDeclarations.append(Self.renderer(of: ticker))
			declaringModuleDeclarations.append { rendering in
				"\(rendering.modifier(.public))struct \(stubName): \(apiName) {}"
			}
			declaringModuleDeclarations.append { rendering in
				"@Instantiable(fulfillingAdditionalTypes: [\(apiName).self], mockOnly: true)\nextension \(serviceName) {\n\t\(rendering.modifier(.public))static func mock(\(mockParameters)) -> \(apiName) {\n\t\t\(stubName)()\n\t}\n}"
			}
		} else {
			var service = InstantiableClass(name: serviceName, conformances: [apiName] + conformances)
			service.arguments = ["fulfillingAdditionalTypes: [\(apiName).self]"]
			service.defaults = defaults
			let arguments = defaults.map { "\($0.name): \($0.name)" }.joined(separator: ", ")
			declaringModuleDeclarations.append(Self.renderer(of: service))
			declaringModuleDeclarations.append { rendering in
				"@Instantiable(fulfillingAdditionalTypes: [\(apiName).self], mockOnly: true)\nextension \(serviceName) {\n\t\(rendering.modifier(.public))static func mock(\(parameters)) -> \(apiName) {\n\t\t\(serviceName)(\(arguments))\n\t}\n}"
			}
		}
		if isErased {
			declaringModuleDeclarations.append { rendering in
				[
					"\(rendering.modifier(.public))struct \(erasedName): \(apiName) {",
					"\t\(rendering.modifier(.public))init(_ value: any \(apiName)) {",
					"\t\tself.value = value",
					"\t}",
					"",
					"\t\(rendering.modifier(.public))let value: any \(apiName)",
					"}",
				].joined(separator: "\n")
			}
		}
		let mockProperty = Property(attribute: "@Instantiated", label: "shareApi", type: apiName)
		let withoutMockProperty = isErased
			? Property(attribute: "@Instantiated(fulfilledByType: \"\(serviceName)\", erasedToConcreteExistential: true)", label: "anyShareApi", type: erasedName)
			: Property(attribute: "@Instantiated", label: "shareService", type: serviceName)
		func holder(_ suffix: String, properties: [Property]) -> InstantiableClass {
			var holder = InstantiableClass(name: name(suffix), conformances: conformances)
			holder.mockGeneration = ".public"
			holder.properties = properties
			return holder
		}
		let orderedProperties = withoutMockFirst ? [withoutMockProperty, mockProperty] : [mockProperty, withoutMockProperty]
		let holders = if isBeneathCycleEdge {
			[holder("ShareHolderA", properties: [withoutMockProperty])]
		} else if hasOneHolder {
			[holder("ShareHolderA", properties: orderedProperties)]
		} else {
			[holder("ShareHolderA", properties: [orderedProperties[0]]), holder("ShareHolderB", properties: [orderedProperties[1]])]
		}
		if holderModule != .seamModule, besideDeclaringModulesOwn, !isBeneathCycleEdge {
			declaringModuleDeclarations.append(Self.renderer(of: holder("ShareRoot", properties: [mockProperty])))
		}
		files.append(File(module: .seamModule, declarations: declaringModuleDeclarations))
		files.append(File(module: holderModule, declarations: holders.map(Self.renderer(of:))))
	}

	/// A call of a public mock whose override member is a closure, in two graphs in five: `OverriddenDetail`, a `.public` type
	/// of the declaring module with an `internal` initializer, builds nothing but a place of `OverriddenPlace1Api` and, now and
	/// then, one of `OverriddenPlace1Store`, so that its mock takes no `SafeDIOverrides`; now and then it receives
	/// `overriddenSession`, which its module cannot build, plainly or renamed from `overriddenMainSession`. Three draws in ten
	/// hold the `OverriddenPlace1Api` place as an `ErasedInstantiator`, filled by `OverriddenPlace1Live` in place of
	/// `OverriddenLive`. `OverriddenScreen`, a mocked consumer in one consumer module, `true` or `.public`, builds it by value or through an
	/// `Instantiator`, and builds the sessions in an extension of its module's own. `OverriddenLive` beside it fills the
	/// `OverriddenPlace1Api` place, reading the session, the other place, both, or nothing, or, three draws in ten, nothing does and
	/// the consumer's mock takes the builder; a fill that reads a session `OverriddenDetail` does not receive reads the one the
	/// consumer builds, and the consumer fills the place as its production twin does (contract rule 7). `OverriddenStoreLive`
	/// fills the other place half the time. The consumer's overrides hold the closure that builds `OverriddenDetail` only where
	/// the call can hand it a builder a person writes for each place
	/// (`GraphFuzzerPublicMockDrawFeature.overrideClosureCannotHandShapes`). Every roll is made before any is read.
	private mutating func drawOverrideClosurePublicMockCall(random: inout GraphFuzzerRandomNumberGenerator) {
		let drawsShape = random.percentChance(40)
		let consumerIsPublic = random.percentChance(40)
		let throughInstantiator = random.percentChance(50)
		let buildsStore = random.percentChance(40)
		let sessionRoll = random.integer(in: 0...9)
		let fillsApi = random.percentChance(70)
		let fillReadsSession = random.percentChance(50)
		let fillReadsStore = random.percentChance(50)
		let fillsStore = random.percentChance(50)
		let consumerModuleRoll = random.integer(in: 0...1)
		let holdsApiAsErasedInstantiator = random.percentChance(30)
		let consumerModules = consumerModules
		guard drawsShape, !consumerModules.isEmpty, !hasDifferingMockCondition else { return }
		let consumerModule = consumerModules[consumerModuleRoll % consumerModules.count]
		let conformances = isSendableGraph ? ["@unchecked Sendable"] : []
		// The two places' types share what the renaming that moves type names across wrapper names reads of a name,
		// `OverriddenPlace1`, so it gives both one letter and keeps their builders' labels in one order: a mock sorts its
		// parameters by label, and a builder's label begins with its type's name, which may follow names (CLAUDE.md, "What may
		// follow names"), a known issue where other draws show it (`publicMockBuilderOrderReason`).
		let apiName = name("OverriddenPlace1Api")
		let storeName = name("OverriddenPlace1Store")
		let sessionName = name("OverriddenSession")
		// Three in ten receive no session, four plainly, three renamed from `overriddenMainSession`.
		let receivesSession = sessionRoll >= 3
		let renamesSession = sessionRoll >= 7
		var detail = InstantiableClass(name: name("OverriddenDetail"), conformances: conformances)
		detail.mockGeneration = ".public"
		// An `internal` initializer, which no consumer module can call, so that the consumer's mock calls the public mock.
		detail.initializerAccess = .internal
		if receivesSession {
			let attribute = renamesSession ? "@Received(fulfilledByDependencyNamed: \"overriddenMainSession\", ofType: \(sessionName).self)" : "@Received"
			detail.properties.append(Property(attribute: attribute, label: "overriddenSession", type: sessionName))
		}
		if buildsStore {
			detail.properties.append(Property(attribute: "@Instantiated", label: "overriddenStore", type: "any \(storeName)"))
		}
		// Three in ten hold the place as an erased instantiator that forwards nothing, whose builder the override closure is
		// handed as the called `mock()` takes it, `() -> any OverriddenPlace1Api`, as a plain place's. Its fill is
		// `OverriddenPlace1Live`, named by `fulfilledByType:` and so in the builder's label, sharing `OverriddenPlace1` with
		// the places' types for the reason above.
		let liveName = holdsApiAsErasedInstantiator ? name("OverriddenPlace1Live") : name("OverriddenLive")
		detail.properties.append(holdsApiAsErasedInstantiator
			? Property(attribute: "@Instantiated(fulfilledByType: \"\(liveName)\")", label: "overriddenApi", type: "ErasedInstantiator<(), any \(apiName)>")
			: Property(attribute: "@Instantiated", label: "overriddenApi", type: "any \(apiName)"))
		var declaringModuleDeclarations = [protocolDeclaration(apiName), Self.renderer(of: detail)]
		if buildsStore {
			declaringModuleDeclarations.append(protocolDeclaration(storeName))
		}
		let readsSession = fillsApi && fillReadsSession
		if receivesSession || readsSession {
			// The type conforms to `Instantiable` by hand, so its module cannot build it, and the consumer's module builds it.
			declaringModuleDeclarations.append { rendering in
				"\(rendering.modifier(.public))final class \(sessionName): Instantiable, Sendable {\n\t\(rendering.modifier(.public))init() {}\n}"
			}
		}
		var screen = InstantiableClass(name: name("OverriddenScreen"), conformances: conformances)
		screen.mockGeneration = consumerIsPublic ? ".public" : "true"
		if receivesSession || readsSession {
			screen.properties.append(Property(attribute: "@Instantiated", label: "overriddenSession", type: sessionName))
		}
		if renamesSession {
			screen.properties.append(Property(attribute: "@Instantiated", label: "overriddenMainSession", type: sessionName))
		}
		screen.properties.append(throughInstantiator
			? Property(attribute: "@Instantiated", label: "overriddenDetailBuilder", type: "Instantiator<\(detail.name)>")
			: Property(attribute: "@Instantiated", label: "overriddenDetail", type: detail.name))
		var consumerDeclarations = [Self.renderer(of: screen)]
		if fillsApi {
			var live = InstantiableClass(name: liveName, conformances: [apiName] + conformances)
			live.arguments = ["fulfillingAdditionalTypes: [\(apiName).self]"]
			if readsSession {
				live.properties.append(Property(attribute: "@Received", label: "overriddenSession", type: sessionName))
			}
			if buildsStore, fillReadsStore {
				live.properties.append(Property(attribute: "@Received", label: "overriddenStore", type: "any \(storeName)"))
			}
			consumerDeclarations.append(Self.renderer(of: live))
		}
		if buildsStore, fillsStore {
			var storeLive = InstantiableClass(name: name("OverriddenStoreLive"), conformances: [storeName] + conformances)
			storeLive.arguments = ["fulfillingAdditionalTypes: [\(storeName).self]"]
			consumerDeclarations.append(Self.renderer(of: storeLive))
		}
		if receivesSession || readsSession {
			consumerDeclarations.append { rendering in
				"@Instantiable(conformsElsewhere: true)\nextension \(sessionName) {\n\t\(rendering.modifier(.public))static func instantiate() -> \(sessionName) {\n\t\t\(sessionName)()\n\t}\n}"
			}
		}
		files.append(File(module: .seamModule, declarations: declaringModuleDeclarations))
		files.append(File(module: consumerModule, declarations: consumerDeclarations))
	}

	/// A place beneath a received dependency a public mock promotes to its root lazily (adopter M2), in one graph in ten:
	/// `PromoteNode`, a `.public` type of the declaring module, builds `PromoteLeaf`, which receives `PromoteOther` through a
	/// `LazilyInstantiated`, or, in a graph whose types are all `Sendable`, now and then a `SendableLazilyInstantiated`,
	/// which nothing in `PromoteNode`'s tree provides, so `PromoteNode`'s mock builds it at its root; `PromoteOther` holds a
	/// place of `PromoteApi`, which no declaration of its module fulfills. The hole draw's `HoleReceiver` and the
	/// self-building draw's received builder draw a promoted dependency by value and through an instantiator, so this draw
	/// keeps only the lazy forms, which neither reaches; its rolls are those of the draw that also drew the other forms, so
	/// each seed draws the lazy form it drew before. `PromoteOther`'s initializer is `internal` half the time, so no consumer
	/// can build it and the mock's own tree builds it with the place, and otherwise `package` or `public`. `PromoteScreen`, a
	/// mocked consumer in one consumer module, `true` or, one draw in three, `.public`, builds `PromoteNode`, and
	/// `PromoteLive` beside it fills the place, or, one draw in five, nothing does and its mock takes the builder. Every roll
	/// is made before any is read.
	private mutating func drawPromotedHolePublicMock(random: inout GraphFuzzerRandomNumberGenerator) {
		let drawsShape = random.percentChance(40)
		let routeRoll = random.integer(in: 0...99)
		let nodeInitializerRoll = random.integer(in: 0...7)
		let otherInitializerRoll = random.integer(in: 0...3)
		let consumerIsPublic = random.percentChance(33)
		let passesUp = random.percentChance(20)
		let consumerModuleRoll = random.integer(in: 0...1)
		let consumerModules = consumerModules
		guard drawsShape, routeRoll >= 75, !consumerModules.isEmpty, !hasDifferingMockCondition else { return }
		let consumerModule = consumerModules[consumerModuleRoll % consumerModules.count]
		let conformances = isSendableGraph ? ["@unchecked Sendable"] : []
		let apiName = name("PromoteApi")
		let nodeName = name("PromoteNode")
		let otherName = name("PromoteOther")
		var node = InstantiableClass(name: nodeName, conformances: conformances)
		node.mockGeneration = ".public"
		node.initializerAccess = nodeInitializerRoll < 4 ? .package : nodeInitializerRoll == 4 ? .internal : .public
		node.properties = [Property(attribute: "@Instantiated", label: "promoteLeaf", type: name("PromoteLeaf"))]
		var leaf = InstantiableClass(name: name("PromoteLeaf"), conformances: conformances)
		let otherForm = routeRoll >= 90 && isSendableGraph ? "SendableLazilyInstantiated<\(otherName)>" : "LazilyInstantiated<\(otherName)>"
		leaf.properties = [Property(attribute: "@Received", label: "promoteOther", type: otherForm)]
		var other = InstantiableClass(name: otherName, conformances: conformances)
		other.initializerAccess = otherInitializerRoll < 2 ? .internal : otherInitializerRoll == 2 ? .package : .public
		other.properties = [Property(attribute: "@Instantiated", label: "promoteApi", type: "any \(apiName)")]
		let declaringModuleDeclarations = [protocolDeclaration(apiName), Self.renderer(of: node), Self.renderer(of: leaf), Self.renderer(of: other)]
		var screen = InstantiableClass(name: name("PromoteScreen"), conformances: conformances)
		screen.mockGeneration = consumerIsPublic ? ".public" : "true"
		screen.properties = [Property(attribute: "@Instantiated", label: "promoteNode", type: nodeName)]
		var consumerDeclarations = [Self.renderer(of: screen)]
		if !passesUp {
			var live = InstantiableClass(name: name("PromoteLive"), conformances: [apiName] + conformances)
			live.arguments = ["fulfillingAdditionalTypes: [\(apiName).self]"]
			consumerDeclarations.append(Self.renderer(of: live))
		}
		files.append(File(module: .seamModule, declarations: declaringModuleDeclarations))
		files.append(File(module: consumerModule, declarations: consumerDeclarations))
	}

	/// A place a public mock's tree instantiates only if available, which no declaration of its module fulfills, in one graph
	/// in five: `OptionalNode`, a `.public` type of the declaring module with an `internal` initializer, so that a consumer's
	/// mock calls its public mock, holds `optionalApi: (any OptionalApi)?` itself, or, half the time, `OptionalLeaf`, which it
	/// builds, holds it, directly or, in a graph whose types are all `Sendable`, through a `SendableInstantiator`. Half the time `OptionalReader`, which the holder builds, receives the value only if available.
	/// `OptionalScreen`, a mocked consumer in one consumer module, `true` or, one draw in three, `.public`, builds
	/// `OptionalNode`, and `OptionalLive` beside it fulfills `OptionalApi`, or, in half the draws, nothing does, so that the
	/// consumer's mock passes the public mock's builder up, defaulting to one that returns `nil`. The value differential
	/// compares each with the same types' internal mocks, where `OptionalLive` builds the place or nothing fulfills it.
	/// Every roll is made before any is read.
	private mutating func drawOptionalPlacePublicMock(random: inout GraphFuzzerRandomNumberGenerator) {
		let drawsShape = random.percentChance(20)
		let onLeaf = random.percentChance(50)
		let receives = random.percentChance(50)
		let consumerIsPublic = random.percentChance(33)
		let passesUp = random.percentChance(50)
		let consumerModuleRoll = random.integer(in: 0...1)
		let consumerModules = consumerModules
		guard drawsShape, !consumerModules.isEmpty, !hasDifferingMockCondition else { return }
		let consumerModule = consumerModules[consumerModuleRoll % consumerModules.count]
		let conformances = isSendableGraph ? ["@unchecked Sendable"] : []
		let apiName = name("OptionalApi")
		let nodeName = name("OptionalNode")
		let leafName = name("OptionalLeaf")
		let readerName = name("OptionalReader")
		let place = Property(attribute: "@Instantiated(onlyIfAvailable: true)", label: "optionalApi", type: "(any \(apiName))?")
		var holderProperties = [place]
		var reader: InstantiableClass?
		if receives {
			var optionalReader = InstantiableClass(name: readerName, conformances: conformances)
			optionalReader.properties = [Property(attribute: "@Received(onlyIfAvailable: true)", label: "optionalApi", type: "(any \(apiName))?")]
			holderProperties.append(Property(attribute: "@Instantiated", label: "optionalReader", type: readerName))
			reader = optionalReader
		}
		var node = InstantiableClass(name: nodeName, conformances: conformances)
		node.mockGeneration = ".public"
		// An `internal` initializer, which no consumer module can call, so that the consumer's mock calls the public mock.
		node.initializerAccess = .internal
		var declaringModuleDeclarations = [protocolDeclaration(apiName)]
		if onLeaf {
			var leaf = InstantiableClass(name: leafName, conformances: conformances)
			leaf.properties = holderProperties
			node.properties = isSendableGraph
				? [Property(attribute: "@Instantiated", label: "optionalLeafBuilder", type: "SendableInstantiator<\(leafName)>")]
				: [Property(attribute: "@Instantiated", label: "optionalLeaf", type: leafName)]
			declaringModuleDeclarations += [Self.renderer(of: node), Self.renderer(of: leaf)]
		} else {
			node.properties = holderProperties
			declaringModuleDeclarations.append(Self.renderer(of: node))
		}
		if let reader {
			declaringModuleDeclarations.append(Self.renderer(of: reader))
		}
		var screen = InstantiableClass(name: name("OptionalScreen"), conformances: conformances)
		screen.mockGeneration = consumerIsPublic ? ".public" : "true"
		screen.properties = [Property(attribute: "@Instantiated", label: "optionalNode", type: nodeName)]
		var consumerDeclarations = [Self.renderer(of: screen)]
		if !passesUp {
			var live = InstantiableClass(name: name("OptionalLive"), conformances: [apiName] + conformances)
			live.arguments = ["fulfillingAdditionalTypes: [\(apiName).self]"]
			consumerDeclarations.append(Self.renderer(of: live))
		}
		files.append(File(module: .seamModule, declarations: declaringModuleDeclarations))
		files.append(File(module: consumerModule, declarations: consumerDeclarations))
	}

	/// A value a consumer's mock cannot build, passed to the public mock it calls, in one graph in five: `UnbuildableScreen`,
	/// a mocked consumer in one consumer module, instantiates `unbuildableFilter`, of a type no `@Instantiable` declares, so
	/// that its `mock()` takes it, and `UnbuildableService`, a `.public` type of the declaring module with an `internal`
	/// initializer, so that its mock calls the public mock. Beneath `UnbuildableService`, `UnbuildableCache` receives the
	/// value only if available. The value is of `UnbuildableFilter`, a public class beside `UnbuildableService`, which every
	/// tier takes (`unbuildableValuePublicMockCallPublicTier`), unless the consumer is in another package and a roll of one
	/// in ten says otherwise: then it is of `[3 of Int]`, whose spelling SafeDI cannot read, which only `UnbuildableCache`'s
	/// `package` initializer mentions, so that SafeDI proves it `package`, the public tier the consumer calls omits it, and
	/// the tool rejects the graph (`leafTierOmitsProvidedValue`) rather than pass `nil`
	/// (`unbuildableValuePublicMockCallTierOmits`). A consumer in the declaring module's package is never handed `[3 of Int]`:
	/// it would reach the `package` tier and be accepted, so the value differential and the compile, which smoke seeds make on
	/// macOS too, where `InlineArray` needs macOS 26, would read it. A type SafeDI reads the spelling of is proven as its
	/// declaration says, so a consumer in another package that can name it reaches a tier that takes it. The value
	/// differential calls the consumer's `mock()` with a value of its own (`GraphFuzzerFixture.publicMockUnbuildableValueProbe`).
	/// Every roll is made before any is read.
	private mutating func drawUnbuildableValuePassedToPublicMock(random: inout GraphFuzzerRandomNumberGenerator) {
		let drawsShape = random.percentChance(20)
		let omitsValueRoll = random.percentChance(10)
		let consumerModuleRoll = random.integer(in: 0...1)
		let consumerModules = consumerModules
		guard drawsShape, !consumerModules.isEmpty, !hasDifferingMockCondition else { return }
		let consumerModule = consumerModules[consumerModuleRoll % consumerModules.count]
		let tierOmitsValue = omitsValueRoll && consumerModule == .otherPackageCaller
		let conformances = isSendableGraph ? ["@unchecked Sendable"] : []
		let filterName = name("UnbuildableFilter")
		let valueType = tierOmitsValue ? Self.unreadableUnbuildableValueType : filterName
		var cache = InstantiableClass(name: name("UnbuildableCache"), conformances: conformances)
		cache.initializerAccess = tierOmitsValue ? .package : .public
		cache.properties = [Property(attribute: "@Received(onlyIfAvailable: true)", label: "unbuildableFilter", type: "\(valueType)?")]
		var service = InstantiableClass(name: name("UnbuildableService"), conformances: conformances)
		service.mockGeneration = ".public"
		// An `internal` initializer, which no consumer module can call, so that the consumer's mock calls the public mock.
		service.initializerAccess = .internal
		service.properties = [Property(attribute: "@Instantiated", label: "unbuildableCache", type: cache.name)]
		var screen = InstantiableClass(name: name("UnbuildableScreen"), conformances: conformances)
		screen.mockGeneration = "true"
		screen.properties = [
			Property(attribute: "@Instantiated", label: "unbuildableFilter", type: valueType),
			Property(attribute: "@Instantiated", label: "unbuildableService", type: service.name),
		]
		var declarations = [Self.renderer(of: service), Self.renderer(of: cache)]
		if !tierOmitsValue {
			declarations.append { rendering in
				"\(rendering.modifier(.public))final class \(filterName): Sendable {\n\t\(rendering.modifier(.public))init() {}\n}"
			}
		}
		files.append(File(module: .seamModule, declarations: declarations))
		files.append(File(module: consumerModule, declarations: [Self.renderer(of: screen)]))
	}

	/// A dependency two public mocks of a module beneath build when passed `nil`, which the module between cannot construct
	/// and the calling module can, in three graphs in twenty: `OuterAlpha` and `OuterBeta`, `.public` types of `FuzzCore`
	/// (package `core`) with `internal` initializers, receive `outerClock: any OuterClock`, which only `OuterMeter`,
	/// `package` in `FuzzCore`, fulfills, so each of their mocks builds it when passed `nil`. `OuterStep`, a `.public` type
	/// of `FuzzSession` (package `shop`) with an `internal` initializer, builds both, so its mock calls theirs and, since its
	/// module cannot construct `OuterMeter`, takes `outerClock` only if available and builds none. `OuterScreen`, a mocked
	/// type of the declaring module, builds `OuterStep`, and `OuterFakeClock`, a `mockOnly` fake beside it, fulfills
	/// `OuterClock`, so `OuterScreen`'s mock builds one fake and hands it to both calls through `OuterStep`'s mock, as the
	/// inline mock does (M8.8b), whether it reads `OuterStep`'s plan from `FuzzSession`'s module info or computes it. Both
	/// receive `outerLabel`, which the value differential hands `OuterScreen`'s mock
	/// (`GraphFuzzerFixture.publicMockOuterFulfillerProbe`). Every roll is made before any is read.
	private mutating func drawFulfillerOnlyCallingModuleCanBuild(random: inout GraphFuzzerRandomNumberGenerator) {
		let drawsShape = random.percentChance(15)
		guard drawsShape, !hasDifferingMockCondition else { return }
		let conformances = isSendableGraph ? ["@unchecked Sendable"] : []
		let clockName = name("OuterClock")
		let fakeName = name("OuterFakeClock")
		var meter = InstantiableClass(name: name("OuterMeter"), conformances: [clockName] + conformances)
		meter.access = .package
		meter.arguments = ["fulfillingAdditionalTypes: [\(clockName).self]"]
		typeAccess[meter.name] = .package
		let calledMocks = ["OuterAlpha", "OuterBeta"].map { suffix in
			var calledMock = InstantiableClass(name: name(suffix), conformances: conformances)
			calledMock.mockGeneration = ".public"
			// An `internal` initializer, which no other module can call, so that each module above calls the public mock.
			calledMock.initializerAccess = .internal
			calledMock.properties = [Property(attribute: "@Received", label: "outerClock", type: "any \(clockName)")]
			return calledMock
		}
		var step = InstantiableClass(name: name("OuterStep"), conformances: conformances)
		step.mockGeneration = ".public"
		step.initializerAccess = .internal
		// Each mock takes `outerLabel` as a required parameter, so that only the probe that hands `OuterScreen`'s mock one
		// calls either: `OuterStep`'s own mock, whose module cannot construct `OuterMeter`, has each called mock build one,
		// as `public-mocks.md` states.
		let label = Property(attribute: "@Received", label: "outerLabel", type: "String")
		step.properties = [
			Property(attribute: "@Instantiated", label: "outerAlpha", type: calledMocks[0].name),
			Property(attribute: "@Instantiated", label: "outerBeta", type: calledMocks[1].name),
			label,
		]
		var screen = InstantiableClass(name: name("OuterScreen"), conformances: conformances)
		screen.mockGeneration = "true"
		screen.properties = [Property(attribute: "@Instantiated", label: "outerStep", type: step.name), label]
		let fake: (Rendering) -> String = { rendering in
			[
				"@Instantiable(fulfillingAdditionalTypes: [\(clockName).self], mockOnly: true)",
				"\(rendering.modifier(.public))final class \(fakeName): \(clockName) {",
				"\t\(rendering.modifier(.public))init() {}",
				"",
				"\t\(rendering.modifier(.public))static func mock() -> \(fakeName) {",
				"\t\t\(fakeName)()",
				"\t}",
				"}",
			].joined(separator: "\n")
		}
		files.append(File(module: .seamDependencyBase, declarations: [protocolDeclaration(clockName), Self.renderer(of: meter)] + calledMocks.map(Self.renderer(of:))))
		files.append(File(module: .seamDependency, declarations: [Self.renderer(of: step)]))
		// The declaring module imports only `FuzzSession`, so its file imports the module that declares `OuterClock`.
		files.append(File(module: .seamModule, declarations: [{ _ in "import \(GraphFuzzerModule.seamDependencyBase.name)" }, Self.renderer(of: screen), fake]))
	}

	/// Twins beneath a public mock, the public mock corpus's form of the base and seam corpora's twins over a shared screen
	/// (`GraphFuzzerGenerator`'s `addingTwinsOverSharedScreen`), in three graphs in twenty: `TwinHome`, a `.public` type of
	/// the declaring module with an `internal` initializer, builds `TwinFirst` by value or through an instantiator, and now
	/// and then opens `TwinSecond` too. `TwinFirst` declares `twinModel` in one form and `TwinSecond` in the other
	/// (`LazilyInstantiated`, or, in half the `Sendable` graphs, `SendableLazilyInstantiated`), and each builds `TwinScreen`,
	/// which receives `twinModel` by value, required or only if available, and now and then builds `TwinPanel`, which
	/// receives it too. `TwinModel` opens `TwinSecond` through an instantiator, so the cycle closes on `TwinSecond`'s
	/// declaration of the model, whichever twin a path built first. `TwinApp`, a mocked consumer in one consumer module,
	/// builds `TwinHome`, so that its mock calls `TwinHome`'s public mock, which the value differential compares with the
	/// known-right path's inline mock. Every roll is made before any is read.
	private mutating func drawTwinsPublicMock(random: inout GraphFuzzerRandomNumberGenerator) {
		let drawsShape = random.percentChance(15)
		let drawsSendableWrappers = random.percentChance(50)
		let valueFirst = random.percentChance(50)
		let screenReceivesRequired = random.percentChance(70)
		let buildsPanel = random.percentChance(40)
		let firstBuiltThroughInstantiator = random.percentChance(50)
		let homeOpensSecond = random.percentChance(40)
		let consumerModuleRoll = random.integer(in: 0...1)
		// Whether each type of two properties lists them in the other order: `TwinFirst`, `TwinSecond`, `TwinScreen`, `TwinHome`.
		let swapsProperties = (0..<4).map { _ in random.percentChance(50) }
		let consumerModules = consumerModules
		guard drawsShape, !consumerModules.isEmpty, !hasDifferingMockCondition else { return }
		let consumerModule = consumerModules[consumerModuleRoll % consumerModules.count]
		let conformances = isSendableGraph ? ["@unchecked Sendable"] : []
		let isSendable = isSendableGraph && drawsSendableWrappers
		let instantiator = isSendable ? "SendableInstantiator" : "Instantiator"
		let lazyWrapper = isSendable ? "SendableLazilyInstantiated" : "LazilyInstantiated"
		func ordered(_ properties: [Property], swapping index: Int) -> [Property] {
			swapsProperties[index] ? properties.reversed() : properties
		}
		let modelName = name("TwinModel")
		let valueModel = Property(attribute: "@Instantiated", label: "twinModel", type: modelName)
		let lazyModel = Property(attribute: "@Instantiated", label: "twinModel", type: "\(lazyWrapper)<\(modelName)>")
		let screenProperty = Property(attribute: "@Instantiated", label: "twinScreen", type: name("TwinScreen"))
		let secondBuilder = Property(attribute: "@Instantiated", label: "twinSecondBuilder", type: "\(instantiator)<\(name("TwinSecond"))>")
		var first = InstantiableClass(name: name("TwinFirst"), conformances: conformances)
		first.properties = ordered([valueFirst ? valueModel : lazyModel, screenProperty], swapping: 0)
		var second = InstantiableClass(name: name("TwinSecond"), conformances: conformances)
		second.properties = ordered([valueFirst ? lazyModel : valueModel, screenProperty], swapping: 1)
		var model = InstantiableClass(name: modelName, conformances: conformances)
		model.properties = [secondBuilder]
		var screen = InstantiableClass(name: name("TwinScreen"), conformances: conformances)
		var screenProperties = [screenReceivesRequired
			? Property(attribute: "@Received", label: "twinModel", type: modelName)
			: Property(attribute: "@Received(onlyIfAvailable: true)", label: "twinModel", type: modelName + "?")]
		var declarations = [(Rendering) -> String]()
		if buildsPanel {
			screenProperties.append(Property(attribute: "@Instantiated", label: "twinPanel", type: name("TwinPanel")))
			var panel = InstantiableClass(name: name("TwinPanel"), conformances: conformances)
			panel.properties = [Property(attribute: "@Received", label: "twinModel", type: modelName)]
			declarations.append(Self.renderer(of: panel))
		}
		screen.properties = ordered(screenProperties, swapping: 2)
		var home = InstantiableClass(name: name("TwinHome"), conformances: conformances)
		home.mockGeneration = ".public"
		// An `internal` initializer, which no consumer module can call, so that the consumer's mock calls the public mock.
		home.initializerAccess = .internal
		var homeProperties = [firstBuiltThroughInstantiator
			? Property(attribute: "@Instantiated", label: "twinFirstBuilder", type: "\(instantiator)<\(first.name)>")
			: Property(attribute: "@Instantiated", label: "twinFirst", type: first.name)]
		if homeOpensSecond {
			homeProperties.append(secondBuilder)
		}
		home.properties = ordered(homeProperties, swapping: 3)
		var app = InstantiableClass(name: name("TwinApp"), conformances: conformances)
		app.mockGeneration = "true"
		app.properties = [Property(attribute: "@Instantiated", label: "twinHome", type: home.name)]
		files.append(File(module: .seamModule, declarations: [Self.renderer(of: home), Self.renderer(of: first), Self.renderer(of: second), Self.renderer(of: model), Self.renderer(of: screen)] + declarations))
		files.append(File(module: consumerModule, declarations: [Self.renderer(of: app)]))
	}

	/// The type of the value `drawUnbuildableValuePassedToPublicMock` hands a public mock whose tier omits it: an
	/// `InlineArray`, whose spelling SafeDI cannot read.
	static let unreadableUnbuildableValueType = "[3 of Int]"

	/// A hole whose label a promoted sibling receives as another type, in one graph in a hundred: `LabelHome`, a `.public`
	/// type of the declaring module, instantiates `labelGadget` of `LabelGadget`, which conforms to `Instantiable` by hand, so
	/// that no declaration fulfills it and its public mock would take a builder for the place – as itself, an `Instantiator`,
	/// or a `LazilyInstantiated`, a third of the draws each – and receives `labelPanelBuilder: Instantiator<LabelPanel>`,
	/// which its mock builds at its root, beside the hole. `LabelPanel` receives `labelGadget: Instantiator<LabelWidget>`,
	/// which `mock()` takes, so that the mock would bind the hole's value under a name of its own and hand its builder
	/// `LabelHome`'s values by label while it holds two under the hole's: the tool rejects the graph
	/// (`publicMockHoleSiteBoundApartFinding`). In half the draws the hole is labeled `labelGadget_lazilyInstantiated`
	/// instead, and `LabelPanel` receives `labelGadget: LazilyInstantiated<LabelWidget>`, around whose value the mock binds a
	/// `LazilyInstantiated` under that name: no type receives the hole's label, and the tool rejects the graph naming the
	/// generated value. The roll is rare, since each graph it draws is one the tool rejects, which no oracle of an accepted
	/// graph judges. `LabelWidget` conforms to `Instantiable` by hand too. Every roll is made before any is read.
	private mutating func drawHoleLabelReceivedByPromotedSibling(random: inout GraphFuzzerRandomNumberGenerator) {
		let drawsShape = random.percentChance(1)
		let holeKindRoll = random.integer(in: 0...2)
		let labelsHoleAsGeneratedName = random.percentChance(50)
		guard drawsShape, !hasDifferingMockCondition else { return }
		let conformances = isSendableGraph ? ["@unchecked Sendable"] : []
		let gadgetName = name("LabelGadget")
		let widgetName = name("LabelWidget")
		let holeType = switch holeKindRoll {
		case 0: gadgetName
		case 1: "Instantiator<\(gadgetName)>"
		default: "LazilyInstantiated<\(gadgetName)>"
		}
		var panel = InstantiableClass(name: name("LabelPanel"), conformances: conformances)
		panel.properties = [Property(attribute: "@Received", label: "labelGadget", type: labelsHoleAsGeneratedName ? "LazilyInstantiated<\(widgetName)>" : "Instantiator<\(widgetName)>")]
		var home = InstantiableClass(name: name("LabelHome"), conformances: conformances)
		home.mockGeneration = ".public"
		home.properties = [
			Property(attribute: "@Received", label: "labelPanelBuilder", type: "Instantiator<\(panel.name)>"),
			Property(attribute: "@Instantiated", label: labelsHoleAsGeneratedName ? "labelGadget_lazilyInstantiated" : "labelGadget", type: holeType),
		]
		// Each conforms to `Instantiable` by hand, so that no `@Instantiable` declaration fulfills it.
		let handConformingClasses: [(Rendering) -> String] = [gadgetName, widgetName].map { typeName in
			{ rendering in "\(rendering.modifier(.public))final class \(typeName): Instantiable, Sendable {\n\t\(rendering.modifier(.public))init() {}\n}" }
		}
		files.append(File(module: .seamModule, declarations: [Self.renderer(of: home), Self.renderer(of: panel)] + handConformingClasses))
	}

	/// A holder of one of a public mock's places declared before a sibling that holds none, in three graphs in twenty:
	/// `CarrierHome`, a `.public` type of the declaring module with an `internal` initializer, declares `carrierStore`, then
	/// `carrierCart`, which receives it, and before both, or three draws in ten between them, the holder of a place of
	/// `CarrierApi`, which no declaration of the declaring module fulfills: `CarrierPart`, whose own property is the place,
	/// or, half the time, `CarrierBanner`, a seam of the declaring module whose tree holds it, which then sets
	/// `generatePlainDependencyTreeInitializers: true`. Two draws in five
	/// `CarrierShelf`, a type `CarrierHome` builds, declares the three instead. The mock builds the holder after its
	/// siblings, so that the place's scope struct carries them, but `CarrierHome`'s `SafeDIOverrides`, or `CarrierShelf`'s
	/// module-level configuration, takes them in declaration order, as the internal mock does
	/// (`GraphFuzzerToolRuns.publicMockOverridesOrderFailure`). `CarrierApp`, a mocked consumer in one consumer module,
	/// builds `CarrierHome`, so that its mock calls `CarrierHome`'s public mock, and `CarrierLive` beside it fills the
	/// place. Half the draws that declare `CarrierShelf` also declare `CarrierLocal`, a type of the declaring module with an
	/// internal mock that builds `CarrierShelf`, so that `CarrierShelf`'s internal `SafeDIMockConfiguration`, which a module
	/// with a public mock configuring the type once took in build order, takes the three in declaration order too. Every roll
	/// is made before any is read.
	private mutating func drawCarrierBeforeSiblingPublicMock(random: inout GraphFuzzerRandomNumberGenerator) {
		let drawsShape = random.percentChance(15)
		let holdsThroughSeam = random.percentChance(50)
		let holderBetweenSiblings = random.percentChance(30)
		let beneathConfiguredChild = random.percentChance(40)
		let consumerModuleRoll = random.integer(in: 0...1)
		// Drawn last, so that the draws before it are the draws they were.
		let shelfMockedInternallyToo = random.percentChance(50)
		let consumerModules = consumerModules
		guard drawsShape, !consumerModules.isEmpty, !hasDifferingMockCondition else { return }
		let consumerModule = consumerModules[consumerModuleRoll % consumerModules.count]
		let conformances = isSendableGraph ? ["@unchecked Sendable"] : []
		let apiName = name("CarrierApi")
		var holder = InstantiableClass(name: name(holdsThroughSeam ? "CarrierBanner" : "CarrierPart"), conformances: conformances)
		if holdsThroughSeam {
			holder.arguments = ["generateDependencyTree: true"]
		}
		holder.properties = [Property(attribute: "@Instantiated", label: "carrierApi", type: "any \(apiName)")]
		let store = InstantiableClass(name: name("CarrierStore"), conformances: conformances)
		var cart = InstantiableClass(name: name("CarrierCart"), conformances: conformances)
		cart.properties = [Property(attribute: "@Received", label: "carrierStore", type: store.name)]
		let holderProperty = Property(attribute: "@Instantiated", label: holdsThroughSeam ? "carrierBanner" : "carrierPart", type: holder.name)
		var siblings = [
			Property(attribute: "@Instantiated", label: "carrierStore", type: store.name),
			Property(attribute: "@Instantiated", label: "carrierCart", type: cart.name),
		]
		siblings.insert(holderProperty, at: holderBetweenSiblings ? 1 : 0)
		var home = InstantiableClass(name: name("CarrierHome"), conformances: conformances)
		home.mockGeneration = ".public"
		// An `internal` initializer, which no consumer module can call, so that a consumer's mock calls the public mock.
		home.initializerAccess = .internal
		var declaringModuleDeclarations = [protocolDeclaration(apiName)]
		if beneathConfiguredChild {
			var shelf = InstantiableClass(name: name("CarrierShelf"), conformances: conformances)
			shelf.properties = siblings
			home.properties = [Property(attribute: "@Instantiated", label: "carrierShelf", type: shelf.name)]
			declaringModuleDeclarations.append(Self.renderer(of: shelf))
			if shelfMockedInternallyToo {
				// An internal mock beside the public one that configures `CarrierShelf` too.
				var local = InstantiableClass(name: name("CarrierLocal"), conformances: conformances)
				local.mockGeneration = "true"
				local.properties = [Property(attribute: "@Instantiated", label: "carrierShelf", type: shelf.name)]
				declaringModuleDeclarations.append(Self.renderer(of: local))
			}
		} else {
			home.properties = siblings
		}
		declaringModuleDeclarations += [Self.renderer(of: home), Self.renderer(of: holder), Self.renderer(of: store), Self.renderer(of: cart)]
		if holdsThroughSeam {
			// The seam's readable initializer, which the builder surface's oracle reads, as the seam corpus's modules declare it
			// (`GraphFuzzerFixture.seamCorpusFixture`). No other module of a graph this draw reaches declares a configuration.
			declaringModuleDeclarations.append { _ in "#SafeDIConfiguration(generatePlainDependencyTreeInitializers: true)" }
		}
		var app = InstantiableClass(name: name("CarrierApp"), conformances: conformances)
		app.mockGeneration = "true"
		app.properties = [Property(attribute: "@Instantiated", label: "carrierHome", type: home.name)]
		var live = InstantiableClass(name: name("CarrierLive"), conformances: [apiName] + conformances)
		live.arguments = ["fulfillingAdditionalTypes: [\(apiName).self]"]
		files.append(File(module: .seamModule, declarations: declaringModuleDeclarations))
		files.append(File(module: consumerModule, declarations: [Self.renderer(of: app), Self.renderer(of: live)]))
	}

	/// A value a public mock takes as the wrapper its tree receives that its tree also reads by value, in three graphs in ten:
	/// `WrapNode`, a `.public` type of the declaring module with an `internal` initializer, so that a consumer calls its mock,
	/// receives `wrapSession` and builds `WrapReader`, directly or, half the time, through an `Instantiator`, which receives it
	/// in the other form. A third of the draws each, `WrapNode` receives the value by value and `WrapReader` the wrapper;
	/// `WrapNode` receives it by value only if available and `WrapReader` the wrapper; or `WrapNode` receives the wrapper and
	/// `WrapReader` the value. The wrapper is a `LazilyInstantiated`, or, in a graph whose types are all `Sendable`, half the
	/// time a `SendableLazilyInstantiated`. `WrapSession` conforms to `Instantiable` by hand, so that the declaring module
	/// cannot build it and `WrapNode`'s mock takes the wrapper, which hands its instance to each type that reads the value;
	/// `WrapScreen`, a mocked consumer in one consumer module, `true` or, one draw in three, `.public`, builds the wrapper
	/// through an extension of `WrapSession` of its own module, and `WrapNode`, whose mock it hands the wrapper. No reader is
	/// built inside a `@Sendable` function, which cannot capture a `LazilyInstantiated` (the error
	/// `SafeDIToolPublicMockLazyWrapperTests` covers). Every roll is made before any is read.
	private mutating func drawWrapperReadByValuePublicMock(random: inout GraphFuzzerRandomNumberGenerator) {
		let drawsShape = random.percentChance(30)
		let formRoll = random.integer(in: 0...2)
		let isSendablyWrapped = random.percentChance(50)
		let readerThroughInstantiator = random.percentChance(50)
		let consumerIsPublic = random.percentChance(33)
		let consumerModuleRoll = random.integer(in: 0...1)
		let consumerModules = consumerModules
		guard drawsShape, !consumerModules.isEmpty, !hasDifferingMockCondition else { return }
		let consumerModule = consumerModules[consumerModuleRoll % consumerModules.count]
		let conformances = isSendableGraph ? ["@unchecked Sendable"] : []
		let sessionName = name("WrapSession")
		let wrapperType = "\(isSendableGraph && isSendablyWrapped ? "SendableLazilyInstantiated" : "LazilyInstantiated")<\(sessionName)>"
		var reader = InstantiableClass(name: name("WrapReader"), conformances: conformances)
		var node = InstantiableClass(name: name("WrapNode"), conformances: conformances)
		node.mockGeneration = ".public"
		node.initializerAccess = .internal
		switch formRoll {
		case 0:
			node.properties = [Property(attribute: "@Received", label: "wrapSession", type: sessionName)]
			reader.properties = [Property(attribute: "@Received", label: "wrapSession", type: wrapperType)]
		case 1:
			node.properties = [Property(attribute: "@Received(onlyIfAvailable: true)", label: "wrapSession", type: "\(sessionName)?")]
			reader.properties = [Property(attribute: "@Received", label: "wrapSession", type: wrapperType)]
		default:
			node.properties = [Property(attribute: "@Received", label: "wrapSession", type: wrapperType)]
			reader.properties = [Property(attribute: "@Received", label: "wrapSession", type: sessionName)]
		}
		node.properties.append(readerThroughInstantiator
			? Property(attribute: "@Instantiated", label: "wrapReaderBuilder", type: "Instantiator<\(reader.name)>")
			: Property(attribute: "@Instantiated", label: "wrapReader", type: reader.name))
		var screen = InstantiableClass(name: name("WrapScreen"), conformances: conformances)
		screen.mockGeneration = consumerIsPublic ? ".public" : "true"
		screen.properties = [
			Property(attribute: "@Instantiated", label: "wrapSession", type: wrapperType),
			Property(attribute: "@Instantiated", label: "wrapNode", type: node.name),
		]
		// `WrapSession` conforms to `Instantiable` by hand, so that only the consumer's module, through an extension of its own,
		// builds it.
		let session: (Rendering) -> String = { rendering in
			"\(rendering.modifier(.public))final class \(sessionName): Instantiable, Sendable {\n\t\(rendering.modifier(.public))init() {}\n}"
		}
		let sessionExtension: (Rendering) -> String = { rendering in
			"@Instantiable(conformsElsewhere: true)\nextension \(sessionName) {\n\t\(rendering.modifier(.public))static func instantiate() -> \(sessionName) {\n\t\t\(sessionName)()\n\t}\n}"
		}
		files.append(File(module: .seamModule, declarations: [Self.renderer(of: node), Self.renderer(of: reader), session]))
		files.append(File(module: consumerModule, declarations: [Self.renderer(of: screen), sessionExtension]))
	}

	/// One value received in several forms beside a call of a public mock that takes it, in seven graphs in twenty, the shapes
	/// of the defects the mock emitter's rewrite fixed: `FormScreen`, a mocked consumer in one consumer module, `true` or, one
	/// draw in three, `.public`, receives `formToken`, a plain class nothing builds, so that it is never a production root,
	/// and, two draws in five, `formSession` in one of the siblings' forms. It builds `FormCache`, a `.public` type of the
	/// declaring module with an `internal` initializer, so that it calls its public mock, directly or, one draw in four,
	/// through `FormHolder`, which builds `FormCache` and itself again through an instantiator, an edge `cycleEdges` prunes.
	/// `FormCache` receives `formSession` by value, only if available, or as a `LazilyInstantiated`. Beside it `FormScreen`
	/// builds one to three siblings, `FormFeed1`…, each now and then through an instantiator, each receiving `formSession` by
	/// value, only if available, through either wrapper kind (the `Sendable` one only in a graph whose types are all
	/// `Sendable`), through an optional `LazilyInstantiated` only if available, or renamed from `formSession`. `FormSession`
	/// conforms to `Instantiable` by hand, and the consumer's module builds it through an extension of its own, so the
	/// declaring module's mock takes it; or, half the time, it is a plain class no module builds, so the consumer's mock takes
	/// it too. A sibling now and then receives the label as `FormMark`, another type, which the mock names apart. Two draws in
	/// five `FormCache` builds `FormCacheEntry`, which receives the label as an optional wrapper only if available, by value,
	/// or as `FormMark`. Two `.public` consumers in five receive an optional wrapper of it only if available, a
	/// `SendableLazilyInstantiated` half the time in a `Sendable` graph, beside a first sibling that receives `FormMark`. Two
	/// draws in five `FormScreen` also builds `FormBadge`, a `.public` type of the declaring module with an
	/// `internal` initializer that takes nothing, whose public mock builds nothing but the type. Every roll is made before
	/// any is read.
	private mutating func drawValueFormsBesidePublicMockCall(random: inout GraphFuzzerRandomNumberGenerator) {
		let drawsShape = random.percentChance(35)
		let sessionIsBuildable = random.percentChance(50)
		let consumerIsPublic = random.percentChance(33)
		let consumerModuleRoll = random.integer(in: 0...1)
		let consumerReceivesSession = random.percentChance(40)
		let consumerFormRoll = random.integer(in: 0...5)
		let cacheFormRoll = random.integer(in: 0...9)
		let buildsThroughHolder = random.percentChance(25)
		let siblingCount = random.integer(in: 1...3)
		let siblingFormRolls = (0..<3).map { _ in random.integer(in: 0...6) }
		let siblingsThroughInstantiator = (0..<3).map { _ in random.percentChance(20) }
		let buildsEmptyPublicMock = random.percentChance(40)
		let cacheBuildsEntry = random.percentChance(40)
		let entryFormRoll = random.integer(in: 0...3)
		let publicConsumerHoldsOptionalWrapperBesideOtherType = random.percentChance(40)
		let optionalWrapperIsSendable = random.percentChance(50)
		let consumerModules = consumerModules
		guard drawsShape, !consumerModules.isEmpty, !hasDifferingMockCondition else { return }
		let consumerModule = consumerModules[consumerModuleRoll % consumerModules.count]
		let conformances = isSendableGraph ? ["@unchecked Sendable"] : []
		let sessionName = name("FormSession")
		let tokenName = name("FormToken")
		let markName = name("FormMark")
		/// The property a type receiving `formSession` in form `roll` declares.
		func sessionProperty(form roll: Int) -> Property {
			switch roll {
			case 0:
				Property(attribute: "@Received", label: "formSession", type: sessionName)
			case 1:
				Property(attribute: "@Received(onlyIfAvailable: true)", label: "formSession", type: "\(sessionName)?")
			case 2:
				Property(attribute: "@Received", label: "formSession", type: "LazilyInstantiated<\(sessionName)>")
			case 3:
				isSendableGraph
					? Property(attribute: "@Received", label: "formSession", type: "SendableLazilyInstantiated<\(sessionName)>")
					: Property(attribute: "@Received", label: "formSession", type: "LazilyInstantiated<\(sessionName)>")
			case 4:
				Property(attribute: "@Received(onlyIfAvailable: true)", label: "formSession", type: "LazilyInstantiated<\(sessionName)>?")
			case 6:
				Property(attribute: "@Received", label: "formSession", type: markName)
			default:
				Property(attribute: "@Received(fulfilledByDependencyNamed: \"formSession\", ofType: \(sessionName).self)", label: "currentFormSession", type: sessionName)
			}
		}
		var cache = InstantiableClass(name: name("FormCache"), conformances: conformances)
		cache.mockGeneration = ".public"
		cache.initializerAccess = .internal
		cache.properties = [cacheFormRoll < 5 ? sessionProperty(form: 0) : cacheFormRoll < 8 ? sessionProperty(form: 1) : sessionProperty(form: 2)]
		var entry: InstantiableClass?
		if cacheBuildsEntry {
			// A type of the called mock's own tree that receives the label in another form.
			var cacheEntry = InstantiableClass(name: name("FormCacheEntry"), conformances: conformances)
			cacheEntry.properties = switch entryFormRoll {
			case 0:
				[Property(attribute: "@Received(onlyIfAvailable: true)", label: "formSession", type: "LazilyInstantiated<\(sessionName)>?")]
			case 1:
				[Property(attribute: "@Received(onlyIfAvailable: true)", label: "formSession", type: "\(isSendableGraph ? "SendableLazilyInstantiated" : "LazilyInstantiated")<\(sessionName)>?")]
			case 2:
				[sessionProperty(form: 0)]
			default:
				[sessionProperty(form: 6)]
			}
			cache.properties.append(Property(attribute: "@Instantiated", label: "formCacheEntry", type: cacheEntry.name))
			entry = cacheEntry
		}
		var screen = InstantiableClass(name: name("FormScreen"), conformances: conformances)
		screen.mockGeneration = consumerIsPublic ? ".public" : "true"
		screen.properties = [Property(attribute: "@Received", label: "formToken", type: tokenName)]
		var siblingForms = siblingFormRolls
		if consumerIsPublic, publicConsumerHoldsOptionalWrapperBesideOtherType {
			// A public mock whose own optional wrapper, received only if available, shares its label with another type a
			// sibling receives, so that the mock names the wrapper apart by its wrapper type.
			screen.properties.append(isSendableGraph && optionalWrapperIsSendable
				? Property(attribute: "@Received(onlyIfAvailable: true)", label: "formSession", type: "SendableLazilyInstantiated<\(sessionName)>?")
				: sessionProperty(form: 4))
			siblingForms[0] = 6
		} else if consumerReceivesSession {
			screen.properties.append(sessionProperty(form: consumerFormRoll))
		}
		var consumerDeclarations = [(Rendering) -> String]()
		if buildsThroughHolder {
			var holder = InstantiableClass(name: name("FormHolder"), conformances: conformances)
			holder.properties = [
				Property(attribute: "@Instantiated", label: "formCache", type: cache.name),
				Property(attribute: "@Instantiated", label: "formHolderBuilder", type: "Instantiator<\(holder.name)>"),
			]
			screen.properties.append(Property(attribute: "@Instantiated", label: "formHolder", type: holder.name))
			consumerDeclarations.append(Self.renderer(of: holder))
		} else {
			screen.properties.append(Property(attribute: "@Instantiated", label: "formCache", type: cache.name))
		}
		for index in 1...siblingCount {
			var sibling = InstantiableClass(name: name("FormFeed\(index)"), conformances: conformances)
			sibling.properties = [sessionProperty(form: siblingForms[index - 1])]
			screen.properties.append(siblingsThroughInstantiator[index - 1]
				? Property(attribute: "@Instantiated", label: "formFeed\(index)Builder", type: "Instantiator<\(sibling.name)>")
				: Property(attribute: "@Instantiated", label: "formFeed\(index)", type: sibling.name))
			consumerDeclarations.append(Self.renderer(of: sibling))
		}
		var declaringModuleDeclarations = [Self.renderer(of: cache), Self.renderer(of: InstantiableClass(name: markName, conformances: conformances))]
		if let entry {
			declaringModuleDeclarations.append(Self.renderer(of: entry))
		}
		if buildsEmptyPublicMock {
			// A `.public` type that takes nothing and builds nothing, whose public mock is one call of its initializer.
			var badge = InstantiableClass(name: name("FormBadge"), conformances: conformances)
			badge.mockGeneration = ".public"
			badge.initializerAccess = .internal
			screen.properties.append(Property(attribute: "@Instantiated", label: "formBadge", type: badge.name))
			declaringModuleDeclarations.append(Self.renderer(of: badge))
		}
		consumerDeclarations.insert(Self.renderer(of: screen), at: 0)
		let token: (Rendering) -> String = { rendering in
			"\(rendering.modifier(.public))final class \(tokenName): Sendable {\n\t\(rendering.modifier(.public))init() {}\n}"
		}
		declaringModuleDeclarations.append(token)
		if sessionIsBuildable {
			// `FormSession` conforms to `Instantiable` by hand, so that only the consumer's module, through an extension of its
			// own, builds it.
			declaringModuleDeclarations.append { rendering in
				"\(rendering.modifier(.public))final class \(sessionName): Instantiable, Sendable {\n\t\(rendering.modifier(.public))init() {}\n}"
			}
			consumerDeclarations.append { rendering in
				"@Instantiable(conformsElsewhere: true)\nextension \(sessionName) {\n\t\(rendering.modifier(.public))static func instantiate() -> \(sessionName) {\n\t\t\(sessionName)()\n\t}\n}"
			}
		} else {
			declaringModuleDeclarations.append { rendering in
				"\(rendering.modifier(.public))final class \(sessionName): Sendable {\n\t\(rendering.modifier(.public))init() {}\n}"
			}
		}
		files.append(File(module: .seamModule, declarations: declaringModuleDeclarations))
		files.append(File(module: consumerModule, declarations: consumerDeclarations))
	}

	/// Declares `Logger`, its production type `ConsoleLogger`, which instantiates `Level`, and a fake: a class at `package`
	/// or `internal` access in a file with no SafeDI content, as a macro expansion would declare it, extended by a
	/// `mockOnly` extension spelling `package` or no access level, whose `mock` takes a defaulted parameter half the
	/// time and one whose label names `ConsoleLogger`'s dependency a third of the time.
	private mutating func declareLogger(random: inout GraphFuzzerRandomNumberGenerator, isSendableGraph: Bool, conformances: [String], into files: inout [File]) {
		let loggerName = name("Logger")
		let levelName = name("Level")
		let fakeName = name("FakeLogger")
		let fakeAccess: AccessLevel = random.percentChance(50) ? .package : .internal
		let extensionAccess: AccessLevel? = fakeAccess == .package && random.percentChance(50) ? .package : nil
		if fakeAccess < .public {
			typeAccess[fakeName] = fakeAccess
		}
		var mockParameters = [String]()
		if random.percentChance(33) {
			mockParameters.append("level: \(levelName) = \(levelName)()")
		}
		if random.percentChance(50) {
			mockParameters.append("verbose: Bool = false")
		}
		let level = InstantiableClass(name: levelName, conformances: conformances)
		var console = InstantiableClass(name: name("ConsoleLogger"), conformances: [loggerName] + conformances)
		console.arguments = ["fulfillingAdditionalTypes: [\(loggerName).self]"]
		console.properties = [Property(attribute: "@Instantiated", label: "level", type: levelName)]
		let protocolDeclaration = "public protocol \(loggerName)\(isSendableGraph ? ": Sendable" : "") {}"
		let parameters = mockParameters.joined(separator: ", ")
		files.append(File(module: .seamModule, declarations: [Self.renderer(of: console), { _ in protocolDeclaration }]))
		files.append(File(module: .seamModule, declarations: [Self.renderer(of: level)]))
		files.append(File(module: .seamModule, fileName: "\(fakeName)Declaration.swift", declarations: [{ rendering in
			let inheritance = ([loggerName] + (isSendableGraph ? ["Sendable"] : [])).joined(separator: ", ")
			return "\(rendering.modifier(fakeAccess))final class \(fakeName): \(inheritance) {\n\t\(rendering.modifier(fakeAccess))init() {}\n}"
		}]))
		files.append(File(module: .seamModule, declarations: [{ rendering in
			"@Instantiable(fulfillingAdditionalTypes: [\(loggerName).self], mockOnly: true)\n\(rendering.extensionModifier(extensionAccess))extension \(fakeName) {\n\t\(rendering.isKnownRight ? "public " : "")static func mock(\(parameters)) -> \(fakeName) {\n\t\t\(fakeName)()\n\t}\n}"
		}]))
	}

	/// Declares the helper types `spelling` names, once, beside the plain types.
	private func declareSpellingHelpers(of spelling: GraphFuzzerPublicMockSpelling, isSendable: Bool, into declarations: inout [(Rendering) -> String], declared: inout Set<String>) {
		let sendable = isSendable ? ": Sendable" : ""
		switch spelling {
		case .plain, .generic:
			let valueName = name("SpellValue")
			if declared.insert("SpellValue").inserted {
				declarations.append { _ in "public final class \(valueName)\(sendable) {\n\tpublic init() {}\n}" }
			}
			if spelling == .generic {
				declared.insert("SpellResult")
			}
		case .existential:
			let protocolName = name("SpellProtocol")
			let conformerName = name("SpellConformer")
			if declared.insert("SpellProtocol").inserted {
				declarations.append { _ in "public protocol \(protocolName)\(sendable) {}\n\npublic final class \(conformerName): \(protocolName)\(isSendable ? ", Sendable" : "") {\n\tpublic init() {}\n}" }
			}
		case .nested:
			let outerName = name("SpellOuter")
			if declared.insert("SpellOuter").inserted {
				declarations.append { _ in "public enum \(outerName) {\n\tpublic final class Item\(sendable) {\n\t\tpublic init() {}\n\t}\n}" }
			}
		case .typealias:
			let aliasName = name("SpellIdentifier")
			if declared.insert("SpellIdentifier").inserted {
				declarations.append { _ in "public typealias \(aliasName) = String" }
			}
		case .closure, .sendableClosure, .optionalClosure, .tuple:
			break
		}
	}

	// MARK: Rendering

	/// The properties `T6`'s hole is declared with once `edit` is made, and the declarations the edit adds, or `nil` when
	/// the edit does not apply to the hole's spelling.
	private static func holeProperties(editedBy edit: GraphFuzzerBuilderSurfaceEdit, attribute: String, label: String, type: String, spelling: HoleSpelling, holeName: String, erasedName: String, protocolName: String, isSendableGraph: Bool) -> (properties: [Property], declarations: [(Rendering) -> String])? {
		let place = Property(attribute: attribute, label: label, type: type)
		switch (edit, spelling) {
		case (.placeBehindLazilyInstantiated, .plain), (.placeBehindLazilyInstantiated, .existential):
			// A `LazilyInstantiated` is not `Sendable`, and a `SendableLazilyInstantiated` place is another family.
			return isSendableGraph ? nil : ([Property(attribute: attribute, label: label, type: "LazilyInstantiated<\(type)>")], [])
		case (.instantiatorPlaceMovedToPlainPlace, .instantiator):
			return ([Property(attribute: attribute, label: label, type: holeName)], [])
		case (.instantiatorChangedToErasedInstantiator, .instantiator):
			return ([Property(attribute: "@Instantiated(fulfilledByType: \"\(holeName)\")", label: label, type: "ErasedInstantiator<\(holeName).ForwardedProperties, \(holeName)>")], [])
		case (.instantiatorMadeSendable, .instantiator):
			return ([Property(attribute: attribute, label: label, type: "SendableInstantiator<\(holeName)>")], [])
		case (.sendableInstantiatorChangedToSendableErasedInstantiator, .instantiator):
			return ([Property(attribute: "@Instantiated(fulfilledByType: \"\(holeName)\")", label: label, type: "SendableErasedInstantiator<\(holeName).ForwardedProperties, \(holeName)>")], [])
		case (.placeOfNewBuilderOfExistingFillingType, .erasedConstant), (.placeOfNewBuilderOfExistingFillingType, .erasedInstantiator):
			// A second erasure of the fill, to a second eraser: a builder of the same filling type returning another type.
			let otherErasedName = erasedName + "Other"
			// The hole's own type with its eraser replaced, so a hole that forwards a value keeps forwarding it.
			let otherType = type.replacingOccurrences(of: erasedName, with: otherErasedName)
			return ([place, Property(attribute: attribute, label: label + "Other", type: otherType)], [{ rendering in
				[
					"\(rendering.modifier(.public))struct \(otherErasedName): \(protocolName) {",
					"\t\(rendering.modifier(.public))init(_ value: any \(protocolName)) {",
					"\t\tself.value = value",
					"\t}",
					"",
					"\t\(rendering.modifier(.public))let value: any \(protocolName)",
					"}",
				].joined(separator: "\n")
			}])
		case (.placeForwardingOtherValues, .plain), (.placeForwardingOtherValuesRemedied, .plain):
			let forwarded = edit == .placeForwardingOtherValues ? "Int" : "()"
			return ([place, Property(attribute: "@Instantiated(fulfilledByType: \"\(holeName)\")", label: label + "Forwarding", type: "ErasedInstantiator<\(forwarded), \(holeName)>")], [])
		case (.secondPlaceInAnotherType, _),
		     (.secondPlaceInInnerSeamOfAnotherModule, _),
		     (.holderMovedToInnerSeamOfAnotherModule, _),
		     (.placeBehindLazilyInstantiated, _),
		     (.instantiatorPlaceMovedToPlainPlace, _),
		     (.instantiatorChangedToErasedInstantiator, _),
		     (.instantiatorMadeSendable, _),
		     (.sendableInstantiatorPlaceMovedToPlainPlace, _),
		     (.sendableInstantiatorChangedToSendableErasedInstantiator, _),
		     (.placeOfNewBuilderOfExistingFillingType, _),
		     (.placeOfNewBuilderInInnerSeamOfAnotherModule, _),
		     (.placeOfHoleTypeNamedAfterSendableLabel, _),
		     (.placeForwardingOtherValues, _),
		     (.placeForwardingOtherValuesRemedied, _),
		     (.placeForwardingOtherValuesInInnerSeamOfAnotherModule, _),
		     (.placeForwardingOtherValuesInInnerSeamOfAnotherModuleRemedied, _):
			// `sendableInstantiatorPlaceMovedToPlainPlace` adds a type, which the draw declares where it makes the edit.
			return nil
		}
	}

	/// The label of the plain builder a public mock takes for the holes of the type named `typeName`: the name with its
	/// leading capitals lowered, keeping the last when a lowercase letter follows it, then `Builder`.
	static func builderLabel(ofTypeNamed typeName: String) -> String {
		let characters = Array(typeName)
		let capitalCount = characters.prefix { $0.isUppercase }.count
		let loweredCount = capitalCount < characters.count && characters[capitalCount].isLowercase ? max(capitalCount - 1, 1) : capitalCount
		return String(characters[..<loweredCount]).lowercased() + String(characters[loweredCount...]) + "Builder"
	}

	fileprivate static func renderer(of declaration: InstantiableClass) -> (Rendering) -> String {
		{ rendering in render(declaration, rendering: rendering) }
	}

	/// The source of `declaration`, an `@Instantiable` class.
	fileprivate static func render(_ declaration: InstantiableClass, rendering: Rendering) -> String {
		var arguments = declaration.arguments
		if let mockGeneration = declaration.mockGeneration {
			arguments.append("generateMock: \(rendering.isKnownRight ? "true" : mockGeneration)")
		}
		if declaration.customMockAccess != nil {
			arguments.append("customMockName: \"customMock\"")
		}
		let attribute = arguments.isEmpty ? "@Instantiable" : "@Instantiable(\(arguments.joined(separator: ", ")))"
		// A type isolated to a global actor is `Sendable` already.
		let conformances = (["Instantiable"] + declaration.conformances.filter { !declaration.isMainActor || $0 != "@unchecked Sendable" }).joined(separator: ", ")
		var lines = [attribute, "\(declaration.isMainActor ? "@MainActor " : "")\(rendering.modifier(declaration.access))final class \(declaration.name): \(conformances) {"]
		/// A function-typed parameter is stored, so it escapes.
		func parameterType(_ type: String) -> String {
			GraphFuzzerSpelling.isFunctionType(type) ? "@escaping \(type)" : type
		}
		let parameters = declaration.properties.map { "\($0.label): \(parameterType($0.type))" }
			+ declaration.defaults.map { "\($0.argumentLabel.map { "\($0) " } ?? "")\($0.name): \($0.isAutoclosure ? "@autoclosure @escaping \($0.type)" : parameterType($0.type)) = \($0.defaultValue)" }
		// The initializer is no wider than its type, nor than the narrowest type it names, so that the fixture compiles.
		let initializerAccess = min(declaration.initializerAccess ?? declaration.access, declaration.narrowestNamedAccess, declaration.access)
		let nonisolated = declaration.initializerIsNonisolated ? "nonisolated " : declaration.initializerSpellsMainActor ? "@MainActor " : ""
		let storedDefaults = rendering.storesEveryParameter ? declaration.defaults : []
		if rendering.storesEveryParameter {
			lines.append("\t\(DifferentialValueCreationStamp.property(counterNamed: rendering.counterName))")
			lines.append("")
		}
		if declaration.properties.isEmpty, storedDefaults.isEmpty {
			lines.append("\t\(nonisolated)\(rendering.modifier(initializerAccess))init(\(parameters.joined(separator: ", "))) {}")
		} else {
			lines.append("\t\(nonisolated)\(rendering.modifier(initializerAccess))init(\(parameters.joined(separator: ", "))) {")
			lines += declaration.properties.map { "\t\tself.\($0.label) = \($0.label)" }
			lines += storedDefaults.map { "\t\tself.\($0.name) = \($0.name)" }
			lines.append("\t}")
			lines.append("")
			lines += declaration.properties.map { "\t\($0.attribute) let \($0.label): \($0.type)" }
			lines += storedDefaults.map { "\tlet \($0.name): \($0.type)" }
		}
		for member in declaration.staticMembers {
			lines.append("")
			lines.append("\t\(declaration.isMainActor ? "nonisolated " : "")\(rendering.modifier(min(member.access, initializerAccess)))\(member.declaration)")
		}
		if let customMockAccess = declaration.customMockAccess {
			let access = min(customMockAccess, declaration.narrowestNamedAccess, declaration.access)
			let mockParameters = declaration.properties.map { "\($0.label): \(parameterType($0.type))" }.joined(separator: ", ")
			let mockArguments = declaration.properties.map { "\($0.label): \($0.label)" }.joined(separator: ", ")
			lines += ["", "\t\(rendering.modifier(access))static func customMock(\(mockParameters)) -> \(declaration.name) {", "\t\t\(declaration.name)(\(mockArguments))", "\t}"]
		}
		lines.append("}")
		return lines.joined(separator: "\n")
	}
}

// MARK: - Oracles

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension GraphFuzzerToolRuns {
	/// The failure of a `generateMockPublic` graph whose two paths disagree about accepting it, or `nil`: the tool rejects
	/// the graph as drawn with an error that is not a public mock's own (`GraphFuzzerOracle.isPublicMockOnlyRejection`)
	/// and accepts its known-right path, or accepts the graph and rejects its known-right path. A public mock's own error
	/// is what the public mock's rules reject that inlining accepts; any other rejection only the drawn path makes is a
	/// shape the public mock world sees differently than the known-right path, a defect, or – before the public mock
	/// lands – the inlining a consumer cannot construct, which `publicMockKnownIssues` lists.
	var publicMockAcceptanceFailure: GraphFuzzerFailure? {
		switch (firstOutcome, knownRightOutcome) {
		case let (.rejected(diagnostics), .accepted?):
			let features = GraphFuzzerPublicMockDraw.drawFeatures(of: fixture)
			let drawsStaleValueRead = features.isSuperset(of: [.holeLoopDeclaresContextAgain, .holeFillReceivesField, .consumerReachesHoleTypeWithFill])
			guard !GraphFuzzerOracle.isPublicMockOnlyRejection(
				diagnostics: diagnostics,
				staleValueLoopTypeName: drawsStaleValueRead ? "\(fixture.typeNamePrefix)HoleLoop" : nil,
				sendableFunctionCarryTypeNamePrefix: features.contains(.holeFillReadsContextBoundOutsideSendableFunction) ? fixture.typeNamePrefix : nil,
			) else { return nil }
			return GraphFuzzerFailure(
				seed: fixture.seed,
				kind: .publicMockRejectsGraphKnownRightAccepts,
				details: "As drawn:\n\(diagnostics)\nThe tool accepts the known-right path.",
			)
		case let (.accepted, .rejected(diagnostics)?):
			return GraphFuzzerFailure(
				seed: fixture.seed,
				kind: .knownRightRejectsGraphPublicMockAccepts,
				details: "The tool accepts the graph as drawn, and rejects its known-right path:\n\(diagnostics)",
			)
		case (.accepted, .accepted?), (.rejected, .rejected?), (_, nil):
			return nil
		}
	}

	/// The failure of a `generateMockPublic` graph the tool accepts whose fill of `T6`'s hole reads only what `T6`'s mock
	/// binds before its tree – `holeSession` or `holeToken` on its root level (`holeFillReceivesRootLevelValue`), or the form
	/// of `holeSession` `HoleHost`'s level binds again (`holeFillReceivesFormBoundAgain`) – and anything else only from a
	/// field `T6` binds, while the consumer in the fill's module takes a builder of `T6`'s places: passing up a place whose
	/// fill reads what the single-module mock hands it, as inline builds it, where the known-right path takes no builder.
	/// `nil` for any other graph.
	var publicMockRootLevelFailure: GraphFuzzerFailure? {
		guard knownRightOutcome != nil, case let .accepted(generatedFiles, _) = firstOutcome else { return nil }
		let features = GraphFuzzerPublicMockDraw.drawFeatures(of: fixture)
		guard features.contains(.holeFillReceivesRootLevelValue) || features.contains(.holeFillReceivesFormBoundAgain) else { return nil }
		let prefix = fixture.typeNamePrefix
		// The draw declares the fill in one consumer module, whose consumer reaches `T6`.
		let fillFile = zip(fixture.fileNames, fixture.swiftFileContent).first { fileName, _ in fileName.hasSuffix("\(prefix)HoleFill.swift") }
		guard let fillModule = fillFile.flatMap({ GraphFuzzerModule(declaredIn: $0.1) }) else { return nil }
		let consumerName = "\(prefix)T\(fillModule == .samePackageCaller ? 7 : 8)"
		// A builder `mock()` takes, as a parameter on a line of its own, `<label>: @escaping (<T6>.SafeDIMockScope_…`; a field of
		// `SafeDIOverrides` that overrides `T6`'s construction spells the type inside its own.
		let builderParameter = try? NSRegularExpression(pattern: "^\\s*[A-Za-z0-9_]+: @escaping (@Sendable )?\\(\(prefix)T6\\.SafeDI(Sendable)?MockScope_")
		let passingUpFiles = generatedFiles.keys.sorted().filter { fileName in
			guard fileName == "\(consumerName)+SafeDIMock.swift" || fileName.hasSuffix("/\(consumerName)+SafeDIMock.swift"), let contents = generatedFiles[fileName] else { return false }
			var isInMockParameters = false
			return contents.split(separator: "\n").contains { line in
				if line.contains("static func mock(") {
					isInMockParameters = true
				} else if line.trimmingCharacters(in: .whitespaces).hasPrefix(") -> ") {
					isInMockParameters = false
				}
				let text = String(line)
				return isInMockParameters && builderParameter?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
			}
		}
		guard !passingUpFiles.isEmpty else { return nil }
		return GraphFuzzerFailure(
			seed: fixture.seed,
			kind: .publicMockPassesUpPlaceItsRootLevelFills,
			details: "`\(consumerName).mock` takes a builder of `\(prefix)T6`'s places, whose fill reads only what `\(prefix)T6`'s mock binds before its tree.\nThis graph:\n\(firstOutcome.description)",
		)
	}

	/// The failure of a `generateMockPublic` graph the tool accepts that draws a call of a public mock whose override member is
	/// a closure (`GraphFuzzerPublicMockDrawFeature.overrideClosureCall`), whose consumer's generated mock holds that member,
	/// `let overriddenDetail: ((…` or `let overriddenDetailBuilder: ((…`, where the call can hand the closure no builder a
	/// person writes (`overrideClosureCannotHandShapes`), or lacks it where the call can. `nil` for any other graph.
	var publicMockOverrideClosureFailure: GraphFuzzerFailure? {
		guard knownRightOutcome != nil, case let .accepted(generatedFiles, _) = firstOutcome else { return nil }
		let features = GraphFuzzerPublicMockDraw.drawFeatures(of: fixture)
		guard features.contains(.overrideClosureCall) else { return nil }
		let consumerName = "\(fixture.typeNamePrefix)OverriddenScreen"
		let member = try? NSRegularExpression(pattern: "^\\s*(public )?let overriddenDetail(Builder)?: \\(\\(", options: [.anchorsMatchLines])
		let holdsMember = generatedFiles.keys.sorted().contains { fileName in
			guard fileName == "\(consumerName)+SafeDIMock.swift" || fileName.hasSuffix("/\(consumerName)+SafeDIMock.swift"), let contents = generatedFiles[fileName] else { return false }
			return member?.firstMatch(in: contents, range: NSRange(contents.startIndex..., in: contents)) != nil
		}
		let canHand = features.isDisjoint(with: GraphFuzzerPublicMockDrawFeature.overrideClosureCannotHandShapes)
		guard holdsMember != canHand else { return nil }
		let cannotHandShapes = features.intersection(GraphFuzzerPublicMockDrawFeature.overrideClosureCannotHandShapes).sorted().map(\.rawValue).joined(separator: ", ")
		return GraphFuzzerFailure(
			seed: fixture.seed,
			kind: canHand ? .publicMockDropsOverrideClosureItsCallCanHand : .publicMockOffersOverrideClosureItsCallCannotHand,
			details: canHand
				? "`\(consumerName)`'s overrides hold no closure that builds `\(fixture.typeNamePrefix)OverriddenDetail`, whose call can hand it a builder a person writes for each place.\nThis graph:\n\(firstOutcome.description)"
				: "`\(consumerName)`'s overrides hold a closure that builds `\(fixture.typeNamePrefix)OverriddenDetail`, whose call can hand it no builder a person writes (\(cannotHandShapes)).\nThis graph:\n\(firstOutcome.description)",
		)
	}

	/// The failure of a `generateMockPublic` graph the tool accepts that draws a holder of a place declared before a sibling
	/// (`GraphFuzzerPublicMockDrawFeature.carrierBeforeSibling`), whose `CarrierHome` `SafeDIOverrides`, or whose
	/// `CarrierShelf` module-level configuration where `CarrierShelf` declares the holder, takes the holder and its siblings
	/// in another order than their declaration: the order the internal mock takes them in, whatever order the public mock
	/// builds them in (the contract's rule 7); or, where `CarrierLocal`'s internal mock configures `CarrierShelf` too, whose
	/// internal `SafeDIMockConfiguration` does. `nil` for any other graph. With `ScopeGenerator.inlineOrdered(_:property:)` returning
	/// its nodes in build order, the holder last, seeds 17, 22, 24, 57, 89, 186 and 246 fail.
	var publicMockOverridesOrderFailure: GraphFuzzerFailure? {
		guard knownRightOutcome != nil, case let .accepted(generatedFiles, _) = firstOutcome else { return nil }
		let prefix = fixture.typeNamePrefix
		let types = GraphFuzzerPublicMockDraw.DeclaredTypes(of: fixture)
		guard let declaredLabels = GraphFuzzerPublicMockDraw.carrierBeforeSiblingDeclaredLabels(in: types, prefix: prefix) else { return nil }
		// The struct whose initializer takes the three: the module-level configuration of `CarrierShelf`, or the overrides
		// `CarrierHome`'s extension declares.
		// The structs whose initializers take the three: the module-level configuration of `CarrierShelf`, and its internal
		// configuration where `CarrierLocal`'s internal mock configures it too, or the overrides `CarrierHome`'s extension
		// declares.
		var structs: [(name: String, opening: String, structOpening: String?)] = if types.declarations["\(prefix)CarrierShelf"] != nil {
			[("`\(prefix)CarrierShelf`'s module-level configuration", "_\(prefix)CarrierShelf_MockConfiguration {", nil)]
		} else {
			[("`\(prefix)CarrierHome`'s `SafeDIOverrides`", "extension \(prefix)CarrierHome {", "struct SafeDIOverrides")]
		}
		if types.declarations["\(prefix)CarrierLocal"] != nil {
			structs.append(("`\(prefix)CarrierShelf`'s `SafeDIMockConfiguration`", "extension \(prefix)CarrierShelf {", "struct SafeDIMockConfiguration"))
		}
		var problems = [String]()
		for (structName, opening, structOpening) in structs {
			let takenLabels = generatedFiles.keys.sorted().lazy.compactMap { fileName in
				generatedFiles[fileName].flatMap { GraphFuzzerOracle.initializerLabels(after: opening, struct: structOpening, in: $0) }
			}.first
			if let takenLabels {
				let takenDeclaredLabels = takenLabels.filter(declaredLabels.contains)
				if takenDeclaredLabels != declaredLabels {
					problems.append("\(structName) takes \(takenDeclaredLabels.joined(separator: ", ")), where its type declares \(declaredLabels.joined(separator: ", ")).")
				}
			} else {
				problems.append("No generated file declares \(structName).")
			}
		}
		guard !problems.isEmpty else { return nil }
		return GraphFuzzerFailure(
			seed: fixture.seed,
			kind: .publicMockOverridesFollowBuildOrder,
			details: "\(problems.joined(separator: "\n"))\nThis graph:\n\(firstOutcome.description)",
		)
	}

	/// The failure of a `generateMockPublic` graph the tool accepts that generates a `public` or `package` declaration
	/// naming a type narrower than the declaration, by the access the generator gave the type
	/// (`GraphFuzzerGenerator.narrowerTypeAccess`), or `nil`.
	var publicMockAccessFailure: GraphFuzzerFailure? {
		guard knownRightOutcome != nil, case let .accepted(generatedFiles, _) = firstOutcome else { return nil }
		let findings = GraphFuzzerOracle.declarationsWiderThanNamedTypes(
			in: generatedFiles,
			typeAccess: GraphFuzzerGenerator.narrowerTypeAccess(forSeed: fixture.seed, features: [.generateMockPublic]),
		)
		guard !findings.isEmpty else { return nil }
		return GraphFuzzerFailure(seed: fixture.seed, kind: .publicMockDeclarationWiderThanNamedType, details: "\(findings.joined(separator: "\n"))\nThis graph:\n\(firstOutcome.description)")
	}
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension GraphFuzzerOracle {
	/// What each of a public mock's own errors says, which a `generateMockPublic` graph's drawn path may report where its
	/// known-right path accepts the graph: a required parameter the public tier cannot take
	/// (`publicTierOmitsRequiredParameter`); a `.public` type an enclosing type narrower than `public` holds; a value a
	/// consumer provides that the tier of the public mock it calls omits (`leafTierOmitsProvidedValue`: "`X` provides `p:
	/// P`, but the `package` mock SafeDI generated for …", or "…, but no mock SafeDI generated for …" when a call in the
	/// mock's tree omits it); a public mock its caller's mock condition does not reach; a hand-written `mock` beside a
	/// generated public one; and a public mock a view of its declaring module cannot call
	/// (`publicMockNotCallableFromThisView`).
	static let publicMockOnlyErrorMarkers = [
		"SafeDI cannot generate the public mock of `",
		"` cannot have a public mock because `",
		"` mock SafeDI generated for ",
		", but no mock SafeDI generated for ",
		".mock()` is generated under ",
		"` has a public `mock()` generated by ",
		"` has a public `mock()`, but ",
	]

	/// What the error says that a mock reports for a fill of a public mock's hole that reads a value a cycle around the
	/// hole declares again (`declarationBoundOnCycleReentry`), as a tree that fills a seam's reports it: inline, the
	/// fill reads the nearest level's value, so only a graph that draws that read may report it
	/// (`GraphFuzzerPublicMockDrawFeature.holeLoopDeclaresContextAgain`).
	static let publicMockStaleValueErrorMarker = "the same values at every level of that cycle"

	/// The labels of the first initializer of a struct in `contents`, a generated file, in the order it takes them: the
	/// struct whose declaration line ends with `opening`, or, where `structOpening` is given, the first struct after it, and
	/// before any other extension, whose declaration line contains `structOpening`. `nil` where `contents` declares no such
	/// struct.
	static func initializerLabels(after opening: String, struct structOpening: String?, in contents: String) -> [String]? {
		var lines = contents.split(separator: "\n", omittingEmptySubsequences: false).lazy.map { $0.trimmingCharacters(in: .whitespaces) }.makeIterator()
		var expectsStruct = structOpening != nil
		var foundOpening = false
		while let line = lines.next() {
			if !foundOpening {
				foundOpening = line.hasSuffix(opening)
			} else if expectsStruct, line.hasPrefix("extension ") {
				// Another extension, of this type or another, before the struct: look for the struct after the opening again.
				foundOpening = line.hasSuffix(opening)
			} else if expectsStruct, let structOpening {
				expectsStruct = !line.contains(structOpening)
			} else if line.hasSuffix("init(") {
				var labels = [String]()
				while let parameter = lines.next(), !parameter.hasPrefix(")") {
					labels.append(String(parameter.prefix { $0 != ":" }))
				}
				return labels
			}
		}
		return nil
	}

	/// What the error says that a tree filling a seam's place inside a `@Sendable` function reports for a fill that reads a
	/// value the seam's tree declares outside that function (`boundOutsideSendableFunction`), which a calling mock reports as
	/// its production twin does (contract rule 7): inline, and in a consumer that builds the public mock's type inline, the
	/// fill reads the value its caller declares, so only a graph drawing seed 157's shape may report it
	/// (`GraphFuzzerPublicMockDrawFeature.holeFillReadsContextBoundOutsideSendableFunction`).
	static let publicMockSendableFunctionCarryErrorMarker = "only what that function binds"

	/// Whether every error in `diagnostics`, a rejection of a `generateMockPublic` graph as drawn, is one of a public
	/// mock's own (`publicMockOnlyErrorMarkers`); where `staleValueLoopTypeName` names the graph's `HoleLoop`, the error of
	/// a fill reading the `holeContext` that type declares again (`publicMockStaleValueErrorMarker`); or, where
	/// `sendableFunctionCarryTypeNamePrefix` is the graph's type name prefix, the error of a fill reading the `holeContext`
	/// its `T6` declares outside the `@Sendable` function that builds `holeHost: SendableLazilyInstantiated<HoleHost>`
	/// (`publicMockSendableFunctionCarryErrorMarker`).
	static func isPublicMockOnlyRejection(diagnostics: String, staleValueLoopTypeName: String? = nil, sendableFunctionCarryTypeNamePrefix: String? = nil) -> Bool {
		let errors = diagnostics.split(separator: "\n").filter { $0.contains(": error: ") }
		return !errors.isEmpty && errors.allSatisfy { error in
			if publicMockOnlyErrorMarkers.contains(where: { error.contains($0) }) {
				true
			} else if let staleValueLoopTypeName, error.contains(publicMockStaleValueErrorMarker) {
				error.contains("receives `holeContext: ") && error.contains("`\(staleValueLoopTypeName)`")
			} else if let prefix = sendableFunctionCarryTypeNamePrefix, error.contains(publicMockSendableFunctionCarryErrorMarker) {
				error.contains("receives `holeContext: \(prefix)HoleContext`, which `\(prefix)T6` declares outside the `@Sendable` function that builds `holeHost: SendableLazilyInstantiated<\(prefix)HoleHost>`")
			} else {
				false
			}
		}
	}

	/// The value differential of a `generateMockPublic` graph the tool accepts as drawn and as its known-right path, or
	/// `nil` for any other graph: the feature path is the graph as drawn with the files the tool generated for it, the
	/// known-right path the graph with every declaration `public` and every `.public` mock `true`, with its own files,
	/// each drawn storing every parameter, which changes nothing the tool generates; the probes are every generated
	/// mock that takes no required parameter, each `.public` type's and each consumer's. `valueFailures` exempts the
	/// stated divergences it derives from the graph's leaf calls (`statedPublicMockValueDivergences(in:of:)`).
	/// - Parameter judgesRetention: Whether the probes also judge what each wrapper of their value keeps alive once the
	///   value is released, as for a graph with a hole.
	static func publicMockValueGraph(of runs: GraphFuzzerToolRuns, judgesRetention: Bool = false) -> DifferentialValueGraph? {
		guard case let .accepted(featureFiles, _) = runs.firstOutcome, case let .accepted(knownRightFiles, _) = runs.knownRightOutcome else { return nil }
		let storingFixture = GraphFuzzerGenerator.fixture(forSeed: runs.fixture.seed, features: [.generateMockPublic], storingEveryParameter: true)
		let knownRightFixture = GraphFuzzerGenerator.knownRightPublicMockFixture(forSeed: runs.fixture.seed, storingEveryParameter: true)
		return DifferentialValueGraph(
			name: "seed \(runs.fixture.seed)",
			feature: DifferentialValuePath(fixture: storingFixture, generatedFiles: featureFiles),
			knownRight: DifferentialValuePath(fixture: knownRightFixture, generatedFiles: knownRightFiles),
			probes: storingFixture.differentialValueProbes(generatedFiles: featureFiles),
			samples: storingFixture.placeInFillInnerScreenSamples,
			judgesRetention: judgesRetention,
		)
	}

	/// The differences of `comparison`, a `generateMockPublic` graph's, that are the shape matrix's two stated divergences,
	/// each derived from a leaf call – a call of a `.public` type's mock (`<prefix>T<i>.mock(` or `<prefix>PromoteNode.mock(`,
	/// or `.__safeDI_mock(`; `leafCalls(ofMockedType:in:prefix:)`) in the generated mock of the probe's type, read from the
	/// graph's generated code – rather than from the difference's text alone, so that any other value a leaf call builds
	/// still fails:
	/// - M8.32 (`isEarlyReadHeldInstance`): a leaf call that passes `<label>.instance` of a lazily instantiated dependency
	///   its caller holds reads that instance before the probe's value is built. The leaf wraps the instance again, a
	///   second wrapper where the known-right path shares the caller's, which the comparator compares by its instance, so
	///   the re-made wrapper over the caller's instance agrees and one over another instance differs at that instance.
	///   It also covers a called mock that takes the value as a plain `x: T` or `x: T? = nil`, which is API: the instance
	///   is then created at the call, before a called tree that reads it only behind an instantiator would create it. A
	///   deliberate gap, the other site of which is the call's construction in `ScopeGenerator` (`public-mock-builders.md`).
	/// - A dependency the calling tree does not provide, which includes one its module cannot name, is built by each call
	///   of a public mock that builds it, and is `nil` in one that receives it only if available (`isInstancePerLeafCall`,
	///   M8.9b widened): a dependency a leaf's tree receives
	///   that no leaf call on either path passes – a call passing `nil`, nothing, or the calling mock's own parameter that
	///   defaults to `nil` and that no binding of its mock shadows passes nothing for the parameterless probe – and that no
	///   declaration of the caller's tree, the probe's type or the type its `Sendable` wrapper builds, holds, so each call
	///   builds an instance of its own where the known-right path's caller builds one and shares it: the node of a later
	///   build is exempt where the known-right path's first sight of it is inside a leaf call too.
	static func statedPublicMockValueDivergences(in comparison: DifferentialValueComparison, of runs: GraphFuzzerToolRuns) -> [DifferentialValueDifference] {
		guard case let .accepted(generatedFiles, _) = runs.firstOutcome else { return [] }
		let prefix = runs.fixture.typeNamePrefix
		let types = GraphFuzzerPublicMockDraw.DeclaredTypes(of: runs.fixture)
		let onlyIfAvailableLabels = Set(types.declarations.values.flatMap { $0.properties.filter { $0.attribute == "@Received(onlyIfAvailable: true)" }.map(\.label) })
		return comparison.differences.filter { difference in
			guard difference.probe.hasSuffix(".mock()") else { return false }
			let mockedType = String(difference.probe.dropLast(".mock()".count))
			let calls = leafCalls(ofMockedType: mockedType, in: generatedFiles, prefix: prefix)
			guard !calls.isEmpty else { return false }
			let callerLabels = Set([mockedType, "\(prefix)T9"].flatMap { types.declarations[$0]?.properties.map(\.label) ?? [] })
			return isEarlyReadHeldInstance(difference, calls: calls, featureDescription: comparison.featureDescription)
				|| isInstancePerLeafCall(difference, calls: calls, callerLabels: callerLabels, onlyIfAvailableLabels: onlyIfAvailableLabels)
		}
	}

	/// A call, in a mocked type's generated mock, of a `.public` type's mock: the label the leaf is held under (`t<i>`,
	/// `anyT<i>` for a leaf held through its eraser, whose call the eraser wraps, or `promoteNode`), the labels it passes a
	/// value – anything but `nil` or the calling mock's own parameter that defaults to `nil` and that no binding of the mock
	/// shadows – and those it passes a wrapper's `.instance`.
	struct PublicMockLeafCall: Equatable {
		let leafLabel: String
		let passedLabels: Set<String>
		let instanceLabels: Set<String>
	}

	/// Each call of a `.public` type's mock – `<prefix>T0` to `<prefix>T2` and `<prefix>T6`, held under `t0` to `t2` and
	/// `t6`, or under `anyT<i>` through an eraser, `<prefix>T6Twin`, held under `t6Twin`, and `<prefix>PromoteNode`, held
	/// under `promoteNode`, whose mock a consumer that can build the `PromoteOther` it promotes hands that instance
	/// (`drawPromotedHolePublicMock`) – in the generated mock of `typeName`, in any module: of its `mock(`, or of the
	/// function only generated code calls, `__safeDI_mock(`, which a call of a mock that takes builders makes. A consumer
	/// holds each leaf it reaches under one label, so a mock wraps either every call of a leaf in the leaf's eraser or none,
	/// but for `T6`'s second label, `t6Second` (D530-1): a call of `T6`'s mock inside the builder function the mock declares
	/// for that label, `__safeDI_t6Second()`, is the leaf held under it.
	static func leafCalls(ofMockedType typeName: String, in generatedFiles: [String: String], prefix: String) -> [PublicMockLeafCall] {
		let leaves = [0, 1, 2, 6].map { PublicMockLeaf(typeName: "\(prefix)T\($0)", label: "t\($0)", eraser: (typeName: "\(prefix)AnyT\($0)", label: "anyT\($0)")) }
			+ [
				PublicMockLeaf(typeName: "\(prefix)T6Twin", label: "t6Twin", eraser: nil),
				PublicMockLeaf(typeName: "\(prefix)PromoteNode", label: "promoteNode", eraser: nil),
			]
		var calls = [PublicMockLeafCall]()
		for (fileName, contents) in generatedFiles.sorted(by: { $0.key < $1.key }) where fileName == "\(typeName)+SafeDIMock.swift" || fileName.hasSuffix("/\(typeName)+SafeDIMock.swift") {
			// The calling mock's own parameters that default to `nil`, which the parameterless probe leaves `nil`, unless a
			// binding of the same name in the mock shadows one.
			let boundNames = Set((try? NSRegularExpression(pattern: #"\blet ([A-Za-z_][A-Za-z0-9_]*) ="#)).map { expression in
				expression.matches(in: contents, range: NSRange(contents.startIndex..., in: contents)).compactMap { Range($0.range(at: 1), in: contents).map { String(contents[$0]) } }
			} ?? [])
			let unpassedParameters = mockParametersDefaultingToNil(in: contents).subtracting(boundNames)
			for leaf in leaves {
				let mockFunctionNames = ["mock", "__safeDI_mock"]
				let erasedLabel = leaf.eraser.flatMap { eraser in
					mockFunctionNames.contains { contents.contains("\(eraser.typeName)(\(leaf.typeName).\($0)(") } ? eraser.label : nil
				}
				// `T6` held under its second label is built in a builder function of its own, whose calls are that leaf's.
				let secondLabelBodies = leaf.label == "t6" ? functionBodies(named: "__safeDI_t6Second", in: contents) : (bodies: [], remainder: contents)
				let regions = [(label: erasedLabel ?? leaf.label, contents: secondLabelBodies.remainder)]
					+ secondLabelBodies.bodies.map { (label: "t6Second", contents: $0) }
				for region in regions {
					for mockFunctionName in mockFunctionNames {
						for call in initializerCalls(of: "\(leaf.typeName).\(mockFunctionName)", in: region.contents) {
							let arguments = call.filter { $0.label != "safeDIOverrides" }
							calls.append(PublicMockLeafCall(
								leafLabel: region.label,
								passedLabels: Set(arguments.filter { $0.value != "nil" && !unpassedParameters.contains($0.value) }.map(\.label)),
								instanceLabels: Set(arguments.filter { $0.value.hasSuffix(".instance") }.map(\.label)),
							))
						}
					}
				}
			}
		}
		return calls
	}

	/// The bodies of every function named `name` that `contents` declares, braces matched, and `contents` without them.
	private static func functionBodies(named name: String, in contents: String) -> (bodies: [String], remainder: String) {
		var bodies = [String]()
		var remainder = ""
		var searchStart = contents.startIndex
		while let declaration = contents.range(of: "func \(name)(", range: searchStart..<contents.endIndex),
		      let open = contents[declaration.upperBound...].firstIndex(of: "{")
		{
			var depth = 1
			var end = contents.index(after: open)
			while depth > 0, end < contents.endIndex {
				switch contents[end] {
				case "{": depth += 1
				case "}": depth -= 1
				default: break
				}
				end = contents.index(after: end)
			}
			remainder += contents[searchStart..<declaration.lowerBound]
			bodies.append(String(contents[open..<end]))
			searchStart = end
		}
		remainder += contents[searchStart...]
		return (bodies, remainder)
	}

	/// A `.public` type whose mock's calls are leaf calls: its name, the label a consumer holds it under, and, where the draw
	/// has a consumer wrap it in an eraser, the eraser's name and the label a consumer holds the erased leaf under.
	private struct PublicMockLeaf {
		let typeName: String
		let label: String
		let eraser: (typeName: String, label: String)?
	}

	/// The names of the parameters that default to `nil` of every `static func mock(` that `contents` declares.
	private static func mockParametersDefaultingToNil(in contents: String) -> Set<String> {
		var names = Set<String>()
		var searchStart = contents.startIndex
		while let declaration = contents.range(of: "static func mock(", range: searchStart..<contents.endIndex) {
			searchStart = declaration.upperBound
			var depth = 1
			var end = declaration.upperBound
			while depth > 0, end < contents.endIndex {
				switch contents[end] {
				case "(": depth += 1
				case ")": depth -= 1
				default: break
				}
				end = contents.index(after: end)
			}
			for parameter in topLevelParameters(String(contents[declaration.upperBound..<contents.index(before: end)])) {
				let trimmed = parameter.trimmingCharacters(in: .whitespacesAndNewlines)
				guard trimmed.hasSuffix("= nil"), let colon = trimmed.firstIndex(of: ":") else { continue }
				names.insert(trimmed[..<colon].trimmingCharacters(in: .whitespaces))
			}
		}
		return names
	}

	/// The components of a described path (`<1> Screen > t0 > analytics`).
	private static func components(of path: String) -> [String] {
		path.components(separatedBy: " > ")
	}

	/// The first of `text`'s captures of `pattern`, matched whole, or `nil`.
	private static func captures(of pattern: String, in text: String) -> [String]? {
		guard let expression = try? NSRegularExpression(pattern: "^" + pattern + "$"),
		      let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
		else { return nil }
		return (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: text).map { String(text[$0]) } }
	}

	/// M8.32's early read: a wrapper's instance built before the probe's value on the feature path alone, the wrapper being
	/// one of a label a leaf call passes as `.instance`, of the instance's type.
	private static func isEarlyReadHeldInstance(_ difference: DifferentialValueDifference, calls: [PublicMockLeafCall], featureDescription: String) -> Bool {
		// The wrapper is the one the feature line names: a difference before it can renumber the known-right side.
		guard difference.path.count == 1,
		      captures(of: #"<(\d+)>\.instance"#, in: difference.path[0]) != nil,
		      let featureLine = captures(of: #"<(\d+)>\.instance: <\d+> ([^ ]+) \(built before the probe's value\)(.*)"#, in: difference.feature),
		      let knownRight = captures(of: #"<\d+>\.instance: <\d+> ([^ ]+)(.*)"#, in: difference.knownRight),
		      featureLine[1] == knownRight[0],
		      (featureLine.count > 2 ? featureLine[2] : "") == (knownRight.count > 1 ? knownRight[1] : ""),
		      let section = probeSection(named: difference.probe, in: featureDescription)
		else { return false }
		let wrapper = featureLine[0]
		let feature = Array(featureLine.dropFirst())
		let instanceLabels = calls.reduce(into: Set<String>()) { $0.formUnion($1.instanceLabels) }
		return section.contains { line in
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			return instanceLabels.contains { label in
				trimmed.hasPrefix("\(label): <\(wrapper)> LazilyInstantiated<\(feature[0])>") || trimmed.hasPrefix("\(label): <\(wrapper)> SendableLazilyInstantiated<\(feature[0])>")
			}
		}
	}

	/// M8.9b's instance per call: a node of `label` that no declaration of the caller's tree holds, and that lies in leaves
	/// no call of which passes `label`, which is fresh on the feature path and shared on the known-right path with a node
	/// in such leaves too – or `nil` on the feature path where the known-right path holds an instance, the receive being
	/// only if available (`onlyIfAvailableLabels`) – since each call builds what it requires and nothing for what it
	/// receives only if available.
	private static func isInstancePerLeafCall(_ difference: DifferentialValueDifference, calls: [PublicMockLeafCall], callerLabels: Set<String>, onlyIfAvailableLabels: Set<String>) -> Bool {
		guard let label = difference.path.last, !callerLabels.contains(label) else { return false }
		func leafLabels(on path: [String]) -> [String] {
			path.dropLast().filter { component in calls.contains { $0.leafLabel == component } }
		}
		func noCallPasses(_ leafLabels: [String]) -> Bool {
			leafLabels.allSatisfy { leafLabel in calls.filter { $0.leafLabel == leafLabel }.allSatisfy { !$0.passedLabels.contains(label) } }
		}
		if difference.feature == "\(label): nil" {
			// The only-if-available receive of one call, `nil`, where the known-right path hands it an instance – the one it
			// first met here, or one met first in another leaf no call of which passes `label`.
			guard onlyIfAvailableLabels.contains(label),
			      let knownRight = captures(of: NSRegularExpression.escapedPattern(for: label) + #": <\d+> ([^ ()]+)(?: \(seen, first at (.+)\))?"#, in: difference.knownRight)
			else { return false }
			let nodeLeaves = leafLabels(on: difference.path)
			let firstSightLeaves = knownRight.count > 1 ? leafLabels(on: components(of: knownRight[1])) : nodeLeaves
			return !nodeLeaves.isEmpty && !firstSightLeaves.isEmpty && noCallPasses(nodeLeaves + firstSightLeaves)
		}
		guard let feature = captures(of: NSRegularExpression.escapedPattern(for: label) + #": <\d+> ([^ ()]+)"#, in: difference.feature),
		      let knownRight = captures(of: NSRegularExpression.escapedPattern(for: label) + #": <\d+> ([^ ()]+) \(seen, first at (.+)\)"#, in: difference.knownRight),
		      feature[0] == knownRight[0],
		      components(of: knownRight[1]).last == label
		else { return false }
		let nodeLeaves = leafLabels(on: difference.path)
		let firstSightLeaves = leafLabels(on: components(of: knownRight[1]))
		return !nodeLeaves.isEmpty && !firstSightLeaves.isEmpty && noCallPasses(nodeLeaves + firstSightLeaves)
	}

	/// The lines of the probe `probe` in a path's description: from its `probe <expression>` line to the next probe's.
	private static func probeSection(named probe: String, in description: String) -> [Substring]? {
		let lines = description.split(separator: "\n", omittingEmptySubsequences: false)
		guard let start = lines.firstIndex(of: "probe \(probe)") else { return nil }
		let end = lines[(start + 1)...].firstIndex { $0.hasPrefix("probe ") } ?? lines.endIndex
		return Array(lines[(start + 1)..<end])
	}

	/// Each `public` or `package` declaration in `generatedFiles` – a mock tier, an override's or a configuration's
	/// member or initializer, a provider – that names a type narrower than itself, by `typeAccess` – the access of each
	/// type narrower than `public`, by the name its fixture spells it with – as a line naming the file, the declaration
	/// and the type. A declaration runs from its modifier to its body's `{` or the end of its line, across the lines a
	/// parameter list spans; every type `typeAccess` does not name is `public`.
	static func declarationsWiderThanNamedTypes(in generatedFiles: [String: String], typeAccess: [String: GraphFuzzerGenerator.AccessLevel]) -> [String] {
		var findings = [String]()
		for (fileName, contents) in generatedFiles.sorted(by: { $0.key < $1.key }) where !fileName.hasSuffix("Caller.swift") {
			let lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
			var index = 0
			while index < lines.count {
				let line = lines[index]
				index += 1
				let words = line.split(separator: " ")
				guard let modifierIndex = words.firstIndex(where: { $0 == "public" || $0 == "package" || $0 == "open" }),
				      words[..<modifierIndex].allSatisfy({ $0.hasPrefix("@") || $0 == "nonisolated" || $0 == "static" })
				else { continue }
				let declarationAccess = accessLevel(spelled: String(words[modifierIndex]))
				// The declaration: its first line, and the lines its parentheses span.
				var declaration = line
				var depth = line.filter { $0 == "(" }.count - line.filter { $0 == ")" }.count
				while depth > 0, index < lines.count {
					declaration += " " + lines[index]
					depth += lines[index].filter { $0 == "(" }.count - lines[index].filter { $0 == ")" }.count
					index += 1
				}
				if let body = declaration.range(of: " {", options: .backwards), declaration.hasSuffix("{") || declaration.hasSuffix("{}") {
					declaration = String(declaration[..<body.lowerBound])
				}
				// Swift checks the names in a default argument's value against the declaration's access only for a `public`
				// declaration, whose default arguments other modules' code evaluates; a `package` declaration's are
				// evaluated in its own module, so they may name an `internal` type.
				let checkedText = declarationAccess == .package ? withoutDefaultValues(declaration) : declaration
				for name in qualifiedNames(in: checkedText) {
					guard let level = typeAccess[name], level < declarationAccess else { continue }
					findings.append("\(fileName): `\(declaration)` is `\(declarationAccess.spelling)`, but `\(name)` is `\(level.spelling)`.")
				}
			}
		}
		return findings
	}

	/// `declaration` without the value of each default argument of its parameter list: everything from a ` = ` inside
	/// the list to the `,` or `)` that ends the parameter.
	private static func withoutDefaultValues(_ declaration: String) -> String {
		var result = ""
		var depth = 0
		var skippingDepth: Int?
		var characters = Array(declaration)[...]
		while let character = characters.popFirst() {
			if let skipping = skippingDepth {
				if character == "(" {
					depth += 1
				} else if character == ")" {
					depth -= 1
					if depth < skipping {
						skippingDepth = nil
						result.append(character)
					}
				} else if character == ",", depth == skipping {
					skippingDepth = nil
					result.append(character)
				}
				continue
			}
			if character == "(" {
				depth += 1
			} else if character == ")" {
				depth -= 1
			} else if character == "=", depth > 0, result.hasSuffix(" "), characters.first == " " {
				skippingDepth = depth
				continue
			}
			result.append(character)
		}
		return result
	}

	/// Each name `text` spells, and every qualified prefix of a nested one: `A.B.C` is `A`, `A.B`, and `A.B.C`.
	private static func qualifiedNames(in text: String) -> [String] {
		var names = [String]()
		var name = ""
		func flush() {
			guard !name.isEmpty else { return }
			let components = name.split(separator: ".")
			for count in 1...components.count {
				names.append(components.prefix(count).joined(separator: "."))
			}
			name = ""
		}
		for character in text {
			if character.isLetter || character.isNumber || character == "_" || character == "." {
				name.append(character)
			} else {
				flush()
			}
		}
		flush()
		return names
	}
}

// MARK: - Reading a graph

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension GraphFuzzerPublicMockDraw {
	/// The shapes drawn in `fixture`, read from its source: the module each file names, the `@Instantiable` declarations
	/// and their properties and initializers, and the lines of the files that declare no `@Instantiable` type.
	static func drawFeatures(of fixture: GraphFuzzerFixture) -> Set<GraphFuzzerPublicMockDrawFeature> {
		let prefix = fixture.typeNamePrefix
		let types = DeclaredTypes(of: fixture)
		var features = Set<GraphFuzzerPublicMockDrawFeature>()
		let modules = Set(fixture.modules ?? [])
		if modules.contains(.samePackageCaller), modules.contains(.otherPackageCaller) {
			features.insert(.bothConsumerModules)
		} else if modules.contains(.samePackageCaller) {
			features.insert(.samePackageConsumerModuleOnly)
		} else if modules.contains(.otherPackageCaller) {
			features.insert(.otherPackageConsumerModuleOnly)
		}
		let seamDependencyDraw = GraphFuzzerSeamDependencyDraw.drawn(in: fixture)
		if seamDependencyDraw.movesDeclaration {
			features.insert(.seamDependency)
		}
		if seamDependencyDraw.drawsChain {
			features.insert(.seamDependencyChain)
		}
		if fixture.swiftFileContent.contains(where: { $0.contains("enum \(prefix)Space {}") && !$0.contains("@Instantiable") }) {
			features.insert(.namespaceInMarkerFreeFile)
		}
		if fixture.swiftFileContent.contains(where: { $0.contains("package enum \(prefix)Dock {}") }) {
			features.insert(.dockPackage)
		}
		if fixture.swiftFileContent.contains(where: { $0.contains("#if canImport(Foundation)\npublic enum \(prefix)Dock {}") }) {
			features.insert(.dockInsidePlatformBlock)
		}
		let leafNames = (0...2).map { "\(prefix)T\($0)" }.filter { types.declarations[$0] != nil }
		switch leafNames.count {
		case 1: features.insert(.onePublicMockType)
		case 2: features.insert(.twoPublicMockTypes)
		case 3: features.insert(.threePublicMockTypes)
		default: break
		}
		let childNames = (3...5).map { "\(prefix)T\($0)" }.filter { types.declarations[$0] != nil }
		let consumerNames = (7...9).map { "\(prefix)T\($0)" }.filter { types.declarations[$0] != nil }
		let treeNames = leafNames + childNames
		/// The leaf a consumer's property reaches: its type, or the type its erasure names.
		func reachedLeaf(_ property: (attribute: String, label: String, type: String)) -> String? {
			leafNames.contains(property.type) ? property.type : leafNames.first { property.attribute.contains("fulfilledByType: \"\($0)\"") }
		}
		for leafName in leafNames {
			switch types.declarations[leafName]?.initializerAccess {
			case "package": features.insert(.packageInitializer)
			case "internal": features.insert(.internalInitializer)
			default: break
			}
			if types.declarations[leafName]?.arguments.contains("customMockName: \"customMock\"") == true {
				features.insert(.customMockName)
			}
			if let leaf = types.declarations[leafName], leaf.takesOwnOptionalDefaultOnNonisolatedTypeThatBuilds {
				features.insert(.ownOptionalDefaultOnNonisolatedTypeThatBuilds)
			}
		}
		for childName in childNames {
			guard let child = types.declarations[childName] else { continue }
			if child.access != "public" {
				features.insert(.narrowerTreeType)
			}
			if child.isMainActor {
				features.insert(child.initializerLine.hasPrefix("nonisolated ") ? .mainActorChildNonisolatedInitializer : .mainActorChildIsolatedInitializer)
				if child.initializerLine.hasPrefix("@MainActor ") {
					features.insert(.mainActorChildInitializerSpellsIsolation)
				}
			}
			let defaults = child.defaultParameters
			if defaults.contains(where: { $0.hasSuffix("= defaultCapacity") }) {
				features.insert(.childDefaultNamingOwnStaticMember)
			}
			if !defaults.isEmpty, defaults.allSatisfy({ $0.hasPrefix("policy: ") }) {
				features.insert(.allNonPublicConfiguration)
			}
			if child.properties.contains(where: { $0.label == "analytics" && $0.attribute == "@Received(onlyIfAvailable: true)" }) {
				features.insert(.lazilyReceivedLabelWithOnlyIfAvailableByValueReceive)
			}
		}
		for typeName in treeNames {
			guard let declaration = types.declarations[typeName] else { continue }
			for property in declaration.properties where property.attribute.hasPrefix("@Received") {
				switch property.label {
				case "session": features.insert(.instantiableParameterType)
				case "token": features.insert(.plainTypeOnlyPackageInitializersTake)
				case "badge": features.insert(.plainTypePublicInitializerTakes)
				case "count": features.insert(property.type.hasPrefix("Swift.") ? .qualifiedAllowlistedParameterType : .allowlistedParameterType)
				case let label where label.hasPrefix("unread"): features.insert(.unreadParameterType)
				case "clock": features.insert(.extensionBasedInstantiable)
				case "seal" where property.attribute == "@Received": features.insert(.requiredParameterNarrowerThanPublic)
				case "shelf":
					if types.lines.contains("extension \(prefix)Space {") {
						features.insert(.namespaceExtensionUnspelled)
					} else if types.lines.contains("public extension \(prefix)Space {") {
						features.insert(.namespaceExtensionPublic)
					} else if types.lines.contains("package extension \(prefix)Space {") {
						features.insert(.namespaceExtensionPackage)
					}
				default:
					if property.label.hasPrefix("pin") {
						features.insert(.typeInExtensionOfInstantiable)
					}
				}
			}
			for parameter in declaration.defaultParameters {
				if parameter.contains(": \(prefix)Tag? = ") {
					features.insert(.plainTypeOnlyDefaultArgumentsName)
					features.insert(.optionalDefaultOfUnprovenType)
				} else if parameter.hasPrefix("name: String? = ") {
					features.insert(.optionalDefaultOfPublicType)
				} else if parameter.hasPrefix("policy: "), leafNames.contains(typeName) {
					features.insert(.optionalDefaultOfPackageType)
				} else if parameter.hasPrefix("retries: Int = ") {
					features.insert(.nonOptionalDefault)
				} else if parameter.hasPrefix("onTap: ") {
					features.insert(.closureDefault)
				}
			}
		}
		if types.lines.contains(where: { $0.hasPrefix("@Instantiable(fulfillingAdditionalTypes: [\(prefix)Logger.self], mockOnly: true)") }) {
			features.insert(.protocolSlotFilledByFake)
			if types.lines.contains("package extension \(prefix)FakeLogger {") {
				features.insert(.fakeExtensionPackage)
			}
			if types.lines.contains(where: { $0.hasPrefix("final class \(prefix)FakeLogger:") }) {
				features.insert(.fakeTypeInternal)
			}
			if types.lines.contains(where: { $0.contains("static func mock(") && $0.contains("verbose: Bool = false") }) {
				features.insert(.fakeMockDefaultedParameter)
			}
			if types.lines.contains(where: { $0.contains("static func mock(level: ") }) {
				features.insert(.fakeMockDependencyBoundParameter)
			}
		}
		// The consumers, and the holders of what their leaves' trees receive.
		var sessionReceivers = Set<String>()
		for leafName in leafNames where types.declarations[leafName]?.properties.contains(where: { $0.label == "session" && $0.attribute == "@Received" }) == true {
			sessionReceivers.insert(leafName)
		}
		for consumerName in consumerNames {
			guard let consumer = types.declarations[consumerName] else { continue }
			if consumer.arguments.contains("generateMock: .public") {
				features.insert(.publicConsumer)
				let reachedLeaves = consumer.properties.compactMap(reachedLeaf)
				let leafTreeReceivesTheme = reachedLeaves.contains { leafName in
					let childName = types.declarations[leafName]?.properties.first { $0.attribute == "@Instantiated" && childNames.contains($0.type) }?.type
					return ([leafName] + [childName].compactMap(\.self)).contains { types.declarations[$0]?.properties.contains { $0.label == "theme" } == true }
				}
				if leafTreeReceivesTheme, !consumer.properties.contains(where: { $0.label == "theme" }) {
					features.insert(.publicConsumerLeavesLeafLabelUnprovided)
				}
			}
			if consumer.properties.contains(where: { $0.type == "SendableInstantiator<\(prefix)T9>" }) {
				features.insert(.sendableWrapperAboveLeaf)
			}
			for property in consumer.properties where reachedLeaf(property) != nil {
				features.insert(property.attribute == "@Received" ? .consumerReceivesLeaf : .consumerInstantiatesLeaf)
				if property.attribute.contains("erasedToConcreteExistential: true") {
					features.insert(
						property.type.hasPrefix("SendableErasedInstantiator<") ? .sendableErasedInstantiatorLeaf
							: property.type.hasPrefix("ErasedInstantiator<") ? .erasedInstantiatorLeaf
							: .erasedConstantLeaf,
					)
				}
			}
			if consumer.properties.contains(where: { $0.label == "analytics" && $0.type.hasPrefix("LazilyInstantiated<") && $0.attribute == "@Instantiated" }) {
				features.insert(.consumerHoldsLazilyInstantiatedWrapper)
			}
			if consumer.properties.contains(where: { $0.label == "analytics" && $0.type.hasPrefix("LazilyInstantiated<") && $0.attribute == "@Received" }) {
				features.insert(.consumerReceivesLazilyInstantiatedWrapper)
			}
			if sessionReceivers.count >= 2, consumer.properties.filter({ reachedLeaf($0).map(sessionReceivers.contains) == true }).count >= 2, consumerName != "\(prefix)T7" {
				features.insert(.twoLeavesReceiveUnnameableDependency)
			}
			let holderIndices = consumer.properties.indices.filter { consumer.properties[$0].label.hasPrefix("holder") }
			guard !holderIndices.isEmpty else { continue }
			features.insert(.consumerHoldsOmittedValue)
			if consumerName == "\(prefix)T9" {
				features.insert(.omittedValueProviderUnderSendableBuilder)
			}
			for holderIndex in holderIndices {
				let holder = consumer.properties[holderIndex]
				if holder.attribute == "@Received" {
					features.insert(.holderlessOmittedValue)
				}
				if holder.type.hasPrefix("LazilyInstantiated<") {
					features.insert(.lazilyInstantiatedOmittedValueProvider)
				}
				if let leafIndex = consumer.properties.firstIndex(where: { reachedLeaf($0) != nil }) {
					features.insert(holderIndex < leafIndex ? .omittedValueProviderBeforeLeaf : .omittedValueProviderAfterLeaf)
				}
				let holderTypeName = holder.type.hasPrefix("LazilyInstantiated<") ? String(holder.type.dropFirst("LazilyInstantiated<".count).dropLast()) : holder.type
				if types.declarations[holderTypeName.split(separator: ".").last.map(String.init) ?? holderTypeName]?.properties.contains(where: { leafNames.contains(String($0.type.dropLast())) }) == true {
					features.insert(.omittedValueProviderAndLeafReceiveEachOther)
				}
			}
		}
		// R7's hole, on `T6` or on the type `HoleHost` it instantiates beneath a wrapper or `HoleReceiver` receives, and its
		// callers.
		let holeLeafName = "\(prefix)T6"
		if let holeLeaf = types.declarations[holeLeafName] {
			let hostName = "\(prefix)HoleHost"
			let holeProperty = (holeLeaf.properties + (types.declarations[hostName]?.properties ?? [])).first { $0.label == "hole" || $0.label == "holeBuilder" }
			let receiverName = "\(prefix)HoleReceiver"
			if holeLeaf.properties.contains(where: { $0.type == receiverName }), let receivedHost = types.declarations[receiverName]?.properties.first(where: { $0.attribute == "@Received" }) {
				if receivedHost.type == hostName {
					features.insert(.holeHostReceivedByValue)
				} else {
					features.insert(receivedHost.type.hasPrefix("Sendable") ? .holeHostReceivedThroughSendableInstantiator : .holeHostReceivedThroughInstantiator)
				}
			} else if let hostProperty = holeLeaf.properties.first(where: { $0.type.hasSuffix("<\(hostName)>") }) {
				if hostProperty.type.hasPrefix("Sendable") {
					features.insert(.holeBeneathSendableWrapper)
				} else {
					features.insert(hostProperty.type.hasPrefix("Instantiator<") ? .holeBeneathInstantiator : .holeBeneathLazilyInstantiated)
				}
			} else {
				features.insert(.holeOnPublicMockType)
			}
			if let loop = types.declarations["\(prefix)HoleLoop"] {
				features.insert(.holeInsideLoop)
				if loop.properties.contains(where: { $0.label == "holeContext" }) {
					features.insert(.holeLoopDeclaresContextAgain)
				}
			}
			if holeLeaf.arguments.contains("mockAttributes: \"@MainActor\"") {
				features.insert(.holeMockIsolatedToMainActor)
			}
			if holeLeaf.arguments.contains("customMockName:"), types.declarations["\(prefix)T6Deck"]?.properties.contains(where: { $0.type == holeLeafName }) == true {
				features.insert(.holeHandWrittenMockBuiltInPublicMock)
				if let holeProperty, holeLeaf.properties.filter({ $0.attribute.hasPrefix("@Instantiated") }).map(\.label) == [holeProperty.label] {
					features.insert(.holeHandWrittenMockTakesNoOverrides)
				}
			}
			if let holeProperty {
				if holeProperty.attribute.contains("erasedToConcreteExistential: true") {
					features.insert(holeProperty.type.hasPrefix("ErasedInstantiator<") ? .holeDeclaredAsErasedInstantiator : .holeDeclaredAsErasedConstant)
					if holeProperty.type.hasPrefix("ErasedInstantiator<Int, ") {
						features.insert(.holeForwardsValue)
					}
				} else if holeProperty.type.hasPrefix("Instantiator<") {
					features.insert(.holeDeclaredAsInstantiator)
				} else if holeProperty.type.hasPrefix("any ") {
					features.insert(.holeDeclaredAsExistential)
				}
			}
			if holeLeaf.properties.contains(where: { $0.label == "session" }) {
				features.insert(.holeScopeHoldsPackageValue)
			}
			// On the root-level stream: what `T6`'s mock binds before its tree.
			let rootBindsLabelInTwoForms = holeLeaf.properties.contains { $0.label == "holeSibling" }
			if let holeSession = holeLeaf.properties.first(where: { $0.label == "holeSession" }) {
				features.insert(holeSession.type.hasPrefix("LazilyInstantiated<") ? .holeRootLevelHoldsWrapper : .holeRootLevelHoldsValues)
			} else if rootBindsLabelInTwoForms {
				features.insert(.holeRootReceivesLabelInTwoForms)
			}
			let bindsContext = holeLeaf.properties.contains { $0.label == "holeContext" }
			if bindsContext {
				features.insert(.holeScopeHoldsPublicValue)
			}
			// `T6`'s caller, not the one the shape #702 fixed draws for `SelfNode`.
			let holeLeafCall = " \(holeLeafName).mock("
			if types.lines.contains(where: { $0.hasPrefix(GraphFuzzerPublicMockDraw.publicMockCallerMarker + GraphFuzzerModule.otherPackageCaller.name + ":") && $0.contains(holeLeafCall) }) {
				features.insert(.holeCallerInOtherPackage)
			} else if types.lines.contains(where: { $0.hasPrefix(GraphFuzzerPublicMockDraw.publicMockCallerMarker + GraphFuzzerModule.samePackageCaller.name + ":") && $0.contains(holeLeafCall) }) {
				features.insert(.holeCallerInSamePackage)
			}
			// The consumer modules that reach `T6`, and the one that declares the fill.
			var reachingModules = Set<GraphFuzzerModule>()
			var fillModule: GraphFuzzerModule?
			for (fileName, content) in zip(fixture.fileNames, fixture.swiftFileContent) {
				guard let module = GraphFuzzerModule(declaredIn: content), module.isCaller else { continue }
				if content.contains(" let t6: \(holeLeafName)\n") {
					reachingModules.insert(module)
				}
				if content.contains(" let t6Second: \(holeLeafName)\n") {
					features.insert(.consumerReachesHoleTypeUnderTwoLabels)
				}
				if content.contains(" let t6Twin: \(holeLeafName)Twin\n") {
					features.insert(.consumerReachesHoleTypeThroughTwoPublicMocks)
				}
				guard fileName.hasSuffix("\(prefix)HoleFill.swift") else { continue }
				fillModule = module
				if content.contains("final class \(prefix)HoleFake: ") {
					features.insert(content.contains(" class \(prefix)HoleFill: ") ? .holeFakeBesideFill : .holeFakeAlone)
				}
				if content.contains(" let t6Builder: Instantiator<\(holeLeafName)>") {
					features.insert(.holeFillClosesLazyCycle)
				}
				if content.contains("holeExtra: ") || content.contains("holeContext: ") && !bindsContext {
					features.insert(.holeFillReceivesNonField)
				} else if content.contains("holeContext: ") {
					features.insert(.holeFillReceivesField)
				}
				if content.contains(" holeSession: ") || content.contains("(holeSession: ") || content.contains(" holeToken: ") {
					features.insert(rootBindsLabelInTwoForms ? .holeFillReceivesFormBoundAgain : .holeFillReceivesRootLevelValue)
				}
				if content.contains("holeSession: LazilyInstantiated<") {
					features.insert(.holeFillReceivesRootLevelWrapper)
				}
			}
			if let fillModule, reachingModules.contains(fillModule) {
				features.insert(.consumerReachesHoleTypeWithFill)
				// Seed 157's shape: the fill's module calls `T6`'s public mock, since it cannot reach the construction `T6`'s mock
				// uses, and the fill reads the `holeContext` `T6` binds outside the `@Sendable` function above the hole.
				let constructionAccess = if holeLeaf.arguments.contains("customMockName:") {
					types.lines.first { $0.contains("static func customMock(") && $0.hasSuffix(") -> \(holeLeafName) {") }.map { line in
						["public", "package"].first { line.hasPrefix($0 + " ") } ?? "internal"
					} ?? "internal"
				} else {
					holeLeaf.initializerAccess
				}
				let fillModuleCallsPublicMock = constructionAccess == "internal" || constructionAccess == "package" && fillModule == .otherPackageCaller
				if fillModuleCallsPublicMock,
				   features.contains(.holeFillReceivesField),
				   holeLeaf.properties.contains(where: { $0.label == "holeHost" && $0.type == "SendableLazilyInstantiated<\(hostName)>" }),
				   holeProperty?.type.hasPrefix("Instantiator<") == true,
				   let loop = types.declarations["\(prefix)HoleLoop"],
				   !loop.properties.contains(where: { $0.label == "holeContext" })
				{
					features.insert(.holeFillReadsContextBoundOutsideSendableFunction)
				}
			}
			if reachingModules.contains(where: { $0 != fillModule }) {
				features.insert(.consumerReachesHoleTypeWithoutFill)
			}
		}
		// The mock condition.
		for (fileName, content) in zip(fixture.fileNames, fixture.swiftFileContent) where content.contains("#SafeDIConfiguration(mockConditionalCompilation: nil") {
			features.insert(.mockConditionDiffers)
			if GraphFuzzerModule(declaredIn: content) == .seamModule, fileName.hasSuffix("/SafeDIConfiguration.swift") {
				features.insert(.declaringModuleConfigurationFile)
			}
		}
		// R15's spellings, and the property kinds the spelled value is drawn as.
		let forwardedByConsumers = Set(consumerNames.flatMap { types.declarations[$0]?.properties.filter { $0.attribute == "@Forwarded" }.map(\.label) ?? [] })
		for typeName in treeNames {
			guard let declaration = types.declarations[typeName] else { continue }
			for property in declaration.properties where property.label.hasPrefix("spelled") {
				if let spelling = GraphFuzzerPublicMockSpelling.spelling(ofType: property.type, prefix: prefix) {
					features.insert(spelling.drawFeature)
				}
				switch property.attribute {
				case "@Forwarded": features.insert(.spelledForwarded)
				case "@Received(onlyIfAvailable: true)": features.insert(.spelledOnlyIfAvailableReceive)
				default: features.insert(forwardedByConsumers.contains(property.label) ? .spelledConsumerPasses : .spelledRequiredReceive)
				}
			}
			for parameter in declaration.defaultParameters where parameter.hasPrefix("spelled") {
				let type = parameter.drop { $0 != ":" }.dropFirst().prefix { $0 != "=" }.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "@escaping ", with: "")
				if let spelling = GraphFuzzerPublicMockSpelling.spelling(ofType: type, prefix: prefix) {
					features.insert(spelling.drawFeature)
				}
				if childNames.contains(typeName) {
					features.insert(.spelledChildDefault)
				} else {
					features.insert(parameter.hasSuffix("= nil") ? .spelledOptionalDefault : .spelledNonOptionalDefault)
				}
			}
		}
		// The gating draws: the shape #702 fixed, and a place inside a public mock's fill.
		if let node = types.declarations["\(prefix)SelfNode"] {
			features.insert(.selfBuildingPublicMock)
			if node.properties.contains(where: { $0.label == "selfStep" }) {
				features.insert(.selfBuildingPublicMockThroughStep)
			}
			// The builder of `SelfNode`, on `SelfNode` or a type of its tree, instantiated or received.
			let builders = (["SelfNode", "SelfStep", "SelfPart", "SelfLink"].compactMap { types.declarations["\(prefix)\($0)"] }).flatMap(\.properties).filter { $0.label == "selfNodeBuilder" }
			if builders.contains(where: { $0.type.hasPrefix("SendableInstantiator<") }) {
				features.insert(.selfBuildingPublicMockThroughSendableInstantiator)
			}
			if types.declarations["\(prefix)SelfPart"]?.properties.contains(where: { $0.label == "selfApi" }) == true {
				features.insert(.selfBuildingPublicMockPlaceBeneath)
			}
			if builders.contains(where: { $0.attribute == "@Received" }) {
				features.insert(.selfBuildingPublicMockReceivesBuilder)
			}
			if let live = types.declarations["\(prefix)SelfLive"] {
				if live.properties.contains(where: { $0.label == "selfToken" }) {
					features.insert(.selfBuildingPublicMockFillReadsToken)
				}
			} else {
				features.insert(.selfBuildingPublicMockPassedUp)
			}
		}
		if let outer = types.declarations["\(prefix)PlaceInFillOuter"] {
			features.insert(.placeInsidePublicMockFill)
			if let live = types.declarations["\(prefix)PlaceInFillLive"] {
				features.insert(.placeInsidePublicMockFillFilledByConsumer)
				if live.properties.contains(where: { $0.label == "placeInFillTag" }), outer.properties.contains(where: { $0.label == "placeInFillTag" }) {
					features.insert(.placeInsidePublicMockFillReadsOuterValue)
				}
				if live.properties.contains(where: { $0.label == "placeInFillId" }) {
					features.insert(.placeInsidePublicMockFillReadsForwardedValue)
				}
			} else {
				features.insert(.placeInsidePublicMockFillPassedUp)
			}
			if types.declarations["\(prefix)PlaceInFillInnerScreen"] != nil {
				features.insert(.placeInsidePublicMockFillOnForwardingRoute)
			}
			if types.declarations["\(prefix)PlaceInFillLoopA"] != nil {
				features.insert(.placeInsidePublicMockFillHoldsLoopOfBuilders)
			}
		}
		if let keywordApp = types.declarations["\(prefix)KeywordApp"] {
			features.insert(.keywordLabeledPublicMock)
			if keywordApp.properties.contains(where: { $0.label == "keywordLocal" }) {
				features.insert(.keywordLabeledPublicMockBesideInternalConfiguration)
			}
		}
		if types.declarations["\(prefix)RetainHome"] != nil {
			features.insert(.retentionPublicMockValueBeforeBuilder)
			if types.declarations["\(prefix)RetainDetail"]?.properties.contains(where: { $0.label == "retainLeafBuilder" }) == true {
				features.insert(.retentionPublicMockValueBeforeBuilderLeafThroughInstantiator)
			}
			if types.declarations["\(prefix)RetainLive"]?.properties.contains(where: { $0.label == "retainNavigator" }) == true {
				features.insert(.retentionPublicMockValueBeforeBuilderFillReadsValue)
			}
		}
		if let firstHolder = types.declarations["\(prefix)ShareHolderA"] {
			features.insert(.sharedConstructionPublicMock)
			if fixture.swiftFileContent.contains(where: { $0.contains("extension \(prefix)ShareService: Instantiable {") }) {
				features.insert(.sharedConstructionPublicMockExtensionBased)
			}
			if fixture.swiftFileContent.contains(where: { $0.contains("let anyShareApi: \(prefix)AnyShareApi") }) {
				features.insert(.sharedConstructionPublicMockErased)
			}
			if types.declarations["\(prefix)ShareTicker"] != nil {
				features.insert(.sharedConstructionPublicMockBeneathCycleEdge)
			} else {
				if types.declarations["\(prefix)ShareHolderB"] == nil {
					features.insert(.sharedConstructionPublicMockOneHolder)
				}
				if firstHolder.properties.first?.label != "shareApi" {
					features.insert(.sharedConstructionPublicMockWithoutMockFirst)
				}
			}
			if types.declarations["\(prefix)ShareRoot"] != nil {
				features.insert(.sharedConstructionPublicMockBesideDeclaringModulesOwn)
			}
			if fixture.swiftFileContent.contains(where: { $0.hasPrefix(GraphFuzzerModule.marker + GraphFuzzerModule.seamModule.name) && $0.contains("class \(prefix)ShareHolderA:") }) {
				features.insert(.sharedConstructionPublicMockInDeclaringModule)
			}
		}
		if let detail = types.declarations["\(prefix)OverriddenDetail"], let screen = types.declarations["\(prefix)OverriddenScreen"] {
			features.insert(.overrideClosureCall)
			let live = types.declarations["\(prefix)OverriddenLive"] ?? types.declarations["\(prefix)OverriddenPlace1Live"]
			if detail.properties.contains(where: { $0.label == "overriddenApi" && $0.type.hasPrefix("ErasedInstantiator<") }) {
				features.insert(.overrideClosureCallPlaceIsErasedInstantiator)
			}
			let buildsStore = detail.properties.contains { $0.label == "overriddenStore" }
			let session = detail.properties.first { $0.label == "overriddenSession" }
			let liveReadsSession = live?.properties.contains { $0.label == "overriddenSession" } == true
			// The consumer fills a place where its production twin does, wherever its module declares the place's fill, and passes
			// it up only where it declares none (contract rule 7): a fill that reads a session `OverriddenDetail` does not receive
			// reads the one the consumer builds.
			let fillsApi = live != nil
			if !fillsApi || buildsStore && types.declarations["\(prefix)OverriddenStoreLive"] == nil {
				features.insert(screen.arguments.contains("generateMock: .public") ? .overrideClosureCallPublicCallerPassesPlaceUp : .overrideClosureCallInternalCallerPassesPlaceUp)
			}
			if fillsApi, live?.properties.contains(where: { $0.label == "overriddenStore" }) == true {
				features.insert(.overrideClosureCallFillReadsCalledMocksOtherPlace)
			}
			if fillsApi, liveReadsSession {
				if let session {
					features.insert(session.attribute.contains("fulfilledByDependencyNamed:") ? .overrideClosureCallFillReadsValueCalledMockRenames : .overrideClosureCallFillReadsCalledMocksParameter)
				} else {
					features.insert(.overrideClosureCallFillReadsConsumersValue)
				}
			}
			if features.isDisjoint(with: GraphFuzzerPublicMockDrawFeature.overrideClosureCannotHandShapes) {
				features.insert(.overrideClosureCallCanHand)
			}
		}
		if let leaf = types.declarations["\(prefix)PromoteLeaf"], let screen = types.declarations["\(prefix)PromoteScreen"] {
			features.insert(.promotedHolePublicMock)
			if leaf.properties.contains(where: { $0.type == "SendableLazilyInstantiated<\(prefix)PromoteOther>" }) {
				features.insert(.promotedHolePublicMockSendableLazily)
			} else {
				features.insert(.promotedHolePublicMockLazily)
			}
			if types.declarations["\(prefix)PromoteLive"] == nil {
				features.insert(.promotedHolePublicMockPassedUp)
			}
			if screen.arguments.contains("generateMock: .public") {
				features.insert(.promotedHolePublicMockPublicConsumer)
			}
		}
		if let node = types.declarations["\(prefix)OptionalNode"], let screen = types.declarations["\(prefix)OptionalScreen"] {
			features.insert(.optionalPlacePublicMock)
			if let leaf = types.declarations["\(prefix)OptionalLeaf"], leaf.properties.contains(where: { $0.label == "optionalApi" }) {
				features.insert(.optionalPlacePublicMockOnLeaf)
			}
			if node.properties.contains(where: { $0.type == "SendableInstantiator<\(prefix)OptionalLeaf>" }) {
				features.insert(.optionalPlacePublicMockSendably)
			}
			if types.declarations["\(prefix)OptionalReader"] != nil {
				features.insert(.optionalPlacePublicMockReceived)
			}
			if types.declarations["\(prefix)OptionalLive"] == nil {
				features.insert(.optionalPlacePublicMockPassedUp)
			}
			if screen.arguments.contains("generateMock: .public") {
				features.insert(.optionalPlacePublicMockPublicConsumer)
			}
		}
		if types.declarations["\(prefix)OuterStep"] != nil, types.declarations["\(prefix)OuterScreen"] != nil {
			features.insert(.outerFulfillerPublicMockCall)
		}
		if let cache = types.declarations["\(prefix)UnbuildableCache"], types.declarations["\(prefix)UnbuildableScreen"] != nil {
			features.insert(.unbuildableValuePublicMockCall)
			features.insert(cache.properties.contains { $0.type == "\(unreadableUnbuildableValueType)?" } ? .unbuildableValuePublicMockCallTierOmits : .unbuildableValuePublicMockCallPublicTier)
		}
		if let node = types.declarations["\(prefix)WrapNode"], let reader = types.declarations["\(prefix)WrapReader"], types.declarations["\(prefix)WrapScreen"] != nil {
			features.insert(.wrapperReadByValuePublicMock)
			if let nodeSession = node.properties.first(where: { $0.label == "wrapSession" }) {
				if nodeSession.type.contains("LazilyInstantiated<") {
					features.insert(.wrapperReadByValuePublicMockTreeReadsValue)
				} else if nodeSession.attribute == "@Received(onlyIfAvailable: true)" {
					features.insert(.wrapperReadByValuePublicMockMockedTypeReadsValueOnlyIfAvailable)
				} else {
					features.insert(.wrapperReadByValuePublicMockMockedTypeReadsValue)
				}
			}
			if (node.properties + reader.properties).contains(where: { $0.type.hasPrefix("SendableLazilyInstantiated<") }) {
				features.insert(.wrapperReadByValuePublicMockSendably)
			}
			if node.properties.contains(where: { $0.label == "wrapReaderBuilder" }) {
				features.insert(.wrapperReadByValuePublicMockReaderThroughInstantiator)
			}
		}
		if let screen = types.declarations["\(prefix)FormScreen"], types.declarations["\(prefix)FormCache"] != nil {
			features.insert(.valueFormsBesidePublicMockCall)
			let cache = types.declarations["\(prefix)FormCache"]
			if !fixture.swiftFileContent.contains(where: { $0.contains("extension \(prefix)FormSession {") }) {
				features.insert(.valueFormsBesidePublicMockCallUnbuildableValue)
			}
			if screen.arguments.contains("generateMock: .public") {
				features.insert(.valueFormsBesidePublicMockCallPublicConsumer)
			}
			if types.declarations["\(prefix)FormHolder"] != nil {
				features.insert(.valueFormsBesidePublicMockCallBeneathCycleEdge)
			}
			if cache?.properties.contains(where: { $0.type == "\(prefix)FormSession?" }) == true {
				features.insert(.valueFormsBesidePublicMockCallCalledTakesOptional)
			}
			let siblingTypes = (1...3).compactMap { types.declarations["\(prefix)FormFeed\($0)"] }.flatMap(\.properties).map(\.type)
			if Set(siblingTypes.filter { $0.contains("LazilyInstantiated<") }).count > 1 {
				features.insert(.valueFormsBesidePublicMockCallTwoWrapperForms)
			}
			if (1...3).compactMap({ types.declarations["\(prefix)FormFeed\($0)"] }).contains(where: { $0.properties.contains { $0.label == "currentFormSession" } }) {
				features.insert(.valueFormsBesidePublicMockCallRenamed)
			}
			if screen.properties.contains(where: { $0.label == "formSession" || $0.label == "currentFormSession" }) {
				features.insert(.valueFormsBesidePublicMockCallConsumerReceivesValue)
			}
			if types.declarations["\(prefix)FormBadge"] != nil {
				features.insert(.valueFormsBesidePublicMockCallEmptyPublicMock)
			}
			if screen.arguments.contains("generateMock: .public"), screen.properties.contains(where: { $0.label == "formSession" && $0.type.hasSuffix(">?") }), fixture.swiftFileContent.contains(where: { $0.contains("let formSession: \(prefix)FormMark") }) {
				features.insert(.valueFormsBesidePublicMockCallPublicOptionalWrapperBesideOtherType)
			}
			if types.declarations["\(prefix)FormCacheEntry"] != nil {
				features.insert(.valueFormsBesidePublicMockCallCalledTreeReceivesValue)
			}
			if fixture.swiftFileContent.contains(where: { $0.contains("let formSession: \(prefix)FormMark") }) {
				features.insert(.valueFormsBesidePublicMockCallLabelOfAnotherType)
			}
		}
		if let home = types.declarations["\(prefix)LabelHome"], let hole = home.properties.first(where: { $0.attribute == "@Instantiated" }) {
			features.insert(.holeLabelReceivedByPromotedSibling)
			if hole.label == "labelGadget_lazilyInstantiated" {
				features.insert(.holeLabelReceivedByPromotedSiblingEqualsGeneratedName)
			}
			if hole.type.hasPrefix("Instantiator<") {
				features.insert(.holeLabelReceivedByPromotedSiblingHeldInInstantiator)
			} else if hole.type.hasPrefix("LazilyInstantiated<") {
				features.insert(.holeLabelReceivedByPromotedSiblingHeldInLazilyInstantiated)
			}
		}
		if let carrierLabels = carrierBeforeSiblingDeclaredLabels(in: types, prefix: prefix) {
			features.insert(.carrierBeforeSibling)
			if carrierLabels.first == "carrierStore" {
				features.insert(.carrierBeforeSiblingBetweenSiblings)
			}
			if carrierLabels.contains("carrierBanner") {
				features.insert(.carrierBeforeSiblingThroughSameModuleSeam)
			}
			if types.declarations["\(prefix)CarrierShelf"] != nil {
				features.insert(.carrierBeforeSiblingBeneathConfiguredChild)
			}
			if types.declarations["\(prefix)CarrierLocal"] != nil {
				features.insert(.carrierBeforeSiblingBeneathInternallyConfiguredChild)
			}
		}
		features.formUnion(TwinShape.shapes(of: fixture).compactMap(GraphFuzzerPublicMockDrawFeature.twinsPublicMock))
		return features
	}

	/// The labels the type that declares `drawCarrierBeforeSiblingPublicMock`'s holder and its siblings declares, in
	/// declaration order – `CarrierShelf` where it is declared, and otherwise `CarrierHome` – or `nil` for a graph that does
	/// not draw it.
	static func carrierBeforeSiblingDeclaredLabels(in types: DeclaredTypes, prefix: String) -> [String]? {
		guard let declaringType = types.declarations["\(prefix)CarrierShelf"] ?? types.declarations["\(prefix)CarrierHome"] else { return nil }
		return declaringType.properties.map(\.label)
	}

	/// The pattern of what a call of a public mock reads first where the calling mock takes an optional builder for the
	/// hole type it fills, `<name>.map { .init(__safeDI_noScope: $0) } ?? `, before the struct it hands otherwise, or
	/// nothing (`public-mock-builders.md`, "Optional builders for filled places").
	static let optionalBuilderRead = #"(\w+\.map \{ \.init\(__safeDI_noScope: \$0\) \} \?\? )?"#

	/// What the generated files of an accepted graph show: `generatedFiles`, keyed by module (`FuzzFeature/…`).
	static func outputFeatures(of fixture: GraphFuzzerFixture, generatedFiles: [String: String]) -> Set<GraphFuzzerPublicMockOutputFeature> {
		let prefix = fixture.typeNamePrefix
		let leafIndices = [0, 1, 2, 6]
		var features = Set<GraphFuzzerPublicMockOutputFeature>()
		var tierAccessesByType = [String: Set<String>]()
		/// The types an extension of declares the function only generated code calls, and the construction function of one
		/// name, by the type the extension extends.
		var typesDeclaringGeneratedOnlyMockFunction = Set<String>()
		var typesDeclaringConstructionMockFunction = Set<String>()
		/// The leaves a consumer calls the function only generated code calls of.
		var leavesConsumersCall = Set<String>()
		for (fileName, contents) in generatedFiles where !fileName.hasSuffix(GraphFuzzerOracle.publicMockCallerFileSuffix) {
			let isConsumerFile = GraphFuzzerModule.allCases.contains { $0.isCaller && fileName.hasPrefix($0.name + "/") }
			let lines = contents.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
			// A fill that builds the public mock's type again passes the fill around it, so the file passes it twice: to `mock()`
			// or to the function only generated code calls.
			if isConsumerFile, lines.filter({ ($0.contains(".mock(") || $0.contains(".__safeDI_mock(")) && $0.range(of: #"Builder: \#(Self.optionalBuilderRead)__safeDI_"#, options: .regularExpression) != nil }).count >= 2 {
				features.insert(.consumerFillReentersPublicMock)
			}
			var extendedType: String?
			/// The declaration of the function only generated code calls whose parameter lines follow.
			var pendingGeneratedOnlyMockFunction: (isolated: Bool, type: String)?
			for line in lines {
				if line.hasPrefix("extension "), line.hasSuffix(" {") {
					extendedType = String(line.dropFirst("extension ".count).dropLast(2))
				}
				if line.contains("static func mock(") {
					let access = ["public", "package"].first { line.hasPrefix($0 + " ") || line.contains(" \($0) static func mock(") } ?? "internal"
					tierAccessesByType[extendedType ?? "", default: []].insert(access)
					if access == "public" {
						features.insert(.publicTier)
					}
				}
				if line.contains("_MockConfiguration"), GraphFuzzerModule.allCases.contains(where: { line.contains("__safeDI_\($0.name)_") }) {
					features.insert(.moduleConfiguration)
				}
				if line.contains("struct SafeDIMockConfiguration") {
					features.insert(.configurationStruct)
				}
				if line == "public init() {" || line == "public init() {}" {
					features.insert(.allNonPublicConfiguration)
				}
				// A construction function, which takes `safeDIBuilder:`, and never the function only generated code calls of the same
				// name, which takes no such parameter.
				if line.contains("__safeDI_init(") || (line.contains("__safeDI_mock(") && line.contains("safeDIBuilder:")) {
					features.insert(.constructionFunction)
				}
				// Every tier declares the function only generated code calls: the one that takes a builder struct, read from the
				// parameter lines below the declaration, is the feature.
				if line.contains("static func __safeDI_mock("), !line.contains("safeDIBuilder:") {
					pendingGeneratedOnlyMockFunction = (isolated: line.hasPrefix("@MainActor "), type: extendedType ?? "")
				} else if let pending = pendingGeneratedOnlyMockFunction {
					if Self.takesBuilderStruct(parameter: line) {
						features.insert(.generatedOnlyMockFunction)
						typesDeclaringGeneratedOnlyMockFunction.insert(pending.type)
						if pending.isolated {
							features.insert(.isolatedGeneratedOnlyMockFunction)
						}
					}
					if line.hasPrefix(")") {
						pendingGeneratedOnlyMockFunction = nil
					}
				}
				if line.contains("static func __safeDI_mock("), line.contains("safeDIBuilder:") {
					typesDeclaringConstructionMockFunction.insert(extendedType ?? "")
				}
				if line.contains("@MainActor static func __safeDI_init") {
					features.insert(.isolatedConstruction)
				}
				if line.contains("?? (") {
					features.insert(.defaultRewritten)
				}
				if !isConsumerFile, line.range(of: #"^\w+: (Sendable)?LazilyInstantiated<.+>(\? = nil)?,?$"#, options: .regularExpression) != nil {
					features.insert(.publicMockTakesWrapper)
				}
				if line.hasPrefix("@usableFromInline nonisolated func __safeDI_"), line.contains("_mockDefault_") {
					features.insert(.forwardedProvider)
				}
				// A builder over an enum of the places, `SafeDIMockScope_…`, or a `@Sendable` builder over one,
				// `SafeDISendableMockScope_…`; or the builder struct the function only generated code calls takes,
				// `<label> __safeDI_<…>: <Type>.SafeDIMockScope_….__safeDI_Builder<…>`, beside the closure `mock()` takes.
				if (line.contains(": @escaping ") && line.contains("MockScope_")) || Self.takesBuilderStruct(parameter: line) || isConsumerFile && Self.takesReadableBuilder(parameter: line), !line.contains("func ") {
					features.insert(isConsumerFile ? .consumerPassesHoleBuilderUp : .holeBuilder)
					if !isConsumerFile, line.contains(": @escaping @Sendable (") || line.contains("SafeDISendableMockScope_") {
						features.insert(.sendableHoleBuilder)
					}
				}
				if line.hasPrefix("let holeLoopBuilder = ") {
					features.insert(.holeLoopBuilder)
					if Self.takesBuilderStructForHole(in: contents, prefix: prefix) {
						features.insert(.holeLoopBuilderOfBuilderStruct)
					}
				}
				guard isConsumerFile else { continue }
				// A fill, handed a place's values, or a dispatcher, which a call declares only with a fill; or a level function, which
				// returns a level's builder struct.
				if line.hasPrefix("func __safeDI_") || line.hasPrefix("@Sendable nonisolated func __safeDI_") || line.hasPrefix("@Sendable nonisolated func __safeDI_"), line.contains("MockScope_"), line.contains("(_ scope: ") || line.contains(".__safeDI_Builder<") {
					features.insert(.consumerFillsHole)
				}
				if line.contains(".__safeDI_mock(") {
					if line.range(of: #"\w+: \#(Self.optionalBuilderRead)__safeDI_\w+\(\)"#, options: .regularExpression) != nil {
						features.insert(.consumerPassesLevelFunctionsStruct)
					}
					// A place passed up without a scope: the struct of a level function that takes the caller's struct as `up`, the
					// builder a person writes, wrapped, or a member of the caller's own struct, handed on as it is.
					if line.range(of: #"\w+: __safeDI_\w+\(up_*: "#, options: .regularExpression) != nil || line.contains(": .init(__safeDI_noScope: ") || line.range(of: #"\w+: __safeDI_\w+\.\w+\(\w*SafeDI(Sendable)?MockScope_\w+\.\w+_Values\(\)\)"#, options: .regularExpression) != nil {
						features.insert(.consumerPassesPlaceUpWithoutScope)
					}
				}
				for leafIndex in leafIndices {
					let leafName = "\(prefix)T\(leafIndex)"
					if line.contains("\(leafName).mock(") || line.contains("\(leafName).__safeDI_mock(") {
						features.insert(.consumerCall)
						if line.contains("\(leafName).__safeDI_mock(") {
							leavesConsumersCall.insert(leafName)
						}
						if line.contains(".instance") {
							features.insert(.consumerPassesInstance)
						}
						if line.contains("\(prefix)AnyT\(leafIndex)(\(leafName).mock(") || line.contains("\(prefix)AnyT\(leafIndex)(\(leafName).__safeDI_mock(") {
							features.insert(.consumerErasedCall)
						}
					} else if line.contains("\(leafName)(") || line.contains("\(leafName).customMock(") {
						features.insert(.consumerInline)
						if line.contains("\(prefix)AnyT\(leafIndex)(\(leafName)(") || line.contains("\(prefix)AnyT\(leafIndex)(\(leafName).customMock(") {
							features.insert(.consumerErasedInline)
						}
					}
				}
				if line.contains("(@Sendable () -> \(prefix)T") {
					features.insert(.consumerSendableFactory)
				}
			}
		}
		let tierCounts = tierAccessesByType.values.map(\.count)
		if tierCounts.contains(where: { $0 >= 2 }) {
			features.insert(.secondTier)
		}
		if tierCounts.contains(where: { $0 >= 3 }) {
			features.insert(.thirdTier)
		}
		if generatedFiles.values.contains(where: { $0.contains("// SafeDI counts `") }) {
			features.insert(.unreadTypeComment)
		}
		if !typesDeclaringGeneratedOnlyMockFunction.isDisjoint(with: typesDeclaringConstructionMockFunction) {
			features.insert(.generatedOnlyMockFunctionBesideConstructionFunction)
		}
		if leavesConsumersCall.contains(where: { leaf in tierAccessesByType[leaf, default: []].count >= 2 && !typesDeclaringGeneratedOnlyMockFunction.contains(leaf) }) {
			features.insert(.consumerCallsTieredMockWithoutBuilderStruct)
		}
		return features
	}

	/// Whether `parameter`, a trimmed line, is a builder struct the function only generated code calls takes:
	/// `<label> __safeDI_<…>: <Type>.SafeDIMockScope_….__safeDI_Builder<…>`.
	static func takesBuilderStruct(parameter: String) -> Bool {
		parameter.range(of: #"^\w+ __safeDI_\w+: [\w.]*\.SafeDI(Sendable)?MockScope_\w*\.__safeDI_Builder<"#, options: .regularExpression) != nil
	}

	/// Whether `parameter`, a trimmed line, is a builder a person writes for a hole, which a mock takes where its place
	/// forwards nothing, `<label>Builder…: @escaping () -> …` (`@escaping @Sendable () -> …` in the `@Sendable` family), or
	/// where it forwards a value, `<label>Builder…: @escaping <Wrapper><…>.Builder`.
	static func takesReadableBuilder(parameter: String) -> Bool {
		parameter.range(of: #"^\w+Builder\w*: @escaping (@Sendable )?\(\) -> "#, options: .regularExpression) != nil
			|| parameter.range(of: #"^\w+Builder\w*: @escaping \w*Instantiator<.*>\.Builder,?$"#, options: .regularExpression) != nil
	}

	/// Whether `contents`, a generated file, declares `T6`'s function only generated code calls taking the builder struct of
	/// a hole type.
	static func takesBuilderStructForHole(in contents: String, prefix: String) -> Bool {
		contents.split(separator: "\n").contains { line in
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			return takesBuilderStruct(parameter: trimmed) && trimmed.contains(": \(prefix)T6.SafeDIMockScope_")
		}
	}

	/// The `@Instantiable` declarations of a fixture by name, with what the readers above need of each, and the trimmed
	/// lines of every file.
	struct DeclaredTypes {
		struct Declaration {
			var arguments = ""
			var access = "internal"
			var isMainActor = false
			var initializerLine = ""
			var initializerAccess = "internal"
			var properties = [(attribute: String, label: String, type: String)]()

			/// The initializer's default-valued parameters, each as written: `retries: Int = 3`.
			var defaultParameters: [String] {
				guard let start = initializerLine.range(of: "init("), let end = initializerLine.range(of: ")", options: .backwards) else { return [] }
				return GraphFuzzerOracle.topLevelParameters(String(initializerLine[start.upperBound..<end.lowerBound]))
					.map { $0.trimmingCharacters(in: .whitespaces) }
					.filter { $0.contains(" = ") }
			}

			/// Whether the type's `mock()` takes an optional-typed default-valued parameter of its initializer, which a public
			/// mock once held in `SafeDIOverrides` where the type is on no actor and builds a dependency: the type is
			/// `.public`, builds through its initializer rather than a hand-written mock, which takes no default, and
			/// instantiates a dependency on no actor.
			var takesOwnOptionalDefaultOnNonisolatedTypeThatBuilds: Bool {
				arguments.contains("generateMock: .public")
					&& !arguments.contains("customMockName:")
					&& !isMainActor
					&& properties.contains { $0.attribute.hasPrefix("@Instantiated") }
					&& defaultParameters.contains { $0.contains("? = ") }
			}
		}

		var declarations = [String: Declaration]()
		var lines = [String]()

		init(of fixture: GraphFuzzerFixture) {
			for content in fixture.swiftFileContent {
				var current: String?
				var pendingArguments: String?
				for rawLine in content.split(separator: "\n") {
					let line = rawLine.trimmingCharacters(in: .whitespaces)
					lines.append(line)
					if line.hasPrefix("@Instantiable") {
						pendingArguments = String(line.dropFirst("@Instantiable".count))
						continue
					}
					if let arguments = pendingArguments, let classRange = line.range(of: "final class ") {
						let name = String(line[classRange.upperBound...].prefix { $0.isLetter || $0.isNumber || $0 == "_" })
						var declaration = Declaration(arguments: arguments)
						declaration.isMainActor = line.hasPrefix("@MainActor ")
						let unattributed = declaration.isMainActor ? line.dropFirst("@MainActor ".count) : Substring(line)
						declaration.access = ["public", "package"].first { unattributed.hasPrefix($0 + " ") } ?? "internal"
						declarations[name] = declaration
						current = name
					} else if let name = current, declarations[name]?.initializerLine.isEmpty == true, line.contains("init(") {
						let unisolated = ["nonisolated ", "@MainActor "].first { line.hasPrefix($0) }.map { line.dropFirst($0.count) } ?? Substring(line)
						declarations[name]?.initializerLine = line
						declarations[name]?.initializerAccess = ["public", "package"].first { unisolated.hasPrefix($0 + " ") } ?? "internal"
					} else if let name = current, line.hasPrefix("@Instantiated") || line.hasPrefix("@Received") || line.hasPrefix("@Forwarded"),
					          let letRange = line.range(of: " let ", options: .backwards),
					          let colon = line[letRange.upperBound...].firstIndex(of: ":")
					{
						declarations[name]?.properties.append((
							String(line[..<letRange.lowerBound]),
							String(line[letRange.upperBound..<colon]),
							line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces),
						))
					}
					pendingArguments = nil
				}
			}
		}
	}
}

/// What a generated public mock takes, read from its generated file by the readers that write or judge a call of it by hand.
enum GraphFuzzerPublicMockBuilders {
	/// The labels of the builders the generated `mock()` of `mockedType` in `generatedFiles` takes as a closure that takes
	/// nothing, `<label>: @escaping () -> T` or `@escaping @Sendable () -> T`, each once, in the order the first tier that
	/// declares it does, since each tier repeats the labels it shares with another.
	static func labelsTakingNothing(of mockedType: String, in generatedFiles: [String: String]) -> [String] {
		var labels = [String]()
		for parameter in builderParameters(of: mockedType, in: generatedFiles) where parameter.type.hasPrefix("@escaping () -> ") || parameter.type.hasPrefix("@escaping @Sendable () -> ") {
			if !labels.contains(parameter.label) {
				labels.append(parameter.label)
			}
		}
		return labels
	}

	/// The builders each generated `mock()` of `mockedType` in `generatedFiles` takes, tier by tier in the order the files
	/// declare them: each parameter labeled as a builder, with its type as the mock spells it, `@escaping` included and a
	/// trailing comma dropped.
	static func builderParameters(of mockedType: String, in generatedFiles: [String: String]) -> [(label: String, type: String)] {
		var parameters = [(label: String, type: String)]()
		for (fileName, contents) in generatedFiles.sorted(by: { $0.key < $1.key }) where !fileName.hasSuffix("+SafeDIPublicMockCaller.swift") {
			var extendedType: String?
			var isInMockParameters = false
			for line in contents.split(separator: "\n") {
				let trimmed = line.trimmingCharacters(in: .whitespaces)
				if trimmed.hasPrefix("extension "), trimmed.hasSuffix(" {") {
					extendedType = String(trimmed.dropFirst("extension ".count).dropLast(2))
				}
				if extendedType == mockedType, trimmed.hasSuffix("static func mock(") {
					isInMockParameters = true
				} else if trimmed.hasPrefix(")") {
					isInMockParameters = false
				} else if isInMockParameters, let colon = trimmed.firstIndex(of: ":") {
					let label = String(trimmed[..<colon])
					let type = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
					if label.contains("Builder") {
						parameters.append((label, type.hasSuffix(",") ? String(type.dropLast()) : type))
					}
				}
			}
		}
		return parameters
	}

	/// Whether a builder of `type`, as `builderParameters(of:in:)` spells it, takes a value its place forwards, so that a
	/// hand-written `{ _ in … }` passed to it takes no scope: the `Builder` of an `Instantiator<T>` or its `Sendable` twin,
	/// which takes `T.ForwardedProperties` (the module cannot see that a type that conforms to `Instantiable` by hand forwards
	/// `()`, so such a place keeps the wrapper's `Builder`, by "A seam's builder takes the type its places give it" in
	/// `seam-and-mock-contract.md`), or of an `ErasedInstantiator<F, T>` or its `Sendable` twin whose `F` is not `()` or
	/// `Void`. A closure that takes nothing, a closure over a scope enum and an erased instantiator's `Builder` over `()`
	/// take none.
	static func takesForwardedValue(builderType type: String) -> Bool {
		let wrapperBuilder = type.hasPrefix("@escaping ") ? String(type.dropFirst("@escaping ".count)) : type
		guard wrapperBuilder.hasSuffix(">.Builder"), let openingBracket = wrapperBuilder.firstIndex(of: "<") else { return false }
		let arguments = wrapperBuilder[wrapperBuilder.index(after: openingBracket)...].dropLast(">.Builder".count)
		switch wrapperBuilder[..<openingBracket] {
		case "Instantiator", "SendableInstantiator":
			return true
		case "ErasedInstantiator", "SendableErasedInstantiator":
			// The forwarded value is the first generic argument: the arguments up to their first comma outside brackets.
			var depth = 0
			var forwarded = ""
			for character in arguments {
				guard character != "," || depth > 0 else { break }
				if "<([".contains(character) {
					depth += 1
				} else if ">)]".contains(character) {
					depth -= 1
				}
				forwarded.append(character)
			}
			return !["()", "Void", "Swift.Void"].contains(forwarded.trimmingCharacters(in: .whitespaces))
		default:
			return false
		}
	}

	/// For each generated `public` `mock()` of `mockedType` in `generatedFiles`, the number of builders it takes: parameters
	/// labeled as builders whose type is a closure. A hand-written call from a module of another package reaches that tier
	/// alone; a narrower tier can take more.
	static func publicTierBuilderCounts(of mockedType: String, in generatedFiles: [String: String]) -> [Int] {
		var counts = [Int]()
		for (fileName, contents) in generatedFiles.sorted(by: { $0.key < $1.key }) where !fileName.hasSuffix("+SafeDIPublicMockCaller.swift") {
			var extendedType: String?
			var builderCount: Int?
			for line in contents.split(separator: "\n") {
				let trimmed = line.trimmingCharacters(in: .whitespaces)
				if trimmed.hasPrefix("extension "), trimmed.hasSuffix(" {") {
					extendedType = String(trimmed.dropFirst("extension ".count).dropLast(2))
				}
				if extendedType == mockedType, trimmed.hasSuffix("public static func mock(") {
					builderCount = 0
				} else if let count = builderCount, trimmed.hasPrefix(")") {
					counts.append(count)
					builderCount = nil
				} else if let count = builderCount, let colon = trimmed.firstIndex(of: ":") {
					let label = trimmed[..<colon]
					let type = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
					if label.contains("Builder"), type.hasPrefix("@escaping ") {
						builderCount = count + 1
					}
				}
			}
		}
		return counts
	}
}
