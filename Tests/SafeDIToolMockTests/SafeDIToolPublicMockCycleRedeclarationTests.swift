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
			\(fixtures["App"]!["Live.swift"]):10:5: error: `Live` receives `cache: Cache`, which `Screen` declares between where `Screen` instantiates `stepBuilder: Instantiator<Step>` and where `Screen` instantiates it again. Inline, the `Step` built again receives `Screen`’s `cache`, but the values struct SafeDI hands the builder for `Step`’s `api: any Api` (`api` of `apiBuilder`) holds the same values at every level of that cycle. Give `cache` on `Screen` another label, or declare an @Instantiable type that fulfills `Api` in module `Feat` or a module it lists among its SafeDI dependencies.
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
			\(fixtures["App"]!["Live.swift"]):11:5: error: `Live` receives `cache: Cache`, which `Screen` declares between where `Screen` instantiates `stepBuilder: Instantiator<Step>` and where `Screen` instantiates it again. Inline, the `Step` built again receives `Screen`’s `cache`, but the scope SafeDI hands the builder for `Step`’s `api: any Api` (case `Step_Scope.api` of `apiBuilder`) holds the same values at every level of that cycle. Give `cache` on `Screen` another label, or declare an @Instantiable type that fulfills `Api` in module `Feat` or a module it lists among its SafeDI dependencies.
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
		            self.home = home
		        }

		        let home: Home.SafeDIOverrides
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        _ = Home.__safeDI_Home_mock_51799E6AA5E7B634.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let home = Home.mock(safeDIOverrides: safeDIOverrides.home)
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
		            self.home = home
		        }

		        let home: Home.SafeDIOverrides
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_home() -> Home {
		            func __safeDI_apiBuilder_Home(_ scope: Home.SafeDIMockScope_Api) -> any Api {
		                switch scope {
		                case let .screen(values, scope): return __safeDI_apiBuilder_Home_Screen_Scope(scope, cache: values.cache)
		                }
		            }
		            func __safeDI_apiBuilder_Home_Screen_Scope(_ scope: Home.SafeDIMockScope_Api.Screen_Scope, cache: Cache) -> any Api {
		                switch scope {
		                case let .stepBuilder(_, scope): return __safeDI_apiBuilder_Home_Step_Scope(scope, cache: cache)
		                }
		            }
		            func __safeDI_apiBuilder_Home_Step_Scope(_ scope: Home.SafeDIMockScope_Api.Step_Scope, cache: Cache) -> any Api {
		                switch scope {
		                case .api:
		                    let api: any Api = Live(cache: cache)
		                    return api
		                }
		            }
		            _ = Home.__safeDI_Home_mock_B981D08F2CFD6B45.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Home.mock(apiBuilder: __safeDI_apiBuilder_Home, safeDIOverrides: safeDIOverrides.home)
		        }
		        let home: Home = __safeDI_home()
		        return Root(home: home)
		    }
		}
		#endif
		""")
	}

	// MARK: Private

	private var filesToDelete: [URL]
}
