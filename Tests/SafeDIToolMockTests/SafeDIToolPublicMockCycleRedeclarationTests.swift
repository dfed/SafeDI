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

/// A public mock hands the builder of a hole the same scope values at every level of a cycle in its tree, as a seam does.
/// A fill that reads a value the cycle declares again would read the first level's, where inline it reads the nearest,
/// so a mock that fills such a builder reports the error a tree that fills a seam's reports.
struct SafeDIToolPublicMockCycleRedeclarationTests: ~Copyable {
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
	mutating func generate_throwsError_whenMockFillsPublicMocksHoleWithTypeReadingValueCycleDeclaresAgain() async {
		// `Screen` instantiates `cache` and `stepBuilder`, and `Step` instantiates the hole `api` and
		// `screenBuilder`, which builds `Screen` again with a new `cache`. `Live`, which fills `api` in `App`, receives
		// `cache`: inline, the `Step` built again hands its `Live` the second `Screen`'s `cache`, but `Home.mock` hands
		// `apiBuilder` the first one's at every level. A tree that fills the same hole of a seam `Home` reports this
		// error, which the mock reports in production's words.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Live.swift"]):10:5: error: `Live` receives `cache: Cache`, which `Screen` declares between where `Screen` instantiates `stepBuilder: Instantiator<Step>` and where `Screen` instantiates it again. Inline, the `Step` built again receives `Screen`’s `cache`, but SafeDI hands the builder for `Step`’s `api: any Api` (`api` of `apiBuilder`) the same values at every level of that cycle. Declare `@Received let cache: Cache` on `Step`, so each `Step` receives the `cache` of its own level and hands it on, or declare an @Instantiable type that fulfills `Api` in module `Feat` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feat"]!["Feat.swift"]):19:5: note: `Screen` declares `cache: Cache` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Core.swift": """
					public protocol Api {}

					@Instantiable
					public final class Cache: Instantiable {
					    public init() {}
					}
					"""]),
					ModuleFixture(name: "Feat", packageName: "Shop", swiftFileContentByFilePath: ["Feat.swift": """
					import Core

					@Instantiable(generateMock: .public)
					public final class Home: Instantiable {
					    init(screen: Screen) {
					        self.screen = screen
					    }

					    @Instantiated let screen: Screen
					}

					@Instantiable
					public final class Screen: Instantiable {
					    init(cache: Cache, stepBuilder: Instantiator<Step>) {
					        self.cache = cache
					        self.stepBuilder = stepBuilder
					    }

					    @Instantiated let cache: Cache
					    @Instantiated let stepBuilder: Instantiator<Step>
					}

					@Instantiable
					public final class Step: Instantiable {
					    init(api: any Api, screenBuilder: Instantiator<Screen>) {
					        self.api = api
					        self.screenBuilder = screenBuilder
					    }

					    @Instantiated let api: any Api
					    @Instantiated let screenBuilder: Instantiator<Screen>
					}
					"""], dependencies: ["Core"]),
					ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: ["Live.swift": """
					import Core
					import Feat

					@Instantiable(fulfillingAdditionalTypes: [(any Api).self])
					public final class Live: Instantiable, Api {
					    public init(cache: Cache) {
					        self.cache = cache
					    }

					    @Received let cache: Cache
					}

					@Instantiable(generateMock: true)
					public final class Root: Instantiable {
					    init(home: Home) {
					        self.home = home
					    }

					    @Instantiated let home: Home
					}
					"""], dependencies: ["Core", "Feat"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenMockFillsPlaceAnotherPublicMockPassesUpWithTypeReadingValueCycleDeclaresAgain() async {
		// The fixture above, with `Shell`, a public mock in `Mid`, between `Home` and `Root`: `Shell` passes `Home`'s place
		// up, and `Root`'s mock fills it with `Live`, which receives `cache`. The call of `Home`'s mock over the reopened
		// `Screen` hands the builder the first `Screen`'s values, so the fill above the pass-up is rejected as the fill of the
		// direct call is.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Live.swift"]):11:5: error: `Live` receives `cache: Cache`, which `Screen` declares between where `Screen` instantiates `stepBuilder: Instantiator<Step>` and where `Screen` instantiates it again. Inline, the `Step` built again receives `Screen`’s `cache`, but SafeDI hands the builder for `Step`’s `api: any Api` (`api` of `apiBuilder`) the same values at every level of that cycle. Declare `@Received let cache: Cache` on `Step`, so each `Step` receives the `cache` of its own level and hands it on, or declare an @Instantiable type that fulfills `Api` in module `Feat` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feat"]!["Feat.swift"]):19:5: note: `Screen` declares `cache: Cache` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Core.swift": """
					public protocol Api {}

					@Instantiable
					public final class Cache: Instantiable {
					    public init() {}
					}
					"""]),
					ModuleFixture(name: "Feat", packageName: "Shop", swiftFileContentByFilePath: ["Feat.swift": """
					import Core

					@Instantiable(generateMock: .public)
					public final class Home: Instantiable {
					    init(screen: Screen) {
					        self.screen = screen
					    }

					    @Instantiated let screen: Screen
					}

					@Instantiable
					public final class Screen: Instantiable {
					    init(cache: Cache, stepBuilder: Instantiator<Step>) {
					        self.cache = cache
					        self.stepBuilder = stepBuilder
					    }

					    @Instantiated let cache: Cache
					    @Instantiated let stepBuilder: Instantiator<Step>
					}

					@Instantiable
					public final class Step: Instantiable {
					    init(api: any Api, screenBuilder: Instantiator<Screen>) {
					        self.api = api
					        self.screenBuilder = screenBuilder
					    }

					    @Instantiated let api: any Api
					    @Instantiated let screenBuilder: Instantiator<Screen>
					}
					"""], dependencies: ["Core"]),
					ModuleFixture(name: "Mid", packageName: "Mid", swiftFileContentByFilePath: ["Shell.swift": """
					import Core
					import Feat

					@Instantiable(generateMock: .public)
					public final class Shell: Instantiable {
					    init(home: Home) {
					        self.home = home
					    }

					    @Instantiated let home: Home
					}
					"""], dependencies: ["Core", "Feat"]),
					ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: ["Live.swift": """
					import Core
					import Feat
					import Mid

					@Instantiable(fulfillingAdditionalTypes: [(any Api).self])
					public final class Live: Instantiable, Api {
					    public init(cache: Cache) {
					        self.cache = cache
					    }

					    @Received let cache: Cache
					}

					@Instantiable(generateMock: true)
					public final class Root: Instantiable {
					    init(shell: Shell) {
					        self.shell = shell
					    }

					    @Instantiated let shell: Shell
					}
					"""], dependencies: ["Core", "Feat", "Mid"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenMockFillsPlacePublicMockPassesUpFromInsideCycleOfItsOwnTreeThatDeclaresValueAgain() async {
		// `Home`, a public mock in `Feat`, instantiates `api`, which nothing there fulfills. `Shell`, a public mock in `Mid`,
		// builds `Screen`, which declares `cache` and whose `Step` calls `Home`'s mock and builds `Screen` again; `Shell`
		// passes `Home`'s place up, and `Root`'s mock fills it with `Live`, which receives `cache`. Inline, the `Home` of the
		// `Screen` built again hands its `api` that `Screen`'s `cache`; `Shell`'s builder is handed the first `Screen`'s at
		// every level, so the fill is rejected, as a seam's is.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Live.swift"]):11:5: error: `Live` receives `cache: Cache`, which `Screen` declares between where `Screen` instantiates `stepBuilder: Instantiator<Step>` and where `Screen` instantiates it again. Inline, the `Step` built again receives `Screen`’s `cache`, but SafeDI hands the builder for `Home`’s `api: any Api` (`api` of `apiBuilder`) the same values at every level of that cycle. Declare `@Received let cache: Cache` on `Step`, so each `Step` receives the `cache` of its own level and hands it on, or declare an @Instantiable type that fulfills `Api` in module `Mid` or a module it lists among its SafeDI dependencies.
			\(fixtures["Mid"]!["Shell.swift"]):20:5: note: `Screen` declares `cache: Cache` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Core.swift": """
					public protocol Api {}

					@Instantiable
					public final class Cache: Instantiable {
					    public init() {}
					}
					"""]),
					ModuleFixture(name: "Feat", packageName: "Shop", swiftFileContentByFilePath: ["Feat.swift": """
					import Core

					@Instantiable(generateMock: .public)
					public final class Home: Instantiable {
					    public init(api: any Api) {
					        self.api = api
					    }

					    @Instantiated let api: any Api
					}
					"""], dependencies: ["Core"]),
					ModuleFixture(name: "Mid", packageName: "Mid", swiftFileContentByFilePath: ["Shell.swift": """
					import Core
					import Feat

					@Instantiable(generateMock: .public)
					public final class Shell: Instantiable {
					    init(screen: Screen) {
					        self.screen = screen
					    }

					    @Instantiated let screen: Screen
					}

					@Instantiable
					public final class Screen: Instantiable {
					    init(cache: Cache, stepBuilder: Instantiator<Step>) {
					        self.cache = cache
					        self.stepBuilder = stepBuilder
					    }

					    @Instantiated let cache: Cache
					    @Instantiated let stepBuilder: Instantiator<Step>
					}

					@Instantiable
					public final class Step: Instantiable {
					    init(home: Home, screenBuilder: Instantiator<Screen>) {
					        self.home = home
					        self.screenBuilder = screenBuilder
					    }

					    @Instantiated let home: Home
					    @Instantiated let screenBuilder: Instantiator<Screen>
					}
					"""], dependencies: ["Core", "Feat"]),
					ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: ["Live.swift": """
					import Core
					import Feat
					import Mid

					@Instantiable(fulfillingAdditionalTypes: [(any Api).self])
					public final class Live: Instantiable, Api {
					    public init(cache: Cache) {
					        self.cache = cache
					    }

					    @Received let cache: Cache
					}

					@Instantiable(generateMock: true)
					public final class Root: Instantiable {
					    init(shell: Shell) {
					        self.shell = shell
					    }

					    @Instantiated let shell: Shell
					}
					"""], dependencies: ["Core", "Feat", "Mid"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_takesNoBuilder_whenModuleOfPublicMockWhoseCycleDeclaresValueAgainDeclaresFillReadingIt() async throws {
		// The error's second remedy, applied to the fixture above: `Live` is declared in `Feat`, so `Home.mock` builds it
		// inline at every level of the cycle and takes no builder for `api`, and `Root.mock` takes none either.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Core.swift": """
				public protocol Api {}

				@Instantiable
				public final class Cache: Instantiable {
				    public init() {}
				}
				"""]),
				ModuleFixture(name: "Feat", packageName: "Shop", swiftFileContentByFilePath: ["Feat.swift": """
				import Core

				@Instantiable(generateMock: .public)
				public final class Home: Instantiable {
				    init(screen: Screen) {
				        self.screen = screen
				    }

				    @Instantiated let screen: Screen
				}

				@Instantiable
				public final class Screen: Instantiable {
				    init(cache: Cache, stepBuilder: Instantiator<Step>) {
				        self.cache = cache
				        self.stepBuilder = stepBuilder
				    }

				    @Instantiated let cache: Cache
				    @Instantiated let stepBuilder: Instantiator<Step>
				}

				@Instantiable
				public final class Step: Instantiable {
				    init(api: any Api, screenBuilder: Instantiator<Screen>) {
				        self.api = api
				        self.screenBuilder = screenBuilder
				    }

				    @Instantiated let api: any Api
				    @Instantiated let screenBuilder: Instantiator<Screen>
				}

				@Instantiable(fulfillingAdditionalTypes: [(any Api).self])
				public final class Live: Instantiable, Api {
				    public init(cache: Cache) {
				        self.cache = cache
				    }

				    @Received let cache: Cache
				}
				"""], dependencies: ["Core"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: ["Root.swift": """
				import Core
				import Feat

				@Instantiable(generateMock: true)
				public final class Root: Instantiable {
				    init(home: Home) {
				        self.home = home
				    }

				    @Instantiated let home: Home
				}
				"""], dependencies: ["Core", "Feat"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feat)
		import Feat
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
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        _ = Home.__safeDI_Home_mock_51799E6AA5E7B634.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let home = Home.__safeDI_mock(safeDIOverrides: safeDIOverrides.home)
		        return Root(home: home)
		    }
		}
		#endif
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_fillsHoleWithValueDeclaredOutsideCycle_whenTypeInPublicMocksCycleGivesItsValueAnotherLabel() async throws {
		// The error's first remedy, applied to the fixture above with `Home` instantiating a `cache` of its own: `Screen`
		// gives its `Cache` another label, so no level of the cycle declares the `cache` `Live` receives, and `Root.mock`
		// fills `api` under the cycle with `Live` built from `Home`'s `cache`, which inline reads at every level too.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Core.swift": """
				public protocol Api {}

				@Instantiable
				public final class Cache: Instantiable {
				    public init() {}
				}
				"""]),
				ModuleFixture(name: "Feat", packageName: "Shop", swiftFileContentByFilePath: ["Feat.swift": """
				import Core

				@Instantiable(generateMock: .public)
				public final class Home: Instantiable {
				    init(cache: Cache, screen: Screen) {
				        self.cache = cache
				        self.screen = screen
				    }

				    @Instantiated let cache: Cache
				    @Instantiated let screen: Screen
				}

				@Instantiable
				public final class Screen: Instantiable {
				    init(screenCache: Cache, stepBuilder: Instantiator<Step>) {
				        self.screenCache = screenCache
				        self.stepBuilder = stepBuilder
				    }

				    @Instantiated let screenCache: Cache
				    @Instantiated let stepBuilder: Instantiator<Step>
				}

				@Instantiable
				public final class Step: Instantiable {
				    init(api: any Api, screenBuilder: Instantiator<Screen>) {
				        self.api = api
				        self.screenBuilder = screenBuilder
				    }

				    @Instantiated let api: any Api
				    @Instantiated let screenBuilder: Instantiator<Screen>
				}
				"""], dependencies: ["Core"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: ["Live.swift": """
				import Core
				import Feat

				@Instantiable(fulfillingAdditionalTypes: [(any Api).self])
				public final class Live: Instantiable, Api {
				    public init(cache: Cache) {
				        self.cache = cache
				    }

				    @Received let cache: Cache
				}

				@Instantiable(generateMock: true)
				public final class Root: Instantiable {
				    init(home: Home) {
				        self.home = home
				    }

				    @Instantiated let home: Home
				}
				"""], dependencies: ["Core", "Feat"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feat)
		import Feat
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
		                .init(screen: { values in __safeDI_apiBuilder_Home_Screen_Scope(cache: values.cache) })
		            }
		            func __safeDI_apiBuilder_Home_Screen_Scope(cache: Cache) -> Home.SafeDIMockScope_Api.Screen_Scope.__safeDI_Builder<any Api> {
		                .init(stepBuilder: { _ in __safeDI_apiBuilder_Home_Step_Scope(cache: cache) })
		            }
		            func __safeDI_apiBuilder_Home_Step_Scope(cache: Cache) -> Home.SafeDIMockScope_Api.Step_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = Live(cache: cache)
		                    return api
		                })
		            }
		            _ = Home.__safeDI_Home_mock_E59AA37ED2CB4611.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Home.__safeDI_mock(apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_Home(), safeDIOverrides: safeDIOverrides.home)
		        }
		        let home: Home = __safeDI_home()
		        return Root(home: home)
		    }
		}
		#endif
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_readsNearestHoldersOverrideOfPublicMockCall_whenCallIsBeneathCycleEdge() async throws {
		// `Holder` builds itself again through `holderBuilder`, an edge `cycleEdges` prunes, so the `Holder` built there has no
		// member in its parent’s configuration; it reads the overrides of the nearest `Holder` above it, and so does its call
		// of `Cache`’s public mock.
		let modules = [
			ModuleFixture(name: "Core", packageName: "pkg", swiftFileContentByFilePath: ["Cache.swift": """
			import SafeDI

			@Instantiable(generateMock: .public)
			public struct Cache: Instantiable {
			    package init() {}
			}
			"""]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["Screen.swift": """
			import Core
			import SafeDI

			@Instantiable(generateMock: true)
			struct Screen: Instantiable {
			    init(holder: Holder) {
			        self.holder = holder
			    }

			    @Instantiated let holder: Holder
			}

			@Instantiable
			struct Holder: Instantiable {
			    init(cache: Cache, holderBuilder: Instantiator<Holder>) {
			        self.cache = cache
			        self.holderBuilder = holderBuilder
			    }

			    @Instantiated let cache: Cache
			    @Instantiated let holderBuilder: Instantiator<Holder>
			}
			"""], dependencies: ["Core"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(output.modules["App"]?.generatedFiles == ["App.swift": """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

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
		            holder: Holder.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                holder: holder
		            )
		        }

		        var holder: Holder.SafeDIMockConfiguration { __safeDI_storage.holder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                holder: Holder.SafeDIMockConfiguration
		            ) {
		                self.holder = holder
		            }

		            let holder: Holder.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_holder() -> Holder {
		            _ = Cache.__safeDI_Cache_mock_CBF29CE484222325.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            let cache = if let safeDIBuilder = safeDIOverrides.holder.cache { safeDIBuilder() } else { Cache.__safeDI_mock() }
		            func __safeDI_holderBuilder() -> Holder {
		                _ = Cache.__safeDI_Cache_mock_CBF29CE484222325.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                let cache = if let safeDIBuilder = safeDIOverrides.holder.cache { safeDIBuilder() } else { Cache.__safeDI_mock() }
		                let holderBuilder = Instantiator<Holder>(__safeDI_holderBuilder)
		                return if let safeDIBuilder = safeDIOverrides.holder.safeDIBuilder { safeDIBuilder(cache, holderBuilder) } else { Holder(cache: cache, holderBuilder: holderBuilder) }
		            }
		            let holderBuilder = Instantiator<Holder>(__safeDI_holderBuilder)
		            return if let safeDIBuilder = safeDIOverrides.holder.safeDIBuilder { safeDIBuilder(cache, holderBuilder) } else { Holder(cache: cache, holderBuilder: holderBuilder) }
		        }
		        let holder: Holder = __safeDI_holder()
		        return Screen(holder: holder)
		    }
		}
		#endif

		#if DEBUG
		extension Holder {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            cache: (() -> Cache)? = nil,
		            _ safeDIBuilder: ((Cache, Instantiator<Holder>) -> Holder)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                cache: cache,
		                safeDIBuilder: safeDIBuilder
		            )
		        }

		        var cache: (() -> Cache)? { __safeDI_storage.cache }
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        var safeDIBuilder: ((Cache, Instantiator<Holder>) -> Holder)? { __safeDI_storage.safeDIBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                cache: (() -> Cache)?,
		                safeDIBuilder: ((Cache, Instantiator<Holder>) -> Holder)?
		            ) {
		                self.cache = cache
		                self.safeDIBuilder = safeDIBuilder
		            }

		            let cache: (() -> Cache)?
		            let safeDIBuilder: ((Cache, Instantiator<Holder>) -> Holder)?
		        }
		    }
		}
		#endif

		"""])
	}

	// MARK: Private

	private var filesToDelete: [URL]
}
