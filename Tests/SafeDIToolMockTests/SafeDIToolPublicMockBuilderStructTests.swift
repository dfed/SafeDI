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

/// A public mock whose places of a hole type forward nothing, are built in plain code, outside every `LazilyInstantiated`,
/// and hold no other scope takes that hole type's builder as a closure that takes nothing in `mock()`, beside a function
/// only generated code calls, which takes the builder struct a seam takes. A module that calls the mock passes the struct its
/// level functions return where it fills every place in each value's own form, and otherwise converts what it passes the
/// closure over the enum into the struct.
struct SafeDIToolPublicMockBuilderStructTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – a mock that takes a builder struct

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesClosureThatTakesNothingAndCallsFunctionOnlyGeneratedCodeCalls_whenPublicMocksOnlyPlaceIsThreeLevelsBeneathIt() async throws {
		// `Page` opens `Detail`, which opens `Leaf`, whose `api` nothing `Feed` sees fulfills. `mock()` takes the builder as a
		// closure a test writes `{ StubApi() }` for, and `Root`'s mock, which sees `Live`, fills the place through level
		// functions.
		let modules = Self.pageModules(app: [
			Self.live,
			Self.root(holding: "page: Page"),
			"""
			final class StubApi: Api {}

			func leafTheTestBuilds() -> Leaf {
			    Page.mock(apiBuilder: { StubApi() }).detailBuilder.instantiate().leafBuilder.instantiate()
			}
			""",
		])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif


		"""])
		#expect(output.modules["Feed"]?.generatedFiles == ["Feed.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Page {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct detailBuilder_Values {
		            public let navigator: Navigator
		            public let logger: Logger
		        }

		        nonisolated public enum Detail_Scope {
		            nonisolated public struct leafBuilder_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let leafBuilder: (leafBuilder_Values) -> SafeDIMockScope_Api.Leaf_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(leafBuilder: @escaping (leafBuilder_Values) -> SafeDIMockScope_Api.Leaf_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.leafBuilder = leafBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(leafBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		                }
		            }
		        }

		        nonisolated public enum Leaf_Scope {
		            nonisolated public struct api_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let api: (api_Values) -> __safeDI_Built

		                public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                    self.api = api
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(api: { _ in __safeDI_builder() })
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let detailBuilder: (detailBuilder_Values) -> SafeDIMockScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(detailBuilder: @escaping (detailBuilder_Values) -> SafeDIMockScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.detailBuilder = detailBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(detailBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            navigator: (() -> Navigator)? = nil,
		            logger: (() -> Logger)? = nil,
		            detailBuilder: __safeDI_Feed_Detail_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                navigator: navigator,
		                logger: logger,
		                detailBuilder: detailBuilder
		            )
		        }

		        public var navigator: (() -> Navigator)? { __safeDI_storage.navigator }
		        public var logger: (() -> Logger)? { __safeDI_storage.logger }
		        public var detailBuilder: __safeDI_Feed_Detail_MockConfiguration { __safeDI_storage.detailBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                navigator: (() -> Navigator)?,
		                logger: (() -> Logger)?,
		                detailBuilder: __safeDI_Feed_Detail_MockConfiguration
		            ) {
		                self.navigator = navigator
		                self.logger = logger
		                self.detailBuilder = detailBuilder
		            }

		            let navigator: (() -> Navigator)?
		            let logger: (() -> Logger)?
		            let detailBuilder: __safeDI_Feed_Detail_MockConfiguration
		        }
		    }

		    // SafeDI counts `Api` as `public`: no module it reads declares it narrower. If `Api` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    public static func mock(
		        apiBuilder: @escaping () -> any Api,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Page {
		        Page.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        apiBuilder __safeDI_apiBuilder: Page.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Page {
		        let navigator = if let safeDIBuilder = safeDIOverrides.navigator { safeDIBuilder() } else { Navigator() }
		        let logger = if let safeDIBuilder = safeDIOverrides.logger { safeDIBuilder() } else { Logger() }
		        let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder.detailBuilder(SafeDIMockScope_Api.detailBuilder_Values(navigator: navigator, logger: logger))
		        func __safeDI_detailBuilder() -> Detail {
		            let __safeDI_apiBuilder_leafBuilder = __safeDI_apiBuilder_detailBuilder.leafBuilder(SafeDIMockScope_Api.Detail_Scope.leafBuilder_Values())
		            func __safeDI_leafBuilder() -> Leaf {
		                let api: any Api = __safeDI_apiBuilder_leafBuilder.api(SafeDIMockScope_Api.Leaf_Scope.api_Values())
		                return if let safeDIBuilder = safeDIOverrides.detailBuilder.leafBuilder { safeDIBuilder(api) } else { Leaf(api: api) }
		            }
		            let leafBuilder = Instantiator<Leaf>(__safeDI_leafBuilder)
		            return Detail.__safeDI_init(leafBuilder: leafBuilder, safeDIBuilder: safeDIOverrides.detailBuilder.safeDIBuilder)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        return Page(navigator: navigator, logger: logger, detailBuilder: detailBuilder)
		    }
		}

		extension Page {
		    public enum __safeDI_Page_mock_50657E78D19F8704 {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `Detail` is constructed within the public mock trees of module `Feed`.
		nonisolated public struct __safeDI_Feed_Detail_MockConfiguration {
		    public init(
		        leafBuilder: ((any Api) -> Leaf)? = nil,
		        _ safeDIBuilder: ((Instantiator<Leaf>) -> Detail)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            leafBuilder: leafBuilder,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var leafBuilder: ((any Api) -> Leaf)? { __safeDI_storage.leafBuilder }
		    /// Overrides how `Detail` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((Instantiator<Leaf>) -> Detail)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            leafBuilder: ((any Api) -> Leaf)?,
		            safeDIBuilder: ((Instantiator<Leaf>) -> Detail)?
		        ) {
		            self.leafBuilder = leafBuilder
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let leafBuilder: ((any Api) -> Leaf)?
		        let safeDIBuilder: ((Instantiator<Leaf>) -> Detail)?
		    }
		}

		extension Detail {
		    static func __safeDI_init(leafBuilder: Instantiator<Leaf>, safeDIBuilder: ((Instantiator<Leaf>) -> Detail)?) -> Detail {
		        if let safeDIBuilder { safeDIBuilder(leafBuilder) } else { Detail(leafBuilder: leafBuilder) }
		    }
		}
		#endif

		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feed)
		import Feed
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            page: Page.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                page: page
		            )
		        }

		        var page: Page.SafeDIOverrides { __safeDI_storage.page }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                page: Page.SafeDIOverrides
		            ) {
		                self.page = page
		            }

		            let page: Page.SafeDIOverrides
		        }
		    }

		    static func mock(
		        apiBuilder: (() -> any Api)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_page() -> Page {
		            func __safeDI_apiBuilder_Page() -> Page.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(detailBuilder: { _ in __safeDI_apiBuilder_Page_Detail_Scope() })
		            }
		            func __safeDI_apiBuilder_Page_Detail_Scope() -> Page.SafeDIMockScope_Api.Detail_Scope.__safeDI_Builder<any Api> {
		                .init(leafBuilder: { _ in __safeDI_apiBuilder_Page_Leaf_Scope() })
		            }
		            func __safeDI_apiBuilder_Page_Leaf_Scope() -> Page.SafeDIMockScope_Api.Leaf_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = Live()
		                    return api
		                })
		            }
		            _ = Page.__safeDI_Page_mock_50657E78D19F8704.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Page.__safeDI_mock(apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_Page(), safeDIOverrides: safeDIOverrides.page)
		        }
		        let page: Page = __safeDI_page()
		        return Root(page: page)
		    }
		}
		#endif
		"""])
	}

	// MARK: Tests – a call that fills every place

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsLevelFunctionTheValueItsFillReads_whenCallerFillsPlaceWhoseFillReadsValueTwoLevelsAbove() async throws {
		// `Live` reads the `logger` `Page` binds. `Root`'s level functions take `logger` as a parameter, so an instantiator of
		// `Leaf` keeps the logger alive, as inline, and not the navigator `Page` binds beside it.
		let modules = Self.pageModules(app: [
			Self.live(receiving: "@Received public let logger: Logger"),
			Self.root(holding: "page: Page"),
			Self.countsWhileLeafBuilderLives,
		])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif


		"""])
		#expect(output.modules["Feed"]?.generatedFiles == ["Feed.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Page {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct detailBuilder_Values {
		            public let navigator: Navigator
		            public let logger: Logger
		        }

		        nonisolated public enum Detail_Scope {
		            nonisolated public struct leafBuilder_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let leafBuilder: (leafBuilder_Values) -> SafeDIMockScope_Api.Leaf_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(leafBuilder: @escaping (leafBuilder_Values) -> SafeDIMockScope_Api.Leaf_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.leafBuilder = leafBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(leafBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		                }
		            }
		        }

		        nonisolated public enum Leaf_Scope {
		            nonisolated public struct api_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let api: (api_Values) -> __safeDI_Built

		                public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                    self.api = api
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(api: { _ in __safeDI_builder() })
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let detailBuilder: (detailBuilder_Values) -> SafeDIMockScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(detailBuilder: @escaping (detailBuilder_Values) -> SafeDIMockScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.detailBuilder = detailBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(detailBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            navigator: (() -> Navigator)? = nil,
		            logger: (() -> Logger)? = nil,
		            detailBuilder: __safeDI_Feed_Detail_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                navigator: navigator,
		                logger: logger,
		                detailBuilder: detailBuilder
		            )
		        }

		        public var navigator: (() -> Navigator)? { __safeDI_storage.navigator }
		        public var logger: (() -> Logger)? { __safeDI_storage.logger }
		        public var detailBuilder: __safeDI_Feed_Detail_MockConfiguration { __safeDI_storage.detailBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                navigator: (() -> Navigator)?,
		                logger: (() -> Logger)?,
		                detailBuilder: __safeDI_Feed_Detail_MockConfiguration
		            ) {
		                self.navigator = navigator
		                self.logger = logger
		                self.detailBuilder = detailBuilder
		            }

		            let navigator: (() -> Navigator)?
		            let logger: (() -> Logger)?
		            let detailBuilder: __safeDI_Feed_Detail_MockConfiguration
		        }
		    }

		    // SafeDI counts `Api` as `public`: no module it reads declares it narrower. If `Api` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    public static func mock(
		        apiBuilder: @escaping () -> any Api,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Page {
		        Page.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        apiBuilder __safeDI_apiBuilder: Page.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Page {
		        let navigator = if let safeDIBuilder = safeDIOverrides.navigator { safeDIBuilder() } else { Navigator() }
		        let logger = if let safeDIBuilder = safeDIOverrides.logger { safeDIBuilder() } else { Logger() }
		        let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder.detailBuilder(SafeDIMockScope_Api.detailBuilder_Values(navigator: navigator, logger: logger))
		        func __safeDI_detailBuilder() -> Detail {
		            let __safeDI_apiBuilder_leafBuilder = __safeDI_apiBuilder_detailBuilder.leafBuilder(SafeDIMockScope_Api.Detail_Scope.leafBuilder_Values())
		            func __safeDI_leafBuilder() -> Leaf {
		                let api: any Api = __safeDI_apiBuilder_leafBuilder.api(SafeDIMockScope_Api.Leaf_Scope.api_Values())
		                return if let safeDIBuilder = safeDIOverrides.detailBuilder.leafBuilder { safeDIBuilder(api) } else { Leaf(api: api) }
		            }
		            let leafBuilder = Instantiator<Leaf>(__safeDI_leafBuilder)
		            return Detail.__safeDI_init(leafBuilder: leafBuilder, safeDIBuilder: safeDIOverrides.detailBuilder.safeDIBuilder)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        return Page(navigator: navigator, logger: logger, detailBuilder: detailBuilder)
		    }
		}

		extension Page {
		    public enum __safeDI_Page_mock_50657E78D19F8704 {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `Detail` is constructed within the public mock trees of module `Feed`.
		nonisolated public struct __safeDI_Feed_Detail_MockConfiguration {
		    public init(
		        leafBuilder: ((any Api) -> Leaf)? = nil,
		        _ safeDIBuilder: ((Instantiator<Leaf>) -> Detail)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            leafBuilder: leafBuilder,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var leafBuilder: ((any Api) -> Leaf)? { __safeDI_storage.leafBuilder }
		    /// Overrides how `Detail` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((Instantiator<Leaf>) -> Detail)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            leafBuilder: ((any Api) -> Leaf)?,
		            safeDIBuilder: ((Instantiator<Leaf>) -> Detail)?
		        ) {
		            self.leafBuilder = leafBuilder
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let leafBuilder: ((any Api) -> Leaf)?
		        let safeDIBuilder: ((Instantiator<Leaf>) -> Detail)?
		    }
		}

		extension Detail {
		    static func __safeDI_init(leafBuilder: Instantiator<Leaf>, safeDIBuilder: ((Instantiator<Leaf>) -> Detail)?) -> Detail {
		        if let safeDIBuilder { safeDIBuilder(leafBuilder) } else { Detail(leafBuilder: leafBuilder) }
		    }
		}
		#endif

		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feed)
		import Feed
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            page: Page.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                page: page
		            )
		        }

		        var page: Page.SafeDIOverrides { __safeDI_storage.page }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                page: Page.SafeDIOverrides
		            ) {
		                self.page = page
		            }

		            let page: Page.SafeDIOverrides
		        }
		    }

		    static func mock(
		        apiBuilder: (() -> any Api)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_page() -> Page {
		            func __safeDI_apiBuilder_Page() -> Page.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(detailBuilder: { values in __safeDI_apiBuilder_Page_Detail_Scope(logger: values.logger) })
		            }
		            func __safeDI_apiBuilder_Page_Detail_Scope(logger: Logger) -> Page.SafeDIMockScope_Api.Detail_Scope.__safeDI_Builder<any Api> {
		                .init(leafBuilder: { _ in __safeDI_apiBuilder_Page_Leaf_Scope(logger: logger) })
		            }
		            func __safeDI_apiBuilder_Page_Leaf_Scope(logger: Logger) -> Page.SafeDIMockScope_Api.Leaf_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = Live(logger: logger)
		                    return api
		                })
		            }
		            _ = Page.__safeDI_Page_mock_50657E78D19F8704.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Page.__safeDI_mock(apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_Page(), safeDIOverrides: safeDIOverrides.page)
		        }
		        let page: Page = __safeDI_page()
		        return Root(page: page)
		    }
		}
		#endif
		"""])
		let counts = try await describedCounts(of: modules, output: output, probe: "countsWhileLeafBuilderLives()")
		if compileVerificationIsEnabled {
			// Known-right keeps the logger `Live` holds and frees the navigator.
			#expect(counts.knownRight == "probe countsWhileLeafBuilderLives()\nString \"Navigator 0, Logger 1\"\n")
			#expect(counts.feature == counts.knownRight)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsRootLevelFunctionTheTokenItBuilds_whenInternalCallerFillsARouteThatBindsNoToken() async throws {
		// `Model`'s `api` is reached through `Page`, which binds `token`, and straight from `Hub`, which does not. `Root` fills
		// both routes with `LiveToken`, which reads `token`: the first with `Page`'s, the second with the `token` its mock
		// builds, which its root level function takes. Everything the probe built is freed.
		let modules = Self.routeModules(app: [
			Self.liveToken,
			Self.root(holding: "hub: Hub"),
			"""
			func countsOfHubTheTestBuilds() -> String {
			    do {
			        let hub = Root.mock().hub
			        let page = hub.pageBuilder.instantiate()
			        hub.navigator.stack.append(page)
			        hub.navigator.stack.append(hub.modelBuilder.instantiate())
			        hub.navigator.stack.append(page.modelBuilder.instantiate())
			    }
			    return "Navigator \\(Navigator.alive), Token \\(Token.alive)"
			}
			""",
		])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif


		"""])
		#expect(output.modules["Feed"]?.generatedFiles == ["Feed.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Hub {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct pageBuilder_Values {
		            public let navigator: Navigator
		        }

		        nonisolated public struct modelBuilder_Values {
		            public let navigator: Navigator
		            public let pageBuilder: Instantiator<Page>
		        }

		        nonisolated public enum Page_Scope {
		            nonisolated public struct modelBuilder_Values {
		                public let token: Token
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let modelBuilder: (modelBuilder_Values) -> SafeDIMockScope_Api.Model_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(modelBuilder: @escaping (modelBuilder_Values) -> SafeDIMockScope_Api.Model_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.modelBuilder = modelBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(modelBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		                }
		            }
		        }

		        nonisolated public enum Model_Scope {
		            nonisolated public struct api_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let api: (api_Values) -> __safeDI_Built

		                public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                    self.api = api
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(api: { _ in __safeDI_builder() })
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let pageBuilder: (pageBuilder_Values) -> SafeDIMockScope_Api.Page_Scope.__safeDI_Builder<__safeDI_Built>
		            public let modelBuilder: (modelBuilder_Values) -> SafeDIMockScope_Api.Model_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(pageBuilder: @escaping (pageBuilder_Values) -> SafeDIMockScope_Api.Page_Scope.__safeDI_Builder<__safeDI_Built>, modelBuilder: @escaping (modelBuilder_Values) -> SafeDIMockScope_Api.Model_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.pageBuilder = pageBuilder
		                self.modelBuilder = modelBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(pageBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) }, modelBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            navigator: (() -> Navigator)? = nil,
		            pageBuilder: __safeDI_Feed_Page_MockConfiguration = .init(),
		            modelBuilder: ((any Api) -> Model)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                navigator: navigator,
		                pageBuilder: pageBuilder,
		                modelBuilder: modelBuilder
		            )
		        }

		        public var navigator: (() -> Navigator)? { __safeDI_storage.navigator }
		        public var pageBuilder: __safeDI_Feed_Page_MockConfiguration { __safeDI_storage.pageBuilder }
		        public var modelBuilder: ((any Api) -> Model)? { __safeDI_storage.modelBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                navigator: (() -> Navigator)?,
		                pageBuilder: __safeDI_Feed_Page_MockConfiguration,
		                modelBuilder: ((any Api) -> Model)?
		            ) {
		                self.navigator = navigator
		                self.pageBuilder = pageBuilder
		                self.modelBuilder = modelBuilder
		            }

		            let navigator: (() -> Navigator)?
		            let pageBuilder: __safeDI_Feed_Page_MockConfiguration
		            let modelBuilder: ((any Api) -> Model)?
		        }
		    }

		    // SafeDI counts `Api` as `public`: no module it reads declares it narrower. If `Api` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    public static func mock(
		        apiBuilder: @escaping () -> any Api,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Hub {
		        Hub.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        apiBuilder __safeDI_apiBuilder: Hub.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Hub {
		        let navigator = if let safeDIBuilder = safeDIOverrides.navigator { safeDIBuilder() } else { Navigator() }
		        let __safeDI_apiBuilder_pageBuilder = __safeDI_apiBuilder.pageBuilder(SafeDIMockScope_Api.pageBuilder_Values(navigator: navigator))
		        func __safeDI_pageBuilder() -> Page {
		            let token = if let safeDIBuilder = safeDIOverrides.pageBuilder.token { safeDIBuilder() } else { Token() }
		            let __safeDI_apiBuilder_modelBuilder = __safeDI_apiBuilder_pageBuilder.modelBuilder(SafeDIMockScope_Api.Page_Scope.modelBuilder_Values(token: token))
		            func __safeDI_modelBuilder() -> Model {
		                let api: any Api = __safeDI_apiBuilder_modelBuilder.api(SafeDIMockScope_Api.Model_Scope.api_Values())
		                return if let safeDIBuilder = safeDIOverrides.pageBuilder.modelBuilder { safeDIBuilder(api) } else { Model(api: api) }
		            }
		            let modelBuilder = Instantiator<Model>(__safeDI_modelBuilder)
		            return Page.__safeDI_init(token: token, modelBuilder: modelBuilder, safeDIBuilder: safeDIOverrides.pageBuilder.safeDIBuilder)
		        }
		        let pageBuilder = Instantiator<Page>(__safeDI_pageBuilder)
		        let __safeDI_apiBuilder_modelBuilder = __safeDI_apiBuilder.modelBuilder(SafeDIMockScope_Api.modelBuilder_Values(navigator: navigator, pageBuilder: pageBuilder))
		        func __safeDI_modelBuilder() -> Model {
		            let api: any Api = __safeDI_apiBuilder_modelBuilder.api(SafeDIMockScope_Api.Model_Scope.api_Values())
		            return if let safeDIBuilder = safeDIOverrides.modelBuilder { safeDIBuilder(api) } else { Model(api: api) }
		        }
		        let modelBuilder = Instantiator<Model>(__safeDI_modelBuilder)
		        return Hub(navigator: navigator, pageBuilder: pageBuilder, modelBuilder: modelBuilder)
		    }
		}

		extension Hub {
		    public enum __safeDI_Hub_mock_9D3DEE011EBEDDFF {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `Page` is constructed within the public mock trees of module `Feed`.
		nonisolated public struct __safeDI_Feed_Page_MockConfiguration {
		    public init(
		        token: (() -> Token)? = nil,
		        modelBuilder: ((any Api) -> Model)? = nil,
		        _ safeDIBuilder: ((Token, Instantiator<Model>) -> Page)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            token: token,
		            modelBuilder: modelBuilder,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var token: (() -> Token)? { __safeDI_storage.token }
		    public var modelBuilder: ((any Api) -> Model)? { __safeDI_storage.modelBuilder }
		    /// Overrides how `Page` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((Token, Instantiator<Model>) -> Page)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            token: (() -> Token)?,
		            modelBuilder: ((any Api) -> Model)?,
		            safeDIBuilder: ((Token, Instantiator<Model>) -> Page)?
		        ) {
		            self.token = token
		            self.modelBuilder = modelBuilder
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let token: (() -> Token)?
		        let modelBuilder: ((any Api) -> Model)?
		        let safeDIBuilder: ((Token, Instantiator<Model>) -> Page)?
		    }
		}

		extension Page {
		    static func __safeDI_init(token: Token, modelBuilder: Instantiator<Model>, safeDIBuilder: ((Token, Instantiator<Model>) -> Page)?) -> Page {
		        if let safeDIBuilder { safeDIBuilder(token, modelBuilder) } else { Page(token: token, modelBuilder: modelBuilder) }
		    }
		}
		#endif

		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feed)
		import Feed
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            token: (() -> Token)? = nil,
		            hub: Hub.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                token: token,
		                hub: hub
		            )
		        }

		        var token: (() -> Token)? { __safeDI_storage.token }
		        var hub: Hub.SafeDIOverrides { __safeDI_storage.hub }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                token: (() -> Token)?,
		                hub: Hub.SafeDIOverrides
		            ) {
		                self.token = token
		                self.hub = hub
		            }

		            let token: (() -> Token)?
		            let hub: Hub.SafeDIOverrides
		        }
		    }

		    static func mock(
		        apiBuilder: (() -> any Api)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let token = if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder() } else { Token() }
		        func __safeDI_hub() -> Hub {
		            func __safeDI_apiBuilder_Hub(token: Token) -> Hub.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(pageBuilder: { _ in __safeDI_apiBuilder_Hub_Page_Scope() }, modelBuilder: { _ in __safeDI_apiBuilder_Hub_Model_Scope(token: token) })
		            }
		            func __safeDI_apiBuilder_Hub_Page_Scope() -> Hub.SafeDIMockScope_Api.Page_Scope.__safeDI_Builder<any Api> {
		                .init(modelBuilder: { values in __safeDI_apiBuilder_Hub_Model_Scope(token: values.token) })
		            }
		            func __safeDI_apiBuilder_Hub_Model_Scope(token: Token) -> Hub.SafeDIMockScope_Api.Model_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveToken(token: token)
		                    return api
		                })
		            }
		            _ = Hub.__safeDI_Hub_mock_9D3DEE011EBEDDFF.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Hub.__safeDI_mock(apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_Hub(token: token), safeDIOverrides: safeDIOverrides.hub)
		        }
		        let hub: Hub = __safeDI_hub()
		        return Root(hub: hub)
		    }
		}
		#endif
		"""])
		let description = try await DifferentialValueOracle.describe(DifferentialValuePath(output: output, modules: modules), probes: [DifferentialValueProbe("countsOfHubTheTestBuilds()")], filesToDelete: &filesToDelete)
		if compileVerificationIsEnabled {
			// Once released, the hub keeps nothing it built alive: the builder it is handed takes nothing that holds them.
			#expect(description == "probe countsOfHubTheTestBuilds()\nString \"Navigator 0, Token 0\"\n")
		}
	}

	// MARK: Tests – a call that passes a place up

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsTheStructOfTheBuilderItTakes_whenInternalCallerFillsNoPlace() async throws {
		// `Root` sees nothing that fulfills `Api`: it takes `Page`'s builder as a parameter of its own and hands `Page` its
		// struct, `.init(__safeDI_noScope: apiBuilder)`. The call has no level function.
		let modules = Self.pageModules(app: [
			Self.root(holding: "page: Page"),
			"""
			final class StubApi: Api {}

			func countsOfPageTheTestBuilds() -> String {
			    var leafBuilder: Instantiator<Leaf>?
			    do {
			        let page = Root.mock(apiBuilder: { StubApi() }).page
			        let detail = page.detailBuilder.instantiate()
			        page.navigator.stack.append(detail)
			        leafBuilder = detail.leafBuilder
			    }
			    return withExtendedLifetime(leafBuilder) { "Navigator \\(Navigator.alive), Logger \\(Logger.alive)" }
			}
			""",
		])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif


		"""])
		#expect(output.modules["Feed"]?.generatedFiles == ["Feed.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Page {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct detailBuilder_Values {
		            public let navigator: Navigator
		            public let logger: Logger
		        }

		        nonisolated public enum Detail_Scope {
		            nonisolated public struct leafBuilder_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let leafBuilder: (leafBuilder_Values) -> SafeDIMockScope_Api.Leaf_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(leafBuilder: @escaping (leafBuilder_Values) -> SafeDIMockScope_Api.Leaf_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.leafBuilder = leafBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(leafBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		                }
		            }
		        }

		        nonisolated public enum Leaf_Scope {
		            nonisolated public struct api_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let api: (api_Values) -> __safeDI_Built

		                public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                    self.api = api
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(api: { _ in __safeDI_builder() })
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let detailBuilder: (detailBuilder_Values) -> SafeDIMockScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(detailBuilder: @escaping (detailBuilder_Values) -> SafeDIMockScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.detailBuilder = detailBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(detailBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            navigator: (() -> Navigator)? = nil,
		            logger: (() -> Logger)? = nil,
		            detailBuilder: __safeDI_Feed_Detail_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                navigator: navigator,
		                logger: logger,
		                detailBuilder: detailBuilder
		            )
		        }

		        public var navigator: (() -> Navigator)? { __safeDI_storage.navigator }
		        public var logger: (() -> Logger)? { __safeDI_storage.logger }
		        public var detailBuilder: __safeDI_Feed_Detail_MockConfiguration { __safeDI_storage.detailBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                navigator: (() -> Navigator)?,
		                logger: (() -> Logger)?,
		                detailBuilder: __safeDI_Feed_Detail_MockConfiguration
		            ) {
		                self.navigator = navigator
		                self.logger = logger
		                self.detailBuilder = detailBuilder
		            }

		            let navigator: (() -> Navigator)?
		            let logger: (() -> Logger)?
		            let detailBuilder: __safeDI_Feed_Detail_MockConfiguration
		        }
		    }

		    // SafeDI counts `Api` as `public`: no module it reads declares it narrower. If `Api` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    public static func mock(
		        apiBuilder: @escaping () -> any Api,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Page {
		        Page.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        apiBuilder __safeDI_apiBuilder: Page.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Page {
		        let navigator = if let safeDIBuilder = safeDIOverrides.navigator { safeDIBuilder() } else { Navigator() }
		        let logger = if let safeDIBuilder = safeDIOverrides.logger { safeDIBuilder() } else { Logger() }
		        let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder.detailBuilder(SafeDIMockScope_Api.detailBuilder_Values(navigator: navigator, logger: logger))
		        func __safeDI_detailBuilder() -> Detail {
		            let __safeDI_apiBuilder_leafBuilder = __safeDI_apiBuilder_detailBuilder.leafBuilder(SafeDIMockScope_Api.Detail_Scope.leafBuilder_Values())
		            func __safeDI_leafBuilder() -> Leaf {
		                let api: any Api = __safeDI_apiBuilder_leafBuilder.api(SafeDIMockScope_Api.Leaf_Scope.api_Values())
		                return if let safeDIBuilder = safeDIOverrides.detailBuilder.leafBuilder { safeDIBuilder(api) } else { Leaf(api: api) }
		            }
		            let leafBuilder = Instantiator<Leaf>(__safeDI_leafBuilder)
		            return Detail.__safeDI_init(leafBuilder: leafBuilder, safeDIBuilder: safeDIOverrides.detailBuilder.safeDIBuilder)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        return Page(navigator: navigator, logger: logger, detailBuilder: detailBuilder)
		    }
		}

		extension Page {
		    public enum __safeDI_Page_mock_50657E78D19F8704 {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `Detail` is constructed within the public mock trees of module `Feed`.
		nonisolated public struct __safeDI_Feed_Detail_MockConfiguration {
		    public init(
		        leafBuilder: ((any Api) -> Leaf)? = nil,
		        _ safeDIBuilder: ((Instantiator<Leaf>) -> Detail)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            leafBuilder: leafBuilder,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var leafBuilder: ((any Api) -> Leaf)? { __safeDI_storage.leafBuilder }
		    /// Overrides how `Detail` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((Instantiator<Leaf>) -> Detail)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            leafBuilder: ((any Api) -> Leaf)?,
		            safeDIBuilder: ((Instantiator<Leaf>) -> Detail)?
		        ) {
		            self.leafBuilder = leafBuilder
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let leafBuilder: ((any Api) -> Leaf)?
		        let safeDIBuilder: ((Instantiator<Leaf>) -> Detail)?
		    }
		}

		extension Detail {
		    static func __safeDI_init(leafBuilder: Instantiator<Leaf>, safeDIBuilder: ((Instantiator<Leaf>) -> Detail)?) -> Detail {
		        if let safeDIBuilder { safeDIBuilder(leafBuilder) } else { Detail(leafBuilder: leafBuilder) }
		    }
		}
		#endif

		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feed)
		import Feed
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            page: Page.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                page: page
		            )
		        }

		        var page: Page.SafeDIOverrides { __safeDI_storage.page }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                page: Page.SafeDIOverrides
		            ) {
		                self.page = page
		            }

		            let page: Page.SafeDIOverrides
		        }
		    }

		    static func mock(
		        apiBuilder: @escaping () -> any Api,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let __safeDI_apiBuilder = apiBuilder
		        _ = Page.__safeDI_Page_mock_50657E78D19F8704.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        func __safeDI_page() -> Page {
		            let apiBuilder: () -> any Api = __safeDI_apiBuilder
		            return Page.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), safeDIOverrides: safeDIOverrides.page)
		        }
		        let page: Page = __safeDI_page()
		        return Root(page: page)
		    }
		}
		#endif
		"""])
		let description = try await DifferentialValueOracle.describe(DifferentialValuePath(output: output, modules: modules), probes: [DifferentialValueProbe("countsOfPageTheTestBuilds()")], filesToDelete: &filesToDelete)
		if compileVerificationIsEnabled {
			// Once released, the page keeps nothing it built alive: the builder it is handed takes nothing that holds them.
			#expect(description == "probe countsOfPageTheTestBuilds()\nString \"Navigator 0, Logger 0\"\n")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsPublicCallersMockWithTheTokenItBuilds_whenPublicCallerFillsARouteThatBindsNoToken() async throws {
		// `Shell`, a public mock in `Mid`, builds `Hub` and fills both of its routes with `LiveToken`: the one through `Page`
		// with `Page`'s `token`, and the other with the `token` its mock takes, which `Root` builds and hands it. `Root` takes
		// no builder. Everything the probe built is freed.
		let modules = Self.chainModules(app: [
			Self.root(holding: "shell: Shell"),
			"""
			func countsOfShellTheTestBuilds() -> String {
			    do {
			        let hub = Root.mock().shell.hub
			        let page = hub.pageBuilder.instantiate()
			        hub.navigator.stack.append(page)
			        hub.navigator.stack.append(hub.modelBuilder.instantiate())
			        hub.navigator.stack.append(page.modelBuilder.instantiate())
			    }
			    return "Navigator \\(Navigator.alive), Token \\(Token.alive), Logger \\(Logger.alive)"
			}
			""",
		])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif


		"""])
		#expect(output.modules["Feed"]?.generatedFiles == ["Feed.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Hub {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct pageBuilder_Values {
		            public let navigator: Navigator
		        }

		        nonisolated public struct modelBuilder_Values {
		            public let navigator: Navigator
		            public let pageBuilder: Instantiator<Page>
		        }

		        nonisolated public enum Page_Scope {
		            nonisolated public struct modelBuilder_Values {
		                public let token: Token
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let modelBuilder: (modelBuilder_Values) -> SafeDIMockScope_Api.Model_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(modelBuilder: @escaping (modelBuilder_Values) -> SafeDIMockScope_Api.Model_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.modelBuilder = modelBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(modelBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		                }
		            }
		        }

		        nonisolated public enum Model_Scope {
		            nonisolated public struct api_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let api: (api_Values) -> __safeDI_Built

		                public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                    self.api = api
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(api: { _ in __safeDI_builder() })
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let pageBuilder: (pageBuilder_Values) -> SafeDIMockScope_Api.Page_Scope.__safeDI_Builder<__safeDI_Built>
		            public let modelBuilder: (modelBuilder_Values) -> SafeDIMockScope_Api.Model_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(pageBuilder: @escaping (pageBuilder_Values) -> SafeDIMockScope_Api.Page_Scope.__safeDI_Builder<__safeDI_Built>, modelBuilder: @escaping (modelBuilder_Values) -> SafeDIMockScope_Api.Model_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.pageBuilder = pageBuilder
		                self.modelBuilder = modelBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(pageBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) }, modelBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            navigator: (() -> Navigator)? = nil,
		            pageBuilder: __safeDI_Feed_Page_MockConfiguration = .init(),
		            modelBuilder: ((any Api) -> Model)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                navigator: navigator,
		                pageBuilder: pageBuilder,
		                modelBuilder: modelBuilder
		            )
		        }

		        public var navigator: (() -> Navigator)? { __safeDI_storage.navigator }
		        public var pageBuilder: __safeDI_Feed_Page_MockConfiguration { __safeDI_storage.pageBuilder }
		        public var modelBuilder: ((any Api) -> Model)? { __safeDI_storage.modelBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                navigator: (() -> Navigator)?,
		                pageBuilder: __safeDI_Feed_Page_MockConfiguration,
		                modelBuilder: ((any Api) -> Model)?
		            ) {
		                self.navigator = navigator
		                self.pageBuilder = pageBuilder
		                self.modelBuilder = modelBuilder
		            }

		            let navigator: (() -> Navigator)?
		            let pageBuilder: __safeDI_Feed_Page_MockConfiguration
		            let modelBuilder: ((any Api) -> Model)?
		        }
		    }

		    // SafeDI counts `Api` as `public`: no module it reads declares it narrower. If `Api` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    public static func mock(
		        apiBuilder: @escaping () -> any Api,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Hub {
		        Hub.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        apiBuilder __safeDI_apiBuilder: Hub.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Hub {
		        let navigator = if let safeDIBuilder = safeDIOverrides.navigator { safeDIBuilder() } else { Navigator() }
		        let __safeDI_apiBuilder_pageBuilder = __safeDI_apiBuilder.pageBuilder(SafeDIMockScope_Api.pageBuilder_Values(navigator: navigator))
		        func __safeDI_pageBuilder() -> Page {
		            let token = if let safeDIBuilder = safeDIOverrides.pageBuilder.token { safeDIBuilder() } else { Token() }
		            let __safeDI_apiBuilder_modelBuilder = __safeDI_apiBuilder_pageBuilder.modelBuilder(SafeDIMockScope_Api.Page_Scope.modelBuilder_Values(token: token))
		            func __safeDI_modelBuilder() -> Model {
		                let api: any Api = __safeDI_apiBuilder_modelBuilder.api(SafeDIMockScope_Api.Model_Scope.api_Values())
		                return if let safeDIBuilder = safeDIOverrides.pageBuilder.modelBuilder { safeDIBuilder(api) } else { Model(api: api) }
		            }
		            let modelBuilder = Instantiator<Model>(__safeDI_modelBuilder)
		            return Page.__safeDI_init(token: token, modelBuilder: modelBuilder, safeDIBuilder: safeDIOverrides.pageBuilder.safeDIBuilder)
		        }
		        let pageBuilder = Instantiator<Page>(__safeDI_pageBuilder)
		        let __safeDI_apiBuilder_modelBuilder = __safeDI_apiBuilder.modelBuilder(SafeDIMockScope_Api.modelBuilder_Values(navigator: navigator, pageBuilder: pageBuilder))
		        func __safeDI_modelBuilder() -> Model {
		            let api: any Api = __safeDI_apiBuilder_modelBuilder.api(SafeDIMockScope_Api.Model_Scope.api_Values())
		            return if let safeDIBuilder = safeDIOverrides.modelBuilder { safeDIBuilder(api) } else { Model(api: api) }
		        }
		        let modelBuilder = Instantiator<Model>(__safeDI_modelBuilder)
		        return Hub(navigator: navigator, pageBuilder: pageBuilder, modelBuilder: modelBuilder)
		    }
		}

		extension Hub {
		    public enum __safeDI_Hub_mock_9D3DEE011EBEDDFF {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `Page` is constructed within the public mock trees of module `Feed`.
		nonisolated public struct __safeDI_Feed_Page_MockConfiguration {
		    public init(
		        token: (() -> Token)? = nil,
		        modelBuilder: ((any Api) -> Model)? = nil,
		        _ safeDIBuilder: ((Token, Instantiator<Model>) -> Page)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            token: token,
		            modelBuilder: modelBuilder,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var token: (() -> Token)? { __safeDI_storage.token }
		    public var modelBuilder: ((any Api) -> Model)? { __safeDI_storage.modelBuilder }
		    /// Overrides how `Page` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((Token, Instantiator<Model>) -> Page)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            token: (() -> Token)?,
		            modelBuilder: ((any Api) -> Model)?,
		            safeDIBuilder: ((Token, Instantiator<Model>) -> Page)?
		        ) {
		            self.token = token
		            self.modelBuilder = modelBuilder
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let token: (() -> Token)?
		        let modelBuilder: ((any Api) -> Model)?
		        let safeDIBuilder: ((Token, Instantiator<Model>) -> Page)?
		    }
		}

		extension Page {
		    static func __safeDI_init(token: Token, modelBuilder: Instantiator<Model>, safeDIBuilder: ((Token, Instantiator<Model>) -> Page)?) -> Page {
		        if let safeDIBuilder { safeDIBuilder(token, modelBuilder) } else { Page(token: token, modelBuilder: modelBuilder) }
		    }
		}
		#endif

		"""])
		#expect(output.modules["Mid"]?.generatedFiles == ["Mid.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feed)
		import Feed
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Shell {
		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            logger: (() -> Logger)? = nil,
		            token: (() -> Token)? = nil,
		            hub: Hub.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                logger: logger,
		                token: token,
		                hub: hub
		            )
		        }

		        public var logger: (() -> Logger)? { __safeDI_storage.logger }
		        public var token: (() -> Token)? { __safeDI_storage.token }
		        public var hub: Hub.SafeDIOverrides { __safeDI_storage.hub }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                logger: (() -> Logger)?,
		                token: (() -> Token)?,
		                hub: Hub.SafeDIOverrides
		            ) {
		                self.logger = logger
		                self.token = token
		                self.hub = hub
		            }

		            let logger: (() -> Logger)?
		            let token: (() -> Token)?
		            let hub: Hub.SafeDIOverrides
		        }
		    }

		    // SafeDI counts `Api` as `public`: no module it reads declares it narrower. If `Api` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    public static func mock(
		        apiBuilder: (() -> any Api)? = nil,
		        token: Token? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Shell {
		        Shell.__safeDI_mock(apiBuilder: apiBuilder, token: token, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        apiBuilder __safeDI_apiBuilder: (() -> any Api)? = nil,
		        token: Token? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Shell {
		        let logger = if let safeDIBuilder = safeDIOverrides.logger { safeDIBuilder() } else { Logger() }
		        let token = if let token { token } else if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder() } else { Token() }
		        func __safeDI_hub() -> Hub {
		            func __safeDI_apiBuilder_Hub(token: Token) -> Hub.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(pageBuilder: { _ in __safeDI_apiBuilder_Hub_Page_Scope() }, modelBuilder: { _ in __safeDI_apiBuilder_Hub_Model_Scope(token: token) })
		            }
		            func __safeDI_apiBuilder_Hub_Page_Scope() -> Hub.SafeDIMockScope_Api.Page_Scope.__safeDI_Builder<any Api> {
		                .init(modelBuilder: { values in __safeDI_apiBuilder_Hub_Model_Scope(token: values.token) })
		            }
		            func __safeDI_apiBuilder_Hub_Model_Scope(token: Token) -> Hub.SafeDIMockScope_Api.Model_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveToken(token: token)
		                    return api
		                })
		            }
		            _ = Hub.__safeDI_Hub_mock_9D3DEE011EBEDDFF.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Hub.__safeDI_mock(apiBuilder: __safeDI_apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_Hub(token: token), safeDIOverrides: safeDIOverrides.hub)
		        }
		        let hub: Hub = __safeDI_hub()
		        return Shell(logger: logger, hub: hub)
		    }
		}

		extension Shell {
		    public enum __safeDI_Shell_mock_AEA38F513AD02F1C {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feed)
		import Feed
		#endif
		#if canImport(Mid)
		import Mid
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            token: (() -> Token)? = nil,
		            shell: Shell.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                token: token,
		                shell: shell
		            )
		        }

		        var token: (() -> Token)? { __safeDI_storage.token }
		        var shell: Shell.SafeDIOverrides { __safeDI_storage.shell }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                token: (() -> Token)?,
		                shell: Shell.SafeDIOverrides
		            ) {
		                self.token = token
		                self.shell = shell
		            }

		            let token: (() -> Token)?
		            let shell: Shell.SafeDIOverrides
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let token = if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder() } else { Token() }
		        _ = Shell.__safeDI_Shell_mock_AEA38F513AD02F1C.self // If this line does not compile, compile the code SafeDI generates for module Mid into Mid: under Bazel, add Mid’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let shell = Shell.__safeDI_mock(token: token, safeDIOverrides: safeDIOverrides.shell)
		        return Root(shell: shell)
		    }
		}
		#endif
		"""])
		let description = try await DifferentialValueOracle.describe(DifferentialValuePath(output: output, modules: modules), probes: [DifferentialValueProbe("countsOfShellTheTestBuilds()")], filesToDelete: &filesToDelete)
		if compileVerificationIsEnabled {
			// Once released, the shell keeps nothing it built alive: the builder it is handed takes nothing that holds them.
			#expect(description == "probe countsOfShellTheTestBuilds()\nString \"Navigator 0, Token 0, Logger 0\"\n")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsPublicCallersStructLevelFunctions_whenPublicCallerFillsEveryPlaceOfCalledMock() async throws {
		// `Shell`, a public mock in `Mid`, sees `Live`, which fulfills `Api` and reads nothing, so it fills both of `Hub`'s
		// routes: its call is static, and `Shell` takes no builder.
		let modules = Self.chainModules(mid: [Self.live], app: [
			Self.root(holding: "shell: Shell"),
		])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif


		"""])
		#expect(output.modules["Feed"]?.generatedFiles == ["Feed.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Hub {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct pageBuilder_Values {
		            public let navigator: Navigator
		        }

		        nonisolated public struct modelBuilder_Values {
		            public let navigator: Navigator
		            public let pageBuilder: Instantiator<Page>
		        }

		        nonisolated public enum Page_Scope {
		            nonisolated public struct modelBuilder_Values {
		                public let token: Token
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let modelBuilder: (modelBuilder_Values) -> SafeDIMockScope_Api.Model_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(modelBuilder: @escaping (modelBuilder_Values) -> SafeDIMockScope_Api.Model_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.modelBuilder = modelBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(modelBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		                }
		            }
		        }

		        nonisolated public enum Model_Scope {
		            nonisolated public struct api_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let api: (api_Values) -> __safeDI_Built

		                public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                    self.api = api
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(api: { _ in __safeDI_builder() })
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let pageBuilder: (pageBuilder_Values) -> SafeDIMockScope_Api.Page_Scope.__safeDI_Builder<__safeDI_Built>
		            public let modelBuilder: (modelBuilder_Values) -> SafeDIMockScope_Api.Model_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(pageBuilder: @escaping (pageBuilder_Values) -> SafeDIMockScope_Api.Page_Scope.__safeDI_Builder<__safeDI_Built>, modelBuilder: @escaping (modelBuilder_Values) -> SafeDIMockScope_Api.Model_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.pageBuilder = pageBuilder
		                self.modelBuilder = modelBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(pageBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) }, modelBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            navigator: (() -> Navigator)? = nil,
		            pageBuilder: __safeDI_Feed_Page_MockConfiguration = .init(),
		            modelBuilder: ((any Api) -> Model)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                navigator: navigator,
		                pageBuilder: pageBuilder,
		                modelBuilder: modelBuilder
		            )
		        }

		        public var navigator: (() -> Navigator)? { __safeDI_storage.navigator }
		        public var pageBuilder: __safeDI_Feed_Page_MockConfiguration { __safeDI_storage.pageBuilder }
		        public var modelBuilder: ((any Api) -> Model)? { __safeDI_storage.modelBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                navigator: (() -> Navigator)?,
		                pageBuilder: __safeDI_Feed_Page_MockConfiguration,
		                modelBuilder: ((any Api) -> Model)?
		            ) {
		                self.navigator = navigator
		                self.pageBuilder = pageBuilder
		                self.modelBuilder = modelBuilder
		            }

		            let navigator: (() -> Navigator)?
		            let pageBuilder: __safeDI_Feed_Page_MockConfiguration
		            let modelBuilder: ((any Api) -> Model)?
		        }
		    }

		    // SafeDI counts `Api` as `public`: no module it reads declares it narrower. If `Api` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    public static func mock(
		        apiBuilder: @escaping () -> any Api,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Hub {
		        Hub.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        apiBuilder __safeDI_apiBuilder: Hub.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Hub {
		        let navigator = if let safeDIBuilder = safeDIOverrides.navigator { safeDIBuilder() } else { Navigator() }
		        let __safeDI_apiBuilder_pageBuilder = __safeDI_apiBuilder.pageBuilder(SafeDIMockScope_Api.pageBuilder_Values(navigator: navigator))
		        func __safeDI_pageBuilder() -> Page {
		            let token = if let safeDIBuilder = safeDIOverrides.pageBuilder.token { safeDIBuilder() } else { Token() }
		            let __safeDI_apiBuilder_modelBuilder = __safeDI_apiBuilder_pageBuilder.modelBuilder(SafeDIMockScope_Api.Page_Scope.modelBuilder_Values(token: token))
		            func __safeDI_modelBuilder() -> Model {
		                let api: any Api = __safeDI_apiBuilder_modelBuilder.api(SafeDIMockScope_Api.Model_Scope.api_Values())
		                return if let safeDIBuilder = safeDIOverrides.pageBuilder.modelBuilder { safeDIBuilder(api) } else { Model(api: api) }
		            }
		            let modelBuilder = Instantiator<Model>(__safeDI_modelBuilder)
		            return Page.__safeDI_init(token: token, modelBuilder: modelBuilder, safeDIBuilder: safeDIOverrides.pageBuilder.safeDIBuilder)
		        }
		        let pageBuilder = Instantiator<Page>(__safeDI_pageBuilder)
		        let __safeDI_apiBuilder_modelBuilder = __safeDI_apiBuilder.modelBuilder(SafeDIMockScope_Api.modelBuilder_Values(navigator: navigator, pageBuilder: pageBuilder))
		        func __safeDI_modelBuilder() -> Model {
		            let api: any Api = __safeDI_apiBuilder_modelBuilder.api(SafeDIMockScope_Api.Model_Scope.api_Values())
		            return if let safeDIBuilder = safeDIOverrides.modelBuilder { safeDIBuilder(api) } else { Model(api: api) }
		        }
		        let modelBuilder = Instantiator<Model>(__safeDI_modelBuilder)
		        return Hub(navigator: navigator, pageBuilder: pageBuilder, modelBuilder: modelBuilder)
		    }
		}

		extension Hub {
		    public enum __safeDI_Hub_mock_9D3DEE011EBEDDFF {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `Page` is constructed within the public mock trees of module `Feed`.
		nonisolated public struct __safeDI_Feed_Page_MockConfiguration {
		    public init(
		        token: (() -> Token)? = nil,
		        modelBuilder: ((any Api) -> Model)? = nil,
		        _ safeDIBuilder: ((Token, Instantiator<Model>) -> Page)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            token: token,
		            modelBuilder: modelBuilder,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var token: (() -> Token)? { __safeDI_storage.token }
		    public var modelBuilder: ((any Api) -> Model)? { __safeDI_storage.modelBuilder }
		    /// Overrides how `Page` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((Token, Instantiator<Model>) -> Page)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            token: (() -> Token)?,
		            modelBuilder: ((any Api) -> Model)?,
		            safeDIBuilder: ((Token, Instantiator<Model>) -> Page)?
		        ) {
		            self.token = token
		            self.modelBuilder = modelBuilder
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let token: (() -> Token)?
		        let modelBuilder: ((any Api) -> Model)?
		        let safeDIBuilder: ((Token, Instantiator<Model>) -> Page)?
		    }
		}

		extension Page {
		    static func __safeDI_init(token: Token, modelBuilder: Instantiator<Model>, safeDIBuilder: ((Token, Instantiator<Model>) -> Page)?) -> Page {
		        if let safeDIBuilder { safeDIBuilder(token, modelBuilder) } else { Page(token: token, modelBuilder: modelBuilder) }
		    }
		}
		#endif

		"""])
		#expect(output.modules["Mid"]?.generatedFiles == ["Mid.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feed)
		import Feed
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Shell {
		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            logger: (() -> Logger)? = nil,
		            hub: Hub.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                logger: logger,
		                hub: hub
		            )
		        }

		        public var logger: (() -> Logger)? { __safeDI_storage.logger }
		        public var hub: Hub.SafeDIOverrides { __safeDI_storage.hub }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                logger: (() -> Logger)?,
		                hub: Hub.SafeDIOverrides
		            ) {
		                self.logger = logger
		                self.hub = hub
		            }

		            let logger: (() -> Logger)?
		            let hub: Hub.SafeDIOverrides
		        }
		    }

		    // SafeDI counts `Api` as `public`: no module it reads declares it narrower. If `Api` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    public static func mock(
		        apiBuilder: (() -> any Api)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Shell {
		        Shell.__safeDI_mock(apiBuilder: apiBuilder, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        apiBuilder __safeDI_apiBuilder: (() -> any Api)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Shell {
		        let logger = if let safeDIBuilder = safeDIOverrides.logger { safeDIBuilder() } else { Logger() }
		        func __safeDI_hub() -> Hub {
		            func __safeDI_apiBuilder_Hub() -> Hub.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(pageBuilder: { _ in __safeDI_apiBuilder_Hub_Page_Scope() }, modelBuilder: { _ in __safeDI_apiBuilder_Hub_Model_Scope() })
		            }
		            func __safeDI_apiBuilder_Hub_Page_Scope() -> Hub.SafeDIMockScope_Api.Page_Scope.__safeDI_Builder<any Api> {
		                .init(modelBuilder: { _ in __safeDI_apiBuilder_Hub_Model_Scope() })
		            }
		            func __safeDI_apiBuilder_Hub_Model_Scope() -> Hub.SafeDIMockScope_Api.Model_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = Live()
		                    return api
		                })
		            }
		            _ = Hub.__safeDI_Hub_mock_9D3DEE011EBEDDFF.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Hub.__safeDI_mock(apiBuilder: __safeDI_apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_Hub(), safeDIOverrides: safeDIOverrides.hub)
		        }
		        let hub: Hub = __safeDI_hub()
		        return Shell(logger: logger, hub: hub)
		    }
		}

		extension Shell {
		    public enum __safeDI_Shell_mock_BEDDA3C65C73F485 {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feed)
		import Feed
		#endif
		#if canImport(Mid)
		import Mid
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            shell: Shell.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                shell: shell
		            )
		        }

		        var shell: Shell.SafeDIOverrides { __safeDI_storage.shell }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                shell: Shell.SafeDIOverrides
		            ) {
		                self.shell = shell
		            }

		            let shell: Shell.SafeDIOverrides
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        _ = Shell.__safeDI_Shell_mock_BEDDA3C65C73F485.self // If this line does not compile, compile the code SafeDI generates for module Mid into Mid: under Bazel, add Mid’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let shell = Shell.__safeDI_mock(safeDIOverrides: safeDIOverrides.shell)
		        return Root(shell: shell)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsFillByNameFromLevelFunction_whenFillBuildsTypeWithChildOfItsOwn() async throws {
		// `Live` builds a `Tracker` of its own, so its fill declares a function, which the level function calls by name.
		let modules = Self.pageModules(app: [
			"""
			@Instantiable
			public final class Tracker: Instantiable {
			    public init() {}
			}
			""",
			"""
			@Instantiable(fulfillingAdditionalTypes: [Api.self])
			public final class Live: Api, Instantiable {
			    public init(tracker: Tracker) {
			        self.tracker = tracker
			    }

			    @Instantiated public let tracker: Tracker
			}
			""",
			Self.root(holding: "page: Page"),
		])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif


		"""])
		#expect(output.modules["Feed"]?.generatedFiles == ["Feed.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Page {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct detailBuilder_Values {
		            public let navigator: Navigator
		            public let logger: Logger
		        }

		        nonisolated public enum Detail_Scope {
		            nonisolated public struct leafBuilder_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let leafBuilder: (leafBuilder_Values) -> SafeDIMockScope_Api.Leaf_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(leafBuilder: @escaping (leafBuilder_Values) -> SafeDIMockScope_Api.Leaf_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.leafBuilder = leafBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(leafBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		                }
		            }
		        }

		        nonisolated public enum Leaf_Scope {
		            nonisolated public struct api_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let api: (api_Values) -> __safeDI_Built

		                public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                    self.api = api
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(api: { _ in __safeDI_builder() })
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let detailBuilder: (detailBuilder_Values) -> SafeDIMockScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(detailBuilder: @escaping (detailBuilder_Values) -> SafeDIMockScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.detailBuilder = detailBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(detailBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            navigator: (() -> Navigator)? = nil,
		            logger: (() -> Logger)? = nil,
		            detailBuilder: __safeDI_Feed_Detail_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                navigator: navigator,
		                logger: logger,
		                detailBuilder: detailBuilder
		            )
		        }

		        public var navigator: (() -> Navigator)? { __safeDI_storage.navigator }
		        public var logger: (() -> Logger)? { __safeDI_storage.logger }
		        public var detailBuilder: __safeDI_Feed_Detail_MockConfiguration { __safeDI_storage.detailBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                navigator: (() -> Navigator)?,
		                logger: (() -> Logger)?,
		                detailBuilder: __safeDI_Feed_Detail_MockConfiguration
		            ) {
		                self.navigator = navigator
		                self.logger = logger
		                self.detailBuilder = detailBuilder
		            }

		            let navigator: (() -> Navigator)?
		            let logger: (() -> Logger)?
		            let detailBuilder: __safeDI_Feed_Detail_MockConfiguration
		        }
		    }

		    // SafeDI counts `Api` as `public`: no module it reads declares it narrower. If `Api` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    public static func mock(
		        apiBuilder: @escaping () -> any Api,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Page {
		        Page.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        apiBuilder __safeDI_apiBuilder: Page.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Page {
		        let navigator = if let safeDIBuilder = safeDIOverrides.navigator { safeDIBuilder() } else { Navigator() }
		        let logger = if let safeDIBuilder = safeDIOverrides.logger { safeDIBuilder() } else { Logger() }
		        let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder.detailBuilder(SafeDIMockScope_Api.detailBuilder_Values(navigator: navigator, logger: logger))
		        func __safeDI_detailBuilder() -> Detail {
		            let __safeDI_apiBuilder_leafBuilder = __safeDI_apiBuilder_detailBuilder.leafBuilder(SafeDIMockScope_Api.Detail_Scope.leafBuilder_Values())
		            func __safeDI_leafBuilder() -> Leaf {
		                let api: any Api = __safeDI_apiBuilder_leafBuilder.api(SafeDIMockScope_Api.Leaf_Scope.api_Values())
		                return if let safeDIBuilder = safeDIOverrides.detailBuilder.leafBuilder { safeDIBuilder(api) } else { Leaf(api: api) }
		            }
		            let leafBuilder = Instantiator<Leaf>(__safeDI_leafBuilder)
		            return Detail.__safeDI_init(leafBuilder: leafBuilder, safeDIBuilder: safeDIOverrides.detailBuilder.safeDIBuilder)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        return Page(navigator: navigator, logger: logger, detailBuilder: detailBuilder)
		    }
		}

		extension Page {
		    public enum __safeDI_Page_mock_50657E78D19F8704 {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `Detail` is constructed within the public mock trees of module `Feed`.
		nonisolated public struct __safeDI_Feed_Detail_MockConfiguration {
		    public init(
		        leafBuilder: ((any Api) -> Leaf)? = nil,
		        _ safeDIBuilder: ((Instantiator<Leaf>) -> Detail)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            leafBuilder: leafBuilder,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var leafBuilder: ((any Api) -> Leaf)? { __safeDI_storage.leafBuilder }
		    /// Overrides how `Detail` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((Instantiator<Leaf>) -> Detail)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            leafBuilder: ((any Api) -> Leaf)?,
		            safeDIBuilder: ((Instantiator<Leaf>) -> Detail)?
		        ) {
		            self.leafBuilder = leafBuilder
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let leafBuilder: ((any Api) -> Leaf)?
		        let safeDIBuilder: ((Instantiator<Leaf>) -> Detail)?
		    }
		}

		extension Detail {
		    static func __safeDI_init(leafBuilder: Instantiator<Leaf>, safeDIBuilder: ((Instantiator<Leaf>) -> Detail)?) -> Detail {
		        if let safeDIBuilder { safeDIBuilder(leafBuilder) } else { Detail(leafBuilder: leafBuilder) }
		    }
		}
		#endif

		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feed)
		import Feed
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            page: Page.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                page: page
		            )
		        }

		        var page: Page.SafeDIOverrides { __safeDI_storage.page }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                page: Page.SafeDIOverrides
		            ) {
		                self.page = page
		            }

		            let page: Page.SafeDIOverrides
		        }
		    }

		    static func mock(
		        apiBuilder: (() -> any Api)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_page() -> Page {
		            func __safeDI_apiBuilder_Page_Leaf_Scope_api(_ scope: Page.SafeDIMockScope_Api.Leaf_Scope.api_Values) -> any Api {
		                func __safeDI_api() -> Live {
		                    let tracker = Tracker()
		                    return Live(tracker: tracker)
		                }
		                let api: any Api = __safeDI_api()
		                return api
		            }
		            func __safeDI_apiBuilder_Page() -> Page.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(detailBuilder: { _ in __safeDI_apiBuilder_Page_Detail_Scope() })
		            }
		            func __safeDI_apiBuilder_Page_Detail_Scope() -> Page.SafeDIMockScope_Api.Detail_Scope.__safeDI_Builder<any Api> {
		                .init(leafBuilder: { _ in __safeDI_apiBuilder_Page_Leaf_Scope() })
		            }
		            func __safeDI_apiBuilder_Page_Leaf_Scope() -> Page.SafeDIMockScope_Api.Leaf_Scope.__safeDI_Builder<any Api> {
		                .init(api: { scope in __safeDI_apiBuilder_Page_Leaf_Scope_api(scope) })
		            }
		            _ = Page.__safeDI_Page_mock_50657E78D19F8704.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Page.__safeDI_mock(apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_Page(), safeDIOverrides: safeDIOverrides.page)
		        }
		        let page: Page = __safeDI_page()
		        return Root(page: page)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresLevelFunctionsInsideEachCallsBuilderFunction_whenCallerCallsPublicMockTwice() async throws {
		let modules = Self.pageModules(app: [
			Self.live,
			"""
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(page: Page, backupPage: Page) {
			        self.page = page
			        self.backupPage = backupPage
			    }

			    @Instantiated public let page: Page
			    @Instantiated public let backupPage: Page
			}
			""",
		])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif


		"""])
		#expect(output.modules["Feed"]?.generatedFiles == ["Feed.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Page {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct detailBuilder_Values {
		            public let navigator: Navigator
		            public let logger: Logger
		        }

		        nonisolated public enum Detail_Scope {
		            nonisolated public struct leafBuilder_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let leafBuilder: (leafBuilder_Values) -> SafeDIMockScope_Api.Leaf_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(leafBuilder: @escaping (leafBuilder_Values) -> SafeDIMockScope_Api.Leaf_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.leafBuilder = leafBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(leafBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		                }
		            }
		        }

		        nonisolated public enum Leaf_Scope {
		            nonisolated public struct api_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let api: (api_Values) -> __safeDI_Built

		                public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                    self.api = api
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(api: { _ in __safeDI_builder() })
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let detailBuilder: (detailBuilder_Values) -> SafeDIMockScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(detailBuilder: @escaping (detailBuilder_Values) -> SafeDIMockScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.detailBuilder = detailBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(detailBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            navigator: (() -> Navigator)? = nil,
		            logger: (() -> Logger)? = nil,
		            detailBuilder: __safeDI_Feed_Detail_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                navigator: navigator,
		                logger: logger,
		                detailBuilder: detailBuilder
		            )
		        }

		        public var navigator: (() -> Navigator)? { __safeDI_storage.navigator }
		        public var logger: (() -> Logger)? { __safeDI_storage.logger }
		        public var detailBuilder: __safeDI_Feed_Detail_MockConfiguration { __safeDI_storage.detailBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                navigator: (() -> Navigator)?,
		                logger: (() -> Logger)?,
		                detailBuilder: __safeDI_Feed_Detail_MockConfiguration
		            ) {
		                self.navigator = navigator
		                self.logger = logger
		                self.detailBuilder = detailBuilder
		            }

		            let navigator: (() -> Navigator)?
		            let logger: (() -> Logger)?
		            let detailBuilder: __safeDI_Feed_Detail_MockConfiguration
		        }
		    }

		    // SafeDI counts `Api` as `public`: no module it reads declares it narrower. If `Api` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    public static func mock(
		        apiBuilder: @escaping () -> any Api,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Page {
		        Page.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        apiBuilder __safeDI_apiBuilder: Page.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Page {
		        let navigator = if let safeDIBuilder = safeDIOverrides.navigator { safeDIBuilder() } else { Navigator() }
		        let logger = if let safeDIBuilder = safeDIOverrides.logger { safeDIBuilder() } else { Logger() }
		        let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder.detailBuilder(SafeDIMockScope_Api.detailBuilder_Values(navigator: navigator, logger: logger))
		        func __safeDI_detailBuilder() -> Detail {
		            let __safeDI_apiBuilder_leafBuilder = __safeDI_apiBuilder_detailBuilder.leafBuilder(SafeDIMockScope_Api.Detail_Scope.leafBuilder_Values())
		            func __safeDI_leafBuilder() -> Leaf {
		                let api: any Api = __safeDI_apiBuilder_leafBuilder.api(SafeDIMockScope_Api.Leaf_Scope.api_Values())
		                return if let safeDIBuilder = safeDIOverrides.detailBuilder.leafBuilder { safeDIBuilder(api) } else { Leaf(api: api) }
		            }
		            let leafBuilder = Instantiator<Leaf>(__safeDI_leafBuilder)
		            return Detail.__safeDI_init(leafBuilder: leafBuilder, safeDIBuilder: safeDIOverrides.detailBuilder.safeDIBuilder)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        return Page(navigator: navigator, logger: logger, detailBuilder: detailBuilder)
		    }
		}

		extension Page {
		    public enum __safeDI_Page_mock_50657E78D19F8704 {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `Detail` is constructed within the public mock trees of module `Feed`.
		nonisolated public struct __safeDI_Feed_Detail_MockConfiguration {
		    public init(
		        leafBuilder: ((any Api) -> Leaf)? = nil,
		        _ safeDIBuilder: ((Instantiator<Leaf>) -> Detail)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            leafBuilder: leafBuilder,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var leafBuilder: ((any Api) -> Leaf)? { __safeDI_storage.leafBuilder }
		    /// Overrides how `Detail` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((Instantiator<Leaf>) -> Detail)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            leafBuilder: ((any Api) -> Leaf)?,
		            safeDIBuilder: ((Instantiator<Leaf>) -> Detail)?
		        ) {
		            self.leafBuilder = leafBuilder
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let leafBuilder: ((any Api) -> Leaf)?
		        let safeDIBuilder: ((Instantiator<Leaf>) -> Detail)?
		    }
		}

		extension Detail {
		    static func __safeDI_init(leafBuilder: Instantiator<Leaf>, safeDIBuilder: ((Instantiator<Leaf>) -> Detail)?) -> Detail {
		        if let safeDIBuilder { safeDIBuilder(leafBuilder) } else { Detail(leafBuilder: leafBuilder) }
		    }
		}
		#endif

		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feed)
		import Feed
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            page: Page.SafeDIOverrides = .init(),
		            backupPage: Page.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                page: page,
		                backupPage: backupPage
		            )
		        }

		        var page: Page.SafeDIOverrides { __safeDI_storage.page }
		        var backupPage: Page.SafeDIOverrides { __safeDI_storage.backupPage }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                page: Page.SafeDIOverrides,
		                backupPage: Page.SafeDIOverrides
		            ) {
		                self.page = page
		                self.backupPage = backupPage
		            }

		            let page: Page.SafeDIOverrides
		            let backupPage: Page.SafeDIOverrides
		        }
		    }

		    static func mock(
		        apiBuilder: (() -> any Api)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_page() -> Page {
		            func __safeDI_apiBuilder_Page() -> Page.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(detailBuilder: { _ in __safeDI_apiBuilder_Page_Detail_Scope() })
		            }
		            func __safeDI_apiBuilder_Page_Detail_Scope() -> Page.SafeDIMockScope_Api.Detail_Scope.__safeDI_Builder<any Api> {
		                .init(leafBuilder: { _ in __safeDI_apiBuilder_Page_Leaf_Scope() })
		            }
		            func __safeDI_apiBuilder_Page_Leaf_Scope() -> Page.SafeDIMockScope_Api.Leaf_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = Live()
		                    return api
		                })
		            }
		            _ = Page.__safeDI_Page_mock_50657E78D19F8704.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Page.__safeDI_mock(apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_Page(), safeDIOverrides: safeDIOverrides.page)
		        }
		        let page: Page = __safeDI_page()
		        func __safeDI_backupPage() -> Page {
		            func __safeDI_apiBuilder_Page() -> Page.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(detailBuilder: { _ in __safeDI_apiBuilder_Page_Detail_Scope() })
		            }
		            func __safeDI_apiBuilder_Page_Detail_Scope() -> Page.SafeDIMockScope_Api.Detail_Scope.__safeDI_Builder<any Api> {
		                .init(leafBuilder: { _ in __safeDI_apiBuilder_Page_Leaf_Scope() })
		            }
		            func __safeDI_apiBuilder_Page_Leaf_Scope() -> Page.SafeDIMockScope_Api.Leaf_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = Live()
		                    return api
		                })
		            }
		            _ = Page.__safeDI_Page_mock_50657E78D19F8704.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Page.__safeDI_mock(apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_Page(), safeDIOverrides: safeDIOverrides.backupPage)
		        }
		        let backupPage: Page = __safeDI_backupPage()
		        return Root(page: page, backupPage: backupPage)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsOverrideClosureFunctionOverFill_whenCalledMockTakesNoOverridesOfItsOwn() async throws {
		// `Detail` builds nothing but its place, so its mock takes no `safeDIOverrides`, and `Root`'s overrides hold a closure
		// that builds `Detail` from the builder a person writes. `Root` fills the place with `Live`, which reads nothing: the
		// closure is handed a function over that fill, and the call the root level function of the struct.
		let modules = [
			ModuleFixture(name: "Core", packageName: "Core", swiftFileContent: [Self.core]),
			ModuleFixture(name: "Feed", packageName: "Feed", swiftFileContent: [
				"""
				import Core
				import SafeDI

				@Instantiable(generateMock: .public)
				public final class Detail: Instantiable {
				    init(api: any Api) {
				        self.api = api
				    }

				    @Instantiated public let api: any Api
				}
				""",
			], dependencies: ["Core"]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContent: [Self.live, Self.root(holding: "detail: Detail")].map { "import Core\nimport Feed\nimport SafeDI\n\n" + $0 }, dependencies: ["Core", "Feed"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif


		"""])
		#expect(output.modules["Feed"]?.generatedFiles == ["Feed.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Detail {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct api_Values {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let api: (api_Values) -> __safeDI_Built

		            public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                self.api = api
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(api: { _ in __safeDI_builder() })
		            }
		        }
		    }

		    // SafeDI counts `Api` as `public`: no module it reads declares it narrower. If `Api` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    public static func mock(
		        apiBuilder: @escaping () -> any Api
		    ) -> Detail {
		        Detail.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        apiBuilder __safeDI_apiBuilder: Detail.SafeDIMockScope_Api.__safeDI_Builder<any Api>
		    ) -> Detail {
		        let api: any Api = __safeDI_apiBuilder.api(SafeDIMockScope_Api.api_Values())
		        return Detail(api: api)
		    }
		}

		extension Detail {
		    public enum __safeDI_Detail_mock_84DC57D5B04EB47D {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feed)
		import Feed
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            detail: ((@escaping () -> any Api) -> Detail)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                detail: detail
		            )
		        }

		        var detail: ((@escaping () -> any Api) -> Detail)? { __safeDI_storage.detail }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                detail: ((@escaping () -> any Api) -> Detail)?
		            ) {
		                self.detail = detail
		            }

		            let detail: ((@escaping () -> any Api) -> Detail)?
		        }
		    }

		    static func mock(
		        apiBuilder: (() -> any Api)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_detail() -> Detail {
		            func __safeDI_apiBuilder_Detail_api() -> any Api {
		                let api: any Api = Live()
		                return api
		            }
		            func __safeDI_apiBuilder_Detail() -> Detail.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(api: { _ in __safeDI_apiBuilder_Detail_api() })
		            }
		            _ = Detail.__safeDI_Detail_mock_84DC57D5B04EB47D.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return if let safeDIBuilder = safeDIOverrides.detail { safeDIBuilder({ if let apiBuilder { apiBuilder() } else { __safeDI_apiBuilder_Detail_api() } }) } else { Detail.__safeDI_mock(apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_Detail()) }
		        }
		        let detail: Detail = __safeDI_detail()
		        return Root(detail: detail)
		    }
		}
		#endif
		"""])
	}

	@Test(arguments: RootLevelValue.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_freesRootLevelValue_whenCallerHoldsOnlyInstantiatorOfChildWhosePlaceItFills(rootLevelValue: RootLevelValue) async throws {
		// `Detail` takes `session` before its tree – forwarded, received, or received only if available – so its root
		// level holds it, and builds `Child`, whose `api` `Root` fills with `Live`, which reads nothing. Holding a child's
		// instantiator keeps no session alive, as inline.
		let feed = """
		import Core
		import SafeDI

		public final class Session {
		    public init() { Session.alive += 1 }
		    deinit { Session.alive -= 1 }
		    nonisolated(unsafe) public static var alive = 0
		}

		@Instantiable
		public final class Child: Instantiable {
		    init(api: any Api) {
		        self.api = api
		    }

		    @Instantiated public let api: any Api
		}

		@Instantiable(generateMock: .public)
		public final class Detail: Instantiable {
		    init(session: \(rootLevelValue.sessionType), childBuilder: Instantiator<Child>) {
		        self.session = session
		        self.childBuilder = childBuilder
		    }

		    \(rootLevelValue.declaration)
		    @Instantiated public let childBuilder: Instantiator<Child>
		}
		"""
		let modules = [
			ModuleFixture(name: "Core", packageName: "Core", swiftFileContent: [Self.core]),
			ModuleFixture(name: "Feed", packageName: "Feed", swiftFileContent: [feed], dependencies: ["Core"]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContent: [Self.live, rootLevelValue.root, rootLevelValue.probe].map { "import Core\nimport Feed\nimport SafeDI\n\n" + $0 }, dependencies: ["Core", "Feed"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		let counts = try await describedCounts(of: modules, output: output, probe: "sessionsWhileChildBuilderLives()")
		if compileVerificationIsEnabled {
			#expect(counts.knownRight == "probe sessionsWhileChildBuilderLives()\nString \"Session 0\"\n")
			#expect(counts.feature == counts.knownRight)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_putsIsolationOnBothFunctions_whenMockedTypeIsOnMainActor() async throws {
		// `Screen` is `@MainActor`, and `Board` spells `mockAttributes: "@MainActor"`: `mock()` and the function only
		// generated code calls each carry the isolation.
		let modules = [
			ModuleFixture(name: "Core", packageName: "Core", swiftFileContent: [Self.core]),
			ModuleFixture(name: "Feed", packageName: "Feed", swiftFileContent: [
				"""
				import Core
				import SafeDI

				@MainActor
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    init(api: any Api) {
				        self.api = api
				    }

				    @Instantiated public let api: any Api
				}

				@Instantiable(mockAttributes: "@MainActor", generateMock: .public)
				public final class Board: Instantiable {
				    init(api: any Api) {
				        self.api = api
				    }

				    @Instantiated public let api: any Api
				}
				""",
			], dependencies: ["Core"]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContent: [
				"""
				import Core
				import Feed

				final class StubApi: Api {}

				@MainActor
				func screenAndBoardTheTestBuilds() -> (Screen, Board) {
				    (Screen.mock(apiBuilder: { StubApi() }), Board.mock(apiBuilder: { StubApi() }))
				}
				""",
			], dependencies: ["Core", "Feed"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif


		"""])
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif


		"""])
		#expect(output.modules["Feed"]?.generatedFiles == ["Feed.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Board {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct api_Values {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let api: (api_Values) -> __safeDI_Built

		            public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                self.api = api
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(api: { _ in __safeDI_builder() })
		            }
		        }
		    }

		    // SafeDI counts `Api` as `public`: no module it reads declares it narrower. If `Api` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    @MainActor public static func mock(
		        apiBuilder: @escaping () -> any Api
		    ) -> Board {
		        Board.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    @MainActor public static func __safeDI_mock(
		        apiBuilder __safeDI_apiBuilder: Board.SafeDIMockScope_Api.__safeDI_Builder<any Api>
		    ) -> Board {
		        let api: any Api = __safeDI_apiBuilder.api(SafeDIMockScope_Api.api_Values())
		        return Board(api: api)
		    }
		}

		extension Board {
		    public enum __safeDI_Board_mock_E5908DDC41D6D7B9 {}
		}
		#endif

		#if DEBUG
		extension Screen {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct api_Values {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let api: (api_Values) -> __safeDI_Built

		            public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                self.api = api
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(api: { _ in __safeDI_builder() })
		            }
		        }
		    }

		    public static func mock(
		        apiBuilder: @escaping () -> any Api
		    ) -> Screen {
		        Screen.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        apiBuilder __safeDI_apiBuilder: Screen.SafeDIMockScope_Api.__safeDI_Builder<any Api>
		    ) -> Screen {
		        let api: any Api = __safeDI_apiBuilder.api(SafeDIMockScope_Api.api_Values())
		        return Screen(api: api)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_8E4A1436EA0AFB5F {}
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresGeneratedOnlyFunctionBesideConstructionFunctionOfOneName_whenTypeWithCustomMockIsBuiltInAnotherPublicMock() async throws {
		// `Card` names a hand-written `preview`, which its generated `mock()` calls, and `Deck`'s public mock builds it with
		// `preview` through `Card.__safeDI_mock(…, safeDIBuilder:)`. `Card`'s mock takes a builder struct, so its function
		// only generated code calls is a `Card.__safeDI_mock` too: the required `safeDIBuilder:` tells the two apart.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.cardModules(cardDeclarations: ["@Instantiated public let logger: Logger"]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif


		"""])
		#expect(output.modules["Feed"]?.generatedFiles == ["Feed.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Card {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct api_Values {
		            public let logger: Logger
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let api: (api_Values) -> __safeDI_Built

		            public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                self.api = api
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(api: { _ in __safeDI_builder() })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            logger: (() -> Logger)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                logger: logger
		            )
		        }

		        public var logger: (() -> Logger)? { __safeDI_storage.logger }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                logger: (() -> Logger)?
		            ) {
		                self.logger = logger
		            }

		            let logger: (() -> Logger)?
		        }
		    }

		    // SafeDI counts `Api` as `public`: no module it reads declares it narrower. If `Api` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    public static func mock(
		        retries: Int? = nil,
		        apiBuilder: @escaping () -> any Api,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Card {
		        Card.__safeDI_mock(retries: retries, apiBuilder: .init(__safeDI_noScope: apiBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        retries: Int? = nil,
		        apiBuilder __safeDI_apiBuilder: Card.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Card {
		        let retries = retries ?? (3)
		        let logger = if let safeDIBuilder = safeDIOverrides.logger { safeDIBuilder() } else { Logger() }
		        let api: any Api = __safeDI_apiBuilder.api(SafeDIMockScope_Api.api_Values(logger: logger))
		        return Card.preview(api: api, logger: logger, retries: retries)
		    }
		}

		extension Card {
		    public enum __safeDI_Card_mock_1B7F9539E82764F7 {}
		}
		#endif

		#if DEBUG
		extension Deck {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct card_Values {}

		        nonisolated public enum Card_Scope {
		            nonisolated public struct api_Values {
		                public let logger: Logger
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let api: (api_Values) -> __safeDI_Built

		                public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                    self.api = api
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(api: { _ in __safeDI_builder() })
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let card: (card_Values) -> SafeDIMockScope_Api.Card_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(card: @escaping (card_Values) -> SafeDIMockScope_Api.Card_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.card = card
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(card: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            card: __safeDI_Feed_Card_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                card: card
		            )
		        }

		        public var card: __safeDI_Feed_Card_MockConfiguration { __safeDI_storage.card }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                card: __safeDI_Feed_Card_MockConfiguration
		            ) {
		                self.card = card
		            }

		            let card: __safeDI_Feed_Card_MockConfiguration
		        }
		    }

		    public static func mock(
		        apiBuilder: @escaping () -> any Api,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Deck {
		        Deck.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        apiBuilder __safeDI_apiBuilder: Deck.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Deck {
		        let __safeDI_apiBuilder_card = __safeDI_apiBuilder.card(SafeDIMockScope_Api.card_Values())
		        func __safeDI_card() -> Card {
		            let logger = if let safeDIBuilder = safeDIOverrides.card.logger { safeDIBuilder() } else { Logger() }
		            let api: any Api = __safeDI_apiBuilder_card.api(SafeDIMockScope_Api.Card_Scope.api_Values(logger: logger))
		            return Card.__safeDI_mock(api: api, logger: logger, retries: safeDIOverrides.card.retries, safeDIBuilder: safeDIOverrides.card.safeDIBuilder)
		        }
		        let card: Card = __safeDI_card()
		        return Deck(card: card)
		    }
		}

		extension Deck {
		    public enum __safeDI_Deck_mock_2DD0789CC2439EEA {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `Card` is constructed within the public mock trees of module `Feed`.
		nonisolated public struct __safeDI_Feed_Card_MockConfiguration {
		    public init(
		        logger: (() -> Logger)? = nil,
		        retries: Int? = nil,
		        _ safeDIBuilder: ((any Api, Logger, Int) -> Card)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            logger: logger,
		            retries: retries,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var logger: (() -> Logger)? { __safeDI_storage.logger }
		    /// `nil` keeps the default of `Card`’s `retries`.
		    public var retries: Int? { __safeDI_storage.retries }
		    /// Overrides how `Card` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((any Api, Logger, Int) -> Card)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            logger: (() -> Logger)?,
		            retries: Int?,
		            safeDIBuilder: ((any Api, Logger, Int) -> Card)?
		        ) {
		            self.logger = logger
		            self.retries = retries
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let logger: (() -> Logger)?
		        let retries: Int?
		        let safeDIBuilder: ((any Api, Logger, Int) -> Card)?
		    }
		}

		extension Card {
		    static func __safeDI_mock(api: any Api, logger: Logger, retries: Int?, safeDIBuilder: ((any Api, Logger, Int) -> Card)?) -> Card {
		        let retries = retries ?? (3)
		        return if let safeDIBuilder { safeDIBuilder(api, logger, retries) } else { Card.preview(api: api, logger: logger, retries: retries) }
		    }
		}
		#endif

		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_tellsOverloadsApartBySafeDIBuilderAlone_whenTypeWithCustomMockTakesNoOverrides() async throws {
		// `Card` builds nothing but its place, so neither of its functions takes `safeDIOverrides`.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.cardModules(cardDeclarations: []), integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif


		"""])
		#expect(output.modules["Feed"]?.generatedFiles == ["Feed.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Card {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct api_Values {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let api: (api_Values) -> __safeDI_Built

		            public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                self.api = api
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(api: { _ in __safeDI_builder() })
		            }
		        }
		    }

		    // SafeDI counts `Api` as `public`: no module it reads declares it narrower. If `Api` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    public static func mock(
		        retries: Int? = nil,
		        apiBuilder: @escaping () -> any Api
		    ) -> Card {
		        Card.__safeDI_mock(retries: retries, apiBuilder: .init(__safeDI_noScope: apiBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        retries: Int? = nil,
		        apiBuilder __safeDI_apiBuilder: Card.SafeDIMockScope_Api.__safeDI_Builder<any Api>
		    ) -> Card {
		        let retries = retries ?? (3)
		        let api: any Api = __safeDI_apiBuilder.api(SafeDIMockScope_Api.api_Values())
		        return Card.preview(api: api, retries: retries)
		    }
		}

		extension Card {
		    public enum __safeDI_Card_mock_3A0ED48D7DF5E1C3 {}
		}
		#endif

		#if DEBUG
		extension Deck {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct card_Values {}

		        nonisolated public enum Card_Scope {
		            nonisolated public struct api_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let api: (api_Values) -> __safeDI_Built

		                public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                    self.api = api
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(api: { _ in __safeDI_builder() })
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let card: (card_Values) -> SafeDIMockScope_Api.Card_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(card: @escaping (card_Values) -> SafeDIMockScope_Api.Card_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.card = card
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(card: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            card: __safeDI_Feed_Card_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                card: card
		            )
		        }

		        public var card: __safeDI_Feed_Card_MockConfiguration { __safeDI_storage.card }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                card: __safeDI_Feed_Card_MockConfiguration
		            ) {
		                self.card = card
		            }

		            let card: __safeDI_Feed_Card_MockConfiguration
		        }
		    }

		    public static func mock(
		        apiBuilder: @escaping () -> any Api,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Deck {
		        Deck.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        apiBuilder __safeDI_apiBuilder: Deck.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Deck {
		        let __safeDI_apiBuilder_card = __safeDI_apiBuilder.card(SafeDIMockScope_Api.card_Values())
		        func __safeDI_card() -> Card {
		            let api: any Api = __safeDI_apiBuilder_card.api(SafeDIMockScope_Api.Card_Scope.api_Values())
		            return Card.__safeDI_mock(api: api, retries: safeDIOverrides.card.retries, safeDIBuilder: safeDIOverrides.card.safeDIBuilder)
		        }
		        let card: Card = __safeDI_card()
		        return Deck(card: card)
		    }
		}

		extension Deck {
		    public enum __safeDI_Deck_mock_34502B3D12A4EE91 {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `Card` is constructed within the public mock trees of module `Feed`.
		nonisolated public struct __safeDI_Feed_Card_MockConfiguration {
		    public init(
		        retries: Int? = nil,
		        _ safeDIBuilder: ((any Api, Int) -> Card)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            retries: retries,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    /// `nil` keeps the default of `Card`’s `retries`.
		    public var retries: Int? { __safeDI_storage.retries }
		    /// Overrides how `Card` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((any Api, Int) -> Card)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            retries: Int?,
		            safeDIBuilder: ((any Api, Int) -> Card)?
		        ) {
		            self.retries = retries
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let retries: Int?
		        let safeDIBuilder: ((any Api, Int) -> Card)?
		    }
		}

		extension Card {
		    static func __safeDI_mock(api: any Api, retries: Int?, safeDIBuilder: ((any Api, Int) -> Card)?) -> Card {
		        let retries = retries ?? (3)
		        return if let safeDIBuilder { safeDIBuilder(api, retries) } else { Card.preview(api: api, retries: retries) }
		    }
		}
		#endif

		"""])
	}

	// MARK: Tests – which hole types take a builder struct

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsClosureOverEnumForHoleTypeBuiltInSendableFunctionOnly_whenMockTakesTwoHoleTypes() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"public protocol Api {}\npublic protocol Gadget: Sendable {}",
				"""
				@Instantiable
				public struct Held: Instantiable, Sendable {
				    public init(gadget: any Gadget) {
				        self.gadget = gadget
				    }

				    @Instantiated let gadget: any Gadget
				}
				""",
				"""
				@Instantiable(generateMock: .public)
				public struct Panel: Instantiable {
				    public init(api: any Api, heldBuilder: SendableInstantiator<Held>) {
				        self.api = api
				        self.heldBuilder = heldBuilder
				    }

				    @Instantiated let api: any Api
				    @Instantiated let heldBuilder: SendableInstantiator<Held>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Panel+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Panel {
			    nonisolated public enum SafeDIMockScope_Api {
			        nonisolated public struct api_Values {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let api: (api_Values) -> __safeDI_Built

			            public init(api: @escaping (api_Values) -> __safeDI_Built) {
			                self.api = api
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(api: { _ in __safeDI_builder() })
			            }
			        }
			    }

			    nonisolated public enum SafeDIMockScope_Gadget {
			        nonisolated public enum Held_Scope {
			            nonisolated public struct gadget_Values {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let gadget: (gadget_Values) -> __safeDI_Built

			                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
			                    self.gadget = gadget
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(gadget: { _ in __safeDI_builder() })
			                }
			            }
			        }
			    }

			    nonisolated public enum SafeDISendableMockScope_Gadget {
			        nonisolated public struct heldBuilder_Values: Sendable {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			            public let heldBuilder: @Sendable (heldBuilder_Values) -> SafeDIMockScope_Gadget.Held_Scope.__safeDI_Builder<__safeDI_Built>

			            public init(heldBuilder: @escaping @Sendable (heldBuilder_Values) -> SafeDIMockScope_Gadget.Held_Scope.__safeDI_Builder<__safeDI_Built>) {
			                self.heldBuilder = heldBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                self.init(heldBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            heldBuilder: (@Sendable (any Gadget) -> Held)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                heldBuilder: heldBuilder
			            )
			        }

			        public var heldBuilder: (@Sendable (any Gadget) -> Held)? { __safeDI_storage.heldBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                heldBuilder: (@Sendable (any Gadget) -> Held)?
			            ) {
			                self.heldBuilder = heldBuilder
			            }

			            let heldBuilder: (@Sendable (any Gadget) -> Held)?
			        }
			    }

			    public static func mock(
			        apiBuilder: @escaping () -> any Api,
			        gadgetSendableBuilder: @escaping @Sendable () -> any Gadget,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Panel {
			        Panel.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), gadgetSendableBuilder: .init(__safeDI_noScope: gadgetSendableBuilder), safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        apiBuilder __safeDI_apiBuilder: Panel.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
			        gadgetSendableBuilder __safeDI_gadgetSendableBuilder: Panel.SafeDISendableMockScope_Gadget.__safeDI_Builder<any Gadget>,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Panel {
			        let api: any Api = __safeDI_apiBuilder.api(SafeDIMockScope_Api.api_Values())
			        let __safeDI_heldBuilder__safeDIBuilder = safeDIOverrides.heldBuilder
			        @Sendable nonisolated func __safeDI_heldBuilder() -> Held {
			            let __safeDI_gadgetSendableBuilder_heldBuilder = __safeDI_gadgetSendableBuilder.heldBuilder(SafeDISendableMockScope_Gadget.heldBuilder_Values())
			            let gadget: any Gadget = __safeDI_gadgetSendableBuilder_heldBuilder.gadget(SafeDIMockScope_Gadget.Held_Scope.gadget_Values())
			            return if let safeDIBuilder = __safeDI_heldBuilder__safeDIBuilder { safeDIBuilder(gadget) } else { Held(gadget: gadget) }
			        }
			        let heldBuilder = SendableInstantiator<Held>(__safeDI_heldBuilder)
			        return Panel(api: api, heldBuilder: heldBuilder)
			    }
			}

			extension Panel {
			    public enum __safeDI_Panel_mock_0806C064B4DBD3BC {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsClosureOverEnumForHoleTypeWhosePlaceForwardsOnly_whenMockTakesTwoHoleTypes() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"public protocol Api {}\npublic protocol Gadget {}",
				"""
				@Instantiable(generateMock: .public)
				public struct Panel: Instantiable {
				    public init(api: any Api, gadgetBuilder: ErasedInstantiator<String, any Gadget>) {
				        self.api = api
				        self.gadgetBuilder = gadgetBuilder
				    }

				    @Instantiated let api: any Api
				    @Instantiated(fulfilledByType: "LiveGadget") let gadgetBuilder: ErasedInstantiator<String, any Gadget>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Panel+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Panel {
			    nonisolated public enum SafeDIMockScope_Api {
			        nonisolated public struct api_Values {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let api: (api_Values) -> __safeDI_Built

			            public init(api: @escaping (api_Values) -> __safeDI_Built) {
			                self.api = api
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(api: { _ in __safeDI_builder() })
			            }
			        }
			    }

			    nonisolated public enum SafeDIMockScope_LiveGadget_Gadget {
			        nonisolated public struct gadgetBuilder_Values {
			            public let api: any Api
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let gadgetBuilder: (gadgetBuilder_Values) -> ErasedInstantiator<String, __safeDI_Built>.Builder

			            public init(gadgetBuilder: @escaping (gadgetBuilder_Values) -> ErasedInstantiator<String, __safeDI_Built>.Builder) {
			                self.gadgetBuilder = gadgetBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<String, __safeDI_Built>.Builder) {
			                self.init(gadgetBuilder: { _ in __safeDI_builder })
			            }
			        }
			    }

			    public static func mock(
			        apiBuilder: @escaping () -> any Api,
			        liveGadget_GadgetBuilder: @escaping ErasedInstantiator<String, any Gadget>.Builder
			    ) -> Panel {
			        Panel.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), liveGadget_GadgetBuilder: .init(__safeDI_noScope: liveGadget_GadgetBuilder))
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        apiBuilder __safeDI_apiBuilder: Panel.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
			        liveGadget_GadgetBuilder __safeDI_liveGadget_GadgetBuilder: Panel.SafeDIMockScope_LiveGadget_Gadget.__safeDI_Builder<any Gadget>
			    ) -> Panel {
			        let api: any Api = __safeDI_apiBuilder.api(SafeDIMockScope_Api.api_Values())
			        let gadgetBuilder = ErasedInstantiator<String, any Gadget>(__safeDI_liveGadget_GadgetBuilder.gadgetBuilder(SafeDIMockScope_LiveGadget_Gadget.gadgetBuilder_Values(api: api)))
			        return Panel(api: api, gadgetBuilder: gadgetBuilder)
			    }
			}

			extension Panel {
			    public enum __safeDI_Panel_mock_138EC2EB92C8F218 {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsClosureOverEnumForHoleTypeHeldLazilyOnly_whenMockTakesTwoHoleTypes() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"public protocol Api {}\npublic protocol Gadget {}",
				"""
				@Instantiable(generateMock: .public)
				public struct Panel: Instantiable {
				    public init(api: any Api, gadget: LazilyInstantiated<any Gadget>) {
				        self.api = api
				        self.gadget = gadget
				    }

				    @Instantiated let api: any Api
				    @Instantiated let gadget: LazilyInstantiated<any Gadget>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Panel+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Panel {
			    nonisolated public enum SafeDIMockScope_Api {
			        nonisolated public struct api_Values {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let api: (api_Values) -> __safeDI_Built

			            public init(api: @escaping (api_Values) -> __safeDI_Built) {
			                self.api = api
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(api: { _ in __safeDI_builder() })
			            }
			        }
			    }

			    nonisolated public enum SafeDIMockScope_Gadget {
			        nonisolated public struct gadget_Values {
			            public let api: any Api
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let gadget: (gadget_Values) -> __safeDI_Built

			            public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
			                self.gadget = gadget
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(gadget: { _ in __safeDI_builder() })
			            }
			        }
			    }

			    public static func mock(
			        apiBuilder: @escaping () -> any Api,
			        gadgetBuilder: @escaping () -> any Gadget
			    ) -> Panel {
			        Panel.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), gadgetBuilder: .init(__safeDI_noScope: gadgetBuilder))
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        apiBuilder __safeDI_apiBuilder: Panel.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
			        gadgetBuilder __safeDI_gadgetBuilder: Panel.SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget>
			    ) -> Panel {
			        let api: any Api = __safeDI_apiBuilder.api(SafeDIMockScope_Api.api_Values())
			        func __safeDI_gadget() -> any Gadget {
			            __safeDI_gadgetBuilder.gadget(SafeDIMockScope_Gadget.gadget_Values(api: api))
			        }
			        let gadget = LazilyInstantiated<any Gadget>(__safeDI_gadget)
			        return Panel(api: api, gadget: gadget)
			    }
			}

			extension Panel {
			    public enum __safeDI_Panel_mock_590FC229934F61CA {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsClosureOverEnumForHoleTypeWhoseEnumHoldsCalledMocksOnly_whenMockTakesTwoHoleTypes() async throws {
		// `Panel` builds `Board`, another module's public mock, whose place of `Gadget` it cannot fill: its `Gadget` enum holds
		// `Board`'s, so that builder keeps its closure, beside `Panel`'s own place of `Api`, whose builder takes the struct.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "Core", swiftFileContent: [
					"""
					import SafeDI

					public protocol Api {}
					public protocol Gadget {}

					@Instantiable(generateMock: .public)
					public struct Board: Instantiable {
					    init(gadget: any Gadget) {
					        self.gadget = gadget
					    }

					    @Instantiated let gadget: any Gadget
					}
					""",
				]),
				ModuleFixture(name: "Feed", packageName: "Feed", swiftFileContent: [
					"""
					import Core
					import SafeDI

					@Instantiable(generateMock: .public)
					public struct Panel: Instantiable {
					    init(api: any Api, board: Board) {
					        self.api = api
					        self.board = board
					    }

					    @Instantiated let api: any Api
					    @Instantiated let board: Board
					}
					""",
				], dependencies: ["Core"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Board {
		    nonisolated public enum SafeDIMockScope_Gadget {
		        nonisolated public struct gadget_Values {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let gadget: (gadget_Values) -> __safeDI_Built

		            public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
		                self.gadget = gadget
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(gadget: { _ in __safeDI_builder() })
		            }
		        }
		    }

		    public static func mock(
		        gadgetBuilder: @escaping () -> any Gadget
		    ) -> Board {
		        Board.__safeDI_mock(gadgetBuilder: .init(__safeDI_noScope: gadgetBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        gadgetBuilder __safeDI_gadgetBuilder: Board.SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget>
		    ) -> Board {
		        let gadget: any Gadget = __safeDI_gadgetBuilder.gadget(SafeDIMockScope_Gadget.gadget_Values())
		        return Board(gadget: gadget)
		    }
		}

		extension Board {
		    public enum __safeDI_Board_mock_87A6E9FF393A9CA1 {}
		}
		#endif
		"""])
		#expect(output.modules["Feed"]?.generatedFiles == ["Feed.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Panel {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct api_Values {
		            public let board: Board
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let api: (api_Values) -> __safeDI_Built

		            public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                self.api = api
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(api: { _ in __safeDI_builder() })
		            }
		        }
		    }

		    nonisolated public enum SafeDIMockScope_Gadget {
		        nonisolated public struct board_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let board: (board_Values) -> Board.SafeDIMockScope_Gadget.__safeDI_Builder<__safeDI_Built>

		            public init(board: @escaping (board_Values) -> Board.SafeDIMockScope_Gadget.__safeDI_Builder<__safeDI_Built>) {
		                self.board = board
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(board: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init() {}
		    }

		    // SafeDI counts `Api` as `public`: no module it reads declares it narrower. If `Api` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    public static func mock(
		        apiBuilder: @escaping () -> any Api,
		        gadgetBuilder: @escaping () -> any Gadget,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Panel {
		        Panel.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), gadgetBuilder: .init(__safeDI_noScope: gadgetBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        apiBuilder __safeDI_apiBuilder: Panel.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
		        gadgetBuilder __safeDI_gadgetBuilder: Panel.SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Panel {
		        _ = Board.__safeDI_Board_mock_87A6E9FF393A9CA1.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let board = Board.__safeDI_mock(gadgetBuilder: __safeDI_gadgetBuilder.board(SafeDIMockScope_Gadget.board_Values()))
		        let api: any Api = __safeDI_apiBuilder.api(SafeDIMockScope_Api.api_Values(board: board))
		        return Panel(api: api, board: board)
		    }
		}

		extension Panel {
		    public enum __safeDI_Panel_mock_73F832E1E516D67D {}
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_convertsOnlyBuilderThatReachesErasedInstantiator_whenCallerFillsEveryPlaceOfTwoBuilders() async throws {
		// `App` sees `LiveGadget` and `LiveApi` and fills every place of both of `Panel`'s builders. The place of `Gadget` is
		// held in an erased instantiator, so its builder's call converts the closure over the enum its dispatcher switches
		// over; the place of `Api` is plain, so its builder is handed its level function's struct. Each `instantiate()` of
		// the erased instantiator builds one `LiveGadget`. `Panel`'s initializer is internal, so `App` calls its public mock,
		// whose overrides configure `logger`, so no override closure takes either builder.
		let modules = [
			ModuleFixture(name: "Feed", packageName: "Feed", swiftFileContent: [
				"""
				import SafeDI

				public protocol Gadget {}
				public struct AnyGadget: Gadget {
				    public init(_ gadget: any Gadget) {}
				}

				public protocol Api {}

				@Instantiable
				public struct Logger: Instantiable {
				    public init() {}
				}

				@Instantiable(generateMock: .public)
				public struct Panel: Instantiable {
				    init(gadgetBuilder: ErasedInstantiator<(), AnyGadget>, api: any Api, logger: Logger) {
				        self.gadgetBuilder = gadgetBuilder
				        self.api = api
				        self.logger = logger
				    }

				    @Instantiated(fulfilledByType: "LiveGadget", erasedToConcreteExistential: true) public let gadgetBuilder: ErasedInstantiator<(), AnyGadget>
				    @Instantiated public let api: any Api
				    @Instantiated let logger: Logger
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContent: [
				"""
				import Feed
				import SafeDI

				@Instantiable
				public final class LiveGadget: Gadget, Instantiable {
				    public init() { LiveGadget.made += 1 }
				    nonisolated(unsafe) public static var made = 0
				}

				@Instantiable(fulfillingAdditionalTypes: [Api.self])
				public final class LiveApi: Api, Instantiable {
				    public init() {}
				}

				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(panel: Panel) {
				        self.panel = panel
				    }

				    @Instantiated let panel: Panel
				}

				func gadgetsEachInstantiateBuilds() -> String {
				    let panel = Screen.mock().panel
				    let before = LiveGadget.made
				    _ = panel.gadgetBuilder.instantiate()
				    _ = panel.gadgetBuilder.instantiate()
				    return "LiveGadget \\(before), then \\(LiveGadget.made)"
				}
				""",
			], dependencies: ["Feed"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feed)
		import Feed
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            panel: Panel.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                panel: panel
		            )
		        }

		        var panel: Panel.SafeDIOverrides { __safeDI_storage.panel }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                panel: Panel.SafeDIOverrides
		            ) {
		                self.panel = panel
		            }

		            let panel: Panel.SafeDIOverrides
		        }
		    }

		    static func mock(
		        apiBuilder: (() -> any Api)? = nil,
		        liveGadget_AnyGadgetBuilder: (() -> AnyGadget)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_panel() -> Panel {
		            func __safeDI_liveGadget_AnyGadgetBuilder_Panel_gadgetBuilder() -> ErasedInstantiator<(), AnyGadget>.Builder {
		                func __safeDI_gadgetBuilder() -> LiveGadget {
		                    LiveGadget()
		                }
		                return { _ in AnyGadget(__safeDI_gadgetBuilder()) }
		            }
		            func __safeDI_apiBuilder_Panel() -> Panel.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveApi()
		                    return api
		                })
		            }
		            func __safeDI_liveGadget_AnyGadgetBuilder_Panel() -> Panel.SafeDIMockScope_LiveGadget_AnyGadget.__safeDI_Builder<AnyGadget> {
		                .init(gadgetBuilder: { _ in __safeDI_liveGadget_AnyGadgetBuilder_Panel_gadgetBuilder() })
		            }
		            _ = Panel.__safeDI_Panel_mock_EF014F3E7845DA5D.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Panel.__safeDI_mock(apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_Panel(), liveGadget_AnyGadgetBuilder: liveGadget_AnyGadgetBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_liveGadget_AnyGadgetBuilder_Panel(), safeDIOverrides: safeDIOverrides.panel)
		        }
		        let panel: Panel = __safeDI_panel()
		        return Screen(panel: panel)
		    }
		}
		#endif
		"""])
		let description = try await DifferentialValueOracle.describe(DifferentialValuePath(output: output, modules: modules), probes: [DifferentialValueProbe("gadgetsEachInstantiateBuilds()")], filesToDelete: &filesToDelete)
		if compileVerificationIsEnabled {
			#expect(description == "probe gadgetsEachInstantiateBuilds()\nString \"LiveGadget 0, then 2\"\n")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesBuilderThatTakesNothing_whenEveryPlaceOfHoleTypeIsErasedInstantiatorThatForwardsNothing() async throws {
		// An erased instantiator of `()` forwards nothing, so its places take the builder struct; every place is one, and
		// `mock()` takes the builder a seam's readable initializer takes for them, `() -> any Gadget`, as a plain place's.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"public protocol Gadget {}\npublic struct AnyGadget: Gadget {\n    public init(_ gadget: any Gadget) {}\n}",
				"""
				@Instantiable
				public struct Row: Instantiable {
				    public init(gadgetBuilder: ErasedInstantiator<(), AnyGadget>) {
				        self.gadgetBuilder = gadgetBuilder
				    }

				    @Instantiated(fulfilledByType: "LiveGadget", erasedToConcreteExistential: true) let gadgetBuilder: ErasedInstantiator<(), AnyGadget>
				}
				""",
				"""
				@Instantiable(generateMock: .public)
				public struct Panel: Instantiable {
				    public init(gadgetBuilder: ErasedInstantiator<(), AnyGadget>, row: Row) {
				        self.gadgetBuilder = gadgetBuilder
				        self.row = row
				    }

				    @Instantiated(fulfilledByType: "LiveGadget", erasedToConcreteExistential: true) let gadgetBuilder: ErasedInstantiator<(), AnyGadget>
				    @Instantiated let row: Row
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Panel+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Panel {
			    nonisolated public enum SafeDIMockScope_LiveGadget_AnyGadget {
			        nonisolated public struct gadgetBuilder_Values {}

			        nonisolated public struct row_Values {
			            public let gadgetBuilder: ErasedInstantiator<(), AnyGadget>
			        }

			        nonisolated public enum Row_Scope {
			            nonisolated public struct gadgetBuilder_Values {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let gadgetBuilder: (gadgetBuilder_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder

			                public init(gadgetBuilder: @escaping (gadgetBuilder_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder) {
			                    self.gadgetBuilder = gadgetBuilder
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(gadgetBuilder: { _ in { _ in __safeDI_builder() } })
			                }
			            }
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let gadgetBuilder: (gadgetBuilder_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder
			            public let row: (row_Values) -> SafeDIMockScope_LiveGadget_AnyGadget.Row_Scope.__safeDI_Builder<__safeDI_Built>

			            public init(gadgetBuilder: @escaping (gadgetBuilder_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder, row: @escaping (row_Values) -> SafeDIMockScope_LiveGadget_AnyGadget.Row_Scope.__safeDI_Builder<__safeDI_Built>) {
			                self.gadgetBuilder = gadgetBuilder
			                self.row = row
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(gadgetBuilder: { _ in { _ in __safeDI_builder() } }, row: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            row: ((ErasedInstantiator<(), AnyGadget>) -> Row)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                row: row
			            )
			        }

			        public var row: ((ErasedInstantiator<(), AnyGadget>) -> Row)? { __safeDI_storage.row }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                row: ((ErasedInstantiator<(), AnyGadget>) -> Row)?
			            ) {
			                self.row = row
			            }

			            let row: ((ErasedInstantiator<(), AnyGadget>) -> Row)?
			        }
			    }

			    public static func mock(
			        liveGadget_AnyGadgetBuilder: @escaping () -> AnyGadget,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Panel {
			        Panel.__safeDI_mock(liveGadget_AnyGadgetBuilder: .init(__safeDI_noScope: liveGadget_AnyGadgetBuilder), safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        liveGadget_AnyGadgetBuilder __safeDI_liveGadget_AnyGadgetBuilder: Panel.SafeDIMockScope_LiveGadget_AnyGadget.__safeDI_Builder<AnyGadget>,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Panel {
			        let gadgetBuilder = ErasedInstantiator<(), AnyGadget>(__safeDI_liveGadget_AnyGadgetBuilder.gadgetBuilder(SafeDIMockScope_LiveGadget_AnyGadget.gadgetBuilder_Values()))
			        let __safeDI_liveGadget_AnyGadgetBuilder_row = __safeDI_liveGadget_AnyGadgetBuilder.row(SafeDIMockScope_LiveGadget_AnyGadget.row_Values(gadgetBuilder: gadgetBuilder))
			        func __safeDI_row() -> Row {
			            let gadgetBuilder = ErasedInstantiator<(), AnyGadget>(__safeDI_liveGadget_AnyGadgetBuilder_row.gadgetBuilder(SafeDIMockScope_LiveGadget_AnyGadget.Row_Scope.gadgetBuilder_Values()))
			            return if let safeDIBuilder = safeDIOverrides.row { safeDIBuilder(gadgetBuilder) } else { Row(gadgetBuilder: gadgetBuilder) }
			        }
			        let row: Row = __safeDI_row()
			        return Panel(gadgetBuilder: gadgetBuilder, row: row)
			    }
			}

			extension Panel {
			    public enum __safeDI_Panel_mock_EA5A6310FFCC5661 {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """

			""",
		])
	}

	// MARK: Tests – tiers

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresPairOnEveryTier_whenPublicMockTakesBuilderStructOnPublicPackageAndInternalTiers() async throws {
		// `Badge`, `package`, receives `serviceBuilder` only if available, and `Note`, `internal`, receives `memo` only if
		// available, so `Panel`'s mock has three tiers, each a pair; the `package` and `internal` tiers take the builder
		// under `serviceBuilder_`. `Mid`, in `Panel`'s package, passes the place up through the `package` tier.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "pkg", swiftFileContent: [
					"""
					import SafeDI

					public protocol Service: Sendable {}

					package struct Thing {}

					struct Memo {}

					@Instantiable
					package struct Badge: Instantiable {
					    package init(serviceBuilder: Thing?) {
					        self.serviceBuilder = serviceBuilder
					    }

					    @Received(onlyIfAvailable: true) let serviceBuilder: Thing?
					}

					@Instantiable
					struct Note: Instantiable {
					    init(memo: Memo?) {
					        self.memo = memo
					    }

					    @Received(onlyIfAvailable: true) let memo: Memo?
					}

					@Instantiable(generateMock: .public)
					public struct Panel: Instantiable {
					    init(service: any Service, badge: Badge, note: Note) {
					        self.service = service
					        self.badge = badge
					        self.note = note
					    }

					    @Instantiated let service: any Service
					    @Instantiated let badge: Badge
					    @Instantiated let note: Note
					}
					""",
				]),
				ModuleFixture(name: "Mid", packageName: "pkg", swiftFileContent: [
					"""
					import Core
					import SafeDI

					@Instantiable(generateMock: true)
					public struct Screen: Instantiable {
					    public init(panel: Panel) {
					        self.panel = panel
					    }

					    @Instantiated let panel: Panel
					}
					""",
				], dependencies: ["Core"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Panel {
		    nonisolated public enum SafeDIMockScope_Service {
		        nonisolated public struct service_Values {
		            internal let memo: Memo?
		            package let serviceBuilder: Thing?
		            package let badge: Badge
		            internal let note: Note
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let service: (service_Values) -> __safeDI_Built

		            public init(service: @escaping (service_Values) -> __safeDI_Built) {
		                self.service = service
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(service: { _ in __safeDI_builder() })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init() {
		            __safeDI_storage = __safeDI_Storage(
		                badge: nil,
		                note: nil
		            )
		        }

		        package init(
		            badge: ((Thing?) -> Badge)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                badge: badge,
		                note: nil
		            )
		        }

		        init(
		            badge: ((Thing?) -> Badge)? = nil,
		            note: ((Memo?) -> Note)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                badge: badge,
		                note: note
		            )
		        }

		        package var badge: ((Thing?) -> Badge)? { __safeDI_storage.badge }
		        var note: ((Memo?) -> Note)? { __safeDI_storage.note }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                badge: ((Thing?) -> Badge)?,
		                note: ((Memo?) -> Note)?
		            ) {
		                self.badge = badge
		                self.note = note
		            }

		            let badge: ((Thing?) -> Badge)?
		            let note: ((Memo?) -> Note)?
		        }
		    }

		    public static func mock(
		        serviceBuilder: @escaping () -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Panel {
		        Panel.__safeDI_mock(serviceBuilder: .init(__safeDI_noScope: serviceBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        serviceBuilder __safeDI_serviceBuilder: Panel.SafeDIMockScope_Service.__safeDI_Builder<any Service>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Panel {
		        Panel.__safeDI_mock(serviceBuilder_: __safeDI_serviceBuilder, serviceBuilder: nil, safeDIOverrides: safeDIOverrides)
		    }

		    package static func mock(
		        serviceBuilder_: @escaping () -> any Service,
		        serviceBuilder: Thing? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Panel {
		        Panel.__safeDI_mock(serviceBuilder_: .init(__safeDI_noScope: serviceBuilder_), serviceBuilder: serviceBuilder, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    package static func __safeDI_mock(
		        serviceBuilder_ __safeDI_serviceBuilder: Panel.SafeDIMockScope_Service.__safeDI_Builder<any Service>,
		        serviceBuilder: Thing? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Panel {
		        Panel.__safeDI_mock(serviceBuilder_: __safeDI_serviceBuilder, memo: nil, serviceBuilder: serviceBuilder, safeDIOverrides: safeDIOverrides)
		    }

		    static func mock(
		        serviceBuilder_: @escaping () -> any Service,
		        memo: Memo? = nil,
		        serviceBuilder: Thing? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Panel {
		        Panel.__safeDI_mock(serviceBuilder_: .init(__safeDI_noScope: serviceBuilder_), memo: memo, serviceBuilder: serviceBuilder, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    static func __safeDI_mock(
		        serviceBuilder_ __safeDI_serviceBuilder: Panel.SafeDIMockScope_Service.__safeDI_Builder<any Service>,
		        memo: Memo? = nil,
		        serviceBuilder: Thing? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Panel {
		        let badge = if let safeDIBuilder = safeDIOverrides.badge { safeDIBuilder(serviceBuilder) } else { Badge(serviceBuilder: serviceBuilder) }
		        let note = if let safeDIBuilder = safeDIOverrides.note { safeDIBuilder(memo) } else { Note(memo: memo) }
		        let service: any Service = __safeDI_serviceBuilder.service(SafeDIMockScope_Service.service_Values(memo: memo, serviceBuilder: serviceBuilder, badge: badge, note: note))
		        return Panel(service: service, badge: badge, note: note)
		    }
		}

		extension Panel {
		    public enum __safeDI_Panel_mock_615ECD1543E5AA59 {}
		}
		#endif
		"""])
		#expect(output.modules["Mid"]?.generatedFiles == ["Mid.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            panel: Panel.SafeDIOverrides = .init(),
		            serviceBuilder_Thing: Thing? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                panel: panel
		            )
		            self.serviceBuilder_Thing = serviceBuilder_Thing
		        }

		        var panel: Panel.SafeDIOverrides { __safeDI_storage.panel }
		        let serviceBuilder_Thing: Thing?

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                panel: Panel.SafeDIOverrides
		            ) {
		                self.panel = panel
		            }

		            let panel: Panel.SafeDIOverrides
		        }
		    }

		    static func mock(
		        serviceBuilder: @escaping () -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let __safeDI_serviceBuilder = serviceBuilder
		        let serviceBuilder_Thing: Thing? = safeDIOverrides.serviceBuilder_Thing
		        _ = Panel.__safeDI_Panel_mock_615ECD1543E5AA59.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        func __safeDI_panel() -> Panel {
		            let serviceBuilder_: () -> any Service = __safeDI_serviceBuilder
		            let serviceBuilder: Thing? = serviceBuilder_Thing
		            return Panel.__safeDI_mock(serviceBuilder_: .init(__safeDI_noScope: serviceBuilder_), serviceBuilder: serviceBuilder, safeDIOverrides: safeDIOverrides.panel)
		        }
		        let panel: Panel = __safeDI_panel()
		        return Screen(panel: panel)
		    }
		}
		#endif
		"""])
	}

	// MARK: Tests – isolation

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_compilesInModulesDefaultingToMainActor_whenInternalCallerFillsPlaceThreeLevelsBeneathPublicMock() async throws {
		let modules = Self.pageModules(app: [Self.live, Self.root(holding: "page: Page")]).map(Self.defaultingToMainActor)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif


		"""])
		#expect(output.modules["Feed"]?.generatedFiles == ["Feed.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Page {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct detailBuilder_Values {
		            public let navigator: Navigator
		            public let logger: Logger
		        }

		        nonisolated public enum Detail_Scope {
		            nonisolated public struct leafBuilder_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let leafBuilder: (leafBuilder_Values) -> SafeDIMockScope_Api.Leaf_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(leafBuilder: @escaping (leafBuilder_Values) -> SafeDIMockScope_Api.Leaf_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.leafBuilder = leafBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(leafBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		                }
		            }
		        }

		        nonisolated public enum Leaf_Scope {
		            nonisolated public struct api_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let api: (api_Values) -> __safeDI_Built

		                public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                    self.api = api
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(api: { _ in __safeDI_builder() })
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let detailBuilder: (detailBuilder_Values) -> SafeDIMockScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(detailBuilder: @escaping (detailBuilder_Values) -> SafeDIMockScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.detailBuilder = detailBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(detailBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            navigator: (() -> Navigator)? = nil,
		            logger: (() -> Logger)? = nil,
		            detailBuilder: __safeDI_Feed_Detail_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                navigator: navigator,
		                logger: logger,
		                detailBuilder: detailBuilder
		            )
		        }

		        public var navigator: (() -> Navigator)? { __safeDI_storage.navigator }
		        public var logger: (() -> Logger)? { __safeDI_storage.logger }
		        public var detailBuilder: __safeDI_Feed_Detail_MockConfiguration { __safeDI_storage.detailBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                navigator: (() -> Navigator)?,
		                logger: (() -> Logger)?,
		                detailBuilder: __safeDI_Feed_Detail_MockConfiguration
		            ) {
		                self.navigator = navigator
		                self.logger = logger
		                self.detailBuilder = detailBuilder
		            }

		            let navigator: (() -> Navigator)?
		            let logger: (() -> Logger)?
		            let detailBuilder: __safeDI_Feed_Detail_MockConfiguration
		        }
		    }

		    // SafeDI counts `Api` as `public`: no module it reads declares it narrower. If `Api` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    public static func mock(
		        apiBuilder: @escaping () -> any Api,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Page {
		        Page.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        apiBuilder __safeDI_apiBuilder: Page.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Page {
		        let navigator = if let safeDIBuilder = safeDIOverrides.navigator { safeDIBuilder() } else { Navigator() }
		        let logger = if let safeDIBuilder = safeDIOverrides.logger { safeDIBuilder() } else { Logger() }
		        let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder.detailBuilder(SafeDIMockScope_Api.detailBuilder_Values(navigator: navigator, logger: logger))
		        func __safeDI_detailBuilder() -> Detail {
		            let __safeDI_apiBuilder_leafBuilder = __safeDI_apiBuilder_detailBuilder.leafBuilder(SafeDIMockScope_Api.Detail_Scope.leafBuilder_Values())
		            func __safeDI_leafBuilder() -> Leaf {
		                let api: any Api = __safeDI_apiBuilder_leafBuilder.api(SafeDIMockScope_Api.Leaf_Scope.api_Values())
		                return if let safeDIBuilder = safeDIOverrides.detailBuilder.leafBuilder { safeDIBuilder(api) } else { Leaf(api: api) }
		            }
		            let leafBuilder = Instantiator<Leaf>(__safeDI_leafBuilder)
		            return Detail.__safeDI_init(leafBuilder: leafBuilder, safeDIBuilder: safeDIOverrides.detailBuilder.safeDIBuilder)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        return Page(navigator: navigator, logger: logger, detailBuilder: detailBuilder)
		    }
		}

		extension Page {
		    public enum __safeDI_Page_mock_50657E78D19F8704 {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `Detail` is constructed within the public mock trees of module `Feed`.
		nonisolated public struct __safeDI_Feed_Detail_MockConfiguration {
		    public init(
		        leafBuilder: ((any Api) -> Leaf)? = nil,
		        _ safeDIBuilder: ((Instantiator<Leaf>) -> Detail)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            leafBuilder: leafBuilder,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var leafBuilder: ((any Api) -> Leaf)? { __safeDI_storage.leafBuilder }
		    /// Overrides how `Detail` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((Instantiator<Leaf>) -> Detail)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            leafBuilder: ((any Api) -> Leaf)?,
		            safeDIBuilder: ((Instantiator<Leaf>) -> Detail)?
		        ) {
		            self.leafBuilder = leafBuilder
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let leafBuilder: ((any Api) -> Leaf)?
		        let safeDIBuilder: ((Instantiator<Leaf>) -> Detail)?
		    }
		}

		extension Detail {
		    static func __safeDI_init(leafBuilder: Instantiator<Leaf>, safeDIBuilder: ((Instantiator<Leaf>) -> Detail)?) -> Detail {
		        if let safeDIBuilder { safeDIBuilder(leafBuilder) } else { Detail(leafBuilder: leafBuilder) }
		    }
		}
		#endif

		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feed)
		import Feed
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            page: Page.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                page: page
		            )
		        }

		        var page: Page.SafeDIOverrides { __safeDI_storage.page }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                page: Page.SafeDIOverrides
		            ) {
		                self.page = page
		            }

		            let page: Page.SafeDIOverrides
		        }
		    }

		    static func mock(
		        apiBuilder: (() -> any Api)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_page() -> Page {
		            func __safeDI_apiBuilder_Page() -> Page.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(detailBuilder: { _ in __safeDI_apiBuilder_Page_Detail_Scope() })
		            }
		            func __safeDI_apiBuilder_Page_Detail_Scope() -> Page.SafeDIMockScope_Api.Detail_Scope.__safeDI_Builder<any Api> {
		                .init(leafBuilder: { _ in __safeDI_apiBuilder_Page_Leaf_Scope() })
		            }
		            func __safeDI_apiBuilder_Page_Leaf_Scope() -> Page.SafeDIMockScope_Api.Leaf_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = Live()
		                    return api
		                })
		            }
		            _ = Page.__safeDI_Page_mock_50657E78D19F8704.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Page.__safeDI_mock(apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_Page(), safeDIOverrides: safeDIOverrides.page)
		        }
		        let page: Page = __safeDI_page()
		        return Root(page: page)
		    }
		}
		#endif
		"""])
		try await expectCompiles(output, inlineControl: Self.inline(modules))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_compilesInModulesDefaultingToMainActor_whenPublicCallerFillsEveryPlaceOfCalledMock() async throws {
		let modules = Self.chainModules(mid: [Self.live], app: [Self.root(holding: "shell: Shell")]).map(Self.defaultingToMainActor)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feed)
		import Feed
		#endif
		#if canImport(Mid)
		import Mid
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            shell: Shell.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                shell: shell
		            )
		        }

		        var shell: Shell.SafeDIOverrides { __safeDI_storage.shell }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                shell: Shell.SafeDIOverrides
		            ) {
		                self.shell = shell
		            }

		            let shell: Shell.SafeDIOverrides
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        _ = Shell.__safeDI_Shell_mock_BEDDA3C65C73F485.self // If this line does not compile, compile the code SafeDI generates for module Mid into Mid: under Bazel, add Mid’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let shell = Shell.__safeDI_mock(safeDIOverrides: safeDIOverrides.shell)
		        return Root(shell: shell)
		    }
		}
		#endif
		"""])
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif


		"""])
		#expect(output.modules["Feed"]?.generatedFiles == ["Feed.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Hub {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct pageBuilder_Values {
		            public let navigator: Navigator
		        }

		        nonisolated public struct modelBuilder_Values {
		            public let navigator: Navigator
		            public let pageBuilder: Instantiator<Page>
		        }

		        nonisolated public enum Page_Scope {
		            nonisolated public struct modelBuilder_Values {
		                public let token: Token
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let modelBuilder: (modelBuilder_Values) -> SafeDIMockScope_Api.Model_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(modelBuilder: @escaping (modelBuilder_Values) -> SafeDIMockScope_Api.Model_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.modelBuilder = modelBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(modelBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		                }
		            }
		        }

		        nonisolated public enum Model_Scope {
		            nonisolated public struct api_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let api: (api_Values) -> __safeDI_Built

		                public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                    self.api = api
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(api: { _ in __safeDI_builder() })
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let pageBuilder: (pageBuilder_Values) -> SafeDIMockScope_Api.Page_Scope.__safeDI_Builder<__safeDI_Built>
		            public let modelBuilder: (modelBuilder_Values) -> SafeDIMockScope_Api.Model_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(pageBuilder: @escaping (pageBuilder_Values) -> SafeDIMockScope_Api.Page_Scope.__safeDI_Builder<__safeDI_Built>, modelBuilder: @escaping (modelBuilder_Values) -> SafeDIMockScope_Api.Model_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.pageBuilder = pageBuilder
		                self.modelBuilder = modelBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(pageBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) }, modelBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            navigator: (() -> Navigator)? = nil,
		            pageBuilder: __safeDI_Feed_Page_MockConfiguration = .init(),
		            modelBuilder: ((any Api) -> Model)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                navigator: navigator,
		                pageBuilder: pageBuilder,
		                modelBuilder: modelBuilder
		            )
		        }

		        public var navigator: (() -> Navigator)? { __safeDI_storage.navigator }
		        public var pageBuilder: __safeDI_Feed_Page_MockConfiguration { __safeDI_storage.pageBuilder }
		        public var modelBuilder: ((any Api) -> Model)? { __safeDI_storage.modelBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                navigator: (() -> Navigator)?,
		                pageBuilder: __safeDI_Feed_Page_MockConfiguration,
		                modelBuilder: ((any Api) -> Model)?
		            ) {
		                self.navigator = navigator
		                self.pageBuilder = pageBuilder
		                self.modelBuilder = modelBuilder
		            }

		            let navigator: (() -> Navigator)?
		            let pageBuilder: __safeDI_Feed_Page_MockConfiguration
		            let modelBuilder: ((any Api) -> Model)?
		        }
		    }

		    // SafeDI counts `Api` as `public`: no module it reads declares it narrower. If `Api` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    public static func mock(
		        apiBuilder: @escaping () -> any Api,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Hub {
		        Hub.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        apiBuilder __safeDI_apiBuilder: Hub.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Hub {
		        let navigator = if let safeDIBuilder = safeDIOverrides.navigator { safeDIBuilder() } else { Navigator() }
		        let __safeDI_apiBuilder_pageBuilder = __safeDI_apiBuilder.pageBuilder(SafeDIMockScope_Api.pageBuilder_Values(navigator: navigator))
		        func __safeDI_pageBuilder() -> Page {
		            let token = if let safeDIBuilder = safeDIOverrides.pageBuilder.token { safeDIBuilder() } else { Token() }
		            let __safeDI_apiBuilder_modelBuilder = __safeDI_apiBuilder_pageBuilder.modelBuilder(SafeDIMockScope_Api.Page_Scope.modelBuilder_Values(token: token))
		            func __safeDI_modelBuilder() -> Model {
		                let api: any Api = __safeDI_apiBuilder_modelBuilder.api(SafeDIMockScope_Api.Model_Scope.api_Values())
		                return if let safeDIBuilder = safeDIOverrides.pageBuilder.modelBuilder { safeDIBuilder(api) } else { Model(api: api) }
		            }
		            let modelBuilder = Instantiator<Model>(__safeDI_modelBuilder)
		            return Page.__safeDI_init(token: token, modelBuilder: modelBuilder, safeDIBuilder: safeDIOverrides.pageBuilder.safeDIBuilder)
		        }
		        let pageBuilder = Instantiator<Page>(__safeDI_pageBuilder)
		        let __safeDI_apiBuilder_modelBuilder = __safeDI_apiBuilder.modelBuilder(SafeDIMockScope_Api.modelBuilder_Values(navigator: navigator, pageBuilder: pageBuilder))
		        func __safeDI_modelBuilder() -> Model {
		            let api: any Api = __safeDI_apiBuilder_modelBuilder.api(SafeDIMockScope_Api.Model_Scope.api_Values())
		            return if let safeDIBuilder = safeDIOverrides.modelBuilder { safeDIBuilder(api) } else { Model(api: api) }
		        }
		        let modelBuilder = Instantiator<Model>(__safeDI_modelBuilder)
		        return Hub(navigator: navigator, pageBuilder: pageBuilder, modelBuilder: modelBuilder)
		    }
		}

		extension Hub {
		    public enum __safeDI_Hub_mock_9D3DEE011EBEDDFF {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `Page` is constructed within the public mock trees of module `Feed`.
		nonisolated public struct __safeDI_Feed_Page_MockConfiguration {
		    public init(
		        token: (() -> Token)? = nil,
		        modelBuilder: ((any Api) -> Model)? = nil,
		        _ safeDIBuilder: ((Token, Instantiator<Model>) -> Page)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            token: token,
		            modelBuilder: modelBuilder,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var token: (() -> Token)? { __safeDI_storage.token }
		    public var modelBuilder: ((any Api) -> Model)? { __safeDI_storage.modelBuilder }
		    /// Overrides how `Page` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((Token, Instantiator<Model>) -> Page)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            token: (() -> Token)?,
		            modelBuilder: ((any Api) -> Model)?,
		            safeDIBuilder: ((Token, Instantiator<Model>) -> Page)?
		        ) {
		            self.token = token
		            self.modelBuilder = modelBuilder
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let token: (() -> Token)?
		        let modelBuilder: ((any Api) -> Model)?
		        let safeDIBuilder: ((Token, Instantiator<Model>) -> Page)?
		    }
		}

		extension Page {
		    static func __safeDI_init(token: Token, modelBuilder: Instantiator<Model>, safeDIBuilder: ((Token, Instantiator<Model>) -> Page)?) -> Page {
		        if let safeDIBuilder { safeDIBuilder(token, modelBuilder) } else { Page(token: token, modelBuilder: modelBuilder) }
		    }
		}
		#endif

		"""])
		#expect(output.modules["Mid"]?.generatedFiles == ["Mid.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feed)
		import Feed
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Shell {
		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            logger: (() -> Logger)? = nil,
		            hub: Hub.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                logger: logger,
		                hub: hub
		            )
		        }

		        public var logger: (() -> Logger)? { __safeDI_storage.logger }
		        public var hub: Hub.SafeDIOverrides { __safeDI_storage.hub }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                logger: (() -> Logger)?,
		                hub: Hub.SafeDIOverrides
		            ) {
		                self.logger = logger
		                self.hub = hub
		            }

		            let logger: (() -> Logger)?
		            let hub: Hub.SafeDIOverrides
		        }
		    }

		    // SafeDI counts `Api` as `public`: no module it reads declares it narrower. If `Api` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    public static func mock(
		        apiBuilder: (() -> any Api)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Shell {
		        Shell.__safeDI_mock(apiBuilder: apiBuilder, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        apiBuilder __safeDI_apiBuilder: (() -> any Api)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Shell {
		        let logger = if let safeDIBuilder = safeDIOverrides.logger { safeDIBuilder() } else { Logger() }
		        func __safeDI_hub() -> Hub {
		            func __safeDI_apiBuilder_Hub() -> Hub.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(pageBuilder: { _ in __safeDI_apiBuilder_Hub_Page_Scope() }, modelBuilder: { _ in __safeDI_apiBuilder_Hub_Model_Scope() })
		            }
		            func __safeDI_apiBuilder_Hub_Page_Scope() -> Hub.SafeDIMockScope_Api.Page_Scope.__safeDI_Builder<any Api> {
		                .init(modelBuilder: { _ in __safeDI_apiBuilder_Hub_Model_Scope() })
		            }
		            func __safeDI_apiBuilder_Hub_Model_Scope() -> Hub.SafeDIMockScope_Api.Model_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = Live()
		                    return api
		                })
		            }
		            _ = Hub.__safeDI_Hub_mock_9D3DEE011EBEDDFF.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Hub.__safeDI_mock(apiBuilder: __safeDI_apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_Hub(), safeDIOverrides: safeDIOverrides.hub)
		        }
		        let hub: Hub = __safeDI_hub()
		        return Shell(logger: logger, hub: hub)
		    }
		}

		extension Shell {
		    public enum __safeDI_Shell_mock_BEDDA3C65C73F485 {}
		}
		#endif
		"""])
		try await expectCompiles(output, inlineControl: Self.inline(modules))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresPlainLevelFunctionsInsideSendableFunction_whenCallerFillsEveryPlaceOfMockItBuildsInSendableInstantiator() async throws {
		// `Root` builds `Panel` in a `SendableInstantiator`, so the call is inside a `@Sendable` function; `Panel`'s builder
		// is plain, so the level functions are plain `func`s, and `DefaultService`'s fill, which builds a `Tracker`, is a
		// function of its own.
		let modules = Self.sendableHolderModules(compilerSettings: VerificationCompilerSettings())
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Panel {
		    nonisolated public enum SafeDIMockScope_Service {
		        nonisolated public struct service_Values {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let service: (service_Values) -> __safeDI_Built

		            public init(service: @escaping (service_Values) -> __safeDI_Built) {
		                self.service = service
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(service: { _ in __safeDI_builder() })
		            }
		        }
		    }

		    public static func mock(
		        serviceBuilder: @escaping () -> any Service
		    ) -> Panel {
		        Panel.__safeDI_mock(serviceBuilder: .init(__safeDI_noScope: serviceBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        serviceBuilder __safeDI_serviceBuilder: Panel.SafeDIMockScope_Service.__safeDI_Builder<any Service>
		    ) -> Panel {
		        let service: any Service = __safeDI_serviceBuilder.service(SafeDIMockScope_Service.service_Values())
		        return Panel(service: service)
		    }
		}

		extension Panel {
		    public enum __safeDI_Panel_mock_4C19E5205B40458C {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
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
		            heldBuilder: (@Sendable (@escaping () -> any Service) -> Panel)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                heldBuilder: heldBuilder
		            )
		        }

		        var heldBuilder: (@Sendable (@escaping () -> any Service) -> Panel)? { __safeDI_storage.heldBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage: Sendable {
		            init(
		                heldBuilder: (@Sendable (@escaping () -> any Service) -> Panel)?
		            ) {
		                self.heldBuilder = heldBuilder
		            }

		            let heldBuilder: (@Sendable (@escaping () -> any Service) -> Panel)?
		        }
		    }

		    static func mock(
		        serviceSendableBuilder: (@Sendable () -> any Service)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let __safeDI_heldBuilder__safeDIBuilder = safeDIOverrides.heldBuilder
		        @Sendable nonisolated func __safeDI_heldBuilder() -> Panel {
		            func __safeDI_serviceBuilder_Panel_service() -> any Service {
		                func __safeDI_service() -> DefaultService {
		                    let tracker = Tracker()
		                    return DefaultService(tracker: tracker)
		                }
		                let service: any Service = __safeDI_service()
		                return service
		            }
		            func __safeDI_serviceBuilder_Panel() -> Panel.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
		                .init(service: { _ in __safeDI_serviceBuilder_Panel_service() })
		            }
		            _ = Panel.__safeDI_Panel_mock_4C19E5205B40458C.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return if let safeDIBuilder = __safeDI_heldBuilder__safeDIBuilder { safeDIBuilder({ if let serviceSendableBuilder { serviceSendableBuilder() } else { __safeDI_serviceBuilder_Panel_service() } }) } else { Panel.__safeDI_mock(serviceBuilder: serviceSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Panel()) }
		        }
		        let heldBuilder = SendableInstantiator<Panel>(__safeDI_heldBuilder)
		        return Root(heldBuilder: heldBuilder)
		    }
		}
		#endif
		"""])
		try await expectCompiles(output, inlineControl: Self.inline(modules))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_compilesInModulesDefaultingToMainActor_whenCallerFillsEveryPlaceOfMockItBuildsInSendableInstantiator() async throws {
		let modules = Self.sendableHolderModules(compilerSettings: VerificationCompilerSettings()).map(Self.defaultingToMainActor)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Panel {
		    nonisolated public enum SafeDIMockScope_Service {
		        nonisolated public struct service_Values {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let service: (service_Values) -> __safeDI_Built

		            public init(service: @escaping (service_Values) -> __safeDI_Built) {
		                self.service = service
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(service: { _ in __safeDI_builder() })
		            }
		        }
		    }

		    public static func mock(
		        serviceBuilder: @escaping () -> any Service
		    ) -> Panel {
		        Panel.__safeDI_mock(serviceBuilder: .init(__safeDI_noScope: serviceBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        serviceBuilder __safeDI_serviceBuilder: Panel.SafeDIMockScope_Service.__safeDI_Builder<any Service>
		    ) -> Panel {
		        let service: any Service = __safeDI_serviceBuilder.service(SafeDIMockScope_Service.service_Values())
		        return Panel(service: service)
		    }
		}

		extension Panel {
		    public enum __safeDI_Panel_mock_4C19E5205B40458C {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
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
		            heldBuilder: (@Sendable (@escaping () -> any Service) -> Panel)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                heldBuilder: heldBuilder
		            )
		        }

		        var heldBuilder: (@Sendable (@escaping () -> any Service) -> Panel)? { __safeDI_storage.heldBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage: Sendable {
		            init(
		                heldBuilder: (@Sendable (@escaping () -> any Service) -> Panel)?
		            ) {
		                self.heldBuilder = heldBuilder
		            }

		            let heldBuilder: (@Sendable (@escaping () -> any Service) -> Panel)?
		        }
		    }

		    static func mock(
		        serviceSendableBuilder: (@Sendable () -> any Service)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let __safeDI_heldBuilder__safeDIBuilder = safeDIOverrides.heldBuilder
		        @Sendable nonisolated func __safeDI_heldBuilder() -> Panel {
		            func __safeDI_serviceBuilder_Panel_service() -> any Service {
		                func __safeDI_service() -> DefaultService {
		                    let tracker = Tracker()
		                    return DefaultService(tracker: tracker)
		                }
		                let service: any Service = __safeDI_service()
		                return service
		            }
		            func __safeDI_serviceBuilder_Panel() -> Panel.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
		                .init(service: { _ in __safeDI_serviceBuilder_Panel_service() })
		            }
		            _ = Panel.__safeDI_Panel_mock_4C19E5205B40458C.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return if let safeDIBuilder = __safeDI_heldBuilder__safeDIBuilder { safeDIBuilder({ if let serviceSendableBuilder { serviceSendableBuilder() } else { __safeDI_serviceBuilder_Panel_service() } }) } else { Panel.__safeDI_mock(serviceBuilder: serviceSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Panel()) }
		        }
		        let heldBuilder = SendableInstantiator<Panel>(__safeDI_heldBuilder)
		        return Root(heldBuilder: heldBuilder)
		    }
		}
		#endif
		"""])
		try await expectCompiles(output, inlineControl: Self.inline(modules))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_leavesThePlaceToThePublicCaller_whenCallersModuleAlsoSeesATypeThatFulfillsIt() async throws {
		// `Shell`, a public mock in `Mid`, fills `Hub`'s place with `LiveToken`, which `Mid` sees; `App` sees `AppApi` too, but
		// `Shell` fills the place, as its production twin does, so `Root` hands it no fill. Everything the probe built is
		// freed.
		let modules = Self.chainModules(mid: [Self.internalLiveToken], app: [
			"""
			@Instantiable(fulfillingAdditionalTypes: [Api.self])
			public final class AppApi: Api, Instantiable {
			    public init(navigator: Navigator) {
			        self.navigator = navigator
			    }

			    @Received public let navigator: Navigator
			}
			""",
			Self.root(holding: "shell: Shell"),
			"""
			func countsOfShellRootBuilds() -> String {
			    do {
			        let hub = Root.mock().shell.hub
			        let page = hub.pageBuilder.instantiate()
			        hub.navigator.stack.append(page)
			        hub.navigator.stack.append(hub.modelBuilder.instantiate())
			        hub.navigator.stack.append(page.modelBuilder.instantiate())
			    }
			    return "Navigator \\(Navigator.alive), Token \\(Token.alive), Logger \\(Logger.alive)"
			}
			""",
		])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif


		"""])
		#expect(output.modules["Feed"]?.generatedFiles == ["Feed.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Hub {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct pageBuilder_Values {
		            public let navigator: Navigator
		        }

		        nonisolated public struct modelBuilder_Values {
		            public let navigator: Navigator
		            public let pageBuilder: Instantiator<Page>
		        }

		        nonisolated public enum Page_Scope {
		            nonisolated public struct modelBuilder_Values {
		                public let token: Token
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let modelBuilder: (modelBuilder_Values) -> SafeDIMockScope_Api.Model_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(modelBuilder: @escaping (modelBuilder_Values) -> SafeDIMockScope_Api.Model_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.modelBuilder = modelBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(modelBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		                }
		            }
		        }

		        nonisolated public enum Model_Scope {
		            nonisolated public struct api_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let api: (api_Values) -> __safeDI_Built

		                public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                    self.api = api
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(api: { _ in __safeDI_builder() })
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let pageBuilder: (pageBuilder_Values) -> SafeDIMockScope_Api.Page_Scope.__safeDI_Builder<__safeDI_Built>
		            public let modelBuilder: (modelBuilder_Values) -> SafeDIMockScope_Api.Model_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(pageBuilder: @escaping (pageBuilder_Values) -> SafeDIMockScope_Api.Page_Scope.__safeDI_Builder<__safeDI_Built>, modelBuilder: @escaping (modelBuilder_Values) -> SafeDIMockScope_Api.Model_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.pageBuilder = pageBuilder
		                self.modelBuilder = modelBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(pageBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) }, modelBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            navigator: (() -> Navigator)? = nil,
		            pageBuilder: __safeDI_Feed_Page_MockConfiguration = .init(),
		            modelBuilder: ((any Api) -> Model)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                navigator: navigator,
		                pageBuilder: pageBuilder,
		                modelBuilder: modelBuilder
		            )
		        }

		        public var navigator: (() -> Navigator)? { __safeDI_storage.navigator }
		        public var pageBuilder: __safeDI_Feed_Page_MockConfiguration { __safeDI_storage.pageBuilder }
		        public var modelBuilder: ((any Api) -> Model)? { __safeDI_storage.modelBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                navigator: (() -> Navigator)?,
		                pageBuilder: __safeDI_Feed_Page_MockConfiguration,
		                modelBuilder: ((any Api) -> Model)?
		            ) {
		                self.navigator = navigator
		                self.pageBuilder = pageBuilder
		                self.modelBuilder = modelBuilder
		            }

		            let navigator: (() -> Navigator)?
		            let pageBuilder: __safeDI_Feed_Page_MockConfiguration
		            let modelBuilder: ((any Api) -> Model)?
		        }
		    }

		    // SafeDI counts `Api` as `public`: no module it reads declares it narrower. If `Api` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    public static func mock(
		        apiBuilder: @escaping () -> any Api,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Hub {
		        Hub.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        apiBuilder __safeDI_apiBuilder: Hub.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Hub {
		        let navigator = if let safeDIBuilder = safeDIOverrides.navigator { safeDIBuilder() } else { Navigator() }
		        let __safeDI_apiBuilder_pageBuilder = __safeDI_apiBuilder.pageBuilder(SafeDIMockScope_Api.pageBuilder_Values(navigator: navigator))
		        func __safeDI_pageBuilder() -> Page {
		            let token = if let safeDIBuilder = safeDIOverrides.pageBuilder.token { safeDIBuilder() } else { Token() }
		            let __safeDI_apiBuilder_modelBuilder = __safeDI_apiBuilder_pageBuilder.modelBuilder(SafeDIMockScope_Api.Page_Scope.modelBuilder_Values(token: token))
		            func __safeDI_modelBuilder() -> Model {
		                let api: any Api = __safeDI_apiBuilder_modelBuilder.api(SafeDIMockScope_Api.Model_Scope.api_Values())
		                return if let safeDIBuilder = safeDIOverrides.pageBuilder.modelBuilder { safeDIBuilder(api) } else { Model(api: api) }
		            }
		            let modelBuilder = Instantiator<Model>(__safeDI_modelBuilder)
		            return Page.__safeDI_init(token: token, modelBuilder: modelBuilder, safeDIBuilder: safeDIOverrides.pageBuilder.safeDIBuilder)
		        }
		        let pageBuilder = Instantiator<Page>(__safeDI_pageBuilder)
		        let __safeDI_apiBuilder_modelBuilder = __safeDI_apiBuilder.modelBuilder(SafeDIMockScope_Api.modelBuilder_Values(navigator: navigator, pageBuilder: pageBuilder))
		        func __safeDI_modelBuilder() -> Model {
		            let api: any Api = __safeDI_apiBuilder_modelBuilder.api(SafeDIMockScope_Api.Model_Scope.api_Values())
		            return if let safeDIBuilder = safeDIOverrides.modelBuilder { safeDIBuilder(api) } else { Model(api: api) }
		        }
		        let modelBuilder = Instantiator<Model>(__safeDI_modelBuilder)
		        return Hub(navigator: navigator, pageBuilder: pageBuilder, modelBuilder: modelBuilder)
		    }
		}

		extension Hub {
		    public enum __safeDI_Hub_mock_9D3DEE011EBEDDFF {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `Page` is constructed within the public mock trees of module `Feed`.
		nonisolated public struct __safeDI_Feed_Page_MockConfiguration {
		    public init(
		        token: (() -> Token)? = nil,
		        modelBuilder: ((any Api) -> Model)? = nil,
		        _ safeDIBuilder: ((Token, Instantiator<Model>) -> Page)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            token: token,
		            modelBuilder: modelBuilder,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var token: (() -> Token)? { __safeDI_storage.token }
		    public var modelBuilder: ((any Api) -> Model)? { __safeDI_storage.modelBuilder }
		    /// Overrides how `Page` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((Token, Instantiator<Model>) -> Page)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            token: (() -> Token)?,
		            modelBuilder: ((any Api) -> Model)?,
		            safeDIBuilder: ((Token, Instantiator<Model>) -> Page)?
		        ) {
		            self.token = token
		            self.modelBuilder = modelBuilder
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let token: (() -> Token)?
		        let modelBuilder: ((any Api) -> Model)?
		        let safeDIBuilder: ((Token, Instantiator<Model>) -> Page)?
		    }
		}

		extension Page {
		    static func __safeDI_init(token: Token, modelBuilder: Instantiator<Model>, safeDIBuilder: ((Token, Instantiator<Model>) -> Page)?) -> Page {
		        if let safeDIBuilder { safeDIBuilder(token, modelBuilder) } else { Page(token: token, modelBuilder: modelBuilder) }
		    }
		}
		#endif

		"""])
		#expect(output.modules["Mid"]?.generatedFiles == ["Mid.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feed)
		import Feed
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Shell {
		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            logger: (() -> Logger)? = nil,
		            token: (() -> Token)? = nil,
		            hub: Hub.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                logger: logger,
		                token: token,
		                hub: hub
		            )
		        }

		        public var logger: (() -> Logger)? { __safeDI_storage.logger }
		        public var token: (() -> Token)? { __safeDI_storage.token }
		        public var hub: Hub.SafeDIOverrides { __safeDI_storage.hub }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                logger: (() -> Logger)?,
		                token: (() -> Token)?,
		                hub: Hub.SafeDIOverrides
		            ) {
		                self.logger = logger
		                self.token = token
		                self.hub = hub
		            }

		            let logger: (() -> Logger)?
		            let token: (() -> Token)?
		            let hub: Hub.SafeDIOverrides
		        }
		    }

		    // SafeDI counts `Api` as `public`: no module it reads declares it narrower. If `Api` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    public static func mock(
		        apiBuilder: (() -> any Api)? = nil,
		        token: Token? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Shell {
		        Shell.__safeDI_mock(apiBuilder: apiBuilder, token: token, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        apiBuilder __safeDI_apiBuilder: (() -> any Api)? = nil,
		        token: Token? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Shell {
		        let logger = if let safeDIBuilder = safeDIOverrides.logger { safeDIBuilder() } else { Logger() }
		        let token = if let token { token } else if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder() } else { Token() }
		        func __safeDI_hub() -> Hub {
		            func __safeDI_apiBuilder_Hub(token: Token) -> Hub.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(pageBuilder: { _ in __safeDI_apiBuilder_Hub_Page_Scope() }, modelBuilder: { _ in __safeDI_apiBuilder_Hub_Model_Scope(token: token) })
		            }
		            func __safeDI_apiBuilder_Hub_Page_Scope() -> Hub.SafeDIMockScope_Api.Page_Scope.__safeDI_Builder<any Api> {
		                .init(modelBuilder: { values in __safeDI_apiBuilder_Hub_Model_Scope(token: values.token) })
		            }
		            func __safeDI_apiBuilder_Hub_Model_Scope(token: Token) -> Hub.SafeDIMockScope_Api.Model_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveToken(token: token)
		                    return api
		                })
		            }
		            _ = Hub.__safeDI_Hub_mock_9D3DEE011EBEDDFF.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Hub.__safeDI_mock(apiBuilder: __safeDI_apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_Hub(token: token), safeDIOverrides: safeDIOverrides.hub)
		        }
		        let hub: Hub = __safeDI_hub()
		        return Shell(logger: logger, hub: hub)
		    }
		}

		extension Shell {
		    public enum __safeDI_Shell_mock_AEA38F513AD02F1C {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feed)
		import Feed
		#endif
		#if canImport(Mid)
		import Mid
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            token: (() -> Token)? = nil,
		            shell: Shell.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                token: token,
		                shell: shell
		            )
		        }

		        var token: (() -> Token)? { __safeDI_storage.token }
		        var shell: Shell.SafeDIOverrides { __safeDI_storage.shell }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                token: (() -> Token)?,
		                shell: Shell.SafeDIOverrides
		            ) {
		                self.token = token
		                self.shell = shell
		            }

		            let token: (() -> Token)?
		            let shell: Shell.SafeDIOverrides
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let token = if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder() } else { Token() }
		        _ = Shell.__safeDI_Shell_mock_AEA38F513AD02F1C.self // If this line does not compile, compile the code SafeDI generates for module Mid into Mid: under Bazel, add Mid’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let shell = Shell.__safeDI_mock(token: token, safeDIOverrides: safeDIOverrides.shell)
		        return Root(shell: shell)
		    }
		}
		#endif
		"""])
		let description = try await DifferentialValueOracle.describe(DifferentialValuePath(output: output, modules: modules), probes: [DifferentialValueProbe("countsOfShellRootBuilds()")], filesToDelete: &filesToDelete)
		if compileVerificationIsEnabled {
			#expect(description == "probe countsOfShellRootBuilds()\nString \"Navigator 0, Token 0, Logger 0\"\n")
		}
	}

	// MARK: Tests – a level that reopens

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsNothingOfFirstScreen_whenCallerStaticallyFillsPlaceBeneathLevelThatReopens() async throws {
		// `Step` builds `Screen` again, which `Home`'s mock builds by re-entering the first screen's step function, which takes
		// no struct of its own. A step of the second screen keeps nothing of the first, because the members of the struct the
		// static caller hands read no values.
		let modules = Self.screenLoopModules(app: [Self.live, Self.root(holding: "home: Home"), Self.cachesWhileSecondStepLives(home: "Root.mock().home")])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif


		"""])
		#expect(output.modules["Feat"]?.generatedFiles == ["Feat.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Home {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct screen_Values {}

		        nonisolated public enum Screen_Scope {
		            nonisolated public struct stepBuilder_Values {
		                public let cache: Cache
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let stepBuilder: (stepBuilder_Values) -> SafeDIMockScope_Api.Step_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(stepBuilder: @escaping (stepBuilder_Values) -> SafeDIMockScope_Api.Step_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.stepBuilder = stepBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(stepBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		                }
		            }
		        }

		        nonisolated public enum Step_Scope {
		            nonisolated public struct api_Values {
		                public let screenBuilder: Instantiator<Screen>
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let api: (api_Values) -> __safeDI_Built

		                public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                    self.api = api
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(api: { _ in __safeDI_builder() })
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let screen: (screen_Values) -> SafeDIMockScope_Api.Screen_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(screen: @escaping (screen_Values) -> SafeDIMockScope_Api.Screen_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.screen = screen
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(screen: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            screen: __safeDI_Feat_Screen_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                screen: screen
		            )
		        }

		        public var screen: __safeDI_Feat_Screen_MockConfiguration { __safeDI_storage.screen }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                screen: __safeDI_Feat_Screen_MockConfiguration
		            ) {
		                self.screen = screen
		            }

		            let screen: __safeDI_Feat_Screen_MockConfiguration
		        }
		    }

		    // SafeDI counts `Api` as `public`: no module it reads declares it narrower. If `Api` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    public static func mock(
		        apiBuilder: @escaping () -> any Api,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Home {
		        Home.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        apiBuilder __safeDI_apiBuilder: Home.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Home {
		        let __safeDI_apiBuilder_screen = __safeDI_apiBuilder.screen(SafeDIMockScope_Api.screen_Values())
		        func __safeDI_screen() -> Screen {
		            let cache = if let safeDIBuilder = safeDIOverrides.screen.cache { safeDIBuilder() } else { Cache() }
		            let __safeDI_apiBuilder_stepBuilder = __safeDI_apiBuilder_screen.stepBuilder(SafeDIMockScope_Api.Screen_Scope.stepBuilder_Values(cache: cache))
		            func __safeDI_stepBuilder() -> Step {
		                func __safeDI_screenBuilder() -> Screen {
		                    let cache = if let safeDIBuilder = safeDIOverrides.screen.cache { safeDIBuilder() } else { Cache() }
		                    let stepBuilder = Instantiator<Step>(__safeDI_stepBuilder)
		                    return Screen.__safeDI_init(cache: cache, stepBuilder: stepBuilder, safeDIBuilder: safeDIOverrides.screen.safeDIBuilder)
		                }
		                let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
		                let api: any Api = __safeDI_apiBuilder_stepBuilder.api(SafeDIMockScope_Api.Step_Scope.api_Values(screenBuilder: screenBuilder))
		                return Step.__safeDI_init(api: api, screenBuilder: screenBuilder, safeDIBuilder: safeDIOverrides.screen.stepBuilder.safeDIBuilder)
		            }
		            let stepBuilder = Instantiator<Step>(__safeDI_stepBuilder)
		            return Screen.__safeDI_init(cache: cache, stepBuilder: stepBuilder, safeDIBuilder: safeDIOverrides.screen.safeDIBuilder)
		        }
		        let screen: Screen = __safeDI_screen()
		        return Home(screen: screen)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_mock_4EAD08687C9164E8 {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `Step` is constructed within the public mock trees of module `Feat`.
		nonisolated public struct __safeDI_Feat_Step_MockConfiguration {
		    public init(
		        _ safeDIBuilder: ((any Api, Instantiator<Screen>) -> Step)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    /// Overrides how `Step` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((any Api, Instantiator<Screen>) -> Step)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            safeDIBuilder: ((any Api, Instantiator<Screen>) -> Step)?
		        ) {
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let safeDIBuilder: ((any Api, Instantiator<Screen>) -> Step)?
		    }
		}

		extension Step {
		    static func __safeDI_init(api: any Api, screenBuilder: Instantiator<Screen>, safeDIBuilder: ((any Api, Instantiator<Screen>) -> Step)?) -> Step {
		        if let safeDIBuilder { safeDIBuilder(api, screenBuilder) } else { Step(api: api, screenBuilder: screenBuilder) }
		    }
		}

		/// Configuration for how `Screen` is constructed within the public mock trees of module `Feat`.
		nonisolated public struct __safeDI_Feat_Screen_MockConfiguration {
		    public init(
		        cache: (() -> Cache)? = nil,
		        stepBuilder: __safeDI_Feat_Step_MockConfiguration = .init(),
		        _ safeDIBuilder: ((Cache, Instantiator<Step>) -> Screen)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            cache: cache,
		            stepBuilder: stepBuilder,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var cache: (() -> Cache)? { __safeDI_storage.cache }
		    public var stepBuilder: __safeDI_Feat_Step_MockConfiguration { __safeDI_storage.stepBuilder }
		    /// Overrides how `Screen` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((Cache, Instantiator<Step>) -> Screen)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            cache: (() -> Cache)?,
		            stepBuilder: __safeDI_Feat_Step_MockConfiguration,
		            safeDIBuilder: ((Cache, Instantiator<Step>) -> Screen)?
		        ) {
		            self.cache = cache
		            self.stepBuilder = stepBuilder
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let cache: (() -> Cache)?
		        let stepBuilder: __safeDI_Feat_Step_MockConfiguration
		        let safeDIBuilder: ((Cache, Instantiator<Step>) -> Screen)?
		    }
		}

		extension Screen {
		    static func __safeDI_init(cache: Cache, stepBuilder: Instantiator<Step>, safeDIBuilder: ((Cache, Instantiator<Step>) -> Screen)?) -> Screen {
		        if let safeDIBuilder { safeDIBuilder(cache, stepBuilder) } else { Screen(cache: cache, stepBuilder: stepBuilder) }
		    }
		}
		#endif

		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feat)
		import Feat
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            home: Home.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                home: home
		            )
		        }

		        var home: Home.SafeDIOverrides { __safeDI_storage.home }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                home: Home.SafeDIOverrides
		            ) {
		                self.home = home
		            }

		            let home: Home.SafeDIOverrides
		        }
		    }

		    static func mock(
		        apiBuilder: (() -> any Api)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_home() -> Home {
		            func __safeDI_apiBuilder_Home() -> Home.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(screen: { _ in __safeDI_apiBuilder_Home_Screen_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Screen_Scope() -> Home.SafeDIMockScope_Api.Screen_Scope.__safeDI_Builder<any Api> {
		                .init(stepBuilder: { _ in __safeDI_apiBuilder_Home_Step_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Step_Scope() -> Home.SafeDIMockScope_Api.Step_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = Live()
		                    return api
		                })
		            }
		            _ = Home.__safeDI_Home_mock_4EAD08687C9164E8.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Home.__safeDI_mock(apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_Home(), safeDIOverrides: safeDIOverrides.home)
		        }
		        let home: Home = __safeDI_home()
		        return Root(home: home)
		    }
		}
		#endif
		"""])
		let counts = try await describedCounts(of: modules, output: output, probe: "cachesWhileSecondStepLives()")
		if compileVerificationIsEnabled {
			// The base keeps the first screen's cache alive: 1.
			#expect(counts.knownRight == "probe cachesWhileSecondStepLives()\nString \"Cache 0\"\n")
			#expect(counts.feature == counts.knownRight)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_convertsClosureOverEnumIntoNestedStruct_whenPublicCallerPassesUpPlaceBeneathLevelThatReopens() async throws {
		// `Shell`, a public mock in `Mid`, builds `Home` and passes its place up, so its call of `Home`'s mock converts the
		// closure over the enum into the struct, one member per level of the enum, which holds no case of a level again. The
		// reopened `Screen` is built by re-entering the first screen's step function, so the closure is handed the first
		// screen's values, as before the struct.
		let modules = Self.screenLoopModules(
			mid: [
				"""
				@Instantiable(generateMock: .public)
				public final class Shell: Instantiable {
				    init(home: Home) {
				        self.home = home
				    }

				    @Instantiated public let home: Home
				}
				""",
			],
			app: [Self.root(holding: "shell: Shell")],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif


		"""])
		#expect(output.modules["Feat"]?.generatedFiles == ["Feat.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Home {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct screen_Values {}

		        nonisolated public enum Screen_Scope {
		            nonisolated public struct stepBuilder_Values {
		                public let cache: Cache
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let stepBuilder: (stepBuilder_Values) -> SafeDIMockScope_Api.Step_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(stepBuilder: @escaping (stepBuilder_Values) -> SafeDIMockScope_Api.Step_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.stepBuilder = stepBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(stepBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		                }
		            }
		        }

		        nonisolated public enum Step_Scope {
		            nonisolated public struct api_Values {
		                public let screenBuilder: Instantiator<Screen>
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let api: (api_Values) -> __safeDI_Built

		                public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                    self.api = api
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(api: { _ in __safeDI_builder() })
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let screen: (screen_Values) -> SafeDIMockScope_Api.Screen_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(screen: @escaping (screen_Values) -> SafeDIMockScope_Api.Screen_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.screen = screen
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(screen: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            screen: __safeDI_Feat_Screen_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                screen: screen
		            )
		        }

		        public var screen: __safeDI_Feat_Screen_MockConfiguration { __safeDI_storage.screen }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                screen: __safeDI_Feat_Screen_MockConfiguration
		            ) {
		                self.screen = screen
		            }

		            let screen: __safeDI_Feat_Screen_MockConfiguration
		        }
		    }

		    // SafeDI counts `Api` as `public`: no module it reads declares it narrower. If `Api` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    public static func mock(
		        apiBuilder: @escaping () -> any Api,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Home {
		        Home.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        apiBuilder __safeDI_apiBuilder: Home.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Home {
		        let __safeDI_apiBuilder_screen = __safeDI_apiBuilder.screen(SafeDIMockScope_Api.screen_Values())
		        func __safeDI_screen() -> Screen {
		            let cache = if let safeDIBuilder = safeDIOverrides.screen.cache { safeDIBuilder() } else { Cache() }
		            let __safeDI_apiBuilder_stepBuilder = __safeDI_apiBuilder_screen.stepBuilder(SafeDIMockScope_Api.Screen_Scope.stepBuilder_Values(cache: cache))
		            func __safeDI_stepBuilder() -> Step {
		                func __safeDI_screenBuilder() -> Screen {
		                    let cache = if let safeDIBuilder = safeDIOverrides.screen.cache { safeDIBuilder() } else { Cache() }
		                    let stepBuilder = Instantiator<Step>(__safeDI_stepBuilder)
		                    return Screen.__safeDI_init(cache: cache, stepBuilder: stepBuilder, safeDIBuilder: safeDIOverrides.screen.safeDIBuilder)
		                }
		                let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
		                let api: any Api = __safeDI_apiBuilder_stepBuilder.api(SafeDIMockScope_Api.Step_Scope.api_Values(screenBuilder: screenBuilder))
		                return Step.__safeDI_init(api: api, screenBuilder: screenBuilder, safeDIBuilder: safeDIOverrides.screen.stepBuilder.safeDIBuilder)
		            }
		            let stepBuilder = Instantiator<Step>(__safeDI_stepBuilder)
		            return Screen.__safeDI_init(cache: cache, stepBuilder: stepBuilder, safeDIBuilder: safeDIOverrides.screen.safeDIBuilder)
		        }
		        let screen: Screen = __safeDI_screen()
		        return Home(screen: screen)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_mock_4EAD08687C9164E8 {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `Step` is constructed within the public mock trees of module `Feat`.
		nonisolated public struct __safeDI_Feat_Step_MockConfiguration {
		    public init(
		        _ safeDIBuilder: ((any Api, Instantiator<Screen>) -> Step)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    /// Overrides how `Step` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((any Api, Instantiator<Screen>) -> Step)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            safeDIBuilder: ((any Api, Instantiator<Screen>) -> Step)?
		        ) {
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let safeDIBuilder: ((any Api, Instantiator<Screen>) -> Step)?
		    }
		}

		extension Step {
		    static func __safeDI_init(api: any Api, screenBuilder: Instantiator<Screen>, safeDIBuilder: ((any Api, Instantiator<Screen>) -> Step)?) -> Step {
		        if let safeDIBuilder { safeDIBuilder(api, screenBuilder) } else { Step(api: api, screenBuilder: screenBuilder) }
		    }
		}

		/// Configuration for how `Screen` is constructed within the public mock trees of module `Feat`.
		nonisolated public struct __safeDI_Feat_Screen_MockConfiguration {
		    public init(
		        cache: (() -> Cache)? = nil,
		        stepBuilder: __safeDI_Feat_Step_MockConfiguration = .init(),
		        _ safeDIBuilder: ((Cache, Instantiator<Step>) -> Screen)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            cache: cache,
		            stepBuilder: stepBuilder,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var cache: (() -> Cache)? { __safeDI_storage.cache }
		    public var stepBuilder: __safeDI_Feat_Step_MockConfiguration { __safeDI_storage.stepBuilder }
		    /// Overrides how `Screen` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((Cache, Instantiator<Step>) -> Screen)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            cache: (() -> Cache)?,
		            stepBuilder: __safeDI_Feat_Step_MockConfiguration,
		            safeDIBuilder: ((Cache, Instantiator<Step>) -> Screen)?
		        ) {
		            self.cache = cache
		            self.stepBuilder = stepBuilder
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let cache: (() -> Cache)?
		        let stepBuilder: __safeDI_Feat_Step_MockConfiguration
		        let safeDIBuilder: ((Cache, Instantiator<Step>) -> Screen)?
		    }
		}

		extension Screen {
		    static func __safeDI_init(cache: Cache, stepBuilder: Instantiator<Step>, safeDIBuilder: ((Cache, Instantiator<Step>) -> Screen)?) -> Screen {
		        if let safeDIBuilder { safeDIBuilder(cache, stepBuilder) } else { Screen(cache: cache, stepBuilder: stepBuilder) }
		    }
		}
		#endif

		"""])
		#expect(output.modules["Mid"]?.generatedFiles == ["Mid.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feat)
		import Feat
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Shell {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct home_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let home: (home_Values) -> Home.SafeDIMockScope_Api.__safeDI_Builder<__safeDI_Built>

		            public init(home: @escaping (home_Values) -> Home.SafeDIMockScope_Api.__safeDI_Builder<__safeDI_Built>) {
		                self.home = home
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(home: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            home: Home.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                home: home
		            )
		        }

		        public var home: Home.SafeDIOverrides { __safeDI_storage.home }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                home: Home.SafeDIOverrides
		            ) {
		                self.home = home
		            }

		            let home: Home.SafeDIOverrides
		        }
		    }

		    // SafeDI counts `Api` as `public`: no module it reads declares it narrower. If `Api` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    public static func mock(
		        apiBuilder: @escaping () -> any Api,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Shell {
		        Shell.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        apiBuilder __safeDI_apiBuilder: Shell.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Shell {
		        _ = Home.__safeDI_Home_mock_4EAD08687C9164E8.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let home = Home.__safeDI_mock(apiBuilder: __safeDI_apiBuilder.home(SafeDIMockScope_Api.home_Values()), safeDIOverrides: safeDIOverrides.home)
		        return Shell(home: home)
		    }
		}

		extension Shell {
		    public enum __safeDI_Shell_mock_BCE44FADDA8E6FCF {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feat)
		import Feat
		#endif
		#if canImport(Mid)
		import Mid
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            shell: Shell.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                shell: shell
		            )
		        }

		        var shell: Shell.SafeDIOverrides { __safeDI_storage.shell }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                shell: Shell.SafeDIOverrides
		            ) {
		                self.shell = shell
		            }

		            let shell: Shell.SafeDIOverrides
		        }
		    }

		    static func mock(
		        apiBuilder: @escaping () -> any Api,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let __safeDI_apiBuilder = apiBuilder
		        _ = Shell.__safeDI_Shell_mock_BCE44FADDA8E6FCF.self // If this line does not compile, compile the code SafeDI generates for module Mid into Mid: under Bazel, add Mid’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        func __safeDI_shell() -> Shell {
		            let apiBuilder: () -> any Api = __safeDI_apiBuilder
		            return Shell.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), safeDIOverrides: safeDIOverrides.shell)
		        }
		        let shell: Shell = __safeDI_shell()
		        return Root(shell: shell)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsNoShallowerScreensValues_whenScreenThatOpensItselfIsHeldDeep() async throws {
		// `Screen` opens itself through `next`, beneath `Home`'s `screenBuilder`; `Root` fills `api` with `Live`, which reads
		// nothing. A screen held four or eight levels deep keeps alive what known-right keeps.
		let feat = """
		import Core
		import SafeDI

		@Instantiable
		public final class Cache: Instantiable {
		    public init() { Cache.alive += 1 }
		    deinit { Cache.alive -= 1 }
		    nonisolated(unsafe) public static var alive = 0
		}

		@Instantiable
		public final class Screen: Instantiable {
		    init(cache: Cache, api: any Api, next: Instantiator<Screen>) {
		        self.cache = cache
		        self.api = api
		        self.next = next
		    }

		    @Instantiated public let cache: Cache
		    @Instantiated public let api: any Api
		    @Instantiated public let next: Instantiator<Screen>
		}

		@Instantiable(generateMock: .public)
		public final class Home: Instantiable {
		    init(screenBuilder: Instantiator<Screen>) {
		        self.screenBuilder = screenBuilder
		    }

		    @Instantiated public let screenBuilder: Instantiator<Screen>
		}
		"""
		let app = [
			"""
			@Instantiable(fulfillingAdditionalTypes: [Api.self])
			public final class Live: Api, Instantiable {
			    public init() { Live.alive += 1 }
			    deinit { Live.alive -= 1 }
			    nonisolated(unsafe) public static var alive = 0
			}
			""",
			Self.root(holding: "home: Home"),
			"""
			func countsWhileScreenLives(atDepth depth: Int) -> String {
			    var screen: Screen?
			    do {
			        var current = Root.mock().home.screenBuilder.instantiate()
			        for _ in 1..<depth {
			            current = current.next.instantiate()
			        }
			        screen = current
			    }
			    return withExtendedLifetime(screen) { "Cache \\(Cache.alive), Live \\(Live.alive)" }
			}
			""",
		]
		let modules = [
			ModuleFixture(name: "Core", packageName: "Core", swiftFileContent: [Self.core]),
			ModuleFixture(name: "Feat", packageName: "Feat", swiftFileContent: [feat], dependencies: ["Core"]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContent: app.map { "import Core\nimport Feat\nimport SafeDI\n\n" + $0 }, dependencies: ["Core", "Feat"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feat)
		import Feat
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            home: Home.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                home: home
		            )
		        }

		        var home: Home.SafeDIOverrides { __safeDI_storage.home }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                home: Home.SafeDIOverrides
		            ) {
		                self.home = home
		            }

		            let home: Home.SafeDIOverrides
		        }
		    }

		    static func mock(
		        apiBuilder: (() -> any Api)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_home() -> Home {
		            func __safeDI_apiBuilder_Home() -> Home.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(screenBuilder: { _ in __safeDI_apiBuilder_Home_Screen_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Screen_Scope() -> Home.SafeDIMockScope_Api.Screen_Scope.__safeDI_Builder<any Api> {
		                .init(
		                    api: { _ in
		                        let api: any Api = Live()
		                        return api
		                    },
		                    next: { _ in __safeDI_apiBuilder_Home_Screen_Scope() }
		                )
		            }
		            _ = Home.__safeDI_Home_mock_B3DB58B0D4D7BB6E.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Home.__safeDI_mock(apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_Home(), safeDIOverrides: safeDIOverrides.home)
		        }
		        let home: Home = __safeDI_home()
		        return Root(home: home)
		    }
		}
		#endif
		"""])
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif


		"""])
		#expect(output.modules["Feat"]?.generatedFiles == ["Feat.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Home {
		    // SafeDI counts `Api` as `public`: no module it reads declares it narrower. If `Api` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct screenBuilder_Values {}

		        nonisolated public enum Screen_Scope {
		            nonisolated public struct api_Values {
		                public let cache: Cache
		            }

		            nonisolated public struct next_Values {
		                public let cache: Cache
		                public let api: any Api
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let api: (api_Values) -> __safeDI_Built
		                public let next: (next_Values) -> SafeDIMockScope_Api.Screen_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(api: @escaping (api_Values) -> __safeDI_Built, next: @escaping (next_Values) -> SafeDIMockScope_Api.Screen_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.api = api
		                    self.next = next
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(api: { _ in __safeDI_builder() }, next: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let screenBuilder: (screenBuilder_Values) -> SafeDIMockScope_Api.Screen_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(screenBuilder: @escaping (screenBuilder_Values) -> SafeDIMockScope_Api.Screen_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.screenBuilder = screenBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(screenBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            screenBuilder: __safeDI_Feat_Screen_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                screenBuilder: screenBuilder
		            )
		        }

		        public var screenBuilder: __safeDI_Feat_Screen_MockConfiguration { __safeDI_storage.screenBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                screenBuilder: __safeDI_Feat_Screen_MockConfiguration
		            ) {
		                self.screenBuilder = screenBuilder
		            }

		            let screenBuilder: __safeDI_Feat_Screen_MockConfiguration
		        }
		    }

		    public static func mock(
		        apiBuilder: @escaping () -> any Api,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Home {
		        Home.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        apiBuilder __safeDI_apiBuilder: Home.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Home {
		        let __safeDI_apiBuilder_screenBuilder = __safeDI_apiBuilder.screenBuilder(SafeDIMockScope_Api.screenBuilder_Values())
		        func __safeDI_screenBuilder() -> Screen {
		            let cache = if let safeDIBuilder = safeDIOverrides.screenBuilder.cache { safeDIBuilder() } else { Cache() }
		            let api: any Api = __safeDI_apiBuilder_screenBuilder.api(SafeDIMockScope_Api.Screen_Scope.api_Values(cache: cache))
		            let __safeDI_apiBuilder_next = __safeDI_apiBuilder_screenBuilder.next(SafeDIMockScope_Api.Screen_Scope.next_Values(cache: cache, api: api))
		            func __safeDI_next() -> Screen {
		                let cache = if let safeDIBuilder = safeDIOverrides.screenBuilder.cache { safeDIBuilder() } else { Cache() }
		                let api: any Api = __safeDI_apiBuilder_next.api(SafeDIMockScope_Api.Screen_Scope.api_Values(cache: cache))
		                let next = Instantiator<Screen>(__safeDI_next)
		                return Screen.__safeDI_init(cache: cache, api: api, next: next, safeDIBuilder: safeDIOverrides.screenBuilder.safeDIBuilder)
		            }
		            let next = Instantiator<Screen>(__safeDI_next)
		            return Screen.__safeDI_init(cache: cache, api: api, next: next, safeDIBuilder: safeDIOverrides.screenBuilder.safeDIBuilder)
		        }
		        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
		        return Home(screenBuilder: screenBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_mock_B3DB58B0D4D7BB6E {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `Screen` is constructed within the public mock trees of module `Feat`.
		nonisolated public struct __safeDI_Feat_Screen_MockConfiguration {
		    public init(
		        cache: (() -> Cache)? = nil,
		        _ safeDIBuilder: ((Cache, any Api, Instantiator<Screen>) -> Screen)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            cache: cache,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var cache: (() -> Cache)? { __safeDI_storage.cache }
		    /// Overrides how `Screen` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((Cache, any Api, Instantiator<Screen>) -> Screen)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            cache: (() -> Cache)?,
		            safeDIBuilder: ((Cache, any Api, Instantiator<Screen>) -> Screen)?
		        ) {
		            self.cache = cache
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let cache: (() -> Cache)?
		        let safeDIBuilder: ((Cache, any Api, Instantiator<Screen>) -> Screen)?
		    }
		}

		extension Screen {
		    static func __safeDI_init(cache: Cache, api: any Api, next: Instantiator<Screen>, safeDIBuilder: ((Cache, any Api, Instantiator<Screen>) -> Screen)?) -> Screen {
		        if let safeDIBuilder { safeDIBuilder(cache, api, next) } else { Screen(cache: cache, api: api, next: next) }
		    }
		}
		#endif

		"""])
		for depth in [4, 8] {
			let counts = try await describedCounts(of: modules, output: output, probe: "countsWhileScreenLives(atDepth: \(depth))")
			if compileVerificationIsEnabled {
				// Known-right keeps the held screen's cache and live alone.
				#expect(counts.knownRight == "probe countsWhileScreenLives(atDepth: \(depth))\nString \"Cache 1, Live 1\"\n")
				#expect(counts.feature == counts.knownRight)
			}
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The types every test's modules share, in module `Core`, each class counting its live instances.
	private static let core = """
	import SafeDI

	public protocol Api: AnyObject {}

	@Instantiable
	public final class Navigator: Instantiable {
	    public init() { Navigator.alive += 1 }
	    deinit { Navigator.alive -= 1 }
	    nonisolated(unsafe) public static var alive = 0
	    public var stack = [AnyObject]()
	}

	@Instantiable
	public final class Logger: Instantiable {
	    public init() { Logger.alive += 1 }
	    deinit { Logger.alive -= 1 }
	    nonisolated(unsafe) public static var alive = 0
	}

	@Instantiable
	public final class Token: Instantiable {
	    public init() { Token.alive += 1 }
	    deinit { Token.alive -= 1 }
	    nonisolated(unsafe) public static var alive = 0
	}
	"""

	/// `Page`, a `.public` mock in module `Feed`, which builds `navigator` and `logger`, then opens `Detail`, which opens
	/// `Leaf`, whose `api` is its one place. The initializers are internal, so `App` calls `Page`'s mock.
	private static func pageModules(app: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Core", packageName: "Core", swiftFileContent: [core]),
			ModuleFixture(name: "Feed", packageName: "Feed", swiftFileContent: [
				"""
				import Core
				import SafeDI

				@Instantiable
				public final class Leaf: Instantiable {
				    init(api: any Api) {
				        self.api = api
				    }

				    @Instantiated public let api: any Api
				}

				@Instantiable
				public final class Detail: Instantiable {
				    init(leafBuilder: Instantiator<Leaf>) {
				        self.leafBuilder = leafBuilder
				    }

				    @Instantiated public let leafBuilder: Instantiator<Leaf>
				}

				@Instantiable(generateMock: .public)
				public final class Page: Instantiable {
				    init(navigator: Navigator, logger: Logger, detailBuilder: Instantiator<Detail>) {
				        self.navigator = navigator
				        self.logger = logger
				        self.detailBuilder = detailBuilder
				    }

				    @Instantiated public let navigator: Navigator
				    @Instantiated public let logger: Logger
				    @Instantiated public let detailBuilder: Instantiator<Detail>
				}
				""",
			], dependencies: ["Core"]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContent: app.map { "import Core\nimport Feed\nimport SafeDI\n\n" + $0 }, dependencies: ["Core", "Feed"]),
		]
	}

	/// `Hub`, a `.public` mock in module `Feed`, whose `Model`'s `api` is reached through `Page`, which binds `token`, and
	/// straight from `Hub`, which does not.
	private static func routeModules(app: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Core", packageName: "Core", swiftFileContent: [core]),
			ModuleFixture(name: "Feed", packageName: "Feed", swiftFileContent: [
				"""
				import Core
				import SafeDI

				@Instantiable
				public final class Model: Instantiable {
				    init(api: any Api) {
				        self.api = api
				    }

				    @Instantiated public let api: any Api
				}

				@Instantiable
				public final class Page: Instantiable {
				    init(token: Token, modelBuilder: Instantiator<Model>) {
				        self.token = token
				        self.modelBuilder = modelBuilder
				    }

				    @Instantiated public let token: Token
				    @Instantiated public let modelBuilder: Instantiator<Model>
				}

				@Instantiable(generateMock: .public)
				public final class Hub: Instantiable {
				    init(navigator: Navigator, pageBuilder: Instantiator<Page>, modelBuilder: Instantiator<Model>) {
				        self.navigator = navigator
				        self.pageBuilder = pageBuilder
				        self.modelBuilder = modelBuilder
				    }

				    @Instantiated public let navigator: Navigator
				    @Instantiated public let pageBuilder: Instantiator<Page>
				    @Instantiated public let modelBuilder: Instantiator<Model>
				}
				""",
			], dependencies: ["Core"]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContent: app.map { "import Core\nimport Feed\nimport SafeDI\n\n" + $0 }, dependencies: ["Core", "Feed"]),
		]
	}

	/// `Hub`'s modules with `Shell`, a public mock in module `Mid` that builds a `logger` and holds `hub`, beside `mid`.
	private static func chainModules(mid: [String] = [liveToken], app: [String]) -> [ModuleFixture] {
		var modules = Array(routeModules(app: []).dropLast())
		modules.append(ModuleFixture(name: "Mid", packageName: "Mid", swiftFileContent: (mid + [
			"""
			@Instantiable(generateMock: .public)
			public final class Shell: Instantiable {
			    init(logger: Logger, hub: Hub) {
			        self.logger = logger
			        self.hub = hub
			    }

			    @Instantiated public let logger: Logger
			    @Instantiated public let hub: Hub
			}
			""",
		]).map { "import Core\nimport Feed\nimport SafeDI\n\n" + $0 }, dependencies: ["Core", "Feed"]))
		modules.append(ModuleFixture(name: "App", packageName: "App", swiftFileContent: app.map { "import Core\nimport Feed\nimport Mid\nimport SafeDI\n\n" + $0 }, dependencies: ["Core", "Feed", "Mid"]))
		return modules
	}

	/// `Live`, which fulfills `Api` and receives `declarations`.
	private static func live(receiving declarations: String) -> String {
		"""
		@Instantiable(fulfillingAdditionalTypes: [Api.self])
		public final class Live: Api, Instantiable {
		    public init(logger: Logger) {
		        self.logger = logger
		    }

		    \(declarations)
		}
		"""
	}

	/// `Live`, which fulfills `Api` and reads nothing.
	private static let live = """
	@Instantiable(fulfillingAdditionalTypes: [Api.self])
	public final class Live: Api, Instantiable {
	    public init() {}
	}
	"""

	/// `LiveToken`, which fulfills `Api` and reads `token`.
	private static let liveToken = """
	@Instantiable(fulfillingAdditionalTypes: [Api.self])
	public final class LiveToken: Api, Instantiable {
	    public init(token: Token) {
	        self.token = token
	    }

	    @Received public let token: Token
	}
	"""

	/// `LiveToken`, internal to its module.
	private static let internalLiveToken = liveToken
		.replacingOccurrences(of: "public final class LiveToken", with: "final class LiveToken")
		.replacingOccurrences(of: "public init(token: Token)", with: "init(token: Token)")

	/// `Root`, whose internal mock calls the public mock of what it holds, `property`.
	private static func root(holding property: String) -> String {
		"""
		@Instantiable(generateMock: true)
		public final class Root: Instantiable {
		    public init(\(property)) {
		        self.\(property.prefix { $0 != ":" }) = \(property.prefix { $0 != ":" })
		    }

		    @Instantiated public let \(property)
		}
		"""
	}

	/// Holds only the instantiator of a `Leaf` of `Root`'s page's detail, which the page's navigator holds, and reports the
	/// navigators and loggers alive.
	private static let countsWhileLeafBuilderLives = """
	func countsWhileLeafBuilderLives() -> String {
	    var leafBuilder: Instantiator<Leaf>?
	    do {
	        let page = Root.mock().page
	        let detail = page.detailBuilder.instantiate()
	        page.navigator.stack.append(detail)
	        leafBuilder = detail.leafBuilder
	    }
	    return withExtendedLifetime(leafBuilder) { "Navigator \\(Navigator.alive), Logger \\(Logger.alive)" }
	}
	"""

	/// A value `Detail` takes before its tree, which its mock's root level holds.
	enum RootLevelValue: CaseIterable, CustomTestStringConvertible {
		case forwarded
		case receivedThatMockCannotBuild
		case receivedOnlyIfAvailable

		var testDescription: String {
			switch self {
			case .forwarded:
				"forwarded"
			case .receivedThatMockCannotBuild:
				"received that the mock cannot build"
			case .receivedOnlyIfAvailable:
				"received only if available"
			}
		}

		/// `Detail`'s declaration of `session`.
		var declaration: String {
			switch self {
			case .forwarded:
				"@Forwarded public let session: Session"
			case .receivedThatMockCannotBuild:
				"@Received public let session: Session"
			case .receivedOnlyIfAvailable:
				"@Received(onlyIfAvailable: true) public let session: Session?"
			}
		}

		var sessionType: String {
			switch self {
			case .forwarded, .receivedThatMockCannotBuild:
				"Session"
			case .receivedOnlyIfAvailable:
				"Session?"
			}
		}

		/// `Root`, which builds `Detail` and hands it a session.
		var root: String {
			switch self {
			case .forwarded:
				"""
				@Instantiable(generateMock: true)
				public final class Root: Instantiable {
				    public init(detailBuilder: Instantiator<Detail>) {
				        self.detailBuilder = detailBuilder
				    }

				    @Instantiated public let detailBuilder: Instantiator<Detail>
				}
				"""
			case .receivedThatMockCannotBuild, .receivedOnlyIfAvailable:
				"""
				@Instantiable(generateMock: true)
				public final class Root: Instantiable {
				    public init(session: Session, detail: Detail) {
				        self.session = session
				        self.detail = detail
				    }

				    @Received public let session: Session
				    @Instantiated public let detail: Detail
				}
				"""
			}
		}

		/// Holds only the instantiator of a child of `Root`'s detail and reports the sessions alive.
		var probe: String {
			let detail = switch self {
			case .forwarded:
				"Root.mock().detailBuilder.instantiate(Session())"
			case .receivedThatMockCannotBuild, .receivedOnlyIfAvailable:
				"Root.mock(session: Session()).detail"
			}
			return """
			func sessionsWhileChildBuilderLives() -> String {
			    var childBuilder: Instantiator<Child>?
			    do {
			        childBuilder = \(detail).childBuilder
			    }
			    return withExtendedLifetime(childBuilder) { "Session \\(Session.alive)" }
			}
			"""
		}
	}

	/// `Card`, a public mock in module `Feed` that names a hand-written `preview` with a default-valued parameter and declares
	/// `cardDeclarations` beside its place, and `Deck`, a public mock whose tree builds `Card` with `preview`.
	private static func cardModules(cardDeclarations: [String]) -> [ModuleFixture] {
		let parameters = cardDeclarations.map { $0.split(separator: " ").dropFirst(3).joined(separator: " ") }
		let labels = parameters.map { $0.prefix { $0 != ":" } }
		return [
			ModuleFixture(name: "Core", packageName: "Core", swiftFileContent: [core]),
			ModuleFixture(name: "Feed", packageName: "Feed", swiftFileContent: [
				"""
				import Core
				import SafeDI

				@Instantiable(generateMock: .public, customMockName: "preview")
				public final class Card: Instantiable {
				    init(\((["api: any Api"] + parameters).joined(separator: ", "))) {
				        self.api = api\(labels.map { "\n        self.\($0) = \($0)" }.joined())
				    }

				    static func preview(\((["api: any Api"] + parameters).joined(separator: ", ")), retries: Int = 3) -> Card {
				        Card(\((["api: api"] + labels.map { "\($0): \($0)" }).joined(separator: ", ")))
				    }

				    @Instantiated public let api: any Api\(cardDeclarations.map { "\n    \($0)" }.joined())
				}

				@Instantiable(generateMock: .public)
				public final class Deck: Instantiable {
				    init(card: Card) {
				        self.card = card
				    }

				    @Instantiated public let card: Card
				}
				""",
			], dependencies: ["Core"]),
		]
	}

	/// `module`, compiled in a module whose declarations default to the main actor.
	/// Every type it declares is `nonisolated`, as an `@Instantiable` type is there, so its initializers and protocols are too and
	/// the same graph built inline compiles (issue #661).
	private static func defaultingToMainActor(_ module: ModuleFixture) -> ModuleFixture {
		ModuleFixture(
			name: module.name,
			packageName: module.packageName,
			swiftFileContent: module.swiftFileContent.map(nonisolatingEveryType),
			dependencies: module.dependencies,
			compilerSettings: VerificationCompilerSettings(defaultIsolation: "MainActor"),
		)
	}

	/// `source` with every type and protocol it declares `nonisolated`.
	private static func nonisolatingEveryType(_ source: String) -> String {
		source
			.replacingOccurrences(of: "\npublic final class ", with: "\nnonisolated public final class ")
			.replacingOccurrences(of: "\npublic struct ", with: "\nnonisolated public struct ")
			.replacingOccurrences(of: "\npublic protocol ", with: "\nnonisolated public protocol ")
			.replacingOccurrences(of: "\nfinal class ", with: "\nnonisolated final class ")
	}

	/// `modules`' declarations in one module, compiled as the first of `modules` is, every public mock internal.
	private static func inline(_ modules: [ModuleFixture]) -> [ModuleFixture] {
		let moduleNames = Set(modules.map(\.name))
		var inlineFiles = [String: String]()
		for module in modules {
			for (index, content) in module.swiftFileContent.enumerated() {
				inlineFiles["\(module.name)_File\(index).swift"] = content
					.split(separator: "\n", omittingEmptySubsequences: false)
					.filter { line in !moduleNames.contains { line == "import \($0)" } }
					.joined(separator: "\n")
					.replacingOccurrences(of: "generateMock: .public", with: "generateMock: true")
			}
		}
		return [ModuleFixture(name: "KnownRight", packageName: "KnownRight", swiftFileContentByFilePath: inlineFiles, compilerSettings: modules[0].compilerSettings)]
	}

	/// `Panel`, a plain-family public mock in module `Core`, and `Root`, which builds it in a `SendableInstantiator` and fills
	/// its place with `DefaultService`, which builds a `Tracker` of its own; each module compiled with `compilerSettings`.
	private static func sendableHolderModules(compilerSettings: VerificationCompilerSettings) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Core", packageName: "Core", swiftFileContent: [
				"""
				import SafeDI

				public protocol Service: Sendable {}

				@Instantiable(generateMock: .public)
				public struct Panel: Instantiable, Sendable {
				    init(service: any Service) {
				        self.service = service
				    }

				    @Instantiated let service: any Service
				}
				""",
			], compilerSettings: compilerSettings),
			ModuleFixture(name: "App", packageName: "App", swiftFileContent: [
				"""
				import Core
				import SafeDI

				@Instantiable
				public struct Tracker: Instantiable, Sendable {
				    public init() {}
				}

				@Instantiable(fulfillingAdditionalTypes: [Service.self])
				public struct DefaultService: Service, Instantiable {
				    public init(tracker: Tracker) {
				        self.tracker = tracker
				    }

				    @Instantiated let tracker: Tracker
				}

				@Instantiable(generateMock: true)
				public struct Root: Instantiable {
				    public init(heldBuilder: SendableInstantiator<Panel>) {
				        self.heldBuilder = heldBuilder
				    }

				    @Instantiated let heldBuilder: SendableInstantiator<Panel>
				}
				""",
			], dependencies: ["Core"], compilerSettings: compilerSettings),
		]
	}

	/// Expects every module of `output` to compile without a warning in its generated code wherever the same graph built in
	/// one module, `inlineControl`, compiles. Where the inline build fails, it must fail with issue #661's errors alone
	/// (`issue661ErrorMessages`), and every error of `output`'s modules must be one the inline build reports too, with the
	/// names it quotes aside: Swift 6.2 (Linux's and Xcode 26's) makes a mock's `SafeDIOverrides` main-actor isolated in a
	/// module whose declarations default to the main actor, and reports "main actor-isolated default value in a nonisolated
	/// context" at `mock()`'s `safeDIOverrides` parameter, in the inline build as in the modules.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectCompiles(_ output: MultiModuleTestOutput, inlineControl: [ModuleFixture], sourceLocation: SourceLocation = #_sourceLocation) async throws {
		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation, sourceLocation: sourceLocation)
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inlineControl, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		let inlineCompilation = try #require(inlineOutput.compilation, sourceLocation: sourceLocation)
		if let inlineFailure = inlineCompilation.failure {
			let inlineErrors = Self.errorMessages(in: inlineFailure.result.stderr)
			#expect(!inlineErrors.isEmpty && inlineErrors.isSubset(of: Self.issue661ErrorMessages), "The same graph built in one module fails with errors other than issue #661’s: \(inlineErrors.subtracting(Self.issue661ErrorMessages).sorted())\n\(inlineFailure.result.stderr)", sourceLocation: sourceLocation)
		}
		for module in compilation.modules {
			if let inlineFailure = inlineCompilation.failure {
				let errors = Self.errorMessages(in: module.result.stderr)
				let unsharedErrors = errors.subtracting(Self.errorMessages(in: inlineFailure.result.stderr))
				#expect(module.result.exitCode == 0 || !errors.isEmpty, "\(module.moduleName) fails without an error: \(module.result.stderr)", sourceLocation: sourceLocation)
				#expect(unsharedErrors.isEmpty, "\(module.moduleName) fails with errors the same graph built in one module does not report: \(unsharedErrors.sorted())\n\(module.result.stderr)", sourceLocation: sourceLocation)
			} else {
				#expect(module.result.exitCode == 0, "\(module.moduleName): \(module.result.stderr)", sourceLocation: sourceLocation)
			}
			#expect(module.generatedCodeWarnings.isEmpty, "\(module.moduleName): \(module.generatedCodeWarnings)", sourceLocation: sourceLocation)
		}
	}

	/// The errors issue #661 makes Swift 6.2 report, as `errorMessages(in:)` spells them: the default value of `mock()`'s
	/// `safeDIOverrides`, and each read of a property of the main-actor isolated `SafeDIOverrides` and mock configurations
	/// it holds from the nonisolated `mock()`.
	private static let issue661ErrorMessages: Set<String> = [
		"main actor-isolated default value in a nonisolated context",
		"main actor-isolated property '_' can not be referenced from a nonisolated context",
	]

	/// The messages of the errors in compiler output `stderr`, each with the names it quotes replaced by `_`.
	private static func errorMessages(in stderr: String) -> Set<String> {
		var messages = Set<String>()
		for line in stderr.split(separator: "\n") {
			guard let range = line.range(of: ": error: ") else { continue }
			let message = line[range.upperBound...]
			messages.insert(message.replacingOccurrences(of: "'[^']*'", with: "'_'", options: .regularExpression))
		}
		return messages
	}

	/// `Home`, a public mock in module `Feat` that builds `Screen`, which builds `cache` and opens `Step`, whose `api` is the
	/// place and which builds `Screen` again; then module `Mid` when `mid` is not empty, and `App`.
	private static func screenLoopModules(mid: [String] = [], app: [String]) -> [ModuleFixture] {
		var modules = [
			ModuleFixture(name: "Core", packageName: "Core", swiftFileContent: [core]),
			ModuleFixture(name: "Feat", packageName: "Feat", swiftFileContent: [
				"""
				import Core
				import SafeDI

				@Instantiable
				public final class Cache: Instantiable {
				    public init() {
				        Cache.created += 1
				        number = Cache.created
				        Cache.alive += 1
				    }

				    deinit { Cache.alive -= 1 }
				    public let number: Int
				    nonisolated(unsafe) public static var alive = 0
				    nonisolated(unsafe) public static var created = 0
				}

				@Instantiable
				public final class Step: Instantiable {
				    init(api: any Api, screenBuilder: Instantiator<Screen>) {
				        self.api = api
				        self.screenBuilder = screenBuilder
				    }

				    @Instantiated public let api: any Api
				    @Instantiated public let screenBuilder: Instantiator<Screen>
				}

				@Instantiable
				public final class Screen: Instantiable {
				    init(cache: Cache, stepBuilder: Instantiator<Step>) {
				        self.cache = cache
				        self.stepBuilder = stepBuilder
				    }

				    @Instantiated public let cache: Cache
				    @Instantiated public let stepBuilder: Instantiator<Step>
				}

				@Instantiable(generateMock: .public)
				public final class Home: Instantiable {
				    init(screen: Screen) {
				        self.screen = screen
				    }

				    @Instantiated public let screen: Screen
				}
				""",
			], dependencies: ["Core"]),
		]
		if !mid.isEmpty {
			modules.append(ModuleFixture(name: "Mid", packageName: "Mid", swiftFileContent: mid.map { "import Core\nimport Feat\nimport SafeDI\n\n" + $0 }, dependencies: ["Core", "Feat"]))
		}
		let appDependencies = ["Core", "Feat"] + (mid.isEmpty ? [] : ["Mid"])
		modules.append(ModuleFixture(name: "App", packageName: "App", swiftFileContent: app.map { appDependencies.map { "import \($0)\n" }.joined() + "import SafeDI\n\n" + $0 }, dependencies: appDependencies))
		return modules
	}

	/// Holds only the step of the second screen of the home `home` builds, and reports the caches alive.
	private static func cachesWhileSecondStepLives(home: String) -> String {
		"""
		func cachesWhileSecondStepLives() -> String {
		    var step: Step?
		    do {
		        let secondScreen = \(home).screen.stepBuilder.instantiate().screenBuilder.instantiate()
		        step = secondScreen.stepBuilder.instantiate()
		    }
		    return withExtendedLifetime(step) { "Cache \\(Cache.alive)" }
		}
		"""
	}

	/// What `probe` describes in the modules `output` generated, and in known-right: the same declarations in one module,
	/// every public mock internal, where no hole is left.
	private mutating func describedCounts(of modules: [ModuleFixture], output: MultiModuleTestOutput, probe: String) async throws -> (feature: String?, knownRight: String?) {
		let moduleNames = Set(modules.map(\.name))
		var inlineFiles = [String: String]()
		for module in modules {
			for (index, content) in module.swiftFileContent.enumerated() {
				inlineFiles["\(module.name)_File\(index).swift"] = content
					.split(separator: "\n", omittingEmptySubsequences: false)
					.filter { line in !moduleNames.contains { line == "import \($0)" } }
					.joined(separator: "\n")
					.replacingOccurrences(of: "generateMock: .public", with: "generateMock: true")
			}
		}
		let inlineModules = [ModuleFixture(name: "KnownRight", packageName: "KnownRight", swiftFileContentByFilePath: inlineFiles)]
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inlineModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		let feature = try await DifferentialValueOracle.describe(DifferentialValuePath(output: output, modules: modules), probes: [DifferentialValueProbe(probe)], filesToDelete: &filesToDelete)
		let knownRight = try await DifferentialValueOracle.describe(DifferentialValuePath(output: inlineOutput, modules: inlineModules), probes: [DifferentialValueProbe(probe)], filesToDelete: &filesToDelete)
		return (feature, knownRight)
	}
}
