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

/// A lazily instantiated value that `Outer`, a seam, declares, and that `Inner`, a seam it calls, defers, read in a fill of
/// `Inner`'s place by a type of a module above both.
///
/// Where the filling module is a seam's, `Top`'s, and the fill's tree reads the value and its wrapper, the memo of `Inner`'s
/// deferred parameter that the fill binds serves the wrapper's read too, as validation lets it: `Top` takes no parameter
/// for it, so a caller of `Top` passes nothing it does not have.
struct SafeDIToolSeamCarriedWrapperReadTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: A seam's fill whose tree reads the value and the wrapper of a memo it binds

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_seamTakesNoParameterForWrapperItsFillsMemoServes_whenFillReadsSendableValueAndWrapper() async throws {
		let modules = Self.fillReadingValueAndWrapperModules()
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Session)
		import Session
		#endif

		extension Top {
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public convenience init() {
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_CDEA8B3F958E03B1.self // If this line does not compile, compile the code SafeDI generates for module Session into Session: under Bazel, add Session’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_serviceBuilder_Inner_service(_ scope: Inner.SafeDIScope_Service.service_Values) -> any Service {
		                let token = scope.__safeDI_token
		                func __safeDI_service() -> ServiceImpl {
		                    let wrapperReader = WrapperReader(token: token)
		                    return ServiceImpl(token: token.instance, wrapperReader: wrapperReader)
		                }
		                let service: any Service = __safeDI_service()
		                return service
		            }
		            func __safeDI_serviceBuilder_Outer() -> Outer.SafeDIScope_Service.__safeDI_Builder<any Service> {
		                .init(inner: { _ in __safeDI_serviceBuilder_Inner() })
		            }
		            func __safeDI_serviceBuilder_Inner() -> Inner.SafeDIScope_Service.__safeDI_Builder<any Service> {
		                .init(service: { scope in __safeDI_serviceBuilder_Inner_service(scope) })
		            }
		            return Outer(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Outer())
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(outer: outer)
		    }
		}

		extension Top {
		    public enum __safeDI_Top_CBF29CE484222325 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Session)
		import Session
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_top() -> Top {
		            _ = Top.__safeDI_Top_CBF29CE484222325.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Top()
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}
		"""])
		try await expectValues(of: output, modules: modules, equalThoseOf: Self.oneModule(modules), probe: Self.leafBesideRootProbe(path: "root.top.outer.inner"))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_seamTakesNoParameterForWrapperItsFillsMemoServes_whenSwiftPackagePluginGeneratesFillingSeam() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.fillReadingValueAndWrapperModules(), integration: .swiftPackagePlugin, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["WrapperReader+SafeDI.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Session)
		import Session
		#endif

		extension Top {
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public convenience init() {
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_CDEA8B3F958E03B1.self // If this line does not compile, add the SafeDI plugin to the target that declares Outer.
		            func __safeDI_serviceBuilder_Inner_service(_ scope: Inner.SafeDIScope_Service.service_Values) -> any Service {
		                let token = scope.__safeDI_token
		                func __safeDI_service() -> ServiceImpl {
		                    let wrapperReader = WrapperReader(token: token)
		                    return ServiceImpl(token: token.instance, wrapperReader: wrapperReader)
		                }
		                let service: any Service = __safeDI_service()
		                return service
		            }
		            func __safeDI_serviceBuilder_Outer() -> Outer.SafeDIScope_Service.__safeDI_Builder<any Service> {
		                .init(inner: { _ in __safeDI_serviceBuilder_Inner() })
		            }
		            func __safeDI_serviceBuilder_Inner() -> Inner.SafeDIScope_Service.__safeDI_Builder<any Service> {
		                .init(service: { scope in __safeDI_serviceBuilder_Inner_service(scope) })
		            }
		            return Outer(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Outer())
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(outer: outer)
		    }
		}

		extension Top {
		    public enum __safeDI_Top_CBF29CE484222325 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["Root+SafeDI.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Session)
		import Session
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_top() -> Top {
		            _ = Top.__safeDI_Top_CBF29CE484222325.self // If this line does not compile, add the SafeDI plugin to the target that declares Top.
		            return Top()
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_seamTakesNoParameterForWrapperItsFillsMemoServes_whenFillReadsPlainValueAndWrapper() async throws {
		let modules = Self.fillReadingValueAndWrapperModules(isSendable: false)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Session)
		import Session
		#endif

		extension Top {
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public convenience init() {
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_497D86E3662145E7.self // If this line does not compile, compile the code SafeDI generates for module Session into Session: under Bazel, add Session’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_serviceBuilder_Inner_service(_ scope: Inner.SafeDIScope_Service.service_Values) -> any Service {
		                let token = scope.__safeDI_token
		                func __safeDI_service() -> ServiceImpl {
		                    let wrapperReader = WrapperReader(token: token)
		                    return ServiceImpl(token: token.instance, wrapperReader: wrapperReader)
		                }
		                let service: any Service = __safeDI_service()
		                return service
		            }
		            func __safeDI_serviceBuilder_Outer() -> Outer.SafeDIScope_Service.__safeDI_Builder<any Service> {
		                .init(inner: { _ in __safeDI_serviceBuilder_Inner() })
		            }
		            func __safeDI_serviceBuilder_Inner() -> Inner.SafeDIScope_Service.__safeDI_Builder<any Service> {
		                .init(service: { scope in __safeDI_serviceBuilder_Inner_service(scope) })
		            }
		            return Outer(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Outer())
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(outer: outer)
		    }
		}

		extension Top {
		    public enum __safeDI_Top_CBF29CE484222325 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Session)
		import Session
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_top() -> Top {
		            _ = Top.__safeDI_Top_CBF29CE484222325.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Top()
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}
		"""])
		try await expectValues(of: output, modules: modules, equalThoseOf: Self.oneModule(modules), probe: Self.leafBesideRootProbe(path: "root.top.outer.inner"))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_seamTakesNoParameterForWrapperItsFillsMemoServes_whenSeamAboveCallsFillingSeam() async throws {
		let modules = Self.fillReadingValueAndWrapperModules(shellCallsTop: true)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Shell"]?.generatedFiles == ["Shell.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Session)
		import Session
		#endif

		extension Shell {
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public convenience init() {
		        func __safeDI_top() -> Top {
		            _ = Top.__safeDI_Top_CBF29CE484222325.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Top()
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}

		extension Shell {
		    public enum __safeDI_Shell_CBF29CE484222325 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Session)
		import Session
		#endif
		#if canImport(Shell)
		import Shell
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_shell() -> Shell {
		            _ = Shell.__safeDI_Shell_CBF29CE484222325.self // If this line does not compile, compile the code SafeDI generates for module Shell into Shell: under Bazel, add Shell’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Shell()
		        }
		        let shell: Shell = __safeDI_shell()
		        self.init(shell: shell)
		    }
		}
		"""])
		try await expectValues(of: output, modules: modules, equalThoseOf: Self.oneModule(modules), probe: Self.leafBesideRootProbe(path: "root.shell.top.outer.inner"))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_seamTakesNoParameterForWrapperItsFillsMemoServes_whenFillsTypesAreInModuleBeneathFillingSeam() async throws {
		let modules = Self.fillReadingValueAndWrapperModules(fillTypesInOwnModule: true)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Impl)
		import Impl
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Session)
		import Session
		#endif

		extension Top {
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public convenience init() {
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_CDEA8B3F958E03B1.self // If this line does not compile, compile the code SafeDI generates for module Session into Session: under Bazel, add Session’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_serviceBuilder_Inner_service(_ scope: Inner.SafeDIScope_Service.service_Values) -> any Service {
		                let token = scope.__safeDI_token
		                func __safeDI_service() -> ServiceImpl {
		                    let wrapperReader = WrapperReader(token: token)
		                    return ServiceImpl(token: token.instance, wrapperReader: wrapperReader)
		                }
		                let service: any Service = __safeDI_service()
		                return service
		            }
		            func __safeDI_serviceBuilder_Outer() -> Outer.SafeDIScope_Service.__safeDI_Builder<any Service> {
		                .init(inner: { _ in __safeDI_serviceBuilder_Inner() })
		            }
		            func __safeDI_serviceBuilder_Inner() -> Inner.SafeDIScope_Service.__safeDI_Builder<any Service> {
		                .init(service: { scope in __safeDI_serviceBuilder_Inner_service(scope) })
		            }
		            return Outer(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Outer())
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(outer: outer)
		    }
		}

		extension Top {
		    public enum __safeDI_Top_CBF29CE484222325 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Impl)
		import Impl
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Session)
		import Session
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_top() -> Top {
		            _ = Top.__safeDI_Top_CBF29CE484222325.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Top()
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}
		"""])
		try await expectValues(of: output, modules: modules, equalThoseOf: Self.oneModule(modules), probe: Self.leafBesideRootProbe(path: "root.top.outer.inner"))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_seamTakesNoParameterForWrapperItsFillsMemoServes_whenFillBuildsWrapperReaderInSendableInstantiator() async throws {
		let modules = Self.fillReadingValueAndWrapperModules(readerInInstantiator: true)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Session)
		import Session
		#endif

		extension Top {
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public convenience init() {
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_CDEA8B3F958E03B1.self // If this line does not compile, compile the code SafeDI generates for module Session into Session: under Bazel, add Session’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_serviceBuilder_Inner_service(_ scope: Inner.SafeDIScope_Service.service_Values) -> any Service {
		                let token = scope.__safeDI_token
		                func __safeDI_service() -> ServiceImpl {
		                    @Sendable func __safeDI_wrapperReader() -> WrapperReader {
		                        WrapperReader(token: token)
		                    }
		                    let wrapperReader = SendableInstantiator<WrapperReader>(__safeDI_wrapperReader)
		                    return ServiceImpl(token: token.instance, wrapperReader: wrapperReader)
		                }
		                let service: any Service = __safeDI_service()
		                return service
		            }
		            func __safeDI_serviceBuilder_Outer() -> Outer.SafeDIScope_Service.__safeDI_Builder<any Service> {
		                .init(inner: { _ in __safeDI_serviceBuilder_Inner() })
		            }
		            func __safeDI_serviceBuilder_Inner() -> Inner.SafeDIScope_Service.__safeDI_Builder<any Service> {
		                .init(service: { scope in __safeDI_serviceBuilder_Inner_service(scope) })
		            }
		            return Outer(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Outer())
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(outer: outer)
		    }
		}

		extension Top {
		    public enum __safeDI_Top_CBF29CE484222325 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Session)
		import Session
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_top() -> Top {
		            _ = Top.__safeDI_Top_CBF29CE484222325.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Top()
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}
		"""])
		try await expectValues(of: output, modules: modules, equalThoseOf: Self.oneModule(modules), probe: Self.leafBesideRootProbe(path: "root.top.outer.inner", readerInInstantiator: true))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_publicMockTakesNoParameterForWrapperItsFillsMemoServes_whenFillingSeamGeneratesPublicMock() async throws {
		let modules = Self.fillReadingValueAndWrapperModules(generatesMocks: true)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Session)
		import Session
		#endif

		extension Top {
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public convenience init() {
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_CDEA8B3F958E03B1.self // If this line does not compile, compile the code SafeDI generates for module Session into Session: under Bazel, add Session’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_serviceBuilder_Inner_service(_ scope: Inner.SafeDIScope_Service.service_Values) -> any Service {
		                let token = scope.__safeDI_token
		                func __safeDI_service() -> ServiceImpl {
		                    let wrapperReader = WrapperReader(token: token)
		                    return ServiceImpl(token: token.instance, wrapperReader: wrapperReader)
		                }
		                let service: any Service = __safeDI_service()
		                return service
		            }
		            func __safeDI_serviceBuilder_Outer() -> Outer.SafeDIScope_Service.__safeDI_Builder<any Service> {
		                .init(inner: { _ in __safeDI_serviceBuilder_Inner() })
		            }
		            func __safeDI_serviceBuilder_Inner() -> Inner.SafeDIScope_Service.__safeDI_Builder<any Service> {
		                .init(service: { scope in __safeDI_serviceBuilder_Inner_service(scope) })
		            }
		            return Outer(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Outer())
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(outer: outer)
		    }
		}

		extension Top {
		    public enum __safeDI_Top_CBF29CE484222325 {}
		}

		#if DEBUG
		extension Top {
		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            outer: __safeDI_Feature_Outer_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                outer: outer
		            )
		        }

		        public var outer: __safeDI_Feature_Outer_MockConfiguration { __safeDI_storage.outer }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                outer: __safeDI_Feature_Outer_MockConfiguration
		            ) {
		                self.outer = outer
		            }

		            let outer: __safeDI_Feature_Outer_MockConfiguration
		        }
		    }

		    public static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Top {
		        func __safeDI_outer() -> Outer {
		            let __safeDI_token__safeDIBuilder = safeDIOverrides.outer.token
		            @Sendable func __safeDI_token() -> Token {
		                if let safeDIBuilder = __safeDI_token__safeDIBuilder { safeDIBuilder() } else { Token() }
		            }
		            let token = SendableLazilyInstantiated<Token>(__safeDI_token)
		            func __safeDI_inner() -> Inner {
		                let __safeDI_leafBuilder__safeDIBuilder = safeDIOverrides.outer.inner.leafBuilder
		                @Sendable func __safeDI_leafBuilder() -> Leaf {
		                    if let safeDIBuilder = __safeDI_leafBuilder__safeDIBuilder { safeDIBuilder(token.instance) } else { Leaf(token: token.instance) }
		                }
		                let leafBuilder = SendableInstantiator<Leaf>(__safeDI_leafBuilder)
		                func __safeDI_service() -> any Service {
		                    let wrapperReader = if let safeDIBuilder = safeDIOverrides.outer.inner.service.wrapperReader { safeDIBuilder(token) } else { WrapperReader(token: token) }
		                    return ServiceImpl.__safeDI_init(token: token.instance, wrapperReader: wrapperReader, safeDIBuilder: safeDIOverrides.outer.inner.service.safeDIBuilder)
		                }
		                let service: any Service = __safeDI_service()
		                return Inner.__safeDI_init(leafBuilder: leafBuilder, service: service, safeDIBuilder: safeDIOverrides.outer.inner.safeDIBuilder)
		            }
		            let inner: Inner = __safeDI_inner()
		            return Outer.__safeDI_init(token: token, inner: inner, safeDIBuilder: safeDIOverrides.outer.safeDIBuilder)
		        }
		        let outer: Outer = __safeDI_outer()
		        return Top(outer: outer)
		    }
		}

		extension Top {
		    public enum __safeDI_Top_mock_51799E6AA5E7B634 {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `ServiceImpl` is constructed within the public mock trees of module `Feature`.
		nonisolated public struct __safeDI_Feature_ServiceImpl_MockConfiguration {
		    public init(
		        wrapperReader: ((SendableLazilyInstantiated<Token>) -> WrapperReader)? = nil,
		        _ safeDIBuilder: ((Token, WrapperReader) -> ServiceImpl)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            wrapperReader: wrapperReader,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var wrapperReader: ((SendableLazilyInstantiated<Token>) -> WrapperReader)? { __safeDI_storage.wrapperReader }
		    /// Overrides how `ServiceImpl` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((Token, WrapperReader) -> ServiceImpl)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            wrapperReader: ((SendableLazilyInstantiated<Token>) -> WrapperReader)?,
		            safeDIBuilder: ((Token, WrapperReader) -> ServiceImpl)?
		        ) {
		            self.wrapperReader = wrapperReader
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let wrapperReader: ((SendableLazilyInstantiated<Token>) -> WrapperReader)?
		        let safeDIBuilder: ((Token, WrapperReader) -> ServiceImpl)?
		    }
		}

		extension ServiceImpl {
		    static func __safeDI_init(token: Token, wrapperReader: WrapperReader, safeDIBuilder: ((Token, WrapperReader) -> ServiceImpl)?) -> ServiceImpl {
		        if let safeDIBuilder { safeDIBuilder(token, wrapperReader) } else { ServiceImpl(token: token, wrapperReader: wrapperReader) }
		    }
		}

		/// Configuration for how `Inner` is constructed within the public mock trees of module `Feature`.
		nonisolated public struct __safeDI_Feature_Inner_MockConfiguration {
		    public init(
		        leafBuilder: (@Sendable (Token) -> Leaf)? = nil,
		        service: __safeDI_Feature_ServiceImpl_MockConfiguration = .init(),
		        _ safeDIBuilder: ((SendableInstantiator<Leaf>, any Service) -> Inner)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            leafBuilder: leafBuilder,
		            service: service,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var leafBuilder: (@Sendable (Token) -> Leaf)? { __safeDI_storage.leafBuilder }
		    public var service: __safeDI_Feature_ServiceImpl_MockConfiguration { __safeDI_storage.service }
		    /// Overrides how `Inner` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((SendableInstantiator<Leaf>, any Service) -> Inner)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            leafBuilder: (@Sendable (Token) -> Leaf)?,
		            service: __safeDI_Feature_ServiceImpl_MockConfiguration,
		            safeDIBuilder: ((SendableInstantiator<Leaf>, any Service) -> Inner)?
		        ) {
		            self.leafBuilder = leafBuilder
		            self.service = service
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let leafBuilder: (@Sendable (Token) -> Leaf)?
		        let service: __safeDI_Feature_ServiceImpl_MockConfiguration
		        let safeDIBuilder: ((SendableInstantiator<Leaf>, any Service) -> Inner)?
		    }
		}

		extension Inner {
		    static func __safeDI_init(leafBuilder: SendableInstantiator<Leaf>, service: any Service, safeDIBuilder: ((SendableInstantiator<Leaf>, any Service) -> Inner)?) -> Inner {
		        if let safeDIBuilder { safeDIBuilder(leafBuilder, service) } else { Inner(leafBuilder: leafBuilder, service: service) }
		    }
		}

		/// Configuration for how `Outer` is constructed within the public mock trees of module `Feature`.
		nonisolated public struct __safeDI_Feature_Outer_MockConfiguration {
		    public init(
		        token: (@Sendable () -> Token)? = nil,
		        inner: __safeDI_Feature_Inner_MockConfiguration = .init(),
		        _ safeDIBuilder: ((SendableLazilyInstantiated<Token>, Inner) -> Outer)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            token: token,
		            inner: inner,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var token: (@Sendable () -> Token)? { __safeDI_storage.token }
		    public var inner: __safeDI_Feature_Inner_MockConfiguration { __safeDI_storage.inner }
		    /// Overrides how `Outer` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((SendableLazilyInstantiated<Token>, Inner) -> Outer)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            token: (@Sendable () -> Token)?,
		            inner: __safeDI_Feature_Inner_MockConfiguration,
		            safeDIBuilder: ((SendableLazilyInstantiated<Token>, Inner) -> Outer)?
		        ) {
		            self.token = token
		            self.inner = inner
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let token: (@Sendable () -> Token)?
		        let inner: __safeDI_Feature_Inner_MockConfiguration
		        let safeDIBuilder: ((SendableLazilyInstantiated<Token>, Inner) -> Outer)?
		    }
		}

		extension Outer {
		    static func __safeDI_init(token: SendableLazilyInstantiated<Token>, inner: Inner, safeDIBuilder: ((SendableLazilyInstantiated<Token>, Inner) -> Outer)?) -> Outer {
		        if let safeDIBuilder { safeDIBuilder(token, inner) } else { Outer(token: token, inner: inner) }
		    }
		}
		#endif

		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Session)
		import Session
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_top() -> Top {
		            _ = Top.__safeDI_Top_CBF29CE484222325.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Top()
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            top: Top.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                top: top
		            )
		        }

		        var top: Top.SafeDIMockConfiguration { __safeDI_storage.top }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                top: Top.SafeDIMockConfiguration
		            ) {
		                self.top = top
		            }

		            let top: Top.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_top() -> Top {
		            func __safeDI_outer() -> Outer {
		                let __safeDI_token__safeDIBuilder = safeDIOverrides.top.outer.token
		                @Sendable func __safeDI_token() -> Token {
		                    if let safeDIBuilder = __safeDI_token__safeDIBuilder { safeDIBuilder() } else { Token() }
		                }
		                let token = SendableLazilyInstantiated<Token>(__safeDI_token)
		                func __safeDI_inner() -> Inner {
		                    let __safeDI_leafBuilder__safeDIBuilder = safeDIOverrides.top.outer.inner.leafBuilder
		                    @Sendable func __safeDI_leafBuilder() -> Leaf {
		                        if let safeDIBuilder = __safeDI_leafBuilder__safeDIBuilder { safeDIBuilder(token.instance) } else { Leaf(token: token.instance) }
		                    }
		                    let leafBuilder = SendableInstantiator<Leaf>(__safeDI_leafBuilder)
		                    func __safeDI_service() -> any Service {
		                        let wrapperReader = if let safeDIBuilder = safeDIOverrides.top.outer.inner.service.wrapperReader { safeDIBuilder(token) } else { WrapperReader(token: token) }
		                        return if let safeDIBuilder = safeDIOverrides.top.outer.inner.service.safeDIBuilder { safeDIBuilder(token.instance, wrapperReader) } else { ServiceImpl(token: token.instance, wrapperReader: wrapperReader) }
		                    }
		                    let service: any Service = __safeDI_service()
		                    return if let safeDIBuilder = safeDIOverrides.top.outer.inner.safeDIBuilder { safeDIBuilder(leafBuilder, service) } else { Inner(leafBuilder: leafBuilder, service: service) }
		                }
		                let inner: Inner = __safeDI_inner()
		                return if let safeDIBuilder = safeDIOverrides.top.outer.safeDIBuilder { safeDIBuilder(token, inner) } else { Outer(token: token, inner: inner) }
		            }
		            let outer: Outer = __safeDI_outer()
		            return if let safeDIBuilder = safeDIOverrides.top.safeDIBuilder { safeDIBuilder(outer) } else { Top(outer: outer) }
		        }
		        let top: Top = __safeDI_top()
		        return Root(top: top)
		    }
		}
		#endif

		#if DEBUG
		extension ServiceImpl {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            wrapperReader: ((SendableLazilyInstantiated<Token>) -> WrapperReader)? = nil,
		            _ safeDIBuilder: ((Token, WrapperReader) -> ServiceImpl)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                wrapperReader: wrapperReader,
		                safeDIBuilder: safeDIBuilder
		            )
		        }

		        var wrapperReader: ((SendableLazilyInstantiated<Token>) -> WrapperReader)? { __safeDI_storage.wrapperReader }
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        var safeDIBuilder: ((Token, WrapperReader) -> ServiceImpl)? { __safeDI_storage.safeDIBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                wrapperReader: ((SendableLazilyInstantiated<Token>) -> WrapperReader)?,
		                safeDIBuilder: ((Token, WrapperReader) -> ServiceImpl)?
		            ) {
		                self.wrapperReader = wrapperReader
		                self.safeDIBuilder = safeDIBuilder
		            }

		            let wrapperReader: ((SendableLazilyInstantiated<Token>) -> WrapperReader)?
		            let safeDIBuilder: ((Token, WrapperReader) -> ServiceImpl)?
		        }
		    }
		}

		extension Inner {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            leafBuilder: (@Sendable (Token) -> Leaf)? = nil,
		            service: ServiceImpl.SafeDIMockConfiguration = .init(),
		            _ safeDIBuilder: ((SendableInstantiator<Leaf>, any Service) -> Inner)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                leafBuilder: leafBuilder,
		                service: service,
		                safeDIBuilder: safeDIBuilder
		            )
		        }

		        var leafBuilder: (@Sendable (Token) -> Leaf)? { __safeDI_storage.leafBuilder }
		        var service: ServiceImpl.SafeDIMockConfiguration { __safeDI_storage.service }
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        var safeDIBuilder: ((SendableInstantiator<Leaf>, any Service) -> Inner)? { __safeDI_storage.safeDIBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                leafBuilder: (@Sendable (Token) -> Leaf)?,
		                service: ServiceImpl.SafeDIMockConfiguration,
		                safeDIBuilder: ((SendableInstantiator<Leaf>, any Service) -> Inner)?
		            ) {
		                self.leafBuilder = leafBuilder
		                self.service = service
		                self.safeDIBuilder = safeDIBuilder
		            }

		            let leafBuilder: (@Sendable (Token) -> Leaf)?
		            let service: ServiceImpl.SafeDIMockConfiguration
		            let safeDIBuilder: ((SendableInstantiator<Leaf>, any Service) -> Inner)?
		        }
		    }
		}

		extension Outer {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            token: (@Sendable () -> Token)? = nil,
		            inner: Inner.SafeDIMockConfiguration = .init(),
		            _ safeDIBuilder: ((SendableLazilyInstantiated<Token>, Inner) -> Outer)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                token: token,
		                inner: inner,
		                safeDIBuilder: safeDIBuilder
		            )
		        }

		        var token: (@Sendable () -> Token)? { __safeDI_storage.token }
		        var inner: Inner.SafeDIMockConfiguration { __safeDI_storage.inner }
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        var safeDIBuilder: ((SendableLazilyInstantiated<Token>, Inner) -> Outer)? { __safeDI_storage.safeDIBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                token: (@Sendable () -> Token)?,
		                inner: Inner.SafeDIMockConfiguration,
		                safeDIBuilder: ((SendableLazilyInstantiated<Token>, Inner) -> Outer)?
		            ) {
		                self.token = token
		                self.inner = inner
		                self.safeDIBuilder = safeDIBuilder
		            }

		            let token: (@Sendable () -> Token)?
		            let inner: Inner.SafeDIMockConfiguration
		            let safeDIBuilder: ((SendableLazilyInstantiated<Token>, Inner) -> Outer)?
		        }
		    }
		}

		extension Top {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            outer: Outer.SafeDIMockConfiguration = .init(),
		            _ safeDIBuilder: ((Outer) -> Top)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                outer: outer,
		                safeDIBuilder: safeDIBuilder
		            )
		        }

		        var outer: Outer.SafeDIMockConfiguration { __safeDI_storage.outer }
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        var safeDIBuilder: ((Outer) -> Top)? { __safeDI_storage.safeDIBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                outer: Outer.SafeDIMockConfiguration,
		                safeDIBuilder: ((Outer) -> Top)?
		            ) {
		                self.outer = outer
		                self.safeDIBuilder = safeDIBuilder
		            }

		            let outer: Outer.SafeDIMockConfiguration
		            let safeDIBuilder: ((Outer) -> Top)?
		        }
		    }
		}
		#endif

		"""])
		try await expectValues(of: output, modules: modules, equalThoseOf: Self.oneModule(modules), probe: Self.leafBesideRootProbe(path: "root.top.outer.inner"))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsDeclarationHiddenByField_whenFillingSeamsFillReadsWrapperAlone() async {
		// The memo serves a read of its wrapper only where the fill's tree reads the value too, which binds it.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["WrapperReader.swift"]):8:2: error: `WrapperReader` receives `token: SendableLazilyInstantiated<Token>`, which `Outer` builds where it calls `Inner`, but SafeDI hands the builder for `Inner`’s `service: any Service` (`service` of `serviceBuilder`) only its instance, `token: Token`, which `Inner`’s tree receives. Declare `@Received let token: SendableLazilyInstantiated<Token>` on `Inner`, so SafeDI hands it to the builder.
			\(fixtures["Session"]!["Outer.swift"]):10:2: note: `Outer` declares `token: SendableLazilyInstantiated<Token>` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.fillReadingValueAndWrapperModules(readsValue: false), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsDeclarationHiddenByField_whenFillingSeamsFillReadsPlainWrapperBesideValueInsideSendableInstantiator() async {
		// The fill binds the `LazilyInstantiated` memo's value, which a `@Sendable` function captures, so no memo serves the
		// wrapper's read.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["WrapperReader.swift"]):8:2: error: `WrapperReader` receives `token: LazilyInstantiated<Token>`, which `Outer` builds where it calls `Inner`, but SafeDI hands the builder for `Inner`’s `service: any Service` (`service` of `serviceBuilder`) only its instance, `token: Token`, which `Inner`’s tree receives. Declare `@Received let token: LazilyInstantiated<Token>` on `Inner`, so SafeDI hands it to the builder.
			\(fixtures["Session"]!["Outer.swift"]):10:2: note: `Outer` declares `token: LazilyInstantiated<Token>` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.fillReadingValueAndWrapperModules(isSendable: false, readsValue: false, readsValueInsideSendableInstantiator: true), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenDeclaration_whenFillingSeamDeclaresWrapperOuterDeclaresValue() async {
		// Inline, `WrapperReader` would read `Top`'s wrapper above `Outer`'s value of the label, which hides it.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["WrapperReader.swift"]):8:2: error: @Received property `token: SendableLazilyInstantiated<Token>` is hidden in chain: Top -> Outer -> Inner -> any Service -> WrapperReader. `Outer` declares `token: Token` with the same label, so the types below `Outer` receive `token: Token` instead. Give `token: Token` on `Outer` a different label to fix.
			\(fixtures["Session"]!["Outer.swift"]):10:2: note: `token: Token` is declared here
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.fillReadingValueAndWrapperModules(outerDeclaresValueTopDeclaresWrapper: true), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Core`, which declares `Token`, `Leaf`, which receives it, and `Inner`, a seam that builds `Leaf` through an
	/// instantiator, so it defers `token`, and holds a place of `Service`; `Session`, whose seam `Outer` declares `token`
	/// lazily and builds `Inner`; `Feature`, whose seam `Top` builds `Outer` and fills `Inner`'s place, which `Outer`
	/// passes up, with `ServiceImpl`, which receives `token` and builds `WrapperReader`, which receives its wrapper; and
	/// `App`, whose root builds `Top`.
	/// - Parameters:
	///   - isSendable: Whether the wrappers and instantiators are the `Sendable` ones.
	///   - readsValue: Whether `ServiceImpl` receives `token`.
	///   - readsValueInsideSendableInstantiator: Whether `ServiceImpl` reads `token` through `Leaf`, built in a
	///     `SendableInstantiator`, rather than receiving it.
	///   - readerInInstantiator: Whether `ServiceImpl` builds `WrapperReader` through a `SendableInstantiator`.
	///   - shellCallsTop: Whether `Shell`, a seam of a module of its own, builds `Top` beneath the root.
	///   - fillTypesInOwnModule: Whether `ServiceImpl` and `WrapperReader` are declared in `Impl`, a module `Feature`
	///     depends on.
	///   - generatesMocks: Whether `Top` generates a public mock and the root a mock.
	///   - outerDeclaresValueTopDeclaresWrapper: Whether `Outer` declares `token` by value, and `Top` declares the wrapper.
	private static func fillReadingValueAndWrapperModules(
		isSendable: Bool = true,
		readsValue: Bool = true,
		readsValueInsideSendableInstantiator: Bool = false,
		readerInInstantiator: Bool = false,
		shellCallsTop: Bool = false,
		fillTypesInOwnModule: Bool = false,
		generatesMocks: Bool = false,
		outerDeclaresValueTopDeclaresWrapper: Bool = false,
	) -> [ModuleFixture] {
		let sendable = isSendable ? "Sendable" : "@unchecked Sendable"
		let wrapper = isSendable ? "SendableLazilyInstantiated" : "LazilyInstantiated"
		let instantiator = isSendable ? "SendableInstantiator" : "Instantiator"
		var serviceImplementationParameters = [String]()
		var serviceImplementationAssignments = [String]()
		var serviceImplementationProperties = [String]()
		if readsValue {
			serviceImplementationParameters.append("token: Token")
			serviceImplementationAssignments.append("self.token = token")
			serviceImplementationProperties.append("@Received let token: Token")
		}
		if readsValueInsideSendableInstantiator {
			serviceImplementationParameters.append("leafBuilder: SendableInstantiator<Leaf>")
			serviceImplementationAssignments.append("self.leafBuilder = leafBuilder")
			serviceImplementationProperties.append("@Instantiated public let leafBuilder: SendableInstantiator<Leaf>")
		}
		let readerType = readerInInstantiator ? "SendableInstantiator<WrapperReader>" : "WrapperReader"
		serviceImplementationParameters.append("wrapperReader: \(readerType)")
		serviceImplementationAssignments.append("self.wrapperReader = wrapperReader")
		serviceImplementationProperties.append("@Instantiated public let wrapperReader: \(readerType)")
		let fillTypes = """
		@Instantiable
		public final class WrapperReader: Instantiable, \(sendable) {
			public init(token: \(wrapper)<Token>) { self.token = token }
			@Received public let token: \(wrapper)<Token>
		}

		@Instantiable(fulfillingAdditionalTypes: [Service.self])
		public final class ServiceImpl: Instantiable, Service, \(sendable) {
			public init(\(serviceImplementationParameters.joined(separator: ", "))) {
				\(serviceImplementationAssignments.joined(separator: "\n\t\t"))
			}
			\(serviceImplementationProperties.joined(separator: "\n\t"))
		}
		"""
		let outerToken = outerDeclaresValueTopDeclaresWrapper ? "Token" : "\(wrapper)<Token>"
		let top = if outerDeclaresValueTopDeclaresWrapper {
			"""
			@Instantiable(generateDependencyTree: true\(generatesMocks ? ", generateMock: .public" : ""))
			public final class Top: Instantiable, \(sendable) {
				public init(token: \(wrapper)<Token>, outer: Outer) { self.token = token; self.outer = outer }
				@Instantiated public let token: \(wrapper)<Token>
				@Instantiated public let outer: Outer
			}
			"""
		} else {
			"""
			@Instantiable(generateDependencyTree: true\(generatesMocks ? ", generateMock: .public" : ""))
			public final class Top: Instantiable, \(sendable) {
				public init(outer: Outer) { self.outer = outer }
				@Instantiated public let outer: Outer
			}
			"""
		}
		var modules = [
			ModuleFixture(name: "Core", packageName: "Min", swiftFileContent: ["""
			import SafeDI

			public protocol Service: Sendable {}

			@Instantiable
			public final class Token: Instantiable, \(sendable) {
				public init() {}
			}

			@Instantiable
			public final class Leaf: Instantiable, \(sendable) {
				public init(token: Token) { self.token = token }
				@Received public let token: Token
			}

			@Instantiable(generateDependencyTree: true)
			public final class Inner: Instantiable, \(sendable) {
				public init(leafBuilder: \(instantiator)<Leaf>, service: any Service) {
					self.leafBuilder = leafBuilder
					self.service = service
				}
				@Instantiated public let leafBuilder: \(instantiator)<Leaf>
				@Instantiated public let service: any Service
			}
			"""]),
			ModuleFixture(name: "Session", packageName: "Min", swiftFileContent: ["""
			import Core
			import SafeDI

			@Instantiable(generateDependencyTree: true)
			public final class Outer: Instantiable, \(sendable) {
				public init(token: \(outerToken), inner: Inner) {
					self.token = token
					self.inner = inner
				}
				@Instantiated public let token: \(outerToken)
				@Instantiated public let inner: Inner
			}
			"""], dependencies: ["Core"]),
		]
		if fillTypesInOwnModule {
			modules.append(ModuleFixture(name: "Impl", packageName: "Min", swiftFileContent: ["""
			import Core
			import SafeDI

			\(fillTypes)
			"""], dependencies: ["Core"]))
			modules.append(ModuleFixture(name: "Feature", packageName: "Min", swiftFileContent: ["""
			import Core
			import Impl
			import Session
			import SafeDI

			\(top)
			"""], dependencies: ["Core", "Session", "Impl"]))
		} else {
			modules.append(ModuleFixture(name: "Feature", packageName: "Min", swiftFileContent: ["""
			import Core
			import Session
			import SafeDI

			\(fillTypes)

			\(top)
			"""], dependencies: ["Core", "Session"]))
		}
		let featureDependencies = modules.map(\.name)
		let rootArguments = generatesMocks ? "isRoot: true, generateMock: true" : "isRoot: true"
		if shellCallsTop {
			modules.append(ModuleFixture(name: "Shell", packageName: "Min", swiftFileContent: ["""
			import Feature
			import SafeDI

			@Instantiable(generateDependencyTree: true)
			public final class Shell: Instantiable, \(sendable) {
				public init(top: Top) { self.top = top }
				@Instantiated public let top: Top
			}
			"""], dependencies: featureDependencies))
			modules.append(ModuleFixture(name: "App", packageName: "Min", swiftFileContent: ["""
			import Shell
			import SafeDI

			@Instantiable(\(rootArguments))
			public final class Root: Instantiable, \(sendable) {
				public init(shell: Shell) { self.shell = shell }
				@Instantiated public let shell: Shell
			}
			"""], dependencies: featureDependencies + ["Shell"]))
		} else {
			modules.append(ModuleFixture(name: "App", packageName: "Min", swiftFileContent: ["""
			import Feature
			import SafeDI

			@Instantiable(\(rootArguments))
			public final class Root: Instantiable, \(sendable) {
				public init(top: Top) { self.top = top }
				@Instantiated public let top: Top
			}
			"""], dependencies: featureDependencies))
		}
		return modules
	}

	/// A probe that builds `Root`, then a `Leaf` through the instantiator of the `Inner` at `path`, and, where
	/// `readerInInstantiator`, a `WrapperReader` through `ServiceImpl`'s: the comparator then sees which `Token` each holds.
	private static func leafBesideRootProbe(path: String, readerInInstantiator: Bool = false) -> DifferentialValueProbe {
		let reader = readerInInstantiator ? ", (\(path).service as! ServiceImpl).wrapperReader.instantiate()" : ""
		return DifferentialValueProbe(name: "root beside a leaf", expression: "{ () -> Any in\n\tlet root = Root()\n\treturn (root, \(path).leafBuilder.instantiate()\(reader))\n}()")
	}

	/// Every declaration of `modules` in one module, which builds every seam's tree inline.
	private static func oneModule(_ modules: [ModuleFixture]) -> [ModuleFixture] {
		let declarations = modules.map { module in
			module.swiftFileContent.joined(separator: "\n\n").components(separatedBy: "\n").filter { !$0.hasPrefix("import ") }.joined(separator: "\n")
		}
		return [ModuleFixture(name: "App", packageName: "Min", swiftFileContent: ["import SafeDI\n" + declarations.joined(separator: "\n")])]
	}

	/// Expects the values `output`, the run of `modules`, builds for `probe` to equal those `knownRightModules` build.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectValues(of output: MultiModuleTestOutput, modules: [ModuleFixture], equalThoseOf knownRightModules: [ModuleFixture], probe: DifferentialValueProbe, sourceLocation: SourceLocation = #_sourceLocation) async throws {
		guard compileVerificationIsEnabled else { return }
		let knownRightOutput = try await executeSafeDIToolMultiModuleTest(modules: knownRightModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		try await expectDifferentialValuesAgree(
			feature: DifferentialValuePath(output: output, modules: modules),
			knownRight: DifferentialValuePath(output: knownRightOutput, modules: knownRightModules),
			probes: [probe],
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}
}
