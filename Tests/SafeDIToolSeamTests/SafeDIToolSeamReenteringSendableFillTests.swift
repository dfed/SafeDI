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

/// A seam whose fill of another seam’s place builds a type of a third module that holds the called seam in a
/// `SendableInstantiator`, and whose tree, through that re-entry or beside it, instantiates a type no declaration the
/// seam’s module sees fulfills. The fill is built in the `@Sendable` function of that builder, so the seam takes a
/// `@Sendable` builder of the type; the level of the fill that makes the call is of the plain family, and its member
/// for that call returns the third module’s `@Sendable` family’s struct, so its no-scope initializer, and that of each
/// level that hands it its builder, takes a `@Sendable` builder, as the root’s does.
struct SafeDIToolSeamReenteringSendableFillTests: ~Copyable {
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

	@Test(arguments: ReenteringFillLayout.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesSendableBuilderOfWhatNothingFulfills_whenReenteringBuilderIsSendableInstantiator(layout: ReenteringFillLayout) async throws {
		// `Screen` fills `Page`’s place with a type whose tree builds `Book`, whose `SendableInstantiator` of `Page` re-enters
		// that fill, and instantiates `analytics: any Analytics`, which nothing `App` sees fulfills. `Screen` takes
		// `analyticsSendableBuilder`, and the generated code compiles and builds, for a builder handed through the
		// generated-only initializer’s no-scope struct, what the same types built inline build.
		let modules = Self.modules(of: layout, analyticsIsInstantiable: false)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)

		let expected = ["Core": Self.expectedCore(of: layout), "Mid": Self.expectedMid(of: layout), "App": Self.expectedApp(of: layout)]
		for module in ["Core", "Mid", "App"] {
			#expect(output.modules[module]?.generatedFiles == [module + ".swift": expected[module] ?? ""], "\(module)")
		}
		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation)
		if let failure = compilation.failure {
			failure.recordIssues(skippingVerificationBy: "pass `compileVerification: .skipped`", sourceLocation: #_sourceLocation)
		} else {
			let inlineModules = Self.inlineModules(of: layout)
			let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inlineModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
			let probe = DifferentialValueProbe(
				name: "(Screen, the re-entered Page)",
				expression: ReenteringFillFixtures.screenAndReenteredPage(of: layout, screen: "App.Screen(__safeDI_analyticsSendableBuilder: .init(__safeDI_noScope: { App.LiveAnalytics() }))"),
				knownRightExpression: ReenteringFillFixtures.screenAndReenteredPage(of: layout, screen: "App.Screen()"),
			)
			let comparison = try #require(try await DifferentialValueOracle.compare(
				feature: DifferentialValuePath(output: output, modules: modules),
				knownRight: DifferentialValuePath(output: inlineOutput, modules: inlineModules),
				probes: [probe],
				filesToDelete: &filesToDelete,
			))
			for difference in comparison.differences {
				Issue.record("The seam builds other values than inline for \(difference)\n\(comparison.report)")
			}
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The modules of `layout` with `Book`, and `DefaultService` where it holds `Page` itself, holding `Page` in a
	/// `SendableInstantiator`: `Page`, `Chapter` and `Book` seams that keep their public mocks, and `Screen` a seam of `App`.
	/// Where `analyticsIsInstantiable`, `LiveAnalytics` is an `Instantiable` that fulfills `Analytics`, else a plain class a
	/// probe hands `Screen`’s builder.
	private static func modules(of layout: ReenteringFillLayout, analyticsIsInstantiable: Bool) -> [ModuleFixture] {
		let attribute = ReenteringFillFixtures.seamAndPublicMock
		return [
			ModuleFixture(name: "Core", packageName: GraphFuzzerCallingMockGraph.packageName, swiftFileContentByFilePath: ["CoreTypes.swift": ReenteringFillFixtures.core(of: layout, attribute: attribute)]),
			ModuleFixture(name: "Mid", packageName: GraphFuzzerCallingMockGraph.packageName, swiftFileContentByFilePath: ["MidTypes.swift": ReenteringFillFixtures.mid(of: layout, attribute: attribute, builder: .sendableInstantiator)], dependencies: ["Core"]),
			ModuleFixture(name: "App", packageName: GraphFuzzerCallingMockGraph.packageName, swiftFileContentByFilePath: ["AppTypes.swift": ReenteringFillFixtures.app(of: layout, callerAttribute: "@Instantiable(generateDependencyTree: true)", access: "public ", analyticsIsInstantiable: analyticsIsInstantiable, builder: .sendableInstantiator)], dependencies: ["Core", "Mid"]),
		]
	}

	/// The same types built inline, in one module named `App`, with `LiveAnalytics` an `Instantiable` that fulfills
	/// `Analytics` and `Screen` a root (`GraphFuzzerCallingMockGraph.inlineModules`).
	private static func inlineModules(of layout: ReenteringFillLayout) -> [ModuleFixture] {
		let files = modules(of: layout, analyticsIsInstantiable: true).map { module in
			GraphFuzzerCallingMockGraph.File(module: module.name, dependencies: module.dependencies, content: module.swiftFileContentByFilePath["\(module.name)Types.swift"] ?? "")
		}
		return GraphFuzzerCallingMockGraph(
			name: "a seam whose fill is re-entered through a SendableInstantiator",
			mockFiles: files,
			twinFiles: files,
			callerTypeName: "Screen",
			callerIsPublic: true,
			mockConfiguration: nil,
			flatParameterLabels: [],
			implementationIsVisible: true,
			expectedTwinInitializerLabels: [],
			expectedPassUpLabels: [],
			expectedTwinErrorSite: nil,
			valueProbes: nil,
		).inlineModules
	}

