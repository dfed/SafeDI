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

/// A mock reads every override a `@Sendable` builder function uses into a local declared before the function, named
/// after the function and the override's path, its labels joined with underscores. Labels may hold underscores too, so
/// two paths can join to one name, and a sibling's builder function can have the name a local would take: each local
/// is named apart from the names of the scope it is declared in and of the scopes that read it, and reads its own
/// override.
struct SafeDIToolMockSendableOverrideLocalNameTests: ~Copyable {
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
	mutating func mock_namesExtractedOverrideLocalsApart_whenTwoOverridePathsJoinToOneName() async throws {
		// `header.leaf` and `header_leaf` both join to `screenBuilder_header_leaf`.
		let fixtureFiles = Self.joinedPathFixture
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [],
			swiftFileContentByFilePath: fixtureFiles,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Root+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            screenBuilder: Screen.SafeDIMockConfiguration = .init()
		        ) {
		            self.screenBuilder = screenBuilder
		        }

		        let screenBuilder: Screen.SafeDIMockConfiguration
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let __safeDI_screenBuilder__screenBuilder_header_safeDIBuilder = safeDIOverrides.screenBuilder.header.safeDIBuilder
		        let __safeDI_screenBuilder__screenBuilder_header_leaf_safeDIBuilder = safeDIOverrides.screenBuilder.header.leaf
		        let __safeDI_screenBuilder__screenBuilder_header_leaf_safeDIBuilder_ = safeDIOverrides.screenBuilder.header_leaf
		        let __safeDI_screenBuilder__safeDIBuilder = safeDIOverrides.screenBuilder.safeDIBuilder
		        @Sendable func __safeDI_screenBuilder() -> Screen {
		            func __safeDI_header() -> Header {
		                let leaf = if let safeDIBuilder = __safeDI_screenBuilder__screenBuilder_header_leaf_safeDIBuilder { safeDIBuilder() } else { Leaf() }
		                return if let safeDIBuilder = __safeDI_screenBuilder__screenBuilder_header_safeDIBuilder { safeDIBuilder(leaf) } else { Header(leaf: leaf) }
		            }
		            let header: Header = __safeDI_header()
		            let header_leaf = if let safeDIBuilder = __safeDI_screenBuilder__screenBuilder_header_leaf_safeDIBuilder_ { safeDIBuilder() } else { Leaf() }
		            return if let safeDIBuilder = __safeDI_screenBuilder__safeDIBuilder { safeDIBuilder(header, header_leaf) } else { Screen(header: header, header_leaf: header_leaf) }
		        }
		        let screenBuilder = SendableInstantiator<Screen>(__safeDI_screenBuilder)
		        return Root(screenBuilder: screenBuilder)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Root+SafeDIMock.swift"] ?? "")")
		let path = try DifferentialValuePath(fixtureFiles: fixtureFiles, generatedFiles: #require(output.generatedFiles))
		try await expectDifferentialValuesAgree(
			feature: path,
			knownRight: path,
			probes: [
				DifferentialValueProbe(
					name: "each override reaches its own receiver",
					expression: "Root.mock(safeDIOverrides: .init(screenBuilder: .init(header: .init(leaf: { Leaf.tagged(1) }), header_leaf: { Leaf.tagged(2) }))).screenBuilder.instantiate()",
					knownRightExpression: "Screen(header: Header(leaf: Leaf.tagged(1)), header_leaf: Leaf.tagged(2))",
				),
			],
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_namesExtractedOverrideLocalsApartFromSiblingBuilderFunctions_whenSiblingLabelsSpellLocalNames() async throws {
		// The siblings' builder functions, `__safeDI_screenBuilder__safeDIBuilder` and
		// `__safeDI_screenBuilder__screenBuilder_leaf_safeDIBuilder`, have the names `screenBuilder`'s locals would take.
		let fixtureFiles = Self.siblingFunctionFixture
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [],
			swiftFileContentByFilePath: fixtureFiles,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Root+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            screenBuilder: Screen.SafeDIMockConfiguration = .init(),
		            screenBuilder__safeDIBuilder: (@Sendable () -> Leaf)? = nil,
		            screenBuilder__screenBuilder_leaf_safeDIBuilder: (() -> Leaf)? = nil
		        ) {
		            self.screenBuilder = screenBuilder
		            self.screenBuilder__safeDIBuilder = screenBuilder__safeDIBuilder
		            self.screenBuilder__screenBuilder_leaf_safeDIBuilder = screenBuilder__screenBuilder_leaf_safeDIBuilder
		        }

		        let screenBuilder: Screen.SafeDIMockConfiguration
		        let screenBuilder__safeDIBuilder: (@Sendable () -> Leaf)?
		        let screenBuilder__screenBuilder_leaf_safeDIBuilder: (() -> Leaf)?
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let __safeDI_screenBuilder__screenBuilder_leaf_safeDIBuilder_ = safeDIOverrides.screenBuilder.leaf
		        let __safeDI_screenBuilder__safeDIBuilder_ = safeDIOverrides.screenBuilder.safeDIBuilder
		        @Sendable func __safeDI_screenBuilder() -> Screen {
		            let leaf = if let safeDIBuilder = __safeDI_screenBuilder__screenBuilder_leaf_safeDIBuilder_ { safeDIBuilder() } else { Leaf() }
		            return if let safeDIBuilder = __safeDI_screenBuilder__safeDIBuilder_ { safeDIBuilder(leaf) } else { Screen(leaf: leaf) }
		        }
		        let screenBuilder = SendableInstantiator<Screen>(__safeDI_screenBuilder)
		        let __safeDI_screenBuilder__safeDIBuilder__safeDIBuilder = safeDIOverrides.screenBuilder__safeDIBuilder
		        @Sendable func __safeDI_screenBuilder__safeDIBuilder() -> Leaf {
		            if let safeDIBuilder = __safeDI_screenBuilder__safeDIBuilder__safeDIBuilder { safeDIBuilder() } else { Leaf() }
		        }
		        let screenBuilder__safeDIBuilder = SendableInstantiator<Leaf>(__safeDI_screenBuilder__safeDIBuilder)
		        func __safeDI_screenBuilder__screenBuilder_leaf_safeDIBuilder() -> Leaf {
		            if let safeDIBuilder = safeDIOverrides.screenBuilder__screenBuilder_leaf_safeDIBuilder { safeDIBuilder() } else { Leaf() }
		        }
		        let screenBuilder__screenBuilder_leaf_safeDIBuilder = Instantiator<Leaf>(__safeDI_screenBuilder__screenBuilder_leaf_safeDIBuilder)
		        return Root(screenBuilder: screenBuilder, screenBuilder__safeDIBuilder: screenBuilder__safeDIBuilder, screenBuilder__screenBuilder_leaf_safeDIBuilder: screenBuilder__screenBuilder_leaf_safeDIBuilder)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Root+SafeDIMock.swift"] ?? "")")
		let path = try DifferentialValuePath(fixtureFiles: fixtureFiles, generatedFiles: #require(output.generatedFiles))
		let overrides = ".init(screenBuilder: .init(leaf: { Leaf.tagged(1) }, { Screen.tagged(leaf: $0, 4) }), screenBuilder__safeDIBuilder: { Leaf.tagged(2) }, screenBuilder__screenBuilder_leaf_safeDIBuilder: { Leaf.tagged(3) })"
		try await expectDifferentialValuesAgree(
			feature: path,
			knownRight: path,
			probes: [
				DifferentialValueProbe(
					name: "screenBuilder",
					expression: "Root.mock(safeDIOverrides: \(overrides)).screenBuilder.instantiate()",
					knownRightExpression: "Screen.tagged(leaf: Leaf.tagged(1), 4)",
				),
				DifferentialValueProbe(
					name: "screenBuilder__safeDIBuilder",
					expression: "Root.mock(safeDIOverrides: \(overrides)).screenBuilder__safeDIBuilder.instantiate()",
					knownRightExpression: "Leaf.tagged(2)",
				),
				DifferentialValueProbe(
					name: "screenBuilder__screenBuilder_leaf_safeDIBuilder",
					expression: "Root.mock(safeDIOverrides: \(overrides)).screenBuilder__screenBuilder_leaf_safeDIBuilder.instantiate()",
					knownRightExpression: "Leaf.tagged(3)",
				),
			],
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_namesExtractedOverrideLocalApartFromBuilderFunctionWhereItIsRead_whenChildLabelSpellsLocalName() async throws {
		// `Header`'s override is read inside `__safeDI_header`, which declares the builder function of its child labeled
		// `screenBuilder__screenBuilder_header_safeDIBuilder`, the name the override's local would take.
		let fixtureFiles = Self.childFunctionFixture
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [],
			swiftFileContentByFilePath: fixtureFiles,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Root+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            screenBuilder: Screen.SafeDIMockConfiguration = .init()
		        ) {
		            self.screenBuilder = screenBuilder
		        }

		        let screenBuilder: Screen.SafeDIMockConfiguration
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let __safeDI_screenBuilder__screenBuilder_header_safeDIBuilder_ = safeDIOverrides.screenBuilder.header.safeDIBuilder
		        let __safeDI_screenBuilder__screenBuilder_header_leaf_safeDIBuilder = safeDIOverrides.screenBuilder.header.leaf
		        let __safeDI_screenBuilder__screenBuilder_header_screenBuilder__screenBuilder_header_safeDIBuilder_safeDIBuilder = safeDIOverrides.screenBuilder.header.screenBuilder__screenBuilder_header_safeDIBuilder
		        let __safeDI_screenBuilder__safeDIBuilder = safeDIOverrides.screenBuilder.safeDIBuilder
		        @Sendable func __safeDI_screenBuilder() -> Screen {
		            func __safeDI_header() -> Header {
		                let leaf = if let safeDIBuilder = __safeDI_screenBuilder__screenBuilder_header_leaf_safeDIBuilder { safeDIBuilder() } else { Leaf() }
		                func __safeDI_screenBuilder__screenBuilder_header_safeDIBuilder() -> Leaf {
		                    if let safeDIBuilder = __safeDI_screenBuilder__screenBuilder_header_screenBuilder__screenBuilder_header_safeDIBuilder_safeDIBuilder { safeDIBuilder() } else { Leaf() }
		                }
		                let screenBuilder__screenBuilder_header_safeDIBuilder = Instantiator<Leaf>(__safeDI_screenBuilder__screenBuilder_header_safeDIBuilder)
		                return if let safeDIBuilder = __safeDI_screenBuilder__screenBuilder_header_safeDIBuilder_ { safeDIBuilder(leaf, screenBuilder__screenBuilder_header_safeDIBuilder) } else { Header(leaf: leaf, screenBuilder__screenBuilder_header_safeDIBuilder: screenBuilder__screenBuilder_header_safeDIBuilder) }
		            }
		            let header: Header = __safeDI_header()
		            return if let safeDIBuilder = __safeDI_screenBuilder__safeDIBuilder { safeDIBuilder(header) } else { Screen(header: header) }
		        }
		        let screenBuilder = SendableInstantiator<Screen>(__safeDI_screenBuilder)
		        return Root(screenBuilder: screenBuilder)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Root+SafeDIMock.swift"] ?? "")")
		let path = try DifferentialValuePath(fixtureFiles: fixtureFiles, generatedFiles: #require(output.generatedFiles))
		try await expectDifferentialValuesAgree(
			feature: path,
			knownRight: path,
			probes: [
				DifferentialValueProbe(
					name: "each override reaches its own receiver",
					expression: "Root.mock(safeDIOverrides: .init(screenBuilder: .init(header: .init(leaf: { Leaf.tagged(1) }, screenBuilder__screenBuilder_header_safeDIBuilder: { Leaf.tagged(2) }, { Header.tagged(leaf: $0, leafBuilder: $1, 3) })))).screenBuilder.instantiate()",
					knownRightExpression: "Screen(header: Header.tagged(leaf: Leaf.tagged(1), leafBuilder: Instantiator<Leaf> { Leaf.tagged(2) }, 3))",
				),
			],
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_namesExtractedOverrideLocalsApartFromAutoclosureLocals_whenUncoveredDependencyLabelSpellsLocalName() async throws {
		// The mock reads its `@Sendable` autoclosure parameter `screenBuilder__screenBuilder_leaf_safeDIBuilder` into
		// `__safeDI_screenBuilder__screenBuilder_leaf_safeDIBuilder`, the name the local of `leaf`'s override would take.
		let fixtureFiles = Self.autoclosureLocalFixture
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [],
			swiftFileContentByFilePath: fixtureFiles,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Root+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            screenBuilder: Screen.SafeDIMockConfiguration = .init()
		        ) {
		            self.screenBuilder = screenBuilder
		        }

		        let screenBuilder: Screen.SafeDIMockConfiguration
		    }

		    static func mock(
		        screenBuilder__screenBuilder_leaf_safeDIBuilder: @autoclosure @escaping @Sendable () -> Missing,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let __safeDI_screenBuilder__screenBuilder_leaf_safeDIBuilder = screenBuilder__screenBuilder_leaf_safeDIBuilder
		        let __safeDI_screenBuilder__screenBuilder_leaf_safeDIBuilder_ = safeDIOverrides.screenBuilder.leaf
		        let __safeDI_screenBuilder__safeDIBuilder = safeDIOverrides.screenBuilder.safeDIBuilder
		        @Sendable func __safeDI_screenBuilder() -> Screen {
		            let screenBuilder__screenBuilder_leaf_safeDIBuilder = __safeDI_screenBuilder__screenBuilder_leaf_safeDIBuilder()
		            let leaf = if let safeDIBuilder = __safeDI_screenBuilder__screenBuilder_leaf_safeDIBuilder_ { safeDIBuilder() } else { Leaf() }
		            return if let safeDIBuilder = __safeDI_screenBuilder__safeDIBuilder { safeDIBuilder(leaf, screenBuilder__screenBuilder_leaf_safeDIBuilder) } else { Screen(leaf: leaf, screenBuilder__screenBuilder_leaf_safeDIBuilder: screenBuilder__screenBuilder_leaf_safeDIBuilder) }
		        }
		        let screenBuilder = SendableInstantiator<Screen>(__safeDI_screenBuilder)
		        return Root(screenBuilder: screenBuilder)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Root+SafeDIMock.swift"] ?? "")")
		let path = try DifferentialValuePath(fixtureFiles: fixtureFiles, generatedFiles: #require(output.generatedFiles))
		try await expectDifferentialValuesAgree(
			feature: path,
			knownRight: path,
			probes: [
				DifferentialValueProbe(
					name: "each value reaches its own receiver",
					expression: "Root.mock(screenBuilder__screenBuilder_leaf_safeDIBuilder: Missing(tag: 2), safeDIOverrides: .init(screenBuilder: .init(leaf: { Leaf.tagged(1) }))).screenBuilder.instantiate()",
					knownRightExpression: "Screen(leaf: Leaf.tagged(1), screenBuilder__screenBuilder_leaf_safeDIBuilder: Missing(tag: 2))",
				),
			],
			filesToDelete: &filesToDelete,
		)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private static let leaf = """
	@Instantiable
	public struct Leaf: Instantiable, Sendable {
	    public init() {}

	    public var tag = 0

	    public static func tagged(_ tag: Int) -> Leaf {
	        var leaf = Leaf()
	        leaf.tag = tag
	        return leaf
	    }
	}
	"""

	private static let joinedPathFixture = [
		"Leaf.swift": leaf,
		"Header.swift": """
		@Instantiable
		public struct Header: Instantiable, Sendable {
		    public init(leaf: Leaf) {
		        self.leaf = leaf
		    }

		    @Instantiated public let leaf: Leaf
		}
		""",
		"Screen.swift": """
		@Instantiable
		public struct Screen: Instantiable, Sendable {
		    public init(header: Header, header_leaf: Leaf) {
		        self.header = header
		        self.header_leaf = header_leaf
		    }

		    @Instantiated public let header: Header
		    @Instantiated public let header_leaf: Leaf
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

	private static let siblingFunctionFixture = [
		"Leaf.swift": leaf,
		"Screen.swift": """
		@Instantiable
		public struct Screen: Instantiable, Sendable {
		    public init(leaf: Leaf) {
		        self.leaf = leaf
		    }

		    @Instantiated public let leaf: Leaf

		    public var tag = 0

		    public static func tagged(leaf: Leaf, _ tag: Int) -> Screen {
		        var screen = Screen(leaf: leaf)
		        screen.tag = tag
		        return screen
		    }
		}
		""",
		"Root.swift": """
		@Instantiable(generateMock: true)
		public struct Root: Instantiable {
		    public init(
		        screenBuilder: SendableInstantiator<Screen>,
		        screenBuilder__safeDIBuilder: SendableInstantiator<Leaf>,
		        screenBuilder__screenBuilder_leaf_safeDIBuilder: Instantiator<Leaf>
		    ) {
		        self.screenBuilder = screenBuilder
		        self.screenBuilder__safeDIBuilder = screenBuilder__safeDIBuilder
		        self.screenBuilder__screenBuilder_leaf_safeDIBuilder = screenBuilder__screenBuilder_leaf_safeDIBuilder
		    }

		    @Instantiated public let screenBuilder: SendableInstantiator<Screen>
		    @Instantiated public let screenBuilder__safeDIBuilder: SendableInstantiator<Leaf>
		    @Instantiated public let screenBuilder__screenBuilder_leaf_safeDIBuilder: Instantiator<Leaf>
		}
		""",
	]

	private static let childFunctionFixture = [
		"Leaf.swift": leaf,
		"Header.swift": """
		@Instantiable
		public struct Header: Instantiable {
		    public init(leaf: Leaf, screenBuilder__screenBuilder_header_safeDIBuilder: Instantiator<Leaf>) {
		        self.leaf = leaf
		        self.screenBuilder__screenBuilder_header_safeDIBuilder = screenBuilder__screenBuilder_header_safeDIBuilder
		    }

		    @Instantiated public let leaf: Leaf
		    @Instantiated public let screenBuilder__screenBuilder_header_safeDIBuilder: Instantiator<Leaf>

		    public var tag = 0

		    public static func tagged(leaf: Leaf, leafBuilder: Instantiator<Leaf>, _ tag: Int) -> Header {
		        var header = Header(leaf: leaf, screenBuilder__screenBuilder_header_safeDIBuilder: leafBuilder)
		        header.tag = tag
		        return header
		    }
		}
		""",
		"Screen.swift": """
		@Instantiable
		public struct Screen: Instantiable {
		    public init(header: Header) {
		        self.header = header
		    }

		    @Instantiated public let header: Header
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

	private static let autoclosureLocalFixture = [
		"Leaf.swift": leaf,
		"Missing.swift": """
		public struct Missing: Sendable {
		    public init(tag: Int) {
		        self.tag = tag
		    }

		    public let tag: Int
		}
		""",
		"Screen.swift": """
		@Instantiable
		public struct Screen: Instantiable {
		    public init(leaf: Leaf, screenBuilder__screenBuilder_leaf_safeDIBuilder: Missing) {
		        self.leaf = leaf
		        self.screenBuilder__screenBuilder_leaf_safeDIBuilder = screenBuilder__screenBuilder_leaf_safeDIBuilder
		    }

		    @Instantiated public let leaf: Leaf
		    @Instantiated public let screenBuilder__screenBuilder_leaf_safeDIBuilder: Missing
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
