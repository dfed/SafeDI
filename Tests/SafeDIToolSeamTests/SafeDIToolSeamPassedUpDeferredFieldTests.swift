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
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let nestService: (__safeDI_Values) -> __safeDI_Built

		            public init(nestService: @escaping (__safeDI_Values) -> __safeDI_Built) {
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
		        let nestService: any NestService = __safeDI_nestServiceBuilder.nestService(SafeDIScope_NestService.__safeDI_Values())
		        self.init(nestService: nestService)
		    }
		}

		extension Nest {
		    public enum __safeDI_Nest_656AF7BB9514ADB0 {}
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
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let seam: (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>

		            public init(seam: @escaping (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>) {
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
		            return Seam(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder.seam(SafeDIScope_HoleService.__safeDI_Values()))
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
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let nestService: (__safeDI_Values) -> __safeDI_Built

		            public init(nestService: @escaping (__safeDI_Values) -> __safeDI_Built) {
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
		        let nestService: any NestService = __safeDI_nestServiceBuilder.nestService(SafeDIScope_NestService.__safeDI_Values())
		        self.init(nestService: nestService)
		    }
		}

		extension Nest {
		    public enum __safeDI_Nest_656AF7BB9514ADB0 {}
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
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let seam: (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>

		            public init(seam: @escaping (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>) {
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
		            return Seam(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder.seam(SafeDIScope_HoleService.__safeDI_Values()))
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
		                    @Sendable func __safeDI_leafBuilder() -> ChainLeaf {
		                        ChainLeaf(chainToken: chainToken)
		                    }
		                    let leafBuilder = SendableInstantiator<ChainLeaf>(__safeDI_leafBuilder)
		                    return HoleImpl(leafBuilder: leafBuilder)
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
		let tokenReaderPath = try #require(output.modules["Other"]).fixtures["TokenReader.swift"]
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
		                    @Sendable func __safeDI_readerBuilder() -> TokenReader {
		                        #sourceLocation(file: "\(tokenReaderPath)", line: 8)
		                        let token: ChainToken = chainToken
		                        #sourceLocation()
		                        return TokenReader(token: token)
		                    }
		                    let readerBuilder = SendableInstantiator<TokenReader>(__safeDI_readerBuilder)
		                    return HoleImpl(readerBuilder: readerBuilder)
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
		            _ = Outer.__safeDI_Outer_21D10E65233A33D4.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_holeServiceBuilder_Seam_NestImpl_Scope_holeService(_ scope: Seam.SafeDIScope_HoleService.NestImpl_Scope.__safeDI_Values, chainToken: ChainToken?) -> any HoleService {
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
		                .init(nestBuilder_nestServiceBuilder: { values in __safeDI_holeServiceBuilder_Seam_Nest(chainToken: values.chainToken) })
		            }
		            func __safeDI_holeServiceBuilder_Seam_NestImpl_Scope(chainToken: ChainToken?) -> Seam.SafeDIScope_HoleService.NestImpl_Scope.__safeDI_Builder<any HoleService> {
		                .init(holeService: { scope in __safeDI_holeServiceBuilder_Seam_NestImpl_Scope_holeService(scope, chainToken: chainToken) })
		            }
		            func __safeDI_holeServiceBuilder_Seam_Nest(chainToken: ChainToken?) -> Nest.SafeDIScope_NestService.__safeDI_Builder<Seam.SafeDIScope_HoleService.NestImpl_Scope.__safeDI_Builder<any HoleService>> {
		                .init(nestService: { _ in __safeDI_holeServiceBuilder_Seam_NestImpl_Scope(chainToken: chainToken) })
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
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let inner: (__safeDI_Values) -> Inner.SafeDIScope_ServiceImpl_Service.__safeDI_Builder<__safeDI_Built>

		            public init(inner: @escaping (__safeDI_Values) -> Inner.SafeDIScope_ServiceImpl_Service.__safeDI_Builder<__safeDI_Built>) {
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
		            return Inner(__safeDI_token: token.instance, __safeDI_serviceImpl_ServiceBuilder: __safeDI_serviceImpl_ServiceBuilder.inner(SafeDIScope_ServiceImpl_Service.__safeDI_Values()))
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
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let inner: (__safeDI_Values) -> Inner.SafeDIScope_ServiceImpl_Service.__safeDI_Builder<__safeDI_Built>

		            public init(inner: @escaping (__safeDI_Values) -> Inner.SafeDIScope_ServiceImpl_Service.__safeDI_Builder<__safeDI_Built>) {
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
		            return Inner(__safeDI_token: token.instance, __safeDI_serviceImpl_ServiceBuilder: __safeDI_serviceImpl_ServiceBuilder.inner(SafeDIScope_ServiceImpl_Service.__safeDI_Values()))
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

	// MARK: A place inside a fill of a passed-up place, filled one module up

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_levelFunctionHandsMemoOn_whenCallerFillsPlaceInsideFillOfPassedUpPlace() async throws {
		// `Top` fills `Mid`'s place `thing`, inside `HoleImpl`, `Mid`'s fill of the place `Outer` passes up from `Seam`. The
		// route reaches `thing` through `Seam`'s level, whose struct holds `Seam`'s memo of `chainToken`: `Seam`'s level
		// function hands the memo on, and the fill reads its instance where `ThingImpl` is built, so `ChainToken` is created
		// when `Worker` is, as in the one-module build.
		let modules = Self.chainTokenModules()
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

		extension Outer {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let seam: (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>

		            public init(seam: @escaping (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>) {
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
		            _ = Seam.__safeDI_Seam_2AD7242F90FE57C2.self
		            return Seam(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder.seam(SafeDIScope_HoleService.__safeDI_Values()))
		        }
		        let seam: Seam = __safeDI_seam()
		        self.init(seam: seam)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_2A8D23C10A89B5A9 {}
		}

		extension Seam {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct holeService_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let leafBuilder: Instantiator<ChainLeaf>
		            public let __safeDI_chainToken: LazilyInstantiated<ChainToken>

		            init(chainToken: LazilyInstantiated<ChainToken>, leafBuilder: Instantiator<ChainLeaf>) {
		                __safeDI_chainToken = chainToken
		                self.leafBuilder = leafBuilder
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
		        func __safeDI_leafBuilder() -> ChainLeaf {
		            ChainLeaf(chainToken: chainToken.instance)
		        }
		        let leafBuilder = Instantiator<ChainLeaf>(__safeDI_leafBuilder)
		        let holeService: any HoleService = __safeDI_holeServiceBuilder.holeService(SafeDIScope_HoleService.holeService_Values(chainToken: chainToken, leafBuilder: leafBuilder))
		        self.init(leafBuilder: leafBuilder, holeService: holeService)
		    }
		}

		extension Seam {
		    public enum __safeDI_Seam_2AD7242F90FE57C2 {}
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

		extension Mid {
		    nonisolated public enum SafeDIScope_ThingService {
		        nonisolated public struct outer_holeServiceBuilder_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let __safeDI_chainToken: LazilyInstantiated<ChainToken>

		            init(chainToken: LazilyInstantiated<ChainToken>) {
		                __safeDI_chainToken = chainToken
		            }
		        }

		        nonisolated public enum HoleImpl_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let workerBuilder: (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(workerBuilder: @escaping (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.workerBuilder = workerBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.workerBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        nonisolated public enum Worker_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let thing: (__safeDI_Values) -> __safeDI_Built

		                public init(thing: @escaping (__safeDI_Values) -> __safeDI_Built) {
		                    self.thing = thing
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.thing = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let outer_holeServiceBuilder: (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(outer_holeServiceBuilder: @escaping (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.outer_holeServiceBuilder = outer_holeServiceBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.outer_holeServiceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		            }
		        }
		    }

		    // SafeDI counts `ThingService` as `public`: no module it reads declares it narrower. If `ThingService` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping () -> ChainToken, __safeDI_thingServiceBuilder: SafeDIScope_ThingService.__safeDI_Builder<any ThingService>) {
		        let chainToken = LazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        let __safeDI_thingServiceBuilder_outer_holeServiceBuilder = __safeDI_thingServiceBuilder.outer_holeServiceBuilder(SafeDIScope_ThingService.outer_holeServiceBuilder_Values(chainToken: chainToken))
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_2A8D23C10A89B5A9.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_holeServiceBuilder_Seam_holeService(_ scope: Seam.SafeDIScope_HoleService.holeService_Values, __safeDI_outer_holeServiceBuilder: SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>) -> any HoleService {
		                func __safeDI_holeService() -> HoleImpl {
		                    let __safeDI_thingServiceBuilder_workerBuilder = __safeDI_outer_holeServiceBuilder.workerBuilder(SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Values())
		                    func __safeDI_workerBuilder() -> Worker {
		                        let thing: any ThingService = __safeDI_thingServiceBuilder_workerBuilder.thing(SafeDIScope_ThingService.Worker_Scope.__safeDI_Values())
		                        return Worker(thing: thing)
		                    }
		                    let workerBuilder = Instantiator<Worker>(__safeDI_workerBuilder)
		                    return HoleImpl(workerBuilder: workerBuilder)
		                }
		                let holeService: any HoleService = __safeDI_holeService()
		                return holeService
		            }
		            func __safeDI_holeServiceBuilder_Outer(up: Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(seam: { values in __safeDI_holeServiceBuilder_Seam(up: up.seam(values)) })
		            }
		            func __safeDI_holeServiceBuilder_Seam(up: Seam.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(holeService: { scope in __safeDI_holeServiceBuilder_Seam_holeService(scope, __safeDI_outer_holeServiceBuilder: up.holeService(scope)) })
		            }
		            return Outer(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder_Outer(up: __safeDI_thingServiceBuilder_outer_holeServiceBuilder))
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(outer: outer)
		    }
		}

		extension Mid {
		    public enum __safeDI_Mid_C9E7A7B945AD1E35 {}
		}
		"""])
		#expect(output.modules["Top"]?.generatedFiles == ["Top.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Other)
		import Other
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension TopRoot {
		    public convenience init() {
		        func __safeDI_chainToken() -> ChainToken {
		            ChainToken()
		        }
		        let chainToken = LazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        func __safeDI_mid() -> Mid {
		            _ = Mid.__safeDI_Mid_C9E7A7B945AD1E35.self // If this line does not compile, compile the code SafeDI generates for module Other into Other: under Bazel, add Other’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_thingServiceBuilder_Mid() -> Mid.SafeDIScope_ThingService.__safeDI_Builder<any ThingService> {
		                .init(outer_holeServiceBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Outer() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: LazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService> {
		                .init(workerBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: chainToken) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: LazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<any ThingService> {
		                .init(thing: { _ in
		                    let thing: any ThingService = ThingImpl(chainToken: chainToken.instance)
		                    return thing
		                })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Outer() -> Outer.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(seam: { _ in __safeDI_thingServiceBuilder_Mid_Seam() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Seam() -> Seam.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(holeService: { values in __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: values.__safeDI_chainToken) })
		            }
		            return Mid(__safeDI_chainToken: chainToken.instance, __safeDI_thingServiceBuilder: __safeDI_thingServiceBuilder_Mid())
		        }
		        let mid: Mid = __safeDI_mid()
		        self.init(chainToken: chainToken, mid: mid)
		    }
		}
		"""])
		try await expectCreationOrderEqualsOneModuleBuild(output, modules: modules)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_levelFunctionHandsMemoOn_whenCallerFillsPlaceInsideFillOfPassedUpPlaceReadingValueOnlyIfAvailable() async throws {
		// As above, with `ThingImpl` receiving `chainToken` only if available.
		let modules = Self.chainTokenModules(thingImpl: """
		@Instantiable(fulfillingAdditionalTypes: [ThingService.self])
		public final class ThingImpl: Instantiable, ThingService {
			public init(chainToken: ChainToken?) { self.chainToken = chainToken; log.append("ThingImpl") }
			@Received(onlyIfAvailable: true) let chainToken: ChainToken?
		}
		""")
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

		extension Outer {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let seam: (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>

		            public init(seam: @escaping (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>) {
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
		            _ = Seam.__safeDI_Seam_2AD7242F90FE57C2.self
		            return Seam(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder.seam(SafeDIScope_HoleService.__safeDI_Values()))
		        }
		        let seam: Seam = __safeDI_seam()
		        self.init(seam: seam)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_2A8D23C10A89B5A9 {}
		}

		extension Seam {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct holeService_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let leafBuilder: Instantiator<ChainLeaf>
		            public let __safeDI_chainToken: LazilyInstantiated<ChainToken>

		            init(chainToken: LazilyInstantiated<ChainToken>, leafBuilder: Instantiator<ChainLeaf>) {
		                __safeDI_chainToken = chainToken
		                self.leafBuilder = leafBuilder
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
		        func __safeDI_leafBuilder() -> ChainLeaf {
		            ChainLeaf(chainToken: chainToken.instance)
		        }
		        let leafBuilder = Instantiator<ChainLeaf>(__safeDI_leafBuilder)
		        let holeService: any HoleService = __safeDI_holeServiceBuilder.holeService(SafeDIScope_HoleService.holeService_Values(chainToken: chainToken, leafBuilder: leafBuilder))
		        self.init(leafBuilder: leafBuilder, holeService: holeService)
		    }
		}

		extension Seam {
		    public enum __safeDI_Seam_2AD7242F90FE57C2 {}
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

		extension Mid {
		    nonisolated public enum SafeDIScope_ThingService {
		        nonisolated public struct outer_holeServiceBuilder_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let __safeDI_chainToken: LazilyInstantiated<ChainToken>

		            init(chainToken: LazilyInstantiated<ChainToken>) {
		                __safeDI_chainToken = chainToken
		            }
		        }

		        nonisolated public enum HoleImpl_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let workerBuilder: (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(workerBuilder: @escaping (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.workerBuilder = workerBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.workerBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        nonisolated public enum Worker_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let thing: (__safeDI_Values) -> __safeDI_Built

		                public init(thing: @escaping (__safeDI_Values) -> __safeDI_Built) {
		                    self.thing = thing
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.thing = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let outer_holeServiceBuilder: (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(outer_holeServiceBuilder: @escaping (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.outer_holeServiceBuilder = outer_holeServiceBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.outer_holeServiceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		            }
		        }
		    }

		    // SafeDI counts `ThingService` as `public`: no module it reads declares it narrower. If `ThingService` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping () -> ChainToken, __safeDI_thingServiceBuilder: SafeDIScope_ThingService.__safeDI_Builder<any ThingService>) {
		        let chainToken = LazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        let __safeDI_thingServiceBuilder_outer_holeServiceBuilder = __safeDI_thingServiceBuilder.outer_holeServiceBuilder(SafeDIScope_ThingService.outer_holeServiceBuilder_Values(chainToken: chainToken))
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_2A8D23C10A89B5A9.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_holeServiceBuilder_Seam_holeService(_ scope: Seam.SafeDIScope_HoleService.holeService_Values, __safeDI_outer_holeServiceBuilder: SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>) -> any HoleService {
		                func __safeDI_holeService() -> HoleImpl {
		                    let __safeDI_thingServiceBuilder_workerBuilder = __safeDI_outer_holeServiceBuilder.workerBuilder(SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Values())
		                    func __safeDI_workerBuilder() -> Worker {
		                        let thing: any ThingService = __safeDI_thingServiceBuilder_workerBuilder.thing(SafeDIScope_ThingService.Worker_Scope.__safeDI_Values())
		                        return Worker(thing: thing)
		                    }
		                    let workerBuilder = Instantiator<Worker>(__safeDI_workerBuilder)
		                    return HoleImpl(workerBuilder: workerBuilder)
		                }
		                let holeService: any HoleService = __safeDI_holeService()
		                return holeService
		            }
		            func __safeDI_holeServiceBuilder_Outer(up: Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(seam: { values in __safeDI_holeServiceBuilder_Seam(up: up.seam(values)) })
		            }
		            func __safeDI_holeServiceBuilder_Seam(up: Seam.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(holeService: { scope in __safeDI_holeServiceBuilder_Seam_holeService(scope, __safeDI_outer_holeServiceBuilder: up.holeService(scope)) })
		            }
		            return Outer(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder_Outer(up: __safeDI_thingServiceBuilder_outer_holeServiceBuilder))
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(outer: outer)
		    }
		}

		extension Mid {
		    public enum __safeDI_Mid_C9E7A7B945AD1E35 {}
		}
		"""])
		#expect(output.modules["Top"]?.generatedFiles == ["Top.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Other)
		import Other
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension TopRoot {
		    public convenience init() {
		        func __safeDI_chainToken() -> ChainToken {
		            ChainToken()
		        }
		        let chainToken = LazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        func __safeDI_mid() -> Mid {
		            _ = Mid.__safeDI_Mid_C9E7A7B945AD1E35.self // If this line does not compile, compile the code SafeDI generates for module Other into Other: under Bazel, add Other’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_thingServiceBuilder_Mid() -> Mid.SafeDIScope_ThingService.__safeDI_Builder<any ThingService> {
		                .init(outer_holeServiceBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Outer() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: LazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService> {
		                .init(workerBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: chainToken) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: LazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<any ThingService> {
		                .init(thing: { _ in
		                    let thing: any ThingService = ThingImpl(chainToken: chainToken.instance)
		                    return thing
		                })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Outer() -> Outer.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(seam: { _ in __safeDI_thingServiceBuilder_Mid_Seam() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Seam() -> Seam.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(holeService: { values in __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: values.__safeDI_chainToken) })
		            }
		            return Mid(__safeDI_chainToken: chainToken.instance, __safeDI_thingServiceBuilder: __safeDI_thingServiceBuilder_Mid())
		        }
		        let mid: Mid = __safeDI_mid()
		        self.init(chainToken: chainToken, mid: mid)
		    }
		}
		"""])
		try await expectCreationOrderEqualsOneModuleBuild(output, modules: modules)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_levelFunctionsHandMemoOn_whenCallerFillsPlacesOfThreeHoleTypesInsideFillOfPassedUpPlace() async throws {
		// `HoleImpl` holds places of three hole types, of both families: `Worker`'s `thing` and `thingBuilder`, whose fills
		// read `chainToken`, and `gadgetBuilder`, which a `@Sendable` function builds. `Seam` builds `ChainLeaf` in a
		// `SendableInstantiator`, so it defers `chainToken` in a `SendableLazilyInstantiated`, whose instance each fill reads
		// where its tree reads it.
		let modules = Self.chainTokenModules(
			thingImpl: """
			@Instantiable(fulfillingAdditionalTypes: [ThingService.self])
			public final class ThingImpl: Instantiable, ThingService {
				public init(chainToken: ChainToken) { self.chainToken = chainToken; log.append("ThingImpl") }
				@Received let chainToken: ChainToken
			}

			@Instantiable(fulfillingAdditionalTypes: [GadgetService.self])
			public final class GadgetImpl: Instantiable, GadgetService {
				public init() { log.append("GadgetImpl") }
			}
			""",
			topChainToken: "@Instantiated let chainToken: SendableLazilyInstantiated<ChainToken>",
			chainLeafBuilder: "SendableInstantiator<ChainLeaf>",
			holeImpl: """
			@Instantiable(fulfillingAdditionalTypes: [HoleService.self])
			public final class HoleImpl: Instantiable, HoleService, @unchecked Sendable {
				public init(workerBuilder: Instantiator<Worker>, thingBuilder: ErasedInstantiator<(), any ThingService>, gadgetBuilder: SendableErasedInstantiator<(), any GadgetService>) {
					self.workerBuilder = workerBuilder
					self.thingBuilder = thingBuilder
					self.gadgetBuilder = gadgetBuilder
					log.append("HoleImpl")
				}
				@Instantiated public let workerBuilder: Instantiator<Worker>
				@Instantiated(fulfilledByType: "ThingImpl") public let thingBuilder: ErasedInstantiator<(), any ThingService>
				@Instantiated(fulfilledByType: "GadgetImpl") public let gadgetBuilder: SendableErasedInstantiator<(), any GadgetService>
			}
			""",
		)
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

		extension Outer {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let seam: (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>

		            public init(seam: @escaping (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>) {
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
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping @Sendable () -> ChainToken, __safeDI_holeServiceBuilder: SafeDIScope_HoleService.__safeDI_Builder<any HoleService>) {
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        func __safeDI_seam() -> Seam {
		            _ = Seam.__safeDI_Seam_29C9310C7F40EFF2.self
		            return Seam(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder.seam(SafeDIScope_HoleService.__safeDI_Values()))
		        }
		        let seam: Seam = __safeDI_seam()
		        self.init(seam: seam)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_D422BB9F89915A21 {}
		}

		extension Seam {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct holeService_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let leafBuilder: SendableInstantiator<ChainLeaf>
		            public let __safeDI_chainToken: SendableLazilyInstantiated<ChainToken>

		            init(chainToken: SendableLazilyInstantiated<ChainToken>, leafBuilder: SendableInstantiator<ChainLeaf>) {
		                __safeDI_chainToken = chainToken
		                self.leafBuilder = leafBuilder
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
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping @Sendable () -> ChainToken, __safeDI_holeServiceBuilder: SafeDIScope_HoleService.__safeDI_Builder<any HoleService>) {
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        @Sendable nonisolated func __safeDI_leafBuilder() -> ChainLeaf {
		            ChainLeaf(chainToken: chainToken.instance)
		        }
		        let leafBuilder = SendableInstantiator<ChainLeaf>(__safeDI_leafBuilder)
		        let holeService: any HoleService = __safeDI_holeServiceBuilder.holeService(SafeDIScope_HoleService.holeService_Values(chainToken: chainToken, leafBuilder: leafBuilder))
		        self.init(leafBuilder: leafBuilder, holeService: holeService)
		    }
		}

		extension Seam {
		    public enum __safeDI_Seam_29C9310C7F40EFF2 {}
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

		extension Mid {
		    nonisolated public enum SafeDISendableScope_GadgetImpl_GadgetService {
		        nonisolated public struct __safeDI_Values: Sendable {}

		        nonisolated public enum HoleImpl_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
		                public let gadgetBuilder: @Sendable (__safeDI_Values) -> SendableErasedInstantiator<(), __safeDI_Built>.Builder

		                public init(gadgetBuilder: @escaping @Sendable (__safeDI_Values) -> SendableErasedInstantiator<(), __safeDI_Built>.Builder) {
		                    self.gadgetBuilder = gadgetBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<(), __safeDI_Built>.Builder) {
		                    self.gadgetBuilder = { _ in __safeDI_builder }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
		            public let outer_holeServiceBuilder_Sendable: @Sendable (__safeDI_Values) -> SafeDISendableScope_GadgetImpl_GadgetService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(outer_holeServiceBuilder_Sendable: @escaping @Sendable (__safeDI_Values) -> SafeDISendableScope_GadgetImpl_GadgetService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.outer_holeServiceBuilder_Sendable = outer_holeServiceBuilder_Sendable
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<(), __safeDI_Built>.Builder) {
		                self.outer_holeServiceBuilder_Sendable = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    nonisolated public enum SafeDIScope_ThingImpl_ThingService {
		        nonisolated public struct outer_holeServiceBuilder_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let __safeDI_chainToken: SendableLazilyInstantiated<ChainToken>

		            init(chainToken: SendableLazilyInstantiated<ChainToken>) {
		                __safeDI_chainToken = chainToken
		            }
		        }

		        nonisolated public enum HoleImpl_Scope {
		            nonisolated public struct thingBuilder_Values {
		                public let workerBuilder: Instantiator<Worker>
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let thingBuilder: (thingBuilder_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder

		                public init(thingBuilder: @escaping (thingBuilder_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder) {
		                    self.thingBuilder = thingBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<(), __safeDI_Built>.Builder) {
		                    self.thingBuilder = { _ in __safeDI_builder }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let outer_holeServiceBuilder: (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingImpl_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(outer_holeServiceBuilder: @escaping (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingImpl_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.outer_holeServiceBuilder = outer_holeServiceBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<(), __safeDI_Built>.Builder) {
		                self.outer_holeServiceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		            }
		        }
		    }

		    nonisolated public enum SafeDIScope_ThingService {
		        nonisolated public struct outer_holeServiceBuilder_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let __safeDI_chainToken: SendableLazilyInstantiated<ChainToken>

		            init(chainToken: SendableLazilyInstantiated<ChainToken>) {
		                __safeDI_chainToken = chainToken
		            }
		        }

		        nonisolated public enum HoleImpl_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let workerBuilder: (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(workerBuilder: @escaping (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.workerBuilder = workerBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.workerBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        nonisolated public enum Worker_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let thing: (__safeDI_Values) -> __safeDI_Built

		                public init(thing: @escaping (__safeDI_Values) -> __safeDI_Built) {
		                    self.thing = thing
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.thing = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let outer_holeServiceBuilder: (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(outer_holeServiceBuilder: @escaping (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.outer_holeServiceBuilder = outer_holeServiceBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.outer_holeServiceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		            }
		        }
		    }

		    // SafeDI counts `GadgetService` and `ThingService` as `public`: no module it reads declares them narrower. If one is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping @Sendable () -> ChainToken, __safeDI_gadgetImpl_GadgetServiceSendableBuilder: SafeDISendableScope_GadgetImpl_GadgetService.__safeDI_Builder<any GadgetService>, __safeDI_thingImpl_ThingServiceBuilder: SafeDIScope_ThingImpl_ThingService.__safeDI_Builder<any ThingService>, __safeDI_thingServiceBuilder: SafeDIScope_ThingService.__safeDI_Builder<any ThingService>) {
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        let __safeDI_gadgetImpl_GadgetServiceSendableBuilder_outer_holeServiceBuilder_Sendable = __safeDI_gadgetImpl_GadgetServiceSendableBuilder.outer_holeServiceBuilder_Sendable(SafeDISendableScope_GadgetImpl_GadgetService.__safeDI_Values())
		        let __safeDI_thingImpl_ThingServiceBuilder_outer_holeServiceBuilder = __safeDI_thingImpl_ThingServiceBuilder.outer_holeServiceBuilder(SafeDIScope_ThingImpl_ThingService.outer_holeServiceBuilder_Values(chainToken: chainToken))
		        let __safeDI_thingServiceBuilder_outer_holeServiceBuilder = __safeDI_thingServiceBuilder.outer_holeServiceBuilder(SafeDIScope_ThingService.outer_holeServiceBuilder_Values(chainToken: chainToken))
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_D422BB9F89915A21.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_holeServiceBuilder_Seam_holeService(_ scope: Seam.SafeDIScope_HoleService.holeService_Values, __safeDI_outer_holeServiceBuilder_thingImpl_ThingServiceBuilder: SafeDIScope_ThingImpl_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>, __safeDI_outer_holeServiceBuilder_thingServiceBuilder: SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>) -> any HoleService {
		                func __safeDI_holeService() -> HoleImpl {
		                    let __safeDI_thingServiceBuilder_workerBuilder = __safeDI_outer_holeServiceBuilder_thingServiceBuilder.workerBuilder(SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Values())
		                    func __safeDI_workerBuilder() -> Worker {
		                        let thing: any ThingService = __safeDI_thingServiceBuilder_workerBuilder.thing(SafeDIScope_ThingService.Worker_Scope.__safeDI_Values())
		                        return Worker(thing: thing)
		                    }
		                    let workerBuilder = Instantiator<Worker>(__safeDI_workerBuilder)
		                    let thingBuilder = ErasedInstantiator<(), any ThingService>(__safeDI_outer_holeServiceBuilder_thingImpl_ThingServiceBuilder.thingBuilder(SafeDIScope_ThingImpl_ThingService.HoleImpl_Scope.thingBuilder_Values(workerBuilder: workerBuilder)))
		                    let gadgetBuilder = SendableErasedInstantiator<(), any GadgetService>(__safeDI_gadgetImpl_GadgetServiceSendableBuilder_outer_holeServiceBuilder_Sendable.gadgetBuilder(SafeDISendableScope_GadgetImpl_GadgetService.HoleImpl_Scope.__safeDI_Values()))
		                    return HoleImpl(workerBuilder: workerBuilder, thingBuilder: thingBuilder, gadgetBuilder: gadgetBuilder)
		                }
		                let holeService: any HoleService = __safeDI_holeService()
		                return holeService
		            }
		            func __safeDI_holeServiceBuilder_Outer(up_outer_holeServiceBuilder_thingImpl_ThingServiceBuilder: Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingImpl_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>, up_outer_holeServiceBuilder_thingServiceBuilder: Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(seam: { values in __safeDI_holeServiceBuilder_Seam(up_outer_holeServiceBuilder_thingImpl_ThingServiceBuilder: up_outer_holeServiceBuilder_thingImpl_ThingServiceBuilder.seam(values), up_outer_holeServiceBuilder_thingServiceBuilder: up_outer_holeServiceBuilder_thingServiceBuilder.seam(values)) })
		            }
		            func __safeDI_holeServiceBuilder_Seam(up_outer_holeServiceBuilder_thingImpl_ThingServiceBuilder: Seam.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingImpl_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>, up_outer_holeServiceBuilder_thingServiceBuilder: Seam.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(holeService: { scope in __safeDI_holeServiceBuilder_Seam_holeService(scope, __safeDI_outer_holeServiceBuilder_thingImpl_ThingServiceBuilder: up_outer_holeServiceBuilder_thingImpl_ThingServiceBuilder.holeService(scope), __safeDI_outer_holeServiceBuilder_thingServiceBuilder: up_outer_holeServiceBuilder_thingServiceBuilder.holeService(scope)) })
		            }
		            return Outer(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder_Outer(up_outer_holeServiceBuilder_thingImpl_ThingServiceBuilder: __safeDI_thingImpl_ThingServiceBuilder_outer_holeServiceBuilder, up_outer_holeServiceBuilder_thingServiceBuilder: __safeDI_thingServiceBuilder_outer_holeServiceBuilder))
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(outer: outer)
		    }
		}

		extension Mid {
		    public enum __safeDI_Mid_CFB9CB1341F93E1F {}
		}
		"""])
		#expect(output.modules["Top"]?.generatedFiles == ["Top.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Other)
		import Other
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension TopRoot {
		    public convenience init() {
		        @Sendable func __safeDI_chainToken() -> ChainToken {
		            ChainToken()
		        }
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        func __safeDI_mid() -> Mid {
		            _ = Mid.__safeDI_Mid_CFB9CB1341F93E1F.self // If this line does not compile, compile the code SafeDI generates for module Other into Other: under Bazel, add Other’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            @Sendable nonisolated func __safeDI_gadgetImpl_GadgetServiceSendableBuilder_Mid_HoleImpl_Scope_gadgetBuilder() -> SendableErasedInstantiator<(), any GadgetService>.Builder {
		                @Sendable nonisolated func __safeDI_gadgetBuilder() -> GadgetImpl {
		                    GadgetImpl()
		                }
		                return { _ in __safeDI_gadgetBuilder() }
		            }
		            func __safeDI_thingImpl_ThingServiceBuilder_Mid_HoleImpl_Scope_thingBuilder(chainToken: SendableLazilyInstantiated<ChainToken>) -> ErasedInstantiator<(), any ThingService>.Builder {
		                func __safeDI_thingBuilder() -> ThingImpl {
		                    ThingImpl(chainToken: chainToken.instance)
		                }
		                return { _ in __safeDI_thingBuilder() }
		            }
		            @Sendable nonisolated func __safeDI_gadgetImpl_GadgetServiceSendableBuilder_Mid() -> Mid.SafeDISendableScope_GadgetImpl_GadgetService.__safeDI_Builder<any GadgetService> {
		                .init(outer_holeServiceBuilder_Sendable: { _ in __safeDI_gadgetImpl_GadgetServiceSendableBuilder_Mid_HoleImpl_Scope() })
		            }
		            @Sendable nonisolated func __safeDI_gadgetImpl_GadgetServiceSendableBuilder_Mid_HoleImpl_Scope() -> Mid.SafeDISendableScope_GadgetImpl_GadgetService.HoleImpl_Scope.__safeDI_Builder<any GadgetService> {
		                .init(gadgetBuilder: { _ in __safeDI_gadgetImpl_GadgetServiceSendableBuilder_Mid_HoleImpl_Scope_gadgetBuilder() })
		            }
		            func __safeDI_thingImpl_ThingServiceBuilder_Mid() -> Mid.SafeDIScope_ThingImpl_ThingService.__safeDI_Builder<any ThingService> {
		                .init(outer_holeServiceBuilder: { _ in __safeDI_thingImpl_ThingServiceBuilder_Mid_Outer() })
		            }
		            func __safeDI_thingImpl_ThingServiceBuilder_Mid_HoleImpl_Scope(chainToken: SendableLazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingImpl_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService> {
		                .init(thingBuilder: { _ in __safeDI_thingImpl_ThingServiceBuilder_Mid_HoleImpl_Scope_thingBuilder(chainToken: chainToken) })
		            }
		            func __safeDI_thingServiceBuilder_Mid() -> Mid.SafeDIScope_ThingService.__safeDI_Builder<any ThingService> {
		                .init(outer_holeServiceBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Outer() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: SendableLazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService> {
		                .init(workerBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: chainToken) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: SendableLazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<any ThingService> {
		                .init(thing: { _ in
		                    let thing: any ThingService = ThingImpl(chainToken: chainToken.instance)
		                    return thing
		                })
		            }
		            func __safeDI_thingImpl_ThingServiceBuilder_Mid_Outer() -> Outer.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingImpl_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(seam: { _ in __safeDI_thingImpl_ThingServiceBuilder_Mid_Seam() })
		            }
		            func __safeDI_thingImpl_ThingServiceBuilder_Mid_Seam() -> Seam.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingImpl_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(holeService: { values in __safeDI_thingImpl_ThingServiceBuilder_Mid_HoleImpl_Scope(chainToken: values.__safeDI_chainToken) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Outer() -> Outer.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(seam: { _ in __safeDI_thingServiceBuilder_Mid_Seam() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Seam() -> Seam.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(holeService: { values in __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: values.__safeDI_chainToken) })
		            }
		            return Mid(__safeDI_chainToken: chainToken.instance, __safeDI_gadgetImpl_GadgetServiceSendableBuilder: __safeDI_gadgetImpl_GadgetServiceSendableBuilder_Mid(), __safeDI_thingImpl_ThingServiceBuilder: __safeDI_thingImpl_ThingServiceBuilder_Mid(), __safeDI_thingServiceBuilder: __safeDI_thingServiceBuilder_Mid())
		        }
		        let mid: Mid = __safeDI_mid()
		        self.init(chainToken: chainToken, mid: mid)
		    }
		}
		"""])
		try await expectCreationOrderEqualsOneModuleBuild(output, modules: modules, builders: ["workerBuilder", "thingBuilder", "gadgetBuilder"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_levelFunctionHandsValueOn_whenCallerFillsPlaceInsideFillOfPassedUpPlaceReadingValueInsideSendableFunction() async throws {
		// `ThingImpl` builds `TokenReader`, which receives `chainToken`, in a `SendableInstantiator`, whose `@Sendable`
		// function cannot capture `Seam`'s `LazilyInstantiated`: the level functions hand the value on, which the fill binds,
		// so the value is created where `Seam`'s level function is called (`seam-holes.md`). Built in one module, the same
		// graph is rejected, since `TokenReader`'s builder would capture `TopRoot`'s `LazilyInstantiated`.
		let modules = Self.chainTokenModules(thingImpl: """
		@Instantiable
		public final class TokenReader: Instantiable, Sendable {
			public init(chainToken: ChainToken) { self.chainToken = chainToken; log.append("TokenReader") }
			@Received let chainToken: ChainToken
		}

		@Instantiable(fulfillingAdditionalTypes: [ThingService.self])
		public final class ThingImpl: Instantiable, ThingService {
			public init(readerBuilder: SendableInstantiator<TokenReader>) { self.readerBuilder = readerBuilder; log.append("ThingImpl") }
			@Instantiated let readerBuilder: SendableInstantiator<TokenReader>
		}
		""")
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

		extension Outer {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let seam: (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>

		            public init(seam: @escaping (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>) {
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
		            _ = Seam.__safeDI_Seam_2AD7242F90FE57C2.self
		            return Seam(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder.seam(SafeDIScope_HoleService.__safeDI_Values()))
		        }
		        let seam: Seam = __safeDI_seam()
		        self.init(seam: seam)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_2A8D23C10A89B5A9 {}
		}

		extension Seam {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct holeService_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let leafBuilder: Instantiator<ChainLeaf>
		            public let __safeDI_chainToken: LazilyInstantiated<ChainToken>

		            init(chainToken: LazilyInstantiated<ChainToken>, leafBuilder: Instantiator<ChainLeaf>) {
		                __safeDI_chainToken = chainToken
		                self.leafBuilder = leafBuilder
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
		        func __safeDI_leafBuilder() -> ChainLeaf {
		            ChainLeaf(chainToken: chainToken.instance)
		        }
		        let leafBuilder = Instantiator<ChainLeaf>(__safeDI_leafBuilder)
		        let holeService: any HoleService = __safeDI_holeServiceBuilder.holeService(SafeDIScope_HoleService.holeService_Values(chainToken: chainToken, leafBuilder: leafBuilder))
		        self.init(leafBuilder: leafBuilder, holeService: holeService)
		    }
		}

		extension Seam {
		    public enum __safeDI_Seam_2AD7242F90FE57C2 {}
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

		extension Mid {
		    nonisolated public enum SafeDIScope_ThingService {
		        nonisolated public struct outer_holeServiceBuilder_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let __safeDI_chainToken: LazilyInstantiated<ChainToken>

		            init(chainToken: LazilyInstantiated<ChainToken>) {
		                __safeDI_chainToken = chainToken
		            }
		        }

		        nonisolated public enum HoleImpl_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let workerBuilder: (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(workerBuilder: @escaping (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.workerBuilder = workerBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.workerBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        nonisolated public enum Worker_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let thing: (__safeDI_Values) -> __safeDI_Built

		                public init(thing: @escaping (__safeDI_Values) -> __safeDI_Built) {
		                    self.thing = thing
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.thing = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let outer_holeServiceBuilder: (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(outer_holeServiceBuilder: @escaping (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.outer_holeServiceBuilder = outer_holeServiceBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.outer_holeServiceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		            }
		        }
		    }

		    // SafeDI counts `ThingService` as `public`: no module it reads declares it narrower. If `ThingService` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping () -> ChainToken, __safeDI_thingServiceBuilder: SafeDIScope_ThingService.__safeDI_Builder<any ThingService>) {
		        let chainToken = LazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        let __safeDI_thingServiceBuilder_outer_holeServiceBuilder = __safeDI_thingServiceBuilder.outer_holeServiceBuilder(SafeDIScope_ThingService.outer_holeServiceBuilder_Values(chainToken: chainToken))
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_2A8D23C10A89B5A9.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_holeServiceBuilder_Seam_holeService(_ scope: Seam.SafeDIScope_HoleService.holeService_Values, __safeDI_outer_holeServiceBuilder: SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>) -> any HoleService {
		                func __safeDI_holeService() -> HoleImpl {
		                    let __safeDI_thingServiceBuilder_workerBuilder = __safeDI_outer_holeServiceBuilder.workerBuilder(SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Values())
		                    func __safeDI_workerBuilder() -> Worker {
		                        let thing: any ThingService = __safeDI_thingServiceBuilder_workerBuilder.thing(SafeDIScope_ThingService.Worker_Scope.__safeDI_Values())
		                        return Worker(thing: thing)
		                    }
		                    let workerBuilder = Instantiator<Worker>(__safeDI_workerBuilder)
		                    return HoleImpl(workerBuilder: workerBuilder)
		                }
		                let holeService: any HoleService = __safeDI_holeService()
		                return holeService
		            }
		            func __safeDI_holeServiceBuilder_Outer(up: Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(seam: { values in __safeDI_holeServiceBuilder_Seam(up: up.seam(values)) })
		            }
		            func __safeDI_holeServiceBuilder_Seam(up: Seam.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(holeService: { scope in __safeDI_holeServiceBuilder_Seam_holeService(scope, __safeDI_outer_holeServiceBuilder: up.holeService(scope)) })
		            }
		            return Outer(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder_Outer(up: __safeDI_thingServiceBuilder_outer_holeServiceBuilder))
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(outer: outer)
		    }
		}

		extension Mid {
		    public enum __safeDI_Mid_C9E7A7B945AD1E35 {}
		}
		"""])
		#expect(output.modules["Top"]?.generatedFiles == ["Top.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Other)
		import Other
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension TopRoot {
		    public convenience init() {
		        func __safeDI_chainToken() -> ChainToken {
		            ChainToken()
		        }
		        let chainToken = LazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        func __safeDI_mid() -> Mid {
		            _ = Mid.__safeDI_Mid_C9E7A7B945AD1E35.self // If this line does not compile, compile the code SafeDI generates for module Other into Other: under Bazel, add Other’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope_thing(_ scope: Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Values, chainToken: ChainToken) -> any ThingService {
		                func __safeDI_thing() -> ThingImpl {
		                    @Sendable func __safeDI_readerBuilder() -> TokenReader {
		                        TokenReader(chainToken: chainToken)
		                    }
		                    let readerBuilder = SendableInstantiator<TokenReader>(__safeDI_readerBuilder)
		                    return ThingImpl(readerBuilder: readerBuilder)
		                }
		                let thing: any ThingService = __safeDI_thing()
		                return thing
		            }
		            func __safeDI_thingServiceBuilder_Mid() -> Mid.SafeDIScope_ThingService.__safeDI_Builder<any ThingService> {
		                .init(outer_holeServiceBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Outer() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: ChainToken) -> Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService> {
		                .init(workerBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: chainToken) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: ChainToken) -> Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<any ThingService> {
		                .init(thing: { scope in __safeDI_thingServiceBuilder_Mid_Worker_Scope_thing(scope, chainToken: chainToken) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Outer() -> Outer.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(seam: { _ in __safeDI_thingServiceBuilder_Mid_Seam() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Seam() -> Seam.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(holeService: { values in __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: values.chainToken) })
		            }
		            return Mid(__safeDI_chainToken: chainToken.instance, __safeDI_thingServiceBuilder: __safeDI_thingServiceBuilder_Mid())
		        }
		        let mid: Mid = __safeDI_mid()
		        self.init(chainToken: chainToken, mid: mid)
		    }
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_levelFunctionHandsMemoToEachFill_whenCallingSeamBuildsPlacesTypeEagerlyOnItsOwnRoute() async throws {
		// `HoleImpl` holds `thing`, which only the route through `Seam` reaches, and builds `Worker`, which `Mid` builds too,
		// eagerly: `Worker`'s level is reached from `Mid`'s own too, where the root dispatcher makes a memo of the caller's
		// declaration, so both fills take the memo, which `HoleImpl`'s level function hands each. `Mid` builds its `Worker`
		// while it is built, so both builds create `ChainToken` then.
		let modules = Self.chainTokenModules(
			holeImpl: """
			@Instantiable(fulfillingAdditionalTypes: [HoleService.self])
			public final class HoleImpl: Instantiable, HoleService, @unchecked Sendable {
				public init(workerBuilder: Instantiator<Worker>, thing: any ThingService) {
					self.workerBuilder = workerBuilder
					self.thing = thing
					log.append("HoleImpl")
				}
				@Instantiated public let workerBuilder: Instantiator<Worker>
				@Instantiated let thing: any ThingService
			}
			""",
			midWorker: true,
		)
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

		extension Outer {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let seam: (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>

		            public init(seam: @escaping (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>) {
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
		            _ = Seam.__safeDI_Seam_2AD7242F90FE57C2.self
		            return Seam(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder.seam(SafeDIScope_HoleService.__safeDI_Values()))
		        }
		        let seam: Seam = __safeDI_seam()
		        self.init(seam: seam)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_2A8D23C10A89B5A9 {}
		}

		extension Seam {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct holeService_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let leafBuilder: Instantiator<ChainLeaf>
		            public let __safeDI_chainToken: LazilyInstantiated<ChainToken>

		            init(chainToken: LazilyInstantiated<ChainToken>, leafBuilder: Instantiator<ChainLeaf>) {
		                __safeDI_chainToken = chainToken
		                self.leafBuilder = leafBuilder
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
		        func __safeDI_leafBuilder() -> ChainLeaf {
		            ChainLeaf(chainToken: chainToken.instance)
		        }
		        let leafBuilder = Instantiator<ChainLeaf>(__safeDI_leafBuilder)
		        let holeService: any HoleService = __safeDI_holeServiceBuilder.holeService(SafeDIScope_HoleService.holeService_Values(chainToken: chainToken, leafBuilder: leafBuilder))
		        self.init(leafBuilder: leafBuilder, holeService: holeService)
		    }
		}

		extension Seam {
		    public enum __safeDI_Seam_2AD7242F90FE57C2 {}
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

		extension Mid {
		    nonisolated public enum SafeDIScope_ThingService {
		        nonisolated public struct worker_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let __safeDI_chainToken: LazilyInstantiated<ChainToken>

		            init(chainToken: LazilyInstantiated<ChainToken>) {
		                __safeDI_chainToken = chainToken
		            }
		        }

		        nonisolated public struct outer_holeServiceBuilder_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let worker: Worker
		            public let __safeDI_chainToken: LazilyInstantiated<ChainToken>

		            init(chainToken: LazilyInstantiated<ChainToken>, worker: Worker) {
		                __safeDI_chainToken = chainToken
		                self.worker = worker
		            }
		        }

		        nonisolated public enum Worker_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let thing: (__safeDI_Values) -> __safeDI_Built

		                public init(thing: @escaping (__safeDI_Values) -> __safeDI_Built) {
		                    self.thing = thing
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.thing = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        nonisolated public enum HoleImpl_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            nonisolated public struct thing_Values {
		                public let workerBuilder: Instantiator<Worker>
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public final class __safeDI_Builder<__safeDI_Built> {
		                public let workerBuilder: (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>
		                public let thing: (thing_Values) -> __safeDI_Built

		                public init(workerBuilder: @escaping (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>, thing: @escaping (thing_Values) -> __safeDI_Built) {
		                    self.workerBuilder = workerBuilder
		                    self.thing = thing
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.workerBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                    self.thing = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public final class __safeDI_Builder<__safeDI_Built> {
		            public let worker: (worker_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>
		            public let outer_holeServiceBuilder: (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(worker: @escaping (worker_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>, outer_holeServiceBuilder: @escaping (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.worker = worker
		                self.outer_holeServiceBuilder = outer_holeServiceBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.worker = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                self.outer_holeServiceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		            }
		        }
		    }

		    // SafeDI counts `ThingService` as `public`: no module it reads declares it narrower. If `ThingService` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping () -> ChainToken, __safeDI_thingServiceBuilder: SafeDIScope_ThingService.__safeDI_Builder<any ThingService>) {
		        let chainToken = LazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        let __safeDI_thingServiceBuilder_worker = __safeDI_thingServiceBuilder.worker(SafeDIScope_ThingService.worker_Values(chainToken: chainToken))
		        func __safeDI_worker() -> Worker {
		            let thing: any ThingService = __safeDI_thingServiceBuilder_worker.thing(SafeDIScope_ThingService.Worker_Scope.__safeDI_Values())
		            return Worker(thing: thing)
		        }
		        let worker: Worker = __safeDI_worker()
		        let __safeDI_thingServiceBuilder_outer_holeServiceBuilder = __safeDI_thingServiceBuilder.outer_holeServiceBuilder(SafeDIScope_ThingService.outer_holeServiceBuilder_Values(chainToken: chainToken, worker: worker))
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_2A8D23C10A89B5A9.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_holeServiceBuilder_Seam_holeService(_ scope: Seam.SafeDIScope_HoleService.holeService_Values, __safeDI_outer_holeServiceBuilder: SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>) -> any HoleService {
		                func __safeDI_holeService() -> HoleImpl {
		                    let __safeDI_thingServiceBuilder_workerBuilder = __safeDI_outer_holeServiceBuilder.workerBuilder(SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Values())
		                    func __safeDI_workerBuilder() -> Worker {
		                        let thing: any ThingService = __safeDI_thingServiceBuilder_workerBuilder.thing(SafeDIScope_ThingService.Worker_Scope.__safeDI_Values())
		                        return Worker(thing: thing)
		                    }
		                    let workerBuilder = Instantiator<Worker>(__safeDI_workerBuilder)
		                    let thing: any ThingService = __safeDI_outer_holeServiceBuilder.thing(SafeDIScope_ThingService.HoleImpl_Scope.thing_Values(workerBuilder: workerBuilder))
		                    return HoleImpl(workerBuilder: workerBuilder, thing: thing)
		                }
		                let holeService: any HoleService = __safeDI_holeService()
		                return holeService
		            }
		            func __safeDI_holeServiceBuilder_Outer(up: Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(seam: { values in __safeDI_holeServiceBuilder_Seam(up: up.seam(values)) })
		            }
		            func __safeDI_holeServiceBuilder_Seam(up: Seam.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(holeService: { scope in __safeDI_holeServiceBuilder_Seam_holeService(scope, __safeDI_outer_holeServiceBuilder: up.holeService(scope)) })
		            }
		            return Outer(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder_Outer(up: __safeDI_thingServiceBuilder_outer_holeServiceBuilder))
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(outer: outer, worker: worker)
		    }
		}

		extension Mid {
		    public enum __safeDI_Mid_FEC927C633CCC02F {}
		}
		"""])
		#expect(output.modules["Top"]?.generatedFiles == ["Top.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Other)
		import Other
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension TopRoot {
		    public convenience init() {
		        func __safeDI_chainToken() -> ChainToken {
		            ChainToken()
		        }
		        let chainToken = LazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        func __safeDI_mid() -> Mid {
		            _ = Mid.__safeDI_Mid_FEC927C633CCC02F.self // If this line does not compile, compile the code SafeDI generates for module Other into Other: under Bazel, add Other’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_thingServiceBuilder_Mid() -> Mid.SafeDIScope_ThingService.__safeDI_Builder<any ThingService> {
		                .init(worker: { _ in __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: LazilyInstantiated<ChainToken>({ chainToken.instance })) }, outer_holeServiceBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Outer() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: LazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<any ThingService> {
		                .init(thing: { _ in
		                    let thing: any ThingService = ThingImpl(chainToken: chainToken.instance)
		                    return thing
		                })
		            }
		            func __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: LazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService> {
		                .init(
		                    workerBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: chainToken) },
		                    thing: { _ in
		                        let thing: any ThingService = ThingImpl(chainToken: chainToken.instance)
		                        return thing
		                    }
		                )
		            }
		            func __safeDI_thingServiceBuilder_Mid_Outer() -> Outer.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(seam: { _ in __safeDI_thingServiceBuilder_Mid_Seam() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Seam() -> Seam.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(holeService: { values in __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: values.__safeDI_chainToken) })
		            }
		            return Mid(__safeDI_chainToken: chainToken.instance, __safeDI_thingServiceBuilder: __safeDI_thingServiceBuilder_Mid())
		        }
		        let mid: Mid = __safeDI_mid()
		        self.init(chainToken: chainToken, mid: mid)
		    }
		}
		"""])
		try await expectCreationOrderEqualsOneModuleBuild(output, modules: modules)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillTakesMemoOnEveryRoute_whenCallingSeamBuildsPlacesTypeLazilyOnItsOwnRouteToo() async throws {
		// `Mid` builds `Worker` in `midWorkerBuilder` too, so `Worker`'s fill is reached from `Mid`'s own root, where the root
		// dispatcher hands the caller's declaration, and through `Seam`'s level, which hands `Seam`'s memo: the fill takes a
		// `LazilyInstantiated` on both routes, the root dispatcher making one of the caller's declaration, so `ChainToken` is
		// created when a `Worker` is first built, as in the one-module build.
		let modules = Self.chainTokenModules(midWorkerBuilder: true)
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

		extension Outer {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let seam: (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>

		            public init(seam: @escaping (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>) {
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
		            _ = Seam.__safeDI_Seam_2AD7242F90FE57C2.self
		            return Seam(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder.seam(SafeDIScope_HoleService.__safeDI_Values()))
		        }
		        let seam: Seam = __safeDI_seam()
		        self.init(seam: seam)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_2A8D23C10A89B5A9 {}
		}

		extension Seam {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct holeService_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let leafBuilder: Instantiator<ChainLeaf>
		            public let __safeDI_chainToken: LazilyInstantiated<ChainToken>

		            init(chainToken: LazilyInstantiated<ChainToken>, leafBuilder: Instantiator<ChainLeaf>) {
		                __safeDI_chainToken = chainToken
		                self.leafBuilder = leafBuilder
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
		        func __safeDI_leafBuilder() -> ChainLeaf {
		            ChainLeaf(chainToken: chainToken.instance)
		        }
		        let leafBuilder = Instantiator<ChainLeaf>(__safeDI_leafBuilder)
		        let holeService: any HoleService = __safeDI_holeServiceBuilder.holeService(SafeDIScope_HoleService.holeService_Values(chainToken: chainToken, leafBuilder: leafBuilder))
		        self.init(leafBuilder: leafBuilder, holeService: holeService)
		    }
		}

		extension Seam {
		    public enum __safeDI_Seam_2AD7242F90FE57C2 {}
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

		extension Mid {
		    nonisolated public enum SafeDIScope_ThingService {
		        nonisolated public struct outer_holeServiceBuilder_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let __safeDI_chainToken: LazilyInstantiated<ChainToken>

		            init(chainToken: LazilyInstantiated<ChainToken>) {
		                __safeDI_chainToken = chainToken
		            }
		        }

		        nonisolated public struct midWorkerBuilder_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let outer: Outer
		            public let __safeDI_chainToken: LazilyInstantiated<ChainToken>

		            init(chainToken: LazilyInstantiated<ChainToken>, outer: Outer) {
		                __safeDI_chainToken = chainToken
		                self.outer = outer
		            }
		        }

		        nonisolated public enum HoleImpl_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let workerBuilder: (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(workerBuilder: @escaping (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.workerBuilder = workerBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.workerBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        nonisolated public enum Worker_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let thing: (__safeDI_Values) -> __safeDI_Built

		                public init(thing: @escaping (__safeDI_Values) -> __safeDI_Built) {
		                    self.thing = thing
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.thing = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public final class __safeDI_Builder<__safeDI_Built> {
		            public let outer_holeServiceBuilder: (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>
		            public let midWorkerBuilder: (midWorkerBuilder_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(outer_holeServiceBuilder: @escaping (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>, midWorkerBuilder: @escaping (midWorkerBuilder_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.outer_holeServiceBuilder = outer_holeServiceBuilder
		                self.midWorkerBuilder = midWorkerBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.outer_holeServiceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		                self.midWorkerBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    // SafeDI counts `ThingService` as `public`: no module it reads declares it narrower. If `ThingService` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping () -> ChainToken, __safeDI_thingServiceBuilder: SafeDIScope_ThingService.__safeDI_Builder<any ThingService>) {
		        let chainToken = LazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        let __safeDI_thingServiceBuilder_outer_holeServiceBuilder = __safeDI_thingServiceBuilder.outer_holeServiceBuilder(SafeDIScope_ThingService.outer_holeServiceBuilder_Values(chainToken: chainToken))
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_2A8D23C10A89B5A9.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_holeServiceBuilder_Seam_holeService(_ scope: Seam.SafeDIScope_HoleService.holeService_Values, __safeDI_outer_holeServiceBuilder: SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>) -> any HoleService {
		                func __safeDI_holeService() -> HoleImpl {
		                    let __safeDI_thingServiceBuilder_workerBuilder = __safeDI_outer_holeServiceBuilder.workerBuilder(SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Values())
		                    func __safeDI_workerBuilder() -> Worker {
		                        let thing: any ThingService = __safeDI_thingServiceBuilder_workerBuilder.thing(SafeDIScope_ThingService.Worker_Scope.__safeDI_Values())
		                        return Worker(thing: thing)
		                    }
		                    let workerBuilder = Instantiator<Worker>(__safeDI_workerBuilder)
		                    return HoleImpl(workerBuilder: workerBuilder)
		                }
		                let holeService: any HoleService = __safeDI_holeService()
		                return holeService
		            }
		            func __safeDI_holeServiceBuilder_Outer(up: Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(seam: { values in __safeDI_holeServiceBuilder_Seam(up: up.seam(values)) })
		            }
		            func __safeDI_holeServiceBuilder_Seam(up: Seam.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(holeService: { scope in __safeDI_holeServiceBuilder_Seam_holeService(scope, __safeDI_outer_holeServiceBuilder: up.holeService(scope)) })
		            }
		            return Outer(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder_Outer(up: __safeDI_thingServiceBuilder_outer_holeServiceBuilder))
		        }
		        let outer: Outer = __safeDI_outer()
		        let __safeDI_thingServiceBuilder_midWorkerBuilder = __safeDI_thingServiceBuilder.midWorkerBuilder(SafeDIScope_ThingService.midWorkerBuilder_Values(chainToken: chainToken, outer: outer))
		        func __safeDI_midWorkerBuilder() -> Worker {
		            let thing: any ThingService = __safeDI_thingServiceBuilder_midWorkerBuilder.thing(SafeDIScope_ThingService.Worker_Scope.__safeDI_Values())
		            return Worker(thing: thing)
		        }
		        let midWorkerBuilder = Instantiator<Worker>(__safeDI_midWorkerBuilder)
		        self.init(outer: outer, midWorkerBuilder: midWorkerBuilder)
		    }
		}

		extension Mid {
		    public enum __safeDI_Mid_FE17154EF8DB3070 {}
		}
		"""])
		#expect(output.modules["Top"]?.generatedFiles == ["Top.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Other)
		import Other
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension TopRoot {
		    public convenience init() {
		        func __safeDI_chainToken() -> ChainToken {
		            ChainToken()
		        }
		        let chainToken = LazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        func __safeDI_mid() -> Mid {
		            _ = Mid.__safeDI_Mid_FE17154EF8DB3070.self // If this line does not compile, compile the code SafeDI generates for module Other into Other: under Bazel, add Other’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_thingServiceBuilder_Mid() -> Mid.SafeDIScope_ThingService.__safeDI_Builder<any ThingService> {
		                .init(outer_holeServiceBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Outer() }, midWorkerBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: LazilyInstantiated<ChainToken>({ chainToken.instance })) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: LazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService> {
		                .init(workerBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: chainToken) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: LazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<any ThingService> {
		                .init(thing: { _ in
		                    let thing: any ThingService = ThingImpl(chainToken: chainToken.instance)
		                    return thing
		                })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Outer() -> Outer.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(seam: { _ in __safeDI_thingServiceBuilder_Mid_Seam() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Seam() -> Seam.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(holeService: { values in __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: values.__safeDI_chainToken) })
		            }
		            return Mid(__safeDI_chainToken: chainToken.instance, __safeDI_thingServiceBuilder: __safeDI_thingServiceBuilder_Mid())
		        }
		        let mid: Mid = __safeDI_mid()
		        self.init(chainToken: chainToken, mid: mid)
		    }
		}
		"""])
		try await expectCreationOrderEqualsOneModuleBuild(output, modules: modules, midBuilders: ["midWorkerBuilder"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillTakesMemoOnEveryRoute_whenTwoPassingUpSeamsDeferValueUnlike() async throws {
		// `Outer` passes up the places of two seams, `Seam`, which defers `chainToken` in a `LazilyInstantiated`, and `SeamB`,
		// whose `SendableInstantiator` defers it in a `SendableLazilyInstantiated`: the fill takes a `LazilyInstantiated`, which
		// `SeamB`'s level makes of its memo, so `ChainToken` is created when `Worker` is built, as in the one-module build.
		let modules = Self.chainTokenModules(topChainToken: "@Instantiated let chainToken: SendableLazilyInstantiated<ChainToken>", outerHoldsSeamB: true)
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

		extension Outer {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public final class __safeDI_Builder<__safeDI_Built> {
		            public let seamB: (__safeDI_Values) -> SeamB.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>
		            public let seam: (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>

		            public init(seamB: @escaping (__safeDI_Values) -> SeamB.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>, seam: @escaping (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>) {
		                self.seamB = seamB
		                self.seam = seam
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.seamB = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                self.seam = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    // SafeDI counts `HoleService` as `public`: no module it reads declares it narrower. If `HoleService` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping @Sendable () -> ChainToken, __safeDI_holeServiceBuilder: SafeDIScope_HoleService.__safeDI_Builder<any HoleService>) {
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        func __safeDI_seamB() -> SeamB {
		            _ = SeamB.__safeDI_SeamB_DC2838BAE7387202.self
		            return SeamB(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder.seamB(SafeDIScope_HoleService.__safeDI_Values()))
		        }
		        let seamB: SeamB = __safeDI_seamB()
		        func __safeDI_seam() -> Seam {
		            _ = Seam.__safeDI_Seam_2AD7242F90FE57C2.self
		            return Seam(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder.seam(SafeDIScope_HoleService.__safeDI_Values()))
		        }
		        let seam: Seam = __safeDI_seam()
		        self.init(seam: seam, seamB: seamB)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_964A004ABC6F5712 {}
		}

		extension Seam {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct holeService_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let leafBuilder: Instantiator<ChainLeaf>
		            public let __safeDI_chainToken: LazilyInstantiated<ChainToken>

		            init(chainToken: LazilyInstantiated<ChainToken>, leafBuilder: Instantiator<ChainLeaf>) {
		                __safeDI_chainToken = chainToken
		                self.leafBuilder = leafBuilder
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
		        func __safeDI_leafBuilder() -> ChainLeaf {
		            ChainLeaf(chainToken: chainToken.instance)
		        }
		        let leafBuilder = Instantiator<ChainLeaf>(__safeDI_leafBuilder)
		        let holeService: any HoleService = __safeDI_holeServiceBuilder.holeService(SafeDIScope_HoleService.holeService_Values(chainToken: chainToken, leafBuilder: leafBuilder))
		        self.init(leafBuilder: leafBuilder, holeService: holeService)
		    }
		}

		extension Seam {
		    public enum __safeDI_Seam_2AD7242F90FE57C2 {}
		}

		extension SeamB {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct holeService_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let leafBuilder: SendableInstantiator<ChainLeaf>
		            public let __safeDI_chainToken: SendableLazilyInstantiated<ChainToken>

		            init(chainToken: SendableLazilyInstantiated<ChainToken>, leafBuilder: SendableInstantiator<ChainLeaf>) {
		                __safeDI_chainToken = chainToken
		                self.leafBuilder = leafBuilder
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
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping @Sendable () -> ChainToken, __safeDI_holeServiceBuilder: SafeDIScope_HoleService.__safeDI_Builder<any HoleService>) {
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        @Sendable nonisolated func __safeDI_leafBuilder() -> ChainLeaf {
		            ChainLeaf(chainToken: chainToken.instance)
		        }
		        let leafBuilder = SendableInstantiator<ChainLeaf>(__safeDI_leafBuilder)
		        let holeService: any HoleService = __safeDI_holeServiceBuilder.holeService(SafeDIScope_HoleService.holeService_Values(chainToken: chainToken, leafBuilder: leafBuilder))
		        self.init(leafBuilder: leafBuilder, holeService: holeService)
		    }
		}

		extension SeamB {
		    public enum __safeDI_SeamB_DC2838BAE7387202 {}
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

		extension Mid {
		    nonisolated public enum SafeDIScope_ThingService {
		        nonisolated public struct outer_holeServiceBuilder_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let __safeDI_chainToken: SendableLazilyInstantiated<ChainToken>

		            init(chainToken: SendableLazilyInstantiated<ChainToken>) {
		                __safeDI_chainToken = chainToken
		            }
		        }

		        nonisolated public enum HoleImpl_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let workerBuilder: (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(workerBuilder: @escaping (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.workerBuilder = workerBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.workerBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        nonisolated public enum Worker_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let thing: (__safeDI_Values) -> __safeDI_Built

		                public init(thing: @escaping (__safeDI_Values) -> __safeDI_Built) {
		                    self.thing = thing
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.thing = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let outer_holeServiceBuilder: (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(outer_holeServiceBuilder: @escaping (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.outer_holeServiceBuilder = outer_holeServiceBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.outer_holeServiceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		            }
		        }
		    }

		    // SafeDI counts `ThingService` as `public`: no module it reads declares it narrower. If `ThingService` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping @Sendable () -> ChainToken, __safeDI_thingServiceBuilder: SafeDIScope_ThingService.__safeDI_Builder<any ThingService>) {
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        let __safeDI_thingServiceBuilder_outer_holeServiceBuilder = __safeDI_thingServiceBuilder.outer_holeServiceBuilder(SafeDIScope_ThingService.outer_holeServiceBuilder_Values(chainToken: chainToken))
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_964A004ABC6F5712.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_holeServiceBuilder_SeamB_SeamB_holeService(_ scope: SeamB.SafeDIScope_HoleService.holeService_Values, __safeDI_outer_holeServiceBuilder: SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>) -> any HoleService {
		                func __safeDI_holeService() -> HoleImpl {
		                    let __safeDI_thingServiceBuilder_workerBuilder = __safeDI_outer_holeServiceBuilder.workerBuilder(SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Values())
		                    func __safeDI_workerBuilder() -> Worker {
		                        let thing: any ThingService = __safeDI_thingServiceBuilder_workerBuilder.thing(SafeDIScope_ThingService.Worker_Scope.__safeDI_Values())
		                        return Worker(thing: thing)
		                    }
		                    let workerBuilder = Instantiator<Worker>(__safeDI_workerBuilder)
		                    return HoleImpl(workerBuilder: workerBuilder)
		                }
		                let holeService: any HoleService = __safeDI_holeService()
		                return holeService
		            }
		            func __safeDI_holeServiceBuilder_Seam_Seam_holeService(_ scope: Seam.SafeDIScope_HoleService.holeService_Values, __safeDI_outer_holeServiceBuilder: SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>) -> any HoleService {
		                func __safeDI_holeService() -> HoleImpl {
		                    let __safeDI_thingServiceBuilder_workerBuilder = __safeDI_outer_holeServiceBuilder.workerBuilder(SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Values())
		                    func __safeDI_workerBuilder() -> Worker {
		                        let thing: any ThingService = __safeDI_thingServiceBuilder_workerBuilder.thing(SafeDIScope_ThingService.Worker_Scope.__safeDI_Values())
		                        return Worker(thing: thing)
		                    }
		                    let workerBuilder = Instantiator<Worker>(__safeDI_workerBuilder)
		                    return HoleImpl(workerBuilder: workerBuilder)
		                }
		                let holeService: any HoleService = __safeDI_holeService()
		                return holeService
		            }
		            func __safeDI_holeServiceBuilder_Outer(up: Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(seamB: { values in __safeDI_holeServiceBuilder_SeamB(up: up.seamB(values)) }, seam: { values in __safeDI_holeServiceBuilder_Seam(up: up.seam(values)) })
		            }
		            func __safeDI_holeServiceBuilder_SeamB(up: SeamB.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> SeamB.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(holeService: { scope in __safeDI_holeServiceBuilder_SeamB_SeamB_holeService(scope, __safeDI_outer_holeServiceBuilder: up.holeService(scope)) })
		            }
		            func __safeDI_holeServiceBuilder_Seam(up: Seam.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(holeService: { scope in __safeDI_holeServiceBuilder_Seam_Seam_holeService(scope, __safeDI_outer_holeServiceBuilder: up.holeService(scope)) })
		            }
		            return Outer(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder_Outer(up: __safeDI_thingServiceBuilder_outer_holeServiceBuilder))
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(outer: outer)
		    }
		}

		extension Mid {
		    public enum __safeDI_Mid_4F0B05A7DE9D5C26 {}
		}
		"""])
		#expect(output.modules["Top"]?.generatedFiles == ["Top.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Other)
		import Other
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension TopRoot {
		    public convenience init() {
		        @Sendable func __safeDI_chainToken() -> ChainToken {
		            ChainToken()
		        }
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        func __safeDI_mid() -> Mid {
		            _ = Mid.__safeDI_Mid_4F0B05A7DE9D5C26.self // If this line does not compile, compile the code SafeDI generates for module Other into Other: under Bazel, add Other’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_thingServiceBuilder_Mid() -> Mid.SafeDIScope_ThingService.__safeDI_Builder<any ThingService> {
		                .init(outer_holeServiceBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Outer() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: LazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService> {
		                .init(workerBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: chainToken) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: LazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<any ThingService> {
		                .init(thing: { _ in
		                    let thing: any ThingService = ThingImpl(chainToken: chainToken.instance)
		                    return thing
		                })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Outer() -> Outer.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(seamB: { _ in __safeDI_thingServiceBuilder_Mid_SeamB() }, seam: { _ in __safeDI_thingServiceBuilder_Mid_Seam() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_SeamB() -> SeamB.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(holeService: { values in __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: LazilyInstantiated<ChainToken>({ [handed = values.__safeDI_chainToken] in handed.instance })) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Seam() -> Seam.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(holeService: { values in __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: values.__safeDI_chainToken) })
		            }
		            return Mid(__safeDI_chainToken: chainToken.instance, __safeDI_thingServiceBuilder: __safeDI_thingServiceBuilder_Mid())
		        }
		        let mid: Mid = __safeDI_mid()
		        self.init(chainToken: chainToken, mid: mid)
		    }
		}
		"""])
		try await expectCreationOrderEqualsOneModuleBuild(output, modules: modules)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillTakesMemoOnEveryRoute_whenCallingSeamBuildsPlacesTypeLazilyOnItsOwnRouteAndCallerHoldsValue() async throws {
		// As `whenCallingSeamBuildsPlacesTypeLazilyOnItsOwnRouteToo`, with `TopRoot` holding `chainToken` by value: the root
		// dispatcher makes a memo of the value.
		let modules = Self.chainTokenModules(topChainToken: "@Instantiated let chainToken: ChainToken", midWorkerBuilder: true)
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

		extension Outer {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let seam: (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>

		            public init(seam: @escaping (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>) {
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
		            _ = Seam.__safeDI_Seam_2AD7242F90FE57C2.self
		            return Seam(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder.seam(SafeDIScope_HoleService.__safeDI_Values()))
		        }
		        let seam: Seam = __safeDI_seam()
		        self.init(seam: seam)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_2A8D23C10A89B5A9 {}
		}

		extension Seam {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct holeService_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let leafBuilder: Instantiator<ChainLeaf>
		            public let __safeDI_chainToken: LazilyInstantiated<ChainToken>

		            init(chainToken: LazilyInstantiated<ChainToken>, leafBuilder: Instantiator<ChainLeaf>) {
		                __safeDI_chainToken = chainToken
		                self.leafBuilder = leafBuilder
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
		        func __safeDI_leafBuilder() -> ChainLeaf {
		            ChainLeaf(chainToken: chainToken.instance)
		        }
		        let leafBuilder = Instantiator<ChainLeaf>(__safeDI_leafBuilder)
		        let holeService: any HoleService = __safeDI_holeServiceBuilder.holeService(SafeDIScope_HoleService.holeService_Values(chainToken: chainToken, leafBuilder: leafBuilder))
		        self.init(leafBuilder: leafBuilder, holeService: holeService)
		    }
		}

		extension Seam {
		    public enum __safeDI_Seam_2AD7242F90FE57C2 {}
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

		extension Mid {
		    nonisolated public enum SafeDIScope_ThingService {
		        nonisolated public struct outer_holeServiceBuilder_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let __safeDI_chainToken: LazilyInstantiated<ChainToken>

		            init(chainToken: LazilyInstantiated<ChainToken>) {
		                __safeDI_chainToken = chainToken
		            }
		        }

		        nonisolated public struct midWorkerBuilder_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let outer: Outer
		            public let __safeDI_chainToken: LazilyInstantiated<ChainToken>

		            init(chainToken: LazilyInstantiated<ChainToken>, outer: Outer) {
		                __safeDI_chainToken = chainToken
		                self.outer = outer
		            }
		        }

		        nonisolated public enum HoleImpl_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let workerBuilder: (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(workerBuilder: @escaping (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.workerBuilder = workerBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.workerBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        nonisolated public enum Worker_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let thing: (__safeDI_Values) -> __safeDI_Built

		                public init(thing: @escaping (__safeDI_Values) -> __safeDI_Built) {
		                    self.thing = thing
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.thing = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public final class __safeDI_Builder<__safeDI_Built> {
		            public let outer_holeServiceBuilder: (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>
		            public let midWorkerBuilder: (midWorkerBuilder_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(outer_holeServiceBuilder: @escaping (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>, midWorkerBuilder: @escaping (midWorkerBuilder_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.outer_holeServiceBuilder = outer_holeServiceBuilder
		                self.midWorkerBuilder = midWorkerBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.outer_holeServiceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		                self.midWorkerBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    // SafeDI counts `ThingService` as `public`: no module it reads declares it narrower. If `ThingService` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping () -> ChainToken, __safeDI_thingServiceBuilder: SafeDIScope_ThingService.__safeDI_Builder<any ThingService>) {
		        let chainToken = LazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        let __safeDI_thingServiceBuilder_outer_holeServiceBuilder = __safeDI_thingServiceBuilder.outer_holeServiceBuilder(SafeDIScope_ThingService.outer_holeServiceBuilder_Values(chainToken: chainToken))
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_2A8D23C10A89B5A9.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_holeServiceBuilder_Seam_holeService(_ scope: Seam.SafeDIScope_HoleService.holeService_Values, __safeDI_outer_holeServiceBuilder: SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>) -> any HoleService {
		                func __safeDI_holeService() -> HoleImpl {
		                    let __safeDI_thingServiceBuilder_workerBuilder = __safeDI_outer_holeServiceBuilder.workerBuilder(SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Values())
		                    func __safeDI_workerBuilder() -> Worker {
		                        let thing: any ThingService = __safeDI_thingServiceBuilder_workerBuilder.thing(SafeDIScope_ThingService.Worker_Scope.__safeDI_Values())
		                        return Worker(thing: thing)
		                    }
		                    let workerBuilder = Instantiator<Worker>(__safeDI_workerBuilder)
		                    return HoleImpl(workerBuilder: workerBuilder)
		                }
		                let holeService: any HoleService = __safeDI_holeService()
		                return holeService
		            }
		            func __safeDI_holeServiceBuilder_Outer(up: Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(seam: { values in __safeDI_holeServiceBuilder_Seam(up: up.seam(values)) })
		            }
		            func __safeDI_holeServiceBuilder_Seam(up: Seam.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(holeService: { scope in __safeDI_holeServiceBuilder_Seam_holeService(scope, __safeDI_outer_holeServiceBuilder: up.holeService(scope)) })
		            }
		            return Outer(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder_Outer(up: __safeDI_thingServiceBuilder_outer_holeServiceBuilder))
		        }
		        let outer: Outer = __safeDI_outer()
		        let __safeDI_thingServiceBuilder_midWorkerBuilder = __safeDI_thingServiceBuilder.midWorkerBuilder(SafeDIScope_ThingService.midWorkerBuilder_Values(chainToken: chainToken, outer: outer))
		        func __safeDI_midWorkerBuilder() -> Worker {
		            let thing: any ThingService = __safeDI_thingServiceBuilder_midWorkerBuilder.thing(SafeDIScope_ThingService.Worker_Scope.__safeDI_Values())
		            return Worker(thing: thing)
		        }
		        let midWorkerBuilder = Instantiator<Worker>(__safeDI_midWorkerBuilder)
		        self.init(outer: outer, midWorkerBuilder: midWorkerBuilder)
		    }
		}

		extension Mid {
		    public enum __safeDI_Mid_FE17154EF8DB3070 {}
		}
		"""])
		#expect(output.modules["Top"]?.generatedFiles == ["Top.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Other)
		import Other
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension TopRoot {
		    public convenience init() {
		        let chainToken = ChainToken()
		        func __safeDI_mid() -> Mid {
		            _ = Mid.__safeDI_Mid_FE17154EF8DB3070.self // If this line does not compile, compile the code SafeDI generates for module Other into Other: under Bazel, add Other’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_thingServiceBuilder_Mid() -> Mid.SafeDIScope_ThingService.__safeDI_Builder<any ThingService> {
		                .init(outer_holeServiceBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Outer() }, midWorkerBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: LazilyInstantiated<ChainToken>({ chainToken })) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: LazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService> {
		                .init(workerBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: chainToken) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: LazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<any ThingService> {
		                .init(thing: { _ in
		                    let thing: any ThingService = ThingImpl(chainToken: chainToken.instance)
		                    return thing
		                })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Outer() -> Outer.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(seam: { _ in __safeDI_thingServiceBuilder_Mid_Seam() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Seam() -> Seam.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(holeService: { values in __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: values.__safeDI_chainToken) })
		            }
		            return Mid(__safeDI_chainToken: chainToken, __safeDI_thingServiceBuilder: __safeDI_thingServiceBuilder_Mid())
		        }
		        let mid: Mid = __safeDI_mid()
		        self.init(chainToken: chainToken, mid: mid)
		    }
		}
		"""])
		try await expectCreationOrderEqualsOneModuleBuild(output, modules: modules, midBuilders: ["midWorkerBuilder"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillTakesMemoOnEveryRoute_whenCallingSeamBuildsPlacesTypeLazilyOnItsOwnRouteAndFillReadsValueOnlyIfAvailable() async throws {
		// As `whenCallingSeamBuildsPlacesTypeLazilyOnItsOwnRouteToo`, with `ThingImpl` receiving `chainToken` only if available:
		// the fill takes the optional form's memo, which `Seam`'s level makes of `Seam`'s memo and the root dispatcher of the
		// caller's declaration.
		let modules = Self.chainTokenModules(
			thingImpl: """
			@Instantiable(fulfillingAdditionalTypes: [ThingService.self])
			public final class ThingImpl: Instantiable, ThingService {
				public init(chainToken: ChainToken?) { self.chainToken = chainToken; log.append("ThingImpl") }
				@Received(onlyIfAvailable: true) let chainToken: ChainToken?
			}
			""",
			midWorkerBuilder: true,
		)
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

		extension Outer {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let seam: (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>

		            public init(seam: @escaping (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>) {
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
		            _ = Seam.__safeDI_Seam_2AD7242F90FE57C2.self
		            return Seam(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder.seam(SafeDIScope_HoleService.__safeDI_Values()))
		        }
		        let seam: Seam = __safeDI_seam()
		        self.init(seam: seam)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_2A8D23C10A89B5A9 {}
		}

		extension Seam {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct holeService_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let leafBuilder: Instantiator<ChainLeaf>
		            public let __safeDI_chainToken: LazilyInstantiated<ChainToken>

		            init(chainToken: LazilyInstantiated<ChainToken>, leafBuilder: Instantiator<ChainLeaf>) {
		                __safeDI_chainToken = chainToken
		                self.leafBuilder = leafBuilder
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
		        func __safeDI_leafBuilder() -> ChainLeaf {
		            ChainLeaf(chainToken: chainToken.instance)
		        }
		        let leafBuilder = Instantiator<ChainLeaf>(__safeDI_leafBuilder)
		        let holeService: any HoleService = __safeDI_holeServiceBuilder.holeService(SafeDIScope_HoleService.holeService_Values(chainToken: chainToken, leafBuilder: leafBuilder))
		        self.init(leafBuilder: leafBuilder, holeService: holeService)
		    }
		}

		extension Seam {
		    public enum __safeDI_Seam_2AD7242F90FE57C2 {}
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

		extension Mid {
		    nonisolated public enum SafeDIScope_ThingService {
		        nonisolated public struct outer_holeServiceBuilder_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let __safeDI_chainToken: LazilyInstantiated<ChainToken>

		            init(chainToken: LazilyInstantiated<ChainToken>) {
		                __safeDI_chainToken = chainToken
		            }
		        }

		        nonisolated public struct midWorkerBuilder_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let outer: Outer
		            public let __safeDI_chainToken: LazilyInstantiated<ChainToken>

		            init(chainToken: LazilyInstantiated<ChainToken>, outer: Outer) {
		                __safeDI_chainToken = chainToken
		                self.outer = outer
		            }
		        }

		        nonisolated public enum HoleImpl_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let workerBuilder: (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(workerBuilder: @escaping (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.workerBuilder = workerBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.workerBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        nonisolated public enum Worker_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let thing: (__safeDI_Values) -> __safeDI_Built

		                public init(thing: @escaping (__safeDI_Values) -> __safeDI_Built) {
		                    self.thing = thing
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.thing = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public final class __safeDI_Builder<__safeDI_Built> {
		            public let outer_holeServiceBuilder: (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>
		            public let midWorkerBuilder: (midWorkerBuilder_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(outer_holeServiceBuilder: @escaping (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>, midWorkerBuilder: @escaping (midWorkerBuilder_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.outer_holeServiceBuilder = outer_holeServiceBuilder
		                self.midWorkerBuilder = midWorkerBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.outer_holeServiceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		                self.midWorkerBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    // SafeDI counts `ThingService` as `public`: no module it reads declares it narrower. If `ThingService` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping () -> ChainToken, __safeDI_thingServiceBuilder: SafeDIScope_ThingService.__safeDI_Builder<any ThingService>) {
		        let chainToken = LazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        let __safeDI_thingServiceBuilder_outer_holeServiceBuilder = __safeDI_thingServiceBuilder.outer_holeServiceBuilder(SafeDIScope_ThingService.outer_holeServiceBuilder_Values(chainToken: chainToken))
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_2A8D23C10A89B5A9.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_holeServiceBuilder_Seam_holeService(_ scope: Seam.SafeDIScope_HoleService.holeService_Values, __safeDI_outer_holeServiceBuilder: SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>) -> any HoleService {
		                func __safeDI_holeService() -> HoleImpl {
		                    let __safeDI_thingServiceBuilder_workerBuilder = __safeDI_outer_holeServiceBuilder.workerBuilder(SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Values())
		                    func __safeDI_workerBuilder() -> Worker {
		                        let thing: any ThingService = __safeDI_thingServiceBuilder_workerBuilder.thing(SafeDIScope_ThingService.Worker_Scope.__safeDI_Values())
		                        return Worker(thing: thing)
		                    }
		                    let workerBuilder = Instantiator<Worker>(__safeDI_workerBuilder)
		                    return HoleImpl(workerBuilder: workerBuilder)
		                }
		                let holeService: any HoleService = __safeDI_holeService()
		                return holeService
		            }
		            func __safeDI_holeServiceBuilder_Outer(up: Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(seam: { values in __safeDI_holeServiceBuilder_Seam(up: up.seam(values)) })
		            }
		            func __safeDI_holeServiceBuilder_Seam(up: Seam.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(holeService: { scope in __safeDI_holeServiceBuilder_Seam_holeService(scope, __safeDI_outer_holeServiceBuilder: up.holeService(scope)) })
		            }
		            return Outer(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder_Outer(up: __safeDI_thingServiceBuilder_outer_holeServiceBuilder))
		        }
		        let outer: Outer = __safeDI_outer()
		        let __safeDI_thingServiceBuilder_midWorkerBuilder = __safeDI_thingServiceBuilder.midWorkerBuilder(SafeDIScope_ThingService.midWorkerBuilder_Values(chainToken: chainToken, outer: outer))
		        func __safeDI_midWorkerBuilder() -> Worker {
		            let thing: any ThingService = __safeDI_thingServiceBuilder_midWorkerBuilder.thing(SafeDIScope_ThingService.Worker_Scope.__safeDI_Values())
		            return Worker(thing: thing)
		        }
		        let midWorkerBuilder = Instantiator<Worker>(__safeDI_midWorkerBuilder)
		        self.init(outer: outer, midWorkerBuilder: midWorkerBuilder)
		    }
		}

		extension Mid {
		    public enum __safeDI_Mid_FE17154EF8DB3070 {}
		}
		"""])
		#expect(output.modules["Top"]?.generatedFiles == ["Top.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Other)
		import Other
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension TopRoot {
		    public convenience init() {
		        func __safeDI_chainToken() -> ChainToken {
		            ChainToken()
		        }
		        let chainToken = LazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        func __safeDI_mid() -> Mid {
		            _ = Mid.__safeDI_Mid_FE17154EF8DB3070.self // If this line does not compile, compile the code SafeDI generates for module Other into Other: under Bazel, add Other’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_thingServiceBuilder_Mid() -> Mid.SafeDIScope_ThingService.__safeDI_Builder<any ThingService> {
		                .init(outer_holeServiceBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Outer() }, midWorkerBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: LazilyInstantiated<ChainToken?>({ chainToken.instance })) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: LazilyInstantiated<ChainToken?>) -> Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService> {
		                .init(workerBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: chainToken) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: LazilyInstantiated<ChainToken?>) -> Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<any ThingService> {
		                .init(thing: { _ in
		                    let thing: any ThingService = ThingImpl(chainToken: chainToken.instance)
		                    return thing
		                })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Outer() -> Outer.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(seam: { _ in __safeDI_thingServiceBuilder_Mid_Seam() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Seam() -> Seam.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(holeService: { values in __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: LazilyInstantiated<ChainToken?>({ [handed = values.__safeDI_chainToken] in handed.instance })) })
		            }
		            return Mid(__safeDI_chainToken: chainToken.instance, __safeDI_thingServiceBuilder: __safeDI_thingServiceBuilder_Mid())
		        }
		        let mid: Mid = __safeDI_mid()
		        self.init(chainToken: chainToken, mid: mid)
		    }
		}
		"""])
		try await expectCreationOrderEqualsOneModuleBuild(output, modules: modules, midBuilders: ["midWorkerBuilder"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillTakesMemoOnEveryRoute_whenTwoPassingUpSeamsDeferValueInFormsThatDifferInOptionality() async throws {
		// As `whenTwoPassingUpSeamsDeferValueUnlike`, with `SeamB`'s tree, and `ThingImpl`, receiving `chainToken` only if
		// available, so `SeamB` defers `chainToken: ChainToken?` and `Seam` `chainToken: ChainToken`: the fill takes a memo of the
		// optional form, which each level makes of its own.
		let modules = Self.chainTokenModules(
			thingImpl: """
			@Instantiable(fulfillingAdditionalTypes: [ThingService.self])
			public final class ThingImpl: Instantiable, ThingService {
				public init(chainToken: ChainToken?) { self.chainToken = chainToken; log.append("ThingImpl") }
				@Received(onlyIfAvailable: true) let chainToken: ChainToken?
			}
			""",
			topChainToken: "@Instantiated let chainToken: SendableLazilyInstantiated<ChainToken>",
			outerHoldsSeamB: true,
			seamBReadsValueOnlyIfAvailable: true,
		)
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

		extension Outer {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public final class __safeDI_Builder<__safeDI_Built> {
		            public let seamB: (__safeDI_Values) -> SeamB.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>
		            public let seam: (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>

		            public init(seamB: @escaping (__safeDI_Values) -> SeamB.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>, seam: @escaping (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>) {
		                self.seamB = seamB
		                self.seam = seam
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.seamB = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                self.seam = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    // SafeDI counts `HoleService` as `public`: no module it reads declares it narrower. If `HoleService` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping @Sendable () -> ChainToken, __safeDI_holeServiceBuilder: SafeDIScope_HoleService.__safeDI_Builder<any HoleService>) {
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        func __safeDI_seamB() -> SeamB {
		            _ = SeamB.__safeDI_SeamB_62D6F929FACD1732.self
		            return SeamB(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder.seamB(SafeDIScope_HoleService.__safeDI_Values()))
		        }
		        let seamB: SeamB = __safeDI_seamB()
		        func __safeDI_seam() -> Seam {
		            _ = Seam.__safeDI_Seam_2AD7242F90FE57C2.self
		            return Seam(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder.seam(SafeDIScope_HoleService.__safeDI_Values()))
		        }
		        let seam: Seam = __safeDI_seam()
		        self.init(seam: seam, seamB: seamB)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_5071F6181F92B263 {}
		}

		extension Seam {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct holeService_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let leafBuilder: Instantiator<ChainLeaf>
		            public let __safeDI_chainToken: LazilyInstantiated<ChainToken>

		            init(chainToken: LazilyInstantiated<ChainToken>, leafBuilder: Instantiator<ChainLeaf>) {
		                __safeDI_chainToken = chainToken
		                self.leafBuilder = leafBuilder
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
		        func __safeDI_leafBuilder() -> ChainLeaf {
		            ChainLeaf(chainToken: chainToken.instance)
		        }
		        let leafBuilder = Instantiator<ChainLeaf>(__safeDI_leafBuilder)
		        let holeService: any HoleService = __safeDI_holeServiceBuilder.holeService(SafeDIScope_HoleService.holeService_Values(chainToken: chainToken, leafBuilder: leafBuilder))
		        self.init(leafBuilder: leafBuilder, holeService: holeService)
		    }
		}

		extension Seam {
		    public enum __safeDI_Seam_2AD7242F90FE57C2 {}
		}

		extension SeamB {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct holeService_Values {
		            public var chainToken: ChainToken? { __safeDI_chainToken.instance }
		            public let leafBuilder: SendableInstantiator<OptionalChainLeaf>
		            public let __safeDI_chainToken: SendableLazilyInstantiated<ChainToken?>

		            init(chainToken: SendableLazilyInstantiated<ChainToken?>, leafBuilder: SendableInstantiator<OptionalChainLeaf>) {
		                __safeDI_chainToken = chainToken
		                self.leafBuilder = leafBuilder
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
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping @Sendable () -> ChainToken?, __safeDI_holeServiceBuilder: SafeDIScope_HoleService.__safeDI_Builder<any HoleService>) {
		        let chainToken = SendableLazilyInstantiated<ChainToken?>(__safeDI_chainToken)
		        @Sendable nonisolated func __safeDI_leafBuilder() -> OptionalChainLeaf {
		            OptionalChainLeaf(chainToken: chainToken.instance)
		        }
		        let leafBuilder = SendableInstantiator<OptionalChainLeaf>(__safeDI_leafBuilder)
		        let holeService: any HoleService = __safeDI_holeServiceBuilder.holeService(SafeDIScope_HoleService.holeService_Values(chainToken: chainToken, leafBuilder: leafBuilder))
		        self.init(leafBuilder: leafBuilder, holeService: holeService)
		    }
		}

		extension SeamB {
		    public enum __safeDI_SeamB_62D6F929FACD1732 {}
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

		extension Mid {
		    nonisolated public enum SafeDIScope_ThingService {
		        nonisolated public struct outer_holeServiceBuilder_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let __safeDI_chainToken: SendableLazilyInstantiated<ChainToken>

		            init(chainToken: SendableLazilyInstantiated<ChainToken>) {
		                __safeDI_chainToken = chainToken
		            }
		        }

		        nonisolated public enum HoleImpl_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let workerBuilder: (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(workerBuilder: @escaping (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.workerBuilder = workerBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.workerBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        nonisolated public enum Worker_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let thing: (__safeDI_Values) -> __safeDI_Built

		                public init(thing: @escaping (__safeDI_Values) -> __safeDI_Built) {
		                    self.thing = thing
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.thing = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let outer_holeServiceBuilder: (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(outer_holeServiceBuilder: @escaping (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.outer_holeServiceBuilder = outer_holeServiceBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.outer_holeServiceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		            }
		        }
		    }

		    // SafeDI counts `ThingService` as `public`: no module it reads declares it narrower. If `ThingService` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping @Sendable () -> ChainToken, __safeDI_thingServiceBuilder: SafeDIScope_ThingService.__safeDI_Builder<any ThingService>) {
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        let __safeDI_thingServiceBuilder_outer_holeServiceBuilder = __safeDI_thingServiceBuilder.outer_holeServiceBuilder(SafeDIScope_ThingService.outer_holeServiceBuilder_Values(chainToken: chainToken))
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_5071F6181F92B263.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_holeServiceBuilder_SeamB_SeamB_holeService(_ scope: SeamB.SafeDIScope_HoleService.holeService_Values, __safeDI_outer_holeServiceBuilder: SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>) -> any HoleService {
		                func __safeDI_holeService() -> HoleImpl {
		                    let __safeDI_thingServiceBuilder_workerBuilder = __safeDI_outer_holeServiceBuilder.workerBuilder(SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Values())
		                    func __safeDI_workerBuilder() -> Worker {
		                        let thing: any ThingService = __safeDI_thingServiceBuilder_workerBuilder.thing(SafeDIScope_ThingService.Worker_Scope.__safeDI_Values())
		                        return Worker(thing: thing)
		                    }
		                    let workerBuilder = Instantiator<Worker>(__safeDI_workerBuilder)
		                    return HoleImpl(workerBuilder: workerBuilder)
		                }
		                let holeService: any HoleService = __safeDI_holeService()
		                return holeService
		            }
		            func __safeDI_holeServiceBuilder_Seam_Seam_holeService(_ scope: Seam.SafeDIScope_HoleService.holeService_Values, __safeDI_outer_holeServiceBuilder: SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>) -> any HoleService {
		                func __safeDI_holeService() -> HoleImpl {
		                    let __safeDI_thingServiceBuilder_workerBuilder = __safeDI_outer_holeServiceBuilder.workerBuilder(SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Values())
		                    func __safeDI_workerBuilder() -> Worker {
		                        let thing: any ThingService = __safeDI_thingServiceBuilder_workerBuilder.thing(SafeDIScope_ThingService.Worker_Scope.__safeDI_Values())
		                        return Worker(thing: thing)
		                    }
		                    let workerBuilder = Instantiator<Worker>(__safeDI_workerBuilder)
		                    return HoleImpl(workerBuilder: workerBuilder)
		                }
		                let holeService: any HoleService = __safeDI_holeService()
		                return holeService
		            }
		            func __safeDI_holeServiceBuilder_Outer(up: Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(seamB: { values in __safeDI_holeServiceBuilder_SeamB(up: up.seamB(values)) }, seam: { values in __safeDI_holeServiceBuilder_Seam(up: up.seam(values)) })
		            }
		            func __safeDI_holeServiceBuilder_SeamB(up: SeamB.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> SeamB.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(holeService: { scope in __safeDI_holeServiceBuilder_SeamB_SeamB_holeService(scope, __safeDI_outer_holeServiceBuilder: up.holeService(scope)) })
		            }
		            func __safeDI_holeServiceBuilder_Seam(up: Seam.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(holeService: { scope in __safeDI_holeServiceBuilder_Seam_Seam_holeService(scope, __safeDI_outer_holeServiceBuilder: up.holeService(scope)) })
		            }
		            return Outer(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder_Outer(up: __safeDI_thingServiceBuilder_outer_holeServiceBuilder))
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(outer: outer)
		    }
		}

		extension Mid {
		    public enum __safeDI_Mid_4FFC7B7ECE96D9DF {}
		}
		"""])
		#expect(output.modules["Top"]?.generatedFiles == ["Top.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Other)
		import Other
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension TopRoot {
		    public convenience init() {
		        @Sendable func __safeDI_chainToken() -> ChainToken {
		            ChainToken()
		        }
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        func __safeDI_mid() -> Mid {
		            _ = Mid.__safeDI_Mid_4FFC7B7ECE96D9DF.self // If this line does not compile, compile the code SafeDI generates for module Other into Other: under Bazel, add Other’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_thingServiceBuilder_Mid() -> Mid.SafeDIScope_ThingService.__safeDI_Builder<any ThingService> {
		                .init(outer_holeServiceBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Outer() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: LazilyInstantiated<ChainToken?>) -> Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService> {
		                .init(workerBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: chainToken) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: LazilyInstantiated<ChainToken?>) -> Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<any ThingService> {
		                .init(thing: { _ in
		                    let thing: any ThingService = ThingImpl(chainToken: chainToken.instance)
		                    return thing
		                })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Outer() -> Outer.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(seamB: { _ in __safeDI_thingServiceBuilder_Mid_SeamB() }, seam: { _ in __safeDI_thingServiceBuilder_Mid_Seam() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_SeamB() -> SeamB.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(holeService: { values in __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: LazilyInstantiated<ChainToken?>({ [handed = values.__safeDI_chainToken] in handed.instance })) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Seam() -> Seam.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(holeService: { values in __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: LazilyInstantiated<ChainToken?>({ [handed = values.__safeDI_chainToken] in handed.instance })) })
		            }
		            return Mid(__safeDI_chainToken: chainToken.instance, __safeDI_thingServiceBuilder: __safeDI_thingServiceBuilder_Mid())
		        }
		        let mid: Mid = __safeDI_mid()
		        self.init(chainToken: chainToken, mid: mid)
		    }
		}
		"""])
		try await expectCreationOrderEqualsOneModuleBuild(output, modules: modules)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillTakesMemoOnEveryRoute_whenCallingSeamDeclaresValueAndBuildsPlacesTypeLazilyOnItsOwnRoute() async throws {
		// `Mid` declares `chainToken` by value and builds `Worker` in `midWorkerBuilder`: on `Mid`'s own route its level's field
		// holds the value, which the root dispatcher's member makes a memo of, and on the route through `Seam`'s level `Seam`'s
		// memo is handed.
		let modules = Self.chainTokenModules(midWorkerBuilder: true, midChainToken: "ChainToken")
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

		extension Outer {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let seam: (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>

		            public init(seam: @escaping (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>) {
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
		            _ = Seam.__safeDI_Seam_2AD7242F90FE57C2.self
		            return Seam(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder.seam(SafeDIScope_HoleService.__safeDI_Values()))
		        }
		        let seam: Seam = __safeDI_seam()
		        self.init(seam: seam)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_2A8D23C10A89B5A9 {}
		}

		extension Seam {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct holeService_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let leafBuilder: Instantiator<ChainLeaf>
		            public let __safeDI_chainToken: LazilyInstantiated<ChainToken>

		            init(chainToken: LazilyInstantiated<ChainToken>, leafBuilder: Instantiator<ChainLeaf>) {
		                __safeDI_chainToken = chainToken
		                self.leafBuilder = leafBuilder
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
		        func __safeDI_leafBuilder() -> ChainLeaf {
		            ChainLeaf(chainToken: chainToken.instance)
		        }
		        let leafBuilder = Instantiator<ChainLeaf>(__safeDI_leafBuilder)
		        let holeService: any HoleService = __safeDI_holeServiceBuilder.holeService(SafeDIScope_HoleService.holeService_Values(chainToken: chainToken, leafBuilder: leafBuilder))
		        self.init(leafBuilder: leafBuilder, holeService: holeService)
		    }
		}

		extension Seam {
		    public enum __safeDI_Seam_2AD7242F90FE57C2 {}
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

		extension Mid {
		    nonisolated public enum SafeDIScope_ThingService {
		        nonisolated public struct outer_holeServiceBuilder_Values {
		            public let chainToken: ChainToken
		        }

		        nonisolated public struct midWorkerBuilder_Values {
		            public let chainToken: ChainToken
		            public let outer: Outer
		        }

		        nonisolated public enum HoleImpl_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let workerBuilder: (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(workerBuilder: @escaping (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.workerBuilder = workerBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.workerBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        nonisolated public enum Worker_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let thing: (__safeDI_Values) -> __safeDI_Built

		                public init(thing: @escaping (__safeDI_Values) -> __safeDI_Built) {
		                    self.thing = thing
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.thing = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public final class __safeDI_Builder<__safeDI_Built> {
		            public let outer_holeServiceBuilder: (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>
		            public let midWorkerBuilder: (midWorkerBuilder_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(outer_holeServiceBuilder: @escaping (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>, midWorkerBuilder: @escaping (midWorkerBuilder_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.outer_holeServiceBuilder = outer_holeServiceBuilder
		                self.midWorkerBuilder = midWorkerBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.outer_holeServiceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		                self.midWorkerBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    // SafeDI counts `ThingService` as `public`: no module it reads declares it narrower. If `ThingService` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_thingServiceBuilder: SafeDIScope_ThingService.__safeDI_Builder<any ThingService>) {
		        let chainToken = ChainToken()
		        let __safeDI_thingServiceBuilder_outer_holeServiceBuilder = __safeDI_thingServiceBuilder.outer_holeServiceBuilder(SafeDIScope_ThingService.outer_holeServiceBuilder_Values(chainToken: chainToken))
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_2A8D23C10A89B5A9.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_holeServiceBuilder_Seam_holeService(_ scope: Seam.SafeDIScope_HoleService.holeService_Values, __safeDI_outer_holeServiceBuilder: SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>) -> any HoleService {
		                func __safeDI_holeService() -> HoleImpl {
		                    let __safeDI_thingServiceBuilder_workerBuilder = __safeDI_outer_holeServiceBuilder.workerBuilder(SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Values())
		                    func __safeDI_workerBuilder() -> Worker {
		                        let thing: any ThingService = __safeDI_thingServiceBuilder_workerBuilder.thing(SafeDIScope_ThingService.Worker_Scope.__safeDI_Values())
		                        return Worker(thing: thing)
		                    }
		                    let workerBuilder = Instantiator<Worker>(__safeDI_workerBuilder)
		                    return HoleImpl(workerBuilder: workerBuilder)
		                }
		                let holeService: any HoleService = __safeDI_holeService()
		                return holeService
		            }
		            func __safeDI_holeServiceBuilder_Outer(up: Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(seam: { values in __safeDI_holeServiceBuilder_Seam(up: up.seam(values)) })
		            }
		            func __safeDI_holeServiceBuilder_Seam(up: Seam.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(holeService: { scope in __safeDI_holeServiceBuilder_Seam_holeService(scope, __safeDI_outer_holeServiceBuilder: up.holeService(scope)) })
		            }
		            return Outer(__safeDI_chainToken: chainToken, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder_Outer(up: __safeDI_thingServiceBuilder_outer_holeServiceBuilder))
		        }
		        let outer: Outer = __safeDI_outer()
		        let __safeDI_thingServiceBuilder_midWorkerBuilder = __safeDI_thingServiceBuilder.midWorkerBuilder(SafeDIScope_ThingService.midWorkerBuilder_Values(chainToken: chainToken, outer: outer))
		        func __safeDI_midWorkerBuilder() -> Worker {
		            let thing: any ThingService = __safeDI_thingServiceBuilder_midWorkerBuilder.thing(SafeDIScope_ThingService.Worker_Scope.__safeDI_Values())
		            return Worker(thing: thing)
		        }
		        let midWorkerBuilder = Instantiator<Worker>(__safeDI_midWorkerBuilder)
		        self.init(chainToken: chainToken, outer: outer, midWorkerBuilder: midWorkerBuilder)
		    }
		}

		extension Mid {
		    public enum __safeDI_Mid_92078A18D5F32239 {}
		}
		"""])
		#expect(output.modules["Top"]?.generatedFiles == ["Top.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Other)
		import Other
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension TopRoot {
		    public convenience init() {
		        func __safeDI_mid() -> Mid {
		            _ = Mid.__safeDI_Mid_92078A18D5F32239.self // If this line does not compile, compile the code SafeDI generates for module Other into Other: under Bazel, add Other’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_thingServiceBuilder_Mid() -> Mid.SafeDIScope_ThingService.__safeDI_Builder<any ThingService> {
		                .init(outer_holeServiceBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Outer() }, midWorkerBuilder: { values in __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: LazilyInstantiated<ChainToken>({ [handed = values.chainToken] in handed })) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: LazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService> {
		                .init(workerBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: chainToken) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: LazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<any ThingService> {
		                .init(thing: { _ in
		                    let thing: any ThingService = ThingImpl(chainToken: chainToken.instance)
		                    return thing
		                })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Outer() -> Outer.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(seam: { _ in __safeDI_thingServiceBuilder_Mid_Seam() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Seam() -> Seam.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(holeService: { values in __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: values.__safeDI_chainToken) })
		            }
		            return Mid(__safeDI_thingServiceBuilder: __safeDI_thingServiceBuilder_Mid())
		        }
		        let mid: Mid = __safeDI_mid()
		        self.init(mid: mid)
		    }
		}
		"""])
		try await expectCreationOrderEqualsOneModuleBuild(output, modules: modules, midBuilders: ["midWorkerBuilder"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_levelFunctionHandsMemoOn_whenTypeAbovePassingUpSeamDeclaresValueLazily() async throws {
		// `Outer` declares `chainToken` lazily, so `thing` carries `Outer`'s `LazilyInstantiated` as a field of `Outer`'s level,
		// but the route through `Seam`'s level, nearer, hands `Seam`'s memo of `ChainToken`: the fill takes that memo, in that
		// form, and reads its instance where `ThingImpl` is built.
		let modules = Self.chainTokenModules(outerDeclaresChainToken: true)
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

		extension Outer {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let seam: (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>

		            public init(seam: @escaping (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>) {
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
		    public convenience init(__safeDI_holeServiceBuilder: SafeDIScope_HoleService.__safeDI_Builder<any HoleService>) {
		        func __safeDI_chainToken() -> ChainToken {
		            ChainToken()
		        }
		        let chainToken = LazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        func __safeDI_seam() -> Seam {
		            _ = Seam.__safeDI_Seam_2AD7242F90FE57C2.self
		            return Seam(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder.seam(SafeDIScope_HoleService.__safeDI_Values()))
		        }
		        let seam: Seam = __safeDI_seam()
		        self.init(chainToken: chainToken, seam: seam)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_6E0AB25F1FE9A45C {}
		}

		extension Seam {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct holeService_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let leafBuilder: Instantiator<ChainLeaf>
		            public let __safeDI_chainToken: LazilyInstantiated<ChainToken>

		            init(chainToken: LazilyInstantiated<ChainToken>, leafBuilder: Instantiator<ChainLeaf>) {
		                __safeDI_chainToken = chainToken
		                self.leafBuilder = leafBuilder
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
		        func __safeDI_leafBuilder() -> ChainLeaf {
		            ChainLeaf(chainToken: chainToken.instance)
		        }
		        let leafBuilder = Instantiator<ChainLeaf>(__safeDI_leafBuilder)
		        let holeService: any HoleService = __safeDI_holeServiceBuilder.holeService(SafeDIScope_HoleService.holeService_Values(chainToken: chainToken, leafBuilder: leafBuilder))
		        self.init(leafBuilder: leafBuilder, holeService: holeService)
		    }
		}

		extension Seam {
		    public enum __safeDI_Seam_2AD7242F90FE57C2 {}
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

		extension Mid {
		    nonisolated public enum SafeDIScope_ThingService {
		        nonisolated public struct __safeDI_Values: Sendable {}

		        nonisolated public enum HoleImpl_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let workerBuilder: (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(workerBuilder: @escaping (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.workerBuilder = workerBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.workerBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        nonisolated public enum Worker_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let thing: (__safeDI_Values) -> __safeDI_Built

		                public init(thing: @escaping (__safeDI_Values) -> __safeDI_Built) {
		                    self.thing = thing
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.thing = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let outer_holeServiceBuilder: (__safeDI_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(outer_holeServiceBuilder: @escaping (__safeDI_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.outer_holeServiceBuilder = outer_holeServiceBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.outer_holeServiceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		            }
		        }
		    }

		    // SafeDI counts `ThingService` as `public`: no module it reads declares it narrower. If `ThingService` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_thingServiceBuilder: SafeDIScope_ThingService.__safeDI_Builder<any ThingService>) {
		        let __safeDI_thingServiceBuilder_outer_holeServiceBuilder = __safeDI_thingServiceBuilder.outer_holeServiceBuilder(SafeDIScope_ThingService.__safeDI_Values())
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_6E0AB25F1FE9A45C.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_holeServiceBuilder_Seam_holeService(_ scope: Seam.SafeDIScope_HoleService.holeService_Values, __safeDI_outer_holeServiceBuilder: SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>) -> any HoleService {
		                func __safeDI_holeService() -> HoleImpl {
		                    let __safeDI_thingServiceBuilder_workerBuilder = __safeDI_outer_holeServiceBuilder.workerBuilder(SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Values())
		                    func __safeDI_workerBuilder() -> Worker {
		                        let thing: any ThingService = __safeDI_thingServiceBuilder_workerBuilder.thing(SafeDIScope_ThingService.Worker_Scope.__safeDI_Values())
		                        return Worker(thing: thing)
		                    }
		                    let workerBuilder = Instantiator<Worker>(__safeDI_workerBuilder)
		                    return HoleImpl(workerBuilder: workerBuilder)
		                }
		                let holeService: any HoleService = __safeDI_holeService()
		                return holeService
		            }
		            func __safeDI_holeServiceBuilder_Outer(up: Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(seam: { values in __safeDI_holeServiceBuilder_Seam(up: up.seam(values)) })
		            }
		            func __safeDI_holeServiceBuilder_Seam(up: Seam.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(holeService: { scope in __safeDI_holeServiceBuilder_Seam_holeService(scope, __safeDI_outer_holeServiceBuilder: up.holeService(scope)) })
		            }
		            return Outer(__safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder_Outer(up: __safeDI_thingServiceBuilder_outer_holeServiceBuilder))
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(outer: outer)
		    }
		}

		extension Mid {
		    public enum __safeDI_Mid_0095BD9FFE05D9DD {}
		}
		"""])
		#expect(output.modules["Top"]?.generatedFiles == ["Top.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Other)
		import Other
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension TopRoot {
		    public convenience init() {
		        func __safeDI_mid() -> Mid {
		            _ = Mid.__safeDI_Mid_0095BD9FFE05D9DD.self // If this line does not compile, compile the code SafeDI generates for module Other into Other: under Bazel, add Other’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_thingServiceBuilder_Mid() -> Mid.SafeDIScope_ThingService.__safeDI_Builder<any ThingService> {
		                .init(outer_holeServiceBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Outer() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: LazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService> {
		                .init(workerBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: chainToken) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: LazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<any ThingService> {
		                .init(thing: { _ in
		                    let thing: any ThingService = ThingImpl(chainToken: chainToken.instance)
		                    return thing
		                })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Outer() -> Outer.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(seam: { _ in __safeDI_thingServiceBuilder_Mid_Seam() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Seam() -> Seam.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(holeService: { values in __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: values.__safeDI_chainToken) })
		            }
		            return Mid(__safeDI_thingServiceBuilder: __safeDI_thingServiceBuilder_Mid())
		        }
		        let mid: Mid = __safeDI_mid()
		        self.init(mid: mid)
		    }
		}
		"""])
		try await expectCreationOrderEqualsOneModuleBuild(output, modules: modules)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillTakesNearerLevelsMemo_whenCallingSeamDeclaresValueLazilyItself() async throws {
		// `Mid`, the calling seam, declares `chainToken` lazily, and the route to `thing` through `Seam`'s level, nearer, hands
		// `Seam`'s memo of `ChainToken`: the fill takes that memo and reads its instance where `ThingImpl` is built.
		let modules = Self.chainTokenModules(midChainToken: "LazilyInstantiated<ChainToken>")
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

		extension Outer {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let seam: (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>

		            public init(seam: @escaping (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>) {
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
		            _ = Seam.__safeDI_Seam_2AD7242F90FE57C2.self
		            return Seam(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder.seam(SafeDIScope_HoleService.__safeDI_Values()))
		        }
		        let seam: Seam = __safeDI_seam()
		        self.init(seam: seam)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_2A8D23C10A89B5A9 {}
		}

		extension Seam {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct holeService_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let leafBuilder: Instantiator<ChainLeaf>
		            public let __safeDI_chainToken: LazilyInstantiated<ChainToken>

		            init(chainToken: LazilyInstantiated<ChainToken>, leafBuilder: Instantiator<ChainLeaf>) {
		                __safeDI_chainToken = chainToken
		                self.leafBuilder = leafBuilder
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
		        func __safeDI_leafBuilder() -> ChainLeaf {
		            ChainLeaf(chainToken: chainToken.instance)
		        }
		        let leafBuilder = Instantiator<ChainLeaf>(__safeDI_leafBuilder)
		        let holeService: any HoleService = __safeDI_holeServiceBuilder.holeService(SafeDIScope_HoleService.holeService_Values(chainToken: chainToken, leafBuilder: leafBuilder))
		        self.init(leafBuilder: leafBuilder, holeService: holeService)
		    }
		}

		extension Seam {
		    public enum __safeDI_Seam_2AD7242F90FE57C2 {}
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

		extension Mid {
		    nonisolated public enum SafeDIScope_ThingService {
		        nonisolated public struct outer_holeServiceBuilder_Values {
		            public let chainToken: LazilyInstantiated<ChainToken>
		        }

		        nonisolated public enum HoleImpl_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let workerBuilder: (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(workerBuilder: @escaping (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.workerBuilder = workerBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.workerBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        nonisolated public enum Worker_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let thing: (__safeDI_Values) -> __safeDI_Built

		                public init(thing: @escaping (__safeDI_Values) -> __safeDI_Built) {
		                    self.thing = thing
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.thing = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let outer_holeServiceBuilder: (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(outer_holeServiceBuilder: @escaping (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.outer_holeServiceBuilder = outer_holeServiceBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.outer_holeServiceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		            }
		        }
		    }

		    // SafeDI counts `ThingService` as `public`: no module it reads declares it narrower. If `ThingService` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_thingServiceBuilder: SafeDIScope_ThingService.__safeDI_Builder<any ThingService>) {
		        func __safeDI_chainToken() -> ChainToken {
		            ChainToken()
		        }
		        let chainToken = LazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        let __safeDI_thingServiceBuilder_outer_holeServiceBuilder = __safeDI_thingServiceBuilder.outer_holeServiceBuilder(SafeDIScope_ThingService.outer_holeServiceBuilder_Values(chainToken: chainToken))
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_2A8D23C10A89B5A9.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_holeServiceBuilder_Seam_holeService(_ scope: Seam.SafeDIScope_HoleService.holeService_Values, __safeDI_outer_holeServiceBuilder: SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>) -> any HoleService {
		                func __safeDI_holeService() -> HoleImpl {
		                    let __safeDI_thingServiceBuilder_workerBuilder = __safeDI_outer_holeServiceBuilder.workerBuilder(SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Values())
		                    func __safeDI_workerBuilder() -> Worker {
		                        let thing: any ThingService = __safeDI_thingServiceBuilder_workerBuilder.thing(SafeDIScope_ThingService.Worker_Scope.__safeDI_Values())
		                        return Worker(thing: thing)
		                    }
		                    let workerBuilder = Instantiator<Worker>(__safeDI_workerBuilder)
		                    return HoleImpl(workerBuilder: workerBuilder)
		                }
		                let holeService: any HoleService = __safeDI_holeService()
		                return holeService
		            }
		            func __safeDI_holeServiceBuilder_Outer(up: Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(seam: { values in __safeDI_holeServiceBuilder_Seam(up: up.seam(values)) })
		            }
		            func __safeDI_holeServiceBuilder_Seam(up: Seam.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(holeService: { scope in __safeDI_holeServiceBuilder_Seam_holeService(scope, __safeDI_outer_holeServiceBuilder: up.holeService(scope)) })
		            }
		            return Outer(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder_Outer(up: __safeDI_thingServiceBuilder_outer_holeServiceBuilder))
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(chainToken: chainToken, outer: outer)
		    }
		}

		extension Mid {
		    public enum __safeDI_Mid_EE42D97524F80263 {}
		}
		"""])
		#expect(output.modules["Top"]?.generatedFiles == ["Top.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Other)
		import Other
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension TopRoot {
		    public convenience init() {
		        func __safeDI_mid() -> Mid {
		            _ = Mid.__safeDI_Mid_EE42D97524F80263.self // If this line does not compile, compile the code SafeDI generates for module Other into Other: under Bazel, add Other’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_thingServiceBuilder_Mid() -> Mid.SafeDIScope_ThingService.__safeDI_Builder<any ThingService> {
		                .init(outer_holeServiceBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Outer() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: LazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService> {
		                .init(workerBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: chainToken) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: LazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<any ThingService> {
		                .init(thing: { _ in
		                    let thing: any ThingService = ThingImpl(chainToken: chainToken.instance)
		                    return thing
		                })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Outer() -> Outer.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(seam: { _ in __safeDI_thingServiceBuilder_Mid_Seam() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Seam() -> Seam.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(holeService: { values in __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: values.__safeDI_chainToken) })
		            }
		            return Mid(__safeDI_thingServiceBuilder: __safeDI_thingServiceBuilder_Mid())
		        }
		        let mid: Mid = __safeDI_mid()
		        self.init(mid: mid)
		    }
		}
		"""])
		try await expectCreationOrderEqualsOneModuleBuild(output, modules: modules)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillTakesDeferringSeamsMemo_whenSeamFillingItsPlaceDeclaresValueLazily() async throws {
		// `Outer` declares `token` lazily and fills `Inner`'s place with `ServiceImpl`, whose place `Top` fills with
		// `GadgetImpl`, whose place, beneath an `Instantiator`, `App` fills with `GizmoImpl`, which reads `token`. `gizmo`
		// carries `Outer`'s `LazilyInstantiated` as a field of `Outer`'s level, but the route through `Inner`'s level, nearer,
		// hands `Inner`'s memo of `Token`: the fill takes that memo, in that form. The level functions once took the field's
		// form and were handed the value, which did not compile.
		let modules = [
			ModuleFixture(name: "Core", packageName: "Min", swiftFileContent: ["""
			import SafeDI

			public nonisolated(unsafe) var log = [String]()

			@Instantiable
			public final class Token: Instantiable { public init() { log.append("Token") } }

			@Instantiable
			public final class Leaf: Instantiable {
				public init(token: Token) { self.token = token; log.append("Leaf") }
				@Received let token: Token
			}

			public protocol Service {}

			@Instantiable(generateDependencyTree: true)
			public final class Inner: Instantiable {
				public init(leafBuilder: Instantiator<Leaf>, service: any Service) { self.leafBuilder = leafBuilder; self.service = service; log.append("Inner") }
				@Instantiated let leafBuilder: Instantiator<Leaf>
				@Instantiated public let service: any Service
			}
			"""]),
			ModuleFixture(name: "Session", packageName: "Min", swiftFileContent: ["""
			import Core
			import SafeDI

			public protocol Gadget {}

			@Instantiable(fulfillingAdditionalTypes: [Service.self])
			public final class ServiceImpl: Instantiable, Service {
				public init(gadget: any Gadget) { self.gadget = gadget; log.append("ServiceImpl") }
				@Instantiated public let gadget: any Gadget
			}

			@Instantiable(generateDependencyTree: true)
			public final class Outer: Instantiable {
				public init(token: LazilyInstantiated<Token>, inner: Inner) { self.token = token; self.inner = inner; log.append("Outer") }
				@Instantiated let token: LazilyInstantiated<Token>
				@Instantiated public let inner: Inner
			}
			"""], dependencies: ["Core"]),
			ModuleFixture(name: "Feature", packageName: "Min", swiftFileContent: ["""
			import Core
			import SafeDI
			import Session

			public protocol Gizmo {}

			@Instantiable
			public final class Worker: Instantiable {
				public init(gizmo: any Gizmo) { self.gizmo = gizmo; log.append("Worker") }
				@Instantiated let gizmo: any Gizmo
			}

			@Instantiable(fulfillingAdditionalTypes: [Gadget.self])
			public final class GadgetImpl: Instantiable, Gadget {
				public init(workerBuilder: Instantiator<Worker>) { self.workerBuilder = workerBuilder; log.append("GadgetImpl") }
				@Instantiated public let workerBuilder: Instantiator<Worker>
			}

			@Instantiable(generateDependencyTree: true)
			public final class Top: Instantiable {
				public init(outer: Outer) { self.outer = outer; log.append("Top") }
				@Instantiated public let outer: Outer
			}
			"""], dependencies: ["Core", "Session"]),
			ModuleFixture(name: "App", packageName: "Min", swiftFileContent: ["""
			import Core
			import Feature
			import SafeDI
			import Session

			@Instantiable(fulfillingAdditionalTypes: [Gizmo.self])
			public final class GizmoImpl: Instantiable, Gizmo {
				public init(token: Token) { self.token = token; log.append("GizmoImpl") }
				@Received let token: Token
			}

			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
				public init(top: Top) { self.top = top; log.append("Root") }
				@Instantiated public let top: Top
			}
			"""], dependencies: ["Core", "Session", "Feature"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Inner {
		    nonisolated public enum SafeDIScope_Service {
		        nonisolated public struct service_Values {
		            public var token: Token { __safeDI_token.instance }
		            public let leafBuilder: Instantiator<Leaf>
		            public let __safeDI_token: LazilyInstantiated<Token>

		            init(token: LazilyInstantiated<Token>, leafBuilder: Instantiator<Leaf>) {
		                __safeDI_token = token
		                self.leafBuilder = leafBuilder
		            }
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

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_token: @autoclosure @escaping () -> Token, __safeDI_serviceBuilder: SafeDIScope_Service.__safeDI_Builder<any Service>) {
		        let token = LazilyInstantiated<Token>(__safeDI_token)
		        func __safeDI_leafBuilder() -> Leaf {
		            Leaf(token: token.instance)
		        }
		        let leafBuilder = Instantiator<Leaf>(__safeDI_leafBuilder)
		        let service: any Service = __safeDI_serviceBuilder.service(SafeDIScope_Service.service_Values(token: token, leafBuilder: leafBuilder))
		        self.init(leafBuilder: leafBuilder, service: service)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_DF6D02696D95A74B {}
		}
		"""])
		#expect(output.modules["Session"]?.generatedFiles == ["Session.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Outer {
		    nonisolated public enum SafeDIScope_Gadget {
		        nonisolated public struct inner_serviceBuilder_Values {
		            public let token: LazilyInstantiated<Token>
		        }

		        nonisolated public enum ServiceImpl_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let gadget: (__safeDI_Values) -> __safeDI_Built

		                public init(gadget: @escaping (__safeDI_Values) -> __safeDI_Built) {
		                    self.gadget = gadget
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.gadget = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let inner_serviceBuilder: (inner_serviceBuilder_Values) -> Inner.SafeDIScope_Service.__safeDI_Builder<SafeDIScope_Gadget.ServiceImpl_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(inner_serviceBuilder: @escaping (inner_serviceBuilder_Values) -> Inner.SafeDIScope_Service.__safeDI_Builder<SafeDIScope_Gadget.ServiceImpl_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.inner_serviceBuilder = inner_serviceBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.inner_serviceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
		        func __safeDI_token() -> Token {
		            Token()
		        }
		        let token = LazilyInstantiated<Token>(__safeDI_token)
		        let __safeDI_gadgetBuilder_inner_serviceBuilder = __safeDI_gadgetBuilder.inner_serviceBuilder(SafeDIScope_Gadget.inner_serviceBuilder_Values(token: token))
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_DF6D02696D95A74B.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_serviceBuilder_Inner_service(_ scope: Inner.SafeDIScope_Service.service_Values, __safeDI_inner_serviceBuilder: SafeDIScope_Gadget.ServiceImpl_Scope.__safeDI_Builder<any Gadget>) -> any Service {
		                func __safeDI_service() -> ServiceImpl {
		                    let gadget: any Gadget = __safeDI_inner_serviceBuilder.gadget(SafeDIScope_Gadget.ServiceImpl_Scope.__safeDI_Values())
		                    return ServiceImpl(gadget: gadget)
		                }
		                let service: any Service = __safeDI_service()
		                return service
		            }
		            func __safeDI_serviceBuilder_Inner(up: Inner.SafeDIScope_Service.__safeDI_Builder<SafeDIScope_Gadget.ServiceImpl_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDIScope_Service.__safeDI_Builder<any Service> {
		                .init(service: { scope in __safeDI_serviceBuilder_Inner_service(scope, __safeDI_inner_serviceBuilder: up.service(scope)) })
		            }
		            return Inner(__safeDI_token: token.instance, __safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner(up: __safeDI_gadgetBuilder_inner_serviceBuilder))
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(token: token, inner: inner)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_C0F14BC4E5CCE803 {}
		}
		"""])
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
		    nonisolated public enum SafeDIScope_Gizmo {
		        nonisolated public struct __safeDI_Values: Sendable {}

		        nonisolated public enum GadgetImpl_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let workerBuilder: (__safeDI_Values) -> SafeDIScope_Gizmo.Worker_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(workerBuilder: @escaping (__safeDI_Values) -> SafeDIScope_Gizmo.Worker_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.workerBuilder = workerBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.workerBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        nonisolated public enum Worker_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let gizmo: (__safeDI_Values) -> __safeDI_Built

		                public init(gizmo: @escaping (__safeDI_Values) -> __safeDI_Built) {
		                    self.gizmo = gizmo
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.gizmo = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let outer_gadgetBuilder: (__safeDI_Values) -> Outer.SafeDIScope_Gadget.__safeDI_Builder<SafeDIScope_Gizmo.GadgetImpl_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(outer_gadgetBuilder: @escaping (__safeDI_Values) -> Outer.SafeDIScope_Gadget.__safeDI_Builder<SafeDIScope_Gizmo.GadgetImpl_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.outer_gadgetBuilder = outer_gadgetBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.outer_gadgetBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_gizmoBuilder: SafeDIScope_Gizmo.__safeDI_Builder<any Gizmo>) {
		        let __safeDI_gizmoBuilder_outer_gadgetBuilder = __safeDI_gizmoBuilder.outer_gadgetBuilder(SafeDIScope_Gizmo.__safeDI_Values())
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_C0F14BC4E5CCE803.self // If this line does not compile, compile the code SafeDI generates for module Session into Session: under Bazel, add Session’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_gadgetBuilder_Outer_ServiceImpl_Scope_gadget(_ scope: Outer.SafeDIScope_Gadget.ServiceImpl_Scope.__safeDI_Values, __safeDI_outer_gadgetBuilder: SafeDIScope_Gizmo.GadgetImpl_Scope.__safeDI_Builder<any Gizmo>) -> any Gadget {
		                func __safeDI_gadget() -> GadgetImpl {
		                    let __safeDI_gizmoBuilder_workerBuilder = __safeDI_outer_gadgetBuilder.workerBuilder(SafeDIScope_Gizmo.GadgetImpl_Scope.__safeDI_Values())
		                    func __safeDI_workerBuilder() -> Worker {
		                        let gizmo: any Gizmo = __safeDI_gizmoBuilder_workerBuilder.gizmo(SafeDIScope_Gizmo.Worker_Scope.__safeDI_Values())
		                        return Worker(gizmo: gizmo)
		                    }
		                    let workerBuilder = Instantiator<Worker>(__safeDI_workerBuilder)
		                    return GadgetImpl(workerBuilder: workerBuilder)
		                }
		                let gadget: any Gadget = __safeDI_gadget()
		                return gadget
		            }
		            func __safeDI_gadgetBuilder_Outer(up: Outer.SafeDIScope_Gadget.__safeDI_Builder<SafeDIScope_Gizmo.GadgetImpl_Scope.__safeDI_Builder<any Gizmo>>) -> Outer.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
		                .init(inner_serviceBuilder: { values in __safeDI_gadgetBuilder_Outer_Inner(up: up.inner_serviceBuilder(values)) })
		            }
		            func __safeDI_gadgetBuilder_Outer_ServiceImpl_Scope(up: Outer.SafeDIScope_Gadget.ServiceImpl_Scope.__safeDI_Builder<SafeDIScope_Gizmo.GadgetImpl_Scope.__safeDI_Builder<any Gizmo>>) -> Outer.SafeDIScope_Gadget.ServiceImpl_Scope.__safeDI_Builder<any Gadget> {
		                .init(gadget: { scope in __safeDI_gadgetBuilder_Outer_ServiceImpl_Scope_gadget(scope, __safeDI_outer_gadgetBuilder: up.gadget(scope)) })
		            }
		            func __safeDI_gadgetBuilder_Outer_Inner(up: Inner.SafeDIScope_Service.__safeDI_Builder<Outer.SafeDIScope_Gadget.ServiceImpl_Scope.__safeDI_Builder<SafeDIScope_Gizmo.GadgetImpl_Scope.__safeDI_Builder<any Gizmo>>>) -> Inner.SafeDIScope_Service.__safeDI_Builder<Outer.SafeDIScope_Gadget.ServiceImpl_Scope.__safeDI_Builder<any Gadget>> {
		                .init(service: { values in __safeDI_gadgetBuilder_Outer_ServiceImpl_Scope(up: up.service(values)) })
		            }
		            return Outer(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Outer(up: __safeDI_gizmoBuilder_outer_gadgetBuilder))
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(outer: outer)
		    }
		}

		extension Top {
		    public enum __safeDI_Top_45E28712A50C176B {}
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
		            _ = Top.__safeDI_Top_45E28712A50C176B.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_gizmoBuilder_Top() -> Top.SafeDIScope_Gizmo.__safeDI_Builder<any Gizmo> {
		                .init(outer_gadgetBuilder: { _ in __safeDI_gizmoBuilder_Top_Outer() })
		            }
		            func __safeDI_gizmoBuilder_Top_GadgetImpl_Scope(token: LazilyInstantiated<Token>) -> Top.SafeDIScope_Gizmo.GadgetImpl_Scope.__safeDI_Builder<any Gizmo> {
		                .init(workerBuilder: { _ in __safeDI_gizmoBuilder_Top_Worker_Scope(token: token) })
		            }
		            func __safeDI_gizmoBuilder_Top_Worker_Scope(token: LazilyInstantiated<Token>) -> Top.SafeDIScope_Gizmo.Worker_Scope.__safeDI_Builder<any Gizmo> {
		                .init(gizmo: { _ in
		                    let gizmo: any Gizmo = GizmoImpl(token: token.instance)
		                    return gizmo
		                })
		            }
		            func __safeDI_gizmoBuilder_Top_Outer() -> Outer.SafeDIScope_Gadget.__safeDI_Builder<Top.SafeDIScope_Gizmo.GadgetImpl_Scope.__safeDI_Builder<any Gizmo>> {
		                .init(inner_serviceBuilder: { _ in __safeDI_gadgetBuilder_Outer_Inner() })
		            }
		            func __safeDI_gadgetBuilder_Outer_Inner() -> Inner.SafeDIScope_Service.__safeDI_Builder<Outer.SafeDIScope_Gadget.ServiceImpl_Scope.__safeDI_Builder<Top.SafeDIScope_Gizmo.GadgetImpl_Scope.__safeDI_Builder<any Gizmo>>> {
		                .init(service: { values in __safeDI_gizmoBuilder_Top_Outer_ServiceImpl_Scope(token: values.__safeDI_token) })
		            }
		            func __safeDI_gizmoBuilder_Top_Outer_ServiceImpl_Scope(token: LazilyInstantiated<Token>) -> Outer.SafeDIScope_Gadget.ServiceImpl_Scope.__safeDI_Builder<Top.SafeDIScope_Gizmo.GadgetImpl_Scope.__safeDI_Builder<any Gizmo>> {
		                .init(gadget: { _ in __safeDI_gizmoBuilder_Top_GadgetImpl_Scope(token: token) })
		            }
		            return Top(__safeDI_gizmoBuilder: __safeDI_gizmoBuilder_Top())
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}
		"""])
		try await expectCreationOrderEqualsOneModuleBuild(output, modules: modules, probeLines: [
			"{ () -> [String] in",
			"\tlog = []",
			"\tlet root = Root()",
			"\tlog.append(\"built Root\")",
			"\t_ = ((root.top.outer.inner.service as! ServiceImpl).gadget as! GadgetImpl).workerBuilder.instantiate()",
			"\tlog.append(\"called workerBuilder\")",
			"\treturn log",
			"}()",
		])
	}

	// MARK: A fill whose tree reads the value and its `SendableLazilyInstantiated`

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillTakesSendableMemo_whenTreeReadsValueAndSendableWrapperAndCallingSeamBuildsPlacesTypeOnItsOwnRoute() async throws {
		// `ThingImpl` reads `chainToken` and builds `WrapperReader`, which reads `TopRoot`'s `SendableLazilyInstantiated`.
		// `Outer` passes up only `SeamB`'s place, whose `SendableInstantiator` defers `chainToken` `@Sendable`, and `Mid` builds
		// `Worker` in `midWorkerBuilder` too, where the root dispatcher hands the caller's declaration: the fill takes
		// `SeamB`'s `SendableLazilyInstantiated`, which the root dispatcher hands as `TopRoot`'s own, so `WrapperReader` reads a
		// wrapper on both routes and `ChainToken` is created when a `Worker` is first built, as in the one-module build.
		let modules = Self.chainTokenModules(thingImpl: Self.thingImplReadingValueAndSendableWrapper, topChainToken: "@Instantiated let chainToken: SendableLazilyInstantiated<ChainToken>", midWorkerBuilder: true, outerHoldsOnlySeamB: true)
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

		extension Outer {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let seamB: (__safeDI_Values) -> SeamB.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>

		            public init(seamB: @escaping (__safeDI_Values) -> SeamB.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>) {
		                self.seamB = seamB
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.seamB = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    // SafeDI counts `HoleService` as `public`: no module it reads declares it narrower. If `HoleService` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping @Sendable () -> ChainToken, __safeDI_holeServiceBuilder: SafeDIScope_HoleService.__safeDI_Builder<any HoleService>) {
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        func __safeDI_seamB() -> SeamB {
		            _ = SeamB.__safeDI_SeamB_DC2838BAE7387202.self
		            return SeamB(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder.seamB(SafeDIScope_HoleService.__safeDI_Values()))
		        }
		        let seamB: SeamB = __safeDI_seamB()
		        self.init(seamB: seamB)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_315CDB5B658F55C9 {}
		}

		extension Seam {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct holeService_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let leafBuilder: Instantiator<ChainLeaf>
		            public let __safeDI_chainToken: LazilyInstantiated<ChainToken>

		            init(chainToken: LazilyInstantiated<ChainToken>, leafBuilder: Instantiator<ChainLeaf>) {
		                __safeDI_chainToken = chainToken
		                self.leafBuilder = leafBuilder
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
		        func __safeDI_leafBuilder() -> ChainLeaf {
		            ChainLeaf(chainToken: chainToken.instance)
		        }
		        let leafBuilder = Instantiator<ChainLeaf>(__safeDI_leafBuilder)
		        let holeService: any HoleService = __safeDI_holeServiceBuilder.holeService(SafeDIScope_HoleService.holeService_Values(chainToken: chainToken, leafBuilder: leafBuilder))
		        self.init(leafBuilder: leafBuilder, holeService: holeService)
		    }
		}

		extension Seam {
		    public enum __safeDI_Seam_2AD7242F90FE57C2 {}
		}

		extension SeamB {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct holeService_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let leafBuilder: SendableInstantiator<ChainLeaf>
		            public let __safeDI_chainToken: SendableLazilyInstantiated<ChainToken>

		            init(chainToken: SendableLazilyInstantiated<ChainToken>, leafBuilder: SendableInstantiator<ChainLeaf>) {
		                __safeDI_chainToken = chainToken
		                self.leafBuilder = leafBuilder
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
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping @Sendable () -> ChainToken, __safeDI_holeServiceBuilder: SafeDIScope_HoleService.__safeDI_Builder<any HoleService>) {
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        @Sendable nonisolated func __safeDI_leafBuilder() -> ChainLeaf {
		            ChainLeaf(chainToken: chainToken.instance)
		        }
		        let leafBuilder = SendableInstantiator<ChainLeaf>(__safeDI_leafBuilder)
		        let holeService: any HoleService = __safeDI_holeServiceBuilder.holeService(SafeDIScope_HoleService.holeService_Values(chainToken: chainToken, leafBuilder: leafBuilder))
		        self.init(leafBuilder: leafBuilder, holeService: holeService)
		    }
		}

		extension SeamB {
		    public enum __safeDI_SeamB_DC2838BAE7387202 {}
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

		extension Mid {
		    nonisolated public enum SafeDIScope_ThingService {
		        nonisolated public struct outer_holeServiceBuilder_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let __safeDI_chainToken: SendableLazilyInstantiated<ChainToken>

		            init(chainToken: SendableLazilyInstantiated<ChainToken>) {
		                __safeDI_chainToken = chainToken
		            }
		        }

		        nonisolated public struct midWorkerBuilder_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let outer: Outer
		            public let __safeDI_chainToken: SendableLazilyInstantiated<ChainToken>

		            init(chainToken: SendableLazilyInstantiated<ChainToken>, outer: Outer) {
		                __safeDI_chainToken = chainToken
		                self.outer = outer
		            }
		        }

		        nonisolated public enum HoleImpl_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let workerBuilder: (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(workerBuilder: @escaping (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.workerBuilder = workerBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.workerBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        nonisolated public enum Worker_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let thing: (__safeDI_Values) -> __safeDI_Built

		                public init(thing: @escaping (__safeDI_Values) -> __safeDI_Built) {
		                    self.thing = thing
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.thing = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public final class __safeDI_Builder<__safeDI_Built> {
		            public let outer_holeServiceBuilder: (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>
		            public let midWorkerBuilder: (midWorkerBuilder_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(outer_holeServiceBuilder: @escaping (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>, midWorkerBuilder: @escaping (midWorkerBuilder_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.outer_holeServiceBuilder = outer_holeServiceBuilder
		                self.midWorkerBuilder = midWorkerBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.outer_holeServiceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		                self.midWorkerBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    // SafeDI counts `ThingService` as `public`: no module it reads declares it narrower. If `ThingService` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping @Sendable () -> ChainToken, __safeDI_thingServiceBuilder: SafeDIScope_ThingService.__safeDI_Builder<any ThingService>) {
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        let __safeDI_thingServiceBuilder_outer_holeServiceBuilder = __safeDI_thingServiceBuilder.outer_holeServiceBuilder(SafeDIScope_ThingService.outer_holeServiceBuilder_Values(chainToken: chainToken))
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_315CDB5B658F55C9.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_holeServiceBuilder_SeamB_holeService(_ scope: SeamB.SafeDIScope_HoleService.holeService_Values, __safeDI_outer_holeServiceBuilder: SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>) -> any HoleService {
		                func __safeDI_holeService() -> HoleImpl {
		                    let __safeDI_thingServiceBuilder_workerBuilder = __safeDI_outer_holeServiceBuilder.workerBuilder(SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Values())
		                    func __safeDI_workerBuilder() -> Worker {
		                        let thing: any ThingService = __safeDI_thingServiceBuilder_workerBuilder.thing(SafeDIScope_ThingService.Worker_Scope.__safeDI_Values())
		                        return Worker(thing: thing)
		                    }
		                    let workerBuilder = Instantiator<Worker>(__safeDI_workerBuilder)
		                    return HoleImpl(workerBuilder: workerBuilder)
		                }
		                let holeService: any HoleService = __safeDI_holeService()
		                return holeService
		            }
		            func __safeDI_holeServiceBuilder_Outer(up: Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(seamB: { values in __safeDI_holeServiceBuilder_SeamB(up: up.seamB(values)) })
		            }
		            func __safeDI_holeServiceBuilder_SeamB(up: SeamB.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> SeamB.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(holeService: { scope in __safeDI_holeServiceBuilder_SeamB_holeService(scope, __safeDI_outer_holeServiceBuilder: up.holeService(scope)) })
		            }
		            return Outer(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder_Outer(up: __safeDI_thingServiceBuilder_outer_holeServiceBuilder))
		        }
		        let outer: Outer = __safeDI_outer()
		        let __safeDI_thingServiceBuilder_midWorkerBuilder = __safeDI_thingServiceBuilder.midWorkerBuilder(SafeDIScope_ThingService.midWorkerBuilder_Values(chainToken: chainToken, outer: outer))
		        func __safeDI_midWorkerBuilder() -> Worker {
		            let thing: any ThingService = __safeDI_thingServiceBuilder_midWorkerBuilder.thing(SafeDIScope_ThingService.Worker_Scope.__safeDI_Values())
		            return Worker(thing: thing)
		        }
		        let midWorkerBuilder = Instantiator<Worker>(__safeDI_midWorkerBuilder)
		        self.init(outer: outer, midWorkerBuilder: midWorkerBuilder)
		    }
		}

		extension Mid {
		    public enum __safeDI_Mid_8DEDB719400A4D1E {}
		}
		"""])
		#expect(output.modules["Top"]?.generatedFiles == ["Top.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Other)
		import Other
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension TopRoot {
		    public convenience init() {
		        @Sendable func __safeDI_chainToken() -> ChainToken {
		            ChainToken()
		        }
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        func __safeDI_mid() -> Mid {
		            _ = Mid.__safeDI_Mid_8DEDB719400A4D1E.self // If this line does not compile, compile the code SafeDI generates for module Other into Other: under Bazel, add Other’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope_thing(_ scope: Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Values, chainToken: SendableLazilyInstantiated<ChainToken>) -> any ThingService {
		                func __safeDI_thing() -> ThingImpl {
		                    let reader = WrapperReader(chainToken: chainToken)
		                    return ThingImpl(chainToken: chainToken.instance, reader: reader)
		                }
		                let thing: any ThingService = __safeDI_thing()
		                return thing
		            }
		            func __safeDI_thingServiceBuilder_Mid() -> Mid.SafeDIScope_ThingService.__safeDI_Builder<any ThingService> {
		                .init(outer_holeServiceBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Outer() }, midWorkerBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: chainToken) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: SendableLazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService> {
		                .init(workerBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: chainToken) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: SendableLazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<any ThingService> {
		                .init(thing: { scope in __safeDI_thingServiceBuilder_Mid_Worker_Scope_thing(scope, chainToken: chainToken) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Outer() -> Outer.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(seamB: { _ in __safeDI_thingServiceBuilder_Mid_SeamB() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_SeamB() -> SeamB.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(holeService: { values in __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: values.__safeDI_chainToken) })
		            }
		            return Mid(__safeDI_chainToken: chainToken.instance, __safeDI_thingServiceBuilder: __safeDI_thingServiceBuilder_Mid())
		        }
		        let mid: Mid = __safeDI_mid()
		        self.init(chainToken: chainToken, mid: mid)
		    }
		}
		"""])
		try await expectCreationOrderEqualsOneModuleBuild(output, modules: modules, seams: ["seamB"], midBuilders: ["midWorkerBuilder"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillTakesSeamsSendableMemo_whenTreeReadsValueAndSendableWrapperAndOnlySeamDefersValueInSendableLazilyInstantiated() async throws {
		// As above, without `Mid`'s own route: every route hands `SeamB`'s memo, which the fill takes as it is.
		let modules = Self.chainTokenModules(thingImpl: Self.thingImplReadingValueAndSendableWrapper, topChainToken: "@Instantiated let chainToken: SendableLazilyInstantiated<ChainToken>", outerHoldsOnlySeamB: true)
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

		extension Outer {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let seamB: (__safeDI_Values) -> SeamB.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>

		            public init(seamB: @escaping (__safeDI_Values) -> SeamB.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>) {
		                self.seamB = seamB
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.seamB = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    // SafeDI counts `HoleService` as `public`: no module it reads declares it narrower. If `HoleService` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping @Sendable () -> ChainToken, __safeDI_holeServiceBuilder: SafeDIScope_HoleService.__safeDI_Builder<any HoleService>) {
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        func __safeDI_seamB() -> SeamB {
		            _ = SeamB.__safeDI_SeamB_DC2838BAE7387202.self
		            return SeamB(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder.seamB(SafeDIScope_HoleService.__safeDI_Values()))
		        }
		        let seamB: SeamB = __safeDI_seamB()
		        self.init(seamB: seamB)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_315CDB5B658F55C9 {}
		}

		extension Seam {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct holeService_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let leafBuilder: Instantiator<ChainLeaf>
		            public let __safeDI_chainToken: LazilyInstantiated<ChainToken>

		            init(chainToken: LazilyInstantiated<ChainToken>, leafBuilder: Instantiator<ChainLeaf>) {
		                __safeDI_chainToken = chainToken
		                self.leafBuilder = leafBuilder
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
		        func __safeDI_leafBuilder() -> ChainLeaf {
		            ChainLeaf(chainToken: chainToken.instance)
		        }
		        let leafBuilder = Instantiator<ChainLeaf>(__safeDI_leafBuilder)
		        let holeService: any HoleService = __safeDI_holeServiceBuilder.holeService(SafeDIScope_HoleService.holeService_Values(chainToken: chainToken, leafBuilder: leafBuilder))
		        self.init(leafBuilder: leafBuilder, holeService: holeService)
		    }
		}

		extension Seam {
		    public enum __safeDI_Seam_2AD7242F90FE57C2 {}
		}

		extension SeamB {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct holeService_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let leafBuilder: SendableInstantiator<ChainLeaf>
		            public let __safeDI_chainToken: SendableLazilyInstantiated<ChainToken>

		            init(chainToken: SendableLazilyInstantiated<ChainToken>, leafBuilder: SendableInstantiator<ChainLeaf>) {
		                __safeDI_chainToken = chainToken
		                self.leafBuilder = leafBuilder
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
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping @Sendable () -> ChainToken, __safeDI_holeServiceBuilder: SafeDIScope_HoleService.__safeDI_Builder<any HoleService>) {
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        @Sendable nonisolated func __safeDI_leafBuilder() -> ChainLeaf {
		            ChainLeaf(chainToken: chainToken.instance)
		        }
		        let leafBuilder = SendableInstantiator<ChainLeaf>(__safeDI_leafBuilder)
		        let holeService: any HoleService = __safeDI_holeServiceBuilder.holeService(SafeDIScope_HoleService.holeService_Values(chainToken: chainToken, leafBuilder: leafBuilder))
		        self.init(leafBuilder: leafBuilder, holeService: holeService)
		    }
		}

		extension SeamB {
		    public enum __safeDI_SeamB_DC2838BAE7387202 {}
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

		extension Mid {
		    nonisolated public enum SafeDIScope_ThingService {
		        nonisolated public struct outer_holeServiceBuilder_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let __safeDI_chainToken: SendableLazilyInstantiated<ChainToken>

		            init(chainToken: SendableLazilyInstantiated<ChainToken>) {
		                __safeDI_chainToken = chainToken
		            }
		        }

		        nonisolated public enum HoleImpl_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let workerBuilder: (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(workerBuilder: @escaping (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.workerBuilder = workerBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.workerBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        nonisolated public enum Worker_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let thing: (__safeDI_Values) -> __safeDI_Built

		                public init(thing: @escaping (__safeDI_Values) -> __safeDI_Built) {
		                    self.thing = thing
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.thing = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let outer_holeServiceBuilder: (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(outer_holeServiceBuilder: @escaping (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.outer_holeServiceBuilder = outer_holeServiceBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.outer_holeServiceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		            }
		        }
		    }

		    // SafeDI counts `ThingService` as `public`: no module it reads declares it narrower. If `ThingService` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping @Sendable () -> ChainToken, __safeDI_thingServiceBuilder: SafeDIScope_ThingService.__safeDI_Builder<any ThingService>) {
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        let __safeDI_thingServiceBuilder_outer_holeServiceBuilder = __safeDI_thingServiceBuilder.outer_holeServiceBuilder(SafeDIScope_ThingService.outer_holeServiceBuilder_Values(chainToken: chainToken))
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_315CDB5B658F55C9.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_holeServiceBuilder_SeamB_holeService(_ scope: SeamB.SafeDIScope_HoleService.holeService_Values, __safeDI_outer_holeServiceBuilder: SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>) -> any HoleService {
		                func __safeDI_holeService() -> HoleImpl {
		                    let __safeDI_thingServiceBuilder_workerBuilder = __safeDI_outer_holeServiceBuilder.workerBuilder(SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Values())
		                    func __safeDI_workerBuilder() -> Worker {
		                        let thing: any ThingService = __safeDI_thingServiceBuilder_workerBuilder.thing(SafeDIScope_ThingService.Worker_Scope.__safeDI_Values())
		                        return Worker(thing: thing)
		                    }
		                    let workerBuilder = Instantiator<Worker>(__safeDI_workerBuilder)
		                    return HoleImpl(workerBuilder: workerBuilder)
		                }
		                let holeService: any HoleService = __safeDI_holeService()
		                return holeService
		            }
		            func __safeDI_holeServiceBuilder_Outer(up: Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(seamB: { values in __safeDI_holeServiceBuilder_SeamB(up: up.seamB(values)) })
		            }
		            func __safeDI_holeServiceBuilder_SeamB(up: SeamB.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> SeamB.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(holeService: { scope in __safeDI_holeServiceBuilder_SeamB_holeService(scope, __safeDI_outer_holeServiceBuilder: up.holeService(scope)) })
		            }
		            return Outer(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder_Outer(up: __safeDI_thingServiceBuilder_outer_holeServiceBuilder))
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(outer: outer)
		    }
		}

		extension Mid {
		    public enum __safeDI_Mid_FAA488108EA67CF5 {}
		}
		"""])
		#expect(output.modules["Top"]?.generatedFiles == ["Top.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Other)
		import Other
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension TopRoot {
		    public convenience init() {
		        @Sendable func __safeDI_chainToken() -> ChainToken {
		            ChainToken()
		        }
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        func __safeDI_mid() -> Mid {
		            _ = Mid.__safeDI_Mid_FAA488108EA67CF5.self // If this line does not compile, compile the code SafeDI generates for module Other into Other: under Bazel, add Other’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope_thing(_ scope: Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Values, chainToken: SendableLazilyInstantiated<ChainToken>) -> any ThingService {
		                func __safeDI_thing() -> ThingImpl {
		                    let reader = WrapperReader(chainToken: chainToken)
		                    return ThingImpl(chainToken: chainToken.instance, reader: reader)
		                }
		                let thing: any ThingService = __safeDI_thing()
		                return thing
		            }
		            func __safeDI_thingServiceBuilder_Mid() -> Mid.SafeDIScope_ThingService.__safeDI_Builder<any ThingService> {
		                .init(outer_holeServiceBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Outer() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: SendableLazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService> {
		                .init(workerBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: chainToken) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: SendableLazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<any ThingService> {
		                .init(thing: { scope in __safeDI_thingServiceBuilder_Mid_Worker_Scope_thing(scope, chainToken: chainToken) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Outer() -> Outer.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(seamB: { _ in __safeDI_thingServiceBuilder_Mid_SeamB() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_SeamB() -> SeamB.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(holeService: { values in __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: values.__safeDI_chainToken) })
		            }
		            return Mid(__safeDI_chainToken: chainToken.instance, __safeDI_thingServiceBuilder: __safeDI_thingServiceBuilder_Mid())
		        }
		        let mid: Mid = __safeDI_mid()
		        self.init(chainToken: chainToken, mid: mid)
		    }
		}
		"""])
		try await expectCreationOrderEqualsOneModuleBuild(output, modules: modules, seams: ["seamB"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillReadsCallersSendableWrapper_whenTreeReadsOnlySendableWrapperAndTwoPassingUpSeamsDeferValueUnlike() async throws {
		// `ThingImpl` reads only `WrapperReader`'s wrapper, with `Seam` deferring `chainToken` in a `LazilyInstantiated` and
		// `SeamB` in a `SendableLazilyInstantiated`: the fill takes no memo and reads `TopRoot`'s declaration.
		let modules = Self.chainTokenModules(thingImpl: Self.thingImplReadingOnlySendableWrapper, topChainToken: "@Instantiated let chainToken: SendableLazilyInstantiated<ChainToken>", outerHoldsSeamB: true)
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

		extension Outer {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public final class __safeDI_Builder<__safeDI_Built> {
		            public let seamB: (__safeDI_Values) -> SeamB.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>
		            public let seam: (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>

		            public init(seamB: @escaping (__safeDI_Values) -> SeamB.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>, seam: @escaping (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>) {
		                self.seamB = seamB
		                self.seam = seam
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.seamB = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                self.seam = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    // SafeDI counts `HoleService` as `public`: no module it reads declares it narrower. If `HoleService` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping @Sendable () -> ChainToken, __safeDI_holeServiceBuilder: SafeDIScope_HoleService.__safeDI_Builder<any HoleService>) {
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        func __safeDI_seamB() -> SeamB {
		            _ = SeamB.__safeDI_SeamB_DC2838BAE7387202.self
		            return SeamB(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder.seamB(SafeDIScope_HoleService.__safeDI_Values()))
		        }
		        let seamB: SeamB = __safeDI_seamB()
		        func __safeDI_seam() -> Seam {
		            _ = Seam.__safeDI_Seam_2AD7242F90FE57C2.self
		            return Seam(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder.seam(SafeDIScope_HoleService.__safeDI_Values()))
		        }
		        let seam: Seam = __safeDI_seam()
		        self.init(seam: seam, seamB: seamB)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_964A004ABC6F5712 {}
		}

		extension Seam {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct holeService_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let leafBuilder: Instantiator<ChainLeaf>
		            public let __safeDI_chainToken: LazilyInstantiated<ChainToken>

		            init(chainToken: LazilyInstantiated<ChainToken>, leafBuilder: Instantiator<ChainLeaf>) {
		                __safeDI_chainToken = chainToken
		                self.leafBuilder = leafBuilder
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
		        func __safeDI_leafBuilder() -> ChainLeaf {
		            ChainLeaf(chainToken: chainToken.instance)
		        }
		        let leafBuilder = Instantiator<ChainLeaf>(__safeDI_leafBuilder)
		        let holeService: any HoleService = __safeDI_holeServiceBuilder.holeService(SafeDIScope_HoleService.holeService_Values(chainToken: chainToken, leafBuilder: leafBuilder))
		        self.init(leafBuilder: leafBuilder, holeService: holeService)
		    }
		}

		extension Seam {
		    public enum __safeDI_Seam_2AD7242F90FE57C2 {}
		}

		extension SeamB {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct holeService_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let leafBuilder: SendableInstantiator<ChainLeaf>
		            public let __safeDI_chainToken: SendableLazilyInstantiated<ChainToken>

		            init(chainToken: SendableLazilyInstantiated<ChainToken>, leafBuilder: SendableInstantiator<ChainLeaf>) {
		                __safeDI_chainToken = chainToken
		                self.leafBuilder = leafBuilder
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
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping @Sendable () -> ChainToken, __safeDI_holeServiceBuilder: SafeDIScope_HoleService.__safeDI_Builder<any HoleService>) {
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        @Sendable nonisolated func __safeDI_leafBuilder() -> ChainLeaf {
		            ChainLeaf(chainToken: chainToken.instance)
		        }
		        let leafBuilder = SendableInstantiator<ChainLeaf>(__safeDI_leafBuilder)
		        let holeService: any HoleService = __safeDI_holeServiceBuilder.holeService(SafeDIScope_HoleService.holeService_Values(chainToken: chainToken, leafBuilder: leafBuilder))
		        self.init(leafBuilder: leafBuilder, holeService: holeService)
		    }
		}

		extension SeamB {
		    public enum __safeDI_SeamB_DC2838BAE7387202 {}
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

		extension Mid {
		    nonisolated public enum SafeDIScope_ThingService {
		        nonisolated public struct outer_holeServiceBuilder_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let __safeDI_chainToken: SendableLazilyInstantiated<ChainToken>

		            init(chainToken: SendableLazilyInstantiated<ChainToken>) {
		                __safeDI_chainToken = chainToken
		            }
		        }

		        nonisolated public enum HoleImpl_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let workerBuilder: (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(workerBuilder: @escaping (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.workerBuilder = workerBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.workerBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        nonisolated public enum Worker_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let thing: (__safeDI_Values) -> __safeDI_Built

		                public init(thing: @escaping (__safeDI_Values) -> __safeDI_Built) {
		                    self.thing = thing
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.thing = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let outer_holeServiceBuilder: (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(outer_holeServiceBuilder: @escaping (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.outer_holeServiceBuilder = outer_holeServiceBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.outer_holeServiceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		            }
		        }
		    }

		    // SafeDI counts `ThingService` as `public`: no module it reads declares it narrower. If `ThingService` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping @Sendable () -> ChainToken, __safeDI_thingServiceBuilder: SafeDIScope_ThingService.__safeDI_Builder<any ThingService>) {
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        let __safeDI_thingServiceBuilder_outer_holeServiceBuilder = __safeDI_thingServiceBuilder.outer_holeServiceBuilder(SafeDIScope_ThingService.outer_holeServiceBuilder_Values(chainToken: chainToken))
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_964A004ABC6F5712.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_holeServiceBuilder_SeamB_SeamB_holeService(_ scope: SeamB.SafeDIScope_HoleService.holeService_Values, __safeDI_outer_holeServiceBuilder: SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>) -> any HoleService {
		                func __safeDI_holeService() -> HoleImpl {
		                    let __safeDI_thingServiceBuilder_workerBuilder = __safeDI_outer_holeServiceBuilder.workerBuilder(SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Values())
		                    func __safeDI_workerBuilder() -> Worker {
		                        let thing: any ThingService = __safeDI_thingServiceBuilder_workerBuilder.thing(SafeDIScope_ThingService.Worker_Scope.__safeDI_Values())
		                        return Worker(thing: thing)
		                    }
		                    let workerBuilder = Instantiator<Worker>(__safeDI_workerBuilder)
		                    return HoleImpl(workerBuilder: workerBuilder)
		                }
		                let holeService: any HoleService = __safeDI_holeService()
		                return holeService
		            }
		            func __safeDI_holeServiceBuilder_Seam_Seam_holeService(_ scope: Seam.SafeDIScope_HoleService.holeService_Values, __safeDI_outer_holeServiceBuilder: SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>) -> any HoleService {
		                func __safeDI_holeService() -> HoleImpl {
		                    let __safeDI_thingServiceBuilder_workerBuilder = __safeDI_outer_holeServiceBuilder.workerBuilder(SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Values())
		                    func __safeDI_workerBuilder() -> Worker {
		                        let thing: any ThingService = __safeDI_thingServiceBuilder_workerBuilder.thing(SafeDIScope_ThingService.Worker_Scope.__safeDI_Values())
		                        return Worker(thing: thing)
		                    }
		                    let workerBuilder = Instantiator<Worker>(__safeDI_workerBuilder)
		                    return HoleImpl(workerBuilder: workerBuilder)
		                }
		                let holeService: any HoleService = __safeDI_holeService()
		                return holeService
		            }
		            func __safeDI_holeServiceBuilder_Outer(up: Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(seamB: { values in __safeDI_holeServiceBuilder_SeamB(up: up.seamB(values)) }, seam: { values in __safeDI_holeServiceBuilder_Seam(up: up.seam(values)) })
		            }
		            func __safeDI_holeServiceBuilder_SeamB(up: SeamB.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> SeamB.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(holeService: { scope in __safeDI_holeServiceBuilder_SeamB_SeamB_holeService(scope, __safeDI_outer_holeServiceBuilder: up.holeService(scope)) })
		            }
		            func __safeDI_holeServiceBuilder_Seam(up: Seam.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(holeService: { scope in __safeDI_holeServiceBuilder_Seam_Seam_holeService(scope, __safeDI_outer_holeServiceBuilder: up.holeService(scope)) })
		            }
		            return Outer(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder_Outer(up: __safeDI_thingServiceBuilder_outer_holeServiceBuilder))
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(outer: outer)
		    }
		}

		extension Mid {
		    public enum __safeDI_Mid_4F0B05A7DE9D5C26 {}
		}
		"""])
		#expect(output.modules["Top"]?.generatedFiles == ["Top.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Other)
		import Other
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension TopRoot {
		    public convenience init() {
		        @Sendable func __safeDI_chainToken() -> ChainToken {
		            ChainToken()
		        }
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        func __safeDI_mid() -> Mid {
		            _ = Mid.__safeDI_Mid_4F0B05A7DE9D5C26.self // If this line does not compile, compile the code SafeDI generates for module Other into Other: under Bazel, add Other’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope_thing(_ scope: Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Values) -> any ThingService {
		                func __safeDI_thing() -> ThingImpl {
		                    let reader = WrapperReader(chainToken: chainToken)
		                    return ThingImpl(reader: reader)
		                }
		                let thing: any ThingService = __safeDI_thing()
		                return thing
		            }
		            func __safeDI_thingServiceBuilder_Mid() -> Mid.SafeDIScope_ThingService.__safeDI_Builder<any ThingService> {
		                .init(outer_holeServiceBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Outer() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope() -> Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService> {
		                .init(workerBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Worker_Scope() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope() -> Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<any ThingService> {
		                .init(thing: { scope in __safeDI_thingServiceBuilder_Mid_Worker_Scope_thing(scope) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Outer() -> Outer.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(seamB: { _ in __safeDI_thingServiceBuilder_Mid_SeamB() }, seam: { _ in __safeDI_thingServiceBuilder_Mid_Seam() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_SeamB() -> SeamB.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(holeService: { _ in __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Seam() -> Seam.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(holeService: { _ in __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope() })
		            }
		            return Mid(__safeDI_chainToken: chainToken.instance, __safeDI_thingServiceBuilder: __safeDI_thingServiceBuilder_Mid())
		        }
		        let mid: Mid = __safeDI_mid()
		        self.init(chainToken: chainToken, mid: mid)
		    }
		}
		"""])
		try await expectCreationOrderEqualsOneModuleBuild(output, modules: modules, seams: ["seam", "seamB"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsSendableWrapperReadBesidePlainMemo_whenTreeReadsValueAndSendableWrapperThroughSeamDeferringValueInLazilyInstantiated() async {
		// `Seam` defers `chainToken` in a `LazilyInstantiated`, which no `@Sendable` function can capture, so the fill takes
		// that memo, which is no `SendableLazilyInstantiated`, and no seam on the route declares `chainToken` itself.
		await assertThrowsMultiModuleError(inModule: "Top", diagnostics: { fixtures in
			"""
			\(fixtures["Top"]!["ThingImpl.swift"]):20:2: error: `WrapperReader` receives `chainToken: SendableLazilyInstantiated<ChainToken>`, which SafeDI hands the builder for `Worker`’s `thing: any ThingService` (`thing` of `thingServiceBuilder`) only as `chainToken: LazilyInstantiated<ChainToken>`, since `Seam`’s tree reads `chainToken` outside a `@Sendable` function and `ThingImpl` receives its instance, `chainToken: ChainToken`. Receive `chainToken: ChainToken` on `WrapperReader`, or receive `chainToken: SendableLazilyInstantiated<ChainToken>` wherever that builder’s tree receives `chainToken: ChainToken`.
			\(fixtures["Top"]!["ThingImpl.swift"]):13:2: note: `ThingImpl` receives `chainToken: ChainToken` here.
			\(fixtures["Core"]!["ChainToken.swift"]):13:2: note: `ChainLeaf` receives `chainToken: ChainToken` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.chainTokenModules(thingImpl: Self.thingImplReadingValueAndSendableWrapper, topChainToken: Self.rootSendableChainToken), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsSendableWrapperReadBesidePlainMemo_whenOneOfTwoPassingUpSeamsDefersValueInLazilyInstantiated() async {
		// `SeamB` defers `chainToken` in a `SendableLazilyInstantiated`, but `Seam`'s route hands its `LazilyInstantiated`.
		await assertThrowsMultiModuleError(inModule: "Top", diagnostics: { fixtures in
			"""
			\(fixtures["Top"]!["ThingImpl.swift"]):20:2: error: `WrapperReader` receives `chainToken: SendableLazilyInstantiated<ChainToken>`, which SafeDI hands the builder for `Worker`’s `thing: any ThingService` (`thing` of `thingServiceBuilder`) only as `chainToken: LazilyInstantiated<ChainToken>`, since `Seam`’s tree reads `chainToken` outside a `@Sendable` function and `ThingImpl` receives its instance, `chainToken: ChainToken`. Receive `chainToken: ChainToken` on `WrapperReader`, or receive `chainToken: SendableLazilyInstantiated<ChainToken>` wherever that builder’s tree receives `chainToken: ChainToken`.
			\(fixtures["Top"]!["ThingImpl.swift"]):13:2: note: `ThingImpl` receives `chainToken: ChainToken` here.
			\(fixtures["Core"]!["ChainToken.swift"]):13:2: note: `ChainLeaf` receives `chainToken: ChainToken` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.chainTokenModules(thingImpl: Self.thingImplReadingValueAndSendableWrapper, topChainToken: Self.rootSendableChainToken, outerHoldsSeamB: true), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsSendableWrapperReadBesidePlainMemo_whenTwoPassingUpSeamsDeferValueInLazilyInstantiated() async {
		// Both seams hand a `LazilyInstantiated`: the error names each, in name order, and the type both trees build that
		// receives the value once.
		await assertThrowsMultiModuleError(inModule: "Top", diagnostics: { fixtures in
			"""
			\(fixtures["Top"]!["ThingImpl.swift"]):20:2: error: `WrapperReader` receives `chainToken: SendableLazilyInstantiated<ChainToken>`, which SafeDI hands the builder for `Worker`’s `thing: any ThingService` (`thing` of `thingServiceBuilder`) only as `chainToken: LazilyInstantiated<ChainToken>`, since `Seam`’s and `SeamB`’s trees read `chainToken` outside a `@Sendable` function and `ThingImpl` receives its instance, `chainToken: ChainToken`. Receive `chainToken: ChainToken` on `WrapperReader`, or receive `chainToken: SendableLazilyInstantiated<ChainToken>` wherever those builders’ trees receive `chainToken: ChainToken`.
			\(fixtures["Top"]!["ThingImpl.swift"]):13:2: note: `ThingImpl` receives `chainToken: ChainToken` here.
			\(fixtures["Core"]!["ChainToken.swift"]):13:2: note: `ChainLeaf` receives `chainToken: ChainToken` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.chainTokenModules(thingImpl: Self.thingImplReadingValueAndSendableWrapper, topChainToken: Self.rootSendableChainToken, outerHoldsSeamB: true, seamBLeafBuilder: "Instantiator"), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillTakesLazyMemo_whenTreeReadsValueTwiceThroughSeamDeferringValueInLazilyInstantiated() async throws {
		// The first remedy of the error above: `WrapperReader` receives the value, which the fill reads from `Seam`'s memo.
		let modules = Self.chainTokenModules(thingImpl: Self.thingImplReadingValueTwice, topChainToken: Self.rootSendableChainToken)
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

		extension Outer {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let seam: (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>

		            public init(seam: @escaping (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>) {
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
		            _ = Seam.__safeDI_Seam_2AD7242F90FE57C2.self
		            return Seam(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder.seam(SafeDIScope_HoleService.__safeDI_Values()))
		        }
		        let seam: Seam = __safeDI_seam()
		        self.init(seam: seam)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_2A8D23C10A89B5A9 {}
		}

		extension Seam {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct holeService_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let leafBuilder: Instantiator<ChainLeaf>
		            public let __safeDI_chainToken: LazilyInstantiated<ChainToken>

		            init(chainToken: LazilyInstantiated<ChainToken>, leafBuilder: Instantiator<ChainLeaf>) {
		                __safeDI_chainToken = chainToken
		                self.leafBuilder = leafBuilder
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
		        func __safeDI_leafBuilder() -> ChainLeaf {
		            ChainLeaf(chainToken: chainToken.instance)
		        }
		        let leafBuilder = Instantiator<ChainLeaf>(__safeDI_leafBuilder)
		        let holeService: any HoleService = __safeDI_holeServiceBuilder.holeService(SafeDIScope_HoleService.holeService_Values(chainToken: chainToken, leafBuilder: leafBuilder))
		        self.init(leafBuilder: leafBuilder, holeService: holeService)
		    }
		}

		extension Seam {
		    public enum __safeDI_Seam_2AD7242F90FE57C2 {}
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

		extension Mid {
		    nonisolated public enum SafeDIScope_ThingService {
		        nonisolated public struct outer_holeServiceBuilder_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let __safeDI_chainToken: LazilyInstantiated<ChainToken>

		            init(chainToken: LazilyInstantiated<ChainToken>) {
		                __safeDI_chainToken = chainToken
		            }
		        }

		        nonisolated public enum HoleImpl_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let workerBuilder: (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(workerBuilder: @escaping (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.workerBuilder = workerBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.workerBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        nonisolated public enum Worker_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let thing: (__safeDI_Values) -> __safeDI_Built

		                public init(thing: @escaping (__safeDI_Values) -> __safeDI_Built) {
		                    self.thing = thing
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.thing = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let outer_holeServiceBuilder: (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(outer_holeServiceBuilder: @escaping (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.outer_holeServiceBuilder = outer_holeServiceBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.outer_holeServiceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		            }
		        }
		    }

		    // SafeDI counts `ThingService` as `public`: no module it reads declares it narrower. If `ThingService` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping () -> ChainToken, __safeDI_thingServiceBuilder: SafeDIScope_ThingService.__safeDI_Builder<any ThingService>) {
		        let chainToken = LazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        let __safeDI_thingServiceBuilder_outer_holeServiceBuilder = __safeDI_thingServiceBuilder.outer_holeServiceBuilder(SafeDIScope_ThingService.outer_holeServiceBuilder_Values(chainToken: chainToken))
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_2A8D23C10A89B5A9.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_holeServiceBuilder_Seam_holeService(_ scope: Seam.SafeDIScope_HoleService.holeService_Values, __safeDI_outer_holeServiceBuilder: SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>) -> any HoleService {
		                func __safeDI_holeService() -> HoleImpl {
		                    let __safeDI_thingServiceBuilder_workerBuilder = __safeDI_outer_holeServiceBuilder.workerBuilder(SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Values())
		                    func __safeDI_workerBuilder() -> Worker {
		                        let thing: any ThingService = __safeDI_thingServiceBuilder_workerBuilder.thing(SafeDIScope_ThingService.Worker_Scope.__safeDI_Values())
		                        return Worker(thing: thing)
		                    }
		                    let workerBuilder = Instantiator<Worker>(__safeDI_workerBuilder)
		                    return HoleImpl(workerBuilder: workerBuilder)
		                }
		                let holeService: any HoleService = __safeDI_holeService()
		                return holeService
		            }
		            func __safeDI_holeServiceBuilder_Outer(up: Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(seam: { values in __safeDI_holeServiceBuilder_Seam(up: up.seam(values)) })
		            }
		            func __safeDI_holeServiceBuilder_Seam(up: Seam.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(holeService: { scope in __safeDI_holeServiceBuilder_Seam_holeService(scope, __safeDI_outer_holeServiceBuilder: up.holeService(scope)) })
		            }
		            return Outer(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder_Outer(up: __safeDI_thingServiceBuilder_outer_holeServiceBuilder))
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(outer: outer)
		    }
		}

		extension Mid {
		    public enum __safeDI_Mid_C9E7A7B945AD1E35 {}
		}
		"""])
		#expect(output.modules["Top"]?.generatedFiles == ["Top.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Other)
		import Other
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension TopRoot {
		    public convenience init() {
		        @Sendable func __safeDI_chainToken() -> ChainToken {
		            ChainToken()
		        }
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        func __safeDI_mid() -> Mid {
		            _ = Mid.__safeDI_Mid_C9E7A7B945AD1E35.self // If this line does not compile, compile the code SafeDI generates for module Other into Other: under Bazel, add Other’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope_thing(_ scope: Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Values, chainToken: LazilyInstantiated<ChainToken>) -> any ThingService {
		                func __safeDI_thing() -> ThingImpl {
		                    let reader = WrapperReader(chainToken: chainToken.instance)
		                    return ThingImpl(chainToken: chainToken.instance, reader: reader)
		                }
		                let thing: any ThingService = __safeDI_thing()
		                return thing
		            }
		            func __safeDI_thingServiceBuilder_Mid() -> Mid.SafeDIScope_ThingService.__safeDI_Builder<any ThingService> {
		                .init(outer_holeServiceBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Outer() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: LazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService> {
		                .init(workerBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: chainToken) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: LazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<any ThingService> {
		                .init(thing: { scope in __safeDI_thingServiceBuilder_Mid_Worker_Scope_thing(scope, chainToken: chainToken) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Outer() -> Outer.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(seam: { _ in __safeDI_thingServiceBuilder_Mid_Seam() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Seam() -> Seam.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(holeService: { values in __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: values.__safeDI_chainToken) })
		            }
		            return Mid(__safeDI_chainToken: chainToken.instance, __safeDI_thingServiceBuilder: __safeDI_thingServiceBuilder_Mid())
		        }
		        let mid: Mid = __safeDI_mid()
		        self.init(chainToken: chainToken, mid: mid)
		    }
		}
		"""])
		try await expectCreationOrderEqualsOneModuleBuild(output, modules: modules, comparingValues: [Self.rootBesideSeamsWorkerProbe])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillReadsCallersSendableWrapper_whenTreeReadsOnlySendableWrapperThroughSeamDeferringValueInLazilyInstantiated() async throws {
		// The second remedy of the error above: `ThingImpl` receives the wrapper too, so the tree reads only the wrapper,
		// which the fill reads from the caller's scope, `TopRoot`'s, as inline.
		let modules = Self.chainTokenModules(thingImpl: Self.thingImplReadingSendableWrapperTwice, topChainToken: Self.rootSendableChainToken)
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

		extension Outer {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let seam: (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>

		            public init(seam: @escaping (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>) {
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
		            _ = Seam.__safeDI_Seam_2AD7242F90FE57C2.self
		            return Seam(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder.seam(SafeDIScope_HoleService.__safeDI_Values()))
		        }
		        let seam: Seam = __safeDI_seam()
		        self.init(seam: seam)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_2A8D23C10A89B5A9 {}
		}

		extension Seam {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct holeService_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let leafBuilder: Instantiator<ChainLeaf>
		            public let __safeDI_chainToken: LazilyInstantiated<ChainToken>

		            init(chainToken: LazilyInstantiated<ChainToken>, leafBuilder: Instantiator<ChainLeaf>) {
		                __safeDI_chainToken = chainToken
		                self.leafBuilder = leafBuilder
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
		        func __safeDI_leafBuilder() -> ChainLeaf {
		            ChainLeaf(chainToken: chainToken.instance)
		        }
		        let leafBuilder = Instantiator<ChainLeaf>(__safeDI_leafBuilder)
		        let holeService: any HoleService = __safeDI_holeServiceBuilder.holeService(SafeDIScope_HoleService.holeService_Values(chainToken: chainToken, leafBuilder: leafBuilder))
		        self.init(leafBuilder: leafBuilder, holeService: holeService)
		    }
		}

		extension Seam {
		    public enum __safeDI_Seam_2AD7242F90FE57C2 {}
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

		extension Mid {
		    nonisolated public enum SafeDIScope_ThingService {
		        nonisolated public struct outer_holeServiceBuilder_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let __safeDI_chainToken: LazilyInstantiated<ChainToken>

		            init(chainToken: LazilyInstantiated<ChainToken>) {
		                __safeDI_chainToken = chainToken
		            }
		        }

		        nonisolated public enum HoleImpl_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let workerBuilder: (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(workerBuilder: @escaping (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.workerBuilder = workerBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.workerBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        nonisolated public enum Worker_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let thing: (__safeDI_Values) -> __safeDI_Built

		                public init(thing: @escaping (__safeDI_Values) -> __safeDI_Built) {
		                    self.thing = thing
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.thing = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let outer_holeServiceBuilder: (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(outer_holeServiceBuilder: @escaping (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.outer_holeServiceBuilder = outer_holeServiceBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.outer_holeServiceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		            }
		        }
		    }

		    // SafeDI counts `ThingService` as `public`: no module it reads declares it narrower. If `ThingService` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping () -> ChainToken, __safeDI_thingServiceBuilder: SafeDIScope_ThingService.__safeDI_Builder<any ThingService>) {
		        let chainToken = LazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        let __safeDI_thingServiceBuilder_outer_holeServiceBuilder = __safeDI_thingServiceBuilder.outer_holeServiceBuilder(SafeDIScope_ThingService.outer_holeServiceBuilder_Values(chainToken: chainToken))
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_2A8D23C10A89B5A9.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_holeServiceBuilder_Seam_holeService(_ scope: Seam.SafeDIScope_HoleService.holeService_Values, __safeDI_outer_holeServiceBuilder: SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>) -> any HoleService {
		                func __safeDI_holeService() -> HoleImpl {
		                    let __safeDI_thingServiceBuilder_workerBuilder = __safeDI_outer_holeServiceBuilder.workerBuilder(SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Values())
		                    func __safeDI_workerBuilder() -> Worker {
		                        let thing: any ThingService = __safeDI_thingServiceBuilder_workerBuilder.thing(SafeDIScope_ThingService.Worker_Scope.__safeDI_Values())
		                        return Worker(thing: thing)
		                    }
		                    let workerBuilder = Instantiator<Worker>(__safeDI_workerBuilder)
		                    return HoleImpl(workerBuilder: workerBuilder)
		                }
		                let holeService: any HoleService = __safeDI_holeService()
		                return holeService
		            }
		            func __safeDI_holeServiceBuilder_Outer(up: Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(seam: { values in __safeDI_holeServiceBuilder_Seam(up: up.seam(values)) })
		            }
		            func __safeDI_holeServiceBuilder_Seam(up: Seam.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(holeService: { scope in __safeDI_holeServiceBuilder_Seam_holeService(scope, __safeDI_outer_holeServiceBuilder: up.holeService(scope)) })
		            }
		            return Outer(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder_Outer(up: __safeDI_thingServiceBuilder_outer_holeServiceBuilder))
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(outer: outer)
		    }
		}

		extension Mid {
		    public enum __safeDI_Mid_C9E7A7B945AD1E35 {}
		}
		"""])
		#expect(output.modules["Top"]?.generatedFiles == ["Top.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Other)
		import Other
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension TopRoot {
		    public convenience init() {
		        @Sendable func __safeDI_chainToken() -> ChainToken {
		            ChainToken()
		        }
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        func __safeDI_mid() -> Mid {
		            _ = Mid.__safeDI_Mid_C9E7A7B945AD1E35.self // If this line does not compile, compile the code SafeDI generates for module Other into Other: under Bazel, add Other’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope_thing(_ scope: Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Values) -> any ThingService {
		                func __safeDI_thing() -> ThingImpl {
		                    let reader = WrapperReader(chainToken: chainToken)
		                    return ThingImpl(chainToken: chainToken, reader: reader)
		                }
		                let thing: any ThingService = __safeDI_thing()
		                return thing
		            }
		            func __safeDI_thingServiceBuilder_Mid() -> Mid.SafeDIScope_ThingService.__safeDI_Builder<any ThingService> {
		                .init(outer_holeServiceBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Outer() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope() -> Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService> {
		                .init(workerBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Worker_Scope() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope() -> Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<any ThingService> {
		                .init(thing: { scope in __safeDI_thingServiceBuilder_Mid_Worker_Scope_thing(scope) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Outer() -> Outer.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(seam: { _ in __safeDI_thingServiceBuilder_Mid_Seam() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Seam() -> Seam.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(holeService: { _ in __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope() })
		            }
		            return Mid(__safeDI_chainToken: chainToken.instance, __safeDI_thingServiceBuilder: __safeDI_thingServiceBuilder_Mid())
		        }
		        let mid: Mid = __safeDI_mid()
		        self.init(chainToken: chainToken, mid: mid)
		    }
		}
		"""])
		try await expectCreationOrderEqualsOneModuleBuild(output, modules: modules, comparingValues: [Self.rootBesideSeamsWorkerProbe])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillBindsSendableMemo_whenTreeReadsSendableWrapperInsideSendableInstantiatorAndCallingSeamBuildsPlacesTypeOnItsOwnRoute() async throws {
		// As `fillTakesSendableMemo_…OnItsOwnRoute`, with `WrapperReader` built in a `SendableInstantiator`: the fill binds the
		// `SendableLazilyInstantiated` it takes as the memo, which the `@Sendable` function captures, rather than its value.
		let modules = Self.chainTokenModules(thingImpl: Self.thingImplReadingSendableWrapperInside(holder: "SendableInstantiator", readsReader: "instantiate()"), topChainToken: Self.rootSendableChainToken, midWorkerBuilder: true, outerHoldsOnlySeamB: true)
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

		extension Outer {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let seamB: (__safeDI_Values) -> SeamB.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>

		            public init(seamB: @escaping (__safeDI_Values) -> SeamB.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>) {
		                self.seamB = seamB
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.seamB = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    // SafeDI counts `HoleService` as `public`: no module it reads declares it narrower. If `HoleService` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping @Sendable () -> ChainToken, __safeDI_holeServiceBuilder: SafeDIScope_HoleService.__safeDI_Builder<any HoleService>) {
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        func __safeDI_seamB() -> SeamB {
		            _ = SeamB.__safeDI_SeamB_DC2838BAE7387202.self
		            return SeamB(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder.seamB(SafeDIScope_HoleService.__safeDI_Values()))
		        }
		        let seamB: SeamB = __safeDI_seamB()
		        self.init(seamB: seamB)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_315CDB5B658F55C9 {}
		}

		extension Seam {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct holeService_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let leafBuilder: Instantiator<ChainLeaf>
		            public let __safeDI_chainToken: LazilyInstantiated<ChainToken>

		            init(chainToken: LazilyInstantiated<ChainToken>, leafBuilder: Instantiator<ChainLeaf>) {
		                __safeDI_chainToken = chainToken
		                self.leafBuilder = leafBuilder
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
		        func __safeDI_leafBuilder() -> ChainLeaf {
		            ChainLeaf(chainToken: chainToken.instance)
		        }
		        let leafBuilder = Instantiator<ChainLeaf>(__safeDI_leafBuilder)
		        let holeService: any HoleService = __safeDI_holeServiceBuilder.holeService(SafeDIScope_HoleService.holeService_Values(chainToken: chainToken, leafBuilder: leafBuilder))
		        self.init(leafBuilder: leafBuilder, holeService: holeService)
		    }
		}

		extension Seam {
		    public enum __safeDI_Seam_2AD7242F90FE57C2 {}
		}

		extension SeamB {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct holeService_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let leafBuilder: SendableInstantiator<ChainLeaf>
		            public let __safeDI_chainToken: SendableLazilyInstantiated<ChainToken>

		            init(chainToken: SendableLazilyInstantiated<ChainToken>, leafBuilder: SendableInstantiator<ChainLeaf>) {
		                __safeDI_chainToken = chainToken
		                self.leafBuilder = leafBuilder
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
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping @Sendable () -> ChainToken, __safeDI_holeServiceBuilder: SafeDIScope_HoleService.__safeDI_Builder<any HoleService>) {
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        @Sendable nonisolated func __safeDI_leafBuilder() -> ChainLeaf {
		            ChainLeaf(chainToken: chainToken.instance)
		        }
		        let leafBuilder = SendableInstantiator<ChainLeaf>(__safeDI_leafBuilder)
		        let holeService: any HoleService = __safeDI_holeServiceBuilder.holeService(SafeDIScope_HoleService.holeService_Values(chainToken: chainToken, leafBuilder: leafBuilder))
		        self.init(leafBuilder: leafBuilder, holeService: holeService)
		    }
		}

		extension SeamB {
		    public enum __safeDI_SeamB_DC2838BAE7387202 {}
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

		extension Mid {
		    nonisolated public enum SafeDIScope_ThingService {
		        nonisolated public struct outer_holeServiceBuilder_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let __safeDI_chainToken: SendableLazilyInstantiated<ChainToken>

		            init(chainToken: SendableLazilyInstantiated<ChainToken>) {
		                __safeDI_chainToken = chainToken
		            }
		        }

		        nonisolated public struct midWorkerBuilder_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let outer: Outer
		            public let __safeDI_chainToken: SendableLazilyInstantiated<ChainToken>

		            init(chainToken: SendableLazilyInstantiated<ChainToken>, outer: Outer) {
		                __safeDI_chainToken = chainToken
		                self.outer = outer
		            }
		        }

		        nonisolated public enum HoleImpl_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let workerBuilder: (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(workerBuilder: @escaping (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.workerBuilder = workerBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.workerBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        nonisolated public enum Worker_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let thing: (__safeDI_Values) -> __safeDI_Built

		                public init(thing: @escaping (__safeDI_Values) -> __safeDI_Built) {
		                    self.thing = thing
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.thing = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public final class __safeDI_Builder<__safeDI_Built> {
		            public let outer_holeServiceBuilder: (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>
		            public let midWorkerBuilder: (midWorkerBuilder_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(outer_holeServiceBuilder: @escaping (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>, midWorkerBuilder: @escaping (midWorkerBuilder_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.outer_holeServiceBuilder = outer_holeServiceBuilder
		                self.midWorkerBuilder = midWorkerBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.outer_holeServiceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		                self.midWorkerBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    // SafeDI counts `ThingService` as `public`: no module it reads declares it narrower. If `ThingService` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping @Sendable () -> ChainToken, __safeDI_thingServiceBuilder: SafeDIScope_ThingService.__safeDI_Builder<any ThingService>) {
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        let __safeDI_thingServiceBuilder_outer_holeServiceBuilder = __safeDI_thingServiceBuilder.outer_holeServiceBuilder(SafeDIScope_ThingService.outer_holeServiceBuilder_Values(chainToken: chainToken))
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_315CDB5B658F55C9.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_holeServiceBuilder_SeamB_holeService(_ scope: SeamB.SafeDIScope_HoleService.holeService_Values, __safeDI_outer_holeServiceBuilder: SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>) -> any HoleService {
		                func __safeDI_holeService() -> HoleImpl {
		                    let __safeDI_thingServiceBuilder_workerBuilder = __safeDI_outer_holeServiceBuilder.workerBuilder(SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Values())
		                    func __safeDI_workerBuilder() -> Worker {
		                        let thing: any ThingService = __safeDI_thingServiceBuilder_workerBuilder.thing(SafeDIScope_ThingService.Worker_Scope.__safeDI_Values())
		                        return Worker(thing: thing)
		                    }
		                    let workerBuilder = Instantiator<Worker>(__safeDI_workerBuilder)
		                    return HoleImpl(workerBuilder: workerBuilder)
		                }
		                let holeService: any HoleService = __safeDI_holeService()
		                return holeService
		            }
		            func __safeDI_holeServiceBuilder_Outer(up: Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(seamB: { values in __safeDI_holeServiceBuilder_SeamB(up: up.seamB(values)) })
		            }
		            func __safeDI_holeServiceBuilder_SeamB(up: SeamB.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> SeamB.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(holeService: { scope in __safeDI_holeServiceBuilder_SeamB_holeService(scope, __safeDI_outer_holeServiceBuilder: up.holeService(scope)) })
		            }
		            return Outer(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder_Outer(up: __safeDI_thingServiceBuilder_outer_holeServiceBuilder))
		        }
		        let outer: Outer = __safeDI_outer()
		        let __safeDI_thingServiceBuilder_midWorkerBuilder = __safeDI_thingServiceBuilder.midWorkerBuilder(SafeDIScope_ThingService.midWorkerBuilder_Values(chainToken: chainToken, outer: outer))
		        func __safeDI_midWorkerBuilder() -> Worker {
		            let thing: any ThingService = __safeDI_thingServiceBuilder_midWorkerBuilder.thing(SafeDIScope_ThingService.Worker_Scope.__safeDI_Values())
		            return Worker(thing: thing)
		        }
		        let midWorkerBuilder = Instantiator<Worker>(__safeDI_midWorkerBuilder)
		        self.init(outer: outer, midWorkerBuilder: midWorkerBuilder)
		    }
		}

		extension Mid {
		    public enum __safeDI_Mid_8DEDB719400A4D1E {}
		}
		"""])
		#expect(output.modules["Top"]?.generatedFiles == ["Top.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Other)
		import Other
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension TopRoot {
		    public convenience init() {
		        @Sendable func __safeDI_chainToken() -> ChainToken {
		            ChainToken()
		        }
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        func __safeDI_mid() -> Mid {
		            _ = Mid.__safeDI_Mid_8DEDB719400A4D1E.self // If this line does not compile, compile the code SafeDI generates for module Other into Other: under Bazel, add Other’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope_thing(_ scope: Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Values, chainToken: SendableLazilyInstantiated<ChainToken>) -> any ThingService {
		                func __safeDI_thing() -> ThingImpl {
		                    @Sendable func __safeDI_readerHolder() -> WrapperReader {
		                        WrapperReader(chainToken: chainToken)
		                    }
		                    let readerHolder = SendableInstantiator<WrapperReader>(__safeDI_readerHolder)
		                    return ThingImpl(chainToken: chainToken.instance, readerHolder: readerHolder)
		                }
		                let thing: any ThingService = __safeDI_thing()
		                return thing
		            }
		            func __safeDI_thingServiceBuilder_Mid() -> Mid.SafeDIScope_ThingService.__safeDI_Builder<any ThingService> {
		                .init(outer_holeServiceBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Outer() }, midWorkerBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: chainToken) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: SendableLazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService> {
		                .init(workerBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: chainToken) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: SendableLazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<any ThingService> {
		                .init(thing: { scope in __safeDI_thingServiceBuilder_Mid_Worker_Scope_thing(scope, chainToken: chainToken) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Outer() -> Outer.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(seamB: { _ in __safeDI_thingServiceBuilder_Mid_SeamB() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_SeamB() -> SeamB.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(holeService: { values in __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: values.__safeDI_chainToken) })
		            }
		            return Mid(__safeDI_chainToken: chainToken.instance, __safeDI_thingServiceBuilder: __safeDI_thingServiceBuilder_Mid())
		        }
		        let mid: Mid = __safeDI_mid()
		        self.init(chainToken: chainToken, mid: mid)
		    }
		}
		"""])
		try await expectCreationOrderEqualsOneModuleBuild(output, modules: modules, seams: ["seamB"], midBuilders: ["midWorkerBuilder"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillBindsSendableMemo_whenTreeReadsSendableWrapperInsideSendableLazilyInstantiatedAndCallingSeamBuildsPlacesTypeOnItsOwnRoute() async throws {
		// As above, with `WrapperReader` built in a `SendableLazilyInstantiated`.
		let modules = Self.chainTokenModules(thingImpl: Self.thingImplReadingSendableWrapperInside(holder: "SendableLazilyInstantiated", readsReader: "instance"), topChainToken: Self.rootSendableChainToken, midWorkerBuilder: true, outerHoldsOnlySeamB: true)
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

		extension Outer {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let seamB: (__safeDI_Values) -> SeamB.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>

		            public init(seamB: @escaping (__safeDI_Values) -> SeamB.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>) {
		                self.seamB = seamB
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.seamB = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    // SafeDI counts `HoleService` as `public`: no module it reads declares it narrower. If `HoleService` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping @Sendable () -> ChainToken, __safeDI_holeServiceBuilder: SafeDIScope_HoleService.__safeDI_Builder<any HoleService>) {
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        func __safeDI_seamB() -> SeamB {
		            _ = SeamB.__safeDI_SeamB_DC2838BAE7387202.self
		            return SeamB(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder.seamB(SafeDIScope_HoleService.__safeDI_Values()))
		        }
		        let seamB: SeamB = __safeDI_seamB()
		        self.init(seamB: seamB)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_315CDB5B658F55C9 {}
		}

		extension Seam {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct holeService_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let leafBuilder: Instantiator<ChainLeaf>
		            public let __safeDI_chainToken: LazilyInstantiated<ChainToken>

		            init(chainToken: LazilyInstantiated<ChainToken>, leafBuilder: Instantiator<ChainLeaf>) {
		                __safeDI_chainToken = chainToken
		                self.leafBuilder = leafBuilder
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
		        func __safeDI_leafBuilder() -> ChainLeaf {
		            ChainLeaf(chainToken: chainToken.instance)
		        }
		        let leafBuilder = Instantiator<ChainLeaf>(__safeDI_leafBuilder)
		        let holeService: any HoleService = __safeDI_holeServiceBuilder.holeService(SafeDIScope_HoleService.holeService_Values(chainToken: chainToken, leafBuilder: leafBuilder))
		        self.init(leafBuilder: leafBuilder, holeService: holeService)
		    }
		}

		extension Seam {
		    public enum __safeDI_Seam_2AD7242F90FE57C2 {}
		}

		extension SeamB {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct holeService_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let leafBuilder: SendableInstantiator<ChainLeaf>
		            public let __safeDI_chainToken: SendableLazilyInstantiated<ChainToken>

		            init(chainToken: SendableLazilyInstantiated<ChainToken>, leafBuilder: SendableInstantiator<ChainLeaf>) {
		                __safeDI_chainToken = chainToken
		                self.leafBuilder = leafBuilder
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
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping @Sendable () -> ChainToken, __safeDI_holeServiceBuilder: SafeDIScope_HoleService.__safeDI_Builder<any HoleService>) {
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        @Sendable nonisolated func __safeDI_leafBuilder() -> ChainLeaf {
		            ChainLeaf(chainToken: chainToken.instance)
		        }
		        let leafBuilder = SendableInstantiator<ChainLeaf>(__safeDI_leafBuilder)
		        let holeService: any HoleService = __safeDI_holeServiceBuilder.holeService(SafeDIScope_HoleService.holeService_Values(chainToken: chainToken, leafBuilder: leafBuilder))
		        self.init(leafBuilder: leafBuilder, holeService: holeService)
		    }
		}

		extension SeamB {
		    public enum __safeDI_SeamB_DC2838BAE7387202 {}
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

		extension Mid {
		    nonisolated public enum SafeDIScope_ThingService {
		        nonisolated public struct outer_holeServiceBuilder_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let __safeDI_chainToken: SendableLazilyInstantiated<ChainToken>

		            init(chainToken: SendableLazilyInstantiated<ChainToken>) {
		                __safeDI_chainToken = chainToken
		            }
		        }

		        nonisolated public struct midWorkerBuilder_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let outer: Outer
		            public let __safeDI_chainToken: SendableLazilyInstantiated<ChainToken>

		            init(chainToken: SendableLazilyInstantiated<ChainToken>, outer: Outer) {
		                __safeDI_chainToken = chainToken
		                self.outer = outer
		            }
		        }

		        nonisolated public enum HoleImpl_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let workerBuilder: (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(workerBuilder: @escaping (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.workerBuilder = workerBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.workerBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        nonisolated public enum Worker_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let thing: (__safeDI_Values) -> __safeDI_Built

		                public init(thing: @escaping (__safeDI_Values) -> __safeDI_Built) {
		                    self.thing = thing
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.thing = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public final class __safeDI_Builder<__safeDI_Built> {
		            public let outer_holeServiceBuilder: (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>
		            public let midWorkerBuilder: (midWorkerBuilder_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(outer_holeServiceBuilder: @escaping (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>, midWorkerBuilder: @escaping (midWorkerBuilder_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.outer_holeServiceBuilder = outer_holeServiceBuilder
		                self.midWorkerBuilder = midWorkerBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.outer_holeServiceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		                self.midWorkerBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    // SafeDI counts `ThingService` as `public`: no module it reads declares it narrower. If `ThingService` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping @Sendable () -> ChainToken, __safeDI_thingServiceBuilder: SafeDIScope_ThingService.__safeDI_Builder<any ThingService>) {
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        let __safeDI_thingServiceBuilder_outer_holeServiceBuilder = __safeDI_thingServiceBuilder.outer_holeServiceBuilder(SafeDIScope_ThingService.outer_holeServiceBuilder_Values(chainToken: chainToken))
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_315CDB5B658F55C9.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_holeServiceBuilder_SeamB_holeService(_ scope: SeamB.SafeDIScope_HoleService.holeService_Values, __safeDI_outer_holeServiceBuilder: SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>) -> any HoleService {
		                func __safeDI_holeService() -> HoleImpl {
		                    let __safeDI_thingServiceBuilder_workerBuilder = __safeDI_outer_holeServiceBuilder.workerBuilder(SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Values())
		                    func __safeDI_workerBuilder() -> Worker {
		                        let thing: any ThingService = __safeDI_thingServiceBuilder_workerBuilder.thing(SafeDIScope_ThingService.Worker_Scope.__safeDI_Values())
		                        return Worker(thing: thing)
		                    }
		                    let workerBuilder = Instantiator<Worker>(__safeDI_workerBuilder)
		                    return HoleImpl(workerBuilder: workerBuilder)
		                }
		                let holeService: any HoleService = __safeDI_holeService()
		                return holeService
		            }
		            func __safeDI_holeServiceBuilder_Outer(up: Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(seamB: { values in __safeDI_holeServiceBuilder_SeamB(up: up.seamB(values)) })
		            }
		            func __safeDI_holeServiceBuilder_SeamB(up: SeamB.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> SeamB.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(holeService: { scope in __safeDI_holeServiceBuilder_SeamB_holeService(scope, __safeDI_outer_holeServiceBuilder: up.holeService(scope)) })
		            }
		            return Outer(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder_Outer(up: __safeDI_thingServiceBuilder_outer_holeServiceBuilder))
		        }
		        let outer: Outer = __safeDI_outer()
		        let __safeDI_thingServiceBuilder_midWorkerBuilder = __safeDI_thingServiceBuilder.midWorkerBuilder(SafeDIScope_ThingService.midWorkerBuilder_Values(chainToken: chainToken, outer: outer))
		        func __safeDI_midWorkerBuilder() -> Worker {
		            let thing: any ThingService = __safeDI_thingServiceBuilder_midWorkerBuilder.thing(SafeDIScope_ThingService.Worker_Scope.__safeDI_Values())
		            return Worker(thing: thing)
		        }
		        let midWorkerBuilder = Instantiator<Worker>(__safeDI_midWorkerBuilder)
		        self.init(outer: outer, midWorkerBuilder: midWorkerBuilder)
		    }
		}

		extension Mid {
		    public enum __safeDI_Mid_8DEDB719400A4D1E {}
		}
		"""])
		#expect(output.modules["Top"]?.generatedFiles == ["Top.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Other)
		import Other
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension TopRoot {
		    public convenience init() {
		        @Sendable func __safeDI_chainToken() -> ChainToken {
		            ChainToken()
		        }
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        func __safeDI_mid() -> Mid {
		            _ = Mid.__safeDI_Mid_8DEDB719400A4D1E.self // If this line does not compile, compile the code SafeDI generates for module Other into Other: under Bazel, add Other’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope_thing(_ scope: Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Values, chainToken: SendableLazilyInstantiated<ChainToken>) -> any ThingService {
		                func __safeDI_thing() -> ThingImpl {
		                    @Sendable func __safeDI_readerHolder() -> WrapperReader {
		                        WrapperReader(chainToken: chainToken)
		                    }
		                    let readerHolder = SendableLazilyInstantiated<WrapperReader>(__safeDI_readerHolder)
		                    return ThingImpl(chainToken: chainToken.instance, readerHolder: readerHolder)
		                }
		                let thing: any ThingService = __safeDI_thing()
		                return thing
		            }
		            func __safeDI_thingServiceBuilder_Mid() -> Mid.SafeDIScope_ThingService.__safeDI_Builder<any ThingService> {
		                .init(outer_holeServiceBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Outer() }, midWorkerBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: chainToken) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: SendableLazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService> {
		                .init(workerBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: chainToken) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: SendableLazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<any ThingService> {
		                .init(thing: { scope in __safeDI_thingServiceBuilder_Mid_Worker_Scope_thing(scope, chainToken: chainToken) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Outer() -> Outer.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(seamB: { _ in __safeDI_thingServiceBuilder_Mid_SeamB() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_SeamB() -> SeamB.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(holeService: { values in __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: values.__safeDI_chainToken) })
		            }
		            return Mid(__safeDI_chainToken: chainToken.instance, __safeDI_thingServiceBuilder: __safeDI_thingServiceBuilder_Mid())
		        }
		        let mid: Mid = __safeDI_mid()
		        self.init(chainToken: chainToken, mid: mid)
		    }
		}
		"""])
		try await expectCreationOrderEqualsOneModuleBuild(output, modules: modules, seams: ["seamB"], midBuilders: ["midWorkerBuilder"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillBindsSendableMemo_whenTreeReadsSendableWrapperBesideValueReadInsideSendableFunctionAndCallingSeamBuildsPlacesTypeOnItsOwnRoute() async throws {
		// `ThingImpl` receives the wrapper and builds `ChainLeaf`, which reads the value, in a `SendableInstantiator`.
		let modules = Self.chainTokenModules(thingImpl: Self.thingImplReadingSendableWrapperAndValueInsideSendableFunction, topChainToken: Self.rootSendableChainToken, midWorkerBuilder: true, outerHoldsOnlySeamB: true)
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

		extension Outer {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let seamB: (__safeDI_Values) -> SeamB.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>

		            public init(seamB: @escaping (__safeDI_Values) -> SeamB.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>) {
		                self.seamB = seamB
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.seamB = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    // SafeDI counts `HoleService` as `public`: no module it reads declares it narrower. If `HoleService` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping @Sendable () -> ChainToken, __safeDI_holeServiceBuilder: SafeDIScope_HoleService.__safeDI_Builder<any HoleService>) {
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        func __safeDI_seamB() -> SeamB {
		            _ = SeamB.__safeDI_SeamB_DC2838BAE7387202.self
		            return SeamB(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder.seamB(SafeDIScope_HoleService.__safeDI_Values()))
		        }
		        let seamB: SeamB = __safeDI_seamB()
		        self.init(seamB: seamB)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_315CDB5B658F55C9 {}
		}

		extension Seam {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct holeService_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let leafBuilder: Instantiator<ChainLeaf>
		            public let __safeDI_chainToken: LazilyInstantiated<ChainToken>

		            init(chainToken: LazilyInstantiated<ChainToken>, leafBuilder: Instantiator<ChainLeaf>) {
		                __safeDI_chainToken = chainToken
		                self.leafBuilder = leafBuilder
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
		        func __safeDI_leafBuilder() -> ChainLeaf {
		            ChainLeaf(chainToken: chainToken.instance)
		        }
		        let leafBuilder = Instantiator<ChainLeaf>(__safeDI_leafBuilder)
		        let holeService: any HoleService = __safeDI_holeServiceBuilder.holeService(SafeDIScope_HoleService.holeService_Values(chainToken: chainToken, leafBuilder: leafBuilder))
		        self.init(leafBuilder: leafBuilder, holeService: holeService)
		    }
		}

		extension Seam {
		    public enum __safeDI_Seam_2AD7242F90FE57C2 {}
		}

		extension SeamB {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct holeService_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let leafBuilder: SendableInstantiator<ChainLeaf>
		            public let __safeDI_chainToken: SendableLazilyInstantiated<ChainToken>

		            init(chainToken: SendableLazilyInstantiated<ChainToken>, leafBuilder: SendableInstantiator<ChainLeaf>) {
		                __safeDI_chainToken = chainToken
		                self.leafBuilder = leafBuilder
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
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping @Sendable () -> ChainToken, __safeDI_holeServiceBuilder: SafeDIScope_HoleService.__safeDI_Builder<any HoleService>) {
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        @Sendable nonisolated func __safeDI_leafBuilder() -> ChainLeaf {
		            ChainLeaf(chainToken: chainToken.instance)
		        }
		        let leafBuilder = SendableInstantiator<ChainLeaf>(__safeDI_leafBuilder)
		        let holeService: any HoleService = __safeDI_holeServiceBuilder.holeService(SafeDIScope_HoleService.holeService_Values(chainToken: chainToken, leafBuilder: leafBuilder))
		        self.init(leafBuilder: leafBuilder, holeService: holeService)
		    }
		}

		extension SeamB {
		    public enum __safeDI_SeamB_DC2838BAE7387202 {}
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

		extension Mid {
		    nonisolated public enum SafeDIScope_ThingService {
		        nonisolated public struct outer_holeServiceBuilder_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let __safeDI_chainToken: SendableLazilyInstantiated<ChainToken>

		            init(chainToken: SendableLazilyInstantiated<ChainToken>) {
		                __safeDI_chainToken = chainToken
		            }
		        }

		        nonisolated public struct midWorkerBuilder_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let outer: Outer
		            public let __safeDI_chainToken: SendableLazilyInstantiated<ChainToken>

		            init(chainToken: SendableLazilyInstantiated<ChainToken>, outer: Outer) {
		                __safeDI_chainToken = chainToken
		                self.outer = outer
		            }
		        }

		        nonisolated public enum HoleImpl_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let workerBuilder: (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(workerBuilder: @escaping (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.workerBuilder = workerBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.workerBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        nonisolated public enum Worker_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let thing: (__safeDI_Values) -> __safeDI_Built

		                public init(thing: @escaping (__safeDI_Values) -> __safeDI_Built) {
		                    self.thing = thing
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.thing = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public final class __safeDI_Builder<__safeDI_Built> {
		            public let outer_holeServiceBuilder: (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>
		            public let midWorkerBuilder: (midWorkerBuilder_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(outer_holeServiceBuilder: @escaping (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>, midWorkerBuilder: @escaping (midWorkerBuilder_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.outer_holeServiceBuilder = outer_holeServiceBuilder
		                self.midWorkerBuilder = midWorkerBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.outer_holeServiceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		                self.midWorkerBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    // SafeDI counts `ThingService` as `public`: no module it reads declares it narrower. If `ThingService` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping @Sendable () -> ChainToken, __safeDI_thingServiceBuilder: SafeDIScope_ThingService.__safeDI_Builder<any ThingService>) {
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        let __safeDI_thingServiceBuilder_outer_holeServiceBuilder = __safeDI_thingServiceBuilder.outer_holeServiceBuilder(SafeDIScope_ThingService.outer_holeServiceBuilder_Values(chainToken: chainToken))
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_315CDB5B658F55C9.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_holeServiceBuilder_SeamB_holeService(_ scope: SeamB.SafeDIScope_HoleService.holeService_Values, __safeDI_outer_holeServiceBuilder: SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>) -> any HoleService {
		                func __safeDI_holeService() -> HoleImpl {
		                    let __safeDI_thingServiceBuilder_workerBuilder = __safeDI_outer_holeServiceBuilder.workerBuilder(SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Values())
		                    func __safeDI_workerBuilder() -> Worker {
		                        let thing: any ThingService = __safeDI_thingServiceBuilder_workerBuilder.thing(SafeDIScope_ThingService.Worker_Scope.__safeDI_Values())
		                        return Worker(thing: thing)
		                    }
		                    let workerBuilder = Instantiator<Worker>(__safeDI_workerBuilder)
		                    return HoleImpl(workerBuilder: workerBuilder)
		                }
		                let holeService: any HoleService = __safeDI_holeService()
		                return holeService
		            }
		            func __safeDI_holeServiceBuilder_Outer(up: Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(seamB: { values in __safeDI_holeServiceBuilder_SeamB(up: up.seamB(values)) })
		            }
		            func __safeDI_holeServiceBuilder_SeamB(up: SeamB.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> SeamB.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(holeService: { scope in __safeDI_holeServiceBuilder_SeamB_holeService(scope, __safeDI_outer_holeServiceBuilder: up.holeService(scope)) })
		            }
		            return Outer(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder_Outer(up: __safeDI_thingServiceBuilder_outer_holeServiceBuilder))
		        }
		        let outer: Outer = __safeDI_outer()
		        let __safeDI_thingServiceBuilder_midWorkerBuilder = __safeDI_thingServiceBuilder.midWorkerBuilder(SafeDIScope_ThingService.midWorkerBuilder_Values(chainToken: chainToken, outer: outer))
		        func __safeDI_midWorkerBuilder() -> Worker {
		            let thing: any ThingService = __safeDI_thingServiceBuilder_midWorkerBuilder.thing(SafeDIScope_ThingService.Worker_Scope.__safeDI_Values())
		            return Worker(thing: thing)
		        }
		        let midWorkerBuilder = Instantiator<Worker>(__safeDI_midWorkerBuilder)
		        self.init(outer: outer, midWorkerBuilder: midWorkerBuilder)
		    }
		}

		extension Mid {
		    public enum __safeDI_Mid_8DEDB719400A4D1E {}
		}
		"""])
		#expect(output.modules["Top"]?.generatedFiles == ["Top.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Other)
		import Other
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension TopRoot {
		    public convenience init() {
		        @Sendable func __safeDI_chainToken() -> ChainToken {
		            ChainToken()
		        }
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        func __safeDI_mid() -> Mid {
		            _ = Mid.__safeDI_Mid_8DEDB719400A4D1E.self // If this line does not compile, compile the code SafeDI generates for module Other into Other: under Bazel, add Other’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope_thing(_ scope: Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Values, chainToken: SendableLazilyInstantiated<ChainToken>) -> any ThingService {
		                func __safeDI_thing() -> ThingImpl {
		                    @Sendable func __safeDI_leafBuilder() -> ChainLeaf {
		                        ChainLeaf(chainToken: chainToken.instance)
		                    }
		                    let leafBuilder = SendableInstantiator<ChainLeaf>(__safeDI_leafBuilder)
		                    return ThingImpl(chainToken: chainToken, leafBuilder: leafBuilder)
		                }
		                let thing: any ThingService = __safeDI_thing()
		                return thing
		            }
		            func __safeDI_thingServiceBuilder_Mid() -> Mid.SafeDIScope_ThingService.__safeDI_Builder<any ThingService> {
		                .init(outer_holeServiceBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Outer() }, midWorkerBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: chainToken) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: SendableLazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService> {
		                .init(workerBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: chainToken) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: SendableLazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<any ThingService> {
		                .init(thing: { scope in __safeDI_thingServiceBuilder_Mid_Worker_Scope_thing(scope, chainToken: chainToken) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Outer() -> Outer.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(seamB: { _ in __safeDI_thingServiceBuilder_Mid_SeamB() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_SeamB() -> SeamB.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(holeService: { values in __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: values.__safeDI_chainToken) })
		            }
		            return Mid(__safeDI_chainToken: chainToken.instance, __safeDI_thingServiceBuilder: __safeDI_thingServiceBuilder_Mid())
		        }
		        let mid: Mid = __safeDI_mid()
		        self.init(chainToken: chainToken, mid: mid)
		    }
		}
		"""])
		try await expectCreationOrderEqualsOneModuleBuild(output, modules: modules, seams: ["seamB"], midBuilders: ["midWorkerBuilder"])
	}

	// MARK: A wrapper read beside a plain memo, inside a `@Sendable` function or through an alias

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsSendableWrapperReadBesidePlainMemo_whenTreeReadsSendableWrapperInsideSendableInstantiator() async {
		// `WrapperReader` is built in a `SendableInstantiator`, so the fill binds the value of `Seam`'s `LazilyInstantiated`
		// rather than the memo, which no `@Sendable` function can capture. The error offers only the wrapper's remedy: a
		// `WrapperReader` that received the value there would read one created where the fill is handed its values struct.
		await assertThrowsMultiModuleError(inModule: "Top", diagnostics: { fixtures in
			"""
			\(fixtures["Top"]!["ThingImpl.swift"]):20:2: error: `WrapperReader` receives `chainToken: SendableLazilyInstantiated<ChainToken>`, which SafeDI hands the builder for `Worker`’s `thing: any ThingService` (`thing` of `thingServiceBuilder`) only as `chainToken: LazilyInstantiated<ChainToken>`, since `Seam`’s tree reads `chainToken` outside a `@Sendable` function and `ThingImpl` receives its instance, `chainToken: ChainToken`. Receive `chainToken: SendableLazilyInstantiated<ChainToken>` wherever that builder’s tree receives `chainToken: ChainToken`.
			\(fixtures["Top"]!["ThingImpl.swift"]):13:2: note: `ThingImpl` receives `chainToken: ChainToken` here.
			\(fixtures["Core"]!["ChainToken.swift"]):13:2: note: `ChainLeaf` receives `chainToken: ChainToken` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.chainTokenModules(thingImpl: Self.thingImplReadingSendableWrapperInside(holder: "SendableInstantiator", readsReader: "instantiate()"), topChainToken: Self.rootSendableChainToken), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsSendableWrapperReadBesidePlainMemo_whenTreeReadsSendableWrapperInsideSendableLazilyInstantiated() async {
		// As above, with `WrapperReader` built in a `SendableLazilyInstantiated`.
		await assertThrowsMultiModuleError(inModule: "Top", diagnostics: { fixtures in
			"""
			\(fixtures["Top"]!["ThingImpl.swift"]):20:2: error: `WrapperReader` receives `chainToken: SendableLazilyInstantiated<ChainToken>`, which SafeDI hands the builder for `Worker`’s `thing: any ThingService` (`thing` of `thingServiceBuilder`) only as `chainToken: LazilyInstantiated<ChainToken>`, since `Seam`’s tree reads `chainToken` outside a `@Sendable` function and `ThingImpl` receives its instance, `chainToken: ChainToken`. Receive `chainToken: SendableLazilyInstantiated<ChainToken>` wherever that builder’s tree receives `chainToken: ChainToken`.
			\(fixtures["Top"]!["ThingImpl.swift"]):13:2: note: `ThingImpl` receives `chainToken: ChainToken` here.
			\(fixtures["Core"]!["ChainToken.swift"]):13:2: note: `ChainLeaf` receives `chainToken: ChainToken` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.chainTokenModules(thingImpl: Self.thingImplReadingSendableWrapperInside(holder: "SendableLazilyInstantiated", readsReader: "instance"), topChainToken: Self.rootSendableChainToken), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsSendableWrapperReadBesidePlainMemo_whenTreeReadsValueInsideSendableInstantiator() async {
		// `ChainLeaf`, which reads the value, is built in a `SendableInstantiator` beside `WrapperReader`, so again the fill binds
		// the memo's value. `ChainLeaf` is the instance's reader, and the type `Seam`'s tree reads the value in, noted once.
		await assertThrowsMultiModuleError(inModule: "Top", diagnostics: { fixtures in
			"""
			\(fixtures["Top"]!["ThingImpl.swift"]):21:2: error: `WrapperReader` receives `chainToken: SendableLazilyInstantiated<ChainToken>`, which SafeDI hands the builder for `Worker`’s `thing: any ThingService` (`thing` of `thingServiceBuilder`) only as `chainToken: LazilyInstantiated<ChainToken>`, since `Seam`’s tree reads `chainToken` outside a `@Sendable` function and `ChainLeaf` receives its instance, `chainToken: ChainToken`. Receive `chainToken: SendableLazilyInstantiated<ChainToken>` wherever that builder’s tree receives `chainToken: ChainToken`.
			\(fixtures["Core"]!["ChainToken.swift"]):13:2: note: `ChainLeaf` receives `chainToken: ChainToken` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.chainTokenModules(thingImpl: Self.thingImplReadingValueInsideSendableInstantiatorBesideSendableWrapper, topChainToken: Self.rootSendableChainToken), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsSendableWrapperReadBesidePlainMemo_whenTreeReadsValueThroughAlias() async {
		// `ThingImpl` receives the value through its alias `token`, which the error names by the property it renames.
		await assertThrowsMultiModuleError(inModule: "Top", diagnostics: { fixtures in
			"""
			\(fixtures["Top"]!["ThingImpl.swift"]):16:2: error: `WrapperReader` receives `chainToken: SendableLazilyInstantiated<ChainToken>`, which SafeDI hands the builder for `Worker`’s `thing: any ThingService` (`thing` of `thingServiceBuilder`) only as `chainToken: LazilyInstantiated<ChainToken>`, since `Seam`’s tree reads `chainToken` outside a `@Sendable` function and `ThingImpl` receives its instance, `chainToken: ChainToken`. Receive `chainToken: ChainToken` on `WrapperReader`, or receive `chainToken: SendableLazilyInstantiated<ChainToken>` wherever that builder’s tree receives `chainToken: ChainToken`.
			\(fixtures["Top"]!["ThingImpl.swift"]):9:2: note: `ThingImpl` receives `chainToken: ChainToken` here.
			\(fixtures["Core"]!["ChainToken.swift"]):13:2: note: `ChainLeaf` receives `chainToken: ChainToken` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.chainTokenModules(thingImpl: Self.thingImplReadingThroughAlias(tokenType: "ChainToken", readerType: "SendableLazilyInstantiated<ChainToken>"), topChainToken: Self.rootSendableChainToken), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillReadsCallersSendableWrapper_whenTreeReadsSendableWrapperBesideReaderInsideSendableInstantiator() async throws {
		// The remedy of the error with `WrapperReader` in a `SendableInstantiator`: `ThingImpl` receives the wrapper too, so the
		// tree reads no value, and the fill reads the caller's wrapper, as inline reads `TopRoot`'s.
		let modules = Self.chainTokenModules(thingImpl: Self.thingImplReadingSendableWrapperBesideReaderInsideSendableInstantiator, topChainToken: Self.rootSendableChainToken)
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

		extension Outer {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let seam: (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>

		            public init(seam: @escaping (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>) {
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
		            _ = Seam.__safeDI_Seam_2AD7242F90FE57C2.self
		            return Seam(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder.seam(SafeDIScope_HoleService.__safeDI_Values()))
		        }
		        let seam: Seam = __safeDI_seam()
		        self.init(seam: seam)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_2A8D23C10A89B5A9 {}
		}

		extension Seam {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct holeService_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let leafBuilder: Instantiator<ChainLeaf>
		            public let __safeDI_chainToken: LazilyInstantiated<ChainToken>

		            init(chainToken: LazilyInstantiated<ChainToken>, leafBuilder: Instantiator<ChainLeaf>) {
		                __safeDI_chainToken = chainToken
		                self.leafBuilder = leafBuilder
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
		        func __safeDI_leafBuilder() -> ChainLeaf {
		            ChainLeaf(chainToken: chainToken.instance)
		        }
		        let leafBuilder = Instantiator<ChainLeaf>(__safeDI_leafBuilder)
		        let holeService: any HoleService = __safeDI_holeServiceBuilder.holeService(SafeDIScope_HoleService.holeService_Values(chainToken: chainToken, leafBuilder: leafBuilder))
		        self.init(leafBuilder: leafBuilder, holeService: holeService)
		    }
		}

		extension Seam {
		    public enum __safeDI_Seam_2AD7242F90FE57C2 {}
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

		extension Mid {
		    nonisolated public enum SafeDIScope_ThingService {
		        nonisolated public struct outer_holeServiceBuilder_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let __safeDI_chainToken: LazilyInstantiated<ChainToken>

		            init(chainToken: LazilyInstantiated<ChainToken>) {
		                __safeDI_chainToken = chainToken
		            }
		        }

		        nonisolated public enum HoleImpl_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let workerBuilder: (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(workerBuilder: @escaping (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.workerBuilder = workerBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.workerBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        nonisolated public enum Worker_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let thing: (__safeDI_Values) -> __safeDI_Built

		                public init(thing: @escaping (__safeDI_Values) -> __safeDI_Built) {
		                    self.thing = thing
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.thing = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let outer_holeServiceBuilder: (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(outer_holeServiceBuilder: @escaping (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.outer_holeServiceBuilder = outer_holeServiceBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.outer_holeServiceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		            }
		        }
		    }

		    // SafeDI counts `ThingService` as `public`: no module it reads declares it narrower. If `ThingService` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping () -> ChainToken, __safeDI_thingServiceBuilder: SafeDIScope_ThingService.__safeDI_Builder<any ThingService>) {
		        let chainToken = LazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        let __safeDI_thingServiceBuilder_outer_holeServiceBuilder = __safeDI_thingServiceBuilder.outer_holeServiceBuilder(SafeDIScope_ThingService.outer_holeServiceBuilder_Values(chainToken: chainToken))
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_2A8D23C10A89B5A9.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_holeServiceBuilder_Seam_holeService(_ scope: Seam.SafeDIScope_HoleService.holeService_Values, __safeDI_outer_holeServiceBuilder: SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>) -> any HoleService {
		                func __safeDI_holeService() -> HoleImpl {
		                    let __safeDI_thingServiceBuilder_workerBuilder = __safeDI_outer_holeServiceBuilder.workerBuilder(SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Values())
		                    func __safeDI_workerBuilder() -> Worker {
		                        let thing: any ThingService = __safeDI_thingServiceBuilder_workerBuilder.thing(SafeDIScope_ThingService.Worker_Scope.__safeDI_Values())
		                        return Worker(thing: thing)
		                    }
		                    let workerBuilder = Instantiator<Worker>(__safeDI_workerBuilder)
		                    return HoleImpl(workerBuilder: workerBuilder)
		                }
		                let holeService: any HoleService = __safeDI_holeService()
		                return holeService
		            }
		            func __safeDI_holeServiceBuilder_Outer(up: Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(seam: { values in __safeDI_holeServiceBuilder_Seam(up: up.seam(values)) })
		            }
		            func __safeDI_holeServiceBuilder_Seam(up: Seam.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(holeService: { scope in __safeDI_holeServiceBuilder_Seam_holeService(scope, __safeDI_outer_holeServiceBuilder: up.holeService(scope)) })
		            }
		            return Outer(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder_Outer(up: __safeDI_thingServiceBuilder_outer_holeServiceBuilder))
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(outer: outer)
		    }
		}

		extension Mid {
		    public enum __safeDI_Mid_C9E7A7B945AD1E35 {}
		}
		"""])
		#expect(output.modules["Top"]?.generatedFiles == ["Top.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Other)
		import Other
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension TopRoot {
		    public convenience init() {
		        @Sendable func __safeDI_chainToken() -> ChainToken {
		            ChainToken()
		        }
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        func __safeDI_mid() -> Mid {
		            _ = Mid.__safeDI_Mid_C9E7A7B945AD1E35.self // If this line does not compile, compile the code SafeDI generates for module Other into Other: under Bazel, add Other’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope_thing(_ scope: Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Values) -> any ThingService {
		                func __safeDI_thing() -> ThingImpl {
		                    @Sendable func __safeDI_readerHolder() -> WrapperReader {
		                        WrapperReader(chainToken: chainToken)
		                    }
		                    let readerHolder = SendableInstantiator<WrapperReader>(__safeDI_readerHolder)
		                    return ThingImpl(chainToken: chainToken, readerHolder: readerHolder)
		                }
		                let thing: any ThingService = __safeDI_thing()
		                return thing
		            }
		            func __safeDI_thingServiceBuilder_Mid() -> Mid.SafeDIScope_ThingService.__safeDI_Builder<any ThingService> {
		                .init(outer_holeServiceBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Outer() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope() -> Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService> {
		                .init(workerBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Worker_Scope() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope() -> Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<any ThingService> {
		                .init(thing: { scope in __safeDI_thingServiceBuilder_Mid_Worker_Scope_thing(scope) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Outer() -> Outer.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(seam: { _ in __safeDI_thingServiceBuilder_Mid_Seam() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Seam() -> Seam.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(holeService: { _ in __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope() })
		            }
		            return Mid(__safeDI_chainToken: chainToken.instance, __safeDI_thingServiceBuilder: __safeDI_thingServiceBuilder_Mid())
		        }
		        let mid: Mid = __safeDI_mid()
		        self.init(chainToken: chainToken, mid: mid)
		    }
		}
		"""])
		try await expectCreationOrderEqualsOneModuleBuild(output, modules: modules, comparingValues: [Self.rootBesideSeamsWorkerProbe])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillReadsSeamsSendableWrapper_whenLeafInsideSendableInstantiatorReceivesSendableWrapper() async throws {
		// The remedy of the error with `ChainLeaf` in a `SendableInstantiator`: `ChainLeaf` receives the wrapper, in `Seam`'s tree
		// too, so no tree reads the value, and `Seam` takes the wrapper, which its values struct carries to the fill.
		let modules = Self.chainTokenModules(thingImpl: Self.thingImplReadingValueInsideSendableInstantiatorBesideSendableWrapper, topChainToken: Self.rootSendableChainToken, chainLeafChainToken: "SendableLazilyInstantiated<ChainToken>")
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

		extension Outer {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let seam: (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>

		            public init(seam: @escaping (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>) {
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
		    public convenience init(__safeDI_chainToken chainToken: SendableLazilyInstantiated<ChainToken>, __safeDI_holeServiceBuilder: SafeDIScope_HoleService.__safeDI_Builder<any HoleService>) {
		        func __safeDI_seam() -> Seam {
		            _ = Seam.__safeDI_Seam_D5997723301E33C6.self
		            return Seam(__safeDI_chainToken: chainToken, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder.seam(SafeDIScope_HoleService.__safeDI_Values()))
		        }
		        let seam: Seam = __safeDI_seam()
		        self.init(seam: seam)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_31C603A9519520BD {}
		}

		extension Seam {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct holeService_Values {
		            public let chainToken: SendableLazilyInstantiated<ChainToken>
		            public let leafBuilder: Instantiator<ChainLeaf>
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
		    public convenience init(__safeDI_chainToken chainToken: SendableLazilyInstantiated<ChainToken>, __safeDI_holeServiceBuilder: SafeDIScope_HoleService.__safeDI_Builder<any HoleService>) {
		        func __safeDI_leafBuilder() -> ChainLeaf {
		            ChainLeaf(chainToken: chainToken)
		        }
		        let leafBuilder = Instantiator<ChainLeaf>(__safeDI_leafBuilder)
		        let holeService: any HoleService = __safeDI_holeServiceBuilder.holeService(SafeDIScope_HoleService.holeService_Values(chainToken: chainToken, leafBuilder: leafBuilder))
		        self.init(leafBuilder: leafBuilder, holeService: holeService)
		    }
		}

		extension Seam {
		    public enum __safeDI_Seam_D5997723301E33C6 {}
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

		extension Mid {
		    nonisolated public enum SafeDIScope_ThingService {
		        nonisolated public struct outer_holeServiceBuilder_Values {
		            public let chainToken: SendableLazilyInstantiated<ChainToken>
		        }

		        nonisolated public enum HoleImpl_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let workerBuilder: (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(workerBuilder: @escaping (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.workerBuilder = workerBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.workerBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        nonisolated public enum Worker_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let thing: (__safeDI_Values) -> __safeDI_Built

		                public init(thing: @escaping (__safeDI_Values) -> __safeDI_Built) {
		                    self.thing = thing
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.thing = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let outer_holeServiceBuilder: (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(outer_holeServiceBuilder: @escaping (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.outer_holeServiceBuilder = outer_holeServiceBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.outer_holeServiceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		            }
		        }
		    }

		    // SafeDI counts `ThingService` as `public`: no module it reads declares it narrower. If `ThingService` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_chainToken chainToken: SendableLazilyInstantiated<ChainToken>, __safeDI_thingServiceBuilder: SafeDIScope_ThingService.__safeDI_Builder<any ThingService>) {
		        let __safeDI_thingServiceBuilder_outer_holeServiceBuilder = __safeDI_thingServiceBuilder.outer_holeServiceBuilder(SafeDIScope_ThingService.outer_holeServiceBuilder_Values(chainToken: chainToken))
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_31C603A9519520BD.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_holeServiceBuilder_Seam_holeService(_ scope: Seam.SafeDIScope_HoleService.holeService_Values, __safeDI_outer_holeServiceBuilder: SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>) -> any HoleService {
		                func __safeDI_holeService() -> HoleImpl {
		                    let __safeDI_thingServiceBuilder_workerBuilder = __safeDI_outer_holeServiceBuilder.workerBuilder(SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Values())
		                    func __safeDI_workerBuilder() -> Worker {
		                        let thing: any ThingService = __safeDI_thingServiceBuilder_workerBuilder.thing(SafeDIScope_ThingService.Worker_Scope.__safeDI_Values())
		                        return Worker(thing: thing)
		                    }
		                    let workerBuilder = Instantiator<Worker>(__safeDI_workerBuilder)
		                    return HoleImpl(workerBuilder: workerBuilder)
		                }
		                let holeService: any HoleService = __safeDI_holeService()
		                return holeService
		            }
		            func __safeDI_holeServiceBuilder_Outer(up: Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(seam: { values in __safeDI_holeServiceBuilder_Seam(up: up.seam(values)) })
		            }
		            func __safeDI_holeServiceBuilder_Seam(up: Seam.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(holeService: { scope in __safeDI_holeServiceBuilder_Seam_holeService(scope, __safeDI_outer_holeServiceBuilder: up.holeService(scope)) })
		            }
		            return Outer(__safeDI_chainToken: chainToken, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder_Outer(up: __safeDI_thingServiceBuilder_outer_holeServiceBuilder))
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(outer: outer)
		    }
		}

		extension Mid {
		    public enum __safeDI_Mid_DFE8B45255806DF4 {}
		}
		"""])
		#expect(output.modules["Top"]?.generatedFiles == ["Top.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Other)
		import Other
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension TopRoot {
		    public convenience init() {
		        @Sendable func __safeDI_chainToken() -> ChainToken {
		            ChainToken()
		        }
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        func __safeDI_mid() -> Mid {
		            _ = Mid.__safeDI_Mid_DFE8B45255806DF4.self // If this line does not compile, compile the code SafeDI generates for module Other into Other: under Bazel, add Other’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope_thing(_ scope: Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Values, chainToken: SendableLazilyInstantiated<ChainToken>) -> any ThingService {
		                func __safeDI_thing() -> ThingImpl {
		                    @Sendable func __safeDI_leafBuilder() -> ChainLeaf {
		                        ChainLeaf(chainToken: chainToken)
		                    }
		                    let leafBuilder = SendableInstantiator<ChainLeaf>(__safeDI_leafBuilder)
		                    let reader = WrapperReader(chainToken: chainToken)
		                    return ThingImpl(leafBuilder: leafBuilder, reader: reader)
		                }
		                let thing: any ThingService = __safeDI_thing()
		                return thing
		            }
		            func __safeDI_thingServiceBuilder_Mid() -> Mid.SafeDIScope_ThingService.__safeDI_Builder<any ThingService> {
		                .init(outer_holeServiceBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Outer() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: SendableLazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService> {
		                .init(workerBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: chainToken) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: SendableLazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<any ThingService> {
		                .init(thing: { scope in __safeDI_thingServiceBuilder_Mid_Worker_Scope_thing(scope, chainToken: chainToken) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Outer() -> Outer.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(seam: { _ in __safeDI_thingServiceBuilder_Mid_Seam() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Seam() -> Seam.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(holeService: { values in __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: values.chainToken) })
		            }
		            return Mid(__safeDI_chainToken: chainToken, __safeDI_thingServiceBuilder: __safeDI_thingServiceBuilder_Mid())
		        }
		        let mid: Mid = __safeDI_mid()
		        self.init(chainToken: chainToken, mid: mid)
		    }
		}
		"""])
		try await expectCreationOrderEqualsOneModuleBuild(output, modules: modules, comparingValues: [Self.rootBesideSeamsWorkerProbe])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillTakesLazyMemo_whenTreeReadsValueThroughAlias() async throws {
		// The first remedy of the error with the alias: `WrapperReader` receives the value, which the fill reads from `Seam`'s
		// memo for the alias too.
		let modules = Self.chainTokenModules(thingImpl: Self.thingImplReadingThroughAlias(tokenType: "ChainToken", readerType: "ChainToken"), topChainToken: Self.rootSendableChainToken)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		// The alias binds its value under a `#sourceLocation` of its declaration.
		let thingImplPath = try #require(output.modules["Top"]).fixtures["ThingImpl.swift"]
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

		extension Outer {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let seam: (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>

		            public init(seam: @escaping (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>) {
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
		            _ = Seam.__safeDI_Seam_2AD7242F90FE57C2.self
		            return Seam(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder.seam(SafeDIScope_HoleService.__safeDI_Values()))
		        }
		        let seam: Seam = __safeDI_seam()
		        self.init(seam: seam)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_2A8D23C10A89B5A9 {}
		}

		extension Seam {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct holeService_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let leafBuilder: Instantiator<ChainLeaf>
		            public let __safeDI_chainToken: LazilyInstantiated<ChainToken>

		            init(chainToken: LazilyInstantiated<ChainToken>, leafBuilder: Instantiator<ChainLeaf>) {
		                __safeDI_chainToken = chainToken
		                self.leafBuilder = leafBuilder
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
		        func __safeDI_leafBuilder() -> ChainLeaf {
		            ChainLeaf(chainToken: chainToken.instance)
		        }
		        let leafBuilder = Instantiator<ChainLeaf>(__safeDI_leafBuilder)
		        let holeService: any HoleService = __safeDI_holeServiceBuilder.holeService(SafeDIScope_HoleService.holeService_Values(chainToken: chainToken, leafBuilder: leafBuilder))
		        self.init(leafBuilder: leafBuilder, holeService: holeService)
		    }
		}

		extension Seam {
		    public enum __safeDI_Seam_2AD7242F90FE57C2 {}
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

		extension Mid {
		    nonisolated public enum SafeDIScope_ThingService {
		        nonisolated public struct outer_holeServiceBuilder_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let __safeDI_chainToken: LazilyInstantiated<ChainToken>

		            init(chainToken: LazilyInstantiated<ChainToken>) {
		                __safeDI_chainToken = chainToken
		            }
		        }

		        nonisolated public enum HoleImpl_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let workerBuilder: (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(workerBuilder: @escaping (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.workerBuilder = workerBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.workerBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        nonisolated public enum Worker_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let thing: (__safeDI_Values) -> __safeDI_Built

		                public init(thing: @escaping (__safeDI_Values) -> __safeDI_Built) {
		                    self.thing = thing
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.thing = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let outer_holeServiceBuilder: (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(outer_holeServiceBuilder: @escaping (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.outer_holeServiceBuilder = outer_holeServiceBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.outer_holeServiceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		            }
		        }
		    }

		    // SafeDI counts `ThingService` as `public`: no module it reads declares it narrower. If `ThingService` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping () -> ChainToken, __safeDI_thingServiceBuilder: SafeDIScope_ThingService.__safeDI_Builder<any ThingService>) {
		        let chainToken = LazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        let __safeDI_thingServiceBuilder_outer_holeServiceBuilder = __safeDI_thingServiceBuilder.outer_holeServiceBuilder(SafeDIScope_ThingService.outer_holeServiceBuilder_Values(chainToken: chainToken))
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_2A8D23C10A89B5A9.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_holeServiceBuilder_Seam_holeService(_ scope: Seam.SafeDIScope_HoleService.holeService_Values, __safeDI_outer_holeServiceBuilder: SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>) -> any HoleService {
		                func __safeDI_holeService() -> HoleImpl {
		                    let __safeDI_thingServiceBuilder_workerBuilder = __safeDI_outer_holeServiceBuilder.workerBuilder(SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Values())
		                    func __safeDI_workerBuilder() -> Worker {
		                        let thing: any ThingService = __safeDI_thingServiceBuilder_workerBuilder.thing(SafeDIScope_ThingService.Worker_Scope.__safeDI_Values())
		                        return Worker(thing: thing)
		                    }
		                    let workerBuilder = Instantiator<Worker>(__safeDI_workerBuilder)
		                    return HoleImpl(workerBuilder: workerBuilder)
		                }
		                let holeService: any HoleService = __safeDI_holeService()
		                return holeService
		            }
		            func __safeDI_holeServiceBuilder_Outer(up: Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(seam: { values in __safeDI_holeServiceBuilder_Seam(up: up.seam(values)) })
		            }
		            func __safeDI_holeServiceBuilder_Seam(up: Seam.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(holeService: { scope in __safeDI_holeServiceBuilder_Seam_holeService(scope, __safeDI_outer_holeServiceBuilder: up.holeService(scope)) })
		            }
		            return Outer(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder_Outer(up: __safeDI_thingServiceBuilder_outer_holeServiceBuilder))
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(outer: outer)
		    }
		}

		extension Mid {
		    public enum __safeDI_Mid_C9E7A7B945AD1E35 {}
		}
		"""])
		#expect(output.modules["Top"]?.generatedFiles == ["Top.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Other)
		import Other
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension TopRoot {
		    public convenience init() {
		        @Sendable func __safeDI_chainToken() -> ChainToken {
		            ChainToken()
		        }
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        func __safeDI_mid() -> Mid {
		            _ = Mid.__safeDI_Mid_C9E7A7B945AD1E35.self // If this line does not compile, compile the code SafeDI generates for module Other into Other: under Bazel, add Other’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope_thing(_ scope: Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Values, chainToken: LazilyInstantiated<ChainToken>) -> any ThingService {
		                func __safeDI_thing() -> ThingImpl {
		                    #sourceLocation(file: "\(thingImplPath)", line: 9)
		                    let token: ChainToken = chainToken.instance
		                    #sourceLocation()
		                    let reader = WrapperReader(chainToken: chainToken.instance)
		                    return ThingImpl(token: token, reader: reader)
		                }
		                let thing: any ThingService = __safeDI_thing()
		                return thing
		            }
		            func __safeDI_thingServiceBuilder_Mid() -> Mid.SafeDIScope_ThingService.__safeDI_Builder<any ThingService> {
		                .init(outer_holeServiceBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Outer() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: LazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService> {
		                .init(workerBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: chainToken) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: LazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<any ThingService> {
		                .init(thing: { scope in __safeDI_thingServiceBuilder_Mid_Worker_Scope_thing(scope, chainToken: chainToken) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Outer() -> Outer.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(seam: { _ in __safeDI_thingServiceBuilder_Mid_Seam() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Seam() -> Seam.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(holeService: { values in __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: values.__safeDI_chainToken) })
		            }
		            return Mid(__safeDI_chainToken: chainToken.instance, __safeDI_thingServiceBuilder: __safeDI_thingServiceBuilder_Mid())
		        }
		        let mid: Mid = __safeDI_mid()
		        self.init(chainToken: chainToken, mid: mid)
		    }
		}
		"""])
		try await expectCreationOrderEqualsOneModuleBuild(output, modules: modules, comparingValues: [Self.rootBesideSeamsWorkerProbe])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillReadsCallersSendableWrapper_whenTreeReadsSendableWrapperThroughAlias() async throws {
		// The second remedy of the error with the alias: the alias renames the wrapper, so the tree reads no value.
		let modules = Self.chainTokenModules(thingImpl: Self.thingImplReadingThroughAlias(tokenType: "SendableLazilyInstantiated<ChainToken>", readerType: "SendableLazilyInstantiated<ChainToken>"), topChainToken: Self.rootSendableChainToken)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		// The alias binds its value under a `#sourceLocation` of its declaration.
		let thingImplPath = try #require(output.modules["Top"]).fixtures["ThingImpl.swift"]
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

		extension Outer {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let seam: (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>

		            public init(seam: @escaping (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>) {
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
		            _ = Seam.__safeDI_Seam_2AD7242F90FE57C2.self
		            return Seam(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder.seam(SafeDIScope_HoleService.__safeDI_Values()))
		        }
		        let seam: Seam = __safeDI_seam()
		        self.init(seam: seam)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_2A8D23C10A89B5A9 {}
		}

		extension Seam {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct holeService_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let leafBuilder: Instantiator<ChainLeaf>
		            public let __safeDI_chainToken: LazilyInstantiated<ChainToken>

		            init(chainToken: LazilyInstantiated<ChainToken>, leafBuilder: Instantiator<ChainLeaf>) {
		                __safeDI_chainToken = chainToken
		                self.leafBuilder = leafBuilder
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
		        func __safeDI_leafBuilder() -> ChainLeaf {
		            ChainLeaf(chainToken: chainToken.instance)
		        }
		        let leafBuilder = Instantiator<ChainLeaf>(__safeDI_leafBuilder)
		        let holeService: any HoleService = __safeDI_holeServiceBuilder.holeService(SafeDIScope_HoleService.holeService_Values(chainToken: chainToken, leafBuilder: leafBuilder))
		        self.init(leafBuilder: leafBuilder, holeService: holeService)
		    }
		}

		extension Seam {
		    public enum __safeDI_Seam_2AD7242F90FE57C2 {}
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

		extension Mid {
		    nonisolated public enum SafeDIScope_ThingService {
		        nonisolated public struct outer_holeServiceBuilder_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let __safeDI_chainToken: LazilyInstantiated<ChainToken>

		            init(chainToken: LazilyInstantiated<ChainToken>) {
		                __safeDI_chainToken = chainToken
		            }
		        }

		        nonisolated public enum HoleImpl_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let workerBuilder: (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(workerBuilder: @escaping (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.workerBuilder = workerBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.workerBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        nonisolated public enum Worker_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let thing: (__safeDI_Values) -> __safeDI_Built

		                public init(thing: @escaping (__safeDI_Values) -> __safeDI_Built) {
		                    self.thing = thing
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.thing = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let outer_holeServiceBuilder: (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(outer_holeServiceBuilder: @escaping (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.outer_holeServiceBuilder = outer_holeServiceBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.outer_holeServiceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		            }
		        }
		    }

		    // SafeDI counts `ThingService` as `public`: no module it reads declares it narrower. If `ThingService` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping () -> ChainToken, __safeDI_thingServiceBuilder: SafeDIScope_ThingService.__safeDI_Builder<any ThingService>) {
		        let chainToken = LazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        let __safeDI_thingServiceBuilder_outer_holeServiceBuilder = __safeDI_thingServiceBuilder.outer_holeServiceBuilder(SafeDIScope_ThingService.outer_holeServiceBuilder_Values(chainToken: chainToken))
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_2A8D23C10A89B5A9.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_holeServiceBuilder_Seam_holeService(_ scope: Seam.SafeDIScope_HoleService.holeService_Values, __safeDI_outer_holeServiceBuilder: SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>) -> any HoleService {
		                func __safeDI_holeService() -> HoleImpl {
		                    let __safeDI_thingServiceBuilder_workerBuilder = __safeDI_outer_holeServiceBuilder.workerBuilder(SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Values())
		                    func __safeDI_workerBuilder() -> Worker {
		                        let thing: any ThingService = __safeDI_thingServiceBuilder_workerBuilder.thing(SafeDIScope_ThingService.Worker_Scope.__safeDI_Values())
		                        return Worker(thing: thing)
		                    }
		                    let workerBuilder = Instantiator<Worker>(__safeDI_workerBuilder)
		                    return HoleImpl(workerBuilder: workerBuilder)
		                }
		                let holeService: any HoleService = __safeDI_holeService()
		                return holeService
		            }
		            func __safeDI_holeServiceBuilder_Outer(up: Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(seam: { values in __safeDI_holeServiceBuilder_Seam(up: up.seam(values)) })
		            }
		            func __safeDI_holeServiceBuilder_Seam(up: Seam.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(holeService: { scope in __safeDI_holeServiceBuilder_Seam_holeService(scope, __safeDI_outer_holeServiceBuilder: up.holeService(scope)) })
		            }
		            return Outer(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder_Outer(up: __safeDI_thingServiceBuilder_outer_holeServiceBuilder))
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(outer: outer)
		    }
		}

		extension Mid {
		    public enum __safeDI_Mid_C9E7A7B945AD1E35 {}
		}
		"""])
		#expect(output.modules["Top"]?.generatedFiles == ["Top.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Other)
		import Other
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension TopRoot {
		    public convenience init() {
		        @Sendable func __safeDI_chainToken() -> ChainToken {
		            ChainToken()
		        }
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        func __safeDI_mid() -> Mid {
		            _ = Mid.__safeDI_Mid_C9E7A7B945AD1E35.self // If this line does not compile, compile the code SafeDI generates for module Other into Other: under Bazel, add Other’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope_thing(_ scope: Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Values) -> any ThingService {
		                func __safeDI_thing() -> ThingImpl {
		                    #sourceLocation(file: "\(thingImplPath)", line: 9)
		                    let token: SendableLazilyInstantiated<ChainToken> = chainToken
		                    #sourceLocation()
		                    let reader = WrapperReader(chainToken: chainToken)
		                    return ThingImpl(token: token, reader: reader)
		                }
		                let thing: any ThingService = __safeDI_thing()
		                return thing
		            }
		            func __safeDI_thingServiceBuilder_Mid() -> Mid.SafeDIScope_ThingService.__safeDI_Builder<any ThingService> {
		                .init(outer_holeServiceBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Outer() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope() -> Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService> {
		                .init(workerBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Worker_Scope() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope() -> Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<any ThingService> {
		                .init(thing: { scope in __safeDI_thingServiceBuilder_Mid_Worker_Scope_thing(scope) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Outer() -> Outer.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(seam: { _ in __safeDI_thingServiceBuilder_Mid_Seam() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Seam() -> Seam.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(holeService: { _ in __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope() })
		            }
		            return Mid(__safeDI_chainToken: chainToken.instance, __safeDI_thingServiceBuilder: __safeDI_thingServiceBuilder_Mid())
		        }
		        let mid: Mid = __safeDI_mid()
		        self.init(chainToken: chainToken, mid: mid)
		    }
		}
		"""])
		try await expectCreationOrderEqualsOneModuleBuild(output, modules: modules, comparingValues: [Self.rootBesideSeamsWorkerProbe])
	}

	// MARK: A wrapper a seam on the route declares, which the fill's tree reads

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsDeclarationHiddenByField_whenOnlyPassingUpSeamDeclaresSendableWrapperTreeReadsAlone() async {
		// Inline, `WrapperReader` reads `Outer`'s wrapper, which `Seam`'s values struct does not carry: it carries
		// `chainToken: ChainToken`, the parameter of `Seam` that `ChainLeaf` receives.
		await assertThrowsMultiModuleError(inModule: "Top", diagnostics: { fixtures in
			"""
			\(fixtures["Top"]!["ThingImpl.swift"]):15:2: error: `WrapperReader` receives `chainToken: SendableLazilyInstantiated<ChainToken>`, which `Outer` builds where it calls `Seam`, but SafeDI hands the builder for `Worker`’s `thing: any ThingService` (`thing` of `thingServiceBuilder`) only its instance, `chainToken: ChainToken`, which `Seam`’s tree receives. Declare `@Received let chainToken: SendableLazilyInstantiated<ChainToken>` on `Seam`, so SafeDI hands it to the builder.
			\(fixtures["Feature"]!["Seam.swift"]):18:2: note: `Outer` declares `chainToken: SendableLazilyInstantiated<ChainToken>` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.chainTokenModules(thingImpl: Self.thingImplReadingOnlySendableWrapper, outerDeclaresChainToken: true, outerChainToken: "SendableLazilyInstantiated<ChainToken>"), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsDeclarationHiddenByField_whenPassingUpSeamAndRootDeclareSendableWrapperTreeReadsAlone() async {
		// Without the error, the fill would read `TopRoot`'s wrapper where inline reads `Outer`'s.
		await assertThrowsMultiModuleError(inModule: "Top", diagnostics: { fixtures in
			"""
			\(fixtures["Top"]!["ThingImpl.swift"]):15:2: error: `WrapperReader` receives `chainToken: SendableLazilyInstantiated<ChainToken>`, which `Outer` builds where it calls `Seam`, but SafeDI hands the builder for `Worker`’s `thing: any ThingService` (`thing` of `thingServiceBuilder`) only its instance, `chainToken: ChainToken`, which `Seam`’s tree receives. Declare `@Received let chainToken: SendableLazilyInstantiated<ChainToken>` on `Seam`, so SafeDI hands it to the builder.
			\(fixtures["Feature"]!["Seam.swift"]):18:2: note: `Outer` declares `chainToken: SendableLazilyInstantiated<ChainToken>` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.chainTokenModules(thingImpl: Self.thingImplReadingOnlySendableWrapper, topChainToken: Self.rootSendableChainToken, outerDeclaresChainToken: true, outerChainToken: "SendableLazilyInstantiated<ChainToken>", rootDeclaresChainTokenToo: true, midDirectLeaf: true), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsDeclarationHiddenByField_whenPassingUpSeamAndRootDeclareLazyWrapperTreeReadsAlone() async {
		// The same for the plain `LazilyInstantiated`: the check is not of the `Sendable` wrapper alone.
		await assertThrowsMultiModuleError(inModule: "Top", diagnostics: { fixtures in
			"""
			\(fixtures["Top"]!["ThingImpl.swift"]):15:2: error: `WrapperReader` receives `chainToken: LazilyInstantiated<ChainToken>`, which `Outer` builds where it calls `Seam`, but SafeDI hands the builder for `Worker`’s `thing: any ThingService` (`thing` of `thingServiceBuilder`) only its instance, `chainToken: ChainToken`, which `Seam`’s tree receives. Declare `@Received let chainToken: LazilyInstantiated<ChainToken>` on `Seam`, so SafeDI hands it to the builder.
			\(fixtures["Feature"]!["Seam.swift"]):18:2: note: `Outer` declares `chainToken: LazilyInstantiated<ChainToken>` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.chainTokenModules(thingImpl: Self.thingImplReadingOnlyLazyWrapper, outerDeclaresChainToken: true, rootDeclaresChainTokenToo: true), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsDeclarationHiddenByField_whenOnlyCallingSeamDeclaresSendableWrapperTreeReadsAlone() async {
		// `Mid`, the seam whose call the fill is, declares the wrapper above its call of `Outer`.
		await assertThrowsMultiModuleError(inModule: "Top", diagnostics: { fixtures in
			"""
			\(fixtures["Top"]!["ThingImpl.swift"]):15:2: error: `WrapperReader` receives `chainToken: SendableLazilyInstantiated<ChainToken>`, which `Mid` builds where it calls `Outer`, but SafeDI hands the builder for `Worker`’s `thing: any ThingService` (`thing` of `thingServiceBuilder`) only its instance, `chainToken: ChainToken`, which `Seam`’s tree receives. Declare `@Received let chainToken: SendableLazilyInstantiated<ChainToken>` on `Seam`, so SafeDI hands it to the builder.
			\(fixtures["Other"]!["Worker.swift"]):20:2: note: `Mid` declares `chainToken: SendableLazilyInstantiated<ChainToken>` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.chainTokenModules(thingImpl: Self.thingImplReadingOnlySendableWrapper, midChainToken: "SendableLazilyInstantiated<ChainToken>"), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsDeclarationHiddenByField_whenPassingUpSeamDeclaresSendableWrapperTreeReadsBesideValue() async {
		// The finding precedes the one about a memo of another kind: the field that hides `Outer`'s wrapper causes both.
		await assertThrowsMultiModuleError(inModule: "Top", diagnostics: { fixtures in
			"""
			\(fixtures["Top"]!["ThingImpl.swift"]):20:2: error: `WrapperReader` receives `chainToken: SendableLazilyInstantiated<ChainToken>`, which `Outer` builds where it calls `Seam`, but SafeDI hands the builder for `Worker`’s `thing: any ThingService` (`thing` of `thingServiceBuilder`) only its instance, `chainToken: ChainToken`, which `Seam`’s tree receives. Declare `@Received let chainToken: SendableLazilyInstantiated<ChainToken>` on `Seam`, so SafeDI hands it to the builder.
			\(fixtures["Feature"]!["Seam.swift"]):18:2: note: `Outer` declares `chainToken: SendableLazilyInstantiated<ChainToken>` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.chainTokenModules(thingImpl: Self.thingImplReadingValueAndSendableWrapper, outerDeclaresChainToken: true, outerChainToken: "SendableLazilyInstantiated<ChainToken>"), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsDeclarationHiddenByField_whenPassingUpSeamAndRootDeclareSendableWrapperTreeReadsBesideValue() async {
		// As above, with `TopRoot` declaring the wrapper too and `Mid` reading the value through a leaf of its own.
		await assertThrowsMultiModuleError(inModule: "Top", diagnostics: { fixtures in
			"""
			\(fixtures["Top"]!["ThingImpl.swift"]):20:2: error: `WrapperReader` receives `chainToken: SendableLazilyInstantiated<ChainToken>`, which `Outer` builds where it calls `Seam`, but SafeDI hands the builder for `Worker`’s `thing: any ThingService` (`thing` of `thingServiceBuilder`) only its instance, `chainToken: ChainToken`, which `Seam`’s tree receives. Declare `@Received let chainToken: SendableLazilyInstantiated<ChainToken>` on `Seam`, so SafeDI hands it to the builder.
			\(fixtures["Feature"]!["Seam.swift"]):18:2: note: `Outer` declares `chainToken: SendableLazilyInstantiated<ChainToken>` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.chainTokenModules(thingImpl: Self.thingImplReadingValueAndSendableWrapper, topChainToken: Self.rootSendableChainToken, outerDeclaresChainToken: true, outerChainToken: "SendableLazilyInstantiated<ChainToken>", rootDeclaresChainTokenToo: true, midDirectLeaf: true), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsDeclarationHiddenByField_whenModuleFillsPlaceOfSeamThatFillsItsOwnPlaceAndPassingUpSeamDeclaresSendableWrapper() async {
		// `Feature` fills `Seam`'s `holeService` itself, so `Top` fills `Worker`'s `thing`, a place of `Seam`'s own tree that
		// `Outer` passes up, with no fill between: the place's own field hides `Outer`'s wrapper.
		await assertThrowsMultiModuleError(inModule: "Top", diagnostics: { fixtures in
			"""
			\(fixtures["Top"]!["ThingImpl.swift"]):15:2: error: `WrapperReader` receives `chainToken: SendableLazilyInstantiated<ChainToken>`, which `Outer` builds where it calls `Seam`, but SafeDI hands the builder for `Worker`’s `thing: any ThingService` (`thing` of `thingServiceBuilder`) only its instance, `chainToken: ChainToken`, which `Seam`’s tree receives. Declare `@Received let chainToken: SendableLazilyInstantiated<ChainToken>` on `Seam`, so SafeDI hands it to the builder.
			\(fixtures["Feature"]!["Seam.swift"]):18:2: note: `Outer` declares `chainToken: SendableLazilyInstantiated<ChainToken>` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.chainTokenModules(thingImpl: Self.thingImplReadingOnlySendableWrapper, outerDeclaresChainToken: true, outerChainToken: "SendableLazilyInstantiated<ChainToken>", featureFillsHoleService: true), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillReadsPassingUpSeamsSendableWrapper_whenSeamReceivesWrapperPassingUpSeamDeclares() async throws {
		// The remedy of the error above: `Seam` receives `Outer`'s wrapper, which its values struct then carries.
		let modules = Self.chainTokenModules(thingImpl: Self.thingImplReadingOnlySendableWrapper, outerDeclaresChainToken: true, outerChainToken: "SendableLazilyInstantiated<ChainToken>", seamChainToken: "SendableLazilyInstantiated<ChainToken>")
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

		extension Outer {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let seam: (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>

		            public init(seam: @escaping (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>) {
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
		    public convenience init(__safeDI_holeServiceBuilder: SafeDIScope_HoleService.__safeDI_Builder<any HoleService>) {
		        @Sendable nonisolated func __safeDI_chainToken() -> ChainToken {
		            ChainToken()
		        }
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        func __safeDI_seam() -> Seam {
		            _ = Seam.__safeDI_Seam_D5997723301E33C6.self
		            return Seam(__safeDI_chainToken: chainToken, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder.seam(SafeDIScope_HoleService.__safeDI_Values()))
		        }
		        let seam: Seam = __safeDI_seam()
		        self.init(chainToken: chainToken, seam: seam)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_03CDAF456B5F899F {}
		}

		extension Seam {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct holeService_Values {
		            public let chainToken: SendableLazilyInstantiated<ChainToken>
		            public let leafBuilder: Instantiator<ChainLeaf>
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
		    public convenience init(__safeDI_chainToken chainToken: SendableLazilyInstantiated<ChainToken>, __safeDI_holeServiceBuilder: SafeDIScope_HoleService.__safeDI_Builder<any HoleService>) {
		        func __safeDI_leafBuilder() -> ChainLeaf {
		            ChainLeaf(chainToken: chainToken.instance)
		        }
		        let leafBuilder = Instantiator<ChainLeaf>(__safeDI_leafBuilder)
		        let holeService: any HoleService = __safeDI_holeServiceBuilder.holeService(SafeDIScope_HoleService.holeService_Values(chainToken: chainToken, leafBuilder: leafBuilder))
		        self.init(chainToken: chainToken, leafBuilder: leafBuilder, holeService: holeService)
		    }
		}

		extension Seam {
		    public enum __safeDI_Seam_D5997723301E33C6 {}
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

		extension Mid {
		    nonisolated public enum SafeDIScope_ThingService {
		        nonisolated public struct __safeDI_Values: Sendable {}

		        nonisolated public enum HoleImpl_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let workerBuilder: (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(workerBuilder: @escaping (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.workerBuilder = workerBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.workerBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        nonisolated public enum Worker_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let thing: (__safeDI_Values) -> __safeDI_Built

		                public init(thing: @escaping (__safeDI_Values) -> __safeDI_Built) {
		                    self.thing = thing
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.thing = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let outer_holeServiceBuilder: (__safeDI_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(outer_holeServiceBuilder: @escaping (__safeDI_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.outer_holeServiceBuilder = outer_holeServiceBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.outer_holeServiceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		            }
		        }
		    }

		    // SafeDI counts `ThingService` as `public`: no module it reads declares it narrower. If `ThingService` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_thingServiceBuilder: SafeDIScope_ThingService.__safeDI_Builder<any ThingService>) {
		        let __safeDI_thingServiceBuilder_outer_holeServiceBuilder = __safeDI_thingServiceBuilder.outer_holeServiceBuilder(SafeDIScope_ThingService.__safeDI_Values())
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_03CDAF456B5F899F.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_holeServiceBuilder_Seam_holeService(_ scope: Seam.SafeDIScope_HoleService.holeService_Values, __safeDI_outer_holeServiceBuilder: SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>) -> any HoleService {
		                func __safeDI_holeService() -> HoleImpl {
		                    let __safeDI_thingServiceBuilder_workerBuilder = __safeDI_outer_holeServiceBuilder.workerBuilder(SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Values())
		                    func __safeDI_workerBuilder() -> Worker {
		                        let thing: any ThingService = __safeDI_thingServiceBuilder_workerBuilder.thing(SafeDIScope_ThingService.Worker_Scope.__safeDI_Values())
		                        return Worker(thing: thing)
		                    }
		                    let workerBuilder = Instantiator<Worker>(__safeDI_workerBuilder)
		                    return HoleImpl(workerBuilder: workerBuilder)
		                }
		                let holeService: any HoleService = __safeDI_holeService()
		                return holeService
		            }
		            func __safeDI_holeServiceBuilder_Outer(up: Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(seam: { values in __safeDI_holeServiceBuilder_Seam(up: up.seam(values)) })
		            }
		            func __safeDI_holeServiceBuilder_Seam(up: Seam.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(holeService: { scope in __safeDI_holeServiceBuilder_Seam_holeService(scope, __safeDI_outer_holeServiceBuilder: up.holeService(scope)) })
		            }
		            return Outer(__safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder_Outer(up: __safeDI_thingServiceBuilder_outer_holeServiceBuilder))
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(outer: outer)
		    }
		}

		extension Mid {
		    public enum __safeDI_Mid_F1AC02614C2E6CBE {}
		}
		"""])
		#expect(output.modules["Top"]?.generatedFiles == ["Top.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Other)
		import Other
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension TopRoot {
		    public convenience init() {
		        func __safeDI_mid() -> Mid {
		            _ = Mid.__safeDI_Mid_F1AC02614C2E6CBE.self // If this line does not compile, compile the code SafeDI generates for module Other into Other: under Bazel, add Other’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope_thing(_ scope: Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Values, chainToken: SendableLazilyInstantiated<ChainToken>) -> any ThingService {
		                func __safeDI_thing() -> ThingImpl {
		                    let reader = WrapperReader(chainToken: chainToken)
		                    return ThingImpl(reader: reader)
		                }
		                let thing: any ThingService = __safeDI_thing()
		                return thing
		            }
		            func __safeDI_thingServiceBuilder_Mid() -> Mid.SafeDIScope_ThingService.__safeDI_Builder<any ThingService> {
		                .init(outer_holeServiceBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Outer() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: SendableLazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService> {
		                .init(workerBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: chainToken) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: SendableLazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<any ThingService> {
		                .init(thing: { scope in __safeDI_thingServiceBuilder_Mid_Worker_Scope_thing(scope, chainToken: chainToken) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Outer() -> Outer.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(seam: { _ in __safeDI_thingServiceBuilder_Mid_Seam() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Seam() -> Seam.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(holeService: { values in __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: values.chainToken) })
		            }
		            return Mid(__safeDI_thingServiceBuilder: __safeDI_thingServiceBuilder_Mid())
		        }
		        let mid: Mid = __safeDI_mid()
		        self.init(mid: mid)
		    }
		}
		"""])
		try await expectCreationOrderEqualsOneModuleBuild(output, modules: modules, comparingValues: [Self.rootBesideSeamsWorkerProbe])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsDeclarationHiddenByField_whenOnlyPassingUpSeamDeclaresSendableWrapperTreeReadsOnlyIfAvailable() async {
		// `WrapperReader` receives the wrapper only if available: the remedy still declares the required wrapper on `Seam`, since
		// `Seam`'s tree receives its instance, which an optional wrapper would not provide.
		await assertThrowsMultiModuleError(inModule: "Top", diagnostics: { fixtures in
			"""
			\(fixtures["Top"]!["ThingImpl.swift"]):15:2: error: `WrapperReader` receives `chainToken: SendableLazilyInstantiated<ChainToken>?`, which `Outer` builds where it calls `Seam`, but SafeDI hands the builder for `Worker`’s `thing: any ThingService` (`thing` of `thingServiceBuilder`) only its instance, `chainToken: ChainToken`, which `Seam`’s tree receives. Declare `@Received let chainToken: SendableLazilyInstantiated<ChainToken>` on `Seam`, so SafeDI hands it to the builder.
			\(fixtures["Feature"]!["Seam.swift"]):18:2: note: `Outer` declares `chainToken: SendableLazilyInstantiated<ChainToken>` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.chainTokenModules(thingImpl: Self.thingImplReadingOnlySendableWrapperOnlyIfAvailable, outerDeclaresChainToken: true, outerChainToken: "SendableLazilyInstantiated<ChainToken>"), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillReadsPassingUpSeamsSendableWrapper_whenSeamReceivesWrapperTreeReadsOnlyIfAvailable() async throws {
		// The remedy of the error above: `Seam` receives `Outer`'s wrapper, which `WrapperReader` reads only if available.
		let modules = Self.chainTokenModules(thingImpl: Self.thingImplReadingOnlySendableWrapperOnlyIfAvailable, outerDeclaresChainToken: true, outerChainToken: "SendableLazilyInstantiated<ChainToken>", seamChainToken: "SendableLazilyInstantiated<ChainToken>")
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

		extension Outer {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let seam: (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>

		            public init(seam: @escaping (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>) {
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
		    public convenience init(__safeDI_holeServiceBuilder: SafeDIScope_HoleService.__safeDI_Builder<any HoleService>) {
		        @Sendable nonisolated func __safeDI_chainToken() -> ChainToken {
		            ChainToken()
		        }
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        func __safeDI_seam() -> Seam {
		            _ = Seam.__safeDI_Seam_D5997723301E33C6.self
		            return Seam(__safeDI_chainToken: chainToken, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder.seam(SafeDIScope_HoleService.__safeDI_Values()))
		        }
		        let seam: Seam = __safeDI_seam()
		        self.init(chainToken: chainToken, seam: seam)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_03CDAF456B5F899F {}
		}

		extension Seam {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct holeService_Values {
		            public let chainToken: SendableLazilyInstantiated<ChainToken>
		            public let leafBuilder: Instantiator<ChainLeaf>
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
		    public convenience init(__safeDI_chainToken chainToken: SendableLazilyInstantiated<ChainToken>, __safeDI_holeServiceBuilder: SafeDIScope_HoleService.__safeDI_Builder<any HoleService>) {
		        func __safeDI_leafBuilder() -> ChainLeaf {
		            ChainLeaf(chainToken: chainToken.instance)
		        }
		        let leafBuilder = Instantiator<ChainLeaf>(__safeDI_leafBuilder)
		        let holeService: any HoleService = __safeDI_holeServiceBuilder.holeService(SafeDIScope_HoleService.holeService_Values(chainToken: chainToken, leafBuilder: leafBuilder))
		        self.init(chainToken: chainToken, leafBuilder: leafBuilder, holeService: holeService)
		    }
		}

		extension Seam {
		    public enum __safeDI_Seam_D5997723301E33C6 {}
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

		extension Mid {
		    nonisolated public enum SafeDIScope_ThingService {
		        nonisolated public struct __safeDI_Values: Sendable {}

		        nonisolated public enum HoleImpl_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let workerBuilder: (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(workerBuilder: @escaping (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.workerBuilder = workerBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.workerBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        nonisolated public enum Worker_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let thing: (__safeDI_Values) -> __safeDI_Built

		                public init(thing: @escaping (__safeDI_Values) -> __safeDI_Built) {
		                    self.thing = thing
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.thing = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let outer_holeServiceBuilder: (__safeDI_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(outer_holeServiceBuilder: @escaping (__safeDI_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.outer_holeServiceBuilder = outer_holeServiceBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.outer_holeServiceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		            }
		        }
		    }

		    // SafeDI counts `ThingService` as `public`: no module it reads declares it narrower. If `ThingService` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_thingServiceBuilder: SafeDIScope_ThingService.__safeDI_Builder<any ThingService>) {
		        let __safeDI_thingServiceBuilder_outer_holeServiceBuilder = __safeDI_thingServiceBuilder.outer_holeServiceBuilder(SafeDIScope_ThingService.__safeDI_Values())
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_03CDAF456B5F899F.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_holeServiceBuilder_Seam_holeService(_ scope: Seam.SafeDIScope_HoleService.holeService_Values, __safeDI_outer_holeServiceBuilder: SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>) -> any HoleService {
		                func __safeDI_holeService() -> HoleImpl {
		                    let __safeDI_thingServiceBuilder_workerBuilder = __safeDI_outer_holeServiceBuilder.workerBuilder(SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Values())
		                    func __safeDI_workerBuilder() -> Worker {
		                        let thing: any ThingService = __safeDI_thingServiceBuilder_workerBuilder.thing(SafeDIScope_ThingService.Worker_Scope.__safeDI_Values())
		                        return Worker(thing: thing)
		                    }
		                    let workerBuilder = Instantiator<Worker>(__safeDI_workerBuilder)
		                    return HoleImpl(workerBuilder: workerBuilder)
		                }
		                let holeService: any HoleService = __safeDI_holeService()
		                return holeService
		            }
		            func __safeDI_holeServiceBuilder_Outer(up: Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(seam: { values in __safeDI_holeServiceBuilder_Seam(up: up.seam(values)) })
		            }
		            func __safeDI_holeServiceBuilder_Seam(up: Seam.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(holeService: { scope in __safeDI_holeServiceBuilder_Seam_holeService(scope, __safeDI_outer_holeServiceBuilder: up.holeService(scope)) })
		            }
		            return Outer(__safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder_Outer(up: __safeDI_thingServiceBuilder_outer_holeServiceBuilder))
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(outer: outer)
		    }
		}

		extension Mid {
		    public enum __safeDI_Mid_F1AC02614C2E6CBE {}
		}
		"""])
		#expect(output.modules["Top"]?.generatedFiles == ["Top.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Other)
		import Other
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension TopRoot {
		    public convenience init() {
		        func __safeDI_mid() -> Mid {
		            _ = Mid.__safeDI_Mid_F1AC02614C2E6CBE.self // If this line does not compile, compile the code SafeDI generates for module Other into Other: under Bazel, add Other’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope_thing(_ scope: Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Values, chainToken: SendableLazilyInstantiated<ChainToken>) -> any ThingService {
		                func __safeDI_thing() -> ThingImpl {
		                    let reader = WrapperReader(chainToken: chainToken)
		                    return ThingImpl(reader: reader)
		                }
		                let thing: any ThingService = __safeDI_thing()
		                return thing
		            }
		            func __safeDI_thingServiceBuilder_Mid() -> Mid.SafeDIScope_ThingService.__safeDI_Builder<any ThingService> {
		                .init(outer_holeServiceBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Outer() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: SendableLazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService> {
		                .init(workerBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: chainToken) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: SendableLazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<any ThingService> {
		                .init(thing: { scope in __safeDI_thingServiceBuilder_Mid_Worker_Scope_thing(scope, chainToken: chainToken) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Outer() -> Outer.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(seam: { _ in __safeDI_thingServiceBuilder_Mid_Seam() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Seam() -> Seam.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(holeService: { values in __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: values.chainToken) })
		            }
		            return Mid(__safeDI_thingServiceBuilder: __safeDI_thingServiceBuilder_Mid())
		        }
		        let mid: Mid = __safeDI_mid()
		        self.init(mid: mid)
		    }
		}
		"""])
		try await expectCreationOrderEqualsOneModuleBuild(output, modules: modules, comparingValues: [Self.rootBesideSeamsWorkerProbe])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillReadsCallingSeamsSendableWrapper_whenSeamReceivesWrapperCallingSeamDeclares() async throws {
		// The same remedy where `Mid` declares the wrapper.
		let modules = Self.chainTokenModules(thingImpl: Self.thingImplReadingOnlySendableWrapper, midChainToken: "SendableLazilyInstantiated<ChainToken>", seamChainToken: "SendableLazilyInstantiated<ChainToken>")
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

		extension Outer {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let seam: (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>

		            public init(seam: @escaping (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>) {
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
		    public convenience init(__safeDI_chainToken chainToken: SendableLazilyInstantiated<ChainToken>, __safeDI_holeServiceBuilder: SafeDIScope_HoleService.__safeDI_Builder<any HoleService>) {
		        func __safeDI_seam() -> Seam {
		            _ = Seam.__safeDI_Seam_D5997723301E33C6.self
		            return Seam(__safeDI_chainToken: chainToken, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder.seam(SafeDIScope_HoleService.__safeDI_Values()))
		        }
		        let seam: Seam = __safeDI_seam()
		        self.init(seam: seam)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_31C603A9519520BD {}
		}

		extension Seam {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct holeService_Values {
		            public let chainToken: SendableLazilyInstantiated<ChainToken>
		            public let leafBuilder: Instantiator<ChainLeaf>
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
		    public convenience init(__safeDI_chainToken chainToken: SendableLazilyInstantiated<ChainToken>, __safeDI_holeServiceBuilder: SafeDIScope_HoleService.__safeDI_Builder<any HoleService>) {
		        func __safeDI_leafBuilder() -> ChainLeaf {
		            ChainLeaf(chainToken: chainToken.instance)
		        }
		        let leafBuilder = Instantiator<ChainLeaf>(__safeDI_leafBuilder)
		        let holeService: any HoleService = __safeDI_holeServiceBuilder.holeService(SafeDIScope_HoleService.holeService_Values(chainToken: chainToken, leafBuilder: leafBuilder))
		        self.init(chainToken: chainToken, leafBuilder: leafBuilder, holeService: holeService)
		    }
		}

		extension Seam {
		    public enum __safeDI_Seam_D5997723301E33C6 {}
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

		extension Mid {
		    nonisolated public enum SafeDIScope_ThingService {
		        nonisolated public struct outer_holeServiceBuilder_Values {
		            public let chainToken: SendableLazilyInstantiated<ChainToken>
		        }

		        nonisolated public enum HoleImpl_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let workerBuilder: (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(workerBuilder: @escaping (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.workerBuilder = workerBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.workerBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        nonisolated public enum Worker_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let thing: (__safeDI_Values) -> __safeDI_Built

		                public init(thing: @escaping (__safeDI_Values) -> __safeDI_Built) {
		                    self.thing = thing
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.thing = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let outer_holeServiceBuilder: (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(outer_holeServiceBuilder: @escaping (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.outer_holeServiceBuilder = outer_holeServiceBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.outer_holeServiceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		            }
		        }
		    }

		    // SafeDI counts `ThingService` as `public`: no module it reads declares it narrower. If `ThingService` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_thingServiceBuilder: SafeDIScope_ThingService.__safeDI_Builder<any ThingService>) {
		        @Sendable nonisolated func __safeDI_chainToken() -> ChainToken {
		            ChainToken()
		        }
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        let __safeDI_thingServiceBuilder_outer_holeServiceBuilder = __safeDI_thingServiceBuilder.outer_holeServiceBuilder(SafeDIScope_ThingService.outer_holeServiceBuilder_Values(chainToken: chainToken))
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_31C603A9519520BD.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_holeServiceBuilder_Seam_holeService(_ scope: Seam.SafeDIScope_HoleService.holeService_Values, __safeDI_outer_holeServiceBuilder: SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>) -> any HoleService {
		                func __safeDI_holeService() -> HoleImpl {
		                    let __safeDI_thingServiceBuilder_workerBuilder = __safeDI_outer_holeServiceBuilder.workerBuilder(SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Values())
		                    func __safeDI_workerBuilder() -> Worker {
		                        let thing: any ThingService = __safeDI_thingServiceBuilder_workerBuilder.thing(SafeDIScope_ThingService.Worker_Scope.__safeDI_Values())
		                        return Worker(thing: thing)
		                    }
		                    let workerBuilder = Instantiator<Worker>(__safeDI_workerBuilder)
		                    return HoleImpl(workerBuilder: workerBuilder)
		                }
		                let holeService: any HoleService = __safeDI_holeService()
		                return holeService
		            }
		            func __safeDI_holeServiceBuilder_Outer(up: Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(seam: { values in __safeDI_holeServiceBuilder_Seam(up: up.seam(values)) })
		            }
		            func __safeDI_holeServiceBuilder_Seam(up: Seam.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(holeService: { scope in __safeDI_holeServiceBuilder_Seam_holeService(scope, __safeDI_outer_holeServiceBuilder: up.holeService(scope)) })
		            }
		            return Outer(__safeDI_chainToken: chainToken, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder_Outer(up: __safeDI_thingServiceBuilder_outer_holeServiceBuilder))
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(chainToken: chainToken, outer: outer)
		    }
		}

		extension Mid {
		    public enum __safeDI_Mid_A9F294865D25D736 {}
		}
		"""])
		#expect(output.modules["Top"]?.generatedFiles == ["Top.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Other)
		import Other
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension TopRoot {
		    public convenience init() {
		        func __safeDI_mid() -> Mid {
		            _ = Mid.__safeDI_Mid_A9F294865D25D736.self // If this line does not compile, compile the code SafeDI generates for module Other into Other: under Bazel, add Other’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope_thing(_ scope: Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Values, chainToken: SendableLazilyInstantiated<ChainToken>) -> any ThingService {
		                func __safeDI_thing() -> ThingImpl {
		                    let reader = WrapperReader(chainToken: chainToken)
		                    return ThingImpl(reader: reader)
		                }
		                let thing: any ThingService = __safeDI_thing()
		                return thing
		            }
		            func __safeDI_thingServiceBuilder_Mid() -> Mid.SafeDIScope_ThingService.__safeDI_Builder<any ThingService> {
		                .init(outer_holeServiceBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Outer() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: SendableLazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService> {
		                .init(workerBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: chainToken) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: SendableLazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<any ThingService> {
		                .init(thing: { scope in __safeDI_thingServiceBuilder_Mid_Worker_Scope_thing(scope, chainToken: chainToken) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Outer() -> Outer.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(seam: { _ in __safeDI_thingServiceBuilder_Mid_Seam() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Seam() -> Seam.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(holeService: { values in __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: values.chainToken) })
		            }
		            return Mid(__safeDI_thingServiceBuilder: __safeDI_thingServiceBuilder_Mid())
		        }
		        let mid: Mid = __safeDI_mid()
		        self.init(mid: mid)
		    }
		}
		"""])
		try await expectCreationOrderEqualsOneModuleBuild(output, modules: modules, comparingValues: [Self.rootBesideSeamsWorkerProbe])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillReadsSeamsLazyMemo_whenPassingUpSeamAndRootDeclareLazyWrapperTreeReadsBesideValue() async throws {
		// A memo of the wrapper's own kind serves the read: the fill binds `Seam`'s `LazilyInstantiated`, which holds
		// `Outer`'s value, where its tree reads the value, and reads that memo where it reads the wrapper.
		let modules = Self.chainTokenModules(thingImpl: Self.thingImplReadingValueAndLazyWrapper, outerDeclaresChainToken: true, rootDeclaresChainTokenToo: true, midDirectLeaf: true)
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

		extension Outer {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let seam: (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>

		            public init(seam: @escaping (__safeDI_Values) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>) {
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
		    public convenience init(__safeDI_holeServiceBuilder: SafeDIScope_HoleService.__safeDI_Builder<any HoleService>) {
		        func __safeDI_chainToken() -> ChainToken {
		            ChainToken()
		        }
		        let chainToken = LazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        func __safeDI_seam() -> Seam {
		            _ = Seam.__safeDI_Seam_2AD7242F90FE57C2.self
		            return Seam(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder.seam(SafeDIScope_HoleService.__safeDI_Values()))
		        }
		        let seam: Seam = __safeDI_seam()
		        self.init(chainToken: chainToken, seam: seam)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_6E0AB25F1FE9A45C {}
		}

		extension Seam {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct holeService_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let leafBuilder: Instantiator<ChainLeaf>
		            public let __safeDI_chainToken: LazilyInstantiated<ChainToken>

		            init(chainToken: LazilyInstantiated<ChainToken>, leafBuilder: Instantiator<ChainLeaf>) {
		                __safeDI_chainToken = chainToken
		                self.leafBuilder = leafBuilder
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
		        func __safeDI_leafBuilder() -> ChainLeaf {
		            ChainLeaf(chainToken: chainToken.instance)
		        }
		        let leafBuilder = Instantiator<ChainLeaf>(__safeDI_leafBuilder)
		        let holeService: any HoleService = __safeDI_holeServiceBuilder.holeService(SafeDIScope_HoleService.holeService_Values(chainToken: chainToken, leafBuilder: leafBuilder))
		        self.init(leafBuilder: leafBuilder, holeService: holeService)
		    }
		}

		extension Seam {
		    public enum __safeDI_Seam_2AD7242F90FE57C2 {}
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

		extension Mid {
		    nonisolated public enum SafeDIScope_ThingService {
		        nonisolated public struct outer_holeServiceBuilder_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let directLeaf: ChainLeaf
		            public let __safeDI_chainToken: LazilyInstantiated<ChainToken>

		            init(chainToken: LazilyInstantiated<ChainToken>, directLeaf: ChainLeaf) {
		                __safeDI_chainToken = chainToken
		                self.directLeaf = directLeaf
		            }
		        }

		        nonisolated public enum HoleImpl_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let workerBuilder: (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(workerBuilder: @escaping (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.workerBuilder = workerBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.workerBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        nonisolated public enum Worker_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let thing: (__safeDI_Values) -> __safeDI_Built

		                public init(thing: @escaping (__safeDI_Values) -> __safeDI_Built) {
		                    self.thing = thing
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.thing = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let outer_holeServiceBuilder: (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(outer_holeServiceBuilder: @escaping (outer_holeServiceBuilder_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.outer_holeServiceBuilder = outer_holeServiceBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.outer_holeServiceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		            }
		        }
		    }

		    // SafeDI counts `ThingService` as `public`: no module it reads declares it narrower. If `ThingService` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping () -> ChainToken, __safeDI_thingServiceBuilder: SafeDIScope_ThingService.__safeDI_Builder<any ThingService>) {
		        let chainToken = LazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        let directLeaf = ChainLeaf(chainToken: chainToken.instance)
		        let __safeDI_thingServiceBuilder_outer_holeServiceBuilder = __safeDI_thingServiceBuilder.outer_holeServiceBuilder(SafeDIScope_ThingService.outer_holeServiceBuilder_Values(chainToken: chainToken, directLeaf: directLeaf))
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_6E0AB25F1FE9A45C.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_holeServiceBuilder_Seam_holeService(_ scope: Seam.SafeDIScope_HoleService.holeService_Values, __safeDI_outer_holeServiceBuilder: SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>) -> any HoleService {
		                func __safeDI_holeService() -> HoleImpl {
		                    let __safeDI_thingServiceBuilder_workerBuilder = __safeDI_outer_holeServiceBuilder.workerBuilder(SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Values())
		                    func __safeDI_workerBuilder() -> Worker {
		                        let thing: any ThingService = __safeDI_thingServiceBuilder_workerBuilder.thing(SafeDIScope_ThingService.Worker_Scope.__safeDI_Values())
		                        return Worker(thing: thing)
		                    }
		                    let workerBuilder = Instantiator<Worker>(__safeDI_workerBuilder)
		                    return HoleImpl(workerBuilder: workerBuilder)
		                }
		                let holeService: any HoleService = __safeDI_holeService()
		                return holeService
		            }
		            func __safeDI_holeServiceBuilder_Outer(up: Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(seam: { values in __safeDI_holeServiceBuilder_Seam(up: up.seam(values)) })
		            }
		            func __safeDI_holeServiceBuilder_Seam(up: Seam.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Seam.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(holeService: { scope in __safeDI_holeServiceBuilder_Seam_holeService(scope, __safeDI_outer_holeServiceBuilder: up.holeService(scope)) })
		            }
		            return Outer(__safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder_Outer(up: __safeDI_thingServiceBuilder_outer_holeServiceBuilder))
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(directLeaf: directLeaf, outer: outer)
		    }
		}

		extension Mid {
		    public enum __safeDI_Mid_640B18CBC0D766C4 {}
		}
		"""])
		#expect(output.modules["Top"]?.generatedFiles == ["Top.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Other)
		import Other
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension TopRoot {
		    public convenience init() {
		        func __safeDI_chainToken() -> ChainToken {
		            ChainToken()
		        }
		        let chainToken = LazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        func __safeDI_mid() -> Mid {
		            _ = Mid.__safeDI_Mid_640B18CBC0D766C4.self // If this line does not compile, compile the code SafeDI generates for module Other into Other: under Bazel, add Other’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope_thing(_ scope: Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Values, chainToken: LazilyInstantiated<ChainToken>) -> any ThingService {
		                func __safeDI_thing() -> ThingImpl {
		                    let reader = WrapperReader(chainToken: chainToken)
		                    return ThingImpl(chainToken: chainToken.instance, reader: reader)
		                }
		                let thing: any ThingService = __safeDI_thing()
		                return thing
		            }
		            func __safeDI_thingServiceBuilder_Mid() -> Mid.SafeDIScope_ThingService.__safeDI_Builder<any ThingService> {
		                .init(outer_holeServiceBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Outer() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: LazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService> {
		                .init(workerBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: chainToken) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: LazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<any ThingService> {
		                .init(thing: { scope in __safeDI_thingServiceBuilder_Mid_Worker_Scope_thing(scope, chainToken: chainToken) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Outer() -> Outer.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(seam: { _ in __safeDI_thingServiceBuilder_Mid_Seam() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Seam() -> Seam.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(holeService: { values in __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: values.__safeDI_chainToken) })
		            }
		            return Mid(__safeDI_chainToken: chainToken.instance, __safeDI_thingServiceBuilder: __safeDI_thingServiceBuilder_Mid())
		        }
		        let mid: Mid = __safeDI_mid()
		        self.init(chainToken: chainToken, mid: mid)
		    }
		}
		"""])
		try await expectCreationOrderEqualsOneModuleBuild(output, modules: modules, comparingValues: [Self.rootBesideSeamsWorkerProbe])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillTakesSeamsSendableMemo_whenPassingUpSeamDeclaresSendableWrapperTreeReadsBesideValue() async throws {
		// `Outer` declares the wrapper and builds only `SeamB`, which defers `chainToken` `@Sendable`: the fill binds
		// `SeamB`'s `SendableLazilyInstantiated`, a memo of the wrapper's own kind.
		let modules = Self.chainTokenModules(thingImpl: Self.thingImplReadingValueAndSendableWrapper, outerHoldsOnlySeamB: true, outerDeclaresChainToken: true, outerChainToken: "SendableLazilyInstantiated<ChainToken>")
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

		extension Outer {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let seamB: (__safeDI_Values) -> SeamB.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>

		            public init(seamB: @escaping (__safeDI_Values) -> SeamB.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>) {
		                self.seamB = seamB
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.seamB = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    // SafeDI counts `HoleService` as `public`: no module it reads declares it narrower. If `HoleService` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_holeServiceBuilder: SafeDIScope_HoleService.__safeDI_Builder<any HoleService>) {
		        @Sendable nonisolated func __safeDI_chainToken() -> ChainToken {
		            ChainToken()
		        }
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        func __safeDI_seamB() -> SeamB {
		            _ = SeamB.__safeDI_SeamB_DC2838BAE7387202.self
		            return SeamB(__safeDI_chainToken: chainToken.instance, __safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder.seamB(SafeDIScope_HoleService.__safeDI_Values()))
		        }
		        let seamB: SeamB = __safeDI_seamB()
		        self.init(chainToken: chainToken, seamB: seamB)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_7ED071A634563EF4 {}
		}

		extension Seam {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct holeService_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let leafBuilder: Instantiator<ChainLeaf>
		            public let __safeDI_chainToken: LazilyInstantiated<ChainToken>

		            init(chainToken: LazilyInstantiated<ChainToken>, leafBuilder: Instantiator<ChainLeaf>) {
		                __safeDI_chainToken = chainToken
		                self.leafBuilder = leafBuilder
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
		        func __safeDI_leafBuilder() -> ChainLeaf {
		            ChainLeaf(chainToken: chainToken.instance)
		        }
		        let leafBuilder = Instantiator<ChainLeaf>(__safeDI_leafBuilder)
		        let holeService: any HoleService = __safeDI_holeServiceBuilder.holeService(SafeDIScope_HoleService.holeService_Values(chainToken: chainToken, leafBuilder: leafBuilder))
		        self.init(leafBuilder: leafBuilder, holeService: holeService)
		    }
		}

		extension Seam {
		    public enum __safeDI_Seam_2AD7242F90FE57C2 {}
		}

		extension SeamB {
		    nonisolated public enum SafeDIScope_HoleService {
		        nonisolated public struct holeService_Values {
		            public var chainToken: ChainToken { __safeDI_chainToken.instance }
		            public let leafBuilder: SendableInstantiator<ChainLeaf>
		            public let __safeDI_chainToken: SendableLazilyInstantiated<ChainToken>

		            init(chainToken: SendableLazilyInstantiated<ChainToken>, leafBuilder: SendableInstantiator<ChainLeaf>) {
		                __safeDI_chainToken = chainToken
		                self.leafBuilder = leafBuilder
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
		    public convenience init(__safeDI_chainToken: @autoclosure @escaping @Sendable () -> ChainToken, __safeDI_holeServiceBuilder: SafeDIScope_HoleService.__safeDI_Builder<any HoleService>) {
		        let chainToken = SendableLazilyInstantiated<ChainToken>(__safeDI_chainToken)
		        @Sendable nonisolated func __safeDI_leafBuilder() -> ChainLeaf {
		            ChainLeaf(chainToken: chainToken.instance)
		        }
		        let leafBuilder = SendableInstantiator<ChainLeaf>(__safeDI_leafBuilder)
		        let holeService: any HoleService = __safeDI_holeServiceBuilder.holeService(SafeDIScope_HoleService.holeService_Values(chainToken: chainToken, leafBuilder: leafBuilder))
		        self.init(leafBuilder: leafBuilder, holeService: holeService)
		    }
		}

		extension SeamB {
		    public enum __safeDI_SeamB_DC2838BAE7387202 {}
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

		extension Mid {
		    nonisolated public enum SafeDIScope_ThingService {
		        nonisolated public struct __safeDI_Values: Sendable {}

		        nonisolated public enum HoleImpl_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let workerBuilder: (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(workerBuilder: @escaping (__safeDI_Values) -> SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.workerBuilder = workerBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.workerBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        nonisolated public enum Worker_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let thing: (__safeDI_Values) -> __safeDI_Built

		                public init(thing: @escaping (__safeDI_Values) -> __safeDI_Built) {
		                    self.thing = thing
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.thing = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let outer_holeServiceBuilder: (__safeDI_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(outer_holeServiceBuilder: @escaping (__safeDI_Values) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.outer_holeServiceBuilder = outer_holeServiceBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.outer_holeServiceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		            }
		        }
		    }

		    // SafeDI counts `ThingService` as `public`: no module it reads declares it narrower. If `ThingService` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_thingServiceBuilder: SafeDIScope_ThingService.__safeDI_Builder<any ThingService>) {
		        let __safeDI_thingServiceBuilder_outer_holeServiceBuilder = __safeDI_thingServiceBuilder.outer_holeServiceBuilder(SafeDIScope_ThingService.__safeDI_Values())
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_7ED071A634563EF4.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_holeServiceBuilder_SeamB_holeService(_ scope: SeamB.SafeDIScope_HoleService.holeService_Values, __safeDI_outer_holeServiceBuilder: SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>) -> any HoleService {
		                func __safeDI_holeService() -> HoleImpl {
		                    let __safeDI_thingServiceBuilder_workerBuilder = __safeDI_outer_holeServiceBuilder.workerBuilder(SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Values())
		                    func __safeDI_workerBuilder() -> Worker {
		                        let thing: any ThingService = __safeDI_thingServiceBuilder_workerBuilder.thing(SafeDIScope_ThingService.Worker_Scope.__safeDI_Values())
		                        return Worker(thing: thing)
		                    }
		                    let workerBuilder = Instantiator<Worker>(__safeDI_workerBuilder)
		                    return HoleImpl(workerBuilder: workerBuilder)
		                }
		                let holeService: any HoleService = __safeDI_holeService()
		                return holeService
		            }
		            func __safeDI_holeServiceBuilder_Outer(up: Outer.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> Outer.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(seamB: { values in __safeDI_holeServiceBuilder_SeamB(up: up.seamB(values)) })
		            }
		            func __safeDI_holeServiceBuilder_SeamB(up: SeamB.SafeDIScope_HoleService.__safeDI_Builder<SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>>) -> SeamB.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
		                .init(holeService: { scope in __safeDI_holeServiceBuilder_SeamB_holeService(scope, __safeDI_outer_holeServiceBuilder: up.holeService(scope)) })
		            }
		            return Outer(__safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder_Outer(up: __safeDI_thingServiceBuilder_outer_holeServiceBuilder))
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(outer: outer)
		    }
		}

		extension Mid {
		    public enum __safeDI_Mid_8D3AC4D5EAB76257 {}
		}
		"""])
		#expect(output.modules["Top"]?.generatedFiles == ["Top.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Other)
		import Other
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension TopRoot {
		    public convenience init() {
		        func __safeDI_mid() -> Mid {
		            _ = Mid.__safeDI_Mid_8D3AC4D5EAB76257.self // If this line does not compile, compile the code SafeDI generates for module Other into Other: under Bazel, add Other’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope_thing(_ scope: Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Values, chainToken: SendableLazilyInstantiated<ChainToken>) -> any ThingService {
		                func __safeDI_thing() -> ThingImpl {
		                    let reader = WrapperReader(chainToken: chainToken)
		                    return ThingImpl(chainToken: chainToken.instance, reader: reader)
		                }
		                let thing: any ThingService = __safeDI_thing()
		                return thing
		            }
		            func __safeDI_thingServiceBuilder_Mid() -> Mid.SafeDIScope_ThingService.__safeDI_Builder<any ThingService> {
		                .init(outer_holeServiceBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Outer() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: SendableLazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService> {
		                .init(workerBuilder: { _ in __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: chainToken) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Worker_Scope(chainToken: SendableLazilyInstantiated<ChainToken>) -> Mid.SafeDIScope_ThingService.Worker_Scope.__safeDI_Builder<any ThingService> {
		                .init(thing: { scope in __safeDI_thingServiceBuilder_Mid_Worker_Scope_thing(scope, chainToken: chainToken) })
		            }
		            func __safeDI_thingServiceBuilder_Mid_Outer() -> Outer.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(seamB: { _ in __safeDI_thingServiceBuilder_Mid_SeamB() })
		            }
		            func __safeDI_thingServiceBuilder_Mid_SeamB() -> SeamB.SafeDIScope_HoleService.__safeDI_Builder<Mid.SafeDIScope_ThingService.HoleImpl_Scope.__safeDI_Builder<any ThingService>> {
		                .init(holeService: { values in __safeDI_thingServiceBuilder_Mid_HoleImpl_Scope(chainToken: values.__safeDI_chainToken) })
		            }
		            return Mid(__safeDI_thingServiceBuilder: __safeDI_thingServiceBuilder_Mid())
		        }
		        let mid: Mid = __safeDI_mid()
		        self.init(mid: mid)
		    }
		}
		"""])
		try await expectCreationOrderEqualsOneModuleBuild(output, modules: modules, seams: ["seamB"])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `TopRoot`'s declaration of `chainToken` as a `SendableLazilyInstantiated`, for `chainTokenModules`.
	private static let rootSendableChainToken = "@Instantiated let chainToken: SendableLazilyInstantiated<ChainToken>"

	/// A `thingImpl` for `chainTokenModules` that receives `chainToken` and builds `WrapperReader`, which receives the
	/// `SendableLazilyInstantiated` the root declares: `ThingImpl` logs whether the reader's wrapper holds the instance it
	/// was handed, so the creation log compares the values too.
	private static let thingImplReadingValueAndSendableWrapper = """
	@Instantiable(fulfillingAdditionalTypes: [ThingService.self])
	public final class ThingImpl: Instantiable, ThingService {
		public init(chainToken: ChainToken, reader: WrapperReader) {
			self.chainToken = chainToken
			self.reader = reader
			log.append(reader.chainToken.instance === chainToken ? "ThingImpl shares ChainToken" : "ThingImpl holds another ChainToken")
		}
		@Received let chainToken: ChainToken
		@Instantiated let reader: WrapperReader
	}

	@Instantiable
	public final class WrapperReader: Instantiable, Sendable {
		public init(chainToken: SendableLazilyInstantiated<ChainToken>) { self.chainToken = chainToken; log.append("WrapperReader") }
		@Received let chainToken: SendableLazilyInstantiated<ChainToken>
	}
	"""

	/// A `thingImpl` for `chainTokenModules` like `thingImplReadingOnlySendableWrapper`, where `WrapperReader` receives the
	/// `SendableLazilyInstantiated` only if available.
	private static let thingImplReadingOnlySendableWrapperOnlyIfAvailable = """
	@Instantiable(fulfillingAdditionalTypes: [ThingService.self])
	public final class ThingImpl: Instantiable, ThingService {
		public init(reader: WrapperReader) { self.reader = reader; log.append("ThingImpl") }
		@Instantiated let reader: WrapperReader
	}

	@Instantiable
	public final class WrapperReader: Instantiable, Sendable {
		public init(chainToken: SendableLazilyInstantiated<ChainToken>?) { self.chainToken = chainToken; log.append("WrapperReader") }
		@Received(onlyIfAvailable: true) let chainToken: SendableLazilyInstantiated<ChainToken>?
	}
	"""

	/// A `thingImpl` for `chainTokenModules` whose `ThingImpl` receives the `SendableLazilyInstantiated` and builds
	/// `WrapperReader`, which receives it too, in a `SendableInstantiator`: `ThingImpl` builds the reader at once and logs
	/// whether the reader's wrapper holds its own wrapper's instance.
	private static let thingImplReadingSendableWrapperBesideReaderInsideSendableInstantiator = """
	@Instantiable(fulfillingAdditionalTypes: [ThingService.self])
	public final class ThingImpl: Instantiable, ThingService {
		public init(chainToken: SendableLazilyInstantiated<ChainToken>, readerHolder: SendableInstantiator<WrapperReader>) {
			self.chainToken = chainToken
			self.readerHolder = readerHolder
			log.append(readerHolder.instantiate().chainToken.instance === chainToken.instance ? "ThingImpl shares ChainToken" : "ThingImpl holds another ChainToken")
		}
		@Received let chainToken: SendableLazilyInstantiated<ChainToken>
		@Instantiated let readerHolder: SendableInstantiator<WrapperReader>
	}

	@Instantiable
	public final class WrapperReader: Instantiable, Sendable {
		public init(chainToken: SendableLazilyInstantiated<ChainToken>) { self.chainToken = chainToken; log.append("WrapperReader") }
		@Received let chainToken: SendableLazilyInstantiated<ChainToken>
	}
	"""

	/// A `thingImpl` for `chainTokenModules` whose `ThingImpl` builds `ChainLeaf`, which receives `chainToken`, in a
	/// `SendableInstantiator`, and `WrapperReader`, which receives the `SendableLazilyInstantiated`. `ThingImpl` builds a leaf
	/// at once.
	private static let thingImplReadingValueInsideSendableInstantiatorBesideSendableWrapper = """
	@Instantiable(fulfillingAdditionalTypes: [ThingService.self])
	public final class ThingImpl: Instantiable, ThingService {
		public init(leafBuilder: SendableInstantiator<ChainLeaf>, reader: WrapperReader) {
			self.leafBuilder = leafBuilder
			self.reader = reader
			_ = leafBuilder.instantiate()
			log.append("ThingImpl")
		}
		@Instantiated let leafBuilder: SendableInstantiator<ChainLeaf>
		@Instantiated let reader: WrapperReader
	}

	@Instantiable
	public final class WrapperReader: Instantiable, Sendable {
		public init(chainToken: SendableLazilyInstantiated<ChainToken>) { self.chainToken = chainToken; log.append("WrapperReader") }
		@Received let chainToken: SendableLazilyInstantiated<ChainToken>
	}
	"""

	/// A `thingImpl` for `chainTokenModules` whose `ThingImpl` receives `chainToken` through its alias `token`, of type
	/// `tokenType`, and builds `WrapperReader`, which receives `chainToken` as `readerType`.
	private static func thingImplReadingThroughAlias(tokenType: String, readerType: String) -> String {
		"""
		@Instantiable(fulfillingAdditionalTypes: [ThingService.self])
		public final class ThingImpl: Instantiable, ThingService {
			public init(token: \(tokenType), reader: WrapperReader) { self.token = token; self.reader = reader; log.append("ThingImpl") }
			@Received(fulfilledByDependencyNamed: "chainToken", ofType: \(tokenType).self) let token: \(tokenType)
			@Instantiated let reader: WrapperReader
		}

		@Instantiable
		public final class WrapperReader: Instantiable, Sendable {
			public init(chainToken: \(readerType)) { self.chainToken = chainToken; log.append("WrapperReader") }
			@Received let chainToken: \(readerType)
		}
		"""
	}

	/// A `thingImpl` for `chainTokenModules` that builds `WrapperReader` and receives no `chainToken` itself.
	private static let thingImplReadingOnlySendableWrapper = """
	@Instantiable(fulfillingAdditionalTypes: [ThingService.self])
	public final class ThingImpl: Instantiable, ThingService {
		public init(reader: WrapperReader) { self.reader = reader; log.append("ThingImpl") }
		@Instantiated let reader: WrapperReader
	}

	@Instantiable
	public final class WrapperReader: Instantiable, Sendable {
		public init(chainToken: SendableLazilyInstantiated<ChainToken>) { self.chainToken = chainToken; log.append("WrapperReader") }
		@Received let chainToken: SendableLazilyInstantiated<ChainToken>
	}
	"""

	/// A `thingImpl` for `chainTokenModules` like `thingImplReadingValueAndSendableWrapper`, where `ThingImpl` and
	/// `WrapperReader` read the plain `LazilyInstantiated`, which is not `Sendable`.
	private static let thingImplReadingValueAndLazyWrapper = """
	@Instantiable(fulfillingAdditionalTypes: [ThingService.self])
	public final class ThingImpl: Instantiable, ThingService, @unchecked Sendable {
		public init(chainToken: ChainToken, reader: WrapperReader) {
			self.chainToken = chainToken
			self.reader = reader
			log.append(reader.chainToken.instance === chainToken ? "ThingImpl shares ChainToken" : "ThingImpl holds another ChainToken")
		}
		@Received let chainToken: ChainToken
		@Instantiated let reader: WrapperReader
	}

	@Instantiable
	public final class WrapperReader: Instantiable {
		public init(chainToken: LazilyInstantiated<ChainToken>) { self.chainToken = chainToken; log.append("WrapperReader") }
		@Received let chainToken: LazilyInstantiated<ChainToken>
	}
	"""

	/// A `thingImpl` for `chainTokenModules` that builds `WrapperReader`, which receives the plain `LazilyInstantiated`, and
	/// receives no `chainToken` itself.
	private static let thingImplReadingOnlyLazyWrapper = """
	@Instantiable(fulfillingAdditionalTypes: [ThingService.self])
	public final class ThingImpl: Instantiable, ThingService, @unchecked Sendable {
		public init(reader: WrapperReader) { self.reader = reader; log.append("ThingImpl") }
		@Instantiated let reader: WrapperReader
	}

	@Instantiable
	public final class WrapperReader: Instantiable {
		public init(chainToken: LazilyInstantiated<ChainToken>) { self.chainToken = chainToken; log.append("WrapperReader") }
		@Received let chainToken: LazilyInstantiated<ChainToken>
	}
	"""

	/// A `thingImpl` for `chainTokenModules` that receives `chainToken` and builds `WrapperReader`, which receives it too.
	private static let thingImplReadingValueTwice = """
	@Instantiable(fulfillingAdditionalTypes: [ThingService.self])
	public final class ThingImpl: Instantiable, ThingService {
		public init(chainToken: ChainToken, reader: WrapperReader) {
			self.chainToken = chainToken
			self.reader = reader
			log.append(reader.chainToken === chainToken ? "ThingImpl shares ChainToken" : "ThingImpl holds another ChainToken")
		}
		@Received let chainToken: ChainToken
		@Instantiated let reader: WrapperReader
	}

	@Instantiable
	public final class WrapperReader: Instantiable, Sendable {
		public init(chainToken: ChainToken) { self.chainToken = chainToken; log.append("WrapperReader") }
		@Received let chainToken: ChainToken
	}
	"""

	/// A `thingImpl` for `chainTokenModules` that receives the `SendableLazilyInstantiated` and builds `WrapperReader`,
	/// which receives it too.
	private static let thingImplReadingSendableWrapperTwice = """
	@Instantiable(fulfillingAdditionalTypes: [ThingService.self])
	public final class ThingImpl: Instantiable, ThingService {
		public init(chainToken: SendableLazilyInstantiated<ChainToken>, reader: WrapperReader) {
			self.chainToken = chainToken
			self.reader = reader
			log.append(reader.chainToken.instance === chainToken.instance ? "ThingImpl shares ChainToken" : "ThingImpl holds another ChainToken")
		}
		@Received let chainToken: SendableLazilyInstantiated<ChainToken>
		@Instantiated let reader: WrapperReader
	}

	@Instantiable
	public final class WrapperReader: Instantiable, Sendable {
		public init(chainToken: SendableLazilyInstantiated<ChainToken>) { self.chainToken = chainToken; log.append("WrapperReader") }
		@Received let chainToken: SendableLazilyInstantiated<ChainToken>
	}
	"""

	/// A `thingImpl` for `chainTokenModules` that receives `chainToken` and builds `WrapperReader`, which receives the
	/// `SendableLazilyInstantiated`, inside a `@Sendable` function: in a `readerHolder` of type `holder`. `ThingImpl` gets
	/// the reader from its holder at once and logs whether the reader's wrapper holds the instance it was handed.
	private static func thingImplReadingSendableWrapperInside(holder: String, readsReader: String) -> String {
		"""
		@Instantiable(fulfillingAdditionalTypes: [ThingService.self])
		public final class ThingImpl: Instantiable, ThingService {
			public init(chainToken: ChainToken, readerHolder: \(holder)<WrapperReader>) {
				self.chainToken = chainToken
				self.readerHolder = readerHolder
				log.append(readerHolder.\(readsReader).chainToken.instance === chainToken ? "ThingImpl shares ChainToken" : "ThingImpl holds another ChainToken")
			}
			@Received let chainToken: ChainToken
			@Instantiated let readerHolder: \(holder)<WrapperReader>
		}

		@Instantiable
		public final class WrapperReader: Instantiable, Sendable {
			public init(chainToken: SendableLazilyInstantiated<ChainToken>) { self.chainToken = chainToken; log.append("WrapperReader") }
			@Received let chainToken: SendableLazilyInstantiated<ChainToken>
		}
		"""
	}

	/// A `thingImpl` for `chainTokenModules` that receives the `SendableLazilyInstantiated` and reads its value inside a
	/// `@Sendable` function, in `leafBuilder`, a `SendableInstantiator` of `ChainLeaf`. `ThingImpl` builds a leaf at once, so
	/// the creation log shows a `ChainToken` created for the leaf apart from its wrapper's.
	private static let thingImplReadingSendableWrapperAndValueInsideSendableFunction = """
	@Instantiable(fulfillingAdditionalTypes: [ThingService.self])
	public final class ThingImpl: Instantiable, ThingService {
		public init(chainToken: SendableLazilyInstantiated<ChainToken>, leafBuilder: SendableInstantiator<ChainLeaf>) {
			self.chainToken = chainToken
			self.leafBuilder = leafBuilder
			_ = leafBuilder.instantiate()
			_ = chainToken.instance
			log.append("ThingImpl")
		}
		@Received let chainToken: SendableLazilyInstantiated<ChainToken>
		@Instantiated let leafBuilder: SendableInstantiator<ChainLeaf>
	}
	"""

	/// `HoleImpl` as `chainTokenModules` declares it by default: it builds `Worker` in an `Instantiator`.
	private static let holeImplBuildingWorker = """
	@Instantiable(fulfillingAdditionalTypes: [HoleService.self])
	public final class HoleImpl: Instantiable, HoleService, @unchecked Sendable {
		public init(workerBuilder: Instantiator<Worker>) { self.workerBuilder = workerBuilder; log.append("HoleImpl") }
		@Instantiated public let workerBuilder: Instantiator<Worker>
	}
	"""

	/// Four modules, each depending on those before it. `Feature`'s seam `Seam` holds `holeService`, which its caller
	/// `Outer` passes up, and builds `ChainLeaf`, which receives `chainToken`, in `chainLeafBuilder`, so `Seam` defers
	/// `chainToken`. `Other` fills `holeService` with `holeImpl` under the seam `Mid`; by default `HoleImpl` builds `Worker`,
	/// in an `Instantiator`, whose place `thing` `Mid` passes up. `Top` fills what `Mid` passes up with `thingImpl`, the
	/// declarations it is given, under `TopRoot`, which declares `chainToken` as `topChainToken`, or, where
	/// `outerDeclaresChainToken` or `midChainToken`, nothing, with `Outer` declaring it lazily or `Mid` as `midChainToken`.
	/// `Mid` builds `Worker` itself too where `midWorker`, and in `midWorkerBuilder`, an `Instantiator`, where
	/// `midWorkerBuilder`. Where `outerHoldsSeamB`, `Outer` builds `SeamB` too, which holds `holeService` and builds
	/// `ChainLeaf` in `seamBLeafBuilder`, by default a `SendableInstantiator`, so it defers `chainToken` `@Sendable`, or, where
	/// `seamBReadsValueOnlyIfAvailable`, builds `OptionalChainLeaf`, which receives it only if available; where
	/// `outerHoldsOnlySeamB`, `Outer` builds `SeamB` and no `Seam`. Where `outerDeclaresChainToken`, `Outer` declares it as
	/// `outerChainToken`, and `TopRoot` declares it too where `rootDeclaresChainTokenToo`. `Mid` builds `ChainLeaf` itself
	/// as `directLeaf`, before `outer`, where `midDirectLeaf`; `Seam` receives `chainToken` as `seamChainToken` where given;
	/// and `Feature`, not `Other`, declares `Worker` and `holeImpl` where `featureFillsHoleService`, so `Seam`'s tree fills
	/// its place itself and passes up `Worker`'s `thing`. `ChainLeaf` receives `chainToken` as `chainLeafChainToken`. Every
	/// type that is built logs it to `log`.
	private static func chainTokenModules(
		thingImpl: String = """
		@Instantiable(fulfillingAdditionalTypes: [ThingService.self])
		public final class ThingImpl: Instantiable, ThingService {
			public init(chainToken: ChainToken) { self.chainToken = chainToken; log.append("ThingImpl") }
			@Received let chainToken: ChainToken
		}
		""",
		topChainToken: String = "@Instantiated let chainToken: LazilyInstantiated<ChainToken>",
		chainLeafBuilder: String = "Instantiator<ChainLeaf>",
		holeImpl: String = holeImplBuildingWorker,
		midWorker: Bool = false,
		midWorkerBuilder: Bool = false,
		outerHoldsSeamB: Bool = false,
		outerHoldsOnlySeamB: Bool = false,
		seamBReadsValueOnlyIfAvailable: Bool = false,
		seamBLeafBuilder: String = "SendableInstantiator",
		outerDeclaresChainToken: Bool = false,
		outerChainToken: String = "LazilyInstantiated<ChainToken>",
		rootDeclaresChainTokenToo: Bool = false,
		midChainToken: String? = nil,
		midDirectLeaf: Bool = false,
		seamChainToken: String? = nil,
		featureFillsHoleService: Bool = false,
		chainLeafChainToken: String = "ChainToken",
	) -> [ModuleFixture] {
		// `Mid`'s properties beside `outer`, each with its type: `chainToken` and `directLeaf`, which its initializer takes
		// before `outer`, and `worker`, which it takes after, are declared before `outer`; `midWorkerBuilder`, after.
		var midPropertiesBeforeOuter = [(label: String, type: String)]()
		var midPropertiesAfterOuter = [(label: String, type: String)]()
		if let midChainToken {
			midPropertiesBeforeOuter.append(("chainToken", midChainToken))
		}
		if midDirectLeaf {
			midPropertiesBeforeOuter.append(("directLeaf", "ChainLeaf"))
		}
		if midWorker {
			midPropertiesAfterOuter.append(("worker", "Worker"))
		}
		if midWorkerBuilder {
			midPropertiesAfterOuter.append(("midWorkerBuilder", "Instantiator<Worker>"))
		}
		let midInitializerProperties = midPropertiesBeforeOuter + [("outer", "Outer")] + midPropertiesAfterOuter
		var midInitializer = "public init(\(midInitializerProperties.map { "\($0.label): \($0.type)" }.joined(separator: ", "))) { \(midInitializerProperties.map { "self.\($0.label) = \($0.label); " }.joined())log.append(\"Mid\") }"
		for property in midPropertiesBeforeOuter + midPropertiesAfterOuter where property.label != "midWorkerBuilder" {
			midInitializer += "\n\t@Instantiated public let \(property.label): \(property.type)"
		}
		midInitializer += "\n\t@Instantiated public let outer: Outer"
		if midWorkerBuilder {
			midInitializer += "\n\t@Instantiated public let midWorkerBuilder: Instantiator<Worker>"
		}
		let midDeclaresChainToken = midChainToken != nil
		let topChainTokenType = topChainToken.components(separatedBy: ": ").last ?? ""
		let outerDeclarations = if outerDeclaresChainToken, outerHoldsOnlySeamB {
			"public init(chainToken: \(outerChainToken), seamB: SeamB) { self.chainToken = chainToken; self.seamB = seamB; log.append(\"Outer\") }\n\t@Instantiated public let chainToken: \(outerChainToken)\n\t@Instantiated public let seamB: SeamB"
		} else if outerDeclaresChainToken {
			"public init(chainToken: \(outerChainToken), seam: Seam) { self.chainToken = chainToken; self.seam = seam; log.append(\"Outer\") }\n\t@Instantiated public let chainToken: \(outerChainToken)"
		} else if outerHoldsOnlySeamB {
			"public init(seamB: SeamB) { self.seamB = seamB; log.append(\"Outer\") }\n\t@Instantiated public let seamB: SeamB"
		} else if outerHoldsSeamB {
			"public init(seam: Seam, seamB: SeamB) { self.seam = seam; self.seamB = seamB; log.append(\"Outer\") }\n\t@Instantiated public let seamB: SeamB"
		} else {
			"public init(seam: Seam) { self.seam = seam; log.append(\"Outer\") }"
		}
		let seamBLeaf = seamBReadsValueOnlyIfAvailable ? "OptionalChainLeaf" : "ChainLeaf"
		let optionalChainLeaf = seamBReadsValueOnlyIfAvailable ? """


		@Instantiable
		public final class OptionalChainLeaf: Instantiable, Sendable {
			public init(chainToken: ChainToken?) { self.chainToken = chainToken; log.append("OptionalChainLeaf") }
			@Received(onlyIfAvailable: true) let chainToken: ChainToken?
		}
		""" : ""
		let outerSeamDeclaration = outerHoldsOnlySeamB ? "" : "\n\t@Instantiated public let seam: Seam"
		let seamB = outerHoldsSeamB || outerHoldsOnlySeamB ? """


		@Instantiable(generateDependencyTree: true)
		public final class SeamB: Instantiable, @unchecked Sendable {
			public init(leafBuilder: \(seamBLeafBuilder)<\(seamBLeaf)>, holeService: any HoleService) {
				self.leafBuilder = leafBuilder
				self.holeService = holeService
				log.append("SeamB")
			}
			@Instantiated public let leafBuilder: \(seamBLeafBuilder)<\(seamBLeaf)>
			@Instantiated public let holeService: any HoleService
		}\(optionalChainLeaf)
		""" : ""
		let topRootDeclarations = (outerDeclaresChainToken || midDeclaresChainToken) && !rootDeclaresChainTokenToo
			? "public init(mid: Mid) { self.mid = mid; log.append(\"TopRoot\") }"
			: "public init(chainToken: \(topChainTokenType), mid: Mid) { self.chainToken = chainToken; self.mid = mid; log.append(\"TopRoot\") }\n\t\(topChainToken)"
		let seamDeclarations = if let seamChainToken {
			"""
			public init(chainToken: \(seamChainToken), leafBuilder: \(chainLeafBuilder), holeService: any HoleService) {
					self.chainToken = chainToken
					self.leafBuilder = leafBuilder
					self.holeService = holeService
					log.append("Seam")
				}
				@Received public let chainToken: \(seamChainToken)
			"""
		} else {
			"""
			public init(leafBuilder: \(chainLeafBuilder), holeService: any HoleService) {
					self.leafBuilder = leafBuilder
					self.holeService = holeService
					log.append("Seam")
				}
			"""
		}
		let worker = """
		@Instantiable
		public final class Worker: Instantiable, Sendable {
			public init(thing: any ThingService) { self.thing = thing; log.append("Worker") }
			@Instantiated let thing: any ThingService
		}

		\(holeImpl)
		"""
		return [
			ModuleFixture(name: "Core", packageName: "Min", swiftFileContent: ["""
			import SafeDI

			public nonisolated(unsafe) var log = [String]()

			@Instantiable
			public final class ChainToken: Instantiable, Sendable {
				public init() { log.append("ChainToken") }
			}

			@Instantiable
			public final class ChainLeaf: Instantiable, Sendable {
				public init(chainToken: \(chainLeafChainToken)) { self.chainToken = chainToken; log.append("ChainLeaf") }
				@Received let chainToken: \(chainLeafChainToken)
			}

			public protocol HoleService: Sendable {}
			public protocol ThingService: Sendable {}
			public protocol GadgetService: Sendable {}
			"""]),
			ModuleFixture(name: "Feature", packageName: "Min", swiftFileContent: ["""
			import Core
			import SafeDI

			@Instantiable(generateDependencyTree: true)
			public final class Seam: Instantiable, @unchecked Sendable {
				\(seamDeclarations)
				@Instantiated public let leafBuilder: \(chainLeafBuilder)
				@Instantiated public let holeService: any HoleService
			}

			@Instantiable(generateDependencyTree: true)
			public final class Outer: Instantiable, @unchecked Sendable {
				\(outerDeclarations)\(outerSeamDeclaration)
			}\(seamB)\(featureFillsHoleService ? "\n\n" + worker : "")
			"""], dependencies: ["Core"]),
			ModuleFixture(name: "Other", packageName: "Min", swiftFileContent: ["""
			import Core
			import Feature
			import SafeDI

			\(featureFillsHoleService ? "" : worker + "\n\n")@Instantiable(generateDependencyTree: true)
			public final class Mid: Instantiable {
				\(midInitializer)
			}
			"""], dependencies: ["Core", "Feature"]),
			ModuleFixture(name: "Top", packageName: "Min", swiftFileContent: ["""
			import Core
			import Feature
			import Other
			import SafeDI

			\(thingImpl)

			@Instantiable(isRoot: true)
			public final class TopRoot: Instantiable {
				\(topRootDeclarations)
				@Instantiated public let mid: Mid
			}
			"""], dependencies: ["Core", "Feature", "Other"]),
		]
	}

	/// Expects the order in which `output`, the run of `modules`, builds its types to equal that of the one-module build:
	/// every module's declarations in one module, which builds every seam inline. The probe builds `TopRoot`, then calls
	/// each of `HoleImpl`'s `builders` in turn, the `HoleImpl` of each of `Outer`'s `seams` in turn, then each of `Mid`'s
	/// `midBuilders`, logging each step, and returns what was logged; or it is `probeLines`.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectCreationOrderEqualsOneModuleBuild(_ output: MultiModuleTestOutput, modules: [ModuleFixture], seams: [String] = ["seam"], builders: [String] = ["workerBuilder"], midBuilders: [String] = [], probeLines givenProbeLines: [String]? = nil, comparingValues valueProbes: [DifferentialValueProbe] = [], sourceLocation: SourceLocation = #_sourceLocation) async throws {
		guard compileVerificationIsEnabled else { return }
		let declarations = modules.map { module in
			module.swiftFileContent.joined(separator: "\n\n").components(separatedBy: "\n").filter { !$0.hasPrefix("import ") }.joined(separator: "\n")
		}
		let oneModule = [ModuleFixture(name: "App", packageName: "Min", swiftFileContent: ["import SafeDI\n" + declarations.joined(separator: "\n")])]
		let oneModuleOutput = try await executeSafeDIToolMultiModuleTest(modules: oneModule, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		var probeLines = ["{ () -> [String] in", "\tlog = []", "\tlet root = TopRoot()", "\tlog.append(\"built TopRoot\")"]
		for seam in seams {
			for builder in builders {
				probeLines.append("\t_ = (root.mid.outer.\(seam).holeService as! HoleImpl).\(builder).instantiate()")
				probeLines.append("\tlog.append(\"called \(seam == "seam" ? builder : "\(seam).\(builder)")\")")
			}
		}
		for builder in midBuilders {
			probeLines.append("\t_ = root.mid.\(builder).instantiate()")
			probeLines.append("\tlog.append(\"called \(builder)\")")
		}
		probeLines += ["\treturn log", "}()"]
		if let givenProbeLines {
			probeLines = givenProbeLines
		}
		try await expectDifferentialValuesAgree(
			feature: DifferentialValuePath(output: output, modules: modules),
			knownRight: DifferentialValuePath(output: oneModuleOutput, modules: oneModule),
			probes: [DifferentialValueProbe(name: "creation order", expression: probeLines.joined(separator: "\n"))] + valueProbes,
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}

	/// A probe of the value `TopRoot` holds beside the `Worker` that `HoleImpl`'s `workerBuilder` beneath `Outer`'s `seam`
	/// builds, which compares the wrapper the fill's tree reads, by its instance, with the declarations of the root's tree.
	private static let rootBesideSeamsWorkerProbe = DifferentialValueProbe(name: "root beside the seam's worker", expression: "{ () -> Any in\n\tlet root = TopRoot()\n\treturn (root, (root.mid.outer.seam.holeService as! HoleImpl).workerBuilder.instantiate())\n}()")

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
