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

/// A fill of a seam's hole is written once per root as a function of the fields it reads, which each fill of the same tree
/// calls with what its case binds (`ScopeGenerator.sharesFillBody(handedParameterFields:)`), and the root lays that function
/// out by type. A fill whose tree reads a label no field hands keeps its own body, in the path key's layout: a value the
/// caller binds, or a receive only if available its case cannot provide, which it passes `nil`. A body reached inside a
/// `@Sendable` function that is not `@Sendable` itself keeps its attributes, so each fill declares it.
///
/// `Feature` declares `F0` and `F1`, seams that receive `service` and instantiate `api: any Api`, a hole `App` fills with
/// `LiveApi`, whose tree builds `C`. Where a test has `F0` and `F1` call `Inner`, a seam that defers `token` and passes its
/// `api` place up, the place's field of `token` is a memo, which a body that reads the value takes, while a tree that reads
/// another form of `token` reads the caller's declaration and keeps its body in its fill.
struct SafeDIToolSeamSharedFillBodyTests: ~Copyable {
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
	mutating func generate_declaresFillBodyOnce_whenTwoSeamCallsFillHoleWithSameTree() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Fixture().modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_apiBuilder_F0_api(_ scope_service: Service) -> any Api {
		            return __safeDI_fillBody_4090EA3CC5C36131(service: scope_service)
		        }
		        func __safeDI_fillBody_4090EA3CC5C36131(service: Service) -> any Api {
		            func __safeDI_api() -> LiveApi {
		                let c = C(service: service)
		                return LiveApi(service: service, c: c)
		            }
		            let api: any Api = __safeDI_api()
		            return api
		        }
		        func __safeDI_apiBuilder_F0() -> F0.__safeDI_ApiCarrier<any Api> {
		            .init(api: { scope_service in __safeDI_apiBuilder_F0_api(scope_service) })
		        }
		        func __safeDI_apiBuilder_F1_api(_ scope_service: Service) -> any Api {
		            return __safeDI_fillBody_4090EA3CC5C36131(service: scope_service)
		        }
		        func __safeDI_apiBuilder_F1() -> F1.__safeDI_ApiCarrier<any Api> {
		            .init(api: { scope_service in __safeDI_apiBuilder_F1_api(scope_service) })
		        }
		        let service = Service()
		        func __safeDI_f0() -> F0 {
		            _ = F0.__safeDI_F0_D025DDBE59384E69.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return F0(__safeDI_service: service, __safeDI_apiBuilder: __safeDI_apiBuilder_F0())
		        }
		        let f0: F0 = __safeDI_f0()
		        func __safeDI_f1() -> F1 {
		            _ = F1.__safeDI_F1_3FF9291B1DFF77D6.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return F1(__safeDI_service: service, __safeDI_apiBuilder: __safeDI_apiBuilder_F1())
		        }
		        let f1: F1 = __safeDI_f1()
		        self.init(service: service, f0: f0, f1: f1)
		    }
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresFillBodyPerCase_whenOneCaseLeavesValueTreeReadsUnavailable() async throws {
		// `F0` instantiates `extra` before `api`, which its fill's tree reads where available; `F1` and `Root` bind no `extra`, so
		// `F1`'s fill passes `nil`, and the two bodies differ in text.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Fixture(
				featureTypes: ["@Instantiable public final class Extra: Instantiable { public init() {} }"],
				f0Declarations: ["@Received public let service: Service", "@Instantiated public let extra: Extra", "@Instantiated public let api: any Api"],
				liveApiDeclarations: Fixture.liveApiDeclarations + ["@Received(onlyIfAvailable: true) let extra: Extra?"],
			).modules,
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_apiBuilder_F0_api(_ scope_service: Service, _ scope_extra: Extra) -> any Api {
		            return __safeDI_fillBody_D695BC8183932011(service: scope_service, extra: scope_extra)
		        }
		        func __safeDI_fillBody_D695BC8183932011(service: Service, extra: Extra) -> any Api {
		            func __safeDI_api() -> LiveApi {
		                let c = C(service: service)
		                return LiveApi(service: service, c: c, extra: extra)
		            }
		            let api: any Api = __safeDI_api()
		            return api
		        }
		        func __safeDI_apiBuilder_F0() -> F0.__safeDI_ApiCarrier<any Api> {
		            .init(api: { scope_service, scope_extra in __safeDI_apiBuilder_F0_api(scope_service, scope_extra) })
		        }
		        let service = Service()
		        func __safeDI_f0() -> F0 {
		            _ = F0.__safeDI_F0_40750668F1945F30.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return F0(__safeDI_service: service, __safeDI_apiBuilder: __safeDI_apiBuilder_F0())
		        }
		        let f0: F0 = __safeDI_f0()
		        func __safeDI_f1() -> F1 {
		            _ = F1.__safeDI_F1_3FF9291B1DFF77D6.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_apiBuilder_F1_api(_ scope_service: Service) -> any Api {
		                let service = scope_service
		                func __safeDI_api() -> LiveApi {
		                    let c = C(service: service)
		                    return LiveApi(service: service, c: c, extra: nil)
		                }
		                let api: any Api = __safeDI_api()
		                return api
		            }
		            func __safeDI_apiBuilder_F1() -> F1.__safeDI_ApiCarrier<any Api> {
		                .init(api: { scope_service in __safeDI_apiBuilder_F1_api(scope_service) })
		            }
		            return F1(__safeDI_service: service, __safeDI_apiBuilder: __safeDI_apiBuilder_F1())
		        }
		        let f1: F1 = __safeDI_f1()
		        self.init(service: service, f0: f0, f1: f1)
		    }
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsFillBodyInFill_whenFillTreeReadsValueCallerBinds() async throws {
		// `LiveApi` receives `x`, which `Root` binds and neither seam receives: the fill reads it from the caller.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Fixture(
				appTypes: ["@Instantiable public final class X: Instantiable { public init() {} }"],
				liveApiDeclarations: Fixture.liveApiDeclarations + ["@Received let x: X"],
				rootDeclarations: ["@Instantiated let x: X"] + Fixture.rootDeclarations,
			).modules,
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        let x = X()
		        let service = Service()
		        func __safeDI_f0() -> F0 {
		            _ = F0.__safeDI_F0_D025DDBE59384E69.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_apiBuilder_F0_api(_ scope_service: Service) -> any Api {
		                let service = scope_service
		                func __safeDI_api() -> LiveApi {
		                    let c = C(service: service)
		                    return LiveApi(service: service, c: c, x: x)
		                }
		                let api: any Api = __safeDI_api()
		                return api
		            }
		            func __safeDI_apiBuilder_F0() -> F0.__safeDI_ApiCarrier<any Api> {
		                .init(api: { scope_service in __safeDI_apiBuilder_F0_api(scope_service) })
		            }
		            return F0(__safeDI_service: service, __safeDI_apiBuilder: __safeDI_apiBuilder_F0())
		        }
		        let f0: F0 = __safeDI_f0()
		        func __safeDI_f1() -> F1 {
		            _ = F1.__safeDI_F1_3FF9291B1DFF77D6.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_apiBuilder_F1_api(_ scope_service: Service) -> any Api {
		                let service = scope_service
		                func __safeDI_api() -> LiveApi {
		                    let c = C(service: service)
		                    return LiveApi(service: service, c: c, x: x)
		                }
		                let api: any Api = __safeDI_api()
		                return api
		            }
		            func __safeDI_apiBuilder_F1() -> F1.__safeDI_ApiCarrier<any Api> {
		                .init(api: { scope_service in __safeDI_apiBuilder_F1_api(scope_service) })
		            }
		            return F1(__safeDI_service: service, __safeDI_apiBuilder: __safeDI_apiBuilder_F1())
		        }
		        let f1: F1 = __safeDI_f1()
		        self.init(x: x, service: service, f0: f0, f1: f1)
		    }
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresFillBodyOnce_whenFillTreeCallsFilledSeamAgain() async throws {
		// `C` builds `F0` again through an instantiator, a call of the seam whose fill the body is, which calls the root's
		// dispatcher of `F0` by name.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Fixture(
				cDeclarations: Fixture.cDeclarations + ["@Instantiated let f0Builder: Instantiator<F0>"],
			).modules,
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_apiBuilder_F0_api(_ scope_service: Service) -> any Api {
		            return __safeDI_fillBody_1CDF274DEAADB187(service: scope_service)
		        }
		        func __safeDI_fillBody_1CDF274DEAADB187(service: Service) -> any Api {
		            func __safeDI_api() -> LiveApi {
		                func __safeDI_c() -> C {
		                    func __safeDI_f0Builder() -> F0 {
		                        _ = F0.__safeDI_F0_D025DDBE59384E69.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                        return F0(__safeDI_service: service, __safeDI_apiBuilder: __safeDI_apiBuilder_F0())
		                    }
		                    let f0Builder = Instantiator<F0>(__safeDI_f0Builder)
		                    return C(service: service, f0Builder: f0Builder)
		                }
		                let c: C = __safeDI_c()
		                return LiveApi(service: service, c: c)
		            }
		            let api: any Api = __safeDI_api()
		            return api
		        }
		        func __safeDI_apiBuilder_F0() -> F0.__safeDI_ApiCarrier<any Api> {
		            .init(api: { scope_service in __safeDI_apiBuilder_F0_api(scope_service) })
		        }
		        func __safeDI_apiBuilder_F1_api(_ scope_service: Service) -> any Api {
		            return __safeDI_fillBody_1CDF274DEAADB187(service: scope_service)
		        }
		        func __safeDI_apiBuilder_F1() -> F1.__safeDI_ApiCarrier<any Api> {
		            .init(api: { scope_service in __safeDI_apiBuilder_F1_api(scope_service) })
		        }
		        let service = Service()
		        func __safeDI_f0() -> F0 {
		            _ = F0.__safeDI_F0_D025DDBE59384E69.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return F0(__safeDI_service: service, __safeDI_apiBuilder: __safeDI_apiBuilder_F0())
		        }
		        let f0: F0 = __safeDI_f0()
		        func __safeDI_f1() -> F1 {
		            _ = F1.__safeDI_F1_3FF9291B1DFF77D6.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return F1(__safeDI_service: service, __safeDI_apiBuilder: __safeDI_apiBuilder_F1())
		        }
		        let f1: F1 = __safeDI_f1()
		        self.init(service: service, f0: f0, f1: f1)
		    }
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresFillBodyOnce_whenFillTreeClosesLazyCycleInsideFill() async throws {
		// `F0`'s hole is `Inner`'s, and `C` builds `Inner` through an instantiator, whose `api` closes a lazy cycle on the
		// fill's own builder function of `api`: the fill's tree reads nothing outside the fill, on both calls, so both share
		// the body, which the type key lays out with the cycle.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Fixture(
				featureTypes: [Fixture.type(named: "Inner", attribute: "@Instantiable", conformances: "", declarations: Fixture.seamDeclarations)],
				f0Declarations: ["@Received public let service: Service", "@Instantiated public let inner: Inner"],
				cDeclarations: Fixture.cDeclarations + ["@Instantiated let innerBuilder: Instantiator<Inner>"],
			).modules,
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_apiBuilder_F0_Inner_Scope_api(service: Service) -> any Api {
		            return __safeDI_fillBody_76F3A2DA438DEAA5(service: service)
		        }
		        func __safeDI_fillBody_76F3A2DA438DEAA5(service: Service) -> any Api {
		            func __safeDI_api() -> LiveApi {
		                let c: C = __safeDI_c()
		                return LiveApi(service: service, c: c)
		            }
		            func __safeDI_c() -> C {
		                let innerBuilder = Instantiator<Inner>(__safeDI_innerBuilder)
		                return C(service: service, innerBuilder: innerBuilder)
		            }
		            func __safeDI_innerBuilder() -> Inner {
		                let api: any Api = __safeDI_api()
		                return Inner(service: service, api: api)
		            }
		            let api: any Api = __safeDI_api()
		            return api
		        }
		        func __safeDI_apiBuilder_F0() -> F0.__safeDI_ApiCarrier<any Api> {
		            .init(inner: { values_service in __safeDI_apiBuilder_F0_Inner_Scope(service: values_service) })
		        }
		        func __safeDI_apiBuilder_F0_Inner_Scope(service: Service) -> F0.__safeDI_ApiCarrier_Inner<any Api> {
		            .init(api: { __safeDI_apiBuilder_F0_Inner_Scope_api(service: service) })
		        }
		        func __safeDI_apiBuilder_F1_api(_ scope_service: Service) -> any Api {
		            return __safeDI_fillBody_76F3A2DA438DEAA5(service: scope_service)
		        }
		        func __safeDI_apiBuilder_F1() -> F1.__safeDI_ApiCarrier<any Api> {
		            .init(api: { scope_service in __safeDI_apiBuilder_F1_api(scope_service) })
		        }
		        let service = Service()
		        func __safeDI_f0() -> F0 {
		            _ = F0.__safeDI_F0_A1D40756FC36A849.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return F0(__safeDI_service: service, __safeDI_apiBuilder: __safeDI_apiBuilder_F0())
		        }
		        let f0: F0 = __safeDI_f0()
		        func __safeDI_f1() -> F1 {
		            _ = F1.__safeDI_F1_3FF9291B1DFF77D6.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return F1(__safeDI_service: service, __safeDI_apiBuilder: __safeDI_apiBuilder_F1())
		        }
		        let f1: F1 = __safeDI_f1()
		        self.init(service: service, f0: f0, f1: f1)
		    }
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsFillBodyInEachFill_whenOneCallIsInsideSendableBuilder() async throws {
		// `Root` builds `F1` through a `SendableInstantiator`: a body reached inside a `@Sendable` function that is not
		// `@Sendable` itself keeps its attributes, so each fill declares it where the root does not.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Fixture(
				isSendable: true,
				rootDeclarations: ["@Instantiated let service: Service", "@Instantiated let f0: F0", "@Instantiated let f1Builder: SendableInstantiator<F1>"],
			).modules,
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        let service = Service()
		        func __safeDI_f0() -> F0 {
		            _ = F0.__safeDI_F0_D025DDBE59384E69.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_apiBuilder_F0_api(_ scope_service: Service) -> any Api {
		                func __safeDI_fillBody_4090EA3CC5C36131(service: Service) -> any Api {
		                    func __safeDI_api() -> LiveApi {
		                        let c = C(service: service)
		                        return LiveApi(service: service, c: c)
		                    }
		                    let api: any Api = __safeDI_api()
		                    return api
		                }
		                return __safeDI_fillBody_4090EA3CC5C36131(service: scope_service)
		            }
		            func __safeDI_apiBuilder_F0() -> F0.__safeDI_ApiCarrier<any Api> {
		                .init(api: { scope_service in __safeDI_apiBuilder_F0_api(scope_service) })
		            }
		            return F0(__safeDI_service: service, __safeDI_apiBuilder: __safeDI_apiBuilder_F0())
		        }
		        let f0: F0 = __safeDI_f0()
		        @Sendable nonisolated func __safeDI_f1Builder() -> F1 {
		            _ = F1.__safeDI_F1_3FF9291B1DFF77D6.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_apiBuilder_F1_api(_ scope_service: Service) -> any Api {
		                func __safeDI_fillBody_4090EA3CC5C36131(service: Service) -> any Api {
		                    func __safeDI_api() -> LiveApi {
		                        let c = C(service: service)
		                        return LiveApi(service: service, c: c)
		                    }
		                    let api: any Api = __safeDI_api()
		                    return api
		                }
		                return __safeDI_fillBody_4090EA3CC5C36131(service: scope_service)
		            }
		            func __safeDI_apiBuilder_F1() -> F1.__safeDI_ApiCarrier<any Api> {
		                .init(api: { scope_service in __safeDI_apiBuilder_F1_api(scope_service) })
		            }
		            return F1(__safeDI_service: service, __safeDI_apiBuilder: __safeDI_apiBuilder_F1())
		        }
		        let f1Builder = SendableInstantiator<F1>(__safeDI_f1Builder)
		        self.init(service: service, f0: f0, f1Builder: f1Builder)
		    }
		}
		"""])
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesFillBodyApartFromDirectoryOfFileItPointsAt_whenFillTreeRefersToAliasDeclarationByDirective(integration: MultiModuleIntegration) async throws {
		// `C` renames `service`, so the body points the compiler at `C`'s declaration with a `#sourceLocation` directive,
		// which names `C.swift` by a path each integration spells apart, and each checkout too; and `C` builds `F0` again,
		// whose guard's comment each integration words apart: the body's name is the same.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Fixture(cDeclarations: [Fixture.renamingDeclaration, "@Instantiated let f0Builder: Instantiator<F0>"]).modules,
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		let app = try #require(output.modules["App"])
		switch integration {
		case .moduleInfo:
			let cPath = app.fixtures["C.swift"]
			expectGeneratedFiles(app.generatedFiles, ["App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public convenience init() {
			        func __safeDI_apiBuilder_F0_api(_ scope_service: Service) -> any Api {
			            return __safeDI_fillBody_DA998F868C342499(service: scope_service)
			        }
			        func __safeDI_fillBody_DA998F868C342499(service: Service) -> any Api {
			            func __safeDI_api() -> LiveApi {
			                func __safeDI_c() -> C {
			                    #sourceLocation(file: "\(cPath)", line: 5)
			                    let renamedService: Service = service
			                    #sourceLocation()
			                    func __safeDI_f0Builder() -> F0 {
			                        _ = F0.__safeDI_F0_D025DDBE59384E69.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			                        return F0(__safeDI_service: service, __safeDI_apiBuilder: __safeDI_apiBuilder_F0())
			                    }
			                    let f0Builder = Instantiator<F0>(__safeDI_f0Builder)
			                    return C(renamedService: renamedService, f0Builder: f0Builder)
			                }
			                let c: C = __safeDI_c()
			                return LiveApi(service: service, c: c)
			            }
			            let api: any Api = __safeDI_api()
			            return api
			        }
			        func __safeDI_apiBuilder_F0() -> F0.__safeDI_ApiCarrier<any Api> {
			            .init(api: { scope_service in __safeDI_apiBuilder_F0_api(scope_service) })
			        }
			        func __safeDI_apiBuilder_F1_api(_ scope_service: Service) -> any Api {
			            return __safeDI_fillBody_DA998F868C342499(service: scope_service)
			        }
			        func __safeDI_apiBuilder_F1() -> F1.__safeDI_ApiCarrier<any Api> {
			            .init(api: { scope_service in __safeDI_apiBuilder_F1_api(scope_service) })
			        }
			        let service = Service()
			        func __safeDI_f0() -> F0 {
			            _ = F0.__safeDI_F0_D025DDBE59384E69.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return F0(__safeDI_service: service, __safeDI_apiBuilder: __safeDI_apiBuilder_F0())
			        }
			        let f0: F0 = __safeDI_f0()
			        func __safeDI_f1() -> F1 {
			            _ = F1.__safeDI_F1_3FF9291B1DFF77D6.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return F1(__safeDI_service: service, __safeDI_apiBuilder: __safeDI_apiBuilder_F1())
			        }
			        let f1: F1 = __safeDI_f1()
			        self.init(service: service, f0: f0, f1: f1)
			    }
			}
			"""])
		case .swiftPackagePlugin:
			let cPath = app.fixtures.compilerPath(of: "C.swift")
			expectGeneratedFiles(app.generatedFiles, ["Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public convenience init() {
			        func __safeDI_apiBuilder_F0_api(_ scope_service: Service) -> any Api {
			            return __safeDI_fillBody_DA998F868C342499(service: scope_service)
			        }
			        func __safeDI_fillBody_DA998F868C342499(service: Service) -> any Api {
			            func __safeDI_api() -> LiveApi {
			                func __safeDI_c() -> C {
			                    #sourceLocation(file: "\(cPath)", line: 5)
			                    let renamedService: Service = service
			                    #sourceLocation()
			                    func __safeDI_f0Builder() -> F0 {
			                        _ = F0.__safeDI_F0_D025DDBE59384E69.self // If this line does not compile, add the SafeDI plugin to the target that declares F0.
			                        return F0(__safeDI_service: service, __safeDI_apiBuilder: __safeDI_apiBuilder_F0())
			                    }
			                    let f0Builder = Instantiator<F0>(__safeDI_f0Builder)
			                    return C(renamedService: renamedService, f0Builder: f0Builder)
			                }
			                let c: C = __safeDI_c()
			                return LiveApi(service: service, c: c)
			            }
			            let api: any Api = __safeDI_api()
			            return api
			        }
			        func __safeDI_apiBuilder_F0() -> F0.__safeDI_ApiCarrier<any Api> {
			            .init(api: { scope_service in __safeDI_apiBuilder_F0_api(scope_service) })
			        }
			        func __safeDI_apiBuilder_F1_api(_ scope_service: Service) -> any Api {
			            return __safeDI_fillBody_DA998F868C342499(service: scope_service)
			        }
			        func __safeDI_apiBuilder_F1() -> F1.__safeDI_ApiCarrier<any Api> {
			            .init(api: { scope_service in __safeDI_apiBuilder_F1_api(scope_service) })
			        }
			        let service = Service()
			        func __safeDI_f0() -> F0 {
			            _ = F0.__safeDI_F0_D025DDBE59384E69.self // If this line does not compile, add the SafeDI plugin to the target that declares F0.
			            return F0(__safeDI_service: service, __safeDI_apiBuilder: __safeDI_apiBuilder_F0())
			        }
			        let f0: F0 = __safeDI_f0()
			        func __safeDI_f1() -> F1 {
			            _ = F1.__safeDI_F1_3FF9291B1DFF77D6.self // If this line does not compile, add the SafeDI plugin to the target that declares F1.
			            return F1(__safeDI_service: service, __safeDI_apiBuilder: __safeDI_apiBuilder_F1())
			        }
			        let f1: F1 = __safeDI_f1()
			        self.init(service: service, f0: f0, f1: f1)
			    }
			}
			"""])
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesFillBodyApartFromDirectoryOfFileItPointsAt_whenFillTreeRefersToAliasDeclarationByComment() async throws {
		// `C` renames `service`, and another file of `App` shares `C.swift`'s name, so the body names `C`'s declaration in a
		// comment, whose path is the one the integration hands `generate`, which each checkout spells apart: the body's
		// name is the same.
		var modules = Fixture(cDeclarations: [Fixture.renamingDeclaration]).modules
		let appFixture = modules[1]
		modules[1] = ModuleFixture(
			name: appFixture.name,
			packageName: appFixture.packageName,
			swiftFileContent: appFixture.swiftFileContent.filter { !$0.contains("class C:") },
			swiftFileContentByFilePath: [
				"One/C.swift": try #require(appFixture.swiftFileContent.first { $0.contains("class C:") }),
				"Two/C.swift": "public struct Unrelated {}",
			],
			dependencies: appFixture.dependencies,
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		let app = try #require(output.modules["App"])
		let cPath = app.fixtures["One/C.swift"]
		expectGeneratedFiles(app.generatedFiles, ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_apiBuilder_F0_api(_ scope_service: Service) -> any Api {
		            return __safeDI_fillBody_9EBD8B88FAD7AB9F(service: scope_service)
		        }
		        func __safeDI_fillBody_9EBD8B88FAD7AB9F(service: Service) -> any Api {
		            func __safeDI_c() -> C {
		                let renamedService: Service = service // Declared at \(cPath):5
		                return C(renamedService: renamedService)
		            }
		            func __safeDI_api() -> LiveApi {
		                let c: C = __safeDI_c()
		                return LiveApi(service: service, c: c)
		            }
		            let api: any Api = __safeDI_api()
		            return api
		        }
		        func __safeDI_apiBuilder_F0() -> F0.__safeDI_ApiCarrier<any Api> {
		            .init(api: { scope_service in __safeDI_apiBuilder_F0_api(scope_service) })
		        }
		        func __safeDI_apiBuilder_F1_api(_ scope_service: Service) -> any Api {
		            return __safeDI_fillBody_9EBD8B88FAD7AB9F(service: scope_service)
		        }
		        func __safeDI_apiBuilder_F1() -> F1.__safeDI_ApiCarrier<any Api> {
		            .init(api: { scope_service in __safeDI_apiBuilder_F1_api(scope_service) })
		        }
		        let service = Service()
		        func __safeDI_f0() -> F0 {
		            _ = F0.__safeDI_F0_D025DDBE59384E69.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return F0(__safeDI_service: service, __safeDI_apiBuilder: __safeDI_apiBuilder_F0())
		        }
		        let f0: F0 = __safeDI_f0()
		        func __safeDI_f1() -> F1 {
		            _ = F1.__safeDI_F1_3FF9291B1DFF77D6.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return F1(__safeDI_service: service, __safeDI_apiBuilder: __safeDI_apiBuilder_F1())
		        }
		        let f1: F1 = __safeDI_f1()
		        self.init(service: service, f0: f0, f1: f1)
		    }
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsCallersWrapperInEachFill_whenFillOfPassedUpPlaceReadsWrapperOfLabelInnerSeamDefers() async throws {
		let seamDeclarations = ["@Received public let service: Service", "@Instantiated public let inner: Inner"]
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Fixture(
				featureTypes: [
					"@Instantiable public final class Token: Instantiable, Sendable { public init() {} }",
					Fixture.type(named: "Leaf", attribute: "@Instantiable", conformances: "", declarations: ["@Received public let token: Token"]),
					Fixture.type(named: "Inner", attribute: "@Instantiable(generateDependencyTree: true)", conformances: "", declarations: ["@Instantiated public let leafBuilder: Instantiator<Leaf>", "@Instantiated public let api: any Api"]),
				],
				f0Declarations: seamDeclarations,
				f1Declarations: seamDeclarations,
				appTypes: [Fixture.type(named: "Reader", attribute: "@Instantiable", conformances: ", Sendable", declarations: ["@Received let token: SendableLazilyInstantiated<Token>"])],
				liveApiDeclarations: ["@Instantiated let readerBuilder: SendableInstantiator<Reader>"],
				rootDeclarations: ["@Instantiated let token: SendableLazilyInstantiated<Token>"] + Fixture.rootDeclarations,
			).modules,
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        @Sendable nonisolated func __safeDI_token() -> Token {
		            Token()
		        }
		        let token = SendableLazilyInstantiated<Token>(__safeDI_token)
		        let service = Service()
		        func __safeDI_f0() -> F0 {
		            _ = F0.__safeDI_F0_E666CFA02F65FBFB.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
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
		            _ = F1.__safeDI_F1_662E4FC5D4A33B62.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
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
		        self.init(token: token, service: service, f0: f0, f1: f1)
		    }
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresFillBodyTakingMemo_whenFillOfPassedUpPlaceReadsValueInnerSeamDefers() async throws {
		let seamDeclarations = ["@Received public let service: Service", "@Instantiated public let inner: Inner"]
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Fixture(
				featureTypes: [
					"@Instantiable public final class Token: Instantiable { public init() {} }",
					Fixture.type(named: "Leaf", attribute: "@Instantiable", conformances: "", declarations: ["@Received public let token: Token"]),
					Fixture.type(named: "Inner", attribute: "@Instantiable(generateDependencyTree: true)", conformances: "", declarations: ["@Instantiated public let leafBuilder: Instantiator<Leaf>", "@Instantiated public let api: any Api"]),
				],
				f0Declarations: seamDeclarations,
				f1Declarations: seamDeclarations,
				appTypes: [Fixture.type(named: "Reader", attribute: "@Instantiable", conformances: "", declarations: ["@Received let token: Token"])],
				liveApiDeclarations: ["@Instantiated let reader: Reader"],
				rootDeclarations: ["@Instantiated let token: Token"] + Fixture.rootDeclarations,
			).modules,
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_apiBuilder_Inner_api(_ scope_token: LazilyInstantiated<Token>, _ scope_leafBuilder: Instantiator<Leaf>) -> any Api {
		            return __safeDI_fillBody_E477729F92E9E05D(token: scope_token)
		        }
		        func __safeDI_fillBody_E477729F92E9E05D(token: LazilyInstantiated<Token>) -> any Api {
		            func __safeDI_api() -> LiveApi {
		                let reader = Reader(token: token.instance)
		                return LiveApi(reader: reader)
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
		        func __safeDI_apiBuilder_F1() -> F1.__safeDI_ApiCarrier<any Api> {
		            .init(inner: __safeDI_apiBuilder_Inner())
		        }
		        let token = Token()
		        let service = Service()
		        func __safeDI_f0() -> F0 {
		            _ = F0.__safeDI_F0_E666CFA02F65FBFB.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return F0(__safeDI_service: service, __safeDI_token: token, __safeDI_apiBuilder: __safeDI_apiBuilder_F0())
		        }
		        let f0: F0 = __safeDI_f0()
		        func __safeDI_f1() -> F1 {
		            _ = F1.__safeDI_F1_662E4FC5D4A33B62.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return F1(__safeDI_service: service, __safeDI_token: token, __safeDI_apiBuilder: __safeDI_apiBuilder_F1())
		        }
		        let f1: F1 = __safeDI_f1()
		        self.init(token: token, service: service, f0: f0, f1: f1)
		    }
		}
		"""])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private struct Fixture {
		static let seamDeclarations = ["@Received public let service: Service", "@Instantiated public let api: any Api"]
		static let liveApiDeclarations = ["@Received let service: Service", "@Instantiated let c: C"]
		static let cDeclarations = ["@Received let service: Service"]
		static let renamingDeclaration = #"@Received(fulfilledByDependencyNamed: "service", ofType: Service.self) let renamedService: Service"#
		static let rootDeclarations = ["@Instantiated let service: Service", "@Instantiated let f0: F0", "@Instantiated let f1: F1"]

		init(
			isSendable: Bool = false,
			featureTypes: [String] = [],
			f0Declarations: [String] = seamDeclarations,
			f1Declarations: [String] = seamDeclarations,
			appTypes: [String] = [],
			liveApiDeclarations: [String] = liveApiDeclarations,
			cDeclarations: [String] = cDeclarations,
			rootDeclarations: [String] = rootDeclarations,
		) {
			let sendable = isSendable ? ", Sendable" : ""
			feature = [
				"public protocol Api\(isSendable ? ": Sendable" : "") {}\n\n@Instantiable public final class Service: Instantiable\(sendable) { public init() {} }",
				Self.type(named: "F0", attribute: "@Instantiable(generateDependencyTree: true)", conformances: sendable, declarations: f0Declarations),
				Self.type(named: "F1", attribute: "@Instantiable(generateDependencyTree: true)", conformances: sendable, declarations: f1Declarations),
			] + featureTypes
			app = appTypes + [
				Self.type(named: "LiveApi", attribute: "@Instantiable(fulfillingAdditionalTypes: [Api.self])", conformances: ", Api\(sendable)", declarations: liveApiDeclarations),
				Self.type(named: "C", attribute: "@Instantiable", conformances: sendable, declarations: cDeclarations),
				Self.type(named: "Root", attribute: "@Instantiable(isRoot: true)", conformances: "", declarations: rootDeclarations),
			]
		}

		var modules: [ModuleFixture] {
			[
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature),
				ModuleFixture(name: "App", packageName: "Other", swiftFileContent: app.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
			]
		}

		/// A final class with a memberwise initializer of `declarations`, each `@Attribute [public] let label: Type`.
		static func type(named name: String, attribute: String, conformances: String, declarations: [String]) -> String {
			let properties = declarations.map { declaration in
				let parts = declaration.components(separatedBy: " let ")
				let labelAndType = parts[1].components(separatedBy: ": ")
				return (label: labelAndType[0], type: labelAndType[1...].joined(separator: ": "))
			}
			let parameters = properties.map { "\($0.label): \($0.type)" }.joined(separator: ", ")
			let assignments = properties.map { "self.\($0.label) = \($0.label)" }.joined(separator: "; ")
			return """
			\(attribute) public final class \(name): Instantiable\(conformances) {
				public init(\(parameters)) { \(assignments) }
			\(declarations.map { "\t\($0)" }.joined(separator: "\n"))
			}
			"""
		}

		private let feature: [String]
		private let app: [String]
	}

	private func expectGeneratedFiles(_ generatedFiles: [String: String]?, _ expected: [String: String], sourceLocation: SourceLocation = #_sourceLocation) {
		#expect(generatedFiles == expected, sourceLocation: sourceLocation)
		if let generatedFiles, generatedFiles != expected {
			Issue.record(Comment(rawValue: generatedFiles.sorted { $0.key < $1.key }.map { "=== \($0.key)\n\($0.value)" }.joined(separator: "\n")), sourceLocation: sourceLocation)
		}
	}
}
