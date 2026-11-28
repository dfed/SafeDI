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

/// A seam takes a builder struct for each hole type, one stored function per member, which its initializer only
/// generated code calls calls where the seam binds each level, so what a
/// level's member returns captures only what the calling module reads from it. Its readable initializer takes a closure
/// that takes nothing. The module that calls the seam writes one function per level, each returning that level's struct;
/// a seam that passes up another seam's places takes a struct whose member for that seam returns that seam's struct.
struct SafeDIToolSeamBuilderStructTests: ~Copyable {
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
	mutating func generate_takesBuilderStruct_whenSeamsOnlyPlaceIsAtItsBoundary() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.fixtures["boundary"] ?? [], integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Home {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let api: () -> __safeDI_Built

		        public init(api: @escaping () -> __safeDI_Built) {
		            self.api = api
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(api: { __safeDI_builder() })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public init(apiBuilder: @escaping () -> any Api) {
		        self.init(__safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let api: any Api = __safeDI_apiBuilder.api()
		        self.init(api: api)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_59C182C3751C58E0 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		            .init(api: {
		                let api: any Api = LiveApi()
		                return api
		            })
		        }
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_59C182C3751C58E0.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		"""])
		try Self.expectCompiles(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_freesWhatInlineFrees_whenFillReadsValueBoundTwoLevelsAboveThePlace() async throws {
		// The adopter's shape: `Home` binds `navigator` and `logger`, then `detailBuilder`, whose `Detail` builds `Leaf`, whose
		// `api` only `App` builds, reading `logger`. A builder that held the case of `Home`'s level would keep the navigator
		// alive with every `Detail`; the struct's member hands its level function `logger` alone.
		let modules = Self.fixtures["adopter"] ?? []
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Home {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let detailBuilder: (Navigator, Logger) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>

		        public init(detailBuilder: @escaping (Navigator, Logger) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>) {
		            self.detailBuilder = detailBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(detailBuilder: { _, _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Detail<__safeDI_Built> {
		        public let leafBuilder: __safeDI_ApiCarrier_Leaf<__safeDI_Built>

		        public init(leafBuilder: __safeDI_ApiCarrier_Leaf<__safeDI_Built>) {
		            self.leafBuilder = leafBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(leafBuilder: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Leaf<__safeDI_Built> {
		        public let api: () -> __safeDI_Built

		        public init(api: @escaping () -> __safeDI_Built) {
		            self.api = api
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(api: { __safeDI_builder() })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(apiBuilder: @escaping () -> any Api) {
		        self.init(__safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let navigator = Navigator()
		        let logger = Logger()
		        let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder.detailBuilder(navigator, logger)
		        @inline(never) func __safeDI_leafBuilder(__safeDI_apiBuilder_leafBuilder: __safeDI_ApiCarrier_Leaf<any Api>) -> Leaf {
		            let api: any Api = __safeDI_apiBuilder_leafBuilder.api()
		            return Leaf(api: api)
		        }
		        @inline(never) func __safeDI_detailBuilder() -> Detail {
		            let __safeDI_apiBuilder_leafBuilder = __safeDI_apiBuilder_detailBuilder.leafBuilder
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(__safeDI_apiBuilder_leafBuilder: __safeDI_apiBuilder_leafBuilder)
		            }
		            return Detail(leafBuilder: leafBuilder)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        self.init(navigator: navigator, logger: logger, detailBuilder: detailBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_74C2C250104CF6FF {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		            .init(detailBuilder: { values_navigator, values_logger in __safeDI_apiBuilder_Home_Detail_Scope(logger: values_logger) })
		        }
		        func __safeDI_apiBuilder_Home_Detail_Scope(logger: Logger) -> Home.__safeDI_ApiCarrier_Detail<any Api> {
		            .init(leafBuilder: __safeDI_apiBuilder_Home_Leaf_Scope(logger: logger))
		        }
		        func __safeDI_apiBuilder_Home_Leaf_Scope(logger: Logger) -> Home.__safeDI_ApiCarrier_Leaf<any Api> {
		            .init(api: {
		                let api: any Api = LiveApi(logger: logger)
		                return api
		            })
		        }
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_74C2C250104CF6FF.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		"""])
		try Self.expectCompiles(output)
		let description = try await DifferentialValueOracle.describe(
			DifferentialValuePath(output: output, modules: modules),
			probes: [DifferentialValueProbe("navigatorIsFreedWhileItsDetailLives()")],
			filesToDelete: &filesToDelete,
		)
		if compileVerificationIsEnabled {
			#expect(description == """
			probe navigatorIsFreedWhileItsDetailLives()
			Bool true

			""")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsSendableMemberAtTopOfSendableFunction_whenPlaceIsBuiltInsideSendableInstantiator() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.fixtures["sendable"] ?? [], integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Home {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Worker<__safeDI_Built> {
		        public let detail: (Logger) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>

		        public init(detail: @escaping (Logger) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>) {
		            self.detail = detail
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(detail: { _ in .init(__safeDI_noScope: __safeDI_builder) })
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
		    nonisolated public final class __safeDI_ApiSendableCarrier<__safeDI_Built>: Sendable {
		        public let workerBuilder: @Sendable () -> __safeDI_ApiCarrier_Worker<__safeDI_Built>

		        public init(workerBuilder: @escaping @Sendable () -> __safeDI_ApiCarrier_Worker<__safeDI_Built>) {
		            self.workerBuilder = workerBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(workerBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(apiSendableBuilder: @escaping @Sendable () -> any Api) {
		        self.init(__safeDI_apiSendableBuilder: .init(__safeDI_noScope: apiSendableBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_apiSendableBuilder: __safeDI_ApiSendableCarrier<any Api>) {
		        @inline(never) @Sendable nonisolated func __safeDI_detail(__safeDI_apiSendableBuilder_detail: __safeDI_ApiCarrier_Detail<any Api>) -> Detail {
		            let api: any Api = __safeDI_apiSendableBuilder_detail.api()
		            return Detail(api: api)
		        }
		        @inline(never) @Sendable nonisolated func __safeDI_workerBuilder() -> Worker {
		            let __safeDI_apiSendableBuilder_workerBuilder = __safeDI_apiSendableBuilder.workerBuilder()
		            let logger = Logger()
		            let __safeDI_apiSendableBuilder_detail = __safeDI_apiSendableBuilder_workerBuilder.detail(logger)
		            let detail: Detail = __safeDI_detail(__safeDI_apiSendableBuilder_detail: __safeDI_apiSendableBuilder_detail)
		            return Worker(logger: logger, detail: detail)
		        }
		        let workerBuilder = SendableInstantiator<Worker>(__safeDI_workerBuilder)
		        self.init(workerBuilder: workerBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_73325E56E192F598 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        @Sendable nonisolated func __safeDI_apiSendableBuilder_Home() -> Home.__safeDI_ApiSendableCarrier<any Api> {
		            .init(workerBuilder: { __safeDI_apiBuilder_Home_Worker_Scope() })
		        }
		        @Sendable nonisolated func __safeDI_apiBuilder_Home_Worker_Scope() -> Home.__safeDI_ApiCarrier_Worker<any Api> {
		            .init(detail: { values_logger in __safeDI_apiBuilder_Home_Detail_Scope(logger: values_logger) })
		        }
		        @Sendable nonisolated func __safeDI_apiBuilder_Home_Detail_Scope(logger: Logger) -> Home.__safeDI_ApiCarrier_Detail<any Api> {
		            .init(api: {
		                let api: any Api = LiveApi(logger: logger)
		                return api
		            })
		        }
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_73325E56E192F598.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Home(__safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		"""])
		try Self.expectCompiles(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_returnsNextSendableStructFromOuterMember_whenTwoSendableFunctionsLeadToPlace() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.fixtures["twoSendable"] ?? [], integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Home {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Inner<__safeDI_Built> {
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
		    nonisolated public final class __safeDI_ApiSendableCarrier<__safeDI_Built>: Sendable {
		        public let outerBuilder_Sendable: __safeDI_ApiSendableCarrier_Outer<__safeDI_Built>

		        public init(outerBuilder_Sendable: __safeDI_ApiSendableCarrier_Outer<__safeDI_Built>) {
		            self.outerBuilder_Sendable = outerBuilder_Sendable
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(outerBuilder_Sendable: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiSendableCarrier_Outer<__safeDI_Built>: Sendable {
		        public let innerBuilder: @Sendable () -> __safeDI_ApiCarrier_Inner<__safeDI_Built>

		        public init(innerBuilder: @escaping @Sendable () -> __safeDI_ApiCarrier_Inner<__safeDI_Built>) {
		            self.innerBuilder = innerBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(innerBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(apiSendableBuilder: @escaping @Sendable () -> any Api) {
		        self.init(__safeDI_apiSendableBuilder: .init(__safeDI_noScope: apiSendableBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_apiSendableBuilder: __safeDI_ApiSendableCarrier<any Api>) {
		        @inline(never) @Sendable nonisolated func __safeDI_innerBuilder(__safeDI_apiSendableBuilder_outerBuilder_Sendable: __safeDI_ApiSendableCarrier_Outer<any Api>) -> Inner {
		            let __safeDI_apiSendableBuilder_innerBuilder = __safeDI_apiSendableBuilder_outerBuilder_Sendable.innerBuilder()
		            let __safeDI_apiSendableBuilder_detail = __safeDI_apiSendableBuilder_innerBuilder.detail
		            let detail: Detail = __safeDI_detail(__safeDI_apiSendableBuilder_detail: __safeDI_apiSendableBuilder_detail)
		            return Inner(detail: detail)
		        }
		        @inline(never) @Sendable nonisolated func __safeDI_detail(__safeDI_apiSendableBuilder_detail: __safeDI_ApiCarrier_Detail<any Api>) -> Detail {
		            let api: any Api = __safeDI_apiSendableBuilder_detail.api()
		            return Detail(api: api)
		        }
		        @inline(never) @Sendable nonisolated func __safeDI_outerBuilder() -> Outer {
		            let __safeDI_apiSendableBuilder_outerBuilder_Sendable = __safeDI_apiSendableBuilder.outerBuilder_Sendable
		            let innerBuilder = SendableInstantiator<Inner> {
		                __safeDI_innerBuilder(__safeDI_apiSendableBuilder_outerBuilder_Sendable: __safeDI_apiSendableBuilder_outerBuilder_Sendable)
		            }
		            return Outer(innerBuilder: innerBuilder)
		        }
		        let outerBuilder = SendableInstantiator<Outer>(__safeDI_outerBuilder)
		        self.init(outerBuilder: outerBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_0C122015F6A26564 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        @Sendable nonisolated func __safeDI_apiSendableBuilder_Home() -> Home.__safeDI_ApiSendableCarrier<any Api> {
		            .init(outerBuilder_Sendable: __safeDI_apiSendableBuilder_Home_Outer_Scope())
		        }
		        @Sendable nonisolated func __safeDI_apiSendableBuilder_Home_Outer_Scope() -> Home.__safeDI_ApiSendableCarrier_Outer<any Api> {
		            .init(innerBuilder: { __safeDI_apiBuilder_Home_Inner_Scope() })
		        }
		        @Sendable nonisolated func __safeDI_apiBuilder_Home_Inner_Scope() -> Home.__safeDI_ApiCarrier_Inner<any Api> {
		            .init(detail: __safeDI_apiBuilder_Home_Detail_Scope())
		        }
		        @Sendable nonisolated func __safeDI_apiBuilder_Home_Detail_Scope() -> Home.__safeDI_ApiCarrier_Detail<any Api> {
		            .init(api: {
		                let api: any Api = LiveApi()
		                return api
		            })
		        }
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_0C122015F6A26564.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Home(__safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		"""])
		try Self.expectCompiles(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsCalledSeamMemberOfOuterSeamsStruct_whenOuterSeamPassesUpSwitchedSeamsPlace() async throws {
		// `Innermost`'s place forwards nothing, so it takes a builder struct; `Inner` passes it up and takes a struct whose
		// member for `Innermost` returns `Innermost`'s, which `Inner` hands `Innermost`. While only a `Detail` lives, `Inner`
		// and its `Navigator` are freed and `Innermost`'s `Logger` is not.
		let modules = Self.fixtures["deep"] ?? []
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Inner {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
		        public let innermost: Innermost.__safeDI_ServiceCarrier<__safeDI_Built>

		        public init(innermost: Innermost.__safeDI_ServiceCarrier<__safeDI_Built>) {
		            self.innermost = innermost
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(innermost: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
		        let navigator = Navigator()
		        @inline(never) func __safeDI_innermost() -> Innermost {
		            _ = Innermost.__safeDI_Innermost_E286A5310BB7EA4E.self
		            return Innermost(__safeDI_serviceBuilder: __safeDI_serviceBuilder.innermost)
		        }
		        let innermost: Innermost = __safeDI_innermost()
		        self.init(navigator: navigator, innermost: innermost)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_6B37CE7AAF7A1362 {}
		}

		extension Innermost {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
		        public let detailBuilder: (Logger) -> __safeDI_ServiceCarrier_Detail<__safeDI_Built>

		        public init(detailBuilder: @escaping (Logger) -> __safeDI_ServiceCarrier_Detail<__safeDI_Built>) {
		            self.detailBuilder = detailBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(detailBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ServiceCarrier_Detail<__safeDI_Built> {
		        public let service: () -> __safeDI_Built

		        public init(service: @escaping () -> __safeDI_Built) {
		            self.service = service
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(service: { __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
		        let logger = Logger()
		        let __safeDI_serviceBuilder_detailBuilder = __safeDI_serviceBuilder.detailBuilder(logger)
		        @inline(never) func __safeDI_detailBuilder() -> Detail {
		            let service: any Service = __safeDI_serviceBuilder_detailBuilder.service()
		            return Detail(service: service)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        self.init(logger: logger, detailBuilder: detailBuilder)
		    }
		}

		extension Innermost {
		    public enum __safeDI_Innermost_E286A5310BB7EA4E {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_serviceBuilder_Inner() -> Inner.__safeDI_ServiceCarrier<any Service> {
		            .init(innermost: __safeDI_serviceBuilder_Innermost())
		        }
		        func __safeDI_serviceBuilder_Innermost() -> Innermost.__safeDI_ServiceCarrier<any Service> {
		            .init(detailBuilder: { values_logger in __safeDI_serviceBuilder_Innermost_Detail_Scope(logger: values_logger) })
		        }
		        func __safeDI_serviceBuilder_Innermost_Detail_Scope(logger: Logger) -> Innermost.__safeDI_ServiceCarrier_Detail<any Service> {
		            .init(service: {
		                let service: any Service = DefaultService(logger: logger)
		                return service
		            })
		        }
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_6B37CE7AAF7A1362.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner())
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(inner: inner)
		    }
		}
		"""])
		try Self.expectCompiles(output)
		try await expectValuesEqualInlineBuild(modules: modules, probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("freedWhileOnlyDetailLives()")])
		let description = try await DifferentialValueOracle.describe(
			DifferentialValuePath(output: output, modules: modules),
			probes: [DifferentialValueProbe("freedWhileOnlyDetailLives()")],
			filesToDelete: &filesToDelete,
		)
		if compileVerificationIsEnabled {
			#expect(description == """
			probe freedWhileOnlyDetailLives()
			Array<Bool>
			  0: Bool true
			  1: Bool true
			  2: Bool false

			""")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsEachLevelsStructInOneFunction_whenOuterSeamPassesUpSwitchedSeamWhoseLevelsLoop() async throws {
		// `Hub`'s `T` and `C` each build the other. `Shell` passes `Hub`'s place up and takes a struct whose member returns
		// `Hub`'s: `Root` builds each level's struct in one function, and a member that opens a level again calls that level's
		// function. Holding only a `C` two levels deep keeps alive one `Mark` and no `MarkReader`, and holding only a `T`
		// five levels deep keeps alive one of each.
		let modules = Self.fixtures["tangle"] ?? []
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Middle"]?.generatedFiles == ["Middle.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Shell {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let hub: Hub.__safeDI_ApiCarrier<__safeDI_Built>

		        public init(hub: Hub.__safeDI_ApiCarrier<__safeDI_Built>) {
		            self.hub = hub
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(hub: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_mark: @autoclosure @escaping () -> Mark?, __safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let mark = LazilyInstantiated<Mark?>(__safeDI_mark)
		        @inline(never) func __safeDI_hub() -> Hub {
		            _ = Hub.__safeDI_Hub_FA5369582812EEA1.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Hub(__safeDI_mark: mark.instance, __safeDI_apiBuilder: __safeDI_apiBuilder.hub)
		        }
		        let hub: Hub = __safeDI_hub()
		        self.init(hub: hub)
		    }
		}

		extension Shell {
		    public enum __safeDI_Shell_E29A93ED17334408 {}
		}
		"""])
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Hub {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let tBuilder: (LazilyInstantiated<Mark?>) -> __safeDI_ApiCarrier_T<__safeDI_Built>
		        public let cBuilder: (LazilyInstantiated<Mark?>, Instantiator<T>) -> __safeDI_ApiCarrier_C<__safeDI_Built>

		        public init(tBuilder: @escaping (LazilyInstantiated<Mark?>) -> __safeDI_ApiCarrier_T<__safeDI_Built>, cBuilder: @escaping (LazilyInstantiated<Mark?>, Instantiator<T>) -> __safeDI_ApiCarrier_C<__safeDI_Built>) {
		            self.tBuilder = tBuilder
		            self.cBuilder = cBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(tBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) }, cBuilder: { _, _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_T<__safeDI_Built> {
		        public let cBuilder: (Mark?, MarkReader) -> __safeDI_ApiCarrier_C<__safeDI_Built>
		        public let api: (Mark?, MarkReader, Instantiator<C>) -> __safeDI_Built

		        public init(cBuilder: @escaping (Mark?, MarkReader) -> __safeDI_ApiCarrier_C<__safeDI_Built>, api: @escaping (Mark?, MarkReader, Instantiator<C>) -> __safeDI_Built) {
		            self.cBuilder = cBuilder
		            self.api = api
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(cBuilder: { _, _ in .init(__safeDI_noScope: __safeDI_builder) }, api: { _, _, _ in __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_C<__safeDI_Built> {
		        public let tBuilder: (Mark) -> __safeDI_ApiCarrier_T<__safeDI_Built>

		        public init(tBuilder: @escaping (Mark) -> __safeDI_ApiCarrier_T<__safeDI_Built>) {
		            self.tBuilder = tBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(tBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_mark __safeDI_mark_: @autoclosure @escaping () -> Mark?, __safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let mark = LazilyInstantiated<Mark?>(__safeDI_mark_)
		        let __safeDI_apiBuilder_tBuilder = __safeDI_apiBuilder.tBuilder(mark)
		        @inline(never) func __safeDI_tBuilder(mark: Mark?) -> T {
		            let reader = MarkReader(mark: mark)
		            @inline(never) func __safeDI_cBuilder() -> C {
		                let mark = Mark()
		                let tBuilder = Instantiator<T> {
		                    __safeDI_tBuilder(mark: mark)
		                }
		                return C(mark: mark, tBuilder: tBuilder)
		            }
		            let cBuilder = Instantiator<C>(__safeDI_cBuilder)
		            let api: any Api = __safeDI_apiBuilder_tBuilder.api(mark, reader, cBuilder)
		            return T(reader: reader, cBuilder: cBuilder, api: api)
		        }
		        let tBuilder = Instantiator<T> {
		            __safeDI_tBuilder(mark: mark.instance)
		        }
		        let __safeDI_apiBuilder_cBuilder = __safeDI_apiBuilder.cBuilder(mark, tBuilder)
		        @inline(never) func __safeDI_cBuilder() -> C {
		            let mark = Mark()
		            let __safeDI_apiBuilder_tBuilder = __safeDI_apiBuilder_cBuilder.tBuilder(mark)
		            @inline(never) func __safeDI_tBuilder() -> T {
		                let reader = MarkReader(mark: mark)
		                let cBuilder = Instantiator<C>(__safeDI_cBuilder)
		                let api: any Api = __safeDI_apiBuilder_tBuilder.api(mark, reader, cBuilder)
		                return T(reader: reader, cBuilder: cBuilder, api: api)
		            }
		            let tBuilder = Instantiator<T>(__safeDI_tBuilder)
		            return C(mark: mark, tBuilder: tBuilder)
		        }
		        let cBuilder = Instantiator<C>(__safeDI_cBuilder)
		        self.init(tBuilder: tBuilder, cBuilder: cBuilder)
		    }
		}

		extension Hub {
		    public enum __safeDI_Hub_FA5369582812EEA1 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Middle)
		import Middle
		#endif

		extension Root {
		    public init() {
		        func __safeDI_apiBuilder_Shell() -> Shell.__safeDI_ApiCarrier<any Api> {
		            .init(hub: __safeDI_apiBuilder_Hub())
		        }
		        func __safeDI_apiBuilder_Hub() -> Hub.__safeDI_ApiCarrier<any Api> {
		            .init(tBuilder: { values_mark in __safeDI_apiBuilder_Hub_T_Scope() }, cBuilder: { values_mark, values_tBuilder in __safeDI_apiBuilder_Hub_C_Scope() })
		        }
		        func __safeDI_apiBuilder_Hub_T_Scope() -> Hub.__safeDI_ApiCarrier_T<any Api> {
		            .init(
		                cBuilder: { values_mark, values_reader in __safeDI_apiBuilder_Hub_C_Scope() },
		                api: { scope_mark, scope_reader, scope_cBuilder in
		                    let mark = scope_mark
		                    let api: any Api = LiveApi(mark: mark)
		                    return api
		                }
		            )
		        }
		        func __safeDI_apiBuilder_Hub_C_Scope() -> Hub.__safeDI_ApiCarrier_C<any Api> {
		            .init(tBuilder: { values_mark in __safeDI_apiBuilder_Hub_T_Scope() })
		        }
		        func __safeDI_shell() -> Shell {
		            _ = Shell.__safeDI_Shell_E29A93ED17334408.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Shell(__safeDI_mark: nil, __safeDI_apiBuilder: __safeDI_apiBuilder_Shell())
		        }
		        let shell: Shell = __safeDI_shell()
		        self.init(shell: shell)
		    }
		}
		"""])
		try Self.expectCompiles(output)
		try await expectValuesEqualInlineBuild(modules: modules, probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().shell.hub.tBuilder.instantiate().cBuilder.instantiate().tBuilder.instantiate()"), DifferentialValueProbe("liveMarksAndReaders(holdingOnlyLevelAtDepth: 2)"), DifferentialValueProbe("liveMarksAndReaders(holdingOnlyLevelAtDepth: 5)")])
		let description = try await DifferentialValueOracle.describe(
			DifferentialValuePath(output: output, modules: modules),
			probes: [DifferentialValueProbe("liveMarksAndReaders(holdingOnlyLevelAtDepth: 2)"), DifferentialValueProbe("liveMarksAndReaders(holdingOnlyLevelAtDepth: 5)")],
			filesToDelete: &filesToDelete,
		)
		if compileVerificationIsEnabled {
			#expect(description == """
			probe liveMarksAndReaders(holdingOnlyLevelAtDepth: 2)
			Array<Int>
			  0: Int 1
			  1: Int 0
			probe liveMarksAndReaders(holdingOnlyLevelAtDepth: 5)
			Array<Int>
			  0: Int 1
			  1: Int 1

			""")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsCalledSeamStructOverCallersStruct_whenOuterSeamsCaseCarriesSwitchedSeamsScope() async throws {
		// `Outer` fills `Inner`'s `service` with a type that holds `Outer`'s own place, so `Outer`'s case carries the scope
		// `Inner` hands the fill: `Root` builds `Inner`'s struct over `Outer`'s level struct, and `Outer`'s dispatchers take it
		// and hand `Inner` a struct whose members call it and build the fill from what it returns. A screen keeps alive only
		// its own service's gadget.
		let modules = Self.fixtures["insideFill"] ?? []
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Middle"]?.generatedFiles == ["Middle.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Outer {
		    nonisolated public enum SafeDIScope_Gadget {
		        nonisolated public struct inner_serviceBuilder_Values {
		            public let tag: Tag
		        }

		        nonisolated public enum DefaultService_Scope {
		            nonisolated public struct gadget_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let gadget: (gadget_Values) -> __safeDI_Built

		                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
		                    self.gadget = gadget
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(gadget: { _ in __safeDI_builder() })
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let inner_serviceBuilder: (inner_serviceBuilder_Values) -> Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(inner_serviceBuilder: @escaping (inner_serviceBuilder_Values) -> Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.inner_serviceBuilder = inner_serviceBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(inner_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
		            }
		        }
		    }

		    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
		        let tag = Tag()
		        let __safeDI_gadgetBuilder_inner_serviceBuilder = __safeDI_gadgetBuilder.inner_serviceBuilder(SafeDIScope_Gadget.inner_serviceBuilder_Values(tag: tag))
		        @inline(never) func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_C5CF4A1EC903198D.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            @inline(never) func __safeDI_serviceBuilder_Inner_service(_ scope_screenBuilder: Instantiator<Screen>, __safeDI_inner_serviceBuilder: SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
		                @inline(never) func __safeDI_service() -> DefaultService {
		                    let gadget: any Gadget = __safeDI_inner_serviceBuilder.gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values())
		                    return DefaultService(gadget: gadget)
		                }
		                let service: any Service = __safeDI_service()
		                return service
		            }
		            @inline(never) func __safeDI_serviceBuilder_Inner_Screen_Scope_service(_ scope_id: Int, __safeDI_inner_serviceBuilder: SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
		                @inline(never) func __safeDI_service() -> DefaultService {
		                    let gadget: any Gadget = __safeDI_inner_serviceBuilder.gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values())
		                    return DefaultService(gadget: gadget)
		                }
		                let service: any Service = __safeDI_service()
		                return service
		            }
		            @inline(never) func __safeDI_serviceBuilder_Inner(up: Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_ServiceCarrier<any Service> {
		                .init(screenBuilder: __safeDI_serviceBuilder_Inner_Screen_Scope(up: up.screenBuilder), service: { scope_screenBuilder in __safeDI_serviceBuilder_Inner_service(scope_screenBuilder, __safeDI_inner_serviceBuilder: up.service(scope_screenBuilder)) })
		            }
		            @inline(never) func __safeDI_serviceBuilder_Inner_Screen_Scope(up: Inner.__safeDI_ServiceCarrier_Screen<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_ServiceCarrier_Screen<any Service> {
		                .init(service: { scope_id in __safeDI_serviceBuilder_Inner_Screen_Scope_service(scope_id, __safeDI_inner_serviceBuilder: up.service(scope_id)) })
		            }
		            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner(up: __safeDI_gadgetBuilder_inner_serviceBuilder))
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(tag: tag, inner: inner)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_3FF816B8F02AA356 {}
		}
		"""])
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Inner {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
		        public let screenBuilder: __safeDI_ServiceCarrier_Screen<__safeDI_Built>
		        public let service: (Instantiator<Screen>) -> __safeDI_Built

		        public init(screenBuilder: __safeDI_ServiceCarrier_Screen<__safeDI_Built>, service: @escaping (Instantiator<Screen>) -> __safeDI_Built) {
		            self.screenBuilder = screenBuilder
		            self.service = service
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(screenBuilder: .init(__safeDI_noScope: __safeDI_builder), service: { _ in __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ServiceCarrier_Screen<__safeDI_Built> {
		        public let service: (Int) -> __safeDI_Built

		        public init(service: @escaping (Int) -> __safeDI_Built) {
		            self.service = service
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(service: { _ in __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
		        let __safeDI_serviceBuilder_screenBuilder = __safeDI_serviceBuilder.screenBuilder
		        @inline(never) func __safeDI_screenBuilder(id: Int) -> Screen {
		            let service: any Service = __safeDI_serviceBuilder_screenBuilder.service(id)
		            return Screen(id: id, service: service)
		        }
		        let screenBuilder = Instantiator<Screen> {
		            __safeDI_screenBuilder(id: $0)
		        }
		        let service: any Service = __safeDI_serviceBuilder.service(screenBuilder)
		        self.init(screenBuilder: screenBuilder, service: service)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_C5CF4A1EC903198D {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Middle)
		import Middle
		#endif

		extension Root {
		    public init() {
		        func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: Int?, tag: Tag) -> Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
		            .init(gadget: { _ in
		                let gadget: any Gadget = LiveGadget(tag: tag, id: id)
		                return gadget
		            })
		        }
		        func __safeDI_gadgetBuilder_Outer_Inner(id: Int?, tag: Tag) -> Inner.__safeDI_ServiceCarrier<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
		            .init(screenBuilder: __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope(tag: tag), service: { values_screenBuilder in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: id, tag: tag) })
		        }
		        func __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope(tag: Tag) -> Inner.__safeDI_ServiceCarrier_Screen<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
		            .init(service: { values_id in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: values_id, tag: tag) })
		        }
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_3FF816B8F02AA356.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_gadgetBuilder_Outer() -> Outer.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
		                .init(inner_serviceBuilder: { values in __safeDI_gadgetBuilder_Outer_Inner(id: nil, tag: values.tag) })
		            }
		            return Outer(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Outer())
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(outer: outer)
		    }
		}
		"""])
		try Self.expectCompiles(output)
		try await expectValuesEqualInlineBuild(modules: modules, probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().outer.inner.screenBuilder.instantiate(7)"), DifferentialValueProbe("liveGadgetsHoldingOnlyScreen()")])
		let description = try await DifferentialValueOracle.describe(
			DifferentialValuePath(output: output, modules: modules),
			probes: [DifferentialValueProbe("liveGadgetsHoldingOnlyScreen()")],
			filesToDelete: &filesToDelete,
		)
		if compileVerificationIsEnabled {
			#expect(description == """
			probe liveGadgetsHoldingOnlyScreen()
			Int 1

			""")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesNoScopeParameterApart_whenPlaceIsBeneathPropertyNamedBuilder() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.fixtures["builderLabel"] ?? [], integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Home {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let builder: __safeDI_ApiCarrier_Part<__safeDI_Built>

		        public init(builder: __safeDI_ApiCarrier_Part<__safeDI_Built>) {
		            self.builder = builder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(builder: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Part<__safeDI_Built> {
		        public let api: () -> __safeDI_Built

		        public init(api: @escaping () -> __safeDI_Built) {
		            self.api = api
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(api: { __safeDI_builder() })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public init(apiBuilder: @escaping () -> any Api) {
		        self.init(__safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let __safeDI_apiBuilder_builder = __safeDI_apiBuilder.builder
		        @inline(never) func __safeDI_builder() -> Part {
		            let api: any Api = __safeDI_apiBuilder_builder.api()
		            return Part(api: api)
		        }
		        let builder = Instantiator<Part>(__safeDI_builder)
		        self.init(builder: builder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_D9E21EF59D1896E5 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		            .init(builder: __safeDI_apiBuilder_Home_Part_Scope())
		        }
		        func __safeDI_apiBuilder_Home_Part_Scope() -> Home.__safeDI_ApiCarrier_Part<any Api> {
		            .init(api: {
		                let api: any Api = LiveApi()
		                return api
		            })
		        }
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_D9E21EF59D1896E5.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		"""])
		try Self.expectCompiles(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesBuilderStructForEachHoleType_whenOneHoleTypesPlaceForwardsValue() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.fixtures["twoHoleTypes"] ?? [], integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Home {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let api: () -> __safeDI_Built

		        public init(api: @escaping () -> __safeDI_Built) {
		            self.api = api
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(api: { __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_LivePanel_PanelCarrier<__safeDI_Built> {
		        public let panelBuilder: (any Api) -> ErasedInstantiator<String, __safeDI_Built>.Builder

		        public init(panelBuilder: @escaping (any Api) -> ErasedInstantiator<String, __safeDI_Built>.Builder) {
		            self.panelBuilder = panelBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<String, __safeDI_Built>.Builder) {
		            self.init(panelBuilder: { _ in __safeDI_builder })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public init(apiBuilder: @escaping () -> any Api, livePanel_PanelBuilder: @escaping ErasedInstantiator<String, any Panel>.Builder) {
		        self.init(__safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder), __safeDI_livePanel_PanelBuilder: .init(__safeDI_noScope: livePanel_PanelBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>, __safeDI_livePanel_PanelBuilder: __safeDI_LivePanel_PanelCarrier<any Panel>) {
		        let api: any Api = __safeDI_apiBuilder.api()
		        let panelBuilder = ErasedInstantiator<String, any Panel>(__safeDI_livePanel_PanelBuilder.panelBuilder(api))
		        self.init(api: api, panelBuilder: panelBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_D6805EB8C483DFEA {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		            .init(api: {
		                let api: any Api = LiveApi()
		                return api
		            })
		        }
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_D6805EB8C483DFEA.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_livePanel_PanelBuilder_Home_panelBuilder() -> ErasedInstantiator<String, any Panel>.Builder {
		                func __safeDI_panelBuilder(title: String) -> LivePanel {
		                    LivePanel(title: title)
		                }
		                return { forwarded in __safeDI_panelBuilder(title: forwarded) }
		            }
		            func __safeDI_livePanel_PanelBuilder_Home() -> Home.__safeDI_LivePanel_PanelCarrier<any Panel> {
		                .init(panelBuilder: { values_api in __safeDI_livePanel_PanelBuilder_Home_panelBuilder() })
		            }
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home(), __safeDI_livePanel_PanelBuilder: __safeDI_livePanel_PanelBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		"""])
		try Self.expectCompiles(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsLevelFunctionTheLazyWrapper_whenLazyValueIsOnTheRouteToThePlace() async throws {
		let modules = Self.fixtures["lazy"] ?? []
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Home {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let detail: (LazilyInstantiated<Logger>) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>

		        public init(detail: @escaping (LazilyInstantiated<Logger>) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>) {
		            self.detail = detail
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(detail: { _ in .init(__safeDI_noScope: __safeDI_builder) })
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

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public init(apiBuilder: @escaping () -> any Api) {
		        self.init(__safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        @inline(never) func __safeDI_logger() -> Logger {
		            Logger()
		        }
		        let logger = LazilyInstantiated<Logger>(__safeDI_logger)
		        let __safeDI_apiBuilder_detail = __safeDI_apiBuilder.detail(logger)
		        @inline(never) func __safeDI_detail() -> Detail {
		            let api: any Api = __safeDI_apiBuilder_detail.api()
		            return Detail(api: api)
		        }
		        let detail = LazilyInstantiated<Detail>(__safeDI_detail)
		        self.init(logger: logger, detail: detail)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_E40E910FA85D3F21 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		            .init(detail: { values_logger in __safeDI_apiBuilder_Home_Detail_Scope(logger: values_logger) })
		        }
		        func __safeDI_apiBuilder_Home_Detail_Scope(logger: LazilyInstantiated<Logger>) -> Home.__safeDI_ApiCarrier_Detail<any Api> {
		            .init(api: {
		                let api: any Api = LiveApi(logger: logger.instance)
		                return api
		            })
		        }
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_E40E910FA85D3F21.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		"""])
		try Self.expectCompiles(output)
		try await expectValuesEqualInlineBuild(modules: modules, probes: [DifferentialValueProbe("Root().home.detail.instance")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsEachRoutesOwnValues_whenTwoRoutesReachOneLevel() async throws {
		let modules = Self.fixtures["twoRoutes"] ?? []
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Home {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let aBuilder: __safeDI_ApiCarrier_A<__safeDI_Built>
		        public let bBuilder: (Instantiator<A>) -> __safeDI_ApiCarrier_B<__safeDI_Built>

		        public init(aBuilder: __safeDI_ApiCarrier_A<__safeDI_Built>, bBuilder: @escaping (Instantiator<A>) -> __safeDI_ApiCarrier_B<__safeDI_Built>) {
		            self.aBuilder = aBuilder
		            self.bBuilder = bBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(aBuilder: .init(__safeDI_noScope: __safeDI_builder), bBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_A<__safeDI_Built> {
		        public let detailBuilder: (Logger, Tag) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>

		        public init(detailBuilder: @escaping (Logger, Tag) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>) {
		            self.detailBuilder = detailBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(detailBuilder: { _, _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_B<__safeDI_Built> {
		        public let detailBuilder: (Logger) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>

		        public init(detailBuilder: @escaping (Logger) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>) {
		            self.detailBuilder = detailBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(detailBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
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

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public init(apiBuilder: @escaping () -> any Api) {
		        self.init(__safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let __safeDI_apiBuilder_aBuilder = __safeDI_apiBuilder.aBuilder
		        @inline(never) func __safeDI_detailBuilder(__safeDI_apiBuilder_detailBuilder: __safeDI_ApiCarrier_Detail<any Api>) -> Detail {
		            let api: any Api = __safeDI_apiBuilder_detailBuilder.api()
		            return Detail(api: api)
		        }
		        @inline(never) func __safeDI_aBuilder() -> A {
		            let logger = Logger()
		            let tag = Tag()
		            let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder_aBuilder.detailBuilder(logger, tag)
		            let detailBuilder = Instantiator<Detail> {
		                __safeDI_detailBuilder(__safeDI_apiBuilder_detailBuilder: __safeDI_apiBuilder_detailBuilder)
		            }
		            return A(logger: logger, tag: tag, detailBuilder: detailBuilder)
		        }
		        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		        let __safeDI_apiBuilder_bBuilder = __safeDI_apiBuilder.bBuilder(aBuilder)
		        @inline(never) func __safeDI_bBuilder() -> B {
		            let logger = Logger()
		            let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder_bBuilder.detailBuilder(logger)
		            let detailBuilder = Instantiator<Detail> {
		                __safeDI_detailBuilder(__safeDI_apiBuilder_detailBuilder: __safeDI_apiBuilder_detailBuilder)
		            }
		            return B(logger: logger, detailBuilder: detailBuilder)
		        }
		        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		        self.init(aBuilder: aBuilder, bBuilder: bBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_06E948B543409F8C {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        func __safeDI_apiBuilder_Home_A_Scope() -> Home.__safeDI_ApiCarrier_A<any Api> {
		            .init(detailBuilder: { values_logger, values_tag in __safeDI_apiBuilder_Home_Detail_Scope(logger: values_logger, tag: values_tag) })
		        }
		        func __safeDI_apiBuilder_Home_Detail_Scope(logger: Logger, tag: Tag?) -> Home.__safeDI_ApiCarrier_Detail<any Api> {
		            .init(api: {
		                let api: any Api = LiveApi(logger: logger, tag: tag)
		                return api
		            })
		        }
		        func __safeDI_apiBuilder_Home_B_Scope(tag: Tag?) -> Home.__safeDI_ApiCarrier_B<any Api> {
		            .init(detailBuilder: { values_logger in __safeDI_apiBuilder_Home_Detail_Scope(logger: values_logger, tag: tag) })
		        }
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_06E948B543409F8C.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		                .init(aBuilder: __safeDI_apiBuilder_Home_A_Scope(), bBuilder: { values_aBuilder in __safeDI_apiBuilder_Home_B_Scope(tag: nil) })
		            }
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		"""])
		try Self.expectCompiles(output)
		try await expectValuesEqualInlineBuild(modules: modules, probes: [DifferentialValueProbe("Root().home.aBuilder.instantiate().detailBuilder.instantiate()"), DifferentialValueProbe("Root().home.bBuilder.instantiate().detailBuilder.instantiate()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_freesFirstScreensValues_whenScreenOpensItselfAgainBeneathTheSeam() async throws {
		// `Screen` builds another `Screen` through `next`. Every deeper screen re-enters the function `Home` built the first
		// with; the member the first screen's level calls hands its level function only `id`, which each place carries, so a
		// screen four or eight levels deep keeps no other screen's `Live` alive, as inline.
		let modules = Self.fixtures["next"] ?? []
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Home {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let screenBuilder: __safeDI_ApiCarrier_Screen<__safeDI_Built>

		        public init(screenBuilder: __safeDI_ApiCarrier_Screen<__safeDI_Built>) {
		            self.screenBuilder = screenBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(screenBuilder: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Screen<__safeDI_Built> {
		        public let api: (Int) -> __safeDI_Built
		        public let next: (Int, any Api) -> __safeDI_ApiCarrier_Screen<__safeDI_Built>

		        public init(api: @escaping (Int) -> __safeDI_Built, next: @escaping (Int, any Api) -> __safeDI_ApiCarrier_Screen<__safeDI_Built>) {
		            self.api = api
		            self.next = next
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(api: { _ in __safeDI_builder() }, next: { _, _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(apiBuilder: @escaping () -> any Api) {
		        self.init(__safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let __safeDI_apiBuilder_screenBuilder = __safeDI_apiBuilder.screenBuilder
		        @inline(never) func __safeDI_next(id: Int, __safeDI_apiBuilder_next: __safeDI_ApiCarrier_Screen<any Api>) -> Screen {
		            let api: any Api = __safeDI_apiBuilder_next.api(id)
		            let next = Instantiator<Screen> {
		                __safeDI_next(id: $0, __safeDI_apiBuilder_next: __safeDI_apiBuilder_next)
		            }
		            return Screen(id: id, api: api, next: next)
		        }
		        @inline(never) func __safeDI_screenBuilder(id: Int) -> Screen {
		            let api: any Api = __safeDI_apiBuilder_screenBuilder.api(id)
		            let __safeDI_apiBuilder_next = __safeDI_apiBuilder_screenBuilder.next(id, api)
		            let next = Instantiator<Screen> {
		                __safeDI_next(id: $0, __safeDI_apiBuilder_next: __safeDI_apiBuilder_next)
		            }
		            return Screen(id: id, api: api, next: next)
		        }
		        let screenBuilder = Instantiator<Screen> {
		            __safeDI_screenBuilder(id: $0)
		        }
		        self.init(screenBuilder: screenBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_76AC111056905E55 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		            .init(screenBuilder: __safeDI_apiBuilder_Home_Screen_Scope())
		        }
		        func __safeDI_apiBuilder_Home_Screen_Scope() -> Home.__safeDI_ApiCarrier_Screen<any Api> {
		            .init(
		                api: { scope_id in
		                    let id = scope_id
		                    let api: any Api = Live(id: id)
		                    return api
		                },
		                next: { values_id, values_api in __safeDI_apiBuilder_Home_Screen_Scope() }
		            )
		        }
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_76AC111056905E55.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		"""])
		try Self.expectCompiles(output)
		let description = try await DifferentialValueOracle.describe(
			DifferentialValuePath(output: output, modules: modules),
			probes: [DifferentialValueProbe("liveCountHoldingOnlyScreen(atDepth: 4)"), DifferentialValueProbe("liveCountHoldingOnlyScreen(atDepth: 8)")],
			filesToDelete: &filesToDelete,
		)
		if compileVerificationIsEnabled {
			#expect(description == """
			probe liveCountHoldingOnlyScreen(atDepth: 4)
			Int 1
			probe liveCountHoldingOnlyScreen(atDepth: 8)
			Int 1

			""")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueACycleDeclaresAgain_whenFillOfReopenedLevelReadsValueTheRouteToItBinds() async {
		// `Step` binds `mark` before it builds another `Screen` through `next`. Inline, the `Live` that fills the second
		// screen's `monitor` reads the first step's `mark`; the level `next` reopens takes its builder from the member `Home`'s
		// first screen called, which carries no `mark`, so the fill would read `nil`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Live.swift"]):10:5: error: `Live` receives `cache: Cache`, which `Screen` declares between where `Screen` instantiates `stepBuilder: Instantiator<Step>` and where `Screen` instantiates it again. Inline, the `Step` built again receives `Screen`’s `cache`, but SafeDI hands the builder for `Step`’s `api: any Api` (`api` of `apiBuilder`) the same values at every level of that cycle. Declare `@Received let cache: Cache` on `Step`, so each `Step` receives the `cache` of its own level and hands it on, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["Screen.swift"]):9:5: note: `Screen` declares `cache: Cache` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.fixtures["mark"] ?? [], integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsReopenedLevelTheValueItsRouteBinds_whenFillOfReopenedLevelReadsOnlyThatValue() async throws {
		// The shape above, where `Live` reads only `mark`: no cycle closes on `Screen`'s builder function, so the screen `next`
		// builds is a level of its own, whose member carries the first step's `mark`, as inline.
		let modules = Self.fixtures["markOnly"] ?? []
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Home {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let screenBuilder: __safeDI_ApiCarrier_Screen<__safeDI_Built>

		        public init(screenBuilder: __safeDI_ApiCarrier_Screen<__safeDI_Built>) {
		            self.screenBuilder = screenBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(screenBuilder: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Screen<__safeDI_Built> {
		        public let monitor: (Cache) -> __safeDI_Built
		        public let stepBuilder: (Cache, any Api) -> __safeDI_ApiCarrier_Step<__safeDI_Built>

		        public init(monitor: @escaping (Cache) -> __safeDI_Built, stepBuilder: @escaping (Cache, any Api) -> __safeDI_ApiCarrier_Step<__safeDI_Built>) {
		            self.monitor = monitor
		            self.stepBuilder = stepBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(monitor: { _ in __safeDI_builder() }, stepBuilder: { _, _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Step<__safeDI_Built> {
		        public let api: (Mark) -> __safeDI_Built
		        public let next: (Mark, any Api) -> __safeDI_ApiCarrier_Screen<__safeDI_Built>

		        public init(api: @escaping (Mark) -> __safeDI_Built, next: @escaping (Mark, any Api) -> __safeDI_ApiCarrier_Screen<__safeDI_Built>) {
		            self.api = api
		            self.next = next
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(api: { _ in __safeDI_builder() }, next: { _, _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public init(apiBuilder: @escaping () -> any Api) {
		        self.init(__safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let __safeDI_apiBuilder_screenBuilder = __safeDI_apiBuilder.screenBuilder
		        @inline(never) func __safeDI_stepBuilder(__safeDI_apiBuilder_stepBuilder: __safeDI_ApiCarrier_Step<any Api>) -> Step {
		            let mark = Mark()
		            let api: any Api = __safeDI_apiBuilder_stepBuilder.api(mark)
		            let __safeDI_apiBuilder_next = __safeDI_apiBuilder_stepBuilder.next(mark, api)
		            let next = Instantiator<Screen> {
		                __safeDI_next(__safeDI_apiBuilder_next: __safeDI_apiBuilder_next, __safeDI_apiBuilder_stepBuilder: __safeDI_apiBuilder_stepBuilder)
		            }
		            return Step(api: api, mark: mark, next: next)
		        }
		        @inline(never) func __safeDI_next(__safeDI_apiBuilder_next: __safeDI_ApiCarrier_Screen<any Api>, __safeDI_apiBuilder_stepBuilder: __safeDI_ApiCarrier_Step<any Api>) -> Screen {
		            let cache = Cache()
		            let monitor: any Api = __safeDI_apiBuilder_next.monitor(cache)
		            let stepBuilder = Instantiator<Step> {
		                __safeDI_stepBuilder(__safeDI_apiBuilder_stepBuilder: __safeDI_apiBuilder_stepBuilder)
		            }
		            return Screen(cache: cache, monitor: monitor, stepBuilder: stepBuilder)
		        }
		        @inline(never) func __safeDI_screenBuilder() -> Screen {
		            let cache = Cache()
		            let monitor: any Api = __safeDI_apiBuilder_screenBuilder.monitor(cache)
		            let __safeDI_apiBuilder_stepBuilder = __safeDI_apiBuilder_screenBuilder.stepBuilder(cache, monitor)
		            let stepBuilder = Instantiator<Step> {
		                __safeDI_stepBuilder(__safeDI_apiBuilder_stepBuilder: __safeDI_apiBuilder_stepBuilder)
		            }
		            return Screen(cache: cache, monitor: monitor, stepBuilder: stepBuilder)
		        }
		        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
		        self.init(screenBuilder: screenBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_0BA0C1690AADBEE1 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        func __safeDI_apiBuilder_Home_Screen_Scope(mark: Mark?) -> Home.__safeDI_ApiCarrier_Screen<any Api> {
		            .init(
		                monitor: { scope_cache in
		                    let monitor: any Api = Live(mark: mark)
		                    return monitor
		                },
		                stepBuilder: { values_cache, values_monitor in __safeDI_apiBuilder_Home_Step_Scope() }
		            )
		        }
		        func __safeDI_apiBuilder_Home_Step_Scope() -> Home.__safeDI_ApiCarrier_Step<any Api> {
		            .init(
		                api: { scope_mark in
		                    let mark = scope_mark
		                    let api: any Api = Live(mark: mark)
		                    return api
		                },
		                next: { values_mark, values_api in __safeDI_apiBuilder_Home_Screen_Scope(mark: values_mark) }
		            )
		        }
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_0BA0C1690AADBEE1.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		                .init(screenBuilder: __safeDI_apiBuilder_Home_Screen_Scope(mark: nil))
		            }
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		"""])
		try Self.expectCompiles(output)
		let description = try await DifferentialValueOracle.describe(
			DifferentialValuePath(output: output, modules: modules),
			probes: [DifferentialValueProbe("secondMonitorsMark()")],
			filesToDelete: &filesToDelete,
		)
		if compileVerificationIsEnabled {
			#expect(description == """
			probe secondMonitorsMark()
			String "the mark of the first step"

			""")
		}
		try await expectValuesEqualInlineBuild(modules: modules, probes: [DifferentialValueProbe("secondMonitorsMark()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reusesRootsLevelFunctionInOuterSeamsStruct_whenFillOfSwitchedSeamCallsOuterSeamThatPassesItsPlaceUp() async throws {
		// `HoleImpl` fills `HoleSeam`'s place beneath `HoleOwner`, reading `holeAnalytics`, which `HoleOwner`'s level carries,
		// and builds `HoleRelay`, which builds `HoleSeam` and passes its place up. The member of `HoleRelay`'s struct for
		// `HoleSeam` calls the function `Root` builds `HoleSeam`'s struct with, whose level function hands the fill
		// `holeAnalytics` from the values of `HoleOwner`'s level.
		let modules = Self.fixtures["reentryThroughOuterSeam"] ?? []
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension HoleRelay {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_HoleServiceCarrier<__safeDI_Built> {
		        public let holeSeamBuilder: HoleSeam.__safeDI_HoleServiceCarrier<__safeDI_Built>

		        public init(holeSeamBuilder: HoleSeam.__safeDI_HoleServiceCarrier<__safeDI_Built>) {
		            self.holeSeamBuilder = holeSeamBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(holeSeamBuilder: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public init(holeServiceBuilder: @escaping () -> any HoleService) {
		        self.init(__safeDI_holeServiceBuilder: .init(__safeDI_noScope: holeServiceBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public init(__safeDI_holeServiceBuilder: __safeDI_HoleServiceCarrier<any HoleService>) {
		        @inline(never) func __safeDI_holeSeamBuilder() -> HoleSeam {
		            _ = HoleSeam.__safeDI_HoleSeam_5FD372FEB0CFA415.self
		            return HoleSeam(__safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder.holeSeamBuilder)
		        }
		        let holeSeamBuilder = Instantiator<HoleSeam>(__safeDI_holeSeamBuilder)
		        self.init(holeSeamBuilder: holeSeamBuilder)
		    }
		}

		extension HoleRelay {
		    public enum __safeDI_HoleRelay_635E3D11CE7DF41B {}
		}

		extension HoleSeam {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_HoleServiceCarrier<__safeDI_Built> {
		        public let holeOwnerBuilder: (HoleAnalytics) -> __safeDI_HoleServiceCarrier_HoleOwner<__safeDI_Built>

		        public init(holeOwnerBuilder: @escaping (HoleAnalytics) -> __safeDI_HoleServiceCarrier_HoleOwner<__safeDI_Built>) {
		            self.holeOwnerBuilder = holeOwnerBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(holeOwnerBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_HoleServiceCarrier_HoleOwner<__safeDI_Built> {
		        public let holeService: () -> __safeDI_Built

		        public init(holeService: @escaping () -> __safeDI_Built) {
		            self.holeService = holeService
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(holeService: { __safeDI_builder() })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public init(holeServiceBuilder: @escaping () -> any HoleService) {
		        self.init(__safeDI_holeServiceBuilder: .init(__safeDI_noScope: holeServiceBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public init(__safeDI_holeServiceBuilder: __safeDI_HoleServiceCarrier<any HoleService>) {
		        let holeAnalytics = HoleAnalytics()
		        let __safeDI_holeServiceBuilder_holeOwnerBuilder = __safeDI_holeServiceBuilder.holeOwnerBuilder(holeAnalytics)
		        @inline(never) func __safeDI_holeOwnerBuilder() -> HoleOwner {
		            let holeService: any HoleService = __safeDI_holeServiceBuilder_holeOwnerBuilder.holeService()
		            return HoleOwner(holeAnalytics: holeAnalytics, holeService: holeService)
		        }
		        let holeOwnerBuilder = Instantiator<HoleOwner>(__safeDI_holeOwnerBuilder)
		        self.init(holeAnalytics: holeAnalytics, holeOwnerBuilder: holeOwnerBuilder)
		    }
		}

		extension HoleSeam {
		    public enum __safeDI_HoleSeam_5FD372FEB0CFA415 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        func __safeDI_holeSeam() -> HoleSeam {
		            _ = HoleSeam.__safeDI_HoleSeam_5FD372FEB0CFA415.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_holeServiceBuilder_HoleSeam_HoleOwner_Scope_holeService(holeAnalytics: HoleAnalytics) -> any HoleService {
		                func __safeDI_holeService() -> HoleImpl {
		                    func __safeDI_holeRelayBuilder() -> HoleRelay {
		                        _ = HoleRelay.__safeDI_HoleRelay_635E3D11CE7DF41B.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                        func __safeDI_holeServiceBuilder_HoleRelay() -> HoleRelay.__safeDI_HoleServiceCarrier<any HoleService> {
		                            .init(holeSeamBuilder: __safeDI_holeServiceBuilder_HoleSeam())
		                        }
		                        return HoleRelay(__safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder_HoleRelay())
		                    }
		                    let holeRelayBuilder = Instantiator<HoleRelay>(__safeDI_holeRelayBuilder)
		                    return HoleImpl(holeAnalytics: holeAnalytics, holeRelayBuilder: holeRelayBuilder)
		                }
		                let holeService: any HoleService = __safeDI_holeService()
		                return holeService
		            }
		            func __safeDI_holeServiceBuilder_HoleSeam() -> HoleSeam.__safeDI_HoleServiceCarrier<any HoleService> {
		                .init(holeOwnerBuilder: { values_holeAnalytics in __safeDI_holeServiceBuilder_HoleSeam_HoleOwner_Scope(holeAnalytics: values_holeAnalytics) })
		            }
		            func __safeDI_holeServiceBuilder_HoleSeam_HoleOwner_Scope(holeAnalytics: HoleAnalytics) -> HoleSeam.__safeDI_HoleServiceCarrier_HoleOwner<any HoleService> {
		                .init(holeService: { __safeDI_holeServiceBuilder_HoleSeam_HoleOwner_Scope_holeService(holeAnalytics: holeAnalytics) })
		            }
		            return HoleSeam(__safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder_HoleSeam())
		        }
		        let holeSeam: HoleSeam = __safeDI_holeSeam()
		        self.init(holeSeam: holeSeam)
		    }
		}
		"""])
		try Self.expectCompiles(output)
		try await expectValuesEqualInlineBuild(modules: modules, probes: [DifferentialValueProbe("Root().holeSeam.holeOwnerBuilder.instantiate().holeService")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsEachLevelsStructInItsOwnFunction_whenOuterSeamPassesUpPlaceBeneathRepeatedLabel() async throws {
		// `Innermost` builds `X` and `X` builds `Y` under one label, `child`, and the fill reads a value each level binds.
		// `Root` builds each level's struct in a function of its own, which its parent level's member calls with the values
		// that level binds, so each level is handed its own.
		let modules = Self.fixtures["repeatedLabel"] ?? []
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Inner {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
		        public let innermost: Innermost.__safeDI_ServiceCarrier<__safeDI_Built>

		        public init(innermost: Innermost.__safeDI_ServiceCarrier<__safeDI_Built>) {
		            self.innermost = innermost
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(innermost: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
		        @inline(never) func __safeDI_innermost() -> Innermost {
		            _ = Innermost.__safeDI_Innermost_13A9D22DA12214A5.self
		            return Innermost(__safeDI_serviceBuilder: __safeDI_serviceBuilder.innermost)
		        }
		        let innermost: Innermost = __safeDI_innermost()
		        self.init(innermost: innermost)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_479DA0C117074FF9 {}
		}

		extension Innermost {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
		        public let child: (Tag) -> __safeDI_ServiceCarrier_X<__safeDI_Built>

		        public init(child: @escaping (Tag) -> __safeDI_ServiceCarrier_X<__safeDI_Built>) {
		            self.child = child
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(child: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ServiceCarrier_X<__safeDI_Built> {
		        public let child: (Logger) -> __safeDI_ServiceCarrier_Y<__safeDI_Built>

		        public init(child: @escaping (Logger) -> __safeDI_ServiceCarrier_Y<__safeDI_Built>) {
		            self.child = child
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(child: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ServiceCarrier_Y<__safeDI_Built> {
		        public let service: () -> __safeDI_Built

		        public init(service: @escaping () -> __safeDI_Built) {
		            self.service = service
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(service: { __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
		        let tag = Tag()
		        let __safeDI_serviceBuilder_child = __safeDI_serviceBuilder.child(tag)
		        @inline(never) func __safeDI_child_(__safeDI_serviceBuilder_child_: __safeDI_ServiceCarrier_Y<any Service>) -> Y {
		            let service: any Service = __safeDI_serviceBuilder_child_.service()
		            return Y(service: service)
		        }
		        @inline(never) func __safeDI_child() -> X {
		            let logger = Logger()
		            let __safeDI_serviceBuilder_child_ = __safeDI_serviceBuilder_child.child(logger)
		            let child = Instantiator<Y> {
		                __safeDI_child_(__safeDI_serviceBuilder_child_: __safeDI_serviceBuilder_child_)
		            }
		            return X(logger: logger, child: child)
		        }
		        let child = Instantiator<X>(__safeDI_child)
		        self.init(tag: tag, child: child)
		    }
		}

		extension Innermost {
		    public enum __safeDI_Innermost_13A9D22DA12214A5 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_serviceBuilder_Inner() -> Inner.__safeDI_ServiceCarrier<any Service> {
		            .init(innermost: __safeDI_serviceBuilder_Innermost())
		        }
		        func __safeDI_serviceBuilder_Innermost() -> Innermost.__safeDI_ServiceCarrier<any Service> {
		            .init(child: { values_tag in __safeDI_serviceBuilder_Innermost_X_Scope(tag: values_tag) })
		        }
		        func __safeDI_serviceBuilder_Innermost_X_Scope(tag: Tag) -> Innermost.__safeDI_ServiceCarrier_X<any Service> {
		            .init(child: { values_logger in __safeDI_serviceBuilder_Innermost_Y_Scope(logger: values_logger, tag: tag) })
		        }
		        func __safeDI_serviceBuilder_Innermost_Y_Scope(logger: Logger, tag: Tag) -> Innermost.__safeDI_ServiceCarrier_Y<any Service> {
		            .init(service: {
		                let service: any Service = DefaultService(tag: tag, logger: logger)
		                return service
		            })
		        }
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_479DA0C117074FF9.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner())
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(inner: inner)
		    }
		}
		"""])
		try Self.expectCompiles(output)
		try await expectValuesEqualInlineBuild(modules: modules, probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().inner.innermost.child.instantiate().child.instantiate().service")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsMembersValuesAsRawIdentifier_whenOuterSeamPassesUpPlaceLabelledWithRawIdentifier() async throws {
		// `Innermost`'s place is `` `my leaf` ``, so the values its member is handed are named by a raw identifier, which needs
		// backticks.
		let modules = Self.fixtures["rawLabel"] ?? []
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Inner {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
		        public let innermost: Innermost.__safeDI_ServiceCarrier<__safeDI_Built>

		        public init(innermost: Innermost.__safeDI_ServiceCarrier<__safeDI_Built>) {
		            self.innermost = innermost
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(innermost: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
		        @inline(never) func __safeDI_innermost() -> Innermost {
		            _ = Innermost.__safeDI_Innermost_06F72FABB8D87C2D.self
		            return Innermost(__safeDI_serviceBuilder: __safeDI_serviceBuilder.innermost)
		        }
		        let innermost: Innermost = __safeDI_innermost()
		        self.init(innermost: innermost)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_F7306DD1F42AB631 {}
		}

		extension Innermost {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
		        public let `my leaf`: (Logger) -> __safeDI_Built

		        public init(`my leaf`: @escaping (Logger) -> __safeDI_Built) {
		            self.`my leaf` = `my leaf`
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(`my leaf`: { _ in __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
		        let logger = Logger()
		        let `my leaf`: any Service = __safeDI_serviceBuilder.`my leaf`(logger)
		        self.init(logger: logger, `my leaf`: `my leaf`)
		    }
		}

		extension Innermost {
		    public enum __safeDI_Innermost_06F72FABB8D87C2D {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_serviceBuilder_Inner() -> Inner.__safeDI_ServiceCarrier<any Service> {
		            .init(innermost: __safeDI_serviceBuilder_Innermost())
		        }
		        func __safeDI_serviceBuilder_Innermost() -> Innermost.__safeDI_ServiceCarrier<any Service> {
		            .init(`my leaf`: { scope_logger in
		                let logger = scope_logger
		                let `my leaf`: any Service = DefaultService(logger: logger)
		                return `my leaf`
		            })
		        }
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_F7306DD1F42AB631.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner())
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(inner: inner)
		    }
		}
		"""])
		try Self.expectCompiles(output)
		try await expectValuesEqualInlineBuild(modules: modules, probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().inner.innermost.`my leaf`")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsMembersValuesAsRawIdentifier_whenOuterSeamPassesUpLoopWhosePlaceIsLabelledWithRawIdentifier() async throws {
		// The tangle, whose `T` holds its place under `` `my leaf` ``: the place's member, and the values it is handed, are named
		// the values it is handed by a raw identifier.
		let modules = Self.fixtures["tangleRawLabel"] ?? []
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Middle"]?.generatedFiles == ["Middle.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Shell {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let hub: Hub.__safeDI_ApiCarrier<__safeDI_Built>

		        public init(hub: Hub.__safeDI_ApiCarrier<__safeDI_Built>) {
		            self.hub = hub
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(hub: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_mark: @autoclosure @escaping () -> Mark?, __safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let mark = LazilyInstantiated<Mark?>(__safeDI_mark)
		        @inline(never) func __safeDI_hub() -> Hub {
		            _ = Hub.__safeDI_Hub_CE9C38978D2626F3.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Hub(__safeDI_mark: mark.instance, __safeDI_apiBuilder: __safeDI_apiBuilder.hub)
		        }
		        let hub: Hub = __safeDI_hub()
		        self.init(hub: hub)
		    }
		}

		extension Shell {
		    public enum __safeDI_Shell_F5CADF3967808332 {}
		}
		"""])
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Hub {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let tBuilder: (LazilyInstantiated<Mark?>) -> __safeDI_ApiCarrier_T<__safeDI_Built>
		        public let cBuilder: (LazilyInstantiated<Mark?>, Instantiator<T>) -> __safeDI_ApiCarrier_C<__safeDI_Built>

		        public init(tBuilder: @escaping (LazilyInstantiated<Mark?>) -> __safeDI_ApiCarrier_T<__safeDI_Built>, cBuilder: @escaping (LazilyInstantiated<Mark?>, Instantiator<T>) -> __safeDI_ApiCarrier_C<__safeDI_Built>) {
		            self.tBuilder = tBuilder
		            self.cBuilder = cBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(tBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) }, cBuilder: { _, _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_T<__safeDI_Built> {
		        public let cBuilder: (Mark?, MarkReader) -> __safeDI_ApiCarrier_C<__safeDI_Built>
		        public let `my leaf`: (Mark?, MarkReader, Instantiator<C>) -> __safeDI_Built

		        public init(cBuilder: @escaping (Mark?, MarkReader) -> __safeDI_ApiCarrier_C<__safeDI_Built>, `my leaf`: @escaping (Mark?, MarkReader, Instantiator<C>) -> __safeDI_Built) {
		            self.cBuilder = cBuilder
		            self.`my leaf` = `my leaf`
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(cBuilder: { _, _ in .init(__safeDI_noScope: __safeDI_builder) }, `my leaf`: { _, _, _ in __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_C<__safeDI_Built> {
		        public let tBuilder: (Mark) -> __safeDI_ApiCarrier_T<__safeDI_Built>

		        public init(tBuilder: @escaping (Mark) -> __safeDI_ApiCarrier_T<__safeDI_Built>) {
		            self.tBuilder = tBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(tBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_mark __safeDI_mark_: @autoclosure @escaping () -> Mark?, __safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let mark = LazilyInstantiated<Mark?>(__safeDI_mark_)
		        let __safeDI_apiBuilder_tBuilder = __safeDI_apiBuilder.tBuilder(mark)
		        @inline(never) func __safeDI_tBuilder(mark: Mark?) -> T {
		            let reader = MarkReader(mark: mark)
		            @inline(never) func __safeDI_cBuilder() -> C {
		                let mark = Mark()
		                let tBuilder = Instantiator<T> {
		                    __safeDI_tBuilder(mark: mark)
		                }
		                return C(mark: mark, tBuilder: tBuilder)
		            }
		            let cBuilder = Instantiator<C>(__safeDI_cBuilder)
		            let `my leaf`: any Api = __safeDI_apiBuilder_tBuilder.`my leaf`(mark, reader, cBuilder)
		            return T(reader: reader, cBuilder: cBuilder, `my leaf`: `my leaf`)
		        }
		        let tBuilder = Instantiator<T> {
		            __safeDI_tBuilder(mark: mark.instance)
		        }
		        let __safeDI_apiBuilder_cBuilder = __safeDI_apiBuilder.cBuilder(mark, tBuilder)
		        @inline(never) func __safeDI_cBuilder() -> C {
		            let mark = Mark()
		            let __safeDI_apiBuilder_tBuilder = __safeDI_apiBuilder_cBuilder.tBuilder(mark)
		            @inline(never) func __safeDI_tBuilder() -> T {
		                let reader = MarkReader(mark: mark)
		                let cBuilder = Instantiator<C>(__safeDI_cBuilder)
		                let `my leaf`: any Api = __safeDI_apiBuilder_tBuilder.`my leaf`(mark, reader, cBuilder)
		                return T(reader: reader, cBuilder: cBuilder, `my leaf`: `my leaf`)
		            }
		            let tBuilder = Instantiator<T>(__safeDI_tBuilder)
		            return C(mark: mark, tBuilder: tBuilder)
		        }
		        let cBuilder = Instantiator<C>(__safeDI_cBuilder)
		        self.init(tBuilder: tBuilder, cBuilder: cBuilder)
		    }
		}

		extension Hub {
		    public enum __safeDI_Hub_CE9C38978D2626F3 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Middle)
		import Middle
		#endif

		extension Root {
		    public init() {
		        func __safeDI_apiBuilder_Shell() -> Shell.__safeDI_ApiCarrier<any Api> {
		            .init(hub: __safeDI_apiBuilder_Hub())
		        }
		        func __safeDI_apiBuilder_Hub() -> Hub.__safeDI_ApiCarrier<any Api> {
		            .init(tBuilder: { values_mark in __safeDI_apiBuilder_Hub_T_Scope() }, cBuilder: { values_mark, values_tBuilder in __safeDI_apiBuilder_Hub_C_Scope() })
		        }
		        func __safeDI_apiBuilder_Hub_T_Scope() -> Hub.__safeDI_ApiCarrier_T<any Api> {
		            .init(
		                cBuilder: { values_mark, values_reader in __safeDI_apiBuilder_Hub_C_Scope() },
		                `my leaf`: { scope_mark, scope_reader, scope_cBuilder in
		                    let mark = scope_mark
		                    let `my leaf`: any Api = LiveApi(mark: mark)
		                    return `my leaf`
		                }
		            )
		        }
		        func __safeDI_apiBuilder_Hub_C_Scope() -> Hub.__safeDI_ApiCarrier_C<any Api> {
		            .init(tBuilder: { values_mark in __safeDI_apiBuilder_Hub_T_Scope() })
		        }
		        func __safeDI_shell() -> Shell {
		            _ = Shell.__safeDI_Shell_F5CADF3967808332.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Shell(__safeDI_mark: nil, __safeDI_apiBuilder: __safeDI_apiBuilder_Shell())
		        }
		        let shell: Shell = __safeDI_shell()
		        self.init(shell: shell)
		    }
		}
		"""])
		try Self.expectCompiles(output)
		try await expectValuesEqualInlineBuild(modules: modules, probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().shell.hub.tBuilder.instantiate().cBuilder.instantiate().tBuilder.instantiate()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsLevelFunctionsAsRawIdentifiers_whenOuterSeamPassesUpLoopOfSeamNamedByRawIdentifier() async throws {
		// The tangle, whose seam is `` `My Hub` ``: each function `Root` builds a level's struct with is named after the seam, so
		// both names are raw identifiers, which need backticks around the whole name.
		let modules = Self.fixtures["tangleRawStem"] ?? []
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Middle"]?.generatedFiles == ["Middle.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Shell {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let hub: `My Hub`.__safeDI_ApiCarrier<__safeDI_Built>

		        public init(hub: `My Hub`.__safeDI_ApiCarrier<__safeDI_Built>) {
		            self.hub = hub
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(hub: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_mark: @autoclosure @escaping () -> Mark?, __safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let mark = LazilyInstantiated<Mark?>(__safeDI_mark)
		        @inline(never) func __safeDI_hub() -> `My Hub` {
		            _ = `My Hub`.`__safeDI_My Hub_FCDA760FC244EE71`.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return `My Hub`(__safeDI_mark: mark.instance, __safeDI_apiBuilder: __safeDI_apiBuilder.hub)
		        }
		        let hub: `My Hub` = __safeDI_hub()
		        self.init(hub: hub)
		    }
		}

		extension Shell {
		    public enum __safeDI_Shell_F1889E3A79BA09C0 {}
		}
		"""])
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension `My Hub` {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let tBuilder: (LazilyInstantiated<Mark?>) -> __safeDI_ApiCarrier_T<__safeDI_Built>
		        public let cBuilder: (LazilyInstantiated<Mark?>, Instantiator<T>) -> __safeDI_ApiCarrier_C<__safeDI_Built>

		        public init(tBuilder: @escaping (LazilyInstantiated<Mark?>) -> __safeDI_ApiCarrier_T<__safeDI_Built>, cBuilder: @escaping (LazilyInstantiated<Mark?>, Instantiator<T>) -> __safeDI_ApiCarrier_C<__safeDI_Built>) {
		            self.tBuilder = tBuilder
		            self.cBuilder = cBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(tBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) }, cBuilder: { _, _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_T<__safeDI_Built> {
		        public let cBuilder: (Mark?, MarkReader) -> __safeDI_ApiCarrier_C<__safeDI_Built>
		        public let api: (Mark?, MarkReader, Instantiator<C>) -> __safeDI_Built

		        public init(cBuilder: @escaping (Mark?, MarkReader) -> __safeDI_ApiCarrier_C<__safeDI_Built>, api: @escaping (Mark?, MarkReader, Instantiator<C>) -> __safeDI_Built) {
		            self.cBuilder = cBuilder
		            self.api = api
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(cBuilder: { _, _ in .init(__safeDI_noScope: __safeDI_builder) }, api: { _, _, _ in __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_C<__safeDI_Built> {
		        public let tBuilder: (Mark) -> __safeDI_ApiCarrier_T<__safeDI_Built>

		        public init(tBuilder: @escaping (Mark) -> __safeDI_ApiCarrier_T<__safeDI_Built>) {
		            self.tBuilder = tBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(tBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_mark __safeDI_mark_: @autoclosure @escaping () -> Mark?, __safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let mark = LazilyInstantiated<Mark?>(__safeDI_mark_)
		        let __safeDI_apiBuilder_tBuilder = __safeDI_apiBuilder.tBuilder(mark)
		        @inline(never) func __safeDI_tBuilder(mark: Mark?) -> T {
		            let reader = MarkReader(mark: mark)
		            @inline(never) func __safeDI_cBuilder() -> C {
		                let mark = Mark()
		                let tBuilder = Instantiator<T> {
		                    __safeDI_tBuilder(mark: mark)
		                }
		                return C(mark: mark, tBuilder: tBuilder)
		            }
		            let cBuilder = Instantiator<C>(__safeDI_cBuilder)
		            let api: any Api = __safeDI_apiBuilder_tBuilder.api(mark, reader, cBuilder)
		            return T(reader: reader, cBuilder: cBuilder, api: api)
		        }
		        let tBuilder = Instantiator<T> {
		            __safeDI_tBuilder(mark: mark.instance)
		        }
		        let __safeDI_apiBuilder_cBuilder = __safeDI_apiBuilder.cBuilder(mark, tBuilder)
		        @inline(never) func __safeDI_cBuilder() -> C {
		            let mark = Mark()
		            let __safeDI_apiBuilder_tBuilder = __safeDI_apiBuilder_cBuilder.tBuilder(mark)
		            @inline(never) func __safeDI_tBuilder() -> T {
		                let reader = MarkReader(mark: mark)
		                let cBuilder = Instantiator<C>(__safeDI_cBuilder)
		                let api: any Api = __safeDI_apiBuilder_tBuilder.api(mark, reader, cBuilder)
		                return T(reader: reader, cBuilder: cBuilder, api: api)
		            }
		            let tBuilder = Instantiator<T>(__safeDI_tBuilder)
		            return C(mark: mark, tBuilder: tBuilder)
		        }
		        let cBuilder = Instantiator<C>(__safeDI_cBuilder)
		        self.init(tBuilder: tBuilder, cBuilder: cBuilder)
		    }
		}

		extension `My Hub` {
		    public enum `__safeDI_My Hub_FCDA760FC244EE71` {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Middle)
		import Middle
		#endif

		extension Root {
		    public init() {
		        func __safeDI_apiBuilder_Shell() -> Shell.__safeDI_ApiCarrier<any Api> {
		            .init(hub: `__safeDI_apiBuilder_My Hub`())
		        }
		        func `__safeDI_apiBuilder_My Hub`() -> `My Hub`.__safeDI_ApiCarrier<any Api> {
		            .init(tBuilder: { values_mark in `__safeDI_apiBuilder_My Hub_T_Scope`() }, cBuilder: { values_mark, values_tBuilder in `__safeDI_apiBuilder_My Hub_C_Scope`() })
		        }
		        func `__safeDI_apiBuilder_My Hub_T_Scope`() -> `My Hub`.__safeDI_ApiCarrier_T<any Api> {
		            .init(
		                cBuilder: { values_mark, values_reader in `__safeDI_apiBuilder_My Hub_C_Scope`() },
		                api: { scope_mark, scope_reader, scope_cBuilder in
		                    let mark = scope_mark
		                    let api: any Api = LiveApi(mark: mark)
		                    return api
		                }
		            )
		        }
		        func `__safeDI_apiBuilder_My Hub_C_Scope`() -> `My Hub`.__safeDI_ApiCarrier_C<any Api> {
		            .init(tBuilder: { values_mark in `__safeDI_apiBuilder_My Hub_T_Scope`() })
		        }
		        func __safeDI_shell() -> Shell {
		            _ = Shell.__safeDI_Shell_F1889E3A79BA09C0.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Shell(__safeDI_mark: nil, __safeDI_apiBuilder: __safeDI_apiBuilder_Shell())
		        }
		        let shell: Shell = __safeDI_shell()
		        self.init(shell: shell)
		    }
		}
		"""])
		try Self.expectCompiles(output)
		try await expectValuesEqualInlineBuild(modules: modules, probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().shell.hub.tBuilder.instantiate().cBuilder.instantiate().tBuilder.instantiate()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesPropertysBuilderFunctionApart_whenFillCallsItsSeamBeneathPropertyNamedLikeLevelFunction() async throws {
		// `HoleImpl` fills `HoleSeam`'s place and builds `HoleSeam` again beneath `holeServiceBuilder_HoleSeam`, whose builder
		// function would be named as the level function the call inside it passes: the property's function is named apart,
		// so the call reaches the level function.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.fixtures["propertyNamedLikeLevelFunction"] ?? [], integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension HoleSeam {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_HoleServiceCarrier<__safeDI_Built> {
		        public let holeService: () -> __safeDI_Built

		        public init(holeService: @escaping () -> __safeDI_Built) {
		            self.holeService = holeService
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(holeService: { __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_holeServiceBuilder: __safeDI_HoleServiceCarrier<any HoleService>) {
		        let holeService: any HoleService = __safeDI_holeServiceBuilder.holeService()
		        self.init(holeService: holeService)
		    }
		}

		extension HoleSeam {
		    public enum __safeDI_HoleSeam_43CD0988574C83D1 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_holeSeam() -> HoleSeam {
		            _ = HoleSeam.__safeDI_HoleSeam_43CD0988574C83D1.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_holeServiceBuilder_HoleSeam_holeService() -> any HoleService {
		                func __safeDI_holeService() -> HoleImpl {
		                    func __safeDI_holeServiceBuilder_HoleSeam_Wrapper() -> Wrapper {
		                        func __safeDI_holeSeam() -> HoleSeam {
		                            _ = HoleSeam.__safeDI_HoleSeam_43CD0988574C83D1.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                            return HoleSeam(__safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder_HoleSeam())
		                        }
		                        let holeSeam: HoleSeam = __safeDI_holeSeam()
		                        return Wrapper(holeSeam: holeSeam)
		                    }
		                    let holeServiceBuilder_HoleSeam = Instantiator<Wrapper>(__safeDI_holeServiceBuilder_HoleSeam_Wrapper)
		                    return HoleImpl(holeServiceBuilder_HoleSeam: holeServiceBuilder_HoleSeam)
		                }
		                let holeService: any HoleService = __safeDI_holeService()
		                return holeService
		            }
		            func __safeDI_holeServiceBuilder_HoleSeam() -> HoleSeam.__safeDI_HoleServiceCarrier<any HoleService> {
		                .init(holeService: { __safeDI_holeServiceBuilder_HoleSeam_holeService() })
		            }
		            return HoleSeam(__safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder_HoleSeam())
		        }
		        let holeSeam: HoleSeam = __safeDI_holeSeam()
		        self.init(holeSeam: holeSeam)
		    }
		}
		"""])
		try Self.expectCompiles(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsIsolationOnce_whenGeneratedInitializerAttributesCarrySeamsInitializersIsolation() async throws {
		// `Inner`'s own initializer is `@MainActor`, and so is every initializer `generatedInitializerAttributes` gives it.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.fixtures["isolationInAttributes"] ?? [], integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Inner {
		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained.
		    @MainActor public convenience init(token: Token) {
		        self.init(__safeDI_token: token)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    @MainActor public convenience init(__safeDI_token token: Token) {
		        let leaf = Leaf()
		        self.init(token: token, leaf: leaf)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_1EB503BFA23A82BA {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        let token = Token()
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_1EB503BFA23A82BA.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Inner(__safeDI_token: token)
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(token: token, inner: inner)
		    }
		}
		"""])
		try Self.expectCompiles(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_givesGeneratedInitializersTypesIsolation_whenMainActorSeamsOwnInitializerIsNonisolated() async throws {
		// `Inner` is `@MainActor` and its own initializer `nonisolated`, which only stores what the tree built. Each generated
		// initializer is declared in an extension of `Inner`, so it takes the main actor and can build `Leaf`, which is
		// `@MainActor`, for `Root` and the hand-written caller, both on the main actor.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.fixtures["nonisolatedInitializerBuildingMainActorTree"] ?? [], integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Inner {
		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained.
		    public convenience init(token: Token) {
		        self.init(__safeDI_token: token)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_token token: Token) {
		        let leaf = Leaf()
		        self.init(token: token, leaf: leaf)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_1EB503BFA23A82BA {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        let token = Token()
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_1EB503BFA23A82BA.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Inner(__safeDI_token: token)
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(token: token, inner: inner)
		    }
		}
		"""])
		try Self.expectCompiles(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_letsNonisolatedCallersCallMainActorSeam_whenGeneratedInitializerAttributesAreNonisolated() async throws {
		// `Inner` is `@MainActor` and nothing its tree builds needs the main actor, so `generatedInitializerAttributes:
		// "nonisolated"` lets `Root` and the hand-written caller, neither on the main actor, call its generated initializers.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.fixtures["nonisolatedInAttributes"] ?? [], integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Inner {
		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained.
		    nonisolated public convenience init(token: Token) {
		        self.init(__safeDI_token: token)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    nonisolated public convenience init(__safeDI_token token: Token) {
		        let leaf = Leaf()
		        self.init(token: token, leaf: leaf)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_1EB503BFA23A82BA {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        let token = Token()
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_1EB503BFA23A82BA.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Inner(__safeDI_token: token)
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(token: token, inner: inner)
		    }
		}
		"""])
		try Self.expectCompiles(output)
	}

	// MARK: Fixtures

	/// Each cell's modules, by the name the cell's test reads it under.
	static let fixtures: [String: [ModuleFixture]] = [
		"boundary": featureAndApp(
			feature: ["public protocol Api {}", seamFixtureType(named: "Home", isSeam: true, declarations: ["@Instantiated public let api: any Api"])],
			app: [fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: []), seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let home: Home"])],
		),
		"adopter": featureAndApp(
			feature: [
				"public protocol Api: AnyObject {}",
				seamFixtureType(named: "Navigator", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Logger", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Leaf", isFinalClass: true, declarations: ["@Instantiated public let api: any Api"]),
				seamFixtureType(named: "Detail", isFinalClass: true, declarations: ["@Instantiated public let leafBuilder: Instantiator<Leaf>"]),
				seamFixtureType(named: "Home", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let navigator: Navigator", "@Instantiated public let logger: Logger", "@Instantiated public let detailBuilder: Instantiator<Detail>"]),
			],
			app: [
				fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: ["@Received public let logger: Logger"]),
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let home: Home"]),
				"""
				func navigatorIsFreedWhileItsDetailLives() -> Bool {
				    weak var weakNavigator: Navigator?
				    var detail: Detail?
				    do {
				        let home = Root().home
				        weakNavigator = home.navigator
				        detail = home.detailBuilder.instantiate()
				    }
				    return withExtendedLifetime(detail) { weakNavigator == nil }
				}
				""",
			],
		),
		"sendable": featureAndApp(
			feature: [
				"public protocol Api {}",
				seamFixtureType(named: "Logger", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Detail", isFinalClass: true, declarations: ["@Instantiated public let api: any Api"]),
				seamFixtureType(named: "Worker", isFinalClass: true, declarations: ["@Instantiated public let logger: Logger", "@Instantiated public let detail: Detail"]),
				seamFixtureType(named: "Home", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let workerBuilder: SendableInstantiator<Worker>"]),
			],
			app: [fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: ["@Received public let logger: Logger"]), seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let home: Home"])],
		),
		"twoSendable": featureAndApp(
			feature: [
				"public protocol Api {}",
				seamFixtureType(named: "Detail", isFinalClass: true, declarations: ["@Instantiated public let api: any Api"]),
				seamFixtureType(named: "Inner", isFinalClass: true, declarations: ["@Instantiated public let detail: Detail"]),
				seamFixtureType(named: "Outer", isFinalClass: true, declarations: ["@Instantiated public let innerBuilder: SendableInstantiator<Inner>"]),
				seamFixtureType(named: "Home", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let outerBuilder: SendableInstantiator<Outer>"]),
			],
			app: [fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: []), seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let home: Home"])],
		),
		"deep": [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"public protocol Service: AnyObject {}\npublic protocol Gadget: AnyObject {}",
				seamFixtureType(named: "Logger", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Navigator", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Detail", isFinalClass: true, declarations: ["@Instantiated public let service: any Service"]),
				seamFixtureType(named: "Innermost", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let logger: Logger", "@Instantiated public let detailBuilder: Instantiator<Detail>"]),
				seamFixtureType(named: "Inner", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let navigator: Navigator", "@Instantiated public let innermost: Innermost"]),
			]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Received public let logger: Logger"]),
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let inner: Inner"]),
				"""
				func freedWhileOnlyDetailLives() -> [Bool] {
				    weak var weakInner: Inner?
				    weak var weakNavigator: Navigator?
				    weak var weakLogger: Logger?
				    var detail: Detail?
				    do {
				        let inner = Root().inner
				        weakInner = inner
				        weakNavigator = inner.navigator
				        weakLogger = inner.innermost.logger
				        detail = inner.innermost.detailBuilder.instantiate()
				    }
				    return withExtendedLifetime(detail) { [weakInner == nil, weakNavigator == nil, weakLogger == nil] }
				}
				""",
			].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		],
		"insideFill": [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"public protocol Service {}\npublic protocol Gadget {}",
				seamFixtureType(named: "Screen", declarations: ["@Forwarded public let id: Int", "@Instantiated public let service: any Service"]),
				seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated public let screenBuilder: Instantiator<Screen>", "@Instantiated public let service: any Service"]),
			]),
			ModuleFixture(name: "Middle", packageName: "Other", swiftFileContent: [
				seamFixtureType(named: "Tag", isFinalClass: true, declarations: []),
				fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let gadget: any Gadget"]),
				seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated public let tag: Tag", "@Instantiated public let inner: Inner"]),
			].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				"""
				@Instantiable(fulfillingAdditionalTypes: [Gadget.self])
				public final class LiveGadget: Instantiable, Gadget {
				    public init(tag: Tag, id: Int?) {
				        self.tag = tag
				        self.id = id
				        LiveGadget.alive += 1
				    }

				    deinit {
				        LiveGadget.alive -= 1
				    }

				    @Received public let tag: Tag
				    @Received(onlyIfAvailable: true) public let id: Int?
				    nonisolated(unsafe) static var alive = 0
				}
				""",
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let outer: Outer"]),
				"""
				func liveGadgetsHoldingOnlyScreen() -> Int {
				    var screen: Screen?
				    do {
				        screen = Root().outer.inner.screenBuilder.instantiate(7)
				    }
				    return withExtendedLifetime(screen) { LiveGadget.alive }
				}
				""",
			].map { "import Feature\nimport Middle\n\n" + $0 }, dependencies: ["Feature", "Middle"]),
		],
		"tangle": [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"public protocol Api {}",
				"""
				@Instantiable
				public final class Mark: Instantiable {
				    public init() {
				        Mark.alive += 1
				    }

				    deinit {
				        Mark.alive -= 1
				    }

				    nonisolated(unsafe) public static var alive = 0
				}
				""",
				"""
				@Instantiable
				public final class MarkReader: Instantiable {
				    public init(mark: Mark?) {
				        self.mark = mark
				        MarkReader.alive += 1
				    }

				    deinit {
				        MarkReader.alive -= 1
				    }

				    @Received(onlyIfAvailable: true) public let mark: Mark?
				    nonisolated(unsafe) public static var alive = 0
				}
				""",
				seamFixtureType(named: "T", declarations: ["@Instantiated public let reader: MarkReader", "@Instantiated public let cBuilder: Instantiator<C>", "@Instantiated public let api: any Api"]),
				seamFixtureType(named: "C", declarations: ["@Instantiated public let mark: Mark", "@Instantiated public let tBuilder: Instantiator<T>"]),
				seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated public let tBuilder: Instantiator<T>", "@Instantiated public let cBuilder: Instantiator<C>"]),
			]),
			ModuleFixture(name: "Middle", packageName: "Other", swiftFileContent: [
				seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Instantiated public let hub: Hub"]),
			].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: ["@Received(onlyIfAvailable: true) public let mark: Mark?"]),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let shell: Shell"]),
				"""
				func liveMarksAndReaders(holdingOnlyLevelAtDepth depth: Int) -> [Int] {
				    var held: Any?
				    do {
				        var t = Root().shell.hub.tBuilder.instantiate()
				        held = t
				        var level = 1
				        while level < depth {
				            let c = t.cBuilder.instantiate()
				            level += 1
				            held = c
				            if level < depth {
				                t = c.tBuilder.instantiate()
				                level += 1
				                held = t
				            }
				        }
				    }
				    return withExtendedLifetime(held) { [Mark.alive, MarkReader.alive] }
				}
				""",
			].map { "import Feature\nimport Middle\n\n" + $0 }, dependencies: ["Feature", "Middle"]),
		],
		"builderLabel": featureAndApp(
			feature: ["public protocol Api {}", seamFixtureType(named: "Part", declarations: ["@Instantiated public let api: any Api"]), seamFixtureType(named: "Home", isSeam: true, declarations: ["@Instantiated public let builder: Instantiator<Part>"])],
			app: [fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: []), seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let home: Home"])],
		),
		"twoHoleTypes": featureAndApp(
			feature: ["public protocol Api {}\npublic protocol Panel {}", seamFixtureType(named: "Home", isSeam: true, declarations: ["@Instantiated public let api: any Api", #"@Instantiated(fulfilledByType: "LivePanel") public let panelBuilder: ErasedInstantiator<String, any Panel>"#])],
			app: [fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: []), fulfillingType(named: "LivePanel", fulfilling: "Panel", declarations: ["@Forwarded public let title: String"]), seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let home: Home"])],
		),
		"lazy": featureAndApp(
			feature: ["public protocol Api {}", seamFixtureType(named: "Logger", isFinalClass: true, declarations: []), seamFixtureType(named: "Detail", declarations: ["@Instantiated public let api: any Api"]), seamFixtureType(named: "Home", isSeam: true, declarations: ["@Instantiated public let logger: LazilyInstantiated<Logger>", "@Instantiated public let detail: LazilyInstantiated<Detail>"])],
			app: [fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: ["@Received public let logger: Logger"]), seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let home: Home"])],
		),
		"twoRoutes": featureAndApp(
			feature: [
				"public protocol Api {}",
				seamFixtureType(named: "Logger", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Tag", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Detail", declarations: ["@Instantiated public let api: any Api"]),
				seamFixtureType(named: "A", declarations: ["@Instantiated public let logger: Logger", "@Instantiated public let tag: Tag", "@Instantiated public let detailBuilder: Instantiator<Detail>"]),
				seamFixtureType(named: "B", declarations: ["@Instantiated public let logger: Logger", "@Instantiated public let detailBuilder: Instantiator<Detail>"]),
				seamFixtureType(named: "Home", isSeam: true, declarations: ["@Instantiated public let aBuilder: Instantiator<A>", "@Instantiated public let bBuilder: Instantiator<B>"]),
			],
			app: [fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: ["@Received public let logger: Logger", "@Received(onlyIfAvailable: true) public let tag: Tag?"]), seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let home: Home"])],
		),
		"next": featureAndApp(
			feature: [
				"public protocol Api: AnyObject {}",
				seamFixtureType(named: "Screen", isFinalClass: true, declarations: ["@Forwarded public let id: Int", "@Instantiated public let api: any Api", "@Instantiated public let next: Instantiator<Screen>"]),
				seamFixtureType(named: "Home", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let screenBuilder: Instantiator<Screen>"]),
			],
			app: [
				"""
				@Instantiable(fulfillingAdditionalTypes: [Api.self])
				public final class Live: Instantiable, Api {
				    public init(id: Int) {
				        self.id = id
				        Live.alive += 1
				    }

				    deinit {
				        Live.alive -= 1
				    }

				    @Received public let id: Int
				    nonisolated(unsafe) static var alive = 0
				}
				""",
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let home: Home"]),
				"""
				func liveCountHoldingOnlyScreen(atDepth depth: Int) -> Int {
				    var screen: Screen?
				    do {
				        var current = Root().home.screenBuilder.instantiate(1)
				        for id in 2...depth {
				            current = current.next.instantiate(id)
				        }
				        screen = current
				    }
				    return withExtendedLifetime(screen) { Live.alive }
				}
				""",
			],
		),
		"mark": featureAndApp(
			feature: markFeature,
			app: [fulfillingType(named: "Live", fulfilling: "Api", declarations: ["@Received public let cache: Cache", "@Received(onlyIfAvailable: true) public let mark: Mark?"]), seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let home: Home"])],
		),
		"reentryThroughOuterSeam": featureAndApp(
			feature: [
				"public protocol HoleService {}",
				seamFixtureType(named: "HoleAnalytics", isFinalClass: true, declarations: []),
				seamFixtureType(named: "HoleOwner", declarations: ["@Received public let holeAnalytics: HoleAnalytics", "@Instantiated public let holeService: any HoleService"]),
				seamFixtureType(named: "HoleSeam", isSeam: true, declarations: ["@Instantiated public let holeAnalytics: HoleAnalytics", "@Instantiated public let holeOwnerBuilder: Instantiator<HoleOwner>"]),
				seamFixtureType(named: "HoleRelay", isSeam: true, declarations: ["@Instantiated public let holeSeamBuilder: Instantiator<HoleSeam>"]),
			],
			app: [
				fulfillingType(named: "HoleImpl", fulfilling: "HoleService", declarations: ["@Received public let holeAnalytics: HoleAnalytics", "@Instantiated public let holeRelayBuilder: Instantiator<HoleRelay>"]),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let holeSeam: HoleSeam"]),
			],
		),
		"markOnly": featureAndApp(
			feature: markFeature,
			app: [
				fulfillingType(named: "Live", fulfilling: "Api", declarations: ["@Received(onlyIfAvailable: true) public let mark: Mark?"]),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let home: Home"]),
				"""
				func secondMonitorsMark() -> String {
				    let step = Root().home.screenBuilder.instantiate().stepBuilder.instantiate()
				    let mark = (step.next.instantiate().monitor as? Live)?.mark
				    return mark.map { $0 === step.mark ? "the mark of the first step" : "another mark" } ?? "nil"
				}
				""",
			],
		),
		"repeatedLabel": [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"public protocol Service: AnyObject {}",
				seamFixtureType(named: "Logger", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Tag", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Y", isFinalClass: true, declarations: ["@Instantiated public let service: any Service"]),
				seamFixtureType(named: "X", isFinalClass: true, declarations: ["@Instantiated public let logger: Logger", "@Instantiated public let child: Instantiator<Y>"]),
				seamFixtureType(named: "Innermost", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let tag: Tag", "@Instantiated public let child: Instantiator<X>"]),
				seamFixtureType(named: "Inner", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let innermost: Innermost"]),
			]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Received public let tag: Tag", "@Received public let logger: Logger"]),
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let inner: Inner"]),
			].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		],
		"rawLabel": [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"public protocol Service: AnyObject {}",
				seamFixtureType(named: "Logger", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Innermost", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let logger: Logger", "@Instantiated public let `my leaf`: any Service"]),
				seamFixtureType(named: "Inner", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let innermost: Innermost"]),
			]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Received public let logger: Logger"]),
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let inner: Inner"]),
			].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		],
		"tangleRawLabel": [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"public protocol Api {}",
				seamFixtureType(named: "Mark", isFinalClass: true, declarations: []),
				seamFixtureType(named: "MarkReader", declarations: ["@Received(onlyIfAvailable: true) public let mark: Mark?"]),
				seamFixtureType(named: "T", declarations: ["@Instantiated public let reader: MarkReader", "@Instantiated public let cBuilder: Instantiator<C>", "@Instantiated public let `my leaf`: any Api"]),
				seamFixtureType(named: "C", declarations: ["@Instantiated public let mark: Mark", "@Instantiated public let tBuilder: Instantiator<T>"]),
				seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated public let tBuilder: Instantiator<T>", "@Instantiated public let cBuilder: Instantiator<C>"]),
			]),
			ModuleFixture(name: "Middle", packageName: "Other", swiftFileContent: [
				seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Instantiated public let hub: Hub"]),
			].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: ["@Received(onlyIfAvailable: true) public let mark: Mark?"]),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let shell: Shell"]),
			].map { "import Feature\nimport Middle\n\n" + $0 }, dependencies: ["Feature", "Middle"]),
		],
		"tangleRawStem": [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"public protocol Api {}",
				seamFixtureType(named: "Mark", isFinalClass: true, declarations: []),
				seamFixtureType(named: "MarkReader", declarations: ["@Received(onlyIfAvailable: true) public let mark: Mark?"]),
				seamFixtureType(named: "T", declarations: ["@Instantiated public let reader: MarkReader", "@Instantiated public let cBuilder: Instantiator<C>", "@Instantiated public let api: any Api"]),
				seamFixtureType(named: "C", declarations: ["@Instantiated public let mark: Mark", "@Instantiated public let tBuilder: Instantiator<T>"]),
				seamFixtureType(named: "`My Hub`", isSeam: true, declarations: ["@Instantiated public let tBuilder: Instantiator<T>", "@Instantiated public let cBuilder: Instantiator<C>"]),
			]),
			ModuleFixture(name: "Middle", packageName: "Other", swiftFileContent: [
				seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Instantiated public let hub: `My Hub`"]),
			].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: ["@Received(onlyIfAvailable: true) public let mark: Mark?"]),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let shell: Shell"]),
			].map { "import Feature\nimport Middle\n\n" + $0 }, dependencies: ["Feature", "Middle"]),
		],
		"propertyNamedLikeLevelFunction": [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"public protocol HoleService {}",
				seamFixtureType(named: "HoleSeam", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let holeService: any HoleService"]),
				seamFixtureType(named: "Wrapper", isFinalClass: true, declarations: ["@Instantiated public let holeSeam: HoleSeam"]),
			]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				fulfillingType(named: "HoleImpl", fulfilling: "HoleService", declarations: ["@Instantiated public let holeServiceBuilder_HoleSeam: Instantiator<Wrapper>"]),
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let holeSeam: HoleSeam"]),
			].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		],
		"isolationInAttributes": [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"""
				@Instantiable(generateDependencyTree: true, generatedInitializerAttributes: "@MainActor")
				public final class Inner: Instantiable {
				    @MainActor public init(token: Token, leaf: Leaf) {
				        self.token = token
				        self.leaf = leaf
				    }

				    @Received let token: Token
				    @Instantiated let leaf: Leaf
				}
				""",
				seamFixtureType(named: "Leaf", isFinalClass: true, declarations: [], conformances: ", Sendable"),
				seamFixtureType(named: "Token", isFinalClass: true, declarations: [], conformances: ", Sendable"),
				"""
				@MainActor
				func handWritten(token: Token) -> Inner {
				    Inner(token: token)
				}
				""",
			], swiftFileContentByFilePath: plainDependencyTreeInitializersConfiguration),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				"""
				@MainActor
				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    public init(token: Token, inner: Inner) {
				        self.token = token
				        self.inner = inner
				    }

				    @Instantiated public let token: Token
				    @Instantiated public let inner: Inner
				}
				""",
			].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		],
		"nonisolatedInitializerBuildingMainActorTree": [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"""
				@MainActor
				@Instantiable(generateDependencyTree: true)
				public final class Inner: Instantiable {
				    nonisolated public init(token: Token, leaf: Leaf) {
				        self.token = token
				        self.leaf = leaf
				    }

				    @Received let token: Token
				    @Instantiated let leaf: Leaf
				}
				""",
				"""
				@MainActor
				@Instantiable
				public final class Leaf: Instantiable {
				    public init() {}
				}
				""",
				seamFixtureType(named: "Token", isFinalClass: true, declarations: [], conformances: ", Sendable"),
				"""
				@MainActor
				func handWritten(token: Token) -> Inner {
				    Inner(token: token)
				}
				""",
			], swiftFileContentByFilePath: plainDependencyTreeInitializersConfiguration),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				"""
				@MainActor
				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    public init(token: Token, inner: Inner) {
				        self.token = token
				        self.inner = inner
				    }

				    @Instantiated public let token: Token
				    @Instantiated public let inner: Inner
				}
				""",
			].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		],
		"nonisolatedInAttributes": [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"""
				@MainActor
				@Instantiable(generateDependencyTree: true, generatedInitializerAttributes: "nonisolated")
				public final class Inner: Instantiable {
				    nonisolated public init(token: Token, leaf: Leaf) {
				        self.token = token
				        self.leaf = leaf
				    }

				    @Received let token: Token
				    @Instantiated let leaf: Leaf
				}
				""",
				seamFixtureType(named: "Leaf", isFinalClass: true, declarations: [], conformances: ", Sendable"),
				seamFixtureType(named: "Token", isFinalClass: true, declarations: [], conformances: ", Sendable"),
				"""
				func handWritten(token: Token) -> Inner {
				    Inner(token: token)
				}
				""",
			], swiftFileContentByFilePath: plainDependencyTreeInitializersConfiguration),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let token: Token", "@Instantiated public let inner: Inner"]),
			].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		],
	]

	/// `Home`, a seam, builds `Screen`, which instantiates `cache`, a hole `monitor` and `Step`, which binds `mark` before it
	/// builds `Screen` again through `next`.
	private static let markFeature = [
		"public protocol Api: AnyObject {}",
		seamFixtureType(named: "Cache", declarations: []),
		seamFixtureType(named: "Mark", isFinalClass: true, declarations: []),
		seamFixtureType(named: "Step", declarations: ["@Instantiated public let api: any Api", "@Instantiated public let mark: Mark", "@Instantiated public let next: Instantiator<Screen>"]),
		seamFixtureType(named: "Screen", declarations: ["@Instantiated public let cache: Cache", "@Instantiated public let monitor: any Api", "@Instantiated public let stepBuilder: Instantiator<Step>"]),
		seamFixtureType(named: "Home", isSeam: true, declarations: ["@Instantiated public let screenBuilder: Instantiator<Screen>"]),
	]

	// MARK: Private

	private var filesToDelete: [URL]

	/// Expects every module of `output` to have compiled, and its generated code to have drawn no warning, where compile
	/// verification is enabled.
	private static func expectCompiles(_ output: MultiModuleTestOutput, sourceLocation: SourceLocation = #_sourceLocation) throws {
		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation, sourceLocation: sourceLocation)
		for module in compilation.modules {
			#expect(module.result.exitCode == 0, "\(module.moduleName): \(module.result.stderr)", sourceLocation: sourceLocation)
			#expect(module.generatedCodeWarnings.isEmpty, "\(module.moduleName): \(module.generatedCodeWarnings)", sourceLocation: sourceLocation)
		}
	}

	/// Expects the modules to construct, for each of `probes`, the values the same graph builds with no seam, every tree
	/// built inline.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectValuesEqualInlineBuild(modules: [ModuleFixture], probes: [DifferentialValueProbe], sourceLocation: SourceLocation = #_sourceLocation) async throws {
		guard compileVerificationIsEnabled else { return }
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		// Inline, every type is in one module, where no hole is left.
		let moduleNames = Set(modules.map(\.name))
		let inlineFiles = modules.flatMap(\.swiftFileContent).map { file in
			file.components(separatedBy: "\n").filter { line in !moduleNames.contains { line == "import \($0)" } }.joined(separator: "\n")
		}
		let inlineModules = [ModuleFixture(name: "App", packageName: "Other", swiftFileContent: inlineFixture(inlineFiles))]
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inlineModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		try await expectDifferentialValuesAgree(
			feature: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: output, modules: modules),
			knownRight: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: inlineOutput, modules: inlineModules),
			probes: probes,
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}

	/// `Feature`, which declares `feature`'s types and generates readable initializers, and `App`, which declares `app`'s.
	private static func featureAndApp(feature: [String], app: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature, swiftFileContentByFilePath: plainDependencyTreeInitializersConfiguration),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: app.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		]
	}

	/// A final class `name` that fulfills `fulfilledType` and declares `declarations`.
	private static func fulfillingType(named name: String, fulfilling fulfilledType: String, declarations: [String]) -> String {
		seamFixtureType(named: name, isFinalClass: true, declarations: declarations, conformances: ", \(fulfilledType)")
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [\(fulfilledType).self])\n")
	}
}
