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
import SafeDICore
import Testing
@testable import SafeDIToolLibrary
@testable import SafeDIToolTestSupport

/// How a person calls a seam, against how generated code does. A tier that defers a parameter has two initializers: a
/// plain one that takes values, whose arguments a call evaluates when it is made and keeps nothing of the caller, and
/// one only generated code calls, with `__safeDI_`-prefixed labels, which defers each value so a `LazilyInstantiated`
/// the caller holds is created where it would be inline. These tests compile and run what the tool really emits.
struct SafeDIToolSeamPlainInitializerTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Fixtures

	/// `Feature`, the adopter's seam: a constant reads `a` while the tree is built, a `LazilyInstantiated` reads `b` when
	/// it is first read, and an `Instantiator` reads `c` when it is called. `StructFeature` is a struct that holds an
	/// `Instantiator` reading `c`, and `SendableFeature` holds a `SendableInstantiator` reading `c`.
	private static let featureFiles = [
		seamFixtureType(named: "EagerReader", declarations: ["@Received let a: Config"]),
		seamFixtureType(named: "LazyReader", declarations: ["@Received let b: Config"]),
		seamFixtureType(named: "Screen", isFinalClass: true, declarations: ["@Received let c: Config"]),
		seamFixtureType(named: "SendableScreen", isFinalClass: true, declarations: ["@Received let c: Config"], conformances: ", Sendable"),
		seamFixtureType(
			named: "Feature",
			isSeam: true,
			isFinalClass: true,
			declarations: ["@Instantiated let eager: EagerReader", "@Instantiated let lazy: LazilyInstantiated<LazyReader>", "@Instantiated let screenBuilder: Instantiator<Screen>"],
		),
		seamFixtureType(named: "StructFeature", isSeam: true, declarations: ["@Instantiated let screenBuilder: Instantiator<Screen>"]),
		seamFixtureType(named: "SendableFeature", isSeam: true, declarations: ["@Instantiated let screenBuilder: SendableInstantiator<SendableScreen>"], conformances: ", Sendable"),
	]

	/// The value every seam of `featureFiles` is passed, a type no `@Instantiable` declaration fulfills, as a person's own
	/// value usually is.
	private static let config = """
	public final class Config: Sendable {
	    public init(name: String) {
	        self.name = name
	    }

	    public let name: String
	}
	"""

	/// `featureFiles` and `handWrittenCalls` run through the tool and compiled, as a path the comparator can run.
	private mutating func handWrittenCallPath(_ handWrittenCalls: String) async throws -> DifferentialValuePath {
		let files = Self.featureFiles + [Self.config + "\n\n" + handWrittenCalls]
		let output = try await executeSafeDIToolTest(swiftFileContent: files, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		return DifferentialValuePath(
			fixtureFiles: Dictionary(uniqueKeysWithValues: files.enumerated().map { ("File\($0.offset).swift", $0.element) }),
			generatedFiles: output.dependencyTreeFiles,
		)
	}

	// MARK: Retention

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func handWrittenCall_releasesOwner_whenOwnerStoresSeamBuiltFromItsOwnProperty() async throws {
		// The three calls that kept the owner alive for as long as the seam lived: the value read lazily or behind an
		// instantiator, never read.
		let path = try await handWrittenCallPath("""
		final class Owner {
		    let config = Config(name: "owner")
		    var feature: Feature?

		    func buildReadingSelf() {
		        feature = Feature(a: self.config, b: self.config, c: self.config)
		    }

		    func buildWithCaptureLists() {
		        let fallback = Config(name: "fallback")
		        feature = Feature(
		            a: { [weak self] in self?.config ?? fallback }(),
		            b: { [weak self] in self?.config ?? fallback }(),
		            c: { [weak self] in self?.config ?? fallback }(),
		        )
		    }
		}

		func isReleased(afterBuilding build: (Owner) -> Void) -> Bool {
		    weak var weakOwner: Owner?
		    do {
		        let owner = Owner()
		        weakOwner = owner
		        build(owner)
		    }
		    return weakOwner == nil
		}

		func releasedReadingSelf() -> Bool {
		    isReleased { $0.buildReadingSelf() }
		}

		func releasedWithNoSelfWritten() -> Bool {
		    isReleased { owner in
		        owner.feature = Feature(a: owner.config, b: owner.config, c: owner.config)
		    }
		}

		func releasedWithCaptureLists() -> Bool {
		    isReleased { $0.buildWithCaptureLists() }
		}
		""")

		let description = try DifferentialValueOracle.describe(
			path,
			probes: ["releasedReadingSelf()", "releasedWithNoSelfWritten()", "releasedWithCaptureLists()"].map(DifferentialValueProbe.init),
			filesToDelete: &filesToDelete,
		)

		if compileVerificationIsEnabled {
			#expect(description == """
			probe releasedReadingSelf()
			Bool true
			probe releasedWithNoSelfWritten()
			Bool true
			probe releasedWithCaptureLists()
			Bool true

			""")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func handWrittenCall_releasesOwner_whenSeamTakesValueSendable() async throws {
		// A `@Sendable` deferred parameter: the plain initializer's closure captures its own parameter, never the caller.
		let path = try await handWrittenCallPath("""
		final class Owner {
		    let config = Config(name: "owner")
		    var feature: SendableFeature?

		    func build() {
		        feature = SendableFeature(c: self.config)
		    }
		}

		func released() -> Bool {
		    weak var weakOwner: Owner?
		    do {
		        let owner = Owner()
		        weakOwner = owner
		        owner.build()
		    }
		    return weakOwner == nil
		}
		""")

		let description = try DifferentialValueOracle.describe(path, probes: [DifferentialValueProbe("released()")], filesToDelete: &filesToDelete)

		if compileVerificationIsEnabled {
			#expect(description == """
			probe released()
			Bool true

			""")
		}
	}

	// MARK: Ordinary code

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func handWrittenCall_compilesAndPassesTheValue_whenArgumentIsCodeAnAutoclosureRejects() async throws {
		// Each of these is a compile error against an `@autoclosure` parameter: implicit `self`, `self` in a struct's `init`
		// or a `mutating` method, an `inout` parameter, `try`, and an unapplied reference typed with the value.
		let path = try await handWrittenCallPath("""
		final class ClassOwner {
		    let config = Config(name: "implicit self")

		    func build() -> Feature {
		        Feature(a: config, b: config, c: config)
		    }
		}

		struct ValueOwner {
		    var config = Config(name: "struct init")
		    var feature: StructFeature?

		    init() {
		        feature = StructFeature(c: config)
		    }

		    mutating func rebuild() {
		        config = Config(name: "mutating")
		        feature = StructFeature(c: config)
		    }
		}

		func viaInout(_ config: inout Config) -> StructFeature {
		    StructFeature(c: config)
		}

		func makeConfig() throws -> Config {
		    Config(name: "try")
		}

		func viaTry() throws -> StructFeature {
		    try StructFeature(c: makeConfig())
		}

		func viaUnappliedReference() -> [StructFeature] {
		    [Config(name: "unapplied")].map(StructFeature.init(c:))
		}

		func nameFromClass() -> String {
		    ClassOwner().build().screenBuilder.instantiate().c.name
		}

		func nameFromStructInit() -> String? {
		    ValueOwner().feature?.screenBuilder.instantiate().c.name
		}

		func nameFromMutating() -> String? {
		    var owner = ValueOwner()
		    owner.rebuild()
		    return owner.feature?.screenBuilder.instantiate().c.name
		}

		func nameFromInout() -> String {
		    var config = Config(name: "inout")
		    return viaInout(&config).screenBuilder.instantiate().c.name
		}

		func nameFromTry() throws -> String {
		    try viaTry().screenBuilder.instantiate().c.name
		}

		func nameFromUnappliedReference() -> [String] {
		    viaUnappliedReference().map { $0.screenBuilder.instantiate().c.name }
		}
		""")

		let description = try DifferentialValueOracle.describe(
			path,
			probes: ["nameFromClass()", "nameFromStructInit()", "nameFromMutating()", "nameFromInout()", "try! nameFromTry()", "nameFromUnappliedReference()"].map(DifferentialValueProbe.init),
			filesToDelete: &filesToDelete,
		)

		if compileVerificationIsEnabled {
			#expect(description == """
			probe nameFromClass()
			String "implicit self"
			probe nameFromStructInit()
			String "struct init"
			probe nameFromMutating()
			String "mutating"
			probe nameFromInout()
			String "inout"
			probe try! nameFromTry()
			String "try"
			probe nameFromUnappliedReference()
			Array<String>
			  0: String "unapplied"

			""")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func handWrittenCall_compiles_whenArgumentAwaitsOrReadsIsolatedProperty() async throws {
		// `await` in an argument, and properties of a global actor's type and of an actor. Compiled together with the seams
		// by `executeSafeDIToolTest`, and nothing to run: what an `@autoclosure` rejected is that these compile at all.
		let path = try await handWrittenCallPath("""
		func makeConfig() async -> Config {
		    Config(name: "await")
		}

		func viaAwait() async -> StructFeature {
		    await StructFeature(c: makeConfig())
		}

		func viaAwaitSendable() async -> SendableFeature {
		    await SendableFeature(c: makeConfig())
		}

		@MainActor
		final class MainActorOwner {
		    var config = Config(name: "main actor")

		    func build() -> StructFeature {
		        StructFeature(c: config)
		    }

		    func buildSendable() -> SendableFeature {
		        SendableFeature(c: config)
		    }
		}

		actor ActorOwner {
		    var config = Config(name: "actor")

		    func build() -> StructFeature {
		        StructFeature(c: config)
		    }

		    func buildSendable() -> SendableFeature {
		        SendableFeature(c: config)
		    }
		}

		func compiled() -> Bool {
		    true
		}
		""")

		let description = try DifferentialValueOracle.describe(path, probes: [DifferentialValueProbe("compiled()")], filesToDelete: &filesToDelete)

		if compileVerificationIsEnabled {
			#expect(description == """
			probe compiled()
			Bool true

			""")
		}
	}

	// MARK: When arguments are evaluated

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func handWrittenCall_evaluatesEveryArgumentAtTheCallInOrder_whenTreeNeverReadsThem() async throws {
		let path = try await handWrittenCallPath("""
		nonisolated(unsafe) var evaluated = [String]()

		func make(_ name: String) -> Config {
		    evaluated.append(name)
		    return Config(name: name)
		}

		func evaluatedAtTheCall() -> [String] {
		    evaluated = []
		    let feature = Feature(a: make("a"), b: make("b"), c: make("c"))
		    withExtendedLifetime(feature) {}
		    return evaluated
		}
		""")

		let description = try DifferentialValueOracle.describe(path, probes: [DifferentialValueProbe("evaluatedAtTheCall()")], filesToDelete: &filesToDelete)

		if compileVerificationIsEnabled {
			#expect(description == """
			probe evaluatedAtTheCall()
			Array<String>
			  0: String "a"
			  1: String "b"
			  2: String "c"

			""")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func handWrittenCall_readsTheValueOfTheCall_whenStoredVarChangesAfterIt() async throws {
		let path = try await handWrittenCallPath("""
		func nameAfterChange() -> String {
		    var config = Config(name: "at the call")
		    let feature = StructFeature(c: config)
		    config = Config(name: "after the call")
		    withExtendedLifetime(config) {}
		    return feature.screenBuilder.instantiate().c.name
		}
		""")

		let description = try DifferentialValueOracle.describe(path, probes: [DifferentialValueProbe("nameAfterChange()")], filesToDelete: &filesToDelete)

		if compileVerificationIsEnabled {
			#expect(description == """
			probe nameAfterChange()
			String "at the call"

			""")
		}
	}

	// MARK: Generated callers' timing

	/// The types the sixteen timing scenarios share, in module `Feature`: each one traces when it is created or built.
	private static let timingBaseFiles = [
		"""
		nonisolated(unsafe) public var traceSink = [String]()

		public func trace(_ line: String) {
		    traceSink.append(line)
		}

		public protocol Uploader: AnyObject {}
		public protocol ReadingUploader: AnyObject {}
		""",
		tracedValue(named: "A"),
		tracedValue(named: "B"),
		tracedValue(named: "C"),
		tracedValue(named: "Logger"),
		tracedValue(named: "Zebra"),
		tracedValue(named: "Apple"),
		tracedReceiver(named: "EagerReader", receives: "a: A"),
		tracedReceiver(named: "LazyReader", receives: "b: B"),
		tracedReceiver(named: "Screen", receives: "c: C"),
		tracedReceiver(named: "SendableScreen", receives: "c: C", conformances: ", Sendable"),
		tracedReceiver(named: "WrappedScreen", receives: "c: LazilyInstantiated<C>"),
		tracedReceiver(named: "ZebraReader", receives: "zebra: Zebra"),
		tracedReceiver(named: "AppleReader", receives: "apple: Apple"),
		"""
		@Instantiable
		public final class Header: Instantiable {
		    public init(logger: Logger?) {
		        self.logger = logger
		        trace("Header built, logger \\(logger == nil ? "nil" : "present")")
		    }

		    @Received(onlyIfAvailable: true) public let logger: Logger?
		}
		""",
	]

	/// `@Instantiable` `name`, which traces when it is created.
	private static func tracedValue(named name: String) -> String {
		"""
		@Instantiable
		public final class \(name): Instantiable, Sendable {
		    public init() {
		        trace("\(name) created")
		    }
		}
		"""
	}

	/// `@Instantiable` `name`, which receives `receives` and traces when it is built.
	private static func tracedReceiver(named name: String, receives: String, conformances: String = "") -> String {
		let label = receives.prefix { $0 != ":" }
		return """
		@Instantiable
		public final class \(name): Instantiable\(conformances) {
		    public init(\(receives)) {
		        self.\(label) = \(label)
		        trace("\(name) built")
		    }

		    @Received public let \(receives)
		}
		"""
	}

	/// The seams of the timing scenarios.
	private static let timingSeamFiles = [
		seamFixtureType(named: "InstantiatorSeam", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let screenBuilder: Instantiator<Screen>"]),
		seamFixtureType(named: "OrderSeam", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let zebraReader: ZebraReader", "@Instantiated public let appleReader: AppleReader"]),
		seamFixtureType(named: "InnerSeam", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let screenBuilder: Instantiator<Screen>"]),
		seamFixtureType(named: "OuterSeam", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let inner: InnerSeam"]),
		seamFixtureType(named: "AdopterFeature", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let eager: EagerReader", "@Instantiated public let lazy: LazilyInstantiated<LazyReader>"]),
		seamFixtureType(named: "OptionalSeam", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let headerBuilder: Instantiator<Header>"]),
		seamFixtureType(named: "SendableSeam", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let screenBuilder: SendableInstantiator<SendableScreen>"], conformances: ", Sendable"),
		seamFixtureType(named: "HoleSeam", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let screenBuilder: Instantiator<Screen>", "@Instantiated public let uploader: any Uploader"]),
		seamFixtureType(named: "ReadingHoleSeam", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let screenBuilder: Instantiator<Screen>", "@Instantiated public let uploader: any ReadingUploader"]),
		seamFixtureType(named: "WrapperSeam", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let screenBuilder: Instantiator<WrappedScreen>"]),
	]

	/// A root in module `App` with `declarations`.
	private static func timingRoot(named name: String, declarations: [String]) -> String {
		"import Feature\n\n" + seamFixtureType(named: name, isRoot: true, isFinalClass: true, declarations: declarations.map { "@Instantiated let \($0)" })
	}

	private static let timingAppFiles = [
		timingRoot(named: "LazyRoot", declarations: ["c: LazilyInstantiated<C>", "seam: InstantiatorSeam"]),
		timingRoot(named: "ConstantRoot", declarations: ["c: C", "seam: InstantiatorSeam"]),
		timingRoot(named: "OrderRoot", declarations: ["zebra: LazilyInstantiated<Zebra>", "apple: LazilyInstantiated<Apple>", "seam: OrderSeam"]),
		timingRoot(named: "NestedRoot", declarations: ["c: LazilyInstantiated<C>", "seam: OuterSeam"]),
		timingRoot(named: "BothLazyRoot", declarations: ["a: LazilyInstantiated<A>", "b: LazilyInstantiated<B>", "seam: AdopterFeature"]),
		timingRoot(named: "MixedRoot", declarations: ["a: LazilyInstantiated<A>", "b: B", "seam: AdopterFeature"]),
		timingRoot(named: "OptionalRoot", declarations: ["logger: LazilyInstantiated<Logger>", "seam: OptionalSeam"]),
		timingRoot(named: "NilRoot", declarations: ["seam: OptionalSeam"]),
		timingRoot(named: "SendableLazyRoot", declarations: ["c: SendableLazilyInstantiated<C>", "seam: InstantiatorSeam"]),
		timingRoot(named: "SendableParameterRoot", declarations: ["c: SendableLazilyInstantiated<C>", "seam: SendableSeam"]),
		timingRoot(named: "HoleRoot", declarations: ["c: LazilyInstantiated<C>", "seam: HoleSeam"]),
		timingRoot(named: "ReadingHoleRoot", declarations: ["c: LazilyInstantiated<C>", "seam: ReadingHoleSeam"]),
		timingRoot(named: "SharedRoot", declarations: ["c: LazilyInstantiated<C>", "first: InstantiatorSeam", "second: InstantiatorSeam"]),
		timingRoot(named: "WrapperRoot", declarations: ["c: LazilyInstantiated<C>", "seam: WrapperSeam"]),
		"""
		import Feature

		@Instantiable(fulfillingAdditionalTypes: [Uploader.self])
		public final class Up: Uploader, Instantiable {
		    public init() {
		        trace("Up built")
		    }
		}
		""",
		"""
		import Feature

		@Instantiable(fulfillingAdditionalTypes: [ReadingUploader.self])
		public final class ReadingUp: ReadingUploader, Instantiable {
		    public init(c: C) {
		        self.c = c
		        trace("ReadingUp built")
		    }

		    @Received public let c: C
		}
		""",
	]

	/// One function per scenario, each returning its trace: the caller is a generated root, built by the tool either
	/// calling the seam or inline, and the two traces must be equal.
	private static let timingScenarios = """
	import Feature

	func traced(_ body: () -> Void) -> [String] {
	    traceSink = []
	    body()
	    return traceSink
	}

	func heldLazilyTwoScreens() -> [String] {
	    traced {
	        let root = LazyRoot()
	        trace("built")
	        let first = root.seam.screenBuilder.instantiate()
	        trace("first")
	        let second = root.seam.screenBuilder.instantiate()
	        trace("second")
	        trace("shared \\(first.c === second.c) sameAsCaller \\(first.c === root.c.instance)")
	    }
	}

	func heldLazilyNoScreen() -> [String] {
	    traced {
	        let root = LazyRoot()
	        trace("built")
	        withExtendedLifetime(root) {}
	    }
	}

	func heldConstant() -> [String] {
	    traced {
	        let root = ConstantRoot()
	        trace("built")
	        _ = root.seam.screenBuilder.instantiate()
	    }
	}

	func twoLazyValuesReadWhileBuilding() -> [String] {
	    traced {
	        let root = OrderRoot()
	        trace("built")
	        withExtendedLifetime(root) {}
	    }
	}

	func seamOfASeam() -> [String] {
	    traced {
	        let root = NestedRoot()
	        trace("built")
	        _ = root.seam.inner.screenBuilder.instantiate()
	        _ = root.seam.inner.screenBuilder.instantiate()
	    }
	}

	func adopterBothLazy() -> [String] {
	    traced {
	        let root = BothLazyRoot()
	        trace("built")
	        _ = root.seam.lazy.instance
	    }
	}

	func adopterMixed() -> [String] {
	    traced {
	        let root = MixedRoot()
	        trace("built")
	        _ = root.seam.lazy.instance
	    }
	}

	func optionalParameterHeldLazily() -> [String] {
	    traced {
	        let root = OptionalRoot()
	        trace("built")
	        _ = root.seam.headerBuilder.instantiate()
	    }
	}

	func optionalParameterHeldByNothing() -> [String] {
	    traced {
	        let root = NilRoot()
	        trace("built")
	        _ = root.seam.headerBuilder.instantiate()
	    }
	}

	func sendableLazyIntoPlainParameter() -> [String] {
	    traced {
	        let root = SendableLazyRoot()
	        trace("built")
	        _ = root.seam.screenBuilder.instantiate()
	    }
	}

	func sendableLazyIntoSendableParameter() -> [String] {
	    traced {
	        let root = SendableParameterRoot()
	        trace("built")
	        _ = root.seam.screenBuilder.instantiate()
	    }
	}

	func holeFillReadsNoField() -> [String] {
	    traced {
	        let root = HoleRoot()
	        trace("built")
	        _ = root.seam.screenBuilder.instantiate()
	    }
	}

	func holeFillReadsField() -> [String] {
	    traced {
	        let root = ReadingHoleRoot()
	        trace("built")
	        _ = root.seam.screenBuilder.instantiate()
	    }
	}

	func twoSeamsShareOneLazy() -> [String] {
	    traced {
	        let root = SharedRoot()
	        trace("built")
	        let first = root.first.screenBuilder.instantiate()
	        let second = root.second.screenBuilder.instantiate()
	        trace("shared \\(first.c === second.c)")
	    }
	}

	func wrapperReceivedAsItself() -> [String] {
	    traced {
	        let root = WrapperRoot()
	        trace("built")
	        _ = root.seam.screenBuilder.instantiate()
	    }
	}
	"""

	private static let timingProbes = [
		"heldLazilyTwoScreens()",
		"heldLazilyNoScreen()",
		"heldConstant()",
		"twoLazyValuesReadWhileBuilding()",
		"seamOfASeam()",
		"adopterBothLazy()",
		"adopterMixed()",
		"optionalParameterHeldLazily()",
		"optionalParameterHeldByNothing()",
		"sendableLazyIntoPlainParameter()",
		"sendableLazyIntoSendableParameter()",
		"holeFillReadsNoField()",
		"holeFillReadsField()",
		"twoSeamsShareOneLazy()",
		"wrapperReceivedAsItself()",
	]

	/// `Feature` and `App`, the seam-world or inline build of `featureFiles`, run through the tool.
	private mutating func timingPath(featureFiles: [String], appFiles: [String], appFileNamedScenarios: String) async throws -> DifferentialValuePath {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: featureFiles),
				ModuleFixture(name: "App", packageName: "Store", swiftFileContent: appFiles + [appFileNamedScenarios], dependencies: ["Feature"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		func fixtureFiles(_ files: [String]) -> [String: String] {
			Dictionary(uniqueKeysWithValues: files.enumerated().map { ("File\($0.offset).swift", $0.element) })
		}
		return try DifferentialValuePath(modules: [
			DifferentialValueModule(name: "Feature", packageName: "Shop", fixtureFiles: fixtureFiles(featureFiles), generatedFiles: #require(output.modules["Feature"]).generatedFiles),
			DifferentialValueModule(name: "App", packageName: "Store", dependencyModuleNames: ["Feature"], fixtureFiles: fixtureFiles(appFiles + [appFileNamedScenarios]), generatedFiles: #require(output.modules["App"]).generatedFiles),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generatedCall_matchesInlineTiming_whenCallerHoldsLazyOrConstantValues() async throws {
		// Each scenario's trace says when each value and type was created: a generated caller of a seam must match the same
		// tree built inline, which is what the initializer only generated code calls exists for.
		let featureFiles = Self.timingBaseFiles + Self.timingSeamFiles
		let seamPath = try await timingPath(featureFiles: featureFiles, appFiles: Self.timingAppFiles, appFileNamedScenarios: Self.timingScenarios)
		let inlinePath = try await timingPath(featureFiles: inlineFixture(featureFiles), appFiles: Self.timingAppFiles, appFileNamedScenarios: Self.timingScenarios)

		try expectDifferentialValuesAgree(
			feature: seamPath,
			knownRight: inlinePath,
			probes: Self.timingProbes.map(DifferentialValueProbe.init),
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generatedCall_createsHeldValueWhenTreeFirstReadsIt_whenPublicTierOmitsPackageValue() async throws {
		// The sixteenth scenario: built inline, the caller could not construct the tree's `package` types, so its trace is
		// the inline one spelled out: the value is created when the first screen is built, after the seam returns.
		let tieredFiles = Self.timingBaseFiles + [
			"package final class Secret: Sendable {\n    package init() {}\n}",
			"""
			@Instantiable
			package final class SecretReader: Instantiable {
			    package init(secret: Secret?) {
			        self.secret = secret
			    }

			    @Received(onlyIfAvailable: true) package let secret: Secret?
			}
			""",
			"""
			@Instantiable(generateDependencyTree: true)
			public final class TierSeam: Instantiable {
			    package init(screenBuilder: Instantiator<Screen>, secretBuilder: Instantiator<SecretReader>) {
			        self.screenBuilder = screenBuilder
			        self.secretBuilder = secretBuilder
			    }

			    @Instantiated public let screenBuilder: Instantiator<Screen>
			    @Instantiated package let secretBuilder: Instantiator<SecretReader>
			}
			""",
		]
		let path = try await timingPath(
			featureFiles: tieredFiles,
			appFiles: [Self.timingRoot(named: "TierRoot", declarations: ["c: LazilyInstantiated<C>", "seam: TierSeam"])],
			appFileNamedScenarios: """
			import Feature

			func publicTierOmitsPackageValue() -> [String] {
			    traceSink = []
			    let root = TierRoot()
			    trace("built")
			    _ = root.seam.screenBuilder.instantiate()
			    return traceSink
			}
			""",
		)

		let description = try DifferentialValueOracle.describe(path, probes: [DifferentialValueProbe("publicTierOmitsPackageValue()")], filesToDelete: &filesToDelete)

		if compileVerificationIsEnabled {
			#expect(description == """
			probe publicTierOmitsPackageValue()
			Array<String>
			  0: String "built"
			  1: String "C created"
			  2: String "Screen built"

			""")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func handWrittenCall_keepsValueLazy_whenTreeReceivesLazilyInstantiatedAsItself() async throws {
		// Evaluating every argument at the call is what a person gets from a value. A type in the tree that wants laziness
		// receives the wrapper as itself, which a tier takes by value, so a person passes the wrapper.
		let featureFiles = Self.timingBaseFiles + Self.timingSeamFiles
		let path = try await timingPath(
			featureFiles: featureFiles,
			appFiles: [],
			appFileNamedScenarios: """
			import Feature
			import SafeDI

			func handWrittenWrapper() -> [String] {
			    traceSink = []
			    let c = LazilyInstantiated<C> { C() }
			    let seam = WrapperSeam(c: c)
			    trace("built")
			    let screen = seam.screenBuilder.instantiate()
			    trace("screen returned")
			    _ = screen.c.instance
			    return traceSink
			}
			""",
		)

		let description = try DifferentialValueOracle.describe(path, probes: [DifferentialValueProbe("handWrittenWrapper()")], filesToDelete: &filesToDelete)

		if compileVerificationIsEnabled {
			#expect(description == """
			probe handWrittenWrapper()
			Array<String>
			  0: String "built"
			  1: String "WrappedScreen built"
			  2: String "screen returned"
			  3: String "C created"

			""")
		}
	}

	/// `JobHoleSeam`, whose tree receives `c` and holds a hole filled in another module, as the Manual's builder example does:
	/// `App`'s implementation builds `Job`s that read `c`, generated in `JobUp` and hand-written in `HandWrittenUploader`.
	private mutating func jobHolePath(appFileNamedScenarios: String) async throws -> DifferentialValuePath {
		let featureFiles = Self.timingBaseFiles + [
			"""
			public protocol JobUploader: AnyObject {
			    func buildJob()
			}
			""",
			Self.tracedReceiver(named: "Job", receives: "c: C"),
			seamFixtureType(named: "JobHoleSeam", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let screenBuilder: Instantiator<Screen>", "@Instantiated public let uploader: any JobUploader"]),
		]
		let appFiles = [
			Self.timingRoot(named: "JobHoleRoot", declarations: ["c: LazilyInstantiated<C>", "seam: JobHoleSeam"]),
			"""
			import Feature
			import SafeDI

			@Instantiable(fulfillingAdditionalTypes: [JobUploader.self])
			public final class JobUp: JobUploader, Instantiable {
			    public init(jobBuilder: Instantiator<Job>) {
			        self.jobBuilder = jobBuilder
			    }

			    public func buildJob() {
			        _ = jobBuilder.instantiate()
			    }

			    @Instantiated public let jobBuilder: Instantiator<Job>
			}
			""",
		]
		return try await timingPath(featureFiles: featureFiles, appFiles: appFiles, appFileNamedScenarios: appFileNamedScenarios)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func handWrittenCall_createsArgumentBeforeSeamIsBuilt_whenHoleImplementationReadsItsStructField() async throws {
		// The Manual's hand-written call: the implementation reads the struct's field only when a `Job` is built, but the
		// argument is a value, so it exists already.
		let path = try await jobHolePath(appFileNamedScenarios: """
		import Feature
		import SafeDI

		final class HandWrittenUploader: JobUploader {
		    init(jobBuilder: Instantiator<Job>) {
		        self.jobBuilder = jobBuilder
		    }

		    func buildJob() {
		        _ = jobBuilder.instantiate()
		    }

		    let jobBuilder: Instantiator<Job>
		}

		func handWrittenCall() -> [String] {
		    traceSink = []
		    let seam = JobHoleSeam(c: C(), jobUploaderBuilder: { scope in
		        switch scope {
		        case let .uploader(values):
		            HandWrittenUploader(jobBuilder: Instantiator { Job(c: values.c) })
		        }
		    })
		    trace("built")
		    seam.uploader.buildJob()
		    return traceSink
		}
		""")

		let description = try DifferentialValueOracle.describe(path, probes: [DifferentialValueProbe("handWrittenCall()")], filesToDelete: &filesToDelete)

		if compileVerificationIsEnabled {
			#expect(description == """
			probe handWrittenCall()
			Array<String>
			  0: String "C created"
			  1: String "built"
			  2: String "Job built"

			""")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generatedCall_createsHeldValueWhenFirstJobIsBuilt_whenHoleImplementationReadsItInsideInstantiator() async throws {
		// The same tree reached by a generated call from a root that holds the value lazily: nothing reads it until a `Job`
		// is built, as inline.
		let path = try await jobHolePath(appFileNamedScenarios: """
		import Feature

		func generatedCall() -> [String] {
		    traceSink = []
		    let root = JobHoleRoot()
		    trace("built")
		    root.seam.uploader.buildJob()
		    return traceSink
		}
		""")

		let description = try DifferentialValueOracle.describe(path, probes: [DifferentialValueProbe("generatedCall()")], filesToDelete: &filesToDelete)

		if compileVerificationIsEnabled {
			#expect(description == """
			probe generatedCall()
			Array<String>
			  0: String "built"
			  1: String "C created"
			  2: String "Job built"

			""")
		}
	}

	// MARK: The code the tool emits

	/// `User`, an `@Instantiable` type a root can build.
	private static let user = """
	@Instantiable
	public final class User: Instantiable, Sendable {
	    public init() {}
	}
	"""

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_emitsPlainInitializerAndPrefixedOne_whenTierDefersParameters() async throws {
		// The plain initializer forwards its values; the other is the deferral, under prefixed labels. The caller, which
		// holds one parameter lazily and one by value, calls the prefixed one.
		let files = [
			seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let a: LazilyInstantiated<User>", "@Instantiated let b: User", "@Instantiated let feature: Feature"]),
			seamFixtureType(named: "EagerReader", declarations: ["@Received let a: User"]),
			seamFixtureType(named: "LazyReader", declarations: ["@Received let b: User"]),
			seamFixtureType(named: "Feature", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let eager: EagerReader", "@Instantiated let lazy: LazilyInstantiated<LazyReader>"]),
			Self.user,
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: files, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles["Feature+SafeDI.swift"] == generatedFileHeader + """
		extension Feature {
		    public convenience init(a: User, b: User) {
		        self.init(__safeDI_a: a, __safeDI_b: b)
		    }

		    public convenience init(__safeDI_a: @autoclosure @escaping () -> User, __safeDI_b: @autoclosure @escaping () -> User) {
		        let a = LazilyInstantiated<User>(__safeDI_a)
		        let b = LazilyInstantiated<User>(__safeDI_b)
		        let eager = EagerReader(a: a.instance)
		        func __safeDI_lazy() -> LazyReader {
		            LazyReader(b: b.instance)
		        }
		        let lazy = LazilyInstantiated<LazyReader>(__safeDI_lazy)
		        self.init(eager: eager, lazy: lazy)
		    }
		}

		extension Feature {
		    public enum __safeDI_Feature_E60F90849A6CBFB6 {}
		}
		""")
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        func __safeDI_a() -> User {
		            User()
		        }
		        let a = LazilyInstantiated<User>(__safeDI_a)
		        let b = User()
		        func __safeDI_feature() -> Feature {
		            _ = Feature.__safeDI_Feature_E60F90849A6CBFB6.self
		            return Feature(__safeDI_a: a.instance, __safeDI_b: b)
		        }
		        let feature: Feature = __safeDI_feature()
		        self.init(a: a, b: b, feature: feature)
		    }
		}
		""")
	}

	/// A seam with a `public` tier that takes `c` and an `internal` tier that also takes `secret`, an `internal` type, with
	/// `parameterType` spelling how the tree receives `c` and `secretType` how it receives `secret`, and a function that
	/// calls each tier by hand, reading what each returns.
	private static func tierFiles(parameterType: String, secretType: String, value: String, readerType: String = "Instantiator<Reader>", conformances: String = "") -> [String] {
		[
			seamFixtureType(named: "Reader", isFinalClass: true, declarations: ["@Received let c: \(parameterType)"], conformances: conformances),
			"""
			final class Secret: Instantiable, Sendable {
			    init() {}
			}

			@Instantiable
			struct SecretReader: Instantiable\(conformances) {
			    init(secret: \(secretType)) {
			        self.secret = secret
			    }

			    @Received(onlyIfAvailable: true) let secret: \(secretType)
			}

			func callEachTier() -> [String] {
			    let value = \(value)
			    let publicTier = Seam(c: value)
			    let internalTier = Seam(c: value, secret: nil)
			    return [String(describing: type(of: publicTier.readerBuilder)), String(describing: type(of: internalTier.secretBuilder))]
			}
			""",
			user,
			"""
			@Instantiable(generateDependencyTree: true)
			public final class Seam: Instantiable\(conformances) {
			    init(readerBuilder: \(readerType), secretBuilder: \(readerType.replacingOccurrences(of: "Reader", with: "SecretReader"))) {
			        self.readerBuilder = readerBuilder
			        self.secretBuilder = secretBuilder
			    }

			    @Instantiated public let readerBuilder: \(readerType)
			    @Instantiated let secretBuilder: \(readerType.replacingOccurrences(of: "Reader", with: "SecretReader"))
			}
			""",
		]
	}

	/// `files` run through the tool, with `callEachTier()`, which calls each tier by hand, compiled and run.
	private mutating func tierOutput(of files: [String], expectingDescriptionOf builderTypes: (String, String)) async throws -> TestOutput {
		let output = try await executeSafeDIToolTest(swiftFileContent: files, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let path = DifferentialValuePath(
			fixtureFiles: Dictionary(uniqueKeysWithValues: files.enumerated().map { ("File\($0.offset).swift", $0.element) }),
			generatedFiles: output.dependencyTreeFiles,
		)
		let description = try DifferentialValueOracle.describe(path, probes: [DifferentialValueProbe("callEachTier()")], filesToDelete: &filesToDelete)
		if compileVerificationIsEnabled {
			#expect(description == """
			probe callEachTier()
			Array<String>
			  0: String "\(builderTypes.0)"
			  1: String "\(builderTypes.1)"

			""")
		}
		return output
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_emitsTwoInitializersPerTier_whenEveryTierDefersAParameter() async throws {
		let files = Self.tierFiles(parameterType: "User", secretType: "Secret?", value: "User()")
		let output = try await tierOutput(of: files, expectingDescriptionOf: ("Instantiator<Reader>", "Instantiator<SecretReader>"))
		#expect(output.dependencyTreeFiles["Seam+SafeDI.swift"] == generatedFileHeader + """
		extension Seam {
		    public convenience init(c: User) {
		        self.init(__safeDI_c: c)
		    }

		    public convenience init(__safeDI_c: @autoclosure @escaping () -> User) {
		        self.init(__safeDI_c: __safeDI_c(), __safeDI_secret: nil)
		    }

		    internal convenience init(c: User, secret: Secret?) {
		        self.init(__safeDI_c: c, __safeDI_secret: secret)
		    }

		    internal convenience init(__safeDI_c: @autoclosure @escaping () -> User, __safeDI_secret: @autoclosure @escaping () -> Secret?) {
		        let c = LazilyInstantiated<User>(__safeDI_c)
		        let secret = LazilyInstantiated<Secret?>(__safeDI_secret)
		        func __safeDI_readerBuilder() -> Reader {
		            Reader(c: c.instance)
		        }
		        let readerBuilder = Instantiator<Reader>(__safeDI_readerBuilder)
		        func __safeDI_secretBuilder() -> SecretReader {
		            SecretReader(secret: secret.instance)
		        }
		        let secretBuilder = Instantiator<SecretReader>(__safeDI_secretBuilder)
		        self.init(readerBuilder: readerBuilder, secretBuilder: secretBuilder)
		    }
		}

		extension Seam {
		    public enum __safeDI_Seam_6D03BBA97CB337EC {}
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_emitsOneInitializerForWideTierAndTwoForNarrow_whenOnlyNarrowTierDefers() async throws {
		// The `public` tier takes only a wrapper, by value, so it has one initializer, which calls the narrow tier's prefixed
		// one; the `internal` tier defers `secret`, so its wrapper parameter is prefixed too, keeping the name its tree reads.
		let files = Self.tierFiles(parameterType: "Instantiator<User>", secretType: "Secret?", value: "Instantiator<User> { User() }")
		let output = try await tierOutput(of: files, expectingDescriptionOf: ("Instantiator<Reader>", "Instantiator<SecretReader>"))
		#expect(output.dependencyTreeFiles["Seam+SafeDI.swift"] == generatedFileHeader + """
		extension Seam {
		    public convenience init(c: Instantiator<User>) {
		        self.init(__safeDI_c: c, __safeDI_secret: nil)
		    }

		    internal convenience init(c: Instantiator<User>, secret: Secret?) {
		        self.init(__safeDI_c: c, __safeDI_secret: secret)
		    }

		    internal convenience init(__safeDI_c c: Instantiator<User>, __safeDI_secret: @autoclosure @escaping () -> Secret?) {
		        let secret = LazilyInstantiated<Secret?>(__safeDI_secret)
		        func __safeDI_readerBuilder() -> Reader {
		            Reader(c: c)
		        }
		        let readerBuilder = Instantiator<Reader>(__safeDI_readerBuilder)
		        func __safeDI_secretBuilder() -> SecretReader {
		            SecretReader(secret: secret.instance)
		        }
		        let secretBuilder = Instantiator<SecretReader>(__safeDI_secretBuilder)
		        self.init(readerBuilder: readerBuilder, secretBuilder: secretBuilder)
		    }
		}

		extension Seam {
		    public enum __safeDI_Seam_89D2B05C913A7A48 {}
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_emitsOneInitializerPerTier_whenNoTierDefers() async throws {
		let files = Self.tierFiles(parameterType: "Instantiator<User>", secretType: "Instantiator<Secret>?", value: "Instantiator<User> { User() }")
		let output = try await tierOutput(of: files, expectingDescriptionOf: ("Instantiator<Reader>", "Instantiator<SecretReader>"))
		#expect(output.dependencyTreeFiles["Seam+SafeDI.swift"] == generatedFileHeader + """
		extension Seam {
		    public convenience init(c: Instantiator<User>) {
		        self.init(c: c, secret: nil)
		    }

		    internal convenience init(c: Instantiator<User>, secret: Instantiator<Secret>?) {
		        func __safeDI_readerBuilder() -> Reader {
		            Reader(c: c)
		        }
		        let readerBuilder = Instantiator<Reader>(__safeDI_readerBuilder)
		        func __safeDI_secretBuilder() -> SecretReader {
		            SecretReader(secret: secret)
		        }
		        let secretBuilder = Instantiator<SecretReader>(__safeDI_secretBuilder)
		        self.init(readerBuilder: readerBuilder, secretBuilder: secretBuilder)
		    }
		}

		extension Seam {
		    public enum __safeDI_Seam_D5DD29724EAB946A {}
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesValuesOnPlainInitializerAndSendableAutoclosuresOnPrefixedOne_whenSendableBuilderReadsParameters() async throws {
		let files = Self.tierFiles(parameterType: "User", secretType: "Secret?", value: "User()", readerType: "SendableInstantiator<Reader>", conformances: ", Sendable")
		let output = try await tierOutput(of: files, expectingDescriptionOf: ("SendableInstantiator<Reader>", "SendableInstantiator<SecretReader>"))
		#expect(output.dependencyTreeFiles["Seam+SafeDI.swift"] == generatedFileHeader + """
		extension Seam {
		    public convenience init(c: User) {
		        self.init(__safeDI_c: c)
		    }

		    public convenience init(__safeDI_c: @autoclosure @escaping @Sendable () -> User) {
		        self.init(__safeDI_c: __safeDI_c(), __safeDI_secret: nil)
		    }

		    internal convenience init(c: User, secret: Secret?) {
		        self.init(__safeDI_c: c, __safeDI_secret: secret)
		    }

		    internal convenience init(__safeDI_c: @autoclosure @escaping @Sendable () -> User, __safeDI_secret: @autoclosure @escaping @Sendable () -> Secret?) {
		        let c = SendableLazilyInstantiated<User>(__safeDI_c)
		        let secret = SendableLazilyInstantiated<Secret?>(__safeDI_secret)
		        @Sendable func __safeDI_readerBuilder() -> Reader {
		            Reader(c: c.instance)
		        }
		        let readerBuilder = SendableInstantiator<Reader>(__safeDI_readerBuilder)
		        @Sendable func __safeDI_secretBuilder() -> SecretReader {
		            SecretReader(secret: secret.instance)
		        }
		        let secretBuilder = SendableInstantiator<SecretReader>(__safeDI_secretBuilder)
		        self.init(readerBuilder: readerBuilder, secretBuilder: secretBuilder)
		    }
		}

		extension Seam {
		    public enum __safeDI_Seam_0B24AF5A9DF774B8 {}
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsPrefixedLabelsAndPlainParameters_whenLabelsAreKeywordsAndRawIdentifiers() async throws {
		// `default` is a keyword only a parameter's name must escape, `inout` must be escaped as a label too, and a raw
		// identifier keeps its backticks once the prefix joins it. A hand-written call compiles against the plain spelling,
		// and the caller against the prefixed one.
		let files = [
			seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let `default`: LazilyInstantiated<User>", "@Instantiated let `inout`: LazilyInstantiated<User>", "@Instantiated let `my label`: LazilyInstantiated<User>", "@Instantiated let seam: Seam"]),
			"""
			@Instantiable
			public struct Reader: Instantiable {
			    public init(default: User, `inout`: User, `my label`: User) {
			        self.default = `default`
			        self.inout = `inout`
			        self.`my label` = `my label`
			    }

			    @Received let `default`: User
			    @Received let `inout`: User
			    @Received let `my label`: User
			}
			""",
			seamFixtureType(named: "Seam", isSeam: true, declarations: ["@Instantiated let readerBuilder: Instantiator<Reader>"]),
			Self.user + """


			func callByHand() -> Seam {
			    let user = User()
			    return Seam(default: user, `inout`: user, `my label`: user)
			}
			""",
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: files, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles["Seam+SafeDI.swift"] == generatedFileHeader + """
		extension Seam {
		    public init(`default`: User, `inout`: User, `my label`: User) {
		        self.init(__safeDI_default: `default`, __safeDI_inout: `inout`, `__safeDI_my label`: `my label`)
		    }

		    public init(__safeDI_default: @autoclosure @escaping () -> User, __safeDI_inout: @autoclosure @escaping () -> User, `__safeDI_my label`: @autoclosure @escaping () -> User) {
		        let `default` = LazilyInstantiated<User>(__safeDI_default)
		        let `inout` = LazilyInstantiated<User>(__safeDI_inout)
		        let `my label` = LazilyInstantiated<User>(`__safeDI_my label`)
		        func __safeDI_readerBuilder() -> Reader {
		            Reader(default: `default`.instance, `inout`: `inout`.instance, `my label`: `my label`.instance)
		        }
		        let readerBuilder = Instantiator<Reader>(__safeDI_readerBuilder)
		        self.init(readerBuilder: readerBuilder)
		    }
		}

		extension Seam {
		    public enum __safeDI_Seam_A5328BC32DDA9F57 {}
		}
		""")
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        func __safeDI_default() -> User {
		            User()
		        }
		        let `default` = LazilyInstantiated<User>(__safeDI_default)
		        func __safeDI_inout() -> User {
		            User()
		        }
		        let `inout` = LazilyInstantiated<User>(__safeDI_inout)
		        func `__safeDI_my label`() -> User {
		            User()
		        }
		        let `my label` = LazilyInstantiated<User>(`__safeDI_my label`)
		        func __safeDI_seam() -> Seam {
		            _ = Seam.__safeDI_Seam_A5328BC32DDA9F57.self
		            return Seam(__safeDI_default: `default`.instance, __safeDI_inout: `inout`.instance, `__safeDI_my label`: `my label`.instance)
		        }
		        let seam: Seam = __safeDI_seam()
		        self.init(default: `default`, `inout`: `inout`, `my label`: `my label`, seam: seam)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresBuilderWithoutUnderscoredName_whenTierDefersNothing() async throws {
		// A tier that defers nothing has one initializer, which documentation must list, so no parameter name has an
		// underscore; the tree still reads the builder by its reserved name, bound first, so a declaration of the builder's
		// label in the tree cannot hide it.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					"public protocol UserService: Sendable {}",
					seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let userService: any UserService"]),
				]),
				ModuleFixture(name: "App", packageName: "Store", swiftFileContent: [
					"import Feature\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let service: Service"]),
					"""
					import Feature

					@Instantiable(fulfillingAdditionalTypes: [UserService.self])
					public struct DefaultUserService: UserService, Instantiable {
					    public init() {}
					}
					""",
				], dependencies: ["Feature"]),
			],
			integration: .swiftPackagePlugin,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles["Service+SafeDI.swift"] == generatedFileHeader + """
		extension Service {
		    @frozen public enum SafeDIScope_UserService {
		        case userService(userService_Values)

		        public struct userService_Values {}
		    }

		    public init(userServiceBuilder: @escaping (SafeDIScope_UserService) -> any UserService) {
		        let __safeDI_userServiceBuilder = userServiceBuilder
		        let userService: any UserService = __safeDI_userServiceBuilder(.userService(SafeDIScope_UserService.userService_Values()))
		        self.init(userService: userService)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_F61C88110D16DE79 {}
		}
		""")
	}

	// MARK: Private

	private var filesToDelete: [URL]
}
