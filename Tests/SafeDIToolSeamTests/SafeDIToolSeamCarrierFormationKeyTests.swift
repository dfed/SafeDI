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

/// The function that forms a carrier is keyed by its family and its isolation: a carrier formed in a `@MainActor` root's
/// initializer and again inside a `@Sendable` builder function is formed by two functions, and a `nonisolated` root whose
/// plain and `@Sendable` levels carry equal values forms each family's carrier in a function of its own.
struct SafeDIToolSeamCarrierFormationKeyTests: ~Copyable {
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
	mutating func generate_formsCarrierInTwoFunctions_whenMainActorRootAndSendableLevelFormIt() async throws {
		let modules = CarrierCells.modules(
			seam: Self.seam,
			app: [Self.impl, CarrierCellRoot.mainActorClassRoot.declaration(building: "home: Home")],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		CarrierCells.expectGeneratedFiles(output.modules["Seam"]?.generatedFiles, ["Seam.swift": generatedFileHeader + """
		extension Home {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let detail: __safeDI_ApiCarrier_Detail<__safeDI_Built>

		        public init(detail: __safeDI_ApiCarrier_Detail<__safeDI_Built>) {
		            self.detail = detail
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(detail: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Detail<__safeDI_Built> {
		        public let api: () -> __safeDI_Built

		        public init(api: @escaping () -> __safeDI_Built) {
		            self.api = api
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(api: { __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Screen<__safeDI_Built> {
		        public let detail: (Int) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>

		        public init(detail: @escaping (Int) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>) {
		            self.detail = detail
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(detail: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiSendableCarrier<__safeDI_Built>: Sendable {
		        public let screenBuilder: @Sendable () -> __safeDI_ApiCarrier_Screen<__safeDI_Built>

		        public init(screenBuilder: @escaping @Sendable () -> __safeDI_ApiCarrier_Screen<__safeDI_Built>) {
		            self.screenBuilder = screenBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(screenBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>, __safeDI_apiSendableBuilder: __safeDI_ApiSendableCarrier<any Api>) {
		        let __safeDI_apiBuilder_detail = __safeDI_apiBuilder.detail
		        func __safeDI_detail() -> Detail {
		            let api: any Api = __safeDI_apiBuilder_detail.api()
		            return Detail(api: api)
		        }
		        let detail: Detail = __safeDI_detail()
		        @Sendable nonisolated func __safeDI_detail_(__safeDI_apiSendableBuilder_detail: __safeDI_ApiCarrier_Detail<any Api>) -> Detail {
		            let api: any Api = __safeDI_apiSendableBuilder_detail.api()
		            return Detail(api: api)
		        }
		        @Sendable nonisolated func __safeDI_screenBuilder(id: Int) -> Screen {
		            let __safeDI_apiSendableBuilder_screenBuilder = __safeDI_apiSendableBuilder.screenBuilder()
		            let __safeDI_apiSendableBuilder_detail = __safeDI_apiSendableBuilder_screenBuilder.detail(id)
		            let detail: Detail = __safeDI_detail_(__safeDI_apiSendableBuilder_detail: __safeDI_apiSendableBuilder_detail)
		            return Screen(id: id, detail: detail)
		        }
		        let screenBuilder = SendableInstantiator<Screen> {
		            __safeDI_screenBuilder(id: $0)
		        }
		        self.init(detail: detail, screenBuilder: screenBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_51CCE29F2E3406F9 {}
		}
		"""])
		CarrierCells.expectGeneratedFiles(output.modules["App"]?.generatedFiles, ["App.swift": generatedFileHeader + """
		#if canImport(Seam)
		import Seam
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		            .init(detail: __safeDI_apiBuilder_Home_Detail_Scope())
		        }
		        @Sendable nonisolated func __safeDI_apiBuilder_Home_Detail_Scope() -> Home.__safeDI_ApiCarrier_Detail<any Api> {
		            .init(api: {
		                let api: any Api = ApiImpl()
		                return api
		            })
		        }
		        @Sendable nonisolated func __safeDI_apiSendableBuilder_Home() -> Home.__safeDI_ApiSendableCarrier<any Api> {
		            .init(screenBuilder: { __safeDI_apiBuilder_Home_Screen_Scope() })
		        }
		        @Sendable nonisolated func __safeDI_apiBuilder_Home_Screen_Scope() -> Home.__safeDI_ApiCarrier_Screen<any Api> {
		            .init(detail: { values_id in __safeDI_apiBuilder_Home_Detail_Scope() })
		        }
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_51CCE29F2E3406F9.self // If this line does not compile, compile the code SafeDI generates for module Seam into Seam: under Bazel, add Seam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home(), __safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_formsEachFamilysCarrierApart_whenNonisolatedRootsFamiliesCarryEqualValues() async throws {
		let modules = CarrierCells.modules(
			seam: Self.seam,
			app: [Self.impl, CarrierCellRoot.attributedNonisolatedRoot.declaration(building: "home: Home")],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		CarrierCells.expectGeneratedFiles(output.modules["Seam"]?.generatedFiles, ["Seam.swift": generatedFileHeader + """
		extension Home {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let detail: __safeDI_ApiCarrier_Detail<__safeDI_Built>

		        public init(detail: __safeDI_ApiCarrier_Detail<__safeDI_Built>) {
		            self.detail = detail
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(detail: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Detail<__safeDI_Built> {
		        public let api: () -> __safeDI_Built

		        public init(api: @escaping () -> __safeDI_Built) {
		            self.api = api
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(api: { __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Screen<__safeDI_Built> {
		        public let detail: (Int) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>

		        public init(detail: @escaping (Int) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>) {
		            self.detail = detail
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(detail: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiSendableCarrier<__safeDI_Built>: Sendable {
		        public let screenBuilder: @Sendable () -> __safeDI_ApiCarrier_Screen<__safeDI_Built>

		        public init(screenBuilder: @escaping @Sendable () -> __safeDI_ApiCarrier_Screen<__safeDI_Built>) {
		            self.screenBuilder = screenBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(screenBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>, __safeDI_apiSendableBuilder: __safeDI_ApiSendableCarrier<any Api>) {
		        let __safeDI_apiBuilder_detail = __safeDI_apiBuilder.detail
		        func __safeDI_detail() -> Detail {
		            let api: any Api = __safeDI_apiBuilder_detail.api()
		            return Detail(api: api)
		        }
		        let detail: Detail = __safeDI_detail()
		        @Sendable nonisolated func __safeDI_detail_(__safeDI_apiSendableBuilder_detail: __safeDI_ApiCarrier_Detail<any Api>) -> Detail {
		            let api: any Api = __safeDI_apiSendableBuilder_detail.api()
		            return Detail(api: api)
		        }
		        @Sendable nonisolated func __safeDI_screenBuilder(id: Int) -> Screen {
		            let __safeDI_apiSendableBuilder_screenBuilder = __safeDI_apiSendableBuilder.screenBuilder()
		            let __safeDI_apiSendableBuilder_detail = __safeDI_apiSendableBuilder_screenBuilder.detail(id)
		            let detail: Detail = __safeDI_detail_(__safeDI_apiSendableBuilder_detail: __safeDI_apiSendableBuilder_detail)
		            return Screen(id: id, detail: detail)
		        }
		        let screenBuilder = SendableInstantiator<Screen> {
		            __safeDI_screenBuilder(id: $0)
		        }
		        self.init(detail: detail, screenBuilder: screenBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_51CCE29F2E3406F9 {}
		}
		"""])
		CarrierCells.expectGeneratedFiles(output.modules["App"]?.generatedFiles, ["App.swift": generatedFileHeader + """
		#if canImport(Seam)
		import Seam
		#endif

		extension Root {
		    @MainActor public convenience init() {
		        func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		            .init(detail: __safeDI_apiBuilder_Home_Detail_Scope())
		        }
		        @Sendable nonisolated func __safeDI_apiBuilder_Home_Detail_Scope() -> Home.__safeDI_ApiCarrier_Detail<any Api> {
		            .init(api: {
		                let api: any Api = ApiImpl()
		                return api
		            })
		        }
		        @Sendable nonisolated func __safeDI_apiSendableBuilder_Home() -> Home.__safeDI_ApiSendableCarrier<any Api> {
		            .init(screenBuilder: { __safeDI_apiBuilder_Home_Screen_Scope() })
		        }
		        @Sendable nonisolated func __safeDI_apiBuilder_Home_Screen_Scope() -> Home.__safeDI_ApiCarrier_Screen<any Api> {
		            .init(detail: { values_id in __safeDI_apiBuilder_Home_Detail_Scope() })
		        }
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_51CCE29F2E3406F9.self // If this line does not compile, compile the code SafeDI generates for module Seam into Seam: under Bazel, add Seam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home(), __safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		"""])
	}

	// MARK: Fixtures

	/// `Home` builds `Detail`, whose place of `Api` is filled by a type on the main actor, by value and in a
	/// `SendableInstantiator` beneath `Screen`, so the plain carrier of `Detail` is formed in both families.
	private static let seam = [
		"public protocol Api {}",
		seamFixtureType(named: "Detail", isFinalClass: true, declarations: ["@Instantiated let api: any Api"]),
		seamFixtureType(named: "Screen", isFinalClass: true, declarations: ["@Forwarded let id: Int", "@Instantiated let detail: Detail"]),
		seamFixtureType(named: "Home", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let detail: Detail", "@Instantiated let screenBuilder: SendableInstantiator<Screen>"]),
	]

	private static let impl = CarrierCells.fulfillingImpl(named: "ApiImpl", fulfilling: "Api", reading: [])

	private var filesToDelete: [URL]
}
