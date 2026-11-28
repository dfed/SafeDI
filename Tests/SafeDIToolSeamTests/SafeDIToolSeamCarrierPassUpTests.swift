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

/// Carriers of a seam that calls another seam: the outer seam fills one of the inner seam's hole types in its own module
/// and passes another up to its caller, holding the inner seam's carrier as a child of its own level's carrier, also
/// where its own level binds values before the call.
struct SafeDIToolSeamCarrierPassUpTests: ~Copyable {
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
	mutating func generate_fillsOneInnerSeamHoleTypeAndPassesAnotherUp() async throws {
		let modules = CarrierCells.modules(
			seam: [
				"public protocol Api {}",
				"public protocol Logger {}",
				seamFixtureType(named: "Detail", isFinalClass: true, declarations: ["@Forwarded let id: Int", "@Instantiated let api: any Api", "@Instantiated let logger: any Logger"]),
				seamFixtureType(named: "Inner", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let detailBuilder: Instantiator<Detail>"]),
				CarrierCells.fulfillingImpl(named: "LoggerImpl", fulfilling: "Logger", reading: ["@Received let id: Int"]),
				seamFixtureType(named: "Home", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let inner: Inner"]),
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
		        public let inner: Inner.__safeDI_ApiCarrier<__safeDI_Built>

		        public init(inner: Inner.__safeDI_ApiCarrier<__safeDI_Built>) {
		            self.inner = inner
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        @inline(never) func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_D0290D5B0174CE2A.self
		            return Inner(__safeDI_apiBuilder: __safeDI_apiBuilder.inner)
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(inner: inner)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_91005CD3AB44FD5C {}
		}

		extension Inner {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let detailBuilder: __safeDI_ApiCarrier_Detail<__safeDI_Built>

		        public init(detailBuilder: __safeDI_ApiCarrier_Detail<__safeDI_Built>) {
		            self.detailBuilder = detailBuilder
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Detail<__safeDI_Built> {
		        public let api: (Int, any Logger) -> __safeDI_Built

		        public init(api: @escaping (Int, any Logger) -> __safeDI_Built) {
		            self.api = api
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder.detailBuilder
		        @inline(never) func __safeDI_detailBuilder(id: Int) -> Detail {
		            let logger: any Logger = LoggerImpl(id: id)
		            let api: any Api = __safeDI_apiBuilder_detailBuilder.api(id, logger)
		            return Detail(id: id, api: api, logger: logger)
		        }
		        let detailBuilder = Instantiator<Detail> {
		            __safeDI_detailBuilder(id: $0)
		        }
		        self.init(detailBuilder: detailBuilder)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_D0290D5B0174CE2A {}
		}
		"""])
		CarrierCells.expectGeneratedFiles(output.modules["App"]?.generatedFiles, ["App.swift": generatedFileHeader + """
		#if canImport(Seam)
		import Seam
		#endif

		extension Root {
		    public init() {
		        func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		            .init(inner: __safeDI_apiBuilder_Inner())
		        }
		        func __safeDI_apiBuilder_Inner() -> Inner.__safeDI_ApiCarrier<any Api> {
		            .init(detailBuilder: __safeDI_apiBuilder_Inner_Detail_Scope())
		        }
		        func __safeDI_apiBuilder_Inner_Detail_Scope() -> Inner.__safeDI_ApiCarrier_Detail<any Api> {
		            .init(api: { scope_id, scope_logger in
		                let id = scope_id
		                let api: any Api = ApiImpl(id: id)
		                return api
		            })
		        }
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_91005CD3AB44FD5C.self // If this line does not compile, compile the code SafeDI generates for module Seam into Seam: under Bazel, add Seam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		"""])
		try await CarrierCells.expectValuesAndRetentionEqualInlineBuild(output, modules: modules, samples: [DifferentialValueSample(type: "Detail.ForwardedProperties", expression: "7")], filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesInnerSeamCarrierAsLet_whenOuterLevelBindsValues() async throws {
		let modules = CarrierCells.modules(
			seam: [
				"public protocol Api {}",
				seamFixtureType(named: "Session", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Detail", isFinalClass: true, declarations: ["@Forwarded let id: Int", "@Instantiated let api: any Api"]),
				seamFixtureType(named: "Inner", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let detailBuilder: Instantiator<Detail>"]),
				seamFixtureType(named: "Screen", isFinalClass: true, declarations: ["@Forwarded let name: String", "@Instantiated let session: Session", "@Instantiated let inner: Inner"]),
				seamFixtureType(named: "Home", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let screenBuilder: Instantiator<Screen>"]),
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
		        public let screenBuilder: __safeDI_ApiCarrier_Screen<__safeDI_Built>

		        public init(screenBuilder: __safeDI_ApiCarrier_Screen<__safeDI_Built>) {
		            self.screenBuilder = screenBuilder
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Screen<__safeDI_Built> {
		        public let inner: Inner.__safeDI_ApiCarrier<__safeDI_Built>

		        public init(inner: Inner.__safeDI_ApiCarrier<__safeDI_Built>) {
		            self.inner = inner
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let __safeDI_apiBuilder_screenBuilder = __safeDI_apiBuilder.screenBuilder
		        @inline(never) func __safeDI_screenBuilder(name: String) -> Screen {
		            let session = Session()
		            @inline(never) func __safeDI_inner() -> Inner {
		                _ = Inner.__safeDI_Inner_376D77FD9EAB6893.self
		                return Inner(__safeDI_apiBuilder: __safeDI_apiBuilder_screenBuilder.inner)
		            }
		            let inner: Inner = __safeDI_inner()
		            return Screen(name: name, session: session, inner: inner)
		        }
		        let screenBuilder = Instantiator<Screen> {
		            __safeDI_screenBuilder(name: $0)
		        }
		        self.init(screenBuilder: screenBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_004836A90DE4B635 {}
		}

		extension Inner {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let detailBuilder: __safeDI_ApiCarrier_Detail<__safeDI_Built>

		        public init(detailBuilder: __safeDI_ApiCarrier_Detail<__safeDI_Built>) {
		            self.detailBuilder = detailBuilder
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Detail<__safeDI_Built> {
		        public let api: (Int) -> __safeDI_Built

		        public init(api: @escaping (Int) -> __safeDI_Built) {
		            self.api = api
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder.detailBuilder
		        @inline(never) func __safeDI_detailBuilder(id: Int) -> Detail {
		            let api: any Api = __safeDI_apiBuilder_detailBuilder.api(id)
		            return Detail(id: id, api: api)
		        }
		        let detailBuilder = Instantiator<Detail> {
		            __safeDI_detailBuilder(id: $0)
		        }
		        self.init(detailBuilder: detailBuilder)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_376D77FD9EAB6893 {}
		}
		"""])
		CarrierCells.expectGeneratedFiles(output.modules["App"]?.generatedFiles, ["App.swift": generatedFileHeader + """
		#if canImport(Seam)
		import Seam
		#endif

		extension Root {
		    public init() {
		        func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		            .init(screenBuilder: __safeDI_apiBuilder_Home_Screen_Scope())
		        }
		        func __safeDI_apiBuilder_Home_Screen_Scope() -> Home.__safeDI_ApiCarrier_Screen<any Api> {
		            .init(inner: __safeDI_apiBuilder_Inner())
		        }
		        func __safeDI_apiBuilder_Inner() -> Inner.__safeDI_ApiCarrier<any Api> {
		            .init(detailBuilder: __safeDI_apiBuilder_Inner_Detail_Scope())
		        }
		        func __safeDI_apiBuilder_Inner_Detail_Scope() -> Inner.__safeDI_ApiCarrier_Detail<any Api> {
		            .init(api: { scope_id in
		                let id = scope_id
		                let api: any Api = ApiImpl(id: id)
		                return api
		            })
		        }
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_004836A90DE4B635.self // If this line does not compile, compile the code SafeDI generates for module Seam into Seam: under Bazel, add Seam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		"""])
		try await CarrierCells.expectValuesAndRetentionEqualInlineBuild(output, modules: modules, samples: [DifferentialValueSample(type: "Detail.ForwardedProperties", expression: "7"), DifferentialValueSample(type: "Screen.ForwardedProperties", expression: "\"screen\"")], filesToDelete: &filesToDelete)
	}

	private var filesToDelete: [URL]
}