	/// The file the tool generates for `Core` in a cell of `layout`.
	private static func expectedCore(of layout: ReenteringFillLayout) -> String {
		switch layout {
		case .fillInstantiatesIt, .calledMocksOwnPlacesFillInstantiatesIt, .fillCallsCalledTypeItselfBesideUncalledHolder:
			generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			extension Page {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
			        public let service: () -> __safeDI_Built

			        public init(service: @escaping () -> __safeDI_Built) {
			            self.service = service
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(service: { __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public convenience init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
			        let service: any Service = __safeDI_serviceBuilder.service()
			        self.init(service: service)
			    }
			}

			extension Page {
			    public enum __safeDI_Page_CC6D10F1397D8E8C {}
			}

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

			extension Page {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_LoggerCarrier<__safeDI_Built> {
			        public let logger: (any Service) -> __safeDI_Built

			        public init(logger: @escaping (any Service) -> __safeDI_Built) {
			            self.logger = logger
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(logger: { _ in __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
			        public let service: () -> __safeDI_Built

			        public init(service: @escaping () -> __safeDI_Built) {
			            self.service = service
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(service: { __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public convenience init(__safeDI_loggerBuilder: __safeDI_LoggerCarrier<any Logger>, __safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
			        let service: any Service = __safeDI_serviceBuilder.service()
			        let logger: any Logger = __safeDI_loggerBuilder.logger(service)
			        self.init(service: service, logger: logger)
			    }
			}

			extension Page {
			    public enum __safeDI_Page_BA8C90641C61521E {}
			}

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
		case .nestedCallsFillInstantiatesIt, .fillAroundNestedCallInstantiatesIt:
			generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			extension Chapter {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_StoreCarrier<__safeDI_Built> {
			        public let store: () -> __safeDI_Built

			        public init(store: @escaping () -> __safeDI_Built) {
			            self.store = store
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(store: { __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public convenience init(__safeDI_storeBuilder: __safeDI_StoreCarrier<any Store>) {
			        let store: any Store = __safeDI_storeBuilder.store()
			        self.init(store: store)
			    }
			}

			extension Chapter {
			    public enum __safeDI_Chapter_C2B4DD008D11C74A {}
			}

			extension Page {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
			        public let service: () -> __safeDI_Built

			        public init(service: @escaping () -> __safeDI_Built) {
			            self.service = service
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(service: { __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public convenience init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
			        let service: any Service = __safeDI_serviceBuilder.service()
			        self.init(service: service)
			    }
			}

			extension Page {
			    public enum __safeDI_Page_CC6D10F1397D8E8C {}
			}

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
		}
	}

	/// The file the tool generates for `Mid` in a cell of `layout`.
	private static func expectedMid(of layout: ReenteringFillLayout) -> String {
		switch layout {
		case .fillInstantiatesIt, .nestedCallsFillInstantiatesIt, .fillAroundNestedCallInstantiatesIt, .fillCallsCalledTypeItselfBesideUncalledHolder:
			generatedFileHeader + """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			extension Book {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceSendableCarrier<__safeDI_Built>: Sendable {
			        public let pageBuilder: @Sendable () -> Page.__safeDI_ServiceCarrier<__safeDI_Built>

			        public init(pageBuilder: @escaping @Sendable () -> Page.__safeDI_ServiceCarrier<__safeDI_Built>) {
			            self.pageBuilder = pageBuilder
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			            self.init(pageBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public convenience init(__safeDI_serviceSendableBuilder: __safeDI_ServiceSendableCarrier<any Service>) {
			        @Sendable nonisolated func __safeDI_pageBuilder() -> Page {
			            _ = Page.__safeDI_Page_CC6D10F1397D8E8C.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
			            return Page(__safeDI_serviceBuilder: __safeDI_serviceSendableBuilder.pageBuilder())
			        }
			        let pageBuilder = SendableInstantiator<Page>(__safeDI_pageBuilder)
			        self.init(pageBuilder: pageBuilder)
			    }
			}

			extension Book {
			    public enum __safeDI_Book_55BCEAB8683D88DE {}
			}

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

			extension Book {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_LoggerSendableCarrier<__safeDI_Built>: Sendable {
			        public let pageBuilder: @Sendable () -> Page.__safeDI_LoggerCarrier<__safeDI_Built>

			        public init(pageBuilder: @escaping @Sendable () -> Page.__safeDI_LoggerCarrier<__safeDI_Built>) {
			            self.pageBuilder = pageBuilder
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			            self.init(pageBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceSendableCarrier<__safeDI_Built>: Sendable {
			        public let pageBuilder: @Sendable () -> Page.__safeDI_ServiceCarrier<__safeDI_Built>

			        public init(pageBuilder: @escaping @Sendable () -> Page.__safeDI_ServiceCarrier<__safeDI_Built>) {
			            self.pageBuilder = pageBuilder
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			            self.init(pageBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public convenience init(__safeDI_loggerSendableBuilder: __safeDI_LoggerSendableCarrier<any Logger>, __safeDI_serviceSendableBuilder: __safeDI_ServiceSendableCarrier<any Service>) {
			        @Sendable nonisolated func __safeDI_pageBuilder() -> Page {
			            _ = Page.__safeDI_Page_BA8C90641C61521E.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
			            return Page(__safeDI_loggerBuilder: __safeDI_loggerSendableBuilder.pageBuilder(), __safeDI_serviceBuilder: __safeDI_serviceSendableBuilder.pageBuilder())
			        }
			        let pageBuilder = SendableInstantiator<Page>(__safeDI_pageBuilder)
			        self.init(pageBuilder: pageBuilder)
			    }
			}

			extension Book {
			    public enum __safeDI_Book_5A6B93E70D2E207D {}
			}

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

			extension Book {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceSendableCarrier<__safeDI_Built>: Sendable {
			        public let pageBuilder: @Sendable () -> Page.__safeDI_ServiceCarrier<__safeDI_Built>

			        public init(pageBuilder: @escaping @Sendable () -> Page.__safeDI_ServiceCarrier<__safeDI_Built>) {
			            self.pageBuilder = pageBuilder
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			            self.init(pageBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_StoreCarrier<__safeDI_Built> {
			        public let store: (SendableInstantiator<Page>) -> __safeDI_Built

			        public init(store: @escaping (SendableInstantiator<Page>) -> __safeDI_Built) {
			            self.store = store
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(store: { _ in __safeDI_builder() })
			        }
			    }

			    // SafeDI counts `Store` as `public`: no module it reads declares it narrower. If `Store` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public convenience init(__safeDI_serviceSendableBuilder: __safeDI_ServiceSendableCarrier<any Service>, __safeDI_storeBuilder: __safeDI_StoreCarrier<any Store>) {
			        @Sendable nonisolated func __safeDI_pageBuilder() -> Page {
			            _ = Page.__safeDI_Page_CC6D10F1397D8E8C.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
			            return Page(__safeDI_serviceBuilder: __safeDI_serviceSendableBuilder.pageBuilder())
			        }
			        let pageBuilder = SendableInstantiator<Page>(__safeDI_pageBuilder)
			        let store: any Store = __safeDI_storeBuilder.store(pageBuilder)
			        self.init(pageBuilder: pageBuilder, store: store)
			    }
			}

			extension Book {
			    public enum __safeDI_Book_A6065A611EBF78F3 {}
			}

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

	/// The file the tool generates for `App` in a cell of `layout`.
	private static func expectedApp(of layout: ReenteringFillLayout) -> String {
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

			extension Screen {
			    nonisolated public enum SafeDIScope_Analytics {
			        nonisolated public enum DefaultService_Scope {
			            nonisolated public struct analytics_Values {
			                public let book: Book
			            }

			            nonisolated public struct book_serviceSendableBuilder_Values {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let analytics: (analytics_Values) -> __safeDI_Built
			                public let book_serviceSendableBuilder: (book_serviceSendableBuilder_Values) -> Book.__safeDI_ServiceSendableCarrier<SafeDIScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			                public init(analytics: @escaping (analytics_Values) -> __safeDI_Built, book_serviceSendableBuilder: @escaping (book_serviceSendableBuilder_Values) -> Book.__safeDI_ServiceSendableCarrier<SafeDIScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                    self.analytics = analytics
			                    self.book_serviceSendableBuilder = book_serviceSendableBuilder
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                    self.init(analytics: { _ in __safeDI_builder() }, book_serviceSendableBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			                }
			            }
			        }
			    }

			    nonisolated public enum SafeDISendableScope_Analytics {
			        nonisolated public struct page_serviceBuilder_Values: Sendable {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			            public let page_serviceBuilder: @Sendable (page_serviceBuilder_Values) -> Page.__safeDI_ServiceCarrier<SafeDIScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(page_serviceBuilder: @escaping @Sendable (page_serviceBuilder_Values) -> Page.__safeDI_ServiceCarrier<SafeDIScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.page_serviceBuilder = page_serviceBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                self.init(page_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			            }
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public convenience init(__safeDI_analyticsSendableBuilder: SafeDISendableScope_Analytics.__safeDI_Builder<any Analytics>) {
			        func __safeDI_page() -> Page {
			            let __safeDI_analyticsSendableBuilder_page_serviceBuilder = __safeDI_analyticsSendableBuilder.page_serviceBuilder(SafeDISendableScope_Analytics.page_serviceBuilder_Values())
			            _ = Page.__safeDI_Page_CC6D10F1397D8E8C.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
			            @Sendable nonisolated func __safeDI_serviceBuilder_Page_service(__safeDI_page_serviceBuilder: SafeDIScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let __safeDI_analyticsSendableBuilder_book_serviceSendableBuilder = __safeDI_page_serviceBuilder.book_serviceSendableBuilder(SafeDIScope_Analytics.DefaultService_Scope.book_serviceSendableBuilder_Values())
			                    func __safeDI_book() -> Book {
			                        _ = Book.__safeDI_Book_55BCEAB8683D88DE.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Book", declaringModule: "Mid"))
			                        @Sendable nonisolated func __safeDI_serviceSendableBuilder_Book(up: Book.__safeDI_ServiceSendableCarrier<SafeDIScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>>) -> Book.__safeDI_ServiceSendableCarrier<any Service> {
			                            .init(pageBuilder: { __safeDI_serviceBuilder_Page(up: up.pageBuilder()) })
			                        }
			                        return Book(__safeDI_serviceSendableBuilder: __safeDI_serviceSendableBuilder_Book(up: __safeDI_analyticsSendableBuilder_book_serviceSendableBuilder))
			                    }
			                    let book: Book = __safeDI_book()
			                    let analytics: any Analytics = __safeDI_page_serviceBuilder.analytics(SafeDIScope_Analytics.DefaultService_Scope.analytics_Values(book: book))
			                    return DefaultService(analytics: analytics, book: book)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            @Sendable nonisolated func __safeDI_serviceBuilder_Page(up: Page.__safeDI_ServiceCarrier<SafeDIScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>>) -> Page.__safeDI_ServiceCarrier<any Service> {
			                .init(service: { __safeDI_serviceBuilder_Page_service(__safeDI_page_serviceBuilder: up.service()) })
			            }
			            return Page(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Page(up: __safeDI_analyticsSendableBuilder_page_serviceBuilder))
			        }
			        let page: Page = __safeDI_page()
			        self.init(page: page)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_4884E835EACBF68D {}
			}
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

			extension Screen {
			    nonisolated public enum SafeDIScope_Analytics {
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
			                public let book_loggerSendableBuilder: (book_loggerSendableBuilder_Values) -> Book.__safeDI_LoggerSendableCarrier<SafeDIScope_Analytics.DefaultLogger_Scope.__safeDI_Builder<__safeDI_Built>>
			                public let book_serviceSendableBuilder: (book_serviceSendableBuilder_Values) -> Book.__safeDI_ServiceSendableCarrier<SafeDIScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			                public init(book_loggerSendableBuilder: @escaping (book_loggerSendableBuilder_Values) -> Book.__safeDI_LoggerSendableCarrier<SafeDIScope_Analytics.DefaultLogger_Scope.__safeDI_Builder<__safeDI_Built>>, book_serviceSendableBuilder: @escaping (book_serviceSendableBuilder_Values) -> Book.__safeDI_ServiceSendableCarrier<SafeDIScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                    self.book_loggerSendableBuilder = book_loggerSendableBuilder
			                    self.book_serviceSendableBuilder = book_serviceSendableBuilder
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                    self.init(book_loggerSendableBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }, book_serviceSendableBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			                }
			            }
			        }
			    }

			    nonisolated public enum SafeDISendableScope_Analytics {
			        nonisolated public struct page_loggerBuilder_Values: Sendable {}

			        nonisolated public struct page_serviceBuilder_Values: Sendable {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			            public let page_loggerBuilder: @Sendable (page_loggerBuilder_Values) -> Page.__safeDI_LoggerCarrier<SafeDIScope_Analytics.DefaultLogger_Scope.__safeDI_Builder<__safeDI_Built>>
			            public let page_serviceBuilder: @Sendable (page_serviceBuilder_Values) -> Page.__safeDI_ServiceCarrier<SafeDIScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(page_loggerBuilder: @escaping @Sendable (page_loggerBuilder_Values) -> Page.__safeDI_LoggerCarrier<SafeDIScope_Analytics.DefaultLogger_Scope.__safeDI_Builder<__safeDI_Built>>, page_serviceBuilder: @escaping @Sendable (page_serviceBuilder_Values) -> Page.__safeDI_ServiceCarrier<SafeDIScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.page_loggerBuilder = page_loggerBuilder
			                self.page_serviceBuilder = page_serviceBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                self.init(page_loggerBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }, page_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			            }
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public convenience init(__safeDI_analyticsSendableBuilder: SafeDISendableScope_Analytics.__safeDI_Builder<any Analytics>) {
			        func __safeDI_page() -> Page {
			            let __safeDI_analyticsSendableBuilder_page_loggerBuilder = __safeDI_analyticsSendableBuilder.page_loggerBuilder(SafeDISendableScope_Analytics.page_loggerBuilder_Values())
			            let __safeDI_analyticsSendableBuilder_page_serviceBuilder = __safeDI_analyticsSendableBuilder.page_serviceBuilder(SafeDISendableScope_Analytics.page_serviceBuilder_Values())
			            _ = Page.__safeDI_Page_BA8C90641C61521E.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
			            @Sendable nonisolated func __safeDI_serviceBuilder_Page_service(__safeDI_page_serviceBuilder: SafeDIScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let __safeDI_analyticsSendableBuilder_book_loggerSendableBuilder = __safeDI_page_serviceBuilder.book_loggerSendableBuilder(SafeDIScope_Analytics.DefaultService_Scope.book_loggerSendableBuilder_Values())
			                    let __safeDI_analyticsSendableBuilder_book_serviceSendableBuilder = __safeDI_page_serviceBuilder.book_serviceSendableBuilder(SafeDIScope_Analytics.DefaultService_Scope.book_serviceSendableBuilder_Values())
			                    func __safeDI_book() -> Book {
			                        _ = Book.__safeDI_Book_5A6B93E70D2E207D.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Book", declaringModule: "Mid"))
			                        @Sendable nonisolated func __safeDI_loggerSendableBuilder_Book(up: Book.__safeDI_LoggerSendableCarrier<SafeDIScope_Analytics.DefaultLogger_Scope.__safeDI_Builder<any Analytics>>) -> Book.__safeDI_LoggerSendableCarrier<any Logger> {
			                            .init(pageBuilder: { __safeDI_loggerBuilder_Page(up: up.pageBuilder()) })
			                        }
			                        @Sendable nonisolated func __safeDI_serviceSendableBuilder_Book(up: Book.__safeDI_ServiceSendableCarrier<SafeDIScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>>) -> Book.__safeDI_ServiceSendableCarrier<any Service> {
			                            .init(pageBuilder: { __safeDI_serviceBuilder_Page(up: up.pageBuilder()) })
			                        }
			                        return Book(__safeDI_loggerSendableBuilder: __safeDI_loggerSendableBuilder_Book(up: __safeDI_analyticsSendableBuilder_book_loggerSendableBuilder), __safeDI_serviceSendableBuilder: __safeDI_serviceSendableBuilder_Book(up: __safeDI_analyticsSendableBuilder_book_serviceSendableBuilder))
			                    }
			                    let book: Book = __safeDI_book()
			                    return DefaultService(book: book)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            @Sendable nonisolated func __safeDI_loggerBuilder_Page_logger(_ scope_service: any Service, __safeDI_page_loggerBuilder: SafeDIScope_Analytics.DefaultLogger_Scope.__safeDI_Builder<any Analytics>) -> any Logger {
			                func __safeDI_logger() -> DefaultLogger {
			                    let analytics: any Analytics = __safeDI_page_loggerBuilder.analytics(SafeDIScope_Analytics.DefaultLogger_Scope.analytics_Values())
			                    return DefaultLogger(analytics: analytics)
			                }
			                let logger: any Logger = __safeDI_logger()
			                return logger
			            }
			            @Sendable nonisolated func __safeDI_loggerBuilder_Page(up: Page.__safeDI_LoggerCarrier<SafeDIScope_Analytics.DefaultLogger_Scope.__safeDI_Builder<any Analytics>>) -> Page.__safeDI_LoggerCarrier<any Logger> {
			                .init(logger: { scope_service in __safeDI_loggerBuilder_Page_logger(scope_service, __safeDI_page_loggerBuilder: up.logger(scope_service)) })
			            }
			            @Sendable nonisolated func __safeDI_serviceBuilder_Page(up: Page.__safeDI_ServiceCarrier<SafeDIScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>>) -> Page.__safeDI_ServiceCarrier<any Service> {
			                .init(service: { __safeDI_serviceBuilder_Page_service(__safeDI_page_serviceBuilder: up.service()) })
			            }
			            return Page(__safeDI_loggerBuilder: __safeDI_loggerBuilder_Page(up: __safeDI_analyticsSendableBuilder_page_loggerBuilder), __safeDI_serviceBuilder: __safeDI_serviceBuilder_Page(up: __safeDI_analyticsSendableBuilder_page_serviceBuilder))
			        }
			        let page: Page = __safeDI_page()
			        self.init(page: page)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_D1D9F025758ACDEC {}
			}
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

			extension Screen {
			    nonisolated public enum SafeDIScope_Analytics {
			        nonisolated public enum DefaultService_Scope {
			            nonisolated public struct book_serviceSendableBuilder_Values {}

			            nonisolated public struct book_storeBuilder_Values {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let book_serviceSendableBuilder: (book_serviceSendableBuilder_Values) -> Book.__safeDI_ServiceSendableCarrier<SafeDIScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>
			                public let book_storeBuilder: (book_storeBuilder_Values) -> Book.__safeDI_StoreCarrier<SafeDIScope_Analytics.DefaultStore_Scope.__safeDI_Builder<__safeDI_Built>>

			                public init(book_serviceSendableBuilder: @escaping (book_serviceSendableBuilder_Values) -> Book.__safeDI_ServiceSendableCarrier<SafeDIScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>, book_storeBuilder: @escaping (book_storeBuilder_Values) -> Book.__safeDI_StoreCarrier<SafeDIScope_Analytics.DefaultStore_Scope.__safeDI_Builder<__safeDI_Built>>) {
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

			    nonisolated public enum SafeDISendableScope_Analytics {
			        nonisolated public struct page_serviceBuilder_Values: Sendable {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			            public let page_serviceBuilder: @Sendable (page_serviceBuilder_Values) -> Page.__safeDI_ServiceCarrier<SafeDIScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(page_serviceBuilder: @escaping @Sendable (page_serviceBuilder_Values) -> Page.__safeDI_ServiceCarrier<SafeDIScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.page_serviceBuilder = page_serviceBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                self.init(page_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			            }
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public convenience init(__safeDI_analyticsSendableBuilder: SafeDISendableScope_Analytics.__safeDI_Builder<any Analytics>) {
			        func __safeDI_page() -> Page {
			            let __safeDI_analyticsSendableBuilder_page_serviceBuilder = __safeDI_analyticsSendableBuilder.page_serviceBuilder(SafeDISendableScope_Analytics.page_serviceBuilder_Values())
			            _ = Page.__safeDI_Page_CC6D10F1397D8E8C.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
			            @Sendable nonisolated func __safeDI_serviceBuilder_Page_service(__safeDI_page_serviceBuilder: SafeDIScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let __safeDI_analyticsSendableBuilder_book_serviceSendableBuilder = __safeDI_page_serviceBuilder.book_serviceSendableBuilder(SafeDIScope_Analytics.DefaultService_Scope.book_serviceSendableBuilder_Values())
			                    let __safeDI_analyticsSendableBuilder_book_storeBuilder = __safeDI_page_serviceBuilder.book_storeBuilder(SafeDIScope_Analytics.DefaultService_Scope.book_storeBuilder_Values())
			                    func __safeDI_book() -> Book {
			                        _ = Book.__safeDI_Book_A6065A611EBF78F3.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Book", declaringModule: "Mid"))
			                        func __safeDI_storeBuilder_Book_store(_ scope_pageBuilder: SendableInstantiator<Page>, __safeDI_book_storeBuilder: SafeDIScope_Analytics.DefaultStore_Scope.__safeDI_Builder<any Analytics>) -> any Store {
			                            func __safeDI_store() -> DefaultStore {
			                                let analytics: any Analytics = __safeDI_book_storeBuilder.analytics(SafeDIScope_Analytics.DefaultStore_Scope.analytics_Values())
			                                return DefaultStore(analytics: analytics)
			                            }
			                            let store: any Store = __safeDI_store()
			                            return store
			                        }
			                        @Sendable nonisolated func __safeDI_serviceSendableBuilder_Book(up: Book.__safeDI_ServiceSendableCarrier<SafeDIScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>>) -> Book.__safeDI_ServiceSendableCarrier<any Service> {
			                            .init(pageBuilder: { __safeDI_serviceBuilder_Page(up: up.pageBuilder()) })
			                        }
			                        func __safeDI_storeBuilder_Book(up: Book.__safeDI_StoreCarrier<SafeDIScope_Analytics.DefaultStore_Scope.__safeDI_Builder<any Analytics>>) -> Book.__safeDI_StoreCarrier<any Store> {
			                            .init(store: { scope_pageBuilder in __safeDI_storeBuilder_Book_store(scope_pageBuilder, __safeDI_book_storeBuilder: up.store(scope_pageBuilder)) })
			                        }
			                        return Book(__safeDI_serviceSendableBuilder: __safeDI_serviceSendableBuilder_Book(up: __safeDI_analyticsSendableBuilder_book_serviceSendableBuilder), __safeDI_storeBuilder: __safeDI_storeBuilder_Book(up: __safeDI_analyticsSendableBuilder_book_storeBuilder))
			                    }
			                    let book: Book = __safeDI_book()
			                    return DefaultService(book: book)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            @Sendable nonisolated func __safeDI_serviceBuilder_Page(up: Page.__safeDI_ServiceCarrier<SafeDIScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>>) -> Page.__safeDI_ServiceCarrier<any Service> {
			                .init(service: { __safeDI_serviceBuilder_Page_service(__safeDI_page_serviceBuilder: up.service()) })
			            }
			            return Page(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Page(up: __safeDI_analyticsSendableBuilder_page_serviceBuilder))
			        }
			        let page: Page = __safeDI_page()
			        self.init(page: page)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_17F000DD26CE3CAF {}
			}
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

			extension Screen {
			    nonisolated public enum SafeDIScope_Analytics {
			        nonisolated public enum DefaultService_Scope {
			            nonisolated public struct chapter_storeBuilder_Values {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let chapter_storeBuilder: (chapter_storeBuilder_Values) -> Chapter.__safeDI_StoreCarrier<SafeDIScope_Analytics.DefaultStore_Scope.__safeDI_Builder<__safeDI_Built>>

			                public init(chapter_storeBuilder: @escaping (chapter_storeBuilder_Values) -> Chapter.__safeDI_StoreCarrier<SafeDIScope_Analytics.DefaultStore_Scope.__safeDI_Builder<__safeDI_Built>>) {
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
			                public let book_serviceSendableBuilder: (book_serviceSendableBuilder_Values) -> Book.__safeDI_ServiceSendableCarrier<SafeDIScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			                public init(analytics: @escaping (analytics_Values) -> __safeDI_Built, book_serviceSendableBuilder: @escaping (book_serviceSendableBuilder_Values) -> Book.__safeDI_ServiceSendableCarrier<SafeDIScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                    self.analytics = analytics
			                    self.book_serviceSendableBuilder = book_serviceSendableBuilder
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                    self.init(analytics: { _ in __safeDI_builder() }, book_serviceSendableBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			                }
			            }
			        }
			    }

			    nonisolated public enum SafeDISendableScope_Analytics {
			        nonisolated public struct page_serviceBuilder_Values: Sendable {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			            public let page_serviceBuilder: @Sendable (page_serviceBuilder_Values) -> Page.__safeDI_ServiceCarrier<SafeDIScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(page_serviceBuilder: @escaping @Sendable (page_serviceBuilder_Values) -> Page.__safeDI_ServiceCarrier<SafeDIScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.page_serviceBuilder = page_serviceBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                self.init(page_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			            }
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public convenience init(__safeDI_analyticsSendableBuilder: SafeDISendableScope_Analytics.__safeDI_Builder<any Analytics>) {
			        func __safeDI_page() -> Page {
			            let __safeDI_analyticsSendableBuilder_page_serviceBuilder = __safeDI_analyticsSendableBuilder.page_serviceBuilder(SafeDISendableScope_Analytics.page_serviceBuilder_Values())
			            _ = Page.__safeDI_Page_CC6D10F1397D8E8C.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
			            @Sendable nonisolated func __safeDI_serviceBuilder_Page_service(__safeDI_page_serviceBuilder: SafeDIScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let __safeDI_analyticsSendableBuilder_chapter_storeBuilder = __safeDI_page_serviceBuilder.chapter_storeBuilder(SafeDIScope_Analytics.DefaultService_Scope.chapter_storeBuilder_Values())
			                    func __safeDI_chapter() -> Chapter {
			                        _ = Chapter.__safeDI_Chapter_C2B4DD008D11C74A.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Chapter", declaringModule: "Core"))
			                        func __safeDI_storeBuilder_Chapter_store(__safeDI_chapter_storeBuilder: SafeDIScope_Analytics.DefaultStore_Scope.__safeDI_Builder<any Analytics>) -> any Store {
			                            func __safeDI_store() -> DefaultStore {
			                                let __safeDI_analyticsSendableBuilder_book_serviceSendableBuilder = __safeDI_chapter_storeBuilder.book_serviceSendableBuilder(SafeDIScope_Analytics.DefaultStore_Scope.book_serviceSendableBuilder_Values())
			                                func __safeDI_book() -> Book {
			                                    _ = Book.__safeDI_Book_55BCEAB8683D88DE.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Book", declaringModule: "Mid"))
			                                    @Sendable nonisolated func __safeDI_serviceSendableBuilder_Book(up: Book.__safeDI_ServiceSendableCarrier<SafeDIScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>>) -> Book.__safeDI_ServiceSendableCarrier<any Service> {
			                                        .init(pageBuilder: { __safeDI_serviceBuilder_Page(up: up.pageBuilder()) })
			                                    }
			                                    return Book(__safeDI_serviceSendableBuilder: __safeDI_serviceSendableBuilder_Book(up: __safeDI_analyticsSendableBuilder_book_serviceSendableBuilder))
			                                }
			                                let book: Book = __safeDI_book()
			                                let analytics: any Analytics = __safeDI_chapter_storeBuilder.analytics(SafeDIScope_Analytics.DefaultStore_Scope.analytics_Values(book: book))
			                                return DefaultStore(analytics: analytics, book: book)
			                            }
			                            let store: any Store = __safeDI_store()
			                            return store
			                        }
			                        func __safeDI_storeBuilder_Chapter(up: Chapter.__safeDI_StoreCarrier<SafeDIScope_Analytics.DefaultStore_Scope.__safeDI_Builder<any Analytics>>) -> Chapter.__safeDI_StoreCarrier<any Store> {
			                            .init(store: { __safeDI_storeBuilder_Chapter_store(__safeDI_chapter_storeBuilder: up.store()) })
			                        }
			                        return Chapter(__safeDI_storeBuilder: __safeDI_storeBuilder_Chapter(up: __safeDI_analyticsSendableBuilder_chapter_storeBuilder))
			                    }
			                    let chapter: Chapter = __safeDI_chapter()
			                    return DefaultService(chapter: chapter)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            @Sendable nonisolated func __safeDI_serviceBuilder_Page(up: Page.__safeDI_ServiceCarrier<SafeDIScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>>) -> Page.__safeDI_ServiceCarrier<any Service> {
			                .init(service: { __safeDI_serviceBuilder_Page_service(__safeDI_page_serviceBuilder: up.service()) })
			            }
			            return Page(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Page(up: __safeDI_analyticsSendableBuilder_page_serviceBuilder))
			        }
			        let page: Page = __safeDI_page()
			        self.init(page: page)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_C1E8FC6866C9CD22 {}
			}
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

			extension Screen {
			    nonisolated public enum SafeDIScope_Analytics {
			        nonisolated public enum DefaultService_Scope {
			            nonisolated public struct analytics_Values {
			                public let chapter: Chapter
			            }

			            nonisolated public struct chapter_storeBuilder_Values {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let analytics: (analytics_Values) -> __safeDI_Built
			                public let chapter_storeBuilder: (chapter_storeBuilder_Values) -> Chapter.__safeDI_StoreCarrier<SafeDIScope_Analytics.DefaultStore_Scope.__safeDI_Builder<__safeDI_Built>>

			                public init(analytics: @escaping (analytics_Values) -> __safeDI_Built, chapter_storeBuilder: @escaping (chapter_storeBuilder_Values) -> Chapter.__safeDI_StoreCarrier<SafeDIScope_Analytics.DefaultStore_Scope.__safeDI_Builder<__safeDI_Built>>) {
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
			                public let book_serviceSendableBuilder: (book_serviceSendableBuilder_Values) -> Book.__safeDI_ServiceSendableCarrier<SafeDIScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			                public init(book_serviceSendableBuilder: @escaping (book_serviceSendableBuilder_Values) -> Book.__safeDI_ServiceSendableCarrier<SafeDIScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                    self.book_serviceSendableBuilder = book_serviceSendableBuilder
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                    self.init(book_serviceSendableBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			                }
			            }
			        }
			    }

			    nonisolated public enum SafeDISendableScope_Analytics {
			        nonisolated public struct page_serviceBuilder_Values: Sendable {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			            public let page_serviceBuilder: @Sendable (page_serviceBuilder_Values) -> Page.__safeDI_ServiceCarrier<SafeDIScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(page_serviceBuilder: @escaping @Sendable (page_serviceBuilder_Values) -> Page.__safeDI_ServiceCarrier<SafeDIScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.page_serviceBuilder = page_serviceBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                self.init(page_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			            }
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public convenience init(__safeDI_analyticsSendableBuilder: SafeDISendableScope_Analytics.__safeDI_Builder<any Analytics>) {
			        func __safeDI_page() -> Page {
			            let __safeDI_analyticsSendableBuilder_page_serviceBuilder = __safeDI_analyticsSendableBuilder.page_serviceBuilder(SafeDISendableScope_Analytics.page_serviceBuilder_Values())
			            _ = Page.__safeDI_Page_CC6D10F1397D8E8C.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
			            @Sendable nonisolated func __safeDI_serviceBuilder_Page_service(__safeDI_page_serviceBuilder: SafeDIScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let __safeDI_analyticsSendableBuilder_chapter_storeBuilder = __safeDI_page_serviceBuilder.chapter_storeBuilder(SafeDIScope_Analytics.DefaultService_Scope.chapter_storeBuilder_Values())
			                    func __safeDI_chapter() -> Chapter {
			                        _ = Chapter.__safeDI_Chapter_C2B4DD008D11C74A.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Chapter", declaringModule: "Core"))
			                        func __safeDI_storeBuilder_Chapter_store(__safeDI_chapter_storeBuilder: SafeDIScope_Analytics.DefaultStore_Scope.__safeDI_Builder<any Analytics>) -> any Store {
			                            func __safeDI_store() -> DefaultStore {
			                                let __safeDI_analyticsSendableBuilder_book_serviceSendableBuilder = __safeDI_chapter_storeBuilder.book_serviceSendableBuilder(SafeDIScope_Analytics.DefaultStore_Scope.book_serviceSendableBuilder_Values())
			                                func __safeDI_book() -> Book {
			                                    _ = Book.__safeDI_Book_55BCEAB8683D88DE.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Book", declaringModule: "Mid"))
			                                    @Sendable nonisolated func __safeDI_serviceSendableBuilder_Book(up: Book.__safeDI_ServiceSendableCarrier<SafeDIScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>>) -> Book.__safeDI_ServiceSendableCarrier<any Service> {
			                                        .init(pageBuilder: { __safeDI_serviceBuilder_Page(up: up.pageBuilder()) })
			                                    }
			                                    return Book(__safeDI_serviceSendableBuilder: __safeDI_serviceSendableBuilder_Book(up: __safeDI_analyticsSendableBuilder_book_serviceSendableBuilder))
			                                }
			                                let book: Book = __safeDI_book()
			                                return DefaultStore(book: book)
			                            }
			                            let store: any Store = __safeDI_store()
			                            return store
			                        }
			                        func __safeDI_storeBuilder_Chapter(up: Chapter.__safeDI_StoreCarrier<SafeDIScope_Analytics.DefaultStore_Scope.__safeDI_Builder<any Analytics>>) -> Chapter.__safeDI_StoreCarrier<any Store> {
			                            .init(store: { __safeDI_storeBuilder_Chapter_store(__safeDI_chapter_storeBuilder: up.store()) })
			                        }
			                        return Chapter(__safeDI_storeBuilder: __safeDI_storeBuilder_Chapter(up: __safeDI_analyticsSendableBuilder_chapter_storeBuilder))
			                    }
			                    let chapter: Chapter = __safeDI_chapter()
			                    let analytics: any Analytics = __safeDI_page_serviceBuilder.analytics(SafeDIScope_Analytics.DefaultService_Scope.analytics_Values(chapter: chapter))
			                    return DefaultService(analytics: analytics, chapter: chapter)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            @Sendable nonisolated func __safeDI_serviceBuilder_Page(up: Page.__safeDI_ServiceCarrier<SafeDIScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>>) -> Page.__safeDI_ServiceCarrier<any Service> {
			                .init(service: { __safeDI_serviceBuilder_Page_service(__safeDI_page_serviceBuilder: up.service()) })
			            }
			            return Page(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Page(up: __safeDI_analyticsSendableBuilder_page_serviceBuilder))
			        }
			        let page: Page = __safeDI_page()
			        self.init(page: page)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_A70584A49C94F6E8 {}
			}
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

			extension Screen {
			    nonisolated public enum SafeDIScope_Analytics {
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

			    nonisolated public enum SafeDISendableScope_Analytics {
			        nonisolated public struct page_serviceBuilder_Values: Sendable {}

			        nonisolated public struct page_serviceBuilder_Sendable_Values: Sendable {}

			        nonisolated public enum DefaultService_Scope {
			            nonisolated public struct pageBuilder_serviceBuilder_Values: Sendable {}

			            nonisolated public struct pageBuilder_serviceBuilder_Sendable_Values: Sendable {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			                public let pageBuilder_serviceBuilder: @Sendable (pageBuilder_serviceBuilder_Values) -> Page.__safeDI_ServiceCarrier<SafeDIScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>
			                public let pageBuilder_serviceBuilder_Sendable: @Sendable (pageBuilder_serviceBuilder_Sendable_Values) -> SafeDISendableScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>

			                public init(pageBuilder_serviceBuilder: @escaping @Sendable (pageBuilder_serviceBuilder_Values) -> Page.__safeDI_ServiceCarrier<SafeDIScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>, pageBuilder_serviceBuilder_Sendable: @escaping @Sendable (pageBuilder_serviceBuilder_Sendable_Values) -> SafeDISendableScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>) {
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
			            public let page_serviceBuilder: @Sendable (page_serviceBuilder_Values) -> Page.__safeDI_ServiceCarrier<SafeDIScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>
			            public let page_serviceBuilder_Sendable: @Sendable (page_serviceBuilder_Sendable_Values) -> SafeDISendableScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>

			            public init(page_serviceBuilder: @escaping @Sendable (page_serviceBuilder_Values) -> Page.__safeDI_ServiceCarrier<SafeDIScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>, page_serviceBuilder_Sendable: @escaping @Sendable (page_serviceBuilder_Sendable_Values) -> SafeDISendableScope_Analytics.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>) {
			                self.page_serviceBuilder = page_serviceBuilder
			                self.page_serviceBuilder_Sendable = page_serviceBuilder_Sendable
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                self.init(page_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }, page_serviceBuilder_Sendable: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			            }
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public convenience init(__safeDI_analyticsSendableBuilder: SafeDISendableScope_Analytics.__safeDI_Builder<any Analytics>) {
			        func __safeDI_page() -> Page {
			            let __safeDI_analyticsSendableBuilder_page_serviceBuilder = __safeDI_analyticsSendableBuilder.page_serviceBuilder(SafeDISendableScope_Analytics.page_serviceBuilder_Values())
			            let __safeDI_analyticsSendableBuilder_page_serviceBuilder_Sendable = __safeDI_analyticsSendableBuilder.page_serviceBuilder_Sendable(SafeDISendableScope_Analytics.page_serviceBuilder_Sendable_Values())
			            _ = Page.__safeDI_Page_CC6D10F1397D8E8C.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
			            @Sendable nonisolated func __safeDI_serviceBuilder_Page_service(__safeDI_page_serviceBuilder: SafeDIScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    @Sendable nonisolated func __safeDI_pageBuilder() -> Page {
			                        let __safeDI_analyticsSendableBuilder_pageBuilder_serviceBuilder = __safeDI_analyticsSendableBuilder_page_serviceBuilder_Sendable.pageBuilder_serviceBuilder(SafeDISendableScope_Analytics.DefaultService_Scope.pageBuilder_serviceBuilder_Values())
			                        _ = Page.__safeDI_Page_CC6D10F1397D8E8C.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
			                        return Page(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Page(up: __safeDI_analyticsSendableBuilder_pageBuilder_serviceBuilder))
			                    }
			                    let pageBuilder = SendableInstantiator<Page>(__safeDI_pageBuilder)
			                    let analytics: any Analytics = __safeDI_page_serviceBuilder.analytics(SafeDIScope_Analytics.DefaultService_Scope.analytics_Values(pageBuilder: pageBuilder))
			                    return DefaultService(analytics: analytics, pageBuilder: pageBuilder)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            @Sendable nonisolated func __safeDI_serviceBuilder_Page(up: Page.__safeDI_ServiceCarrier<SafeDIScope_Analytics.DefaultService_Scope.__safeDI_Builder<any Analytics>>) -> Page.__safeDI_ServiceCarrier<any Service> {
			                .init(service: { __safeDI_serviceBuilder_Page_service(__safeDI_page_serviceBuilder: up.service()) })
			            }
			            return Page(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Page(up: __safeDI_analyticsSendableBuilder_page_serviceBuilder))
			        }
			        let page: Page = __safeDI_page()
			        self.init(page: page)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_6D8653B4D25DA0CA {}
			}
			"""
		}
	}
}
