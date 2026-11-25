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

/// An internal mock that calls another module's public mock inside a `@Sendable` builder function reads the call's
/// override into a local before the function (`SendableOverrideExtractor`). Under the type key's layout, the call binds
/// that override before it calls (`PassedArgument.bindsBeforeCall`), as the walk binds the local, so the root is laid out
/// rather than keeping the walk's body. Each test compares the values the laid-out mock builds with the walk's.
struct SafeDIToolMockTypeKeySendablePublicMockCallTests: ~Copyable {
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
	mutating func mock_laysOutPublicMockCallInSendableBuilder_whenCallReadsItsOverride() async throws {
		let modules = Self.modules(app: Self.root)
		let (outcomes, mocks) = try await generatedMocks(of: modules)

		#expect(outcomes == ["Root: laidOut"])
		#expect(mocks.laidOut.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            panelBuilder: (@Sendable () -> Panel.SafeDIOverrides)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                panelBuilder: panelBuilder
		            )
		        }

		        var panelBuilder: (@Sendable () -> Panel.SafeDIOverrides)? { __safeDI_storage.panelBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage: Sendable {
		            init(
		                panelBuilder: (@Sendable () -> Panel.SafeDIOverrides)?
		            ) {
		                self.panelBuilder = panelBuilder
		            }

		            let panelBuilder: (@Sendable () -> Panel.SafeDIOverrides)?
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        @Sendable nonisolated func __safeDI_panelBuilder(safeDIBuilder: (@Sendable () -> Panel.SafeDIOverrides)?) -> Panel {
		            _ = Panel.__safeDI_Panel_mock_51799E6AA5E7B634.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Panel.__safeDI_mock(safeDIOverrides: safeDIBuilder?() ?? .init())
		        }
		        let __safeDI_panelBuilder__safeDIBuilder: (@Sendable () -> Panel.SafeDIOverrides)? = safeDIOverrides.panelBuilder
		        let panelBuilder = SendableInstantiator<Panel> {
		            __safeDI_panelBuilder(safeDIBuilder: __safeDI_panelBuilder__safeDIBuilder)
		        }
		        return Root(panelBuilder: panelBuilder)
		    }
		}
		#endif
		""")
		try await expectDifferentialValuesAgree(
			feature: DifferentialValuePath(output: mocks.laidOut, modules: modules),
			knownRight: DifferentialValuePath(output: mocks.walk, modules: modules),
			probes: [
				DifferentialValueProbe("Root.mock().panelBuilder.instantiate().leaf.tag"),
				DifferentialValueProbe("Root.mock(safeDIOverrides: .init(panelBuilder: { .init(leaf: { Leaf(tag: 7) }) })).panelBuilder.instantiate().leaf.tag"),
			],
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_laysOutPublicMockCallInSendableBuilder_whenFunctionBindsTheHoleBuilderItPassesAgain() async throws {
		// `Root`'s mock takes the hole's builder `@Sendable`, and the function binds it again in the form `Panel`'s mock
		// takes, which the call reads inside the function.
		let modules = Self.modules(core: Self.panelWithHole, app: Self.root)
		let (outcomes, mocks) = try await generatedMocks(of: modules)

		#expect(outcomes == ["Root: laidOut"])
		#expect(mocks.laidOut.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            panelBuilder: (@Sendable (@escaping () -> any Service) -> Panel)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                panelBuilder: panelBuilder
		            )
		        }

		        var panelBuilder: (@Sendable (@escaping () -> any Service) -> Panel)? { __safeDI_storage.panelBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage: Sendable {
		            init(
		                panelBuilder: (@Sendable (@escaping () -> any Service) -> Panel)?
		            ) {
		                self.panelBuilder = panelBuilder
		            }

		            let panelBuilder: (@Sendable (@escaping () -> any Service) -> Panel)?
		        }
		    }

		    static func mock(
		        serviceSendableBuilder: @escaping @Sendable () -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        @Sendable nonisolated func __safeDI_panelBuilder(safeDIBuilder: (@Sendable (@escaping () -> any Service) -> Panel)?) -> Panel {
		            _ = Panel.__safeDI_Panel_mock_4C19E5205B40458C.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            let serviceBuilder: () -> any Service = serviceSendableBuilder
		            return if let safeDIBuilder = safeDIBuilder { safeDIBuilder(serviceBuilder) } else { Panel.__safeDI_mock(serviceBuilder: .init(__safeDI_noScope: serviceBuilder)) }
		        }
		        let __safeDI_panelBuilder__safeDIBuilder: (@Sendable (@escaping () -> any Service) -> Panel)? = safeDIOverrides.panelBuilder
		        let panelBuilder = SendableInstantiator<Panel> {
		            __safeDI_panelBuilder(safeDIBuilder: __safeDI_panelBuilder__safeDIBuilder)
		        }
		        return Root(panelBuilder: panelBuilder)
		    }
		}
		#endif
		""")
		try await expectDifferentialValuesAgree(
			feature: DifferentialValuePath(output: mocks.laidOut, modules: modules),
			knownRight: DifferentialValuePath(output: mocks.walk, modules: modules),
			probes: [
				DifferentialValueProbe(#"Root.mock(serviceSendableBuilder: { NamedService(name: "a") }).panelBuilder.instantiate().service.name"#),
				DifferentialValueProbe(#"Root.mock(serviceSendableBuilder: { NamedService(name: "a") }, safeDIOverrides: .init(panelBuilder: { serviceBuilder in Panel.mock(serviceBuilder: { NamedService(name: serviceBuilder().name + "b") }) })).panelBuilder.instantiate().service.name"#),
			],
			filesToDelete: &filesToDelete,
		)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// Each mocked type's layout outcome, and the modules' output as the type key lays out their mocks and as the walk
	/// writes them.
	private mutating func generatedMocks(of modules: [ModuleFixture]) async throws -> (outcomes: [String], (laidOut: MultiModuleTestOutput, walk: MultiModuleTestOutput)) {
		let (stream, continuation) = AsyncStream.makeStream(of: String.self)
		let laidOut = try await MockLowering.$typeKeyLayoutObserver.withValue({ mockedType, outcome in continuation.yield("\(mockedType): \(outcome)") }) {
			try await MockLowering.$laysOutWithTypeKey.withValue(true) {
				try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
			}
		}
		continuation.finish()
		var outcomes = [String]()
		for await outcome in stream {
			outcomes.append(outcome)
		}
		let walk = try await MockLowering.$laysOutWithTypeKey.withValue(false) {
			try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
		return (outcomes.sorted(), (laidOut, walk))
	}

	private static func modules(core: String = Self.panel, app: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Core", packageName: "core", swiftFileContent: [core]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContent: [app], dependencies: ["Core"]),
		]
	}

	private static let panel = """
	import SafeDI

	@Instantiable
	public final class Leaf: Instantiable, Sendable {
	    public init() {
	        tag = 0
	    }

	    public init(tag: Int) {
	        self.tag = tag
	    }

	    public let tag: Int
	}

	@Instantiable(generateMock: .public)
	public final class Panel: Instantiable, Sendable {
	    package init(leaf: Leaf) {
	        self.leaf = leaf
	    }

	    @Instantiated public let leaf: Leaf
	}
	"""

	/// `Panel` with a hole: no declaration fulfills `Service`, so `Panel`'s public mock takes a builder of it, which a
	/// caller's mock takes in turn.
	private static let panelWithHole = """
	import SafeDI

	public protocol Service: Sendable {
	    var name: String { get }
	}

	public struct NamedService: Service {
	    public init(name: String) {
	        self.name = name
	    }

	    public let name: String
	}

	@Instantiable(generateMock: .public)
	public final class Panel: Instantiable, Sendable {
	    package init(service: any Service) {
	        self.service = service
	    }

	    @Instantiated public let service: any Service
	}
	"""

	private static let root = """
	import Core
	import SafeDI

	@Instantiable(generateMock: true)
	public final class Root: Instantiable {
	    public init(panelBuilder: SendableInstantiator<Panel>) {
	        self.panelBuilder = panelBuilder
	    }

	    @Instantiated public let panelBuilder: SendableInstantiator<Panel>
	}
	"""
}
