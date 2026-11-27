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

/// A public mock takes one builder per hole type and family over an enum of the places its tree builds, as a seam does, and
/// a module that calls it fills each place it can and passes the others up.
struct SafeDIToolPublicMockNestedBuilderTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – the declaring module

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesOneBuilderOverAnEnumOfItsPlaces_whenPublicMockBuildsTwoPlacesUnderOneLabel() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(app: [Self.screen]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Panel {
		    nonisolated public enum SafeDIMockScope_Service {
		        nonisolated public struct row_Values {}

		        nonisolated public struct service_Values {
		            public let row: Row
		        }

		        nonisolated public enum Row_Scope {
		            nonisolated public struct service_Values {
		                public let token: Token
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

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let row: (row_Values) -> SafeDIMockScope_Service.Row_Scope.__safeDI_Builder<__safeDI_Built>
		            public let service: (service_Values) -> __safeDI_Built

		            public init(row: @escaping (row_Values) -> SafeDIMockScope_Service.Row_Scope.__safeDI_Builder<__safeDI_Built>, service: @escaping (service_Values) -> __safeDI_Built) {
		                self.row = row
		                self.service = service
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(row: { _ in .init(__safeDI_noScope: __safeDI_builder) }, service: { _ in __safeDI_builder() })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            row: __safeDI_Core_Row_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                row: row
		            )
		        }

		        public var row: __safeDI_Core_Row_MockConfiguration { __safeDI_storage.row }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                row: __safeDI_Core_Row_MockConfiguration
		            ) {
		                self.row = row
		            }

		            let row: __safeDI_Core_Row_MockConfiguration
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
		        let __safeDI_serviceBuilder_row = __safeDI_serviceBuilder.row(SafeDIMockScope_Service.row_Values())
		        func __safeDI_row() -> Row {
		            let token = if let safeDIBuilder = safeDIOverrides.row.token { safeDIBuilder() } else { Token() }
		            let service: any Service = __safeDI_serviceBuilder_row.service(SafeDIMockScope_Service.Row_Scope.service_Values(token: token))
		            return Row.__safeDI_init(token: token, service: service, safeDIBuilder: safeDIOverrides.row.safeDIBuilder)
		        }
		        let row: Row = __safeDI_row()
		        let service: any Service = __safeDI_serviceBuilder.service(SafeDIMockScope_Service.service_Values(row: row))
		        return Panel(row: row, service: service)
		    }
		}

		extension Panel {
		    public enum __safeDI_Panel_mock_4401C36B70302082 {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `Row` is constructed within the public mock trees of module `Core`.
		nonisolated public struct __safeDI_Core_Row_MockConfiguration {
		    public init(
		        token: (() -> Token)? = nil,
		        _ safeDIBuilder: ((Token, any Service) -> Row)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            token: token,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var token: (() -> Token)? { __safeDI_storage.token }
		    /// Overrides how `Row` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((Token, any Service) -> Row)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            token: (() -> Token)?,
		            safeDIBuilder: ((Token, any Service) -> Row)?
		        ) {
		            self.token = token
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let token: (() -> Token)?
		        let safeDIBuilder: ((Token, any Service) -> Row)?
		    }
		}

		extension Row {
		    static func __safeDI_init(token: Token, service: any Service, safeDIBuilder: ((Token, any Service) -> Row)?) -> Row {
		        if let safeDIBuilder { safeDIBuilder(token, service) } else { Row(token: token, service: service) }
		    }
		}
		#endif

		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_compilesHandWrittenCallerThatPassesClosureThatTakesNothing_whenAModuleCallsAPublicMockByHand() async throws {
		// `Panel`'s places of `Service` forward nothing, so its `mock()` takes a builder that takes nothing, which a person
		// writes without naming a scope.
		_ = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(app: [
			"""
			import Core

			struct StubService: Service {
			    let name: String
			}

			func panel() -> Panel {
			    Panel.mock(serviceBuilder: { StubService(name: "any") })
			}
			""",
		]), integration: .moduleInfo, filesToDelete: &filesToDelete)
	}

	// MARK: Tests – an internal caller

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsEveryPlaceWithADispatcher_whenInternalCallerSeesATypeThatFulfillsTheHole() async throws {
		let modules = Self.modules(app: [Self.screen, Self.defaultService])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		\(Self.screenPrelude)
		    static func mock(
		        serviceBuilder: (() -> any Service)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_panel() -> Panel {
		            func __safeDI_serviceBuilder_Panel() -> Panel.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
		                .init(
		                    row: { _ in __safeDI_serviceBuilder_Panel_Row_Scope() },
		                    service: { _ in
		                        let service: any Service = DefaultService()
		                        return service
		                    }
		                )
		            }
		            func __safeDI_serviceBuilder_Panel_Row_Scope() -> Panel.SafeDIMockScope_Service.Row_Scope.__safeDI_Builder<any Service> {
		                .init(service: { _ in
		                    let service: any Service = DefaultService()
		                    return service
		                })
		            }
		            _ = Panel.__safeDI_Panel_mock_4401C36B70302082.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Panel.__safeDI_mock(serviceBuilder: serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Panel(), safeDIOverrides: safeDIOverrides.panel)
		        }
		        let panel: Panel = __safeDI_panel()
		        return Screen(panel: panel)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("Screen.mock()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesTheCalledMocksBuilderAsAFlatParameter_whenInternalCallerSeesNoTypeThatFulfillsTheHole() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(app: [Self.screen]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == [
			"App.swift": generatedFileHeader + """
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
			        serviceBuilder: @escaping () -> any Service,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        let __safeDI_serviceBuilder = serviceBuilder
			        func __safeDI_panel() -> Panel {
			            _ = Panel.__safeDI_Panel_mock_4401C36B70302082.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            let serviceBuilder: () -> any Service = __safeDI_serviceBuilder
			            return Panel.__safeDI_mock(serviceBuilder: .init(__safeDI_noScope: serviceBuilder), safeDIOverrides: safeDIOverrides.panel)
			        }
			        let panel: Panel = __safeDI_panel()
			        return Screen(panel: panel)
			    }
			}
			#endif
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsThePlaceBesideRowWithTheTokenItBuilds_whenInternalCallerReachesOnlyRowsPlaceOnARouteThatBindsTheToken() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(app: [Self.screen, Self.defaultServiceReceivingToken]), integration: .moduleInfo, filesToDelete: &filesToDelete)
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
		            token: (() -> Token)? = nil,
		            panel: Panel.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                token: token,
		                panel: panel
		            )
		        }

		        var token: (() -> Token)? { __safeDI_storage.token }
		        var panel: Panel.SafeDIOverrides { __safeDI_storage.panel }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                token: (() -> Token)?,
		                panel: Panel.SafeDIOverrides
		            ) {
		                self.token = token
		                self.panel = panel
		            }

		            let token: (() -> Token)?
		            let panel: Panel.SafeDIOverrides
		        }
		    }

		    static func mock(
		        serviceBuilder: (() -> any Service)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let token = if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder() } else { Token() }
		        func __safeDI_panel() -> Panel {
		            func __safeDI_serviceBuilder_Panel() -> Panel.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
		                .init(
		                    row: { _ in __safeDI_serviceBuilder_Panel_Row_Scope() },
		                    service: { _ in
		                        let service: any Service = DefaultService(token: token)
		                        return service
		                    }
		                )
		            }
		            func __safeDI_serviceBuilder_Panel_Row_Scope() -> Panel.SafeDIMockScope_Service.Row_Scope.__safeDI_Builder<any Service> {
		                .init(service: { scope in
		                    let token = scope.token
		                    let service: any Service = DefaultService(token: token)
		                    return service
		                })
		            }
		            _ = Panel.__safeDI_Panel_mock_4401C36B70302082.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Panel.__safeDI_mock(serviceBuilder: serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Panel(), safeDIOverrides: safeDIOverrides.panel)
		        }
		        let panel: Panel = __safeDI_panel()
		        return Screen(panel: panel)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsEachRouteItsNearestToken_whenInternalCallerReachesOneCaseOnTwoRoutes() async throws {
		// `Hub` builds `Model` inside `Page`, which binds `token`, and beside it, where nothing does. `HubScreen` fills the
		// place on the route through `Page` with `Page`'s `token`, and on the other with the `token` its mock builds, as inline
		// does.
		let modules = Self.modules(core: [Self.hub], app: [Self.hubScreen, Self.defaultServiceReceivingToken])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Hub {
		    nonisolated public enum SafeDIMockScope_Service {
		        nonisolated public struct page_Values {}

		        nonisolated public struct model_Values {
		            public let page: Page
		        }

		        nonisolated public enum Page_Scope {
		            nonisolated public struct model_Values {
		                public let token: Token
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let model: (model_Values) -> SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(model: @escaping (model_Values) -> SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.model = model
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(model: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		                }
		            }
		        }

		        nonisolated public enum Model_Scope {
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

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let page: (page_Values) -> SafeDIMockScope_Service.Page_Scope.__safeDI_Builder<__safeDI_Built>
		            public let model: (model_Values) -> SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(page: @escaping (page_Values) -> SafeDIMockScope_Service.Page_Scope.__safeDI_Builder<__safeDI_Built>, model: @escaping (model_Values) -> SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.page = page
		                self.model = model
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(page: { _ in .init(__safeDI_noScope: __safeDI_builder) }, model: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            page: __safeDI_Core_Page_MockConfiguration = .init(),
		            model: ((any Service) -> Model)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                page: page,
		                model: model
		            )
		        }

		        public var page: __safeDI_Core_Page_MockConfiguration { __safeDI_storage.page }
		        public var model: ((any Service) -> Model)? { __safeDI_storage.model }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                page: __safeDI_Core_Page_MockConfiguration,
		                model: ((any Service) -> Model)?
		            ) {
		                self.page = page
		                self.model = model
		            }

		            let page: __safeDI_Core_Page_MockConfiguration
		            let model: ((any Service) -> Model)?
		        }
		    }

		    public static func mock(
		        serviceBuilder: @escaping () -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Hub {
		        Hub.__safeDI_mock(serviceBuilder: .init(__safeDI_noScope: serviceBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        serviceBuilder __safeDI_serviceBuilder: Hub.SafeDIMockScope_Service.__safeDI_Builder<any Service>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Hub {
		        let __safeDI_serviceBuilder_page = __safeDI_serviceBuilder.page(SafeDIMockScope_Service.page_Values())
		        func __safeDI_page() -> Page {
		            let token = if let safeDIBuilder = safeDIOverrides.page.token { safeDIBuilder() } else { Token() }
		            let __safeDI_serviceBuilder_model = __safeDI_serviceBuilder_page.model(SafeDIMockScope_Service.Page_Scope.model_Values(token: token))
		            func __safeDI_model() -> Model {
		                let service: any Service = __safeDI_serviceBuilder_model.service(SafeDIMockScope_Service.Model_Scope.service_Values())
		                return if let safeDIBuilder = safeDIOverrides.page.model { safeDIBuilder(service) } else { Model(service: service) }
		            }
		            let model: Model = __safeDI_model()
		            return Page.__safeDI_init(token: token, model: model, safeDIBuilder: safeDIOverrides.page.safeDIBuilder)
		        }
		        let page: Page = __safeDI_page()
		        let __safeDI_serviceBuilder_model = __safeDI_serviceBuilder.model(SafeDIMockScope_Service.model_Values(page: page))
		        func __safeDI_model() -> Model {
		            let service: any Service = __safeDI_serviceBuilder_model.service(SafeDIMockScope_Service.Model_Scope.service_Values())
		            return if let safeDIBuilder = safeDIOverrides.model { safeDIBuilder(service) } else { Model(service: service) }
		        }
		        let model: Model = __safeDI_model()
		        return Hub(page: page, model: model)
		    }
		}

		extension Hub {
		    public enum __safeDI_Hub_mock_CB4845364B55B503 {}
		}
		#endif

		#if DEBUG
		extension Panel {
		    nonisolated public enum SafeDIMockScope_Service {
		        nonisolated public struct row_Values {}

		        nonisolated public struct service_Values {
		            public let row: Row
		        }

		        nonisolated public enum Row_Scope {
		            nonisolated public struct service_Values {
		                public let token: Token
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

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let row: (row_Values) -> SafeDIMockScope_Service.Row_Scope.__safeDI_Builder<__safeDI_Built>
		            public let service: (service_Values) -> __safeDI_Built

		            public init(row: @escaping (row_Values) -> SafeDIMockScope_Service.Row_Scope.__safeDI_Builder<__safeDI_Built>, service: @escaping (service_Values) -> __safeDI_Built) {
		                self.row = row
		                self.service = service
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(row: { _ in .init(__safeDI_noScope: __safeDI_builder) }, service: { _ in __safeDI_builder() })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            row: __safeDI_Core_Row_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                row: row
		            )
		        }

		        public var row: __safeDI_Core_Row_MockConfiguration { __safeDI_storage.row }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                row: __safeDI_Core_Row_MockConfiguration
		            ) {
		                self.row = row
		            }

		            let row: __safeDI_Core_Row_MockConfiguration
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
		        let __safeDI_serviceBuilder_row = __safeDI_serviceBuilder.row(SafeDIMockScope_Service.row_Values())
		        func __safeDI_row() -> Row {
		            let token = if let safeDIBuilder = safeDIOverrides.row.token { safeDIBuilder() } else { Token() }
		            let service: any Service = __safeDI_serviceBuilder_row.service(SafeDIMockScope_Service.Row_Scope.service_Values(token: token))
		            return Row.__safeDI_init(token: token, service: service, safeDIBuilder: safeDIOverrides.row.safeDIBuilder)
		        }
		        let row: Row = __safeDI_row()
		        let service: any Service = __safeDI_serviceBuilder.service(SafeDIMockScope_Service.service_Values(row: row))
		        return Panel(row: row, service: service)
		    }
		}

		extension Panel {
		    public enum __safeDI_Panel_mock_4401C36B70302082 {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `Page` is constructed within the public mock trees of module `Core`.
		nonisolated public struct __safeDI_Core_Page_MockConfiguration {
		    public init(
		        token: (() -> Token)? = nil,
		        model: ((any Service) -> Model)? = nil,
		        _ safeDIBuilder: ((Token, Model) -> Page)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            token: token,
		            model: model,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var token: (() -> Token)? { __safeDI_storage.token }
		    public var model: ((any Service) -> Model)? { __safeDI_storage.model }
		    /// Overrides how `Page` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((Token, Model) -> Page)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            token: (() -> Token)?,
		            model: ((any Service) -> Model)?,
		            safeDIBuilder: ((Token, Model) -> Page)?
		        ) {
		            self.token = token
		            self.model = model
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let token: (() -> Token)?
		        let model: ((any Service) -> Model)?
		        let safeDIBuilder: ((Token, Model) -> Page)?
		    }
		}

		extension Page {
		    static func __safeDI_init(token: Token, model: Model, safeDIBuilder: ((Token, Model) -> Page)?) -> Page {
		        if let safeDIBuilder { safeDIBuilder(token, model) } else { Page(token: token, model: model) }
		    }
		}

		/// Configuration for how `Row` is constructed within the public mock trees of module `Core`.
		nonisolated public struct __safeDI_Core_Row_MockConfiguration {
		    public init(
		        token: (() -> Token)? = nil,
		        _ safeDIBuilder: ((Token, any Service) -> Row)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            token: token,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var token: (() -> Token)? { __safeDI_storage.token }
		    /// Overrides how `Row` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((Token, any Service) -> Row)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            token: (() -> Token)?,
		            safeDIBuilder: ((Token, any Service) -> Row)?
		        ) {
		            self.token = token
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let token: (() -> Token)?
		        let safeDIBuilder: ((Token, any Service) -> Row)?
		    }
		}

		extension Row {
		    static func __safeDI_init(token: Token, service: any Service, safeDIBuilder: ((Token, any Service) -> Row)?) -> Row {
		        if let safeDIBuilder { safeDIBuilder(token, service) } else { Row(token: token, service: service) }
		    }
		}
		#endif

		"""])
		// `Page` binds `token` before `model`, which its dispatcher hands on; beside `Page`, nothing does, so the place is passed up.
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension HubScreen {
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
		        serviceBuilder: (() -> any Service)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> HubScreen {
		        let token = if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder() } else { Token() }
		        func __safeDI_hub() -> Hub {
		            func __safeDI_serviceBuilder_Hub(token: Token) -> Hub.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
		                .init(page: { _ in __safeDI_serviceBuilder_Hub_Page_Scope() }, model: { _ in __safeDI_serviceBuilder_Hub_Model_Scope(token: token) })
		            }
		            func __safeDI_serviceBuilder_Hub_Page_Scope() -> Hub.SafeDIMockScope_Service.Page_Scope.__safeDI_Builder<any Service> {
		                .init(model: { values in __safeDI_serviceBuilder_Hub_Model_Scope(token: values.token) })
		            }
		            func __safeDI_serviceBuilder_Hub_Model_Scope(token: Token) -> Hub.SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<any Service> {
		                .init(service: { _ in
		                    let service: any Service = DefaultService(token: token)
		                    return service
		                })
		            }
		            _ = Hub.__safeDI_Hub_mock_CB4845364B55B503.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Hub.__safeDI_mock(serviceBuilder: serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Hub(token: token), safeDIOverrides: safeDIOverrides.hub)
		        }
		        let hub: Hub = __safeDI_hub()
		        return HubScreen(hub: hub)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("HubScreen.mock()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesNestedEnumAsMockedTypesModuleSpellsItsType_whenCallersModuleDeclaresTypeOfSameName() async throws {
		// `Feature`'s `Store` holds the place `api` of `Home`'s public mock; `App` declares a `Store` of its own, so `App`'s run
		// spells `Feature`'s as `Feature.Store`. The enum is named by `Feature`'s spelling in both runs, so `App`'s dispatcher
		// names the enum `Feature` declares.
		let output = try await executeSafeDIToolMultiModuleTest(modules: [
			ModuleFixture(name: "Feature", packageName: "feature", swiftFileContent: [
				"""
				import SafeDI

				public protocol Api {}

				@Instantiable
				final class Store: Instantiable {
				    init(api: any Api) {
				        self.api = api
				    }

				    @Instantiated let api: any Api
				}

				@Instantiable(generateMock: .public)
				public final class Home: Instantiable {
				    init(store: Store) {
				        self.store = store
				    }

				    @Instantiated let store: Store
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContent: [
				"""
				import Feature
				import SafeDI

				@Instantiable
				public final class Store: Instantiable {
				    public init() {}
				}

				@Instantiable(fulfillingAdditionalTypes: [Api.self])
				final class LiveApi: Api, Instantiable {
				    init() {}
				}

				@Instantiable(generateMock: true)
				public final class Root: Instantiable {
				    public init(appStore: Store, home: Home) {
				        self.appStore = appStore
				        self.home = home
				    }

				    @Instantiated let appStore: Store
				    @Instantiated let home: Home
				}
				""",
			], dependencies: ["Feature"]),
		], integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Home {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct store_Values {}

		        nonisolated public enum Store_Scope {
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
		            public let store: (store_Values) -> SafeDIMockScope_Api.Store_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(store: @escaping (store_Values) -> SafeDIMockScope_Api.Store_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.store = store
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(store: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init() {
		            __safeDI_storage = __safeDI_Storage(
		                store: nil
		            )
		        }

		        init(
		            store: ((any Api) -> Store)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                store: store
		            )
		        }

		        var store: ((any Api) -> Store)? { __safeDI_storage.store }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                store: ((any Api) -> Store)?
		            ) {
		                self.store = store
		            }

		            let store: ((any Api) -> Store)?
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
		        let __safeDI_apiBuilder_store = __safeDI_apiBuilder.store(SafeDIMockScope_Api.store_Values())
		        func __safeDI_store() -> Store {
		            let api: any Api = __safeDI_apiBuilder_store.api(SafeDIMockScope_Api.Store_Scope.api_Values())
		            return if let safeDIBuilder = safeDIOverrides.store { safeDIBuilder(api) } else { Store(api: api) }
		        }
		        let store: Store = __safeDI_store()
		        return Home(store: store)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_mock_D2C2C192F781580B {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            appStore: (() -> Store)? = nil,
		            home: Home.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                appStore: appStore,
		                home: home
		            )
		        }

		        var appStore: (() -> Store)? { __safeDI_storage.appStore }
		        var home: Home.SafeDIOverrides { __safeDI_storage.home }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                appStore: (() -> Store)?,
		                home: Home.SafeDIOverrides
		            ) {
		                self.appStore = appStore
		                self.home = home
		            }

		            let appStore: (() -> Store)?
		            let home: Home.SafeDIOverrides
		        }
		    }

		    static func mock(
		        apiBuilder: (() -> any Api)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let appStore = if let safeDIBuilder = safeDIOverrides.appStore { safeDIBuilder() } else { Store() }
		        func __safeDI_home() -> Home {
		            func __safeDI_apiBuilder_Home() -> Home.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(store: { _ in __safeDI_apiBuilder_Home_Store_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Store_Scope() -> Home.SafeDIMockScope_Api.Store_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveApi()
		                    return api
		                })
		            }
		            _ = Home.__safeDI_Home_mock_D2C2C192F781580B.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Home.__safeDI_mock(apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_Home(), safeDIOverrides: safeDIOverrides.home)
		        }
		        let home: Home = __safeDI_home()
		        return Root(appStore: appStore, home: home)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesUpThePlaceAFillWouldCallAPartlyFilledMockFor_whenTheFulfillersTreeCallsAPublicMockWithAnUnfilledPlace() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(core: [Self.gadget], app: [
			Self.screen,
			"""
			import Core
			import SafeDI

			@Instantiable(fulfillingAdditionalTypes: [Service.self])
			public struct DefaultService: Service, Instantiable {
			    public init(gadget: Gadget) {
			        self.gadget = gadget
			    }

			    @Instantiated let gadget: Gadget
			}

			@Instantiable(fulfillingAdditionalTypes: [Widget.self])
			public struct DefaultWidget: Widget, Instantiable {
			    public init() {}
			}
			""",
		]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		// The fill of either place would call `Gadget`'s mock, whose `gizmo` `App` cannot fill, so both pass up.
		#expect(output.modules["App"]?.generatedFiles == [
			"App.swift": generatedFileHeader + """
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
			        gizmoBuilder: @escaping () -> any Gizmo,
			        serviceBuilder: (() -> any Service)? = nil,
			        widgetBuilder: (() -> any Widget)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_panel() -> Panel {
			            func __safeDI_serviceBuilder_Panel_service(_ scope: Panel.SafeDIMockScope_Service.service_Values) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    func __safeDI_gadget() -> Gadget {
			                        func __safeDI_widgetBuilder_Gadget_widget() -> any Widget {
			                            let widget: any Widget = DefaultWidget()
			                            return widget
			                        }
			                        func __safeDI_widgetBuilder_Gadget() -> Gadget.SafeDIMockScope_Widget.__safeDI_Builder<any Widget> {
			                            .init(widget: { _ in __safeDI_widgetBuilder_Gadget_widget() })
			                        }
			                        return Gadget.__safeDI_mock(gizmoBuilder: .init(__safeDI_noScope: gizmoBuilder), widgetBuilder: widgetBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_widgetBuilder_Gadget())
			                    }
			                    let gadget: Gadget = __safeDI_gadget()
			                    return DefaultService(gadget: gadget)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Panel_Row_Scope_service(_ scope: Panel.SafeDIMockScope_Service.Row_Scope.service_Values) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    func __safeDI_gadget() -> Gadget {
			                        func __safeDI_widgetBuilder_Gadget_widget() -> any Widget {
			                            let widget: any Widget = DefaultWidget()
			                            return widget
			                        }
			                        func __safeDI_widgetBuilder_Gadget() -> Gadget.SafeDIMockScope_Widget.__safeDI_Builder<any Widget> {
			                            .init(widget: { _ in __safeDI_widgetBuilder_Gadget_widget() })
			                        }
			                        return Gadget.__safeDI_mock(gizmoBuilder: .init(__safeDI_noScope: gizmoBuilder), widgetBuilder: widgetBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_widgetBuilder_Gadget())
			                    }
			                    let gadget: Gadget = __safeDI_gadget()
			                    return DefaultService(gadget: gadget)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Panel() -> Panel.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(row: { _ in __safeDI_serviceBuilder_Panel_Row_Scope() }, service: { scope in __safeDI_serviceBuilder_Panel_service(scope) })
			            }
			            func __safeDI_serviceBuilder_Panel_Row_Scope() -> Panel.SafeDIMockScope_Service.Row_Scope.__safeDI_Builder<any Service> {
			                .init(service: { scope in __safeDI_serviceBuilder_Panel_Row_Scope_service(scope) })
			            }
			            _ = Panel.__safeDI_Panel_mock_4401C36B70302082.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Panel.__safeDI_mock(serviceBuilder: serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Panel(), safeDIOverrides: safeDIOverrides.panel)
			        }
			        let panel: Panel = __safeDI_panel()
			        return Screen(panel: panel)
			    }
			}
			#endif
			""",
		])
	}

	// MARK: Tests – a public caller

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_holdsTheCalledMocksEnumInACaseOfEachFamily_whenPublicCallerCallsItInPlainCodeAndInASendableFunction() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(mid: [Self.board], app: [Self.boardScreen]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Mid"]?.generatedFiles == ["Mid.swift": generatedFileHeader + """
		\(Self.boardPrelude)
		    public static func mock(
		        serviceBuilder: @escaping () -> any Service,
		        serviceSendableBuilder: @escaping @Sendable () -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Board {
		        Board.__safeDI_mock(serviceBuilder: .init(__safeDI_noScope: serviceBuilder), serviceSendableBuilder: .init(__safeDI_noScope: serviceSendableBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        serviceBuilder __safeDI_serviceBuilder: Board.SafeDIMockScope_Service.__safeDI_Builder<any Service>,
		        serviceSendableBuilder __safeDI_serviceSendableBuilder: Board.SafeDISendableMockScope_Service.__safeDI_Builder<any Service>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Board {
		        _ = Panel.__safeDI_Panel_mock_4401C36B70302082.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let panel = Panel.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder.panel(SafeDIMockScope_Service.panel_Values()), safeDIOverrides: safeDIOverrides.panel)
		        _ = Panel.__safeDI_Panel_mock_4401C36B70302082.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let __safeDI_held__safeDIBuilder = safeDIOverrides.held
		        @Sendable nonisolated func __safeDI_held() -> Panel {
		            Panel.__safeDI_mock(serviceBuilder: __safeDI_serviceSendableBuilder.held(SafeDISendableMockScope_Service.held_Values()), safeDIOverrides: __safeDI_held__safeDIBuilder?() ?? .init())
		        }
		        let held = SendableInstantiator<Panel>(__safeDI_held)
		        return Board(panel: panel, held: held)
		    }
		}

		extension Board {
		    public enum __safeDI_Board_mock_A0691DACD6EAFFC3 {}
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesOneSendableBuilderForBothFamiliesItPassesUp_whenInternalCallerBuildsAPublicCallerInASendableFunction() async throws {
		// `BoardScreen` builds `Board` in a `@Sendable` builder function, which captures both builders `Board`'s mock passes
		// up: the plain family's, which `BoardScreen`'s mock takes `@Sendable`, and so in the `@Sendable` family, and the
		// `@Sendable` family's, so `BoardScreen`'s mock takes one `@Sendable` builder, labeled for that family, for both.
		let heldBoardScreen = """
		import Core
		import Mid
		import SafeDI

		@Instantiable(generateMock: true)
		public struct BoardScreen: Instantiable {
		    public init(board: SendableInstantiator<Board>) {
		        self.board = board
		    }

		    @Instantiated let board: SendableInstantiator<Board>
		}
		"""
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(mid: [Self.board], app: [heldBoardScreen]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
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
		extension BoardScreen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            board: (@Sendable () -> Board.SafeDIOverrides)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                board: board
		            )
		        }

		        var board: (@Sendable () -> Board.SafeDIOverrides)? { __safeDI_storage.board }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage: Sendable {
		            init(
		                board: (@Sendable () -> Board.SafeDIOverrides)?
		            ) {
		                self.board = board
		            }

		            let board: (@Sendable () -> Board.SafeDIOverrides)?
		        }
		    }

		    static func mock(
		        serviceSendableBuilder: @escaping @Sendable () -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> BoardScreen {
		        let __safeDI_serviceSendableBuilder = serviceSendableBuilder
		        @Sendable nonisolated func __safeDI_board(safeDIBuilder: (@Sendable () -> Board.SafeDIOverrides)?) -> Board {
		            _ = Board.__safeDI_Board_mock_A0691DACD6EAFFC3.self // If this line does not compile, compile the code SafeDI generates for module Mid into Mid: under Bazel, add Mid’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            let serviceBuilder: () -> any Service = __safeDI_serviceSendableBuilder
		            let serviceSendableBuilder: @Sendable () -> any Service = __safeDI_serviceSendableBuilder
		            return Board.__safeDI_mock(serviceBuilder: .init(__safeDI_noScope: serviceBuilder), serviceSendableBuilder: .init(__safeDI_noScope: serviceSendableBuilder), safeDIOverrides: safeDIBuilder?() ?? .init())
		        }
		        let __safeDI_board__safeDIBuilder: (@Sendable () -> Board.SafeDIOverrides)? = safeDIOverrides.board
		        let board = SendableInstantiator<Board> {
		            __safeDI_board(safeDIBuilder: __safeDI_board__safeDIBuilder)
		        }
		        return BoardScreen(board: board)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsThroughBothFamiliesDispatchers_whenCallerOfAPublicCallerSeesATypeThatFulfillsTheHole() async throws {
		let modules = Self.modules(mid: [Self.board], app: [Self.boardScreen, Self.defaultService])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
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
		extension BoardScreen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            board: Board.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                board: board
		            )
		        }

		        var board: Board.SafeDIOverrides { __safeDI_storage.board }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                board: Board.SafeDIOverrides
		            ) {
		                self.board = board
		            }

		            let board: Board.SafeDIOverrides
		        }
		    }

		    static func mock(
		        serviceBuilder: (() -> any Service)? = nil,
		        serviceSendableBuilder: (@Sendable () -> any Service)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> BoardScreen {
		        func __safeDI_board() -> Board {
		            func __safeDI_serviceBuilder_Board() -> Board.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
		                .init(panel: { _ in __safeDI_serviceBuilder_Panel() })
		            }
		            @Sendable nonisolated func __safeDI_serviceBuilder_Panel() -> Panel.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
		                .init(
		                    row: { _ in __safeDI_serviceBuilder_Panel_Row_Scope() },
		                    service: { _ in
		                        let service: any Service = DefaultService()
		                        return service
		                    }
		                )
		            }
		            @Sendable nonisolated func __safeDI_serviceBuilder_Panel_Row_Scope() -> Panel.SafeDIMockScope_Service.Row_Scope.__safeDI_Builder<any Service> {
		                .init(service: { _ in
		                    let service: any Service = DefaultService()
		                    return service
		                })
		            }
		            @Sendable nonisolated func __safeDI_serviceSendableBuilder_Board() -> Board.SafeDISendableMockScope_Service.__safeDI_Builder<any Service> {
		                .init(held: { _ in __safeDI_serviceBuilder_Panel() })
		            }
		            _ = Board.__safeDI_Board_mock_A0691DACD6EAFFC3.self // If this line does not compile, compile the code SafeDI generates for module Mid into Mid: under Bazel, add Mid’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Board.__safeDI_mock(serviceBuilder: serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Board(), serviceSendableBuilder: serviceSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceSendableBuilder_Board(), safeDIOverrides: safeDIOverrides.board)
		        }
		        let board: Board = __safeDI_board()
		        return BoardScreen(board: board)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("BoardScreen.mock()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsThePlaceBesideRowWithItsOwnToken_whenPublicCallerReachesOnlyRowsPlaceOnARouteThatBindsTheToken() async throws {
		let modules = Self.modules(mid: [Self.board, Self.defaultServiceReceivingToken], app: [Self.boardScreen])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Mid"]?.generatedFiles == ["Mid.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Board {
		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            token: (() -> Token)? = nil,
		            panel: Panel.SafeDIOverrides = .init(),
		            held: (@Sendable () -> Panel.SafeDIOverrides)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                token: token,
		                panel: panel,
		                held: held
		            )
		        }

		        public var token: (() -> Token)? { __safeDI_storage.token }
		        public var panel: Panel.SafeDIOverrides { __safeDI_storage.panel }
		        public var held: (@Sendable () -> Panel.SafeDIOverrides)? { __safeDI_storage.held }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                token: (() -> Token)?,
		                panel: Panel.SafeDIOverrides,
		                held: (@Sendable () -> Panel.SafeDIOverrides)?
		            ) {
		                self.token = token
		                self.panel = panel
		                self.held = held
		            }

		            let token: (() -> Token)?
		            let panel: Panel.SafeDIOverrides
		            let held: (@Sendable () -> Panel.SafeDIOverrides)?
		        }
		    }

		    public static func mock(
		        serviceBuilder: (() -> any Service)? = nil,
		        serviceSendableBuilder: (@Sendable () -> any Service)? = nil,
		        token: Token? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Board {
		        Board.__safeDI_mock(serviceBuilder: serviceBuilder, serviceSendableBuilder: serviceSendableBuilder, token: token, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        serviceBuilder __safeDI_serviceBuilder: (() -> any Service)? = nil,
		        serviceSendableBuilder __safeDI_serviceSendableBuilder: (@Sendable () -> any Service)? = nil,
		        token: Token? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Board {
		        let token = if let token { token } else if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder() } else { Token() }
		        func __safeDI_panel() -> Panel {
		            func __safeDI_serviceBuilder_Panel() -> Panel.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
		                .init(
		                    row: { _ in __safeDI_serviceBuilder_Panel_Row_Scope() },
		                    service: { _ in
		                        let service: any Service = DefaultService(token: token)
		                        return service
		                    }
		                )
		            }
		            func __safeDI_serviceBuilder_Panel_Row_Scope() -> Panel.SafeDIMockScope_Service.Row_Scope.__safeDI_Builder<any Service> {
		                .init(service: { scope in
		                    let token = scope.token
		                    let service: any Service = DefaultService(token: token)
		                    return service
		                })
		            }
		            _ = Panel.__safeDI_Panel_mock_4401C36B70302082.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Panel.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Panel(), safeDIOverrides: safeDIOverrides.panel)
		        }
		        let panel: Panel = __safeDI_panel()
		        let __safeDI_held__safeDIBuilder = safeDIOverrides.held
		        @Sendable nonisolated func __safeDI_held() -> Panel {
		            func __safeDI_serviceBuilder_Panel() -> Panel.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
		                .init(
		                    row: { _ in __safeDI_serviceBuilder_Panel_Row_Scope() },
		                    service: { _ in
		                        let service: any Service = DefaultService(token: token)
		                        return service
		                    }
		                )
		            }
		            func __safeDI_serviceBuilder_Panel_Row_Scope() -> Panel.SafeDIMockScope_Service.Row_Scope.__safeDI_Builder<any Service> {
		                .init(service: { scope in
		                    let token = scope.token
		                    let service: any Service = DefaultService(token: token)
		                    return service
		                })
		            }
		            _ = Panel.__safeDI_Panel_mock_4401C36B70302082.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Panel.__safeDI_mock(serviceBuilder: __safeDI_serviceSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Panel(), safeDIOverrides: __safeDI_held__safeDIBuilder?() ?? .init())
		        }
		        let held = SendableInstantiator<Panel>(__safeDI_held)
		        return Board(panel: panel, held: held)
		    }
		}

		extension Board {
		    public enum __safeDI_Board_mock_CD8B9B1996BC3E03 {}
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesASendablePlaceUpUnderTheCalledMocksStem_whenNeitherCallerFillsIt() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(
			core: [
				"""
				import SafeDI

				@Instantiable
				public struct Job: Instantiable, Sendable {
				    public init(service: any Service) {
				        self.service = service
				    }

				    @Instantiated let service: any Service
				}

				@Instantiable(generateMock: .public)
				public struct Crate: Instantiable, Sendable {
				    package init(job: SendableInstantiator<Job>) {
				        self.job = job
				    }

				    @Instantiated let job: SendableInstantiator<Job>
				}
				""",
			],
			mid: [
				"""
				import Core
				import SafeDI

				@Instantiable(generateMock: .public)
				public struct Shelf: Instantiable {
				    package init(crate: Crate) {
				        self.crate = crate
				    }

				    @Instantiated let crate: Crate
				}
				""",
			],
			app: [
				"""
				import Mid
				import SafeDI

				@Instantiable(generateMock: true)
				public struct ShelfScreen: Instantiable {
				    public init(shelf: Shelf) {
				        self.shelf = shelf
				    }

				    @Instantiated let shelf: Shelf
				}
				""",
			],
		), integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Mid"]?.generatedFiles == ["Mid.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Shelf {
		    nonisolated public enum SafeDISendableMockScope_Service {
		        nonisolated public struct crate_Sendable_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
		            public let crate_Sendable: @Sendable (crate_Sendable_Values) -> Crate.SafeDISendableMockScope_Service.__safeDI_Builder<__safeDI_Built>

		            public init(crate_Sendable: @escaping @Sendable (crate_Sendable_Values) -> Crate.SafeDISendableMockScope_Service.__safeDI_Builder<__safeDI_Built>) {
		                self.crate_Sendable = crate_Sendable
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		                self.init(crate_Sendable: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            crate: Crate.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                crate: crate
		            )
		        }

		        public var crate: Crate.SafeDIOverrides { __safeDI_storage.crate }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                crate: Crate.SafeDIOverrides
		            ) {
		                self.crate = crate
		            }

		            let crate: Crate.SafeDIOverrides
		        }
		    }

		    public static func mock(
		        serviceSendableBuilder: @escaping @Sendable () -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Shelf {
		        Shelf.__safeDI_mock(serviceSendableBuilder: .init(__safeDI_noScope: serviceSendableBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        serviceSendableBuilder __safeDI_serviceSendableBuilder: Shelf.SafeDISendableMockScope_Service.__safeDI_Builder<any Service>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Shelf {
		        _ = Crate.__safeDI_Crate_mock_8ACF7D7D62F52A60.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let crate = Crate.__safeDI_mock(serviceSendableBuilder: __safeDI_serviceSendableBuilder.crate_Sendable(SafeDISendableMockScope_Service.crate_Sendable_Values()), safeDIOverrides: safeDIOverrides.crate)
		        return Shelf(crate: crate)
		    }
		}

		extension Shelf {
		    public enum __safeDI_Shelf_mock_B904C3F4C805C0B4 {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
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
		extension ShelfScreen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            shelf: Shelf.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                shelf: shelf
		            )
		        }

		        var shelf: Shelf.SafeDIOverrides { __safeDI_storage.shelf }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                shelf: Shelf.SafeDIOverrides
		            ) {
		                self.shelf = shelf
		            }

		            let shelf: Shelf.SafeDIOverrides
		        }
		    }

		    static func mock(
		        serviceSendableBuilder: @escaping @Sendable () -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> ShelfScreen {
		        let __safeDI_serviceSendableBuilder = serviceSendableBuilder
		        func __safeDI_shelf() -> Shelf {
		            _ = Shelf.__safeDI_Shelf_mock_B904C3F4C805C0B4.self // If this line does not compile, compile the code SafeDI generates for module Mid into Mid: under Bazel, add Mid’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            let serviceSendableBuilder: @Sendable () -> any Service = __safeDI_serviceSendableBuilder
		            return Shelf.__safeDI_mock(serviceSendableBuilder: .init(__safeDI_noScope: serviceSendableBuilder), safeDIOverrides: safeDIOverrides.shelf)
		        }
		        let shelf: Shelf = __safeDI_shelf()
		        return ShelfScreen(shelf: shelf)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsPublicCallersMockWithoutBuilders_whenPublicCallerFillsEveryPlaceOfTheCalledMock() async throws {
		// `Mid` fills both of `Panel`'s places with `TokenService`: `row_service` with `Row`'s `token`, and `service` with the
		// `token` `Board`'s mock takes. `App` calls `Board`'s mock with the `token` it builds and hands it no builder, though
		// it sees `FakeService`.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(mid: [Self.plainBoard, Self.tokenService], app: [Self.boardScreen, Self.fakeService]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
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
		extension BoardScreen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            token: (() -> Token)? = nil,
		            board: Board.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                token: token,
		                board: board
		            )
		        }

		        var token: (() -> Token)? { __safeDI_storage.token }
		        var board: Board.SafeDIOverrides { __safeDI_storage.board }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                token: (() -> Token)?,
		                board: Board.SafeDIOverrides
		            ) {
		                self.token = token
		                self.board = board
		            }

		            let token: (() -> Token)?
		            let board: Board.SafeDIOverrides
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> BoardScreen {
		        let token: Token? = if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder() } else { Token() }
		        _ = Board.__safeDI_Board_mock_50A6478EF5665EF8.self // If this line does not compile, compile the code SafeDI generates for module Mid into Mid: under Bazel, add Mid’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let board = Board.__safeDI_mock(token: token, safeDIOverrides: safeDIOverrides.board)
		        return BoardScreen(board: board)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsPublicCallersMockWithoutBuilders_whenPublicCallerFillsEveryPlaceInEachFamily() async throws {
		// As above, with `Board` also building `Panel` in a `SendableInstantiator`: `Mid` fills the places of both families.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(mid: [Self.board, Self.tokenService], app: [Self.boardScreen, Self.fakeService]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
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
		extension BoardScreen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            token: (() -> Token)? = nil,
		            board: Board.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                token: token,
		                board: board
		            )
		        }

		        var token: (() -> Token)? { __safeDI_storage.token }
		        var board: Board.SafeDIOverrides { __safeDI_storage.board }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                token: (() -> Token)?,
		                board: Board.SafeDIOverrides
		            ) {
		                self.token = token
		                self.board = board
		            }

		            let token: (() -> Token)?
		            let board: Board.SafeDIOverrides
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> BoardScreen {
		        let token: Token? = if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder() } else { Token() }
		        _ = Board.__safeDI_Board_mock_CD8B9B1996BC3E03.self // If this line does not compile, compile the code SafeDI generates for module Mid into Mid: under Bazel, add Mid’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let board = Board.__safeDI_mock(token: token, safeDIOverrides: safeDIOverrides.board)
		        return BoardScreen(board: board)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesABuilderForWhatTheFillInstantiates_whenInternalCallersFulfillerInstantiatesATypeNothingFulfills() async throws {
		// `Screen` fills both of `Panel`’s places with `DefaultService`, whose `gizmo` nothing in `App` fulfills, and takes
		// `gizmoBuilder`, which each `DefaultService` calls where it is built, as the `.public` caller below does.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(app: [Self.screen, Self.defaultServiceInstantiatingGizmo]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == [
			"App.swift": generatedFileHeader + """
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
			        gizmoBuilder: @escaping () -> any Gizmo,
			        serviceBuilder: (() -> any Service)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_panel() -> Panel {
			            func __safeDI_serviceBuilder_Panel_service(_ scope: Panel.SafeDIMockScope_Service.service_Values) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let gizmo: any Gizmo = gizmoBuilder()
			                    return DefaultService(gizmo: gizmo)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Panel_Row_Scope_service(_ scope: Panel.SafeDIMockScope_Service.Row_Scope.service_Values) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let gizmo: any Gizmo = gizmoBuilder()
			                    return DefaultService(gizmo: gizmo)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Panel() -> Panel.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(row: { _ in __safeDI_serviceBuilder_Panel_Row_Scope() }, service: { scope in __safeDI_serviceBuilder_Panel_service(scope) })
			            }
			            func __safeDI_serviceBuilder_Panel_Row_Scope() -> Panel.SafeDIMockScope_Service.Row_Scope.__safeDI_Builder<any Service> {
			                .init(service: { scope in __safeDI_serviceBuilder_Panel_Row_Scope_service(scope) })
			            }
			            _ = Panel.__safeDI_Panel_mock_4401C36B70302082.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Panel.__safeDI_mock(serviceBuilder: serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Panel(), safeDIOverrides: safeDIOverrides.panel)
			        }
			        let panel: Panel = __safeDI_panel()
			        return Screen(panel: panel)
			    }
			}
			#endif
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsWithTheFakeAndTakesNoBuilder_whenInternalCallersFulfillerInstantiatesATypeOnlyAMockOnlyFakeFulfills() async throws {
		// A `mockOnly` fake of `Gizmo` fulfills it in mocks, so the fill builds it, as a seam’s own internal mock and the
		// `.public` caller do, and `mock()` takes no builder.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(app: [Self.screen, Self.defaultServiceInstantiatingGizmo, Self.fakeGizmo]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == [
			"App.swift": generatedFileHeader + """
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
			        serviceBuilder: (() -> any Service)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_panel() -> Panel {
			            func __safeDI_serviceBuilder_Panel_service(_ scope: Panel.SafeDIMockScope_Service.service_Values) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let gizmo: any Gizmo = FakeGizmo.mock()
			                    return DefaultService(gizmo: gizmo)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Panel_Row_Scope_service(_ scope: Panel.SafeDIMockScope_Service.Row_Scope.service_Values) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let gizmo: any Gizmo = FakeGizmo.mock()
			                    return DefaultService(gizmo: gizmo)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Panel() -> Panel.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(row: { _ in __safeDI_serviceBuilder_Panel_Row_Scope() }, service: { scope in __safeDI_serviceBuilder_Panel_service(scope) })
			            }
			            func __safeDI_serviceBuilder_Panel_Row_Scope() -> Panel.SafeDIMockScope_Service.Row_Scope.__safeDI_Builder<any Service> {
			                .init(service: { scope in __safeDI_serviceBuilder_Panel_Row_Scope_service(scope) })
			            }
			            _ = Panel.__safeDI_Panel_mock_4401C36B70302082.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Panel.__safeDI_mock(serviceBuilder: serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Panel(), safeDIOverrides: safeDIOverrides.panel)
			        }
			        let panel: Panel = __safeDI_panel()
			        return Screen(panel: panel)
			    }
			}
			#endif
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesThePlaceUp_whenInternalCallersFulfillerIsAnotherModulesSeamItCannotConstruct() async throws {
		// `GadgetSeam`, in `Mid`, fulfills `Service`, but its initializer is `internal`, so `App` cannot build it inline: the
		// mock passes the place up, as the `.public` caller does.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(mid: [Self.gadgetSeam], app: [Self.screen]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == [
			"App.swift": generatedFileHeader + """
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
			        serviceBuilder: @escaping () -> any Service,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        let __safeDI_serviceBuilder = serviceBuilder
			        func __safeDI_panel() -> Panel {
			            _ = Panel.__safeDI_Panel_mock_4401C36B70302082.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            let serviceBuilder: () -> any Service = __safeDI_serviceBuilder
			            return Panel.__safeDI_mock(serviceBuilder: .init(__safeDI_noScope: serviceBuilder), safeDIOverrides: safeDIOverrides.panel)
			        }
			        let panel: Panel = __safeDI_panel()
			        return Screen(panel: panel)
			    }
			}
			#endif
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesABuilderForWhatTheFillInstantiates_whenPublicCallersFulfillerInstantiatesATypeNothingFulfills() async throws {
		let modules = Self.modules(mid: [Self.plainBoard, Self.defaultServiceInstantiatingGizmo], app: [Self.boardScreen])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Mid"]?.generatedFiles == ["Mid.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Board {
		    nonisolated public enum SafeDIMockScope_Gizmo {
		        nonisolated public struct panel_serviceBuilder_Values {}

		        nonisolated public enum DefaultService_Scope {
		            nonisolated public struct gizmo_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let gizmo: (gizmo_Values) -> __safeDI_Built

		                public init(gizmo: @escaping (gizmo_Values) -> __safeDI_Built) {
		                    self.gizmo = gizmo
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(gizmo: { _ in __safeDI_builder() })
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let panel_serviceBuilder: (panel_serviceBuilder_Values) -> Panel.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gizmo.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(panel_serviceBuilder: @escaping (panel_serviceBuilder_Values) -> Panel.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gizmo.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.panel_serviceBuilder = panel_serviceBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(panel_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            panel: Panel.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                panel: panel
		            )
		        }

		        public var panel: Panel.SafeDIOverrides { __safeDI_storage.panel }

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

		    public static func mock(
		        gizmoBuilder: @escaping () -> any Gizmo,
		        serviceBuilder: (() -> any Service)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Board {
		        Board.__safeDI_mock(gizmoBuilder: .init(__safeDI_noScope: gizmoBuilder), serviceBuilder: serviceBuilder, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        gizmoBuilder __safeDI_gizmoBuilder: Board.SafeDIMockScope_Gizmo.__safeDI_Builder<any Gizmo>,
		        serviceBuilder __safeDI_serviceBuilder: (() -> any Service)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Board {
		        let __safeDI_gizmoBuilder_panel_serviceBuilder = __safeDI_gizmoBuilder.panel_serviceBuilder(SafeDIMockScope_Gizmo.panel_serviceBuilder_Values())
		        func __safeDI_panel() -> Panel {
		            func __safeDI_serviceBuilder_Panel_service(_ scope: Panel.SafeDIMockScope_Service.service_Values, __safeDI_panel_serviceBuilder: SafeDIMockScope_Gizmo.DefaultService_Scope.__safeDI_Builder<any Gizmo>) -> any Service {
		                func __safeDI_service() -> DefaultService {
		                    let gizmo: any Gizmo = __safeDI_panel_serviceBuilder.gizmo(SafeDIMockScope_Gizmo.DefaultService_Scope.gizmo_Values())
		                    return DefaultService(gizmo: gizmo)
		                }
		                let service: any Service = __safeDI_service()
		                return service
		            }
		            func __safeDI_serviceBuilder_Panel_Row_Scope_service(_ scope: Panel.SafeDIMockScope_Service.Row_Scope.service_Values, __safeDI_panel_serviceBuilder: SafeDIMockScope_Gizmo.DefaultService_Scope.__safeDI_Builder<any Gizmo>) -> any Service {
		                func __safeDI_service() -> DefaultService {
		                    let gizmo: any Gizmo = __safeDI_panel_serviceBuilder.gizmo(SafeDIMockScope_Gizmo.DefaultService_Scope.gizmo_Values())
		                    return DefaultService(gizmo: gizmo)
		                }
		                let service: any Service = __safeDI_service()
		                return service
		            }
		            func __safeDI_serviceBuilder_Panel(up: Panel.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gizmo.DefaultService_Scope.__safeDI_Builder<any Gizmo>>) -> Panel.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
		                .init(row: { values in __safeDI_serviceBuilder_Panel_Row_Scope(up: up.row(values)) }, service: { scope in __safeDI_serviceBuilder_Panel_service(scope, __safeDI_panel_serviceBuilder: up.service(scope)) })
		            }
		            func __safeDI_serviceBuilder_Panel_Row_Scope(up: Panel.SafeDIMockScope_Service.Row_Scope.__safeDI_Builder<SafeDIMockScope_Gizmo.DefaultService_Scope.__safeDI_Builder<any Gizmo>>) -> Panel.SafeDIMockScope_Service.Row_Scope.__safeDI_Builder<any Service> {
		                .init(service: { scope in __safeDI_serviceBuilder_Panel_Row_Scope_service(scope, __safeDI_panel_serviceBuilder: up.service(scope)) })
		            }
		            _ = Panel.__safeDI_Panel_mock_4401C36B70302082.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Panel.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Panel(up: __safeDI_gizmoBuilder_panel_serviceBuilder), safeDIOverrides: safeDIOverrides.panel)
		        }
		        let panel: Panel = __safeDI_panel()
		        return Board(panel: panel)
		    }
		}

		extension Board {
		    public enum __safeDI_Board_mock_4274BD5F87CE5E68 {}
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_appendsUnderscoreToBuildersLabel_whenPublicMockTakesAParameterUnderTheBuildersLabel() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: [
			ModuleFixture(name: "Core", packageName: "pkg", swiftFileContent: [
				"""
				import SafeDI

				public protocol Service: Sendable {}

				public final class ServiceBuilder: Sendable {
				    public init() {}
				}

				@Instantiable
				public struct Row: Instantiable, Sendable {
				    public init(serviceBuilder: ServiceBuilder, service: any Service) {
				        self.serviceBuilder = serviceBuilder
				        self.service = service
				    }

				    @Received let serviceBuilder: ServiceBuilder
				    @Instantiated let service: any Service
				}

				@Instantiable(generateMock: .public)
				public struct Panel: Instantiable, Sendable {
				    package init(row: Row) {
				        self.row = row
				    }

				    @Instantiated let row: Row
				}
				""",
			]),
		], integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Panel {
		    nonisolated public enum SafeDIMockScope_Service {
		        nonisolated public struct row_Values {
		            public let serviceBuilder: ServiceBuilder
		        }

		        nonisolated public enum Row_Scope {
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

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let row: (row_Values) -> SafeDIMockScope_Service.Row_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(row: @escaping (row_Values) -> SafeDIMockScope_Service.Row_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.row = row
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(row: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            row: ((ServiceBuilder, any Service) -> Row)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                row: row
		            )
		        }

		        public var row: ((ServiceBuilder, any Service) -> Row)? { __safeDI_storage.row }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                row: ((ServiceBuilder, any Service) -> Row)?
		            ) {
		                self.row = row
		            }

		            let row: ((ServiceBuilder, any Service) -> Row)?
		        }
		    }

		    public static func mock(
		        serviceBuilder: ServiceBuilder,
		        serviceBuilder_: @escaping () -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Panel {
		        Panel.__safeDI_mock(serviceBuilder: serviceBuilder, serviceBuilder_: .init(__safeDI_noScope: serviceBuilder_), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        serviceBuilder: ServiceBuilder,
		        serviceBuilder_ __safeDI_serviceBuilder_: Panel.SafeDIMockScope_Service.__safeDI_Builder<any Service>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Panel {
		        let __safeDI_serviceBuilder__row = __safeDI_serviceBuilder_.row(SafeDIMockScope_Service.row_Values(serviceBuilder: serviceBuilder))
		        func __safeDI_row() -> Row {
		            let service: any Service = __safeDI_serviceBuilder__row.service(SafeDIMockScope_Service.Row_Scope.service_Values())
		            return if let safeDIBuilder = safeDIOverrides.row { safeDIBuilder(serviceBuilder, service) } else { Row(serviceBuilder: serviceBuilder, service: service) }
		        }
		        let row: Row = __safeDI_row()
		        return Panel(row: row)
		    }
		}

		extension Panel {
		    public enum __safeDI_Panel_mock_0B007639F47298C9 {}
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenFillCallsPublicMockGeneratedUnderAnotherMockCondition() async {
		// `App` fills `Panel`'s places with `DefaultService`, whose public mock `Impl` generates under `TESTING`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Screen.swift"]):10:5: error: `DefaultService.mock()` is generated under `#if TESTING` in `Impl`, but this module’s mocks compile under `#if DEBUG`. Give both modules one `mockConditionalCompilation`.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "pkg", swiftFileContent: [Self.panel]),
					ModuleFixture(
						name: "Impl",
						packageName: "impl",
						swiftFileContentByFilePath: [
							"DefaultService.swift": """
							import Core
							import SafeDI

							@Instantiable(fulfillingAdditionalTypes: [Service.self], generateMock: .public)
							public struct DefaultService: Service, Instantiable {
							    package init(token: Token) {
							        self.token = token
							    }

							    @Instantiated let token: Token
							}
							""",
							"SafeDIConfiguration.swift": "#SafeDIConfiguration(mockConditionalCompilation: \"TESTING\")",
						],
						dependencies: ["Core"],
						mockConditionalCompilation: "TESTING",
					),
					ModuleFixture(name: "App", packageName: "app", swiftFileContent: [Self.screen], dependencies: ["Core", "Impl"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenPublicCallerFillsTheCalledMocksPlacesWithAFulfillerItsCallersCannotSee() async {
		await assertThrowsMultiModuleError(inModule: "Mid", diagnostics: { fixtures in
			"""
			\(NormalizedFilePath(fixtures["Mid"]!.compilerPath(of: "Board.swift")).path):5:29: error: SafeDI cannot generate the public mock of `Board`: its signature depends on `DefaultService`, which is declared in a directory this module’s `#SafeDIConfiguration` adds, and the modules that call the mock cannot see that declaration, so their calls would not match the mock. Declare `DefaultService` in a file of this module, or of a module it depends on.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "pkg", swiftFileContent: [Self.panel]),
					ModuleFixture(name: "Vendor", packageName: "vendor", swiftFileContent: [Self.defaultService], dependencies: ["Core"], isCheckoutPackage: true),
					ModuleFixture(
						name: "Mid",
						packageName: "mid",
						swiftFileContentByFilePath: [
							"Board.swift": "import Vendor\n" + Self.plainBoard,
							"SafeDIConfiguration.swift": "#SafeDIConfiguration(additionalDirectoriesToInclude: [\"$FIXTURE_ROOT/checkouts/vendor/Sources/Vendor\"])",
						],
						dependencies: ["Core", "Vendor"],
					),
					ModuleFixture(name: "App", packageName: "app", swiftFileContent: [Self.boardScreen], dependencies: ["Core", "Mid"]),
				],
				integration: .swiftPackagePlugin,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Tests – what a fill's calls pass

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenFillCallsAPublicMockWhoseTierOmitsAValueTheCallerProvides() async {
		// `App` fills `Panel`'s place with `DefaultService`, whose `public` mock passes `nil` to `TokenCache`'s `filter`,
		// which the inline mock would hand the `filter` `Panel` receives. `Panel`'s root level holds it, so the fill is handed
		// it there, and the error is located where `Screen` builds `Panel`, naming the value as `Panel`'s mock hands it, which
		// `Screen` forwards.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Screen.swift"]):12:5: error: `Panel`’s mock hands this fill `filter: [3 of Int]`, but the `public` mock SafeDI generated for `DefaultService` in module `Impl`, the narrowest one module `App` can call, does not take it: `DefaultService.mock` takes `filter` only on its `package` tier, so this call would pass `nil` to `TokenCache`, which the inline mock would hand `filter`. `[3 of Int]` is `package` as far as SafeDI can tell: SafeDI cannot read its spelling, and every initializer, `instantiate(…)` and mock method that mentions it in module `Impl` or on a type that receives it is `package` (`TokenCache.init(filter:)`); a mention on any other declaration matches it by name alone, so it does not count. Widen `TokenCache.init(filter:)` to `public`; mention `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; or stop providing `filter` on this path.
			\(fixtures["Impl"]!["TokenCache.swift"]):10:5: note: `TokenCache` receives `filter: [3 of Int]?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "pkg", swiftFileContent: [Self.panelReceivingFilter]),
					ModuleFixture(name: "Impl", packageName: "impl", swiftFileContent: [Self.defaultServiceWithTokenCache], dependencies: ["Core"]),
					ModuleFixture(name: "App", packageName: "app", swiftFileContent: [
						"""
						import Core
						import SafeDI

						@Instantiable(generateMock: true)
						public struct Screen: Instantiable {
						    public init(filter: [3 of Int], panel: Panel) {
						        self.filter = filter
						        self.panel = panel
						    }

						    @Forwarded let filter: [3 of Int]
						    @Instantiated let panel: Panel
						}
						""",
					], dependencies: ["Core", "Impl"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenPublicCallersFillCallsAPublicMockWhoseTierOmitsAValueItsCallerProvides() async {
		// `Mid` fills `Panel`'s places in `Board`'s public mock with `DefaultService`, whose `public` mock passes `nil` to
		// `TokenCache`'s `filter`, so no tier of `Board`'s mock takes the `filter` `Screen` forwards.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Screen.swift"]):12:5: error: `Screen` provides `filter: [3 of Int]`, but no mock SafeDI generated for `Board` takes it: `Board`’s mock tree calls the `public` mock SafeDI generated for `DefaultService` in module `Impl`, the narrowest one module `Mid` can call, which takes `filter` only on its `package` tier, so calling it would pass `nil` to `TokenCache`, which the inline mock would hand `filter`. `[3 of Int]` is `package` as far as SafeDI can tell: SafeDI cannot read its spelling, and every initializer, `instantiate(…)` and mock method that mentions it in module `Impl` or on a type that receives it is `package` (`TokenCache.init(filter:)`); a mention on any other declaration matches it by name alone, so it does not count. Widen `TokenCache.init(filter:)` to `public`; mention `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; or stop providing `filter` on this path.
			\(fixtures["Impl"]!["TokenCache.swift"]):10:5: note: `TokenCache` receives `filter: [3 of Int]?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "pkg", swiftFileContent: [Self.panel]),
					ModuleFixture(name: "Impl", packageName: "impl", swiftFileContent: [Self.defaultServiceWithTokenCache], dependencies: ["Core"]),
					ModuleFixture(name: "Mid", packageName: "mid", swiftFileContent: [Self.plainBoard], dependencies: ["Core", "Impl"]),
					ModuleFixture(name: "App", packageName: "app", swiftFileContent: [
						"""
						import Core
						import Mid
						import SafeDI

						@Instantiable(generateMock: true)
						public struct Screen: Instantiable {
						    public init(filter: [3 of Int], board: Board) {
						        self.filter = filter
						        self.board = board
						    }

						    @Forwarded let filter: [3 of Int]
						    @Instantiated let board: Board
						}
						""",
					], dependencies: ["Core", "Impl", "Mid"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Tests – an internal caller's passed-up builders

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsThePassedUpBuilderApart_whenInternalCallerInstantiatesAPropertyUnderTheBuildersLabel() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(app: [
			Self.thing,
			"""
			import Core
			import SafeDI

			@Instantiable(generateMock: true)
			public struct Screen: Instantiable {
			    public init(serviceBuilder: Thing, panel: Panel) {
			        self.serviceBuilder = serviceBuilder
			        self.panel = panel
			    }

			    @Instantiated let serviceBuilder: Thing
			    @Instantiated let panel: Panel
			}
			""",
		]), integration: .moduleInfo, filesToDelete: &filesToDelete)
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
		            serviceBuilder: (() -> Thing)? = nil,
		            panel: Panel.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                serviceBuilder: serviceBuilder,
		                panel: panel
		            )
		        }

		        var serviceBuilder: (() -> Thing)? { __safeDI_storage.serviceBuilder }
		        var panel: Panel.SafeDIOverrides { __safeDI_storage.panel }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                serviceBuilder: (() -> Thing)?,
		                panel: Panel.SafeDIOverrides
		            ) {
		                self.serviceBuilder = serviceBuilder
		                self.panel = panel
		            }

		            let serviceBuilder: (() -> Thing)?
		            let panel: Panel.SafeDIOverrides
		        }
		    }

		    static func mock(
		        serviceBuilder: @escaping () -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let __safeDI_serviceBuilder_ = serviceBuilder
		        let serviceBuilder = if let safeDIBuilder = safeDIOverrides.serviceBuilder { safeDIBuilder() } else { Thing() }
		        func __safeDI_panel() -> Panel {
		            _ = Panel.__safeDI_Panel_mock_4401C36B70302082.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            let serviceBuilder: () -> any Service = __safeDI_serviceBuilder_
		            return Panel.__safeDI_mock(serviceBuilder: .init(__safeDI_noScope: serviceBuilder), safeDIOverrides: safeDIOverrides.panel)
		        }
		        let panel: Panel = __safeDI_panel()
		        return Screen(serviceBuilder: serviceBuilder, panel: panel)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesThePassedUpBuilderApart_whenInternalCallerReceivesAPropertyUnderTheBuildersLabel() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(app: [
			"""
			import SafeDI

			public struct Thing: Sendable {
			    public init() {}
			}
			""",
			"""
			import Core
			import SafeDI

			@Instantiable(generateMock: true)
			public struct Screen: Instantiable {
			    public init(serviceBuilder: Thing, panel: Panel) {
			        self.serviceBuilder = serviceBuilder
			        self.panel = panel
			    }

			    @Received let serviceBuilder: Thing
			    @Instantiated let panel: Panel
			}
			""",
		]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		\(Self.screenPrelude)
		    static func mock(
		        serviceBuilder: Thing,
		        serviceBuilder_: @escaping () -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_panel() -> Panel {
		            _ = Panel.__safeDI_Panel_mock_4401C36B70302082.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            let serviceBuilder: () -> any Service = serviceBuilder_
		            return Panel.__safeDI_mock(serviceBuilder: .init(__safeDI_noScope: serviceBuilder), safeDIOverrides: safeDIOverrides.panel)
		        }
		        let panel: Panel = __safeDI_panel()
		        return Screen(serviceBuilder: serviceBuilder, panel: panel)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsThePassedUpBuilderApart_whenATypeBetweenTheCallerAndTheCallInstantiatesAPropertyUnderTheBuildersLabel() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(app: [
			Self.thing,
			"""
			import Core
			import SafeDI

			@Instantiable
			public struct Middle: Instantiable {
			    public init(serviceBuilder: Thing, panel: Panel) {
			        self.serviceBuilder = serviceBuilder
			        self.panel = panel
			    }

			    @Instantiated let serviceBuilder: Thing
			    @Instantiated let panel: Panel
			}
			""",
			"""
			import Core
			import SafeDI

			@Instantiable(generateMock: true)
			public struct Screen: Instantiable {
			    public init(middle: Middle) {
			        self.middle = middle
			    }

			    @Instantiated let middle: Middle
			}
			""",
		]), integration: .moduleInfo, filesToDelete: &filesToDelete)
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
		            middle: Middle.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                middle: middle
		            )
		        }

		        var middle: Middle.SafeDIMockConfiguration { __safeDI_storage.middle }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                middle: Middle.SafeDIMockConfiguration
		            ) {
		                self.middle = middle
		            }

		            let middle: Middle.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        serviceBuilder: @escaping () -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let __safeDI_serviceBuilder_ = serviceBuilder
		        func __safeDI_panel() -> Panel {
		            _ = Panel.__safeDI_Panel_mock_4401C36B70302082.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            let serviceBuilder: () -> any Service = __safeDI_serviceBuilder_
		            return Panel.__safeDI_mock(serviceBuilder: .init(__safeDI_noScope: serviceBuilder), safeDIOverrides: safeDIOverrides.middle.panel)
		        }
		        func __safeDI_middle(__safeDI_Middle_configuration: Middle.SafeDIMockConfiguration) -> Middle {
		            let serviceBuilder = if let safeDIBuilder = __safeDI_Middle_configuration.serviceBuilder { safeDIBuilder() } else { Thing() }
		            let panel: Panel = __safeDI_panel()
		            return if let safeDIBuilder = __safeDI_Middle_configuration.safeDIBuilder { safeDIBuilder(serviceBuilder, panel) } else { Middle(serviceBuilder: serviceBuilder, panel: panel) }
		        }
		        let middle: Middle = __safeDI_middle(__safeDI_Middle_configuration: safeDIOverrides.middle)
		        return Screen(middle: middle)
		    }
		}
		#endif

		#if DEBUG
		extension Middle {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            serviceBuilder: (() -> Thing)? = nil,
		            panel: Panel.SafeDIOverrides = .init(),
		            _ safeDIBuilder: ((Thing, Panel) -> Middle)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                serviceBuilder: serviceBuilder,
		                panel: panel,
		                safeDIBuilder: safeDIBuilder
		            )
		        }

		        var serviceBuilder: (() -> Thing)? { __safeDI_storage.serviceBuilder }
		        var panel: Panel.SafeDIOverrides { __safeDI_storage.panel }
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        var safeDIBuilder: ((Thing, Panel) -> Middle)? { __safeDI_storage.safeDIBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                serviceBuilder: (() -> Thing)?,
		                panel: Panel.SafeDIOverrides,
		                safeDIBuilder: ((Thing, Panel) -> Middle)?
		            ) {
		                self.serviceBuilder = serviceBuilder
		                self.panel = panel
		                self.safeDIBuilder = safeDIBuilder
		            }

		            let serviceBuilder: (() -> Thing)?
		            let panel: Panel.SafeDIOverrides
		            let safeDIBuilder: ((Thing, Panel) -> Middle)?
		        }
		    }
		}
		#endif

		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsOnePassedUpBuilderToBothCalledMocks_whenInternalCallerCallsTwoPublicMocksWithOneHoleType() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(core: [
			"""
			import SafeDI

			@Instantiable(generateMock: .public)
			public struct Deck: Instantiable, Sendable {
			    package init(service: any Service) {
			        self.service = service
			    }

			    @Instantiated let service: any Service
			}
			""",
		], app: [
			"""
			import Core
			import SafeDI

			@Instantiable(generateMock: true)
			public struct Screen: Instantiable {
			    public init(panel: Panel, deck: Deck) {
			        self.panel = panel
			        self.deck = deck
			    }

			    @Instantiated let panel: Panel
			    @Instantiated let deck: Deck
			}
			""",
		]), integration: .moduleInfo, filesToDelete: &filesToDelete)
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
		            panel: Panel.SafeDIOverrides = .init(),
		            deck: ((@escaping () -> any Service) -> Deck)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                panel: panel,
		                deck: deck
		            )
		        }

		        var panel: Panel.SafeDIOverrides { __safeDI_storage.panel }
		        var deck: ((@escaping () -> any Service) -> Deck)? { __safeDI_storage.deck }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                panel: Panel.SafeDIOverrides,
		                deck: ((@escaping () -> any Service) -> Deck)?
		            ) {
		                self.panel = panel
		                self.deck = deck
		            }

		            let panel: Panel.SafeDIOverrides
		            let deck: ((@escaping () -> any Service) -> Deck)?
		        }
		    }

		    static func mock(
		        serviceBuilder: @escaping () -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let __safeDI_serviceBuilder = serviceBuilder
		        func __safeDI_panel() -> Panel {
		            _ = Panel.__safeDI_Panel_mock_4401C36B70302082.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            let serviceBuilder: () -> any Service = __safeDI_serviceBuilder
		            return Panel.__safeDI_mock(serviceBuilder: .init(__safeDI_noScope: serviceBuilder), safeDIOverrides: safeDIOverrides.panel)
		        }
		        let panel: Panel = __safeDI_panel()
		        func __safeDI_deck() -> Deck {
		            _ = Deck.__safeDI_Deck_mock_5D1497ABC5C963A0.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            let serviceBuilder: () -> any Service = __safeDI_serviceBuilder
		            return if let safeDIBuilder = safeDIOverrides.deck { safeDIBuilder(serviceBuilder) } else { Deck.__safeDI_mock(serviceBuilder: .init(__safeDI_noScope: serviceBuilder)) }
		        }
		        let deck: Deck = __safeDI_deck()
		        return Screen(panel: panel, deck: deck)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsThePassedUpBuilderApart_whenTreeAlsoDeclaresTheLabelSuffixedWithTheCalledType() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(app: [
			Self.thing,
			"""
			import Core
			import SafeDI

			@Instantiable(generateMock: true)
			public struct Screen: Instantiable {
			    public init(serviceBuilder: Thing, serviceBuilder_Panel: Thing, panel: Panel) {
			        self.serviceBuilder = serviceBuilder
			        self.serviceBuilder_Panel = serviceBuilder_Panel
			        self.panel = panel
			    }

			    @Instantiated let serviceBuilder: Thing
			    @Instantiated let serviceBuilder_Panel: Thing
			    @Instantiated let panel: Panel
			}
			""",
		]), integration: .moduleInfo, filesToDelete: &filesToDelete)
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
		            serviceBuilder: (() -> Thing)? = nil,
		            serviceBuilder_Panel: (() -> Thing)? = nil,
		            panel: Panel.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                serviceBuilder: serviceBuilder,
		                serviceBuilder_Panel: serviceBuilder_Panel,
		                panel: panel
		            )
		        }

		        var serviceBuilder: (() -> Thing)? { __safeDI_storage.serviceBuilder }
		        var serviceBuilder_Panel: (() -> Thing)? { __safeDI_storage.serviceBuilder_Panel }
		        var panel: Panel.SafeDIOverrides { __safeDI_storage.panel }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                serviceBuilder: (() -> Thing)?,
		                serviceBuilder_Panel: (() -> Thing)?,
		                panel: Panel.SafeDIOverrides
		            ) {
		                self.serviceBuilder = serviceBuilder
		                self.serviceBuilder_Panel = serviceBuilder_Panel
		                self.panel = panel
		            }

		            let serviceBuilder: (() -> Thing)?
		            let serviceBuilder_Panel: (() -> Thing)?
		            let panel: Panel.SafeDIOverrides
		        }
		    }

		    static func mock(
		        serviceBuilder: @escaping () -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let __safeDI_serviceBuilder_ = serviceBuilder
		        let serviceBuilder = if let safeDIBuilder = safeDIOverrides.serviceBuilder { safeDIBuilder() } else { Thing() }
		        let serviceBuilder_Panel = if let safeDIBuilder = safeDIOverrides.serviceBuilder_Panel { safeDIBuilder() } else { Thing() }
		        func __safeDI_panel() -> Panel {
		            _ = Panel.__safeDI_Panel_mock_4401C36B70302082.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            let serviceBuilder: () -> any Service = __safeDI_serviceBuilder_
		            return Panel.__safeDI_mock(serviceBuilder: .init(__safeDI_noScope: serviceBuilder), safeDIOverrides: safeDIOverrides.panel)
		        }
		        let panel: Panel = __safeDI_panel()
		        return Screen(serviceBuilder: serviceBuilder, serviceBuilder_Panel: serviceBuilder_Panel, panel: panel)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesOneBuilderForBothForms_whenInternalCallerPassesUpAPlainPlaceBesideAnInstantiatorOfAHandConformingType() async throws {
		// `Screen`'s mock takes one builder for the places of `HoleHanded` its two calls pass up, a plain place's and an
		// `Instantiator`'s, as its twin does: `() -> HoleHanded`, which it hands `Deck`'s call through an adapter that drops
		// the value the `Instantiator` forwards.
		let core = """
		import SafeDI

		open class HoleHanded: Instantiable, @unchecked Sendable {
		    public init() {}
		}

		@Instantiable(generateMock: .public)
		public struct Panel: Instantiable, Sendable {
		    init(handed: HoleHanded) {
		        self.handed = handed
		    }

		    @Instantiated let handed: HoleHanded
		}

		@Instantiable(generateMock: .public)
		public struct Deck: Instantiable {
		    init(handedBuilder: Instantiator<HoleHanded>) {
		        self.handedBuilder = handedBuilder
		    }

		    @Instantiated let handedBuilder: Instantiator<HoleHanded>
		}
		"""
		let app = """
		import Core
		import SafeDI

		@Instantiable(generateMock: true)
		public struct Screen: Instantiable {
		    public init(panel: Panel, deck: Deck) {
		        self.panel = panel
		        self.deck = deck
		    }

		    @Instantiated let panel: Panel
		    @Instantiated let deck: Deck
		}
		"""
		let modules = [
			ModuleFixture(name: "Core", packageName: "core", swiftFileContent: [core]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContent: [app, Self.holeHandedOfEachPlace], dependencies: ["Core"]),
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
		            panel: ((@escaping () -> HoleHanded) -> Panel)? = nil,
		            deck: ((@escaping Instantiator<HoleHanded>.Builder) -> Deck)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                panel: panel,
		                deck: deck
		            )
		        }

		        var panel: ((@escaping () -> HoleHanded) -> Panel)? { __safeDI_storage.panel }
		        var deck: ((@escaping Instantiator<HoleHanded>.Builder) -> Deck)? { __safeDI_storage.deck }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                panel: ((@escaping () -> HoleHanded) -> Panel)?,
		                deck: ((@escaping Instantiator<HoleHanded>.Builder) -> Deck)?
		            ) {
		                self.panel = panel
		                self.deck = deck
		            }

		            let panel: ((@escaping () -> HoleHanded) -> Panel)?
		            let deck: ((@escaping Instantiator<HoleHanded>.Builder) -> Deck)?
		        }
		    }

		    static func mock(
		        holeHandedBuilder: @escaping () -> HoleHanded,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let __safeDI_holeHandedBuilder = holeHandedBuilder
		        let __safeDI_holeHandedBuilder_: Instantiator<HoleHanded>.Builder = { _ in __safeDI_holeHandedBuilder() }
		        func __safeDI_panel() -> Panel {
		            _ = Panel.__safeDI_Panel_mock_920AE2F589261CB1.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            let holeHandedBuilder: () -> HoleHanded = __safeDI_holeHandedBuilder
		            return if let safeDIBuilder = safeDIOverrides.panel { safeDIBuilder(holeHandedBuilder) } else { Panel.__safeDI_mock(holeHandedBuilder: .init(__safeDI_noScope: holeHandedBuilder)) }
		        }
		        let panel: Panel = __safeDI_panel()
		        func __safeDI_deck() -> Deck {
		            _ = Deck.__safeDI_Deck_mock_919F7F5998DF3519.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            let holeHandedBuilder: Instantiator<HoleHanded>.Builder = __safeDI_holeHandedBuilder_
		            return if let safeDIBuilder = safeDIOverrides.deck { safeDIBuilder(holeHandedBuilder) } else { Deck.__safeDI_mock(holeHandedBuilder: .init(__safeDI_noScope: holeHandedBuilder)) }
		        }
		        let deck: Deck = __safeDI_deck()
		        return Screen(panel: panel, deck: deck)
		    }
		}
		#endif
		"""])
		guard compileVerificationIsEnabled else { return }
		// The one builder builds both places: the inline mock is handed the same subclass for each.
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe(
			name: "Screen.mock(…)",
			expression: "Screen.mock(holeHandedBuilder: { PanelHoleHanded() })",
			knownRightExpression: "Screen.mock(handed: PanelHoleHanded(), handedBuilder: Instantiator<HoleHanded> { PanelHoleHanded() })",
		)])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesOneBuilderForBothForms_whenInternalCallerPassesUpAPlainPlaceInASendableFunctionBesideAnErasedInstantiator() async throws {
		// `Screen`'s mock takes one `@Sendable` builder for the places of `LiveService` its two calls pass up, the plain
		// place's, which the `@Sendable` builder function of `panel` captures, and the erased instantiator's, which forwards
		// nothing, as its twin does.
		let core = """
		import SafeDI

		public protocol Service: Sendable {}

		@Instantiable(generateMock: .public)
		public struct Panel: Instantiable, Sendable {
		    init(service: any Service) {
		        self.service = service
		    }

		    @Instantiated(fulfilledByType: "LiveService") let service: any Service
		}

		@Instantiable(generateMock: .public)
		public struct Deck: Instantiable, Sendable {
		    init(serviceBuilder: SendableErasedInstantiator<(), any Service>) {
		        self.serviceBuilder = serviceBuilder
		    }

		    @Instantiated(fulfilledByType: "LiveService") let serviceBuilder: SendableErasedInstantiator<(), any Service>
		}
		"""
		let app = """
		import Core
		import SafeDI

		@Instantiable(generateMock: true)
		public struct Screen: Instantiable {
		    public init(panel: SendableInstantiator<Panel>, deck: Deck) {
		        self.panel = panel
		        self.deck = deck
		    }

		    @Instantiated let panel: SendableInstantiator<Panel>
		    @Instantiated let deck: Deck
		}
		"""
		let modules = [
			ModuleFixture(name: "Core", packageName: "core", swiftFileContent: [core]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContent: [app, Self.stubService], dependencies: ["Core"]),
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
		            panel: (@Sendable (@escaping () -> any Service) -> Panel)? = nil,
		            deck: ((@escaping @Sendable () -> any Service) -> Deck)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                panel: panel,
		                deck: deck
		            )
		        }

		        var panel: (@Sendable (@escaping () -> any Service) -> Panel)? { __safeDI_storage.panel }
		        var deck: ((@escaping @Sendable () -> any Service) -> Deck)? { __safeDI_storage.deck }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                panel: (@Sendable (@escaping () -> any Service) -> Panel)?,
		                deck: ((@escaping @Sendable () -> any Service) -> Deck)?
		            ) {
		                self.panel = panel
		                self.deck = deck
		            }

		            let panel: (@Sendable (@escaping () -> any Service) -> Panel)?
		            let deck: ((@escaping @Sendable () -> any Service) -> Deck)?
		        }
		    }

		    static func mock(
		        liveService_ServiceSendableBuilder: @escaping @Sendable () -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let __safeDI_liveService_ServiceSendableBuilder = liveService_ServiceSendableBuilder
		        @Sendable nonisolated func __safeDI_panel(safeDIBuilder: (@Sendable (@escaping () -> any Service) -> Panel)?) -> Panel {
		            _ = Panel.__safeDI_Panel_mock_2FE61C6EFD6704FC.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            let liveService_ServiceBuilder: () -> any Service = __safeDI_liveService_ServiceSendableBuilder
		            return if let safeDIBuilder = safeDIBuilder { safeDIBuilder(liveService_ServiceBuilder) } else { Panel.__safeDI_mock(liveService_ServiceBuilder: .init(__safeDI_noScope: liveService_ServiceBuilder)) }
		        }
		        let __safeDI_panel__safeDIBuilder: (@Sendable (@escaping () -> any Service) -> Panel)? = safeDIOverrides.panel
		        let panel = SendableInstantiator<Panel> {
		            __safeDI_panel(safeDIBuilder: __safeDI_panel__safeDIBuilder)
		        }
		        func __safeDI_deck() -> Deck {
		            _ = Deck.__safeDI_Deck_mock_6D0422E3966C2DF8.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            let liveService_ServiceSendableBuilder: @Sendable () -> any Service = __safeDI_liveService_ServiceSendableBuilder
		            return if let safeDIBuilder = safeDIOverrides.deck { safeDIBuilder(liveService_ServiceSendableBuilder) } else { Deck.__safeDI_mock(liveService_ServiceSendableBuilder: .init(__safeDI_noScope: liveService_ServiceSendableBuilder)) }
		        }
		        let deck: Deck = __safeDI_deck()
		        return Screen(panel: panel, deck: deck)
		    }
		}
		#endif
		"""])
		guard compileVerificationIsEnabled else { return }
		// The one builder builds both places. The comparator does not call an erased instantiator, so a probe reads the value
		// `deck`'s builds.
		let builders = #"liveService_ServiceSendableBuilder: { StubService(name: "service") }"#
		let inlineArguments = #"service: StubService(name: "service"), serviceBuilder: SendableErasedInstantiator<(), any Service> { StubService(name: "service") }"#
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [
			DifferentialValueProbe(
				name: "Screen.mock(…)",
				expression: "Screen.mock(\(builders))",
				knownRightExpression: "Screen.mock(\(inlineArguments))",
			),
			DifferentialValueProbe(
				name: "Screen.mock(…)'s places",
				expression: "{ let screen = Screen.mock(\(builders)); return [screen.panel.instantiate().service, screen.deck.serviceBuilder.instantiate()] as [any Service] }()",
				knownRightExpression: "{ let screen = Screen.mock(\(inlineArguments)); return [screen.panel.instantiate().service, screen.deck.serviceBuilder.instantiate()] as [any Service] }()",
			),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesOneBuilderForBothForms_whenSeamsOwnErasedInstantiatorPlaceIsBesideACallsPlainPlaceInASendableFunction() async throws {
		// `Screen`'s mock takes one `@Sendable` builder for its own erased instantiator's places of `LiveService` and the plain
		// place that the call of `Panel`'s mock in `panel`'s `@Sendable` builder function passes up, as its twin, and its mock
		// where every type is in one module, do.
		let core = """
		import SafeDI

		public protocol Service: Sendable {}

		@Instantiable(generateDependencyTree: true, generateMock: .public)
		public struct Panel: Instantiable, Sendable {
		    init(service: any Service) {
		        self.service = service
		    }

		    @Instantiated(fulfilledByType: "LiveService") let service: any Service
		}

		@Instantiable(generateDependencyTree: true, generateMock: .public)
		public struct Deck: Instantiable, Sendable {
		    init(serviceBuilder: SendableErasedInstantiator<(), any Service>) {
		        self.serviceBuilder = serviceBuilder
		    }

		    @Instantiated(fulfilledByType: "LiveService") let serviceBuilder: SendableErasedInstantiator<(), any Service>
		}
		"""
		let app = """
		import Core
		import SafeDI

		@Instantiable(generateDependencyTree: true, generateMock: true)
		public struct Screen: Instantiable {
		    public init(panel: SendableInstantiator<Panel>, serviceBuilder: SendableErasedInstantiator<(), any Service>) {
		        self.panel = panel
		        self.serviceBuilder = serviceBuilder
		    }

		    @Instantiated let panel: SendableInstantiator<Panel>
		    @Instantiated(fulfilledByType: "LiveService") let serviceBuilder: SendableErasedInstantiator<(), any Service>
		}
		"""
		let modules = [
			ModuleFixture(name: "Core", packageName: "core", swiftFileContent: [core]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContent: [app, Self.stubService], dependencies: ["Core"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Screen {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_LiveService_ServiceSendableCarrier<__safeDI_Built>: Sendable {
		        public let panel: @Sendable () -> Panel.__safeDI_LiveService_ServiceCarrier<__safeDI_Built>
		        public let serviceBuilder: @Sendable () -> SendableErasedInstantiator<(), __safeDI_Built>.Builder

		        public init(panel: @escaping @Sendable () -> Panel.__safeDI_LiveService_ServiceCarrier<__safeDI_Built>, serviceBuilder: @escaping @Sendable () -> SendableErasedInstantiator<(), __safeDI_Built>.Builder) {
		            self.panel = panel
		            self.serviceBuilder = serviceBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(panel: { .init(__safeDI_noScope: __safeDI_builder) }, serviceBuilder: { { _ in __safeDI_builder() } })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_liveService_ServiceSendableBuilder: __safeDI_LiveService_ServiceSendableCarrier<any Service>) {
		        @inline(never) @Sendable nonisolated func __safeDI_panel() -> Panel {
		            _ = Panel.__safeDI_Panel_9FEE5F70C886577B.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Panel(__safeDI_liveService_ServiceBuilder: __safeDI_liveService_ServiceSendableBuilder.panel())
		        }
		        let panel = SendableInstantiator<Panel>(__safeDI_panel)
		        let serviceBuilder = SendableErasedInstantiator<(), any Service>(__safeDI_liveService_ServiceSendableBuilder.serviceBuilder())
		        self.init(panel: panel, serviceBuilder: serviceBuilder)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_DF708D18715237E1 {}
		}

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            panel: (@Sendable (@escaping () -> any Service) -> Panel)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                panel: panel
		            )
		        }

		        var panel: (@Sendable (@escaping () -> any Service) -> Panel)? { __safeDI_storage.panel }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage: Sendable {
		            init(
		                panel: (@Sendable (@escaping () -> any Service) -> Panel)?
		            ) {
		                self.panel = panel
		            }

		            let panel: (@Sendable (@escaping () -> any Service) -> Panel)?
		        }
		    }

		    static func mock(
		        liveService_ServiceSendableBuilder: @escaping @Sendable () -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let serviceBuilder = SendableErasedInstantiator<(), any Service>(liveService_ServiceSendableBuilder)
		        @Sendable nonisolated func __safeDI_panel(safeDIBuilder: (@Sendable (@escaping () -> any Service) -> Panel)?) -> Panel {
		            _ = Panel.__safeDI_Panel_mock_2FE61C6EFD6704FC.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            let liveService_ServiceBuilder: () -> any Service = liveService_ServiceSendableBuilder
		            return if let safeDIBuilder = safeDIBuilder { safeDIBuilder(liveService_ServiceBuilder) } else { Panel.__safeDI_mock(liveService_ServiceBuilder: .init(__safeDI_noScope: liveService_ServiceBuilder)) }
		        }
		        let __safeDI_panel__safeDIBuilder: (@Sendable (@escaping () -> any Service) -> Panel)? = safeDIOverrides.panel
		        let panel = SendableInstantiator<Panel> {
		            __safeDI_panel(safeDIBuilder: __safeDI_panel__safeDIBuilder)
		        }
		        return Screen(panel: panel, serviceBuilder: serviceBuilder)
		    }
		}
		#endif
		"""])
		guard compileVerificationIsEnabled else { return }
		// The comparator does not call an erased instantiator, so a probe reads the value `Screen`'s own builds.
		let builders = #"liveService_ServiceSendableBuilder: { StubService(name: "service") }"#
		let inlineBuilder = #"liveService_ServiceSendableBuilder: { StubService(name: "service") }"#
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [
			DifferentialValueProbe(
				name: "Screen.mock(…)",
				expression: "Screen.mock(\(builders))",
				knownRightExpression: "Screen.mock(\(inlineBuilder))",
			),
			DifferentialValueProbe(
				name: "Screen.mock(…)'s places",
				expression: "{ let screen = Screen.mock(\(builders)); return [screen.panel.instantiate().service, screen.serviceBuilder.instantiate()] as [any Service] }()",
				knownRightExpression: "{ let screen = Screen.mock(\(inlineBuilder)); return [screen.panel.instantiate().service, screen.serviceBuilder.instantiate()] as [any Service] }()",
			),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesOneBuilderForBothForms_whenEachCallerKindCallsMocksHoldingThePlaceInTwoForms() async throws {
		// `Panel` holds a plain place of `LiveService` and `Deck` an erased instantiator that forwards nothing, which
		// `Deck`'s mock takes as `() -> any Service`, as a plain place's builder is. Every kind of mock that calls both takes
		// that one builder, as its twin does, under the label `OnlyDeck`, which calls `Deck` alone, gives it, so a second call
		// renames nothing.
		let core = """
		import SafeDI

		public protocol Service: Sendable {}

		@Instantiable(generateMock: .public)
		public struct Panel: Instantiable {
		    init(service: any Service) {
		        self.service = service
		    }

		    @Instantiated(fulfilledByType: "LiveService") let service: any Service
		}

		@Instantiable(generateMock: .public)
		public struct Deck: Instantiable {
		    init(serviceBuilder: ErasedInstantiator<(), any Service>) {
		        self.serviceBuilder = serviceBuilder
		    }

		    @Instantiated(fulfilledByType: "LiveService") let serviceBuilder: ErasedInstantiator<(), any Service>
		}
		"""
		let app = """
		import Core
		import SafeDI

		#SafeDIConfiguration(additionalMocksToGenerate: ["Listed"])

		@Instantiable(generateMock: true)
		public struct OnlyDeck: Instantiable {
		    public init(deck: Deck) {
		        self.deck = deck
		    }

		    @Instantiated let deck: Deck
		}

		@Instantiable(generateMock: true)
		public struct Screen: Instantiable {
		    public init(panel: Panel, deck: Deck) {
		        self.panel = panel
		        self.deck = deck
		    }

		    @Instantiated let panel: Panel
		    @Instantiated let deck: Deck
		}

		@Instantiable
		public struct Listed: Instantiable {
		    public init(deck: Deck, panel: Panel) {
		        self.deck = deck
		        self.panel = panel
		    }

		    @Instantiated let deck: Deck
		    @Instantiated let panel: Panel
		}

		@Instantiable(generateMock: .public)
		public struct Board: Instantiable {
		    public init(panel: Panel, deck: Deck) {
		        self.panel = panel
		        self.deck = deck
		    }

		    @Instantiated let panel: Panel
		    @Instantiated let deck: Deck
		}
		"""
		let modules = [
			ModuleFixture(name: "Core", packageName: "core", swiftFileContent: [core]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContent: [app, Self.stubService], dependencies: ["Core"]),
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
		extension Board {
		    nonisolated public enum SafeDIMockScope_LiveService_Service {
		        nonisolated public struct panel_Values: Sendable {}

		        nonisolated public struct deck_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let panel: (panel_Values) -> Panel.SafeDIMockScope_LiveService_Service.__safeDI_Builder<__safeDI_Built>
		            public let deck: (deck_Values) -> Deck.SafeDIMockScope_LiveService_Service.__safeDI_Builder<__safeDI_Built>

		            public init(panel: @escaping (panel_Values) -> Panel.SafeDIMockScope_LiveService_Service.__safeDI_Builder<__safeDI_Built>, deck: @escaping (deck_Values) -> Deck.SafeDIMockScope_LiveService_Service.__safeDI_Builder<__safeDI_Built>) {
		                self.panel = panel
		                self.deck = deck
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(panel: { _ in .init(__safeDI_noScope: __safeDI_builder) }, deck: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init() {}
		    }

		    public static func mock(
		        liveService_ServiceBuilder: @escaping () -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Board {
		        Board.__safeDI_mock(liveService_ServiceBuilder: .init(__safeDI_noScope: liveService_ServiceBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        liveService_ServiceBuilder __safeDI_liveService_ServiceBuilder: Board.SafeDIMockScope_LiveService_Service.__safeDI_Builder<any Service>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Board {
		        _ = Panel.__safeDI_Panel_mock_2FE61C6EFD6704FC.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let panel = Panel.__safeDI_mock(liveService_ServiceBuilder: __safeDI_liveService_ServiceBuilder.panel(SafeDIMockScope_LiveService_Service.panel_Values()))
		        _ = Deck.__safeDI_Deck_mock_D7499869CFDA1215.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let deck = Deck.__safeDI_mock(liveService_ServiceBuilder: __safeDI_liveService_ServiceBuilder.deck(SafeDIMockScope_LiveService_Service.deck_Values()))
		        return Board(panel: panel, deck: deck)
		    }
		}

		extension Board {
		    public enum __safeDI_Board_mock_52CF18BC991361B0 {}
		}
		#endif

		#if DEBUG
		extension Listed {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            deck: ((@escaping () -> any Service) -> Deck)? = nil,
		            panel: ((@escaping () -> any Service) -> Panel)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                deck: deck,
		                panel: panel
		            )
		        }

		        var deck: ((@escaping () -> any Service) -> Deck)? { __safeDI_storage.deck }
		        var panel: ((@escaping () -> any Service) -> Panel)? { __safeDI_storage.panel }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                deck: ((@escaping () -> any Service) -> Deck)?,
		                panel: ((@escaping () -> any Service) -> Panel)?
		            ) {
		                self.deck = deck
		                self.panel = panel
		            }

		            let deck: ((@escaping () -> any Service) -> Deck)?
		            let panel: ((@escaping () -> any Service) -> Panel)?
		        }
		    }

		    static func mock(
		        liveService_ServiceBuilder: @escaping () -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Listed {
		        let __safeDI_liveService_ServiceBuilder = liveService_ServiceBuilder
		        func __safeDI_deck() -> Deck {
		            _ = Deck.__safeDI_Deck_mock_D7499869CFDA1215.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            let liveService_ServiceBuilder: () -> any Service = __safeDI_liveService_ServiceBuilder
		            return if let safeDIBuilder = safeDIOverrides.deck { safeDIBuilder(liveService_ServiceBuilder) } else { Deck.__safeDI_mock(liveService_ServiceBuilder: .init(__safeDI_noScope: liveService_ServiceBuilder)) }
		        }
		        let deck: Deck = __safeDI_deck()
		        func __safeDI_panel() -> Panel {
		            _ = Panel.__safeDI_Panel_mock_2FE61C6EFD6704FC.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            let liveService_ServiceBuilder: () -> any Service = __safeDI_liveService_ServiceBuilder
		            return if let safeDIBuilder = safeDIOverrides.panel { safeDIBuilder(liveService_ServiceBuilder) } else { Panel.__safeDI_mock(liveService_ServiceBuilder: .init(__safeDI_noScope: liveService_ServiceBuilder)) }
		        }
		        let panel: Panel = __safeDI_panel()
		        return Listed(deck: deck, panel: panel)
		    }
		}
		#endif

		#if DEBUG
		extension OnlyDeck {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            deck: ((@escaping () -> any Service) -> Deck)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                deck: deck
		            )
		        }

		        var deck: ((@escaping () -> any Service) -> Deck)? { __safeDI_storage.deck }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                deck: ((@escaping () -> any Service) -> Deck)?
		            ) {
		                self.deck = deck
		            }

		            let deck: ((@escaping () -> any Service) -> Deck)?
		        }
		    }

		    static func mock(
		        liveService_ServiceBuilder: @escaping () -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> OnlyDeck {
		        let __safeDI_liveService_ServiceBuilder = liveService_ServiceBuilder
		        func __safeDI_deck() -> Deck {
		            _ = Deck.__safeDI_Deck_mock_D7499869CFDA1215.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            let liveService_ServiceBuilder: () -> any Service = __safeDI_liveService_ServiceBuilder
		            return if let safeDIBuilder = safeDIOverrides.deck { safeDIBuilder(liveService_ServiceBuilder) } else { Deck.__safeDI_mock(liveService_ServiceBuilder: .init(__safeDI_noScope: liveService_ServiceBuilder)) }
		        }
		        let deck: Deck = __safeDI_deck()
		        return OnlyDeck(deck: deck)
		    }
		}
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            panel: ((@escaping () -> any Service) -> Panel)? = nil,
		            deck: ((@escaping () -> any Service) -> Deck)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                panel: panel,
		                deck: deck
		            )
		        }

		        var panel: ((@escaping () -> any Service) -> Panel)? { __safeDI_storage.panel }
		        var deck: ((@escaping () -> any Service) -> Deck)? { __safeDI_storage.deck }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                panel: ((@escaping () -> any Service) -> Panel)?,
		                deck: ((@escaping () -> any Service) -> Deck)?
		            ) {
		                self.panel = panel
		                self.deck = deck
		            }

		            let panel: ((@escaping () -> any Service) -> Panel)?
		            let deck: ((@escaping () -> any Service) -> Deck)?
		        }
		    }

		    static func mock(
		        liveService_ServiceBuilder: @escaping () -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let __safeDI_liveService_ServiceBuilder = liveService_ServiceBuilder
		        func __safeDI_panel() -> Panel {
		            _ = Panel.__safeDI_Panel_mock_2FE61C6EFD6704FC.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            let liveService_ServiceBuilder: () -> any Service = __safeDI_liveService_ServiceBuilder
		            return if let safeDIBuilder = safeDIOverrides.panel { safeDIBuilder(liveService_ServiceBuilder) } else { Panel.__safeDI_mock(liveService_ServiceBuilder: .init(__safeDI_noScope: liveService_ServiceBuilder)) }
		        }
		        let panel: Panel = __safeDI_panel()
		        func __safeDI_deck() -> Deck {
		            _ = Deck.__safeDI_Deck_mock_D7499869CFDA1215.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            let liveService_ServiceBuilder: () -> any Service = __safeDI_liveService_ServiceBuilder
		            return if let safeDIBuilder = safeDIOverrides.deck { safeDIBuilder(liveService_ServiceBuilder) } else { Deck.__safeDI_mock(liveService_ServiceBuilder: .init(__safeDI_noScope: liveService_ServiceBuilder)) }
		        }
		        let deck: Deck = __safeDI_deck()
		        return Screen(panel: panel, deck: deck)
		    }
		}
		#endif
		"""])
		guard compileVerificationIsEnabled else { return }
		// The comparator does not call an erased instantiator, so a probe reads the value `deck`'s builds.
		let builder = #"liveService_ServiceBuilder: { StubService(name: "service") }"#
		// The inline mock takes each value in the order its tree first builds it: `Listed` builds `deck` first.
		let service = #"service: StubService(name: "service")"#
		let serviceBuilder = #"serviceBuilder: ErasedInstantiator<(), any Service> { StubService(name: "service") }"#
		var probes = [DifferentialValueProbe]()
		for (caller, inlineArguments) in [("Screen", "\(service), \(serviceBuilder)"), ("Listed", "\(serviceBuilder), \(service)"), ("Board", "\(service), \(serviceBuilder)")] {
			probes.append(DifferentialValueProbe(
				name: "\(caller).mock(…)'s places",
				expression: "{ let caller = \(caller).mock(\(builder)); return [caller.panel.service, caller.deck.serviceBuilder.instantiate()] as [any Service] }()",
				knownRightExpression: "{ let caller = \(caller).mock(\(inlineArguments)); return [caller.panel.service, caller.deck.serviceBuilder.instantiate()] as [any Service] }()",
			))
		}
		probes.append(DifferentialValueProbe(
			name: "OnlyDeck.mock(…)'s place",
			expression: "OnlyDeck.mock(\(builder)).deck.serviceBuilder.instantiate()",
			knownRightExpression: #"OnlyDeck.mock(serviceBuilder: ErasedInstantiator<(), any Service> { StubService(name: "service") }).deck.serviceBuilder.instantiate()"#,
		))
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: probes)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsTheCalledMockACaseOfItsOwnEnum_whenPublicCallerInstantiatesAPropertyUnderTheCalledMocksBuilderLabel() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(mid: [
			Self.thing,
			"""
			import Core
			import SafeDI

			@Instantiable(generateMock: .public)
			public struct Board: Instantiable, Sendable {
			    package init(serviceBuilder: Thing, panel: Panel) {
			        self.serviceBuilder = serviceBuilder
			        self.panel = panel
			    }

			    @Instantiated let serviceBuilder: Thing
			    @Instantiated let panel: Panel
			}
			""",
		], app: [Self.boardScreen]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Mid"]?.generatedFiles == ["Mid.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Board {
		    nonisolated public enum SafeDIMockScope_Service {
		        nonisolated public struct panel_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let panel: (panel_Values) -> Panel.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>

		            public init(panel: @escaping (panel_Values) -> Panel.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>) {
		                self.panel = panel
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(panel: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            serviceBuilder: (() -> Thing)? = nil,
		            panel: Panel.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                serviceBuilder: serviceBuilder,
		                panel: panel
		            )
		        }

		        public var serviceBuilder: (() -> Thing)? { __safeDI_storage.serviceBuilder }
		        public var panel: Panel.SafeDIOverrides { __safeDI_storage.panel }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                serviceBuilder: (() -> Thing)?,
		                panel: Panel.SafeDIOverrides
		            ) {
		                self.serviceBuilder = serviceBuilder
		                self.panel = panel
		            }

		            let serviceBuilder: (() -> Thing)?
		            let panel: Panel.SafeDIOverrides
		        }
		    }

		    public static func mock(
		        serviceBuilder: @escaping () -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Board {
		        Board.__safeDI_mock(serviceBuilder: .init(__safeDI_noScope: serviceBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        serviceBuilder __safeDI_serviceBuilder_: Board.SafeDIMockScope_Service.__safeDI_Builder<any Service>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Board {
		        let serviceBuilder = if let safeDIBuilder = safeDIOverrides.serviceBuilder { safeDIBuilder() } else { Thing() }
		        _ = Panel.__safeDI_Panel_mock_4401C36B70302082.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let panel = Panel.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder_.panel(SafeDIMockScope_Service.panel_Values()), safeDIOverrides: safeDIOverrides.panel)
		        return Board(serviceBuilder: serviceBuilder, panel: panel)
		    }
		}

		extension Board {
		    public enum __safeDI_Board_mock_BA4502B330EF6045 {}
		}
		#endif
		"""])
	}

	// MARK: Tests – forwarded values

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_carriesAForwardedTypealiasOfAFunctionInTheCases_whenPublicMocksPlaceIsAnErasedInstantiator() async throws {
		let modules = [
			ModuleFixture(name: "Core", packageName: "pkg", swiftFileContent: [
				"""
				import SafeDI

				public typealias OnTap = @Sendable () -> Void

				public protocol Service: Sendable {}

				public struct AnyService: Service {
				    public init(_ service: any Service) {
				        self.service = service
				    }

				    public let service: any Service
				}

				@Instantiable(generateMock: .public)
				public struct Host: Instantiable {
				    package init(maker: ErasedInstantiator<OnTap, AnyService>, sendableMaker: SendableErasedInstantiator<OnTap, AnyService>) {
				        self.maker = maker
				        self.sendableMaker = sendableMaker
				    }

				    @Instantiated(fulfilledByType: "TapService", erasedToConcreteExistential: true) let maker: ErasedInstantiator<OnTap, AnyService>
				    @Instantiated(fulfilledByType: "TapService", erasedToConcreteExistential: true) let sendableMaker: SendableErasedInstantiator<OnTap, AnyService>
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContent: [
				"""
				import Core
				import SafeDI

				@Instantiable
				public struct TapService: Service, Instantiable {
				    public init(onTap: @escaping OnTap) {
				        self.onTap = onTap
				    }

				    @Forwarded let onTap: OnTap
				}

				@Instantiable(generateMock: true)
				public struct HostScreen: Instantiable {
				    public init(host: Host) {
				        self.host = host
				    }

				    @Instantiated let host: Host
				}
				""",
			], dependencies: ["Core"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Host {
		    nonisolated public enum SafeDIMockScope_TapService_AnyService {
		        nonisolated public struct maker_Values {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let maker: (maker_Values) -> ErasedInstantiator<OnTap, __safeDI_Built>.Builder

		            public init(maker: @escaping (maker_Values) -> ErasedInstantiator<OnTap, __safeDI_Built>.Builder) {
		                self.maker = maker
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<OnTap, __safeDI_Built>.Builder) {
		                self.init(maker: { _ in __safeDI_builder })
		            }
		        }
		    }

		    nonisolated public enum SafeDISendableMockScope_TapService_AnyService {
		        nonisolated public struct sendableMaker_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
		            public let sendableMaker: @Sendable (sendableMaker_Values) -> SendableErasedInstantiator<OnTap, __safeDI_Built>.Builder

		            public init(sendableMaker: @escaping @Sendable (sendableMaker_Values) -> SendableErasedInstantiator<OnTap, __safeDI_Built>.Builder) {
		                self.sendableMaker = sendableMaker
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<OnTap, __safeDI_Built>.Builder) {
		                self.init(sendableMaker: { _ in __safeDI_builder })
		            }
		        }
		    }

		    public static func mock(
		        tapService_AnyServiceBuilder: @escaping ErasedInstantiator<OnTap, AnyService>.Builder,
		        tapService_AnyServiceSendableBuilder: @escaping SendableErasedInstantiator<OnTap, AnyService>.Builder
		    ) -> Host {
		        Host.__safeDI_mock(tapService_AnyServiceBuilder: .init(__safeDI_noScope: tapService_AnyServiceBuilder), tapService_AnyServiceSendableBuilder: .init(__safeDI_noScope: tapService_AnyServiceSendableBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        tapService_AnyServiceBuilder __safeDI_tapService_AnyServiceBuilder: Host.SafeDIMockScope_TapService_AnyService.__safeDI_Builder<AnyService>,
		        tapService_AnyServiceSendableBuilder __safeDI_tapService_AnyServiceSendableBuilder: Host.SafeDISendableMockScope_TapService_AnyService.__safeDI_Builder<AnyService>
		    ) -> Host {
		        let maker = ErasedInstantiator<OnTap, AnyService>(__safeDI_tapService_AnyServiceBuilder.maker(SafeDIMockScope_TapService_AnyService.maker_Values()))
		        let sendableMaker = SendableErasedInstantiator<OnTap, AnyService>(__safeDI_tapService_AnyServiceSendableBuilder.sendableMaker(SafeDISendableMockScope_TapService_AnyService.sendableMaker_Values()))
		        return Host(maker: maker, sendableMaker: sendableMaker)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_mock_7BE7BA53778E487E {}
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
		extension HostScreen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            host: ((@escaping ErasedInstantiator<OnTap, AnyService>.Builder, @escaping SendableErasedInstantiator<OnTap, AnyService>.Builder) -> Host)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                host: host
		            )
		        }

		        var host: ((@escaping ErasedInstantiator<OnTap, AnyService>.Builder, @escaping SendableErasedInstantiator<OnTap, AnyService>.Builder) -> Host)? { __safeDI_storage.host }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                host: ((@escaping ErasedInstantiator<OnTap, AnyService>.Builder, @escaping SendableErasedInstantiator<OnTap, AnyService>.Builder) -> Host)?
		            ) {
		                self.host = host
		            }

		            let host: ((@escaping ErasedInstantiator<OnTap, AnyService>.Builder, @escaping SendableErasedInstantiator<OnTap, AnyService>.Builder) -> Host)?
		        }
		    }

		    static func mock(
		        tapService_AnyServiceBuilder: ErasedInstantiator<OnTap, AnyService>.Builder? = nil,
		        tapService_AnyServiceSendableBuilder: SendableErasedInstantiator<OnTap, AnyService>.Builder? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> HostScreen {
		        func __safeDI_host() -> Host {
		            func __safeDI_tapService_AnyServiceBuilder_Host_maker() -> ErasedInstantiator<OnTap, AnyService>.Builder {
		                func __safeDI_maker(onTap: @escaping OnTap) -> TapService {
		                    TapService(onTap: onTap)
		                }
		                return { forwarded in AnyService(__safeDI_maker(onTap: forwarded)) }
		            }
		            @Sendable nonisolated func __safeDI_tapService_AnyServiceSendableBuilder_Host_sendableMaker() -> SendableErasedInstantiator<OnTap, AnyService>.Builder {
		                @Sendable nonisolated func __safeDI_sendableMaker(onTap: @escaping OnTap) -> TapService {
		                    TapService(onTap: onTap)
		                }
		                return { forwarded in AnyService(__safeDI_sendableMaker(onTap: forwarded)) }
		            }
		            func __safeDI_tapService_AnyServiceBuilder_Host() -> Host.SafeDIMockScope_TapService_AnyService.__safeDI_Builder<AnyService> {
		                .init(maker: { _ in __safeDI_tapService_AnyServiceBuilder_Host_maker() })
		            }
		            @Sendable nonisolated func __safeDI_tapService_AnyServiceSendableBuilder_Host() -> Host.SafeDISendableMockScope_TapService_AnyService.__safeDI_Builder<AnyService> {
		                .init(sendableMaker: { _ in __safeDI_tapService_AnyServiceSendableBuilder_Host_sendableMaker() })
		            }
		            _ = Host.__safeDI_Host_mock_7BE7BA53778E487E.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return if let safeDIBuilder = safeDIOverrides.host { safeDIBuilder(tapService_AnyServiceBuilder ?? __safeDI_tapService_AnyServiceBuilder_Host_maker(), tapService_AnyServiceSendableBuilder ?? __safeDI_tapService_AnyServiceSendableBuilder_Host_sendableMaker()) } else { Host.__safeDI_mock(tapService_AnyServiceBuilder: tapService_AnyServiceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_tapService_AnyServiceBuilder_Host(), tapService_AnyServiceSendableBuilder: tapService_AnyServiceSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_tapService_AnyServiceSendableBuilder_Host()) }
		        }
		        let host: Host = __safeDI_host()
		        return HostScreen(host: host)
		    }
		}
		#endif
		"""])
	}

	// MARK: Tests – what each route hands on

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsEveryRouteWithItsNearestToken_whenThreeRoutesBindTheTokenAsTokenAsOptionalTokenAndNotAtAllInEveryOrder() async throws {
		// `Lobby` forwards a `Token?` and `Desk` binds a `Token`, each of which provides the `Token?` the fill reads; nothing
		// binds one beside them, so that route hands on the `Token?` the calling mock takes, as inline does. The order of
		// `Office`'s properties orders the members of the root's builder struct and the level functions, and changes nothing
		// else: two routes that read one form share one level function.
		let properties = [
			"lobbyBuilder": "@Instantiated let lobbyBuilder: Instantiator<Lobby>",
			"desk": "@Instantiated let desk: Desk",
			"model": "@Instantiated let model: Model",
		]
		let expectedAppFileByOrder: [[String]: String] = [
			["lobbyBuilder", "desk", "model"]: """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension OfficeScreen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            office: Office.SafeDIOverrides = .init(),
			            token: Token? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                office: office
			            )
			            self.token = token
			        }

			        var office: Office.SafeDIOverrides { __safeDI_storage.office }
			        let token: Token?

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                office: Office.SafeDIOverrides
			            ) {
			                self.office = office
			            }

			            let office: Office.SafeDIOverrides
			        }
			    }

			    static func mock(
			        serviceBuilder: (() -> any Service)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> OfficeScreen {
			        let token: Token? = safeDIOverrides.token
			        func __safeDI_office() -> Office {
			            func __safeDI_serviceBuilder_Office_Model_Scope_service(_ scope: Office.SafeDIMockScope_Service.Model_Scope.service_Values, token: Token?) -> any Service {
			                let service: any Service = DefaultService(token: token)
			                return service
			            }
			            func __safeDI_serviceBuilder_Office(token: Token?) -> Office.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(lobbyBuilder: { _ in __safeDI_serviceBuilder_Office_Lobby_Scope() }, desk: { _ in __safeDI_serviceBuilder_Office_Desk_Scope() }, model: { _ in __safeDI_serviceBuilder_Office_Model_Scope(token: token) })
			            }
			            func __safeDI_serviceBuilder_Office_Lobby_Scope() -> Office.SafeDIMockScope_Service.Lobby_Scope.__safeDI_Builder<any Service> {
			                .init(model: { values in __safeDI_serviceBuilder_Office_Model_Scope(token: values.token) })
			            }
			            func __safeDI_serviceBuilder_Office_Model_Scope(token: Token?) -> Office.SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<any Service> {
			                .init(service: { scope in __safeDI_serviceBuilder_Office_Model_Scope_service(scope, token: token) })
			            }
			            func __safeDI_serviceBuilder_Office_Desk_Scope() -> Office.SafeDIMockScope_Service.Desk_Scope.__safeDI_Builder<any Service> {
			                .init(model: { values in __safeDI_serviceBuilder_Office_Model_Scope_(token: values.token) })
			            }
			            func __safeDI_serviceBuilder_Office_Model_Scope_(token: Token) -> Office.SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<any Service> {
			                .init(service: { scope in __safeDI_serviceBuilder_Office_Model_Scope_service(scope, token: token) })
			            }
			            _ = Office.__safeDI_Office_mock_4F95B52A533B3978.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Office.__safeDI_mock(serviceBuilder: serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Office(token: token), safeDIOverrides: safeDIOverrides.office)
			        }
			        let office: Office = __safeDI_office()
			        return OfficeScreen(office: office)
			    }
			}
			#endif
			""",
			["lobbyBuilder", "model", "desk"]: """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension OfficeScreen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            office: Office.SafeDIOverrides = .init(),
			            token: Token? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                office: office
			            )
			            self.token = token
			        }

			        var office: Office.SafeDIOverrides { __safeDI_storage.office }
			        let token: Token?

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                office: Office.SafeDIOverrides
			            ) {
			                self.office = office
			            }

			            let office: Office.SafeDIOverrides
			        }
			    }

			    static func mock(
			        serviceBuilder: (() -> any Service)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> OfficeScreen {
			        let token: Token? = safeDIOverrides.token
			        func __safeDI_office() -> Office {
			            func __safeDI_serviceBuilder_Office_Model_Scope_service(_ scope: Office.SafeDIMockScope_Service.Model_Scope.service_Values, token: Token?) -> any Service {
			                let service: any Service = DefaultService(token: token)
			                return service
			            }
			            func __safeDI_serviceBuilder_Office(token: Token?) -> Office.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(lobbyBuilder: { _ in __safeDI_serviceBuilder_Office_Lobby_Scope() }, model: { _ in __safeDI_serviceBuilder_Office_Model_Scope(token: token) }, desk: { _ in __safeDI_serviceBuilder_Office_Desk_Scope() })
			            }
			            func __safeDI_serviceBuilder_Office_Lobby_Scope() -> Office.SafeDIMockScope_Service.Lobby_Scope.__safeDI_Builder<any Service> {
			                .init(model: { values in __safeDI_serviceBuilder_Office_Model_Scope(token: values.token) })
			            }
			            func __safeDI_serviceBuilder_Office_Model_Scope(token: Token?) -> Office.SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<any Service> {
			                .init(service: { scope in __safeDI_serviceBuilder_Office_Model_Scope_service(scope, token: token) })
			            }
			            func __safeDI_serviceBuilder_Office_Desk_Scope() -> Office.SafeDIMockScope_Service.Desk_Scope.__safeDI_Builder<any Service> {
			                .init(model: { values in __safeDI_serviceBuilder_Office_Model_Scope_(token: values.token) })
			            }
			            func __safeDI_serviceBuilder_Office_Model_Scope_(token: Token) -> Office.SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<any Service> {
			                .init(service: { scope in __safeDI_serviceBuilder_Office_Model_Scope_service(scope, token: token) })
			            }
			            _ = Office.__safeDI_Office_mock_91E1E79792065664.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Office.__safeDI_mock(serviceBuilder: serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Office(token: token), safeDIOverrides: safeDIOverrides.office)
			        }
			        let office: Office = __safeDI_office()
			        return OfficeScreen(office: office)
			    }
			}
			#endif
			""",
			["desk", "lobbyBuilder", "model"]: """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension OfficeScreen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            office: Office.SafeDIOverrides = .init(),
			            token: Token? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                office: office
			            )
			            self.token = token
			        }

			        var office: Office.SafeDIOverrides { __safeDI_storage.office }
			        let token: Token?

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                office: Office.SafeDIOverrides
			            ) {
			                self.office = office
			            }

			            let office: Office.SafeDIOverrides
			        }
			    }

			    static func mock(
			        serviceBuilder: (() -> any Service)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> OfficeScreen {
			        let token: Token? = safeDIOverrides.token
			        func __safeDI_office() -> Office {
			            func __safeDI_serviceBuilder_Office_Model_Scope_service(_ scope: Office.SafeDIMockScope_Service.Model_Scope.service_Values, token: Token?) -> any Service {
			                let service: any Service = DefaultService(token: token)
			                return service
			            }
			            func __safeDI_serviceBuilder_Office(token: Token?) -> Office.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(desk: { _ in __safeDI_serviceBuilder_Office_Desk_Scope() }, lobbyBuilder: { _ in __safeDI_serviceBuilder_Office_Lobby_Scope() }, model: { _ in __safeDI_serviceBuilder_Office_Model_Scope_(token: token) })
			            }
			            func __safeDI_serviceBuilder_Office_Desk_Scope() -> Office.SafeDIMockScope_Service.Desk_Scope.__safeDI_Builder<any Service> {
			                .init(model: { values in __safeDI_serviceBuilder_Office_Model_Scope(token: values.token) })
			            }
			            func __safeDI_serviceBuilder_Office_Model_Scope(token: Token) -> Office.SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<any Service> {
			                .init(service: { scope in __safeDI_serviceBuilder_Office_Model_Scope_service(scope, token: token) })
			            }
			            func __safeDI_serviceBuilder_Office_Lobby_Scope() -> Office.SafeDIMockScope_Service.Lobby_Scope.__safeDI_Builder<any Service> {
			                .init(model: { values in __safeDI_serviceBuilder_Office_Model_Scope_(token: values.token) })
			            }
			            func __safeDI_serviceBuilder_Office_Model_Scope_(token: Token?) -> Office.SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<any Service> {
			                .init(service: { scope in __safeDI_serviceBuilder_Office_Model_Scope_service(scope, token: token) })
			            }
			            _ = Office.__safeDI_Office_mock_A266DFED08CA10F5.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Office.__safeDI_mock(serviceBuilder: serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Office(token: token), safeDIOverrides: safeDIOverrides.office)
			        }
			        let office: Office = __safeDI_office()
			        return OfficeScreen(office: office)
			    }
			}
			#endif
			""",
			["desk", "model", "lobbyBuilder"]: """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension OfficeScreen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            office: Office.SafeDIOverrides = .init(),
			            token: Token? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                office: office
			            )
			            self.token = token
			        }

			        var office: Office.SafeDIOverrides { __safeDI_storage.office }
			        let token: Token?

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                office: Office.SafeDIOverrides
			            ) {
			                self.office = office
			            }

			            let office: Office.SafeDIOverrides
			        }
			    }

			    static func mock(
			        serviceBuilder: (() -> any Service)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> OfficeScreen {
			        let token: Token? = safeDIOverrides.token
			        func __safeDI_office() -> Office {
			            func __safeDI_serviceBuilder_Office_Model_Scope_service(_ scope: Office.SafeDIMockScope_Service.Model_Scope.service_Values, token: Token?) -> any Service {
			                let service: any Service = DefaultService(token: token)
			                return service
			            }
			            func __safeDI_serviceBuilder_Office(token: Token?) -> Office.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(desk: { _ in __safeDI_serviceBuilder_Office_Desk_Scope() }, model: { _ in __safeDI_serviceBuilder_Office_Model_Scope_(token: token) }, lobbyBuilder: { _ in __safeDI_serviceBuilder_Office_Lobby_Scope() })
			            }
			            func __safeDI_serviceBuilder_Office_Desk_Scope() -> Office.SafeDIMockScope_Service.Desk_Scope.__safeDI_Builder<any Service> {
			                .init(model: { values in __safeDI_serviceBuilder_Office_Model_Scope(token: values.token) })
			            }
			            func __safeDI_serviceBuilder_Office_Model_Scope(token: Token) -> Office.SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<any Service> {
			                .init(service: { scope in __safeDI_serviceBuilder_Office_Model_Scope_service(scope, token: token) })
			            }
			            func __safeDI_serviceBuilder_Office_Model_Scope_(token: Token?) -> Office.SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<any Service> {
			                .init(service: { scope in __safeDI_serviceBuilder_Office_Model_Scope_service(scope, token: token) })
			            }
			            func __safeDI_serviceBuilder_Office_Lobby_Scope() -> Office.SafeDIMockScope_Service.Lobby_Scope.__safeDI_Builder<any Service> {
			                .init(model: { values in __safeDI_serviceBuilder_Office_Model_Scope_(token: values.token) })
			            }
			            _ = Office.__safeDI_Office_mock_F5856D2B9C057ABE.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Office.__safeDI_mock(serviceBuilder: serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Office(token: token), safeDIOverrides: safeDIOverrides.office)
			        }
			        let office: Office = __safeDI_office()
			        return OfficeScreen(office: office)
			    }
			}
			#endif
			""",
			["model", "lobbyBuilder", "desk"]: """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension OfficeScreen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            office: Office.SafeDIOverrides = .init(),
			            token: Token? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                office: office
			            )
			            self.token = token
			        }

			        var office: Office.SafeDIOverrides { __safeDI_storage.office }
			        let token: Token?

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                office: Office.SafeDIOverrides
			            ) {
			                self.office = office
			            }

			            let office: Office.SafeDIOverrides
			        }
			    }

			    static func mock(
			        serviceBuilder: (() -> any Service)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> OfficeScreen {
			        let token: Token? = safeDIOverrides.token
			        func __safeDI_office() -> Office {
			            func __safeDI_serviceBuilder_Office_Model_Scope_service(_ scope: Office.SafeDIMockScope_Service.Model_Scope.service_Values, token: Token?) -> any Service {
			                let service: any Service = DefaultService(token: token)
			                return service
			            }
			            func __safeDI_serviceBuilder_Office(token: Token?) -> Office.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(model: { _ in __safeDI_serviceBuilder_Office_Model_Scope(token: token) }, lobbyBuilder: { _ in __safeDI_serviceBuilder_Office_Lobby_Scope() }, desk: { _ in __safeDI_serviceBuilder_Office_Desk_Scope() })
			            }
			            func __safeDI_serviceBuilder_Office_Model_Scope(token: Token?) -> Office.SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<any Service> {
			                .init(service: { scope in __safeDI_serviceBuilder_Office_Model_Scope_service(scope, token: token) })
			            }
			            func __safeDI_serviceBuilder_Office_Lobby_Scope() -> Office.SafeDIMockScope_Service.Lobby_Scope.__safeDI_Builder<any Service> {
			                .init(model: { values in __safeDI_serviceBuilder_Office_Model_Scope(token: values.token) })
			            }
			            func __safeDI_serviceBuilder_Office_Desk_Scope() -> Office.SafeDIMockScope_Service.Desk_Scope.__safeDI_Builder<any Service> {
			                .init(model: { values in __safeDI_serviceBuilder_Office_Model_Scope_(token: values.token) })
			            }
			            func __safeDI_serviceBuilder_Office_Model_Scope_(token: Token) -> Office.SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<any Service> {
			                .init(service: { scope in __safeDI_serviceBuilder_Office_Model_Scope_service(scope, token: token) })
			            }
			            _ = Office.__safeDI_Office_mock_004D069F4A3620FF.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Office.__safeDI_mock(serviceBuilder: serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Office(token: token), safeDIOverrides: safeDIOverrides.office)
			        }
			        let office: Office = __safeDI_office()
			        return OfficeScreen(office: office)
			    }
			}
			#endif
			""",
			["model", "desk", "lobbyBuilder"]: """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension OfficeScreen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            office: Office.SafeDIOverrides = .init(),
			            token: Token? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                office: office
			            )
			            self.token = token
			        }

			        var office: Office.SafeDIOverrides { __safeDI_storage.office }
			        let token: Token?

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                office: Office.SafeDIOverrides
			            ) {
			                self.office = office
			            }

			            let office: Office.SafeDIOverrides
			        }
			    }

			    static func mock(
			        serviceBuilder: (() -> any Service)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> OfficeScreen {
			        let token: Token? = safeDIOverrides.token
			        func __safeDI_office() -> Office {
			            func __safeDI_serviceBuilder_Office_Model_Scope_service(_ scope: Office.SafeDIMockScope_Service.Model_Scope.service_Values, token: Token?) -> any Service {
			                let service: any Service = DefaultService(token: token)
			                return service
			            }
			            func __safeDI_serviceBuilder_Office(token: Token?) -> Office.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(model: { _ in __safeDI_serviceBuilder_Office_Model_Scope(token: token) }, desk: { _ in __safeDI_serviceBuilder_Office_Desk_Scope() }, lobbyBuilder: { _ in __safeDI_serviceBuilder_Office_Lobby_Scope() })
			            }
			            func __safeDI_serviceBuilder_Office_Model_Scope(token: Token?) -> Office.SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<any Service> {
			                .init(service: { scope in __safeDI_serviceBuilder_Office_Model_Scope_service(scope, token: token) })
			            }
			            func __safeDI_serviceBuilder_Office_Desk_Scope() -> Office.SafeDIMockScope_Service.Desk_Scope.__safeDI_Builder<any Service> {
			                .init(model: { values in __safeDI_serviceBuilder_Office_Model_Scope_(token: values.token) })
			            }
			            func __safeDI_serviceBuilder_Office_Model_Scope_(token: Token) -> Office.SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<any Service> {
			                .init(service: { scope in __safeDI_serviceBuilder_Office_Model_Scope_service(scope, token: token) })
			            }
			            func __safeDI_serviceBuilder_Office_Lobby_Scope() -> Office.SafeDIMockScope_Service.Lobby_Scope.__safeDI_Builder<any Service> {
			                .init(model: { values in __safeDI_serviceBuilder_Office_Model_Scope(token: values.token) })
			            }
			            _ = Office.__safeDI_Office_mock_0EA84CC466CEEDD6.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Office.__safeDI_mock(serviceBuilder: serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Office(token: token), safeDIOverrides: safeDIOverrides.office)
			        }
			        let office: Office = __safeDI_office()
			        return OfficeScreen(office: office)
			    }
			}
			#endif
			""",
		]
		for order in Self.permutations(of: ["lobbyBuilder", "desk", "model"]) {
			let modules = Self.modules(core: [Self.officeOfThreeRoutes(order: order.map { properties[$0] ?? "" })], app: [Self.officeScreen, Self.defaultServiceReceivingTokenIfAvailable])
			let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
			#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + (expectedAppFileByOrder[order] ?? "")])
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresOneEnumPerTypeAndCallerCompiles_whenPublicMocksTwentyFourScreensReachEachOtherInLayers() async throws {
		// Shape E: `Home` opens four screens, each screen opens three of the next layer's four, six layers deep, and each
		// screen of the last layer builds a model whose `api` only `App` can build. By type the enum has a values struct per
		// property: 4 + 20 × 3 + 4 + 4. The screens are internal, so `App` calls `Home`'s public mock rather than building its
		// tree.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.publicShapeEModules(screenCount: 24), integration: .moduleInfo, filesToDelete: &filesToDelete)
		let coreFile = try #require(output.modules["Core"]?.generatedFiles["Core.swift"])
		let enumDeclaration = try #require(coreFile.components(separatedBy: "    /// Overrides for the mock dependency tree.").first)
		let valuesCount = enumDeclaration.components(separatedBy: "\n").filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("nonisolated public struct ") && $0.contains("_Values") }.count
		let enumCount = enumDeclaration.components(separatedBy: "nonisolated public enum ").count - 1
		#expect(valuesCount == 72)
		#expect(enumCount == 29)
		// `App` fills every place, so it declares one level function per enum, each returning its level's struct: the caller
		// compiled above.
		let appFile = try #require(output.modules["App"]?.generatedFiles["App.swift"])
		#expect(appFile.components(separatedBy: "func __safeDI_apiBuilder_Home").count - 1 == 29)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsEachRouteItsNearestTokenInTheFormTheFillReads_whenOneRouteForwardsAnOptionalTokenAndAnotherBindsAToken() async throws {
		let modules = Self.modules(core: [Self.officeForwardingOptionalToken], app: [Self.officeScreen, Self.defaultServiceReceivingTokenIfAvailable])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Office {
		    nonisolated public enum SafeDIMockScope_Service {
		        nonisolated public struct lobbyBuilder_Values {
		            public let token: Token
		        }

		        nonisolated public struct model_Values {
		            public let token: Token
		            public let lobbyBuilder: Instantiator<Lobby>
		        }

		        nonisolated public enum Lobby_Scope {
		            nonisolated public struct model_Values {
		                public let token: Token?
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let model: (model_Values) -> SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(model: @escaping (model_Values) -> SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.model = model
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(model: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		                }
		            }
		        }

		        nonisolated public enum Model_Scope {
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

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let lobbyBuilder: (lobbyBuilder_Values) -> SafeDIMockScope_Service.Lobby_Scope.__safeDI_Builder<__safeDI_Built>
		            public let model: (model_Values) -> SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(lobbyBuilder: @escaping (lobbyBuilder_Values) -> SafeDIMockScope_Service.Lobby_Scope.__safeDI_Builder<__safeDI_Built>, model: @escaping (model_Values) -> SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.lobbyBuilder = lobbyBuilder
		                self.model = model
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(lobbyBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) }, model: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            token: (() -> Token)? = nil,
		            lobbyBuilder: __safeDI_Core_Lobby_MockConfiguration = .init(),
		            model: ((any Service) -> Model)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                token: token,
		                lobbyBuilder: lobbyBuilder,
		                model: model
		            )
		        }

		        public var token: (() -> Token)? { __safeDI_storage.token }
		        public var lobbyBuilder: __safeDI_Core_Lobby_MockConfiguration { __safeDI_storage.lobbyBuilder }
		        public var model: ((any Service) -> Model)? { __safeDI_storage.model }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                token: (() -> Token)?,
		                lobbyBuilder: __safeDI_Core_Lobby_MockConfiguration,
		                model: ((any Service) -> Model)?
		            ) {
		                self.token = token
		                self.lobbyBuilder = lobbyBuilder
		                self.model = model
		            }

		            let token: (() -> Token)?
		            let lobbyBuilder: __safeDI_Core_Lobby_MockConfiguration
		            let model: ((any Service) -> Model)?
		        }
		    }

		    public static func mock(
		        serviceBuilder: @escaping () -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Office {
		        Office.__safeDI_mock(serviceBuilder: .init(__safeDI_noScope: serviceBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        serviceBuilder __safeDI_serviceBuilder: Office.SafeDIMockScope_Service.__safeDI_Builder<any Service>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Office {
		        let token = if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder() } else { Token() }
		        let __safeDI_serviceBuilder_lobbyBuilder = __safeDI_serviceBuilder.lobbyBuilder(SafeDIMockScope_Service.lobbyBuilder_Values(token: token))
		        func __safeDI_lobbyBuilder(token: Token?) -> Lobby {
		            let __safeDI_serviceBuilder_model = __safeDI_serviceBuilder_lobbyBuilder.model(SafeDIMockScope_Service.Lobby_Scope.model_Values(token: token))
		            func __safeDI_model() -> Model {
		                let service: any Service = __safeDI_serviceBuilder_model.service(SafeDIMockScope_Service.Model_Scope.service_Values())
		                return if let safeDIBuilder = safeDIOverrides.lobbyBuilder.model { safeDIBuilder(service) } else { Model(service: service) }
		            }
		            let model: Model = __safeDI_model()
		            return Lobby.__safeDI_init(token: token, model: model, safeDIBuilder: safeDIOverrides.lobbyBuilder.safeDIBuilder)
		        }
		        let lobbyBuilder = Instantiator<Lobby> {
		            __safeDI_lobbyBuilder(token: $0)
		        }
		        let __safeDI_serviceBuilder_model = __safeDI_serviceBuilder.model(SafeDIMockScope_Service.model_Values(token: token, lobbyBuilder: lobbyBuilder))
		        func __safeDI_model() -> Model {
		            let service: any Service = __safeDI_serviceBuilder_model.service(SafeDIMockScope_Service.Model_Scope.service_Values())
		            return if let safeDIBuilder = safeDIOverrides.model { safeDIBuilder(service) } else { Model(service: service) }
		        }
		        let model: Model = __safeDI_model()
		        return Office(token: token, lobbyBuilder: lobbyBuilder, model: model)
		    }
		}

		extension Office {
		    public enum __safeDI_Office_mock_0EA6B4982010697F {}
		}
		#endif

		#if DEBUG
		extension Panel {
		    nonisolated public enum SafeDIMockScope_Service {
		        nonisolated public struct row_Values {}

		        nonisolated public struct service_Values {
		            public let row: Row
		        }

		        nonisolated public enum Row_Scope {
		            nonisolated public struct service_Values {
		                public let token: Token
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

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let row: (row_Values) -> SafeDIMockScope_Service.Row_Scope.__safeDI_Builder<__safeDI_Built>
		            public let service: (service_Values) -> __safeDI_Built

		            public init(row: @escaping (row_Values) -> SafeDIMockScope_Service.Row_Scope.__safeDI_Builder<__safeDI_Built>, service: @escaping (service_Values) -> __safeDI_Built) {
		                self.row = row
		                self.service = service
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(row: { _ in .init(__safeDI_noScope: __safeDI_builder) }, service: { _ in __safeDI_builder() })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            row: __safeDI_Core_Row_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                row: row
		            )
		        }

		        public var row: __safeDI_Core_Row_MockConfiguration { __safeDI_storage.row }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                row: __safeDI_Core_Row_MockConfiguration
		            ) {
		                self.row = row
		            }

		            let row: __safeDI_Core_Row_MockConfiguration
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
		        let __safeDI_serviceBuilder_row = __safeDI_serviceBuilder.row(SafeDIMockScope_Service.row_Values())
		        func __safeDI_row() -> Row {
		            let token = if let safeDIBuilder = safeDIOverrides.row.token { safeDIBuilder() } else { Token() }
		            let service: any Service = __safeDI_serviceBuilder_row.service(SafeDIMockScope_Service.Row_Scope.service_Values(token: token))
		            return Row.__safeDI_init(token: token, service: service, safeDIBuilder: safeDIOverrides.row.safeDIBuilder)
		        }
		        let row: Row = __safeDI_row()
		        let service: any Service = __safeDI_serviceBuilder.service(SafeDIMockScope_Service.service_Values(row: row))
		        return Panel(row: row, service: service)
		    }
		}

		extension Panel {
		    public enum __safeDI_Panel_mock_4401C36B70302082 {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `Lobby` is constructed within the public mock trees of module `Core`.
		nonisolated public struct __safeDI_Core_Lobby_MockConfiguration {
		    public init(
		        model: ((any Service) -> Model)? = nil,
		        _ safeDIBuilder: ((Token?, Model) -> Lobby)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            model: model,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var model: ((any Service) -> Model)? { __safeDI_storage.model }
		    /// Overrides how `Lobby` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((Token?, Model) -> Lobby)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            model: ((any Service) -> Model)?,
		            safeDIBuilder: ((Token?, Model) -> Lobby)?
		        ) {
		            self.model = model
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let model: ((any Service) -> Model)?
		        let safeDIBuilder: ((Token?, Model) -> Lobby)?
		    }
		}

		extension Lobby {
		    static func __safeDI_init(token: Token?, model: Model, safeDIBuilder: ((Token?, Model) -> Lobby)?) -> Lobby {
		        if let safeDIBuilder { safeDIBuilder(token, model) } else { Lobby(token: token, model: model) }
		    }
		}

		/// Configuration for how `Row` is constructed within the public mock trees of module `Core`.
		nonisolated public struct __safeDI_Core_Row_MockConfiguration {
		    public init(
		        token: (() -> Token)? = nil,
		        _ safeDIBuilder: ((Token, any Service) -> Row)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            token: token,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var token: (() -> Token)? { __safeDI_storage.token }
		    /// Overrides how `Row` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((Token, any Service) -> Row)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            token: (() -> Token)?,
		            safeDIBuilder: ((Token, any Service) -> Row)?
		        ) {
		            self.token = token
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let token: (() -> Token)?
		        let safeDIBuilder: ((Token, any Service) -> Row)?
		    }
		}

		extension Row {
		    static func __safeDI_init(token: Token, service: any Service, safeDIBuilder: ((Token, any Service) -> Row)?) -> Row {
		        if let safeDIBuilder { safeDIBuilder(token, service) } else { Row(token: token, service: service) }
		    }
		}
		#endif

		"""])
		// The fill reads `token: Token?`, which `Lobby`'s `Token?` and `Office`'s `Token` both provide: every route fills.
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension OfficeScreen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            office: Office.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                office: office
		            )
		        }

		        var office: Office.SafeDIOverrides { __safeDI_storage.office }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                office: Office.SafeDIOverrides
		            ) {
		                self.office = office
		            }

		            let office: Office.SafeDIOverrides
		        }
		    }

		    static func mock(
		        serviceBuilder: (() -> any Service)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> OfficeScreen {
		        func __safeDI_office() -> Office {
		            func __safeDI_serviceBuilder_Office_Model_Scope_service(_ scope: Office.SafeDIMockScope_Service.Model_Scope.service_Values, token: Token?) -> any Service {
		                let service: any Service = DefaultService(token: token)
		                return service
		            }
		            func __safeDI_serviceBuilder_Office() -> Office.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
		                .init(lobbyBuilder: { _ in __safeDI_serviceBuilder_Office_Lobby_Scope() }, model: { values in __safeDI_serviceBuilder_Office_Model_Scope_(token: values.token) })
		            }
		            func __safeDI_serviceBuilder_Office_Lobby_Scope() -> Office.SafeDIMockScope_Service.Lobby_Scope.__safeDI_Builder<any Service> {
		                .init(model: { values in __safeDI_serviceBuilder_Office_Model_Scope(token: values.token) })
		            }
		            func __safeDI_serviceBuilder_Office_Model_Scope(token: Token?) -> Office.SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<any Service> {
		                .init(service: { scope in __safeDI_serviceBuilder_Office_Model_Scope_service(scope, token: token) })
		            }
		            func __safeDI_serviceBuilder_Office_Model_Scope_(token: Token) -> Office.SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<any Service> {
		                .init(service: { scope in __safeDI_serviceBuilder_Office_Model_Scope_service(scope, token: token) })
		            }
		            _ = Office.__safeDI_Office_mock_0EA6B4982010697F.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Office.__safeDI_mock(serviceBuilder: serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Office(), safeDIOverrides: safeDIOverrides.office)
		        }
		        let office: Office = __safeDI_office()
		        return OfficeScreen(office: office)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [
			DifferentialValueProbe("OfficeScreen.mock().office.lobbyBuilder.instantiate(Token()).model.service"),
			DifferentialValueProbe("OfficeScreen.mock().office.lobbyBuilder.instantiate(nil).model.service"),
			DifferentialValueProbe("OfficeScreen.mock().office.model.service"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsEveryRouteWithoutPassingUp_whenOneRouteBindsATokenAndAnotherAnOptionalToken() async throws {
		let modules = Self.modules(core: [Self.officeOfThreeRoutes(order: ["@Instantiated let lobbyBuilder: Instantiator<Lobby>", "@Instantiated let desk: Desk"])], app: [Self.officeScreen, Self.defaultServiceReceivingTokenIfAvailable])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Office {
		    nonisolated public enum SafeDIMockScope_Service {
		        nonisolated public struct lobbyBuilder_Values {}

		        nonisolated public struct desk_Values {
		            public let lobbyBuilder: Instantiator<Lobby>
		        }

		        nonisolated public enum Lobby_Scope {
		            nonisolated public struct model_Values {
		                public let token: Token?
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let model: (model_Values) -> SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(model: @escaping (model_Values) -> SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.model = model
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(model: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		                }
		            }
		        }

		        nonisolated public enum Desk_Scope {
		            nonisolated public struct model_Values {
		                public let token: Token
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let model: (model_Values) -> SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(model: @escaping (model_Values) -> SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.model = model
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(model: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		                }
		            }
		        }

		        nonisolated public enum Model_Scope {
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

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let lobbyBuilder: (lobbyBuilder_Values) -> SafeDIMockScope_Service.Lobby_Scope.__safeDI_Builder<__safeDI_Built>
		            public let desk: (desk_Values) -> SafeDIMockScope_Service.Desk_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(lobbyBuilder: @escaping (lobbyBuilder_Values) -> SafeDIMockScope_Service.Lobby_Scope.__safeDI_Builder<__safeDI_Built>, desk: @escaping (desk_Values) -> SafeDIMockScope_Service.Desk_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.lobbyBuilder = lobbyBuilder
		                self.desk = desk
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(lobbyBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) }, desk: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            lobbyBuilder: __safeDI_Core_Lobby_MockConfiguration = .init(),
		            desk: __safeDI_Core_Desk_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                lobbyBuilder: lobbyBuilder,
		                desk: desk
		            )
		        }

		        public var lobbyBuilder: __safeDI_Core_Lobby_MockConfiguration { __safeDI_storage.lobbyBuilder }
		        public var desk: __safeDI_Core_Desk_MockConfiguration { __safeDI_storage.desk }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                lobbyBuilder: __safeDI_Core_Lobby_MockConfiguration,
		                desk: __safeDI_Core_Desk_MockConfiguration
		            ) {
		                self.lobbyBuilder = lobbyBuilder
		                self.desk = desk
		            }

		            let lobbyBuilder: __safeDI_Core_Lobby_MockConfiguration
		            let desk: __safeDI_Core_Desk_MockConfiguration
		        }
		    }

		    public static func mock(
		        serviceBuilder: @escaping () -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Office {
		        Office.__safeDI_mock(serviceBuilder: .init(__safeDI_noScope: serviceBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        serviceBuilder __safeDI_serviceBuilder: Office.SafeDIMockScope_Service.__safeDI_Builder<any Service>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Office {
		        let __safeDI_serviceBuilder_lobbyBuilder = __safeDI_serviceBuilder.lobbyBuilder(SafeDIMockScope_Service.lobbyBuilder_Values())
		        func __safeDI_lobbyBuilder(token: Token?) -> Lobby {
		            let __safeDI_serviceBuilder_model = __safeDI_serviceBuilder_lobbyBuilder.model(SafeDIMockScope_Service.Lobby_Scope.model_Values(token: token))
		            func __safeDI_model() -> Model {
		                let service: any Service = __safeDI_serviceBuilder_model.service(SafeDIMockScope_Service.Model_Scope.service_Values())
		                return if let safeDIBuilder = safeDIOverrides.lobbyBuilder.model { safeDIBuilder(service) } else { Model(service: service) }
		            }
		            let model: Model = __safeDI_model()
		            return Lobby.__safeDI_init(token: token, model: model, safeDIBuilder: safeDIOverrides.lobbyBuilder.safeDIBuilder)
		        }
		        let lobbyBuilder = Instantiator<Lobby> {
		            __safeDI_lobbyBuilder(token: $0)
		        }
		        let __safeDI_serviceBuilder_desk = __safeDI_serviceBuilder.desk(SafeDIMockScope_Service.desk_Values(lobbyBuilder: lobbyBuilder))
		        func __safeDI_desk() -> Desk {
		            let token = if let safeDIBuilder = safeDIOverrides.desk.token { safeDIBuilder() } else { Token() }
		            let __safeDI_serviceBuilder_model = __safeDI_serviceBuilder_desk.model(SafeDIMockScope_Service.Desk_Scope.model_Values(token: token))
		            func __safeDI_model() -> Model {
		                let service: any Service = __safeDI_serviceBuilder_model.service(SafeDIMockScope_Service.Model_Scope.service_Values())
		                return if let safeDIBuilder = safeDIOverrides.desk.model { safeDIBuilder(service) } else { Model(service: service) }
		            }
		            let model: Model = __safeDI_model()
		            return Desk.__safeDI_init(token: token, model: model, safeDIBuilder: safeDIOverrides.desk.safeDIBuilder)
		        }
		        let desk: Desk = __safeDI_desk()
		        return Office(lobbyBuilder: lobbyBuilder, desk: desk)
		    }
		}

		extension Office {
		    public enum __safeDI_Office_mock_B1E33A311A11F6C1 {}
		}
		#endif

		#if DEBUG
		extension Panel {
		    nonisolated public enum SafeDIMockScope_Service {
		        nonisolated public struct row_Values {}

		        nonisolated public struct service_Values {
		            public let row: Row
		        }

		        nonisolated public enum Row_Scope {
		            nonisolated public struct service_Values {
		                public let token: Token
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

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let row: (row_Values) -> SafeDIMockScope_Service.Row_Scope.__safeDI_Builder<__safeDI_Built>
		            public let service: (service_Values) -> __safeDI_Built

		            public init(row: @escaping (row_Values) -> SafeDIMockScope_Service.Row_Scope.__safeDI_Builder<__safeDI_Built>, service: @escaping (service_Values) -> __safeDI_Built) {
		                self.row = row
		                self.service = service
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(row: { _ in .init(__safeDI_noScope: __safeDI_builder) }, service: { _ in __safeDI_builder() })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            row: __safeDI_Core_Row_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                row: row
		            )
		        }

		        public var row: __safeDI_Core_Row_MockConfiguration { __safeDI_storage.row }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                row: __safeDI_Core_Row_MockConfiguration
		            ) {
		                self.row = row
		            }

		            let row: __safeDI_Core_Row_MockConfiguration
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
		        let __safeDI_serviceBuilder_row = __safeDI_serviceBuilder.row(SafeDIMockScope_Service.row_Values())
		        func __safeDI_row() -> Row {
		            let token = if let safeDIBuilder = safeDIOverrides.row.token { safeDIBuilder() } else { Token() }
		            let service: any Service = __safeDI_serviceBuilder_row.service(SafeDIMockScope_Service.Row_Scope.service_Values(token: token))
		            return Row.__safeDI_init(token: token, service: service, safeDIBuilder: safeDIOverrides.row.safeDIBuilder)
		        }
		        let row: Row = __safeDI_row()
		        let service: any Service = __safeDI_serviceBuilder.service(SafeDIMockScope_Service.service_Values(row: row))
		        return Panel(row: row, service: service)
		    }
		}

		extension Panel {
		    public enum __safeDI_Panel_mock_4401C36B70302082 {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `Lobby` is constructed within the public mock trees of module `Core`.
		nonisolated public struct __safeDI_Core_Lobby_MockConfiguration {
		    public init(
		        model: ((any Service) -> Model)? = nil,
		        _ safeDIBuilder: ((Token?, Model) -> Lobby)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            model: model,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var model: ((any Service) -> Model)? { __safeDI_storage.model }
		    /// Overrides how `Lobby` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((Token?, Model) -> Lobby)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            model: ((any Service) -> Model)?,
		            safeDIBuilder: ((Token?, Model) -> Lobby)?
		        ) {
		            self.model = model
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let model: ((any Service) -> Model)?
		        let safeDIBuilder: ((Token?, Model) -> Lobby)?
		    }
		}

		extension Lobby {
		    static func __safeDI_init(token: Token?, model: Model, safeDIBuilder: ((Token?, Model) -> Lobby)?) -> Lobby {
		        if let safeDIBuilder { safeDIBuilder(token, model) } else { Lobby(token: token, model: model) }
		    }
		}

		/// Configuration for how `Desk` is constructed within the public mock trees of module `Core`.
		nonisolated public struct __safeDI_Core_Desk_MockConfiguration {
		    public init(
		        token: (() -> Token)? = nil,
		        model: ((any Service) -> Model)? = nil,
		        _ safeDIBuilder: ((Token, Model) -> Desk)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            token: token,
		            model: model,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var token: (() -> Token)? { __safeDI_storage.token }
		    public var model: ((any Service) -> Model)? { __safeDI_storage.model }
		    /// Overrides how `Desk` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((Token, Model) -> Desk)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            token: (() -> Token)?,
		            model: ((any Service) -> Model)?,
		            safeDIBuilder: ((Token, Model) -> Desk)?
		        ) {
		            self.token = token
		            self.model = model
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let token: (() -> Token)?
		        let model: ((any Service) -> Model)?
		        let safeDIBuilder: ((Token, Model) -> Desk)?
		    }
		}

		extension Desk {
		    static func __safeDI_init(token: Token, model: Model, safeDIBuilder: ((Token, Model) -> Desk)?) -> Desk {
		        if let safeDIBuilder { safeDIBuilder(token, model) } else { Desk(token: token, model: model) }
		    }
		}

		/// Configuration for how `Row` is constructed within the public mock trees of module `Core`.
		nonisolated public struct __safeDI_Core_Row_MockConfiguration {
		    public init(
		        token: (() -> Token)? = nil,
		        _ safeDIBuilder: ((Token, any Service) -> Row)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            token: token,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var token: (() -> Token)? { __safeDI_storage.token }
		    /// Overrides how `Row` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((Token, any Service) -> Row)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            token: (() -> Token)?,
		            safeDIBuilder: ((Token, any Service) -> Row)?
		        ) {
		            self.token = token
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let token: (() -> Token)?
		        let safeDIBuilder: ((Token, any Service) -> Row)?
		    }
		}

		extension Row {
		    static func __safeDI_init(token: Token, service: any Service, safeDIBuilder: ((Token, any Service) -> Row)?) -> Row {
		        if let safeDIBuilder { safeDIBuilder(token, service) } else { Row(token: token, service: service) }
		    }
		}
		#endif

		"""])
		// Every place is filled, so no dispatcher takes `passUp`, and `Model`'s takes the `Token?` the fill reads, which both routes provide.
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension OfficeScreen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            office: Office.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                office: office
		            )
		        }

		        var office: Office.SafeDIOverrides { __safeDI_storage.office }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                office: Office.SafeDIOverrides
		            ) {
		                self.office = office
		            }

		            let office: Office.SafeDIOverrides
		        }
		    }

		    static func mock(
		        serviceBuilder: (() -> any Service)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> OfficeScreen {
		        func __safeDI_office() -> Office {
		            func __safeDI_serviceBuilder_Office_Model_Scope_service(_ scope: Office.SafeDIMockScope_Service.Model_Scope.service_Values, token: Token?) -> any Service {
		                let service: any Service = DefaultService(token: token)
		                return service
		            }
		            func __safeDI_serviceBuilder_Office() -> Office.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
		                .init(lobbyBuilder: { _ in __safeDI_serviceBuilder_Office_Lobby_Scope() }, desk: { _ in __safeDI_serviceBuilder_Office_Desk_Scope() })
		            }
		            func __safeDI_serviceBuilder_Office_Lobby_Scope() -> Office.SafeDIMockScope_Service.Lobby_Scope.__safeDI_Builder<any Service> {
		                .init(model: { values in __safeDI_serviceBuilder_Office_Model_Scope(token: values.token) })
		            }
		            func __safeDI_serviceBuilder_Office_Model_Scope(token: Token?) -> Office.SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<any Service> {
		                .init(service: { scope in __safeDI_serviceBuilder_Office_Model_Scope_service(scope, token: token) })
		            }
		            func __safeDI_serviceBuilder_Office_Desk_Scope() -> Office.SafeDIMockScope_Service.Desk_Scope.__safeDI_Builder<any Service> {
		                .init(model: { values in __safeDI_serviceBuilder_Office_Model_Scope_(token: values.token) })
		            }
		            func __safeDI_serviceBuilder_Office_Model_Scope_(token: Token) -> Office.SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<any Service> {
		                .init(service: { scope in __safeDI_serviceBuilder_Office_Model_Scope_service(scope, token: token) })
		            }
		            _ = Office.__safeDI_Office_mock_B1E33A311A11F6C1.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Office.__safeDI_mock(serviceBuilder: serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Office(), safeDIOverrides: safeDIOverrides.office)
		        }
		        let office: Office = __safeDI_office()
		        return OfficeScreen(office: office)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [
			DifferentialValueProbe("OfficeScreen.mock().office.lobbyBuilder.instantiate(Token()).model.service"),
			DifferentialValueProbe("OfficeScreen.mock().office.lobbyBuilder.instantiate(nil).model.service"),
			DifferentialValueProbe("OfficeScreen.mock().office.desk.model.service"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_typesEveryFillAndDispatcherByTheFormTheFillReads_whenATypeIsReachedOnlyOnARouteThatBindsAnotherForm() async throws {
		let modules = Self.modules(core: [Self.officeWithWing], app: [Self.officeScreen, Self.defaultServiceReceivingTokenIfAvailable])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Office {
		    nonisolated public enum SafeDIMockScope_Service {
		        nonisolated public struct lobbyBuilder_Values {
		            public let token: Token
		        }

		        nonisolated public struct wing_Values {
		            public let token: Token
		            public let lobbyBuilder: Instantiator<Lobby>
		        }

		        nonisolated public enum Lobby_Scope {
		            nonisolated public struct model_Values {
		                public let token: Token?
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let model: (model_Values) -> SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(model: @escaping (model_Values) -> SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.model = model
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(model: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		                }
		            }
		        }

		        nonisolated public enum Wing_Scope {
		            nonisolated public struct model_Values {}

		            nonisolated public struct gauge_Values {
		                public let model: Model
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let model: (model_Values) -> SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<__safeDI_Built>
		                public let gauge: (gauge_Values) -> SafeDIMockScope_Service.Gauge_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(model: @escaping (model_Values) -> SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<__safeDI_Built>, gauge: @escaping (gauge_Values) -> SafeDIMockScope_Service.Gauge_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.model = model
		                    self.gauge = gauge
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(model: { _ in .init(__safeDI_noScope: __safeDI_builder) }, gauge: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		                }
		            }
		        }

		        nonisolated public enum Model_Scope {
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

		        nonisolated public enum Gauge_Scope {
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

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let lobbyBuilder: (lobbyBuilder_Values) -> SafeDIMockScope_Service.Lobby_Scope.__safeDI_Builder<__safeDI_Built>
		            public let wing: (wing_Values) -> SafeDIMockScope_Service.Wing_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(lobbyBuilder: @escaping (lobbyBuilder_Values) -> SafeDIMockScope_Service.Lobby_Scope.__safeDI_Builder<__safeDI_Built>, wing: @escaping (wing_Values) -> SafeDIMockScope_Service.Wing_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.lobbyBuilder = lobbyBuilder
		                self.wing = wing
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(lobbyBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) }, wing: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            token: (() -> Token)? = nil,
		            lobbyBuilder: __safeDI_Core_Lobby_MockConfiguration = .init(),
		            wing: __safeDI_Core_Wing_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                token: token,
		                lobbyBuilder: lobbyBuilder,
		                wing: wing
		            )
		        }

		        public var token: (() -> Token)? { __safeDI_storage.token }
		        public var lobbyBuilder: __safeDI_Core_Lobby_MockConfiguration { __safeDI_storage.lobbyBuilder }
		        public var wing: __safeDI_Core_Wing_MockConfiguration { __safeDI_storage.wing }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                token: (() -> Token)?,
		                lobbyBuilder: __safeDI_Core_Lobby_MockConfiguration,
		                wing: __safeDI_Core_Wing_MockConfiguration
		            ) {
		                self.token = token
		                self.lobbyBuilder = lobbyBuilder
		                self.wing = wing
		            }

		            let token: (() -> Token)?
		            let lobbyBuilder: __safeDI_Core_Lobby_MockConfiguration
		            let wing: __safeDI_Core_Wing_MockConfiguration
		        }
		    }

		    public static func mock(
		        serviceBuilder: @escaping () -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Office {
		        Office.__safeDI_mock(serviceBuilder: .init(__safeDI_noScope: serviceBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        serviceBuilder __safeDI_serviceBuilder: Office.SafeDIMockScope_Service.__safeDI_Builder<any Service>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Office {
		        let token = if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder() } else { Token() }
		        let __safeDI_serviceBuilder_lobbyBuilder = __safeDI_serviceBuilder.lobbyBuilder(SafeDIMockScope_Service.lobbyBuilder_Values(token: token))
		        func __safeDI_lobbyBuilder(token: Token?) -> Lobby {
		            let __safeDI_serviceBuilder_model = __safeDI_serviceBuilder_lobbyBuilder.model(SafeDIMockScope_Service.Lobby_Scope.model_Values(token: token))
		            func __safeDI_model() -> Model {
		                let service: any Service = __safeDI_serviceBuilder_model.service(SafeDIMockScope_Service.Model_Scope.service_Values())
		                return if let safeDIBuilder = safeDIOverrides.lobbyBuilder.model { safeDIBuilder(service) } else { Model(service: service) }
		            }
		            let model: Model = __safeDI_model()
		            return Lobby.__safeDI_init(token: token, model: model, safeDIBuilder: safeDIOverrides.lobbyBuilder.safeDIBuilder)
		        }
		        let lobbyBuilder = Instantiator<Lobby> {
		            __safeDI_lobbyBuilder(token: $0)
		        }
		        let __safeDI_serviceBuilder_wing = __safeDI_serviceBuilder.wing(SafeDIMockScope_Service.wing_Values(token: token, lobbyBuilder: lobbyBuilder))
		        func __safeDI_wing() -> Wing {
		            let __safeDI_serviceBuilder_model = __safeDI_serviceBuilder_wing.model(SafeDIMockScope_Service.Wing_Scope.model_Values())
		            func __safeDI_model() -> Model {
		                let service: any Service = __safeDI_serviceBuilder_model.service(SafeDIMockScope_Service.Model_Scope.service_Values())
		                return if let safeDIBuilder = safeDIOverrides.wing.model { safeDIBuilder(service) } else { Model(service: service) }
		            }
		            let model: Model = __safeDI_model()
		            let __safeDI_serviceBuilder_gauge = __safeDI_serviceBuilder_wing.gauge(SafeDIMockScope_Service.Wing_Scope.gauge_Values(model: model))
		            func __safeDI_gauge() -> Gauge {
		                let service: any Service = __safeDI_serviceBuilder_gauge.service(SafeDIMockScope_Service.Gauge_Scope.service_Values())
		                return if let safeDIBuilder = safeDIOverrides.wing.gauge { safeDIBuilder(service) } else { Gauge(service: service) }
		            }
		            let gauge: Gauge = __safeDI_gauge()
		            return Wing.__safeDI_init(model: model, gauge: gauge, safeDIBuilder: safeDIOverrides.wing.safeDIBuilder)
		        }
		        let wing: Wing = __safeDI_wing()
		        return Office(token: token, lobbyBuilder: lobbyBuilder, wing: wing)
		    }
		}

		extension Office {
		    public enum __safeDI_Office_mock_06FC4B2D8AF9D380 {}
		}
		#endif

		#if DEBUG
		extension Panel {
		    nonisolated public enum SafeDIMockScope_Service {
		        nonisolated public struct row_Values {}

		        nonisolated public struct service_Values {
		            public let row: Row
		        }

		        nonisolated public enum Row_Scope {
		            nonisolated public struct service_Values {
		                public let token: Token
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

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let row: (row_Values) -> SafeDIMockScope_Service.Row_Scope.__safeDI_Builder<__safeDI_Built>
		            public let service: (service_Values) -> __safeDI_Built

		            public init(row: @escaping (row_Values) -> SafeDIMockScope_Service.Row_Scope.__safeDI_Builder<__safeDI_Built>, service: @escaping (service_Values) -> __safeDI_Built) {
		                self.row = row
		                self.service = service
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(row: { _ in .init(__safeDI_noScope: __safeDI_builder) }, service: { _ in __safeDI_builder() })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            row: __safeDI_Core_Row_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                row: row
		            )
		        }

		        public var row: __safeDI_Core_Row_MockConfiguration { __safeDI_storage.row }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                row: __safeDI_Core_Row_MockConfiguration
		            ) {
		                self.row = row
		            }

		            let row: __safeDI_Core_Row_MockConfiguration
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
		        let __safeDI_serviceBuilder_row = __safeDI_serviceBuilder.row(SafeDIMockScope_Service.row_Values())
		        func __safeDI_row() -> Row {
		            let token = if let safeDIBuilder = safeDIOverrides.row.token { safeDIBuilder() } else { Token() }
		            let service: any Service = __safeDI_serviceBuilder_row.service(SafeDIMockScope_Service.Row_Scope.service_Values(token: token))
		            return Row.__safeDI_init(token: token, service: service, safeDIBuilder: safeDIOverrides.row.safeDIBuilder)
		        }
		        let row: Row = __safeDI_row()
		        let service: any Service = __safeDI_serviceBuilder.service(SafeDIMockScope_Service.service_Values(row: row))
		        return Panel(row: row, service: service)
		    }
		}

		extension Panel {
		    public enum __safeDI_Panel_mock_4401C36B70302082 {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `Lobby` is constructed within the public mock trees of module `Core`.
		nonisolated public struct __safeDI_Core_Lobby_MockConfiguration {
		    public init(
		        model: ((any Service) -> Model)? = nil,
		        _ safeDIBuilder: ((Token?, Model) -> Lobby)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            model: model,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var model: ((any Service) -> Model)? { __safeDI_storage.model }
		    /// Overrides how `Lobby` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((Token?, Model) -> Lobby)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            model: ((any Service) -> Model)?,
		            safeDIBuilder: ((Token?, Model) -> Lobby)?
		        ) {
		            self.model = model
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let model: ((any Service) -> Model)?
		        let safeDIBuilder: ((Token?, Model) -> Lobby)?
		    }
		}

		extension Lobby {
		    static func __safeDI_init(token: Token?, model: Model, safeDIBuilder: ((Token?, Model) -> Lobby)?) -> Lobby {
		        if let safeDIBuilder { safeDIBuilder(token, model) } else { Lobby(token: token, model: model) }
		    }
		}

		/// Configuration for how `Wing` is constructed within the public mock trees of module `Core`.
		nonisolated public struct __safeDI_Core_Wing_MockConfiguration {
		    public init(
		        model: ((any Service) -> Model)? = nil,
		        gauge: ((any Service) -> Gauge)? = nil,
		        _ safeDIBuilder: ((Model, Gauge) -> Wing)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            model: model,
		            gauge: gauge,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var model: ((any Service) -> Model)? { __safeDI_storage.model }
		    public var gauge: ((any Service) -> Gauge)? { __safeDI_storage.gauge }
		    /// Overrides how `Wing` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((Model, Gauge) -> Wing)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            model: ((any Service) -> Model)?,
		            gauge: ((any Service) -> Gauge)?,
		            safeDIBuilder: ((Model, Gauge) -> Wing)?
		        ) {
		            self.model = model
		            self.gauge = gauge
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let model: ((any Service) -> Model)?
		        let gauge: ((any Service) -> Gauge)?
		        let safeDIBuilder: ((Model, Gauge) -> Wing)?
		    }
		}

		extension Wing {
		    static func __safeDI_init(model: Model, gauge: Gauge, safeDIBuilder: ((Model, Gauge) -> Wing)?) -> Wing {
		        if let safeDIBuilder { safeDIBuilder(model, gauge) } else { Wing(model: model, gauge: gauge) }
		    }
		}

		/// Configuration for how `Row` is constructed within the public mock trees of module `Core`.
		nonisolated public struct __safeDI_Core_Row_MockConfiguration {
		    public init(
		        token: (() -> Token)? = nil,
		        _ safeDIBuilder: ((Token, any Service) -> Row)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            token: token,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var token: (() -> Token)? { __safeDI_storage.token }
		    /// Overrides how `Row` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((Token, any Service) -> Row)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            token: (() -> Token)?,
		            safeDIBuilder: ((Token, any Service) -> Row)?
		        ) {
		            self.token = token
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let token: (() -> Token)?
		        let safeDIBuilder: ((Token, any Service) -> Row)?
		    }
		}

		extension Row {
		    static func __safeDI_init(token: Token, service: any Service, safeDIBuilder: ((Token, any Service) -> Row)?) -> Row {
		        if let safeDIBuilder { safeDIBuilder(token, service) } else { Row(token: token, service: service) }
		    }
		}
		#endif

		"""])
		// `Gauge` is reached only beneath `Office`'s `Token`, and `Model` beneath `Lobby`'s `Token?` too: both fills, and `Wing`'s
		// dispatcher, take the `Token?` they read.
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension OfficeScreen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            office: Office.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                office: office
		            )
		        }

		        var office: Office.SafeDIOverrides { __safeDI_storage.office }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                office: Office.SafeDIOverrides
		            ) {
		                self.office = office
		            }

		            let office: Office.SafeDIOverrides
		        }
		    }

		    static func mock(
		        serviceBuilder: (() -> any Service)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> OfficeScreen {
		        func __safeDI_office() -> Office {
		            func __safeDI_serviceBuilder_Office_Model_Scope_service(_ scope: Office.SafeDIMockScope_Service.Model_Scope.service_Values, token: Token?) -> any Service {
		                let service: any Service = DefaultService(token: token)
		                return service
		            }
		            func __safeDI_serviceBuilder_Office_Gauge_Scope_service(_ scope: Office.SafeDIMockScope_Service.Gauge_Scope.service_Values, token: Token?) -> any Service {
		                let service: any Service = DefaultService(token: token)
		                return service
		            }
		            func __safeDI_serviceBuilder_Office() -> Office.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
		                .init(lobbyBuilder: { _ in __safeDI_serviceBuilder_Office_Lobby_Scope() }, wing: { values in __safeDI_serviceBuilder_Office_Wing_Scope(token: values.token) })
		            }
		            func __safeDI_serviceBuilder_Office_Lobby_Scope() -> Office.SafeDIMockScope_Service.Lobby_Scope.__safeDI_Builder<any Service> {
		                .init(model: { values in __safeDI_serviceBuilder_Office_Model_Scope(token: values.token) })
		            }
		            func __safeDI_serviceBuilder_Office_Model_Scope(token: Token?) -> Office.SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<any Service> {
		                .init(service: { scope in __safeDI_serviceBuilder_Office_Model_Scope_service(scope, token: token) })
		            }
		            func __safeDI_serviceBuilder_Office_Wing_Scope(token: Token) -> Office.SafeDIMockScope_Service.Wing_Scope.__safeDI_Builder<any Service> {
		                .init(model: { _ in __safeDI_serviceBuilder_Office_Model_Scope_(token: token) }, gauge: { _ in __safeDI_serviceBuilder_Office_Gauge_Scope(token: token) })
		            }
		            func __safeDI_serviceBuilder_Office_Model_Scope_(token: Token) -> Office.SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<any Service> {
		                .init(service: { scope in __safeDI_serviceBuilder_Office_Model_Scope_service(scope, token: token) })
		            }
		            func __safeDI_serviceBuilder_Office_Gauge_Scope(token: Token) -> Office.SafeDIMockScope_Service.Gauge_Scope.__safeDI_Builder<any Service> {
		                .init(service: { scope in __safeDI_serviceBuilder_Office_Gauge_Scope_service(scope, token: token) })
		            }
		            _ = Office.__safeDI_Office_mock_06FC4B2D8AF9D380.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Office.__safeDI_mock(serviceBuilder: serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Office(), safeDIOverrides: safeDIOverrides.office)
		        }
		        let office: Office = __safeDI_office()
		        return OfficeScreen(office: office)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [
			DifferentialValueProbe("OfficeScreen.mock().office.lobbyBuilder.instantiate(Token()).model.service"),
			DifferentialValueProbe("OfficeScreen.mock().office.wing.model.service"),
			DifferentialValueProbe("OfficeScreen.mock().office.wing.gauge.service"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsTheCallersTokenThroughAnIntermediateDispatcher_whenOneRouteBindsNoTokenAboveTheIntermediateType() async throws {
		// `Hub` builds `Model` inside `Page`, which binds `token`, and inside `Hall`, beside `Page`, where nothing does.
		// `HubScreen` hands the `token` its mock builds through `Hall`'s dispatcher to the place inside it, as inline does.
		let modules = Self.modules(core: [Self.hubWithHall], app: [Self.hubScreen, Self.defaultServiceReceivingToken])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Hub {
		    nonisolated public enum SafeDIMockScope_Service {
		        nonisolated public struct page_Values {}

		        nonisolated public struct hall_Values {
		            public let page: Page
		        }

		        nonisolated public enum Page_Scope {
		            nonisolated public struct model_Values {
		                public let token: Token
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let model: (model_Values) -> SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(model: @escaping (model_Values) -> SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.model = model
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(model: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		                }
		            }
		        }

		        nonisolated public enum Hall_Scope {
		            nonisolated public struct model_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let model: (model_Values) -> SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(model: @escaping (model_Values) -> SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.model = model
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(model: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		                }
		            }
		        }

		        nonisolated public enum Model_Scope {
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

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let page: (page_Values) -> SafeDIMockScope_Service.Page_Scope.__safeDI_Builder<__safeDI_Built>
		            public let hall: (hall_Values) -> SafeDIMockScope_Service.Hall_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(page: @escaping (page_Values) -> SafeDIMockScope_Service.Page_Scope.__safeDI_Builder<__safeDI_Built>, hall: @escaping (hall_Values) -> SafeDIMockScope_Service.Hall_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.page = page
		                self.hall = hall
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(page: { _ in .init(__safeDI_noScope: __safeDI_builder) }, hall: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            page: __safeDI_Core_Page_MockConfiguration = .init(),
		            hall: __safeDI_Core_Hall_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                page: page,
		                hall: hall
		            )
		        }

		        public var page: __safeDI_Core_Page_MockConfiguration { __safeDI_storage.page }
		        public var hall: __safeDI_Core_Hall_MockConfiguration { __safeDI_storage.hall }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                page: __safeDI_Core_Page_MockConfiguration,
		                hall: __safeDI_Core_Hall_MockConfiguration
		            ) {
		                self.page = page
		                self.hall = hall
		            }

		            let page: __safeDI_Core_Page_MockConfiguration
		            let hall: __safeDI_Core_Hall_MockConfiguration
		        }
		    }

		    public static func mock(
		        serviceBuilder: @escaping () -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Hub {
		        Hub.__safeDI_mock(serviceBuilder: .init(__safeDI_noScope: serviceBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        serviceBuilder __safeDI_serviceBuilder: Hub.SafeDIMockScope_Service.__safeDI_Builder<any Service>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Hub {
		        let __safeDI_serviceBuilder_page = __safeDI_serviceBuilder.page(SafeDIMockScope_Service.page_Values())
		        func __safeDI_page() -> Page {
		            let token = if let safeDIBuilder = safeDIOverrides.page.token { safeDIBuilder() } else { Token() }
		            let __safeDI_serviceBuilder_model = __safeDI_serviceBuilder_page.model(SafeDIMockScope_Service.Page_Scope.model_Values(token: token))
		            func __safeDI_model() -> Model {
		                let service: any Service = __safeDI_serviceBuilder_model.service(SafeDIMockScope_Service.Model_Scope.service_Values())
		                return if let safeDIBuilder = safeDIOverrides.page.model { safeDIBuilder(service) } else { Model(service: service) }
		            }
		            let model: Model = __safeDI_model()
		            return Page.__safeDI_init(token: token, model: model, safeDIBuilder: safeDIOverrides.page.safeDIBuilder)
		        }
		        let page: Page = __safeDI_page()
		        let __safeDI_serviceBuilder_hall = __safeDI_serviceBuilder.hall(SafeDIMockScope_Service.hall_Values(page: page))
		        func __safeDI_hall() -> Hall {
		            let __safeDI_serviceBuilder_model = __safeDI_serviceBuilder_hall.model(SafeDIMockScope_Service.Hall_Scope.model_Values())
		            func __safeDI_model() -> Model {
		                let service: any Service = __safeDI_serviceBuilder_model.service(SafeDIMockScope_Service.Model_Scope.service_Values())
		                return if let safeDIBuilder = safeDIOverrides.hall.model { safeDIBuilder(service) } else { Model(service: service) }
		            }
		            let model: Model = __safeDI_model()
		            return Hall.__safeDI_init(model: model, safeDIBuilder: safeDIOverrides.hall.safeDIBuilder)
		        }
		        let hall: Hall = __safeDI_hall()
		        return Hub(page: page, hall: hall)
		    }
		}

		extension Hub {
		    public enum __safeDI_Hub_mock_002BD72DF05A9136 {}
		}
		#endif

		#if DEBUG
		extension Panel {
		    nonisolated public enum SafeDIMockScope_Service {
		        nonisolated public struct row_Values {}

		        nonisolated public struct service_Values {
		            public let row: Row
		        }

		        nonisolated public enum Row_Scope {
		            nonisolated public struct service_Values {
		                public let token: Token
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

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let row: (row_Values) -> SafeDIMockScope_Service.Row_Scope.__safeDI_Builder<__safeDI_Built>
		            public let service: (service_Values) -> __safeDI_Built

		            public init(row: @escaping (row_Values) -> SafeDIMockScope_Service.Row_Scope.__safeDI_Builder<__safeDI_Built>, service: @escaping (service_Values) -> __safeDI_Built) {
		                self.row = row
		                self.service = service
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(row: { _ in .init(__safeDI_noScope: __safeDI_builder) }, service: { _ in __safeDI_builder() })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            row: __safeDI_Core_Row_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                row: row
		            )
		        }

		        public var row: __safeDI_Core_Row_MockConfiguration { __safeDI_storage.row }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                row: __safeDI_Core_Row_MockConfiguration
		            ) {
		                self.row = row
		            }

		            let row: __safeDI_Core_Row_MockConfiguration
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
		        let __safeDI_serviceBuilder_row = __safeDI_serviceBuilder.row(SafeDIMockScope_Service.row_Values())
		        func __safeDI_row() -> Row {
		            let token = if let safeDIBuilder = safeDIOverrides.row.token { safeDIBuilder() } else { Token() }
		            let service: any Service = __safeDI_serviceBuilder_row.service(SafeDIMockScope_Service.Row_Scope.service_Values(token: token))
		            return Row.__safeDI_init(token: token, service: service, safeDIBuilder: safeDIOverrides.row.safeDIBuilder)
		        }
		        let row: Row = __safeDI_row()
		        let service: any Service = __safeDI_serviceBuilder.service(SafeDIMockScope_Service.service_Values(row: row))
		        return Panel(row: row, service: service)
		    }
		}

		extension Panel {
		    public enum __safeDI_Panel_mock_4401C36B70302082 {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `Page` is constructed within the public mock trees of module `Core`.
		nonisolated public struct __safeDI_Core_Page_MockConfiguration {
		    public init(
		        token: (() -> Token)? = nil,
		        model: ((any Service) -> Model)? = nil,
		        _ safeDIBuilder: ((Token, Model) -> Page)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            token: token,
		            model: model,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var token: (() -> Token)? { __safeDI_storage.token }
		    public var model: ((any Service) -> Model)? { __safeDI_storage.model }
		    /// Overrides how `Page` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((Token, Model) -> Page)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            token: (() -> Token)?,
		            model: ((any Service) -> Model)?,
		            safeDIBuilder: ((Token, Model) -> Page)?
		        ) {
		            self.token = token
		            self.model = model
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let token: (() -> Token)?
		        let model: ((any Service) -> Model)?
		        let safeDIBuilder: ((Token, Model) -> Page)?
		    }
		}

		extension Page {
		    static func __safeDI_init(token: Token, model: Model, safeDIBuilder: ((Token, Model) -> Page)?) -> Page {
		        if let safeDIBuilder { safeDIBuilder(token, model) } else { Page(token: token, model: model) }
		    }
		}

		/// Configuration for how `Hall` is constructed within the public mock trees of module `Core`.
		nonisolated public struct __safeDI_Core_Hall_MockConfiguration {
		    public init(
		        model: ((any Service) -> Model)? = nil,
		        _ safeDIBuilder: ((Model) -> Hall)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            model: model,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var model: ((any Service) -> Model)? { __safeDI_storage.model }
		    /// Overrides how `Hall` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((Model) -> Hall)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            model: ((any Service) -> Model)?,
		            safeDIBuilder: ((Model) -> Hall)?
		        ) {
		            self.model = model
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let model: ((any Service) -> Model)?
		        let safeDIBuilder: ((Model) -> Hall)?
		    }
		}

		extension Hall {
		    static func __safeDI_init(model: Model, safeDIBuilder: ((Model) -> Hall)?) -> Hall {
		        if let safeDIBuilder { safeDIBuilder(model) } else { Hall(model: model) }
		    }
		}

		/// Configuration for how `Row` is constructed within the public mock trees of module `Core`.
		nonisolated public struct __safeDI_Core_Row_MockConfiguration {
		    public init(
		        token: (() -> Token)? = nil,
		        _ safeDIBuilder: ((Token, any Service) -> Row)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            token: token,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var token: (() -> Token)? { __safeDI_storage.token }
		    /// Overrides how `Row` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((Token, any Service) -> Row)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            token: (() -> Token)?,
		            safeDIBuilder: ((Token, any Service) -> Row)?
		        ) {
		            self.token = token
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let token: (() -> Token)?
		        let safeDIBuilder: ((Token, any Service) -> Row)?
		    }
		}

		extension Row {
		    static func __safeDI_init(token: Token, service: any Service, safeDIBuilder: ((Token, any Service) -> Row)?) -> Row {
		        if let safeDIBuilder { safeDIBuilder(token, service) } else { Row(token: token, service: service) }
		    }
		}
		#endif

		"""])
		// Nothing above `Hall` binds `token`, so the root hands its dispatcher `nil`, which it hands on to `Model`'s.
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension HubScreen {
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
		        serviceBuilder: (() -> any Service)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> HubScreen {
		        let token = if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder() } else { Token() }
		        func __safeDI_hub() -> Hub {
		            func __safeDI_serviceBuilder_Hub(token: Token) -> Hub.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
		                .init(page: { _ in __safeDI_serviceBuilder_Hub_Page_Scope() }, hall: { _ in __safeDI_serviceBuilder_Hub_Hall_Scope(token: token) })
		            }
		            func __safeDI_serviceBuilder_Hub_Page_Scope() -> Hub.SafeDIMockScope_Service.Page_Scope.__safeDI_Builder<any Service> {
		                .init(model: { values in __safeDI_serviceBuilder_Hub_Model_Scope(token: values.token) })
		            }
		            func __safeDI_serviceBuilder_Hub_Model_Scope(token: Token) -> Hub.SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<any Service> {
		                .init(service: { _ in
		                    let service: any Service = DefaultService(token: token)
		                    return service
		                })
		            }
		            func __safeDI_serviceBuilder_Hub_Hall_Scope(token: Token) -> Hub.SafeDIMockScope_Service.Hall_Scope.__safeDI_Builder<any Service> {
		                .init(model: { _ in __safeDI_serviceBuilder_Hub_Model_Scope(token: token) })
		            }
		            _ = Hub.__safeDI_Hub_mock_002BD72DF05A9136.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Hub.__safeDI_mock(serviceBuilder: serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Hub(token: token), safeDIOverrides: safeDIOverrides.hub)
		        }
		        let hub: Hub = __safeDI_hub()
		        return HubScreen(hub: hub)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("HubScreen.mock()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsTwinsHiddenReceiveError_whenATypeBindsTheLabelAsAnotherTypeBeneathOneThatBindsIt() async {
		// `Model` binds `token: Token` and builds `Bench`, which binds `token: Badge` before its `service`. `DefaultService`
		// receives `token: Token`, which `Bench`'s `token` hides at the place inside `Bench`. The twin reports the receive
		// hidden, so the calling mock reports the same.
		await expectTwinsError(core: [Self.hubWithBench], app: [Self.hubScreen, Self.defaultServiceReceivingToken]) { fixtures in
			"""
			\(fixtures["App"]!["DefaultService.swift"]):10:5: error: @Received property `token: Token` is hidden in chain: HubScreen -> Hub -> Model -> Bench -> DefaultService. `Bench` declares `token: Badge` with the same label, so the types below `Bench` receive `token: Badge` instead. Give `token: Badge` on `Bench` a different label to fix.
			\(fixtures["Core"]!["Badge.swift"]):15:5: note: `token: Badge` is declared here
			"""
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsEachRoutesFillItsNearestTokenBesideTheForwardedValue_whenAnErasedInstantiatorIsThePlace() async throws {
		// `Hub` builds `Model`, whose `part` forwards a name, inside `Page`, which binds `token`, and beside it, where nothing
		// does. `HubScreen` fills the route through `Page` with `Page`'s `token`, and the other with the `token` its mock
		// builds, each fill taking the name its place forwards.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(core: [Self.hubWithErasedPart], app: [Self.hubScreen, Self.defaultPartReceivingToken]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Hub {
		    nonisolated public enum SafeDIMockScope_DefaultPart_Part {
		        nonisolated public struct page_Values {}

		        nonisolated public struct model_Values {
		            public let page: Page
		        }

		        nonisolated public enum Page_Scope {
		            nonisolated public struct model_Values {
		                public let token: Token
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let model: (model_Values) -> SafeDIMockScope_DefaultPart_Part.Model_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(model: @escaping (model_Values) -> SafeDIMockScope_DefaultPart_Part.Model_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.model = model
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<String, __safeDI_Built>.Builder) {
		                    self.init(model: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		                }
		            }
		        }

		        nonisolated public enum Model_Scope {
		            nonisolated public struct part_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let part: (part_Values) -> ErasedInstantiator<String, __safeDI_Built>.Builder

		                public init(part: @escaping (part_Values) -> ErasedInstantiator<String, __safeDI_Built>.Builder) {
		                    self.part = part
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<String, __safeDI_Built>.Builder) {
		                    self.init(part: { _ in __safeDI_builder })
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let page: (page_Values) -> SafeDIMockScope_DefaultPart_Part.Page_Scope.__safeDI_Builder<__safeDI_Built>
		            public let model: (model_Values) -> SafeDIMockScope_DefaultPart_Part.Model_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(page: @escaping (page_Values) -> SafeDIMockScope_DefaultPart_Part.Page_Scope.__safeDI_Builder<__safeDI_Built>, model: @escaping (model_Values) -> SafeDIMockScope_DefaultPart_Part.Model_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.page = page
		                self.model = model
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<String, __safeDI_Built>.Builder) {
		                self.init(page: { _ in .init(__safeDI_noScope: __safeDI_builder) }, model: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            page: __safeDI_Core_Page_MockConfiguration = .init(),
		            model: ((ErasedInstantiator<String, any Part>) -> Model)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                page: page,
		                model: model
		            )
		        }

		        public var page: __safeDI_Core_Page_MockConfiguration { __safeDI_storage.page }
		        public var model: ((ErasedInstantiator<String, any Part>) -> Model)? { __safeDI_storage.model }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                page: __safeDI_Core_Page_MockConfiguration,
		                model: ((ErasedInstantiator<String, any Part>) -> Model)?
		            ) {
		                self.page = page
		                self.model = model
		            }

		            let page: __safeDI_Core_Page_MockConfiguration
		            let model: ((ErasedInstantiator<String, any Part>) -> Model)?
		        }
		    }

		    public static func mock(
		        defaultPart_PartBuilder: @escaping ErasedInstantiator<String, any Part>.Builder,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Hub {
		        Hub.__safeDI_mock(defaultPart_PartBuilder: .init(__safeDI_noScope: defaultPart_PartBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        defaultPart_PartBuilder __safeDI_defaultPart_PartBuilder: Hub.SafeDIMockScope_DefaultPart_Part.__safeDI_Builder<any Part>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Hub {
		        let __safeDI_defaultPart_PartBuilder_page = __safeDI_defaultPart_PartBuilder.page(SafeDIMockScope_DefaultPart_Part.page_Values())
		        func __safeDI_page() -> Page {
		            let token = if let safeDIBuilder = safeDIOverrides.page.token { safeDIBuilder() } else { Token() }
		            let __safeDI_defaultPart_PartBuilder_model = __safeDI_defaultPart_PartBuilder_page.model(SafeDIMockScope_DefaultPart_Part.Page_Scope.model_Values(token: token))
		            func __safeDI_model() -> Model {
		                let part = ErasedInstantiator<String, any Part>(__safeDI_defaultPart_PartBuilder_model.part(SafeDIMockScope_DefaultPart_Part.Model_Scope.part_Values()))
		                return if let safeDIBuilder = safeDIOverrides.page.model { safeDIBuilder(part) } else { Model(part: part) }
		            }
		            let model: Model = __safeDI_model()
		            return Page.__safeDI_init(token: token, model: model, safeDIBuilder: safeDIOverrides.page.safeDIBuilder)
		        }
		        let page: Page = __safeDI_page()
		        let __safeDI_defaultPart_PartBuilder_model = __safeDI_defaultPart_PartBuilder.model(SafeDIMockScope_DefaultPart_Part.model_Values(page: page))
		        func __safeDI_model() -> Model {
		            let part = ErasedInstantiator<String, any Part>(__safeDI_defaultPart_PartBuilder_model.part(SafeDIMockScope_DefaultPart_Part.Model_Scope.part_Values()))
		            return if let safeDIBuilder = safeDIOverrides.model { safeDIBuilder(part) } else { Model(part: part) }
		        }
		        let model: Model = __safeDI_model()
		        return Hub(page: page, model: model)
		    }
		}

		extension Hub {
		    public enum __safeDI_Hub_mock_2D12229128E94215 {}
		}
		#endif

		#if DEBUG
		extension Panel {
		    nonisolated public enum SafeDIMockScope_Service {
		        nonisolated public struct row_Values {}

		        nonisolated public struct service_Values {
		            public let row: Row
		        }

		        nonisolated public enum Row_Scope {
		            nonisolated public struct service_Values {
		                public let token: Token
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

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let row: (row_Values) -> SafeDIMockScope_Service.Row_Scope.__safeDI_Builder<__safeDI_Built>
		            public let service: (service_Values) -> __safeDI_Built

		            public init(row: @escaping (row_Values) -> SafeDIMockScope_Service.Row_Scope.__safeDI_Builder<__safeDI_Built>, service: @escaping (service_Values) -> __safeDI_Built) {
		                self.row = row
		                self.service = service
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(row: { _ in .init(__safeDI_noScope: __safeDI_builder) }, service: { _ in __safeDI_builder() })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            row: __safeDI_Core_Row_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                row: row
		            )
		        }

		        public var row: __safeDI_Core_Row_MockConfiguration { __safeDI_storage.row }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                row: __safeDI_Core_Row_MockConfiguration
		            ) {
		                self.row = row
		            }

		            let row: __safeDI_Core_Row_MockConfiguration
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
		        let __safeDI_serviceBuilder_row = __safeDI_serviceBuilder.row(SafeDIMockScope_Service.row_Values())
		        func __safeDI_row() -> Row {
		            let token = if let safeDIBuilder = safeDIOverrides.row.token { safeDIBuilder() } else { Token() }
		            let service: any Service = __safeDI_serviceBuilder_row.service(SafeDIMockScope_Service.Row_Scope.service_Values(token: token))
		            return Row.__safeDI_init(token: token, service: service, safeDIBuilder: safeDIOverrides.row.safeDIBuilder)
		        }
		        let row: Row = __safeDI_row()
		        let service: any Service = __safeDI_serviceBuilder.service(SafeDIMockScope_Service.service_Values(row: row))
		        return Panel(row: row, service: service)
		    }
		}

		extension Panel {
		    public enum __safeDI_Panel_mock_4401C36B70302082 {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `Page` is constructed within the public mock trees of module `Core`.
		nonisolated public struct __safeDI_Core_Page_MockConfiguration {
		    public init(
		        token: (() -> Token)? = nil,
		        model: ((ErasedInstantiator<String, any Part>) -> Model)? = nil,
		        _ safeDIBuilder: ((Token, Model) -> Page)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            token: token,
		            model: model,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var token: (() -> Token)? { __safeDI_storage.token }
		    public var model: ((ErasedInstantiator<String, any Part>) -> Model)? { __safeDI_storage.model }
		    /// Overrides how `Page` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((Token, Model) -> Page)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            token: (() -> Token)?,
		            model: ((ErasedInstantiator<String, any Part>) -> Model)?,
		            safeDIBuilder: ((Token, Model) -> Page)?
		        ) {
		            self.token = token
		            self.model = model
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let token: (() -> Token)?
		        let model: ((ErasedInstantiator<String, any Part>) -> Model)?
		        let safeDIBuilder: ((Token, Model) -> Page)?
		    }
		}

		extension Page {
		    static func __safeDI_init(token: Token, model: Model, safeDIBuilder: ((Token, Model) -> Page)?) -> Page {
		        if let safeDIBuilder { safeDIBuilder(token, model) } else { Page(token: token, model: model) }
		    }
		}

		/// Configuration for how `Row` is constructed within the public mock trees of module `Core`.
		nonisolated public struct __safeDI_Core_Row_MockConfiguration {
		    public init(
		        token: (() -> Token)? = nil,
		        _ safeDIBuilder: ((Token, any Service) -> Row)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            token: token,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var token: (() -> Token)? { __safeDI_storage.token }
		    /// Overrides how `Row` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((Token, any Service) -> Row)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            token: (() -> Token)?,
		            safeDIBuilder: ((Token, any Service) -> Row)?
		        ) {
		            self.token = token
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let token: (() -> Token)?
		        let safeDIBuilder: ((Token, any Service) -> Row)?
		    }
		}

		extension Row {
		    static func __safeDI_init(token: Token, service: any Service, safeDIBuilder: ((Token, any Service) -> Row)?) -> Row {
		        if let safeDIBuilder { safeDIBuilder(token, service) } else { Row(token: token, service: service) }
		    }
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
		extension HubScreen {
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
		        defaultPart_PartBuilder: ErasedInstantiator<String, any Part>.Builder? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> HubScreen {
		        let token = if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder() } else { Token() }
		        func __safeDI_hub() -> Hub {
		            func __safeDI_defaultPart_PartBuilder_Hub_Model_Scope_part(token: Token) -> ErasedInstantiator<String, any Part>.Builder {
		                func __safeDI_part(name: String) -> DefaultPart {
		                    DefaultPart(name: name, token: token)
		                }
		                return { forwarded in __safeDI_part(name: forwarded) }
		            }
		            func __safeDI_defaultPart_PartBuilder_Hub(token: Token) -> Hub.SafeDIMockScope_DefaultPart_Part.__safeDI_Builder<any Part> {
		                .init(page: { _ in __safeDI_defaultPart_PartBuilder_Hub_Page_Scope() }, model: { _ in __safeDI_defaultPart_PartBuilder_Hub_Model_Scope(token: token) })
		            }
		            func __safeDI_defaultPart_PartBuilder_Hub_Page_Scope() -> Hub.SafeDIMockScope_DefaultPart_Part.Page_Scope.__safeDI_Builder<any Part> {
		                .init(model: { values in __safeDI_defaultPart_PartBuilder_Hub_Model_Scope(token: values.token) })
		            }
		            func __safeDI_defaultPart_PartBuilder_Hub_Model_Scope(token: Token) -> Hub.SafeDIMockScope_DefaultPart_Part.Model_Scope.__safeDI_Builder<any Part> {
		                .init(part: { _ in __safeDI_defaultPart_PartBuilder_Hub_Model_Scope_part(token: token) })
		            }
		            _ = Hub.__safeDI_Hub_mock_2D12229128E94215.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Hub.__safeDI_mock(defaultPart_PartBuilder: defaultPart_PartBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_defaultPart_PartBuilder_Hub(token: token), safeDIOverrides: safeDIOverrides.hub)
		        }
		        let hub: Hub = __safeDI_hub()
		        return HubScreen(hub: hub)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsTwinsHiddenReceiveError_whenTypeThatBuildsThePlaceBindsTheLabelAfterIt() async {
		// `Office` binds `token` and builds `Model` beside `Desk` and inside it; `Desk` binds `token: Stamp` after its `model`.
		// `DefaultService` receives `token: Token`, which `Desk`'s `token` hides at the place inside `Desk`. The twin reports
		// the receive hidden, so the calling mock reports the same.
		await expectTwinsError(core: [Self.officeWithDesk(laterLabel: "token")], app: [Self.officeScreen, Self.defaultServiceReceivingToken]) { fixtures in
			"""
			\(fixtures["App"]!["DefaultService.swift"]):10:5: error: @Received property `token: Token` is hidden in chain: OfficeScreen -> Office -> Desk -> Model -> DefaultService. `Desk` declares `token: Stamp` with the same label, so the types below `Desk` receive `token: Stamp` instead. Give `token: Stamp` on `Desk` a different label to fix.
			\(fixtures["Core"]!["Model.swift"]):29:5: note: `token: Stamp` is declared here
			"""
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsTwinsHiddenReceiveError_whenTypeThatBuildsThePlaceBindsTheLabelAsAnotherTypeBeforeIt() async {
		// `Office` binds `token` and builds `Model` beside `Bench` and inside it; `Bench` binds `token: Badge` before its
		// `model`. `DefaultService` receives `token: Token`, which `Bench`'s `token` hides at the place inside `Bench`. The
		// twin reports the receive hidden, so the calling mock reports the same.
		await expectTwinsError(core: [Self.officeWithBench], app: [Self.officeScreen, Self.defaultServiceReceivingToken]) { fixtures in
			"""
			\(fixtures["App"]!["DefaultService.swift"]):10:5: error: @Received property `token: Token` is hidden in chain: OfficeScreen -> Office -> Bench -> Model -> DefaultService. `Bench` declares `token: Badge` with the same label, so the types below `Bench` receive `token: Badge` instead. Give `token: Badge` on `Bench` a different label to fix.
			\(fixtures["Core"]!["Model.swift"]):24:5: note: `token: Badge` is declared here
			"""
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesAnotherGuard_whenOnlyWhetherATypeBindsTheLabelAfterThePlaceDiffers() async throws {
		// The enums are alike but for the label `Desk` binds after `model`, which hides a farther value of that label from a
		// fill of the place inside `Desk`, and so decides whether a caller's fill that reads it is accepted.
		var guardTypeNames = [String]()
		for laterLabel in ["token", "stamp"] {
			let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(core: [Self.officeWithDesk(laterLabel: laterLabel)], app: [Self.officeScreen, Self.defaultService]), integration: .moduleInfo, filesToDelete: &filesToDelete)
			let coreFile = try #require(output.modules["Core"]?.generatedFiles["Core.swift"])
			guardTypeNames += coreFile.components(separatedBy: "\n").filter { $0.hasPrefix("    public enum __safeDI_Office_mock_") }
		}
		#expect(guardTypeNames.count == 2)
		#expect(Set(guardTypeNames).count == 2)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_marksTheCaseThatHoldsItsOwnTypesEnumIndirect_whenAPublicMocksTreeBuildsATypeThatOpensItself() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(core: [Self.hubOpeningNodes], app: [Self.hubScreen, Self.defaultServiceReceivingIdAndToken]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Hub {
		    nonisolated public enum SafeDIMockScope_Service {
		        nonisolated public struct node_Values {
		            public let token: Token
		        }

		        nonisolated public enum Node_Scope {
		            nonisolated public struct next_Values {
		                public let id: Int
		            }

		            nonisolated public struct service_Values {
		                public let id: Int
		                public let next: Instantiator<Node>
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let next: (next_Values) -> SafeDIMockScope_Service.Node_Scope.__safeDI_Builder<__safeDI_Built>
		                public let service: (service_Values) -> __safeDI_Built

		                public init(next: @escaping (next_Values) -> SafeDIMockScope_Service.Node_Scope.__safeDI_Builder<__safeDI_Built>, service: @escaping (service_Values) -> __safeDI_Built) {
		                    self.next = next
		                    self.service = service
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(next: { _ in .init(__safeDI_noScope: __safeDI_builder) }, service: { _ in __safeDI_builder() })
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let node: (node_Values) -> SafeDIMockScope_Service.Node_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(node: @escaping (node_Values) -> SafeDIMockScope_Service.Node_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.node = node
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(node: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            token: (() -> Token)? = nil,
		            node: __safeDI_Core_Node_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                token: token,
		                node: node
		            )
		        }

		        public var token: (() -> Token)? { __safeDI_storage.token }
		        public var node: __safeDI_Core_Node_MockConfiguration { __safeDI_storage.node }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                token: (() -> Token)?,
		                node: __safeDI_Core_Node_MockConfiguration
		            ) {
		                self.token = token
		                self.node = node
		            }

		            let token: (() -> Token)?
		            let node: __safeDI_Core_Node_MockConfiguration
		        }
		    }

		    public static func mock(
		        serviceBuilder: @escaping () -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Hub {
		        Hub.__safeDI_mock(serviceBuilder: .init(__safeDI_noScope: serviceBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        serviceBuilder __safeDI_serviceBuilder: Hub.SafeDIMockScope_Service.__safeDI_Builder<any Service>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Hub {
		        let token = if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder() } else { Token() }
		        let __safeDI_serviceBuilder_node = __safeDI_serviceBuilder.node(SafeDIMockScope_Service.node_Values(token: token))
		        func __safeDI_node(id: Int) -> Node {
		            let __safeDI_serviceBuilder_next = __safeDI_serviceBuilder_node.next(SafeDIMockScope_Service.Node_Scope.next_Values(id: id))
		            func __safeDI_next(id: Int) -> Node {
		                let next = Instantiator<Node> {
		                    __safeDI_next(id: $0)
		                }
		                let service: any Service = __safeDI_serviceBuilder_next.service(SafeDIMockScope_Service.Node_Scope.service_Values(id: id, next: next))
		                return Node.__safeDI_init(id: id, next: next, service: service, safeDIBuilder: safeDIOverrides.node.safeDIBuilder)
		            }
		            let next = Instantiator<Node> {
		                __safeDI_next(id: $0)
		            }
		            let service: any Service = __safeDI_serviceBuilder_node.service(SafeDIMockScope_Service.Node_Scope.service_Values(id: id, next: next))
		            return Node.__safeDI_init(id: id, next: next, service: service, safeDIBuilder: safeDIOverrides.node.safeDIBuilder)
		        }
		        let node = Instantiator<Node> {
		            __safeDI_node(id: $0)
		        }
		        return Hub(token: token, node: node)
		    }
		}

		extension Hub {
		    public enum __safeDI_Hub_mock_84C653EDD7BD3292 {}
		}
		#endif

		#if DEBUG
		extension Panel {
		    nonisolated public enum SafeDIMockScope_Service {
		        nonisolated public struct row_Values {}

		        nonisolated public struct service_Values {
		            public let row: Row
		        }

		        nonisolated public enum Row_Scope {
		            nonisolated public struct service_Values {
		                public let token: Token
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

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let row: (row_Values) -> SafeDIMockScope_Service.Row_Scope.__safeDI_Builder<__safeDI_Built>
		            public let service: (service_Values) -> __safeDI_Built

		            public init(row: @escaping (row_Values) -> SafeDIMockScope_Service.Row_Scope.__safeDI_Builder<__safeDI_Built>, service: @escaping (service_Values) -> __safeDI_Built) {
		                self.row = row
		                self.service = service
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(row: { _ in .init(__safeDI_noScope: __safeDI_builder) }, service: { _ in __safeDI_builder() })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            row: __safeDI_Core_Row_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                row: row
		            )
		        }

		        public var row: __safeDI_Core_Row_MockConfiguration { __safeDI_storage.row }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                row: __safeDI_Core_Row_MockConfiguration
		            ) {
		                self.row = row
		            }

		            let row: __safeDI_Core_Row_MockConfiguration
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
		        let __safeDI_serviceBuilder_row = __safeDI_serviceBuilder.row(SafeDIMockScope_Service.row_Values())
		        func __safeDI_row() -> Row {
		            let token = if let safeDIBuilder = safeDIOverrides.row.token { safeDIBuilder() } else { Token() }
		            let service: any Service = __safeDI_serviceBuilder_row.service(SafeDIMockScope_Service.Row_Scope.service_Values(token: token))
		            return Row.__safeDI_init(token: token, service: service, safeDIBuilder: safeDIOverrides.row.safeDIBuilder)
		        }
		        let row: Row = __safeDI_row()
		        let service: any Service = __safeDI_serviceBuilder.service(SafeDIMockScope_Service.service_Values(row: row))
		        return Panel(row: row, service: service)
		    }
		}

		extension Panel {
		    public enum __safeDI_Panel_mock_4401C36B70302082 {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `Node` is constructed within the public mock trees of module `Core`.
		nonisolated public struct __safeDI_Core_Node_MockConfiguration {
		    public init(
		        _ safeDIBuilder: ((Int, Instantiator<Node>, any Service) -> Node)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    /// Overrides how `Node` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((Int, Instantiator<Node>, any Service) -> Node)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            safeDIBuilder: ((Int, Instantiator<Node>, any Service) -> Node)?
		        ) {
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let safeDIBuilder: ((Int, Instantiator<Node>, any Service) -> Node)?
		    }
		}

		extension Node {
		    static func __safeDI_init(id: Int, next: Instantiator<Node>, service: any Service, safeDIBuilder: ((Int, Instantiator<Node>, any Service) -> Node)?) -> Node {
		        if let safeDIBuilder { safeDIBuilder(id, next, service) } else { Node(id: id, next: next, service: service) }
		    }
		}

		/// Configuration for how `Row` is constructed within the public mock trees of module `Core`.
		nonisolated public struct __safeDI_Core_Row_MockConfiguration {
		    public init(
		        token: (() -> Token)? = nil,
		        _ safeDIBuilder: ((Token, any Service) -> Row)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            token: token,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var token: (() -> Token)? { __safeDI_storage.token }
		    /// Overrides how `Row` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((Token, any Service) -> Row)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            token: (() -> Token)?,
		            safeDIBuilder: ((Token, any Service) -> Row)?
		        ) {
		            self.token = token
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let token: (() -> Token)?
		        let safeDIBuilder: ((Token, any Service) -> Row)?
		    }
		}

		extension Row {
		    static func __safeDI_init(token: Token, service: any Service, safeDIBuilder: ((Token, any Service) -> Row)?) -> Row {
		        if let safeDIBuilder { safeDIBuilder(token, service) } else { Row(token: token, service: service) }
		    }
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
		extension HubScreen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            hub: Hub.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                hub: hub
		            )
		        }

		        var hub: Hub.SafeDIOverrides { __safeDI_storage.hub }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                hub: Hub.SafeDIOverrides
		            ) {
		                self.hub = hub
		            }

		            let hub: Hub.SafeDIOverrides
		        }
		    }

		    static func mock(
		        serviceBuilder: (() -> any Service)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> HubScreen {
		        func __safeDI_hub() -> Hub {
		            func __safeDI_serviceBuilder_Hub() -> Hub.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
		                .init(node: { values in __safeDI_serviceBuilder_Hub_Node_Scope(token: values.token) })
		            }
		            func __safeDI_serviceBuilder_Hub_Node_Scope(token: Token) -> Hub.SafeDIMockScope_Service.Node_Scope.__safeDI_Builder<any Service> {
		                .init(
		                    next: { _ in __safeDI_serviceBuilder_Hub_Node_Scope(token: token) },
		                    service: { scope in
		                        let id = scope.id
		                        let service: any Service = DefaultService(id: id, token: token)
		                        return service
		                    }
		                )
		            }
		            _ = Hub.__safeDI_Hub_mock_84C653EDD7BD3292.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Hub.__safeDI_mock(serviceBuilder: serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Hub(), safeDIOverrides: safeDIOverrides.hub)
		        }
		        let hub: Hub = __safeDI_hub()
		        return HubScreen(hub: hub)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsEveryRouteWithOneFillHandingCalledMocksScope_whenPublicCallersFillHoldsAPlaceItsCallerFillsOnTwoRoutes() async throws {
		let modules = Self.modules(core: [Self.hub], mid: [Self.defaultServiceInstantiatingGizmo, Self.boardCallingHub], app: [Self.boardScreen])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		// `Hub`'s case for `Model`'s `service` stands for two places, and the fill of each holds a place of `Board`'s own,
		// nested by type in `Board`'s case for the builder it fills, `hub_serviceBuilder`, which holds the scope `Hub`'s mock
		// handed the fill: one fill builds both places, each handing on its own route's scope.
		#expect(output.modules["Mid"]?.generatedFiles == ["Mid.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Board {
		    nonisolated public enum SafeDIMockScope_Gizmo {
		        nonisolated public struct hub_serviceBuilder_Values {}

		        nonisolated public enum DefaultService_Scope {
		            nonisolated public struct gizmo_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let gizmo: (gizmo_Values) -> __safeDI_Built

		                public init(gizmo: @escaping (gizmo_Values) -> __safeDI_Built) {
		                    self.gizmo = gizmo
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(gizmo: { _ in __safeDI_builder() })
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let hub_serviceBuilder: (hub_serviceBuilder_Values) -> Hub.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gizmo.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(hub_serviceBuilder: @escaping (hub_serviceBuilder_Values) -> Hub.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gizmo.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.hub_serviceBuilder = hub_serviceBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(hub_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            hub: Hub.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                hub: hub
		            )
		        }

		        public var hub: Hub.SafeDIOverrides { __safeDI_storage.hub }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                hub: Hub.SafeDIOverrides
		            ) {
		                self.hub = hub
		            }

		            let hub: Hub.SafeDIOverrides
		        }
		    }

		    public static func mock(
		        gizmoBuilder: @escaping () -> any Gizmo,
		        serviceBuilder: (() -> any Service)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Board {
		        Board.__safeDI_mock(gizmoBuilder: .init(__safeDI_noScope: gizmoBuilder), serviceBuilder: serviceBuilder, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        gizmoBuilder __safeDI_gizmoBuilder: Board.SafeDIMockScope_Gizmo.__safeDI_Builder<any Gizmo>,
		        serviceBuilder __safeDI_serviceBuilder: (() -> any Service)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Board {
		        let __safeDI_gizmoBuilder_hub_serviceBuilder = __safeDI_gizmoBuilder.hub_serviceBuilder(SafeDIMockScope_Gizmo.hub_serviceBuilder_Values())
		        func __safeDI_hub() -> Hub {
		            func __safeDI_serviceBuilder_Hub_Model_Scope_service(_ scope: Hub.SafeDIMockScope_Service.Model_Scope.service_Values, __safeDI_hub_serviceBuilder: SafeDIMockScope_Gizmo.DefaultService_Scope.__safeDI_Builder<any Gizmo>) -> any Service {
		                func __safeDI_service() -> DefaultService {
		                    let gizmo: any Gizmo = __safeDI_hub_serviceBuilder.gizmo(SafeDIMockScope_Gizmo.DefaultService_Scope.gizmo_Values())
		                    return DefaultService(gizmo: gizmo)
		                }
		                let service: any Service = __safeDI_service()
		                return service
		            }
		            func __safeDI_serviceBuilder_Hub(up: Hub.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gizmo.DefaultService_Scope.__safeDI_Builder<any Gizmo>>) -> Hub.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
		                .init(page: { values in __safeDI_serviceBuilder_Hub_Page_Scope(up: up.page(values)) }, model: { values in __safeDI_serviceBuilder_Hub_Model_Scope(up: up.model(values)) })
		            }
		            func __safeDI_serviceBuilder_Hub_Page_Scope(up: Hub.SafeDIMockScope_Service.Page_Scope.__safeDI_Builder<SafeDIMockScope_Gizmo.DefaultService_Scope.__safeDI_Builder<any Gizmo>>) -> Hub.SafeDIMockScope_Service.Page_Scope.__safeDI_Builder<any Service> {
		                .init(model: { values in __safeDI_serviceBuilder_Hub_Model_Scope(up: up.model(values)) })
		            }
		            func __safeDI_serviceBuilder_Hub_Model_Scope(up: Hub.SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<SafeDIMockScope_Gizmo.DefaultService_Scope.__safeDI_Builder<any Gizmo>>) -> Hub.SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<any Service> {
		                .init(service: { scope in __safeDI_serviceBuilder_Hub_Model_Scope_service(scope, __safeDI_hub_serviceBuilder: up.service(scope)) })
		            }
		            _ = Hub.__safeDI_Hub_mock_CB4845364B55B503.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Hub.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Hub(up: __safeDI_gizmoBuilder_hub_serviceBuilder), safeDIOverrides: safeDIOverrides.hub)
		        }
		        let hub: Hub = __safeDI_hub()
		        return Board(hub: hub)
		    }
		}

		extension Board {
		    public enum __safeDI_Board_mock_1E108321181DF0B5 {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
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
		extension BoardScreen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            board: Board.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                board: board
		            )
		        }

		        var board: Board.SafeDIOverrides { __safeDI_storage.board }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                board: Board.SafeDIOverrides
		            ) {
		                self.board = board
		            }

		            let board: Board.SafeDIOverrides
		        }
		    }

		    static func mock(
		        gizmoBuilder: @escaping () -> any Gizmo,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> BoardScreen {
		        let __safeDI_gizmoBuilder = gizmoBuilder
		        func __safeDI_board() -> Board {
		            _ = Board.__safeDI_Board_mock_1E108321181DF0B5.self // If this line does not compile, compile the code SafeDI generates for module Mid into Mid: under Bazel, add Mid’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            let gizmoBuilder: () -> any Gizmo = __safeDI_gizmoBuilder
		            return Board.__safeDI_mock(gizmoBuilder: .init(__safeDI_noScope: gizmoBuilder), safeDIOverrides: safeDIOverrides.board)
		        }
		        let board: Board = __safeDI_board()
		        return BoardScreen(board: board)
		    }
		}
		#endif
		"""])
	}

	// MARK: Tests – each tier names its builders apart from its own parameters and wider ones only

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsPublicTiersBuilderLabelAndEnum_whenPackageParameterTakesBuildersLabel() async throws {
		// `Badge`, a `package` type in `Panel`'s mock tree, receives `serviceBuilder` only if available, so only the mock's
		// `package` tier takes it. The `public` tier names its builder `serviceBuilder` over `SafeDIMockScope_Service`, as it
		// would without `Badge`; the `package` tier names the same builder apart from its parameter. Neither caller can
		// construct `Panel`, whose initializer is `internal`: `Mid`, in `Panel`'s package, calls the `package` tier, and
		// `App`, in another package, the `public` one.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "pkg", swiftFileContent: [Self.panelBesideBadgeReceivingServiceBuilder]),
				ModuleFixture(name: "Mid", packageName: "pkg", swiftFileContent: [Self.screen], dependencies: ["Core"]),
				ModuleFixture(name: "App", packageName: "app", swiftFileContent: [Self.screen], dependencies: ["Core"]),
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
		            package let serviceBuilder: Thing?
		            package let badge: Badge
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
		                badge: nil
		            )
		        }

		        package init(
		            badge: ((Thing?) -> Badge)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                badge: badge
		            )
		        }

		        package var badge: ((Thing?) -> Badge)? { __safeDI_storage.badge }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                badge: ((Thing?) -> Badge)?
		            ) {
		                self.badge = badge
		            }

		            let badge: ((Thing?) -> Badge)?
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
		        let badge = if let safeDIBuilder = safeDIOverrides.badge { safeDIBuilder(serviceBuilder) } else { Badge(serviceBuilder: serviceBuilder) }
		        let service: any Service = __safeDI_serviceBuilder.service(SafeDIMockScope_Service.service_Values(serviceBuilder: serviceBuilder, badge: badge))
		        return Panel(service: service, badge: badge)
		    }
		}

		extension Panel {
		    public enum __safeDI_Panel_mock_68173143F8AFF57A {}
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
		        func __safeDI_panel() -> Panel {
		            _ = Panel.__safeDI_Panel_mock_68173143F8AFF57A.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
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
		        serviceBuilder: @escaping () -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let __safeDI_serviceBuilder = serviceBuilder
		        func __safeDI_panel() -> Panel {
		            _ = Panel.__safeDI_Panel_mock_68173143F8AFF57A.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            let serviceBuilder: () -> any Service = __safeDI_serviceBuilder
		            return Panel.__safeDI_mock(serviceBuilder: .init(__safeDI_noScope: serviceBuilder), safeDIOverrides: safeDIOverrides.panel)
		        }
		        let panel: Panel = __safeDI_panel()
		        return Screen(panel: panel)
		    }
		}
		#endif
		"""])
	}

	// MARK: Private

	/// `Panel`, whose public mock's tree builds `service`, a hole, and `badge`, whose `package` type receives
	/// `serviceBuilder: Thing?` only if available.
	private static let panelBesideBadgeReceivingServiceBuilder = """
	import SafeDI

	public protocol Service: Sendable {}

	package struct Thing {}

	@Instantiable
	package struct Badge: Instantiable {
	    package init(serviceBuilder: Thing?) {
	        self.serviceBuilder = serviceBuilder
	    }

	    @Received(onlyIfAvailable: true) let serviceBuilder: Thing?
	}

	@Instantiable(generateMock: .public)
	public struct Panel: Instantiable {
	    init(service: any Service, badge: Badge) {
	        self.service = service
	        self.badge = badge
	    }

	    @Instantiated let service: any Service
	    @Instantiated let badge: Badge
	}
	"""

	private var filesToDelete: [URL]

	/// Expects `App`'s calling mock and its production twin to report `diagnostics`. The twin is the same declarations with
	/// `core`'s public mocks and `app`'s mocked types declared seams; `Panel`, which `app` does not call, is unchanged.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectTwinsError(
		core: [String],
		app: [String],
		sourceLocation: SourceLocation = #_sourceLocation,
		diagnostics: (_ fixtures: [String: FixturePaths]) -> String,
	) async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: diagnostics, sourceLocation: sourceLocation) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.modules(core: core, app: app), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete, sourceLocation: sourceLocation)
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: diagnostics, sourceLocation: sourceLocation) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.modules(core: core.map(callingMockProductionTwin(of:)), app: app.map(callingMockProductionTwin(of:))), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete, sourceLocation: sourceLocation)
		}
	}

	/// `App`'s file up to `Screen`'s `mock()`.
	private static let screenPrelude = """
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

	"""

	/// `Mid`'s file up to `Board`'s `mock()`.
	private static let boardPrelude = """
	#if canImport(Core)
	import Core
	#endif
	#if canImport(SafeDI)
	import SafeDI
	#endif

	#if DEBUG
	extension Board {
	    nonisolated public enum SafeDIMockScope_Service {
	        nonisolated public struct panel_Values: Sendable {}

	        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
	        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
	            public let panel: (panel_Values) -> Panel.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>

	            public init(panel: @escaping (panel_Values) -> Panel.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>) {
	                self.panel = panel
	            }

	            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
	                self.init(panel: { _ in .init(__safeDI_noScope: __safeDI_builder) })
	            }
	        }
	    }

	    nonisolated public enum SafeDISendableMockScope_Service {
	        nonisolated public struct held_Values: Sendable {}

	        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
	        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
	            public let held: @Sendable (held_Values) -> Panel.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>

	            public init(held: @escaping @Sendable (held_Values) -> Panel.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>) {
	                self.held = held
	            }

	            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
	                self.init(held: { _ in .init(__safeDI_noScope: __safeDI_builder) })
	            }
	        }
	    }

	    /// Overrides for the mock dependency tree.
	    nonisolated public struct SafeDIOverrides {
	        public init(
	            panel: Panel.SafeDIOverrides = .init(),
	            held: (@Sendable () -> Panel.SafeDIOverrides)? = nil
	        ) {
	            __safeDI_storage = __safeDI_Storage(
	                panel: panel,
	                held: held
	            )
	        }

	        public var panel: Panel.SafeDIOverrides { __safeDI_storage.panel }
	        public var held: (@Sendable () -> Panel.SafeDIOverrides)? { __safeDI_storage.held }

	        private let __safeDI_storage: __safeDI_Storage

	        private final class __safeDI_Storage {
	            init(
	                panel: Panel.SafeDIOverrides,
	                held: (@Sendable () -> Panel.SafeDIOverrides)?
	            ) {
	                self.panel = panel
	                self.held = held
	            }

	            let panel: Panel.SafeDIOverrides
	            let held: (@Sendable () -> Panel.SafeDIOverrides)?
	        }
	    }

	"""

	/// `Core`'s `Panel`, whose public mock's tree builds a `Service` at two places, one inside `Row`, which carries `token`, and
	/// one beside it, which carries `row`; `Mid`, another package, holding `mid`, when given; and `App`, a third package.
	private static func modules(core: [String] = [], mid: [String]? = nil, app: [String]) -> [ModuleFixture] {
		var modules = [ModuleFixture(name: "Core", packageName: "pkg", swiftFileContent: [Self.panel] + core)]
		if let mid {
			modules.append(ModuleFixture(name: "Mid", packageName: "mid", swiftFileContent: mid, dependencies: ["Core"]))
		}
		modules.append(ModuleFixture(name: "App", packageName: "app", swiftFileContent: app, dependencies: mid == nil ? ["Core"] : ["Core", "Mid"]))
		return modules
	}

	/// `App`'s `StubService`, which no declaration SafeDI reads fulfills `Service` with, so that a probe can hand a mock a
	/// `Service` of its own, named for what it stands for, for each place no declaration fulfills.
	private static let stubService = """
	import Core

	public final class StubService: Service {
	    public init(name: String) {
	        self.name = name
	    }

	    let name: String
	}
	"""

	/// `App`'s subclasses of `HoleHanded`, one for each place of it that no declaration fulfills, so that a probe can tell
	/// which builder built a place.
	private static let holeHandedOfEachPlace = """
	import Core

	final class PanelHoleHanded: HoleHanded {}

	final class DeckHoleHanded: HoleHanded {}
	"""

	private static let panel = """
	import SafeDI

	public protocol Service: Sendable {}

	@Instantiable
	public final class Token: Instantiable, Sendable {
	    public init() {}
	}

	@Instantiable
	public struct Row: Instantiable, Sendable {
	    public init(token: Token, service: any Service) {
	        self.token = token
	        self.service = service
	    }

	    @Instantiated public let token: Token
	    @Instantiated let service: any Service
	}

	@Instantiable(generateMock: .public)
	public struct Panel: Instantiable, Sendable {
	    package init(row: Row, service: any Service) {
	        self.row = row
	        self.service = service
	    }

	    @Instantiated let row: Row
	    @Instantiated let service: any Service
	}
	"""

	/// `Panel`, receiving a `filter` its callers provide.
	private static let panelReceivingFilter = """
	import SafeDI

	public protocol Service: Sendable {}

	@Instantiable
	public struct Row: Instantiable, Sendable {
	    package init() {}
	}

	@Instantiable(generateMock: .public)
	public struct Panel: Instantiable {
	    public init(filter: [3 of Int], row: Row, service: any Service) {
	        self.filter = filter
	        self.row = row
	        self.service = service
	    }

	    @Received let filter: [3 of Int]
	    @Instantiated let row: Row
	    @Instantiated let service: any Service
	}
	"""

	/// A fulfiller in another package whose public mock's `public` tier passes `nil` to the `filter` its tree receives.
	private static let defaultServiceWithTokenCache = """
	import Core
	import SafeDI

	@Instantiable
	package struct TokenCache: Instantiable {
	    package init(filter: [3 of Int]?) {
	        self.filter = filter
	    }

	    @Received(onlyIfAvailable: true) let filter: [3 of Int]?
	}

	@Instantiable(fulfillingAdditionalTypes: [Service.self], generateMock: .public)
	public struct DefaultService: Service, Instantiable {
	    package init(tokenCache: TokenCache) {
	        self.tokenCache = tokenCache
	    }

	    @Instantiated let tokenCache: TokenCache
	}
	"""

	/// A public mock whose tree builds `Model`, and so its `Service`, on two routes: inside `Page`, which binds `token` before
	/// `model`, and beside it, where nothing binds `token`.
	private static let hub = """
	import SafeDI

	@Instantiable
	public struct Model: Instantiable, Sendable {
	    public init(service: any Service) {
	        self.service = service
	    }

	    @Instantiated let service: any Service
	}

	@Instantiable
	public struct Page: Instantiable, Sendable {
	    public init(token: Token, model: Model) {
	        self.token = token
	        self.model = model
	    }

	    @Instantiated public let token: Token
	    @Instantiated let model: Model
	}

	@Instantiable(generateMock: .public)
	public struct Hub: Instantiable, Sendable {
	    package init(page: Page, model: Model) {
	        self.page = page
	        self.model = model
	    }

	    @Instantiated let page: Page
	    @Instantiated let model: Model
	}
	"""

	private static let hubScreen = """
	import Core
	import SafeDI

	@Instantiable(generateMock: true)
	public struct HubScreen: Instantiable {
	    public init(hub: Hub) {
	        self.hub = hub
	    }

	    @Instantiated let hub: Hub
	}
	"""

	private static let officeScreen = """
	import Core
	import SafeDI

	@Instantiable(generateMock: true)
	public struct OfficeScreen: Instantiable {
	    public init(office: Office) {
	        self.office = office
	    }

	    @Instantiated let office: Office
	}
	"""

	/// A type whose name no hole has, for a property under a builder's label.
	private static let thing = """
	import SafeDI

	@Instantiable
	public struct Thing: Instantiable, Sendable {
	    public init() {}
	}
	"""

	/// A public mock with two holes, one `App` fills.
	private static let gadget = """
	import SafeDI

	public protocol Widget: Sendable {}

	public protocol Gizmo: Sendable {}

	@Instantiable(generateMock: .public)
	public struct Gadget: Instantiable, Sendable {
	    package init(widget: any Widget, gizmo: any Gizmo) {
	        self.widget = widget
	        self.gizmo = gizmo
	    }

	    @Instantiated let widget: any Widget
	    @Instantiated let gizmo: any Gizmo
	}
	"""

	private static let screen = """
	import Core
	import SafeDI

	@Instantiable(generateMock: true)
	public struct Screen: Instantiable {
	    public init(panel: Panel) {
	        self.panel = panel
	    }

	    @Instantiated let panel: Panel
	}
	"""

	private static let defaultService = """
	import Core
	import SafeDI

	@Instantiable(fulfillingAdditionalTypes: [Service.self])
	public struct DefaultService: Service, Instantiable {
	    public init() {}
	}
	"""

	/// A fulfiller only the place inside `Row` carries what it reads for.
	private static let defaultServiceReceivingToken = """
	import Core
	import SafeDI

	@Instantiable(fulfillingAdditionalTypes: [Service.self])
	public struct DefaultService: Service, Instantiable {
	    public init(token: Token) {
	        self.token = token
	    }

	    @Received let token: Token
	}
	"""

	/// A public mock in `Mid` that calls `Panel`'s in plain code and inside a `@Sendable` function.
	private static let board = """
	import Core
	import SafeDI

	@Instantiable(generateMock: .public)
	public struct Board: Instantiable, Sendable {
	    package init(panel: Panel, held: SendableInstantiator<Panel>) {
	        self.panel = panel
	        self.held = held
	    }

	    @Instantiated let panel: Panel
	    @Instantiated let held: SendableInstantiator<Panel>
	}
	"""

	/// A public mock in `Mid` that calls `Panel`'s in plain code only.
	private static let plainBoard = """
	import Core
	import SafeDI

	@Instantiable(generateMock: .public)
	public struct Board: Instantiable, Sendable {
	    package init(panel: Panel) {
	        self.panel = panel
	    }

	    @Instantiated let panel: Panel
	}
	"""

	/// A fulfiller that fills only the place inside `Row`, which carries `token`.
	private static let tokenService = """
	import Core
	import SafeDI

	@Instantiable(fulfillingAdditionalTypes: [Service.self])
	public struct TokenService: Service, Instantiable {
	    public init(token: Token) {
	        self.token = token
	    }

	    @Received let token: Token
	}
	"""

	/// A fake that fills every place of `Service`, in mocks only.
	private static let fakeService = """
	import Core
	import SafeDI

	@Instantiable(fulfillingAdditionalTypes: [Service.self], mockOnly: true)
	public struct FakeService: Service {
	    public static func mock() -> FakeService {
	        FakeService()
	    }
	}
	"""

	/// A fulfiller whose tree instantiates a type nothing fulfills.
	private static let defaultServiceInstantiatingGizmo = """
	import Core
	import SafeDI

	public protocol Gizmo: Sendable {}

	@Instantiable(fulfillingAdditionalTypes: [Service.self])
	public struct DefaultService: Service, Instantiable {
	    public init(gizmo: any Gizmo) {
	        self.gizmo = gizmo
	    }

	    @Instantiated let gizmo: any Gizmo
	}
	"""

	/// A fake of `Gizmo`, which `defaultServiceInstantiatingGizmo` declares, in mocks only.
	private static let fakeGizmo = """
	import SafeDI

	@Instantiable(fulfillingAdditionalTypes: [Gizmo.self], mockOnly: true)
	public struct FakeGizmo: Gizmo {
	    public static func mock() -> FakeGizmo {
	        FakeGizmo()
	    }
	}
	"""

	/// A seam in `Mid` that fulfills `Service`, whose initializer another module cannot call, with a hole of its own.
	private static let gadgetSeam = """
	import Core
	import SafeDI

	public protocol Gadget: Sendable {}

	@Instantiable(generateDependencyTree: true, fulfillingAdditionalTypes: [Service.self])
	public struct GadgetSeam: Service, Instantiable {
	    init(gadget: any Gadget) {
	        self.gadget = gadget
	    }

	    @Instantiated let gadget: any Gadget
	}
	"""

	private static let boardScreen = """
	import Core
	import Mid
	import SafeDI

	@Instantiable(generateMock: true)
	public struct BoardScreen: Instantiable {
	    public init(board: Board) {
	        self.board = board
	    }

	    @Instantiated let board: Board
	}
	"""

	/// A `Model`, whose `Service` is a place of the public mocks beside it.
	private static let model = """
	@Instantiable
	public struct Model: Instantiable, Sendable {
	    public init(service: any Service) {
	        self.service = service
	    }

	    @Instantiated let service: any Service
	}
	"""

	/// A `Lobby` that forwards a `Token?` before it builds a `Model`.
	private static let lobbyForwardingOptionalToken = """
	@Instantiable
	public struct Lobby: Instantiable {
	    public init(token: Token?, model: Model) {
	        self.token = token
	        self.model = model
	    }

	    @Forwarded let token: Token?
	    @Instantiated let model: Model
	}
	"""

	/// A public mock whose tree builds `Model`, and so its `Service`, on two routes: inside `Lobby`, whose nearest `token`
	/// is the `Token?` it forwards, and beside it, whose nearest is the `Token` `Office` binds first.
	private static let officeForwardingOptionalToken = """
	import SafeDI

	\(model)

	\(lobbyForwardingOptionalToken)

	@Instantiable(generateMock: .public)
	public struct Office: Instantiable {
	    package init(token: Token, lobbyBuilder: Instantiator<Lobby>, model: Model) {
	        self.token = token
	        self.lobbyBuilder = lobbyBuilder
	        self.model = model
	    }

	    @Instantiated let token: Token
	    @Instantiated let lobbyBuilder: Instantiator<Lobby>
	    @Instantiated let model: Model
	}
	"""

	/// A public mock whose tree builds `Model`, and so its `Service`, on a route for each of `properties`, in that order:
	/// inside `Lobby`, whose nearest `token` is the `Token?` it forwards; inside `Desk`, whose nearest is the `Token` it
	/// binds first; and beside them, where nothing binds a `token`.
	private static func officeOfThreeRoutes(order properties: [String]) -> String {
		let parameters = properties.map { $0.components(separatedBy: " let ").last ?? "" }
		let labels = parameters.map { String($0.prefix { $0 != ":" }) }
		return """
		import SafeDI

		\(model)

		\(lobbyForwardingOptionalToken)

		@Instantiable
		public struct Desk: Instantiable {
		    public init(token: Token, model: Model) {
		        self.token = token
		        self.model = model
		    }

		    @Instantiated let token: Token
		    @Instantiated let model: Model
		}

		@Instantiable(generateMock: .public)
		public struct Office: Instantiable {
		    package init(\(parameters.joined(separator: ", "))) {
		\(labels.map { "        self.\($0) = \($0)" }.joined(separator: "\n"))
		    }

		\(properties.map { "    \($0)" }.joined(separator: "\n"))
		}
		"""
	}

	/// Every order of `elements`.
	private static func permutations(of elements: [String]) -> [[String]] {
		guard elements.count > 1 else { return [elements] }
		return elements.indices.flatMap { index in
			var rest = elements
			let element = rest.remove(at: index)
			return permutations(of: rest).map { [element] + $0 }
		}
	}

	/// A public mock whose tree builds `Model` inside `Lobby`, whose nearest `token` is the `Token?` it forwards, and inside
	/// `Wing`, beside `Gauge`, whose nearest is the `Token` `Office` binds first: `Gauge` is reached on that route only.
	private static let officeWithWing = """
	import SafeDI

	\(model)

	\(lobbyForwardingOptionalToken)

	@Instantiable
	public struct Gauge: Instantiable, Sendable {
	    public init(service: any Service) {
	        self.service = service
	    }

	    @Instantiated let service: any Service
	}

	@Instantiable
	public struct Wing: Instantiable {
	    public init(model: Model, gauge: Gauge) {
	        self.model = model
	        self.gauge = gauge
	    }

	    @Instantiated let model: Model
	    @Instantiated let gauge: Gauge
	}

	@Instantiable(generateMock: .public)
	public struct Office: Instantiable {
	    package init(token: Token, lobbyBuilder: Instantiator<Lobby>, wing: Wing) {
	        self.token = token
	        self.lobbyBuilder = lobbyBuilder
	        self.wing = wing
	    }

	    @Instantiated let token: Token
	    @Instantiated let lobbyBuilder: Instantiator<Lobby>
	    @Instantiated let wing: Wing
	}
	"""

	/// A fulfiller that reads `token` only if available.
	private static let defaultServiceReceivingTokenIfAvailable = """
	import Core
	import SafeDI

	@Instantiable(fulfillingAdditionalTypes: [Service.self])
	public struct DefaultService: Service, Instantiable {
	    public init(token: Token?) {
	        self.token = token
	    }

	    @Received(onlyIfAvailable: true) let token: Token?
	}
	"""

	/// A public mock whose tree builds `Model` inside `Page`, which binds `token` before it, and inside `Hall`, beneath which
	/// nothing binds one: `Hall`'s dispatcher hands on what the root hands it.
	private static let hubWithHall = """
	import SafeDI

	\(model)

	@Instantiable
	public struct Page: Instantiable, Sendable {
	    public init(token: Token, model: Model) {
	        self.token = token
	        self.model = model
	    }

	    @Instantiated public let token: Token
	    @Instantiated let model: Model
	}

	@Instantiable
	public struct Hall: Instantiable, Sendable {
	    public init(model: Model) {
	        self.model = model
	    }

	    @Instantiated let model: Model
	}

	@Instantiable(generateMock: .public)
	public struct Hub: Instantiable, Sendable {
	    package init(page: Page, hall: Hall) {
	        self.page = page
	        self.hall = hall
	    }

	    @Instantiated let page: Page
	    @Instantiated let hall: Hall
	}
	"""

	/// A public mock whose `Model` binds a `Token` before its own `Service` and its `Bench`, which binds a `Badge` under the
	/// label before its `Service`.
	private static let hubWithBench = """
	import SafeDI

	@Instantiable
	public struct Badge: Instantiable, Sendable {
	    public init() {}
	}

	@Instantiable
	public struct Bench: Instantiable, Sendable {
	    public init(token: Badge, service: any Service) {
	        self.token = token
	        self.service = service
	    }

	    @Instantiated let token: Badge
	    @Instantiated let service: any Service
	}

	@Instantiable
	public struct Model: Instantiable, Sendable {
	    public init(token: Token, service: any Service, bench: Bench) {
	        self.token = token
	        self.service = service
	        self.bench = bench
	    }

	    @Instantiated let token: Token
	    @Instantiated let service: any Service
	    @Instantiated let bench: Bench
	}

	@Instantiable(generateMock: .public)
	public struct Hub: Instantiable, Sendable {
	    package init(model: Model) {
	        self.model = model
	    }

	    @Instantiated let model: Model
	}
	"""

	/// A public mock whose `Model` holds an `ErasedInstantiator` place, built inside `Page`, which binds `token` before it,
	/// and beside it, where nothing binds one.
	private static let hubWithErasedPart = """
	import SafeDI

	public protocol Part {}

	@Instantiable
	public struct Model: Instantiable {
	    public init(part: ErasedInstantiator<String, any Part>) {
	        self.part = part
	    }

	    @Instantiated(fulfilledByType: "DefaultPart") let part: ErasedInstantiator<String, any Part>
	}

	@Instantiable
	public struct Page: Instantiable {
	    public init(token: Token, model: Model) {
	        self.token = token
	        self.model = model
	    }

	    @Instantiated public let token: Token
	    @Instantiated let model: Model
	}

	@Instantiable(generateMock: .public)
	public struct Hub: Instantiable {
	    package init(page: Page, model: Model) {
	        self.page = page
	        self.model = model
	    }

	    @Instantiated let page: Page
	    @Instantiated let model: Model
	}
	"""

	/// The fulfiller of `hubWithErasedPart`'s place, which forwards a name and reads `token`.
	private static let defaultPartReceivingToken = """
	import Core
	import SafeDI

	@Instantiable
	public struct DefaultPart: Part, Instantiable {
	    public init(name: String, token: Token) {
	        self.name = name
	        self.token = token
	    }

	    @Forwarded let name: String
	    @Received let token: Token
	}
	"""

	/// A public mock whose tree builds `Model` beside `token`, which `Office` binds first, and inside `Desk`, which binds a
	/// property labeled `laterLabel` after `model`.
	private static func officeWithDesk(laterLabel: String) -> String {
		"""
		import SafeDI

		\(model)

		@Instantiable
		public struct Stamp: Instantiable, Sendable {
		    public init(model: Model) {
		        self.model = model
		    }

		    @Received let model: Model
		}

		@Instantiable
		public struct Desk: Instantiable, Sendable {
		    public init(model: Model, \(laterLabel): Stamp) {
		        self.model = model
		        self.\(laterLabel) = \(laterLabel)
		    }

		    @Instantiated let model: Model
		    @Instantiated let \(laterLabel): Stamp
		}

		@Instantiable(generateMock: .public)
		public struct Office: Instantiable, Sendable {
		    package init(token: Token, desk: Desk, model: Model) {
		        self.token = token
		        self.desk = desk
		        self.model = model
		    }

		    @Instantiated let token: Token
		    @Instantiated let desk: Desk
		    @Instantiated let model: Model
		}
		"""
	}

	/// A public mock whose tree builds `Model` beside `token`, which `Office` binds first, and inside `Bench`, which binds a
	/// `Badge` under the label before `model`.
	private static let officeWithBench = """
	import SafeDI

	\(model)

	@Instantiable
	public struct Badge: Instantiable, Sendable {
	    public init() {}
	}

	@Instantiable
	public struct Bench: Instantiable, Sendable {
	    public init(token: Badge, model: Model) {
	        self.token = token
	        self.model = model
	    }

	    @Instantiated let token: Badge
	    @Instantiated let model: Model
	}

	@Instantiable(generateMock: .public)
	public struct Office: Instantiable, Sendable {
	    package init(token: Token, bench: Bench, model: Model) {
	        self.token = token
	        self.bench = bench
	        self.model = model
	    }

	    @Instantiated let token: Token
	    @Instantiated let bench: Bench
	    @Instantiated let model: Model
	}
	"""

	/// A public mock whose tree opens `Node`s, each of which opens the next and builds a `Service`.
	private static let hubOpeningNodes = """
	import SafeDI

	@Instantiable
	public struct Node: Instantiable {
	    public init(id: Int, next: Instantiator<Node>, service: any Service) {
	        self.id = id
	        self.next = next
	        self.service = service
	    }

	    @Forwarded let id: Int
	    @Instantiated let next: Instantiator<Node>
	    @Instantiated let service: any Service
	}

	@Instantiable(generateMock: .public)
	public struct Hub: Instantiable {
	    package init(token: Token, node: Instantiator<Node>) {
	        self.token = token
	        self.node = node
	    }

	    @Instantiated let token: Token
	    @Instantiated let node: Instantiator<Node>
	}
	"""

	/// A fulfiller that reads a node's `id` and the `token` `Hub` binds.
	private static let defaultServiceReceivingIdAndToken = """
	import Core
	import SafeDI

	@Instantiable(fulfillingAdditionalTypes: [Service.self])
	public struct DefaultService: Service, Instantiable {
	    public init(id: Int, token: Token) {
	        self.id = id
	        self.token = token
	    }

	    @Received let id: Int
	    @Received let token: Token
	}
	"""

	/// Shape E as a public mock with `screenCount` internal screens in layers of four: screen `i` opens the three screens of
	/// the next layer but the one at its own position, every screen forwards an `id`, and each screen of the last layer
	/// instantiates a model with the place `api`, which `App` fills.
	private static func publicShapeEModules(screenCount: Int) -> [ModuleFixture] {
		let layerCount = screenCount / 4
		var core = ["import SafeDI", "public protocol Api {}"]
		func type(named name: String, access: String = "", attributes: String = "@Instantiable", properties: [String]) -> String {
			let parameters = properties.map { $0.components(separatedBy: " let ").last ?? "" }
			let labels = parameters.map { String($0.prefix { $0 != ":" }) }
			return """
			\(attributes)
			\(access)struct \(name): Instantiable {
			    init(\(parameters.joined(separator: ", "))) {
			\(labels.map { "        self.\($0) = \($0)" }.joined(separator: "\n"))
			    }
			\(properties.map { "    \($0)" }.joined(separator: "\n"))
			}
			"""
		}
		for screen in 0..<screenCount {
			let layer = screen / 4
			let opened = layer < layerCount - 1 ? (0..<4).filter { $0 != screen % 4 }.map { (layer + 1) * 4 + $0 } : []
			var screenProperties = ["@Forwarded let id: Int", "@Instantiated let model\(screen): Model\(screen)"]
			screenProperties += opened.map { "@Instantiated let screen\($0)Builder: Instantiator<Screen\($0)>" }
			core.append(type(named: "Screen\(screen)", properties: screenProperties))
			var modelProperties = ["@Received let id: Int"]
			if opened.isEmpty {
				modelProperties.append("@Instantiated let api: any Api")
			}
			core.append(type(named: "Model\(screen)", properties: modelProperties))
		}
		core.append(type(named: "Home", access: "public ", attributes: "@Instantiable(generateMock: .public)", properties: (0..<4).map { "@Instantiated let screen\($0)Builder: Instantiator<Screen\($0)>" }))
		return [
			ModuleFixture(name: "Core", packageName: "pkg", swiftFileContent: [core.joined(separator: "\n\n")]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContent: ["""
			import Core
			import SafeDI

			@Instantiable(fulfillingAdditionalTypes: [Api.self])
			struct LiveApi: Api, Instantiable {
			    init(id: Int) {
			        self.id = id
			    }

			    @Received let id: Int
			}

			@Instantiable(generateMock: true)
			struct HomeScreen: Instantiable {
			    init(home: Home) {
			        self.home = home
			    }

			    @Instantiated let home: Home
			}
			"""], dependencies: ["Core"]),
		]
	}

	/// A public mock in `Mid` that calls `Hub`'s.
	private static let boardCallingHub = """
	import Core
	import SafeDI

	@Instantiable(generateMock: .public)
	public struct Board: Instantiable, Sendable {
	    package init(hub: Hub) {
	        self.hub = hub
	    }

	    @Instantiated let hub: Hub
	}
	"""

	/// Compares the values the mocks of `modules`, as `output` generated them, build for `probes` with what internal
	/// mocks build inline when every declaration of `modules` is in one module and every public mock is internal.
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
			for (index, content) in module.swiftFileContent.enumerated() {
				inlineFiles["\(module.name)_File\(index).swift"] = inline(content)
			}
		}
		let inlineModules = [ModuleFixture(name: modules[0].name, packageName: modules[0].packageName, swiftFileContentByFilePath: inlineFiles)]
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inlineModules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		func path(of modules: [ModuleFixture], output: MultiModuleTestOutput) throws -> DifferentialValuePath {
			try DifferentialValuePath(modules: modules.map { module in
				var fixtureFiles = module.swiftFileContentByFilePath
				for (index, content) in module.swiftFileContent.enumerated() {
					fixtureFiles["File\(index).swift"] = content
				}
				return try DifferentialValueModule(
					name: module.name,
					packageName: module.packageName,
					dependencyModuleNames: module.dependencies,
					fixtureFiles: fixtureFiles,
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
