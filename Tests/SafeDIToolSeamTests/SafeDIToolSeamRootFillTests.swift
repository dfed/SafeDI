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
		let (output, disagreements) = try await collectingRootFunctionKeyDisagreements {
			try await executeSafeDIToolMultiModuleTest(modules: Self.siblingCallModules(callsInnerThroughOuterSeam: false), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}

		#expect(disagreements == [])
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
		let (output, disagreements) = try await collectingRootFunctionKeyDisagreements {
			try await executeSafeDIToolMultiModuleTest(modules: Self.siblingCallModules(callsInnerThroughOuterSeam: true), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}

		#expect(disagreements == [])
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

	// MARK: Fixtures

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
