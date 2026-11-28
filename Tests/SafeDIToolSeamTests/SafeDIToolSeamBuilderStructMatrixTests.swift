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

/// The neighbors of a seam that takes a builder struct: the order its declarations are read in, two bindings at one path,
/// a path through types narrower than the seam, its tiers, a module whose declarations default to the main actor, the
/// calls a seam that passes up its places makes of it, a public mock beside such a call, and the closures a person passes
/// its readable initializer.
struct SafeDIToolSeamBuilderStructMatrixTests: ~Copyable {
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

	@Test(arguments: twoRoutesDeclarationOrders)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesSameCode_whenTypesOfTwoRoutesIntoOneLevelAreDeclaredInOneFileInAnyOrder(order: [String]) async throws {
		// Files are read in path order, so only declarations in one file can be read in another order.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.twoRoutes(inOneFileInOrder: order), integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
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
	}

	@Test(arguments: twoFillsPlaceOrders)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsEachFillCaseThePayloadBoundForIt_whenTwoCasesBindPayloadsAtOneCall(placeOrder: [String]) async throws {
		// `Outer` binds its two cases' payloads at its call of `Inner`, in the order of their names, which is the order of
		// `Inner`'s builders under one order of its places and reverses the order its places are built in under the other.
		// `Inner` takes a builder struct for each place; the struct `Outer` hands it calls `Outer`'s dispatcher of that
		// builder, which hands its fill the payload of its own case.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.twoFills(placeOrder: placeOrder), integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		let expectedFiles = try #require(Self.twoFillsExpectedFiles[placeOrder.joined(separator: "-")])
		#expect(output.modules["Feature"]?.generatedFiles == expectedFiles["Feature"].map { ["Feature.swift": $0] })
		#expect(output.modules["Middle"]?.generatedFiles == expectedFiles["Middle"].map { ["Middle.swift": $0] })
		#expect(output.modules["App"]?.generatedFiles == expectedFiles["App"].map { ["App.swift": $0] })
		try Self.expectCompiles(output)
		let modules = Self.twoFills(placeOrder: placeOrder)
		try await expectValuesEqualInlineBuild(modules: modules, probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("liveGadgetsHoldingOnlyAlpha()")])
		let description = try await DifferentialValueOracle.describe(
			DifferentialValuePath(output: output, modules: modules),
			probes: [DifferentialValueProbe("liveGadgetsHoldingOnlyAlpha()")],
			filesToDelete: &filesToDelete,
		)
		if compileVerificationIsEnabled {
			#expect(description == """
			probe liveGadgetsHoldingOnlyAlpha()
			Int 1

			""")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsEachFamilysLevelFromItsOwnRoot_whenPlainAndSendableRoutesShareOnePath() async throws {
		// The path `aBuilder` leads to `A`'s place under the plain root and to `Worker`'s under the `@Sendable` root: each
		// root's step at that path is bound from that root's struct, and each place reads its own level's `logger`.
		let modules = Self.fixtures["twoFamiliesOnePath"] ?? []
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Home {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let aBuilder: __safeDI_ApiCarrier_A<__safeDI_Built>

		        public init(aBuilder: __safeDI_ApiCarrier_A<__safeDI_Built>) {
		            self.aBuilder = aBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(aBuilder: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_A<__safeDI_Built> {
		        public let api: (Logger) -> __safeDI_Built

		        public init(api: @escaping (Logger) -> __safeDI_Built) {
		            self.api = api
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(api: { _ in __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Worker<__safeDI_Built> {
		        public let api: (Logger) -> __safeDI_Built

		        public init(api: @escaping (Logger) -> __safeDI_Built) {
		            self.api = api
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(api: { _ in __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiSendableCarrier<__safeDI_Built>: Sendable {
		        public let aBuilder_Sendable: __safeDI_ApiSendableCarrier_A<__safeDI_Built>

		        public init(aBuilder_Sendable: __safeDI_ApiSendableCarrier_A<__safeDI_Built>) {
		            self.aBuilder_Sendable = aBuilder_Sendable
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(aBuilder_Sendable: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiSendableCarrier_A<__safeDI_Built>: Sendable {
		        public let workerBuilder: @Sendable () -> __safeDI_ApiCarrier_Worker<__safeDI_Built>

		        public init(workerBuilder: @escaping @Sendable () -> __safeDI_ApiCarrier_Worker<__safeDI_Built>) {
		            self.workerBuilder = workerBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(workerBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(apiBuilder: @escaping () -> any Api, apiSendableBuilder: @escaping @Sendable () -> any Api) {
		        self.init(__safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder), __safeDI_apiSendableBuilder: .init(__safeDI_noScope: apiSendableBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>, __safeDI_apiSendableBuilder: __safeDI_ApiSendableCarrier<any Api>) {
		        let __safeDI_apiBuilder_aBuilder = __safeDI_apiBuilder.aBuilder
		        let __safeDI_apiSendableBuilder_aBuilder_Sendable = __safeDI_apiSendableBuilder.aBuilder_Sendable
		        @inline(never) @Sendable nonisolated func __safeDI_workerBuilder() -> Worker {
		            let __safeDI_apiSendableBuilder_workerBuilder = __safeDI_apiSendableBuilder_aBuilder_Sendable.workerBuilder()
		            let logger = Logger()
		            let api: any Api = __safeDI_apiSendableBuilder_workerBuilder.api(logger)
		            return Worker(logger: logger, api: api)
		        }
		        @inline(never) func __safeDI_aBuilder() -> A {
		            let logger = Logger()
		            let api: any Api = __safeDI_apiBuilder_aBuilder.api(logger)
		            let workerBuilder = SendableInstantiator<Worker>(__safeDI_workerBuilder)
		            return A(logger: logger, api: api, workerBuilder: workerBuilder)
		        }
		        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		        self.init(aBuilder: aBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_C64AD5BEB0E776E5 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		            .init(aBuilder: __safeDI_apiBuilder_Home_A_Scope())
		        }
		        func __safeDI_apiBuilder_Home_A_Scope() -> Home.__safeDI_ApiCarrier_A<any Api> {
		            .init(api: { scope_logger in
		                let logger = scope_logger
		                let api: any Api = LiveApi(logger: logger)
		                return api
		            })
		        }
		        @Sendable nonisolated func __safeDI_apiSendableBuilder_Home() -> Home.__safeDI_ApiSendableCarrier<any Api> {
		            .init(aBuilder_Sendable: __safeDI_apiSendableBuilder_Home_A_Scope())
		        }
		        @Sendable nonisolated func __safeDI_apiSendableBuilder_Home_A_Scope() -> Home.__safeDI_ApiSendableCarrier_A<any Api> {
		            .init(workerBuilder: { __safeDI_apiBuilder_Home_Worker_Scope() })
		        }
		        @Sendable nonisolated func __safeDI_apiBuilder_Home_Worker_Scope() -> Home.__safeDI_ApiCarrier_Worker<any Api> {
		            .init(api: { scope_logger in
		                let logger = scope_logger
		                let api: any Api = LiveApi(logger: logger)
		                return api
		            })
		        }
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_C64AD5BEB0E776E5.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home(), __safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		"""])
		try Self.expectCompiles(output)
		try await expectValuesEqualInlineBuild(modules: modules, probes: [DifferentialValueProbe("Root().home.aBuilder.instantiate()"), DifferentialValueProbe("Root().home.aBuilder.instantiate().workerBuilder.instantiate()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresFieldOfInternalTypeAtItsAccess_whenPublicSeamsPathRunsThroughInternalTypes() async throws {
		// The structs name each level by an identifier, never by its internal type; `Detail`'s level carries its forwarded
		// `title` and its internal `secret`, which stays `internal`.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.fixtures["internalPath"] ?? [], integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Home {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public struct __safeDI_DetailValues2 {
		        public let title: String
		        internal let secret: Secret

		        init(title: String, secret: Secret) {
		            self.title = title
		            self.secret = secret
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let detailBuilder: (Navigator) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>

		        public init(detailBuilder: @escaping (Navigator) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>) {
		            self.detailBuilder = detailBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(detailBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Detail<__safeDI_Built> {
		        public let leafBuilder: (__safeDI_DetailValues2) -> __safeDI_ApiCarrier_Leaf<__safeDI_Built>

		        public init(leafBuilder: @escaping (__safeDI_DetailValues2) -> __safeDI_ApiCarrier_Leaf<__safeDI_Built>) {
		            self.leafBuilder = leafBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(leafBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
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
		        let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder.detailBuilder(navigator)
		        @inline(never) func __safeDI_leafBuilder(__safeDI_apiBuilder_leafBuilder: __safeDI_ApiCarrier_Leaf<any Api>) -> Leaf {
		            let api: any Api = __safeDI_apiBuilder_leafBuilder.api()
		            return Leaf(api: api)
		        }
		        @inline(never) func __safeDI_detailBuilder(title: String) -> Detail {
		            let secret = Secret()
		            let __safeDI_Detail_values2 = __safeDI_DetailValues2(title: title, secret: secret)
		            let __safeDI_apiBuilder_leafBuilder = __safeDI_apiBuilder_detailBuilder.leafBuilder(__safeDI_Detail_values2)
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(__safeDI_apiBuilder_leafBuilder: __safeDI_apiBuilder_leafBuilder)
		            }
		            return Detail(title: title, secret: secret, leafBuilder: leafBuilder)
		        }
		        let detailBuilder = Instantiator<Detail> {
		            __safeDI_detailBuilder(title: $0)
		        }
		        self.init(navigator: navigator, detailBuilder: detailBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_EFD12958E7691809 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		            .init(detailBuilder: { values_navigator in __safeDI_apiBuilder_Home_Detail_Scope(navigator: values_navigator) })
		        }
		        func __safeDI_apiBuilder_Home_Detail_Scope(navigator: Navigator) -> Home.__safeDI_ApiCarrier_Detail<any Api> {
		            .init(leafBuilder: { values in __safeDI_apiBuilder_Home_Leaf_Scope(navigator: navigator, title: values.title) })
		        }
		        func __safeDI_apiBuilder_Home_Leaf_Scope(navigator: Navigator, title: String) -> Home.__safeDI_ApiCarrier_Leaf<any Api> {
		            .init(api: {
		                let api: any Api = LiveApi(navigator: navigator, title: title)
		                return api
		            })
		        }
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_EFD12958E7691809.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
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
	mutating func generate_takesReadableBuilderAtEachTier_whenOptionalParameterIsPackage() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.fixtures["packageTier"] ?? [], integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Service {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public struct __safeDI_Values2 {
		        package let theme: LazilyInstantiated<Theme?>
		        public let badge: Badge

		        init(theme: LazilyInstantiated<Theme?>, badge: Badge) {
		            self.theme = theme
		            self.badge = badge
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let api: (__safeDI_Values2) -> __safeDI_Built

		        public init(api: @escaping (__safeDI_Values2) -> __safeDI_Built) {
		            self.api = api
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(api: { _ in __safeDI_builder() })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(apiBuilder: @escaping () -> any Api) {
		        self.init(__safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        self.init(__safeDI_theme: nil, __safeDI_apiBuilder: __safeDI_apiBuilder)
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    package convenience init(theme: Theme?, apiBuilder: @escaping () -> any Api) {
		        self.init(__safeDI_theme: theme, __safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    package convenience init(__safeDI_theme: @autoclosure @escaping () -> Theme?, __safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let theme = LazilyInstantiated<Theme?>(__safeDI_theme)
		        let badge = Badge(theme: theme.instance)
		        let __safeDI__values2 = __safeDI_Values2(theme: theme, badge: badge)
		        let api: any Api = __safeDI_apiBuilder.api(__safeDI__values2)
		        self.init(badge: badge, api: api)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_0FCB0160F9664B99 {}
		}
		"""])
		#expect(output.modules["Mid"]?.generatedFiles == ["Mid.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension MidRoot {
		    public convenience init() {
		        func __safeDI_apiBuilder_Service() -> Service.__safeDI_ApiCarrier<any Api> {
		            .init(api: { scope in
		                let api: any Api = MidApi()
		                return api
		            })
		        }
		        func __safeDI_shellBuilder(theme: Theme) -> MidShell {
		            func __safeDI_service() -> Service {
		                _ = Service.__safeDI_Service_0FCB0160F9664B99.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                return Service(__safeDI_theme: theme, __safeDI_apiBuilder: __safeDI_apiBuilder_Service())
		            }
		            let service: Service = __safeDI_service()
		            return MidShell(theme: theme, service: service)
		        }
		        let shellBuilder = Instantiator<MidShell> {
		            __safeDI_shellBuilder(theme: $0)
		        }
		        self.init(shellBuilder: shellBuilder)
		    }
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension AppRoot {
		    public convenience init() {
		        func __safeDI_apiBuilder_Service() -> Service.__safeDI_ApiCarrier<any Api> {
		            .init(api: { scope in
		                let api: any Api = AppApi()
		                return api
		            })
		        }
		        func __safeDI_service() -> Service {
		            _ = Service.__safeDI_Service_0FCB0160F9664B99.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Service(__safeDI_apiBuilder: __safeDI_apiBuilder_Service())
		        }
		        let service: Service = __safeDI_service()
		        self.init(service: service)
		    }
		}
		"""])
		try Self.expectCompiles(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesReadableBuilderAtEachTier_whenOptionalParameterIsInternal() async throws {
		// No generated call reaches the `internal` tier: a module that can fill the place is another module. Code written in
		// `Feature` calls its readable initializer.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.fixtures["internalTier"] ?? [], integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Service {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public struct __safeDI_Values2 {
		        internal let color: LazilyInstantiated<Color?>
		        public let swatch: Swatch

		        init(color: LazilyInstantiated<Color?>, swatch: Swatch) {
		            self.color = color
		            self.swatch = swatch
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let api: (__safeDI_Values2) -> __safeDI_Built

		        public init(api: @escaping (__safeDI_Values2) -> __safeDI_Built) {
		            self.api = api
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(api: { _ in __safeDI_builder() })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(apiBuilder: @escaping () -> any Api) {
		        self.init(__safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        self.init(__safeDI_color: nil, __safeDI_apiBuilder: __safeDI_apiBuilder)
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    internal convenience init(color: Color?, apiBuilder: @escaping () -> any Api) {
		        self.init(__safeDI_color: color, __safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    internal convenience init(__safeDI_color: @autoclosure @escaping () -> Color?, __safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let color = LazilyInstantiated<Color?>(__safeDI_color)
		        let swatch = Swatch(color: color.instance)
		        let __safeDI__values2 = __safeDI_Values2(color: color, swatch: swatch)
		        let api: any Api = __safeDI_apiBuilder.api(__safeDI__values2)
		        self.init(swatch: swatch, api: api)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_B46DB63012FC4965 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension AppRoot {
		    public convenience init() {
		        func __safeDI_apiBuilder_Service() -> Service.__safeDI_ApiCarrier<any Api> {
		            .init(api: { scope in
		                let api: any Api = AppApi()
		                return api
		            })
		        }
		        func __safeDI_service() -> Service {
		            _ = Service.__safeDI_Service_B46DB63012FC4965.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Service(__safeDI_apiBuilder: __safeDI_apiBuilder_Service())
		        }
		        let service: Service = __safeDI_service()
		        self.init(service: service)
		    }
		}
		"""])
		try Self.expectCompiles(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesReadableBuilderAtPackageTier_whenSeamIsPackage() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.fixtures["packageSeam"] ?? [], integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Service {
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
		    package convenience init(apiBuilder: @escaping () -> any Api) {
		        self.init(__safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    package convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let api: any Api = __safeDI_apiBuilder.api()
		        self.init(api: api)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_8A25914F93188023 {}
		}
		"""])
		#expect(output.modules["Mid"]?.generatedFiles == ["Mid.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension MidRoot {
		    public convenience init() {
		        func __safeDI_apiBuilder_Service() -> Service.__safeDI_ApiCarrier<any Api> {
		            .init(api: {
		                let api: any Api = MidApi()
		                return api
		            })
		        }
		        func __safeDI_service() -> Service {
		            _ = Service.__safeDI_Service_8A25914F93188023.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Service(__safeDI_apiBuilder: __safeDI_apiBuilder_Service())
		        }
		        let service: Service = __safeDI_service()
		        self.init(service: service)
		    }
		}
		"""])
		try Self.expectCompiles(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_compilesInModulesDefaultingToMainActor_whenMainActorSeamsOwnInitializerIsNonisolated() async throws {
		// `Inner` is explicitly `@MainActor` and its own initializer `nonisolated`, which stores `Sendable` values; every caller,
		// `Root` and the hand-written one, is on the main actor, as every declaration of these modules but `Token` is. `Leaf` is
		// explicitly `@MainActor`, so the generated initializer that builds it compiles only on the main actor: it takes
		// `Inner`'s isolation, which its callers share, never its own initializer's `nonisolated`.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.fixtures["mainActorNonisolatedInitializer"] ?? [], integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
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
		try await expectCompiles(output, inlineControl: Self.fixtures["mainActorNonisolatedInitializerInline"] ?? [])
		try await expectValuesEqualInlineBuild(modules: Self.fixtures["mainActorNonisolatedInitializerValues"] ?? [], probes: [DifferentialValueProbe("Root()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_compilesInModulesDefaultingToMainActor_whenMainActorSeamsFillBuildsItsOwnTree() async throws {
		// The fill declares a function, which the level function calls by name: declared inside the struct's closure, it would
		// not take the main actor's isolation.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.fixtures["mainActorPlain"] ?? [], integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Home {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let detailBuilder: (Navigator) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>

		        public init(detailBuilder: @escaping (Navigator) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>) {
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
		    public convenience init(apiBuilder: @escaping () -> any Api) {
		        self.init(__safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let navigator = Navigator()
		        let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder.detailBuilder(navigator)
		        @inline(never) func __safeDI_detailBuilder() -> Detail {
		            let api: any Api = __safeDI_apiBuilder_detailBuilder.api()
		            return Detail(api: api)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        self.init(navigator: navigator, detailBuilder: detailBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_C4B9D7A756031A26 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_C4B9D7A756031A26.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_apiBuilder_Home_Detail_Scope_api() -> any Api {
		                func __safeDI_api() -> LiveApi {
		                    let client = Client()
		                    return LiveApi(client: client)
		                }
		                let api: any Api = __safeDI_api()
		                return api
		            }
		            func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		                .init(detailBuilder: { values_navigator in __safeDI_apiBuilder_Home_Detail_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Detail_Scope() -> Home.__safeDI_ApiCarrier_Detail<any Api> {
		                .init(api: { __safeDI_apiBuilder_Home_Detail_Scope_api() })
		            }
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		"""])
		try await expectCompiles(output, inlineControl: Self.fixtures["mainActorPlainInline"] ?? [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_compilesInModulesDefaultingToMainActor_whenMainActorSeamBuildsPlaceInsideSendableFunction() async throws {
		// Each `@Sendable` local function, the seam's own and the calling module's, is `nonisolated`: inside the `@MainActor`
		// seam's initializer, or `Root`'s, a `@Sendable` local function is otherwise inferred to be on the main actor, which a
		// `@Sendable` function cannot be.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.fixtures["mainActorSendable"] ?? [], integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Home {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Worker<__safeDI_Built> {
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
		            let __safeDI_apiSendableBuilder_detail = __safeDI_apiSendableBuilder_workerBuilder.detail
		            let detail: Detail = __safeDI_detail(__safeDI_apiSendableBuilder_detail: __safeDI_apiSendableBuilder_detail)
		            return Worker(detail: detail)
		        }
		        let workerBuilder = SendableInstantiator<Worker>(__safeDI_workerBuilder)
		        self.init(workerBuilder: workerBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_0431767B3AEAC163 {}
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
		            .init(detail: __safeDI_apiBuilder_Home_Detail_Scope())
		        }
		        @Sendable nonisolated func __safeDI_apiBuilder_Home_Detail_Scope() -> Home.__safeDI_ApiCarrier_Detail<any Api> {
		            .init(api: {
		                let api: any Api = LiveApi()
		                return api
		            })
		        }
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_0431767B3AEAC163.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Home(__safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		"""])
		try await expectCompiles(output, inlineControl: Self.fixtures["mainActorSendableInline"] ?? [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsInnerSeamMemberOfSendableStruct_whenOuterSeamPassesUpPlaceBuiltInsideSendableFunction() async throws {
		// `Inner` holds `Innermost`'s scope and passes its place up, built inside a `@Sendable` function: `Inner` takes the
		// `@Sendable` family's struct, whose member for `Innermost` returns `Innermost`'s, and `Outer`'s dispatchers over
		// both structs are `@Sendable nonisolated`.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.fixtures["deepSendable"] ?? [], integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Inner {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ServiceSendableCarrier<__safeDI_Built>: Sendable {
		        public let innermost_Sendable: Innermost.__safeDI_ServiceSendableCarrier<__safeDI_Built>

		        public init(innermost_Sendable: Innermost.__safeDI_ServiceSendableCarrier<__safeDI_Built>) {
		            self.innermost_Sendable = innermost_Sendable
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(innermost_Sendable: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_serviceSendableBuilder: __safeDI_ServiceSendableCarrier<any Service>) {
		        let navigator = Navigator()
		        @inline(never) func __safeDI_innermost() -> Innermost {
		            _ = Innermost.__safeDI_Innermost_0E421A2032AE741E.self
		            return Innermost(__safeDI_serviceSendableBuilder: __safeDI_serviceSendableBuilder.innermost_Sendable)
		        }
		        let innermost: Innermost = __safeDI_innermost()
		        self.init(navigator: navigator, innermost: innermost)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_FDA346AE260C4082 {}
		}

		extension Innermost {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ServiceCarrier_Detail<__safeDI_Built> {
		        public let service: (Logger) -> __safeDI_Built

		        public init(service: @escaping (Logger) -> __safeDI_Built) {
		            self.service = service
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(service: { _ in __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ServiceSendableCarrier<__safeDI_Built>: Sendable {
		        public let detailBuilder: @Sendable () -> __safeDI_ServiceCarrier_Detail<__safeDI_Built>

		        public init(detailBuilder: @escaping @Sendable () -> __safeDI_ServiceCarrier_Detail<__safeDI_Built>) {
		            self.detailBuilder = detailBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(detailBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_serviceSendableBuilder: __safeDI_ServiceSendableCarrier<any Service>) {
		        @inline(never) @Sendable nonisolated func __safeDI_detailBuilder() -> Detail {
		            let __safeDI_serviceSendableBuilder_detailBuilder = __safeDI_serviceSendableBuilder.detailBuilder()
		            let logger = Logger()
		            let service: any Service = __safeDI_serviceSendableBuilder_detailBuilder.service(logger)
		            return Detail(logger: logger, service: service)
		        }
		        let detailBuilder = SendableInstantiator<Detail>(__safeDI_detailBuilder)
		        self.init(detailBuilder: detailBuilder)
		    }
		}

		extension Innermost {
		    public enum __safeDI_Innermost_0E421A2032AE741E {}
		}
		"""])
		#expect(output.modules["Mid"]?.generatedFiles == ["Mid.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Outer {
		    nonisolated public enum SafeDIScope_Gadget {
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
		    }

		    nonisolated public enum SafeDISendableScope_Gadget {
		        nonisolated public struct inner_serviceSendableBuilder_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
		            public let inner_serviceSendableBuilder: @Sendable (inner_serviceSendableBuilder_Values) -> Inner.__safeDI_ServiceSendableCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(inner_serviceSendableBuilder: @escaping @Sendable (inner_serviceSendableBuilder_Values) -> Inner.__safeDI_ServiceSendableCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.inner_serviceSendableBuilder = inner_serviceSendableBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		                self.init(inner_serviceSendableBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
		            }
		        }
		    }

		    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_gadgetSendableBuilder: SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget>) {
		        let tag = Tag()
		        @inline(never) func __safeDI_inner() -> Inner {
		            let __safeDI_gadgetSendableBuilder_inner_serviceSendableBuilder = __safeDI_gadgetSendableBuilder.inner_serviceSendableBuilder(SafeDISendableScope_Gadget.inner_serviceSendableBuilder_Values())
		            _ = Inner.__safeDI_Inner_FDA346AE260C4082.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            @inline(never) @Sendable nonisolated func __safeDI_serviceSendableBuilder_Innermost_Detail_Scope_service(_ scope_logger: Logger, __safeDI_inner_serviceSendableBuilder: SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
		                let logger = scope_logger
		                @inline(never) func __safeDI_service() -> DefaultService {
		                    let gadget: any Gadget = __safeDI_inner_serviceSendableBuilder.gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values())
		                    return DefaultService(logger: logger, gadget: gadget)
		                }
		                let service: any Service = __safeDI_service()
		                return service
		            }
		            @inline(never) @Sendable nonisolated func __safeDI_serviceSendableBuilder_Inner(up: Inner.__safeDI_ServiceSendableCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_ServiceSendableCarrier<any Service> {
		                .init(innermost_Sendable: __safeDI_serviceSendableBuilder_Innermost(up: up.innermost_Sendable))
		            }
		            @inline(never) @Sendable nonisolated func __safeDI_serviceSendableBuilder_Innermost(up: Innermost.__safeDI_ServiceSendableCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Innermost.__safeDI_ServiceSendableCarrier<any Service> {
		                .init(detailBuilder: { __safeDI_serviceBuilder_Innermost_Detail_Scope(up: up.detailBuilder()) })
		            }
		            @inline(never) @Sendable nonisolated func __safeDI_serviceBuilder_Innermost_Detail_Scope(up: Innermost.__safeDI_ServiceCarrier_Detail<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Innermost.__safeDI_ServiceCarrier_Detail<any Service> {
		                .init(service: { scope_logger in __safeDI_serviceSendableBuilder_Innermost_Detail_Scope_service(scope_logger, __safeDI_inner_serviceSendableBuilder: up.service(scope_logger)) })
		            }
		            return Inner(__safeDI_serviceSendableBuilder: __safeDI_serviceSendableBuilder_Inner(up: __safeDI_gadgetSendableBuilder_inner_serviceSendableBuilder))
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(tag: tag, inner: inner)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_E4BFBF1584BC0B92 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Mid)
		import Mid
		#endif

		extension Root {
		    public convenience init() {
		        @Sendable nonisolated func __safeDI_gadgetSendableBuilder_Outer() -> Outer.SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget> {
		            .init(inner_serviceSendableBuilder: { _ in __safeDI_gadgetBuilder_Outer_Inner() })
		        }
		        @Sendable nonisolated func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(logger: Logger) -> Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
		            .init(gadget: { _ in
		                let gadget: any Gadget = LiveGadget(logger: logger)
		                return gadget
		            })
		        }
		        @Sendable nonisolated func __safeDI_gadgetBuilder_Outer_Inner() -> Inner.__safeDI_ServiceSendableCarrier<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
		            .init(innermost_Sendable: __safeDI_gadgetBuilder_Outer_Innermost())
		        }
		        @Sendable nonisolated func __safeDI_gadgetBuilder_Outer_Innermost() -> Innermost.__safeDI_ServiceSendableCarrier<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
		            .init(detailBuilder: { __safeDI_gadgetBuilder_Outer_Innermost_Detail_Scope() })
		        }
		        @Sendable nonisolated func __safeDI_gadgetBuilder_Outer_Innermost_Detail_Scope() -> Innermost.__safeDI_ServiceCarrier_Detail<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
		            .init(service: { values_logger in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(logger: values_logger) })
		        }
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_E4BFBF1584BC0B92.self // If this line does not compile, compile the code SafeDI generates for module Mid into Mid: under Bazel, add Mid’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Outer(__safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_Outer())
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(outer: outer)
		    }
		}
		"""])
		try Self.expectCompiles(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_rebuildsEachSendableCaseWithoutItsValues_whenPassedUpPlaceIsBeneathTwoSendableFunctions() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.fixtures["twoNestedSendable"] ?? [], integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Inner {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ServiceSendableCarrier<__safeDI_Built>: Sendable {
		        public let innermost_Sendable: Innermost.__safeDI_ServiceSendableCarrier<__safeDI_Built>

		        public init(innermost_Sendable: Innermost.__safeDI_ServiceSendableCarrier<__safeDI_Built>) {
		            self.innermost_Sendable = innermost_Sendable
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(innermost_Sendable: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_serviceSendableBuilder: __safeDI_ServiceSendableCarrier<any Service>) {
		        let navigator = Navigator()
		        @inline(never) func __safeDI_innermost() -> Innermost {
		            _ = Innermost.__safeDI_Innermost_0E4839673138E517.self
		            return Innermost(__safeDI_serviceSendableBuilder: __safeDI_serviceSendableBuilder.innermost_Sendable)
		        }
		        let innermost: Innermost = __safeDI_innermost()
		        self.init(navigator: navigator, innermost: innermost)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_8E8BBA360A244AC1 {}
		}

		extension Innermost {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ServiceCarrier_Card<__safeDI_Built> {
		        public let service: (Logger) -> __safeDI_Built

		        public init(service: @escaping (Logger) -> __safeDI_Built) {
		            self.service = service
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(service: { _ in __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ServiceSendableCarrier<__safeDI_Built>: Sendable {
		        public let stackBuilder_Sendable: __safeDI_ServiceSendableCarrier_Stack<__safeDI_Built>

		        public init(stackBuilder_Sendable: __safeDI_ServiceSendableCarrier_Stack<__safeDI_Built>) {
		            self.stackBuilder_Sendable = stackBuilder_Sendable
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(stackBuilder_Sendable: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ServiceSendableCarrier_Stack<__safeDI_Built>: Sendable {
		        public let cardBuilder: @Sendable () -> __safeDI_ServiceCarrier_Card<__safeDI_Built>

		        public init(cardBuilder: @escaping @Sendable () -> __safeDI_ServiceCarrier_Card<__safeDI_Built>) {
		            self.cardBuilder = cardBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(cardBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_serviceSendableBuilder: __safeDI_ServiceSendableCarrier<any Service>) {
		        @inline(never) @Sendable nonisolated func __safeDI_cardBuilder(__safeDI_serviceSendableBuilder_stackBuilder_Sendable: __safeDI_ServiceSendableCarrier_Stack<any Service>) -> Card {
		            let __safeDI_serviceSendableBuilder_cardBuilder = __safeDI_serviceSendableBuilder_stackBuilder_Sendable.cardBuilder()
		            let logger = Logger()
		            let service: any Service = __safeDI_serviceSendableBuilder_cardBuilder.service(logger)
		            return Card(logger: logger, service: service)
		        }
		        @inline(never) @Sendable nonisolated func __safeDI_stackBuilder() -> Stack {
		            let __safeDI_serviceSendableBuilder_stackBuilder_Sendable = __safeDI_serviceSendableBuilder.stackBuilder_Sendable
		            let cardBuilder = SendableInstantiator<Card> {
		                __safeDI_cardBuilder(__safeDI_serviceSendableBuilder_stackBuilder_Sendable: __safeDI_serviceSendableBuilder_stackBuilder_Sendable)
		            }
		            return Stack(cardBuilder: cardBuilder)
		        }
		        let stackBuilder = SendableInstantiator<Stack>(__safeDI_stackBuilder)
		        self.init(stackBuilder: stackBuilder)
		    }
		}

		extension Innermost {
		    public enum __safeDI_Innermost_0E4839673138E517 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        @Sendable nonisolated func __safeDI_serviceSendableBuilder_Inner() -> Inner.__safeDI_ServiceSendableCarrier<any Service> {
		            .init(innermost_Sendable: __safeDI_serviceSendableBuilder_Innermost())
		        }
		        @Sendable nonisolated func __safeDI_serviceSendableBuilder_Innermost() -> Innermost.__safeDI_ServiceSendableCarrier<any Service> {
		            .init(stackBuilder_Sendable: __safeDI_serviceSendableBuilder_Innermost_Stack_Scope())
		        }
		        @Sendable nonisolated func __safeDI_serviceSendableBuilder_Innermost_Stack_Scope() -> Innermost.__safeDI_ServiceSendableCarrier_Stack<any Service> {
		            .init(cardBuilder: { __safeDI_serviceBuilder_Innermost_Card_Scope() })
		        }
		        @Sendable nonisolated func __safeDI_serviceBuilder_Innermost_Card_Scope() -> Innermost.__safeDI_ServiceCarrier_Card<any Service> {
		            .init(service: { scope_logger in
		                let logger = scope_logger
		                let service: any Service = DefaultService(logger: logger)
		                return service
		            })
		        }
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_8E8BBA360A244AC1.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Inner(__safeDI_serviceSendableBuilder: __safeDI_serviceSendableBuilder_Inner())
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(inner: inner)
		    }
		}
		"""])
		try Self.expectCompiles(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_rebuildsCaseFromRootWithEachLevelsValues_whenPassedUpPlaceIsThreeLevelsDeep() async throws {
		let modules = Self.fixtures["deepLeaf"] ?? []
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
		            _ = Innermost.__safeDI_Innermost_B842D270F952A270.self
		            return Innermost(__safeDI_serviceBuilder: __safeDI_serviceBuilder.innermost)
		        }
		        let innermost: Innermost = __safeDI_innermost()
		        self.init(navigator: navigator, innermost: innermost)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_69254168DAEF0084 {}
		}

		extension Innermost {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
		        public let aBuilder: (Logger) -> __safeDI_ServiceCarrier_A<__safeDI_Built>

		        public init(aBuilder: @escaping (Logger) -> __safeDI_ServiceCarrier_A<__safeDI_Built>) {
		            self.aBuilder = aBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(aBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ServiceCarrier_A<__safeDI_Built> {
		        public let bBuilder: (Tag) -> __safeDI_ServiceCarrier_B<__safeDI_Built>

		        public init(bBuilder: @escaping (Tag) -> __safeDI_ServiceCarrier_B<__safeDI_Built>) {
		            self.bBuilder = bBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(bBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ServiceCarrier_B<__safeDI_Built> {
		        public let service: (Badge) -> __safeDI_Built

		        public init(service: @escaping (Badge) -> __safeDI_Built) {
		            self.service = service
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(service: { _ in __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
		        let logger = Logger()
		        let __safeDI_serviceBuilder_aBuilder = __safeDI_serviceBuilder.aBuilder(logger)
		        @inline(never) func __safeDI_bBuilder(__safeDI_serviceBuilder_bBuilder: __safeDI_ServiceCarrier_B<any Service>) -> B {
		            let badge = Badge()
		            let service: any Service = __safeDI_serviceBuilder_bBuilder.service(badge)
		            return B(badge: badge, service: service)
		        }
		        @inline(never) func __safeDI_aBuilder() -> A {
		            let tag = Tag()
		            let __safeDI_serviceBuilder_bBuilder = __safeDI_serviceBuilder_aBuilder.bBuilder(tag)
		            let bBuilder = Instantiator<B> {
		                __safeDI_bBuilder(__safeDI_serviceBuilder_bBuilder: __safeDI_serviceBuilder_bBuilder)
		            }
		            return A(tag: tag, bBuilder: bBuilder)
		        }
		        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		        self.init(logger: logger, aBuilder: aBuilder)
		    }
		}

		extension Innermost {
		    public enum __safeDI_Innermost_B842D270F952A270 {}
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
		            .init(aBuilder: { values_logger in __safeDI_serviceBuilder_Innermost_A_Scope(logger: values_logger) })
		        }
		        func __safeDI_serviceBuilder_Innermost_A_Scope(logger: Logger) -> Innermost.__safeDI_ServiceCarrier_A<any Service> {
		            .init(bBuilder: { values_tag in __safeDI_serviceBuilder_Innermost_B_Scope(logger: logger, tag: values_tag) })
		        }
		        func __safeDI_serviceBuilder_Innermost_B_Scope(logger: Logger, tag: Tag) -> Innermost.__safeDI_ServiceCarrier_B<any Service> {
		            .init(service: { scope_badge in
		                let badge = scope_badge
		                let service: any Service = DefaultService(logger: logger, tag: tag, badge: badge)
		                return service
		            })
		        }
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_69254168DAEF0084.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner())
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(inner: inner)
		    }
		}
		"""])
		try Self.expectCompiles(output)
		try await expectValuesEqualInlineBuild(modules: modules, probes: [DifferentialValueProbe("Root().inner.innermost.aBuilder.instantiate().bBuilder.instantiate()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsLevelFunctionsToPublicMockThatBuildsSeamInline_whenCallerFillsPlaceReadingLevelValue() async throws {
		// `Inner`'s seam side hands `Innermost` a struct; its public mock builds `Innermost`'s tree itself and takes its builder
		// struct, as the seam does. `Screen`'s mock fills the place, which reads `logger` from `detailBuilder_Values`, so it
		// calls `Inner.__safeDI_mock` with level functions.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.fixtures["mockBeside"] ?? [], integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
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

		#if DEBUG
		extension Inner {
		    nonisolated public enum SafeDIMockScope_Service {
		        nonisolated public struct innermost_Values {
		            public let navigator: Navigator
		        }

		        nonisolated public enum Innermost_Scope {
		            nonisolated public struct detailBuilder_Values {
		                public let logger: Logger
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let detailBuilder: (detailBuilder_Values) -> SafeDIMockScope_Service.Detail_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(detailBuilder: @escaping (detailBuilder_Values) -> SafeDIMockScope_Service.Detail_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.detailBuilder = detailBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(detailBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		                }
		            }
		        }

		        nonisolated public enum Detail_Scope {
		            nonisolated public struct service_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let service: (service_Values) -> __safeDI_Built

		                public init(service: @escaping (service_Values) -> __safeDI_Built) {
		                    self.service = service
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(service: { _ in __safeDI_builder() })
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let innermost: (innermost_Values) -> SafeDIMockScope_Service.Innermost_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(innermost: @escaping (innermost_Values) -> SafeDIMockScope_Service.Innermost_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.innermost = innermost
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(innermost: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            navigator: (() -> Navigator)? = nil,
		            innermost: __safeDI_Feature_Innermost_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                navigator: navigator,
		                innermost: innermost
		            )
		        }

		        public var navigator: (() -> Navigator)? { __safeDI_storage.navigator }
		        public var innermost: __safeDI_Feature_Innermost_MockConfiguration { __safeDI_storage.innermost }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                navigator: (() -> Navigator)?,
		                innermost: __safeDI_Feature_Innermost_MockConfiguration
		            ) {
		                self.navigator = navigator
		                self.innermost = innermost
		            }

		            let navigator: (() -> Navigator)?
		            let innermost: __safeDI_Feature_Innermost_MockConfiguration
		        }
		    }

		    public static func mock(
		        serviceBuilder: @escaping () -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Inner {
		        Inner.__safeDI_mock(serviceBuilder: .init(__safeDI_noScope: serviceBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        serviceBuilder __safeDI_serviceBuilder: Inner.SafeDIMockScope_Service.__safeDI_Builder<any Service>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Inner {
		        let navigator = if let safeDIBuilder = safeDIOverrides.navigator { safeDIBuilder() } else { Navigator() }
		        let __safeDI_serviceBuilder_innermost = __safeDI_serviceBuilder.innermost(SafeDIMockScope_Service.innermost_Values(navigator: navigator))
		        func __safeDI_innermost() -> Innermost {
		            let logger = if let safeDIBuilder = safeDIOverrides.innermost.logger { safeDIBuilder() } else { Logger() }
		            let __safeDI_serviceBuilder_detailBuilder = __safeDI_serviceBuilder_innermost.detailBuilder(SafeDIMockScope_Service.Innermost_Scope.detailBuilder_Values(logger: logger))
		            func __safeDI_detailBuilder() -> Detail {
		                let service: any Service = __safeDI_serviceBuilder_detailBuilder.service(SafeDIMockScope_Service.Detail_Scope.service_Values())
		                return if let safeDIBuilder = safeDIOverrides.innermost.detailBuilder { safeDIBuilder(service) } else { Detail(service: service) }
		            }
		            let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		            return Innermost.__safeDI_init(logger: logger, detailBuilder: detailBuilder, safeDIBuilder: safeDIOverrides.innermost.safeDIBuilder)
		        }
		        let innermost: Innermost = __safeDI_innermost()
		        return Inner(navigator: navigator, innermost: innermost)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_mock_DA6A3DB1524E7958 {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `Innermost` is constructed within the public mock trees of module `Feature`.
		nonisolated public struct __safeDI_Feature_Innermost_MockConfiguration {
		    public init(
		        logger: (() -> Logger)? = nil,
		        detailBuilder: ((any Service) -> Detail)? = nil,
		        _ safeDIBuilder: ((Logger, Instantiator<Detail>) -> Innermost)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            logger: logger,
		            detailBuilder: detailBuilder,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var logger: (() -> Logger)? { __safeDI_storage.logger }
		    public var detailBuilder: ((any Service) -> Detail)? { __safeDI_storage.detailBuilder }
		    /// Overrides how `Innermost` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((Logger, Instantiator<Detail>) -> Innermost)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            logger: (() -> Logger)?,
		            detailBuilder: ((any Service) -> Detail)?,
		            safeDIBuilder: ((Logger, Instantiator<Detail>) -> Innermost)?
		        ) {
		            self.logger = logger
		            self.detailBuilder = detailBuilder
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let logger: (() -> Logger)?
		        let detailBuilder: ((any Service) -> Detail)?
		        let safeDIBuilder: ((Logger, Instantiator<Detail>) -> Innermost)?
		    }
		}

		extension Innermost {
		    static func __safeDI_init(logger: Logger, detailBuilder: Instantiator<Detail>, safeDIBuilder: ((Logger, Instantiator<Detail>) -> Innermost)?) -> Innermost {
		        if let safeDIBuilder { safeDIBuilder(logger, detailBuilder) } else { Innermost(logger: logger, detailBuilder: detailBuilder) }
		    }
		}
		#endif

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
		        func __safeDI_screen() -> Screen {
		            func __safeDI_inner() -> Inner {
		                _ = Inner.__safeDI_Inner_6B37CE7AAF7A1362.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner())
		            }
		            let inner: Inner = __safeDI_inner()
		            return Screen(inner: inner)
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(screen: screen)
		    }
		}

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            inner: Inner.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                inner: inner
		            )
		        }

		        var inner: Inner.SafeDIOverrides { __safeDI_storage.inner }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                inner: Inner.SafeDIOverrides
		            ) {
		                self.inner = inner
		            }

		            let inner: Inner.SafeDIOverrides
		        }
		    }

		    static func mock(
		        serviceBuilder: (() -> any Service)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_inner() -> Inner {
		            func __safeDI_serviceBuilder_Inner() -> Inner.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
		                .init(innermost: { _ in __safeDI_serviceBuilder_Inner_Innermost_Scope() })
		            }
		            func __safeDI_serviceBuilder_Inner_Innermost_Scope() -> Inner.SafeDIMockScope_Service.Innermost_Scope.__safeDI_Builder<any Service> {
		                .init(detailBuilder: { values in __safeDI_serviceBuilder_Inner_Detail_Scope(logger: values.logger) })
		            }
		            func __safeDI_serviceBuilder_Inner_Detail_Scope(logger: Logger) -> Inner.SafeDIMockScope_Service.Detail_Scope.__safeDI_Builder<any Service> {
		                .init(service: { _ in
		                    let service: any Service = DefaultService(logger: logger)
		                    return service
		                })
		            }
		            _ = Inner.__safeDI_Inner_mock_DA6A3DB1524E7958.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Inner.__safeDI_mock(serviceBuilder: serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Inner(), safeDIOverrides: safeDIOverrides.inner)
		        }
		        let inner: Inner = __safeDI_inner()
		        return Screen(inner: inner)
		    }
		}
		#endif
		"""])
		try Self.expectCompiles(output)
		try await expectValuesEqualInlineBuild(modules: Self.fixtures["mockBeside"] ?? [], probes: [DifferentialValueProbe("Screen.mock().inner.innermost.detailBuilder.instantiate().service")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_compilesEachClosureAPersonPasses_whenCodeCallsReadableInitializers() async throws {
		// `handWrittenCalls()` passes the plain builder a closure, an initializer, a stored closure and a stored `@Sendable`
		// closure, and the `@Sendable` builder each of those that is `@Sendable`.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.fixtures["readableCalls"] ?? [], integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
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
		    public convenience init(apiBuilder: @escaping () -> any Api) {
		        self.init(__safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let api: any Api = __safeDI_apiBuilder.api()
		        self.init(api: api)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_59C182C3751C58E0 {}
		}

		extension SendableHome {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Worker<__safeDI_Built> {
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
		        @inline(never) @Sendable nonisolated func __safeDI_workerBuilder() -> Worker {
		            let __safeDI_apiSendableBuilder_workerBuilder = __safeDI_apiSendableBuilder.workerBuilder()
		            let api: any Api = __safeDI_apiSendableBuilder_workerBuilder.api()
		            return Worker(api: api)
		        }
		        let workerBuilder = SendableInstantiator<Worker>(__safeDI_workerBuilder)
		        self.init(workerBuilder: workerBuilder)
		    }
		}

		extension SendableHome {
		    public enum __safeDI_SendableHome_B4C4458CA3131A58 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		            .init(api: {
		                let api: any Api = LiveApi()
		                return api
		            })
		        }
		        @Sendable nonisolated func __safeDI_apiSendableBuilder_SendableHome() -> SendableHome.__safeDI_ApiSendableCarrier<any Api> {
		            .init(workerBuilder: { __safeDI_apiBuilder_SendableHome_Worker_Scope() })
		        }
		        @Sendable nonisolated func __safeDI_apiBuilder_SendableHome_Worker_Scope() -> SendableHome.__safeDI_ApiCarrier_Worker<any Api> {
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
		        func __safeDI_sendableHome() -> SendableHome {
		            _ = SendableHome.__safeDI_SendableHome_B4C4458CA3131A58.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return SendableHome(__safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_SendableHome())
		        }
		        let sendableHome: SendableHome = __safeDI_sendableHome()
		        self.init(home: home, sendableHome: sendableHome)
		    }
		}
		"""])
		try Self.expectCompiles(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesBuilderStructInBothFamilies_whenSendablePlaceForwardsBesidePlainPlaceThatDoesNot() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.fixtures["plainPlaceBesideSendableForwardingPlace"] ?? [], integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_PanelCarrier<__safeDI_Built> {
		        public let panel: () -> __safeDI_Built

		        public init(panel: @escaping () -> __safeDI_Built) {
		            self.panel = panel
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(panel: { __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_PanelSendableCarrier<__safeDI_Built>: Sendable {
		        public let heldBuilder: @Sendable () -> SendableErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder

		        public init(heldBuilder: @escaping @Sendable () -> SendableErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.heldBuilder = heldBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.init(heldBuilder: { __safeDI_builder })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(panelBuilder: @escaping () -> Panel, panelSendableBuilder: @escaping SendableInstantiator<Panel>.Builder) {
		        self.init(__safeDI_panelBuilder: .init(__safeDI_noScope: panelBuilder), __safeDI_panelSendableBuilder: .init(__safeDI_noScope: panelSendableBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_panelBuilder: __safeDI_PanelCarrier<Panel>, __safeDI_panelSendableBuilder: __safeDI_PanelSendableCarrier<Panel>) {
		        let panel: Panel = __safeDI_panelBuilder.panel()
		        let heldBuilder = SendableInstantiator<Panel>(__safeDI_panelSendableBuilder.heldBuilder())
		        self.init(panel: panel, heldBuilder: heldBuilder)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_286D15B0DCA35A43 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_286D15B0DCA35A43.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_panelBuilder_Host_panel() -> Panel {
		                func __safeDI_panel() -> DefaultPanel {
		                    let tag = Tag()
		                    return DefaultPanel(tag: tag)
		                }
		                let panel: Panel = __safeDI_panel()
		                return panel
		            }
		            @Sendable nonisolated func __safeDI_panelSendableBuilder_Host_heldBuilder() -> SendableInstantiator<Panel>.Builder {
		                @Sendable nonisolated func __safeDI_heldBuilder() -> DefaultPanel {
		                    let tag = Tag()
		                    return DefaultPanel(tag: tag)
		                }
		                return { _ in __safeDI_heldBuilder() }
		            }
		            func __safeDI_panelBuilder_Host() -> Host.__safeDI_PanelCarrier<Panel> {
		                .init(panel: { __safeDI_panelBuilder_Host_panel() })
		            }
		            @Sendable nonisolated func __safeDI_panelSendableBuilder_Host() -> Host.__safeDI_PanelSendableCarrier<Panel> {
		                .init(heldBuilder: { __safeDI_panelSendableBuilder_Host_heldBuilder() })
		            }
		            return Host(__safeDI_panelBuilder: __safeDI_panelBuilder_Host(), __safeDI_panelSendableBuilder: __safeDI_panelSendableBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		try Self.expectCompiles(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesBuilderStructInBothFamilies_whenPlainPlaceForwardsBesideSendablePlaceThatDoesNot() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.fixtures["forwardingPlaceBesideSendablePlainPlace"] ?? [], integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_PanelCarrier<__safeDI_Built> {
		        public let held: () -> ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder

		        public init(held: @escaping () -> ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.held = held
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.init(held: { __safeDI_builder })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_PanelCarrier_Worker<__safeDI_Built> {
		        public let panel: () -> __safeDI_Built

		        public init(panel: @escaping () -> __safeDI_Built) {
		            self.panel = panel
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(panel: { __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_PanelSendableCarrier<__safeDI_Built>: Sendable {
		        public let workerBuilder: @Sendable () -> __safeDI_PanelCarrier_Worker<__safeDI_Built>

		        public init(workerBuilder: @escaping @Sendable () -> __safeDI_PanelCarrier_Worker<__safeDI_Built>) {
		            self.workerBuilder = workerBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(workerBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(panelBuilder: @escaping Instantiator<Panel>.Builder, panelSendableBuilder: @escaping @Sendable () -> Panel) {
		        self.init(__safeDI_panelBuilder: .init(__safeDI_noScope: panelBuilder), __safeDI_panelSendableBuilder: .init(__safeDI_noScope: panelSendableBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_panelBuilder: __safeDI_PanelCarrier<Panel>, __safeDI_panelSendableBuilder: __safeDI_PanelSendableCarrier<Panel>) {
		        let held = Instantiator<Panel>(__safeDI_panelBuilder.held())
		        @inline(never) @Sendable nonisolated func __safeDI_workerBuilder() -> Worker {
		            let __safeDI_panelSendableBuilder_workerBuilder = __safeDI_panelSendableBuilder.workerBuilder()
		            let panel: Panel = __safeDI_panelSendableBuilder_workerBuilder.panel()
		            return Worker(panel: panel)
		        }
		        let workerBuilder = SendableInstantiator<Worker>(__safeDI_workerBuilder)
		        self.init(held: held, workerBuilder: workerBuilder)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_3FB0969910BCAA7E {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_3FB0969910BCAA7E.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_panelBuilder_Host_held() -> Instantiator<Panel>.Builder {
		                func __safeDI_held() -> DefaultPanel {
		                    let tag = Tag()
		                    return DefaultPanel(tag: tag)
		                }
		                return { _ in __safeDI_held() }
		            }
		            @Sendable nonisolated func __safeDI_panelSendableBuilder_Host_Worker_Scope_panel() -> Panel {
		                func __safeDI_panel() -> DefaultPanel {
		                    let tag = Tag()
		                    return DefaultPanel(tag: tag)
		                }
		                let panel: Panel = __safeDI_panel()
		                return panel
		            }
		            func __safeDI_panelBuilder_Host() -> Host.__safeDI_PanelCarrier<Panel> {
		                .init(held: { __safeDI_panelBuilder_Host_held() })
		            }
		            @Sendable nonisolated func __safeDI_panelSendableBuilder_Host() -> Host.__safeDI_PanelSendableCarrier<Panel> {
		                .init(workerBuilder: { __safeDI_panelBuilder_Host_Worker_Scope() })
		            }
		            @Sendable nonisolated func __safeDI_panelBuilder_Host_Worker_Scope() -> Host.__safeDI_PanelCarrier_Worker<Panel> {
		                .init(panel: { __safeDI_panelSendableBuilder_Host_Worker_Scope_panel() })
		            }
		            return Host(__safeDI_panelBuilder: __safeDI_panelBuilder_Host(), __safeDI_panelSendableBuilder: __safeDI_panelSendableBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		try Self.expectCompiles(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesBuilderTakingNothing_whenOneBuilderReachesInstantiatorBesidePlainPlace() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.fixtures["plainPlaceBesideForwardingPlace"] ?? [], integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_PanelCarrier<__safeDI_Built> {
		        public let panel: () -> __safeDI_Built
		        public let held: (Panel) -> ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder

		        public init(panel: @escaping () -> __safeDI_Built, held: @escaping (Panel) -> ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.panel = panel
		            self.held = held
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(panel: { __safeDI_builder() }, held: { _ in { _ in __safeDI_builder() } })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(panelBuilder: @escaping () -> Panel) {
		        self.init(__safeDI_panelBuilder: .init(__safeDI_noScope: panelBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_panelBuilder: __safeDI_PanelCarrier<Panel>) {
		        let panel: Panel = __safeDI_panelBuilder.panel()
		        let held = Instantiator<Panel>(__safeDI_panelBuilder.held(panel))
		        self.init(panel: panel, held: held)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_39F98A0986A20D2E {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_39F98A0986A20D2E.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_panelBuilder_Host_panel() -> Panel {
		                func __safeDI_panel() -> DefaultPanel {
		                    let tag = Tag()
		                    return DefaultPanel(tag: tag)
		                }
		                let panel: Panel = __safeDI_panel()
		                return panel
		            }
		            func __safeDI_panelBuilder_Host_held() -> Instantiator<Panel>.Builder {
		                func __safeDI_held() -> DefaultPanel {
		                    let tag = Tag()
		                    return DefaultPanel(tag: tag)
		                }
		                return { _ in __safeDI_held() }
		            }
		            func __safeDI_panelBuilder_Host() -> Host.__safeDI_PanelCarrier<Panel> {
		                .init(panel: { __safeDI_panelBuilder_Host_panel() }, held: { values_panel in __safeDI_panelBuilder_Host_held() })
		            }
		            return Host(__safeDI_panelBuilder: __safeDI_panelBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		try Self.expectCompiles(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reentersLevelsFunction_whenOuterSeamPassesUpScreenThatOpensItself() async throws {
		// `Home`'s `Screen` builds another through `next`, and `Shell` passes `Home`'s place up: the member for `next` calls
		// the function `Root` builds `Screen`'s level with again, so a screen four or eight levels deep keeps one `Live`
		// alive, as inline.
		let modules = Self.fixtures["nextUnderShell"] ?? []
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Middle"]?.generatedFiles == ["Middle.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Shell {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let home: Home.__safeDI_ApiCarrier<__safeDI_Built>

		        public init(home: Home.__safeDI_ApiCarrier<__safeDI_Built>) {
		            self.home = home
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(home: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        @inline(never) func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_76AC111056905E55.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder.home)
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}

		extension Shell {
		    public enum __safeDI_Shell_80ECA18D33573374 {}
		}
		"""])
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

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
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
		#if canImport(Middle)
		import Middle
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_apiBuilder_Shell() -> Shell.__safeDI_ApiCarrier<any Api> {
		            .init(home: __safeDI_apiBuilder_Home())
		        }
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
		        func __safeDI_shell() -> Shell {
		            _ = Shell.__safeDI_Shell_80ECA18D33573374.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Shell(__safeDI_apiBuilder: __safeDI_apiBuilder_Shell())
		        }
		        let shell: Shell = __safeDI_shell()
		        self.init(shell: shell)
		    }
		}
		"""])
		try Self.expectCompiles(output)
		try await expectValuesEqualInlineBuild(modules: modules, probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().shell.home.screenBuilder.instantiate(1).next.instantiate(2).next.instantiate(3)"), DifferentialValueProbe("liveCountHoldingOnlyScreen(atDepth: 4)"), DifferentialValueProbe("liveCountHoldingOnlyScreen(atDepth: 8)")])
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
	mutating func generate_buildsLevelInSendableFunction_whenOuterSeamPassesUpScreenThatOpensItselfInSendableInstantiator() async throws {
		// `Screen` builds another in a `SendableInstantiator`, which reopens the level in a `@Sendable` function: that function
		// calls its family's member on each entry, so the `@Sendable` root's struct holds no loop, and `Root` builds
		// `Screen`'s level in a `@Sendable nonisolated` function.
		let modules = Self.fixtures["sendableLoopUnderShell"] ?? []
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Middle"]?.generatedFiles == ["Middle.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Shell {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let home: Home.__safeDI_ApiCarrier<__safeDI_Built>

		        public init(home: Home.__safeDI_ApiCarrier<__safeDI_Built>) {
		            self.home = home
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(home: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiSendableCarrier<__safeDI_Built>: Sendable {
		        public let home_Sendable: Home.__safeDI_ApiSendableCarrier<__safeDI_Built>

		        public init(home_Sendable: Home.__safeDI_ApiSendableCarrier<__safeDI_Built>) {
		            self.home_Sendable = home_Sendable
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(home_Sendable: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>, __safeDI_apiSendableBuilder: __safeDI_ApiSendableCarrier<any Api>) {
		        @inline(never) func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_228180A7BA0C6D1A.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder.home, __safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder.home_Sendable)
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}

		extension Shell {
		    public enum __safeDI_Shell_788289D71573702B {}
		}
		"""])
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
		        public let screenBuilder_Sendable: __safeDI_ApiSendableCarrier_Screen<__safeDI_Built>

		        public init(screenBuilder_Sendable: __safeDI_ApiSendableCarrier_Screen<__safeDI_Built>) {
		            self.screenBuilder_Sendable = screenBuilder_Sendable
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(screenBuilder_Sendable: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiSendableCarrier_Screen<__safeDI_Built>: Sendable {
		        public let again: @Sendable () -> __safeDI_ApiCarrier_Screen<__safeDI_Built>

		        public init(again: @escaping @Sendable () -> __safeDI_ApiCarrier_Screen<__safeDI_Built>) {
		            self.again = again
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(again: { .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>, __safeDI_apiSendableBuilder: __safeDI_ApiSendableCarrier<any Api>) {
		        let __safeDI_apiBuilder_screenBuilder = __safeDI_apiBuilder.screenBuilder
		        let __safeDI_apiSendableBuilder_screenBuilder_Sendable = __safeDI_apiSendableBuilder.screenBuilder_Sendable
		        @inline(never) @Sendable nonisolated func __safeDI_again() -> Screen {
		            let __safeDI_apiSendableBuilder_again = __safeDI_apiSendableBuilder_screenBuilder_Sendable.again()
		            let api: any Api = __safeDI_apiSendableBuilder_again.api()
		            let again = SendableInstantiator<Screen>(__safeDI_again)
		            return Screen(api: api, again: again)
		        }
		        @inline(never) func __safeDI_screenBuilder() -> Screen {
		            let api: any Api = __safeDI_apiBuilder_screenBuilder.api()
		            let again = SendableInstantiator<Screen>(__safeDI_again)
		            return Screen(api: api, again: again)
		        }
		        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
		        self.init(screenBuilder: screenBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_228180A7BA0C6D1A {}
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
		    public convenience init() {
		        func __safeDI_apiBuilder_Shell() -> Shell.__safeDI_ApiCarrier<any Api> {
		            .init(home: __safeDI_apiBuilder_Home())
		        }
		        func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		            .init(screenBuilder: __safeDI_apiBuilder_Home_Screen_Scope())
		        }
		        @Sendable nonisolated func __safeDI_apiBuilder_Home_Screen_Scope() -> Home.__safeDI_ApiCarrier_Screen<any Api> {
		            .init(api: {
		                let api: any Api = LiveApi()
		                return api
		            })
		        }
		        @Sendable nonisolated func __safeDI_apiSendableBuilder_Shell() -> Shell.__safeDI_ApiSendableCarrier<any Api> {
		            .init(home_Sendable: __safeDI_apiSendableBuilder_Home())
		        }
		        @Sendable nonisolated func __safeDI_apiSendableBuilder_Home() -> Home.__safeDI_ApiSendableCarrier<any Api> {
		            .init(screenBuilder_Sendable: __safeDI_apiSendableBuilder_Home_Screen_Scope())
		        }
		        @Sendable nonisolated func __safeDI_apiSendableBuilder_Home_Screen_Scope() -> Home.__safeDI_ApiSendableCarrier_Screen<any Api> {
		            .init(again: { __safeDI_apiBuilder_Home_Screen_Scope() })
		        }
		        func __safeDI_shell() -> Shell {
		            _ = Shell.__safeDI_Shell_788289D71573702B.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Shell(__safeDI_apiBuilder: __safeDI_apiBuilder_Shell(), __safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_Shell())
		        }
		        let shell: Shell = __safeDI_shell()
		        self.init(shell: shell)
		    }
		}
		"""])
		try Self.expectCompiles(output)
		try await expectValuesEqualInlineBuild(modules: modules, probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().shell.home.screenBuilder.instantiate().again.instantiate().again.instantiate()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsLevelInSendableFunction_whenOuterSeamPassesUpCycleClosingOnFunctionBuiltByValue() async throws {
		// `Hub` builds `A` by value, and `B`, built in `A`'s `SendableInstantiator`, builds `A` again, which calls the function
		// `Hub`'s tree builds `A` with from a `@Sendable` closure; `Shell` passes `Hub`'s place up. The cycle closes on a
		// `@Sendable` function, which calls its family's member on each entry, so the struct holds no loop, and `Root`
		// builds `B`'s level in a `@Sendable nonisolated` function.
		let modules = Self.fixtures["byValueLoopUnderShell"] ?? []
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Middle"]?.generatedFiles == ["Middle.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Shell {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiSendableCarrier<__safeDI_Built>: Sendable {
		        public let hub_Sendable: Hub.__safeDI_ApiSendableCarrier<__safeDI_Built>

		        public init(hub_Sendable: Hub.__safeDI_ApiSendableCarrier<__safeDI_Built>) {
		            self.hub_Sendable = hub_Sendable
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(hub_Sendable: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_apiSendableBuilder: __safeDI_ApiSendableCarrier<any Api>) {
		        @inline(never) func __safeDI_hub() -> Hub {
		            _ = Hub.__safeDI_Hub_2987642971A9E8B1.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Hub(__safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder.hub_Sendable)
		        }
		        let hub: Hub = __safeDI_hub()
		        self.init(hub: hub)
		    }
		}

		extension Shell {
		    public enum __safeDI_Shell_7CD6F06EC8CF7105 {}
		}
		"""])
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Hub {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_B<__safeDI_Built> {
		        public let api: (A) -> __safeDI_Built

		        public init(api: @escaping (A) -> __safeDI_Built) {
		            self.api = api
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(api: { _ in __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiSendableCarrier<__safeDI_Built>: Sendable {
		        public let a_Sendable: __safeDI_ApiSendableCarrier_A<__safeDI_Built>

		        public init(a_Sendable: __safeDI_ApiSendableCarrier_A<__safeDI_Built>) {
		            self.a_Sendable = a_Sendable
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(a_Sendable: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiSendableCarrier_A<__safeDI_Built>: Sendable {
		        public let bBuilder: @Sendable () -> __safeDI_ApiCarrier_B<__safeDI_Built>

		        public init(bBuilder: @escaping @Sendable () -> __safeDI_ApiCarrier_B<__safeDI_Built>) {
		            self.bBuilder = bBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(bBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_apiSendableBuilder: __safeDI_ApiSendableCarrier<any Api>) {
		        @inline(never) @Sendable nonisolated func __safeDI_a() -> A {
		            let __safeDI_apiSendableBuilder_a_Sendable = __safeDI_apiSendableBuilder.a_Sendable
		            let bBuilder = SendableInstantiator<B> {
		                __safeDI_bBuilder(__safeDI_apiSendableBuilder_a_Sendable: __safeDI_apiSendableBuilder_a_Sendable)
		            }
		            return A(bBuilder: bBuilder)
		        }
		        @inline(never) @Sendable nonisolated func __safeDI_bBuilder(__safeDI_apiSendableBuilder_a_Sendable: __safeDI_ApiSendableCarrier_A<any Api>) -> B {
		            let __safeDI_apiSendableBuilder_bBuilder = __safeDI_apiSendableBuilder_a_Sendable.bBuilder()
		            let a: A = __safeDI_a()
		            let api: any Api = __safeDI_apiSendableBuilder_bBuilder.api(a)
		            return B(api: api, a: a)
		        }
		        let a: A = __safeDI_a()
		        self.init(a: a)
		    }
		}

		extension Hub {
		    public enum __safeDI_Hub_2987642971A9E8B1 {}
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
		        @Sendable nonisolated func __safeDI_apiSendableBuilder_Shell() -> Shell.__safeDI_ApiSendableCarrier<any Api> {
		            .init(hub_Sendable: __safeDI_apiSendableBuilder_Hub())
		        }
		        @Sendable nonisolated func __safeDI_apiSendableBuilder_Hub() -> Hub.__safeDI_ApiSendableCarrier<any Api> {
		            .init(a_Sendable: __safeDI_apiSendableBuilder_Hub_A_Scope())
		        }
		        @Sendable nonisolated func __safeDI_apiSendableBuilder_Hub_A_Scope() -> Hub.__safeDI_ApiSendableCarrier_A<any Api> {
		            .init(bBuilder: { __safeDI_apiBuilder_Hub_B_Scope() })
		        }
		        @Sendable nonisolated func __safeDI_apiBuilder_Hub_B_Scope() -> Hub.__safeDI_ApiCarrier_B<any Api> {
		            .init(api: { scope_a in
		                let api: any Api = LiveApi()
		                return api
		            })
		        }
		        func __safeDI_shell() -> Shell {
		            _ = Shell.__safeDI_Shell_7CD6F06EC8CF7105.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Shell(__safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_Shell())
		        }
		        let shell: Shell = __safeDI_shell()
		        self.init(shell: shell)
		    }
		}
		"""])
		try Self.expectCompiles(output)
		try await expectValuesEqualInlineBuild(modules: modules, probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().shell.hub.a.bBuilder.instantiate().a.bBuilder.instantiate()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_sharesOneLevelFunctionBetweenFamilies_whenOuterSeamPassesUpBothFamiliesOverOneLoopedLevel() async throws {
		// `Home` builds `Screen` in an `Instantiator` and in a `SendableInstantiator`, and `Screen` builds itself again through
		// `next`: the looped level is reached from both root structs, so `Root` builds it in one `@Sendable nonisolated`
		// function that both families' members call.
		let modules = Self.fixtures["bothFamiliesLoopUnderShell"] ?? []
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Middle"]?.generatedFiles == ["Middle.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Shell {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let home: Home.__safeDI_ApiCarrier<__safeDI_Built>

		        public init(home: Home.__safeDI_ApiCarrier<__safeDI_Built>) {
		            self.home = home
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(home: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiSendableCarrier<__safeDI_Built>: Sendable {
		        public let home_Sendable: Home.__safeDI_ApiSendableCarrier<__safeDI_Built>

		        public init(home_Sendable: Home.__safeDI_ApiSendableCarrier<__safeDI_Built>) {
		            self.home_Sendable = home_Sendable
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(home_Sendable: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>, __safeDI_apiSendableBuilder: __safeDI_ApiSendableCarrier<any Api>) {
		        @inline(never) func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_4A42258D8046FCE3.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder.home, __safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder.home_Sendable)
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}

		extension Shell {
		    public enum __safeDI_Shell_A391C922F785D2FC {}
		}
		"""])
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
		        public let api: () -> __safeDI_Built
		        public let next: (any Api) -> __safeDI_ApiCarrier_Screen<__safeDI_Built>

		        public init(api: @escaping () -> __safeDI_Built, next: @escaping (any Api) -> __safeDI_ApiCarrier_Screen<__safeDI_Built>) {
		            self.api = api
		            self.next = next
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(api: { __safeDI_builder() }, next: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiSendableCarrier<__safeDI_Built>: Sendable {
		        public let sendableScreenBuilder: @Sendable () -> __safeDI_ApiCarrier_Screen<__safeDI_Built>

		        public init(sendableScreenBuilder: @escaping @Sendable () -> __safeDI_ApiCarrier_Screen<__safeDI_Built>) {
		            self.sendableScreenBuilder = sendableScreenBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(sendableScreenBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>, __safeDI_apiSendableBuilder: __safeDI_ApiSendableCarrier<any Api>) {
		        let __safeDI_apiBuilder_screenBuilder = __safeDI_apiBuilder.screenBuilder
		        @inline(never) func __safeDI_next(__safeDI_apiBuilder_next: __safeDI_ApiCarrier_Screen<any Api>) -> Screen {
		            let api: any Api = __safeDI_apiBuilder_next.api()
		            let next = Instantiator<Screen> {
		                __safeDI_next(__safeDI_apiBuilder_next: __safeDI_apiBuilder_next)
		            }
		            return Screen(api: api, next: next)
		        }
		        @inline(never) func __safeDI_screenBuilder() -> Screen {
		            let api: any Api = __safeDI_apiBuilder_screenBuilder.api()
		            let __safeDI_apiBuilder_next = __safeDI_apiBuilder_screenBuilder.next(api)
		            let next = Instantiator<Screen> {
		                __safeDI_next(__safeDI_apiBuilder_next: __safeDI_apiBuilder_next)
		            }
		            return Screen(api: api, next: next)
		        }
		        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
		        @inline(never) @Sendable nonisolated func __safeDI_next_(__safeDI_apiSendableBuilder_next: __safeDI_ApiCarrier_Screen<any Api>) -> Screen {
		            let api: any Api = __safeDI_apiSendableBuilder_next.api()
		            let next = Instantiator<Screen> {
		                __safeDI_next_(__safeDI_apiSendableBuilder_next: __safeDI_apiSendableBuilder_next)
		            }
		            return Screen(api: api, next: next)
		        }
		        @inline(never) @Sendable nonisolated func __safeDI_sendableScreenBuilder() -> Screen {
		            let __safeDI_apiSendableBuilder_sendableScreenBuilder = __safeDI_apiSendableBuilder.sendableScreenBuilder()
		            let api: any Api = __safeDI_apiSendableBuilder_sendableScreenBuilder.api()
		            let __safeDI_apiSendableBuilder_next = __safeDI_apiSendableBuilder_sendableScreenBuilder.next(api)
		            let next = Instantiator<Screen> {
		                __safeDI_next_(__safeDI_apiSendableBuilder_next: __safeDI_apiSendableBuilder_next)
		            }
		            return Screen(api: api, next: next)
		        }
		        let sendableScreenBuilder = SendableInstantiator<Screen>(__safeDI_sendableScreenBuilder)
		        self.init(screenBuilder: screenBuilder, sendableScreenBuilder: sendableScreenBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_4A42258D8046FCE3 {}
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
		    public convenience init() {
		        func __safeDI_apiBuilder_Shell() -> Shell.__safeDI_ApiCarrier<any Api> {
		            .init(home: __safeDI_apiBuilder_Home())
		        }
		        func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		            .init(screenBuilder: __safeDI_apiBuilder_Home_Screen_Scope())
		        }
		        @Sendable nonisolated func __safeDI_apiBuilder_Home_Screen_Scope() -> Home.__safeDI_ApiCarrier_Screen<any Api> {
		            .init(
		                api: {
		                    let api: any Api = LiveApi()
		                    return api
		                },
		                next: { values_api in __safeDI_apiBuilder_Home_Screen_Scope() }
		            )
		        }
		        @Sendable nonisolated func __safeDI_apiSendableBuilder_Shell() -> Shell.__safeDI_ApiSendableCarrier<any Api> {
		            .init(home_Sendable: __safeDI_apiSendableBuilder_Home())
		        }
		        @Sendable nonisolated func __safeDI_apiSendableBuilder_Home() -> Home.__safeDI_ApiSendableCarrier<any Api> {
		            .init(sendableScreenBuilder: { __safeDI_apiBuilder_Home_Screen_Scope() })
		        }
		        func __safeDI_shell() -> Shell {
		            _ = Shell.__safeDI_Shell_A391C922F785D2FC.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Shell(__safeDI_apiBuilder: __safeDI_apiBuilder_Shell(), __safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_Shell())
		        }
		        let shell: Shell = __safeDI_shell()
		        self.init(shell: shell)
		    }
		}
		"""])
		try Self.expectCompiles(output)
		try await expectValuesEqualInlineBuild(modules: modules, probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().shell.home.screenBuilder.instantiate().next.instantiate()"), DifferentialValueProbe("Root().shell.home.sendableScreenBuilder.instantiate().next.instantiate()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresDispatcherPerCalleeLevel_whenOuterSeamsFillCaseCarriesCalleeWhoseLevelReopens() async throws {
		// `Outer` fills `Inner`'s `service` with a type that holds `Outer`'s own place, so its dispatchers take `Inner`'s
		// struct over `Outer`'s level struct, and `Inner`'s `Screen` builds itself again through `next`: one dispatcher per
		// level of `Inner`'s, whose member for `next` calls its own level's dispatcher again.
		let modules = Self.fixtures["insideFillLoop"] ?? []
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
		            _ = Inner.__safeDI_Inner_F3B9DC72B16DBD2C.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
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
		                .init(service: { scope_id in __safeDI_serviceBuilder_Inner_Screen_Scope_service(scope_id, __safeDI_inner_serviceBuilder: up.service(scope_id)) }, next: { values_id, values_service in __safeDI_serviceBuilder_Inner_Screen_Scope(up: up.next(values_id, values_service)) })
		            }
		            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner(up: __safeDI_gadgetBuilder_inner_serviceBuilder))
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(tag: tag, inner: inner)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_EE81B3871ACF0FAD {}
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
		        public let next: (Int, any Service) -> __safeDI_ServiceCarrier_Screen<__safeDI_Built>

		        public init(service: @escaping (Int) -> __safeDI_Built, next: @escaping (Int, any Service) -> __safeDI_ServiceCarrier_Screen<__safeDI_Built>) {
		            self.service = service
		            self.next = next
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(service: { _ in __safeDI_builder() }, next: { _, _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
		        let __safeDI_serviceBuilder_screenBuilder = __safeDI_serviceBuilder.screenBuilder
		        @inline(never) func __safeDI_next(id: Int, __safeDI_serviceBuilder_next: __safeDI_ServiceCarrier_Screen<any Service>) -> Screen {
		            let service: any Service = __safeDI_serviceBuilder_next.service(id)
		            let next = Instantiator<Screen> {
		                __safeDI_next(id: $0, __safeDI_serviceBuilder_next: __safeDI_serviceBuilder_next)
		            }
		            return Screen(id: id, service: service, next: next)
		        }
		        @inline(never) func __safeDI_screenBuilder(id: Int) -> Screen {
		            let service: any Service = __safeDI_serviceBuilder_screenBuilder.service(id)
		            let __safeDI_serviceBuilder_next = __safeDI_serviceBuilder_screenBuilder.next(id, service)
		            let next = Instantiator<Screen> {
		                __safeDI_next(id: $0, __safeDI_serviceBuilder_next: __safeDI_serviceBuilder_next)
		            }
		            return Screen(id: id, service: service, next: next)
		        }
		        let screenBuilder = Instantiator<Screen> {
		            __safeDI_screenBuilder(id: $0)
		        }
		        let service: any Service = __safeDI_serviceBuilder.service(screenBuilder)
		        self.init(screenBuilder: screenBuilder, service: service)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_F3B9DC72B16DBD2C {}
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
		            .init(service: { values_id in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: values_id, tag: tag) }, next: { values_id, values_service in __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope(tag: tag) })
		        }
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_EE81B3871ACF0FAD.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
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
		try await expectValuesEqualInlineBuild(modules: modules, probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().outer.inner.screenBuilder.instantiate(7).next.instantiate(8)")])
	}

	// MARK: Expected files

	/// What each module of `twoFills(placeOrder:)` generates, by the place order joined with `-`.
	static let twoFillsExpectedFiles: [String: [String: String]] = [
		"alpha-zeta": [
			"Feature": generatedFileHeader + """
			extension Inner {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_AlphaCarrier<__safeDI_Built> {
			        public let alpha: () -> __safeDI_Built

			        public init(alpha: @escaping () -> __safeDI_Built) {
			            self.alpha = alpha
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(alpha: { __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ZetaCarrier<__safeDI_Built> {
			        public let zeta: (any Alpha) -> __safeDI_Built

			        public init(zeta: @escaping (any Alpha) -> __safeDI_Built) {
			            self.zeta = zeta
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(zeta: { _ in __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_alphaBuilder: __safeDI_AlphaCarrier<any Alpha>, __safeDI_zetaBuilder: __safeDI_ZetaCarrier<any Zeta>) {
			        let alpha: any Alpha = __safeDI_alphaBuilder.alpha()
			        let zeta: any Zeta = __safeDI_zetaBuilder.zeta(alpha)
			        self.init(alpha: alpha, zeta: zeta)
			    }
			}

			extension Inner {
			    public enum __safeDI_Inner_669E4E11316402D2 {}
			}
			""",
			"Middle": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Outer {
			    nonisolated public enum SafeDIScope_Gadget {
			        nonisolated public struct inner_alphaBuilder_Values {
			            public let tag: Tag
			        }

			        nonisolated public struct inner_zetaBuilder_Values {
			            public let tag: Tag
			        }

			        nonisolated public enum DefaultAlpha_Scope {
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

			        nonisolated public enum DefaultZeta_Scope {
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
			            public let inner_alphaBuilder: (inner_alphaBuilder_Values) -> Inner.__safeDI_AlphaCarrier<SafeDIScope_Gadget.DefaultAlpha_Scope.__safeDI_Builder<__safeDI_Built>>
			            public let inner_zetaBuilder: (inner_zetaBuilder_Values) -> Inner.__safeDI_ZetaCarrier<SafeDIScope_Gadget.DefaultZeta_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(inner_alphaBuilder: @escaping (inner_alphaBuilder_Values) -> Inner.__safeDI_AlphaCarrier<SafeDIScope_Gadget.DefaultAlpha_Scope.__safeDI_Builder<__safeDI_Built>>, inner_zetaBuilder: @escaping (inner_zetaBuilder_Values) -> Inner.__safeDI_ZetaCarrier<SafeDIScope_Gadget.DefaultZeta_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.inner_alphaBuilder = inner_alphaBuilder
			                self.inner_zetaBuilder = inner_zetaBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(inner_alphaBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }, inner_zetaBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			            }
			        }
			    }

			    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
			        let tag = Tag()
			        let __safeDI_gadgetBuilder_inner_alphaBuilder = __safeDI_gadgetBuilder.inner_alphaBuilder(SafeDIScope_Gadget.inner_alphaBuilder_Values(tag: tag))
			        let __safeDI_gadgetBuilder_inner_zetaBuilder = __safeDI_gadgetBuilder.inner_zetaBuilder(SafeDIScope_Gadget.inner_zetaBuilder_Values(tag: tag))
			        @inline(never) func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_669E4E11316402D2.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            @inline(never) func __safeDI_alphaBuilder_Inner_alpha(__safeDI_inner_alphaBuilder: SafeDIScope_Gadget.DefaultAlpha_Scope.__safeDI_Builder<any Gadget>) -> any Alpha {
			                @inline(never) func __safeDI_alpha() -> DefaultAlpha {
			                    let gadget: any Gadget = __safeDI_inner_alphaBuilder.gadget(SafeDIScope_Gadget.DefaultAlpha_Scope.gadget_Values())
			                    return DefaultAlpha(gadget: gadget)
			                }
			                let alpha: any Alpha = __safeDI_alpha()
			                return alpha
			            }
			            @inline(never) func __safeDI_zetaBuilder_Inner_zeta(_ scope_alpha: any Alpha, __safeDI_inner_zetaBuilder: SafeDIScope_Gadget.DefaultZeta_Scope.__safeDI_Builder<any Gadget>) -> any Zeta {
			                @inline(never) func __safeDI_zeta() -> DefaultZeta {
			                    let gadget: any Gadget = __safeDI_inner_zetaBuilder.gadget(SafeDIScope_Gadget.DefaultZeta_Scope.gadget_Values())
			                    return DefaultZeta(gadget: gadget)
			                }
			                let zeta: any Zeta = __safeDI_zeta()
			                return zeta
			            }
			            @inline(never) func __safeDI_alphaBuilder_Inner(up: Inner.__safeDI_AlphaCarrier<SafeDIScope_Gadget.DefaultAlpha_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_AlphaCarrier<any Alpha> {
			                .init(alpha: { __safeDI_alphaBuilder_Inner_alpha(__safeDI_inner_alphaBuilder: up.alpha()) })
			            }
			            @inline(never) func __safeDI_zetaBuilder_Inner(up: Inner.__safeDI_ZetaCarrier<SafeDIScope_Gadget.DefaultZeta_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_ZetaCarrier<any Zeta> {
			                .init(zeta: { scope_alpha in __safeDI_zetaBuilder_Inner_zeta(scope_alpha, __safeDI_inner_zetaBuilder: up.zeta(scope_alpha)) })
			            }
			            return Inner(__safeDI_alphaBuilder: __safeDI_alphaBuilder_Inner(up: __safeDI_gadgetBuilder_inner_alphaBuilder), __safeDI_zetaBuilder: __safeDI_zetaBuilder_Inner(up: __safeDI_gadgetBuilder_inner_zetaBuilder))
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(tag: tag, inner: inner)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_38E59F2DF66752D4 {}
			}
			""",
			"App": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			extension Root {
			    public init() {
			        func __safeDI_gadgetBuilder_Outer() -> Outer.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
			            .init(inner_alphaBuilder: { values in __safeDI_gadgetBuilder_Outer_Inner_SafeDICarrierScope_Alpha(tag: values.tag) }, inner_zetaBuilder: { values in __safeDI_gadgetBuilder_Outer_Inner_SafeDICarrierScope_Zeta(tag: values.tag) })
			        }
			        func __safeDI_gadgetBuilder_Outer_DefaultAlpha_Scope(tag: Tag) -> Outer.SafeDIScope_Gadget.DefaultAlpha_Scope.__safeDI_Builder<any Gadget> {
			            .init(gadget: { _ in
			                let gadget: any Gadget = LiveGadget(tag: tag)
			                return gadget
			            })
			        }
			        func __safeDI_gadgetBuilder_Outer_DefaultZeta_Scope(tag: Tag) -> Outer.SafeDIScope_Gadget.DefaultZeta_Scope.__safeDI_Builder<any Gadget> {
			            .init(gadget: { _ in
			                let gadget: any Gadget = LiveGadget(tag: tag)
			                return gadget
			            })
			        }
			        func __safeDI_gadgetBuilder_Outer_Inner_SafeDICarrierScope_Alpha(tag: Tag) -> Inner.__safeDI_AlphaCarrier<Outer.SafeDIScope_Gadget.DefaultAlpha_Scope.__safeDI_Builder<any Gadget>> {
			            .init(alpha: { __safeDI_gadgetBuilder_Outer_DefaultAlpha_Scope(tag: tag) })
			        }
			        func __safeDI_gadgetBuilder_Outer_Inner_SafeDICarrierScope_Zeta(tag: Tag) -> Inner.__safeDI_ZetaCarrier<Outer.SafeDIScope_Gadget.DefaultZeta_Scope.__safeDI_Builder<any Gadget>> {
			            .init(zeta: { values_alpha in __safeDI_gadgetBuilder_Outer_DefaultZeta_Scope(tag: tag) })
			        }
			        func __safeDI_outer() -> Outer {
			            _ = Outer.__safeDI_Outer_38E59F2DF66752D4.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Outer(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Outer())
			        }
			        let outer: Outer = __safeDI_outer()
			        self.init(outer: outer)
			    }
			}
			""",
		],
		"zeta-alpha": [
			"Feature": generatedFileHeader + """
			extension Inner {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_AlphaCarrier<__safeDI_Built> {
			        public let alpha: (any Zeta) -> __safeDI_Built

			        public init(alpha: @escaping (any Zeta) -> __safeDI_Built) {
			            self.alpha = alpha
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(alpha: { _ in __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ZetaCarrier<__safeDI_Built> {
			        public let zeta: () -> __safeDI_Built

			        public init(zeta: @escaping () -> __safeDI_Built) {
			            self.zeta = zeta
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(zeta: { __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_alphaBuilder: __safeDI_AlphaCarrier<any Alpha>, __safeDI_zetaBuilder: __safeDI_ZetaCarrier<any Zeta>) {
			        let zeta: any Zeta = __safeDI_zetaBuilder.zeta()
			        let alpha: any Alpha = __safeDI_alphaBuilder.alpha(zeta)
			        self.init(zeta: zeta, alpha: alpha)
			    }
			}

			extension Inner {
			    public enum __safeDI_Inner_D8330B6A95F51428 {}
			}
			""",
			"Middle": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Outer {
			    nonisolated public enum SafeDIScope_Gadget {
			        nonisolated public struct inner_alphaBuilder_Values {
			            public let tag: Tag
			        }

			        nonisolated public struct inner_zetaBuilder_Values {
			            public let tag: Tag
			        }

			        nonisolated public enum DefaultAlpha_Scope {
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

			        nonisolated public enum DefaultZeta_Scope {
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
			            public let inner_alphaBuilder: (inner_alphaBuilder_Values) -> Inner.__safeDI_AlphaCarrier<SafeDIScope_Gadget.DefaultAlpha_Scope.__safeDI_Builder<__safeDI_Built>>
			            public let inner_zetaBuilder: (inner_zetaBuilder_Values) -> Inner.__safeDI_ZetaCarrier<SafeDIScope_Gadget.DefaultZeta_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(inner_alphaBuilder: @escaping (inner_alphaBuilder_Values) -> Inner.__safeDI_AlphaCarrier<SafeDIScope_Gadget.DefaultAlpha_Scope.__safeDI_Builder<__safeDI_Built>>, inner_zetaBuilder: @escaping (inner_zetaBuilder_Values) -> Inner.__safeDI_ZetaCarrier<SafeDIScope_Gadget.DefaultZeta_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.inner_alphaBuilder = inner_alphaBuilder
			                self.inner_zetaBuilder = inner_zetaBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(inner_alphaBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }, inner_zetaBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			            }
			        }
			    }

			    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
			        let tag = Tag()
			        let __safeDI_gadgetBuilder_inner_alphaBuilder = __safeDI_gadgetBuilder.inner_alphaBuilder(SafeDIScope_Gadget.inner_alphaBuilder_Values(tag: tag))
			        let __safeDI_gadgetBuilder_inner_zetaBuilder = __safeDI_gadgetBuilder.inner_zetaBuilder(SafeDIScope_Gadget.inner_zetaBuilder_Values(tag: tag))
			        @inline(never) func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_D8330B6A95F51428.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            @inline(never) func __safeDI_alphaBuilder_Inner_alpha(_ scope_zeta: any Zeta, __safeDI_inner_alphaBuilder: SafeDIScope_Gadget.DefaultAlpha_Scope.__safeDI_Builder<any Gadget>) -> any Alpha {
			                @inline(never) func __safeDI_alpha() -> DefaultAlpha {
			                    let gadget: any Gadget = __safeDI_inner_alphaBuilder.gadget(SafeDIScope_Gadget.DefaultAlpha_Scope.gadget_Values())
			                    return DefaultAlpha(gadget: gadget)
			                }
			                let alpha: any Alpha = __safeDI_alpha()
			                return alpha
			            }
			            @inline(never) func __safeDI_zetaBuilder_Inner_zeta(__safeDI_inner_zetaBuilder: SafeDIScope_Gadget.DefaultZeta_Scope.__safeDI_Builder<any Gadget>) -> any Zeta {
			                @inline(never) func __safeDI_zeta() -> DefaultZeta {
			                    let gadget: any Gadget = __safeDI_inner_zetaBuilder.gadget(SafeDIScope_Gadget.DefaultZeta_Scope.gadget_Values())
			                    return DefaultZeta(gadget: gadget)
			                }
			                let zeta: any Zeta = __safeDI_zeta()
			                return zeta
			            }
			            @inline(never) func __safeDI_alphaBuilder_Inner(up: Inner.__safeDI_AlphaCarrier<SafeDIScope_Gadget.DefaultAlpha_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_AlphaCarrier<any Alpha> {
			                .init(alpha: { scope_zeta in __safeDI_alphaBuilder_Inner_alpha(scope_zeta, __safeDI_inner_alphaBuilder: up.alpha(scope_zeta)) })
			            }
			            @inline(never) func __safeDI_zetaBuilder_Inner(up: Inner.__safeDI_ZetaCarrier<SafeDIScope_Gadget.DefaultZeta_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_ZetaCarrier<any Zeta> {
			                .init(zeta: { __safeDI_zetaBuilder_Inner_zeta(__safeDI_inner_zetaBuilder: up.zeta()) })
			            }
			            return Inner(__safeDI_alphaBuilder: __safeDI_alphaBuilder_Inner(up: __safeDI_gadgetBuilder_inner_alphaBuilder), __safeDI_zetaBuilder: __safeDI_zetaBuilder_Inner(up: __safeDI_gadgetBuilder_inner_zetaBuilder))
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(tag: tag, inner: inner)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_88F1BE2DFCDCFFC2 {}
			}
			""",
			"App": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			extension Root {
			    public init() {
			        func __safeDI_gadgetBuilder_Outer() -> Outer.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
			            .init(inner_alphaBuilder: { values in __safeDI_gadgetBuilder_Outer_Inner_SafeDICarrierScope_Alpha(tag: values.tag) }, inner_zetaBuilder: { values in __safeDI_gadgetBuilder_Outer_Inner_SafeDICarrierScope_Zeta(tag: values.tag) })
			        }
			        func __safeDI_gadgetBuilder_Outer_DefaultAlpha_Scope(tag: Tag) -> Outer.SafeDIScope_Gadget.DefaultAlpha_Scope.__safeDI_Builder<any Gadget> {
			            .init(gadget: { _ in
			                let gadget: any Gadget = LiveGadget(tag: tag)
			                return gadget
			            })
			        }
			        func __safeDI_gadgetBuilder_Outer_DefaultZeta_Scope(tag: Tag) -> Outer.SafeDIScope_Gadget.DefaultZeta_Scope.__safeDI_Builder<any Gadget> {
			            .init(gadget: { _ in
			                let gadget: any Gadget = LiveGadget(tag: tag)
			                return gadget
			            })
			        }
			        func __safeDI_gadgetBuilder_Outer_Inner_SafeDICarrierScope_Alpha(tag: Tag) -> Inner.__safeDI_AlphaCarrier<Outer.SafeDIScope_Gadget.DefaultAlpha_Scope.__safeDI_Builder<any Gadget>> {
			            .init(alpha: { values_zeta in __safeDI_gadgetBuilder_Outer_DefaultAlpha_Scope(tag: tag) })
			        }
			        func __safeDI_gadgetBuilder_Outer_Inner_SafeDICarrierScope_Zeta(tag: Tag) -> Inner.__safeDI_ZetaCarrier<Outer.SafeDIScope_Gadget.DefaultZeta_Scope.__safeDI_Builder<any Gadget>> {
			            .init(zeta: { __safeDI_gadgetBuilder_Outer_DefaultZeta_Scope(tag: tag) })
			        }
			        func __safeDI_outer() -> Outer {
			            _ = Outer.__safeDI_Outer_88F1BE2DFCDCFFC2.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Outer(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Outer())
			        }
			        let outer: Outer = __safeDI_outer()
			        self.init(outer: outer)
			    }
			}
			""",
		],
	]

	// MARK: Fixtures

	/// The six orders of `A`, `B` and `Detail`, the three declarations of `twoRoutes(inOneFileInOrder:)`'s file.
	static let twoRoutesDeclarationOrders = [
		["A", "B", "Detail"], ["A", "Detail", "B"], ["B", "A", "Detail"], ["B", "Detail", "A"], ["Detail", "A", "B"], ["Detail", "B", "A"],
	]

	/// `Home`'s `Detail_Scope` reached through `A` and through `B`, each of which binds its own `logger`; only `A` binds `tag`,
	/// which `App`'s fill reads only if available. `A`, `B` and `Detail` are declared in one file, in `order`.
	static func twoRoutes(inOneFileInOrder order: [String]) -> [ModuleFixture] {
		let declarations = [
			"A": seamFixtureType(named: "A", declarations: ["@Instantiated public let logger: Logger", "@Instantiated public let tag: Tag", "@Instantiated public let detailBuilder: Instantiator<Detail>"]),
			"B": seamFixtureType(named: "B", declarations: ["@Instantiated public let logger: Logger", "@Instantiated public let detailBuilder: Instantiator<Detail>"]),
			"Detail": seamFixtureType(named: "Detail", declarations: ["@Instantiated public let api: any Api"]),
		]
		return [
			ModuleFixture(
				name: "Feature",
				packageName: "Shop",
				swiftFileContent: [
					"public protocol Api {}",
					seamFixtureType(named: "Logger", isFinalClass: true, declarations: []),
					seamFixtureType(named: "Tag", isFinalClass: true, declarations: []),
					seamFixtureType(named: "Home", isSeam: true, declarations: ["@Instantiated public let aBuilder: Instantiator<A>", "@Instantiated public let bBuilder: Instantiator<B>"]),
				],
				swiftFileContentByFilePath: plainDependencyTreeInitializersConfiguration.merging(["Routes.swift": order.compactMap { declarations[$0] }.joined(separator: "\n\n")]) { first, _ in first },
			),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: ["@Received public let logger: Logger", "@Received(onlyIfAvailable: true) public let tag: Tag?"]),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let home: Home"]),
			].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		]
	}

	/// The two orders of `Inner`'s places `alpha` and `zeta`: the order of the names of the bindings of `Outer`'s two cases
	/// at its call of `Inner` agrees with the order of `Inner`'s builders in one and reverses it in the other.
	static let twoFillsPlaceOrders = [["alpha", "zeta"], ["zeta", "alpha"]]

	/// `Outer` calls `Inner` and fills both of its builders with a type that holds `Outer`'s own place `gadget`, so two of
	/// `Outer`'s cases carry `Inner`'s scope and bind their payloads at the call. `Inner` declares its places in `order`.
	static func twoFills(placeOrder order: [String]) -> [ModuleFixture] {
		let places = [
			"alpha": "@Instantiated public let alpha: any Alpha",
			"zeta": "@Instantiated public let zeta: any Zeta",
		]
		return [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"public protocol Alpha {}\npublic protocol Zeta {}\npublic protocol Gadget {}",
				seamFixtureType(named: "Inner", isSeam: true, declarations: order.compactMap { places[$0] }),
			]),
			ModuleFixture(name: "Middle", packageName: "Other", swiftFileContent: [
				seamFixtureType(named: "Tag", isFinalClass: true, declarations: []),
				fulfillingType(named: "DefaultAlpha", fulfilling: "Alpha", declarations: ["@Instantiated public let gadget: any Gadget"]),
				fulfillingType(named: "DefaultZeta", fulfilling: "Zeta", declarations: ["@Instantiated public let gadget: any Gadget"]),
				seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated public let tag: Tag", "@Instantiated public let inner: Inner"]),
			].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				"""
				@Instantiable(fulfillingAdditionalTypes: [Gadget.self])
				public final class LiveGadget: Instantiable, Gadget {
				    public init(tag: Tag) {
				        self.tag = tag
				        LiveGadget.alive += 1
				    }

				    deinit {
				        LiveGadget.alive -= 1
				    }

				    @Received public let tag: Tag
				    nonisolated(unsafe) static var alive = 0
				}
				""",
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let outer: Outer"]),
				"""
				func liveGadgetsHoldingOnlyAlpha() -> Int {
				    var alpha: (any Alpha)?
				    do {
				        alpha = Root().outer.inner.alpha
				    }
				    return withExtendedLifetime(alpha) { LiveGadget.alive }
				}
				""",
			].map { "import Feature\nimport Middle\n\n" + $0 }, dependencies: ["Feature", "Middle"]),
		]
	}

	/// Each cell's modules, by the name the cell's test reads it under.
	static let fixtures: [String: [ModuleFixture]] = [
		// `A`'s level is reached by the place `A` builds itself, in plain code, and by the place `Worker` builds inside the
		// `@Sendable` function `A` builds it in: one path under the plain root and under the `@Sendable` root.
		"twoFamiliesOnePath": featureAndApp(
			feature: [
				"public protocol Api {}",
				seamFixtureType(named: "Logger", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Worker", isFinalClass: true, declarations: ["@Instantiated public let logger: Logger", "@Instantiated public let api: any Api"]),
				seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated public let logger: Logger", "@Instantiated public let api: any Api", "@Instantiated public let workerBuilder: SendableInstantiator<Worker>"]),
				seamFixtureType(named: "Home", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let aBuilder: Instantiator<A>"]),
			],
			app: [
				fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: ["@Received public let logger: Logger"]),
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let home: Home"]),
			],
		),
		// A public `Home` whose path to its place runs through the internal `Detail` and `Leaf`; `Detail` forwards `title` and
		// binds the internal `secret`.
		"internalPath": featureAndApp(
			feature: [
				"public protocol Api {}",
				seamFixtureType(named: "Navigator", isFinalClass: true, declarations: []),
				"""
				@Instantiable
				final class Secret: Instantiable {
				    init() {}
				}
				""",
				"""
				@Instantiable
				struct Leaf: Instantiable {
				    init(api: any Api) {
				        self.api = api
				    }

				    @Instantiated let api: any Api
				}
				""",
				"""
				@Instantiable
				struct Detail: Instantiable {
				    init(title: String, secret: Secret, leafBuilder: Instantiator<Leaf>) {
				        self.title = title
				        self.secret = secret
				        self.leafBuilder = leafBuilder
				    }

				    @Forwarded let title: String
				    @Instantiated let secret: Secret
				    @Instantiated let leafBuilder: Instantiator<Leaf>
				}
				""",
				"""
				@Instantiable(generateDependencyTree: true)
				public final class Home: Instantiable {
				    init(navigator: Navigator, detailBuilder: Instantiator<Detail>) {
				        self.navigator = navigator
				        self.detailBuilder = detailBuilder
				    }

				    @Instantiated public let navigator: Navigator
				    @Instantiated let detailBuilder: Instantiator<Detail>
				}
				""",
			],
			app: [
				fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: ["@Received public let navigator: Navigator", "@Received public let title: String"]),
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let home: Home"]),
			],
		),
		// `theme` is proven `package`: `Service` has a `public` and a `package` tier. `Mid`, in `Service`'s package, calls the
		// `package` tier; `App`, in another, the `public` one.
		"packageTier": [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"public protocol Api {}",
				"""
				@Instantiable
				public struct Badge: Instantiable {
				    package init(theme: Theme?) {
				        self.theme = theme
				    }

				    @Received(onlyIfAvailable: true) package let theme: Theme?
				}

				package struct Theme: Sendable {
				    package init() {}
				}
				""",
				seamFixtureType(named: "Service", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let badge: Badge", "@Instantiated public let api: any Api"]),
			], swiftFileContentByFilePath: plainDependencyTreeInitializersConfiguration),
			ModuleFixture(name: "Mid", packageName: "Shop", swiftFileContent: [
				fulfillingType(named: "MidApi", fulfilling: "Api", declarations: []),
				"""
				@Instantiable(isRoot: true)
				public final class MidRoot: Instantiable {
				    package init(shellBuilder: Instantiator<MidShell>) {
				        self.shellBuilder = shellBuilder
				    }

				    @Instantiated package let shellBuilder: Instantiator<MidShell>
				}
				""",
				"""
				@Instantiable
				package final class MidShell: Instantiable {
				    package init(theme: Theme, service: Service) {
				        self.theme = theme
				        self.service = service
				    }

				    @Forwarded package let theme: Theme
				    @Instantiated package let service: Service
				}
				""",
			].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				fulfillingType(named: "AppApi", fulfilling: "Api", declarations: []),
				seamFixtureType(named: "AppRoot", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let service: Service"]),
			].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		],
		// `color` is proven `internal`: `Service` has a `public` and an `internal` tier. `App` calls the `public` tier; code
		// written in `Feature` calls the readable `internal` one.
		"internalTier": [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"public protocol Api {}",
				"""
				@Instantiable
				public struct Swatch: Instantiable {
				    init(color: Color?) {
				        self.color = color
				    }

				    @Received(onlyIfAvailable: true) let color: Color?
				}

				struct Color: Sendable {
				    init() {}
				}
				""",
				seamFixtureType(named: "Service", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let swatch: Swatch", "@Instantiated public let api: any Api"]),
				"""
				struct HandWrittenApi: Api {}

				func handWrittenService() -> Service {
				    Service(color: Color(), apiBuilder: { HandWrittenApi() })
				}
				""",
			], swiftFileContentByFilePath: plainDependencyTreeInitializersConfiguration),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				fulfillingType(named: "AppApi", fulfilling: "Api", declarations: []),
				seamFixtureType(named: "AppRoot", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let service: Service"]),
			].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		],
		// A `package` seam whose place is of a `package` protocol: its widest tier is `package`, which `Mid` calls.
		"packageSeam": [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"package protocol Api {}",
				"""
				@Instantiable(generateDependencyTree: true)
				package final class Service: Instantiable {
				    package init(api: any Api) {
				        self.api = api
				    }

				    @Instantiated package let api: any Api
				}
				""",
			], swiftFileContentByFilePath: plainDependencyTreeInitializersConfiguration),
			ModuleFixture(name: "Mid", packageName: "Shop", swiftFileContent: [
				fulfillingType(named: "MidApi", fulfilling: "Api", declarations: []),
				"""
				@Instantiable(isRoot: true)
				public final class MidRoot: Instantiable {
				    package init(service: Service) {
				        self.service = service
				    }

				    @Instantiated package let service: Service
				}
				""",
			].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		],
		// `Inner`, explicitly `@MainActor`, whose own initializer is `nonisolated`, built by `Root` and by a hand-written caller.
		"mainActorNonisolatedInitializer": mainActorModules(feature: mainActorNonisolatedInitializerFeature + [mainActorNonisolatedInitializerHandWrittenCaller], app: mainActorNonisolatedInitializerApp),
		"mainActorNonisolatedInitializerInline": [ModuleFixture(name: "App", packageName: "Other", swiftFileContent: inlineFixture(mainActorNonisolatedInitializerFeature + mainActorNonisolatedInitializerApp), compilerSettings: mainActorByDefault)],
		// The same graph with no hand-written caller, whose every type spells its isolation, as the value comparison
		// compiles it with no default isolation.
		"mainActorNonisolatedInitializerValues": mainActorModules(feature: mainActorNonisolatedInitializerFeature, app: mainActorNonisolatedInitializerApp),
		// An explicitly `@MainActor` seam in modules whose declarations default to the main actor; `App` fills its place with
		// a type that builds a `Client` of its own.
		"mainActorPlain": mainActorModules(feature: mainActorPlainFeature, app: mainActorPlainApp),
		"mainActorPlainInline": [ModuleFixture(name: "App", packageName: "Other", swiftFileContent: inlineFixture(mainActorPlainFeature + mainActorPlainApp), compilerSettings: mainActorByDefault)],
		// The seam is `@MainActor`; `Worker`, `Detail` and the fill, built inside the `@Sendable` function, are `nonisolated`.
		"mainActorSendable": mainActorModules(feature: mainActorSendableFeature, app: mainActorSendableApp),
		"mainActorSendableInline": [ModuleFixture(name: "App", packageName: "Other", swiftFileContent: inlineFixture(mainActorSendableFeature + mainActorSendableApp), compilerSettings: mainActorByDefault)],
		// `Innermost` builds `Detail`, which holds its place, inside a `@Sendable` function; `Inner` passes the place up, and
		// `Outer` fills it with a type that holds `Outer`'s own place.
		"deepSendable": [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"public protocol Service: AnyObject {}\npublic protocol Gadget: AnyObject {}",
				seamFixtureType(named: "Logger", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Navigator", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Tag", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Detail", isFinalClass: true, declarations: ["@Instantiated public let logger: Logger", "@Instantiated public let service: any Service"]),
				seamFixtureType(named: "Innermost", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let detailBuilder: SendableInstantiator<Detail>"]),
				seamFixtureType(named: "Inner", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let navigator: Navigator", "@Instantiated public let innermost: Innermost"]),
			]),
			ModuleFixture(name: "Mid", packageName: "Other", swiftFileContent: [
				fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Received public let logger: Logger", "@Instantiated public let gadget: any Gadget"]),
				seamFixtureType(named: "Outer", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let tag: Tag", "@Instantiated public let inner: Inner"]),
			].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received public let logger: Logger"]),
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let outer: Outer"]),
			].map { "import Feature\nimport Mid\n\n" + $0 }, dependencies: ["Feature", "Mid"]),
		],
		// `Innermost` builds `Stack` in a `@Sendable` function, which builds `Card`, which holds the place, in another; `Inner`
		// passes the place up.
		"twoNestedSendable": [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"public protocol Service: AnyObject {}",
				seamFixtureType(named: "Logger", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Navigator", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Card", isFinalClass: true, declarations: ["@Instantiated public let logger: Logger", "@Instantiated public let service: any Service"]),
				seamFixtureType(named: "Stack", isFinalClass: true, declarations: ["@Instantiated public let cardBuilder: SendableInstantiator<Card>"]),
				seamFixtureType(named: "Innermost", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let stackBuilder: SendableInstantiator<Stack>"]),
				seamFixtureType(named: "Inner", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let navigator: Navigator", "@Instantiated public let innermost: Innermost"]),
			]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Received public let logger: Logger"]),
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let inner: Inner"]),
			].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		],
		// `Innermost`'s place is three levels beneath it, each level binding a value the fill reads; `Inner` passes it up.
		"deepLeaf": [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"public protocol Service: AnyObject {}",
				seamFixtureType(named: "Logger", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Tag", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Badge", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Navigator", isFinalClass: true, declarations: []),
				seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Instantiated public let badge: Badge", "@Instantiated public let service: any Service"]),
				seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated public let tag: Tag", "@Instantiated public let bBuilder: Instantiator<B>"]),
				seamFixtureType(named: "Innermost", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let logger: Logger", "@Instantiated public let aBuilder: Instantiator<A>"]),
				seamFixtureType(named: "Inner", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let navigator: Navigator", "@Instantiated public let innermost: Innermost"]),
			]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Received public let logger: Logger", "@Received public let tag: Tag", "@Received public let badge: Badge"]),
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let inner: Inner"]),
			].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		],
		// `Inner` passes `Innermost`'s place up and has a public mock; `App`'s `Screen` holds it, and `Screen`'s mock, which
		// cannot call `Inner`'s internal initializer, calls `Inner`'s.
		"mockBeside": [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"public protocol Service: AnyObject {}",
				seamFixtureType(named: "Logger", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Navigator", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Detail", isFinalClass: true, declarations: ["@Instantiated public let service: any Service"]),
				seamFixtureType(named: "Innermost", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let logger: Logger", "@Instantiated public let detailBuilder: Instantiator<Detail>"]),
				"""
				@Instantiable(generateDependencyTree: true, generateMock: .public)
				public final class Inner: Instantiable {
				    init(navigator: Navigator, innermost: Innermost) {
				        self.navigator = navigator
				        self.innermost = innermost
				    }

				    @Instantiated public let navigator: Navigator
				    @Instantiated public let innermost: Innermost
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Received public let logger: Logger"]),
				seamFixtureType(named: "Screen", isFinalClass: true, declarations: ["@Instantiated public let inner: Inner"])
					.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(generateMock: true)\n"),
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let screen: Screen"]),
			].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		],
		// Code written in `App` calls each readable initializer with each closure a person passes it.
		"readableCalls": featureAndApp(
			feature: [
				"public protocol Api {}",
				seamFixtureType(named: "Worker", isFinalClass: true, declarations: ["@Instantiated public let api: any Api"]),
				seamFixtureType(named: "Home", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let api: any Api"]),
				seamFixtureType(named: "SendableHome", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let workerBuilder: SendableInstantiator<Worker>"]),
			],
			app: [
				fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: []),
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let home: Home", "@Instantiated public let sendableHome: SendableHome"]),
				"""
				func handWrittenCalls() -> [AnyObject] {
				    let stored: () -> any Api = { LiveApi() }
				    let sendableStored: @Sendable () -> any Api = { LiveApi() }
				    return [
				        Home(apiBuilder: { LiveApi() }),
				        Home(apiBuilder: LiveApi.init),
				        Home(apiBuilder: stored),
				        Home(apiBuilder: sendableStored),
				        SendableHome(apiSendableBuilder: { LiveApi() }),
				        SendableHome(apiSendableBuilder: LiveApi.init),
				        SendableHome(apiSendableBuilder: sendableStored),
				    ]
				}
				""",
			],
		),
		// One hole type: a plain place that forwards nothing and a place held in a `SendableInstantiator`, which forwards.
		"plainPlaceBesideSendableForwardingPlace": panelModules(hostDeclarations: ["@Instantiated public let panel: Panel", "@Instantiated public let heldBuilder: SendableInstantiator<Panel>"]),
		// One hole type: a place held in an `Instantiator`, which forwards, and a place `Worker` builds inside a `@Sendable`
		// function, which forwards nothing.
		"forwardingPlaceBesideSendablePlainPlace": panelModules(hostDeclarations: ["@Instantiated public let held: Instantiator<Panel>", "@Instantiated public let workerBuilder: SendableInstantiator<Worker>"]),
		// One builder: a plain place that forwards nothing and a place held in an `Instantiator`, which forwards.
		"plainPlaceBesideForwardingPlace": panelModules(hostDeclarations: ["@Instantiated public let panel: Panel", "@Instantiated public let held: Instantiator<Panel>"]),
		// `Home`'s `Screen` builds another `Screen` through `next`; `Shell` passes `Home`'s place up.
		"nextUnderShell": [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"public protocol Api: AnyObject {}",
				seamFixtureType(named: "Screen", isFinalClass: true, declarations: ["@Forwarded public let id: Int", "@Instantiated public let api: any Api", "@Instantiated public let next: Instantiator<Screen>"]),
				seamFixtureType(named: "Home", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let screenBuilder: Instantiator<Screen>"]),
			]),
			ModuleFixture(name: "Middle", packageName: "Other", swiftFileContent: [
				seamFixtureType(named: "Shell", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let home: Home"]),
			].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
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
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let shell: Shell"]),
				"""
				func liveCountHoldingOnlyScreen(atDepth depth: Int) -> Int {
				    var screen: Screen?
				    do {
				        var current = Root().shell.home.screenBuilder.instantiate(1)
				        for id in 2...depth {
				            current = current.next.instantiate(id)
				        }
				        screen = current
				    }
				    return withExtendedLifetime(screen) { Live.alive }
				}
				""",
			].map { "import Feature\nimport Middle\n\n" + $0 }, dependencies: ["Feature", "Middle"]),
		],
		// `Home`'s `Screen` builds another `Screen` in a `SendableInstantiator`; `Shell` passes `Home`'s place up.
		"sendableLoopUnderShell": [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"public protocol Api: Sendable {}",
				seamFixtureType(named: "Screen", isFinalClass: true, declarations: ["@Instantiated public let api: any Api", "@Instantiated public let again: SendableInstantiator<Screen>"], conformances: ", Sendable"),
				seamFixtureType(named: "Home", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let screenBuilder: Instantiator<Screen>"]),
			]),
			ModuleFixture(name: "Middle", packageName: "Other", swiftFileContent: [
				seamFixtureType(named: "Shell", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let home: Home"]),
			].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: []),
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let shell: Shell"]),
			].map { "import Feature\nimport Middle\n\n" + $0 }, dependencies: ["Feature", "Middle"]),
		],
		// `Hub` builds `A` by value; `B`, built in `A`'s `SendableInstantiator`, builds `A` again; `Shell` passes `Hub`'s place
		// up.
		"byValueLoopUnderShell": [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"public protocol Api: Sendable {}",
				seamFixtureType(named: "A", declarations: ["@Instantiated public let bBuilder: SendableInstantiator<B>"], conformances: ", Sendable"),
				seamFixtureType(named: "B", declarations: ["@Instantiated public let api: any Api", "@Instantiated public let a: A"], conformances: ", Sendable"),
				seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated public let a: A"], conformances: ", Sendable"),
			]),
			ModuleFixture(name: "Middle", packageName: "Other", swiftFileContent: [
				seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Instantiated public let hub: Hub"]),
			].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: []),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let shell: Shell"]),
			].map { "import Feature\nimport Middle\n\n" + $0 }, dependencies: ["Feature", "Middle"]),
		],
		// `Home` builds `Screen` in an `Instantiator` and in a `SendableInstantiator`, and `Screen` builds itself again through
		// `next`; `Shell` passes `Home`'s place up.
		"bothFamiliesLoopUnderShell": [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"public protocol Api: Sendable {}",
				seamFixtureType(named: "Screen", isFinalClass: true, declarations: ["@Instantiated public let api: any Api", "@Instantiated public let next: Instantiator<Screen>"]),
				seamFixtureType(named: "Home", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let screenBuilder: Instantiator<Screen>", "@Instantiated public let sendableScreenBuilder: SendableInstantiator<Screen>"]),
			]),
			ModuleFixture(name: "Middle", packageName: "Other", swiftFileContent: [
				seamFixtureType(named: "Shell", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let home: Home"]),
			].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: []),
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let shell: Shell"]),
			].map { "import Feature\nimport Middle\n\n" + $0 }, dependencies: ["Feature", "Middle"]),
		],
		// `Outer` fills `Inner`'s `service` with a type that holds `Outer`'s own place; `Inner`'s `Screen` builds itself again
		// through `next`.
		"insideFillLoop": [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"public protocol Service {}\npublic protocol Gadget {}",
				seamFixtureType(named: "Screen", declarations: ["@Forwarded public let id: Int", "@Instantiated public let service: any Service", "@Instantiated public let next: Instantiator<Screen>"]),
				seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated public let screenBuilder: Instantiator<Screen>", "@Instantiated public let service: any Service"]),
			]),
			ModuleFixture(name: "Middle", packageName: "Other", swiftFileContent: [
				seamFixtureType(named: "Tag", isFinalClass: true, declarations: []),
				fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let gadget: any Gadget"]),
				seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated public let tag: Tag", "@Instantiated public let inner: Inner"]),
			].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received public let tag: Tag", "@Received(onlyIfAvailable: true) public let id: Int?"]),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let outer: Outer"]),
			].map { "import Feature\nimport Middle\n\n" + $0 }, dependencies: ["Feature", "Middle"]),
		],
	]

	/// The compiler settings of a module whose declarations default to the main actor.
	static let mainActorByDefault = VerificationCompilerSettings(defaultIsolation: "MainActor")

	private static let mainActorNonisolatedInitializerFeature = [
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
		"@MainActor\n" + seamFixtureType(named: "Leaf", isFinalClass: true, declarations: []),
		seamFixtureType(named: "Token", isFinalClass: true, declarations: [], conformances: ", Sendable").replacingOccurrences(of: "public final class", with: "nonisolated public final class"),
	]

	/// A caller written by hand, which calls `Inner`'s readable initializer, so it is no part of the inline control.
	private static let mainActorNonisolatedInitializerHandWrittenCaller = """
	func handWritten(token: Token) -> Inner {
	    Inner(token: token)
	}
	"""

	/// `Root`, explicitly `@MainActor`: a type that conforms only to `Instantiable` is inferred `nonisolated`.
	private static let mainActorNonisolatedInitializerApp = [
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
	]

	private static let mainActorPlainFeature = [
		"nonisolated public protocol Api: AnyObject {}",
		"""
		@MainActor
		@Instantiable
		public final class Navigator: Instantiable {
		    public init() {}
		}
		""",
		"""
		@MainActor
		@Instantiable
		public final class Detail: Instantiable {
		    public init(api: any Api) {
		        self.api = api
		    }

		    @Instantiated public let api: any Api
		}
		""",
		"""
		@MainActor
		@Instantiable(generateDependencyTree: true)
		public final class Home: Instantiable {
		    public init(navigator: Navigator, detailBuilder: Instantiator<Detail>) {
		        self.navigator = navigator
		        self.detailBuilder = detailBuilder
		    }

		    @Instantiated public let navigator: Navigator
		    @Instantiated public let detailBuilder: Instantiator<Detail>
		}
		""",
	]

	private static let mainActorPlainApp = [
		"""
		@MainActor
		@Instantiable
		public final class Client: Instantiable {
		    public init() {}
		}
		""",
		"""
		@MainActor
		@Instantiable(fulfillingAdditionalTypes: [Api.self])
		public final class LiveApi: Api, Instantiable {
		    public init(client: Client) {
		        self.client = client
		    }

		    @Instantiated public let client: Client
		}
		""",
		"""
		@MainActor
		@Instantiable(isRoot: true)
		public final class Root: Instantiable {
		    public init(home: Home) {
		        self.home = home
		    }

		    @Instantiated public let home: Home
		}
		""",
	]

	private static let mainActorSendableFeature = [
		"nonisolated public protocol Api: AnyObject {}",
		"""
		@Instantiable
		nonisolated public final class Detail: Instantiable {
		    public init(api: any Api) {
		        self.api = api
		    }

		    @Instantiated public let api: any Api
		}
		""",
		"""
		@Instantiable
		nonisolated public final class Worker: Instantiable {
		    public init(detail: Detail) {
		        self.detail = detail
		    }

		    @Instantiated public let detail: Detail
		}
		""",
		"""
		@MainActor
		@Instantiable(generateDependencyTree: true)
		public final class Home: Instantiable {
		    public init(workerBuilder: SendableInstantiator<Worker>) {
		        self.workerBuilder = workerBuilder
		    }

		    @Instantiated public let workerBuilder: SendableInstantiator<Worker>
		}
		""",
	]

	private static let mainActorSendableApp = [
		"""
		@Instantiable(fulfillingAdditionalTypes: [Api.self])
		nonisolated public final class LiveApi: Api, Instantiable {
		    public init() {}
		}
		""",
		"""
		@MainActor
		@Instantiable(isRoot: true)
		public final class Root: Instantiable {
		    public init(home: Home) {
		        self.home = home
		    }

		    @Instantiated public let home: Home
		}
		""",
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

	/// Expects every module of `output` to have compiled, and its generated code to have drawn no warning, where compile
	/// verification is enabled, and compiles `inlineControl`, the same graph built in one module, as a control: a failure
	/// the inline build shares is one of every module whose declarations default to the main actor (issue #661), which
	/// the message says.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectCompiles(_ output: MultiModuleTestOutput, inlineControl: [ModuleFixture], sourceLocation: SourceLocation = #_sourceLocation) async throws {
		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation, sourceLocation: sourceLocation)
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inlineControl, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		let inlineCompilation = try #require(inlineOutput.compilation, sourceLocation: sourceLocation)
		let inlineFailure = inlineCompilation.failure.map { "\nThe same graph built in one module fails too (issue #661): \($0.result.stderr)" } ?? ""
		for module in compilation.modules {
			#expect(module.result.exitCode == 0, "\(module.moduleName): \(module.result.stderr)\(inlineFailure)", sourceLocation: sourceLocation)
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

	/// `featureAndApp(feature:app:)`'s modules, each compiled with its declarations defaulting to the main actor.
	private static func mainActorModules(feature: [String], app: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature, swiftFileContentByFilePath: plainDependencyTreeInitializersConfiguration, compilerSettings: mainActorByDefault),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: app.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"], compilerSettings: mainActorByDefault),
		]
	}

	/// `Feature`'s seam `Host`, which declares `hostDeclarations`, of the class `Panel`, which conforms to `Instantiable` by
	/// hand and so is a hole, and of `Worker`, which holds a `Panel`; and `App`, whose `DefaultPanel` fills every place.
	private static func panelModules(hostDeclarations: [String]) -> [ModuleFixture] {
		featureAndApp(
			feature: [
				"""
				open class Panel: Instantiable, @unchecked Sendable {
				    public init() {}
				}
				""",
				seamFixtureType(named: "Worker", isFinalClass: true, declarations: ["@Instantiated public let panel: Panel"]),
				seamFixtureType(named: "Host", isSeam: true, isFinalClass: true, declarations: hostDeclarations),
			],
			app: [
				seamFixtureType(named: "Tag", isFinalClass: true, declarations: [], conformances: ", Sendable"),
				"""
				@Instantiable(fulfillingAdditionalTypes: [Panel.self], conformsElsewhere: true)
				public final class DefaultPanel: Panel, @unchecked Sendable {
				    public init(tag: Tag) {
				        self.tag = tag
				        super.init()
				    }

				    @Instantiated let tag: Tag
				}
				""",
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let host: Host"]),
			],
		)
	}

	/// A final class `name` that fulfills `fulfilledType` and declares `declarations`.
	private static func fulfillingType(named name: String, fulfilling fulfilledType: String, declarations: [String]) -> String {
		seamFixtureType(named: name, isFinalClass: true, declarations: declarations, conformances: ", \(fulfilledType)")
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [\(fulfilledType).self])\n")
	}
}
