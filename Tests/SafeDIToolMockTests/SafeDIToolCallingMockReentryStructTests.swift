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

/// A calling mock whose fill of a called public mock’s place builds a type of a third module whose public mock holds a
/// builder of the called type, and whose tree, through that re-entry or beside it, reaches a type no declaration the
/// caller’s module sees fulfills. The calling mock takes a builder of that type, as the production twin does, and a
/// `.public` caller hands it through the struct of its own level: the call of the third module’s public mock takes the
/// struct of the caller’s level its route leads to and hands it on to the level function it re-enters, as the twin’s
/// call of the third module’s seam does, so every place is filled and the values are those of the same types built
/// inline.
struct SafeDIToolCallingMockReentryStructTests: ~Copyable {
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

	@Test(arguments: GraphFuzzerCallingMockCell.Caller.allCases, Layout.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsEveryPlaceHandingCallersStructThroughReentry_whenReenteringFillReachesTypeNothingFulfills(caller: GraphFuzzerCallingMockCell.Caller, layout: Layout) async throws {
		// `Page`’s fill `DefaultService` builds, itself or through `Chapter`’s fill, `Book`, whose builder of `Page` re-enters
		// the call of `Page`, and a type of the tree, inside the re-entered call’s fills or beside it, instantiates
		// `analytics: any Analytics`, which nothing `App` sees fulfills. `mock()` takes `analyticsBuilder` and fills every place,
		// as the twin does, for every caller kind; a `.public` caller’s call of `Book` hands the re-entered level functions the
		// struct of its own level, so the generated code compiles and builds what the same types built inline build.
		let graph = Self.graph(caller: caller, layout: layout)
		let modules = graph.modules(.mock)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)

		let expected = Self.expectedFiles(of: layout, caller: caller)
		for module in ["Core", "Mid", "App"] {
			#expect(output.modules[module]?.generatedFiles == [module + ".swift": expected[module] ?? ""], "\(module)")
		}
		if compileVerificationIsEnabled {
			try await expectCompilesAndBuildsInlineValues(of: graph, output: output, modules: modules, probes: [Self.probe(of: layout)])
		}
	}

