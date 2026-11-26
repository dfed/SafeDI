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

/// A fill of a call of another module's seam that captures nothing of the call, binding only what its dispatcher hands
/// it, is declared once, at the top of the root that holds the call, however many paths reach it
/// (`ScopeGenerator.fillRootFunction`, `RootFunctionHoisting`). A fill that reads a value of the caller stays in each call.
/// Every cell compiles.
struct SafeDIToolSeamRootFillTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests

	/// `Last` holds `screenBuilder`, a hole only `App` can fill, with `AppScreen`, which opens `Last` again: the fill
	/// re-enters its call, so it is a function of its own. The root opens `Last` and `AppScreen`, so the fill is reached on
	/// two paths, and the root declares it once, at its top.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresFillOnceAtTheRootsTop_whenFillReentersItsCallOnTwoPaths() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.screenModules(readingToken: false), integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Seam)
		import Seam
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_appScreen_AnyScreenBuilder_Last_screenBuilder(service: Service) -> ErasedInstantiator<Int, AnyScreen>.Builder {
		            func __safeDI_screenBuilder(id: Int) -> AppScreen {
		                func __safeDI_lastBuilder(id: Int) -> Last {
		                    _ = Last.__safeDI_Last_64640399A387E1E1.self // If this line does not compile, compile the code SafeDI generates for module Seam into Seam: under Bazel, add Seam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                    return Last(__safeDI_id: id, __safeDI_service: service, __safeDI_appScreen_AnyScreenBuilder: __safeDI_appScreen_AnyScreenBuilder_Last())
		                }
		                let lastBuilder = ErasedInstantiator<Int, AnyScreen> {
		                    AnyScreen(__safeDI_lastBuilder(id: $0))
		                }
		                return AppScreen(id: id, service: service, lastBuilder: lastBuilder)
		            }
		            return { forwarded in AnyScreen(__safeDI_screenBuilder(id: forwarded)) }
		        }
		        func __safeDI_appScreen_AnyScreenBuilder_Last() -> Last.__safeDI_AppScreen_AnyScreenCarrier<AnyScreen> {
		            .init(screenBuilder: { values_id, values_service in __safeDI_appScreen_AnyScreenBuilder_Last_screenBuilder(service: values_service) })
		        }
		        let service = Service()
		        func __safeDI_lastBuilder(id: Int) -> Last {
		            _ = Last.__safeDI_Last_64640399A387E1E1.self // If this line does not compile, compile the code SafeDI generates for module Seam into Seam: under Bazel, add Seam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Last(__safeDI_id: id, __safeDI_service: service, __safeDI_appScreen_AnyScreenBuilder: __safeDI_appScreen_AnyScreenBuilder_Last())
		        }
		        let lastBuilder = ErasedInstantiator<Int, AnyScreen> {
		            AnyScreen(__safeDI_lastBuilder(id: $0))
		        }
		        func __safeDI_screenBuilder(id: Int) -> AppScreen {
		            func __safeDI_lastBuilder(id: Int) -> Last {
		                _ = Last.__safeDI_Last_64640399A387E1E1.self // If this line does not compile, compile the code SafeDI generates for module Seam into Seam: under Bazel, add Seam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                return Last(__safeDI_id: id, __safeDI_service: service, __safeDI_appScreen_AnyScreenBuilder: __safeDI_appScreen_AnyScreenBuilder_Last())
		            }
		            let lastBuilder = ErasedInstantiator<Int, AnyScreen> {
		                AnyScreen(__safeDI_lastBuilder(id: $0))
		            }
		            return AppScreen(id: id, service: service, lastBuilder: lastBuilder)
		        }
		        let screenBuilder = ErasedInstantiator<Int, AnyScreen> {
		            AnyScreen(__safeDI_screenBuilder(id: $0))
		        }
		        self.init(service: service, lastBuilder: lastBuilder, screenBuilder: screenBuilder)
		    }
		}
		""")
	}

	/// The same shape, but `AppScreen` receives `token`, which only the root declares: the fill reads the caller's `token`,
	/// so each call declares it.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresFillInEachCall_whenFillThatReentersItsCallReadsCallersValue() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.screenModules(readingToken: true), integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Seam)
		import Seam
		#endif

		extension Root {
		    public convenience init() {
		        let service = Service()
		        let token = Token()
		        func __safeDI_lastBuilder(id: Int) -> Last {
		            _ = Last.__safeDI_Last_64640399A387E1E1.self // If this line does not compile, compile the code SafeDI generates for module Seam into Seam: under Bazel, add Seam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_appScreen_AnyScreenBuilder_Last_screenBuilder(service: Service) -> ErasedInstantiator<Int, AnyScreen>.Builder {
		                func __safeDI_screenBuilder(id: Int) -> AppScreen {
		                    func __safeDI_lastBuilder(id: Int) -> Last {
		                        _ = Last.__safeDI_Last_64640399A387E1E1.self // If this line does not compile, compile the code SafeDI generates for module Seam into Seam: under Bazel, add Seam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                        return Last(__safeDI_id: id, __safeDI_service: service, __safeDI_appScreen_AnyScreenBuilder: __safeDI_appScreen_AnyScreenBuilder_Last())
		                    }
		                    let lastBuilder = ErasedInstantiator<Int, AnyScreen> {
		                        AnyScreen(__safeDI_lastBuilder(id: $0))
		                    }
		                    return AppScreen(id: id, service: service, lastBuilder: lastBuilder, token: token)
		                }
		                return { forwarded in AnyScreen(__safeDI_screenBuilder(id: forwarded)) }
		            }
		            func __safeDI_appScreen_AnyScreenBuilder_Last() -> Last.__safeDI_AppScreen_AnyScreenCarrier<AnyScreen> {
		                .init(screenBuilder: { values_id, values_service in __safeDI_appScreen_AnyScreenBuilder_Last_screenBuilder(service: values_service) })
		            }
		            return Last(__safeDI_id: id, __safeDI_service: service, __safeDI_appScreen_AnyScreenBuilder: __safeDI_appScreen_AnyScreenBuilder_Last())
		        }
		        let lastBuilder = ErasedInstantiator<Int, AnyScreen> {
		            AnyScreen(__safeDI_lastBuilder(id: $0))
		        }
		        func __safeDI_screenBuilder(id: Int) -> AppScreen {
		            func __safeDI_lastBuilder(id: Int) -> Last {
		                _ = Last.__safeDI_Last_64640399A387E1E1.self // If this line does not compile, compile the code SafeDI generates for module Seam into Seam: under Bazel, add Seam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                func __safeDI_appScreen_AnyScreenBuilder_Last_screenBuilder(service: Service) -> ErasedInstantiator<Int, AnyScreen>.Builder {
		                    func __safeDI_screenBuilder(id: Int) -> AppScreen {
		                        func __safeDI_lastBuilder(id: Int) -> Last {
		                            _ = Last.__safeDI_Last_64640399A387E1E1.self // If this line does not compile, compile the code SafeDI generates for module Seam into Seam: under Bazel, add Seam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                            return Last(__safeDI_id: id, __safeDI_service: service, __safeDI_appScreen_AnyScreenBuilder: __safeDI_appScreen_AnyScreenBuilder_Last())
		                        }
		                        let lastBuilder = ErasedInstantiator<Int, AnyScreen> {
		                            AnyScreen(__safeDI_lastBuilder(id: $0))
		                        }
		                        return AppScreen(id: id, service: service, lastBuilder: lastBuilder, token: token)
		                    }
		                    return { forwarded in AnyScreen(__safeDI_screenBuilder(id: forwarded)) }
		                }
		                func __safeDI_appScreen_AnyScreenBuilder_Last() -> Last.__safeDI_AppScreen_AnyScreenCarrier<AnyScreen> {
		                    .init(screenBuilder: { values_id, values_service in __safeDI_appScreen_AnyScreenBuilder_Last_screenBuilder(service: values_service) })
		                }
		                return Last(__safeDI_id: id, __safeDI_service: service, __safeDI_appScreen_AnyScreenBuilder: __safeDI_appScreen_AnyScreenBuilder_Last())
		            }
		            let lastBuilder = ErasedInstantiator<Int, AnyScreen> {
		                AnyScreen(__safeDI_lastBuilder(id: $0))
		            }
		            return AppScreen(id: id, service: service, lastBuilder: lastBuilder, token: token)
		        }
		        let screenBuilder = ErasedInstantiator<Int, AnyScreen> {
		            AnyScreen(__safeDI_screenBuilder(id: $0))
		        }
		        self.init(service: service, lastBuilder: lastBuilder, screenBuilder: screenBuilder, token: token)
		    }
		}
		""")
	}

	/// The root opens `Last` only in a `SendableErasedInstantiator`, whose `@Sendable` builder function declares `Last`'s
	/// fill, which is plain: the root cannot declare it at its top, where the `@Sendable` function would call a plain one, so
	/// the fill stays in the call.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresFillInItsCall_whenCallIsInsideSendableFunctionAndFillIsPlain() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.screenModules(readingToken: false, opensLastInSendableWrapperOnly: true), integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Seam)
		import Seam
		#endif

		extension Root {
		    public convenience init() {
		        let service = Service()
		        @Sendable nonisolated func __safeDI_lastBuilder(id: Int) -> Last {
		            _ = Last.__safeDI_Last_64640399A387E1E1.self // If this line does not compile, compile the code SafeDI generates for module Seam into Seam: under Bazel, add Seam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_appScreen_AnyScreenBuilder_Last_screenBuilder(service: Service) -> ErasedInstantiator<Int, AnyScreen>.Builder {
		                func __safeDI_screenBuilder(id: Int) -> AppScreen {
		                    func __safeDI_lastBuilder(id: Int) -> Last {
		                        _ = Last.__safeDI_Last_64640399A387E1E1.self // If this line does not compile, compile the code SafeDI generates for module Seam into Seam: under Bazel, add Seam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                        return Last(__safeDI_id: id, __safeDI_service: service, __safeDI_appScreen_AnyScreenBuilder: __safeDI_appScreen_AnyScreenBuilder_Last())
		                    }
		                    let lastBuilder = ErasedInstantiator<Int, AnyScreen> {
		                        AnyScreen(__safeDI_lastBuilder(id: $0))
		                    }
		                    return AppScreen(id: id, service: service, lastBuilder: lastBuilder)
		                }
		                return { forwarded in AnyScreen(__safeDI_screenBuilder(id: forwarded)) }
		            }
		            func __safeDI_appScreen_AnyScreenBuilder_Last() -> Last.__safeDI_AppScreen_AnyScreenCarrier<AnyScreen> {
		                .init(screenBuilder: { values_id, values_service in __safeDI_appScreen_AnyScreenBuilder_Last_screenBuilder(service: values_service) })
		            }
		            return Last(__safeDI_id: id, __safeDI_service: service, __safeDI_appScreen_AnyScreenBuilder: __safeDI_appScreen_AnyScreenBuilder_Last())
		        }
		        let lastBuilder = SendableErasedInstantiator<Int, AnyScreen> {
		            AnyScreen(__safeDI_lastBuilder(id: $0))
		        }
		        self.init(service: service, lastBuilder: lastBuilder)
		    }
		}
		""")
	}

	/// `Inner` and `Outer` are seams of two modules, each with an `api` only `App` fills, and `Outer`'s tree opens `Inner`.
	/// The root instantiates both, so `Inner` is called twice: by the root, and inside `Outer`'s call. Each call declares a
	/// dispatcher named for `Inner`'s level that calls that call's own fill, so the two dispatchers share a name and differ
	/// in text, and each is declared where its call put it, calling its own fill.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsEachCallsDispatcherInItsCall_whenTwoCallsDeclareDispatchersOfOneNameCallingTheirOwnFills() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.siblingCallModules(callsInnerThroughOuterSeam: false), integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(InnerSeam)
		import InnerSeam
		#endif
		#if canImport(OuterSeam)
		import OuterSeam
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_apiBuilder_Inner_api(_ scope_service: Service) -> any Api {
		            let service = scope_service
		            func __safeDI_api() -> LiveApi {
		                let detail = Detail(service: service)
		                return LiveApi(service: service, detail: detail)
		            }
		            let api: any Api = __safeDI_api()
		            return api
		        }
		        func __safeDI_apiBuilder_Outer_api(_ scope_service: Service, _ scope_innerBuilder: Instantiator<Inner>) -> any Api {
		            let service = scope_service
		            func __safeDI_api() -> LiveApi {
		                let detail = Detail(service: service)
		                return LiveApi(service: service, detail: detail)
		            }
		            let api: any Api = __safeDI_api()
		            return api
		        }
		        func __safeDI_apiBuilder_Inner_Inner_api(_ scope_service: Service) -> any Api {
		            let service = scope_service
		            func __safeDI_api() -> LiveApi {
		                let detail = Detail(service: service)
		                return LiveApi(service: service, detail: detail)
		            }
		            let api: any Api = __safeDI_api()
		            return api
		        }
		        let service = Service()
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_85D90E2A41851D5B.self // If this line does not compile, compile the code SafeDI generates for module InnerSeam into InnerSeam: under Bazel, add InnerSeam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_apiBuilder_Inner() -> Inner.__safeDI_ApiCarrier<any Api> {
		                .init(api: { scope_service in __safeDI_apiBuilder_Inner_api(scope_service) })
		            }
		            return Inner(__safeDI_service: service, __safeDI_apiBuilder: __safeDI_apiBuilder_Inner())
		        }
		        let inner: Inner = __safeDI_inner()
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_3B95A2880DC768BE.self // If this line does not compile, compile the code SafeDI generates for module OuterSeam into OuterSeam: under Bazel, add OuterSeam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_apiBuilder_Outer() -> Outer.__safeDI_ApiCarrier<any Api> {
		                .init(api: { scope_service, scope_innerBuilder in __safeDI_apiBuilder_Outer_api(scope_service, scope_innerBuilder) }, innerBuilder: __safeDI_apiBuilder_Inner())
		            }
		            func __safeDI_apiBuilder_Inner() -> Inner.__safeDI_ApiCarrier<any Api> {
		                .init(api: { scope_service in __safeDI_apiBuilder_Inner_Inner_api(scope_service) })
		            }
		            return Outer(__safeDI_service: service, __safeDI_apiBuilder: __safeDI_apiBuilder_Outer())
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(service: service, inner: inner, outer: outer)
		    }
		}
		""")
	}

	/// The same seams, but the root calls `Inner` only inside the calls of two seams of `OuterSeam`: `InnerHost`, which
	/// instantiates it, and `Outer`, which opens it through an instantiator. Each call declares a dispatcher named for
	/// `Inner`'s level, and the two call different fills.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsEachCallsDispatcherInItsCall_whenTwoSeamsOfOneModuleCallAnotherModulesSeam() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.siblingCallModules(callsInnerThroughOuterSeam: true), integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(InnerSeam)
		import InnerSeam
		#endif
		#if canImport(OuterSeam)
		import OuterSeam
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_apiBuilder_Inner_api(_ scope_service: Service) -> any Api {
		            let service = scope_service
		            func __safeDI_api() -> LiveApi {
		                let detail = Detail(service: service)
		                return LiveApi(service: service, detail: detail)
		            }
		            let api: any Api = __safeDI_api()
		            return api
		        }
		        func __safeDI_apiBuilder_Outer_api(_ scope_service: Service, _ scope_innerBuilder: Instantiator<Inner>) -> any Api {
		            let service = scope_service
		            func __safeDI_api() -> LiveApi {
		                let detail = Detail(service: service)
		                return LiveApi(service: service, detail: detail)
		            }
		            let api: any Api = __safeDI_api()
		            return api
		        }
		        func __safeDI_apiBuilder_Inner_Inner_api(_ scope_service: Service) -> any Api {
		            let service = scope_service
		            func __safeDI_api() -> LiveApi {
		                let detail = Detail(service: service)
		                return LiveApi(service: service, detail: detail)
		            }
		            let api: any Api = __safeDI_api()
		            return api
		        }
		        let service = Service()
		        func __safeDI_innerHost() -> InnerHost {
		            _ = InnerHost.__safeDI_InnerHost_44A0EA0C8BC24872.self // If this line does not compile, compile the code SafeDI generates for module OuterSeam into OuterSeam: under Bazel, add OuterSeam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_apiBuilder_InnerHost() -> InnerHost.__safeDI_ApiCarrier<any Api> {
		                .init(inner: __safeDI_apiBuilder_Inner())
		            }
		            func __safeDI_apiBuilder_Inner() -> Inner.__safeDI_ApiCarrier<any Api> {
		                .init(api: { scope_service in __safeDI_apiBuilder_Inner_api(scope_service) })
		            }
		            return InnerHost(__safeDI_service: service, __safeDI_apiBuilder: __safeDI_apiBuilder_InnerHost())
		        }
		        let innerHost: InnerHost = __safeDI_innerHost()
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_3B95A2880DC768BE.self // If this line does not compile, compile the code SafeDI generates for module OuterSeam into OuterSeam: under Bazel, add OuterSeam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_apiBuilder_Outer() -> Outer.__safeDI_ApiCarrier<any Api> {
		                .init(api: { scope_service, scope_innerBuilder in __safeDI_apiBuilder_Outer_api(scope_service, scope_innerBuilder) }, innerBuilder: __safeDI_apiBuilder_Inner())
		            }
		            func __safeDI_apiBuilder_Inner() -> Inner.__safeDI_ApiCarrier<any Api> {
		                .init(api: { scope_service in __safeDI_apiBuilder_Inner_Inner_api(scope_service) })
		            }
		            return Outer(__safeDI_service: service, __safeDI_apiBuilder: __safeDI_apiBuilder_Outer())
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(service: service, innerHost: innerHost, outer: outer)
		    }
		}
		""")
	}

	/// `Inner`, a seam of `Seam` whose `api` only `App` fills and that builds `Leaf`, which receives `token`, is called by
	/// `F0` and `F1`, seams of `Callers` that pass its place up. `App`'s `LiveApi` fills it and builds `Reader`, which
	/// receives `token` as a `SendableLazilyInstantiated`: another form of the label than the field the fill is handed.
	/// `Mid`, beneath the root, declares that wrapper and calls both seams, so each fill reads `Mid`'s wrapper and stays in
	/// its call, where the root declares no `token`.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsFillInItsCall_whenFillReadsAnotherFormOfHandedLabelDeclaredBeneathRoot() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.wrapperFormModules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Callers)
		import Callers
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Seam)
		import Seam
		#endif

		extension Root {
		    public convenience init() {
		        @Sendable nonisolated func __safeDI_token() -> Token {
		            Token()
		        }
		        func __safeDI_mid() -> Mid {
		            let token = SendableLazilyInstantiated<Token>(__safeDI_token)
		            let service = Service()
		            func __safeDI_f0() -> F0 {
		                _ = F0.__safeDI_F0_E666CFA02F65FBFB.self // If this line does not compile, compile the code SafeDI generates for module Callers into Callers: under Bazel, add Callers’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                func __safeDI_apiBuilder_Inner_api(_ scope_token: LazilyInstantiated<Token>, _ scope_leafBuilder: Instantiator<Leaf>) -> any Api {
		                    func __safeDI_api() -> LiveApi {
		                        @Sendable nonisolated func __safeDI_readerBuilder() -> Reader {
		                            Reader(token: token)
		                        }
		                        let readerBuilder = SendableInstantiator<Reader>(__safeDI_readerBuilder)
		                        return LiveApi(readerBuilder: readerBuilder)
		                    }
		                    let api: any Api = __safeDI_api()
		                    return api
		                }
		                func __safeDI_apiBuilder_F0() -> F0.__safeDI_ApiCarrier<any Api> {
		                    .init(inner: __safeDI_apiBuilder_Inner())
		                }
		                func __safeDI_apiBuilder_Inner() -> Inner.__safeDI_ApiCarrier<any Api> {
		                    .init(api: { scope_token, scope_leafBuilder in __safeDI_apiBuilder_Inner_api(scope_token, scope_leafBuilder) })
		                }
		                return F0(__safeDI_service: service, __safeDI_token: token.instance, __safeDI_apiBuilder: __safeDI_apiBuilder_F0())
		            }
		            let f0: F0 = __safeDI_f0()
		            func __safeDI_f1() -> F1 {
		                _ = F1.__safeDI_F1_662E4FC5D4A33B62.self // If this line does not compile, compile the code SafeDI generates for module Callers into Callers: under Bazel, add Callers’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                func __safeDI_apiBuilder_Inner_api(_ scope_token: LazilyInstantiated<Token>, _ scope_leafBuilder: Instantiator<Leaf>) -> any Api {
		                    func __safeDI_api() -> LiveApi {
		                        @Sendable nonisolated func __safeDI_readerBuilder() -> Reader {
		                            Reader(token: token)
		                        }
		                        let readerBuilder = SendableInstantiator<Reader>(__safeDI_readerBuilder)
		                        return LiveApi(readerBuilder: readerBuilder)
		                    }
		                    let api: any Api = __safeDI_api()
		                    return api
		                }
		                func __safeDI_apiBuilder_F1() -> F1.__safeDI_ApiCarrier<any Api> {
		                    .init(inner: __safeDI_apiBuilder_Inner())
		                }
		                func __safeDI_apiBuilder_Inner() -> Inner.__safeDI_ApiCarrier<any Api> {
		                    .init(api: { scope_token, scope_leafBuilder in __safeDI_apiBuilder_Inner_api(scope_token, scope_leafBuilder) })
		                }
		                return F1(__safeDI_service: service, __safeDI_token: token.instance, __safeDI_apiBuilder: __safeDI_apiBuilder_F1())
		            }
		            let f1: F1 = __safeDI_f1()
		            return Mid(token: token, service: service, f0: f0, f1: f1)
		        }
		        let mid: Mid = __safeDI_mid()
		        self.init(mid: mid)
		    }
		}
		""")
	}

	/// `Inner`'s fill builds `Reader`, which receives `token` only if available, a value no field hands the fill. `Mid`,
	/// beneath the root, declares `token` and calls `F0` and `F1`, so each fill reads `Mid`'s `token` and stays in its call,
	/// where the root declares none (`ScopeGenerator.readsOnlyHandedForms(handedParameters:)`).
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsFillInItsCall_whenFillReadsValueOnlyIfAvailableDeclaredBeneathRoot() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.onlyIfAvailableReadModules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Callers)
		import Callers
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Seam)
		import Seam
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_mid() -> Mid {
		            let token = Token()
		            let service = Service()
		            func __safeDI_f0() -> F0 {
		                _ = F0.__safeDI_F0_8A4A2258C5C348BD.self // If this line does not compile, compile the code SafeDI generates for module Callers into Callers: under Bazel, add Callers’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                func __safeDI_apiBuilder_Inner_api() -> any Api {
		                    func __safeDI_api() -> LiveApi {
		                        let reader = Reader(token: token)
		                        return LiveApi(reader: reader)
		                    }
		                    let api: any Api = __safeDI_api()
		                    return api
		                }
		                func __safeDI_apiBuilder_F0() -> F0.__safeDI_ApiCarrier<any Api> {
		                    .init(inner: __safeDI_apiBuilder_Inner())
		                }
		                func __safeDI_apiBuilder_Inner() -> Inner.__safeDI_ApiCarrier<any Api> {
		                    .init(api: { __safeDI_apiBuilder_Inner_api() })
		                }
		                return F0(__safeDI_service: service, __safeDI_apiBuilder: __safeDI_apiBuilder_F0())
		            }
		            let f0: F0 = __safeDI_f0()
		            func __safeDI_f1() -> F1 {
		                _ = F1.__safeDI_F1_455D433B11798DC6.self // If this line does not compile, compile the code SafeDI generates for module Callers into Callers: under Bazel, add Callers’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                func __safeDI_apiBuilder_Inner_api() -> any Api {
		                    func __safeDI_api() -> LiveApi {
		                        let reader = Reader(token: token)
		                        return LiveApi(reader: reader)
		                    }
		                    let api: any Api = __safeDI_api()
		                    return api
		                }
		                func __safeDI_apiBuilder_F1() -> F1.__safeDI_ApiCarrier<any Api> {
		                    .init(inner: __safeDI_apiBuilder_Inner())
		                }
		                func __safeDI_apiBuilder_Inner() -> Inner.__safeDI_ApiCarrier<any Api> {
		                    .init(api: { __safeDI_apiBuilder_Inner_api() })
		                }
		                return F1(__safeDI_service: service, __safeDI_apiBuilder: __safeDI_apiBuilder_F1())
		            }
		            let f1: F1 = __safeDI_f1()
		            return Mid(token: token, service: service, f0: f0, f1: f1)
		        }
		        let mid: Mid = __safeDI_mid()
		        self.init(mid: mid)
		    }
		}
		""")
	}

	/// `Home`'s fill builds `LiveApi`, which receives `logger` only if available. `Feature`, beneath the root, declares
	/// `logger`, so the call lists the read of a `Logger?` property while its declaration is a `Logger`. The text reads the
	/// label at every place that shares it, so the label is required and the root is laid out by type: `Panel`'s function
	/// takes `logger` as a `Logger`.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutRootByType_whenFilledCallReadsValueOnlyIfAvailableDeclaredBeneathRoot() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.onlyIfAvailableLayoutModules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_panel(logger: Logger) -> Panel {
		            func __safeDI_home() -> Home {
		                _ = Home.__safeDI_Home_59C182C3751C58E0.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		                    .init(api: {
		                        let api: any Api = LiveApi(logger: logger)
		                        return api
		                    })
		                }
		                return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
		            }
		            let home: Home = __safeDI_home()
		            return Panel(home: home)
		        }
		        func __safeDI_feature() -> Feature {
		            let logger = Logger()
		            let panel: Panel = __safeDI_panel(logger: logger)
		            return Feature(logger: logger, panel: panel)
		        }
		        let feature: Feature = __safeDI_feature()
		        func __safeDI_left() -> Left {
		            let shared = Shared()
		            return Left(shared: shared)
		        }
		        let left: Left = __safeDI_left()
		        func __safeDI_right() -> Right {
		            let shared = Shared()
		            return Right(shared: shared)
		        }
		        let right: Right = __safeDI_right()
		        self.init(feature: feature, left: left, right: right)
		    }
		}
		""")
	}

	/// `W` is built again through `T3`'s instantiator, so its function is called with `v1` as the root's `V1` and, beneath
	/// `T0`, as `T0`'s `LazilyInstantiated<V1>`, while the call of `S0` inside it reads `v1` as a value: no one parameter
	/// type answers both, so the statement that builds `wBuilder` keeps the path key's code. `Left` and `Right` reach no
	/// such place and are still laid out by type: `Shared`'s function is declared once for both.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutOtherRootStatementsByType_whenOneStatementReachesFilledCallTheTypeKeyCannotShare() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.lazyCycleFallbackModules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_liveApi_ApiBuilder_S0_In0_Scope_apiBuilder() -> ErasedInstantiator<(), any Api>.Builder {
		            func __safeDI_apiBuilder() -> LiveApi {
		                LiveApi()
		            }
		            return { _ in __safeDI_apiBuilder() }
		        }
		        func __safeDI_liveApi_ApiBuilder_S0() -> S0.__safeDI_LiveApi_ApiCarrier<any Api> {
		            .init(in0: { values_v1 in __safeDI_liveApi_ApiBuilder_S0_In0_Scope() })
		        }
		        func __safeDI_liveApi_ApiBuilder_S0_In0_Scope() -> S0.__safeDI_LiveApi_ApiCarrier_In0<any Api> {
		            .init(apiBuilder: { __safeDI_liveApi_ApiBuilder_S0_In0_Scope_apiBuilder() })
		        }
		        let v1 = V1()
		        func __safeDI_wBuilder(v1: V1) -> W {
		            func __safeDI_t0() -> T0 {
		                func __safeDI_v1() -> V1 {
		                    V1()
		                }
		                let v1 = LazilyInstantiated<V1>(__safeDI_v1)
		                func __safeDI_t3() -> T3 {
		                    let wBuilder = Instantiator<W> {
		                        __safeDI_wBuilder(v1: v1.instance)
		                    }
		                    return T3(wBuilder: wBuilder)
		                }
		                let t3: T3 = __safeDI_t3()
		                return T0(v1: v1, t3: t3)
		            }
		            let t0: T0 = __safeDI_t0()
		            func __safeDI_t3() -> T3 {
		                let wBuilder = Instantiator<W> {
		                    __safeDI_wBuilder(v1: v1)
		                }
		                return T3(wBuilder: wBuilder)
		            }
		            let t3: T3 = __safeDI_t3()
		            func __safeDI_s0() -> S0 {
		                _ = S0.__safeDI_S0_B89382A9F3250846.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                return S0(__safeDI_v1: v1, __safeDI_liveApi_ApiBuilder: __safeDI_liveApi_ApiBuilder_S0())
		            }
		            let s0: S0 = __safeDI_s0()
		            return W(t0: t0, t3: t3, s0: s0)
		        }
		        let wBuilder = Instantiator<W> {
		            __safeDI_wBuilder(v1: v1)
		        }
		        func __safeDI_shared() -> Shared {
		            let leaf = Leaf()
		            return Shared(leaf: leaf)
		        }
		        func __safeDI_left() -> Left {
		            let shared: Shared = __safeDI_shared()
		            return Left(shared: shared)
		        }
		        let left: Left = __safeDI_left()
		        func __safeDI_right() -> Right {
		            let shared: Shared = __safeDI_shared()
		            return Right(shared: shared)
		        }
		        let right: Right = __safeDI_right()
		        self.init(v1: v1, wBuilder: wBuilder, left: left, right: right)
		    }
		}
		""")
	}

	/// `Inner` takes `token`, which its `Leaf` receives, and its `api` place `LiveApi` fills. The root's call of `Inner`
	/// hands the root's `token`, so its fill and dispatcher read the call's values and stay in it. The fill builds `Outer`,
	/// which opens `Inner`, whose dispatcher the call inside the fill names as the root's call names its own. The root's
	/// `outer` calls `Outer` too, so that dispatcher has a record the root could declare at its top, where the fill's call of
	/// it would reach the root's `Outer` call's functions instead of its own: each stays in its call, so what the root's
	/// `inner` builds does not depend on whether the root also holds `outer`.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsRootFunctionInItsCall_whenItCallsFunctionAnEnclosingCallDeclaresInPlace() async throws {
		let modules = Self.inPlaceCalleeModules
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(InnerSeam)
		import InnerSeam
		#endif
		#if canImport(OuterSeam)
		import OuterSeam
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Root {
		    public convenience init() {
		        let token = Token()
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_F86A70B275C4BA6F.self // If this line does not compile, compile the code SafeDI generates for module InnerSeam into InnerSeam: under Bazel, add InnerSeam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_apiBuilder_Inner_api(_ scope_token: LazilyInstantiated<Token>, _ scope_leafBuilder: Instantiator<Leaf>) -> any Api {
		                func __safeDI_api() -> LiveApi {
		                    func __safeDI_outerBuilder() -> Outer {
		                        _ = Outer.__safeDI_Outer_DE0AB35781D8E4A3.self // If this line does not compile, compile the code SafeDI generates for module OuterSeam into OuterSeam: under Bazel, add OuterSeam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                        func __safeDI_apiBuilder_Outer() -> Outer.__safeDI_ApiCarrier<any Api> {
		                            .init(innerBuilder: __safeDI_apiBuilder_Inner())
		                        }
		                        return Outer(__safeDI_apiBuilder: __safeDI_apiBuilder_Outer())
		                    }
		                    let outerBuilder = Instantiator<Outer>(__safeDI_outerBuilder)
		                    return LiveApi(token: token, outerBuilder: outerBuilder)
		                }
		                let api: any Api = __safeDI_api()
		                return api
		            }
		            func __safeDI_apiBuilder_Inner() -> Inner.__safeDI_ApiCarrier<any Api> {
		                .init(api: { scope_token, scope_leafBuilder in __safeDI_apiBuilder_Inner_api(scope_token, scope_leafBuilder) })
		            }
		            return Inner(__safeDI_token: token, __safeDI_apiBuilder: __safeDI_apiBuilder_Inner())
		        }
		        let inner: Inner = __safeDI_inner()
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_DE0AB35781D8E4A3.self // If this line does not compile, compile the code SafeDI generates for module OuterSeam into OuterSeam: under Bazel, add OuterSeam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_apiBuilder_Inner_api(_ scope_token: LazilyInstantiated<Token>, _ scope_leafBuilder: Instantiator<Leaf>) -> any Api {
		                let token = scope_token
		                func __safeDI_api() -> LiveApi {
		                    func __safeDI_outerBuilder() -> Outer {
		                        _ = Outer.__safeDI_Outer_DE0AB35781D8E4A3.self // If this line does not compile, compile the code SafeDI generates for module OuterSeam into OuterSeam: under Bazel, add OuterSeam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                        return Outer(__safeDI_apiBuilder: __safeDI_apiBuilder_Outer())
		                    }
		                    let outerBuilder = Instantiator<Outer>(__safeDI_outerBuilder)
		                    return LiveApi(token: token.instance, outerBuilder: outerBuilder)
		                }
		                let api: any Api = __safeDI_api()
		                return api
		            }
		            func __safeDI_apiBuilder_Outer() -> Outer.__safeDI_ApiCarrier<any Api> {
		                .init(innerBuilder: __safeDI_apiBuilder_Inner())
		            }
		            func __safeDI_apiBuilder_Inner() -> Inner.__safeDI_ApiCarrier<any Api> {
		                .init(api: { scope_token, scope_leafBuilder in __safeDI_apiBuilder_Inner_api(scope_token, scope_leafBuilder) })
		            }
		            return Outer(__safeDI_apiBuilder: __safeDI_apiBuilder_Outer())
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(token: token, inner: inner, outer: outer)
		    }
		}
		""")
		guard compileVerificationIsEnabled else { return }
		let withoutOuterModules = modules.map { module in
			guard module.name == "App" else { return module }
			return ModuleFixture(name: module.name, packageName: module.packageName, swiftFileContentByFilePath: module.swiftFileContentByFilePath.mapValues {
				$0.replacingOccurrences(of: "public init(token: Token, inner: Inner, outer: Outer) {", with: "public init(token: Token, inner: Inner) {")
					.replacingOccurrences(of: "        self.outer = outer\n", with: "")
					.replacingOccurrences(of: "    @Instantiated public let outer: Outer\n", with: "")
			}, dependencies: module.dependencies)
		}
		let withoutOuterOutput = try await executeSafeDIToolMultiModuleTest(modules: withoutOuterModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		try await expectDifferentialValuesAgree(
			feature: DifferentialValuePath(output: output, modules: modules),
			knownRight: DifferentialValuePath(output: withoutOuterOutput, modules: withoutOuterModules),
			probes: [DifferentialValueProbe(
				name: "the token the LiveApi of the Outer the root's inner opens reads",
				expression: """
				{ () -> [Bool] in
				    let root = Root()
				    let outer = (root.inner.api as! LiveApi).outerBuilder.instantiate()
				    let token = (outer.innerBuilder.instantiate().api as! LiveApi).token
				    return [token === root.token, token === outer.token]
				}()
				""",
			)],
			filesToDelete: &filesToDelete,
		)
	}

	/// `Inner`'s fill is named `__safeDI_apiBuilder_Inner_api`, and `Mid`, between the root and the call of `Inner` inside
	/// `Child`, declares a builder function of that name for its `apiBuilder_Inner_api`. `Outer` calls `Inner` too, so the
	/// two calls' dispatchers differ and stay in their calls, and `Mid`'s statement keeps the path key's code: a fill the root
	/// declared at its top would be hidden by `Mid`'s function where `Child`'s dispatcher calls it, so it stays in its call.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsFillInItsCall_whenBuilderFunctionBetweenRootAndCallTakesFillsName() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.builderNamedAsFillModules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(InnerSeam)
		import InnerSeam
		#endif
		#if canImport(OuterSeam)
		import OuterSeam
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_apiBuilder_Outer_api(_ scope_token: Token, _ scope_innerBuilder: Instantiator<Inner>) -> any Api {
		            let token = scope_token
		            func __safeDI_api() -> LiveApi {
		                func __safeDI_extra() -> Extra {
		                    let part = Part()
		                    return Extra(part: part)
		                }
		                let extra: Extra = __safeDI_extra()
		                return LiveApi(token: token, extra: extra)
		            }
		            let api: any Api = __safeDI_api()
		            return api
		        }
		        func __safeDI_apiBuilder_Inner_Inner_api(_ scope_token: Token) -> any Api {
		            let token = scope_token
		            func __safeDI_api() -> LiveApi {
		                func __safeDI_extra() -> Extra {
		                    let part = Part()
		                    return Extra(part: part)
		                }
		                let extra: Extra = __safeDI_extra()
		                return LiveApi(token: token, extra: extra)
		            }
		            let api: any Api = __safeDI_api()
		            return api
		        }
		        let token = Token()
		        func __safeDI_mid() -> Mid {
		            func __safeDI_apiBuilder_Inner_api() -> Extra {
		                let part = Part()
		                return Extra(part: part)
		            }
		            let apiBuilder_Inner_api: Extra = __safeDI_apiBuilder_Inner_api()
		            func __safeDI_child() -> Child {
		                func __safeDI_inner() -> Inner {
		                    _ = Inner.__safeDI_Inner_058A9DC2CD763CF7.self // If this line does not compile, compile the code SafeDI generates for module InnerSeam into InnerSeam: under Bazel, add InnerSeam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                    func __safeDI_apiBuilder_Inner_api(_ scope_token: Token) -> any Api {
		                        let token = scope_token
		                        func __safeDI_api() -> LiveApi {
		                            func __safeDI_extra() -> Extra {
		                                let part = Part()
		                                return Extra(part: part)
		                            }
		                            let extra: Extra = __safeDI_extra()
		                            return LiveApi(token: token, extra: extra)
		                        }
		                        let api: any Api = __safeDI_api()
		                        return api
		                    }
		                    func __safeDI_apiBuilder_Inner() -> Inner.__safeDI_ApiCarrier<any Api> {
		                        .init(api: { scope_token in __safeDI_apiBuilder_Inner_api(scope_token) })
		                    }
		                    return Inner(__safeDI_token: token, __safeDI_apiBuilder: __safeDI_apiBuilder_Inner())
		                }
		                let inner: Inner = __safeDI_inner()
		                return Child(inner: inner)
		            }
		            let child: Child = __safeDI_child()
		            func __safeDI_outer() -> Outer {
		                _ = Outer.__safeDI_Outer_5F0A5BAD4C94F93A.self // If this line does not compile, compile the code SafeDI generates for module OuterSeam into OuterSeam: under Bazel, add OuterSeam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                func __safeDI_apiBuilder_Outer() -> Outer.__safeDI_ApiCarrier<any Api> {
		                    .init(api: { scope_token, scope_innerBuilder in __safeDI_apiBuilder_Outer_api(scope_token, scope_innerBuilder) }, innerBuilder: __safeDI_apiBuilder_Inner())
		                }
		                func __safeDI_apiBuilder_Inner() -> Inner.__safeDI_ApiCarrier<any Api> {
		                    .init(api: { scope_token in __safeDI_apiBuilder_Inner_Inner_api(scope_token) })
		                }
		                return Outer(__safeDI_token: token, __safeDI_apiBuilder: __safeDI_apiBuilder_Outer())
		            }
		            let outer: Outer = __safeDI_outer()
		            return Mid(apiBuilder_Inner_api: apiBuilder_Inner_api, child: child, outer: outer)
		        }
		        let mid: Mid = __safeDI_mid()
		        self.init(token: token, mid: mid)
		    }
		}
		""")
	}

	// MARK: Fixtures

	/// The modules of `generate_keepsFillInItsCall_whenBuilderFunctionBetweenRootAndCallTakesFillsName`.
	private static let builderNamedAsFillModules = [
		ModuleFixture(name: "InnerSeam", packageName: "pkg", swiftFileContentByFilePath: ["Inner.swift": """
		import SafeDI

		nonisolated public protocol Api {}

		@Instantiable
		public final class Token: Instantiable {
		    public init() {}
		}

		@Instantiable(generateDependencyTree: true)
		public final class Inner: Instantiable {
		    public init(token: Token, api: any Api) {
		        self.token = token
		        self.api = api
		    }

		    @Received let token: Token
		    @Instantiated let api: any Api
		}
		"""]),
		ModuleFixture(name: "OuterSeam", packageName: "pkg", swiftFileContentByFilePath: ["Outer.swift": """
		import InnerSeam
		import SafeDI

		@Instantiable(generateDependencyTree: true)
		public final class Outer: Instantiable {
		    public init(token: Token, api: any Api, innerBuilder: Instantiator<Inner>) {
		        self.token = token
		        self.api = api
		        self.innerBuilder = innerBuilder
		    }

		    @Received let token: Token
		    @Instantiated let api: any Api
		    @Instantiated let innerBuilder: Instantiator<Inner>
		}
		"""], dependencies: ["InnerSeam"]),
		ModuleFixture(name: "App", packageName: "pkg", swiftFileContentByFilePath: ["Root.swift": """
		import InnerSeam
		import OuterSeam
		import SafeDI

		@Instantiable(fulfillingAdditionalTypes: [(any Api).self])
		public final class LiveApi: Api, Instantiable {
		    public init(token: Token, extra: Extra) {
		        self.token = token
		        self.extra = extra
		    }

		    @Received let token: Token
		    @Instantiated let extra: Extra
		}

		@Instantiable
		public final class Part: Instantiable {
		    public init() {}
		}

		@Instantiable
		public final class Extra: Instantiable {
		    public init(part: Part) {
		        self.part = part
		    }

		    @Instantiated let part: Part
		}

		@Instantiable
		public final class Child: Instantiable {
		    public init(inner: Inner) {
		        self.inner = inner
		    }

		    @Instantiated let inner: Inner
		}

		@Instantiable
		public final class Mid: Instantiable {
		    public init(apiBuilder_Inner_api: Extra, child: Child, outer: Outer) {
		        self.apiBuilder_Inner_api = apiBuilder_Inner_api
		        self.child = child
		        self.outer = outer
		    }

		    @Instantiated let apiBuilder_Inner_api: Extra
		    @Instantiated let child: Child
		    @Instantiated let outer: Outer
		}

		@Instantiable(isRoot: true)
		public final class Root: Instantiable {
		    public init(token: Token, mid: Mid) {
		        self.token = token
		        self.mid = mid
		    }

		    @Instantiated let token: Token
		    @Instantiated let mid: Mid
		}
		"""], dependencies: ["InnerSeam", "OuterSeam"]),
	]

	/// The modules of `generate_keepsRootFunctionInItsCall_whenItCallsFunctionAnEnclosingCallDeclaresInPlace`.
	private static let inPlaceCalleeModules = [
		ModuleFixture(name: "InnerSeam", packageName: "pkg", swiftFileContentByFilePath: ["Inner.swift": """
		import SafeDI

		nonisolated public protocol Api: AnyObject {}

		@Instantiable
		public final class Token: Instantiable {
		    public init() {}
		}

		@Instantiable
		public final class Leaf: Instantiable {
		    public init(token: Token) {
		        self.token = token
		    }

		    @Received public let token: Token
		}

		@Instantiable(generateDependencyTree: true)
		public final class Inner: Instantiable {
		    public init(leafBuilder: Instantiator<Leaf>, api: any Api) {
		        self.leafBuilder = leafBuilder
		        self.api = api
		    }

		    @Instantiated public let leafBuilder: Instantiator<Leaf>
		    @Instantiated public let api: any Api
		}
		"""]),
		ModuleFixture(name: "OuterSeam", packageName: "pkg", swiftFileContentByFilePath: ["Outer.swift": """
		import InnerSeam
		import SafeDI

		@Instantiable(generateDependencyTree: true)
		public final class Outer: Instantiable {
		    public init(token: Token, innerBuilder: Instantiator<Inner>) {
		        self.token = token
		        self.innerBuilder = innerBuilder
		    }

		    @Instantiated public let token: Token
		    @Instantiated public let innerBuilder: Instantiator<Inner>
		}
		"""], dependencies: ["InnerSeam"]),
		ModuleFixture(name: "App", packageName: "pkg", swiftFileContentByFilePath: ["Root.swift": """
		import InnerSeam
		import OuterSeam
		import SafeDI

		@Instantiable(fulfillingAdditionalTypes: [(any Api).self])
		public final class LiveApi: Api, Instantiable {
		    public init(token: Token, outerBuilder: Instantiator<Outer>) {
		        self.token = token
		        self.outerBuilder = outerBuilder
		    }

		    @Received public let token: Token
		    @Instantiated public let outerBuilder: Instantiator<Outer>
		}

		@Instantiable(isRoot: true)
		public final class Root: Instantiable {
		    public init(token: Token, inner: Inner, outer: Outer) {
		        self.token = token
		        self.inner = inner
		        self.outer = outer
		    }

		    @Instantiated public let token: Token
		    @Instantiated public let inner: Inner
		    @Instantiated public let outer: Outer
		}
		"""], dependencies: ["InnerSeam", "OuterSeam"]),
	]

	/// The modules of `generate_laysOutOtherRootStatementsByType_whenOneStatementReachesFilledCallTheTypeKeyCannotShare`.
	private static let lazyCycleFallbackModules = [
		ModuleFixture(name: "Core", packageName: "pkg", swiftFileContentByFilePath: ["Types.swift": """
		import SafeDI

		nonisolated public protocol Api {}

		@Instantiable
		public final class V1: Instantiable {
		    public init() {}
		}

		@Instantiable
		public final class In0: Instantiable {
		    public init(apiBuilder: ErasedInstantiator<(), any Api>, v1: V1) {
		        self.apiBuilder = apiBuilder
		        self.v1 = v1
		    }

		    @Instantiated(fulfilledByType: "LiveApi") let apiBuilder: ErasedInstantiator<(), any Api>
		    @Received let v1: V1
		}

		@Instantiable(generateDependencyTree: true)
		public final class S0: Instantiable {
		    public init(in0: In0) {
		        self.in0 = in0
		    }

		    @Instantiated let in0: In0
		}
		"""]),
		ModuleFixture(name: "App", packageName: "pkg", swiftFileContentByFilePath: ["Root.swift": """
		import Core
		import SafeDI

		@Instantiable(fulfillingAdditionalTypes: [(any Api).self])
		public final class LiveApi: Api, Instantiable {
		    public init() {}
		}

		@Instantiable
		public final class T3: Instantiable {
		    public init(wBuilder: Instantiator<W>) {
		        self.wBuilder = wBuilder
		    }

		    @Instantiated let wBuilder: Instantiator<W>
		}

		@Instantiable
		public final class T0: Instantiable {
		    public init(v1: LazilyInstantiated<V1>, t3: T3) {
		        self.v1 = v1
		        self.t3 = t3
		    }

		    @Instantiated let v1: LazilyInstantiated<V1>
		    @Instantiated let t3: T3
		}

		@Instantiable
		public final class W: Instantiable {
		    public init(t0: T0, t3: T3, s0: S0) {
		        self.t0 = t0
		        self.t3 = t3
		        self.s0 = s0
		    }

		    @Instantiated let t0: T0
		    @Instantiated let t3: T3
		    @Instantiated let s0: S0
		}

		@Instantiable
		public final class Leaf: Instantiable {
		    public init() {}
		}

		@Instantiable
		public final class Shared: Instantiable {
		    public init(leaf: Leaf) {
		        self.leaf = leaf
		    }

		    @Instantiated let leaf: Leaf
		}

		@Instantiable
		public final class Left: Instantiable {
		    public init(shared: Shared) {
		        self.shared = shared
		    }

		    @Instantiated let shared: Shared
		}

		@Instantiable
		public final class Right: Instantiable {
		    public init(shared: Shared) {
		        self.shared = shared
		    }

		    @Instantiated let shared: Shared
		}

		@Instantiable(isRoot: true)
		public final class Root: Instantiable {
		    public init(v1: V1, wBuilder: Instantiator<W>, left: Left, right: Right) {
		        self.v1 = v1
		        self.wBuilder = wBuilder
		        self.left = left
		        self.right = right
		    }

		    @Instantiated let v1: V1
		    @Instantiated let wBuilder: Instantiator<W>
		    @Instantiated let left: Left
		    @Instantiated let right: Right
		}
		"""], dependencies: ["Core"]),
	]

	/// The modules of `generate_laysOutRootByType_whenFilledCallReadsValueOnlyIfAvailableDeclaredBeneathRoot`.
	private static let onlyIfAvailableLayoutModules = [
		ModuleFixture(name: "Core", packageName: "pkg", swiftFileContentByFilePath: ["Types.swift": """
		import SafeDI

		nonisolated public protocol Api {}

		@Instantiable
		public final class Logger: Instantiable {
		    public init() {}
		}

		@Instantiable(generateDependencyTree: true)
		public final class Home: Instantiable {
		    public init(api: any Api) {
		        self.api = api
		    }

		    @Instantiated let api: any Api
		}
		"""]),
		ModuleFixture(name: "App", packageName: "pkg", swiftFileContentByFilePath: ["Root.swift": """
		import Core
		import SafeDI

		@Instantiable(fulfillingAdditionalTypes: [(any Api).self])
		public final class LiveApi: Api, Instantiable {
		    public init(logger: Logger?) {
		        self.logger = logger
		    }

		    @Received(onlyIfAvailable: true) let logger: Logger?
		}

		@Instantiable
		public final class Panel: Instantiable {
		    public init(home: Home) {
		        self.home = home
		    }

		    @Instantiated let home: Home
		}

		@Instantiable
		public final class Feature: Instantiable {
		    public init(logger: Logger, panel: Panel) {
		        self.logger = logger
		        self.panel = panel
		    }

		    @Instantiated let logger: Logger
		    @Instantiated let panel: Panel
		}

		@Instantiable
		public final class Shared: Instantiable {
		    public init() {}
		}

		@Instantiable
		public final class Left: Instantiable {
		    public init(shared: Shared) {
		        self.shared = shared
		    }

		    @Instantiated let shared: Shared
		}

		@Instantiable
		public final class Right: Instantiable {
		    public init(shared: Shared) {
		        self.shared = shared
		    }

		    @Instantiated let shared: Shared
		}

		@Instantiable(isRoot: true)
		public final class Root: Instantiable {
		    public init(feature: Feature, left: Left, right: Right) {
		        self.feature = feature
		        self.left = left
		        self.right = right
		    }

		    @Instantiated let feature: Feature
		    @Instantiated let left: Left
		    @Instantiated let right: Right
		}
		"""], dependencies: ["Core"]),
	]

	/// The modules of `generate_keepsFillInItsCall_whenFillReadsValueOnlyIfAvailableDeclaredBeneathRoot`.
	private static let onlyIfAvailableReadModules = [
		ModuleFixture(name: "Seam", packageName: "pkg", swiftFileContentByFilePath: ["Types.swift": """
		import SafeDI

		nonisolated public protocol Api {}

		@Instantiable
		public final class Service: Instantiable {
		    public init() {}
		}

		@Instantiable
		public final class Token: Instantiable {
		    public init() {}
		}

		@Instantiable(generateDependencyTree: true)
		public final class Inner: Instantiable {
		    public init(api: any Api) {
		        self.api = api
		    }

		    @Instantiated let api: any Api
		}
		"""]),
		ModuleFixture(name: "Callers", packageName: "pkg", swiftFileContentByFilePath: ["Types.swift": """
		import SafeDI
		import Seam

		@Instantiable(generateDependencyTree: true)
		public final class F0: Instantiable {
		    public init(service: Service, inner: Inner) {
		        self.service = service
		        self.inner = inner
		    }

		    @Received let service: Service
		    @Instantiated let inner: Inner
		}

		@Instantiable(generateDependencyTree: true)
		public final class F1: Instantiable {
		    public init(service: Service, inner: Inner) {
		        self.service = service
		        self.inner = inner
		    }

		    @Received let service: Service
		    @Instantiated let inner: Inner
		}
		"""], dependencies: ["Seam"]),
		ModuleFixture(name: "App", packageName: "pkg", swiftFileContentByFilePath: ["Root.swift": """
		import Callers
		import SafeDI
		import Seam

		@Instantiable(fulfillingAdditionalTypes: [(any Api).self])
		public final class LiveApi: Api, Instantiable {
		    public init(reader: Reader) {
		        self.reader = reader
		    }

		    @Instantiated let reader: Reader
		}

		@Instantiable
		public final class Reader: Instantiable {
		    public init(token: Token?) {
		        self.token = token
		    }

		    @Received(onlyIfAvailable: true) let token: Token?
		}

		@Instantiable
		public final class Mid: Instantiable {
		    public init(token: Token, service: Service, f0: F0, f1: F1) {
		        self.token = token
		        self.service = service
		        self.f0 = f0
		        self.f1 = f1
		    }

		    @Instantiated let token: Token
		    @Instantiated let service: Service
		    @Instantiated let f0: F0
		    @Instantiated let f1: F1
		}

		@Instantiable(isRoot: true)
		public final class Root: Instantiable {
		    public init(mid: Mid) {
		        self.mid = mid
		    }

		    @Instantiated let mid: Mid
		}
		"""], dependencies: ["Callers", "Seam"]),
	]

	/// The modules of `generate_keepsFillInItsCall_whenFillReadsAnotherFormOfHandedLabelDeclaredBeneathRoot`.
	private static let wrapperFormModules = [
		ModuleFixture(name: "Seam", packageName: "pkg", swiftFileContentByFilePath: ["Types.swift": """
		import SafeDI

		nonisolated public protocol Api: Sendable {}

		@Instantiable
		public final class Service: Instantiable, Sendable {
		    public init() {}
		}

		@Instantiable
		public final class Token: Instantiable, Sendable {
		    public init() {}
		}

		@Instantiable
		public final class Leaf: Instantiable {
		    public init(token: Token) {
		        self.token = token
		    }

		    @Received let token: Token
		}

		@Instantiable(generateDependencyTree: true)
		public final class Inner: Instantiable {
		    public init(leafBuilder: Instantiator<Leaf>, api: any Api) {
		        self.leafBuilder = leafBuilder
		        self.api = api
		    }

		    @Instantiated let leafBuilder: Instantiator<Leaf>
		    @Instantiated let api: any Api
		}
		"""]),
		ModuleFixture(name: "Callers", packageName: "pkg", swiftFileContentByFilePath: ["Types.swift": """
		import SafeDI
		import Seam

		@Instantiable(generateDependencyTree: true)
		public final class F0: Instantiable {
		    public init(service: Service, inner: Inner) {
		        self.service = service
		        self.inner = inner
		    }

		    @Received let service: Service
		    @Instantiated let inner: Inner
		}

		@Instantiable(generateDependencyTree: true)
		public final class F1: Instantiable {
		    public init(service: Service, inner: Inner) {
		        self.service = service
		        self.inner = inner
		    }

		    @Received let service: Service
		    @Instantiated let inner: Inner
		}
		"""], dependencies: ["Seam"]),
		ModuleFixture(name: "App", packageName: "pkg", swiftFileContentByFilePath: ["Root.swift": """
		import Callers
		import SafeDI
		import Seam

		@Instantiable(fulfillingAdditionalTypes: [(any Api).self])
		public final class LiveApi: Api, Instantiable {
		    public init(readerBuilder: SendableInstantiator<Reader>) {
		        self.readerBuilder = readerBuilder
		    }

		    @Instantiated let readerBuilder: SendableInstantiator<Reader>
		}

		@Instantiable
		public final class Reader: Instantiable, Sendable {
		    public init(token: SendableLazilyInstantiated<Token>) {
		        self.token = token
		    }

		    @Received let token: SendableLazilyInstantiated<Token>
		}

		@Instantiable
		public final class Mid: Instantiable {
		    public init(token: SendableLazilyInstantiated<Token>, service: Service, f0: F0, f1: F1) {
		        self.token = token
		        self.service = service
		        self.f0 = f0
		        self.f1 = f1
		    }

		    @Instantiated let token: SendableLazilyInstantiated<Token>
		    @Instantiated let service: Service
		    @Instantiated let f0: F0
		    @Instantiated let f1: F1
		}

		@Instantiable(isRoot: true)
		public final class Root: Instantiable {
		    public init(mid: Mid) {
		        self.mid = mid
		    }

		    @Instantiated let mid: Mid
		}
		"""], dependencies: ["Callers", "Seam"]),
	]

	/// `Inner`, a seam of module `InnerSeam` whose `api` only `App` fills; `Outer`, a seam of module `OuterSeam` whose `api`
	/// only `App` fills too and whose tree opens `Inner`; and `App`, whose `LiveApi` fills both, instantiating `Detail`, and
	/// whose root instantiates `Outer` and, where `callsInnerThroughOuterSeam`, `InnerHost`, a seam of `OuterSeam` that
	/// instantiates `Inner`, else `Inner` itself.
	private static func siblingCallModules(callsInnerThroughOuterSeam: Bool) -> [ModuleFixture] {
		[
			ModuleFixture(name: "InnerSeam", packageName: "pkg", swiftFileContentByFilePath: ["Types.swift": """
			import SafeDI

			nonisolated public protocol Api: AnyObject {}

			@Instantiable
			public final class Service: Instantiable {
			    public init() {}
			}

			@Instantiable(generateDependencyTree: true)
			public final class Inner: Instantiable {
			    public init(service: Service, api: any Api) {
			        self.service = service
			        self.api = api
			    }

			    @Received let service: Service
			    @Instantiated let api: any Api
			}
			"""]),
			ModuleFixture(name: "OuterSeam", packageName: "pkg", swiftFileContentByFilePath: ["Types.swift": """
			import InnerSeam
			import SafeDI

			@Instantiable(generateDependencyTree: true)
			public final class Outer: Instantiable {
			    public init(service: Service, api: any Api, innerBuilder: Instantiator<Inner>) {
			        self.service = service
			        self.api = api
			        self.innerBuilder = innerBuilder
			    }

			    @Received let service: Service
			    @Instantiated let api: any Api
			    @Instantiated let innerBuilder: Instantiator<Inner>
			}
			""" + (callsInnerThroughOuterSeam ? """


			@Instantiable(generateDependencyTree: true)
			public final class InnerHost: Instantiable {
			    public init(service: Service, inner: Inner) {
			        self.service = service
			        self.inner = inner
			    }

			    @Received let service: Service
			    @Instantiated let inner: Inner
			}
			""" : "")], dependencies: ["InnerSeam"]),
			ModuleFixture(name: "App", packageName: "pkg", swiftFileContentByFilePath: ["Root.swift": """
			import InnerSeam
			import OuterSeam
			import SafeDI

			@Instantiable(fulfillingAdditionalTypes: [(any Api).self])
			public final class LiveApi: Api, Instantiable {
			    public init(service: Service, detail: Detail) {
			        self.service = service
			        self.detail = detail
			    }

			    @Received let service: Service
			    @Instantiated let detail: Detail
			}

			@Instantiable
			public final class Detail: Instantiable {
			    public init(service: Service) {
			        self.service = service
			    }

			    @Received let service: Service
			}

			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(service: Service, \(callsInnerThroughOuterSeam ? "innerHost: InnerHost" : "inner: Inner"), outer: Outer) {
			        self.service = service
			        \(callsInnerThroughOuterSeam ? "self.innerHost = innerHost" : "self.inner = inner")
			        self.outer = outer
			    }

			    @Instantiated let service: Service
			    @Instantiated let \(callsInnerThroughOuterSeam ? "innerHost: InnerHost" : "inner: Inner")
			    @Instantiated let outer: Outer
			}
			"""], dependencies: ["InnerSeam", "OuterSeam"]),
		]
	}

	/// `Last`, a seam whose `screenBuilder` only `App` can fill, and `App`, whose `AppScreen` fills it and opens `Last`
	/// again, and whose root opens both. Where `readingToken`, `AppScreen` receives `token`, which only the root declares.
	/// Where `opensLastInSendableWrapperOnly`, the root opens only `Last`, in a `SendableErasedInstantiator`.
	private static func screenModules(readingToken: Bool, opensLastInSendableWrapperOnly: Bool = false) -> [ModuleFixture] {
		let tokenParameter = readingToken ? ", token: Token" : ""
		let tokenAssignment = readingToken ? "; self.token = token" : ""
		let appScreenToken = readingToken ? "\n    @Received let token: Token" : ""
		let rootToken = readingToken ? "\n    @Instantiated let token: Token" : ""
		let root = opensLastInSendableWrapperOnly ? """
		@Instantiable(isRoot: true)
		public final class Root: Instantiable {
		    public init(service: Service, lastBuilder: SendableErasedInstantiator<Int, AnyScreen>) {
		        self.service = service; self.lastBuilder = lastBuilder
		    }
		    @Instantiated let service: Service
		    @Instantiated(fulfilledByType: "Last", erasedToConcreteExistential: true) let lastBuilder: SendableErasedInstantiator<Int, AnyScreen>
		}
		""" : """
		@Instantiable(isRoot: true)
		public final class Root: Instantiable {
		    public init(service: Service, lastBuilder: ErasedInstantiator<Int, AnyScreen>, screenBuilder: ErasedInstantiator<Int, AnyScreen>\(tokenParameter)) {
		        self.service = service; self.lastBuilder = lastBuilder; self.screenBuilder = screenBuilder\(tokenAssignment)
		    }
		    @Instantiated let service: Service
		    @Instantiated(fulfilledByType: "Last", erasedToConcreteExistential: true) let lastBuilder: ErasedInstantiator<Int, AnyScreen>
		    @Instantiated(fulfilledByType: "AppScreen", erasedToConcreteExistential: true) let screenBuilder: ErasedInstantiator<Int, AnyScreen>\(rootToken)
		}
		"""
		return [
			ModuleFixture(name: "Seam", packageName: "pkg", swiftFileContentByFilePath: ["Types.swift": """
			import SafeDI

			public final class AnyScreen {
			    public init(_ screen: AnyObject) { self.screen = screen }
			    public let screen: AnyObject
			}

			@Instantiable
			public final class Service: Instantiable, Sendable {
			    public init() {}
			}

			@Instantiable
			public final class Token: Instantiable {
			    public init() {}
			}

			@Instantiable(generateDependencyTree: true)
			public final class Last: Instantiable {
			    public init(id: Int, service: Service, screenBuilder: ErasedInstantiator<Int, AnyScreen>) {
			        self.id = id; self.service = service; self.screenBuilder = screenBuilder
			    }
			    @Forwarded let id: Int
			    @Received let service: Service
			    @Instantiated(fulfilledByType: "AppScreen", erasedToConcreteExistential: true) let screenBuilder: ErasedInstantiator<Int, AnyScreen>
			}
			"""]),
			ModuleFixture(name: "App", packageName: "pkg", swiftFileContentByFilePath: ["Root.swift": """
			import Seam
			import SafeDI

			@Instantiable
			public final class AppScreen: Instantiable {
			    public init(id: Int, service: Service, lastBuilder: ErasedInstantiator<Int, AnyScreen>\(tokenParameter)) {
			        self.id = id; self.service = service; self.lastBuilder = lastBuilder\(tokenAssignment)
			    }
			    @Forwarded let id: Int
			    @Received let service: Service
			    @Instantiated(fulfilledByType: "Last", erasedToConcreteExistential: true) let lastBuilder: ErasedInstantiator<Int, AnyScreen>\(appScreenToken)
			}


			\(root)
			"""], dependencies: ["Seam"]),
		]
	}

	private var filesToDelete: [URL]
}
