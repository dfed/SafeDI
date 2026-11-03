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
	/// An `@Instantiable` type declared in an extension of an `@Instantiable` type of the module: an exact entry.
	case typeInExtensionOfInstantiable
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
	/// A consumer holding a value its leaf's tree receives only if available, of a type whose proof is narrower than
	/// the type's own access, so that the tier the consumer reaches omits it.
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
	/// The hole declared as `Instantiator<Hole>`, whose type conforms to `Instantiable` by hand, as `any HoleProtocol`, or
	/// as an erasure of `HoleFill`, which only a consumer module may declare, to `AnyHole`: a constant or an
	/// `ErasedInstantiator`.
	case holeDeclaredAsInstantiator
	case holeDeclaredAsExistential
	case holeDeclaredAsErasedConstant
	case holeDeclaredAsErasedInstantiator
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

	static func < (lhs: GraphFuzzerPublicMockDrawFeature, rhs: GraphFuzzerPublicMockDrawFeature) -> Bool {
		lhs.rawValue < rhs.rawValue
	}
}

/// What the generated code of a graph the tool accepts shows, read from it, never from the draw (section 6's output
/// features). `publicMockCorpusOutputFeatureMinimumShares` pins each one the corpus shows; the consumer's call of a public
/// mock (`consumerCall`, `consumerPassesInstance`) needs the consumer side.
/// That no generated mock takes a `LazilyInstantiated` parameter for a receive is `wrapperParameterFailure`, an oracle
/// every graph of every corpus passes.
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
	/// A consumer's leaf call passing `.instance`.
	case consumerPassesInstance
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
	/// A public mock taking a builder for a hole, `<label>Builder: @escaping (…SafeDIMockScope_…`, and a staged one, whose
	/// first stage returns a `@Sendable` builder, in the declaring module.
	case holeBuilder
	case stagedHoleBuilder
	/// A consumer's mock filling a called public mock's builder with a function of its own (`func
	/// __safeDI_<label>Builder(_ scope: …`), a fill that calls the public mock again with the fill around it (a fully
	/// lazy cycle), and a consumer's mock taking the builder and passing it up.
	case consumerFillsHole
	case consumerFillReentersPublicMock
	case consumerPassesHoleBuilderUp

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
/// children `T3` to `T5`, the `.public` type `T6` whose tree holds a hole, and the consumers `T7` (same package), `T8`
/// (another package) and `T9` (a type a `Sendable` wrapper builds), each held under the label `t<index>`, and the eraser
/// `AnyT<index>` of a leaf a consumer reaches through an erasure, held under `anyT<index>`; the helper types keep their
/// names.
struct GraphFuzzerPublicMockDraw {
	init(seed: UInt64) {
		prefix = GraphFuzzerFixture.typeNamePrefix(forSeed: seed)
		var random = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.publicMockRandomSeedMask)
		var spellingRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.publicMockSpellingRandomSeedMask)
		var requiredParameterRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.publicMockRequiredParameterRandomSeedMask)
		var isolationSpellingRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.publicMockIsolationSpellingRandomSeedMask)
		var erasureRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.publicMockErasureRandomSeedMask)
		var holeRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.publicMockHoleRandomSeedMask)
		draw(
			random: &random,
			spellingRandom: &spellingRandom,
			requiredParameterRandom: &requiredParameterRandom,
			isolationSpellingRandom: &isolationSpellingRandom,
			erasureRandom: &erasureRandom,
			holeRandom: &holeRandom,
		)
	}

	/// The files of the graph, each beginning with its module's marker: as drawn, or, for the known-right path of the
	/// value differential, with every declaration `public` and every `generateMock: .public` turned into `true`.
	/// - Parameter storingEveryParameter: Whether each type stores every default-valued parameter it takes, and each class
	///   a creation stamp, as `GraphFuzzerGenerator.fixture(forSeed:storingEveryParameter:)` describes.
	func swiftFileContent(storingEveryParameter: Bool, isKnownRight: Bool) -> [String] {
		let rendering = Rendering(prefix: prefix, storesEveryParameter: storingEveryParameter, isKnownRight: isKnownRight)
		return files.enumerated().map { index, file in
			var lines = [GraphFuzzerModule.marker + file.module.name]
			if let fileName = file.fileName {
				lines.append(GraphFuzzerFixture.fileNameMarker + fileName)
			}
			lines += file.module.dependencies.map { "import \($0.name)" }
			var content = lines.joined(separator: "\n") + "\n\n" + file.declarations.map { $0(rendering) }.joined(separator: "\n\n") + "\n"
			// The creation stamps' counter, in the first file of the module every other module imports.
			if storingEveryParameter, index == 0 {
				content += "\n" + DifferentialValueCreationStamp.counterDeclaration(named: rendering.counterName) + "\n"
			}
			return content
		}
	}

	/// The access the draw gave each type narrower than `public` – its spelled level capped by the types and extensions
	/// enclosing it – by the name the fixture spells it with (`S1_Space.S1_Shelf` for a nested type): the ground truth
	/// the access oracle checks generated declarations against. Every other type the graph declares is `public`.
	private(set) var typeAccess = [String: GraphFuzzerGenerator.AccessLevel]()

	static let publicMockRandomSeedMask: UInt64 = 0x7075626C69636D6B
	static let publicMockSpellingRandomSeedMask: UInt64 = 0x7075626D6B73706C
	/// Draws only whether a parameter of a plain type narrower than its type's own access is required, which the public
	/// tier then cannot take (`publicTierOmitsRequiredParameter`): rolls added after the rest of the draw was pinned, so
	/// that its other shapes are drawn as before, about one graph in ten drawing the error.
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
	/// Whether consumers reach `T6`, some in a module that declares an `@Instantiable` type fulfilling its hole, whose
	/// generated mock fills the builder, and some in one that does not, whose mock takes the builder and passes it on.
	/// Off, `T6` is called only by its hand-written caller, so the corpus checks the declaring side alone. Its rolls are
	/// drawn on the hole stream, after `T6`'s own, so turning it off moves no other shape.
	static let drawsHoleConsumers = true
	/// What begins the comment in `T6`'s file that holds its hand-written caller's call, after the caller's module:
	/// `// publicMockCaller in FuzzOther: S1_T6.mock(holeBuilder: …)`. `GraphFuzzerOracle.addingPublicMockCallers` reads it.
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
		let module: GraphFuzzerModule
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

	/// Where `T6`'s tree instantiates its hole: on `T6`, or on the type `HoleHost` that `T6` instantiates as a wrapper.
	private enum HolePosition {
		case direct
		case instantiator
		case lazilyInstantiated
		case sendableInstantiator
		case sendableLazilyInstantiated

		var wrapperName: String {
			switch self {
			case .direct: ""
			case .instantiator: "Instantiator"
			case .lazilyInstantiated: "LazilyInstantiated"
			case .sendableInstantiator: "SendableInstantiator"
			case .sendableLazilyInstantiated: "SendableLazilyInstantiated"
			}
		}

		/// The label `T6` holds the host under.
		var hostLabel: String {
			switch self {
			case .direct, .lazilyInstantiated, .sendableLazilyInstantiated: "holeHost"
			case .instantiator, .sendableInstantiator: "holeHostBuilder"
			}
		}

		/// Whether the hole is built inside a `@Sendable` builder function, whose builder the public mock takes staged.
		var isSendable: Bool {
			switch self {
			case .direct, .instantiator, .lazilyInstantiated: false
			case .sendableInstantiator, .sendableLazilyInstantiated: true
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
	) {
		let moduleRoll = random.integer(in: 0...9)
		let consumerModules: [GraphFuzzerModule] = moduleRoll < 4 ? [.samePackageCaller, .otherPackageCaller] : moduleRoll < 7 ? [.samePackageCaller] : [.otherPackageCaller]
		let leafCount = random.integer(in: 1...3)
		// Some graphs are `Sendable` throughout, which alone may build a leaf inside a `@Sendable` builder.
		let isSendableGraph = random.percentChance(35)
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
						helperFiles.append(File(module: .seamModule, declarations: [{ rendering in
							"\(rendering.modifier(namespaceAccess))enum \(namespaceName) {}\n\n\(rendering.extensionModifier(extensionAccess))extension \(namespaceName) {\n\(indented(Self.render(shelfDeclaration, rendering: rendering)))\n}"
						}]))
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
					// A parameter narrower than public, a package plain type: required, which no public tier can take, two
					// times in five, else only if available.
					property = received("seal", plain("Seal", access: .package), onlyIfAvailable: !requiredParameterRandom.percentChance(40))
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
			// A value the leaf's tree receives only if available that a consumer may hold: a public type declared in an
			// extension of a public namespace that spells no access level, which the receiving initializer proves no
			// wider than its own access, so the public tier omits it.
			if random.percentChance(30) {
				let holderName = name("Holder\(leafIndex)")
				let qualifiedName = "\(dockName).\(holderName)"
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
					plainDeclarations.append { rendering in "\(rendering.modifier(.public))enum \(dockName) {}" }
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
		// it builds beneath an `Instantiator`, a `LazilyInstantiated`, or a `Sendable` wrapper (`HoleHost`). The hole is
		// declared as the public class `Hole`, as `Instantiator<Hole>` (the class then conforming to `Instantiable` by
		// hand), as `any HoleProtocol`, or as an erasure of the type `HoleFill`, which only a consumer module may declare,
		// to the eraser `AnyHole`, a constant or an `ErasedInstantiator` – the last always on `T6`, so that a fill that
		// builds `T6` again through an `Instantiator` closes a fully lazy cycle. Before the hole `T6` now and then binds a
		// `package` value and a public one (`holeContext`), which the hole's scope struct holds as fields. A hand-written
		// caller in a consumer module – the other package's when there is one – calls its public mock with a builder that
		// ignores the scope it is handed (`publicMockCallerMarker`).
		let callerModule = consumerModules.contains(.otherPackageCaller) ? GraphFuzzerModule.otherPackageCaller : .samePackageCaller
		var holeLeaf: (declaration: InstantiableClass, spelling: HoleSpelling, position: HolePosition)?
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
			let position: HolePosition = switch positionRoll {
			case _ where spelling == .erasedInstantiator: .direct
			case 0..<6: .direct
			case 6, 7: .instantiator
			case 8, 9: .lazilyInstantiated
			case 10: isSendableGraph ? .sendableInstantiator : .instantiator
			default: isSendableGraph ? .sendableLazilyInstantiated : .lazilyInstantiated
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
				value = "Instantiator<\(holeName)> { \(holeName)() }"
				plainDeclarations.append(plainClass(holeName, access: .public, conformances: ["Instantiable"]))
			case .existential:
				holeType = "any \(protocolName)"
				value = "\(conformerName)()"
			case .erasedConstant, .erasedInstantiator:
				holeType = spelling == .erasedConstant ? erasedName : "ErasedInstantiator<(), \(erasedName)>"
				value = spelling == .erasedConstant ? "\(erasedName)(\(conformerName)())" : "ErasedInstantiator<(), \(erasedName)> { \(erasedName)(\(conformerName)()) }"
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
			helperFiles.append(File(module: .seamModule, declarations: [Self.renderer(of: prover)]))

			var declaration = instantiableClass("T6")
			declaration.mockGeneration = ".public"
			let initializerRoll = holeRandom.integer(in: 0...7)
			declaration.initializerAccess = initializerRoll < 4 ? .package : initializerRoll == 4 ? .internal : .public
			if holeRandom.percentChance(30) {
				declaration.add(Property(attribute: "@Instantiated", label: "session", type: instantiable("Session", access: .package)))
				declaration.names(.package)
			}
			if holeRandom.percentChance(40) {
				declaration.add(Property(attribute: "@Instantiated", label: "holeContext", type: instantiable("HoleContext")))
			}
			let owner: String
			switch position {
			case .direct:
				owner = declaration.name
				declaration.add(Property(attribute: attribute, label: holeLabel, type: holeType))
			case .instantiator, .lazilyInstantiated, .sendableInstantiator, .sendableLazilyInstantiated:
				let hostAccess: AccessLevel = holeRandom.percentChance(50) ? .public : .package
				var host = instantiableClass("HoleHost", access: hostAccess)
				host.properties = [Property(attribute: attribute, label: holeLabel, type: holeType)]
				owner = host.name
				declaration.add(Property(attribute: "@Instantiated", label: position.hostLabel, type: "\(position.wrapperName)<\(host.name)>"))
				declaration.names(hostAccess)
				declaringFiles.append(File(module: .seamModule, declarations: [Self.renderer(of: host)]))
			}
			// The call: a builder for the hole, `<label>Builder`, handed the hole's scope struct, `SafeDIMockScope_<owner>_<label>`,
			// staged around a `@Sendable` builder function.
			let scopeType = "\(declaration.name).SafeDIMockScope_\(owner)_\(holeLabel)"
			let builder = position.isSendable
				? "{ (_: \(scopeType).Outer) in { (_: \(scopeType).Inner) in \(value) } }"
				: "{ (_: \(scopeType)) in \(value) }"
			let call = "\(declaration.name).mock(\(holeLabel)Builder: \(builder))"
			let holeDeclaration = declaration
			declaringFiles.append(File(module: .seamModule, declarations: [
				Self.renderer(of: holeDeclaration),
				{ _ in "\(Self.publicMockCallerMarker)\(callerModule.name): \(call)" },
			]))
			holeLeaf = (declaration, spelling, position)
		}

		// The consumers: `T7` in the same package, `T8` in another, each reaching one leaf, or both of M8.9b's.
		var consumerFiles = [File]()
		let wrapperModule: GraphFuzzerModule? = isSendableGraph && random.percentChance(70) ? random.element(of: consumerModules) : nil
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
					providers.append(Property(attribute: "@Instantiated", label: "analytics", type: "LazilyInstantiated<\(name("Analytics"))>"))
				}
				// A public consumer leaves `theme` unprovided half the time.
				if leaf.receivesTheme, !(isPublicConsumer && random.percentChance(50)), random.percentChance(60) {
					providers.append(Property(attribute: "@Instantiated", label: "theme", type: name("Theme")))
				}
				if let spelled = leaf.spelledConsumerValue {
					providers.append(Property(attribute: "@Forwarded", label: spelled.label, type: spelled.type))
				}
				if let holder = leaf.holder, random.percentChance(55) {
					switch random.integer(in: 0...3) {
					case 0:
						providers.append(Property(attribute: "@Received", label: holder.label, type: holder.type))
					case 1:
						providers.append(Property(attribute: "@Instantiated", label: holder.label, type: "LazilyInstantiated<\(holder.type)>"))
					default:
						providers.append(Property(attribute: "@Instantiated", label: holder.label, type: holder.type))
					}
					providersFirst = random.percentChance(50)
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
			if Self.drawsHoleConsumers, let holeLeaf, holeRandom.percentChance(60) {
				leafProperties.append(Property(attribute: holeRandom.percentChance(50) ? "@Received" : "@Instantiated", label: "t6", type: holeLeaf.declaration.name))
				if !declared.contains("HoleFill"), holeRandom.percentChance(50) {
					declared.insert("HoleFill")
					let holeName = name("Hole")
					let extraName = name("HoleExtra")
					let canCloseLazyCycle = holeLeaf.spelling == .erasedInstantiator && holeLeaf.position == .direct
					let bindsContext = holeLeaf.declaration.properties.contains { $0.label == "holeContext" }
					let dependencyRoll = holeRandom.integer(in: 0...9)
					// A fill receiving `holeContext` where `T6` binds none receives a value no field holds, as `holeExtra` is.
					let dependency: HoleFillDependency = if canCloseLazyCycle, holeRandom.percentChance(50) {
						.lazyCycle
					} else if dependencyRoll < (bindsContext ? 3 : 5) {
						.none
					} else if bindsContext ? dependencyRoll < 8 : dependencyRoll >= 8 {
						.field
					} else {
						.nonField
					}
					let dependencies: [Property] = switch dependency {
					case .none: []
					case .field: [Property(attribute: "@Received", label: "holeContext", type: instantiable("HoleContext"))]
					case .nonField: [Property(attribute: "@Received", label: "holeExtra", type: extraName)]
					case .lazyCycle: [Property(attribute: "@Instantiated", label: "t6Builder", type: "Instantiator<\(holeLeaf.declaration.name)>")]
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
						holeFulfillerDeclarations.insert(Self.renderer(of: fill), at: 0)
					}
				}
			}
			var declarations = [(Rendering) -> String]()
			let canWrap = !reachedLeaves.contains { $0.forwards || $0.receivesNonSendableSpelledValue || $0.declaration.isMainActor }
			if wrapperModule == module, canWrap {
				// A `Sendable` wrapper above the leaf, whose type builds the leaf and what the consumer would provide, and
				// always the lazily instantiated dependency the leaf receives, which no `@Sendable` builder can capture.
				if reachedLeaves.contains(where: \.receivesAnalyticsLazily), !uniqueProviders.contains(where: { $0.label == "analytics" }) {
					uniqueProviders.append(Property(attribute: "@Instantiated", label: "analytics", type: "LazilyInstantiated<\(name("Analytics"))>"))
				}
				var builtType = instantiableClass("T9")
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
			consumerFiles.append(File(module: module, declarations: declarations))
			if !holeFulfillerDeclarations.isEmpty {
				consumerFiles.append(File(module: module, fileName: "\(prefix)HoleFill.swift", declarations: holeFulfillerDeclarations))
			}
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
				// `Result` and `Error` are not on the proof's allowlist, so the prover mentions them too.
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
			+ declaration.defaults.map { "\($0.argumentLabel.map { "\($0) " } ?? "")\($0.name): \(parameterType($0.type)) = \($0.defaultValue)" }
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
			guard !GraphFuzzerOracle.isPublicMockOnlyRejection(diagnostics: diagnostics) else { return nil }
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
		"` has a public `mock()`, but it cannot be called from ",
	]

	/// Whether every error in `diagnostics`, a rejection of a `generateMockPublic` graph as drawn, is one of a public
	/// mock's own (`publicMockOnlyErrorMarkers`).
	static func isPublicMockOnlyRejection(diagnostics: String) -> Bool {
		let errors = diagnostics.split(separator: "\n").filter { $0.contains(": error: ") }
		return !errors.isEmpty && errors.allSatisfy { error in publicMockOnlyErrorMarkers.contains { error.contains($0) } }
	}

	/// The value differential of a `generateMockPublic` graph the tool accepts as drawn and as its known-right path, or
	/// `nil` for any other graph: the feature path is the graph as drawn with the files the tool generated for it, the
	/// known-right path the graph with every declaration `public` and every `.public` mock `true`, with its own files,
	/// each drawn storing every parameter, which changes nothing the tool generates; the probes are every generated
	/// mock that takes no required parameter, each `.public` type's and each consumer's. `valueFailures` exempts the
	/// stated divergences it derives from the graph's leaf calls (`statedPublicMockValueDivergences(in:of:)`).
	static func publicMockValueGraph(of runs: GraphFuzzerToolRuns) -> DifferentialValueGraph? {
		guard case let .accepted(featureFiles, _) = runs.firstOutcome, case let .accepted(knownRightFiles, _) = runs.knownRightOutcome else { return nil }
		let storingFixture = GraphFuzzerGenerator.fixture(forSeed: runs.fixture.seed, features: [.generateMockPublic], storingEveryParameter: true)
		let knownRightFixture = GraphFuzzerGenerator.knownRightPublicMockFixture(forSeed: runs.fixture.seed, storingEveryParameter: true)
		return DifferentialValueGraph(
			name: "seed \(runs.fixture.seed)",
			feature: DifferentialValuePath(fixture: storingFixture, generatedFiles: featureFiles),
			knownRight: DifferentialValuePath(fixture: knownRightFixture, generatedFiles: knownRightFiles),
			probes: storingFixture.differentialValueProbes(generatedFiles: featureFiles),
		)
	}

	/// The differences of `comparison`, a `generateMockPublic` graph's, that are the shape matrix's two stated divergences,
	/// each derived from a leaf call – a call of a `.public` type's mock (`<prefix>T<i>.mock(`) in the generated mock of the
	/// probe's type, read from the graph's generated code – rather than from the difference's text alone, so that any
	/// other value a leaf call builds still fails:
	/// - M8.32 (`isReWrappedHeldInstance`, `isEarlyReadHeldInstance`): a leaf call that passes `<label>.instance` of a
	///   lazily instantiated dependency its caller holds makes the leaf wrap the instance again, a second wrapper where the
	///   known-right path shares the caller's, whose instance the call reads before the probe's value is built. The
	///   re-made wrapper's node is exempt only where the instance beneath it is the one beneath the node the known-right
	///   path shares it with (`heldInstanceUnderReWrappedWrapperIsConsumers(_:firstSeenAt:in:)`).
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
			return isReWrappedHeldInstance(difference, calls: calls, featureDescription: comparison.featureDescription)
				|| isEarlyReadHeldInstance(difference, calls: calls, featureDescription: comparison.featureDescription)
				|| isInstancePerLeafCall(difference, calls: calls, callerLabels: callerLabels, onlyIfAvailableLabels: onlyIfAvailableLabels)
		}
	}

	/// A call, in a mocked type's generated mock, of a `.public` type's mock: the label the leaf is held under (`t<i>`, or
	/// `anyT<i>` for a leaf held through its eraser, whose call the eraser wraps), the labels it passes a value – anything
	/// but `nil` or the calling mock's own parameter that defaults to `nil` and that no binding of the mock shadows – and
	/// those it passes a wrapper's `.instance`.
	struct PublicMockLeafCall: Equatable {
		let leafLabel: String
		let passedLabels: Set<String>
		let instanceLabels: Set<String>
	}

	/// Each call of a `.public` type's mock – `<prefix>T0` to `<prefix>T2` and `<prefix>T6`, held under `t0` to `t2` and
	/// `t6`, or under `anyT<i>` through an eraser – in the generated mock of `typeName`, in any module. A consumer holds each
	/// leaf it reaches under one label, so a mock wraps either every call of a leaf in the leaf's eraser or none.
	static func leafCalls(ofMockedType typeName: String, in generatedFiles: [String: String], prefix: String) -> [PublicMockLeafCall] {
		var calls = [PublicMockLeafCall]()
		for (fileName, contents) in generatedFiles.sorted(by: { $0.key < $1.key }) where fileName == "\(typeName)+SafeDIMock.swift" || fileName.hasSuffix("/\(typeName)+SafeDIMock.swift") {
			// The calling mock's own parameters that default to `nil`, which the parameterless probe leaves `nil`, unless a
			// binding of the same name in the mock shadows one.
			let boundNames = Set((try? NSRegularExpression(pattern: #"\blet ([A-Za-z_][A-Za-z0-9_]*) ="#)).map { expression in
				expression.matches(in: contents, range: NSRange(contents.startIndex..., in: contents)).compactMap { Range($0.range(at: 1), in: contents).map { String(contents[$0]) } }
			} ?? [])
			let unpassedParameters = mockParametersDefaultingToNil(in: contents).subtracting(boundNames)
			for index in [0, 1, 2, 6] {
				let isErased = contents.contains("\(prefix)AnyT\(index)(\(prefix)T\(index).mock(")
				for call in initializerCalls(of: "\(prefix)T\(index).mock", in: contents) {
					let arguments = call.filter { $0.label != "safeDIOverrides" }
					calls.append(PublicMockLeafCall(
						leafLabel: isErased ? "anyT\(index)" : "t\(index)",
						passedLabels: Set(arguments.filter { $0.value != "nil" && !unpassedParameters.contains($0.value) }.map(\.label)),
						instanceLabels: Set(arguments.filter { $0.value.hasSuffix(".instance") }.map(\.label)),
					))
				}
			}
		}
		return calls
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

	/// M8.32's re-made wrapper: a wrapper node of `label`, fresh on the feature path and shared on the known-right path,
	/// where every leaf on the node's path and on its first sight passes `label` as `.instance`, at least one does, and the
	/// two hold one instance on the feature path.
	private static func isReWrappedHeldInstance(_ difference: DifferentialValueDifference, calls: [PublicMockLeafCall], featureDescription: String) -> Bool {
		guard let label = difference.path.last,
		      let feature = captures(of: NSRegularExpression.escapedPattern(for: label) + #": <\d+> ((?:Sendable)?LazilyInstantiated<.+>) \(instance read last\)"#, in: difference.feature),
		      let knownRight = captures(of: NSRegularExpression.escapedPattern(for: label) + #": <\d+> ((?:Sendable)?LazilyInstantiated<.+>) \(seen, first at (.+)\)"#, in: difference.knownRight),
		      feature[0] == knownRight[0]
		else { return false }
		let firstSeenAt = knownRight[1]
		let leafLabels = (difference.path + components(of: firstSeenAt)).filter { component in calls.contains { $0.leafLabel == component } }
		return !leafLabels.isEmpty
			&& leafLabels.allSatisfy { leafLabel in calls.filter { $0.leafLabel == leafLabel }.allSatisfy { $0.instanceLabels.contains(label) } }
			&& heldInstanceUnderReWrappedWrapperIsConsumers(difference, firstSeenAt: firstSeenAt, in: featureDescription)
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

	/// Whether, beneath the re-made wrapper an M8.32 exemption names, the feature path's `description` holds the
	/// consumer's own instance: the instance the re-made wrapper's `.instance` line names is the one the consumer's
	/// wrapper, at the path `firstSeenAt` names (`<1> Screen > analytics`), names. The exemption removes everything
	/// beneath the wrapper's node from the comparison, so this check stands beside it: a re-made wrapper over a second
	/// instance fails it.
	static func heldInstanceUnderReWrappedWrapperIsConsumers(_ exemption: DifferentialValueDifference, firstSeenAt: String, in description: String) -> Bool {
		guard let reMadeWrapper = identity(in: exemption.feature.drop { $0 != ":" }),
		      let section = probeSection(named: exemption.probe, in: description),
		      let consumerWrapperLine = line(at: firstSeenAt.components(separatedBy: " > "), in: section),
		      let consumerWrapper = identity(in: consumerWrapperLine.drop { $0 != ":" }),
		      let consumerInstance = instanceIdentity(ofWrapper: consumerWrapper, in: section),
		      let reMadeInstance = instanceIdentity(ofWrapper: reMadeWrapper, in: section)
		else { return false }
		return consumerInstance == reMadeInstance
	}

	/// The identity a described value names first: `3` of `: <3> LazilyInstantiated<Analytics>`.
	private static func identity(in text: some StringProtocol) -> Int? {
		guard let start = text.firstIndex(of: "<"), let end = text[start...].firstIndex(of: ">") else { return nil }
		return Int(text[text.index(after: start)..<end])
	}

	/// The identity of the instance `<wrapper>.instance: <n> …` names in `lines`.
	private static func instanceIdentity(ofWrapper wrapper: Int, in lines: [Substring]) -> Int? {
		let prefix = "<\(wrapper)>.instance: "
		return lines.lazy.compactMap { line in line.hasPrefix(prefix) ? identity(in: line.dropFirst(prefix.count)) : nil }.first
	}

	/// The lines of the probe `probe` in a path's description: from its `probe <expression>` line to the next probe's.
	private static func probeSection(named probe: String, in description: String) -> [Substring]? {
		let lines = description.split(separator: "\n", omittingEmptySubsequences: false)
		guard let start = lines.firstIndex(of: "probe \(probe)") else { return nil }
		let end = lines[(start + 1)...].firstIndex { $0.hasPrefix("probe ") } ?? lines.endIndex
		return Array(lines[(start + 1)..<end])
	}

	/// The line at `path` in a probe's lines – its value's line (`<1> Screen`), then each child's by its label, two
	/// spaces deeper than its parent's.
	private static func line(at path: [String], in lines: [Substring]) -> Substring? {
		guard let first = path.first, var index = lines.firstIndex(where: { $0 == first }) else { return nil }
		var indent = 0
		for label in path.dropFirst() {
			indent += 2
			let childPrefix = String(repeating: " ", count: indent) + label + ": "
			let subtreeEnd = lines[(index + 1)...].firstIndex { $0.prefix { $0 == " " }.count < indent } ?? lines.endIndex
			guard let child = lines[(index + 1)..<subtreeEnd].firstIndex(where: { $0.hasPrefix(childPrefix) }) else { return nil }
			index = child
		}
		return lines[index]
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
				for name in qualifiedNames(in: declaration) {
					guard let level = typeAccess[name], level < declarationAccess else { continue }
					findings.append("\(fileName): `\(declaration)` is `\(declarationAccess.spelling)`, but `\(name)` is `\(level.spelling)`.")
				}
			}
		}
		return findings
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
			if consumer.properties.contains(where: { $0.label == "analytics" && $0.type.hasPrefix("LazilyInstantiated<") }) {
				features.insert(.consumerHoldsLazilyInstantiatedWrapper)
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
		// R7's hole, on `T6` or on the type `HoleHost` it instantiates beneath a wrapper, and its callers.
		let holeLeafName = "\(prefix)T6"
		if let holeLeaf = types.declarations[holeLeafName] {
			let hostName = "\(prefix)HoleHost"
			let holeProperty = (holeLeaf.properties + (types.declarations[hostName]?.properties ?? [])).first { $0.label == "hole" || $0.label == "holeBuilder" }
			if let hostProperty = holeLeaf.properties.first(where: { $0.type.hasSuffix("<\(hostName)>") }) {
				if hostProperty.type.hasPrefix("Sendable") {
					features.insert(.holeBeneathSendableWrapper)
				} else {
					features.insert(hostProperty.type.hasPrefix("Instantiator<") ? .holeBeneathInstantiator : .holeBeneathLazilyInstantiated)
				}
			} else {
				features.insert(.holeOnPublicMockType)
			}
			if let holeProperty {
				if holeProperty.attribute.contains("erasedToConcreteExistential: true") {
					features.insert(holeProperty.type.hasPrefix("ErasedInstantiator<") ? .holeDeclaredAsErasedInstantiator : .holeDeclaredAsErasedConstant)
				} else if holeProperty.type.hasPrefix("Instantiator<") {
					features.insert(.holeDeclaredAsInstantiator)
				} else if holeProperty.type.hasPrefix("any ") {
					features.insert(.holeDeclaredAsExistential)
				}
			}
			if holeLeaf.properties.contains(where: { $0.label == "session" }) {
				features.insert(.holeScopeHoldsPackageValue)
			}
			let bindsContext = holeLeaf.properties.contains { $0.label == "holeContext" }
			if bindsContext {
				features.insert(.holeScopeHoldsPublicValue)
			}
			if types.lines.contains(where: { $0.hasPrefix(GraphFuzzerPublicMockDraw.publicMockCallerMarker + GraphFuzzerModule.otherPackageCaller.name + ":") }) {
				features.insert(.holeCallerInOtherPackage)
			} else if types.lines.contains(where: { $0.hasPrefix(GraphFuzzerPublicMockDraw.publicMockCallerMarker + GraphFuzzerModule.samePackageCaller.name + ":") }) {
				features.insert(.holeCallerInSamePackage)
			}
			// The consumer modules that reach `T6`, and the one that declares the fill.
			var reachingModules = Set<GraphFuzzerModule>()
			var fillModule: GraphFuzzerModule?
			for (fileName, content) in zip(fixture.fileNames, fixture.swiftFileContent) {
				guard let module = GraphFuzzerModule(declaredIn: content), module != .seamModule else { continue }
				if content.contains(" let t6: \(holeLeafName)\n") {
					reachingModules.insert(module)
				}
				guard fileName.hasSuffix("\(prefix)HoleFill.swift") else { continue }
				fillModule = module
				if content.contains(" let t6Builder: Instantiator<\(holeLeafName)>") {
					features.insert(.holeFillClosesLazyCycle)
				}
				if content.contains("holeExtra: ") || content.contains("holeContext: ") && !bindsContext {
					features.insert(.holeFillReceivesNonField)
				} else if content.contains("holeContext: ") {
					features.insert(.holeFillReceivesField)
				}
			}
			if let fillModule, reachingModules.contains(fillModule) {
				features.insert(.consumerReachesHoleTypeWithFill)
			}
			if reachingModules.contains(where: { $0 != fillModule }) {
				features.insert(.consumerReachesHoleTypeWithoutFill)
			}
		}
		// The mock condition.
		for (fileName, content) in zip(fixture.fileNames, fixture.swiftFileContent) where content.contains("#SafeDIConfiguration(mockConditionalCompilation: nil)") {
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
		return features
	}

	/// What the generated files of an accepted graph show: `generatedFiles`, keyed by module (`FuzzFeature/…`).
	static func outputFeatures(of fixture: GraphFuzzerFixture, generatedFiles: [String: String]) -> Set<GraphFuzzerPublicMockOutputFeature> {
		let prefix = fixture.typeNamePrefix
		let leafIndices = [0, 1, 2, 6]
		var features = Set<GraphFuzzerPublicMockOutputFeature>()
		var tierAccessesByType = [String: Set<String>]()
		for (fileName, contents) in generatedFiles where !fileName.hasSuffix(GraphFuzzerOracle.publicMockCallerFileSuffix) {
			let isConsumerFile = !fileName.hasPrefix(GraphFuzzerModule.seamModule.name + "/")
			let lines = contents.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
			// A fill that builds the public mock's type again passes the fill around it, so the file passes it twice.
			if isConsumerFile, lines.filter({ $0.contains(".mock(") && $0.contains("Builder: __safeDI_") }).count >= 2 {
				features.insert(.consumerFillReentersPublicMock)
			}
			var extendedType: String?
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
				if line.contains("_MockConfiguration"), line.contains("__safeDI_\(GraphFuzzerModule.seamModule.name)_") || line.contains("__safeDI_\(GraphFuzzerModule.samePackageCaller.name)_") || line.contains("__safeDI_\(GraphFuzzerModule.otherPackageCaller.name)_") {
					features.insert(.moduleConfiguration)
				}
				if line.contains("struct SafeDIMockConfiguration") {
					features.insert(.configurationStruct)
				}
				if line == "public init() {" || line == "public init() {}" {
					features.insert(.allNonPublicConfiguration)
				}
				if line.contains("__safeDI_init(") || line.contains("__safeDI_mock(") {
					features.insert(.constructionFunction)
				}
				if line.contains("@MainActor static func __safeDI_init") {
					features.insert(.isolatedConstruction)
				}
				if line.contains("?? (") {
					features.insert(.defaultRewritten)
				}
				if line.hasPrefix("@usableFromInline nonisolated func __safeDI_"), line.contains("_mockDefault_") {
					features.insert(.forwardedProvider)
				}
				if line.contains("Builder: @escaping ("), line.contains(".SafeDIMockScope_") {
					features.insert(isConsumerFile ? .consumerPassesHoleBuilderUp : .holeBuilder)
					if !isConsumerFile, line.contains(") -> @Sendable (") {
						features.insert(.stagedHoleBuilder)
					}
				}
				guard isConsumerFile else { continue }
				if line.hasPrefix("func __safeDI_"), line.contains("Builder(_ scope: "), line.contains(".SafeDIMockScope_") {
					features.insert(.consumerFillsHole)
				}
				for leafIndex in leafIndices {
					let leafName = "\(prefix)T\(leafIndex)"
					if line.contains("\(leafName).mock(") {
						features.insert(.consumerCall)
						if line.contains(".instance") {
							features.insert(.consumerPassesInstance)
						}
						if line.contains("\(prefix)AnyT\(leafIndex)(\(leafName).mock(") {
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
		return features
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
