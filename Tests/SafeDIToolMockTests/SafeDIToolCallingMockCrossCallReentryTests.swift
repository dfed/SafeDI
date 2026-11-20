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
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let service: (__safeDI_Values) -> __safeDI_Built

		            public init(service: @escaping (__safeDI_Values) -> __safeDI_Built) {
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
		        let service: any Service = __safeDI_serviceBuilder.service(SafeDIMockScope_Service.__safeDI_Values())
		        return Page(service: service)
		    }
		}

		extension Page {
		    public enum __safeDI_Page_mock_8616590B7F80513D {}
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
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let pageBuilder: (__safeDI_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>

		            public init(pageBuilder: @escaping (__safeDI_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>) {
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
		        _ = Page.__safeDI_Page_mock_8616590B7F80513D.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
		        func __safeDI_pageBuilder() -> Page {
		            Page.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder.pageBuilder(SafeDIMockScope_Service.__safeDI_Values()))
		        }
		        let pageBuilder = Instantiator<Page>(__safeDI_pageBuilder)
		        return Book(pageBuilder: pageBuilder)
		    }
		}

		extension Book {
		    public enum __safeDI_Book_mock_0011B1D815B1ECB7 {}
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
		            _ = Page.__safeDI_Page_mock_8616590B7F80513D.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
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
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let service: (__safeDI_Values) -> __safeDI_Built

		            public init(service: @escaping (__safeDI_Values) -> __safeDI_Built) {
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
		        let service: any Service = __safeDI_serviceBuilder.service(SafeDIMockScope_Service.__safeDI_Values())
		        return Page(service: service)
		    }
		}

		extension Page {
		    public enum __safeDI_Page_mock_8616590B7F80513D {}
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
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let pageBuilder: (__safeDI_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>

		            public init(pageBuilder: @escaping (__safeDI_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>) {
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
		        _ = Page.__safeDI_Page_mock_8616590B7F80513D.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
		        func __safeDI_pageBuilder() -> Page {
		            Page.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder.pageBuilder(SafeDIMockScope_Service.__safeDI_Values()))
		        }
		        let pageBuilder = Instantiator<Page>(__safeDI_pageBuilder)
		        return Book(pageBuilder: pageBuilder)
		    }
		}

		extension Book {
		    public enum __safeDI_Book_mock_0011B1D815B1ECB7 {}
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
		            _ = Page.__safeDI_Page_mock_8616590B7F80513D.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
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
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let service: (__safeDI_Values) -> __safeDI_Built

		            public init(service: @escaping (__safeDI_Values) -> __safeDI_Built) {
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
		        let service: any Service = __safeDI_serviceBuilder.service(SafeDIMockScope_Service.__safeDI_Values())
		        return Page(service: service)
		    }
		}

		extension Page {
		    public enum __safeDI_Page_mock_8616590B7F80513D {}
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
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let pageBuilder: (__safeDI_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>

		            public init(pageBuilder: @escaping (__safeDI_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>) {
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
		        _ = Page.__safeDI_Page_mock_8616590B7F80513D.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
		        func __safeDI_pageBuilder() -> Page {
		            Page.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder.pageBuilder(SafeDIMockScope_Service.__safeDI_Values()))
		        }
		        let pageBuilder = Instantiator<Page>(__safeDI_pageBuilder)
		        return Book(pageBuilder: pageBuilder)
		    }
		}

		extension Book {
		    public enum __safeDI_Book_mock_0011B1D815B1ECB7 {}
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
		            _ = Page.__safeDI_Page_mock_8616590B7F80513D.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
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
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let service: (__safeDI_Values) -> __safeDI_Built

		            public init(service: @escaping (__safeDI_Values) -> __safeDI_Built) {
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
		        let service: any Service = __safeDI_serviceBuilder.service(SafeDIMockScope_Service.__safeDI_Values())
		        return Page(service: service)
		    }
		}

		extension Page {
		    public enum __safeDI_Page_mock_8616590B7F80513D {}
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
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
		            public let pageBuilder: @Sendable (__safeDI_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>

		            public init(pageBuilder: @escaping @Sendable (__safeDI_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>) {
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
		        _ = Page.__safeDI_Page_mock_8616590B7F80513D.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
		        @Sendable func __safeDI_pageBuilder() -> Page {
		            Page.__safeDI_mock(serviceBuilder: __safeDI_serviceSendableBuilder.pageBuilder(SafeDISendableMockScope_Service.__safeDI_Values()))
		        }
		        let pageBuilder = SendableInstantiator<Page>(__safeDI_pageBuilder)
		        return Book(pageBuilder: pageBuilder)
		    }
		}

		extension Book {
		    public enum __safeDI_Book_mock_C54DD09BF85A385B {}
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
		            _ = Page.__safeDI_Page_mock_8616590B7F80513D.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
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
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let serviceBuilder: (__safeDI_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder

		            public init(serviceBuilder: @escaping (__safeDI_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder) {
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
		        let serviceBuilder = ErasedInstantiator<Int, any Service>(__safeDI_defaultService_ServiceBuilder.serviceBuilder(SafeDIMockScope_DefaultService_Service.__safeDI_Values()))
		        return Page(serviceBuilder: serviceBuilder)
		    }
		}

		extension Page {
		    public enum __safeDI_Page_mock_5F8A188A8883BADE {}
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
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let pageBuilder: (__safeDI_Values) -> Page.SafeDIMockScope_DefaultService_Service.__safeDI_Builder<__safeDI_Built>

		            public init(pageBuilder: @escaping (__safeDI_Values) -> Page.SafeDIMockScope_DefaultService_Service.__safeDI_Builder<__safeDI_Built>) {
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
		        _ = Page.__safeDI_Page_mock_5F8A188A8883BADE.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
		        func __safeDI_pageBuilder() -> Page {
		            Page.__safeDI_mock(defaultService_ServiceBuilder: __safeDI_defaultService_ServiceBuilder.pageBuilder(SafeDIMockScope_DefaultService_Service.__safeDI_Values()))
		        }
		        let pageBuilder = Instantiator<Page>(__safeDI_pageBuilder)
		        return Book(pageBuilder: pageBuilder)
		    }
		}

		extension Book {
		    public enum __safeDI_Book_mock_8407221CFC49F8FF {}
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
		            _ = Page.__safeDI_Page_mock_5F8A188A8883BADE.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
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
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let service: (__safeDI_Values) -> __safeDI_Built

		            public init(service: @escaping (__safeDI_Values) -> __safeDI_Built) {
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
		        let service: any Service = __safeDI_serviceBuilder.service(SafeDIMockScope_Service.__safeDI_Values())
		        return Page(service: service)
		    }
		}

		extension Page {
		    public enum __safeDI_Page_mock_8616590B7F80513D {}
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
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let pageBuilder: (__safeDI_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>

		            public init(pageBuilder: @escaping (__safeDI_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>) {
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
		        _ = Page.__safeDI_Page_mock_8616590B7F80513D.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
		        func __safeDI_pageBuilder() -> Page {
		            Page.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder.pageBuilder(SafeDIMockScope_Service.__safeDI_Values()))
		        }
		        let pageBuilder = Instantiator<Page>(__safeDI_pageBuilder)
		        return Book(pageBuilder: pageBuilder)
		    }
		}

		extension Book {
		    public enum __safeDI_Book_mock_0011B1D815B1ECB7 {}
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
		            func __safeDI_serviceBuilder_Page_service(_ scope: Page.SafeDIMockScope_Service.__safeDI_Values, token: Token) -> any Service {
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
		            _ = Page.__safeDI_Page_mock_8616590B7F80513D.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
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
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let service: (__safeDI_Values) -> __safeDI_Built

		            public init(service: @escaping (__safeDI_Values) -> __safeDI_Built) {
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
		        let service: any Service = __safeDI_serviceBuilder.service(SafeDIMockScope_Service.__safeDI_Values())
		        return Page(service: service)
		    }
		}

		extension Page {
		    public enum __safeDI_Page_mock_8616590B7F80513D {}
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
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let pageBuilder: (__safeDI_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>

		            public init(pageBuilder: @escaping (__safeDI_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>) {
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
		        _ = Page.__safeDI_Page_mock_8616590B7F80513D.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
		        func __safeDI_pageBuilder() -> Page {
		            Page.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder.pageBuilder(SafeDIMockScope_Service.__safeDI_Values()))
		        }
		        let pageBuilder = Instantiator<Page>(__safeDI_pageBuilder)
		        return Book(pageBuilder: pageBuilder)
		    }
		}

		extension Book {
		    public enum __safeDI_Book_mock_0011B1D815B1ECB7 {}
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
		            func __safeDI_serviceBuilder_Page_service(_ scope: Page.SafeDIMockScope_Service.__safeDI_Values, token: Token) -> any Service {
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
		            _ = Page.__safeDI_Page_mock_8616590B7F80513D.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
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
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let service: (__safeDI_Values) -> __safeDI_Built

		            public init(service: @escaping (__safeDI_Values) -> __safeDI_Built) {
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
		        let service: any Service = __safeDI_serviceBuilder.service(SafeDIMockScope_Service.__safeDI_Values())
		        return Page(service: service)
		    }
		}

		extension Page {
		    public enum __safeDI_Page_mock_8616590B7F80513D {}
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
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let pageBuilder: (__safeDI_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>

		            public init(pageBuilder: @escaping (__safeDI_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>) {
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
		        _ = Page.__safeDI_Page_mock_8616590B7F80513D.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
		        func __safeDI_pageBuilder() -> Page {
		            Page.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder.pageBuilder(SafeDIMockScope_Service.__safeDI_Values()))
		        }
		        let pageBuilder = Instantiator<Page>(__safeDI_pageBuilder)
		        return Book(pageBuilder: pageBuilder)
		    }
		}

		extension Book {
		    public enum __safeDI_Book_mock_0011B1D815B1ECB7 {}
		}
		#endif

		#if DEBUG
		extension Shelf {
		    nonisolated public enum SafeDIMockScope_Service {
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let pageBuilder: (__safeDI_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>

		            public init(pageBuilder: @escaping (__safeDI_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>) {
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
		        _ = Page.__safeDI_Page_mock_8616590B7F80513D.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
		        func __safeDI_pageBuilder() -> Page {
		            Page.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder.pageBuilder(SafeDIMockScope_Service.__safeDI_Values()))
		        }
		        let pageBuilder = Instantiator<Page>(__safeDI_pageBuilder)
		        return Shelf(pageBuilder: pageBuilder)
		    }
		}

		extension Shelf {
		    public enum __safeDI_Shelf_mock_F175C8C93C69D9E3 {}
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
		            func __safeDI_serviceBuilder_Page_service(_ scope: Page.SafeDIMockScope_Service.__safeDI_Values, token: Token) -> any Service {
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
		            _ = Shelf.__safeDI_Shelf_mock_F175C8C93C69D9E3.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Shelf", declaringModule: "Mid"))
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
	mutating func generate_reentersEnclosingCallsLevelBeneathRootWithNearestValue_whenTypeBetweenHoldsBuilderOfFilledType(caller: GraphFuzzerCallingMockCell.Caller) async throws {
		// The graph above, with `Middle` holding `Page` in an `Instantiator` itself, in place of `Book`: the call of `Page` inside
		// the fill re-enters `Page`’s level function beneath the call of `Shelf`’s root with `Middle`’s `token`, so the
		// `DefaultService` that `Middle`’s builder builds again reads it, as inline reads it.
		let graph = Self.graph(caller: caller, builder: "Instantiator", deferredPlace: false, fillReadsCallersToken: true, typeBetweenDeclaresToken: true, enclosingCallIsOfHolder: true, middleHoldsFilledType: true)
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
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let service: (__safeDI_Values) -> __safeDI_Built

		            public init(service: @escaping (__safeDI_Values) -> __safeDI_Built) {
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
		        let service: any Service = __safeDI_serviceBuilder.service(SafeDIMockScope_Service.__safeDI_Values())
		        return Page(service: service)
		    }
		}

		extension Page {
		    public enum __safeDI_Page_mock_8616590B7F80513D {}
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
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let pageBuilder: (__safeDI_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>

		            public init(pageBuilder: @escaping (__safeDI_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>) {
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
		        _ = Page.__safeDI_Page_mock_8616590B7F80513D.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
		        func __safeDI_pageBuilder() -> Page {
		            Page.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder.pageBuilder(SafeDIMockScope_Service.__safeDI_Values()))
		        }
		        let pageBuilder = Instantiator<Page>(__safeDI_pageBuilder)
		        return Book(pageBuilder: pageBuilder)
		    }
		}

		extension Book {
		    public enum __safeDI_Book_mock_0011B1D815B1ECB7 {}
		}
		#endif

		#if DEBUG
		extension Shelf {
		    nonisolated public enum SafeDIMockScope_Service {
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let pageBuilder: (__safeDI_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>

		            public init(pageBuilder: @escaping (__safeDI_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>) {
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
		        _ = Page.__safeDI_Page_mock_8616590B7F80513D.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
		        func __safeDI_pageBuilder() -> Page {
		            Page.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder.pageBuilder(SafeDIMockScope_Service.__safeDI_Values()))
		        }
		        let pageBuilder = Instantiator<Page>(__safeDI_pageBuilder)
		        return Shelf(pageBuilder: pageBuilder)
		    }
		}

		extension Shelf {
		    public enum __safeDI_Shelf_mock_F175C8C93C69D9E3 {}
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
		            func __safeDI_serviceBuilder_Page_service(_ scope: Page.SafeDIMockScope_Service.__safeDI_Values, token: Token) -> any Service {
		                func __safeDI_service() -> DefaultService {
		                    func __safeDI_middle() -> Middle {
		                        let token = Token()
		                        func __safeDI_pageBuilder() -> Page {
		                            Page.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder_Page(token: token))
		                        }
		                        let pageBuilder = Instantiator<Page>(__safeDI_pageBuilder)
		                        return Middle(token: token, pageBuilder: pageBuilder)
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
		            _ = Shelf.__safeDI_Shelf_mock_F175C8C93C69D9E3.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Shelf", declaringModule: "Mid"))
		            return Shelf.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder_Shelf(token: token), safeDIOverrides: safeDIOverrides.shelf)
		        }
		        let shelf: Shelf = __safeDI_shelf()
		        return Screen(token: token, shelf: shelf)
		    }
		}
		\(spelling.guardExtension)#endif
		"""])
		try await expectCompilesAndBuildsInlineValues(of: graph, output: output, modules: modules, probes: [Self.nearestTokenProbe(calledLabel: "shelf", middleHoldsFilledType: true)])
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"), arguments: GraphFuzzerCallingMockCell.Caller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reentersEnclosingCallsRootLevelFromLevelBeneathCalledMocksRoot_whenCalledMockBuildsTypeHoldingBuilderOfFilledType(caller: GraphFuzzerCallingMockCell.Caller) async throws {
		// The first graph, with `Book` holding `Binder` in an `Instantiator`, and `Binder` holding `Page`’s: the call of `Book`
		// inside the fill declares `Binder`’s level function beneath its root, whose case for `pageBuilder` re-enters the root
		// level function of the call of `Page` that encloses it.
		let graph = Self.graph(caller: caller, builder: "Instantiator", deferredPlace: false, calledMockHoldsBuilderBeneathRoot: true)
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
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let service: (__safeDI_Values) -> __safeDI_Built

		            public init(service: @escaping (__safeDI_Values) -> __safeDI_Built) {
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
		        let service: any Service = __safeDI_serviceBuilder.service(SafeDIMockScope_Service.__safeDI_Values())
		        return Page(service: service)
		    }
		}

		extension Page {
		    public enum __safeDI_Page_mock_8616590B7F80513D {}
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
		        nonisolated public struct __safeDI_Values: Sendable {}

		        nonisolated public enum Binder_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let pageBuilder: (__safeDI_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>

		                public init(pageBuilder: @escaping (__safeDI_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>) {
		                    self.pageBuilder = pageBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.pageBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let binderBuilder: (__safeDI_Values) -> SafeDIMockScope_Service.Binder_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(binderBuilder: @escaping (__safeDI_Values) -> SafeDIMockScope_Service.Binder_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.binderBuilder = binderBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.binderBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            binderBuilder: __safeDI_Mid_Binder_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                binderBuilder: binderBuilder
		            )
		        }

		        public var binderBuilder: __safeDI_Mid_Binder_MockConfiguration { __safeDI_storage.binderBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                binderBuilder: __safeDI_Mid_Binder_MockConfiguration
		            ) {
		                self.binderBuilder = binderBuilder
		            }

		            let binderBuilder: __safeDI_Mid_Binder_MockConfiguration
		        }
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
		        let __safeDI_serviceBuilder_binderBuilder = __safeDI_serviceBuilder.binderBuilder(SafeDIMockScope_Service.__safeDI_Values())
		        func __safeDI_binderBuilder() -> Binder {
		            _ = Page.__safeDI_Page_mock_8616590B7F80513D.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
		            func __safeDI_pageBuilder() -> Page {
		                Page.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder_binderBuilder.pageBuilder(SafeDIMockScope_Service.Binder_Scope.__safeDI_Values()))
		            }
		            let pageBuilder = Instantiator<Page>(__safeDI_pageBuilder)
		            return Binder.__safeDI_init(pageBuilder: pageBuilder, safeDIBuilder: safeDIOverrides.binderBuilder.safeDIBuilder)
		        }
		        let binderBuilder = Instantiator<Binder>(__safeDI_binderBuilder)
		        return Book(binderBuilder: binderBuilder)
		    }
		}

		extension Book {
		    public enum __safeDI_Book_mock_446B5EA517A27896 {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `Binder` is constructed within the public mock trees of module `Mid`.
		nonisolated public struct __safeDI_Mid_Binder_MockConfiguration {
		    public init(
		        _ safeDIBuilder: ((Instantiator<Page>) -> Binder)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    /// Overrides how `Binder` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((Instantiator<Page>) -> Binder)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            safeDIBuilder: ((Instantiator<Page>) -> Binder)?
		        ) {
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let safeDIBuilder: ((Instantiator<Page>) -> Binder)?
		    }
		}

		extension Binder {
		    static func __safeDI_init(pageBuilder: Instantiator<Page>, safeDIBuilder: ((Instantiator<Page>) -> Binder)?) -> Binder {
		        if let safeDIBuilder { safeDIBuilder(pageBuilder) } else { Binder(pageBuilder: pageBuilder) }
		    }
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
		            page: ((@escaping () -> any Service) -> Page)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                page: page
		            )
		        }

		        \(spelling.member)var page: ((@escaping () -> any Service) -> Page)? { __safeDI_storage.page }

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

		    \(spelling.member)static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_page() -> Page {
		            func __safeDI_serviceBuilder_Page_service() -> any Service {
		                func __safeDI_service() -> DefaultService {
		                    func __safeDI_book() -> Book {
		                        func __safeDI_serviceBuilder_Book() -> Book.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
		                            .init(binderBuilder: { _ in __safeDI_serviceBuilder_Book_Binder_Scope() })
		                        }
		                        func __safeDI_serviceBuilder_Book_Binder_Scope() -> Book.SafeDIMockScope_Service.Binder_Scope.__safeDI_Builder<any Service> {
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
		            _ = Page.__safeDI_Page_mock_8616590B7F80513D.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
		            return if let safeDIBuilder = safeDIOverrides.page { safeDIBuilder({ __safeDI_serviceBuilder_Page_service() }) } else { Page.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder_Page()) }
		        }
		        let page: Page = __safeDI_page()
		        return Screen(page: page)
		    }
		}
		\(spelling.guardExtension)#endif
		"""])
		try await expectCompilesAndBuildsInlineValues(of: graph, output: output, modules: modules, probes: [Self.pageBinderBuildsProbe])
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
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let service: (__safeDI_Values) -> __safeDI_Built

		            public init(service: @escaping (__safeDI_Values) -> __safeDI_Built) {
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
		        let service: any Service = __safeDI_serviceBuilder.service(SafeDIMockScope_Service.__safeDI_Values())
		        return Page(service: service)
		    }
		}

		extension Page {
		    public enum __safeDI_Page_mock_8616590B7F80513D {}
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
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let pageBuilder: (__safeDI_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>

		            public init(pageBuilder: @escaping (__safeDI_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>) {
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
		        _ = Page.__safeDI_Page_mock_8616590B7F80513D.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
		        func __safeDI_pageBuilder() -> Page {
		            Page.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder.pageBuilder(SafeDIMockScope_Service.__safeDI_Values()))
		        }
		        let pageBuilder = Instantiator<Page>(__safeDI_pageBuilder)
		        return Book(pageBuilder: pageBuilder)
		    }
		}

		extension Book {
		    public enum __safeDI_Book_mock_0011B1D815B1ECB7 {}
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
		            func __safeDI_serviceBuilder_Page_service(_ scope: Page.SafeDIMockScope_Service.__safeDI_Values, token: LazilyInstantiated<Token>) -> any Service {
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
		            _ = Page.__safeDI_Page_mock_8616590B7F80513D.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
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

	@Test(arguments: GraphFuzzerCallingMockCell.Caller.allCases, HiddenToken.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsTwinsError_whenCalledMockDeclaresValueFillReadsOnItsWayToBuilderOfFilledType(caller: GraphFuzzerCallingMockCell.Caller, hiddenToken: HiddenToken) async {
		// `DefaultService` receives `token`, and the `Book` it builds declares one of its own on the way to its builder of
		// `Page`, or a type `Book` builds does, or `Library`, a public mock of a fourth module that builds `Book`. The call of
		// `Book` inside the fill re-enters the level function of the enclosing call of `Page`, which can hand the re-entered
		// fill only what the caller’s scope holds, while inline the `DefaultService` that `Book`’s builder builds reads the
		// declaration of the called mocks’ side: the mock reports the twin’s error, where it would otherwise build another
		// value than inline.
		let (appLine, declaringType, declaringModule, declarationLine, calledType, calledTypeModule) = switch hiddenToken {
		case .calledMockBeforeBuilder:
			(15, "Book", "Mid", 7, "Book", "Mid")
		case .calledMockAfterBuilder:
			(15, "Book", "Mid", 8, "Book", "Mid")
		case .typeInsideCalledMock:
			(15, "Inner", "Mid", 13, "Book", "Mid")
		case .calledMockOfFourthModule:
			(16, "Library", "Top", 8, "Library", "Top")
		}
		let boundOnPath = declaringType == calledType
			? "which `\(calledType)` builds where it calls `Page`"
			: "which `\(declaringType)` builds on the path where `\(calledType)` calls `Page`"
		let handed = declaringType == calledType ? "`\(calledType)`’s values" : "that value"
		let diagnostics = { (fixtures: [String: FixturePaths]) in
			"""
			\(fixtures["App"]!["AppTypes.swift"]):\(appLine):5: error: `DefaultService` receives `token: Token`, \(boundOnPath), but `\(calledType)` passes the builder for `Page`’s `service: any Service` (`service` of `serviceBuilder`) on from its own caller, which cannot hand it \(handed). Declare `@Received let token: Token` on `Page`, so SafeDI hands it to the builder, or declare an @Instantiable type that fulfills `Service` in module `\(calledTypeModule)` or a module it lists among its SafeDI dependencies, so `\(calledType)` fills the builder itself.
			\(fixtures[declaringModule]!["\(declaringModule)Types.swift"]):\(declarationLine):5: note: `\(declaringType)` declares `token: Token` here.
			"""
		}
		let graph = Self.hiddenTokenGraph(caller: caller, hiddenToken: hiddenToken)
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: diagnostics) {
			try await executeSafeDIToolMultiModuleTest(modules: graph.modules(.mock), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: diagnostics) {
			try await executeSafeDIToolMultiModuleTest(modules: graph.modules(.twin), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"), arguments: GraphFuzzerCallingMockCell.Caller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reentersEnclosingCallsRootLevelWithCalledMocksValue_whenFilledTypeReceivesValueCalledMockDeclares(caller: GraphFuzzerCallingMockCell.Caller) async throws {
		// The error above’s first remedy: `Page` receives `token`, so `Book`’s values struct for its builder of `Page` carries
		// `Book`’s, which the re-entered fill reads from its case’s payload, as inline reads `Book`’s.
		let graph = Self.hiddenTokenGraph(caller: caller, hiddenToken: .calledMockBeforeBuilder, pageReceivesToken: true)
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
		                self.service = { _ in __safeDI_builder() }
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            token: (() -> Token)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                token: token
		            )
		        }

		        public var token: (() -> Token)? { __safeDI_storage.token }

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

		    public static func mock(
		        serviceBuilder: @escaping () -> any Service,
		        token: Token? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Page {
		        Page.__safeDI_mock(serviceBuilder: .init(__safeDI_noScope: serviceBuilder), token: token, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        serviceBuilder __safeDI_serviceBuilder: Page.SafeDIMockScope_Service.__safeDI_Builder<any Service>,
		        token: Token? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Page {
		        let token = if let token { token } else if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder() } else { Token() }
		        let service: any Service = __safeDI_serviceBuilder.service(SafeDIMockScope_Service.service_Values(token: token))
		        return Page(token: token, service: service)
		    }
		}

		extension Page {
		    public enum __safeDI_Page_mock_C5813F6661CC087D {}
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
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let pageBuilder: (__safeDI_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>

		            public init(pageBuilder: @escaping (__safeDI_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>) {
		                self.pageBuilder = pageBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.pageBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            token: (() -> Token)? = nil,
		            pageBuilder: Page.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                token: token,
		                pageBuilder: pageBuilder
		            )
		        }

		        public var token: (() -> Token)? { __safeDI_storage.token }
		        public var pageBuilder: Page.SafeDIOverrides { __safeDI_storage.pageBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                token: (() -> Token)?,
		                pageBuilder: Page.SafeDIOverrides
		            ) {
		                self.token = token
		                self.pageBuilder = pageBuilder
		            }

		            let token: (() -> Token)?
		            let pageBuilder: Page.SafeDIOverrides
		        }
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
		        let token = if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder() } else { Token() }
		        _ = Page.__safeDI_Page_mock_C5813F6661CC087D.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
		        func __safeDI_pageBuilder() -> Page {
		            Page.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder.pageBuilder(SafeDIMockScope_Service.__safeDI_Values()), token: token, safeDIOverrides: safeDIOverrides.pageBuilder)
		        }
		        let pageBuilder = Instantiator<Page>(__safeDI_pageBuilder)
		        return Book(token: token, pageBuilder: pageBuilder)
		    }
		}

		extension Book {
		    public enum __safeDI_Book_mock_6DCCA60482490FFF {}
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
		            page: Page.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                token: token,
		                page: page
		            )
		        }

		        \(spelling.member)var token: (() -> Token)? { __safeDI_storage.token }
		        \(spelling.member)var page: Page.SafeDIOverrides { __safeDI_storage.page }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                token: (() -> Token)?,
		                page: Page.SafeDIOverrides
		            ) {
		                self.token = token
		                self.page = page
		            }

		            let token: (() -> Token)?
		            let page: Page.SafeDIOverrides
		        }
		    }

		    \(spelling.member)static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let token = if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder() } else { Token() }
		        func __safeDI_page() -> Page {
		            func __safeDI_serviceBuilder_Page_service(_ scope: Page.SafeDIMockScope_Service.service_Values) -> any Service {
		                let token = scope.token
		                func __safeDI_service() -> DefaultService {
		                    func __safeDI_book() -> Book {
		                        func __safeDI_serviceBuilder_Book() -> Book.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
		                            .init(pageBuilder: { _ in __safeDI_serviceBuilder_Page() })
		                        }
		                        return Book.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder_Book())
		                    }
		                    let book: Book = __safeDI_book()
		                    return DefaultService(token: token, book: book)
		                }
		                let service: any Service = __safeDI_service()
		                return service
		            }
		            func __safeDI_serviceBuilder_Page() -> Page.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
		                .init(service: { scope in __safeDI_serviceBuilder_Page_service(scope) })
		            }
		            _ = Page.__safeDI_Page_mock_C5813F6661CC087D.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Page", declaringModule: "Core"))
		            return Page.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder_Page(), token: token, safeDIOverrides: safeDIOverrides.page)
		        }
		        let page: Page = __safeDI_page()
		        return Screen(token: token, page: page)
		    }
		}
		\(spelling.guardExtension)#endif
		"""])
		try await expectCompilesAndBuildsInlineValues(of: graph, output: output, modules: modules, probes: [Self.calledMocksTokenProbe])
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

	/// What a cell whose fill reaches `Book` through `Middle`, or, where `middleHoldsFilledType`, `Middle`’s own builder of
	/// `Page`, compares: whether the `DefaultService` that builder builds again reads `Middle`’s `token`, the declaration
	/// nearest it, and whether it reads `Screen`’s.
	private static func nearestTokenProbe(calledLabel: String, middleHoldsFilledType: Bool = false) -> DifferentialValueProbe {
		let read = { (screen: String) in
			"{ let screen = \(screen); let service = screen.\(calledLabel)\(calledLabel == "shelf" ? ".pageBuilder.instantiate()" : "").service as! App.DefaultService; let inner = service.middle\(middleHoldsFilledType ? "" : ".book").pageBuilder.instantiate().service as! App.DefaultService; return (inner.token === service.middle.token, inner.token === screen.token) }()"
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

	/// What the cell whose `Page` receives `token` compares: whether the `DefaultService` that `Book`’s builder builds reads
	/// `Book`’s `token`, the declaration nearest it, and whether it reads `Screen`’s.
	private static let calledMocksTokenProbe = {
		let read = { (screen: String) in
			"{ let screen = \(screen); let service = screen.page.service as! App.DefaultService; let inner = service.book.pageBuilder.instantiate().service as! App.DefaultService; return (inner.token === service.book.token, inner.token === screen.token) }()"
		}
		return DifferentialValueProbe(name: "the token the re-entered fill reads", expression: read("App.Screen.mock()"), knownRightExpression: read("App.Screen()"))
	}()

	/// What the cell whose `Book` holds `Page`’s builder inside `Binder` compares: `Screen`, and the `Page` that builder
	/// builds, whose fill builds `Book` again.
	private static let pageBinderBuildsProbe = {
		let read = { (screen: String) in
			"{ let screen = \(screen); let service = screen.page.service as! App.DefaultService; return (screen, service.book.binderBuilder.instantiate().pageBuilder.instantiate()) }()"
		}
		return DifferentialValueProbe(name: "(Screen, the Page Binder builds)", expression: read("App.Screen.mock()"), knownRightExpression: read("App.Screen()"))
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
	/// `Instantiator`, in place of `Page`; where `middleHoldsFilledType`, `Middle` holds `Page` in an `Instantiator` itself,
	/// in place of `Book`; where `calledMockHoldsBuilderBeneathRoot`, `Book` holds, in an `Instantiator`, `Binder`, a plain
	/// type of `Mid` that holds `Page` in the `builder`, so `Page`’s builder is on a level beneath `Book`’s root. The called
	/// types’ initializers are internal, so `Screen`’s mock calls `Page`’s, or `Shelf`’s,
	/// public mock, and the fill calls `Book`’s, or `Page`’s. The calling mock’s form declares the called types public
	/// mocks only; the twin declares them seams that keep their public mocks.
	private static func graph(
		caller: GraphFuzzerCallingMockCell.Caller,
		builder: String,
		deferredPlace: Bool,
		fillReadsCallersToken: Bool = false,
		token: String = "Token",
		typeBetweenDeclaresToken: Bool = false,
		enclosingCallIsOfHolder: Bool = false,
		middleHoldsFilledType: Bool = false,
		calledMockHoldsBuilderBeneathRoot: Bool = false,
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
			if calledMockHoldsBuilderBeneathRoot {
				return """
				import Core
				import SafeDI

				\(attribute)
				public final class Book: Instantiable {
				    init(binderBuilder: Instantiator<Binder>) { self.binderBuilder = binderBuilder }
				    @Instantiated public let binderBuilder: Instantiator<Binder>
				}

				@Instantiable
				public final class Binder: Instantiable {
				    init(pageBuilder: \(builder)<Page>) { self.pageBuilder = pageBuilder }
				    @Instantiated public let pageBuilder: \(builder)<Page>
				}
				\(shelf)
				"""
			} else {
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
		}
		func app(callerAttribute: String) -> String {
			let access = caller == .public ? "public " : ""
			let middleProperties = if middleHoldsFilledType {
				"""
				    \(access)init(token: \(token), pageBuilder: Instantiator<Page>) { self.token = token; self.pageBuilder = pageBuilder }
				    @Instantiated let token: \(token)
				    @Instantiated let pageBuilder: Instantiator<Page>
				"""
			} else {
				"""
				    \(access)init(token: \(token), book: Book) { self.token = token; self.book = book }
				    @Instantiated let token: \(token)
				    @Instantiated let book: Book
				"""
			}
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
				\(middleProperties)
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

	/// Where a type on the called mocks’ side declares the `token` the fill reads, between the root of the mock the fill
	/// calls and the builder of `Page` that mock holds, so no scope of the caller holds it.
	enum HiddenToken: CaseIterable {
		/// `Book` declares `token` before its builder of `Page`.
		case calledMockBeforeBuilder
		/// `Book` declares `token` after its builder of `Page`.
		case calledMockAfterBuilder
		/// `Book` builds `Inner`, which declares `token` beside a builder of `Page`.
		case typeInsideCalledMock
		/// The fill builds `Library`, a public mock of a fourth module `Top` that declares `token` and builds `Book`.
		case calledMockOfFourthModule
	}

	/// The graph: module `Core` declares `Token` and `Page`, whose place of `Service` no type `Core` sees fulfills, and
	/// which, where `pageReceivesToken`, receives `token`; module `Mid` declares `Book`, which holds `Page` in an
	/// `Instantiator`; and module `App` declares the caller `Screen`, which builds `token` and `Page`, and
	/// `DefaultService`, which fills `Page`’s place, receives `token`, and builds `Book`, or, for
	/// `.calledMockOfFourthModule`, `Library`. `hiddenToken` says where the called mocks’ side declares a `token` of its
	/// own. The calling mock’s form declares the called types public mocks only; the twin declares them seams that keep
	/// their public mocks.
	private static func hiddenTokenGraph(caller: GraphFuzzerCallingMockCell.Caller, hiddenToken: HiddenToken, pageReceivesToken: Bool = false) -> GraphFuzzerCallingMockGraph {
		func core(attribute: String) -> String {
			let page = if pageReceivesToken {
				"""
				    init(token: Token, service: any Service) { self.token = token; self.service = service }
				    @Received public let token: Token
				    @Instantiated public let service: any Service
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

			@Instantiable
			public final class Token: Instantiable {
			    public init() {}
			}

			\(attribute)
			public final class Page: Instantiable {
			\(page)
			}

			"""
		}
		func mid(attribute: String) -> String {
			let book = switch hiddenToken {
			case .calledMockBeforeBuilder:
				"""
				    init(token: Token, pageBuilder: Instantiator<Page>) { self.token = token; self.pageBuilder = pageBuilder }
				    @Instantiated public let token: Token
				    @Instantiated public let pageBuilder: Instantiator<Page>
				}
				"""
			case .calledMockAfterBuilder:
				"""
				    init(pageBuilder: Instantiator<Page>, token: Token) { self.pageBuilder = pageBuilder; self.token = token }
				    @Instantiated public let pageBuilder: Instantiator<Page>
				    @Instantiated public let token: Token
				}
				"""
			case .typeInsideCalledMock:
				"""
				    init(inner: Inner) { self.inner = inner }
				    @Instantiated public let inner: Inner
				}

				@Instantiable
				public final class Inner: Instantiable {
				    public init(token: Token, pageBuilder: Instantiator<Page>) { self.token = token; self.pageBuilder = pageBuilder }
				    @Instantiated public let token: Token
				    @Instantiated public let pageBuilder: Instantiator<Page>
				}
				"""
			case .calledMockOfFourthModule:
				"""
				    init(pageBuilder: Instantiator<Page>) { self.pageBuilder = pageBuilder }
				    @Instantiated public let pageBuilder: Instantiator<Page>
				}
				"""
			}
			return """
			import Core
			import SafeDI

			\(attribute)
			public final class Book: Instantiable {
			\(book)

			"""
		}
		func top(attribute: String) -> String {
			"""
			import Core
			import Mid
			import SafeDI

			\(attribute)
			public final class Library: Instantiable {
			    init(token: Token, book: Book) { self.token = token; self.book = book }
			    @Instantiated public let token: Token
			    @Instantiated public let book: Book
			}

			"""
		}
		func app(callerAttribute: String) -> String {
			let access = caller == .public ? "public " : ""
			let (builtLabel, builtType) = hiddenToken == .calledMockOfFourthModule ? ("library", "Library") : ("book", "Book")
			var imports = "import Core\nimport Mid\n"
			if hiddenToken == .calledMockOfFourthModule {
				imports += "import Top\n"
			}
			return imports + """
			import SafeDI

			\(callerAttribute)
			\(access)final class Screen: Instantiable {
			    \(access)init(token: Token, page: Page) { self.token = token; self.page = page }
			    @Instantiated let token: Token
			    @Instantiated let page: Page
			}

			@Instantiable(fulfillingAdditionalTypes: [(any Service).self])
			\(access)final class DefaultService: Service, Instantiable {
			    \(access)init(token: Token, \(builtLabel): \(builtType)) { self.token = token; self.\(builtLabel) = \(builtLabel) }
			    @Received let token: Token
			    @Instantiated let \(builtLabel): \(builtType)
			}

			"""
		}
		func files(calledTypeAttribute: String, callerAttribute: String) -> [GraphFuzzerCallingMockGraph.File] {
			var files = [
				GraphFuzzerCallingMockGraph.File(module: "Core", dependencies: [], content: core(attribute: calledTypeAttribute)),
				GraphFuzzerCallingMockGraph.File(module: "Mid", dependencies: ["Core"], content: mid(attribute: calledTypeAttribute)),
			]
			if hiddenToken == .calledMockOfFourthModule {
				files.append(GraphFuzzerCallingMockGraph.File(module: "Top", dependencies: ["Core", "Mid"], content: top(attribute: calledTypeAttribute)))
				files.append(GraphFuzzerCallingMockGraph.File(module: "App", dependencies: ["Core", "Mid", "Top"], content: app(callerAttribute: callerAttribute)))
			} else {
				files.append(GraphFuzzerCallingMockGraph.File(module: "App", dependencies: ["Core", "Mid"], content: app(callerAttribute: callerAttribute)))
			}
			return files
		}
		let callerAttribute = switch caller {
		case .internal:
			"@Instantiable(generateMock: true)"
		case .public:
			"@Instantiable(generateMock: .public)"
		case .listed:
			"@Instantiable"
		}
		return GraphFuzzerCallingMockGraph(
			name: "a fill holding a builder of the enclosing called type behind a declaration of the called mocks’ side",
			mockFiles: files(calledTypeAttribute: "@Instantiable(generateMock: .public)", callerAttribute: callerAttribute),
			twinFiles: files(calledTypeAttribute: "@Instantiable(generateDependencyTree: true, generateMock: .public)", callerAttribute: "@Instantiable(generateDependencyTree: true)"),
			callerTypeName: "Screen",
			callerIsPublic: caller == .public,
			mockConfiguration: caller == .listed ? "import SafeDI\n\n#SafeDIConfiguration(additionalMocksToGenerate: [\"Screen\"])\n" : nil,
			flatParameterLabels: [],
			implementationIsVisible: true,
			expectedTwinInitializerLabels: [],
			expectedPassUpLabels: [],
			expectedTwinErrorSite: nil,
			valueProbes: [screenProbe],
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
