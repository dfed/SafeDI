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

/// A seam whose places forward no value and hold no seam's scope takes a builder struct for each hole type, one stored
/// function per member, which its initializer only generated code calls calls where the seam binds each level, so what a
/// level's member returns captures only what the calling module reads from it. Its readable initializer takes a closure
/// that takes nothing. The module that calls the seam writes one function per level, each returning that level's struct;
/// a seam that still takes a closure over its enum, and calls such a seam, hands it a struct whose members build the case
/// its own closure takes.
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
		#expect(output.modules["Feature"]?.generatedFiles["Feature.swift"] == generatedFileHeader + """
		extension Home {
		    @frozen nonisolated public enum SafeDIScope_Api {
		        case api(api_Values)

		        nonisolated public struct api_Values {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let api: (api_Values) -> __safeDI_Built

		            public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                self.api = api
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.api = { _ in __safeDI_builder() }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public init(apiBuilder: @escaping () -> any Api) {
		        self.init(__safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
		        let api: any Api = __safeDI_apiBuilder.api(SafeDIScope_Api.api_Values())
		        self.init(api: api)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_74DEAFE93792C3B0 {}
		}
		""")
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_74DEAFE93792C3B0.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_apiBuilder_Home() -> Home.SafeDIScope_Api.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveApi()
		                    return api
		                })
		            }
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		""")
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
		#expect(output.modules["Feature"]?.generatedFiles["Feature.swift"] == generatedFileHeader + """
		extension Home {
		    @frozen nonisolated public enum SafeDIScope_Api {
		        case detailBuilder(detailBuilder_Values, SafeDIScope_Api.Detail_Scope)

		        nonisolated public struct detailBuilder_Values {
		            public let navigator: Navigator
		            public let logger: Logger
		        }

		        @frozen nonisolated public enum Detail_Scope {
		            case leafBuilder(leafBuilder_Values, SafeDIScope_Api.Leaf_Scope)

		            nonisolated public struct leafBuilder_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let leafBuilder: (leafBuilder_Values) -> SafeDIScope_Api.Leaf_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(leafBuilder: @escaping (leafBuilder_Values) -> SafeDIScope_Api.Leaf_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.leafBuilder = leafBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.leafBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        @frozen nonisolated public enum Leaf_Scope {
		            case api(api_Values)

		            nonisolated public struct api_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let api: (api_Values) -> __safeDI_Built

		                public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                    self.api = api
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.api = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let detailBuilder: (detailBuilder_Values) -> SafeDIScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(detailBuilder: @escaping (detailBuilder_Values) -> SafeDIScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.detailBuilder = detailBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.detailBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(apiBuilder: @escaping () -> any Api) {
		        self.init(__safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
		        let navigator = Navigator()
		        let logger = Logger()
		        let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder.detailBuilder(SafeDIScope_Api.detailBuilder_Values(navigator: navigator, logger: logger))
		        func __safeDI_detailBuilder() -> Detail {
		            let __safeDI_apiBuilder_leafBuilder = __safeDI_apiBuilder_detailBuilder.leafBuilder(SafeDIScope_Api.Detail_Scope.leafBuilder_Values())
		            func __safeDI_leafBuilder() -> Leaf {
		                let api: any Api = __safeDI_apiBuilder_leafBuilder.api(SafeDIScope_Api.Leaf_Scope.api_Values())
		                return Leaf(api: api)
		            }
		            let leafBuilder = Instantiator<Leaf>(__safeDI_leafBuilder)
		            return Detail(leafBuilder: leafBuilder)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        self.init(navigator: navigator, logger: logger, detailBuilder: detailBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_7826251AC9105FEF {}
		}
		""")
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_7826251AC9105FEF.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_apiBuilder_Home() -> Home.SafeDIScope_Api.__safeDI_Builder<any Api> {
		                .init(detailBuilder: { values in __safeDI_apiBuilder_Home_Detail_Scope(logger: values.logger) })
		            }
		            func __safeDI_apiBuilder_Home_Detail_Scope(logger: Logger) -> Home.SafeDIScope_Api.Detail_Scope.__safeDI_Builder<any Api> {
		                .init(leafBuilder: { _ in __safeDI_apiBuilder_Home_Leaf_Scope(logger: logger) })
		            }
		            func __safeDI_apiBuilder_Home_Leaf_Scope(logger: Logger) -> Home.SafeDIScope_Api.Leaf_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveApi(logger: logger)
		                    return api
		                })
		            }
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		""")
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
		#expect(output.modules["Feature"]?.generatedFiles["Feature.swift"] == generatedFileHeader + """
		extension Home {
		    @frozen nonisolated public enum SafeDIScope_Api {
		        @frozen nonisolated public enum Worker_Scope {
		            case detail(detail_Values, SafeDIScope_Api.Detail_Scope)

		            nonisolated public struct detail_Values {
		                public let logger: Logger
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let detail: (detail_Values) -> SafeDIScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(detail: @escaping (detail_Values) -> SafeDIScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.detail = detail
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.detail = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        @frozen nonisolated public enum Detail_Scope {
		            case api(api_Values)

		            nonisolated public struct api_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let api: (api_Values) -> __safeDI_Built

		                public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                    self.api = api
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.api = { _ in __safeDI_builder() }
		                }
		            }
		        }
		    }

		    @frozen nonisolated public enum SafeDISendableScope_Api {
		        case workerBuilder(SafeDIScope_Api.Worker_Scope)

		        nonisolated public struct workerBuilder_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
		            public let workerBuilder: @Sendable (workerBuilder_Values) -> SafeDIScope_Api.Worker_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(workerBuilder: @escaping @Sendable (workerBuilder_Values) -> SafeDIScope_Api.Worker_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.workerBuilder = workerBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		                self.workerBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(apiSendableBuilder: @escaping @Sendable () -> any Api) {
		        self.init(__safeDI_apiSendableBuilder: .init(__safeDI_noScope: apiSendableBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_apiSendableBuilder: SafeDISendableScope_Api.__safeDI_Builder<any Api>) {
		        @Sendable nonisolated func __safeDI_workerBuilder() -> Worker {
		            let __safeDI_apiSendableBuilder_workerBuilder = __safeDI_apiSendableBuilder.workerBuilder(SafeDISendableScope_Api.workerBuilder_Values())
		            let logger = Logger()
		            let __safeDI_apiSendableBuilder_detail = __safeDI_apiSendableBuilder_workerBuilder.detail(SafeDIScope_Api.Worker_Scope.detail_Values(logger: logger))
		            func __safeDI_detail() -> Detail {
		                let api: any Api = __safeDI_apiSendableBuilder_detail.api(SafeDIScope_Api.Detail_Scope.api_Values())
		                return Detail(api: api)
		            }
		            let detail: Detail = __safeDI_detail()
		            return Worker(logger: logger, detail: detail)
		        }
		        let workerBuilder = SendableInstantiator<Worker>(__safeDI_workerBuilder)
		        self.init(workerBuilder: workerBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_1B86BE724F73AD06 {}
		}
		""")
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_1B86BE724F73AD06.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            @Sendable nonisolated func __safeDI_apiSendableBuilder_Home() -> Home.SafeDISendableScope_Api.__safeDI_Builder<any Api> {
		                .init(workerBuilder: { _ in __safeDI_apiBuilder_Home_Worker_Scope() })
		            }
		            @Sendable nonisolated func __safeDI_apiBuilder_Home_Worker_Scope() -> Home.SafeDIScope_Api.Worker_Scope.__safeDI_Builder<any Api> {
		                .init(detail: { values in __safeDI_apiBuilder_Home_Detail_Scope(logger: values.logger) })
		            }
		            @Sendable nonisolated func __safeDI_apiBuilder_Home_Detail_Scope(logger: Logger) -> Home.SafeDIScope_Api.Detail_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveApi(logger: logger)
		                    return api
		                })
		            }
		            return Home(__safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		""")
		try Self.expectCompiles(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_returnsNextSendableStructFromOuterMember_whenTwoSendableFunctionsLeadToPlace() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.fixtures["twoSendable"] ?? [], integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles["Feature.swift"] == generatedFileHeader + """
		extension Home {
		    @frozen nonisolated public enum SafeDIScope_Api {
		        @frozen nonisolated public enum Inner_Scope {
		            case detail(detail_Values, SafeDIScope_Api.Detail_Scope)

		            nonisolated public struct detail_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let detail: (detail_Values) -> SafeDIScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(detail: @escaping (detail_Values) -> SafeDIScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.detail = detail
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.detail = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        @frozen nonisolated public enum Detail_Scope {
		            case api(api_Values)

		            nonisolated public struct api_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let api: (api_Values) -> __safeDI_Built

		                public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                    self.api = api
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.api = { _ in __safeDI_builder() }
		                }
		            }
		        }
		    }

		    @frozen nonisolated public enum SafeDISendableScope_Api {
		        case outerBuilder_Sendable(SafeDISendableScope_Api.Outer_Scope)

		        nonisolated public struct outerBuilder_Sendable_Values: Sendable {}

		        @frozen nonisolated public enum Outer_Scope {
		            case innerBuilder(SafeDIScope_Api.Inner_Scope)

		            nonisolated public struct innerBuilder_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
		                public let innerBuilder: @Sendable (innerBuilder_Values) -> SafeDIScope_Api.Inner_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(innerBuilder: @escaping @Sendable (innerBuilder_Values) -> SafeDIScope_Api.Inner_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.innerBuilder = innerBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		                    self.innerBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
		            public let outerBuilder_Sendable: @Sendable (outerBuilder_Sendable_Values) -> SafeDISendableScope_Api.Outer_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(outerBuilder_Sendable: @escaping @Sendable (outerBuilder_Sendable_Values) -> SafeDISendableScope_Api.Outer_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.outerBuilder_Sendable = outerBuilder_Sendable
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		                self.outerBuilder_Sendable = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(apiSendableBuilder: @escaping @Sendable () -> any Api) {
		        self.init(__safeDI_apiSendableBuilder: .init(__safeDI_noScope: apiSendableBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_apiSendableBuilder: SafeDISendableScope_Api.__safeDI_Builder<any Api>) {
		        @Sendable nonisolated func __safeDI_outerBuilder() -> Outer {
		            let __safeDI_apiSendableBuilder_outerBuilder_Sendable = __safeDI_apiSendableBuilder.outerBuilder_Sendable(SafeDISendableScope_Api.outerBuilder_Sendable_Values())
		            @Sendable nonisolated func __safeDI_innerBuilder() -> Inner {
		                let __safeDI_apiSendableBuilder_innerBuilder = __safeDI_apiSendableBuilder_outerBuilder_Sendable.innerBuilder(SafeDISendableScope_Api.Outer_Scope.innerBuilder_Values())
		                let __safeDI_apiSendableBuilder_detail = __safeDI_apiSendableBuilder_innerBuilder.detail(SafeDIScope_Api.Inner_Scope.detail_Values())
		                func __safeDI_detail() -> Detail {
		                    let api: any Api = __safeDI_apiSendableBuilder_detail.api(SafeDIScope_Api.Detail_Scope.api_Values())
		                    return Detail(api: api)
		                }
		                let detail: Detail = __safeDI_detail()
		                return Inner(detail: detail)
		            }
		            let innerBuilder = SendableInstantiator<Inner>(__safeDI_innerBuilder)
		            return Outer(innerBuilder: innerBuilder)
		        }
		        let outerBuilder = SendableInstantiator<Outer>(__safeDI_outerBuilder)
		        self.init(outerBuilder: outerBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_33C78863D0ED2308 {}
		}
		""")
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_33C78863D0ED2308.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            @Sendable nonisolated func __safeDI_apiSendableBuilder_Home() -> Home.SafeDISendableScope_Api.__safeDI_Builder<any Api> {
		                .init(outerBuilder_Sendable: { _ in __safeDI_apiSendableBuilder_Home_Outer_Scope() })
		            }
		            @Sendable nonisolated func __safeDI_apiSendableBuilder_Home_Outer_Scope() -> Home.SafeDISendableScope_Api.Outer_Scope.__safeDI_Builder<any Api> {
		                .init(innerBuilder: { _ in __safeDI_apiBuilder_Home_Inner_Scope() })
		            }
		            @Sendable nonisolated func __safeDI_apiBuilder_Home_Inner_Scope() -> Home.SafeDIScope_Api.Inner_Scope.__safeDI_Builder<any Api> {
		                .init(detail: { _ in __safeDI_apiBuilder_Home_Detail_Scope() })
		            }
		            @Sendable nonisolated func __safeDI_apiBuilder_Home_Detail_Scope() -> Home.SafeDIScope_Api.Detail_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveApi()
		                    return api
		                })
		            }
		            return Home(__safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		""")
		try Self.expectCompiles(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsCalledSeamStructBuildingKeptSeamsCase_whenKeptSeamPassesUpSwitchedSeamsPlace() async throws {
		// `Innermost`'s place forwards nothing, so it takes a builder struct; `Inner` passes it up and keeps its closure over
		// its enum, whose case holds `Innermost`'s. `Inner` hands `Innermost` a struct whose member for the place calls its
		// own builder with the case rebuilt from the values each member was handed.
		let modules = Self.fixtures["deep"] ?? []
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles["Feature.swift"] == generatedFileHeader + """
		extension Inner {
		    @frozen public enum SafeDIScope_Service {
		        case innermost(Innermost.SafeDIScope_Service)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
		        let navigator = Navigator()
		        func __safeDI_innermost() -> Innermost {
		            _ = Innermost.__safeDI_Innermost_AFB8CC1B9186E9DE.self
		            return Innermost(__safeDI_serviceBuilder: .init(
		                detailBuilder: { __safeDI_detailBuilderValues in
		                    .init(service: { __safeDI_serviceValues in __safeDI_serviceBuilder(.innermost(.detailBuilder(__safeDI_detailBuilderValues, .service(__safeDI_serviceValues)))) })
		                }
		            ))
		        }
		        let innermost: Innermost = __safeDI_innermost()
		        self.init(navigator: navigator, innermost: innermost)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_897570648FDA2A58 {}
		}

		extension Innermost {
		    @frozen nonisolated public enum SafeDIScope_Service {
		        case detailBuilder(detailBuilder_Values, SafeDIScope_Service.Detail_Scope)

		        nonisolated public struct detailBuilder_Values {
		            public let logger: Logger
		        }

		        @frozen nonisolated public enum Detail_Scope {
		            case service(service_Values)

		            nonisolated public struct service_Values {}

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

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let detailBuilder: (detailBuilder_Values) -> SafeDIScope_Service.Detail_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(detailBuilder: @escaping (detailBuilder_Values) -> SafeDIScope_Service.Detail_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.detailBuilder = detailBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.detailBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_serviceBuilder: SafeDIScope_Service.__safeDI_Builder<any Service>) {
		        let logger = Logger()
		        let __safeDI_serviceBuilder_detailBuilder = __safeDI_serviceBuilder.detailBuilder(SafeDIScope_Service.detailBuilder_Values(logger: logger))
		        func __safeDI_detailBuilder() -> Detail {
		            let service: any Service = __safeDI_serviceBuilder_detailBuilder.service(SafeDIScope_Service.Detail_Scope.service_Values())
		            return Detail(service: service)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        self.init(logger: logger, detailBuilder: detailBuilder)
		    }
		}

		extension Innermost {
		    public enum __safeDI_Innermost_AFB8CC1B9186E9DE {}
		}
		""")
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_897570648FDA2A58.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_serviceBuilder_Inner(_ scope: Inner.SafeDIScope_Service) -> any Service {
		                switch scope {
		                case let .innermost(scope): return __safeDI_serviceBuilder_Innermost(scope)
		                }
		            }
		            func __safeDI_serviceBuilder_Innermost(_ scope: Innermost.SafeDIScope_Service) -> any Service {
		                switch scope {
		                case let .detailBuilder(values, scope): return __safeDI_serviceBuilder_Innermost_Detail_Scope(scope, logger: values.logger)
		                }
		            }
		            func __safeDI_serviceBuilder_Innermost_Detail_Scope(_ scope: Innermost.SafeDIScope_Service.Detail_Scope, logger: Logger) -> any Service {
		                switch scope {
		                case .service:
		                    let service: any Service = DefaultService(logger: logger)
		                    return service
		                }
		            }
		            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner)
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(inner: inner)
		    }
		}
		""")
		try Self.expectCompiles(output)
		try await expectValuesEqualInlineBuild(modules: modules, probes: [DifferentialValueProbe("Root()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_convertsThroughOneFunctionPerFirstOpening_whenKeptSeamPassesUpSwitchedSeamWhoseLevelsLoop() async throws {
		// `Hub`'s `T` and `C` each build the other. `Shell` passes `Hub`'s place up and keeps its closure over its enum: one
		// function per level each route first opens, and a member that opens a level again calls that level's function with
		// what wrapped the case where the route first opened it.
		let modules = Self.fixtures["tangle"] ?? []
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Middle"]?.generatedFiles["Middle.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Shell {
		    @frozen public enum SafeDIScope_Api {
		        case hub(Hub.SafeDIScope_Api)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_mark: @autoclosure @escaping () -> Mark?, __safeDI_apiBuilder: @escaping (SafeDIScope_Api) -> any Api) {
		        let mark = LazilyInstantiated<Mark?>(__safeDI_mark)
		        func __safeDI_hub() -> Hub {
		            _ = Hub.__safeDI_Hub_3346DB48A8E1A345.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_apiBuilder_Hub(_ __safeDI_apiBuilder_Hub_wrap: @escaping (Hub.SafeDIScope_Api) -> Hub.SafeDIScope_Api) -> Hub.SafeDIScope_Api.__safeDI_Builder<any Api> {
		                .init(tBuilder: { __safeDI_tBuilderValues in __safeDI_apiBuilder_Hub_T_Scope({ __safeDI_apiBuilder_Hub_wrap(.tBuilder(__safeDI_tBuilderValues, $0)) }) }, cBuilder: { __safeDI_cBuilderValues in __safeDI_apiBuilder_Hub_C_Scope_({ __safeDI_apiBuilder_Hub_wrap(.cBuilder(__safeDI_cBuilderValues, $0)) }) })
		            }
		            func __safeDI_apiBuilder_Hub_T_Scope(_ __safeDI_apiBuilder_Hub_T_Scope_wrap: @escaping (Hub.SafeDIScope_Api.T_Scope) -> Hub.SafeDIScope_Api) -> Hub.SafeDIScope_Api.T_Scope.__safeDI_Builder<any Api> {
		                .init(cBuilder: { __safeDI_cBuilderValues in __safeDI_apiBuilder_Hub_C_Scope({ __safeDI_apiBuilder_Hub_T_Scope_wrap(.cBuilder(__safeDI_cBuilderValues, $0)) }, __safeDI_apiBuilder_Hub_T_Scope_wrap: __safeDI_apiBuilder_Hub_T_Scope_wrap) }, api: { __safeDI_apiValues in __safeDI_apiBuilder(.hub(__safeDI_apiBuilder_Hub_T_Scope_wrap(.api(__safeDI_apiValues)))) })
		            }
		            func __safeDI_apiBuilder_Hub_C_Scope(_ __safeDI_apiBuilder_Hub_C_Scope_wrap: @escaping (Hub.SafeDIScope_Api.C_Scope) -> Hub.SafeDIScope_Api, __safeDI_apiBuilder_Hub_T_Scope_wrap: @escaping (Hub.SafeDIScope_Api.T_Scope) -> Hub.SafeDIScope_Api) -> Hub.SafeDIScope_Api.C_Scope.__safeDI_Builder<any Api> {
		                .init(tBuilder: { _ in __safeDI_apiBuilder_Hub_T_Scope(__safeDI_apiBuilder_Hub_T_Scope_wrap) })
		            }
		            func __safeDI_apiBuilder_Hub_C_Scope_(_ __safeDI_apiBuilder_Hub_C_Scope__wrap: @escaping (Hub.SafeDIScope_Api.C_Scope) -> Hub.SafeDIScope_Api) -> Hub.SafeDIScope_Api.C_Scope.__safeDI_Builder<any Api> {
		                .init(tBuilder: { __safeDI_tBuilderValues in __safeDI_apiBuilder_Hub_T_Scope_({ __safeDI_apiBuilder_Hub_C_Scope__wrap(.tBuilder(__safeDI_tBuilderValues, $0)) }, __safeDI_apiBuilder_Hub_C_Scope__wrap: __safeDI_apiBuilder_Hub_C_Scope__wrap) })
		            }
		            func __safeDI_apiBuilder_Hub_T_Scope_(_ __safeDI_apiBuilder_Hub_T_Scope__wrap: @escaping (Hub.SafeDIScope_Api.T_Scope) -> Hub.SafeDIScope_Api, __safeDI_apiBuilder_Hub_C_Scope__wrap: @escaping (Hub.SafeDIScope_Api.C_Scope) -> Hub.SafeDIScope_Api) -> Hub.SafeDIScope_Api.T_Scope.__safeDI_Builder<any Api> {
		                .init(cBuilder: { _ in __safeDI_apiBuilder_Hub_C_Scope_(__safeDI_apiBuilder_Hub_C_Scope__wrap) }, api: { __safeDI_apiValues in __safeDI_apiBuilder(.hub(__safeDI_apiBuilder_Hub_T_Scope__wrap(.api(__safeDI_apiValues)))) })
		            }
		            return Hub(__safeDI_mark: mark.instance, __safeDI_apiBuilder: __safeDI_apiBuilder_Hub({ $0 }))
		        }
		        let hub: Hub = __safeDI_hub()
		        self.init(hub: hub)
		    }
		}

		extension Shell {
		    public enum __safeDI_Shell_CC5517DC407C149C {}
		}
		""")
		#expect(output.modules["Feature"]?.generatedFiles["Feature.swift"] == generatedFileHeader + """
		extension Hub {
		    @frozen nonisolated public enum SafeDIScope_Api {
		        case tBuilder(tBuilder_Values, SafeDIScope_Api.T_Scope)
		        case cBuilder(cBuilder_Values, SafeDIScope_Api.C_Scope)

		        nonisolated public struct tBuilder_Values {
		            public var mark: Mark? { __safeDI_mark.instance }
		            let __safeDI_mark: LazilyInstantiated<Mark?>

		            init(mark: LazilyInstantiated<Mark?>) {
		                __safeDI_mark = mark
		            }
		        }

		        nonisolated public struct cBuilder_Values {
		            public var mark: Mark? { __safeDI_mark.instance }
		            public let tBuilder: Instantiator<T>
		            let __safeDI_mark: LazilyInstantiated<Mark?>

		            init(mark: LazilyInstantiated<Mark?>, tBuilder: Instantiator<T>) {
		                __safeDI_mark = mark
		                self.tBuilder = tBuilder
		            }
		        }

		        @frozen nonisolated public enum T_Scope {
		            indirect case cBuilder(cBuilder_Values, SafeDIScope_Api.C_Scope)
		            case api(api_Values)

		            nonisolated public struct cBuilder_Values {
		                public let mark: Mark?
		                public let reader: MarkReader
		            }

		            nonisolated public struct api_Values {
		                public let mark: Mark?
		                public let reader: MarkReader
		                public let cBuilder: Instantiator<C>
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let cBuilder: (cBuilder_Values) -> SafeDIScope_Api.C_Scope.__safeDI_Builder<__safeDI_Built>
		                public let api: (api_Values) -> __safeDI_Built

		                public init(cBuilder: @escaping (cBuilder_Values) -> SafeDIScope_Api.C_Scope.__safeDI_Builder<__safeDI_Built>, api: @escaping (api_Values) -> __safeDI_Built) {
		                    self.cBuilder = cBuilder
		                    self.api = api
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.cBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                    self.api = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        @frozen nonisolated public enum C_Scope {
		            indirect case tBuilder(tBuilder_Values, SafeDIScope_Api.T_Scope)

		            nonisolated public struct tBuilder_Values {
		                public let mark: Mark
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let tBuilder: (tBuilder_Values) -> SafeDIScope_Api.T_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(tBuilder: @escaping (tBuilder_Values) -> SafeDIScope_Api.T_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.tBuilder = tBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.tBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let tBuilder: (tBuilder_Values) -> SafeDIScope_Api.T_Scope.__safeDI_Builder<__safeDI_Built>
		            public let cBuilder: (cBuilder_Values) -> SafeDIScope_Api.C_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(tBuilder: @escaping (tBuilder_Values) -> SafeDIScope_Api.T_Scope.__safeDI_Builder<__safeDI_Built>, cBuilder: @escaping (cBuilder_Values) -> SafeDIScope_Api.C_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.tBuilder = tBuilder
		                self.cBuilder = cBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.tBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                self.cBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_mark __safeDI_mark_: @autoclosure @escaping () -> Mark?, __safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
		        let mark = LazilyInstantiated<Mark?>(__safeDI_mark_)
		        let __safeDI_apiBuilder_tBuilder = __safeDI_apiBuilder.tBuilder(SafeDIScope_Api.tBuilder_Values(mark: mark))
		        func __safeDI_tBuilder(mark: Mark?) -> T {
		            let reader = MarkReader(mark: mark)
		            func __safeDI_cBuilder() -> C {
		                let mark = Mark()
		                let tBuilder = Instantiator<T> {
		                    __safeDI_tBuilder(mark: mark)
		                }
		                return C(mark: mark, tBuilder: tBuilder)
		            }
		            let cBuilder = Instantiator<C>(__safeDI_cBuilder)
		            let api: any Api = __safeDI_apiBuilder_tBuilder.api(SafeDIScope_Api.T_Scope.api_Values(mark: mark, reader: reader, cBuilder: cBuilder))
		            return T(reader: reader, cBuilder: cBuilder, api: api)
		        }
		        let tBuilder = Instantiator<T> {
		            __safeDI_tBuilder(mark: mark.instance)
		        }
		        let __safeDI_apiBuilder_cBuilder = __safeDI_apiBuilder.cBuilder(SafeDIScope_Api.cBuilder_Values(mark: mark, tBuilder: tBuilder))
		        func __safeDI_cBuilder() -> C {
		            let mark = Mark()
		            let __safeDI_apiBuilder_tBuilder = __safeDI_apiBuilder_cBuilder.tBuilder(SafeDIScope_Api.C_Scope.tBuilder_Values(mark: mark))
		            func __safeDI_tBuilder() -> T {
		                let reader = MarkReader(mark: mark)
		                let cBuilder = Instantiator<C>(__safeDI_cBuilder)
		                let api: any Api = __safeDI_apiBuilder_tBuilder.api(SafeDIScope_Api.T_Scope.api_Values(mark: mark, reader: reader, cBuilder: cBuilder))
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
		    public enum __safeDI_Hub_3346DB48A8E1A345 {}
		}
		""")
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Middle)
		import Middle
		#endif

		extension Root {
		    public init() {
		        func __safeDI_shell() -> Shell {
		            _ = Shell.__safeDI_Shell_CC5517DC407C149C.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_apiBuilder_Shell(_ scope: Shell.SafeDIScope_Api) -> any Api {
		                switch scope {
		                case let .hub(scope): return __safeDI_apiBuilder_Hub(scope)
		                }
		            }
		            func __safeDI_apiBuilder_Hub(_ scope: Hub.SafeDIScope_Api) -> any Api {
		                switch scope {
		                case let .tBuilder(_, scope): return __safeDI_apiBuilder_Hub_T_Scope(scope)
		                case let .cBuilder(_, scope): return __safeDI_apiBuilder_Hub_C_Scope(scope)
		                }
		            }
		            func __safeDI_apiBuilder_Hub_T_Scope(_ scope: Hub.SafeDIScope_Api.T_Scope) -> any Api {
		                switch scope {
		                case let .cBuilder(_, scope): return __safeDI_apiBuilder_Hub_C_Scope(scope)
		                case let .api(scope):
		                    let mark = scope.mark
		                    let api: any Api = LiveApi(mark: mark)
		                    return api
		                }
		            }
		            func __safeDI_apiBuilder_Hub_C_Scope(_ scope: Hub.SafeDIScope_Api.C_Scope) -> any Api {
		                switch scope {
		                case let .tBuilder(_, scope): return __safeDI_apiBuilder_Hub_T_Scope(scope)
		                }
		            }
		            return Shell(__safeDI_mark: nil, __safeDI_apiBuilder: __safeDI_apiBuilder_Shell)
		        }
		        let shell: Shell = __safeDI_shell()
		        self.init(shell: shell)
		    }
		}
		""")
		try Self.expectCompiles(output)
		try await expectValuesEqualInlineBuild(modules: modules, probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().shell.hub.tBuilder.instantiate().cBuilder.instantiate().tBuilder.instantiate()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsCallersDispatcherTheRebuiltCase_whenKeptSeamsCaseCarriesSwitchedSeamsScope() async throws {
		// `Outer` fills `Inner`'s `service` with a type that holds `Outer`'s own place, so `Outer`'s case carries the scope
		// `Inner` hands the fill, and its dispatchers keep their switch over `Inner`'s enum: `Inner` is handed a struct whose
		// members hand them the case.
		let modules = Self.fixtures["insideFill"] ?? []
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Middle"]?.generatedFiles["Middle.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Outer {
		    @frozen public enum SafeDIScope_Gadget {
		        case inner_serviceBuilder(inner_serviceBuilder_Values, Inner.SafeDIScope_Service, SafeDIScope_Gadget.DefaultService_Scope)

		        public struct inner_serviceBuilder_Values {
		            public let tag: Tag
		        }

		        @frozen public enum DefaultService_Scope {
		            case gadget(gadget_Values)

		            public struct gadget_Values {}
		        }
		    }

		    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_gadgetBuilder: @escaping (SafeDIScope_Gadget) -> any Gadget) {
		        let tag = Tag()
		        let __safeDI_gadgetValues_inner_serviceBuilder = SafeDIScope_Gadget.inner_serviceBuilder_Values(tag: tag)
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_F6242724384070E7.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_serviceBuilder_Inner(_ __safeDI_inner_serviceBuilder: Inner.SafeDIScope_Service) -> any Service {
		                switch __safeDI_inner_serviceBuilder {
		                case let .screenBuilder(_, scope): return __safeDI_serviceBuilder_Inner_Screen_Scope(scope, __safeDI_inner_serviceBuilder: __safeDI_inner_serviceBuilder)
		                case .service:
		                    func __safeDI_service() -> DefaultService {
		                        let gadget: any Gadget = __safeDI_gadgetBuilder(.inner_serviceBuilder(__safeDI_gadgetValues_inner_serviceBuilder, __safeDI_inner_serviceBuilder, .gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values())))
		                        return DefaultService(gadget: gadget)
		                    }
		                    let service: any Service = __safeDI_service()
		                    return service
		                }
		            }
		            func __safeDI_serviceBuilder_Inner_Screen_Scope(_ scope: Inner.SafeDIScope_Service.Screen_Scope, __safeDI_inner_serviceBuilder: Inner.SafeDIScope_Service) -> any Service {
		                switch scope {
		                case .service:
		                    func __safeDI_service() -> DefaultService {
		                        let gadget: any Gadget = __safeDI_gadgetBuilder(.inner_serviceBuilder(__safeDI_gadgetValues_inner_serviceBuilder, __safeDI_inner_serviceBuilder, .gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values())))
		                        return DefaultService(gadget: gadget)
		                    }
		                    let service: any Service = __safeDI_service()
		                    return service
		                }
		            }
		            return Inner(__safeDI_serviceBuilder: .init(
		                screenBuilder: { __safeDI_screenBuilderValues in
		                    .init(service: { __safeDI_serviceValues in __safeDI_serviceBuilder_Inner(.screenBuilder(__safeDI_screenBuilderValues, .service(__safeDI_serviceValues))) })
		                },
		                service: { __safeDI_serviceValues in __safeDI_serviceBuilder_Inner(.service(__safeDI_serviceValues)) }
		            ))
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(tag: tag, inner: inner)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_B543483265135986 {}
		}
		""")
		#expect(output.modules["Feature"]?.generatedFiles["Feature.swift"] == generatedFileHeader + """
		extension Inner {
		    @frozen nonisolated public enum SafeDIScope_Service {
		        case screenBuilder(screenBuilder_Values, SafeDIScope_Service.Screen_Scope)
		        case service(service_Values)

		        nonisolated public struct screenBuilder_Values {}

		        nonisolated public struct service_Values {
		            public let screenBuilder: Instantiator<Screen>
		        }

		        @frozen nonisolated public enum Screen_Scope {
		            case service(service_Values)

		            nonisolated public struct service_Values {
		                public let id: Int
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

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let screenBuilder: (screenBuilder_Values) -> SafeDIScope_Service.Screen_Scope.__safeDI_Builder<__safeDI_Built>
		            public let service: (service_Values) -> __safeDI_Built

		            public init(screenBuilder: @escaping (screenBuilder_Values) -> SafeDIScope_Service.Screen_Scope.__safeDI_Builder<__safeDI_Built>, service: @escaping (service_Values) -> __safeDI_Built) {
		                self.screenBuilder = screenBuilder
		                self.service = service
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.screenBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                self.service = { _ in __safeDI_builder() }
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_serviceBuilder: SafeDIScope_Service.__safeDI_Builder<any Service>) {
		        let __safeDI_serviceBuilder_screenBuilder = __safeDI_serviceBuilder.screenBuilder(SafeDIScope_Service.screenBuilder_Values())
		        func __safeDI_screenBuilder(id: Int) -> Screen {
		            let service: any Service = __safeDI_serviceBuilder_screenBuilder.service(SafeDIScope_Service.Screen_Scope.service_Values(id: id))
		            return Screen(id: id, service: service)
		        }
		        let screenBuilder = Instantiator<Screen> {
		            __safeDI_screenBuilder(id: $0)
		        }
		        let service: any Service = __safeDI_serviceBuilder.service(SafeDIScope_Service.service_Values(screenBuilder: screenBuilder))
		        self.init(screenBuilder: screenBuilder, service: service)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_F6242724384070E7 {}
		}
		""")
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Middle)
		import Middle
		#endif

		extension Root {
		    public init() {
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_B543483265135986.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_gadgetBuilder_Outer(_ scope: Outer.SafeDIScope_Gadget) -> any Gadget {
		                switch scope {
		                case let .inner_serviceBuilder(values, innerScope, scope): return __safeDI_gadgetBuilder_Outer_DefaultService_Scope(scope, id: __safeDI_id_Inner_SafeDIScope_Service(innerScope), tag: values.tag)
		                }
		            }
		            func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(_ scope: Outer.SafeDIScope_Gadget.DefaultService_Scope, id: Int?, tag: Tag) -> any Gadget {
		                switch scope {
		                case .gadget:
		                    let gadget: any Gadget = LiveGadget(tag: tag, id: id)
		                    return gadget
		                }
		            }
		            func __safeDI_id_Inner_SafeDIScope_Service(_ scope: Inner.SafeDIScope_Service) -> Int? {
		                switch scope {
		                case let .screenBuilder(_, scope): return __safeDI_id_Inner_Screen_Scope(scope)
		                case .service: return nil
		                }
		            }
		            func __safeDI_id_Inner_Screen_Scope(_ scope: Inner.SafeDIScope_Service.Screen_Scope) -> Int {
		                switch scope {
		                case let .service(values): return values.id
		                }
		            }
		            return Outer(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Outer)
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(outer: outer)
		    }
		}
		""")
		try Self.expectCompiles(output)
		try await expectValuesEqualInlineBuild(modules: modules, probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().outer.inner.screenBuilder.instantiate(7)")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesNoScopeParameterApart_whenPlaceIsBeneathPropertyNamedBuilder() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.fixtures["builderLabel"] ?? [], integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles["Feature.swift"] == generatedFileHeader + """
		extension Home {
		    @frozen nonisolated public enum SafeDIScope_Api {
		        case builder(builder_Values, SafeDIScope_Api.Part_Scope)

		        nonisolated public struct builder_Values {}

		        @frozen nonisolated public enum Part_Scope {
		            case api(api_Values)

		            nonisolated public struct api_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let api: (api_Values) -> __safeDI_Built

		                public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                    self.api = api
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.api = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let builder: (builder_Values) -> SafeDIScope_Api.Part_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(builder: @escaping (builder_Values) -> SafeDIScope_Api.Part_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.builder = builder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.builder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public init(apiBuilder: @escaping () -> any Api) {
		        self.init(__safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
		        let __safeDI_apiBuilder_builder = __safeDI_apiBuilder.builder(SafeDIScope_Api.builder_Values())
		        func __safeDI_builder() -> Part {
		            let api: any Api = __safeDI_apiBuilder_builder.api(SafeDIScope_Api.Part_Scope.api_Values())
		            return Part(api: api)
		        }
		        let builder = Instantiator<Part>(__safeDI_builder)
		        self.init(builder: builder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_16D534714B302E55 {}
		}
		""")
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_16D534714B302E55.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_apiBuilder_Home() -> Home.SafeDIScope_Api.__safeDI_Builder<any Api> {
		                .init(builder: { _ in __safeDI_apiBuilder_Home_Part_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Part_Scope() -> Home.SafeDIScope_Api.Part_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveApi()
		                    return api
		                })
		            }
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		""")
		try Self.expectCompiles(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsNonisolatedOnEachInitializer_whenMainActorSeamsOwnInitializerIsNonisolated() async throws {
		// `Inner` is `@MainActor` and its initializer `nonisolated`: an initializer declared in an extension of `Inner` takes
		// the main actor, so `Root`'s `init()` and a nonisolated hand-written caller could call neither unless each spells the
		// isolation of the initializer it forwards to.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.fixtures["mainActor"] ?? [], integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles["Feature.swift"] == generatedFileHeader + """
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
		""")
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
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
		""")
		try Self.expectCompiles(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsClosureOverEnumForForwardingBuilderOnly_whenSeamTakesPlainAndForwardingHoleTypes() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.fixtures["twoHoleTypes"] ?? [], integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles["Feature.swift"] == generatedFileHeader + """
		extension Home {
		    @frozen nonisolated public enum SafeDIScope_Api {
		        case api(api_Values)

		        nonisolated public struct api_Values {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let api: (api_Values) -> __safeDI_Built

		            public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                self.api = api
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.api = { _ in __safeDI_builder() }
		            }
		        }
		    }

		    @frozen public enum SafeDIScope_LivePanel_Panel {
		        case panelBuilder(panelBuilder_Values, String)

		        public struct panelBuilder_Values {
		            public let api: any Api
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public init(apiBuilder: @escaping () -> any Api, livePanel_PanelBuilder: @escaping (SafeDIScope_LivePanel_Panel) -> any Panel) {
		        self.init(__safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder), __safeDI_livePanel_PanelBuilder: livePanel_PanelBuilder)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>, __safeDI_livePanel_PanelBuilder: @escaping (SafeDIScope_LivePanel_Panel) -> any Panel) {
		        let api: any Api = __safeDI_apiBuilder.api(SafeDIScope_Api.api_Values())
		        let panelBuilder = ErasedInstantiator<String, any Panel> {
		            __safeDI_livePanel_PanelBuilder(.panelBuilder(SafeDIScope_LivePanel_Panel.panelBuilder_Values(api: api), $0))
		        }
		        self.init(api: api, panelBuilder: panelBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_61E1CB625FF3A2B0 {}
		}
		""")
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_61E1CB625FF3A2B0.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_apiBuilder_Home() -> Home.SafeDIScope_Api.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveApi()
		                    return api
		                })
		            }
		            func __safeDI_livePanel_PanelBuilder_Home(_ scope: Home.SafeDIScope_LivePanel_Panel) -> any Panel {
		                switch scope {
		                case let .panelBuilder(_, __safeDI_forwarded):
		                    func __safeDI_panelBuilder(title: String) -> LivePanel {
		                        LivePanel(title: title)
		                    }
		                    return __safeDI_panelBuilder(title: __safeDI_forwarded)
		                }
		            }
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home(), __safeDI_livePanel_PanelBuilder: __safeDI_livePanel_PanelBuilder_Home)
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		""")
		try Self.expectCompiles(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsLevelFunctionTheLazyWrapper_whenLazyValueIsOnTheRouteToThePlace() async throws {
		let modules = Self.fixtures["lazy"] ?? []
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles["Feature.swift"] == generatedFileHeader + """
		extension Home {
		    @frozen nonisolated public enum SafeDIScope_Api {
		        case detail(detail_Values, SafeDIScope_Api.Detail_Scope)

		        nonisolated public struct detail_Values {
		            public let logger: LazilyInstantiated<Logger>
		        }

		        @frozen nonisolated public enum Detail_Scope {
		            case api(api_Values)

		            nonisolated public struct api_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let api: (api_Values) -> __safeDI_Built

		                public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                    self.api = api
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.api = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let detail: (detail_Values) -> SafeDIScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(detail: @escaping (detail_Values) -> SafeDIScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.detail = detail
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.detail = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public init(apiBuilder: @escaping () -> any Api) {
		        self.init(__safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
		        func __safeDI_logger() -> Logger {
		            Logger()
		        }
		        let logger = LazilyInstantiated<Logger>(__safeDI_logger)
		        let __safeDI_apiBuilder_detail = __safeDI_apiBuilder.detail(SafeDIScope_Api.detail_Values(logger: logger))
		        func __safeDI_detail() -> Detail {
		            let api: any Api = __safeDI_apiBuilder_detail.api(SafeDIScope_Api.Detail_Scope.api_Values())
		            return Detail(api: api)
		        }
		        let detail = LazilyInstantiated<Detail>(__safeDI_detail)
		        self.init(logger: logger, detail: detail)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_812FFB5BD10F50D1 {}
		}
		""")
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_812FFB5BD10F50D1.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_apiBuilder_Home() -> Home.SafeDIScope_Api.__safeDI_Builder<any Api> {
		                .init(detail: { values in __safeDI_apiBuilder_Home_Detail_Scope(logger: values.logger) })
		            }
		            func __safeDI_apiBuilder_Home_Detail_Scope(logger: LazilyInstantiated<Logger>) -> Home.SafeDIScope_Api.Detail_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveApi(logger: logger.instance)
		                    return api
		                })
		            }
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		""")
		try Self.expectCompiles(output)
		try await expectValuesEqualInlineBuild(modules: modules, probes: [DifferentialValueProbe("Root().home.detail.instance")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsEachRoutesOwnValues_whenTwoRoutesReachOneLevel() async throws {
		let modules = Self.fixtures["twoRoutes"] ?? []
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles["Feature.swift"] == generatedFileHeader + """
		extension Home {
		    @frozen nonisolated public enum SafeDIScope_Api {
		        case aBuilder(aBuilder_Values, SafeDIScope_Api.A_Scope)
		        case bBuilder(bBuilder_Values, SafeDIScope_Api.B_Scope)

		        nonisolated public struct aBuilder_Values {}

		        nonisolated public struct bBuilder_Values {
		            public let aBuilder: Instantiator<A>
		        }

		        @frozen nonisolated public enum A_Scope {
		            case detailBuilder(detailBuilder_Values, SafeDIScope_Api.Detail_Scope)

		            nonisolated public struct detailBuilder_Values {
		                public let logger: Logger
		                public let tag: Tag
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let detailBuilder: (detailBuilder_Values) -> SafeDIScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(detailBuilder: @escaping (detailBuilder_Values) -> SafeDIScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.detailBuilder = detailBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.detailBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        @frozen nonisolated public enum B_Scope {
		            case detailBuilder(detailBuilder_Values, SafeDIScope_Api.Detail_Scope)

		            nonisolated public struct detailBuilder_Values {
		                public let logger: Logger
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let detailBuilder: (detailBuilder_Values) -> SafeDIScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(detailBuilder: @escaping (detailBuilder_Values) -> SafeDIScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.detailBuilder = detailBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.detailBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        @frozen nonisolated public enum Detail_Scope {
		            case api(api_Values)

		            nonisolated public struct api_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let api: (api_Values) -> __safeDI_Built

		                public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                    self.api = api
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.api = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let aBuilder: (aBuilder_Values) -> SafeDIScope_Api.A_Scope.__safeDI_Builder<__safeDI_Built>
		            public let bBuilder: (bBuilder_Values) -> SafeDIScope_Api.B_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(aBuilder: @escaping (aBuilder_Values) -> SafeDIScope_Api.A_Scope.__safeDI_Builder<__safeDI_Built>, bBuilder: @escaping (bBuilder_Values) -> SafeDIScope_Api.B_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.aBuilder = aBuilder
		                self.bBuilder = bBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.aBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                self.bBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public init(apiBuilder: @escaping () -> any Api) {
		        self.init(__safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
		        let __safeDI_apiBuilder_aBuilder = __safeDI_apiBuilder.aBuilder(SafeDIScope_Api.aBuilder_Values())
		        func __safeDI_aBuilder() -> A {
		            let logger = Logger()
		            let tag = Tag()
		            let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder_aBuilder.detailBuilder(SafeDIScope_Api.A_Scope.detailBuilder_Values(logger: logger, tag: tag))
		            func __safeDI_detailBuilder() -> Detail {
		                let api: any Api = __safeDI_apiBuilder_detailBuilder.api(SafeDIScope_Api.Detail_Scope.api_Values())
		                return Detail(api: api)
		            }
		            let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		            return A(logger: logger, tag: tag, detailBuilder: detailBuilder)
		        }
		        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		        let __safeDI_apiBuilder_bBuilder = __safeDI_apiBuilder.bBuilder(SafeDIScope_Api.bBuilder_Values(aBuilder: aBuilder))
		        func __safeDI_bBuilder() -> B {
		            let logger = Logger()
		            let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder_bBuilder.detailBuilder(SafeDIScope_Api.B_Scope.detailBuilder_Values(logger: logger))
		            func __safeDI_detailBuilder() -> Detail {
		                let api: any Api = __safeDI_apiBuilder_detailBuilder.api(SafeDIScope_Api.Detail_Scope.api_Values())
		                return Detail(api: api)
		            }
		            let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		            return B(logger: logger, detailBuilder: detailBuilder)
		        }
		        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		        self.init(aBuilder: aBuilder, bBuilder: bBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_574BB99012C8137C {}
		}
		""")
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_574BB99012C8137C.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_apiBuilder_Home() -> Home.SafeDIScope_Api.__safeDI_Builder<any Api> {
		                .init(aBuilder: { _ in __safeDI_apiBuilder_Home_A_Scope() }, bBuilder: { _ in __safeDI_apiBuilder_Home_B_Scope(tag: nil) })
		            }
		            func __safeDI_apiBuilder_Home_A_Scope() -> Home.SafeDIScope_Api.A_Scope.__safeDI_Builder<any Api> {
		                .init(detailBuilder: { values in __safeDI_apiBuilder_Home_Detail_Scope(logger: values.logger, tag: values.tag) })
		            }
		            func __safeDI_apiBuilder_Home_Detail_Scope(logger: Logger, tag: Tag?) -> Home.SafeDIScope_Api.Detail_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveApi(logger: logger, tag: tag)
		                    return api
		                })
		            }
		            func __safeDI_apiBuilder_Home_B_Scope(tag: Tag?) -> Home.SafeDIScope_Api.B_Scope.__safeDI_Builder<any Api> {
		                .init(detailBuilder: { values in __safeDI_apiBuilder_Home_Detail_Scope(logger: values.logger, tag: tag) })
		            }
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		""")
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
		#expect(output.modules["Feature"]?.generatedFiles["Feature.swift"] == generatedFileHeader + """
		extension Home {
		    @frozen nonisolated public enum SafeDIScope_Api {
		        case screenBuilder(screenBuilder_Values, SafeDIScope_Api.Screen_Scope)

		        nonisolated public struct screenBuilder_Values {}

		        @frozen nonisolated public enum Screen_Scope {
		            case api(api_Values)
		            indirect case next(next_Values, SafeDIScope_Api.Screen_Scope)

		            nonisolated public struct api_Values {
		                public let id: Int
		            }

		            nonisolated public struct next_Values {
		                public let id: Int
		                public let api: any Api
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let api: (api_Values) -> __safeDI_Built
		                public let next: (next_Values) -> SafeDIScope_Api.Screen_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(api: @escaping (api_Values) -> __safeDI_Built, next: @escaping (next_Values) -> SafeDIScope_Api.Screen_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.api = api
		                    self.next = next
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.api = { _ in __safeDI_builder() }
		                    self.next = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let screenBuilder: (screenBuilder_Values) -> SafeDIScope_Api.Screen_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(screenBuilder: @escaping (screenBuilder_Values) -> SafeDIScope_Api.Screen_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.screenBuilder = screenBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.screenBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(apiBuilder: @escaping () -> any Api) {
		        self.init(__safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
		        let __safeDI_apiBuilder_screenBuilder = __safeDI_apiBuilder.screenBuilder(SafeDIScope_Api.screenBuilder_Values())
		        func __safeDI_screenBuilder(id: Int) -> Screen {
		            let api: any Api = __safeDI_apiBuilder_screenBuilder.api(SafeDIScope_Api.Screen_Scope.api_Values(id: id))
		            let __safeDI_apiBuilder_next = __safeDI_apiBuilder_screenBuilder.next(SafeDIScope_Api.Screen_Scope.next_Values(id: id, api: api))
		            func __safeDI_next(id: Int) -> Screen {
		                let api: any Api = __safeDI_apiBuilder_next.api(SafeDIScope_Api.Screen_Scope.api_Values(id: id))
		                let next = Instantiator<Screen> {
		                    __safeDI_next(id: $0)
		                }
		                return Screen(id: id, api: api, next: next)
		            }
		            let next = Instantiator<Screen> {
		                __safeDI_next(id: $0)
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
		    public enum __safeDI_Home_0F7FF883EEE00B05 {}
		}
		""")
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_0F7FF883EEE00B05.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_apiBuilder_Home() -> Home.SafeDIScope_Api.__safeDI_Builder<any Api> {
		                .init(screenBuilder: { _ in __safeDI_apiBuilder_Home_Screen_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Screen_Scope() -> Home.SafeDIScope_Api.Screen_Scope.__safeDI_Builder<any Api> {
		                .init(
		                    api: { scope in
		                        let id = scope.id
		                        let api: any Api = Live(id: id)
		                        return api
		                    },
		                    next: { _ in __safeDI_apiBuilder_Home_Screen_Scope() }
		                )
		            }
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		""")
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
			\(fixtures["App"]!["Live.swift"]):10:5: error: `Live` receives `cache: Cache`, which `Screen` declares between where `Screen` instantiates `stepBuilder: Instantiator<Step>` and where `Screen` instantiates it again. Inline, the `Step` built again receives `Screen`’s `cache`, but the scope SafeDI hands the builder for `Step`’s `api: any Api` (case `Step_Scope.api` of `apiBuilder`) holds the same values at every level of that cycle. Give `cache` on `Screen` another label, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
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
		try await expectValuesEqualInlineBuild(modules: Self.fixtures["markOnly"] ?? [], probes: [DifferentialValueProbe("secondMonitorsMark()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsKeptSeamTheDispatchersOverTheEnum_whenFillOfSwitchedSeamCallsKeptSeamThatPassesItsPlaceUp() async throws {
		// `HoleImpl` fills `HoleSeam`'s place beneath `HoleOwner`, reading `holeAnalytics`, which `HoleOwner`'s level carries,
		// and builds `HoleRelay`, which keeps its closure over its enum, whose case carries `HoleSeam`'s, since `HoleRelay`
		// builds `HoleSeam` and passes its place up. `HoleRelay`'s dispatcher reuses `Root`'s over `HoleSeam`'s enum, which
		// hand the fill `holeAnalytics` from the case that carries it, so `Root` keeps them over the enum and hands `HoleSeam`
		// their conversion to its builder struct.
		let modules = Self.fixtures["reentryThroughKeptSeam"] ?? []
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        func __safeDI_holeSeam() -> HoleSeam {
		            _ = HoleSeam.__safeDI_HoleSeam_4CB00D206C704C2F.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_holeServiceBuilder_HoleSeam(_ scope: HoleSeam.SafeDIScope_HoleService) -> any HoleService {
		                switch scope {
		                case let .holeOwnerBuilder(values, scope): return __safeDI_holeServiceBuilder_HoleSeam_HoleOwner_Scope(scope, holeAnalytics: values.holeAnalytics)
		                }
		            }
		            func __safeDI_holeServiceBuilder_HoleSeam_HoleOwner_Scope(_ scope: HoleSeam.SafeDIScope_HoleService.HoleOwner_Scope, holeAnalytics: HoleAnalytics) -> any HoleService {
		                switch scope {
		                case .holeService:
		                    func __safeDI_holeService() -> HoleImpl {
		                        func __safeDI_holeRelayBuilder() -> HoleRelay {
		                            _ = HoleRelay.__safeDI_HoleRelay_06BFEF9C3AC0C4CD.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                            func __safeDI_holeServiceBuilder_HoleRelay(_ scope: HoleRelay.SafeDIScope_HoleService) -> any HoleService {
		                                switch scope {
		                                case let .holeSeamBuilder(scope): return __safeDI_holeServiceBuilder_HoleSeam(scope)
		                                }
		                            }
		                            return HoleRelay(__safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder_HoleRelay)
		                        }
		                        let holeRelayBuilder = Instantiator<HoleRelay>(__safeDI_holeRelayBuilder)
		                        return HoleImpl(holeAnalytics: holeAnalytics, holeRelayBuilder: holeRelayBuilder)
		                    }
		                    let holeService: any HoleService = __safeDI_holeService()
		                    return holeService
		                }
		            }
		            return HoleSeam(__safeDI_holeServiceBuilder: .init(
		                holeOwnerBuilder: { __safeDI_holeOwnerBuilderValues in
		                    .init(holeService: { __safeDI_holeServiceValues in __safeDI_holeServiceBuilder_HoleSeam(.holeOwnerBuilder(__safeDI_holeOwnerBuilderValues, .holeService(__safeDI_holeServiceValues))) })
		                }
		            ))
		        }
		        let holeSeam: HoleSeam = __safeDI_holeSeam()
		        self.init(holeSeam: holeSeam)
		    }
		}
		""")
		try Self.expectCompiles(output)
		try await expectValuesEqualInlineBuild(modules: modules, probes: [DifferentialValueProbe("Root().holeSeam.holeOwnerBuilder.instantiate().holeService")])
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
				fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received public let tag: Tag", "@Received(onlyIfAvailable: true) public let id: Int?"]),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let outer: Outer"]),
			].map { "import Feature\nimport Middle\n\n" + $0 }, dependencies: ["Feature", "Middle"]),
		],
		"tangle": [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"public protocol Api {}",
				seamFixtureType(named: "Mark", isFinalClass: true, declarations: []),
				seamFixtureType(named: "MarkReader", declarations: ["@Received(onlyIfAvailable: true) public let mark: Mark?"]),
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
			].map { "import Feature\nimport Middle\n\n" + $0 }, dependencies: ["Feature", "Middle"]),
		],
		"builderLabel": featureAndApp(
			feature: ["public protocol Api {}", seamFixtureType(named: "Part", declarations: ["@Instantiated public let api: any Api"]), seamFixtureType(named: "Home", isSeam: true, declarations: ["@Instantiated public let builder: Instantiator<Part>"])],
			app: [fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: []), seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let home: Home"])],
		),
		"mainActor": [
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
		"reentryThroughKeptSeam": featureAndApp(
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
				    return mark.map { $0 === step.mark ? "the first step's mark" : "another mark" } ?? "nil"
				}
				""",
			],
		),
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

	/// Expects every module of `output` to have compiled, where compile verification is enabled.
	private static func expectCompiles(_ output: MultiModuleTestOutput, sourceLocation: SourceLocation = #_sourceLocation) throws {
		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation, sourceLocation: sourceLocation)
		for module in compilation.modules {
			#expect(module.result.exitCode == 0, "\(module.moduleName): \(module.result.stderr)", sourceLocation: sourceLocation)
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