	@Test(arguments: GraphFuzzerCallingMockCell.Caller.allCases, Layout.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsEveryPlaceThroughSendableBuilder_whenReenteringBuilderIsSendableInstantiator(caller: GraphFuzzerCallingMockCell.Caller, layout: Layout) async throws {
		// The layouts above with `Book`, and `DefaultService` where it holds `Page` itself, holding `Page` in a
		// `SendableInstantiator`: the fill of `Page`’s place is built in the `@Sendable` function of `Book`’s builder, so
		// `mock()` takes `analyticsSendableBuilder`. The level of the fill that makes the call of `Book` is of the plain
		// family, and its member for that call returns `Book`’s `@Sendable` family’s struct, so its no-scope initializer, and
		// that of each level that hands it its builder, takes a `@Sendable` builder, as `mock()`’s does.
		let graph = Self.graph(caller: caller, layout: layout, builder: .sendableInstantiator)
		let modules = graph.modules(.mock)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)

		let app = switch caller {
		case .internal, .listed:
			Self.expectedSendableInternalApp(of: layout)
		case .public:
			Self.expectedSendablePublicApp(of: layout)
		}
		let expected = ["Core": Self.expectedCore(of: layout), "Mid": Self.expectedSendableMid(of: layout), "App": app]
		for module in ["Core", "Mid", "App"] {
			#expect(output.modules[module]?.generatedFiles == [module + ".swift": expected[module] ?? ""], "\(module)")
		}
		if compileVerificationIsEnabled {
			try await expectCompilesAndBuildsInlineValues(of: graph, output: output, modules: modules, probes: [Self.probe(of: layout, builder: .sendableInstantiator)])
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_makesSendableLevelFunctionFromRecords_whenReenteringBuilderIsSendableInstantiator() async throws {
		// `DefaultService`, the fill of `Page`’s place, builds `Book`, whose call re-enters `Page`’s level function from the
		// `@Sendable` function of `Book`’s builder, which makes it `@Sendable`: node records make `Screen`’s call’s level
		// functions with it so, as the tree does, where they read what the call inside the fill refers to
		// (`FillReferences`). The fill builds nothing else, so no place of `Screen`’s own is inside it.
		let modules = [
			ModuleFixture(name: "Core", packageName: "Core", swiftFileContent: [ReenteringFillFixtures.core(of: .fillInstantiatesIt, attribute: ReenteringFillFixtures.publicMock)]),
			ModuleFixture(name: "Mid", packageName: "Mid", swiftFileContent: [ReenteringFillFixtures.mid(of: .fillInstantiatesIt, attribute: ReenteringFillFixtures.publicMock, builder: .sendableInstantiator)], dependencies: ["Core"]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["""
			import Core
			import Mid
			import SafeDI

			@Instantiable(fulfillingAdditionalTypes: [(any Service).self])
			final class DefaultService: Service, Instantiable {
			    init(book: Book) { self.book = book }
			    @Instantiated let book: Book
			}

			@Instantiable(generateMock: true)
			final class Screen: Instantiable {
			    init(page: Page) { self.page = page }
			    @Instantiated let page: Page
			}
			"""], dependencies: ["Core", "Mid"]),
		]
		let (stream, continuation) = AsyncStream.makeStream(of: LevelFunctionRecordsObservation.self)
		_ = try await LevelFunctionRecordsObservation.$observer.withValue({ continuation.yield($0) }) {
			try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
		continuation.finish()
		var treeProjections = Set<String>()
		var recordsProjections = [String]()
		for await observation in stream {
			if observation.root == "Screen" {
				recordsProjections.append(observation.projection)
			} else if observation.root == nil {
				treeProjections.insert(observation.projection)
			}
		}

		let sendablePageLevel = "dispatcherKey: \"dispatcher Page Service Service plain\", builderType: SafeDICore.TypeDescription.nested(name: \"__safeDI_Builder\", parentType: SafeDICore.TypeDescription.nested(name: \"SafeDIMockScope_Service\", parentType: SafeDICore.TypeDescription.simple(name: \"Page\", generics: []), generics: []), generics: [SafeDICore.TypeDescription.any(SafeDICore.TypeDescription.simple(name: \"Service\", generics: []))]), isSendable: true"
		#expect(recordsProjections.count == 1)
		#expect(recordsProjections.allSatisfy { treeProjections.contains($0) && $0.contains(sendablePageLevel) }, "\(recordsProjections)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsInlineValuesThroughCallersLevelFunctions_whenAnotherModuleCallsPublicMockWhoseReenteringFillReachesTypeNothingFulfills() async throws {
		// `Top`’s `Root` builds `Screen`, whose `.public` mock takes `analyticsBuilder`, the `split` layout’s, and `Top`’s
		// `LiveAnalytics` fulfills `Analytics`, so `Root`’s mock fills it: its level functions implement each route of
		// `Screen`’s struct, the route through the call of `Book` inside `DefaultService` included, which `Book`’s level
		// functions hand on to the level functions of `Page` they re-enter. The values are those of the same types built
		// inline.
		let graph = Self.calledFromAnotherModuleGraph()
		let modules = graph.modules(.mock)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)

		for module in ["Core", "Mid", "App", "Top"] {
			#expect(output.modules[module]?.generatedFiles == [module + ".swift": Self.expectedFilesCalledFromAnotherModule[module] ?? ""], "\(module)")
		}
		if compileVerificationIsEnabled {
			let read = { (root: String, module: String) in
				"{ let root = \(root); let service = root.screen.page.service as! \(module).DefaultService; return (root, service.book.pageBuilder.instantiate()) }()"
			}
			try await expectCompilesAndBuildsInlineValues(of: graph, output: output, modules: modules, probes: [DifferentialValueProbe(name: "(Root, the Page Book builds)", expression: read("Top.Root.mock()", "App"), knownRightExpression: read("Top.Root()", "Top"))])
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	typealias Layout = ReenteringFillLayout

	/// The graph: module `Core` declares `Page`, whose places of `Service`, and of `Logger` for the sibling place’s layout,
	/// no type `Core` sees fulfills, and, where the layout nests a call, `Chapter`, whose place of `Store` no type `Core` sees
	/// fulfills either; module `Mid` declares `Book`, which holds `Page` in an `Instantiator`, and, for the called mock’s own
	/// place’s layout, a place of `Store`; and module `App` declares `Analytics`, which no type `App` sees fulfills,
	/// `LiveAnalytics`, a plain class a probe hands `mock()`’s builder, the fills (`Layout`), and the caller `Screen`, which
	/// builds `Page` (`ReenteringFillFixtures`). `builder` holds `Page` in `Book`, and in `DefaultService` where it holds
	/// `Page` itself. The calling mock’s form declares the called types public mocks only; the twin declares them seams that
	/// keep their public mocks, and `LiveAnalytics` an `Instantiable` that fulfills `Analytics`, so the same types built
	/// inline, which are read from the twin, build what a probe hands `mock()`.
	private static func graph(caller: GraphFuzzerCallingMockCell.Caller, layout: Layout, builder: ReenteringFillBuilder = .instantiator) -> GraphFuzzerCallingMockGraph {
		let access = caller == .public ? "public " : ""
		func files(calledTypeAttribute: String, callerAttribute: String, analyticsIsInstantiable: Bool) -> [GraphFuzzerCallingMockGraph.File] {
			[
				GraphFuzzerCallingMockGraph.File(module: "Core", dependencies: [], content: ReenteringFillFixtures.core(of: layout, attribute: calledTypeAttribute)),
				GraphFuzzerCallingMockGraph.File(module: "Mid", dependencies: ["Core"], content: ReenteringFillFixtures.mid(of: layout, attribute: calledTypeAttribute, builder: builder)),
				GraphFuzzerCallingMockGraph.File(module: "App", dependencies: ["Core", "Mid"], content: ReenteringFillFixtures.app(of: layout, callerAttribute: callerAttribute, access: access, analyticsIsInstantiable: analyticsIsInstantiable, builder: builder)),
			]
		}
		return GraphFuzzerCallingMockGraph(
			name: "a fill that re-enters the called type and reaches a type nothing fulfills",
			mockFiles: files(calledTypeAttribute: ReenteringFillFixtures.publicMock, callerAttribute: callerAttribute(of: caller), analyticsIsInstantiable: false),
			twinFiles: files(calledTypeAttribute: ReenteringFillFixtures.seamAndPublicMock, callerAttribute: "@Instantiable(generateDependencyTree: true)", analyticsIsInstantiable: true),
			callerTypeName: "Screen",
			callerIsPublic: caller == .public,
			mockConfiguration: caller == .listed ? "import SafeDI\n\n#SafeDIConfiguration(additionalMocksToGenerate: [\"Screen\"])\n" : nil,
			flatParameterLabels: [],
			implementationIsVisible: true,
			expectedTwinInitializerLabels: [],
			expectedPassUpLabels: [],
			expectedTwinErrorSite: nil,
			valueProbes: nil,
		)
	}

	/// The graph of `siblingPlacesFillInstantiatesIt` with a `.public` `Screen` whose initializer only `App` calls, and a
	/// fourth module, `Top`, whose `Root` builds `Screen`, and whose `LiveAnalytics` fulfills `Analytics`: `Root`’s internal
	/// mock calls `Screen`’s public mock and fills its place of `Analytics`.
	private static func calledFromAnotherModuleGraph() -> GraphFuzzerCallingMockGraph {
		let layout = Layout.siblingPlacesFillInstantiatesIt
		func top(rootAttribute: String) -> String {
			"""
			import App
			import Core
			import Mid
			import SafeDI

			@Instantiable(fulfillingAdditionalTypes: [(any Analytics).self])
			final class LiveAnalytics: Analytics, Instantiable {
			    init() {}
			}

			\(rootAttribute)
			final class Root: Instantiable {
			    init(screen: Screen) { self.screen = screen }
			    @Instantiated let screen: Screen
			}

			"""
		}
		func files(calledTypeAttribute: String, rootAttribute: String) -> [GraphFuzzerCallingMockGraph.File] {
			[
				GraphFuzzerCallingMockGraph.File(module: "Core", dependencies: [], content: ReenteringFillFixtures.core(of: layout, attribute: calledTypeAttribute)),
				GraphFuzzerCallingMockGraph.File(module: "Mid", dependencies: ["Core"], content: ReenteringFillFixtures.mid(of: layout, attribute: calledTypeAttribute)),
				GraphFuzzerCallingMockGraph.File(module: "App", dependencies: ["Core", "Mid"], content: ReenteringFillFixtures.app(of: layout, callerAttribute: calledTypeAttribute, access: "public ", analyticsIsInstantiable: nil)),
				GraphFuzzerCallingMockGraph.File(module: "Top", dependencies: ["Core", "Mid", "App"], content: top(rootAttribute: rootAttribute)),
			]
		}
		return GraphFuzzerCallingMockGraph(
			name: "a module that calls a public mock whose re-entering fill reaches a type nothing fulfills",
			mockFiles: files(calledTypeAttribute: ReenteringFillFixtures.publicMock, rootAttribute: "@Instantiable(generateMock: true)"),
			twinFiles: files(calledTypeAttribute: ReenteringFillFixtures.seamAndPublicMock, rootAttribute: "@Instantiable(generateDependencyTree: true)"),
			callerTypeName: "Root",
			callerIsPublic: false,
			mockConfiguration: nil,
			flatParameterLabels: [],
			implementationIsVisible: true,
			expectedTwinInitializerLabels: [],
			expectedPassUpLabels: [],
			expectedTwinErrorSite: nil,
			valueProbes: nil,
		)
	}

	/// What a cell of `layout` whose builder is `builder` compares: `Screen`, and the `Page` that `Book`’s builder builds,
	/// or, where `DefaultService` holds `Page`’s builder itself, that builder builds, which re-enters the call’s level
	/// functions.
	private static func probe(of layout: Layout, builder: ReenteringFillBuilder = .instantiator) -> DifferentialValueProbe {
		DifferentialValueProbe(
			name: "(Screen, the re-entered Page)",
			expression: ReenteringFillFixtures.screenAndReenteredPage(of: layout, screen: "App.Screen.mock(\(builder.analyticsBuilderLabel): { App.LiveAnalytics() })"),
			knownRightExpression: ReenteringFillFixtures.screenAndReenteredPage(of: layout, screen: "App.Screen()"),
		)
	}

	private static func callerAttribute(of caller: GraphFuzzerCallingMockCell.Caller) -> String {
		switch caller {
		case .internal:
			"@Instantiable(generateMock: true)"
		case .public:
			"@Instantiable(generateMock: .public)"
		case .listed:
			"@Instantiable"
		}
	}

	/// The file the tool generates for each module in a cell of `layout` whose caller is `caller`.
	private static func expectedFiles(of layout: Layout, caller: GraphFuzzerCallingMockCell.Caller) -> [String: String] {
		let app = switch caller {
		case .internal, .listed:
			expectedInternalApp(of: layout)
		case .public:
			expectedPublicApp(of: layout)
		}
		return ["Core": expectedCore(of: layout), "Mid": expectedMid(of: layout), "App": app]
	}

	/// The file the tool generates for `Core` in a cell of `layout`, for every caller kind.
	private static func expectedCore(of layout: Layout) -> String {
		switch layout {
		case .fillInstantiatesIt:
			generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Page {
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
			    ) -> Page {
			        Page.__safeDI_mock(serviceBuilder: .init(__safeDI_noScope: serviceBuilder))
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        serviceBuilder __safeDI_serviceBuilder: Page.SafeDIMockScope_Service.__safeDI_Builder<any Service>
			    ) -> Page {
			        let service: any Service = __safeDI_serviceBuilder.service(SafeDIMockScope_Service.service_Values())
			        return Page(service: service)
			    }
			}

			extension Page {
			    public enum __safeDI_Page_mock_4A57B09DFB8A9D2C {}
			}
			#endif
			"""
		case .siblingPlacesFillInstantiatesIt:
			generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Page {
			    nonisolated public enum SafeDIMockScope_Logger {
			        nonisolated public struct logger_Values {
			            public let service: any Service
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let logger: (logger_Values) -> __safeDI_Built

			            public init(logger: @escaping (logger_Values) -> __safeDI_Built) {
			                self.logger = logger
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(logger: { _ in __safeDI_builder() })
			            }
			        }
			    }

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
			        loggerBuilder: @escaping () -> any Logger,
			        serviceBuilder: @escaping () -> any Service
			    ) -> Page {
			        Page.__safeDI_mock(loggerBuilder: .init(__safeDI_noScope: loggerBuilder), serviceBuilder: .init(__safeDI_noScope: serviceBuilder))
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        loggerBuilder __safeDI_loggerBuilder: Page.SafeDIMockScope_Logger.__safeDI_Builder<any Logger>,
			        serviceBuilder __safeDI_serviceBuilder: Page.SafeDIMockScope_Service.__safeDI_Builder<any Service>
			    ) -> Page {
			        let service: any Service = __safeDI_serviceBuilder.service(SafeDIMockScope_Service.service_Values())
			        let logger: any Logger = __safeDI_loggerBuilder.logger(SafeDIMockScope_Logger.logger_Values(service: service))
			        return Page(service: service, logger: logger)
			    }
			}

			extension Page {
			    public enum __safeDI_Page_mock_D554EC7204DBF437 {}
			}
			#endif
			"""
		case .calledMocksOwnPlacesFillInstantiatesIt:
			generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Page {
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
			    ) -> Page {
			        Page.__safeDI_mock(serviceBuilder: .init(__safeDI_noScope: serviceBuilder))
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        serviceBuilder __safeDI_serviceBuilder: Page.SafeDIMockScope_Service.__safeDI_Builder<any Service>
			    ) -> Page {
			        let service: any Service = __safeDI_serviceBuilder.service(SafeDIMockScope_Service.service_Values())
			        return Page(service: service)
			    }
			}

			extension Page {
			    public enum __safeDI_Page_mock_4A57B09DFB8A9D2C {}
			}
			#endif
			"""
		case .nestedCallsFillInstantiatesIt:
			generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Chapter {
			    nonisolated public enum SafeDIMockScope_Store {
			        nonisolated public struct store_Values {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let store: (store_Values) -> __safeDI_Built

			            public init(store: @escaping (store_Values) -> __safeDI_Built) {
			                self.store = store
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(store: { _ in __safeDI_builder() })
			            }
			        }
			    }

			    public static func mock(
			        storeBuilder: @escaping () -> any Store
			    ) -> Chapter {
			        Chapter.__safeDI_mock(storeBuilder: .init(__safeDI_noScope: storeBuilder))
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        storeBuilder __safeDI_storeBuilder: Chapter.SafeDIMockScope_Store.__safeDI_Builder<any Store>
			    ) -> Chapter {
			        let store: any Store = __safeDI_storeBuilder.store(SafeDIMockScope_Store.store_Values())
			        return Chapter(store: store)
			    }
			}

			extension Chapter {
			    public enum __safeDI_Chapter_mock_759F0D6BCCE8B912 {}
			}
			#endif

			#if DEBUG
			extension Page {
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
			    ) -> Page {
			        Page.__safeDI_mock(serviceBuilder: .init(__safeDI_noScope: serviceBuilder))
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        serviceBuilder __safeDI_serviceBuilder: Page.SafeDIMockScope_Service.__safeDI_Builder<any Service>
			    ) -> Page {
			        let service: any Service = __safeDI_serviceBuilder.service(SafeDIMockScope_Service.service_Values())
			        return Page(service: service)
			    }
			}

			extension Page {
			    public enum __safeDI_Page_mock_4A57B09DFB8A9D2C {}
			}
			#endif
			"""
		case .fillAroundNestedCallInstantiatesIt:
			generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Chapter {
			    nonisolated public enum SafeDIMockScope_Store {
			        nonisolated public struct store_Values {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let store: (store_Values) -> __safeDI_Built

			            public init(store: @escaping (store_Values) -> __safeDI_Built) {
			                self.store = store
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(store: { _ in __safeDI_builder() })
			            }
			        }
			    }

			    public static func mock(
			        storeBuilder: @escaping () -> any Store
			    ) -> Chapter {
			        Chapter.__safeDI_mock(storeBuilder: .init(__safeDI_noScope: storeBuilder))
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        storeBuilder __safeDI_storeBuilder: Chapter.SafeDIMockScope_Store.__safeDI_Builder<any Store>
			    ) -> Chapter {
			        let store: any Store = __safeDI_storeBuilder.store(SafeDIMockScope_Store.store_Values())
			        return Chapter(store: store)
			    }
			}

			extension Chapter {
			    public enum __safeDI_Chapter_mock_759F0D6BCCE8B912 {}
			}
			#endif

			#if DEBUG
			extension Page {
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
			    ) -> Page {
			        Page.__safeDI_mock(serviceBuilder: .init(__safeDI_noScope: serviceBuilder))
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        serviceBuilder __safeDI_serviceBuilder: Page.SafeDIMockScope_Service.__safeDI_Builder<any Service>
			    ) -> Page {
			        let service: any Service = __safeDI_serviceBuilder.service(SafeDIMockScope_Service.service_Values())
			        return Page(service: service)
			    }
			}

			extension Page {
			    public enum __safeDI_Page_mock_4A57B09DFB8A9D2C {}
			}
			#endif
			"""
		case .fillCallsCalledTypeItselfBesideUncalledHolder:
			generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Page {
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
			    ) -> Page {
			        Page.__safeDI_mock(serviceBuilder: .init(__safeDI_noScope: serviceBuilder))
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        serviceBuilder __safeDI_serviceBuilder: Page.SafeDIMockScope_Service.__safeDI_Builder<any Service>
			    ) -> Page {
			        let service: any Service = __safeDI_serviceBuilder.service(SafeDIMockScope_Service.service_Values())
			        return Page(service: service)
			    }
			}

			extension Page {
			    public enum __safeDI_Page_mock_4A57B09DFB8A9D2C {}
			}
			#endif
			"""
		}
	}

	/// The file the tool generates for `Mid` in a cell of `layout`, for every caller kind.
	private static func expectedMid(of layout: Layout) -> String {
		switch layout {
		case .fillInstantiatesIt:
			generatedFileHeader + """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Book {
			    nonisolated public enum SafeDIMockScope_Service {
			        nonisolated public struct pageBuilder_Values: Sendable {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let pageBuilder: (pageBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>

			            public init(pageBuilder: @escaping (pageBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>) {
			                self.pageBuilder = pageBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(pageBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init() {}
			    }

			    public static func mock(
			        serviceBuilder: @escaping () -> any Service,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Book {
			        Book.__safeDI_mock(serviceBuilder: .init(__safeDI_noScope: serviceBuilder), safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        serviceBuilder __safeDI_serviceBuilder: Book.SafeDIMockScope_Service.__safeDI_Builder<any Service>,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Book {
			        _ = Page.__safeDI_Page_mock_4A57B09DFB8A9D2C.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
			        func __safeDI_pageBuilder() -> Page {
			            Page.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder.pageBuilder(SafeDIMockScope_Service.pageBuilder_Values()))
			        }
			        let pageBuilder = Instantiator<Page>(__safeDI_pageBuilder)
			        return Book(pageBuilder: pageBuilder)
			    }
			}

			extension Book {
			    public enum __safeDI_Book_mock_00BE9B499BC3E7F2 {}
			}
			#endif
			"""
		case .siblingPlacesFillInstantiatesIt:
			generatedFileHeader + """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Book {
			    nonisolated public enum SafeDIMockScope_Logger {
			        nonisolated public struct pageBuilder_Values: Sendable {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let pageBuilder: (pageBuilder_Values) -> Page.SafeDIMockScope_Logger.__safeDI_Builder<__safeDI_Built>

			            public init(pageBuilder: @escaping (pageBuilder_Values) -> Page.SafeDIMockScope_Logger.__safeDI_Builder<__safeDI_Built>) {
			                self.pageBuilder = pageBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(pageBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			            }
			        }
			    }

			    nonisolated public enum SafeDIMockScope_Service {
			        nonisolated public struct pageBuilder_Values: Sendable {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let pageBuilder: (pageBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>

			            public init(pageBuilder: @escaping (pageBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>) {
			                self.pageBuilder = pageBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(pageBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init() {}
			    }

			    public static func mock(
			        loggerBuilder: @escaping () -> any Logger,
			        serviceBuilder: @escaping () -> any Service,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Book {
			        Book.__safeDI_mock(loggerBuilder: .init(__safeDI_noScope: loggerBuilder), serviceBuilder: .init(__safeDI_noScope: serviceBuilder), safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        loggerBuilder __safeDI_loggerBuilder: Book.SafeDIMockScope_Logger.__safeDI_Builder<any Logger>,
			        serviceBuilder __safeDI_serviceBuilder: Book.SafeDIMockScope_Service.__safeDI_Builder<any Service>,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Book {
			        _ = Page.__safeDI_Page_mock_D554EC7204DBF437.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
			        func __safeDI_pageBuilder() -> Page {
			            Page.__safeDI_mock(loggerBuilder: __safeDI_loggerBuilder.pageBuilder(SafeDIMockScope_Logger.pageBuilder_Values()), serviceBuilder: __safeDI_serviceBuilder.pageBuilder(SafeDIMockScope_Service.pageBuilder_Values()))
			        }
			        let pageBuilder = Instantiator<Page>(__safeDI_pageBuilder)
			        return Book(pageBuilder: pageBuilder)
			    }
			}

			extension Book {
			    public enum __safeDI_Book_mock_BB5F55D5B8AAE3B1 {}
			}
			#endif
			"""
		case .calledMocksOwnPlacesFillInstantiatesIt:
			generatedFileHeader + """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Book {
			    nonisolated public enum SafeDIMockScope_Service {
			        nonisolated public struct pageBuilder_Values: Sendable {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let pageBuilder: (pageBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>

			            public init(pageBuilder: @escaping (pageBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>) {
			                self.pageBuilder = pageBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(pageBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			            }
			        }
			    }

			    nonisolated public enum SafeDIMockScope_Store {
			        nonisolated public struct store_Values {
			            public let pageBuilder: Instantiator<Page>
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let store: (store_Values) -> __safeDI_Built

			            public init(store: @escaping (store_Values) -> __safeDI_Built) {
			                self.store = store
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(store: { _ in __safeDI_builder() })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init() {}
			    }

			    // SafeDI counts `Store` as `public`: no module it reads declares it narrower. If `Store` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    public static func mock(
			        serviceBuilder: @escaping () -> any Service,
			        storeBuilder: @escaping () -> any Store,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Book {
			        Book.__safeDI_mock(serviceBuilder: .init(__safeDI_noScope: serviceBuilder), storeBuilder: .init(__safeDI_noScope: storeBuilder), safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        serviceBuilder __safeDI_serviceBuilder: Book.SafeDIMockScope_Service.__safeDI_Builder<any Service>,
			        storeBuilder __safeDI_storeBuilder: Book.SafeDIMockScope_Store.__safeDI_Builder<any Store>,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Book {
			        _ = Page.__safeDI_Page_mock_4A57B09DFB8A9D2C.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
			        func __safeDI_pageBuilder() -> Page {
			            Page.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder.pageBuilder(SafeDIMockScope_Service.pageBuilder_Values()))
			        }
			        let pageBuilder = Instantiator<Page>(__safeDI_pageBuilder)
			        let store: any Store = __safeDI_storeBuilder.store(SafeDIMockScope_Store.store_Values(pageBuilder: pageBuilder))
			        return Book(pageBuilder: pageBuilder, store: store)
			    }
			}

			extension Book {
			    public enum __safeDI_Book_mock_07F50A152F8D05E1 {}
			}
			#endif
			"""
		case .nestedCallsFillInstantiatesIt:
			generatedFileHeader + """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Book {
			    nonisolated public enum SafeDIMockScope_Service {
			        nonisolated public struct pageBuilder_Values: Sendable {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let pageBuilder: (pageBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>

			            public init(pageBuilder: @escaping (pageBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>) {
			                self.pageBuilder = pageBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(pageBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init() {}
			    }

			    public static func mock(
			        serviceBuilder: @escaping () -> any Service,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Book {
			        Book.__safeDI_mock(serviceBuilder: .init(__safeDI_noScope: serviceBuilder), safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        serviceBuilder __safeDI_serviceBuilder: Book.SafeDIMockScope_Service.__safeDI_Builder<any Service>,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Book {
			        _ = Page.__safeDI_Page_mock_4A57B09DFB8A9D2C.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
			        func __safeDI_pageBuilder() -> Page {
			            Page.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder.pageBuilder(SafeDIMockScope_Service.pageBuilder_Values()))
			        }
			        let pageBuilder = Instantiator<Page>(__safeDI_pageBuilder)
			        return Book(pageBuilder: pageBuilder)
			    }
			}

			extension Book {
			    public enum __safeDI_Book_mock_00BE9B499BC3E7F2 {}
			}
			#endif
			"""
		case .fillAroundNestedCallInstantiatesIt:
			generatedFileHeader + """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Book {
			    nonisolated public enum SafeDIMockScope_Service {
			        nonisolated public struct pageBuilder_Values: Sendable {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let pageBuilder: (pageBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>

			            public init(pageBuilder: @escaping (pageBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>) {
			                self.pageBuilder = pageBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(pageBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init() {}
			    }

			    public static func mock(
			        serviceBuilder: @escaping () -> any Service,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Book {
			        Book.__safeDI_mock(serviceBuilder: .init(__safeDI_noScope: serviceBuilder), safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        serviceBuilder __safeDI_serviceBuilder: Book.SafeDIMockScope_Service.__safeDI_Builder<any Service>,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Book {
			        _ = Page.__safeDI_Page_mock_4A57B09DFB8A9D2C.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
			        func __safeDI_pageBuilder() -> Page {
			            Page.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder.pageBuilder(SafeDIMockScope_Service.pageBuilder_Values()))
			        }
			        let pageBuilder = Instantiator<Page>(__safeDI_pageBuilder)
			        return Book(pageBuilder: pageBuilder)
			    }
			}

			extension Book {
			    public enum __safeDI_Book_mock_00BE9B499BC3E7F2 {}
			}
			#endif
			"""
		case .fillCallsCalledTypeItselfBesideUncalledHolder:
			generatedFileHeader + """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Book {
			    nonisolated public enum SafeDIMockScope_Service {
			        nonisolated public struct pageBuilder_Values: Sendable {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let pageBuilder: (pageBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>

			            public init(pageBuilder: @escaping (pageBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>) {
			                self.pageBuilder = pageBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(pageBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init() {}
			    }

			    public static func mock(
			        serviceBuilder: @escaping () -> any Service,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Book {
			        Book.__safeDI_mock(serviceBuilder: .init(__safeDI_noScope: serviceBuilder), safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        serviceBuilder __safeDI_serviceBuilder: Book.SafeDIMockScope_Service.__safeDI_Builder<any Service>,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Book {
			        _ = Page.__safeDI_Page_mock_4A57B09DFB8A9D2C.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
			        func __safeDI_pageBuilder() -> Page {
			            Page.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder.pageBuilder(SafeDIMockScope_Service.pageBuilder_Values()))
			        }
			        let pageBuilder = Instantiator<Page>(__safeDI_pageBuilder)
			        return Book(pageBuilder: pageBuilder)
			    }
			}

			extension Book {
			    public enum __safeDI_Book_mock_00BE9B499BC3E7F2 {}
			}
			#endif
			"""
		}
	}

	/// The file the tool generates for `App` in a cell of `layout` whose caller is internal or listed.
	private static func expectedInternalApp(of layout: Layout) -> String {
		switch layout {
		case .fillInstantiatesIt:
			generatedFileHeader + """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(Mid)
			import Mid
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            page: ((@escaping () -> any Service) -> Page)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                page: page
			            )
			        }

			        var page: ((@escaping () -> any Service) -> Page)? { __safeDI_storage.page }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                page: ((@escaping () -> any Service) -> Page)?
			            ) {
			                self.page = page
			            }

			            let page: ((@escaping () -> any Service) -> Page)?
			        }
			    }

			    static func mock(
			        analyticsBuilder: @escaping () -> any Analytics,
			        serviceBuilder: (() -> any Service)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_page() -> Page {
			            func __safeDI_serviceBuilder_Page_service() -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let analytics: any Analytics = analyticsBuilder()
			                    func __safeDI_book() -> Book {
			                        func __safeDI_serviceBuilder_Book() -> Book.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                            .init(pageBuilder: { _ in __safeDI_serviceBuilder_Page() })
			                        }
			                        return Book.__safeDI_mock(serviceBuilder: serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Book())
			                    }
			                    let book: Book = __safeDI_book()
			                    return DefaultService(analytics: analytics, book: book)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Page() -> Page.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(service: { _ in __safeDI_serviceBuilder_Page_service() })
			            }
			            _ = Page.__safeDI_Page_mock_4A57B09DFB8A9D2C.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
			            return if let safeDIBuilder = safeDIOverrides.page { safeDIBuilder({ if let serviceBuilder { serviceBuilder() } else { __safeDI_serviceBuilder_Page_service() } }) } else { Page.__safeDI_mock(serviceBuilder: serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Page()) }
			        }
			        let page: Page = __safeDI_page()
			        return Screen(page: page)
			    }
			}
			#endif
			"""
		case .siblingPlacesFillInstantiatesIt:
			generatedFileHeader + """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(Mid)
			import Mid
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            page: ((@escaping () -> any Logger, @escaping () -> any Service) -> Page)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                page: page
			            )
			        }

			        var page: ((@escaping () -> any Logger, @escaping () -> any Service) -> Page)? { __safeDI_storage.page }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                page: ((@escaping () -> any Logger, @escaping () -> any Service) -> Page)?
			            ) {
			                self.page = page
			            }

			            let page: ((@escaping () -> any Logger, @escaping () -> any Service) -> Page)?
			        }
			    }

			    static func mock(
			        analyticsBuilder: @escaping () -> any Analytics,
			        loggerBuilder: (() -> any Logger)? = nil,
			        serviceBuilder: (() -> any Service)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_page() -> Page {
			            func __safeDI_loggerBuilder_Page_logger() -> any Logger {
			                func __safeDI_logger() -> DefaultLogger {
			                    let analytics: any Analytics = analyticsBuilder()
			                    return DefaultLogger(analytics: analytics)
			                }
			                let logger: any Logger = __safeDI_logger()
			                return logger
			            }
			            func __safeDI_serviceBuilder_Page_service() -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    func __safeDI_book() -> Book {
			                        func __safeDI_loggerBuilder_Book() -> Book.SafeDIMockScope_Logger.__safeDI_Builder<any Logger> {
			                            .init(pageBuilder: { _ in __safeDI_loggerBuilder_Page() })
			                        }
			                        func __safeDI_serviceBuilder_Book() -> Book.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                            .init(pageBuilder: { _ in __safeDI_serviceBuilder_Page() })
			                        }
			                        return Book.__safeDI_mock(loggerBuilder: loggerBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_loggerBuilder_Book(), serviceBuilder: serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Book())
			                    }
			                    let book: Book = __safeDI_book()
			                    return DefaultService(book: book)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_loggerBuilder_Page() -> Page.SafeDIMockScope_Logger.__safeDI_Builder<any Logger> {
			                .init(logger: { _ in __safeDI_loggerBuilder_Page_logger() })
			            }
			            func __safeDI_serviceBuilder_Page() -> Page.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(service: { _ in __safeDI_serviceBuilder_Page_service() })
			            }
			            _ = Page.__safeDI_Page_mock_D554EC7204DBF437.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
			            return if let safeDIBuilder = safeDIOverrides.page { safeDIBuilder({ if let loggerBuilder { loggerBuilder() } else { __safeDI_loggerBuilder_Page_logger() } }, { if let serviceBuilder { serviceBuilder() } else { __safeDI_serviceBuilder_Page_service() } }) } else { Page.__safeDI_mock(loggerBuilder: loggerBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_loggerBuilder_Page(), serviceBuilder: serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Page()) }
			        }
			        let page: Page = __safeDI_page()
			        return Screen(page: page)
			    }
			}
			#endif
			"""
		case .calledMocksOwnPlacesFillInstantiatesIt:
			generatedFileHeader + """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(Mid)
			import Mid
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            page: ((@escaping () -> any Service) -> Page)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                page: page
			            )
			        }

			        var page: ((@escaping () -> any Service) -> Page)? { __safeDI_storage.page }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                page: ((@escaping () -> any Service) -> Page)?
			            ) {
			                self.page = page
			            }

			            let page: ((@escaping () -> any Service) -> Page)?
			        }
			    }

			    static func mock(
			        analyticsBuilder: @escaping () -> any Analytics,
			        serviceBuilder: (() -> any Service)? = nil,
			        storeBuilder: (() -> any Store)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_page() -> Page {
			            func __safeDI_serviceBuilder_Page_service() -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    func __safeDI_book() -> Book {
			                        func __safeDI_storeBuilder_Book_store(_ scope: Book.SafeDIMockScope_Store.store_Values) -> any Store {
			                            func __safeDI_store() -> DefaultStore {
			                                let analytics: any Analytics = analyticsBuilder()
			                                return DefaultStore(analytics: analytics)
			                            }
			                            let store: any Store = __safeDI_store()
			                            return store
			                        }
			                        func __safeDI_serviceBuilder_Book() -> Book.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                            .init(pageBuilder: { _ in __safeDI_serviceBuilder_Page() })
			                        }
			                        func __safeDI_storeBuilder_Book() -> Book.SafeDIMockScope_Store.__safeDI_Builder<any Store> {
			                            .init(store: { scope in __safeDI_storeBuilder_Book_store(scope) })
			                        }
			                        return Book.__safeDI_mock(serviceBuilder: serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Book(), storeBuilder: storeBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_storeBuilder_Book())
			                    }
			                    let book: Book = __safeDI_book()
			                    return DefaultService(book: book)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Page() -> Page.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(service: { _ in __safeDI_serviceBuilder_Page_service() })
			            }
			            _ = Page.__safeDI_Page_mock_4A57B09DFB8A9D2C.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
			            return if let safeDIBuilder = safeDIOverrides.page { safeDIBuilder({ if let serviceBuilder { serviceBuilder() } else { __safeDI_serviceBuilder_Page_service() } }) } else { Page.__safeDI_mock(serviceBuilder: serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Page()) }
			        }
			        let page: Page = __safeDI_page()
			        return Screen(page: page)
			    }
			}
			#endif
			"""
		case .nestedCallsFillInstantiatesIt:
			generatedFileHeader + """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(Mid)
			import Mid
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            page: ((@escaping () -> any Service) -> Page)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                page: page
			            )
			        }

			        var page: ((@escaping () -> any Service) -> Page)? { __safeDI_storage.page }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                page: ((@escaping () -> any Service) -> Page)?
			            ) {
			                self.page = page
			            }

			            let page: ((@escaping () -> any Service) -> Page)?
			        }
			    }

			    static func mock(
			        analyticsBuilder: @escaping () -> any Analytics,
			        serviceBuilder: (() -> any Service)? = nil,
			        storeBuilder: (() -> any Store)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_page() -> Page {
			            func __safeDI_serviceBuilder_Page_service() -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    func __safeDI_chapter() -> Chapter {
			                        func __safeDI_storeBuilder_Chapter_store() -> any Store {
			                            func __safeDI_store() -> DefaultStore {
			                                let analytics: any Analytics = analyticsBuilder()
			                                func __safeDI_book() -> Book {
			                                    func __safeDI_serviceBuilder_Book() -> Book.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                                        .init(pageBuilder: { _ in __safeDI_serviceBuilder_Page() })
			                                    }
			                                    return Book.__safeDI_mock(serviceBuilder: serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Book())
			                                }
			                                let book: Book = __safeDI_book()
			                                return DefaultStore(analytics: analytics, book: book)
			                            }
			                            let store: any Store = __safeDI_store()
			                            return store
			                        }
			                        func __safeDI_storeBuilder_Chapter() -> Chapter.SafeDIMockScope_Store.__safeDI_Builder<any Store> {
			                            .init(store: { _ in __safeDI_storeBuilder_Chapter_store() })
			                        }
			                        return Chapter.__safeDI_mock(storeBuilder: storeBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_storeBuilder_Chapter())
			                    }
			                    let chapter: Chapter = __safeDI_chapter()
			                    return DefaultService(chapter: chapter)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Page() -> Page.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(service: { _ in __safeDI_serviceBuilder_Page_service() })
			            }
			            _ = Page.__safeDI_Page_mock_4A57B09DFB8A9D2C.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
			            return if let safeDIBuilder = safeDIOverrides.page { safeDIBuilder({ if let serviceBuilder { serviceBuilder() } else { __safeDI_serviceBuilder_Page_service() } }) } else { Page.__safeDI_mock(serviceBuilder: serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Page()) }
			        }
			        let page: Page = __safeDI_page()
			        return Screen(page: page)
			    }
			}
			#endif
			"""
		case .fillAroundNestedCallInstantiatesIt:
			generatedFileHeader + """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(Mid)
			import Mid
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            page: ((@escaping () -> any Service) -> Page)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                page: page
			            )
			        }

			        var page: ((@escaping () -> any Service) -> Page)? { __safeDI_storage.page }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                page: ((@escaping () -> any Service) -> Page)?
			            ) {
			                self.page = page
			            }

			            let page: ((@escaping () -> any Service) -> Page)?
			        }
			    }

			    static func mock(
			        analyticsBuilder: @escaping () -> any Analytics,
			        serviceBuilder: (() -> any Service)? = nil,
			        storeBuilder: (() -> any Store)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_page() -> Page {
			            func __safeDI_serviceBuilder_Page_service() -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let analytics: any Analytics = analyticsBuilder()
			                    func __safeDI_chapter() -> Chapter {
			                        func __safeDI_storeBuilder_Chapter_store() -> any Store {
			                            func __safeDI_store() -> DefaultStore {
			                                func __safeDI_book() -> Book {
			                                    func __safeDI_serviceBuilder_Book() -> Book.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                                        .init(pageBuilder: { _ in __safeDI_serviceBuilder_Page() })
			                                    }
			                                    return Book.__safeDI_mock(serviceBuilder: serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Book())
			                                }
			                                let book: Book = __safeDI_book()
			                                return DefaultStore(book: book)
			                            }
			                            let store: any Store = __safeDI_store()
			                            return store
			                        }
			                        func __safeDI_storeBuilder_Chapter() -> Chapter.SafeDIMockScope_Store.__safeDI_Builder<any Store> {
			                            .init(store: { _ in __safeDI_storeBuilder_Chapter_store() })
			                        }
			                        return Chapter.__safeDI_mock(storeBuilder: storeBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_storeBuilder_Chapter())
			                    }
			                    let chapter: Chapter = __safeDI_chapter()
			                    return DefaultService(analytics: analytics, chapter: chapter)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Page() -> Page.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(service: { _ in __safeDI_serviceBuilder_Page_service() })
			            }
			            _ = Page.__safeDI_Page_mock_4A57B09DFB8A9D2C.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
			            return if let safeDIBuilder = safeDIOverrides.page { safeDIBuilder({ if let serviceBuilder { serviceBuilder() } else { __safeDI_serviceBuilder_Page_service() } }) } else { Page.__safeDI_mock(serviceBuilder: serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Page()) }
			        }
			        let page: Page = __safeDI_page()
			        return Screen(page: page)
			    }
			}
			#endif
			"""
		case .fillCallsCalledTypeItselfBesideUncalledHolder:
			generatedFileHeader + """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(Mid)
			import Mid
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            page: ((@escaping () -> any Service) -> Page)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                page: page
			            )
			        }

			        var page: ((@escaping () -> any Service) -> Page)? { __safeDI_storage.page }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                page: ((@escaping () -> any Service) -> Page)?
			            ) {
			                self.page = page
			            }

			            let page: ((@escaping () -> any Service) -> Page)?
			        }
			    }

			    static func mock(
			        analyticsBuilder: @escaping () -> any Analytics,
			        serviceBuilder: (() -> any Service)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_page() -> Page {
			            func __safeDI_serviceBuilder_Page_service() -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let analytics: any Analytics = analyticsBuilder()
			                    func __safeDI_pageBuilder() -> Page {
			                        Page.__safeDI_mock(serviceBuilder: serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Page())
			                    }
			                    let pageBuilder = Instantiator<Page>(__safeDI_pageBuilder)
			                    return DefaultService(analytics: analytics, pageBuilder: pageBuilder)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Page() -> Page.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(service: { _ in __safeDI_serviceBuilder_Page_service() })
			            }
			            _ = Page.__safeDI_Page_mock_4A57B09DFB8A9D2C.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
			            return if let safeDIBuilder = safeDIOverrides.page { safeDIBuilder({ if let serviceBuilder { serviceBuilder() } else { __safeDI_serviceBuilder_Page_service() } }) } else { Page.__safeDI_mock(serviceBuilder: serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Page()) }
			        }
			        let page: Page = __safeDI_page()
			        return Screen(page: page)
			    }
			}
			#endif
			"""
		}
	}

	/// The file the tool generates for `App` in a cell of `layout` whose caller is `.public`.
	private static func expectedPublicApp(of layout: Layout) -> String {
		switch layout {
		case .fillInstantiatesIt:
			generatedFileHeader + """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(Mid)
			import Mid
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Screen {
			    nonisolated public enum SafeDIMockScope_Analytics {
			        nonisolated public struct page_serviceBuilder_Values {}

			        nonisolated public enum DefaultService_Scope {
			            nonisolated public struct analytics_Values {
			                public let book: Book
			            }

			            nonisolated public struct book_serviceBuilder_Values {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let analytics: (analytics_Values) -> __safeDI_Built
			                public let book_serviceBuilder: (book_serviceBuilder_Values) -> Book.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			                public init(analytics: @escaping (analytics_Values) -> __safeDI_Built, book_serviceBuilder: @escaping (book_serviceBuilder_Values) -> Book.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                    self.analytics = analytics
			                    self.book_serviceBuilder = book_serviceBuilder
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(analytics: { _ in __safeDI_builder() }, book_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			                }
			            }
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let page_serviceBuilder: (page_serviceBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(page_serviceBuilder: @escaping (page_serviceBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.page_serviceBuilder = page_serviceBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(page_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init() {}
			    }

			    public static func mock(
			        analyticsBuilder: @escaping () -> any Analytics,
			        serviceBuilder: (() -> any Service)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        Screen.__safeDI_mock(analyticsBuilder: .init(__safeDI_noScope: analyticsBuilder), serviceBuilder: serviceBuilder, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        analyticsBuilder __safeDI_analyticsBuilder: Screen.SafeDIMockScope_Analytics.__safeDI_Builder<any Analytics>,
			        serviceBuilder __safeDI_serviceBuilder: (() -> any Service)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        let __safeDI_analyticsBuilder_page_serviceBuilder = __safeDI_analyticsBuilder.page_serviceBuilder(SafeDIMockScope_Analytics.page_serviceBuilder_Values())
			        func __safeDI_page() -> Page {
			            func __safeDI_serviceBuilder_Page_service(_ scope: Page.SafeDIMockScope_Service.service_Values, __safeDI_page_serviceBuilder: SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let __safeDI_analyticsBuilder_book_serviceBuilder = __safeDI_page_serviceBuilder.book_serviceBuilder(SafeDIMockScope_Analytics.DefaultService_Scope.book_serviceBuilder_Values())
			                    func __safeDI_book() -> Book {
			                        func __safeDI_serviceBuilder_Book(up: Book.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>>) -> Book.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                            .init(pageBuilder: { values in __safeDI_serviceBuilder_Page(up: up.pageBuilder(values)) })
			                        }
			                        return Book.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Book(up: __safeDI_analyticsBuilder_book_serviceBuilder))
			                    }
			                    let book: Book = __safeDI_book()
			                    let analytics: any Analytics = __safeDI_page_serviceBuilder.analytics(SafeDIMockScope_Analytics.DefaultService_Scope.analytics_Values(book: book))
			                    return DefaultService(analytics: analytics, book: book)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Page(up: Page.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>>) -> Page.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(service: { scope in __safeDI_serviceBuilder_Page_service(scope, __safeDI_page_serviceBuilder: up.service(scope)) })
			            }
			            _ = Page.__safeDI_Page_mock_4A57B09DFB8A9D2C.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
			            return Page.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Page(up: __safeDI_analyticsBuilder_page_serviceBuilder))
			        }
			        let page: Page = __safeDI_page()
			        return Screen(page: page)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_CAB1C39683F7E072 {}
			}
			#endif
			"""
		case .siblingPlacesFillInstantiatesIt:
			generatedFileHeader + """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(Mid)
			import Mid
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Screen {
			    nonisolated public enum SafeDIMockScope_Analytics {
			        nonisolated public struct page_loggerBuilder_Values {}

			        nonisolated public struct page_serviceBuilder_Values {}

			        nonisolated public enum DefaultLogger_Scope {
			            nonisolated public struct analytics_Values {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let analytics: (analytics_Values) -> __safeDI_Built

			                public init(analytics: @escaping (analytics_Values) -> __safeDI_Built) {
			                    self.analytics = analytics
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(analytics: { _ in __safeDI_builder() })
			                }
			            }
			        }

			        nonisolated public enum DefaultService_Scope {
			            nonisolated public struct book_loggerBuilder_Values {}

			            nonisolated public struct book_serviceBuilder_Values {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let book_loggerBuilder: (book_loggerBuilder_Values) -> Book.SafeDIMockScope_Logger.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultLogger_Scope.__safeDI_Builder<__safeDI_Built>>
			                public let book_serviceBuilder: (book_serviceBuilder_Values) -> Book.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			                public init(book_loggerBuilder: @escaping (book_loggerBuilder_Values) -> Book.SafeDIMockScope_Logger.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultLogger_Scope.__safeDI_Builder<__safeDI_Built>>, book_serviceBuilder: @escaping (book_serviceBuilder_Values) -> Book.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                    self.book_loggerBuilder = book_loggerBuilder
			                    self.book_serviceBuilder = book_serviceBuilder
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(book_loggerBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }, book_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			                }
			            }
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let page_loggerBuilder: (page_loggerBuilder_Values) -> Page.SafeDIMockScope_Logger.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultLogger_Scope.__safeDI_Builder<__safeDI_Built>>
			            public let page_serviceBuilder: (page_serviceBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(page_loggerBuilder: @escaping (page_loggerBuilder_Values) -> Page.SafeDIMockScope_Logger.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultLogger_Scope.__safeDI_Builder<__safeDI_Built>>, page_serviceBuilder: @escaping (page_serviceBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.page_loggerBuilder = page_loggerBuilder
			                self.page_serviceBuilder = page_serviceBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(page_loggerBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }, page_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init() {}
			    }

			    public static func mock(
			        analyticsBuilder: @escaping () -> any Analytics,
			        loggerBuilder: (() -> any Logger)? = nil,
			        serviceBuilder: (() -> any Service)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        Screen.__safeDI_mock(analyticsBuilder: .init(__safeDI_noScope: analyticsBuilder), loggerBuilder: loggerBuilder, serviceBuilder: serviceBuilder, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        analyticsBuilder __safeDI_analyticsBuilder: Screen.SafeDIMockScope_Analytics.__safeDI_Builder<any Analytics>,
			        loggerBuilder __safeDI_loggerBuilder: (() -> any Logger)? = nil,
			        serviceBuilder __safeDI_serviceBuilder: (() -> any Service)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        let __safeDI_analyticsBuilder_page_loggerBuilder = __safeDI_analyticsBuilder.page_loggerBuilder(SafeDIMockScope_Analytics.page_loggerBuilder_Values())
			        let __safeDI_analyticsBuilder_page_serviceBuilder = __safeDI_analyticsBuilder.page_serviceBuilder(SafeDIMockScope_Analytics.page_serviceBuilder_Values())
			        func __safeDI_page() -> Page {
			            func __safeDI_serviceBuilder_Page_service(_ scope: Page.SafeDIMockScope_Service.service_Values, __safeDI_page_serviceBuilder: SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let __safeDI_analyticsBuilder_book_loggerBuilder = __safeDI_page_serviceBuilder.book_loggerBuilder(SafeDIMockScope_Analytics.DefaultService_Scope.book_loggerBuilder_Values())
			                    let __safeDI_analyticsBuilder_book_serviceBuilder = __safeDI_page_serviceBuilder.book_serviceBuilder(SafeDIMockScope_Analytics.DefaultService_Scope.book_serviceBuilder_Values())
			                    func __safeDI_book() -> Book {
			                        func __safeDI_loggerBuilder_Book(up: Book.SafeDIMockScope_Logger.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultLogger_Scope.__safeDI_Builder<any Analytics>>) -> Book.SafeDIMockScope_Logger.__safeDI_Builder<any Logger> {
			                            .init(pageBuilder: { values in __safeDI_loggerBuilder_Page(up: up.pageBuilder(values)) })
			                        }
			                        func __safeDI_serviceBuilder_Book(up: Book.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>>) -> Book.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                            .init(pageBuilder: { values in __safeDI_serviceBuilder_Page(up: up.pageBuilder(values)) })
			                        }
			                        return Book.__safeDI_mock(loggerBuilder: __safeDI_loggerBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_loggerBuilder_Book(up: __safeDI_analyticsBuilder_book_loggerBuilder), serviceBuilder: __safeDI_serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Book(up: __safeDI_analyticsBuilder_book_serviceBuilder))
			                    }
			                    let book: Book = __safeDI_book()
			                    return DefaultService(book: book)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_loggerBuilder_Page_logger(_ scope: Page.SafeDIMockScope_Logger.logger_Values, __safeDI_page_loggerBuilder: SafeDIMockScope_Analytics.DefaultLogger_Scope.__safeDI_Builder<any Analytics>) -> any Logger {
			                func __safeDI_logger() -> DefaultLogger {
			                    let analytics: any Analytics = __safeDI_page_loggerBuilder.analytics(SafeDIMockScope_Analytics.DefaultLogger_Scope.analytics_Values())
			                    return DefaultLogger(analytics: analytics)
			                }
			                let logger: any Logger = __safeDI_logger()
			                return logger
			            }
			            func __safeDI_loggerBuilder_Page(up: Page.SafeDIMockScope_Logger.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultLogger_Scope.__safeDI_Builder<any Analytics>>) -> Page.SafeDIMockScope_Logger.__safeDI_Builder<any Logger> {
			                .init(logger: { scope in __safeDI_loggerBuilder_Page_logger(scope, __safeDI_page_loggerBuilder: up.logger(scope)) })
			            }
			            func __safeDI_serviceBuilder_Page(up: Page.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>>) -> Page.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(service: { scope in __safeDI_serviceBuilder_Page_service(scope, __safeDI_page_serviceBuilder: up.service(scope)) })
			            }
			            _ = Page.__safeDI_Page_mock_D554EC7204DBF437.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
			            return Page.__safeDI_mock(loggerBuilder: __safeDI_loggerBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_loggerBuilder_Page(up: __safeDI_analyticsBuilder_page_loggerBuilder), serviceBuilder: __safeDI_serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Page(up: __safeDI_analyticsBuilder_page_serviceBuilder))
			        }
			        let page: Page = __safeDI_page()
			        return Screen(page: page)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_ACC62E339A62491E {}
			}
			#endif
			"""
		case .calledMocksOwnPlacesFillInstantiatesIt:
			generatedFileHeader + """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(Mid)
			import Mid
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Screen {
			    nonisolated public enum SafeDIMockScope_Analytics {
			        nonisolated public struct page_serviceBuilder_Values {}

			        nonisolated public enum DefaultService_Scope {
			            nonisolated public struct book_serviceBuilder_Values {}

			            nonisolated public struct book_storeBuilder_Values {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let book_serviceBuilder: (book_serviceBuilder_Values) -> Book.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>
			                public let book_storeBuilder: (book_storeBuilder_Values) -> Book.SafeDIMockScope_Store.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultStore_Scope.__safeDI_Builder<__safeDI_Built>>

			                public init(book_serviceBuilder: @escaping (book_serviceBuilder_Values) -> Book.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>, book_storeBuilder: @escaping (book_storeBuilder_Values) -> Book.SafeDIMockScope_Store.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultStore_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                    self.book_serviceBuilder = book_serviceBuilder
			                    self.book_storeBuilder = book_storeBuilder
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(book_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }, book_storeBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			                }
			            }
			        }

			        nonisolated public enum DefaultStore_Scope {
			            nonisolated public struct analytics_Values {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let analytics: (analytics_Values) -> __safeDI_Built

			                public init(analytics: @escaping (analytics_Values) -> __safeDI_Built) {
			                    self.analytics = analytics
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(analytics: { _ in __safeDI_builder() })
			                }
			            }
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let page_serviceBuilder: (page_serviceBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(page_serviceBuilder: @escaping (page_serviceBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.page_serviceBuilder = page_serviceBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(page_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init() {}
			    }

			    // SafeDI counts `Store` as `public`: no module it reads declares it narrower. If `Store` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    public static func mock(
			        analyticsBuilder: @escaping () -> any Analytics,
			        serviceBuilder: (() -> any Service)? = nil,
			        storeBuilder: (() -> any Store)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        Screen.__safeDI_mock(analyticsBuilder: .init(__safeDI_noScope: analyticsBuilder), serviceBuilder: serviceBuilder, storeBuilder: storeBuilder, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        analyticsBuilder __safeDI_analyticsBuilder: Screen.SafeDIMockScope_Analytics.__safeDI_Builder<any Analytics>,
			        serviceBuilder __safeDI_serviceBuilder: (() -> any Service)? = nil,
			        storeBuilder __safeDI_storeBuilder: (() -> any Store)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        let __safeDI_analyticsBuilder_page_serviceBuilder = __safeDI_analyticsBuilder.page_serviceBuilder(SafeDIMockScope_Analytics.page_serviceBuilder_Values())
			        func __safeDI_page() -> Page {
			            func __safeDI_serviceBuilder_Page_service(_ scope: Page.SafeDIMockScope_Service.service_Values, __safeDI_page_serviceBuilder: SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let __safeDI_analyticsBuilder_book_serviceBuilder = __safeDI_page_serviceBuilder.book_serviceBuilder(SafeDIMockScope_Analytics.DefaultService_Scope.book_serviceBuilder_Values())
			                    let __safeDI_analyticsBuilder_book_storeBuilder = __safeDI_page_serviceBuilder.book_storeBuilder(SafeDIMockScope_Analytics.DefaultService_Scope.book_storeBuilder_Values())
			                    func __safeDI_book() -> Book {
			                        func __safeDI_storeBuilder_Book_store(_ scope: Book.SafeDIMockScope_Store.store_Values, __safeDI_book_storeBuilder: SafeDIMockScope_Analytics.DefaultStore_Scope.__safeDI_Builder<any Analytics>) -> any Store {
			                            func __safeDI_store() -> DefaultStore {
			                                let analytics: any Analytics = __safeDI_book_storeBuilder.analytics(SafeDIMockScope_Analytics.DefaultStore_Scope.analytics_Values())
			                                return DefaultStore(analytics: analytics)
			                            }
			                            let store: any Store = __safeDI_store()
			                            return store
			                        }
			                        func __safeDI_serviceBuilder_Book(up: Book.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>>) -> Book.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                            .init(pageBuilder: { values in __safeDI_serviceBuilder_Page(up: up.pageBuilder(values)) })
			                        }
			                        func __safeDI_storeBuilder_Book(up: Book.SafeDIMockScope_Store.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultStore_Scope.__safeDI_Builder<any Analytics>>) -> Book.SafeDIMockScope_Store.__safeDI_Builder<any Store> {
			                            .init(store: { scope in __safeDI_storeBuilder_Book_store(scope, __safeDI_book_storeBuilder: up.store(scope)) })
			                        }
			                        return Book.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Book(up: __safeDI_analyticsBuilder_book_serviceBuilder), storeBuilder: __safeDI_storeBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_storeBuilder_Book(up: __safeDI_analyticsBuilder_book_storeBuilder))
			                    }
			                    let book: Book = __safeDI_book()
			                    return DefaultService(book: book)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Page(up: Page.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>>) -> Page.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(service: { scope in __safeDI_serviceBuilder_Page_service(scope, __safeDI_page_serviceBuilder: up.service(scope)) })
			            }
			            _ = Page.__safeDI_Page_mock_4A57B09DFB8A9D2C.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
			            return Page.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Page(up: __safeDI_analyticsBuilder_page_serviceBuilder))
			        }
			        let page: Page = __safeDI_page()
			        return Screen(page: page)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_968BC200719A49F8 {}
			}
			#endif
			"""
		case .nestedCallsFillInstantiatesIt:
			generatedFileHeader + """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(Mid)
			import Mid
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Screen {
			    nonisolated public enum SafeDIMockScope_Analytics {
			        nonisolated public struct page_serviceBuilder_Values {}

			        nonisolated public enum DefaultService_Scope {
			            nonisolated public struct chapter_storeBuilder_Values {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let chapter_storeBuilder: (chapter_storeBuilder_Values) -> Chapter.SafeDIMockScope_Store.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultStore_Scope.__safeDI_Builder<__safeDI_Built>>

			                public init(chapter_storeBuilder: @escaping (chapter_storeBuilder_Values) -> Chapter.SafeDIMockScope_Store.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultStore_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                    self.chapter_storeBuilder = chapter_storeBuilder
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(chapter_storeBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			                }
			            }
			        }

			        nonisolated public enum DefaultStore_Scope {
			            nonisolated public struct analytics_Values {
			                public let book: Book
			            }

			            nonisolated public struct book_serviceBuilder_Values {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let analytics: (analytics_Values) -> __safeDI_Built
			                public let book_serviceBuilder: (book_serviceBuilder_Values) -> Book.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			                public init(analytics: @escaping (analytics_Values) -> __safeDI_Built, book_serviceBuilder: @escaping (book_serviceBuilder_Values) -> Book.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                    self.analytics = analytics
			                    self.book_serviceBuilder = book_serviceBuilder
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(analytics: { _ in __safeDI_builder() }, book_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			                }
			            }
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let page_serviceBuilder: (page_serviceBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(page_serviceBuilder: @escaping (page_serviceBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.page_serviceBuilder = page_serviceBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(page_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init() {}
			    }

			    public static func mock(
			        analyticsBuilder: @escaping () -> any Analytics,
			        serviceBuilder: (() -> any Service)? = nil,
			        storeBuilder: (() -> any Store)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        Screen.__safeDI_mock(analyticsBuilder: .init(__safeDI_noScope: analyticsBuilder), serviceBuilder: serviceBuilder, storeBuilder: storeBuilder, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        analyticsBuilder __safeDI_analyticsBuilder: Screen.SafeDIMockScope_Analytics.__safeDI_Builder<any Analytics>,
			        serviceBuilder __safeDI_serviceBuilder: (() -> any Service)? = nil,
			        storeBuilder __safeDI_storeBuilder: (() -> any Store)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        let __safeDI_analyticsBuilder_page_serviceBuilder = __safeDI_analyticsBuilder.page_serviceBuilder(SafeDIMockScope_Analytics.page_serviceBuilder_Values())
			        func __safeDI_page() -> Page {
			            func __safeDI_serviceBuilder_Page_service(_ scope: Page.SafeDIMockScope_Service.service_Values, __safeDI_page_serviceBuilder: SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let __safeDI_analyticsBuilder_chapter_storeBuilder = __safeDI_page_serviceBuilder.chapter_storeBuilder(SafeDIMockScope_Analytics.DefaultService_Scope.chapter_storeBuilder_Values())
			                    func __safeDI_chapter() -> Chapter {
			                        func __safeDI_storeBuilder_Chapter_store(_ scope: Chapter.SafeDIMockScope_Store.store_Values, __safeDI_chapter_storeBuilder: SafeDIMockScope_Analytics.DefaultStore_Scope.__safeDI_Builder<any Analytics>) -> any Store {
			                            func __safeDI_store() -> DefaultStore {
			                                let __safeDI_analyticsBuilder_book_serviceBuilder = __safeDI_chapter_storeBuilder.book_serviceBuilder(SafeDIMockScope_Analytics.DefaultStore_Scope.book_serviceBuilder_Values())
			                                func __safeDI_book() -> Book {
			                                    func __safeDI_serviceBuilder_Book(up: Book.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>>) -> Book.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                                        .init(pageBuilder: { values in __safeDI_serviceBuilder_Page(up: up.pageBuilder(values)) })
			                                    }
			                                    return Book.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Book(up: __safeDI_analyticsBuilder_book_serviceBuilder))
			                                }
			                                let book: Book = __safeDI_book()
			                                let analytics: any Analytics = __safeDI_chapter_storeBuilder.analytics(SafeDIMockScope_Analytics.DefaultStore_Scope.analytics_Values(book: book))
			                                return DefaultStore(analytics: analytics, book: book)
			                            }
			                            let store: any Store = __safeDI_store()
			                            return store
			                        }
			                        func __safeDI_storeBuilder_Chapter(up: Chapter.SafeDIMockScope_Store.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultStore_Scope.__safeDI_Builder<any Analytics>>) -> Chapter.SafeDIMockScope_Store.__safeDI_Builder<any Store> {
			                            .init(store: { scope in __safeDI_storeBuilder_Chapter_store(scope, __safeDI_chapter_storeBuilder: up.store(scope)) })
			                        }
			                        return Chapter.__safeDI_mock(storeBuilder: __safeDI_storeBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_storeBuilder_Chapter(up: __safeDI_analyticsBuilder_chapter_storeBuilder))
			                    }
			                    let chapter: Chapter = __safeDI_chapter()
			                    return DefaultService(chapter: chapter)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Page(up: Page.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>>) -> Page.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(service: { scope in __safeDI_serviceBuilder_Page_service(scope, __safeDI_page_serviceBuilder: up.service(scope)) })
			            }
			            _ = Page.__safeDI_Page_mock_4A57B09DFB8A9D2C.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
			            return Page.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Page(up: __safeDI_analyticsBuilder_page_serviceBuilder))
			        }
			        let page: Page = __safeDI_page()
			        return Screen(page: page)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_BA8AF8AA6D481ADB {}
			}
			#endif
			"""
		case .fillAroundNestedCallInstantiatesIt:
			generatedFileHeader + """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(Mid)
			import Mid
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Screen {
			    nonisolated public enum SafeDIMockScope_Analytics {
			        nonisolated public struct page_serviceBuilder_Values {}

			        nonisolated public enum DefaultService_Scope {
			            nonisolated public struct analytics_Values {
			                public let chapter: Chapter
			            }

			            nonisolated public struct chapter_storeBuilder_Values {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let analytics: (analytics_Values) -> __safeDI_Built
			                public let chapter_storeBuilder: (chapter_storeBuilder_Values) -> Chapter.SafeDIMockScope_Store.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultStore_Scope.__safeDI_Builder<__safeDI_Built>>

			                public init(analytics: @escaping (analytics_Values) -> __safeDI_Built, chapter_storeBuilder: @escaping (chapter_storeBuilder_Values) -> Chapter.SafeDIMockScope_Store.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultStore_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                    self.analytics = analytics
			                    self.chapter_storeBuilder = chapter_storeBuilder
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(analytics: { _ in __safeDI_builder() }, chapter_storeBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			                }
			            }
			        }

			        nonisolated public enum DefaultStore_Scope {
			            nonisolated public struct book_serviceBuilder_Values {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let book_serviceBuilder: (book_serviceBuilder_Values) -> Book.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			                public init(book_serviceBuilder: @escaping (book_serviceBuilder_Values) -> Book.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                    self.book_serviceBuilder = book_serviceBuilder
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(book_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			                }
			            }
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let page_serviceBuilder: (page_serviceBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(page_serviceBuilder: @escaping (page_serviceBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.page_serviceBuilder = page_serviceBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(page_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init() {}
			    }

			    public static func mock(
			        analyticsBuilder: @escaping () -> any Analytics,
			        serviceBuilder: (() -> any Service)? = nil,
			        storeBuilder: (() -> any Store)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        Screen.__safeDI_mock(analyticsBuilder: .init(__safeDI_noScope: analyticsBuilder), serviceBuilder: serviceBuilder, storeBuilder: storeBuilder, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        analyticsBuilder __safeDI_analyticsBuilder: Screen.SafeDIMockScope_Analytics.__safeDI_Builder<any Analytics>,
			        serviceBuilder __safeDI_serviceBuilder: (() -> any Service)? = nil,
			        storeBuilder __safeDI_storeBuilder: (() -> any Store)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        let __safeDI_analyticsBuilder_page_serviceBuilder = __safeDI_analyticsBuilder.page_serviceBuilder(SafeDIMockScope_Analytics.page_serviceBuilder_Values())
			        func __safeDI_page() -> Page {
			            func __safeDI_serviceBuilder_Page_service(_ scope: Page.SafeDIMockScope_Service.service_Values, __safeDI_page_serviceBuilder: SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let __safeDI_analyticsBuilder_chapter_storeBuilder = __safeDI_page_serviceBuilder.chapter_storeBuilder(SafeDIMockScope_Analytics.DefaultService_Scope.chapter_storeBuilder_Values())
			                    func __safeDI_chapter() -> Chapter {
			                        func __safeDI_storeBuilder_Chapter_store(_ scope: Chapter.SafeDIMockScope_Store.store_Values, __safeDI_chapter_storeBuilder: SafeDIMockScope_Analytics.DefaultStore_Scope.__safeDI_Builder<any Analytics>) -> any Store {
			                            func __safeDI_store() -> DefaultStore {
			                                let __safeDI_analyticsBuilder_book_serviceBuilder = __safeDI_chapter_storeBuilder.book_serviceBuilder(SafeDIMockScope_Analytics.DefaultStore_Scope.book_serviceBuilder_Values())
			                                func __safeDI_book() -> Book {
			                                    func __safeDI_serviceBuilder_Book(up: Book.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>>) -> Book.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                                        .init(pageBuilder: { values in __safeDI_serviceBuilder_Page(up: up.pageBuilder(values)) })
			                                    }
			                                    return Book.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Book(up: __safeDI_analyticsBuilder_book_serviceBuilder))
			                                }
			                                let book: Book = __safeDI_book()
			                                return DefaultStore(book: book)
			                            }
			                            let store: any Store = __safeDI_store()
			                            return store
			                        }
			                        func __safeDI_storeBuilder_Chapter(up: Chapter.SafeDIMockScope_Store.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultStore_Scope.__safeDI_Builder<any Analytics>>) -> Chapter.SafeDIMockScope_Store.__safeDI_Builder<any Store> {
			                            .init(store: { scope in __safeDI_storeBuilder_Chapter_store(scope, __safeDI_chapter_storeBuilder: up.store(scope)) })
			                        }
			                        return Chapter.__safeDI_mock(storeBuilder: __safeDI_storeBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_storeBuilder_Chapter(up: __safeDI_analyticsBuilder_chapter_storeBuilder))
			                    }
			                    let chapter: Chapter = __safeDI_chapter()
			                    let analytics: any Analytics = __safeDI_page_serviceBuilder.analytics(SafeDIMockScope_Analytics.DefaultService_Scope.analytics_Values(chapter: chapter))
			                    return DefaultService(analytics: analytics, chapter: chapter)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Page(up: Page.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>>) -> Page.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(service: { scope in __safeDI_serviceBuilder_Page_service(scope, __safeDI_page_serviceBuilder: up.service(scope)) })
			            }
			            _ = Page.__safeDI_Page_mock_4A57B09DFB8A9D2C.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
			            return Page.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Page(up: __safeDI_analyticsBuilder_page_serviceBuilder))
			        }
			        let page: Page = __safeDI_page()
			        return Screen(page: page)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_353A1427036388A9 {}
			}
			#endif
			"""
		case .fillCallsCalledTypeItselfBesideUncalledHolder:
			generatedFileHeader + """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(Mid)
			import Mid
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Screen {
			    nonisolated public enum SafeDIMockScope_Analytics {
			        nonisolated public struct page_serviceBuilder_Values {}

			        nonisolated public enum DefaultService_Scope {
			            nonisolated public struct analytics_Values {
			                public let pageBuilder: Instantiator<Page>
			            }

			            nonisolated public struct pageBuilder_serviceBuilder_Values {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let analytics: (analytics_Values) -> __safeDI_Built
			                public let pageBuilder_serviceBuilder: (pageBuilder_serviceBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			                public init(analytics: @escaping (analytics_Values) -> __safeDI_Built, pageBuilder_serviceBuilder: @escaping (pageBuilder_serviceBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                    self.analytics = analytics
			                    self.pageBuilder_serviceBuilder = pageBuilder_serviceBuilder
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(analytics: { _ in __safeDI_builder() }, pageBuilder_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			                }
			            }
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let page_serviceBuilder: (page_serviceBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(page_serviceBuilder: @escaping (page_serviceBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.page_serviceBuilder = page_serviceBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(page_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init() {}
			    }

			    public static func mock(
			        analyticsBuilder: @escaping () -> any Analytics,
			        serviceBuilder: (() -> any Service)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        Screen.__safeDI_mock(analyticsBuilder: .init(__safeDI_noScope: analyticsBuilder), serviceBuilder: serviceBuilder, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        analyticsBuilder __safeDI_analyticsBuilder: Screen.SafeDIMockScope_Analytics.__safeDI_Builder<any Analytics>,
			        serviceBuilder __safeDI_serviceBuilder: (() -> any Service)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        let __safeDI_analyticsBuilder_page_serviceBuilder = __safeDI_analyticsBuilder.page_serviceBuilder(SafeDIMockScope_Analytics.page_serviceBuilder_Values())
			        func __safeDI_page() -> Page {
			            func __safeDI_serviceBuilder_Page_service(_ scope: Page.SafeDIMockScope_Service.service_Values, __safeDI_page_serviceBuilder: SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let __safeDI_analyticsBuilder_pageBuilder_serviceBuilder = __safeDI_page_serviceBuilder.pageBuilder_serviceBuilder(SafeDIMockScope_Analytics.DefaultService_Scope.pageBuilder_serviceBuilder_Values())
			                    func __safeDI_pageBuilder() -> Page {
			                        Page.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Page(up: __safeDI_analyticsBuilder_pageBuilder_serviceBuilder))
			                    }
			                    let pageBuilder = Instantiator<Page>(__safeDI_pageBuilder)
			                    let analytics: any Analytics = __safeDI_page_serviceBuilder.analytics(SafeDIMockScope_Analytics.DefaultService_Scope.analytics_Values(pageBuilder: pageBuilder))
			                    return DefaultService(analytics: analytics, pageBuilder: pageBuilder)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Page(up: Page.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>>) -> Page.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(service: { scope in __safeDI_serviceBuilder_Page_service(scope, __safeDI_page_serviceBuilder: up.service(scope)) })
			            }
			            _ = Page.__safeDI_Page_mock_4A57B09DFB8A9D2C.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
			            return Page.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Page(up: __safeDI_analyticsBuilder_page_serviceBuilder))
			        }
			        let page: Page = __safeDI_page()
			        return Screen(page: page)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_D9B3B0F71CB6CE6A {}
			}
			#endif
			"""
		}
	}

	/// The file the tool generates for `Mid` in a cell of `layout` whose builder is a `SendableInstantiator`, for every
	/// caller kind.
	private static func expectedSendableMid(of layout: Layout) -> String {
		switch layout {
		case .fillInstantiatesIt, .nestedCallsFillInstantiatesIt, .fillAroundNestedCallInstantiatesIt, .fillCallsCalledTypeItselfBesideUncalledHolder:
			generatedFileHeader + """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Book {
			    nonisolated public enum SafeDISendableMockScope_Service {
			        nonisolated public struct pageBuilder_Values: Sendable {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			            public let pageBuilder: @Sendable (pageBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>

			            public init(pageBuilder: @escaping @Sendable (pageBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>) {
			                self.pageBuilder = pageBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                self.init(pageBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init() {}
			    }

			    public static func mock(
			        serviceSendableBuilder: @escaping @Sendable () -> any Service,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Book {
			        Book.__safeDI_mock(serviceSendableBuilder: .init(__safeDI_noScope: serviceSendableBuilder), safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        serviceSendableBuilder __safeDI_serviceSendableBuilder: Book.SafeDISendableMockScope_Service.__safeDI_Builder<any Service>,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Book {
			        _ = Page.__safeDI_Page_mock_4A57B09DFB8A9D2C.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
			        @Sendable nonisolated func __safeDI_pageBuilder() -> Page {
			            Page.__safeDI_mock(serviceBuilder: __safeDI_serviceSendableBuilder.pageBuilder(SafeDISendableMockScope_Service.pageBuilder_Values()))
			        }
			        let pageBuilder = SendableInstantiator<Page>(__safeDI_pageBuilder)
			        return Book(pageBuilder: pageBuilder)
			    }
			}

			extension Book {
			    public enum __safeDI_Book_mock_B9084D3C3DCDE1EE {}
			}
			#endif
			"""
		case .siblingPlacesFillInstantiatesIt:
			generatedFileHeader + """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Book {
			    nonisolated public enum SafeDISendableMockScope_Logger {
			        nonisolated public struct pageBuilder_Values: Sendable {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			            public let pageBuilder: @Sendable (pageBuilder_Values) -> Page.SafeDIMockScope_Logger.__safeDI_Builder<__safeDI_Built>

			            public init(pageBuilder: @escaping @Sendable (pageBuilder_Values) -> Page.SafeDIMockScope_Logger.__safeDI_Builder<__safeDI_Built>) {
			                self.pageBuilder = pageBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                self.init(pageBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			            }
			        }
			    }

			    nonisolated public enum SafeDISendableMockScope_Service {
			        nonisolated public struct pageBuilder_Values: Sendable {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			            public let pageBuilder: @Sendable (pageBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>

			            public init(pageBuilder: @escaping @Sendable (pageBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>) {
			                self.pageBuilder = pageBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                self.init(pageBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init() {}
			    }

			    public static func mock(
			        loggerSendableBuilder: @escaping @Sendable () -> any Logger,
			        serviceSendableBuilder: @escaping @Sendable () -> any Service,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Book {
			        Book.__safeDI_mock(loggerSendableBuilder: .init(__safeDI_noScope: loggerSendableBuilder), serviceSendableBuilder: .init(__safeDI_noScope: serviceSendableBuilder), safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        loggerSendableBuilder __safeDI_loggerSendableBuilder: Book.SafeDISendableMockScope_Logger.__safeDI_Builder<any Logger>,
			        serviceSendableBuilder __safeDI_serviceSendableBuilder: Book.SafeDISendableMockScope_Service.__safeDI_Builder<any Service>,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Book {
			        _ = Page.__safeDI_Page_mock_D554EC7204DBF437.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
			        @Sendable nonisolated func __safeDI_pageBuilder() -> Page {
			            Page.__safeDI_mock(loggerBuilder: __safeDI_loggerSendableBuilder.pageBuilder(SafeDISendableMockScope_Logger.pageBuilder_Values()), serviceBuilder: __safeDI_serviceSendableBuilder.pageBuilder(SafeDISendableMockScope_Service.pageBuilder_Values()))
			        }
			        let pageBuilder = SendableInstantiator<Page>(__safeDI_pageBuilder)
			        return Book(pageBuilder: pageBuilder)
			    }
			}

			extension Book {
			    public enum __safeDI_Book_mock_6C2F648D40CDEBB9 {}
			}
			#endif
			"""
		case .calledMocksOwnPlacesFillInstantiatesIt:
			generatedFileHeader + """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Book {
			    nonisolated public enum SafeDISendableMockScope_Service {
			        nonisolated public struct pageBuilder_Values: Sendable {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			            public let pageBuilder: @Sendable (pageBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>

			            public init(pageBuilder: @escaping @Sendable (pageBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>) {
			                self.pageBuilder = pageBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                self.init(pageBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			            }
			        }
			    }

			    nonisolated public enum SafeDIMockScope_Store {
			        nonisolated public struct store_Values {
			            public let pageBuilder: SendableInstantiator<Page>
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let store: (store_Values) -> __safeDI_Built

			            public init(store: @escaping (store_Values) -> __safeDI_Built) {
			                self.store = store
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(store: { _ in __safeDI_builder() })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init() {}
			    }

			    // SafeDI counts `Store` as `public`: no module it reads declares it narrower. If `Store` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    public static func mock(
			        serviceSendableBuilder: @escaping @Sendable () -> any Service,
			        storeBuilder: @escaping () -> any Store,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Book {
			        Book.__safeDI_mock(serviceSendableBuilder: .init(__safeDI_noScope: serviceSendableBuilder), storeBuilder: .init(__safeDI_noScope: storeBuilder), safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        serviceSendableBuilder __safeDI_serviceSendableBuilder: Book.SafeDISendableMockScope_Service.__safeDI_Builder<any Service>,
			        storeBuilder __safeDI_storeBuilder: Book.SafeDIMockScope_Store.__safeDI_Builder<any Store>,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Book {
			        _ = Page.__safeDI_Page_mock_4A57B09DFB8A9D2C.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
			        @Sendable nonisolated func __safeDI_pageBuilder() -> Page {
			            Page.__safeDI_mock(serviceBuilder: __safeDI_serviceSendableBuilder.pageBuilder(SafeDISendableMockScope_Service.pageBuilder_Values()))
			        }
			        let pageBuilder = SendableInstantiator<Page>(__safeDI_pageBuilder)
			        let store: any Store = __safeDI_storeBuilder.store(SafeDIMockScope_Store.store_Values(pageBuilder: pageBuilder))
			        return Book(pageBuilder: pageBuilder, store: store)
			    }
			}

			extension Book {
			    public enum __safeDI_Book_mock_2B1CDD7A4DD23EFB {}
			}
			#endif
			"""
		}
	}

	/// The file the tool generates for `App` in a cell of `layout` whose builder is a `SendableInstantiator` and whose
	/// caller is internal or listed.
	private static func expectedSendableInternalApp(of layout: Layout) -> String {
		switch layout {
		case .fillInstantiatesIt:
			generatedFileHeader + """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(Mid)
			import Mid
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            page: ((@escaping () -> any Service) -> Page)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                page: page
			            )
			        }

			        var page: ((@escaping () -> any Service) -> Page)? { __safeDI_storage.page }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                page: ((@escaping () -> any Service) -> Page)?
			            ) {
			                self.page = page
			            }

			            let page: ((@escaping () -> any Service) -> Page)?
			        }
			    }

			    static func mock(
			        analyticsSendableBuilder: @escaping @Sendable () -> any Analytics,
			        serviceBuilder: (() -> any Service)? = nil,
			        serviceSendableBuilder: (@Sendable () -> any Service)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_page() -> Page {
			            @Sendable nonisolated func __safeDI_serviceBuilder_Page_service() -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let analytics: any Analytics = analyticsSendableBuilder()
			                    func __safeDI_book() -> Book {
			                        @Sendable nonisolated func __safeDI_serviceSendableBuilder_Book() -> Book.SafeDISendableMockScope_Service.__safeDI_Builder<any Service> {
			                            .init(pageBuilder: { _ in __safeDI_serviceBuilder_Page() })
			                        }
			                        return Book.__safeDI_mock(serviceSendableBuilder: serviceSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceSendableBuilder_Book())
			                    }
			                    let book: Book = __safeDI_book()
			                    return DefaultService(analytics: analytics, book: book)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            @Sendable nonisolated func __safeDI_serviceBuilder_Page() -> Page.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(service: { _ in __safeDI_serviceBuilder_Page_service() })
			            }
			            _ = Page.__safeDI_Page_mock_4A57B09DFB8A9D2C.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
			            return if let safeDIBuilder = safeDIOverrides.page { safeDIBuilder({ if let serviceBuilder { serviceBuilder() } else { __safeDI_serviceBuilder_Page_service() } }) } else { Page.__safeDI_mock(serviceBuilder: serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Page()) }
			        }
			        let page: Page = __safeDI_page()
			        return Screen(page: page)
			    }
			}
			#endif
			"""
		case .siblingPlacesFillInstantiatesIt:
			generatedFileHeader + """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(Mid)
			import Mid
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            page: ((@escaping () -> any Logger, @escaping () -> any Service) -> Page)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                page: page
			            )
			        }

			        var page: ((@escaping () -> any Logger, @escaping () -> any Service) -> Page)? { __safeDI_storage.page }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                page: ((@escaping () -> any Logger, @escaping () -> any Service) -> Page)?
			            ) {
			                self.page = page
			            }

			            let page: ((@escaping () -> any Logger, @escaping () -> any Service) -> Page)?
			        }
			    }

			    static func mock(
			        analyticsSendableBuilder: @escaping @Sendable () -> any Analytics,
			        loggerBuilder: (() -> any Logger)? = nil,
			        loggerSendableBuilder: (@Sendable () -> any Logger)? = nil,
			        serviceBuilder: (() -> any Service)? = nil,
			        serviceSendableBuilder: (@Sendable () -> any Service)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_page() -> Page {
			            @Sendable nonisolated func __safeDI_loggerBuilder_Page_logger() -> any Logger {
			                func __safeDI_logger() -> DefaultLogger {
			                    let analytics: any Analytics = analyticsSendableBuilder()
			                    return DefaultLogger(analytics: analytics)
			                }
			                let logger: any Logger = __safeDI_logger()
			                return logger
			            }
			            @Sendable nonisolated func __safeDI_serviceBuilder_Page_service() -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    func __safeDI_book() -> Book {
			                        @Sendable nonisolated func __safeDI_loggerSendableBuilder_Book() -> Book.SafeDISendableMockScope_Logger.__safeDI_Builder<any Logger> {
			                            .init(pageBuilder: { _ in __safeDI_loggerBuilder_Page() })
			                        }
			                        @Sendable nonisolated func __safeDI_serviceSendableBuilder_Book() -> Book.SafeDISendableMockScope_Service.__safeDI_Builder<any Service> {
			                            .init(pageBuilder: { _ in __safeDI_serviceBuilder_Page() })
			                        }
			                        return Book.__safeDI_mock(loggerSendableBuilder: loggerSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_loggerSendableBuilder_Book(), serviceSendableBuilder: serviceSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceSendableBuilder_Book())
			                    }
			                    let book: Book = __safeDI_book()
			                    return DefaultService(book: book)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            @Sendable nonisolated func __safeDI_loggerBuilder_Page() -> Page.SafeDIMockScope_Logger.__safeDI_Builder<any Logger> {
			                .init(logger: { _ in __safeDI_loggerBuilder_Page_logger() })
			            }
			            @Sendable nonisolated func __safeDI_serviceBuilder_Page() -> Page.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(service: { _ in __safeDI_serviceBuilder_Page_service() })
			            }
			            _ = Page.__safeDI_Page_mock_D554EC7204DBF437.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
			            return if let safeDIBuilder = safeDIOverrides.page { safeDIBuilder({ if let loggerBuilder { loggerBuilder() } else { __safeDI_loggerBuilder_Page_logger() } }, { if let serviceBuilder { serviceBuilder() } else { __safeDI_serviceBuilder_Page_service() } }) } else { Page.__safeDI_mock(loggerBuilder: loggerBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_loggerBuilder_Page(), serviceBuilder: serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Page()) }
			        }
			        let page: Page = __safeDI_page()
			        return Screen(page: page)
			    }
			}
			#endif
			"""
		case .calledMocksOwnPlacesFillInstantiatesIt:
			generatedFileHeader + """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(Mid)
			import Mid
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            page: ((@escaping () -> any Service) -> Page)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                page: page
			            )
			        }

			        var page: ((@escaping () -> any Service) -> Page)? { __safeDI_storage.page }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                page: ((@escaping () -> any Service) -> Page)?
			            ) {
			                self.page = page
			            }

			            let page: ((@escaping () -> any Service) -> Page)?
			        }
			    }

			    static func mock(
			        analyticsSendableBuilder: @escaping @Sendable () -> any Analytics,
			        serviceBuilder: (() -> any Service)? = nil,
			        serviceSendableBuilder: (@Sendable () -> any Service)? = nil,
			        storeSendableBuilder: (@Sendable () -> any Store)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_page() -> Page {
			            @Sendable nonisolated func __safeDI_serviceBuilder_Page_service() -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    func __safeDI_book() -> Book {
			                        func __safeDI_storeBuilder_Book_store(_ scope: Book.SafeDIMockScope_Store.store_Values) -> any Store {
			                            func __safeDI_store() -> DefaultStore {
			                                let analytics: any Analytics = analyticsSendableBuilder()
			                                return DefaultStore(analytics: analytics)
			                            }
			                            let store: any Store = __safeDI_store()
			                            return store
			                        }
			                        @Sendable nonisolated func __safeDI_serviceSendableBuilder_Book() -> Book.SafeDISendableMockScope_Service.__safeDI_Builder<any Service> {
			                            .init(pageBuilder: { _ in __safeDI_serviceBuilder_Page() })
			                        }
			                        func __safeDI_storeBuilder_Book() -> Book.SafeDIMockScope_Store.__safeDI_Builder<any Store> {
			                            .init(store: { scope in __safeDI_storeBuilder_Book_store(scope) })
			                        }
			                        return Book.__safeDI_mock(serviceSendableBuilder: serviceSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceSendableBuilder_Book(), storeBuilder: storeSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_storeBuilder_Book())
			                    }
			                    let book: Book = __safeDI_book()
			                    return DefaultService(book: book)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            @Sendable nonisolated func __safeDI_serviceBuilder_Page() -> Page.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(service: { _ in __safeDI_serviceBuilder_Page_service() })
			            }
			            _ = Page.__safeDI_Page_mock_4A57B09DFB8A9D2C.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
			            return if let safeDIBuilder = safeDIOverrides.page { safeDIBuilder({ if let serviceBuilder { serviceBuilder() } else { __safeDI_serviceBuilder_Page_service() } }) } else { Page.__safeDI_mock(serviceBuilder: serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Page()) }
			        }
			        let page: Page = __safeDI_page()
			        return Screen(page: page)
			    }
			}
			#endif
			"""
		case .nestedCallsFillInstantiatesIt:
			generatedFileHeader + """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(Mid)
			import Mid
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            page: ((@escaping () -> any Service) -> Page)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                page: page
			            )
			        }

			        var page: ((@escaping () -> any Service) -> Page)? { __safeDI_storage.page }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                page: ((@escaping () -> any Service) -> Page)?
			            ) {
			                self.page = page
			            }

			            let page: ((@escaping () -> any Service) -> Page)?
			        }
			    }

			    static func mock(
			        analyticsSendableBuilder: @escaping @Sendable () -> any Analytics,
			        serviceBuilder: (() -> any Service)? = nil,
			        serviceSendableBuilder: (@Sendable () -> any Service)? = nil,
			        storeSendableBuilder: (@Sendable () -> any Store)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_page() -> Page {
			            @Sendable nonisolated func __safeDI_serviceBuilder_Page_service() -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    func __safeDI_chapter() -> Chapter {
			                        func __safeDI_storeBuilder_Chapter_store() -> any Store {
			                            func __safeDI_store() -> DefaultStore {
			                                let analytics: any Analytics = analyticsSendableBuilder()
			                                func __safeDI_book() -> Book {
			                                    @Sendable nonisolated func __safeDI_serviceSendableBuilder_Book() -> Book.SafeDISendableMockScope_Service.__safeDI_Builder<any Service> {
			                                        .init(pageBuilder: { _ in __safeDI_serviceBuilder_Page() })
			                                    }
			                                    return Book.__safeDI_mock(serviceSendableBuilder: serviceSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceSendableBuilder_Book())
			                                }
			                                let book: Book = __safeDI_book()
			                                return DefaultStore(analytics: analytics, book: book)
			                            }
			                            let store: any Store = __safeDI_store()
			                            return store
			                        }
			                        func __safeDI_storeBuilder_Chapter() -> Chapter.SafeDIMockScope_Store.__safeDI_Builder<any Store> {
			                            .init(store: { _ in __safeDI_storeBuilder_Chapter_store() })
			                        }
			                        return Chapter.__safeDI_mock(storeBuilder: storeSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_storeBuilder_Chapter())
			                    }
			                    let chapter: Chapter = __safeDI_chapter()
			                    return DefaultService(chapter: chapter)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            @Sendable nonisolated func __safeDI_serviceBuilder_Page() -> Page.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(service: { _ in __safeDI_serviceBuilder_Page_service() })
			            }
			            _ = Page.__safeDI_Page_mock_4A57B09DFB8A9D2C.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
			            return if let safeDIBuilder = safeDIOverrides.page { safeDIBuilder({ if let serviceBuilder { serviceBuilder() } else { __safeDI_serviceBuilder_Page_service() } }) } else { Page.__safeDI_mock(serviceBuilder: serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Page()) }
			        }
			        let page: Page = __safeDI_page()
			        return Screen(page: page)
			    }
			}
			#endif
			"""
		case .fillAroundNestedCallInstantiatesIt:
			generatedFileHeader + """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(Mid)
			import Mid
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            page: ((@escaping () -> any Service) -> Page)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                page: page
			            )
			        }

			        var page: ((@escaping () -> any Service) -> Page)? { __safeDI_storage.page }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                page: ((@escaping () -> any Service) -> Page)?
			            ) {
			                self.page = page
			            }

			            let page: ((@escaping () -> any Service) -> Page)?
			        }
			    }

			    static func mock(
			        analyticsSendableBuilder: @escaping @Sendable () -> any Analytics,
			        serviceBuilder: (() -> any Service)? = nil,
			        serviceSendableBuilder: (@Sendable () -> any Service)? = nil,
			        storeSendableBuilder: (@Sendable () -> any Store)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_page() -> Page {
			            @Sendable nonisolated func __safeDI_serviceBuilder_Page_service() -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let analytics: any Analytics = analyticsSendableBuilder()
			                    func __safeDI_chapter() -> Chapter {
			                        func __safeDI_storeBuilder_Chapter_store() -> any Store {
			                            func __safeDI_store() -> DefaultStore {
			                                func __safeDI_book() -> Book {
			                                    @Sendable nonisolated func __safeDI_serviceSendableBuilder_Book() -> Book.SafeDISendableMockScope_Service.__safeDI_Builder<any Service> {
			                                        .init(pageBuilder: { _ in __safeDI_serviceBuilder_Page() })
			                                    }
			                                    return Book.__safeDI_mock(serviceSendableBuilder: serviceSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceSendableBuilder_Book())
			                                }
			                                let book: Book = __safeDI_book()
			                                return DefaultStore(book: book)
			                            }
			                            let store: any Store = __safeDI_store()
			                            return store
			                        }
			                        func __safeDI_storeBuilder_Chapter() -> Chapter.SafeDIMockScope_Store.__safeDI_Builder<any Store> {
			                            .init(store: { _ in __safeDI_storeBuilder_Chapter_store() })
			                        }
			                        return Chapter.__safeDI_mock(storeBuilder: storeSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_storeBuilder_Chapter())
			                    }
			                    let chapter: Chapter = __safeDI_chapter()
			                    return DefaultService(analytics: analytics, chapter: chapter)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            @Sendable nonisolated func __safeDI_serviceBuilder_Page() -> Page.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(service: { _ in __safeDI_serviceBuilder_Page_service() })
			            }
			            _ = Page.__safeDI_Page_mock_4A57B09DFB8A9D2C.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
			            return if let safeDIBuilder = safeDIOverrides.page { safeDIBuilder({ if let serviceBuilder { serviceBuilder() } else { __safeDI_serviceBuilder_Page_service() } }) } else { Page.__safeDI_mock(serviceBuilder: serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Page()) }
			        }
			        let page: Page = __safeDI_page()
			        return Screen(page: page)
			    }
			}
			#endif
			"""
		case .fillCallsCalledTypeItselfBesideUncalledHolder:
			generatedFileHeader + """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(Mid)
			import Mid
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            page: ((@escaping () -> any Service) -> Page)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                page: page
			            )
			        }

			        var page: ((@escaping () -> any Service) -> Page)? { __safeDI_storage.page }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                page: ((@escaping () -> any Service) -> Page)?
			            ) {
			                self.page = page
			            }

			            let page: ((@escaping () -> any Service) -> Page)?
			        }
			    }

			    static func mock(
			        analyticsSendableBuilder: @escaping @Sendable () -> any Analytics,
			        serviceBuilder: (() -> any Service)? = nil,
			        serviceSendableBuilder: (@Sendable () -> any Service)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_page() -> Page {
			            @Sendable nonisolated func __safeDI_serviceBuilder_Page_service() -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let analytics: any Analytics = analyticsSendableBuilder()
			                    @Sendable nonisolated func __safeDI_pageBuilder() -> Page {
			                        Page.__safeDI_mock(serviceBuilder: serviceSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Page())
			                    }
			                    let pageBuilder = SendableInstantiator<Page>(__safeDI_pageBuilder)
			                    return DefaultService(analytics: analytics, pageBuilder: pageBuilder)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            @Sendable nonisolated func __safeDI_serviceBuilder_Page() -> Page.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(service: { _ in __safeDI_serviceBuilder_Page_service() })
			            }
			            _ = Page.__safeDI_Page_mock_4A57B09DFB8A9D2C.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
			            return if let safeDIBuilder = safeDIOverrides.page { safeDIBuilder({ if let serviceBuilder { serviceBuilder() } else { __safeDI_serviceBuilder_Page_service() } }) } else { Page.__safeDI_mock(serviceBuilder: serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Page()) }
			        }
			        let page: Page = __safeDI_page()
			        return Screen(page: page)
			    }
			}
			#endif
			"""
		}
	}

	/// The file the tool generates for `App` in a cell of `layout` whose builder is a `SendableInstantiator` and whose
	/// caller is `.public`.
	private static func expectedSendablePublicApp(of layout: Layout) -> String {
		switch layout {
		case .fillInstantiatesIt:
			generatedFileHeader + """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(Mid)
			import Mid
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Screen {
			    nonisolated public enum SafeDIMockScope_Analytics {
			        nonisolated public enum DefaultService_Scope {
			            nonisolated public struct analytics_Values {
			                public let book: Book
			            }

			            nonisolated public struct book_serviceSendableBuilder_Values {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let analytics: (analytics_Values) -> __safeDI_Built
			                public let book_serviceSendableBuilder: (book_serviceSendableBuilder_Values) -> Book.SafeDISendableMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			                public init(analytics: @escaping (analytics_Values) -> __safeDI_Built, book_serviceSendableBuilder: @escaping (book_serviceSendableBuilder_Values) -> Book.SafeDISendableMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                    self.analytics = analytics
			                    self.book_serviceSendableBuilder = book_serviceSendableBuilder
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                    self.init(analytics: { _ in __safeDI_builder() }, book_serviceSendableBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			                }
			            }
			        }
			    }

			    nonisolated public enum SafeDISendableMockScope_Analytics {
			        nonisolated public struct page_serviceBuilder_Values: Sendable {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			            public let page_serviceBuilder: @Sendable (page_serviceBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(page_serviceBuilder: @escaping @Sendable (page_serviceBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.page_serviceBuilder = page_serviceBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                self.init(page_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init() {}
			    }

			    public static func mock(
			        analyticsSendableBuilder: @escaping @Sendable () -> any Analytics,
			        serviceBuilder: (() -> any Service)? = nil,
			        serviceSendableBuilder: (@Sendable () -> any Service)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        Screen.__safeDI_mock(analyticsSendableBuilder: .init(__safeDI_noScope: analyticsSendableBuilder), serviceBuilder: serviceBuilder, serviceSendableBuilder: serviceSendableBuilder, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        analyticsSendableBuilder __safeDI_analyticsSendableBuilder: Screen.SafeDISendableMockScope_Analytics.__safeDI_Builder<any Analytics>,
			        serviceBuilder __safeDI_serviceBuilder: (() -> any Service)? = nil,
			        serviceSendableBuilder __safeDI_serviceSendableBuilder: (@Sendable () -> any Service)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_page() -> Page {
			            let __safeDI_analyticsSendableBuilder_page_serviceBuilder = __safeDI_analyticsSendableBuilder.page_serviceBuilder(SafeDISendableMockScope_Analytics.page_serviceBuilder_Values())
			            @Sendable nonisolated func __safeDI_serviceBuilder_Page_service(_ scope: Page.SafeDIMockScope_Service.service_Values, __safeDI_page_serviceBuilder: SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let __safeDI_analyticsSendableBuilder_book_serviceSendableBuilder = __safeDI_page_serviceBuilder.book_serviceSendableBuilder(SafeDIMockScope_Analytics.DefaultService_Scope.book_serviceSendableBuilder_Values())
			                    func __safeDI_book() -> Book {
			                        @Sendable nonisolated func __safeDI_serviceSendableBuilder_Book(up: Book.SafeDISendableMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>>) -> Book.SafeDISendableMockScope_Service.__safeDI_Builder<any Service> {
			                            .init(pageBuilder: { values in __safeDI_serviceBuilder_Page(up: up.pageBuilder(values)) })
			                        }
			                        return Book.__safeDI_mock(serviceSendableBuilder: __safeDI_serviceSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceSendableBuilder_Book(up: __safeDI_analyticsSendableBuilder_book_serviceSendableBuilder))
			                    }
			                    let book: Book = __safeDI_book()
			                    let analytics: any Analytics = __safeDI_page_serviceBuilder.analytics(SafeDIMockScope_Analytics.DefaultService_Scope.analytics_Values(book: book))
			                    return DefaultService(analytics: analytics, book: book)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            @Sendable nonisolated func __safeDI_serviceBuilder_Page(up: Page.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>>) -> Page.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(service: { scope in __safeDI_serviceBuilder_Page_service(scope, __safeDI_page_serviceBuilder: up.service(scope)) })
			            }
			            _ = Page.__safeDI_Page_mock_4A57B09DFB8A9D2C.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
			            return Page.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Page(up: __safeDI_analyticsSendableBuilder_page_serviceBuilder))
			        }
			        let page: Page = __safeDI_page()
			        return Screen(page: page)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_CB666FC47FA17223 {}
			}
			#endif
			"""
		case .siblingPlacesFillInstantiatesIt:
			generatedFileHeader + """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(Mid)
			import Mid
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Screen {
			    nonisolated public enum SafeDIMockScope_Analytics {
			        nonisolated public enum DefaultLogger_Scope {
			            nonisolated public struct analytics_Values {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let analytics: (analytics_Values) -> __safeDI_Built

			                public init(analytics: @escaping (analytics_Values) -> __safeDI_Built) {
			                    self.analytics = analytics
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(analytics: { _ in __safeDI_builder() })
			                }
			            }
			        }

			        nonisolated public enum DefaultService_Scope {
			            nonisolated public struct book_loggerSendableBuilder_Values {}

			            nonisolated public struct book_serviceSendableBuilder_Values {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let book_loggerSendableBuilder: (book_loggerSendableBuilder_Values) -> Book.SafeDISendableMockScope_Logger.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultLogger_Scope.__safeDI_Builder<__safeDI_Built>>
			                public let book_serviceSendableBuilder: (book_serviceSendableBuilder_Values) -> Book.SafeDISendableMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			                public init(book_loggerSendableBuilder: @escaping (book_loggerSendableBuilder_Values) -> Book.SafeDISendableMockScope_Logger.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultLogger_Scope.__safeDI_Builder<__safeDI_Built>>, book_serviceSendableBuilder: @escaping (book_serviceSendableBuilder_Values) -> Book.SafeDISendableMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                    self.book_loggerSendableBuilder = book_loggerSendableBuilder
			                    self.book_serviceSendableBuilder = book_serviceSendableBuilder
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                    self.init(book_loggerSendableBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }, book_serviceSendableBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			                }
			            }
			        }
			    }

			    nonisolated public enum SafeDISendableMockScope_Analytics {
			        nonisolated public struct page_loggerBuilder_Values: Sendable {}

			        nonisolated public struct page_serviceBuilder_Values: Sendable {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			            public let page_loggerBuilder: @Sendable (page_loggerBuilder_Values) -> Page.SafeDIMockScope_Logger.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultLogger_Scope.__safeDI_Builder<__safeDI_Built>>
			            public let page_serviceBuilder: @Sendable (page_serviceBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(page_loggerBuilder: @escaping @Sendable (page_loggerBuilder_Values) -> Page.SafeDIMockScope_Logger.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultLogger_Scope.__safeDI_Builder<__safeDI_Built>>, page_serviceBuilder: @escaping @Sendable (page_serviceBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.page_loggerBuilder = page_loggerBuilder
			                self.page_serviceBuilder = page_serviceBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                self.init(page_loggerBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }, page_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init() {}
			    }

			    public static func mock(
			        analyticsSendableBuilder: @escaping @Sendable () -> any Analytics,
			        loggerBuilder: (() -> any Logger)? = nil,
			        loggerSendableBuilder: (@Sendable () -> any Logger)? = nil,
			        serviceBuilder: (() -> any Service)? = nil,
			        serviceSendableBuilder: (@Sendable () -> any Service)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        Screen.__safeDI_mock(analyticsSendableBuilder: .init(__safeDI_noScope: analyticsSendableBuilder), loggerBuilder: loggerBuilder, loggerSendableBuilder: loggerSendableBuilder, serviceBuilder: serviceBuilder, serviceSendableBuilder: serviceSendableBuilder, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        analyticsSendableBuilder __safeDI_analyticsSendableBuilder: Screen.SafeDISendableMockScope_Analytics.__safeDI_Builder<any Analytics>,
			        loggerBuilder __safeDI_loggerBuilder: (() -> any Logger)? = nil,
			        loggerSendableBuilder __safeDI_loggerSendableBuilder: (@Sendable () -> any Logger)? = nil,
			        serviceBuilder __safeDI_serviceBuilder: (() -> any Service)? = nil,
			        serviceSendableBuilder __safeDI_serviceSendableBuilder: (@Sendable () -> any Service)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_page() -> Page {
			            let __safeDI_analyticsSendableBuilder_page_loggerBuilder = __safeDI_analyticsSendableBuilder.page_loggerBuilder(SafeDISendableMockScope_Analytics.page_loggerBuilder_Values())
			            let __safeDI_analyticsSendableBuilder_page_serviceBuilder = __safeDI_analyticsSendableBuilder.page_serviceBuilder(SafeDISendableMockScope_Analytics.page_serviceBuilder_Values())
			            @Sendable nonisolated func __safeDI_serviceBuilder_Page_service(_ scope: Page.SafeDIMockScope_Service.service_Values, __safeDI_page_serviceBuilder: SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let __safeDI_analyticsSendableBuilder_book_loggerSendableBuilder = __safeDI_page_serviceBuilder.book_loggerSendableBuilder(SafeDIMockScope_Analytics.DefaultService_Scope.book_loggerSendableBuilder_Values())
			                    let __safeDI_analyticsSendableBuilder_book_serviceSendableBuilder = __safeDI_page_serviceBuilder.book_serviceSendableBuilder(SafeDIMockScope_Analytics.DefaultService_Scope.book_serviceSendableBuilder_Values())
			                    func __safeDI_book() -> Book {
			                        @Sendable nonisolated func __safeDI_loggerSendableBuilder_Book(up: Book.SafeDISendableMockScope_Logger.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultLogger_Scope.__safeDI_Builder<any Analytics>>) -> Book.SafeDISendableMockScope_Logger.__safeDI_Builder<any Logger> {
			                            .init(pageBuilder: { values in __safeDI_loggerBuilder_Page(up: up.pageBuilder(values)) })
			                        }
			                        @Sendable nonisolated func __safeDI_serviceSendableBuilder_Book(up: Book.SafeDISendableMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>>) -> Book.SafeDISendableMockScope_Service.__safeDI_Builder<any Service> {
			                            .init(pageBuilder: { values in __safeDI_serviceBuilder_Page(up: up.pageBuilder(values)) })
			                        }
			                        return Book.__safeDI_mock(loggerSendableBuilder: __safeDI_loggerSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_loggerSendableBuilder_Book(up: __safeDI_analyticsSendableBuilder_book_loggerSendableBuilder), serviceSendableBuilder: __safeDI_serviceSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceSendableBuilder_Book(up: __safeDI_analyticsSendableBuilder_book_serviceSendableBuilder))
			                    }
			                    let book: Book = __safeDI_book()
			                    return DefaultService(book: book)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            @Sendable nonisolated func __safeDI_loggerBuilder_Page_logger(_ scope: Page.SafeDIMockScope_Logger.logger_Values, __safeDI_page_loggerBuilder: SafeDIMockScope_Analytics.DefaultLogger_Scope.__safeDI_Builder<any Analytics>) -> any Logger {
			                func __safeDI_logger() -> DefaultLogger {
			                    let analytics: any Analytics = __safeDI_page_loggerBuilder.analytics(SafeDIMockScope_Analytics.DefaultLogger_Scope.analytics_Values())
			                    return DefaultLogger(analytics: analytics)
			                }
			                let logger: any Logger = __safeDI_logger()
			                return logger
			            }
			            @Sendable nonisolated func __safeDI_loggerBuilder_Page(up: Page.SafeDIMockScope_Logger.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultLogger_Scope.__safeDI_Builder<any Analytics>>) -> Page.SafeDIMockScope_Logger.__safeDI_Builder<any Logger> {
			                .init(logger: { scope in __safeDI_loggerBuilder_Page_logger(scope, __safeDI_page_loggerBuilder: up.logger(scope)) })
			            }
			            @Sendable nonisolated func __safeDI_serviceBuilder_Page(up: Page.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>>) -> Page.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(service: { scope in __safeDI_serviceBuilder_Page_service(scope, __safeDI_page_serviceBuilder: up.service(scope)) })
			            }
			            _ = Page.__safeDI_Page_mock_D554EC7204DBF437.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
			            return Page.__safeDI_mock(loggerBuilder: __safeDI_loggerBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_loggerBuilder_Page(up: __safeDI_analyticsSendableBuilder_page_loggerBuilder), serviceBuilder: __safeDI_serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Page(up: __safeDI_analyticsSendableBuilder_page_serviceBuilder))
			        }
			        let page: Page = __safeDI_page()
			        return Screen(page: page)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_50D1F62B5AABFF76 {}
			}
			#endif
			"""
		case .calledMocksOwnPlacesFillInstantiatesIt:
			generatedFileHeader + """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(Mid)
			import Mid
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Screen {
			    nonisolated public enum SafeDIMockScope_Analytics {
			        nonisolated public enum DefaultService_Scope {
			            nonisolated public struct book_serviceSendableBuilder_Values {}

			            nonisolated public struct book_storeBuilder_Values {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let book_serviceSendableBuilder: (book_serviceSendableBuilder_Values) -> Book.SafeDISendableMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>
			                public let book_storeBuilder: (book_storeBuilder_Values) -> Book.SafeDIMockScope_Store.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultStore_Scope.__safeDI_Builder<__safeDI_Built>>

			                public init(book_serviceSendableBuilder: @escaping (book_serviceSendableBuilder_Values) -> Book.SafeDISendableMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>, book_storeBuilder: @escaping (book_storeBuilder_Values) -> Book.SafeDIMockScope_Store.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultStore_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                    self.book_serviceSendableBuilder = book_serviceSendableBuilder
			                    self.book_storeBuilder = book_storeBuilder
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                    self.init(book_serviceSendableBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }, book_storeBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			                }
			            }
			        }

			        nonisolated public enum DefaultStore_Scope {
			            nonisolated public struct analytics_Values {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let analytics: (analytics_Values) -> __safeDI_Built

			                public init(analytics: @escaping (analytics_Values) -> __safeDI_Built) {
			                    self.analytics = analytics
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(analytics: { _ in __safeDI_builder() })
			                }
			            }
			        }
			    }

			    nonisolated public enum SafeDISendableMockScope_Analytics {
			        nonisolated public struct page_serviceBuilder_Values: Sendable {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			            public let page_serviceBuilder: @Sendable (page_serviceBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(page_serviceBuilder: @escaping @Sendable (page_serviceBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.page_serviceBuilder = page_serviceBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                self.init(page_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init() {}
			    }

			    // SafeDI counts `Store` as `public`: no module it reads declares it narrower. If `Store` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    public static func mock(
			        analyticsSendableBuilder: @escaping @Sendable () -> any Analytics,
			        serviceBuilder: (() -> any Service)? = nil,
			        serviceSendableBuilder: (@Sendable () -> any Service)? = nil,
			        storeSendableBuilder: (@Sendable () -> any Store)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        Screen.__safeDI_mock(analyticsSendableBuilder: .init(__safeDI_noScope: analyticsSendableBuilder), serviceBuilder: serviceBuilder, serviceSendableBuilder: serviceSendableBuilder, storeSendableBuilder: storeSendableBuilder, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        analyticsSendableBuilder __safeDI_analyticsSendableBuilder: Screen.SafeDISendableMockScope_Analytics.__safeDI_Builder<any Analytics>,
			        serviceBuilder __safeDI_serviceBuilder: (() -> any Service)? = nil,
			        serviceSendableBuilder __safeDI_serviceSendableBuilder: (@Sendable () -> any Service)? = nil,
			        storeSendableBuilder __safeDI_storeSendableBuilder: (@Sendable () -> any Store)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_page() -> Page {
			            let __safeDI_analyticsSendableBuilder_page_serviceBuilder = __safeDI_analyticsSendableBuilder.page_serviceBuilder(SafeDISendableMockScope_Analytics.page_serviceBuilder_Values())
			            @Sendable nonisolated func __safeDI_serviceBuilder_Page_service(_ scope: Page.SafeDIMockScope_Service.service_Values, __safeDI_page_serviceBuilder: SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let __safeDI_analyticsSendableBuilder_book_serviceSendableBuilder = __safeDI_page_serviceBuilder.book_serviceSendableBuilder(SafeDIMockScope_Analytics.DefaultService_Scope.book_serviceSendableBuilder_Values())
			                    let __safeDI_analyticsSendableBuilder_book_storeBuilder = __safeDI_page_serviceBuilder.book_storeBuilder(SafeDIMockScope_Analytics.DefaultService_Scope.book_storeBuilder_Values())
			                    func __safeDI_book() -> Book {
			                        func __safeDI_storeBuilder_Book_store(_ scope: Book.SafeDIMockScope_Store.store_Values, __safeDI_book_storeBuilder: SafeDIMockScope_Analytics.DefaultStore_Scope.__safeDI_Builder<any Analytics>) -> any Store {
			                            func __safeDI_store() -> DefaultStore {
			                                let analytics: any Analytics = __safeDI_book_storeBuilder.analytics(SafeDIMockScope_Analytics.DefaultStore_Scope.analytics_Values())
			                                return DefaultStore(analytics: analytics)
			                            }
			                            let store: any Store = __safeDI_store()
			                            return store
			                        }
			                        @Sendable nonisolated func __safeDI_serviceSendableBuilder_Book(up: Book.SafeDISendableMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>>) -> Book.SafeDISendableMockScope_Service.__safeDI_Builder<any Service> {
			                            .init(pageBuilder: { values in __safeDI_serviceBuilder_Page(up: up.pageBuilder(values)) })
			                        }
			                        func __safeDI_storeBuilder_Book(up: Book.SafeDIMockScope_Store.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultStore_Scope.__safeDI_Builder<any Analytics>>) -> Book.SafeDIMockScope_Store.__safeDI_Builder<any Store> {
			                            .init(store: { scope in __safeDI_storeBuilder_Book_store(scope, __safeDI_book_storeBuilder: up.store(scope)) })
			                        }
			                        return Book.__safeDI_mock(serviceSendableBuilder: __safeDI_serviceSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceSendableBuilder_Book(up: __safeDI_analyticsSendableBuilder_book_serviceSendableBuilder), storeBuilder: __safeDI_storeSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_storeBuilder_Book(up: __safeDI_analyticsSendableBuilder_book_storeBuilder))
			                    }
			                    let book: Book = __safeDI_book()
			                    return DefaultService(book: book)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            @Sendable nonisolated func __safeDI_serviceBuilder_Page(up: Page.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>>) -> Page.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(service: { scope in __safeDI_serviceBuilder_Page_service(scope, __safeDI_page_serviceBuilder: up.service(scope)) })
			            }
			            _ = Page.__safeDI_Page_mock_4A57B09DFB8A9D2C.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
			            return Page.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Page(up: __safeDI_analyticsSendableBuilder_page_serviceBuilder))
			        }
			        let page: Page = __safeDI_page()
			        return Screen(page: page)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_2232634E9DD7D517 {}
			}
			#endif
			"""
		case .nestedCallsFillInstantiatesIt:
			generatedFileHeader + """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(Mid)
			import Mid
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Screen {
			    nonisolated public enum SafeDIMockScope_Analytics {
			        nonisolated public enum DefaultService_Scope {
			            nonisolated public struct chapter_storeBuilder_Values {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let chapter_storeBuilder: (chapter_storeBuilder_Values) -> Chapter.SafeDIMockScope_Store.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultStore_Scope.__safeDI_Builder<__safeDI_Built>>

			                public init(chapter_storeBuilder: @escaping (chapter_storeBuilder_Values) -> Chapter.SafeDIMockScope_Store.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultStore_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                    self.chapter_storeBuilder = chapter_storeBuilder
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                    self.init(chapter_storeBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			                }
			            }
			        }

			        nonisolated public enum DefaultStore_Scope {
			            nonisolated public struct analytics_Values {
			                public let book: Book
			            }

			            nonisolated public struct book_serviceSendableBuilder_Values {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let analytics: (analytics_Values) -> __safeDI_Built
			                public let book_serviceSendableBuilder: (book_serviceSendableBuilder_Values) -> Book.SafeDISendableMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			                public init(analytics: @escaping (analytics_Values) -> __safeDI_Built, book_serviceSendableBuilder: @escaping (book_serviceSendableBuilder_Values) -> Book.SafeDISendableMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                    self.analytics = analytics
			                    self.book_serviceSendableBuilder = book_serviceSendableBuilder
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                    self.init(analytics: { _ in __safeDI_builder() }, book_serviceSendableBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			                }
			            }
			        }
			    }

			    nonisolated public enum SafeDISendableMockScope_Analytics {
			        nonisolated public struct page_serviceBuilder_Values: Sendable {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			            public let page_serviceBuilder: @Sendable (page_serviceBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(page_serviceBuilder: @escaping @Sendable (page_serviceBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.page_serviceBuilder = page_serviceBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                self.init(page_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init() {}
			    }

			    public static func mock(
			        analyticsSendableBuilder: @escaping @Sendable () -> any Analytics,
			        serviceBuilder: (() -> any Service)? = nil,
			        serviceSendableBuilder: (@Sendable () -> any Service)? = nil,
			        storeSendableBuilder: (@Sendable () -> any Store)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        Screen.__safeDI_mock(analyticsSendableBuilder: .init(__safeDI_noScope: analyticsSendableBuilder), serviceBuilder: serviceBuilder, serviceSendableBuilder: serviceSendableBuilder, storeSendableBuilder: storeSendableBuilder, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        analyticsSendableBuilder __safeDI_analyticsSendableBuilder: Screen.SafeDISendableMockScope_Analytics.__safeDI_Builder<any Analytics>,
			        serviceBuilder __safeDI_serviceBuilder: (() -> any Service)? = nil,
			        serviceSendableBuilder __safeDI_serviceSendableBuilder: (@Sendable () -> any Service)? = nil,
			        storeSendableBuilder __safeDI_storeSendableBuilder: (@Sendable () -> any Store)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_page() -> Page {
			            let __safeDI_analyticsSendableBuilder_page_serviceBuilder = __safeDI_analyticsSendableBuilder.page_serviceBuilder(SafeDISendableMockScope_Analytics.page_serviceBuilder_Values())
			            @Sendable nonisolated func __safeDI_serviceBuilder_Page_service(_ scope: Page.SafeDIMockScope_Service.service_Values, __safeDI_page_serviceBuilder: SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let __safeDI_analyticsSendableBuilder_chapter_storeBuilder = __safeDI_page_serviceBuilder.chapter_storeBuilder(SafeDIMockScope_Analytics.DefaultService_Scope.chapter_storeBuilder_Values())
			                    func __safeDI_chapter() -> Chapter {
			                        func __safeDI_storeBuilder_Chapter_store(_ scope: Chapter.SafeDIMockScope_Store.store_Values, __safeDI_chapter_storeBuilder: SafeDIMockScope_Analytics.DefaultStore_Scope.__safeDI_Builder<any Analytics>) -> any Store {
			                            func __safeDI_store() -> DefaultStore {
			                                let __safeDI_analyticsSendableBuilder_book_serviceSendableBuilder = __safeDI_chapter_storeBuilder.book_serviceSendableBuilder(SafeDIMockScope_Analytics.DefaultStore_Scope.book_serviceSendableBuilder_Values())
			                                func __safeDI_book() -> Book {
			                                    @Sendable nonisolated func __safeDI_serviceSendableBuilder_Book(up: Book.SafeDISendableMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>>) -> Book.SafeDISendableMockScope_Service.__safeDI_Builder<any Service> {
			                                        .init(pageBuilder: { values in __safeDI_serviceBuilder_Page(up: up.pageBuilder(values)) })
			                                    }
			                                    return Book.__safeDI_mock(serviceSendableBuilder: __safeDI_serviceSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceSendableBuilder_Book(up: __safeDI_analyticsSendableBuilder_book_serviceSendableBuilder))
			                                }
			                                let book: Book = __safeDI_book()
			                                let analytics: any Analytics = __safeDI_chapter_storeBuilder.analytics(SafeDIMockScope_Analytics.DefaultStore_Scope.analytics_Values(book: book))
			                                return DefaultStore(analytics: analytics, book: book)
			                            }
			                            let store: any Store = __safeDI_store()
			                            return store
			                        }
			                        func __safeDI_storeBuilder_Chapter(up: Chapter.SafeDIMockScope_Store.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultStore_Scope.__safeDI_Builder<any Analytics>>) -> Chapter.SafeDIMockScope_Store.__safeDI_Builder<any Store> {
			                            .init(store: { scope in __safeDI_storeBuilder_Chapter_store(scope, __safeDI_chapter_storeBuilder: up.store(scope)) })
			                        }
			                        return Chapter.__safeDI_mock(storeBuilder: __safeDI_storeSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_storeBuilder_Chapter(up: __safeDI_analyticsSendableBuilder_chapter_storeBuilder))
			                    }
			                    let chapter: Chapter = __safeDI_chapter()
			                    return DefaultService(chapter: chapter)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            @Sendable nonisolated func __safeDI_serviceBuilder_Page(up: Page.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>>) -> Page.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(service: { scope in __safeDI_serviceBuilder_Page_service(scope, __safeDI_page_serviceBuilder: up.service(scope)) })
			            }
			            _ = Page.__safeDI_Page_mock_4A57B09DFB8A9D2C.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
			            return Page.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Page(up: __safeDI_analyticsSendableBuilder_page_serviceBuilder))
			        }
			        let page: Page = __safeDI_page()
			        return Screen(page: page)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_46550D63692D553C {}
			}
			#endif
			"""
		case .fillAroundNestedCallInstantiatesIt:
			generatedFileHeader + """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(Mid)
			import Mid
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Screen {
			    nonisolated public enum SafeDIMockScope_Analytics {
			        nonisolated public enum DefaultService_Scope {
			            nonisolated public struct analytics_Values {
			                public let chapter: Chapter
			            }

			            nonisolated public struct chapter_storeBuilder_Values {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let analytics: (analytics_Values) -> __safeDI_Built
			                public let chapter_storeBuilder: (chapter_storeBuilder_Values) -> Chapter.SafeDIMockScope_Store.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultStore_Scope.__safeDI_Builder<__safeDI_Built>>

			                public init(analytics: @escaping (analytics_Values) -> __safeDI_Built, chapter_storeBuilder: @escaping (chapter_storeBuilder_Values) -> Chapter.SafeDIMockScope_Store.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultStore_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                    self.analytics = analytics
			                    self.chapter_storeBuilder = chapter_storeBuilder
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                    self.init(analytics: { _ in __safeDI_builder() }, chapter_storeBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			                }
			            }
			        }

			        nonisolated public enum DefaultStore_Scope {
			            nonisolated public struct book_serviceSendableBuilder_Values {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let book_serviceSendableBuilder: (book_serviceSendableBuilder_Values) -> Book.SafeDISendableMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			                public init(book_serviceSendableBuilder: @escaping (book_serviceSendableBuilder_Values) -> Book.SafeDISendableMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                    self.book_serviceSendableBuilder = book_serviceSendableBuilder
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                    self.init(book_serviceSendableBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			                }
			            }
			        }
			    }

			    nonisolated public enum SafeDISendableMockScope_Analytics {
			        nonisolated public struct page_serviceBuilder_Values: Sendable {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			            public let page_serviceBuilder: @Sendable (page_serviceBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(page_serviceBuilder: @escaping @Sendable (page_serviceBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.page_serviceBuilder = page_serviceBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                self.init(page_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init() {}
			    }

			    public static func mock(
			        analyticsSendableBuilder: @escaping @Sendable () -> any Analytics,
			        serviceBuilder: (() -> any Service)? = nil,
			        serviceSendableBuilder: (@Sendable () -> any Service)? = nil,
			        storeSendableBuilder: (@Sendable () -> any Store)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        Screen.__safeDI_mock(analyticsSendableBuilder: .init(__safeDI_noScope: analyticsSendableBuilder), serviceBuilder: serviceBuilder, serviceSendableBuilder: serviceSendableBuilder, storeSendableBuilder: storeSendableBuilder, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        analyticsSendableBuilder __safeDI_analyticsSendableBuilder: Screen.SafeDISendableMockScope_Analytics.__safeDI_Builder<any Analytics>,
			        serviceBuilder __safeDI_serviceBuilder: (() -> any Service)? = nil,
			        serviceSendableBuilder __safeDI_serviceSendableBuilder: (@Sendable () -> any Service)? = nil,
			        storeSendableBuilder __safeDI_storeSendableBuilder: (@Sendable () -> any Store)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_page() -> Page {
			            let __safeDI_analyticsSendableBuilder_page_serviceBuilder = __safeDI_analyticsSendableBuilder.page_serviceBuilder(SafeDISendableMockScope_Analytics.page_serviceBuilder_Values())
			            @Sendable nonisolated func __safeDI_serviceBuilder_Page_service(_ scope: Page.SafeDIMockScope_Service.service_Values, __safeDI_page_serviceBuilder: SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let __safeDI_analyticsSendableBuilder_chapter_storeBuilder = __safeDI_page_serviceBuilder.chapter_storeBuilder(SafeDIMockScope_Analytics.DefaultService_Scope.chapter_storeBuilder_Values())
			                    func __safeDI_chapter() -> Chapter {
			                        func __safeDI_storeBuilder_Chapter_store(_ scope: Chapter.SafeDIMockScope_Store.store_Values, __safeDI_chapter_storeBuilder: SafeDIMockScope_Analytics.DefaultStore_Scope.__safeDI_Builder<any Analytics>) -> any Store {
			                            func __safeDI_store() -> DefaultStore {
			                                let __safeDI_analyticsSendableBuilder_book_serviceSendableBuilder = __safeDI_chapter_storeBuilder.book_serviceSendableBuilder(SafeDIMockScope_Analytics.DefaultStore_Scope.book_serviceSendableBuilder_Values())
			                                func __safeDI_book() -> Book {
			                                    @Sendable nonisolated func __safeDI_serviceSendableBuilder_Book(up: Book.SafeDISendableMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>>) -> Book.SafeDISendableMockScope_Service.__safeDI_Builder<any Service> {
			                                        .init(pageBuilder: { values in __safeDI_serviceBuilder_Page(up: up.pageBuilder(values)) })
			                                    }
			                                    return Book.__safeDI_mock(serviceSendableBuilder: __safeDI_serviceSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceSendableBuilder_Book(up: __safeDI_analyticsSendableBuilder_book_serviceSendableBuilder))
			                                }
			                                let book: Book = __safeDI_book()
			                                return DefaultStore(book: book)
			                            }
			                            let store: any Store = __safeDI_store()
			                            return store
			                        }
			                        func __safeDI_storeBuilder_Chapter(up: Chapter.SafeDIMockScope_Store.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultStore_Scope.__safeDI_Builder<any Analytics>>) -> Chapter.SafeDIMockScope_Store.__safeDI_Builder<any Store> {
			                            .init(store: { scope in __safeDI_storeBuilder_Chapter_store(scope, __safeDI_chapter_storeBuilder: up.store(scope)) })
			                        }
			                        return Chapter.__safeDI_mock(storeBuilder: __safeDI_storeSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_storeBuilder_Chapter(up: __safeDI_analyticsSendableBuilder_chapter_storeBuilder))
			                    }
			                    let chapter: Chapter = __safeDI_chapter()
			                    let analytics: any Analytics = __safeDI_page_serviceBuilder.analytics(SafeDIMockScope_Analytics.DefaultService_Scope.analytics_Values(chapter: chapter))
			                    return DefaultService(analytics: analytics, chapter: chapter)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            @Sendable nonisolated func __safeDI_serviceBuilder_Page(up: Page.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>>) -> Page.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(service: { scope in __safeDI_serviceBuilder_Page_service(scope, __safeDI_page_serviceBuilder: up.service(scope)) })
			            }
			            _ = Page.__safeDI_Page_mock_4A57B09DFB8A9D2C.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
			            return Page.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Page(up: __safeDI_analyticsSendableBuilder_page_serviceBuilder))
			        }
			        let page: Page = __safeDI_page()
			        return Screen(page: page)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_8A1B9670770BE4CA {}
			}
			#endif
			"""
		case .fillCallsCalledTypeItselfBesideUncalledHolder:
			generatedFileHeader + """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(Mid)
			import Mid
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Screen {
			    nonisolated public enum SafeDIMockScope_Analytics {
			        nonisolated public enum DefaultService_Scope {
			            nonisolated public struct analytics_Values {
			                public let pageBuilder: SendableInstantiator<Page>
			            }

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let analytics: (analytics_Values) -> __safeDI_Built

			                public init(analytics: @escaping (analytics_Values) -> __safeDI_Built) {
			                    self.analytics = analytics
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(analytics: { _ in __safeDI_builder() })
			                }
			            }
			        }
			    }

			    nonisolated public enum SafeDISendableMockScope_Analytics {
			        nonisolated public struct page_serviceBuilder_Values: Sendable {}

			        nonisolated public struct page_serviceBuilder_Sendable_Values: Sendable {}

			        nonisolated public enum DefaultService_Scope {
			            nonisolated public struct pageBuilder_serviceBuilder_Values: Sendable {}

			            nonisolated public struct pageBuilder_serviceBuilder_Sendable_Values: Sendable {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			                public let pageBuilder_serviceBuilder: @Sendable (pageBuilder_serviceBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>
			                public let pageBuilder_serviceBuilder_Sendable: @Sendable (pageBuilder_serviceBuilder_Sendable_Values) -> SafeDISendableMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>

			                public init(pageBuilder_serviceBuilder: @escaping @Sendable (pageBuilder_serviceBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>, pageBuilder_serviceBuilder_Sendable: @escaping @Sendable (pageBuilder_serviceBuilder_Sendable_Values) -> SafeDISendableMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>) {
			                    self.pageBuilder_serviceBuilder = pageBuilder_serviceBuilder
			                    self.pageBuilder_serviceBuilder_Sendable = pageBuilder_serviceBuilder_Sendable
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                    self.init(pageBuilder_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }, pageBuilder_serviceBuilder_Sendable: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			                }
			            }
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			            public let page_serviceBuilder: @Sendable (page_serviceBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>
			            public let page_serviceBuilder_Sendable: @Sendable (page_serviceBuilder_Sendable_Values) -> SafeDISendableMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>

			            public init(page_serviceBuilder: @escaping @Sendable (page_serviceBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>, page_serviceBuilder_Sendable: @escaping @Sendable (page_serviceBuilder_Sendable_Values) -> SafeDISendableMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>) {
			                self.page_serviceBuilder = page_serviceBuilder
			                self.page_serviceBuilder_Sendable = page_serviceBuilder_Sendable
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                self.init(page_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }, page_serviceBuilder_Sendable: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init() {}
			    }

			    public static func mock(
			        analyticsSendableBuilder: @escaping @Sendable () -> any Analytics,
			        serviceBuilder: (() -> any Service)? = nil,
			        serviceSendableBuilder: (@Sendable () -> any Service)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        Screen.__safeDI_mock(analyticsSendableBuilder: .init(__safeDI_noScope: analyticsSendableBuilder), serviceBuilder: serviceBuilder, serviceSendableBuilder: serviceSendableBuilder, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        analyticsSendableBuilder __safeDI_analyticsSendableBuilder: Screen.SafeDISendableMockScope_Analytics.__safeDI_Builder<any Analytics>,
			        serviceBuilder __safeDI_serviceBuilder: (() -> any Service)? = nil,
			        serviceSendableBuilder __safeDI_serviceSendableBuilder: (@Sendable () -> any Service)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_page() -> Page {
			            let __safeDI_analyticsSendableBuilder_page_serviceBuilder = __safeDI_analyticsSendableBuilder.page_serviceBuilder(SafeDISendableMockScope_Analytics.page_serviceBuilder_Values())
			            let __safeDI_analyticsSendableBuilder_page_serviceBuilder_Sendable = __safeDI_analyticsSendableBuilder.page_serviceBuilder_Sendable(SafeDISendableMockScope_Analytics.page_serviceBuilder_Sendable_Values())
			            @Sendable nonisolated func __safeDI_serviceBuilder_Page_service(_ scope: Page.SafeDIMockScope_Service.service_Values, __safeDI_page_serviceBuilder: SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    @Sendable nonisolated func __safeDI_pageBuilder() -> Page {
			                        let __safeDI_analyticsSendableBuilder_pageBuilder_serviceBuilder = __safeDI_analyticsSendableBuilder_page_serviceBuilder_Sendable.pageBuilder_serviceBuilder(SafeDISendableMockScope_Analytics.DefaultService_Scope.pageBuilder_serviceBuilder_Values())
			                        return Page.__safeDI_mock(serviceBuilder: __safeDI_serviceSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Page(up: __safeDI_analyticsSendableBuilder_pageBuilder_serviceBuilder))
			                    }
			                    let pageBuilder = SendableInstantiator<Page>(__safeDI_pageBuilder)
			                    let analytics: any Analytics = __safeDI_page_serviceBuilder.analytics(SafeDIMockScope_Analytics.DefaultService_Scope.analytics_Values(pageBuilder: pageBuilder))
			                    return DefaultService(analytics: analytics, pageBuilder: pageBuilder)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            @Sendable nonisolated func __safeDI_serviceBuilder_Page(up: Page.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>>) -> Page.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(service: { scope in __safeDI_serviceBuilder_Page_service(scope, __safeDI_page_serviceBuilder: up.service(scope)) })
			            }
			            _ = Page.__safeDI_Page_mock_4A57B09DFB8A9D2C.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
			            return Page.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Page(up: __safeDI_analyticsSendableBuilder_page_serviceBuilder))
			        }
			        let page: Page = __safeDI_page()
			        return Screen(page: page)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_35D57403AB266355 {}
			}
			#endif
			"""
		}
	}

	/// The files the tool generates for `Core`, `Mid`, `App` and `Top` where `Top` calls `Screen`’s public mock.
	private static let expectedFilesCalledFromAnotherModule = [
		"Core": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Page {
		    nonisolated public enum SafeDIMockScope_Logger {
		        nonisolated public struct logger_Values {
		            public let service: any Service
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let logger: (logger_Values) -> __safeDI_Built

		            public init(logger: @escaping (logger_Values) -> __safeDI_Built) {
		                self.logger = logger
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(logger: { _ in __safeDI_builder() })
		            }
		        }
		    }

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
		        loggerBuilder: @escaping () -> any Logger,
		        serviceBuilder: @escaping () -> any Service
		    ) -> Page {
		        Page.__safeDI_mock(loggerBuilder: .init(__safeDI_noScope: loggerBuilder), serviceBuilder: .init(__safeDI_noScope: serviceBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        loggerBuilder __safeDI_loggerBuilder: Page.SafeDIMockScope_Logger.__safeDI_Builder<any Logger>,
		        serviceBuilder __safeDI_serviceBuilder: Page.SafeDIMockScope_Service.__safeDI_Builder<any Service>
		    ) -> Page {
		        let service: any Service = __safeDI_serviceBuilder.service(SafeDIMockScope_Service.service_Values())
		        let logger: any Logger = __safeDI_loggerBuilder.logger(SafeDIMockScope_Logger.logger_Values(service: service))
		        return Page(service: service, logger: logger)
		    }
		}

		extension Page {
		    public enum __safeDI_Page_mock_D554EC7204DBF437 {}
		}
		#endif
		""",
		"Mid": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Book {
		    nonisolated public enum SafeDIMockScope_Logger {
		        nonisolated public struct pageBuilder_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let pageBuilder: (pageBuilder_Values) -> Page.SafeDIMockScope_Logger.__safeDI_Builder<__safeDI_Built>

		            public init(pageBuilder: @escaping (pageBuilder_Values) -> Page.SafeDIMockScope_Logger.__safeDI_Builder<__safeDI_Built>) {
		                self.pageBuilder = pageBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(pageBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    nonisolated public enum SafeDIMockScope_Service {
		        nonisolated public struct pageBuilder_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let pageBuilder: (pageBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>

		            public init(pageBuilder: @escaping (pageBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>) {
		                self.pageBuilder = pageBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(pageBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init() {}
		    }

		    public static func mock(
		        loggerBuilder: @escaping () -> any Logger,
		        serviceBuilder: @escaping () -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Book {
		        Book.__safeDI_mock(loggerBuilder: .init(__safeDI_noScope: loggerBuilder), serviceBuilder: .init(__safeDI_noScope: serviceBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        loggerBuilder __safeDI_loggerBuilder: Book.SafeDIMockScope_Logger.__safeDI_Builder<any Logger>,
		        serviceBuilder __safeDI_serviceBuilder: Book.SafeDIMockScope_Service.__safeDI_Builder<any Service>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Book {
		        _ = Page.__safeDI_Page_mock_D554EC7204DBF437.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
		        func __safeDI_pageBuilder() -> Page {
		            Page.__safeDI_mock(loggerBuilder: __safeDI_loggerBuilder.pageBuilder(SafeDIMockScope_Logger.pageBuilder_Values()), serviceBuilder: __safeDI_serviceBuilder.pageBuilder(SafeDIMockScope_Service.pageBuilder_Values()))
		        }
		        let pageBuilder = Instantiator<Page>(__safeDI_pageBuilder)
		        return Book(pageBuilder: pageBuilder)
		    }
		}

		extension Book {
		    public enum __safeDI_Book_mock_BB5F55D5B8AAE3B1 {}
		}
		#endif
		""",
		"App": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Mid)
		import Mid
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    nonisolated public enum SafeDIMockScope_Analytics {
		        nonisolated public struct page_loggerBuilder_Values {}

		        nonisolated public struct page_serviceBuilder_Values {}

		        nonisolated public enum DefaultLogger_Scope {
		            nonisolated public struct analytics_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let analytics: (analytics_Values) -> __safeDI_Built

		                public init(analytics: @escaping (analytics_Values) -> __safeDI_Built) {
		                    self.analytics = analytics
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(analytics: { _ in __safeDI_builder() })
		                }
		            }
		        }

		        nonisolated public enum DefaultService_Scope {
		            nonisolated public struct book_loggerBuilder_Values {}

		            nonisolated public struct book_serviceBuilder_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let book_loggerBuilder: (book_loggerBuilder_Values) -> Book.SafeDIMockScope_Logger.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultLogger_Scope.__safeDI_Builder<__safeDI_Built>>
		                public let book_serviceBuilder: (book_serviceBuilder_Values) -> Book.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

		                public init(book_loggerBuilder: @escaping (book_loggerBuilder_Values) -> Book.SafeDIMockScope_Logger.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultLogger_Scope.__safeDI_Builder<__safeDI_Built>>, book_serviceBuilder: @escaping (book_serviceBuilder_Values) -> Book.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                    self.book_loggerBuilder = book_loggerBuilder
		                    self.book_serviceBuilder = book_serviceBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(book_loggerBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }, book_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let page_loggerBuilder: (page_loggerBuilder_Values) -> Page.SafeDIMockScope_Logger.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultLogger_Scope.__safeDI_Builder<__safeDI_Built>>
		            public let page_serviceBuilder: (page_serviceBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(page_loggerBuilder: @escaping (page_loggerBuilder_Values) -> Page.SafeDIMockScope_Logger.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultLogger_Scope.__safeDI_Builder<__safeDI_Built>>, page_serviceBuilder: @escaping (page_serviceBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.page_loggerBuilder = page_loggerBuilder
		                self.page_serviceBuilder = page_serviceBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(page_loggerBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }, page_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init() {}
		    }

		    public static func mock(
		        analyticsBuilder: @escaping () -> any Analytics,
		        loggerBuilder: (() -> any Logger)? = nil,
		        serviceBuilder: (() -> any Service)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        Screen.__safeDI_mock(analyticsBuilder: .init(__safeDI_noScope: analyticsBuilder), loggerBuilder: loggerBuilder, serviceBuilder: serviceBuilder, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        analyticsBuilder __safeDI_analyticsBuilder: Screen.SafeDIMockScope_Analytics.__safeDI_Builder<any Analytics>,
		        loggerBuilder __safeDI_loggerBuilder: (() -> any Logger)? = nil,
		        serviceBuilder __safeDI_serviceBuilder: (() -> any Service)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let __safeDI_analyticsBuilder_page_loggerBuilder = __safeDI_analyticsBuilder.page_loggerBuilder(SafeDIMockScope_Analytics.page_loggerBuilder_Values())
		        let __safeDI_analyticsBuilder_page_serviceBuilder = __safeDI_analyticsBuilder.page_serviceBuilder(SafeDIMockScope_Analytics.page_serviceBuilder_Values())
		        func __safeDI_page() -> Page {
		            func __safeDI_serviceBuilder_Page_service(_ scope: Page.SafeDIMockScope_Service.service_Values, __safeDI_page_serviceBuilder: SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>) -> any Service {
		                func __safeDI_service() -> DefaultService {
		                    let __safeDI_analyticsBuilder_book_loggerBuilder = __safeDI_page_serviceBuilder.book_loggerBuilder(SafeDIMockScope_Analytics.DefaultService_Scope.book_loggerBuilder_Values())
		                    let __safeDI_analyticsBuilder_book_serviceBuilder = __safeDI_page_serviceBuilder.book_serviceBuilder(SafeDIMockScope_Analytics.DefaultService_Scope.book_serviceBuilder_Values())
		                    func __safeDI_book() -> Book {
		                        func __safeDI_loggerBuilder_Book(up: Book.SafeDIMockScope_Logger.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultLogger_Scope.__safeDI_Builder<any Analytics>>) -> Book.SafeDIMockScope_Logger.__safeDI_Builder<any Logger> {
		                            .init(pageBuilder: { values in __safeDI_loggerBuilder_Page(up: up.pageBuilder(values)) })
		                        }
		                        func __safeDI_serviceBuilder_Book(up: Book.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>>) -> Book.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
		                            .init(pageBuilder: { values in __safeDI_serviceBuilder_Page(up: up.pageBuilder(values)) })
		                        }
		                        return Book.__safeDI_mock(loggerBuilder: __safeDI_loggerBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_loggerBuilder_Book(up: __safeDI_analyticsBuilder_book_loggerBuilder), serviceBuilder: __safeDI_serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Book(up: __safeDI_analyticsBuilder_book_serviceBuilder))
		                    }
		                    let book: Book = __safeDI_book()
		                    return DefaultService(book: book)
		                }
		                let service: any Service = __safeDI_service()
		                return service
		            }
		            func __safeDI_loggerBuilder_Page_logger(_ scope: Page.SafeDIMockScope_Logger.logger_Values, __safeDI_page_loggerBuilder: SafeDIMockScope_Analytics.DefaultLogger_Scope.__safeDI_Builder<any Analytics>) -> any Logger {
		                func __safeDI_logger() -> DefaultLogger {
		                    let analytics: any Analytics = __safeDI_page_loggerBuilder.analytics(SafeDIMockScope_Analytics.DefaultLogger_Scope.analytics_Values())
		                    return DefaultLogger(analytics: analytics)
		                }
		                let logger: any Logger = __safeDI_logger()
		                return logger
		            }
		            func __safeDI_loggerBuilder_Page(up: Page.SafeDIMockScope_Logger.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultLogger_Scope.__safeDI_Builder<any Analytics>>) -> Page.SafeDIMockScope_Logger.__safeDI_Builder<any Logger> {
		                .init(logger: { scope in __safeDI_loggerBuilder_Page_logger(scope, __safeDI_page_loggerBuilder: up.logger(scope)) })
		            }
		            func __safeDI_serviceBuilder_Page(up: Page.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>>) -> Page.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
		                .init(service: { scope in __safeDI_serviceBuilder_Page_service(scope, __safeDI_page_serviceBuilder: up.service(scope)) })
		            }
		            _ = Page.__safeDI_Page_mock_D554EC7204DBF437.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
		            return Page.__safeDI_mock(loggerBuilder: __safeDI_loggerBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_loggerBuilder_Page(up: __safeDI_analyticsBuilder_page_loggerBuilder), serviceBuilder: __safeDI_serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Page(up: __safeDI_analyticsBuilder_page_serviceBuilder))
		        }
		        let page: Page = __safeDI_page()
		        return Screen(page: page)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_ACC62E339A62491E {}
		}
		#endif
		""",
		"Top": generatedFileHeader + """
		#if canImport(App)
		import App
		#endif
		#if canImport(Core)
		import Core
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
		        analyticsBuilder: (() -> any Analytics)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_screen() -> Screen {
		            func __safeDI_analyticsBuilder_Screen() -> Screen.SafeDIMockScope_Analytics.__safeDI_Builder<any Analytics> {
		                .init(page_loggerBuilder: { _ in __safeDI_analyticsBuilder_Screen_Page_SafeDIMockScope_Logger() }, page_serviceBuilder: { _ in __safeDI_analyticsBuilder_Screen_Page_SafeDIMockScope_Service() })
		            }
		            func __safeDI_analyticsBuilder_Screen_Page_SafeDIMockScope_Logger() -> Page.SafeDIMockScope_Logger.__safeDI_Builder<Screen.SafeDIMockScope_Analytics.DefaultLogger_Scope.__safeDI_Builder<any Analytics>> {
		                .init(logger: { _ in __safeDI_analyticsBuilder_Screen_DefaultLogger_Scope() })
		            }
		            func __safeDI_analyticsBuilder_Screen_DefaultLogger_Scope() -> Screen.SafeDIMockScope_Analytics.DefaultLogger_Scope.__safeDI_Builder<any Analytics> {
		                .init(analytics: { _ in
		                    let analytics: any Analytics = LiveAnalytics()
		                    return analytics
		                })
		            }
		            func __safeDI_analyticsBuilder_Screen_Page_SafeDIMockScope_Service() -> Page.SafeDIMockScope_Service.__safeDI_Builder<Screen.SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>> {
		                .init(service: { _ in __safeDI_analyticsBuilder_Screen_DefaultService_Scope() })
		            }
		            func __safeDI_analyticsBuilder_Screen_DefaultService_Scope() -> Screen.SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics> {
		                .init(book_loggerBuilder: { _ in __safeDI_analyticsBuilder_Screen_Book_SafeDIMockScope_Logger() }, book_serviceBuilder: { _ in __safeDI_analyticsBuilder_Screen_Book_SafeDIMockScope_Service() })
		            }
		            func __safeDI_analyticsBuilder_Screen_Book_SafeDIMockScope_Logger() -> Book.SafeDIMockScope_Logger.__safeDI_Builder<Screen.SafeDIMockScope_Analytics.DefaultLogger_Scope.__safeDI_Builder<any Analytics>> {
		                .init(pageBuilder: { _ in __safeDI_analyticsBuilder_Screen_Page_SafeDIMockScope_Logger() })
		            }
		            func __safeDI_analyticsBuilder_Screen_Book_SafeDIMockScope_Service() -> Book.SafeDIMockScope_Service.__safeDI_Builder<Screen.SafeDIMockScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>> {
		                .init(pageBuilder: { _ in __safeDI_analyticsBuilder_Screen_Page_SafeDIMockScope_Service() })
		            }
		            _ = Screen.__safeDI_Screen_mock_ACC62E339A62491E.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Screen", declaringModule: "App"))
		            return Screen.__safeDI_mock(analyticsBuilder: analyticsBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_analyticsBuilder_Screen(), safeDIOverrides: safeDIOverrides.screen)
		        }
		        let screen: Screen = __safeDI_screen()
		        return Root(screen: screen)
		    }
		}
		#endif
		""",
	]

	/// Expects the calling mock `output`, generated for `modules` and compiled, to have compiled, and to build for each of
	/// `probes` what the same types built inline build (`GraphFuzzerCallingMockGraph.inlineModules`). A module that does not
	/// compile is recorded as `verifyGeneratedCodeCompiles` records it, and nothing is compared.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectCompilesAndBuildsInlineValues(of graph: GraphFuzzerCallingMockGraph, output: MultiModuleTestOutput, modules: [ModuleFixture], probes: [DifferentialValueProbe], sourceLocation: SourceLocation = #_sourceLocation) async throws {
		let compilation = try #require(output.compilation, sourceLocation: sourceLocation)
		if let failure = compilation.failure {
			failure.recordIssues(skippingVerificationBy: "pass `compileVerification: .skipped`", sourceLocation: sourceLocation)
		} else {
			let inlineModules = graph.inlineModules
			let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inlineModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
			let comparison = try #require(try await DifferentialValueOracle.compare(
				feature: DifferentialValuePath(output: output, modules: modules),
				knownRight: DifferentialValuePath(output: inlineOutput, modules: inlineModules),
				probes: probes,
				filesToDelete: &filesToDelete,
			), sourceLocation: sourceLocation)
			for difference in comparison.differences {
				Issue.record("The calling mock builds other values than inline for \(difference)\n\(comparison.report)", sourceLocation: sourceLocation)
			}
		}
	}
}
