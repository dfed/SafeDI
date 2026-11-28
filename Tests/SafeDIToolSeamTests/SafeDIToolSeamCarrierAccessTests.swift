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

/// A carrier’s access: a public seam whose level binds a value of an `internal` type declares that value’s field
/// `internal` in the level’s public values struct, so the module compiles, and a caller in the same package fills the
/// level’s place reading only the public field. Inline, the caller’s module could not build the `internal` types, so the
/// cell has no inline build to compare values with.
struct SafeDIToolSeamCarrierAccessTests: ~Copyable {
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
	mutating func generate_declaresInternalTypedValueInternal_whenPublicSeamsLevelBindsIt() async throws {
		let modules = CarrierCells.modules(
			seam: Self.internalValueSeam,
			app: [
				CarrierCells.fulfillingImpl(named: "ApiImpl", fulfilling: "Api", reading: ["@Received let id: Int"]),
				CarrierCellRoot.structRoot.declaration(building: "home: Home"),
			],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		CarrierCells.expectGeneratedFiles(output.modules["Seam"]?.generatedFiles, ["Seam.swift": generatedFileHeader + """
		extension Home {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public struct __safeDI_ScreenValues2 {
		        public let id: Int
		        internal let secret: Secret

		        init(id: Int, secret: Secret) {
		            self.id = id
		            self.secret = secret
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let screenBuilder: __safeDI_ApiCarrier_Screen<__safeDI_Built>

		        public init(screenBuilder: __safeDI_ApiCarrier_Screen<__safeDI_Built>) {
		            self.screenBuilder = screenBuilder
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Screen<__safeDI_Built> {
		        public let detailBuilder: (__safeDI_ScreenValues2) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>

		        public init(detailBuilder: @escaping (__safeDI_ScreenValues2) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>) {
		            self.detailBuilder = detailBuilder
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Detail<__safeDI_Built> {
		        public let api: () -> __safeDI_Built

		        public init(api: @escaping () -> __safeDI_Built) {
		            self.api = api
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let __safeDI_apiBuilder_screenBuilder = __safeDI_apiBuilder.screenBuilder
		        @inline(never) func __safeDI_detailBuilder(__safeDI_apiBuilder_detailBuilder: __safeDI_ApiCarrier_Detail<any Api>) -> Detail {
		            let api: any Api = __safeDI_apiBuilder_detailBuilder.api()
		            return Detail(api: api)
		        }
		        @inline(never) func __safeDI_screenBuilder(id: Int) -> Screen {
		            let secret = Secret()
		            let __safeDI_Screen_values2 = __safeDI_ScreenValues2(id: id, secret: secret)
		            let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder_screenBuilder.detailBuilder(__safeDI_Screen_values2)
		            let detailBuilder = Instantiator<Detail> {
		                __safeDI_detailBuilder(__safeDI_apiBuilder_detailBuilder: __safeDI_apiBuilder_detailBuilder)
		            }
		            return Screen(id: id, secret: secret, detailBuilder: detailBuilder)
		        }
		        let screenBuilder = Instantiator<Screen> {
		            __safeDI_screenBuilder(id: $0)
		        }
		        self.init(screenBuilder: screenBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_64715D07E7979647 {}
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
		            .init(detailBuilder: { values in __safeDI_apiBuilder_Home_Detail_Scope(id: values.id) })
		        }
		        func __safeDI_apiBuilder_Home_Detail_Scope(id: Int) -> Home.__safeDI_ApiCarrier_Detail<any Api> {
		            .init(api: {
		                let api: any Api = ApiImpl(id: id)
		                return api
		            })
		        }
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_64715D07E7979647.self // If this line does not compile, compile the code SafeDI generates for module Seam into Seam: under Bazel, add Seam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		"""])
	}

	// MARK: Fixtures

	/// `Home`, a public seam with an `internal` initializer, builds `Screen`, an `internal` type that binds `Secret`, an
	/// `internal` type, before `Detail`, whose public place of `Api` the calling module fills reading only `id`.
	private static let internalValueSeam = [
		"public protocol Api {}",
		"""
		@Instantiable
		final class Secret: Instantiable {
		    init() {}
		}
		""",
		seamFixtureType(named: "Detail", isFinalClass: true, declarations: ["@Instantiated let api: any Api"]),
		"""
		@Instantiable
		final class Screen: Instantiable {
		    init(id: Int, secret: Secret, detailBuilder: Instantiator<Detail>) {
		        self.id = id
		        self.secret = secret
		        self.detailBuilder = detailBuilder
		    }

		    @Forwarded let id: Int
		    @Instantiated let secret: Secret
		    @Instantiated let detailBuilder: Instantiator<Detail>
		}
		""",
		"""
		@Instantiable(generateDependencyTree: true)
		public final class Home: Instantiable {
		    init(screenBuilder: Instantiator<Screen>) {
		        self.screenBuilder = screenBuilder
		    }

		    @Instantiated let screenBuilder: Instantiator<Screen>
		}
		""",
	]

	private var filesToDelete: [URL]
}
