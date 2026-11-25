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
	mutating func mock_keepsWalksBody_whenPlaceBeneathSendableBuilderIsUnrecorded() async throws {
		let mocks = try await generatedMocks(of: Self.unrecordedPlaceBeneathFixture)
		let laidOut = mocks.laidOut.mockFiles["Root+SafeDIMock.swift"] ?? ""
		let walk = mocks.walk.mockFiles["Root+SafeDIMock.swift"] ?? ""

		#expect(laidOut == walk)
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: Self.unrecordedPlaceBeneathFixture, probes: [
			DifferentialValueProbe("Root.mock(missing: Missing(tag: 1)).screenBuilder.instantiate()"),
			DifferentialValueProbe("Root.mock(missing: Missing(tag: 2), safeDIOverrides: .init(screenBuilder: .init(panel: .init(leaf: { Leaf.tagged(3) })))).screenBuilder.instantiate()"),
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
	/// `mock()` takes it as a `@Sendable` autoclosure that `Panel`'s function binds at its top: a statement no record holds,
	/// so `Panel` keeps the walk's text, and `screenBuilder`'s function keeps the locals that text reads.
	private static let unrecordedPlaceBeneathFixture = [
		"Leaf.swift": leaf,
		"Missing.swift": """
		public struct Missing: Sendable {
		    public init(tag: Int) {
		        self.tag = tag
		    }

		    public let tag: Int
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
}
