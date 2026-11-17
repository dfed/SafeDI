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

/// How a fill binds a deferred parameter's field of a place a seam passes up from a seam it calls. The struct holds the
/// passing-up seam's memo of what it passed, which the fill binds and whose instance its tree reads where it reads the
/// value, as inline. Two things change that binding: a fill of a place held in an instantiator takes each field it reads
/// as a parameter, which is then the memo too; and where the fill's tree reads the value inside a `@Sendable` function,
/// which cannot capture a `LazilyInstantiated`, the fill binds the struct's by-value member instead.
struct SafeDIToolSeamPassedUpDeferredFieldTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: A fill that reads the value inside a @Sendable function

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillBindsStructsValue_whenPassedUpPlacesFillHandsValueReceivedOnlyIfAvailableToSeamTakingItSendable() async throws {
		// `Outer` passes up `Seam`'s place `holeService`, whose struct holds `Seam`'s memo of `chainToken`, a
		// `LazilyInstantiated`. `HoleImpl`'s fill hands `chainToken` to `Relay`, which takes it `@Sendable`, so the fill binds
		// the struct's `chainToken` rather than the memo.
		let modules = [
			ModuleFixture(name: "Core", packageName: "Min", swiftFileContent: ["""
			import SafeDI

			public final class ChainToken: Sendable { public init() {} }

			@Instantiable
			public final class ChainLeaf: Instantiable, Sendable {
				public init(chainToken: ChainToken?) { self.chainToken = chainToken }
				@Received(onlyIfAvailable: true) let chainToken: ChainToken?
			}

			public protocol HoleService: Sendable {}
			public protocol NestService: Sendable {}

			@Instantiable(generateDependencyTree: true)
			public final class Nest: Instantiable, Sendable {
				public init(nestService: any NestService) { self.nestService = nestService }
				@Instantiated let nestService: any NestService
			}
			"""]),
			ModuleFixture(name: "Feature", packageName: "Min", swiftFileContent: ["""
			import Core
			import SafeDI

			@Instantiable(generateDependencyTree: true)
			public final class Seam: Instantiable, @unchecked Sendable {
				public init(chainLeaf: ChainLeaf, holeService: any HoleService) {
					self.chainLeaf = chainLeaf
					self.holeService = holeService
				}
				@Instantiated let chainLeaf: ChainLeaf
				@Instantiated let holeService: any HoleService
			}

			@Instantiable(fulfillingAdditionalTypes: [NestService.self])
			public final class NestImpl: Instantiable, NestService {
				public init(holeService: any HoleService) { self.holeService = holeService }
				@Instantiated let holeService: any HoleService
			}

			@Instantiable(generateDependencyTree: true)
			public final class Relay: Instantiable, Sendable {
				public init(leafBuilder: SendableInstantiator<ChainLeaf>) { self.leafBuilder = leafBuilder }
				@Instantiated let leafBuilder: SendableInstantiator<ChainLeaf>
			}

			@Instantiable(generateDependencyTree: true)
			public final class Outer: Instantiable, @unchecked Sendable {
				public init(seam: Seam) { self.seam = seam }
				@Instantiated let seam: Seam
			}
			"""], dependencies: ["Core"]),
			ModuleFixture(name: "Other", packageName: "Min", swiftFileContent: ["""
			import Core
			import Feature
			import SafeDI

			@Instantiable(fulfillingAdditionalTypes: [HoleService.self])
			public final class HoleImpl: Instantiable, HoleService, @unchecked Sendable {
				public init(relayBuilder: Instantiator<Relay>) { self.relayBuilder = relayBuilder }
				@Instantiated let relayBuilder: Instantiator<Relay>
			}

			@Instantiable(isRoot: true)
			public final class OtherRoot: Instantiable {
				public init(outer: Outer) { self.outer = outer }
				@Instantiated let outer: Outer
			}
			"""], dependencies: ["Core", "Feature"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Nest {
		    nonisolated public enum SafeDIScope_NestService {
		        nonisolated public struct nestService_Values {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let nestService: (nestService_Values) -> __safeDI_Built

		            public init(nestService: @escaping (nestService_Values) -> __safeDI_Built) {
		                self.nestService = nestService
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.nestService = { _ in __safeDI_builder() }
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_nestServiceBuilder: SafeDIScope_NestService.__safeDI_Builder<any NestService>) {
		        let nestService: any NestService = __safeDI_nestServiceBuilder.nestService(SafeDIScope_NestService.nestService_Values())
		        self.init(nestService: nestService)
		    }
		}

		extension Nest {
		    public enum __safeDI_Nest_89D63F9124E92B75 {}
		}
		"""])
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Outer {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct seam_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let seam: (seam_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>

		            public init(seam: @escaping (seam_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>) {
		                self.seam = seam
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.seam = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    // SafeDI counts `HoleService` as `public`: no module it reads declares it narrower. If `HoleService` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping () -> ChainToken?, __safeDI_holeServiceBuilder: SafeDIScope_HoleService.__safeDI_Builder<any HoleService>) {
		        let chainToken = LazilyInstantiated<ChainToken?>(__safeDI_chainToken)
		        func __safeDI_seam() -> Seam {
		            _ = Seam.__safeDI_Seam_C4104938716F228A.self
		            return Seam(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder.seam(SafeDIScope_HoleService.seam_Values()))
		        }
		        let seam: Seam = __safeDI_seam()
		        self.init(seam: seam)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_892C1C6300EA18A3 {}
		}

		extension Relay {
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping @Sendable () -> ChainToken?) {
		        let chainToken = SendableLazilyInstantiated<ChainToken?>(__safeDI_chainToken)
		        @Sendable func __safeDI_leafBuilder() -> ChainLeaf {
		            ChainLeaf(chainToken: chainToken.instance)
		        }
		        let leafBuilder = SendableInstantiator<ChainLeaf>(__safeDI_leafBuilder)
		        self.init(leafBuilder: leafBuilder)
		    }
		}

		extension Relay {
		    public enum __safeDI_Relay_6E41D8FCDF4140B3 {}
		}

		extension Seam {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct holeService_Values {
		            public var chainToken: ChainToken? { __safeDI_chainToken.instance }
		            public let chainLeaf: ChainLeaf
		            public let __safeDI_chainToken: LazilyInstantiated<ChainToken?>

		            init(chainToken: LazilyInstantiated<ChainToken?>, chainLeaf: ChainLeaf) {
		                __safeDI_chainToken = chainToken
		                self.chainLeaf = chainLeaf
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let holeService: (holeService_Values) -> __safeDI_Built

		            public init(holeService: @escaping (holeService_Values) -> __safeDI_Built) {
		                self.holeService = holeService
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.holeService = { _ in __safeDI_builder() }
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping () -> ChainToken?, __safeDI_holeServiceBuilder: SafeDIScope_HoleService.__safeDI_Builder<any HoleService>) {
		        let chainToken = LazilyInstantiated<ChainToken?>(__safeDI_chainToken)
		        let chainLeaf = ChainLeaf(chainToken: chainToken.instance)
		        let holeService: any HoleService = __safeDI_holeServiceBuilder.holeService(SafeDIScope_HoleService.holeService_Values(chainToken: chainToken, chainLeaf: chainLeaf))
		        self.init(chainLeaf: chainLeaf, holeService: holeService)
		    }
		}

		extension Seam {
		    public enum __safeDI_Seam_C4104938716F228A {}
		}
		"""])
		#expect(output.modules["Other"]?.generatedFiles == ["Other.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension OtherRoot {
		    public convenience init() {
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_892C1C6300EA18A3.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_holeServiceBuilder_Seam_holeService(_ scope: Seam.SafeDIScope_HoleService.holeService_Values) -> any HoleService {
		                let chainToken = scope.chainToken
		                func __safeDI_holeService() -> HoleImpl {
		                    func __safeDI_relayBuilder() -> Relay {
		                        _ = Relay.__safeDI_Relay_6E41D8FCDF4140B3.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                        return Relay(__safeDI_chainToken: chainToken)
		                    }
		                    let relayBuilder = Instantiator<Relay>(__safeDI_relayBuilder)
		                    return HoleImpl(relayBuilder: relayBuilder)
		                }
		                let holeService: any HoleService = __safeDI_holeService()
		                return holeService
		            }
		            func __safeDI_holeServiceBuilder_Outer() -> Outer.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(seam: { _ in __safeDI_holeServiceBuilder_Seam() })
		            }
		            func __safeDI_holeServiceBuilder_Seam() -> Seam.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(holeService: { scope in __safeDI_holeServiceBuilder_Seam_holeService(scope) })
		            }
		            return Outer(__safeDI_chainToken: nil, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder_Outer())
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(outer: outer)
		    }
		}
		"""])
		try await expectValuesEqualVisibleBuild(output, modules: modules, movingToFeature: "HoleImpl", probe: "OtherRoot()")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillBindsStructsValue_whenPassedUpPlacesFillHandsRequiredValueToSeamTakingItSendable() async throws {
		// As above, with `chainToken` required and built by `OtherRoot`.
		let modules = [
			ModuleFixture(name: "Core", packageName: "Min", swiftFileContent: ["""
			import SafeDI

			@Instantiable
			public final class ChainToken: Instantiable, Sendable { public init() {} }

			@Instantiable
			public final class ChainLeaf: Instantiable, Sendable {
				public init(chainToken: ChainToken) { self.chainToken = chainToken }
				@Received let chainToken: ChainToken
			}

			public protocol HoleService: Sendable {}
			public protocol NestService: Sendable {}

			@Instantiable(generateDependencyTree: true)
			public final class Nest: Instantiable, Sendable {
				public init(nestService: any NestService) { self.nestService = nestService }
				@Instantiated let nestService: any NestService
			}
			"""]),
			ModuleFixture(name: "Feature", packageName: "Min", swiftFileContent: ["""
			import Core
			import SafeDI

			@Instantiable(generateDependencyTree: true)
			public final class Seam: Instantiable, @unchecked Sendable {
				public init(chainLeaf: ChainLeaf, holeService: any HoleService) {
					self.chainLeaf = chainLeaf
					self.holeService = holeService
				}
				@Instantiated let chainLeaf: ChainLeaf
				@Instantiated let holeService: any HoleService
			}

			@Instantiable(fulfillingAdditionalTypes: [NestService.self])
			public final class NestImpl: Instantiable, NestService {
				public init(holeService: any HoleService) { self.holeService = holeService }
				@Instantiated let holeService: any HoleService
			}

			@Instantiable(generateDependencyTree: true)
			public final class Relay: Instantiable, Sendable {
				public init(leafBuilder: SendableInstantiator<ChainLeaf>) { self.leafBuilder = leafBuilder }
				@Instantiated let leafBuilder: SendableInstantiator<ChainLeaf>
			}

			@Instantiable(generateDependencyTree: true)
			public final class Outer: Instantiable, @unchecked Sendable {
				public init(seam: Seam) { self.seam = seam }
				@Instantiated let seam: Seam
			}
			"""], dependencies: ["Core"]),
			ModuleFixture(name: "Other", packageName: "Min", swiftFileContent: ["""
			import Core
			import Feature
			import SafeDI

			@Instantiable(fulfillingAdditionalTypes: [HoleService.self])
			public final class HoleImpl: Instantiable, HoleService, @unchecked Sendable {
				public init(relayBuilder: Instantiator<Relay>) { self.relayBuilder = relayBuilder }
				@Instantiated let relayBuilder: Instantiator<Relay>
			}

			@Instantiable(isRoot: true)
			public final class OtherRoot: Instantiable {
				public init(chainToken: ChainToken, outer: Outer) { self.chainToken = chainToken; self.outer = outer }
				@Instantiated let chainToken: ChainToken
				@Instantiated let outer: Outer
			}
			"""], dependencies: ["Core", "Feature"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Nest {
		    nonisolated public enum SafeDIScope_NestService {
		        nonisolated public struct nestService_Values {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let nestService: (nestService_Values) -> __safeDI_Built

		            public init(nestService: @escaping (nestService_Values) -> __safeDI_Built) {
		                self.nestService = nestService
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.nestService = { _ in __safeDI_builder() }
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_nestServiceBuilder: SafeDIScope_NestService.__safeDI_Builder<any NestService>) {
		        let nestService: any NestService = __safeDI_nestServiceBuilder.nestService(SafeDIScope_NestService.nestService_Values())
		        self.init(nestService: nestService)
		    }
		}

		extension Nest {
		    public enum __safeDI_Nest_89D63F9124E92B75 {}
		}
		"""])
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Outer {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct seam_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let seam: (seam_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>

		            public init(seam: @escaping (seam_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>) {
		                self.seam = seam
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.seam = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    // SafeDI counts `HoleService` as `public`: no module it reads declares it narrower. If `HoleService` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping () -> ChainToken, __safeDI_holeServiceBuilder: SafeDIScope_HoleService.__safeDI_Builder<any HoleService>) {
		        let chainToken = LazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        func __safeDI_seam() -> Seam {
		            _ = Seam.__safeDI_Seam_55DA8662DD70A848.self
		            return Seam(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder.seam(SafeDIScope_HoleService.seam_Values()))
		        }
		        let seam: Seam = __safeDI_seam()
		        self.init(seam: seam)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_96BDB6C170135367 {}
		}

		extension Relay {
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping @Sendable () -> ChainToken) {
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        @Sendable func __safeDI_leafBuilder() -> ChainLeaf {
		            ChainLeaf(chainToken: chainToken.instance)
		        }
		        let leafBuilder = SendableInstantiator<ChainLeaf>(__safeDI_leafBuilder)
		        self.init(leafBuilder: leafBuilder)
		    }
		}

		extension Relay {
		    public enum __safeDI_Relay_8334A2F06A1857BE {}
		}

		extension Seam {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct holeService_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let chainLeaf: ChainLeaf
		            public let __safeDI_chainToken: LazilyInstantiated<ChainToken>

		            init(chainToken: LazilyInstantiated<ChainToken>, chainLeaf: ChainLeaf) {
		                __safeDI_chainToken = chainToken
		                self.chainLeaf = chainLeaf
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let holeService: (holeService_Values) -> __safeDI_Built

		            public init(holeService: @escaping (holeService_Values) -> __safeDI_Built) {
		                self.holeService = holeService
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.holeService = { _ in __safeDI_builder() }
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping () -> ChainToken, __safeDI_holeServiceBuilder: SafeDIScope_HoleService.__safeDI_Builder<any HoleService>) {
		        let chainToken = LazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        let chainLeaf = ChainLeaf(chainToken: chainToken.instance)
		        let holeService: any HoleService = __safeDI_holeServiceBuilder.holeService(SafeDIScope_HoleService.holeService_Values(chainToken: chainToken, chainLeaf: chainLeaf))
		        self.init(chainLeaf: chainLeaf, holeService: holeService)
		    }
		}

		extension Seam {
		    public enum __safeDI_Seam_55DA8662DD70A848 {}
		}
		"""])
		#expect(output.modules["Other"]?.generatedFiles == ["Other.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension OtherRoot {
		    public convenience init() {
		        let chainToken = ChainToken()
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_96BDB6C170135367.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_holeServiceBuilder_Seam_holeService(_ scope: Seam.SafeDIScope_HoleService.holeService_Values) -> any HoleService {
		                let chainToken = scope.chainToken
		                func __safeDI_holeService() -> HoleImpl {
		                    func __safeDI_relayBuilder() -> Relay {
		                        _ = Relay.__safeDI_Relay_8334A2F06A1857BE.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                        return Relay(__safeDI_chainToken: chainToken)
		                    }
		                    let relayBuilder = Instantiator<Relay>(__safeDI_relayBuilder)
		                    return HoleImpl(relayBuilder: relayBuilder)
		                }
		                let holeService: any HoleService = __safeDI_holeService()
		                return holeService
		            }
		            func __safeDI_holeServiceBuilder_Outer() -> Outer.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(seam: { _ in __safeDI_holeServiceBuilder_Seam() })
		            }
		            func __safeDI_holeServiceBuilder_Seam() -> Seam.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(holeService: { scope in __safeDI_holeServiceBuilder_Seam_holeService(scope) })
		            }
		            return Outer(__safeDI_chainToken: chainToken, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder_Outer())
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(chainToken: chainToken, outer: outer)
		    }
		}
		"""])
		try await expectValuesEqualVisibleBuild(output, modules: modules, movingToFeature: "HoleImpl", probe: "OtherRoot()")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_compiles_whenPassedUpPlacesFillReceivesValueInsideSendableInstantiator() async throws {
		// `HoleImpl` builds `ChainLeaf`, which receives `chainToken`, inside the `@Sendable` function of a
		// `SendableInstantiator`.
		let modules = Self.chainModules(holeImpl: """
		@Instantiable(fulfillingAdditionalTypes: [HoleService.self])
		public final class HoleImpl: Instantiable, HoleService, @unchecked Sendable {
			public init(leafBuilder: SendableInstantiator<ChainLeaf>) { self.leafBuilder = leafBuilder }
			@Instantiated let leafBuilder: SendableInstantiator<ChainLeaf>
		}
		""")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		try await expectValuesEqualVisibleBuild(output, modules: modules, movingToFeature: "HoleImpl", probe: "OtherRoot()")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_compiles_whenPassedUpPlacesFillAliasesValueInsideSendableInstantiator() async throws {
		// `TokenReader` receives `chainToken` under another label, inside the `@Sendable` function of a
		// `SendableInstantiator`.
		let modules = Self.chainModules(holeImpl: """
		@Instantiable
		public final class TokenReader: Instantiable, Sendable {
			public init(token: ChainToken) { self.token = token }
			@Received(fulfilledByDependencyNamed: "chainToken", ofType: ChainToken.self) let token: ChainToken
		}

		@Instantiable(fulfillingAdditionalTypes: [HoleService.self])
		public final class HoleImpl: Instantiable, HoleService, @unchecked Sendable {
			public init(readerBuilder: SendableInstantiator<TokenReader>) { self.readerBuilder = readerBuilder }
			@Instantiated let readerBuilder: SendableInstantiator<TokenReader>
		}
		""")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		try await expectValuesEqualVisibleBuild(output, modules: modules, movingToFeature: "HoleImpl", probe: "OtherRoot()")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_compiles_whenFillOfPlaceInsideInnerSeamsFillHandsValueToSeamTakingItSendable() async throws {
		// `Seam`'s place `holeService` is inside `NestImpl`, which fills `Nest`'s place in `Seam`'s tree: the level function
		// of `Nest` hands the fill `chainToken`, which it reads from `Seam`'s struct by value too.
		let modules = [
			ModuleFixture(name: "Core", packageName: "Min", swiftFileContent: [
				"""
				import SafeDI

				public final class ChainToken: Sendable { public init() {} }

				@Instantiable
				public final class ChainLeaf: Instantiable, Sendable {
					public init(chainToken: ChainToken?) { self.chainToken = chainToken }
					@Received(onlyIfAvailable: true) let chainToken: ChainToken?
				}

				public protocol HoleService: Sendable {}
				public protocol NestService: Sendable {}

				@Instantiable(generateDependencyTree: true)
				public final class Nest: Instantiable, Sendable {
					public init(nestService: any NestService) { self.nestService = nestService }
					@Instantiated let nestService: any NestService
				}
				""",
			]),
			ModuleFixture(name: "Feature", packageName: "Min", swiftFileContent: [
				"""
				import Core
				import SafeDI

				@Instantiable(generateDependencyTree: true)
				public final class Seam: Instantiable, @unchecked Sendable {
					public init(chainLeaf: ChainLeaf, nestBuilder: Instantiator<Nest>) {
						self.chainLeaf = chainLeaf
						self.nestBuilder = nestBuilder
					}
					@Instantiated let chainLeaf: ChainLeaf
					@Instantiated let nestBuilder: Instantiator<Nest>
				}

				@Instantiable(fulfillingAdditionalTypes: [NestService.self])
				public final class NestImpl: Instantiable, NestService {
					public init(holeService: any HoleService) { self.holeService = holeService }
					@Instantiated let holeService: any HoleService
				}

				@Instantiable(generateDependencyTree: true)
				public final class Relay: Instantiable, Sendable {
					public init(leafBuilder: SendableInstantiator<ChainLeaf>) { self.leafBuilder = leafBuilder }
					@Instantiated let leafBuilder: SendableInstantiator<ChainLeaf>
				}

				@Instantiable(generateDependencyTree: true)
				public final class Outer: Instantiable, @unchecked Sendable {
					public init(seam: Seam) { self.seam = seam }
					@Instantiated let seam: Seam
				}
				""",
			], dependencies: ["Core"]),
			ModuleFixture(name: "Other", packageName: "Min", swiftFileContent: [
				"""
				import Core
				import Feature
				import SafeDI

				@Instantiable(fulfillingAdditionalTypes: [HoleService.self])
				public final class HoleImpl: Instantiable, HoleService, @unchecked Sendable {
					public init(relayBuilder: Instantiator<Relay>) { self.relayBuilder = relayBuilder }
					@Instantiated let relayBuilder: Instantiator<Relay>
				}

				@Instantiable(isRoot: true)
				public final class OtherRoot: Instantiable {
					public init(outer: Outer) { self.outer = outer }
					@Instantiated let outer: Outer
				}
				""",
			], dependencies: ["Core", "Feature"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		try await expectValuesEqualVisibleBuild(output, modules: modules, movingToFeature: "HoleImpl", probe: "OtherRoot()")
	}

	// MARK: A fill of a place held in an instantiator

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillTakesStructsMemo_whenPassedUpInstantiatorPlacesFillReadsValueReceivedOnlyIfAvailable() async throws {
		// `Outer` passes up `Inner`'s place `serviceBuilder`, held in an `ErasedInstantiator`, whose struct holds `Inner`'s
		// memo of `token`. The fill takes each field it reads as a parameter, so it takes the memo, whose instance it reads.
		let modules = Self.tokenModules(isRequired: false)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """

		"""])
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Inner {
		    // SafeDI counts `Service` and `Token` as `public`: no module it reads declares them narrower. If one is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    nonisolated public enum SafeDIScope_ServiceImpl_Service {
		        nonisolated public struct serviceBuilder_Values {
		            public var token: Token? { __safeDI_token.instance }
		            public let reader: Reader
		            public let __safeDI_token: LazilyInstantiated<Token?>

		            init(token: LazilyInstantiated<Token?>, reader: Reader) {
		                __safeDI_token = token
		                self.reader = reader
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let serviceBuilder: (serviceBuilder_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder

		            public init(serviceBuilder: @escaping (serviceBuilder_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder) {
		                self.serviceBuilder = serviceBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<(), __safeDI_Built>.Builder) {
		                self.serviceBuilder = { _ in __safeDI_builder }
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_token: @autoclosure @escaping () -> Token?, __safeDI_serviceImpl_ServiceBuilder: SafeDIScope_ServiceImpl_Service.__safeDI_Builder<any Service>) {
		        let token = LazilyInstantiated<Token?>(__safeDI_token)
		        let reader = Reader(token: token.instance)
		        let serviceBuilder = ErasedInstantiator<(), any Service>(__safeDI_serviceImpl_ServiceBuilder.serviceBuilder(SafeDIScope_ServiceImpl_Service.serviceBuilder_Values(token: token, reader: reader)))
		        self.init(reader: reader, serviceBuilder: serviceBuilder)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_33FC336DE4179A64 {}
		}

		extension Outer {
		    nonisolated public enum SafeDIScope_ServiceImpl_Service {
		        nonisolated public struct inner_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let inner: (inner_Values) -> Inner.SafeDIScope_ServiceImpl_Service.__safeDI_Builder<__safeDI_Built>

		            public init(inner: @escaping (inner_Values) -> Inner.SafeDIScope_ServiceImpl_Service.__safeDI_Builder<__safeDI_Built>) {
		                self.inner = inner
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<(), __safeDI_Built>.Builder) {
		                self.inner = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_token: @autoclosure @escaping () -> Token?, __safeDI_serviceImpl_ServiceBuilder: SafeDIScope_ServiceImpl_Service.__safeDI_Builder<any Service>) {
		        let token = LazilyInstantiated<Token?>(__safeDI_token)
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_33FC336DE4179A64.self
		            return Inner(__safeDI_token: token.instance, __safeDI_serviceImpl_ServiceBuilder: __safeDI_serviceImpl_ServiceBuilder.inner(SafeDIScope_ServiceImpl_Service.inner_Values()))
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(inner: inner)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_11F897FFBF22FFE1 {}
		}
		"""])
		#expect(output.modules["Other"]?.generatedFiles == ["Other.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_11F897FFBF22FFE1.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_serviceImpl_ServiceBuilder_Inner_serviceBuilder(token: LazilyInstantiated<Token?>) -> ErasedInstantiator<(), any Service>.Builder {
		                func __safeDI_serviceBuilder() -> ServiceImpl {
		                    ServiceImpl(token: token.instance)
		                }
		                return { _ in __safeDI_serviceBuilder() }
		            }
		            func __safeDI_serviceImpl_ServiceBuilder_Outer() -> Outer.SafeDIScope_ServiceImpl_Service.__safeDI_Builder<any Service> {
		                .init(inner: { _ in __safeDI_serviceImpl_ServiceBuilder_Inner() })
		            }
		            func __safeDI_serviceImpl_ServiceBuilder_Inner() -> Inner.SafeDIScope_ServiceImpl_Service.__safeDI_Builder<any Service> {
		                .init(serviceBuilder: { values in __safeDI_serviceImpl_ServiceBuilder_Inner_serviceBuilder(token: values.__safeDI_token) })
		            }
		            return Outer(__safeDI_token: nil, __safeDI_serviceImpl_ServiceBuilder: __safeDI_serviceImpl_ServiceBuilder_Outer())
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(outer: outer)
		    }
		}
		"""])
		try await expectValuesEqualVisibleBuild(output, modules: modules, movingToFeature: "ServiceImpl", probe: "Root()")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillTakesStructsMemo_whenPassedUpInstantiatorPlacesFillReadsRequiredValue() async throws {
		// As above, with `token` required and built by `Root`.
		let modules = Self.tokenModules(isRequired: true)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif


		"""])
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Inner {
		    nonisolated public enum SafeDIScope_ServiceImpl_Service {
		        nonisolated public struct serviceBuilder_Values {
		            public var token: Token { __safeDI_token.instance }
		            public let reader: Reader
		            public let __safeDI_token: LazilyInstantiated<Token>

		            init(token: LazilyInstantiated<Token>, reader: Reader) {
		                __safeDI_token = token
		                self.reader = reader
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let serviceBuilder: (serviceBuilder_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder

		            public init(serviceBuilder: @escaping (serviceBuilder_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder) {
		                self.serviceBuilder = serviceBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<(), __safeDI_Built>.Builder) {
		                self.serviceBuilder = { _ in __safeDI_builder }
		            }
		        }
		    }

		    // SafeDI counts `Service` as `public`: no module it reads declares it narrower. If `Service` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_token: @autoclosure @escaping () -> Token, __safeDI_serviceImpl_ServiceBuilder: SafeDIScope_ServiceImpl_Service.__safeDI_Builder<any Service>) {
		        let token = LazilyInstantiated<Token>(__safeDI_token)
		        let reader = Reader(token: token.instance)
		        let serviceBuilder = ErasedInstantiator<(), any Service>(__safeDI_serviceImpl_ServiceBuilder.serviceBuilder(SafeDIScope_ServiceImpl_Service.serviceBuilder_Values(token: token, reader: reader)))
		        self.init(reader: reader, serviceBuilder: serviceBuilder)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_FF9A3431C4147E8C {}
		}

		extension Outer {
		    nonisolated public enum SafeDIScope_ServiceImpl_Service {
		        nonisolated public struct inner_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let inner: (inner_Values) -> Inner.SafeDIScope_ServiceImpl_Service.__safeDI_Builder<__safeDI_Built>

		            public init(inner: @escaping (inner_Values) -> Inner.SafeDIScope_ServiceImpl_Service.__safeDI_Builder<__safeDI_Built>) {
		                self.inner = inner
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<(), __safeDI_Built>.Builder) {
		                self.inner = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_token: @autoclosure @escaping () -> Token, __safeDI_serviceImpl_ServiceBuilder: SafeDIScope_ServiceImpl_Service.__safeDI_Builder<any Service>) {
		        let token = LazilyInstantiated<Token>(__safeDI_token)
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_FF9A3431C4147E8C.self
		            return Inner(__safeDI_token: token.instance, __safeDI_serviceImpl_ServiceBuilder: __safeDI_serviceImpl_ServiceBuilder.inner(SafeDIScope_ServiceImpl_Service.inner_Values()))
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(inner: inner)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_BE8DBAB0197E35A9 {}
		}
		"""])
		#expect(output.modules["Other"]?.generatedFiles == ["Other.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Root {
		    public convenience init() {
		        let token = Token()
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_BE8DBAB0197E35A9.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_serviceImpl_ServiceBuilder_Inner_serviceBuilder(token: LazilyInstantiated<Token>) -> ErasedInstantiator<(), any Service>.Builder {
		                func __safeDI_serviceBuilder() -> ServiceImpl {
		                    ServiceImpl(token: token.instance)
		                }
		                return { _ in __safeDI_serviceBuilder() }
		            }
		            func __safeDI_serviceImpl_ServiceBuilder_Outer() -> Outer.SafeDIScope_ServiceImpl_Service.__safeDI_Builder<any Service> {
		                .init(inner: { _ in __safeDI_serviceImpl_ServiceBuilder_Inner() })
		            }
		            func __safeDI_serviceImpl_ServiceBuilder_Inner() -> Inner.SafeDIScope_ServiceImpl_Service.__safeDI_Builder<any Service> {
		                .init(serviceBuilder: { values in __safeDI_serviceImpl_ServiceBuilder_Inner_serviceBuilder(token: values.__safeDI_token) })
		            }
		            return Outer(__safeDI_token: token, __safeDI_serviceImpl_ServiceBuilder: __safeDI_serviceImpl_ServiceBuilder_Outer())
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(token: token, outer: outer)
		    }
		}
		"""])
		try await expectValuesEqualVisibleBuild(output, modules: modules, movingToFeature: "ServiceImpl", probe: "Root()")
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The modules of the required shape above, with `holeImpl`, the declarations that fill `Seam`'s place, in `Other`.
	private static func chainModules(holeImpl: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Core", packageName: "Min", swiftFileContent: ["""
			import SafeDI

			@Instantiable
			public final class ChainToken: Instantiable, Sendable { public init() {} }

			@Instantiable
			public final class ChainLeaf: Instantiable, Sendable {
				public init(chainToken: ChainToken) { self.chainToken = chainToken }
				@Received let chainToken: ChainToken
			}

			public protocol HoleService: Sendable {}
			public protocol NestService: Sendable {}

			@Instantiable(generateDependencyTree: true)
			public final class Nest: Instantiable, Sendable {
				public init(nestService: any NestService) { self.nestService = nestService }
				@Instantiated let nestService: any NestService
			}
			"""]),
			ModuleFixture(name: "Feature", packageName: "Min", swiftFileContent: ["""
			import Core
			import SafeDI

			@Instantiable(generateDependencyTree: true)
			public final class Seam: Instantiable, @unchecked Sendable {
				public init(chainLeaf: ChainLeaf, holeService: any HoleService) {
					self.chainLeaf = chainLeaf
					self.holeService = holeService
				}
				@Instantiated let chainLeaf: ChainLeaf
				@Instantiated let holeService: any HoleService
			}

			@Instantiable(fulfillingAdditionalTypes: [NestService.self])
			public final class NestImpl: Instantiable, NestService {
				public init(holeService: any HoleService) { self.holeService = holeService }
				@Instantiated let holeService: any HoleService
			}

			@Instantiable(generateDependencyTree: true)
			public final class Relay: Instantiable, Sendable {
				public init(leafBuilder: SendableInstantiator<ChainLeaf>) { self.leafBuilder = leafBuilder }
				@Instantiated let leafBuilder: SendableInstantiator<ChainLeaf>
			}

			@Instantiable(generateDependencyTree: true)
			public final class Outer: Instantiable, @unchecked Sendable {
				public init(seam: Seam) { self.seam = seam }
				@Instantiated let seam: Seam
			}
			"""], dependencies: ["Core"]),
			ModuleFixture(name: "Other", packageName: "Min", swiftFileContent: [
				"""
				import Core
				import Feature
				import SafeDI

				\(holeImpl)

				@Instantiable(isRoot: true)
				public final class OtherRoot: Instantiable {
					public init(chainToken: ChainToken, outer: Outer) { self.chainToken = chainToken; self.outer = outer }
					@Instantiated let chainToken: ChainToken
					@Instantiated let outer: Outer
				}
				""",
			], dependencies: ["Core", "Feature"]),
		]
	}

	/// `Core`, which declares `Token` and `Service`; `Feature`, whose seam `Outer` builds `Inner`, a seam that reads
	/// `token` and holds a place of `Service` in an `ErasedInstantiator`; and `Other`, which fills it with `ServiceImpl`,
	/// which reads `token` too, under `Root`. `token` is received only if available, or, when `isRequired`, required and
	/// built by `Root`.
	private static func tokenModules(isRequired: Bool) -> [ModuleFixture] {
		let token = isRequired ? "Token" : "Token?"
		let received = isRequired ? "@Received" : "@Received(onlyIfAvailable: true)"
		return [
			ModuleFixture(name: "Core", packageName: "Min", swiftFileContent: [
				"""
				import SafeDI

				\(isRequired ? "@Instantiable\npublic final class Token: Instantiable, Sendable { public init() {} }" : "public final class Token: Sendable { public init() {} }")

				public protocol Service: Sendable {}
				""",
			]),
			ModuleFixture(name: "Feature", packageName: "Min", swiftFileContent: [
				"""
				import Core
				import SafeDI

				@Instantiable
				public final class Reader: Instantiable {
					public init(token: \(token)) { self.token = token }
					\(received) let token: \(token)
				}

				@Instantiable(generateDependencyTree: true)
				public final class Inner: Instantiable {
					public init(reader: Reader, serviceBuilder: ErasedInstantiator<(), any Service>) {
						self.reader = reader
						self.serviceBuilder = serviceBuilder
					}
					@Instantiated let reader: Reader
					@Instantiated(fulfilledByType: "ServiceImpl") let serviceBuilder: ErasedInstantiator<(), any Service>
				}

				@Instantiable(generateDependencyTree: true)
				public final class Outer: Instantiable {
					public init(inner: Inner) { self.inner = inner }
					@Instantiated let inner: Inner
				}
				""",
			], dependencies: ["Core"]),
			ModuleFixture(name: "Other", packageName: "Min", swiftFileContent: [
				"""
				import Core
				import Feature
				import SafeDI

				@Instantiable
				public final class ServiceImpl: Instantiable, Service {
					public init(token: \(token)) { self.token = token }
					\(received) let token: \(token)
				}

				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
					\(isRequired ? "public init(token: Token, outer: Outer) { self.token = token; self.outer = outer }\n\t@Instantiated let token: Token" : "public init(outer: Outer) { self.outer = outer }")
					@Instantiated let outer: Outer
				}
				""",
			], dependencies: ["Core", "Feature"]),
		]
	}

	/// Expects the values `output`, the run of `modules`, builds for `probe` to equal those of the visible build: the same
	/// modules with the declaration of `typeName` that `Other` holds moved to `Feature`, whose seam then builds it inline.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectValuesEqualVisibleBuild(_ output: MultiModuleTestOutput, modules: [ModuleFixture], movingToFeature typeName: String, probe: String, sourceLocation: SourceLocation = #_sourceLocation) async throws {
		guard compileVerificationIsEnabled else { return }
		let visibleModules = Self.modules(modules, movingToFeature: typeName)
		let visibleOutput = try await executeSafeDIToolMultiModuleTest(modules: visibleModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		try await expectDifferentialValuesAgree(
			feature: DifferentialValuePath(output: output, modules: modules),
			knownRight: DifferentialValuePath(output: visibleOutput, modules: visibleModules),
			probes: [DifferentialValueProbe(probe)],
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}

	/// `modules` with the declaration of `typeName` in `Other`'s one file, and every declaration before it in that file
	/// up to its imports, moved to the end of `Feature`'s one file.
	private static func modules(_ modules: [ModuleFixture], movingToFeature typeName: String) -> [ModuleFixture] {
		let otherFile = modules[2].swiftFileContent[0]
		let declarationsEnd = otherFile.range(of: "\n\n@Instantiable(isRoot: true)")!.lowerBound
		let declarationsStart = otherFile.range(of: "import SafeDI\n\n")!.upperBound
		let movedDeclarations = String(otherFile[declarationsStart..<declarationsEnd])
		precondition(movedDeclarations.contains("class \(typeName):"))
		return [
			modules[0],
			ModuleFixture(name: "Feature", packageName: "Min", swiftFileContent: [modules[1].swiftFileContent[0] + "\n\n" + movedDeclarations], dependencies: ["Core"]),
			ModuleFixture(name: "Other", packageName: "Min", swiftFileContent: [String(otherFile[..<declarationsStart]) + String(otherFile[declarationsEnd...].dropFirst(2))], dependencies: ["Core", "Feature"]),
		]
	}
}
