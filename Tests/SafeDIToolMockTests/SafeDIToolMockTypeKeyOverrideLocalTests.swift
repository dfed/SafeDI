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
@testable import SafeDICore
@testable import SafeDIToolLibrary
@testable import SafeDIToolTestSupport

/// A `@Sendable` builder function of an internal mock reads the overrides beneath it into locals before the function
/// (`SendableOverrideExtractor`). Under the type key's layout, such a place is laid out where every place beneath it is
/// recorded: its call binds what it hands the function before it calls (`PassedArgument.bindsBeforeCall`), as the
/// walk binds the locals. A place beneath it that keeps the walk's text keeps the walk's body for the whole root. Each
/// cell compares the values the laid-out mock builds with the walk's.
struct SafeDIToolMockTypeKeyOverrideLocalTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_laysOutSendableBuilderOfConfiguredNode_whenEveryPlaceBeneathIsRecorded() async throws {
		let mocks = try await generatedMocks(of: Self.configuredNodeFixture)
		let laidOut = mocks.laidOut.mockFiles["Root+SafeDIMock.swift"] ?? ""
		let walk = mocks.walk.mockFiles["Root+SafeDIMock.swift"] ?? ""

		#expect(laidOut == generatedFileHeader + """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            screenBuilder: Screen.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                screenBuilder: screenBuilder
		            )
		        }

		        var screenBuilder: Screen.SafeDIMockConfiguration { __safeDI_storage.screenBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage: Sendable {
		            init(
		                screenBuilder: Screen.SafeDIMockConfiguration
		            ) {
		                self.screenBuilder = screenBuilder
		            }

		            let screenBuilder: Screen.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        @Sendable nonisolated func __safeDI_screenBuilder(__safeDI_Screen_configuration: Screen.SafeDIMockConfiguration) -> Screen {
		            let leaf = if let safeDIBuilder = __safeDI_Screen_configuration.leaf { safeDIBuilder() } else { Leaf() }
		            return if let safeDIBuilder = __safeDI_Screen_configuration.safeDIBuilder { safeDIBuilder(leaf, __safeDI_Screen_configuration.title()) } else { Screen(leaf: leaf, title: __safeDI_Screen_configuration.title()) }
		        }
		        let __safeDI_screenBuilder____safeDI_Screen_configuration: Screen.SafeDIMockConfiguration = safeDIOverrides.screenBuilder
		        let screenBuilder = SendableInstantiator<Screen> {
		            __safeDI_screenBuilder(__safeDI_Screen_configuration: __safeDI_screenBuilder____safeDI_Screen_configuration)
		        }
		        return Root(screenBuilder: screenBuilder)
		    }
		}
		#endif
		""", "Unexpected output \(laidOut)")
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: Self.configuredNodeFixture, probes: [
			DifferentialValueProbe("Root.mock().screenBuilder.instantiate()"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(screenBuilder: .init(leaf: { Leaf.tagged(1) }, title: \"overridden\"))).screenBuilder.instantiate()"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(screenBuilder: .init(leaf: nil) { leaf, _ in Screen(leaf: leaf, title: \"built\") })).screenBuilder.instantiate()"),
		])
		#expect(walk != laidOut)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_laysOutSendableBuilderReadingOverrideClosure_whenNodeHasNoConfiguration() async throws {
		let mocks = try await generatedMocks(of: Self.overrideClosureFixture)
		let laidOut = mocks.laidOut.mockFiles["Root+SafeDIMock.swift"] ?? ""
		let walk = mocks.walk.mockFiles["Root+SafeDIMock.swift"] ?? ""

		#expect(laidOut == generatedFileHeader + """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            leafBuilder: (@Sendable () -> Leaf)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                leafBuilder: leafBuilder
		            )
		        }

		        var leafBuilder: (@Sendable () -> Leaf)? { __safeDI_storage.leafBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage: Sendable {
		            init(
		                leafBuilder: (@Sendable () -> Leaf)?
		            ) {
		                self.leafBuilder = leafBuilder
		            }

		            let leafBuilder: (@Sendable () -> Leaf)?
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        @Sendable nonisolated func __safeDI_leafBuilder(__safeDI_Leaf_configuration: (@Sendable () -> Leaf)?) -> Leaf {
		            if let safeDIBuilder = __safeDI_Leaf_configuration { safeDIBuilder() } else { Leaf() }
		        }
		        let __safeDI_leafBuilder____safeDI_Leaf_configuration: (@Sendable () -> Leaf)? = safeDIOverrides.leafBuilder
		        let leafBuilder = SendableInstantiator<Leaf> {
		            __safeDI_leafBuilder(__safeDI_Leaf_configuration: __safeDI_leafBuilder____safeDI_Leaf_configuration)
		        }
		        return Root(leafBuilder: leafBuilder)
		    }
		}
		#endif
		""", "Unexpected output \(laidOut)")
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: Self.overrideClosureFixture, probes: [
			DifferentialValueProbe("Root.mock().leafBuilder.instantiate()"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(leafBuilder: { Leaf.tagged(2) })).leafBuilder.instantiate()"),
		])
		#expect(walk != laidOut)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_laysOutSendableAutoclosureBinding_whenTypeBeneathSendableBuilderInstantiatesUncoveredDependency() async throws {
		let mocks = try await generatedMocks(of: Self.sendableAutoclosureFixture)
		let laidOut = mocks.laidOut.mockFiles["Root+SafeDIMock.swift"] ?? ""
		let walk = mocks.walk.mockFiles["Root+SafeDIMock.swift"] ?? ""

		#expect(laidOut == generatedFileHeader + """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            screenBuilder: Screen.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                screenBuilder: screenBuilder
		            )
		        }

		        var screenBuilder: Screen.SafeDIMockConfiguration { __safeDI_storage.screenBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage: Sendable {
		            init(
		                screenBuilder: Screen.SafeDIMockConfiguration
		            ) {
		                self.screenBuilder = screenBuilder
		            }

		            let screenBuilder: Screen.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        missing: @autoclosure @escaping @Sendable () -> Missing,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let __safeDI_missing = missing
		        @Sendable nonisolated func __safeDI_panel(__safeDI_Panel_configuration: Panel.SafeDIMockConfiguration) -> Panel {
		            let missing = __safeDI_missing()
		            let leaf = if let safeDIBuilder = __safeDI_Panel_configuration.leaf { safeDIBuilder() } else { Leaf() }
		            return if let safeDIBuilder = __safeDI_Panel_configuration.safeDIBuilder { safeDIBuilder(leaf, missing) } else { Panel(leaf: leaf, missing: missing) }
		        }
		        @Sendable nonisolated func __safeDI_screenBuilder(__safeDI_Screen_configuration: Screen.SafeDIMockConfiguration) -> Screen {
		            let panel: Panel = __safeDI_panel(__safeDI_Panel_configuration: __safeDI_Screen_configuration.panel)
		            return if let safeDIBuilder = __safeDI_Screen_configuration.safeDIBuilder { safeDIBuilder(panel) } else { Screen(panel: panel) }
		        }
		        let __safeDI_screenBuilder____safeDI_Screen_configuration: Screen.SafeDIMockConfiguration = safeDIOverrides.screenBuilder
		        let screenBuilder = SendableInstantiator<Screen> {
		            __safeDI_screenBuilder(__safeDI_Screen_configuration: __safeDI_screenBuilder____safeDI_Screen_configuration)
		        }
		        return Root(screenBuilder: screenBuilder)
		    }
		}
		#endif
		""", "Unexpected output \(laidOut)")
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: Self.sendableAutoclosureFixture, probes: [
			DifferentialValueProbe("Root.mock(missing: Missing(tag: 1)).screenBuilder.instantiate()"),
			DifferentialValueProbe("Root.mock(missing: Missing(tag: 2), safeDIOverrides: .init(screenBuilder: .init(panel: .init(leaf: { Leaf.tagged(3) })))).screenBuilder.instantiate()"),
			DifferentialValueProbe(name: "autoclosure evaluated once per construction", expression: "{ let builder = Root.mock(missing: Missing.next()).screenBuilder; return [builder.instantiate().panel.missing.tag, builder.instantiate().panel.missing.tag] }()"),
		])
		#expect(walk != laidOut)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_laysOutReceiverBindings_whenTypeBuiltTwiceReceivesFlatParameterNamedApart() async throws {
		let mocks = try await generatedMocks(of: Self.receiverBindingFixture)
		let laidOut = mocks.laidOut.mockFiles["Root+SafeDIMock.swift"] ?? ""
		let walk = mocks.walk.mockFiles["Root+SafeDIMock.swift"] ?? ""

		#expect(laidOut == generatedFileHeader + """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            first: ((Service) -> User)? = nil,
		            second: ((Service) -> User)? = nil,
		            named: ((String) -> NamedUser)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                first: first,
		                second: second,
		                named: named
		            )
		        }

		        var first: ((Service) -> User)? { __safeDI_storage.first }
		        var second: ((Service) -> User)? { __safeDI_storage.second }
		        var named: ((String) -> NamedUser)? { __safeDI_storage.named }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                first: ((Service) -> User)?,
		                second: ((Service) -> User)?,
		                named: ((String) -> NamedUser)?
		            ) {
		                self.first = first
		                self.second = second
		                self.named = named
		            }

		            let first: ((Service) -> User)?
		            let second: ((Service) -> User)?
		            let named: ((String) -> NamedUser)?
		        }
		    }

		    static func mock(
		        service_Service: Service,
		        service_String: String,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_first(__safeDI_User_configuration: ((Service) -> User)?) -> User {
		            let service: Service = service_Service
		            return if let safeDIBuilder = __safeDI_User_configuration { safeDIBuilder(service) } else { User(service: service) }
		        }
		        let first: User = __safeDI_first(__safeDI_User_configuration: safeDIOverrides.first)
		        let second: User = __safeDI_first(__safeDI_User_configuration: safeDIOverrides.second)
		        func __safeDI_named(__safeDI_NamedUser_configuration: ((String) -> NamedUser)?) -> NamedUser {
		            let service: String = service_String
		            return if let safeDIBuilder = __safeDI_NamedUser_configuration { safeDIBuilder(service) } else { NamedUser(service: service) }
		        }
		        let named: NamedUser = __safeDI_named(__safeDI_NamedUser_configuration: safeDIOverrides.named)
		        return Root(first: first, second: second, named: named)
		    }
		}
		#endif
		""", "Unexpected output \(laidOut)")
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: Self.receiverBindingFixture, probes: [
			DifferentialValueProbe("{ let root = Root.mock(service_Service: Service(tag: 1), service_String: \"named\"); return [String(root.first.service.tag), String(root.second.service.tag), root.named.service] }()"),
		])
		#expect(walk != laidOut)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_keepsWalksBody_whenPlaceBeneathSendableBuilderIsUnrecorded() async throws {
		let mocks = try await generatedMocks(of: Self.unrecordedPlaceBeneathFixture)
		let laidOut = mocks.laidOut.mockFiles["Root+SafeDIMock.swift"] ?? ""
		let walk = mocks.walk.mockFiles["Root+SafeDIMock.swift"] ?? ""

		#expect(laidOut == walk)
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: Self.unrecordedPlaceBeneathFixture, probes: [
			DifferentialValueProbe("Root.mock().screenBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate().leaf.tag"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(screenBuilder: .init(leaf: { Leaf.tagged(3) }))).screenBuilder.instantiate().leaf.tag"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_keepsWalksBody_whenRootEntersMockedLazyCycle() async throws {
		// Which edge of the cycle `computeCycleEdges` prunes follows the types' names, and so does whether a root's walk
		// crosses it or only closes the cycle on it: every root that builds both types of the edge keeps the walk's body.
		let mocks = try await generatedMocks(of: Self.mockedLazyCycleFixture)
		for file in ["Alpha+SafeDIMock.swift", "Bravo+SafeDIMock.swift", "Root+SafeDIMock.swift"] {
			#expect(mocks.laidOut.mockFiles[file] == mocks.walk.mockFiles[file], "\(file)")
		}
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: Self.mockedLazyCycleFixture, probes: [
			DifferentialValueProbe("Root.mock().alphaBuilder.instantiate().bravoBuilder.instantiate().badge.title"),
			DifferentialValueProbe("Bravo.mock(safeDIOverrides: .init(badge: .init(title: \"bravo\"))).alphaBuilder.instantiate().bravoBuilder.instantiate().badge.title"),
			DifferentialValueProbe("Alpha.mock(safeDIOverrides: .init(bravoBuilder: .init(badge: .init(title: \"alpha\")))).bravoBuilder.instantiate().badge.title"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_evaluatesDefaultOncePerConstruction_whenSendableBuilderIsLaidOut() async throws {
		let mocks = try await generatedMocks(of: Self.sideEffectingDefaultFixture)
		let laidOut = mocks.laidOut.mockFiles["Root+SafeDIMock.swift"] ?? ""
		let walk = mocks.walk.mockFiles["Root+SafeDIMock.swift"] ?? ""

		#expect(laidOut == generatedFileHeader + """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            screenBuilder: Screen.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                screenBuilder: screenBuilder
		            )
		        }

		        var screenBuilder: Screen.SafeDIMockConfiguration { __safeDI_storage.screenBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage: Sendable {
		            init(
		                screenBuilder: Screen.SafeDIMockConfiguration
		            ) {
		                self.screenBuilder = screenBuilder
		            }

		            let screenBuilder: Screen.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        @Sendable nonisolated func __safeDI_screenBuilder(__safeDI_Screen_configuration: Screen.SafeDIMockConfiguration) -> Screen {
		            let leaf = if let safeDIBuilder = __safeDI_Screen_configuration.leaf { safeDIBuilder() } else { Leaf() }
		            return if let safeDIBuilder = __safeDI_Screen_configuration.safeDIBuilder { safeDIBuilder(leaf, __safeDI_Screen_configuration.stamp()) } else { Screen(leaf: leaf, stamp: __safeDI_Screen_configuration.stamp()) }
		        }
		        let __safeDI_screenBuilder____safeDI_Screen_configuration: Screen.SafeDIMockConfiguration = safeDIOverrides.screenBuilder
		        let screenBuilder = SendableInstantiator<Screen> {
		            __safeDI_screenBuilder(__safeDI_Screen_configuration: __safeDI_screenBuilder____safeDI_Screen_configuration)
		        }
		        return Root(screenBuilder: screenBuilder)
		    }
		}
		#endif
		""", "Unexpected output \(laidOut)")
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: Self.sideEffectingDefaultFixture, probes: [
			DifferentialValueProbe(name: "two instances, each stamped once", expression: "{ let builder = Root.mock().screenBuilder; return [builder.instantiate(), builder.instantiate()] }()"),
		])
		#expect(walk != laidOut)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Root`'s mock as the type key lays it out, and as the walk writes it.
	private mutating func generatedMocks(of fixtureFiles: [String: String]) async throws -> (laidOut: TestOutput, walk: TestOutput) {
		let laidOut = try await MockLowering.$laysOutWithTypeKey.withValue(true) {
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixtureFiles, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		let walk = try await MockLowering.$laysOutWithTypeKey.withValue(false) {
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixtureFiles, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		return (laidOut, walk)
	}

	/// Compares what the laid-out mock builds for `probes` with what the walk's builds, the walk being the known-right path.
	private mutating func expectLaidOutValuesEqualWalks(
		_ mocks: (laidOut: TestOutput, walk: TestOutput),
		fixtureFiles: [String: String],
		probes: [DifferentialValueProbe],
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		try await expectDifferentialValuesAgree(
			feature: DifferentialValuePath(fixtureFiles: fixtureFiles, generatedFiles: #require(mocks.laidOut.generatedFiles)),
			knownRight: DifferentialValuePath(fixtureFiles: fixtureFiles, generatedFiles: #require(mocks.walk.generatedFiles)),
			probes: probes,
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}

	private static let leaf = """
	@Instantiable
	public final class Leaf: Instantiable, Sendable {
	    public init() {
	        tag = 0
	    }

	    public let tag: Int

	    private init(tag: Int) {
	        self.tag = tag
	    }

	    public static func tagged(_ tag: Int) -> Leaf {
	        Leaf(tag: tag)
	    }
	}
	"""

	private static let screen = """
	@Instantiable
	public final class Screen: Instantiable, Sendable {
	    public init(leaf: Leaf, title: String = "default") {
	        self.leaf = leaf
	        self.title = title
	    }

	    @Instantiated public let leaf: Leaf
	    public let title: String
	}
	"""

	private static let configuredNodeFixture = [
		"Leaf.swift": leaf,
		"Screen.swift": screen,
		"Root.swift": """
		@Instantiable(generateMock: true)
		public struct Root: Instantiable {
		    public init(screenBuilder: SendableInstantiator<Screen>) {
		        self.screenBuilder = screenBuilder
		    }

		    @Instantiated public let screenBuilder: SendableInstantiator<Screen>
		}
		""",
	]

	private static let overrideClosureFixture = [
		"Leaf.swift": leaf,
		"Root.swift": """
		@Instantiable(generateMock: true)
		public struct Root: Instantiable {
		    public init(leafBuilder: SendableInstantiator<Leaf>) {
		        self.leafBuilder = leafBuilder
		    }

		    @Instantiated public let leafBuilder: SendableInstantiator<Leaf>
		}
		""",
	]

	/// `Panel` instantiates `Missing`, which no declaration fulfills, inside `screenBuilder`'s `@Sendable` function, so
	/// `mock()` takes it as a `@Sendable` autoclosure that `Panel`'s function binds at its top.
	private static let sendableAutoclosureFixture = [
		"Leaf.swift": leaf,
		"Missing.swift": """
		public struct Missing: Sendable {
		    public init(tag: Int) {
		        self.tag = tag
		    }

		    public let tag: Int

		    public static func next() -> Missing {
		        count += 1
		        return Missing(tag: count)
		    }

		    // The probe builds on one thread.
		    nonisolated(unsafe) private static var count = 0
		}
		""",
		"Panel.swift": """
		@Instantiable
		public struct Panel: Instantiable, Sendable {
		    public init(leaf: Leaf, missing: Missing) {
		        self.leaf = leaf
		        self.missing = missing
		    }

		    @Instantiated public let leaf: Leaf
		    @Instantiated public let missing: Missing
		}
		""",
		"Screen.swift": """
		@Instantiable
		public final class Screen: Instantiable, Sendable {
		    public init(panel: Panel) {
		        self.panel = panel
		    }

		    @Instantiated public let panel: Panel
		}
		""",
		"Root.swift": """
		@Instantiable(generateMock: true)
		public struct Root: Instantiable {
		    public init(screenBuilder: SendableInstantiator<Screen>) {
		        self.screenBuilder = screenBuilder
		    }

		    @Instantiated public let screenBuilder: SendableInstantiator<Screen>
		}
		""",
	]

	/// `Root` builds `User` twice and `NamedUser` once, which receive `service` as two types that nothing builds, so
	/// `mock()` takes each under a name of its own, which each builder function binds under the label at its top.
	private static let receiverBindingFixture = [
		"Service.swift": """
		public struct Service {
		    public init(tag: Int) {
		        self.tag = tag
		    }

		    public let tag: Int
		}
		""",
		"User.swift": """
		@Instantiable
		public struct User: Instantiable {
		    public init(service: Service) {
		        self.service = service
		    }

		    @Received public let service: Service
		}
		""",
		"NamedUser.swift": """
		@Instantiable
		public struct NamedUser: Instantiable {
		    public init(service: String) {
		        self.service = service
		    }

		    @Received public let service: String
		}
		""",
		"Root.swift": """
		@Instantiable(generateMock: true)
		public struct Root: Instantiable {
		    public init(first: User, second: User, named: NamedUser) {
		        self.first = first
		        self.second = second
		        self.named = named
		    }

		    @Instantiated public let first: User
		    @Instantiated public let second: User
		    @Instantiated public let named: NamedUser
		}
		""",
	]

	/// `Screen`, built in `screenBuilder`'s `@Sendable` function, instantiates `aBuilder` and `bBuilder`, which receive one
	/// another: a loop of builders, whose functions rebind each other at their tops, statements no record holds, so the
	/// root keeps the walk's text.
	private static let unrecordedPlaceBeneathFixture = [
		"Leaf.swift": leaf,
		"A.swift": """
		@Instantiable
		public final class A: Instantiable {
		    public init(bBuilder: Instantiator<B>) {
		        self.bBuilder = bBuilder
		    }

		    @Received public let bBuilder: Instantiator<B>
		}
		""",
		"B.swift": """
		@Instantiable
		public final class B: Instantiable {
		    public init(aBuilder: Instantiator<A>, leaf: Leaf) {
		        self.aBuilder = aBuilder
		        self.leaf = leaf
		    }

		    @Received public let aBuilder: Instantiator<A>
		    @Received public let leaf: Leaf
		}
		""",
		"Screen.swift": """
		@Instantiable
		public final class Screen: Instantiable {
		    public init(leaf: Leaf, aBuilder: Instantiator<A>, bBuilder: Instantiator<B>) {
		        self.leaf = leaf
		        self.aBuilder = aBuilder
		        self.bBuilder = bBuilder
		    }

		    @Instantiated public let leaf: Leaf
		    @Instantiated public let aBuilder: Instantiator<A>
		    @Instantiated public let bBuilder: Instantiator<B>
		}
		""",
		"Root.swift": """
		@Instantiable(generateMock: true)
		public struct Root: Instantiable {
		    public init(screenBuilder: SendableInstantiator<Screen>) {
		        self.screenBuilder = screenBuilder
		    }

		    @Instantiated public let screenBuilder: SendableInstantiator<Screen>
		}
		""",
	]

	/// `Screen`'s default stamps each value it makes, so a default evaluated twice for one construction, or once for
	/// two, builds other stamps than the walk's.
	private static let sideEffectingDefaultFixture = [
		"Leaf.swift": leaf,
		"Stamp.swift": """
		public final class Stamp: Sendable {
		    public init() {
		        Stamp.count += 1
		        value = Stamp.count
		    }

		    public let value: Int

		    // The probe builds on one thread.
		    nonisolated(unsafe) private static var count = 0
		}
		""",
		"Screen.swift": """
		@Instantiable
		public final class Screen: Instantiable, Sendable {
		    public init(leaf: Leaf, stamp: Stamp = Stamp()) {
		        self.leaf = leaf
		        self.stamp = stamp
		    }

		    @Instantiated public let leaf: Leaf
		    public let stamp: Stamp
		}
		""",
		"Root.swift": """
		@Instantiable(generateMock: true)
		public struct Root: Instantiable {
		    public init(screenBuilder: SendableInstantiator<Screen>) {
		        self.screenBuilder = screenBuilder
		    }

		    @Instantiated public let screenBuilder: SendableInstantiator<Screen>
		}
		""",
	]

	private static let mockedLazyCycleFixture = [
		"Alpha.swift": """
		@Instantiable(generateMock: true)
		public final class Alpha: Instantiable {
		    public init(bravoBuilder: Instantiator<Bravo>) {
		        self.bravoBuilder = bravoBuilder
		    }

		    @Instantiated public let bravoBuilder: Instantiator<Bravo>
		}
		""",
		"Badge.swift": """
		@Instantiable
		public final class Badge: Instantiable {
		    public init(title: String = "default") {
		        self.title = title
		    }

		    public let title: String
		}
		""",
		"Bravo.swift": """
		@Instantiable(generateMock: true)
		public final class Bravo: Instantiable {
		    public init(alphaBuilder: Instantiator<Alpha>, badge: Badge) {
		        self.alphaBuilder = alphaBuilder
		        self.badge = badge
		    }

		    @Instantiated public let alphaBuilder: Instantiator<Alpha>
		    @Instantiated public let badge: Badge
		}
		""",
		"Root.swift": """
		@Instantiable(generateMock: true)
		public final class Root: Instantiable {
		    public init(alphaBuilder: Instantiator<Alpha>) {
		        self.alphaBuilder = alphaBuilder
		    }

		    @Instantiated public let alphaBuilder: Instantiator<Alpha>
		}
		""",
	]
}
