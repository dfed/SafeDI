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
/// builder of the enclosing called type. The call inside the fill re-enters the root level function of the call that
/// encloses it, as the production twin’s call of the third module’s seam re-enters its enclosing seam call, so the
/// builder builds the enclosing called type with the caller’s fill, as the same types built inline do.
struct SafeDIToolCallingMockCrossCallReentryTests: ~Copyable {
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

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reentersEnclosingCallsRootLevel_whenFillHoldsInstantiatorOfEnclosingCalledType() async throws {
		// `Screen` builds `Page`, whose place `service` module `Core` cannot fill, so `Screen`’s mock calls `Page`’s public
		// mock and fills the place with `DefaultService`, which builds `Book`, whose public mock holds an `Instantiator<Page>`.
		// The call of `Book` inside the fill re-enters the root level function of the call of `Page` that encloses it, as the
		// production twin’s call of `Book`’s seam re-enters its call of `Page`’s:
		// `.init(pageBuilder: { _ in __safeDI_serviceBuilder_Page() })`.
		let graph = Self.graph(caller: .internal, builder: "Instantiator", deferredPlace: false)
		let modules = graph.modules(.mock)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)

		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
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
		                self.service = { _ in __safeDI_builder() }
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
		"""])
		#expect(output.modules["Mid"]?.generatedFiles == ["Mid.swift": generatedFileHeader + """
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
		                self.pageBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
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
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_page() -> Page {
		            func __safeDI_serviceBuilder_Page_service() -> any Service {
		                func __safeDI_service() -> DefaultService {
		                    func __safeDI_book() -> Book {
		                        func __safeDI_serviceBuilder_Book() -> Book.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
		                            .init(pageBuilder: { _ in __safeDI_serviceBuilder_Page() })
		                        }
		                        return Book.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder_Book())
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
		            return if let safeDIBuilder = safeDIOverrides.page { safeDIBuilder({ __safeDI_serviceBuilder_Page_service() }) } else { Page.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder_Page()) }
		        }
		        let page: Page = __safeDI_page()
		        return Screen(page: page)
		    }
		}
		#endif
		"""])
		try await expectCompilesAndBuildsInlineValues(of: graph, output: output, modules: modules, probes: [Self.screenProbe])
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reentersEnclosingCallsRootLevel_whenPublicCallersFillHoldsInstantiatorOfEnclosingCalledType() async throws {
		// The graph above with a `.public` caller, whose mock’s call inside the fill re-enters the enclosing call’s root
		// level function as the internal mock’s does.
		let graph = Self.graph(caller: .public, builder: "Instantiator", deferredPlace: false)
		let modules = graph.modules(.mock)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)

		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
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
		                self.service = { _ in __safeDI_builder() }
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
		"""])
		#expect(output.modules["Mid"]?.generatedFiles == ["Mid.swift": generatedFileHeader + """
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
		                self.pageBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
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
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            page: ((@escaping () -> any Service) -> Page)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                page: page
		            )
		        }

		        public var page: ((@escaping () -> any Service) -> Page)? { __safeDI_storage.page }

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

		    public static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_page() -> Page {
		            func __safeDI_serviceBuilder_Page_service() -> any Service {
		                func __safeDI_service() -> DefaultService {
		                    func __safeDI_book() -> Book {
		                        func __safeDI_serviceBuilder_Book() -> Book.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
		                            .init(pageBuilder: { _ in __safeDI_serviceBuilder_Page() })
		                        }
		                        return Book.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder_Book())
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
		            return if let safeDIBuilder = safeDIOverrides.page { safeDIBuilder({ __safeDI_serviceBuilder_Page_service() }) } else { Page.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder_Page()) }
		        }
		        let page: Page = __safeDI_page()
		        return Screen(page: page)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_51799E6AA5E7B634 {}
		}
		#endif
		"""])
		try await expectCompilesAndBuildsInlineValues(of: graph, output: output, modules: modules, probes: [Self.screenProbe])
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reentersEnclosingCallsRootLevel_whenListedCallersFillHoldsInstantiatorOfEnclosingCalledType() async throws {
		// The graph above with `Screen` a plain `@Instantiable` its module lists in `additionalMocksToGenerate`, whose mock
		// is internal and generated as an internal caller’s is.
		let graph = Self.graph(caller: .listed, builder: "Instantiator", deferredPlace: false)
		let modules = graph.modules(.mock)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)

		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
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
		                self.service = { _ in __safeDI_builder() }
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
		"""])
		#expect(output.modules["Mid"]?.generatedFiles == ["Mid.swift": generatedFileHeader + """
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
		                self.pageBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
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
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_page() -> Page {
		            func __safeDI_serviceBuilder_Page_service() -> any Service {
		                func __safeDI_service() -> DefaultService {
		                    func __safeDI_book() -> Book {
		                        func __safeDI_serviceBuilder_Book() -> Book.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
		                            .init(pageBuilder: { _ in __safeDI_serviceBuilder_Page() })
		                        }
		                        return Book.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder_Book())
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
		            return if let safeDIBuilder = safeDIOverrides.page { safeDIBuilder({ __safeDI_serviceBuilder_Page_service() }) } else { Page.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder_Page()) }
		        }
		        let page: Page = __safeDI_page()
		        return Screen(page: page)
		    }
		}
		#endif
		"""])
		try await expectCompilesAndBuildsInlineValues(of: graph, output: output, modules: modules, probes: [Self.screenProbe])
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reentersEnclosingCallsRootLevel_whenFillHoldsSendableInstantiatorOfEnclosingCalledType() async throws {
		// `Book` holds a `SendableInstantiator<Page>`, so its public mock takes the `@Sendable` family’s struct, whose
		// member the call inside the fill fills with the enclosing call’s root level function, which is `@Sendable` too.
		let graph = Self.graph(caller: .internal, builder: "SendableInstantiator", deferredPlace: false)
		let modules = graph.modules(.mock)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)

		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
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
		                self.service = { _ in __safeDI_builder() }
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
		"""])
		#expect(output.modules["Mid"]?.generatedFiles == ["Mid.swift": generatedFileHeader + """
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
		                self.pageBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
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
		        @Sendable func __safeDI_pageBuilder() -> Page {
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
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_page() -> Page {
		            @Sendable func __safeDI_serviceBuilder_Page_service() -> any Service {
		                func __safeDI_service() -> DefaultService {
		                    func __safeDI_book() -> Book {
		                        @Sendable nonisolated func __safeDI_serviceSendableBuilder_Book() -> Book.SafeDISendableMockScope_Service.__safeDI_Builder<any Service> {
		                            .init(pageBuilder: { _ in __safeDI_serviceBuilder_Page() })
		                        }
		                        return Book.__safeDI_mock(serviceSendableBuilder: __safeDI_serviceSendableBuilder_Book())
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
		            return if let safeDIBuilder = safeDIOverrides.page { safeDIBuilder({ __safeDI_serviceBuilder_Page_service() }) } else { Page.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder_Page()) }
		        }
		        let page: Page = __safeDI_page()
		        return Screen(page: page)
		    }
		}
		#endif
		"""])
		try await expectCompilesAndBuildsInlineValues(of: graph, output: output, modules: modules, probes: [Self.screenProbe])
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reentersEnclosingCallsRootLevel_whenFillOfDeferredPlaceHoldsInstantiatorOfEnclosingCalledType() async throws {
		// `Page`’s place is deferred, an `ErasedInstantiator<Int, any Service>` that `DefaultService`, forwarding `id`,
		// fulfills by name, so the call inside the fill builds `Book` in the place’s builder and re-enters the enclosing
		// call’s root level function from there.
		let graph = Self.graph(caller: .internal, builder: "Instantiator", deferredPlace: true)
		let modules = graph.modules(.mock)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)

		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Page {
		    nonisolated public enum SafeDIMockScope_DefaultService_Service {
		        nonisolated public struct serviceBuilder_Values {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let serviceBuilder: (serviceBuilder_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder

		            public init(serviceBuilder: @escaping (serviceBuilder_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                self.serviceBuilder = serviceBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                self.serviceBuilder = { _ in __safeDI_builder }
		            }
		        }
		    }

		    public static func mock(
		        defaultService_ServiceBuilder: @escaping ErasedInstantiator<Int, any Service>.Builder
		    ) -> Page {
		        Page.__safeDI_mock(defaultService_ServiceBuilder: .init(__safeDI_noScope: defaultService_ServiceBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        defaultService_ServiceBuilder __safeDI_defaultService_ServiceBuilder: Page.SafeDIMockScope_DefaultService_Service.__safeDI_Builder<any Service>
		    ) -> Page {
		        let serviceBuilder = ErasedInstantiator<Int, any Service>(__safeDI_defaultService_ServiceBuilder.serviceBuilder(SafeDIMockScope_DefaultService_Service.serviceBuilder_Values()))
		        return Page(serviceBuilder: serviceBuilder)
		    }
		}

		extension Page {
		    public enum __safeDI_Page_mock_D15A253F853DBCB8 {}
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
		extension Book {
		    nonisolated public enum SafeDIMockScope_DefaultService_Service {
		        nonisolated public struct pageBuilder_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let pageBuilder: (pageBuilder_Values) -> Page.SafeDIMockScope_DefaultService_Service.__safeDI_Builder<__safeDI_Built>

		            public init(pageBuilder: @escaping (pageBuilder_Values) -> Page.SafeDIMockScope_DefaultService_Service.__safeDI_Builder<__safeDI_Built>) {
		                self.pageBuilder = pageBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                self.pageBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init() {}
		    }

		    public static func mock(
		        defaultService_ServiceBuilder: @escaping ErasedInstantiator<Int, any Service>.Builder,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Book {
		        Book.__safeDI_mock(defaultService_ServiceBuilder: .init(__safeDI_noScope: defaultService_ServiceBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        defaultService_ServiceBuilder __safeDI_defaultService_ServiceBuilder: Book.SafeDIMockScope_DefaultService_Service.__safeDI_Builder<any Service>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Book {
		        _ = Page.__safeDI_Page_mock_D15A253F853DBCB8.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
		        func __safeDI_pageBuilder() -> Page {
		            Page.__safeDI_mock(defaultService_ServiceBuilder: __safeDI_defaultService_ServiceBuilder.pageBuilder(SafeDIMockScope_DefaultService_Service.pageBuilder_Values()))
		        }
		        let pageBuilder = Instantiator<Page>(__safeDI_pageBuilder)
		        return Book(pageBuilder: pageBuilder)
		    }
		}

		extension Book {
		    public enum __safeDI_Book_mock_12A9084ABFC242B9 {}
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
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            page: ((@escaping ErasedInstantiator<Int, any Service>.Builder) -> Page)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                page: page
		            )
		        }

		        var page: ((@escaping ErasedInstantiator<Int, any Service>.Builder) -> Page)? { __safeDI_storage.page }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                page: ((@escaping ErasedInstantiator<Int, any Service>.Builder) -> Page)?
		            ) {
		                self.page = page
		            }

		            let page: ((@escaping ErasedInstantiator<Int, any Service>.Builder) -> Page)?
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_page() -> Page {
		            func __safeDI_defaultService_ServiceBuilder_Page_serviceBuilder() -> ErasedInstantiator<Int, any Service>.Builder {
		                func __safeDI_serviceBuilder(id: Int) -> DefaultService {
		                    func __safeDI_book() -> Book {
		                        func __safeDI_defaultService_ServiceBuilder_Book() -> Book.SafeDIMockScope_DefaultService_Service.__safeDI_Builder<any Service> {
		                            .init(pageBuilder: { _ in __safeDI_defaultService_ServiceBuilder_Page() })
		                        }
		                        return Book.__safeDI_mock(defaultService_ServiceBuilder: __safeDI_defaultService_ServiceBuilder_Book())
		                    }
		                    let book: Book = __safeDI_book()
		                    return DefaultService(id: id, book: book)
		                }
		                return { forwarded in __safeDI_serviceBuilder(id: forwarded) }
		            }
		            func __safeDI_defaultService_ServiceBuilder_Page() -> Page.SafeDIMockScope_DefaultService_Service.__safeDI_Builder<any Service> {
		                .init(serviceBuilder: { _ in __safeDI_defaultService_ServiceBuilder_Page_serviceBuilder() })
		            }
		            _ = Page.__safeDI_Page_mock_D15A253F853DBCB8.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
		            return if let safeDIBuilder = safeDIOverrides.page { safeDIBuilder(__safeDI_defaultService_ServiceBuilder_Page_serviceBuilder()) } else { Page.__safeDI_mock(defaultService_ServiceBuilder: __safeDI_defaultService_ServiceBuilder_Page()) }
		        }
		        let page: Page = __safeDI_page()
		        return Screen(page: page)
		    }
		}
		#endif
		"""])
		try await expectCompilesAndBuildsInlineValues(of: graph, output: output, modules: modules, probes: [Self.deferredPlaceProbe])
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reentersEnclosingCallsRootLevel_whenFillThatHoldsInstantiatorOfEnclosingCalledTypeReadsCallersValue() async throws {
		// `DefaultService` also receives the `Token` `Screen` instantiates. A call inside the fill re-enters the root level
		// function, so the fill takes `token` from it, as a call of the same builder inside a fill does: the call of `Page`
		// hands it `Screen`’s, and the call of `Book` its own nearest declaration, here the fill’s, which holds `Screen`’s, as
		// inline’s `DefaultService` reads it.
		let graph = Self.graph(caller: .internal, builder: "Instantiator", deferredPlace: false, fillReadsCallersToken: true)
		let modules = graph.modules(.mock)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)

		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
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
		                self.service = { _ in __safeDI_builder() }
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
		"""])
		#expect(output.modules["Mid"]?.generatedFiles == ["Mid.swift": generatedFileHeader + """
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
		                self.pageBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
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
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            token: (() -> Token)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                token: token
		            )
		        }

		        var token: (() -> Token)? { __safeDI_storage.token }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                token: (() -> Token)?
		            ) {
		                self.token = token
		            }

		            let token: (() -> Token)?
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let token = if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder() } else { Token() }
		        func __safeDI_page() -> Page {
		            func __safeDI_serviceBuilder_Page_service(_ scope: Page.SafeDIMockScope_Service.service_Values, token: Token) -> any Service {
		                func __safeDI_service() -> DefaultService {
		                    func __safeDI_book() -> Book {
		                        func __safeDI_serviceBuilder_Book() -> Book.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
		                            .init(pageBuilder: { _ in __safeDI_serviceBuilder_Page(token: token) })
		                        }
		                        return Book.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder_Book())
		                    }
		                    let book: Book = __safeDI_book()
		                    return DefaultService(token: token, book: book)
		                }
		                let service: any Service = __safeDI_service()
		                return service
		            }
		            func __safeDI_serviceBuilder_Page(token: Token) -> Page.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
		                .init(service: { scope in __safeDI_serviceBuilder_Page_service(scope, token: token) })
		            }
		            _ = Page.__safeDI_Page_mock_4A57B09DFB8A9D2C.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
		            return Page.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder_Page(token: token))
		        }
		        let page: Page = __safeDI_page()
		        return Screen(token: token, page: page)
		    }
		}
		#endif
		"""])
		try await expectCompilesAndBuildsInlineValues(of: graph, output: output, modules: modules, probes: [Self.screenProbe])
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"), arguments: GraphFuzzerCallingMockCell.Caller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reentersEnclosingCallsRootLevelWithNearestValue_whenTypeBetweenFillAndCallDeclaresCallersValueAgain(caller: GraphFuzzerCallingMockCell.Caller) async throws {
		// `DefaultService` receives `Screen`’s `Token` and builds `Book` through `Middle`, which declares a `token` of its own.
		// The call of `Book` re-enters the root level function with `Middle`’s, the declaration nearest it, so the
		// `DefaultService` that `Book`’s builder builds reads `Middle`’s `token`, as inline’s does, where the twin reports that
		// `Book`’s call cannot hand it `Middle`’s values (contract rule 7’s re-entry outcome).
		let graph = Self.graph(caller: caller, builder: "Instantiator", deferredPlace: false, fillReadsCallersToken: true, typeBetweenDeclaresToken: true)
		let modules = graph.modules(.mock)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		let spelling = Self.appSpelling(of: caller)

		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
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
		                self.service = { _ in __safeDI_builder() }
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
		"""])
		#expect(output.modules["Mid"]?.generatedFiles == ["Mid.swift": generatedFileHeader + """
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
		                self.pageBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
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
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    \(spelling.overrides)struct SafeDIOverrides {
		        \(spelling.member)init(
		            token: (() -> Token)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                token: token
		            )
		        }

		        \(spelling.member)var token: (() -> Token)? { __safeDI_storage.token }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                token: (() -> Token)?
		            ) {
		                self.token = token
		            }

		            let token: (() -> Token)?
		        }
		    }

		    \(spelling.member)static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let token = if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder() } else { Token() }
		        func __safeDI_page() -> Page {
		            func __safeDI_serviceBuilder_Page_service(_ scope: Page.SafeDIMockScope_Service.service_Values, token: Token) -> any Service {
		                func __safeDI_service() -> DefaultService {
		                    func __safeDI_middle() -> Middle {
		                        let token = Token()
		                        func __safeDI_book() -> Book {
		                            func __safeDI_serviceBuilder_Book() -> Book.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
		                                .init(pageBuilder: { _ in __safeDI_serviceBuilder_Page(token: token) })
		                            }
		                            return Book.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder_Book())
		                        }
		                        let book: Book = __safeDI_book()
		                        return Middle(token: token, book: book)
		                    }
		                    let middle: Middle = __safeDI_middle()
		                    return DefaultService(token: token, middle: middle)
		                }
		                let service: any Service = __safeDI_service()
		                return service
		            }
		            func __safeDI_serviceBuilder_Page(token: Token) -> Page.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
		                .init(service: { scope in __safeDI_serviceBuilder_Page_service(scope, token: token) })
		            }
		            _ = Page.__safeDI_Page_mock_4A57B09DFB8A9D2C.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
		            return Page.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder_Page(token: token))
		        }
		        let page: Page = __safeDI_page()
		        return Screen(token: token, page: page)
		    }
		}
		\(spelling.guardExtension)#endif
		"""])
		try await expectCompilesAndBuildsInlineValues(of: graph, output: output, modules: modules, probes: [Self.nearestTokenProbe(calledLabel: "page")])
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"), arguments: GraphFuzzerCallingMockCell.Caller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reentersEnclosingCallsLevelBeneathRoot_whenEnclosingCallIsOfTypeThatHoldsBuilderOfFilledType(caller: GraphFuzzerCallingMockCell.Caller) async throws {
		// The graph above, with `Screen` building `Shelf`, a public mock of `Mid` that holds `Page` in an `Instantiator`, in
		// place of `Page`: the call of `Shelf` declares `Page`’s level function beneath its root, which takes `token`, and the
		// call of `Book` inside the fill re-enters it with `Middle`’s, as inline reads it.
		let graph = Self.graph(caller: caller, builder: "Instantiator", deferredPlace: false, fillReadsCallersToken: true, typeBetweenDeclaresToken: true, enclosingCallIsOfHolder: true)
		let modules = graph.modules(.mock)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		let spelling = Self.appSpelling(of: caller)

		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
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
		                self.service = { _ in __safeDI_builder() }
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
		"""])
		#expect(output.modules["Mid"]?.generatedFiles == ["Mid.swift": generatedFileHeader + """
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
		                self.pageBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
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

		#if DEBUG
		extension Shelf {
		    nonisolated public enum SafeDIMockScope_Service {
		        nonisolated public struct pageBuilder_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let pageBuilder: (pageBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>

		            public init(pageBuilder: @escaping (pageBuilder_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>) {
		                self.pageBuilder = pageBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.pageBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
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
		    ) -> Shelf {
		        Shelf.__safeDI_mock(serviceBuilder: .init(__safeDI_noScope: serviceBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        serviceBuilder __safeDI_serviceBuilder: Shelf.SafeDIMockScope_Service.__safeDI_Builder<any Service>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Shelf {
		        _ = Page.__safeDI_Page_mock_4A57B09DFB8A9D2C.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
		        func __safeDI_pageBuilder() -> Page {
		            Page.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder.pageBuilder(SafeDIMockScope_Service.pageBuilder_Values()))
		        }
		        let pageBuilder = Instantiator<Page>(__safeDI_pageBuilder)
		        return Shelf(pageBuilder: pageBuilder)
		    }
		}

		extension Shelf {
		    public enum __safeDI_Shelf_mock_0AA2046DBF99EF48 {}
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
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    \(spelling.overrides)struct SafeDIOverrides {
		        \(spelling.member)init(
		            token: (() -> Token)? = nil,
		            shelf: Shelf.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                token: token,
		                shelf: shelf
		            )
		        }

		        \(spelling.member)var token: (() -> Token)? { __safeDI_storage.token }
		        \(spelling.member)var shelf: Shelf.SafeDIOverrides { __safeDI_storage.shelf }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                token: (() -> Token)?,
		                shelf: Shelf.SafeDIOverrides
		            ) {
		                self.token = token
		                self.shelf = shelf
		            }

		            let token: (() -> Token)?
		            let shelf: Shelf.SafeDIOverrides
		        }
		    }

		    \(spelling.member)static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let token = if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder() } else { Token() }
		        func __safeDI_shelf() -> Shelf {
		            func __safeDI_serviceBuilder_Page_service(_ scope: Page.SafeDIMockScope_Service.service_Values, token: Token) -> any Service {
		                func __safeDI_service() -> DefaultService {
		                    func __safeDI_middle() -> Middle {
		                        let token = Token()
		                        func __safeDI_book() -> Book {
		                            func __safeDI_serviceBuilder_Book() -> Book.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
		                                .init(pageBuilder: { _ in __safeDI_serviceBuilder_Page(token: token) })
		                            }
		                            return Book.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder_Book())
		                        }
		                        let book: Book = __safeDI_book()
		                        return Middle(token: token, book: book)
		                    }
		                    let middle: Middle = __safeDI_middle()
		                    return DefaultService(token: token, middle: middle)
		                }
		                let service: any Service = __safeDI_service()
		                return service
		            }
		            func __safeDI_serviceBuilder_Shelf(token: Token) -> Shelf.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
		                .init(pageBuilder: { _ in __safeDI_serviceBuilder_Page(token: token) })
		            }
		            func __safeDI_serviceBuilder_Page(token: Token) -> Page.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
		                .init(service: { scope in __safeDI_serviceBuilder_Page_service(scope, token: token) })
		            }
		            _ = Shelf.__safeDI_Shelf_mock_0AA2046DBF99EF48.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Shelf", declaringModule: "Mid"))
		            return Shelf.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder_Shelf(token: token), safeDIOverrides: safeDIOverrides.shelf)
		        }
		        let shelf: Shelf = __safeDI_shelf()
		        return Screen(token: token, shelf: shelf)
		    }
		}
		\(spelling.guardExtension)#endif
		"""])
		try await expectCompilesAndBuildsInlineValues(of: graph, output: output, modules: modules, probes: [Self.nearestTokenProbe(calledLabel: "shelf")])
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"), arguments: GraphFuzzerCallingMockCell.Caller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_createsReenteredTreeInInlineOrder_whenReenteringCallHandsLazyValue(caller: GraphFuzzerCallingMockCell.Caller) async throws {
		// The first graph above with `token` a `LazilyInstantiated<Token>` and `Token` recording its creation: the call of
		// `Book` hands the re-entered level function `Middle`’s wrapper, so building `Page` again creates no `Token`, and
		// reading the inner `DefaultService`’s `token` creates `Middle`’s, as inline creates it.
		let graph = Self.graph(caller: caller, builder: "Instantiator", deferredPlace: false, fillReadsCallersToken: true, token: "LazilyInstantiated<Token>", typeBetweenDeclaresToken: true)
		let modules = graph.modules(.mock)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		let spelling = Self.appSpelling(of: caller)

		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
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
		                self.service = { _ in __safeDI_builder() }
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
		"""])
		#expect(output.modules["Mid"]?.generatedFiles == ["Mid.swift": generatedFileHeader + """
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
		                self.pageBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
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
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    \(spelling.overrides)struct SafeDIOverrides {
		        \(spelling.member)init(
		            token: (() -> Token)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                token: token
		            )
		        }

		        \(spelling.member)var token: (() -> Token)? { __safeDI_storage.token }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                token: (() -> Token)?
		            ) {
		                self.token = token
		            }

		            let token: (() -> Token)?
		        }
		    }

		    \(spelling.member)static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_token() -> Token {
		            if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder() } else { Token() }
		        }
		        let token = LazilyInstantiated<Token>(__safeDI_token)
		        func __safeDI_page() -> Page {
		            func __safeDI_serviceBuilder_Page_service(_ scope: Page.SafeDIMockScope_Service.service_Values, token: LazilyInstantiated<Token>) -> any Service {
		                func __safeDI_service() -> DefaultService {
		                    func __safeDI_middle() -> Middle {
		                        func __safeDI_token() -> Token {
		                            Token()
		                        }
		                        let token = LazilyInstantiated<Token>(__safeDI_token)
		                        func __safeDI_book() -> Book {
		                            func __safeDI_serviceBuilder_Book() -> Book.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
		                                .init(pageBuilder: { _ in __safeDI_serviceBuilder_Page(token: token) })
		                            }
		                            return Book.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder_Book())
		                        }
		                        let book: Book = __safeDI_book()
		                        return Middle(token: token, book: book)
		                    }
		                    let middle: Middle = __safeDI_middle()
		                    return DefaultService(token: token, middle: middle)
		                }
		                let service: any Service = __safeDI_service()
		                return service
		            }
		            func __safeDI_serviceBuilder_Page(token: LazilyInstantiated<Token>) -> Page.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
		                .init(service: { scope in __safeDI_serviceBuilder_Page_service(scope, token: token) })
		            }
		            _ = Page.__safeDI_Page_mock_4A57B09DFB8A9D2C.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
		            return Page.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder_Page(token: token))
		        }
		        let page: Page = __safeDI_page()
		        return Screen(token: token, page: page)
		    }
		}
		\(spelling.guardExtension)#endif
		"""])
		try await expectCompilesAndBuildsInlineValues(of: graph, output: output, modules: modules, probes: [Self.lazyTokenCreationOrderProbe])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// What a caller’s kind changes in `App`’s file: the access of `SafeDIOverrides`, of its members and of `mock()`, and the
	/// guard a `.public` mock declares.
	private static func appSpelling(of caller: GraphFuzzerCallingMockCell.Caller) -> (overrides: String, member: String, guardExtension: String) {
		switch caller {
		case .internal, .listed:
			("", "", "")
		case .public:
			("nonisolated public ", "public ", "\nextension Screen {\n    public enum __safeDI_Screen_mock_51799E6AA5E7B634 {}\n}\n")
		}
	}

	/// What a cell whose fill reaches `Book` through `Middle` compares: whether the `DefaultService` that `Book`’s builder
	/// builds again reads `Middle`’s `token`, the declaration nearest it, and whether it reads `Screen`’s.
	private static func nearestTokenProbe(calledLabel: String) -> DifferentialValueProbe {
		let read = { (screen: String) in
			"{ let screen = \(screen); let service = screen.\(calledLabel)\(calledLabel == "shelf" ? ".pageBuilder.instantiate()" : "").service as! App.DefaultService; let inner = service.middle.book.pageBuilder.instantiate().service as! App.DefaultService; return (inner.token === service.middle.token, inner.token === screen.token) }()"
		}
		return DifferentialValueProbe(name: "the token the re-entered fill reads", expression: read("App.Screen.mock()"), knownRightExpression: read("App.Screen()"))
	}

	/// What the lazy cell compares: when each `Token` is created as `Screen` is built, its `page`’s `Book` builds `Page`
	/// again, and the `DefaultService` there reads its `token`, and whether that reads `Middle`’s.
	private static let lazyTokenCreationOrderProbe = {
		let read = { (screen: String) in
			"{ App.Token.created = []; let screen = \(screen); App.Token.created.append(\"Screen\"); let service = screen.page.service as! App.DefaultService; let inner = service.middle.book.pageBuilder.instantiate().service as! App.DefaultService; App.Token.created.append(\"Page again\"); let token = inner.token.instance; App.Token.created.append(\"read\"); return (App.Token.created.joined(separator: \", \"), token === service.middle.token.instance) }()"
		}
		return DifferentialValueProbe(name: "creation order", expression: read("App.Screen.mock()"), knownRightExpression: read("App.Screen()"))
	}()

	/// What a plain place’s cells compare: `Screen` against the same types built inline.
	private static let screenProbe = DifferentialValueProbe(name: "Screen", expression: "App.Screen.mock()", knownRightExpression: "App.Screen()")

	/// What a deferred place’s cell compares: `Screen` and what its `page`’s place builds for `id` 7, in one tuple, since
	/// the comparator calls no `ErasedInstantiator`.
	private static let deferredPlaceProbe = DifferentialValueProbe(
		name: "(Screen, Screen.page.serviceBuilder.instantiate(7))",
		expression: GraphFuzzerCallingMockDraw.callerAndFill(of: "App.Screen.mock()", place: "page.serviceBuilder"),
		knownRightExpression: GraphFuzzerCallingMockDraw.callerAndFill(of: "App.Screen()", place: "page.serviceBuilder"),
	)

	/// The graph: module `Core` declares `Page`, whose place of `Service` no type `Core` sees fulfills; module `Mid` declares
	/// `Book`, which holds `Page` in a `builder`; and module `App` declares `DefaultService`, which fills `Page`’s place and
	/// builds `Book`, and the caller `Screen`, which builds `Page`, and, where `fillReadsCallersToken`, a `Token` the fill
	/// receives, as `token`, a `Token` or a `LazilyInstantiated<Token>`, whose `Token` records its creation in
	/// `Token.created`. Where `typeBetweenDeclaresToken`, the fill builds `Book` through `Middle`, which declares a `token` of
	/// its own; where `enclosingCallIsOfHolder`, `Screen` builds `Shelf`, a public mock of `Mid` that holds `Page` in an
	/// `Instantiator`, in place of `Page`. The called types’ initializers are internal, so `Screen`’s mock calls `Page`’s, or
	/// `Shelf`’s, public mock, and the fill calls `Book`’s. The calling mock’s form declares the called types public mocks
	/// only; the twin declares them seams that keep their public mocks.
	private static func graph(
		caller: GraphFuzzerCallingMockCell.Caller,
		builder: String,
		deferredPlace: Bool,
		fillReadsCallersToken: Bool = false,
		token: String = "Token",
		typeBetweenDeclaresToken: Bool = false,
		enclosingCallIsOfHolder: Bool = false,
	) -> GraphFuzzerCallingMockGraph {
		func core(attribute: String) -> String {
			let place = if deferredPlace {
				"""
				    init(serviceBuilder: ErasedInstantiator<Int, any Service>) { self.serviceBuilder = serviceBuilder }
				    @Instantiated(fulfilledByType: "DefaultService") public let serviceBuilder: ErasedInstantiator<Int, any Service>
				"""
			} else {
				"""
				    init(service: any Service) { self.service = service }
				    @Instantiated public let service: any Service
				"""
			}
			return """
			import SafeDI

			public protocol Service: AnyObject {}

			\(attribute)
			public final class Page: Instantiable {
			\(place)
			}

			"""
		}
		func mid(attribute: String) -> String {
			let shelf = if enclosingCallIsOfHolder {
				"""

				\(attribute)
				public final class Shelf: Instantiable {
				    init(pageBuilder: Instantiator<Page>) { self.pageBuilder = pageBuilder }
				    @Instantiated public let pageBuilder: Instantiator<Page>
				}

				"""
			} else {
				""
			}
			return """
			import Core
			import SafeDI

			\(attribute)
			public final class Book: Instantiable {
			    init(pageBuilder: \(builder)<Page>) { self.pageBuilder = pageBuilder }
			    @Instantiated public let pageBuilder: \(builder)<Page>
			}
			\(shelf)
			"""
		}
		func app(callerAttribute: String) -> String {
			let access = caller == .public ? "public " : ""
			var declarations = [String]()
			if fillReadsCallersToken {
				declarations.append("""
				@Instantiable
				public final class Token: Instantiable {
				    public init() {
				        Token.created.append("Token")
				    }

				    nonisolated(unsafe) public static var created = [String]()
				}
				""")
			}
			if deferredPlace {
				declarations.append("""
				@Instantiable
				\(access)final class DefaultService: Service, Instantiable {
				    \(access)init(id: Int, book: Book) { self.id = id; self.book = book }
				    @Forwarded let id: Int
				    @Instantiated let book: Book
				}
				""")
			} else if typeBetweenDeclaresToken {
				declarations.append("""
				@Instantiable(fulfillingAdditionalTypes: [(any Service).self])
				\(access)final class DefaultService: Service, Instantiable {
				    \(access)init(token: \(token), middle: Middle) { self.token = token; self.middle = middle }
				    @Received let token: \(token)
				    @Instantiated let middle: Middle
				}

				@Instantiable
				\(access)final class Middle: Instantiable {
				    \(access)init(token: \(token), book: Book) { self.token = token; self.book = book }
				    @Instantiated let token: \(token)
				    @Instantiated let book: Book
				}
				""")
			} else if fillReadsCallersToken {
				declarations.append("""
				@Instantiable(fulfillingAdditionalTypes: [(any Service).self])
				\(access)final class DefaultService: Service, Instantiable {
				    \(access)init(token: \(token), book: Book) { self.token = token; self.book = book }
				    @Received let token: \(token)
				    @Instantiated let book: Book
				}
				""")
			} else {
				declarations.append("""
				@Instantiable(fulfillingAdditionalTypes: [(any Service).self])
				\(access)final class DefaultService: Service, Instantiable {
				    \(access)init(book: Book) { self.book = book }
				    @Instantiated let book: Book
				}
				""")
			}
			let calledType = enclosingCallIsOfHolder ? "Shelf" : "Page"
			let calledLabel = calledType.lowercased()
			if fillReadsCallersToken {
				declarations.append("""
				\(callerAttribute)
				\(access)final class Screen: Instantiable {
				    \(access)init(token: \(token), \(calledLabel): \(calledType)) { self.token = token; self.\(calledLabel) = \(calledLabel) }
				    @Instantiated let token: \(token)
				    @Instantiated let \(calledLabel): \(calledType)
				}
				""")
			} else {
				declarations.append("""
				\(callerAttribute)
				\(access)final class Screen: Instantiable {
				    \(access)init(page: Page) { self.page = page }
				    @Instantiated let page: Page
				}
				""")
			}
			return "import Core\nimport Mid\nimport SafeDI\n\n" + declarations.joined(separator: "\n\n") + "\n"
		}
		let callerAttribute = switch caller {
		case .internal:
			"@Instantiable(generateMock: true)"
		case .public:
			"@Instantiable(generateMock: .public)"
		case .listed:
			"@Instantiable"
		}
		let publicMock = "@Instantiable(generateMock: .public)"
		let seamAndPublicMock = "@Instantiable(generateDependencyTree: true, generateMock: .public)"
		return GraphFuzzerCallingMockGraph(
			name: "a fill holding a builder of the enclosing called type",
			mockFiles: [
				GraphFuzzerCallingMockGraph.File(module: "Core", dependencies: [], content: core(attribute: publicMock)),
				GraphFuzzerCallingMockGraph.File(module: "Mid", dependencies: ["Core"], content: mid(attribute: publicMock)),
				GraphFuzzerCallingMockGraph.File(module: "App", dependencies: ["Core", "Mid"], content: app(callerAttribute: callerAttribute)),
			],
			twinFiles: [
				GraphFuzzerCallingMockGraph.File(module: "Core", dependencies: [], content: core(attribute: seamAndPublicMock)),
				GraphFuzzerCallingMockGraph.File(module: "Mid", dependencies: ["Core"], content: mid(attribute: seamAndPublicMock)),
				GraphFuzzerCallingMockGraph.File(module: "App", dependencies: ["Core", "Mid"], content: app(callerAttribute: "@Instantiable(generateDependencyTree: true)")),
			],
			callerTypeName: "Screen",
			callerIsPublic: caller == .public,
			mockConfiguration: caller == .listed ? "import SafeDI\n\n#SafeDIConfiguration(additionalMocksToGenerate: [\"Screen\"])\n" : nil,
			flatParameterLabels: [],
			implementationIsVisible: true,
			expectedTwinInitializerLabels: [],
			expectedPassUpLabels: [],
			expectedTwinErrorSite: nil,
			valueProbes: [deferredPlace ? deferredPlaceProbe : screenProbe],
		)
	}

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
