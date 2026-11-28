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

/// Carriers of a loop of builders: places on screens that open one another, whose levels bind values the fills read. Each
/// build of a screen hands its place the values of its own level, as the inline build does, however deep the loop runs,
/// and the screens of one loop share their carriers.
struct SafeDIToolSeamCarrierLoopTests: ~Copyable {
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

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_formsZonePerLoopDepth_whenLoopLevelBindsValueAFillReads() async throws {
		let modules = CarrierCells.modules(
			seam: [
				"public protocol Api {}",
				seamFixtureType(named: "Mark", isFinalClass: true, declarations: []),
				seamFixtureType(named: "ScreenA", isFinalClass: true, declarations: ["@Forwarded let id: Int", "@Instantiated let mark: Mark", "@Instantiated let api: any Api", "@Received let screenBBuilder: Instantiator<ScreenB>"]),
				seamFixtureType(named: "ScreenB", isFinalClass: true, declarations: ["@Forwarded let id: Int", "@Instantiated let api: any Api", "@Received let screenABuilder: Instantiator<ScreenA>"]),
				seamFixtureType(named: "Home", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let screenABuilder: Instantiator<ScreenA>", "@Instantiated let screenBBuilder: Instantiator<ScreenB>"]),
			],
			app: [
				CarrierCells.fulfillingImpl(named: "ApiImpl", fulfilling: "Api", reading: ["@Received let id: Int", "@Received(onlyIfAvailable: true) let mark: Mark?"]),
				CarrierCellRoot.structRoot.declaration(building: "home: Home"),
			],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		CarrierCells.expectGeneratedFiles(output.modules["Seam"]?.generatedFiles, ["Seam.swift": generatedFileHeader + """
		extension Home {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let screenABuilder: __safeDI_ApiCarrier_ScreenA<__safeDI_Built>
		        public let screenBBuilder: __safeDI_ApiCarrier_ScreenB<__safeDI_Built>

		        public init(screenABuilder: __safeDI_ApiCarrier_ScreenA<__safeDI_Built>, screenBBuilder: __safeDI_ApiCarrier_ScreenB<__safeDI_Built>) {
		            self.screenABuilder = screenABuilder
		            self.screenBBuilder = screenBBuilder
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_ScreenA<__safeDI_Built> {
		        public let api: (Int, Instantiator<ScreenB>, Mark) -> __safeDI_Built

		        public init(api: @escaping (Int, Instantiator<ScreenB>, Mark) -> __safeDI_Built) {
		            self.api = api
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_ScreenB<__safeDI_Built> {
		        public let api: (Int, Instantiator<ScreenA>) -> __safeDI_Built

		        public init(api: @escaping (Int, Instantiator<ScreenA>) -> __safeDI_Built) {
		            self.api = api
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let __safeDI_screenABuilder_loopLevels = __safeDI_LoopLevels_0B2EF1D82F50807F(
		            __safeDI_apiBuilder_screenABuilder: __safeDI_apiBuilder.screenABuilder,
		            __safeDI_apiBuilder_screenBBuilder: __safeDI_apiBuilder.screenBBuilder
		        )
		        @inline(never) func __safeDI_screenABuilder(id: Int) -> ScreenA {
		            let __safeDI_apiBuilder_screenABuilder = __safeDI_screenABuilder_loopLevels.__safeDI_apiBuilder_screenABuilder
		            let screenBBuilder = Instantiator<ScreenB> {
		                __safeDI_screenBBuilder(id: $0)
		            }
		            let mark = Mark()
		            let api: any Api = __safeDI_apiBuilder_screenABuilder.api(id, screenBBuilder, mark)
		            return ScreenA(id: id, mark: mark, api: api, screenBBuilder: screenBBuilder)
		        }
		        let screenABuilder = Instantiator<ScreenA> {
		            __safeDI_screenABuilder(id: $0)
		        }
		        @inline(never) func __safeDI_screenBBuilder(id: Int) -> ScreenB {
		            let __safeDI_apiBuilder_screenBBuilder = __safeDI_screenABuilder_loopLevels.__safeDI_apiBuilder_screenBBuilder
		            let screenABuilder = Instantiator<ScreenA> {
		                __safeDI_screenABuilder(id: $0)
		            }
		            let api: any Api = __safeDI_apiBuilder_screenBBuilder.api(id, screenABuilder)
		            return ScreenB(id: id, api: api, screenABuilder: screenABuilder)
		        }
		        let screenBBuilder = Instantiator<ScreenB> {
		            __safeDI_screenBBuilder(id: $0)
		        }
		        self.init(screenABuilder: screenABuilder, screenBBuilder: screenBBuilder)
		    }

		    /// Holds the payloads of a loop of builders, so that each builder function of the loop captures one reference.
		    nonisolated private final class __safeDI_LoopLevels_0B2EF1D82F50807F {
		        init(
		            __safeDI_apiBuilder_screenABuilder: __safeDI_ApiCarrier_ScreenA<any Api>,
		            __safeDI_apiBuilder_screenBBuilder: __safeDI_ApiCarrier_ScreenB<any Api>
		        ) {
		            self.__safeDI_apiBuilder_screenABuilder = __safeDI_apiBuilder_screenABuilder
		            self.__safeDI_apiBuilder_screenBBuilder = __safeDI_apiBuilder_screenBBuilder
		        }

		        let __safeDI_apiBuilder_screenABuilder: __safeDI_ApiCarrier_ScreenA<any Api>
		        let __safeDI_apiBuilder_screenBBuilder: __safeDI_ApiCarrier_ScreenB<any Api>
		    }
		}

		extension Home {
		    public enum __safeDI_Home_9EC4FFA6DC178BB7 {}
		}
		"""])
		CarrierCells.expectGeneratedFiles(output.modules["App"]?.generatedFiles, ["App.swift": generatedFileHeader + """
		#if canImport(Seam)
		import Seam
		#endif

		extension Root {
		    public init() {
		        func __safeDI_apiBuilder_Home_ScreenA_Scope() -> Home.__safeDI_ApiCarrier_ScreenA<any Api> {
		            .init(api: { scope_id, scope_screenBBuilder, scope_mark in
		                let id = scope_id
		                let mark = scope_mark
		                let api: any Api = ApiImpl(id: id, mark: mark)
		                return api
		            })
		        }
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_9EC4FFA6DC178BB7.self // If this line does not compile, compile the code SafeDI generates for module Seam into Seam: under Bazel, add Seam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		                .init(screenABuilder: __safeDI_apiBuilder_Home_ScreenA_Scope(), screenBBuilder: __safeDI_apiBuilder_Home_ScreenB_Scope())
		            }
		            func __safeDI_apiBuilder_Home_ScreenB_Scope() -> Home.__safeDI_ApiCarrier_ScreenB<any Api> {
		                .init(api: { scope_id, scope_screenABuilder in
		                    let id = scope_id
		                    let api: any Api = ApiImpl(id: id, mark: nil)
		                    return api
		                })
		            }
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		"""])
		try await CarrierCells.expectValuesAndRetentionEqualInlineBuild(output, modules: modules, samples: ["ScreenA", "ScreenB"].map { DifferentialValueSample(type: "\($0).ForwardedProperties", expression: "7") }, filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_sharesOneCarrier_whenPlacesFormACycle() async throws {
		let modules = CarrierCells.modules(
			seam: [
				"public protocol Api {}",
				seamFixtureType(named: "ScreenA", isFinalClass: true, declarations: ["@Forwarded let id: Int", "@Instantiated let api: any Api", "@Received let screenBBuilder: Instantiator<ScreenB>"]),
				seamFixtureType(named: "ScreenB", isFinalClass: true, declarations: ["@Forwarded let id: Int", "@Instantiated let api: any Api", "@Received let screenCBuilder: Instantiator<ScreenC>"]),
				seamFixtureType(named: "ScreenC", isFinalClass: true, declarations: ["@Forwarded let id: Int", "@Instantiated let api: any Api", "@Received let screenABuilder: Instantiator<ScreenA>"]),
				seamFixtureType(named: "Home", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let screenABuilder: Instantiator<ScreenA>", "@Instantiated let screenBBuilder: Instantiator<ScreenB>", "@Instantiated let screenCBuilder: Instantiator<ScreenC>"]),
			],
			app: [
				CarrierCells.fulfillingImpl(named: "ApiImpl", fulfilling: "Api", reading: ["@Received let id: Int"]),
				CarrierCellRoot.structRoot.declaration(building: "home: Home"),
			],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		CarrierCells.expectGeneratedFiles(output.modules["Seam"]?.generatedFiles, ["Seam.swift": generatedFileHeader + """
		extension Home {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let screenABuilder: __safeDI_ApiCarrier_ScreenA<__safeDI_Built>
		        public let screenBBuilder: __safeDI_ApiCarrier_ScreenB<__safeDI_Built>
		        public let screenCBuilder: __safeDI_ApiCarrier_ScreenC<__safeDI_Built>

		        public init(screenABuilder: __safeDI_ApiCarrier_ScreenA<__safeDI_Built>, screenBBuilder: __safeDI_ApiCarrier_ScreenB<__safeDI_Built>, screenCBuilder: __safeDI_ApiCarrier_ScreenC<__safeDI_Built>) {
		            self.screenABuilder = screenABuilder
		            self.screenBBuilder = screenBBuilder
		            self.screenCBuilder = screenCBuilder
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_ScreenA<__safeDI_Built> {
		        public let api: (Int, Instantiator<ScreenB>) -> __safeDI_Built

		        public init(api: @escaping (Int, Instantiator<ScreenB>) -> __safeDI_Built) {
		            self.api = api
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_ScreenB<__safeDI_Built> {
		        public let api: (Int, Instantiator<ScreenC>) -> __safeDI_Built

		        public init(api: @escaping (Int, Instantiator<ScreenC>) -> __safeDI_Built) {
		            self.api = api
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_ScreenC<__safeDI_Built> {
		        public let api: (Int, Instantiator<ScreenA>) -> __safeDI_Built

		        public init(api: @escaping (Int, Instantiator<ScreenA>) -> __safeDI_Built) {
		            self.api = api
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let __safeDI_screenABuilder_loopLevels = __safeDI_LoopLevels_6810F24E4F3FBD4D(
		            __safeDI_apiBuilder_screenABuilder: __safeDI_apiBuilder.screenABuilder,
		            __safeDI_apiBuilder_screenBBuilder: __safeDI_apiBuilder.screenBBuilder,
		            __safeDI_apiBuilder_screenCBuilder: __safeDI_apiBuilder.screenCBuilder
		        )
		        @inline(never) func __safeDI_screenABuilder(id: Int) -> ScreenA {
		            let __safeDI_apiBuilder_screenABuilder = __safeDI_screenABuilder_loopLevels.__safeDI_apiBuilder_screenABuilder
		            let screenBBuilder = Instantiator<ScreenB> {
		                __safeDI_screenBBuilder(id: $0)
		            }
		            let api: any Api = __safeDI_apiBuilder_screenABuilder.api(id, screenBBuilder)
		            return ScreenA(id: id, api: api, screenBBuilder: screenBBuilder)
		        }
		        let screenABuilder = Instantiator<ScreenA> {
		            __safeDI_screenABuilder(id: $0)
		        }
		        @inline(never) func __safeDI_screenBBuilder(id: Int) -> ScreenB {
		            let __safeDI_apiBuilder_screenBBuilder = __safeDI_screenABuilder_loopLevels.__safeDI_apiBuilder_screenBBuilder
		            let screenCBuilder = Instantiator<ScreenC> {
		                __safeDI_screenCBuilder(id: $0)
		            }
		            let api: any Api = __safeDI_apiBuilder_screenBBuilder.api(id, screenCBuilder)
		            return ScreenB(id: id, api: api, screenCBuilder: screenCBuilder)
		        }
		        let screenBBuilder = Instantiator<ScreenB> {
		            __safeDI_screenBBuilder(id: $0)
		        }
		        @inline(never) func __safeDI_screenCBuilder(id: Int) -> ScreenC {
		            let __safeDI_apiBuilder_screenCBuilder = __safeDI_screenABuilder_loopLevels.__safeDI_apiBuilder_screenCBuilder
		            let screenABuilder = Instantiator<ScreenA> {
		                __safeDI_screenABuilder(id: $0)
		            }
		            let api: any Api = __safeDI_apiBuilder_screenCBuilder.api(id, screenABuilder)
		            return ScreenC(id: id, api: api, screenABuilder: screenABuilder)
		        }
		        let screenCBuilder = Instantiator<ScreenC> {
		            __safeDI_screenCBuilder(id: $0)
		        }
		        self.init(screenABuilder: screenABuilder, screenBBuilder: screenBBuilder, screenCBuilder: screenCBuilder)
		    }

		    /// Holds the payloads of a loop of builders, so that each builder function of the loop captures one reference.
		    nonisolated private final class __safeDI_LoopLevels_6810F24E4F3FBD4D {
		        init(
		            __safeDI_apiBuilder_screenABuilder: __safeDI_ApiCarrier_ScreenA<any Api>,
		            __safeDI_apiBuilder_screenBBuilder: __safeDI_ApiCarrier_ScreenB<any Api>,
		            __safeDI_apiBuilder_screenCBuilder: __safeDI_ApiCarrier_ScreenC<any Api>
		        ) {
		            self.__safeDI_apiBuilder_screenABuilder = __safeDI_apiBuilder_screenABuilder
		            self.__safeDI_apiBuilder_screenBBuilder = __safeDI_apiBuilder_screenBBuilder
		            self.__safeDI_apiBuilder_screenCBuilder = __safeDI_apiBuilder_screenCBuilder
		        }

		        let __safeDI_apiBuilder_screenABuilder: __safeDI_ApiCarrier_ScreenA<any Api>
		        let __safeDI_apiBuilder_screenBBuilder: __safeDI_ApiCarrier_ScreenB<any Api>
		        let __safeDI_apiBuilder_screenCBuilder: __safeDI_ApiCarrier_ScreenC<any Api>
		    }
		}

		extension Home {
		    public enum __safeDI_Home_6D4E0593FD00DAB3 {}
		}
		"""])
		CarrierCells.expectGeneratedFiles(output.modules["App"]?.generatedFiles, ["App.swift": generatedFileHeader + """
		#if canImport(Seam)
		import Seam
		#endif

		extension Root {
		    public init() {
		        func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		            .init(screenABuilder: __safeDI_apiBuilder_Home_ScreenA_Scope(), screenBBuilder: __safeDI_apiBuilder_Home_ScreenB_Scope(), screenCBuilder: __safeDI_apiBuilder_Home_ScreenC_Scope())
		        }
		        func __safeDI_apiBuilder_Home_ScreenA_Scope() -> Home.__safeDI_ApiCarrier_ScreenA<any Api> {
		            .init(api: { scope_id, scope_screenBBuilder in
		                let id = scope_id
		                let api: any Api = ApiImpl(id: id)
		                return api
		            })
		        }
		        func __safeDI_apiBuilder_Home_ScreenB_Scope() -> Home.__safeDI_ApiCarrier_ScreenB<any Api> {
		            .init(api: { scope_id, scope_screenCBuilder in
		                let id = scope_id
		                let api: any Api = ApiImpl(id: id)
		                return api
		            })
		        }
		        func __safeDI_apiBuilder_Home_ScreenC_Scope() -> Home.__safeDI_ApiCarrier_ScreenC<any Api> {
		            .init(api: { scope_id, scope_screenABuilder in
		                let id = scope_id
		                let api: any Api = ApiImpl(id: id)
		                return api
		            })
		        }
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_6D4E0593FD00DAB3.self // If this line does not compile, compile the code SafeDI generates for module Seam into Seam: under Bazel, add Seam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		"""])
		try await CarrierCells.expectValuesAndRetentionEqualInlineBuild(output, modules: modules, samples: ["ScreenA", "ScreenB", "ScreenC"].map { DifferentialValueSample(type: "\($0).ForwardedProperties", expression: "7") }, filesToDelete: &filesToDelete)
	}

	private var filesToDelete: [URL]
}
