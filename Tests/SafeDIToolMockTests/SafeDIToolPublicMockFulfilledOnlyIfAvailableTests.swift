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

/// A public mock of a type whose tree instantiates only if available a dependency a declaration fulfills builds it, as
/// production does, and takes the entry `<label>IsUnavailable: Bool = false` before the dependency’s own, in its
/// `SafeDIOverrides` and in the module-level configuration of the type that declares the dependency, whose `true`
/// binds the dependency to `nil`, as an internal mock does. A mock in another module that calls the public mock hands
/// it its `SafeDIOverrides` entry whole, so a test sets the entry through the calling mock.
struct SafeDIToolPublicMockFulfilledOnlyIfAvailableTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try? FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_takesEntryInOverridesAndModuleLevelConfiguration_whenPublicMocksTreeInstantiatesFulfilledTypeOnlyIfAvailable() async throws {
		// `Screen` and `Panel`, beneath it, each instantiate `analytics` only if available, which `AnalyticsImpl` fulfills:
		// `SafeDIOverrides` holds `Screen`’s entry and `Panel`’s module-level configuration its own, and `Leaf`, which
		// receives `analytics`, is passed `Panel`’s.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            analyticsIsUnavailable: Bool = false,
		            analytics: (() -> any Analytics)? = nil,
		            panel: __safeDI_Feature_Panel_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                analyticsIsUnavailable: analyticsIsUnavailable,
		                analytics: analytics,
		                panel: panel
		            )
		        }

		        public var analyticsIsUnavailable: Bool { __safeDI_storage.analyticsIsUnavailable }
		        public var analytics: (() -> any Analytics)? { __safeDI_storage.analytics }
		        public var panel: __safeDI_Feature_Panel_MockConfiguration { __safeDI_storage.panel }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                analyticsIsUnavailable: Bool,
		                analytics: (() -> any Analytics)?,
		                panel: __safeDI_Feature_Panel_MockConfiguration
		            ) {
		                self.analyticsIsUnavailable = analyticsIsUnavailable
		                self.analytics = analytics
		                self.panel = panel
		            }

		            let analyticsIsUnavailable: Bool
		            let analytics: (() -> any Analytics)?
		            let panel: __safeDI_Feature_Panel_MockConfiguration
		        }
		    }

		    public static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        Screen.__safeDI_mock(safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let analytics: (any Analytics)? = if safeDIOverrides.analyticsIsUnavailable { nil } else if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { AnalyticsImpl() }
		        func __safeDI_panel() -> Panel {
		            let analytics: (any Analytics)? = if safeDIOverrides.panel.analyticsIsUnavailable { nil } else if let safeDIBuilder = safeDIOverrides.panel.analytics { safeDIBuilder() } else { AnalyticsImpl() }
		            let leaf = if let safeDIBuilder = safeDIOverrides.panel.leaf { safeDIBuilder(analytics) } else { Leaf(analytics: analytics) }
		            return Panel.__safeDI_init(analytics: analytics, leaf: leaf, safeDIBuilder: safeDIOverrides.panel.safeDIBuilder)
		        }
		        let panel: Panel = __safeDI_panel()
		        return Screen(analytics: analytics, panel: panel)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_51799E6AA5E7B634 {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `Panel` is constructed within the public mock trees of module `Feature`.
		nonisolated public struct __safeDI_Feature_Panel_MockConfiguration {
		    public init(
		        analyticsIsUnavailable: Bool = false,
		        analytics: (() -> any Analytics)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            analyticsIsUnavailable: analyticsIsUnavailable,
		            analytics: analytics,
		            leaf: nil,
		            safeDIBuilder: nil
		        )
		    }

		    init(
		        analyticsIsUnavailable: Bool = false,
		        analytics: (() -> any Analytics)? = nil,
		        leaf: (((any Analytics)?) -> Leaf)? = nil,
		        _ safeDIBuilder: (((any Analytics)?, Leaf) -> Panel)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            analyticsIsUnavailable: analyticsIsUnavailable,
		            analytics: analytics,
		            leaf: leaf,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var analyticsIsUnavailable: Bool { __safeDI_storage.analyticsIsUnavailable }
		    public var analytics: (() -> any Analytics)? { __safeDI_storage.analytics }
		    var leaf: (((any Analytics)?) -> Leaf)? { __safeDI_storage.leaf }
		    /// Overrides how `Panel` is constructed. Parameters match the type’s initializer or custom mock method.
		    var safeDIBuilder: (((any Analytics)?, Leaf) -> Panel)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            analyticsIsUnavailable: Bool,
		            analytics: (() -> any Analytics)?,
		            leaf: (((any Analytics)?) -> Leaf)?,
		            safeDIBuilder: (((any Analytics)?, Leaf) -> Panel)?
		        ) {
		            self.analyticsIsUnavailable = analyticsIsUnavailable
		            self.analytics = analytics
		            self.leaf = leaf
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let analyticsIsUnavailable: Bool
		        let analytics: (() -> any Analytics)?
		        let leaf: (((any Analytics)?) -> Leaf)?
		        let safeDIBuilder: (((any Analytics)?, Leaf) -> Panel)?
		    }
		}

		extension Panel {
		    static func __safeDI_init(analytics: (any Analytics)?, leaf: Leaf, safeDIBuilder: (((any Analytics)?, Leaf) -> Panel)?) -> Panel {
		        if let safeDIBuilder { safeDIBuilder(analytics, leaf) } else { Panel(analytics: analytics, leaf: leaf) }
		    }
		}
		#endif

		"""])
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_setsCalledMocksEntryThroughItsOverrides_whenMockCallsPublicMockInstantiatingFulfilledTypeOnlyIfAvailable(integration: MultiModuleIntegration) async throws {
		// `Home`’s mock calls `Screen`’s, which `App`, in another package, cannot build inline, and hands it
		// `safeDIOverrides.screen`, which holds both entries; each binds the same value as the same types’ mocks built in
		// one module.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules, integration: integration, filesToDelete: &filesToDelete)

		let (fileName, callComment) = switch integration {
		case .moduleInfo:
			("App.swift", "compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.")
		case .swiftPackagePlugin:
			("Home+SafeDIMock.swift", "add the SafeDI plugin to the target that declares Screen.")
		}
		#expect(output.modules["App"]?.generatedFiles[fileName] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Home {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            screen: Screen.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                screen: screen
		            )
		        }

		        var screen: Screen.SafeDIOverrides { __safeDI_storage.screen }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                screen: Screen.SafeDIOverrides
		            ) {
		                self.screen = screen
		            }

		            let screen: Screen.SafeDIOverrides
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Home {
		        _ = Screen.__safeDI_Screen_mock_51799E6AA5E7B634.self // If this line does not compile, \(callComment)
		        let screen = Screen.__safeDI_mock(safeDIOverrides: safeDIOverrides.screen)
		        return Home(screen: screen)
		    }
		}
		#endif
		""")
		try await expectValuesAgreeWithInlineMocks(of: Self.modules, output: output, probes: [
			DifferentialValueProbe("Home.mock()"),
			DifferentialValueProbe("Home.mock(safeDIOverrides: .init(screen: .init(analyticsIsUnavailable: true)))"),
			DifferentialValueProbe("Home.mock(safeDIOverrides: .init(screen: .init(panel: .init(analyticsIsUnavailable: true))))"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_readsEntryFromLocal_whenPublicMockBuildsTypeInstantiatingFulfilledTypeOnlyIfAvailableInsideSendableFunction() async throws {
		// `Child` is built inside a `@Sendable` builder function, which reads each field of a public configuration, never
		// `Sendable`, into a local bound before it: the entry is read so too.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public protocol Analytics: Sendable {}
				""",
				"""
				@Instantiable(fulfillingAdditionalTypes: [Analytics.self])
				public final class DefaultAnalytics: Analytics, Instantiable {
				    public init() {}
				}
				""",
				"""
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable, Sendable {
				    public init(childBuilder: SendableInstantiator<Child>) {
				        self.childBuilder = childBuilder
				    }
				    @Instantiated let childBuilder: SendableInstantiator<Child>
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable, Sendable {
				    public init(analytics: (any Analytics)?) {
				        self.analytics = analytics
				    }
				    @Instantiated(onlyIfAvailable: true) let analytics: (any Analytics)?
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            childBuilder: __safeDI_Child_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                childBuilder: childBuilder
		            )
		        }

		        public var childBuilder: __safeDI_Child_MockConfiguration { __safeDI_storage.childBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                childBuilder: __safeDI_Child_MockConfiguration
		            ) {
		                self.childBuilder = childBuilder
		            }

		            let childBuilder: __safeDI_Child_MockConfiguration
		        }
		    }

		    public static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        Screen.__safeDI_mock(safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let __safeDI_childBuilder__childBuilder_analytics_safeDIBuilder = safeDIOverrides.childBuilder.analytics
		        let __safeDI_childBuilder__childBuilder_analyticsIsUnavailable = safeDIOverrides.childBuilder.analyticsIsUnavailable
		        let __safeDI_childBuilder__safeDIBuilder = safeDIOverrides.childBuilder.safeDIBuilder
		        @Sendable nonisolated func __safeDI_childBuilder() -> Child {
		            let analytics: (any Analytics)? = if __safeDI_childBuilder__childBuilder_analyticsIsUnavailable { nil } else if let safeDIBuilder = __safeDI_childBuilder__childBuilder_analytics_safeDIBuilder { safeDIBuilder() } else { DefaultAnalytics() }
		            return Child.__safeDI_init(analytics: analytics, safeDIBuilder: __safeDI_childBuilder__safeDIBuilder)
		        }
		        let childBuilder = SendableInstantiator<Child>(__safeDI_childBuilder)
		        return Screen(childBuilder: childBuilder)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_51799E6AA5E7B634 {}
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
		#expect(output.mockConfigurationFile == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		/// Configuration for how `Child` is constructed within the public mock trees of this module.
		nonisolated public struct __safeDI_Child_MockConfiguration {
		    public init(
		        analyticsIsUnavailable: Bool = false,
		        analytics: (@Sendable () -> any Analytics)? = nil,
		        _ safeDIBuilder: (@Sendable ((any Analytics)?) -> Child)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            analyticsIsUnavailable: analyticsIsUnavailable,
		            analytics: analytics,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var analyticsIsUnavailable: Bool { __safeDI_storage.analyticsIsUnavailable }
		    public var analytics: (@Sendable () -> any Analytics)? { __safeDI_storage.analytics }
		    /// Overrides how `Child` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: (@Sendable ((any Analytics)?) -> Child)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            analyticsIsUnavailable: Bool,
		            analytics: (@Sendable () -> any Analytics)?,
		            safeDIBuilder: (@Sendable ((any Analytics)?) -> Child)?
		        ) {
		            self.analyticsIsUnavailable = analyticsIsUnavailable
		            self.analytics = analytics
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let analyticsIsUnavailable: Bool
		        let analytics: (@Sendable () -> any Analytics)?
		        let safeDIBuilder: (@Sendable ((any Analytics)?) -> Child)?
		    }
		}

		extension Child {
		    static func __safeDI_init(analytics: (any Analytics)?, safeDIBuilder: (@Sendable ((any Analytics)?) -> Child)?) -> Child {
		        if let safeDIBuilder { safeDIBuilder(analytics) } else { Child(analytics: analytics) }
		    }
		}
		#endif

		""", "Unexpected output \(output.mockConfigurationFile ?? "")")
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Feature`, whose `Screen` has a public mock and an internal initializer, so `App`, in another package, calls the
	/// mock; `Screen` and `Panel`, beneath it, each instantiate `analytics` only if available, which `AnalyticsImpl`
	/// fulfills, and `Leaf`, beneath `Panel`, receives it only if available. `App` declares `Home`, whose mock builds
	/// `Screen`.
	private static let modules = [
		ModuleFixture(name: "Feature", packageName: "shop", swiftFileContentByFilePath: ["Screen.swift": """
		import SafeDI

		public protocol Analytics {}

		@Instantiable(fulfillingAdditionalTypes: [Analytics.self])
		public final class AnalyticsImpl: Instantiable, Analytics {
		    public init() {}
		}

		@Instantiable(generateMock: .public)
		public final class Screen: Instantiable {
		    init(analytics: (any Analytics)?, panel: Panel) {
		        self.analytics = analytics
		        self.panel = panel
		    }

		    @Instantiated(onlyIfAvailable: true) let analytics: (any Analytics)?
		    @Instantiated let panel: Panel
		}

		@Instantiable
		final class Panel: Instantiable {
		    init(analytics: (any Analytics)?, leaf: Leaf) {
		        self.analytics = analytics
		        self.leaf = leaf
		    }

		    @Instantiated(onlyIfAvailable: true) let analytics: (any Analytics)?
		    @Instantiated let leaf: Leaf
		}

		@Instantiable
		final class Leaf: Instantiable {
		    init(analytics: (any Analytics)?) {
		        self.analytics = analytics
		    }

		    @Received(onlyIfAvailable: true) let analytics: (any Analytics)?
		}

		"""]),
		ModuleFixture(name: "App", packageName: "other", swiftFileContentByFilePath: ["Home.swift": """
		import Feature
		import SafeDI

		@Instantiable(generateMock: true)
		public final class Home: Instantiable {
		    public init(screen: Screen) {
		        self.screen = screen
		    }

		    @Instantiated public let screen: Screen
		}

		"""], dependencies: ["Feature"]),
	]

	/// Compiles `output` and the same types built in one module, with every public mock an internal one, and compares what
	/// `probes` build in each.
	private mutating func expectValuesAgreeWithInlineMocks(
		of modules: [ModuleFixture],
		output: MultiModuleTestOutput,
		probes: [DifferentialValueProbe],
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		let moduleNames = Set(modules.map(\.name))
		func inline(_ source: String) -> String {
			source
				.split(separator: "\n", omittingEmptySubsequences: false)
				.filter { line in !moduleNames.contains { line == "import \($0)" } }
				.joined(separator: "\n")
				.replacingOccurrences(of: "generateMock: .public", with: "generateMock: true")
		}
		var inlineFiles = [String: String]()
		for module in modules {
			for (fileName, content) in module.swiftFileContentByFilePath {
				inlineFiles["\(module.name)_\(fileName)"] = inline(content)
			}
		}
		let inlineModules = [ModuleFixture(name: modules[0].name, packageName: modules[0].packageName, swiftFileContentByFilePath: inlineFiles)]
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inlineModules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		func path(of modules: [ModuleFixture], output: MultiModuleTestOutput) throws -> DifferentialValuePath {
			try DifferentialValuePath(modules: modules.map { module in
				try DifferentialValueModule(
					name: module.name,
					packageName: module.packageName,
					dependencyModuleNames: module.dependencies,
					fixtureFiles: module.swiftFileContentByFilePath,
					generatedFiles: #require(output.modules[module.name], sourceLocation: sourceLocation).generatedFiles,
				)
			})
		}
		try await expectDifferentialValuesAgree(
			feature: path(of: modules, output: output),
			knownRight: path(of: inlineModules, output: inlineOutput),
			probes: probes,
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}
}
