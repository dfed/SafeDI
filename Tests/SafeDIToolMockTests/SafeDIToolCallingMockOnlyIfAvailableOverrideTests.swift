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

/// An internal mock whose tree calls another module’s public mock, whose tree receives a value only if available that
/// nothing in the calling tree provides, takes an override for the value, as the same types built inline in one module
/// take one for their tree’s receive only if available, and passes it to the call. A public mock takes the same value as a
/// parameter of `mock()` instead.
struct SafeDIToolCallingMockOnlyIfAvailableOverrideTests: ~Copyable {
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
	mutating func generate_takesOverrideAndPassesItToCall_whenOnlyPublicMockCallReceivesValueOnlyIfAvailable() async throws {
		let modules = Self.modules(screen: """
		import Core
		import SafeDI

		@Instantiable(generateMock: true)
		public struct Screen: Instantiable {
		    public init(cache: Cache) {
		        self.cache = cache
		    }

		    @Instantiated let cache: Cache
		}
		""")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
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
		            cache: Cache.SafeDIOverrides = .init(),
		            filter: (any FilterProtocol)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                cache: cache
		            )
		            self.filter = filter
		        }

		        var cache: Cache.SafeDIOverrides { __safeDI_storage.cache }
		        let filter: (any FilterProtocol)?

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                cache: Cache.SafeDIOverrides
		            ) {
		                self.cache = cache
		            }

		            let cache: Cache.SafeDIOverrides
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let filter: (any FilterProtocol)? = safeDIOverrides.filter
		        _ = Cache.__safeDI_Cache_mock_215B449271BCAB93.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let cache = Cache.__safeDI_mock(filter: filter, safeDIOverrides: safeDIOverrides.cache)
		        return Screen(cache: cache)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [
			DifferentialValueProbe("Screen.mock()"),
			Self.screenMockPassedFilter,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNilToCall_whenSiblingBuiltAfterCallProvidesValueCallReceivesOnlyIfAvailable() async throws {
		// `Filter` receives `cache`, so `Screen`’s mock builds `cache` first, and the call of `Cache`’s public mock is passed
		// `nil` for the `filter` its tree receives only if available, as production passes `nil` to a receive of a sibling
		// built later.
		let modules = Self.modules(
			screen: """
			import Core
			import SafeDI

			@Instantiable(generateMock: true)
			public struct Screen: Instantiable {
			    public init(cache: Cache, filter: Filter) {
			        self.cache = cache
			        self.filter = filter
			    }

			    @Instantiated let cache: Cache
			    @Instantiated let filter: Filter
			}
			""",
			filterType: "Filter?",
			coreAddition: """
			@Instantiable
			public final class Filter: Instantiable {
			    public init(cache: Cache) {
			        self.cache = cache
			    }

			    @Received let cache: Cache
			}
			""",
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
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
		            cache: Cache.SafeDIOverrides = .init(),
		            filter: ((Cache) -> Filter)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                cache: cache,
		                filter: filter
		            )
		        }

		        var cache: Cache.SafeDIOverrides { __safeDI_storage.cache }
		        var filter: ((Cache) -> Filter)? { __safeDI_storage.filter }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                cache: Cache.SafeDIOverrides,
		                filter: ((Cache) -> Filter)?
		            ) {
		                self.cache = cache
		                self.filter = filter
		            }

		            let cache: Cache.SafeDIOverrides
		            let filter: ((Cache) -> Filter)?
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        _ = Cache.__safeDI_Cache_mock_7257C1618F8CE2B3.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let cache = Cache.__safeDI_mock(filter: nil, safeDIOverrides: safeDIOverrides.cache)
		        let filter = if let safeDIBuilder = safeDIOverrides.filter { safeDIBuilder(cache) } else { Filter(cache: cache) }
		        return Screen(cache: cache, filter: filter)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [
			DifferentialValueProbe("Screen.mock()"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNilToRootLevelFunction_whenSiblingBuiltAfterCallProvidesValueFillReceivesOnlyIfAvailable() async throws {
		// `Feed`, whose public mock `Screen` calls, builds `Model` at its root and inside `Page`, which declares `token`, so the
		// fill of `Model`’s `api` takes `token` from the root level function on the route through `Feed`’s root. `Token` and
		// `Feed` each receive the other only if available, so `Screen`’s mock builds `feed` first and the fill reads `nil`,
		// as production passes `nil` to a receive of a sibling built later: the root level function is handed `nil` too,
		// not the `token` declared after the call.
		let modules = [
			ModuleFixture(name: "Core", packageName: "Core", swiftFileContentByFilePath: ["Core.swift": """
			import SafeDI

			public protocol Api: AnyObject {}

			@Instantiable(generateMock: .public)
			public final class Feed: Instantiable {
			    init(page: Page, model: Model) {
			        self.page = page
			        self.model = model
			    }

			    @Instantiated let page: Page
			    @Instantiated let model: Model
			}

			@Instantiable
			public final class Page: Instantiable {
			    init(token: Token, model: Model) {
			        self.token = token
			        self.model = model
			    }

			    @Instantiated let token: Token
			    @Instantiated let model: Model
			}

			@Instantiable
			public final class Model: Instantiable {
			    init(api: any Api) {
			        self.api = api
			    }

			    @Instantiated let api: any Api
			}

			@Instantiable
			public final class Token: Instantiable {
			    public init(feed: Feed?) {
			        self.feed = feed
			    }

			    @Received(onlyIfAvailable: true) let feed: Feed?
			}
			"""]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: ["Screen.swift": """
			import Core
			import SafeDI

			@Instantiable(fulfillingAdditionalTypes: [Api.self])
			public final class LiveApi: Instantiable, Api {
			    public init(token: Token?) {
			        self.token = token
			    }

			    @Received(onlyIfAvailable: true) let token: Token?
			}

			@Instantiable(generateMock: true)
			public final class Screen: Instantiable {
			    public init(token: Token, feed: Feed) {
			        self.token = token
			        self.feed = feed
			    }

			    @Instantiated let token: Token
			    @Instantiated let feed: Feed
			}
			"""], dependencies: ["Core"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
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
		            feed: Feed.SafeDIOverrides = .init(),
		            token: ((Feed?) -> Token)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                feed: feed,
		                token: token
		            )
		        }

		        var feed: Feed.SafeDIOverrides { __safeDI_storage.feed }
		        var token: ((Feed?) -> Token)? { __safeDI_storage.token }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                feed: Feed.SafeDIOverrides,
		                token: ((Feed?) -> Token)?
		            ) {
		                self.feed = feed
		                self.token = token
		            }

		            let feed: Feed.SafeDIOverrides
		            let token: ((Feed?) -> Token)?
		        }
		    }

		    static func mock(
		        apiBuilder: (() -> any Api)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_fillBody_4B36035601BEA37A(token: Token?) -> any Api {
		            let api: any Api = LiveApi(token: token)
		            return api
		        }
		        func __safeDI_feed() -> Feed {
		            func __safeDI_apiBuilder_Feed_Model_Scope_api(_ scope: Feed.SafeDIMockScope_Api.Model_Scope.api_Values, token: Token?) -> any Api {
		                return __safeDI_fillBody_4B36035601BEA37A(token: token)
		            }
		            func __safeDI_apiBuilder_Feed(token: Token?) -> Feed.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(page: { _ in __safeDI_apiBuilder_Feed_Page_Scope() }, model: { _ in __safeDI_apiBuilder_Feed_Model_Scope_(token: token) })
		            }
		            func __safeDI_apiBuilder_Feed_Page_Scope() -> Feed.SafeDIMockScope_Api.Page_Scope.__safeDI_Builder<any Api> {
		                .init(model: { values in __safeDI_apiBuilder_Feed_Model_Scope(token: values.token) })
		            }
		            func __safeDI_apiBuilder_Feed_Model_Scope(token: Token) -> Feed.SafeDIMockScope_Api.Model_Scope.__safeDI_Builder<any Api> {
		                .init(api: { scope in __safeDI_apiBuilder_Feed_Model_Scope_api(scope, token: token) })
		            }
		            func __safeDI_apiBuilder_Feed_Model_Scope_(token: Token?) -> Feed.SafeDIMockScope_Api.Model_Scope.__safeDI_Builder<any Api> {
		                .init(api: { scope in __safeDI_apiBuilder_Feed_Model_Scope_api(scope, token: token) })
		            }
		            _ = Feed.__safeDI_Feed_mock_774316E7D473A6D8.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Feed.__safeDI_mock(apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_Feed(token: nil), feed: nil, safeDIOverrides: safeDIOverrides.feed)
		        }
		        let feed: Feed = __safeDI_feed()
		        let token = if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder(feed) } else { Token(feed: feed) }
		        return Screen(token: token, feed: feed)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [
			DifferentialValueProbe("Screen.mock()"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsCallUnderOverridesLabelInsideBuilderFunction_whenTypeBuiltInInstantiatorCallsPublicMockOfLabelMockReceivesOnlyIfAvailable() async throws {
		// `Screen` receives `cache` only if available, so its mock binds the override `cache`, and `Home`, built in
		// `homeBuilder`’s function, calls `Cache`’s public mock for its own `cache`, bound under the label inside that
		// function, where it hides the override.
		let modules = Self.modules(screen: """
		import Core
		import SafeDI

		@Instantiable(generateMock: true)
		public struct Screen: Instantiable {
		    public init(cache: Cache?, homeBuilder: Instantiator<Home>) {
		        self.cache = cache
		        self.homeBuilder = homeBuilder
		    }

		    @Received(onlyIfAvailable: true) let cache: Cache?
		    @Instantiated let homeBuilder: Instantiator<Home>
		}

		@Instantiable
		public struct Home: Instantiable {
		    public init(cache: Cache) {
		        self.cache = cache
		    }

		    @Instantiated let cache: Cache
		}
		""")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
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
		            homeBuilder: Home.SafeDIMockConfiguration = .init(),
		            cache: Cache? = nil,
		            filter: (any FilterProtocol)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                homeBuilder: homeBuilder
		            )
		            self.cache = cache
		            self.filter = filter
		        }

		        var homeBuilder: Home.SafeDIMockConfiguration { __safeDI_storage.homeBuilder }
		        let cache: Cache?
		        let filter: (any FilterProtocol)?

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                homeBuilder: Home.SafeDIMockConfiguration
		            ) {
		                self.homeBuilder = homeBuilder
		            }

		            let homeBuilder: Home.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let cache: Cache? = safeDIOverrides.cache
		        let filter: (any FilterProtocol)? = safeDIOverrides.filter
		        func __safeDI_homeBuilder() -> Home {
		            _ = Cache.__safeDI_Cache_mock_215B449271BCAB93.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            let cache = Cache.__safeDI_mock(filter: filter, safeDIOverrides: safeDIOverrides.homeBuilder.cache)
		            return if let safeDIBuilder = safeDIOverrides.homeBuilder.safeDIBuilder { safeDIBuilder(cache) } else { Home(cache: cache) }
		        }
		        let homeBuilder = Instantiator<Home>(__safeDI_homeBuilder)
		        return Screen(cache: cache, homeBuilder: homeBuilder)
		    }
		}
		#endif

		#if DEBUG
		extension Home {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            cache: Cache.SafeDIOverrides = .init(),
		            _ safeDIBuilder: ((Cache) -> Home)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                cache: cache,
		                safeDIBuilder: safeDIBuilder
		            )
		        }

		        var cache: Cache.SafeDIOverrides { __safeDI_storage.cache }
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        var safeDIBuilder: ((Cache) -> Home)? { __safeDI_storage.safeDIBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                cache: Cache.SafeDIOverrides,
		                safeDIBuilder: ((Cache) -> Home)?
		            ) {
		                self.cache = cache
		                self.safeDIBuilder = safeDIBuilder
		            }

		            let cache: Cache.SafeDIOverrides
		            let safeDIBuilder: ((Cache) -> Home)?
		        }
		    }
		}
		#endif

		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [
			DifferentialValueProbe("Screen.mock()"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesOverrideAndPassesItToCall_whenListedCallersPublicMockCallReceivesValueOnlyIfAvailable() async throws {
		let modules = Self.modules(screen: """
		import Core
		import SafeDI

		@Instantiable
		public struct Screen: Instantiable {
		    public init(cache: Cache) {
		        self.cache = cache
		    }

		    @Instantiated let cache: Cache
		}
		""", appFiles: ["SafeDIConfiguration.swift": "import SafeDI\n\n#SafeDIConfiguration(additionalMocksToGenerate: [\"Screen\"])\n"])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
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
		            cache: Cache.SafeDIOverrides = .init(),
		            filter: (any FilterProtocol)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                cache: cache
		            )
		            self.filter = filter
		        }

		        var cache: Cache.SafeDIOverrides { __safeDI_storage.cache }
		        let filter: (any FilterProtocol)?

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                cache: Cache.SafeDIOverrides
		            ) {
		                self.cache = cache
		            }

		            let cache: Cache.SafeDIOverrides
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let filter: (any FilterProtocol)? = safeDIOverrides.filter
		        _ = Cache.__safeDI_Cache_mock_215B449271BCAB93.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let cache = Cache.__safeDI_mock(filter: filter, safeDIOverrides: safeDIOverrides.cache)
		        return Screen(cache: cache)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [
			DifferentialValueProbe("Screen.mock()"),
			Self.screenMockPassedFilter,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesOverrideToCallInsideInstantiator_whenInstantiatorBuildsPublicMockReceivingValueOnlyIfAvailable() async throws {
		let modules = Self.modules(screen: """
		import Core
		import SafeDI

		@Instantiable(generateMock: true)
		public struct Screen: Instantiable {
		    public init(cacheBuilder: Instantiator<Cache>) {
		        self.cacheBuilder = cacheBuilder
		    }

		    @Instantiated public let cacheBuilder: Instantiator<Cache>
		}
		""")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
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
		            cacheBuilder: Cache.SafeDIOverrides = .init(),
		            filter: (any FilterProtocol)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                cacheBuilder: cacheBuilder
		            )
		            self.filter = filter
		        }

		        var cacheBuilder: Cache.SafeDIOverrides { __safeDI_storage.cacheBuilder }
		        let filter: (any FilterProtocol)?

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                cacheBuilder: Cache.SafeDIOverrides
		            ) {
		                self.cacheBuilder = cacheBuilder
		            }

		            let cacheBuilder: Cache.SafeDIOverrides
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let filter: (any FilterProtocol)? = safeDIOverrides.filter
		        _ = Cache.__safeDI_Cache_mock_215B449271BCAB93.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        func __safeDI_cacheBuilder() -> Cache {
		            Cache.__safeDI_mock(filter: filter, safeDIOverrides: safeDIOverrides.cacheBuilder)
		        }
		        let cacheBuilder = Instantiator<Cache>(__safeDI_cacheBuilder)
		        return Screen(cacheBuilder: cacheBuilder)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [
			DifferentialValueProbe(name: "Screen.mock()’s cache", expression: "Screen.mock().cacheBuilder.instantiate()", knownRightExpression: "Screen.mock().cacheBuilder.instantiate()"),
			DifferentialValueProbe(
				name: "Screen.mock() passed a filter, its cache",
				expression: "Screen.mock(safeDIOverrides: .init(filter: ProbeFilter())).cacheBuilder.instantiate()",
				knownRightExpression: "Screen.mock(safeDIOverrides: .init(filter: ProbeFilter())).cacheBuilder.instantiate()",
			),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesOneOverrideToEveryCall_whenTwoPublicMocksReceiveValueOnlyIfAvailable() async throws {
		let modules = Self.modules(screen: """
		import Core
		import SafeDI

		@Instantiable(generateMock: true)
		public struct Screen: Instantiable {
		    public init(cache: Cache, vault: Vault) {
		        self.cache = cache
		        self.vault = vault
		    }

		    @Instantiated let cache: Cache
		    @Instantiated let vault: Vault
		}
		""", coreAddition: """
		@Instantiable(generateMock: .public)
		public struct Vault: Instantiable {
		    package init(tokenCache: TokenCache) {
		        self.tokenCache = tokenCache
		    }

		    @Instantiated let tokenCache: TokenCache
		}
		""")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
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
		            cache: Cache.SafeDIOverrides = .init(),
		            vault: Vault.SafeDIOverrides = .init(),
		            filter: (any FilterProtocol)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                cache: cache,
		                vault: vault
		            )
		            self.filter = filter
		        }

		        var cache: Cache.SafeDIOverrides { __safeDI_storage.cache }
		        var vault: Vault.SafeDIOverrides { __safeDI_storage.vault }
		        let filter: (any FilterProtocol)?

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                cache: Cache.SafeDIOverrides,
		                vault: Vault.SafeDIOverrides
		            ) {
		                self.cache = cache
		                self.vault = vault
		            }

		            let cache: Cache.SafeDIOverrides
		            let vault: Vault.SafeDIOverrides
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let filter: (any FilterProtocol)? = safeDIOverrides.filter
		        _ = Cache.__safeDI_Cache_mock_215B449271BCAB93.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let cache = Cache.__safeDI_mock(filter: filter, safeDIOverrides: safeDIOverrides.cache)
		        _ = Vault.__safeDI_Vault_mock_215B449271BCAB93.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let vault = Vault.__safeDI_mock(filter: filter, safeDIOverrides: safeDIOverrides.vault)
		        return Screen(cache: cache, vault: vault)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [
			DifferentialValueProbe("Screen.mock()"),
			Self.screenMockPassedFilter,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesInstanceOverrideAndPassesItsWrapperToCall_whenOnlyPublicMockCallReceivesLazilyInstantiatedValueOnlyIfAvailable() async throws {
		let modules = Self.modules(screen: """
		import Core
		import SafeDI

		@Instantiable(generateMock: true)
		public struct Screen: Instantiable {
		    public init(cache: Cache) {
		        self.cache = cache
		    }

		    @Instantiated let cache: Cache
		}
		""", filterType: "LazilyInstantiated<any FilterProtocol>?")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
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
		            cache: Cache.SafeDIOverrides = .init(),
		            filter: (any FilterProtocol)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                cache: cache
		            )
		            self.filter = filter
		        }

		        var cache: Cache.SafeDIOverrides { __safeDI_storage.cache }
		        let filter: (any FilterProtocol)?

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                cache: Cache.SafeDIOverrides
		            ) {
		                self.cache = cache
		            }

		            let cache: Cache.SafeDIOverrides
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let filter: (any FilterProtocol)? = safeDIOverrides.filter
		        let filter_lazilyInstantiated = filter.map { instance in LazilyInstantiated<any FilterProtocol> { instance } }
		        _ = Cache.__safeDI_Cache_mock_8045DFD2FB3769D2.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let cache = Cache.__safeDI_mock(filter: filter_lazilyInstantiated, safeDIOverrides: safeDIOverrides.cache)
		        return Screen(cache: cache)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [
			DifferentialValueProbe("Screen.mock()"),
			Self.screenMockPassedFilter,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesOverrideCalledMockBuildsWhenPassedNil_whenCallerCannotConstructValueCalledMockRequires() async throws {
		// `Session` is `public` with a `package` initializer, so `App` names it but cannot build it: `Cache`’s mock builds it
		// when passed `nil`, since `SessionReader` requires it, and `Screen`’s mock takes an override that defaults to `nil`.
		let modules = Self.modules(screen: """
		import Core
		import SafeDI

		@Instantiable(generateMock: true)
		public struct Screen: Instantiable {
		    public init(cache: Cache) {
		        self.cache = cache
		    }

		    @Instantiated let cache: Cache
		}
		""", coreAddition: """
		@Instantiable
		public final class Session: Instantiable {
		    package init() {}
		}

		@Instantiable
		package struct SessionReader: Instantiable {
		    package init(session: Session) {
		        self.session = session
		    }

		    @Received let session: Session
		}
		""", cacheInstantiatesSessionReader: true)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
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
		            cache: Cache.SafeDIOverrides = .init(),
		            filter: (any FilterProtocol)? = nil,
		            session: Session? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                cache: cache
		            )
		            self.filter = filter
		            self.session = session
		        }

		        var cache: Cache.SafeDIOverrides { __safeDI_storage.cache }
		        let filter: (any FilterProtocol)?
		        let session: Session?

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                cache: Cache.SafeDIOverrides
		            ) {
		                self.cache = cache
		            }

		            let cache: Cache.SafeDIOverrides
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let filter: (any FilterProtocol)? = safeDIOverrides.filter
		        let session: Session? = safeDIOverrides.session
		        _ = Cache.__safeDI_Cache_mock_9029937F38DBD702.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let cache = Cache.__safeDI_mock(filter: filter, session: session, safeDIOverrides: safeDIOverrides.cache)
		        return Screen(cache: cache)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [
			DifferentialValueProbe("Screen.mock()"),
			Self.screenMockPassedFilter,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesOverrideApartAndKeepsParameterLabel_whenTreeRequiresLabelInAnotherFormNothingBuilds() async throws {
		// `Reader` requires `filter: Marker`, which nothing builds, so `mock()` takes it as a parameter, which keeps its label:
		// the override for the `filter` only `Cache`’s call receives is named apart from it. The same types built inline name
		// the parameter apart from their own override instead.
		let modules = Self.modules(screen: """
		import Core
		import SafeDI

		@Instantiable(generateMock: true)
		public struct Screen: Instantiable {
		    public init(cache: Cache, reader: Reader) {
		        self.cache = cache
		        self.reader = reader
		    }

		    @Instantiated let cache: Cache
		    @Instantiated let reader: Reader
		}

		public final class Marker {
		    public init() {}
		}

		@Instantiable
		public struct Reader: Instantiable {
		    public init(filter: Marker) {
		        self.filter = filter
		    }

		    @Received let filter: Marker
		}
		""")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
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
		            cache: Cache.SafeDIOverrides = .init(),
		            reader: ((Marker) -> Reader)? = nil,
		            filter_FilterProtocol: (any FilterProtocol)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                cache: cache,
		                reader: reader
		            )
		            self.filter_FilterProtocol = filter_FilterProtocol
		        }

		        var cache: Cache.SafeDIOverrides { __safeDI_storage.cache }
		        var reader: ((Marker) -> Reader)? { __safeDI_storage.reader }
		        let filter_FilterProtocol: (any FilterProtocol)?

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                cache: Cache.SafeDIOverrides,
		                reader: ((Marker) -> Reader)?
		            ) {
		                self.cache = cache
		                self.reader = reader
		            }

		            let cache: Cache.SafeDIOverrides
		            let reader: ((Marker) -> Reader)?
		        }
		    }

		    static func mock(
		        filter: Marker,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let filter_FilterProtocol: (any FilterProtocol)? = safeDIOverrides.filter_FilterProtocol
		        _ = Cache.__safeDI_Cache_mock_215B449271BCAB93.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        func __safeDI_cache() -> Cache {
		            let filter: (any FilterProtocol)? = filter_FilterProtocol
		            return Cache.__safeDI_mock(filter: filter, safeDIOverrides: safeDIOverrides.cache)
		        }
		        let cache: Cache = __safeDI_cache()
		        let reader = if let safeDIBuilder = safeDIOverrides.reader { safeDIBuilder(filter) } else { Reader(filter: filter) }
		        return Screen(cache: cache, reader: reader)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [
			DifferentialValueProbe(
				name: "Screen.mock() passed a marker and a filter",
				expression: "Screen.mock(filter: Marker(), safeDIOverrides: .init(filter_FilterProtocol: ProbeFilter()))",
				knownRightExpression: "Screen.mock(filter_Marker: Marker(), safeDIOverrides: .init(filter: ProbeFilter()))",
			),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsOwnOverrideLabelAndNamesNewOverrideApart_whenTreeReceivesLabelOnlyIfAvailableAsAnotherType() async throws {
		// `Reader` receives `filter: Marker?` only if available, which nothing provides, so `mock()` takes an override for it,
		// as it did before it took one for what `Cache`’s call receives: that override keeps its label, and the override for
		// the `filter` only `Cache`’s call receives is named apart from it. The same types built inline name both apart.
		let modules = Self.modules(screen: """
		import Core
		import SafeDI

		@Instantiable(generateMock: true)
		public struct Screen: Instantiable {
		    public init(cache: Cache, reader: Reader) {
		        self.cache = cache
		        self.reader = reader
		    }

		    @Instantiated let cache: Cache
		    @Instantiated let reader: Reader
		}

		public final class Marker {
		    public init() {}
		}

		@Instantiable
		public struct Reader: Instantiable {
		    public init(filter: Marker?) {
		        self.filter = filter
		    }

		    @Received(onlyIfAvailable: true) let filter: Marker?
		}
		""")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
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
		            cache: Cache.SafeDIOverrides = .init(),
		            reader: ((Marker?) -> Reader)? = nil,
		            filter_FilterProtocol: (any FilterProtocol)? = nil,
		            filter: Marker? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                cache: cache,
		                reader: reader
		            )
		            self.filter_FilterProtocol = filter_FilterProtocol
		            self.filter = filter
		        }

		        var cache: Cache.SafeDIOverrides { __safeDI_storage.cache }
		        var reader: ((Marker?) -> Reader)? { __safeDI_storage.reader }
		        let filter_FilterProtocol: (any FilterProtocol)?
		        let filter: Marker?

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                cache: Cache.SafeDIOverrides,
		                reader: ((Marker?) -> Reader)?
		            ) {
		                self.cache = cache
		                self.reader = reader
		            }

		            let cache: Cache.SafeDIOverrides
		            let reader: ((Marker?) -> Reader)?
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let filter_FilterProtocol: (any FilterProtocol)? = safeDIOverrides.filter_FilterProtocol
		        let filter: Marker? = safeDIOverrides.filter
		        _ = Cache.__safeDI_Cache_mock_215B449271BCAB93.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        func __safeDI_cache() -> Cache {
		            let filter: (any FilterProtocol)? = filter_FilterProtocol
		            return Cache.__safeDI_mock(filter: filter, safeDIOverrides: safeDIOverrides.cache)
		        }
		        let cache: Cache = __safeDI_cache()
		        let reader = if let safeDIBuilder = safeDIOverrides.reader { safeDIBuilder(filter) } else { Reader(filter: filter) }
		        return Screen(cache: cache, reader: reader)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [
			DifferentialValueProbe(
				name: "Screen.mock() passed a marker",
				expression: "Screen.mock(safeDIOverrides: .init(filter: Marker()))",
				knownRightExpression: "Screen.mock(safeDIOverrides: .init(filter_Marker: Marker()))",
			),
			DifferentialValueProbe(
				name: "Screen.mock() passed a filter and a marker",
				expression: "Screen.mock(safeDIOverrides: .init(filter_FilterProtocol: ProbeFilter(), filter: Marker()))",
				knownRightExpression: "Screen.mock(safeDIOverrides: .init(filter_FilterProtocol: ProbeFilter(), filter_Marker: Marker()))",
			),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesNoOverrideAndPassesCallNil_whenCallInSendableFunctionReceivesValueOnlyIfAvailable() async throws {
		// `Wrapper` is built inside the `@Sendable` builder function of a `SendableInstantiator`, where an override the mock
		// bound above it would be captured, and `any FilterProtocol` is not `Sendable`: the mock takes no override, and the
		// call passes `nil`, so the mock compiles. The same types built inline take an override that does not compile here.
		let modules = Self.modules(screen: """
		import Core
		import SafeDI

		@Instantiable
		public struct Wrapper: Instantiable {
		    public init(cache: Cache) {
		        self.cache = cache
		    }

		    @Instantiated let cache: Cache
		}

		@Instantiable(generateMock: true)
		public struct Screen: Instantiable {
		    public init(wrapperBuilder: SendableInstantiator<Wrapper>) {
		        self.wrapperBuilder = wrapperBuilder
		    }

		    @Instantiated let wrapperBuilder: SendableInstantiator<Wrapper>
		}
		""")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
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
		            wrapperBuilder: Wrapper.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                wrapperBuilder: wrapperBuilder
		            )
		        }

		        var wrapperBuilder: Wrapper.SafeDIMockConfiguration { __safeDI_storage.wrapperBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage: Sendable {
		            init(
		                wrapperBuilder: Wrapper.SafeDIMockConfiguration
		            ) {
		                self.wrapperBuilder = wrapperBuilder
		            }

		            let wrapperBuilder: Wrapper.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let __safeDI_wrapperBuilder__overrides = safeDIOverrides.wrapperBuilder
		        @Sendable nonisolated func __safeDI_wrapperBuilder() -> Wrapper {
		            _ = Cache.__safeDI_Cache_mock_215B449271BCAB93.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            let cache = Cache.__safeDI_mock(filter: nil, safeDIOverrides: __safeDI_wrapperBuilder__overrides.cache?() ?? .init())
		            return if let safeDIBuilder = __safeDI_wrapperBuilder__overrides.safeDIBuilder { safeDIBuilder(cache) } else { Wrapper(cache: cache) }
		        }
		        let wrapperBuilder = SendableInstantiator<Wrapper>(__safeDI_wrapperBuilder)
		        return Screen(wrapperBuilder: wrapperBuilder)
		    }
		}
		#endif

		#if DEBUG
		extension Wrapper {
		    /// Configuration for how this type is constructed within a mock tree.
		    nonisolated struct SafeDIMockConfiguration: Sendable {
		        init(
		            cache: (@Sendable () -> Cache.SafeDIOverrides)? = nil,
		            _ safeDIBuilder: (@Sendable (Cache) -> Wrapper)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                cache: cache,
		                safeDIBuilder: safeDIBuilder
		            )
		        }

		        var cache: (@Sendable () -> Cache.SafeDIOverrides)? { __safeDI_storage.cache }
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        var safeDIBuilder: (@Sendable (Cache) -> Wrapper)? { __safeDI_storage.safeDIBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage: Sendable {
		            init(
		                cache: (@Sendable () -> Cache.SafeDIOverrides)?,
		                safeDIBuilder: (@Sendable (Cache) -> Wrapper)?
		            ) {
		                self.cache = cache
		                self.safeDIBuilder = safeDIBuilder
		            }

		            let cache: (@Sendable () -> Cache.SafeDIOverrides)?
		            let safeDIBuilder: (@Sendable (Cache) -> Wrapper)?
		        }
		    }
		}
		#endif
		""" + "\n"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesNoOverrideAndPassesEveryCallNil_whenAnotherCallOutsideSendableFunctionReceivesValueToo() async throws {
		// `Screen`’s own call of `Cache`’s mock reads `filter` outside every `@Sendable` function, but `Wrapper`’s reads it inside
		// one: the mock takes no override for it, and both calls pass `nil`.
		let modules = Self.modules(screen: """
		import Core
		import SafeDI

		@Instantiable
		public struct Wrapper: Instantiable {
		    public init(cache: Cache) {
		        self.cache = cache
		    }

		    @Instantiated let cache: Cache
		}

		@Instantiable(generateMock: true)
		public struct Screen: Instantiable {
		    public init(cache: Cache, wrapperBuilder: SendableInstantiator<Wrapper>) {
		        self.cache = cache
		        self.wrapperBuilder = wrapperBuilder
		    }

		    @Instantiated let cache: Cache
		    @Instantiated let wrapperBuilder: SendableInstantiator<Wrapper>
		}
		""")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
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
		            cache: Cache.SafeDIOverrides = .init(),
		            wrapperBuilder: Wrapper.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                cache: cache,
		                wrapperBuilder: wrapperBuilder
		            )
		        }

		        var cache: Cache.SafeDIOverrides { __safeDI_storage.cache }
		        var wrapperBuilder: Wrapper.SafeDIMockConfiguration { __safeDI_storage.wrapperBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                cache: Cache.SafeDIOverrides,
		                wrapperBuilder: Wrapper.SafeDIMockConfiguration
		            ) {
		                self.cache = cache
		                self.wrapperBuilder = wrapperBuilder
		            }

		            let cache: Cache.SafeDIOverrides
		            let wrapperBuilder: Wrapper.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        _ = Cache.__safeDI_Cache_mock_215B449271BCAB93.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let cache = Cache.__safeDI_mock(filter: nil, safeDIOverrides: safeDIOverrides.cache)
		        let __safeDI_wrapperBuilder__overrides = safeDIOverrides.wrapperBuilder
		        @Sendable nonisolated func __safeDI_wrapperBuilder() -> Wrapper {
		            _ = Cache.__safeDI_Cache_mock_215B449271BCAB93.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            let cache = Cache.__safeDI_mock(filter: nil, safeDIOverrides: __safeDI_wrapperBuilder__overrides.cache?() ?? .init())
		            return if let safeDIBuilder = __safeDI_wrapperBuilder__overrides.safeDIBuilder { safeDIBuilder(cache) } else { Wrapper(cache: cache) }
		        }
		        let wrapperBuilder = SendableInstantiator<Wrapper>(__safeDI_wrapperBuilder)
		        return Screen(cache: cache, wrapperBuilder: wrapperBuilder)
		    }
		}
		#endif

		#if DEBUG
		extension Wrapper {
		    /// Configuration for how this type is constructed within a mock tree.
		    nonisolated struct SafeDIMockConfiguration: Sendable {
		        init(
		            cache: (@Sendable () -> Cache.SafeDIOverrides)? = nil,
		            _ safeDIBuilder: (@Sendable (Cache) -> Wrapper)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                cache: cache,
		                safeDIBuilder: safeDIBuilder
		            )
		        }

		        var cache: (@Sendable () -> Cache.SafeDIOverrides)? { __safeDI_storage.cache }
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        var safeDIBuilder: (@Sendable (Cache) -> Wrapper)? { __safeDI_storage.safeDIBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage: Sendable {
		            init(
		                cache: (@Sendable () -> Cache.SafeDIOverrides)?,
		                safeDIBuilder: (@Sendable (Cache) -> Wrapper)?
		            ) {
		                self.cache = cache
		                self.safeDIBuilder = safeDIBuilder
		            }

		            let cache: (@Sendable () -> Cache.SafeDIOverrides)?
		            let safeDIBuilder: (@Sendable (Cache) -> Wrapper)?
		        }
		    }
		}
		#endif
		""" + "\n"])
	}

	/// Before, the calling mock took its own `filter: (() -> Filter)?` override for the instance its tree requires and
	/// passed the call `nil`; now it promotes the wrapper, as the inline mock does, so the override is
	/// `(@Sendable () -> Filter)?` and the call is handed the wrapper whose instance the tree reads.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_promotesWrapperAndPassesItToCall_whenCalledMockReceivesSendableWrapperOnlyIfAvailableAndTreeRequiresItsInstance() async throws {
		let modules = [
			ModuleFixture(name: "Core", packageName: "pkg", swiftFileContentByFilePath: ["Cache.swift": """
			import SafeDI

			@Instantiable
			public final class Filter: Instantiable, Sendable {
			    public init() {}
			}

			@Instantiable
			package struct TokenCache: Instantiable {
			    package init(filter: SendableLazilyInstantiated<Filter>?) {
			        self.filter = filter
			    }

			    @Received(onlyIfAvailable: true) let filter: SendableLazilyInstantiated<Filter>?
			}

			@Instantiable(generateMock: .public)
			public struct Cache: Instantiable {
			    package init(tokenCache: TokenCache) {
			        self.tokenCache = tokenCache
			    }

			    @Instantiated let tokenCache: TokenCache
			}
			"""]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["Screen.swift": """
			import Core
			import SafeDI

			@Instantiable(generateMock: true)
			public struct Screen: Instantiable {
			    public init(cache: Cache, reader: Reader) {
			        self.cache = cache
			        self.reader = reader
			    }

			    @Instantiated let cache: Cache
			    @Instantiated let reader: Reader
			}

			@Instantiable
			public struct Reader: Instantiable {
			    public init(filter: Filter) {
			        self.filter = filter
			    }

			    @Received let filter: Filter
			}
			"""], dependencies: ["Core"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
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
		            filter: (@Sendable () -> Filter)? = nil,
		            cache: Cache.SafeDIOverrides = .init(),
		            reader: ((Filter) -> Reader)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                filter: filter,
		                cache: cache,
		                reader: reader
		            )
		        }

		        var filter: (@Sendable () -> Filter)? { __safeDI_storage.filter }
		        var cache: Cache.SafeDIOverrides { __safeDI_storage.cache }
		        var reader: ((Filter) -> Reader)? { __safeDI_storage.reader }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                filter: (@Sendable () -> Filter)?,
		                cache: Cache.SafeDIOverrides,
		                reader: ((Filter) -> Reader)?
		            ) {
		                self.filter = filter
		                self.cache = cache
		                self.reader = reader
		            }

		            let filter: (@Sendable () -> Filter)?
		            let cache: Cache.SafeDIOverrides
		            let reader: ((Filter) -> Reader)?
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let __safeDI_filter__safeDIBuilder = safeDIOverrides.filter
		        @Sendable nonisolated func __safeDI_filter() -> Filter {
		            if let safeDIBuilder = __safeDI_filter__safeDIBuilder { safeDIBuilder() } else { Filter() }
		        }
		        let filter = SendableLazilyInstantiated<Filter>(__safeDI_filter)
		        _ = Cache.__safeDI_Cache_mock_5E1700DCC2ECDE3C.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let cache = Cache.__safeDI_mock(filter: filter, safeDIOverrides: safeDIOverrides.cache)
		        let reader = if let safeDIBuilder = safeDIOverrides.reader { safeDIBuilder(filter.instance) } else { Reader(filter: filter.instance) }
		        return Screen(cache: cache, reader: reader)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [
			DifferentialValueProbe("Screen.mock()"),
		])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The probe that passes `ProbeFilter` through the override, which the inline mock takes for its tree’s receive only if
	/// available.
	private static let screenMockPassedFilter = DifferentialValueProbe(
		name: "Screen.mock() passed a filter",
		expression: "Screen.mock(safeDIOverrides: .init(filter: ProbeFilter()))",
		knownRightExpression: "Screen.mock(safeDIOverrides: .init(filter: ProbeFilter()))",
	)

	/// `Core`, whose `Cache` has a public mock and holds the `package` `TokenCache`, which `App`, in another package, cannot
	/// build, so `App` calls `Cache`’s public mock; `TokenCache` receives `filter` only if available, and nothing in `Core`
	/// provides it, so `Cache`’s mock takes `filter: (any FilterProtocol)? = nil`. `App` declares `screen` and `ProbeFilter`,
	/// which the probes pass as `filter`.
	/// `filterType` is the type `TokenCache` receives `filter` as; `coreAddition`, when not empty, is a second file of `Core`;
	/// and `Cache` also instantiates `Core`’s `SessionReader` when `cacheInstantiatesSessionReader`.
	private static func modules(
		screen: String,
		appFiles: [String: String] = [:],
		filterType: String = "(any FilterProtocol)?",
		coreAddition: String = "",
		cacheInstantiatesSessionReader: Bool = false,
	) -> [ModuleFixture] {
		var files = appFiles
		files["Screen.swift"] = screen + "\n\n" + """
		public final class ProbeFilter: FilterProtocol {
		    public init() {}
		}
		"""
		let cache = if cacheInstantiatesSessionReader {
			"""
			@Instantiable(generateMock: .public)
			public struct Cache: Instantiable {
			    package init(tokenCache: TokenCache, sessionReader: SessionReader) {
			        self.tokenCache = tokenCache
			        self.sessionReader = sessionReader
			    }

			    @Instantiated let tokenCache: TokenCache
			    @Instantiated let sessionReader: SessionReader
			}
			"""
		} else {
			"""
			@Instantiable(generateMock: .public)
			public struct Cache: Instantiable {
			    package init(tokenCache: TokenCache) {
			        self.tokenCache = tokenCache
			    }

			    @Instantiated let tokenCache: TokenCache
			}
			"""
		}
		var coreFiles = ["Cache.swift": """
		import SafeDI

		public protocol FilterProtocol {}

		@Instantiable
		package struct TokenCache: Instantiable {
		    package init(filter: \(filterType)) {
		        self.filter = filter
		    }

		    @Received(onlyIfAvailable: true) let filter: \(filterType)
		}

		\(cache)
		"""]
		if !coreAddition.isEmpty {
			coreFiles["Addition.swift"] = "import SafeDI\n\n" + coreAddition
		}
		return [
			ModuleFixture(name: "Core", packageName: "pkg", swiftFileContentByFilePath: coreFiles),
			ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: files, dependencies: ["Core"]),
		]
	}

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
