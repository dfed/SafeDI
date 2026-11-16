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

/// A seam that calls another seam whose holes it cannot fill takes builder structs for them: a whole builder handed on, a
/// fill that carries the called seam's struct, and a seam whose tree builds it again.
struct SafeDIToolSeamPassUpTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: A place passed up through a seam that binds the value its fill reads

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_compiles_whenRootDeclaresNoValueThePassedUpPlacesFillReads() async throws {
		try await expectOutput(
			of: Self.passedUpLoggerModules(rootDeclarations: ["@Instantiated public let outer: Outer"]),
			[
				"App": ["App.swift": """
				#if canImport(Feature)
				import Feature
				#endif

				extension Root {
				    public convenience init() {
				        func __safeDI_outer() -> Outer {
				            _ = Outer.__safeDI_Outer_4E4B07FC4178976F.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            func __safeDI_apiBuilder_Outer() -> Outer.SafeDIScope_Api.__safeDI_Builder<any Api> {
				                .init(inner: { _ in __safeDI_apiBuilder_Inner() })
				            }
				            func __safeDI_apiBuilder_Inner() -> Inner.SafeDIScope_Api.__safeDI_Builder<any Api> {
				                .init(detail: { values in __safeDI_apiBuilder_Inner_Detail_Scope(logger: values.logger) })
				            }
				            func __safeDI_apiBuilder_Inner_Detail_Scope(logger: Logger) -> Inner.SafeDIScope_Api.Detail_Scope.__safeDI_Builder<any Api> {
				                .init(api: { _ in
				                    let api: any Api = LiveApi(logger: logger)
				                    return api
				                })
				            }
				            return Outer(__safeDI_apiBuilder: __safeDI_apiBuilder_Outer())
				        }
				        let outer: Outer = __safeDI_outer()
				        self.init(outer: outer)
				    }
				}
				"""],
				"Feature": ["Feature.swift": """
				extension Inner {
				    nonisolated public enum SafeDIScope_Api {
				        nonisolated public struct detail_Values {
				            public var logger: Logger { __safeDI_logger.instance }
				            let __safeDI_logger: LazilyInstantiated<Logger>

				            init(logger: LazilyInstantiated<Logger>) {
				                __safeDI_logger = logger
				            }
				        }

				        nonisolated public enum Detail_Scope {
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

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_logger: @autoclosure @escaping () -> Logger, __safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
				        let logger = LazilyInstantiated<Logger>(__safeDI_logger)
				        let __safeDI_apiBuilder_detail = __safeDI_apiBuilder.detail(SafeDIScope_Api.detail_Values(logger: logger))
				        func __safeDI_detail() -> Detail {
				            let api: any Api = __safeDI_apiBuilder_detail.api(SafeDIScope_Api.Detail_Scope.api_Values())
				            return Detail(logger: logger.instance, api: api)
				        }
				        let detail: Detail = __safeDI_detail()
				        self.init(detail: detail)
				    }
				}

				extension Inner {
				    public enum __safeDI_Inner_606A33C33A7FE02A {}
				}

				extension Outer {
				    nonisolated public enum SafeDIScope_Api {
				        nonisolated public struct inner_Values: Sendable {}

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let inner: (inner_Values) -> Inner.SafeDIScope_Api.__safeDI_Builder<__safeDI_Built>

				            public init(inner: @escaping (inner_Values) -> Inner.SafeDIScope_Api.__safeDI_Builder<__safeDI_Built>) {
				                self.inner = inner
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.inner = { _ in .init(__safeDI_noScope: __safeDI_builder) }
				            }
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
				        let logger = Logger()
				        func __safeDI_inner() -> Inner {
				            _ = Inner.__safeDI_Inner_606A33C33A7FE02A.self
				            return Inner(__safeDI_logger: logger, __safeDI_apiBuilder: __safeDI_apiBuilder.inner(SafeDIScope_Api.inner_Values()))
				        }
				        let inner: Inner = __safeDI_inner()
				        self.init(logger: logger, inner: inner)
				    }
				}

				extension Outer {
				    public enum __safeDI_Outer_4E4B07FC4178976F {}
				}
				"""],
			],
			inline: Self.passedUpLoggerModules(rootDeclarations: ["@Instantiated public let outer: Outer"], liveApiInFeature: true),
			probes: [
				DifferentialValueProbe("Root().outer.inner.detail.api"),
				DifferentialValueProbe("{ let root = Root(); return (root.outer.inner.detail.api as! LiveApi).logger === root.outer.logger }()"),
			],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsWithPassingUpSeamsValue_whenRootDeclaresValueOfTheSameLabel() async throws {
		let rootDeclarations = ["@Instantiated public let logger: Logger", "@Instantiated public let outer: Outer"]
		try await expectOutput(
			of: Self.passedUpLoggerModules(rootDeclarations: rootDeclarations),
			[
				"App": ["App.swift": """
				#if canImport(Feature)
				import Feature
				#endif

				extension Root {
				    public convenience init() {
				        let logger = Logger()
				        func __safeDI_outer() -> Outer {
				            _ = Outer.__safeDI_Outer_4E4B07FC4178976F.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            func __safeDI_apiBuilder_Outer() -> Outer.SafeDIScope_Api.__safeDI_Builder<any Api> {
				                .init(inner: { _ in __safeDI_apiBuilder_Inner() })
				            }
				            func __safeDI_apiBuilder_Inner() -> Inner.SafeDIScope_Api.__safeDI_Builder<any Api> {
				                .init(detail: { values in __safeDI_apiBuilder_Inner_Detail_Scope(logger: values.logger) })
				            }
				            func __safeDI_apiBuilder_Inner_Detail_Scope(logger: Logger) -> Inner.SafeDIScope_Api.Detail_Scope.__safeDI_Builder<any Api> {
				                .init(api: { _ in
				                    let api: any Api = LiveApi(logger: logger)
				                    return api
				                })
				            }
				            return Outer(__safeDI_apiBuilder: __safeDI_apiBuilder_Outer())
				        }
				        let outer: Outer = __safeDI_outer()
				        self.init(logger: logger, outer: outer)
				    }
				}
				"""],
				"Feature": ["Feature.swift": """
				extension Inner {
				    nonisolated public enum SafeDIScope_Api {
				        nonisolated public struct detail_Values {
				            public var logger: Logger { __safeDI_logger.instance }
				            let __safeDI_logger: LazilyInstantiated<Logger>

				            init(logger: LazilyInstantiated<Logger>) {
				                __safeDI_logger = logger
				            }
				        }

				        nonisolated public enum Detail_Scope {
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

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_logger: @autoclosure @escaping () -> Logger, __safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
				        let logger = LazilyInstantiated<Logger>(__safeDI_logger)
				        let __safeDI_apiBuilder_detail = __safeDI_apiBuilder.detail(SafeDIScope_Api.detail_Values(logger: logger))
				        func __safeDI_detail() -> Detail {
				            let api: any Api = __safeDI_apiBuilder_detail.api(SafeDIScope_Api.Detail_Scope.api_Values())
				            return Detail(logger: logger.instance, api: api)
				        }
				        let detail: Detail = __safeDI_detail()
				        self.init(detail: detail)
				    }
				}

				extension Inner {
				    public enum __safeDI_Inner_606A33C33A7FE02A {}
				}

				extension Outer {
				    nonisolated public enum SafeDIScope_Api {
				        nonisolated public struct inner_Values: Sendable {}

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let inner: (inner_Values) -> Inner.SafeDIScope_Api.__safeDI_Builder<__safeDI_Built>

				            public init(inner: @escaping (inner_Values) -> Inner.SafeDIScope_Api.__safeDI_Builder<__safeDI_Built>) {
				                self.inner = inner
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.inner = { _ in .init(__safeDI_noScope: __safeDI_builder) }
				            }
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
				        let logger = Logger()
				        func __safeDI_inner() -> Inner {
				            _ = Inner.__safeDI_Inner_606A33C33A7FE02A.self
				            return Inner(__safeDI_logger: logger, __safeDI_apiBuilder: __safeDI_apiBuilder.inner(SafeDIScope_Api.inner_Values()))
				        }
				        let inner: Inner = __safeDI_inner()
				        self.init(logger: logger, inner: inner)
				    }
				}

				extension Outer {
				    public enum __safeDI_Outer_4E4B07FC4178976F {}
				}
				"""],
			],
			inline: Self.passedUpLoggerModules(rootDeclarations: rootDeclarations, liveApiInFeature: true),
			probes: [
				DifferentialValueProbe("{ let root = Root(); return (root.outer.inner.detail.api as! LiveApi).logger === root.outer.logger }()"),
			],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsWithNearestPassingUpSeamsValues_whenTwoSeamsPassThePlaceUp() async throws {
		try await expectOutput(
			of: Self.twoLevelPassUpModules(),
			[
				"App": ["App.swift": """
				#if canImport(Feature)
				import Feature
				#endif

				extension Root {
				    public convenience init() {
				        let logger = Logger()
				        let tag = Tag()
				        func __safeDI_outer() -> Outer {
				            _ = Outer.__safeDI_Outer_583D2F623BD662A1.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            func __safeDI_apiBuilder_Outer() -> Outer.SafeDIScope_Api.__safeDI_Builder<any Api> {
				                .init(middle: { _ in __safeDI_apiBuilder_Middle() })
				            }
				            func __safeDI_apiBuilder_Middle() -> Middle.SafeDIScope_Api.__safeDI_Builder<any Api> {
				                .init(inner: { _ in __safeDI_apiBuilder_Inner() })
				            }
				            func __safeDI_apiBuilder_Inner() -> Inner.SafeDIScope_Api.__safeDI_Builder<any Api> {
				                .init(detailBuilder: { values in __safeDI_apiBuilder_Inner_Detail_Scope(logger: values.logger, tag: values.tag) })
				            }
				            func __safeDI_apiBuilder_Inner_Detail_Scope(logger: Logger, tag: Tag?) -> Inner.SafeDIScope_Api.Detail_Scope.__safeDI_Builder<any Api> {
				                .init(api: { _ in
				                    let api: any Api = LiveApi(logger: logger, tag: tag)
				                    return api
				                })
				            }
				            return Outer(__safeDI_apiBuilder: __safeDI_apiBuilder_Outer())
				        }
				        let outer: Outer = __safeDI_outer()
				        self.init(logger: logger, tag: tag, outer: outer)
				    }
				}
				"""],
				"Feature": ["Feature.swift": """
				extension Inner {
				    nonisolated public enum SafeDIScope_Api {
				        nonisolated public struct detailBuilder_Values {
				            public var logger: Logger { __safeDI_logger.instance }
				            public var tag: Tag? { __safeDI_tag.instance }
				            let __safeDI_logger: LazilyInstantiated<Logger>
				            let __safeDI_tag: LazilyInstantiated<Tag?>

				            init(logger: LazilyInstantiated<Logger>, tag: LazilyInstantiated<Tag?>) {
				                __safeDI_logger = logger
				                __safeDI_tag = tag
				            }
				        }

				        nonisolated public enum Detail_Scope {
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

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_logger: @autoclosure @escaping () -> Logger, __safeDI_tag: @autoclosure @escaping () -> Tag?, __safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
				        let logger = LazilyInstantiated<Logger>(__safeDI_logger)
				        let tag = LazilyInstantiated<Tag?>(__safeDI_tag)
				        let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder.detailBuilder(SafeDIScope_Api.detailBuilder_Values(logger: logger, tag: tag))
				        func __safeDI_detailBuilder() -> Detail {
				            let api: any Api = __safeDI_apiBuilder_detailBuilder.api(SafeDIScope_Api.Detail_Scope.api_Values())
				            return Detail(logger: logger.instance, tag: tag.instance, api: api)
				        }
				        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
				        self.init(detailBuilder: detailBuilder)
				    }
				}

				extension Inner {
				    public enum __safeDI_Inner_1D55F50158483DDE {}
				}

				extension Middle {
				    nonisolated public enum SafeDIScope_Api {
				        nonisolated public struct inner_Values: Sendable {}

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let inner: (inner_Values) -> Inner.SafeDIScope_Api.__safeDI_Builder<__safeDI_Built>

				            public init(inner: @escaping (inner_Values) -> Inner.SafeDIScope_Api.__safeDI_Builder<__safeDI_Built>) {
				                self.inner = inner
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.inner = { _ in .init(__safeDI_noScope: __safeDI_builder) }
				            }
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_logger: @autoclosure @escaping () -> Logger, __safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
				        let logger = LazilyInstantiated<Logger>(__safeDI_logger)
				        let tag = Tag()
				        func __safeDI_inner() -> Inner {
				            _ = Inner.__safeDI_Inner_1D55F50158483DDE.self
				            return Inner(__safeDI_logger: logger.instance, __safeDI_tag: tag, __safeDI_apiBuilder: __safeDI_apiBuilder.inner(SafeDIScope_Api.inner_Values()))
				        }
				        let inner: Inner = __safeDI_inner()
				        self.init(tag: tag, inner: inner)
				    }
				}

				extension Middle {
				    public enum __safeDI_Middle_47A35834A9D01D76 {}
				}

				extension Outer {
				    nonisolated public enum SafeDIScope_Api {
				        nonisolated public struct middle_Values: Sendable {}

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let middle: (middle_Values) -> Middle.SafeDIScope_Api.__safeDI_Builder<__safeDI_Built>

				            public init(middle: @escaping (middle_Values) -> Middle.SafeDIScope_Api.__safeDI_Builder<__safeDI_Built>) {
				                self.middle = middle
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.middle = { _ in .init(__safeDI_noScope: __safeDI_builder) }
				            }
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
				        let logger = Logger()
				        func __safeDI_middle() -> Middle {
				            _ = Middle.__safeDI_Middle_47A35834A9D01D76.self
				            return Middle(__safeDI_logger: logger, __safeDI_apiBuilder: __safeDI_apiBuilder.middle(SafeDIScope_Api.middle_Values()))
				        }
				        let middle: Middle = __safeDI_middle()
				        self.init(logger: logger, middle: middle)
				    }
				}

				extension Outer {
				    public enum __safeDI_Outer_583D2F623BD662A1 {}
				}
				"""],
			],
			inline: Self.twoLevelPassUpModules(liveApiInFeature: true),
			probes: [
				DifferentialValueProbe("{ let root = Root(); let detail = root.outer.middle.inner.detailBuilder.instantiate(); let api = detail.api as! LiveApi; return [api.logger === root.outer.logger, api.tag === root.outer.middle.tag, detail.tag === root.outer.middle.tag] }()"),
			],
		)
	}

	// MARK: A whole builder handed on

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsInnerSeamsBuilderOn_whenSeamPassesEveryPlaceUp() async throws {
		try await expectOutput(
			of: Self.handedOnModules(outerDeclaration: "@Instantiated public let inner: Inner"),
			[
				"App": ["App.swift": """
				#if canImport(Feature)
				import Feature
				#endif
				#if canImport(Middle)
				import Middle
				#endif

				extension Root {
				    public init() {
				        func __safeDI_outer() -> Outer {
				            _ = Outer.__safeDI_Outer_7D8830DF8628BD6B.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            func __safeDI_apiBuilder_Outer() -> Outer.SafeDIScope_Api.__safeDI_Builder<any Api> {
				                .init(inner: { _ in __safeDI_apiBuilder_Inner() })
				            }
				            func __safeDI_apiBuilder_Inner() -> Inner.SafeDIScope_Api.__safeDI_Builder<any Api> {
				                .init(api: { _ in
				                    let api: any Api = LiveApi()
				                    return api
				                })
				            }
				            return Outer(__safeDI_apiBuilder: __safeDI_apiBuilder_Outer())
				        }
				        let outer: Outer = __safeDI_outer()
				        self.init(outer: outer)
				    }
				}
				"""],
				"Feature": ["Feature.swift": """
				extension Inner {
				    nonisolated public enum SafeDIScope_Api {
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

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
				        let api: any Api = __safeDI_apiBuilder.api(SafeDIScope_Api.api_Values())
				        self.init(api: api)
				    }
				}

				extension Inner {
				    public enum __safeDI_Inner_9EB1889B854C9039 {}
				}
				"""],
				"Middle": ["Middle.swift": """
				#if canImport(Feature)
				import Feature
				#endif

				extension Outer {
				    nonisolated public enum SafeDIScope_Api {
				        nonisolated public struct inner_Values: Sendable {}

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let inner: (inner_Values) -> Inner.SafeDIScope_Api.__safeDI_Builder<__safeDI_Built>

				            public init(inner: @escaping (inner_Values) -> Inner.SafeDIScope_Api.__safeDI_Builder<__safeDI_Built>) {
				                self.inner = inner
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.inner = { _ in .init(__safeDI_noScope: __safeDI_builder) }
				            }
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
				        func __safeDI_inner() -> Inner {
				            _ = Inner.__safeDI_Inner_9EB1889B854C9039.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return Inner(__safeDI_apiBuilder: __safeDI_apiBuilder.inner(SafeDIScope_Api.inner_Values()))
				        }
				        let inner: Inner = __safeDI_inner()
				        self.init(inner: inner)
				    }
				}

				extension Outer {
				    public enum __safeDI_Outer_7D8830DF8628BD6B {}
				}
				"""],
			],
			inline: Self.handedOnModules(outerDeclaration: "@Instantiated public let inner: Inner", liveApiInFeature: true),
			probes: [DifferentialValueProbe("Root().outer.inner.api")],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsInnerSeamsSendableBuilderOn_whenSeamHoldsInnerSeamInSendableInstantiator() async throws {
		try await expectOutput(
			of: Self.handedOnModules(outerDeclaration: "@Instantiated public let innerBuilder: SendableInstantiator<Inner>", isSendable: true),
			[
				"App": ["App.swift": """
				#if canImport(Feature)
				import Feature
				#endif
				#if canImport(Middle)
				import Middle
				#endif

				extension Root {
				    public init() {
				        func __safeDI_outer() -> Outer {
				            _ = Outer.__safeDI_Outer_A2439164466693CC.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            @Sendable nonisolated func __safeDI_apiSendableBuilder_Outer() -> Outer.SafeDISendableScope_Api.__safeDI_Builder<any Api> {
				                .init(innerBuilder: { _ in __safeDI_apiBuilder_Inner() })
				            }
				            @Sendable nonisolated func __safeDI_apiBuilder_Inner() -> Inner.SafeDIScope_Api.__safeDI_Builder<any Api> {
				                .init(api: { _ in
				                    let api: any Api = LiveApi()
				                    return api
				                })
				            }
				            return Outer(__safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_Outer())
				        }
				        let outer: Outer = __safeDI_outer()
				        self.init(outer: outer)
				    }
				}
				"""],
				"Feature": ["Feature.swift": """
				extension Inner {
				    nonisolated public enum SafeDIScope_Api {
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

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
				        let api: any Api = __safeDI_apiBuilder.api(SafeDIScope_Api.api_Values())
				        self.init(api: api)
				    }
				}

				extension Inner {
				    public enum __safeDI_Inner_9EB1889B854C9039 {}
				}
				"""],
				"Middle": ["Middle.swift": """
				#if canImport(Feature)
				import Feature
				#endif

				extension Outer {
				    nonisolated public enum SafeDISendableScope_Api {
				        nonisolated public struct innerBuilder_Values: Sendable {}

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
				            public let innerBuilder: @Sendable (innerBuilder_Values) -> Inner.SafeDIScope_Api.__safeDI_Builder<__safeDI_Built>

				            public init(innerBuilder: @escaping @Sendable (innerBuilder_Values) -> Inner.SafeDIScope_Api.__safeDI_Builder<__safeDI_Built>) {
				                self.innerBuilder = innerBuilder
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
				                self.innerBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
				            }
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public init(__safeDI_apiSendableBuilder: SafeDISendableScope_Api.__safeDI_Builder<any Api>) {
				        @Sendable nonisolated func __safeDI_innerBuilder() -> Inner {
				            _ = Inner.__safeDI_Inner_9EB1889B854C9039.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return Inner(__safeDI_apiBuilder: __safeDI_apiSendableBuilder.innerBuilder(SafeDISendableScope_Api.innerBuilder_Values()))
				        }
				        let innerBuilder = SendableInstantiator<Inner>(__safeDI_innerBuilder)
				        self.init(innerBuilder: innerBuilder)
				    }
				}

				extension Outer {
				    public enum __safeDI_Outer_A2439164466693CC {}
				}
				"""],
			],
			inline: Self.handedOnModules(outerDeclaration: "@Instantiated public let innerBuilder: SendableInstantiator<Inner>", isSendable: true, liveApiInFeature: true),
			probes: [DifferentialValueProbe("Root().outer.innerBuilder.instantiate().api")],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsInnerSeamsBuilderOnTwice_whenTwoSeamsPassEveryPlaceUp() async throws {
		try await expectOutput(
			of: Self.handedOnModules(outerDeclaration: "@Instantiated public let inner: Inner", top: true),
			[
				"App": ["App.swift": """
				#if canImport(Feature)
				import Feature
				#endif
				#if canImport(Middle)
				import Middle
				#endif

				extension Root {
				    public init() {
				        func __safeDI_top() -> Top {
				            _ = Top.__safeDI_Top_F07D71F03F10D371.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            func __safeDI_apiBuilder_Top() -> Top.SafeDIScope_Api.__safeDI_Builder<any Api> {
				                .init(outer: { _ in __safeDI_apiBuilder_Outer() })
				            }
				            func __safeDI_apiBuilder_Outer() -> Outer.SafeDIScope_Api.__safeDI_Builder<any Api> {
				                .init(inner: { _ in __safeDI_apiBuilder_Inner() })
				            }
				            func __safeDI_apiBuilder_Inner() -> Inner.SafeDIScope_Api.__safeDI_Builder<any Api> {
				                .init(api: { _ in
				                    let api: any Api = LiveApi()
				                    return api
				                })
				            }
				            return Top(__safeDI_apiBuilder: __safeDI_apiBuilder_Top())
				        }
				        let top: Top = __safeDI_top()
				        self.init(top: top)
				    }
				}
				"""],
				"Feature": ["Feature.swift": """
				extension Inner {
				    nonisolated public enum SafeDIScope_Api {
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

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
				        let api: any Api = __safeDI_apiBuilder.api(SafeDIScope_Api.api_Values())
				        self.init(api: api)
				    }
				}

				extension Inner {
				    public enum __safeDI_Inner_9EB1889B854C9039 {}
				}
				"""],
				"Middle": ["Middle.swift": """
				#if canImport(Feature)
				import Feature
				#endif

				extension Outer {
				    nonisolated public enum SafeDIScope_Api {
				        nonisolated public struct inner_Values: Sendable {}

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let inner: (inner_Values) -> Inner.SafeDIScope_Api.__safeDI_Builder<__safeDI_Built>

				            public init(inner: @escaping (inner_Values) -> Inner.SafeDIScope_Api.__safeDI_Builder<__safeDI_Built>) {
				                self.inner = inner
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.inner = { _ in .init(__safeDI_noScope: __safeDI_builder) }
				            }
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
				        func __safeDI_inner() -> Inner {
				            _ = Inner.__safeDI_Inner_9EB1889B854C9039.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return Inner(__safeDI_apiBuilder: __safeDI_apiBuilder.inner(SafeDIScope_Api.inner_Values()))
				        }
				        let inner: Inner = __safeDI_inner()
				        self.init(inner: inner)
				    }
				}

				extension Outer {
				    public enum __safeDI_Outer_7D8830DF8628BD6B {}
				}

				extension Top {
				    nonisolated public enum SafeDIScope_Api {
				        nonisolated public struct outer_Values: Sendable {}

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let outer: (outer_Values) -> Outer.SafeDIScope_Api.__safeDI_Builder<__safeDI_Built>

				            public init(outer: @escaping (outer_Values) -> Outer.SafeDIScope_Api.__safeDI_Builder<__safeDI_Built>) {
				                self.outer = outer
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.outer = { _ in .init(__safeDI_noScope: __safeDI_builder) }
				            }
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
				        func __safeDI_outer() -> Outer {
				            _ = Outer.__safeDI_Outer_7D8830DF8628BD6B.self
				            return Outer(__safeDI_apiBuilder: __safeDI_apiBuilder.outer(SafeDIScope_Api.outer_Values()))
				        }
				        let outer: Outer = __safeDI_outer()
				        self.init(outer: outer)
				    }
				}

				extension Top {
				    public enum __safeDI_Top_F07D71F03F10D371 {}
				}
				"""],
			],
			inline: Self.handedOnModules(outerDeclaration: "@Instantiated public let inner: Inner", top: true, liveApiInFeature: true),
			probes: [DifferentialValueProbe("Root().top.outer.inner.api")],
		)
	}

	// MARK: A seam built again

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_servesReenteringCallWithRootLevel_whenSeamsTreeBuildsSeamAgainThroughInstantiator() async throws {
		try await expectOutput(
			of: Self.reenteringModules(),
			[
				"App": ["App.swift": """
				#if canImport(Feature)
				import Feature
				#endif

				extension Root {
				    public convenience init() {
				        func __safeDI_home() -> Home {
				            _ = Home.__safeDI_Home_E5E0B5436B6C5E33.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            func __safeDI_apiBuilder_Home() -> Home.SafeDIScope_Api.__safeDI_Builder<any Api> {
				                .init(
				                    api: { _ in
				                        let api: any Api = LiveApi()
				                        return api
				                    },
				                    screenBuilder: { _ in __safeDI_apiBuilder_Home_Screen_Scope() }
				                )
				            }
				            func __safeDI_apiBuilder_Home_Screen_Scope() -> Home.SafeDIScope_Api.Screen_Scope.__safeDI_Builder<any Api> {
				                .init(homeBuilder: { _ in __safeDI_apiBuilder_Home() })
				            }
				            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
				        }
				        let home: Home = __safeDI_home()
				        self.init(home: home)
				    }
				}
				"""],
				"Feature": ["Feature.swift": """
				extension Home {
				    nonisolated public enum SafeDIScope_Api {
				        nonisolated public struct api_Values {
				            public let screenBuilder: Instantiator<Screen>
				        }

				        nonisolated public struct screenBuilder_Values {}

				        nonisolated public enum Screen_Scope {
				            nonisolated public struct homeBuilder_Values: Sendable {}

				            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				                public let homeBuilder: (homeBuilder_Values) -> Home.SafeDIScope_Api.__safeDI_Builder<__safeDI_Built>

				                public init(homeBuilder: @escaping (homeBuilder_Values) -> Home.SafeDIScope_Api.__safeDI_Builder<__safeDI_Built>) {
				                    self.homeBuilder = homeBuilder
				                }

				                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                    self.homeBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
				                }
				            }
				        }

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let api: (api_Values) -> __safeDI_Built
				            public let screenBuilder: (screenBuilder_Values) -> SafeDIScope_Api.Screen_Scope.__safeDI_Builder<__safeDI_Built>

				            public init(api: @escaping (api_Values) -> __safeDI_Built, screenBuilder: @escaping (screenBuilder_Values) -> SafeDIScope_Api.Screen_Scope.__safeDI_Builder<__safeDI_Built>) {
				                self.api = api
				                self.screenBuilder = screenBuilder
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.api = { _ in __safeDI_builder() }
				                self.screenBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
				            }
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
				        let __safeDI_apiBuilder_screenBuilder = __safeDI_apiBuilder.screenBuilder(SafeDIScope_Api.screenBuilder_Values())
				        func __safeDI_screenBuilder() -> Screen {
				            func __safeDI_homeBuilder() -> Home {
				                _ = Home.__safeDI_Home_E5E0B5436B6C5E33.self
				                return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_screenBuilder.homeBuilder(SafeDIScope_Api.Screen_Scope.homeBuilder_Values()))
				            }
				            let homeBuilder = Instantiator<Home>(__safeDI_homeBuilder)
				            return Screen(homeBuilder: homeBuilder)
				        }
				        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
				        let api: any Api = __safeDI_apiBuilder.api(SafeDIScope_Api.api_Values(screenBuilder: screenBuilder))
				        self.init(api: api, screenBuilder: screenBuilder)
				    }
				}

				extension Home {
				    public enum __safeDI_Home_E5E0B5436B6C5E33 {}
				}
				"""],
			],
			inline: Self.reenteringModules(liveApiInFeature: true),
			probes: [DifferentialValueProbe("Root().home.screenBuilder.instantiate().homeBuilder.instantiate().screenBuilder.instantiate().homeBuilder.instantiate().api")],
		)
	}

	// MARK: A fill that carries an inner seam's struct

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_carriesInnerSeamsStruct_whenFillOfInnerSeamsHoleHoldsPlace() async throws {
		try await expectOutput(
			of: Self.carriedModules(),
			[
				"App": ["App.swift": """
				#if canImport(Feature)
				import Feature
				#endif
				#if canImport(Middle)
				import Middle
				#endif

				extension Root {
				    public convenience init() {
				        func __safeDI_outer() -> Outer {
				            _ = Outer.__safeDI_Outer_E04E6E2A75994D99.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            func __safeDI_gadgetBuilder_Outer() -> Outer.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
				                .init(inner_serviceBuilder: { values in __safeDI_gadgetBuilder_Outer_Inner(tag: values.tag) })
				            }
				            func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(tag: Tag) -> Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
				                .init(gadget: { scope in
				                    let logger = scope.logger
				                    let gadget: any Gadget = LiveGadget(tag: tag, logger: logger)
				                    return gadget
				                })
				            }
				            func __safeDI_gadgetBuilder_Outer_Inner(tag: Tag) -> Inner.SafeDIScope_Service.__safeDI_Builder<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
				                .init(service: { _ in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(tag: tag) })
				            }
				            return Outer(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Outer())
				        }
				        let outer: Outer = __safeDI_outer()
				        self.init(outer: outer)
				    }
				}
				"""],
				"Feature": ["Feature.swift": """
				extension Inner {
				    nonisolated public enum SafeDIScope_Service {
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

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_serviceBuilder: SafeDIScope_Service.__safeDI_Builder<any Service>) {
				        let service: any Service = __safeDI_serviceBuilder.service(SafeDIScope_Service.service_Values())
				        self.init(service: service)
				    }
				}

				extension Inner {
				    public enum __safeDI_Inner_8DBB5EEFBE99D753 {}
				}
				"""],
				"Middle": ["Middle.swift": """
				#if canImport(Feature)
				import Feature
				#endif

				extension Outer {
				    nonisolated public enum SafeDIScope_Gadget {
				        nonisolated public struct inner_serviceBuilder_Values {
				            public let tag: Tag
				        }

				        nonisolated public enum DefaultService_Scope {
				            nonisolated public struct gadget_Values {
				                public let logger: Logger
				            }

				            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				                public let gadget: (gadget_Values) -> __safeDI_Built

				                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
				                    self.gadget = gadget
				                }

				                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                    self.gadget = { _ in __safeDI_builder() }
				                }
				            }
				        }

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let inner_serviceBuilder: (inner_serviceBuilder_Values) -> Inner.SafeDIScope_Service.__safeDI_Builder<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

				            public init(inner_serviceBuilder: @escaping (inner_serviceBuilder_Values) -> Inner.SafeDIScope_Service.__safeDI_Builder<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
				                self.inner_serviceBuilder = inner_serviceBuilder
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.inner_serviceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
				            }
				        }
				    }

				    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
				        let tag = Tag()
				        let __safeDI_gadgetBuilder_inner_serviceBuilder = __safeDI_gadgetBuilder.inner_serviceBuilder(SafeDIScope_Gadget.inner_serviceBuilder_Values(tag: tag))
				        func __safeDI_inner() -> Inner {
				            _ = Inner.__safeDI_Inner_8DBB5EEFBE99D753.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            func __safeDI_serviceBuilder_Inner_service(_ scope: Inner.SafeDIScope_Service.service_Values, __safeDI_inner_serviceBuilder: SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
				                func __safeDI_service() -> DefaultService {
				                    let logger = Logger()
				                    let gadget: any Gadget = __safeDI_inner_serviceBuilder.gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values(logger: logger))
				                    return DefaultService(logger: logger, gadget: gadget)
				                }
				                let service: any Service = __safeDI_service()
				                return service
				            }
				            func __safeDI_serviceBuilder_Inner(up: Inner.SafeDIScope_Service.__safeDI_Builder<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDIScope_Service.__safeDI_Builder<any Service> {
				                .init(service: { scope in __safeDI_serviceBuilder_Inner_service(scope, __safeDI_inner_serviceBuilder: up.service(scope)) })
				            }
				            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner(up: __safeDI_gadgetBuilder_inner_serviceBuilder))
				        }
				        let inner: Inner = __safeDI_inner()
				        self.init(tag: tag, inner: inner)
				    }
				}

				extension Outer {
				    public enum __safeDI_Outer_E04E6E2A75994D99 {}
				}
				"""],
			],
			inline: Self.carriedModules(fulfillersInFeature: true),
			probes: [DifferentialValueProbe("{ let outer = Root().outer; let service = outer.inner.service as! DefaultService; let gadget = service.gadget as! LiveGadget; return [gadget.tag === outer.tag, gadget.logger === service.logger] }()")],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_carriesInnerSeamsSendableStruct_whenFillOfInnerSeamHeldInSendableInstantiatorHoldsPlace() async throws {
		try await expectOutput(
			of: Self.carriedModules(isSendable: true),
			[
				"App": ["App.swift": """
				#if canImport(Feature)
				import Feature
				#endif
				#if canImport(Middle)
				import Middle
				#endif

				extension Root {
				    public convenience init() {
				        func __safeDI_outer() -> Outer {
				            _ = Outer.__safeDI_Outer_D43AAC93DEE3F859.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            @Sendable nonisolated func __safeDI_gadgetSendableBuilder_Outer() -> Outer.SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget> {
				                .init(innerBuilder_serviceBuilder: { _ in __safeDI_gadgetBuilder_Outer_Inner() })
				            }
				            @Sendable nonisolated func __safeDI_gadgetBuilder_Outer_DefaultService_Scope() -> Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
				                .init(gadget: { scope in
				                    let logger = scope.logger
				                    let gadget: any Gadget = LiveGadget(logger: logger)
				                    return gadget
				                })
				            }
				            @Sendable nonisolated func __safeDI_gadgetBuilder_Outer_Inner() -> Inner.SafeDIScope_Service.__safeDI_Builder<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
				                .init(service: { _ in __safeDI_gadgetBuilder_Outer_DefaultService_Scope() })
				            }
				            return Outer(__safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_Outer())
				        }
				        let outer: Outer = __safeDI_outer()
				        self.init(outer: outer)
				    }
				}
				"""],
				"Feature": ["Feature.swift": """
				extension Inner {
				    nonisolated public enum SafeDIScope_Service {
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

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_serviceBuilder: SafeDIScope_Service.__safeDI_Builder<any Service>) {
				        let service: any Service = __safeDI_serviceBuilder.service(SafeDIScope_Service.service_Values())
				        self.init(service: service)
				    }
				}

				extension Inner {
				    public enum __safeDI_Inner_8DBB5EEFBE99D753 {}
				}
				"""],
				"Middle": ["Middle.swift": """
				#if canImport(Feature)
				import Feature
				#endif

				extension Outer {
				    nonisolated public enum SafeDIScope_Gadget {
				        nonisolated public enum DefaultService_Scope {
				            nonisolated public struct gadget_Values {
				                public let logger: Logger
				            }

				            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				                public let gadget: (gadget_Values) -> __safeDI_Built

				                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
				                    self.gadget = gadget
				                }

				                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                    self.gadget = { _ in __safeDI_builder() }
				                }
				            }
				        }
				    }

				    nonisolated public enum SafeDISendableScope_Gadget {
				        nonisolated public struct innerBuilder_serviceBuilder_Values: Sendable {}

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
				            public let innerBuilder_serviceBuilder: @Sendable (innerBuilder_serviceBuilder_Values) -> Inner.SafeDIScope_Service.__safeDI_Builder<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

				            public init(innerBuilder_serviceBuilder: @escaping @Sendable (innerBuilder_serviceBuilder_Values) -> Inner.SafeDIScope_Service.__safeDI_Builder<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
				                self.innerBuilder_serviceBuilder = innerBuilder_serviceBuilder
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
				                self.innerBuilder_serviceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
				            }
				        }
				    }

				    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_gadgetSendableBuilder: SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget>) {
				        let tag = Tag()
				        @Sendable nonisolated func __safeDI_innerBuilder() -> Inner {
				            let __safeDI_gadgetSendableBuilder_innerBuilder_serviceBuilder = __safeDI_gadgetSendableBuilder.innerBuilder_serviceBuilder(SafeDISendableScope_Gadget.innerBuilder_serviceBuilder_Values())
				            _ = Inner.__safeDI_Inner_8DBB5EEFBE99D753.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            func __safeDI_serviceBuilder_Inner_service(_ scope: Inner.SafeDIScope_Service.service_Values, __safeDI_innerBuilder_serviceBuilder: SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
				                func __safeDI_service() -> DefaultService {
				                    let logger = Logger()
				                    let gadget: any Gadget = __safeDI_innerBuilder_serviceBuilder.gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values(logger: logger))
				                    return DefaultService(logger: logger, gadget: gadget)
				                }
				                let service: any Service = __safeDI_service()
				                return service
				            }
				            func __safeDI_serviceBuilder_Inner(up: Inner.SafeDIScope_Service.__safeDI_Builder<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDIScope_Service.__safeDI_Builder<any Service> {
				                .init(service: { scope in __safeDI_serviceBuilder_Inner_service(scope, __safeDI_innerBuilder_serviceBuilder: up.service(scope)) })
				            }
				            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner(up: __safeDI_gadgetSendableBuilder_innerBuilder_serviceBuilder))
				        }
				        let innerBuilder = SendableInstantiator<Inner>(__safeDI_innerBuilder)
				        self.init(tag: tag, innerBuilder: innerBuilder)
				    }
				}

				extension Outer {
				    public enum __safeDI_Outer_D43AAC93DEE3F859 {}
				}
				"""],
			],
			inline: Self.carriedModules(isSendable: true, fulfillersInFeature: true),
			probes: [DifferentialValueProbe("{ let outer = Root().outer; let service = outer.innerBuilder.instantiate().service as! DefaultService; let gadget = service.gadget as! LiveGadget; return gadget.logger === service.logger }()")],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_carriesInnerSeamsStructThreeSeamsDeep_whenFillOfPassedUpHoleHoldsPlace() async throws {
		try await expectOutput(
			of: Self.deepModules(),
			[
				"App": ["App.swift": """
				#if canImport(Feature)
				import Feature
				#endif
				#if canImport(Middle)
				import Middle
				#endif

				extension Root {
				    public convenience init() {
				        func __safeDI_outer() -> Outer {
				            _ = Outer.__safeDI_Outer_A4ACDA948128EE83.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            func __safeDI_gadgetBuilder_Outer() -> Outer.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
				                .init(inner_serviceBuilder: { values in __safeDI_gadgetBuilder_Outer_Inner(tag: values.tag) })
				            }
				            func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(logger: Logger, tag: Tag) -> Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
				                .init(gadget: { _ in
				                    let gadget: any Gadget = LiveGadget(tag: tag, logger: logger)
				                    return gadget
				                })
				            }
				            func __safeDI_gadgetBuilder_Outer_Inner(tag: Tag) -> Inner.SafeDIScope_Service.__safeDI_Builder<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
				                .init(innermost: { _ in __safeDI_gadgetBuilder_Outer_Innermost(tag: tag) })
				            }
				            func __safeDI_gadgetBuilder_Outer_Innermost(tag: Tag) -> Innermost.SafeDIScope_Service.__safeDI_Builder<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
				                .init(detailBuilder: { values in __safeDI_gadgetBuilder_Outer_Innermost_Detail_Scope(logger: values.logger, tag: tag) })
				            }
				            func __safeDI_gadgetBuilder_Outer_Innermost_Detail_Scope(logger: Logger, tag: Tag) -> Innermost.SafeDIScope_Service.Detail_Scope.__safeDI_Builder<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
				                .init(service: { _ in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(logger: logger, tag: tag) })
				            }
				            return Outer(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Outer())
				        }
				        let outer: Outer = __safeDI_outer()
				        self.init(outer: outer)
				    }
				}
				"""],
				"Feature": ["Feature.swift": """
				extension Inner {
				    nonisolated public enum SafeDIScope_Service {
				        nonisolated public struct innermost_Values: Sendable {}

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let innermost: (innermost_Values) -> Innermost.SafeDIScope_Service.__safeDI_Builder<__safeDI_Built>

				            public init(innermost: @escaping (innermost_Values) -> Innermost.SafeDIScope_Service.__safeDI_Builder<__safeDI_Built>) {
				                self.innermost = innermost
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.innermost = { _ in .init(__safeDI_noScope: __safeDI_builder) }
				            }
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_serviceBuilder: SafeDIScope_Service.__safeDI_Builder<any Service>) {
				        let navigator = Navigator()
				        func __safeDI_innermost() -> Innermost {
				            _ = Innermost.__safeDI_Innermost_AFB8CC1B9186E9DE.self
				            return Innermost(__safeDI_serviceBuilder: __safeDI_serviceBuilder.innermost(SafeDIScope_Service.innermost_Values()))
				        }
				        let innermost: Innermost = __safeDI_innermost()
				        self.init(navigator: navigator, innermost: innermost)
				    }
				}

				extension Inner {
				    public enum __safeDI_Inner_B60688E365D998F8 {}
				}

				extension Innermost {
				    nonisolated public enum SafeDIScope_Service {
				        nonisolated public struct detailBuilder_Values {
				            public let logger: Logger
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
				"""],
				"Middle": ["Middle.swift": """
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
				                    self.gadget = { _ in __safeDI_builder() }
				                }
				            }
				        }

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let inner_serviceBuilder: (inner_serviceBuilder_Values) -> Inner.SafeDIScope_Service.__safeDI_Builder<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

				            public init(inner_serviceBuilder: @escaping (inner_serviceBuilder_Values) -> Inner.SafeDIScope_Service.__safeDI_Builder<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
				                self.inner_serviceBuilder = inner_serviceBuilder
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.inner_serviceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
				            }
				        }
				    }

				    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
				        let tag = Tag()
				        let __safeDI_gadgetBuilder_inner_serviceBuilder = __safeDI_gadgetBuilder.inner_serviceBuilder(SafeDIScope_Gadget.inner_serviceBuilder_Values(tag: tag))
				        func __safeDI_inner() -> Inner {
				            _ = Inner.__safeDI_Inner_B60688E365D998F8.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            func __safeDI_serviceBuilder_Innermost_Detail_Scope_service(_ scope: Innermost.SafeDIScope_Service.Detail_Scope.service_Values, logger: Logger, __safeDI_inner_serviceBuilder: SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
				                func __safeDI_service() -> DefaultService {
				                    let gadget: any Gadget = __safeDI_inner_serviceBuilder.gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values())
				                    return DefaultService(logger: logger, gadget: gadget)
				                }
				                let service: any Service = __safeDI_service()
				                return service
				            }
				            func __safeDI_serviceBuilder_Inner(up: Inner.SafeDIScope_Service.__safeDI_Builder<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDIScope_Service.__safeDI_Builder<any Service> {
				                .init(innermost: { values in __safeDI_serviceBuilder_Innermost(up: up.innermost(values)) })
				            }
				            func __safeDI_serviceBuilder_Innermost(up: Innermost.SafeDIScope_Service.__safeDI_Builder<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Innermost.SafeDIScope_Service.__safeDI_Builder<any Service> {
				                .init(detailBuilder: { values in __safeDI_serviceBuilder_Innermost_Detail_Scope(up: up.detailBuilder(values), logger: values.logger) })
				            }
				            func __safeDI_serviceBuilder_Innermost_Detail_Scope(up: Innermost.SafeDIScope_Service.Detail_Scope.__safeDI_Builder<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>, logger: Logger) -> Innermost.SafeDIScope_Service.Detail_Scope.__safeDI_Builder<any Service> {
				                .init(service: { scope in __safeDI_serviceBuilder_Innermost_Detail_Scope_service(scope, logger: logger, __safeDI_inner_serviceBuilder: up.service(scope)) })
				            }
				            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner(up: __safeDI_gadgetBuilder_inner_serviceBuilder))
				        }
				        let inner: Inner = __safeDI_inner()
				        self.init(tag: tag, inner: inner)
				    }
				}

				extension Outer {
				    public enum __safeDI_Outer_A4ACDA948128EE83 {}
				}
				"""],
			],
			inline: Self.deepModules(fulfillersInFeature: true),
			probes: [DifferentialValueProbe("{ let outer = Root().outer; let innermost = outer.inner.innermost; let first = innermost.detailBuilder.instantiate(); let second = innermost.detailBuilder.instantiate(); let service = first.service as! DefaultService; let gadget = service.gadget as! LiveGadget; return [service.logger === innermost.logger, gadget.tag === outer.tag, gadget.logger === innermost.logger, first.service !== second.service] }()")],
		)
	}

	// MARK: A fill whose fulfiller is a seam that passes its own hole up

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsFulfillingSeamItsStruct_whenFillsFulfillerIsSeamWithHoleTheFillingModuleCannotFill() async throws {
		try await expectOutput(
			of: Self.fulfillingSeamModules(),
			[
				"App": ["App.swift": """
				#if canImport(Mid)
				import Mid
				#endif
				#if canImport(Up)
				import Up
				#endif

				extension Root {
				    public convenience init() {
				        func __safeDI_feature() -> Feature {
				            _ = Feature.__safeDI_Feature_056AEDAEB9583142.self // If this line does not compile, compile the code SafeDI generates for module Mid into Mid: under Bazel, add Mid’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            func __safeDI_gadgetBuilder_Feature() -> Feature.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
				                .init(inner_serviceBuilder: { _ in __safeDI_gadgetBuilder_GadgetSeam_Inner() })
				            }
				            func __safeDI_gadgetBuilder_GadgetSeam() -> GadgetSeam.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
				                .init(gadget: { _ in
				                    let gadget: any Gadget = LiveGadget()
				                    return gadget
				                })
				            }
				            func __safeDI_gadgetBuilder_GadgetSeam_Inner() -> Inner.SafeDIScope_Service.__safeDI_Builder<GadgetSeam.SafeDIScope_Gadget.__safeDI_Builder<any Gadget>> {
				                .init(service: { _ in __safeDI_gadgetBuilder_GadgetSeam() })
				            }
				            return Feature(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Feature())
				        }
				        let feature: Feature = __safeDI_feature()
				        self.init(feature: feature)
				    }
				}
				"""],
				"Mid": ["Mid.swift": """
				#if canImport(Up)
				import Up
				#endif

				extension Feature {
				    nonisolated public enum SafeDIScope_Gadget {
				        nonisolated public struct inner_serviceBuilder_Values {}

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let inner_serviceBuilder: (inner_serviceBuilder_Values) -> Inner.SafeDIScope_Service.__safeDI_Builder<GadgetSeam.SafeDIScope_Gadget.__safeDI_Builder<__safeDI_Built>>

				            public init(inner_serviceBuilder: @escaping (inner_serviceBuilder_Values) -> Inner.SafeDIScope_Service.__safeDI_Builder<GadgetSeam.SafeDIScope_Gadget.__safeDI_Builder<__safeDI_Built>>) {
				                self.inner_serviceBuilder = inner_serviceBuilder
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.inner_serviceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
				            }
				        }
				    }

				    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
				        let __safeDI_gadgetBuilder_inner_serviceBuilder = __safeDI_gadgetBuilder.inner_serviceBuilder(SafeDIScope_Gadget.inner_serviceBuilder_Values())
				        func __safeDI_inner() -> Inner {
				            _ = Inner.__safeDI_Inner_8DBB5EEFBE99D753.self // If this line does not compile, compile the code SafeDI generates for module Up into Up: under Bazel, add Up’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            func __safeDI_serviceBuilder_Inner_service(_ scope: Inner.SafeDIScope_Service.service_Values, __safeDI_inner_serviceBuilder: GadgetSeam.SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) -> any Service {
				                func __safeDI_service() -> GadgetSeam {
				                    _ = GadgetSeam.__safeDI_GadgetSeam_F008142A1E900BA7.self
				                    return GadgetSeam(__safeDI_gadgetBuilder: __safeDI_inner_serviceBuilder)
				                }
				                let service: any Service = __safeDI_service()
				                return service
				            }
				            func __safeDI_serviceBuilder_Inner(up: Inner.SafeDIScope_Service.__safeDI_Builder<GadgetSeam.SafeDIScope_Gadget.__safeDI_Builder<any Gadget>>) -> Inner.SafeDIScope_Service.__safeDI_Builder<any Service> {
				                .init(service: { scope in __safeDI_serviceBuilder_Inner_service(scope, __safeDI_inner_serviceBuilder: up.service(scope)) })
				            }
				            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner(up: __safeDI_gadgetBuilder_inner_serviceBuilder))
				        }
				        let inner: Inner = __safeDI_inner()
				        self.init(inner: inner)
				    }
				}

				extension Feature {
				    public enum __safeDI_Feature_056AEDAEB9583142 {}
				}

				extension GadgetSeam {
				    nonisolated public enum SafeDIScope_Gadget {
				        nonisolated public struct gadget_Values {}

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let gadget: (gadget_Values) -> __safeDI_Built

				            public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
				                self.gadget = gadget
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.gadget = { _ in __safeDI_builder() }
				            }
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
				        let gadget: any Gadget = __safeDI_gadgetBuilder.gadget(SafeDIScope_Gadget.gadget_Values())
				        self.init(gadget: gadget)
				    }
				}

				extension GadgetSeam {
				    public enum __safeDI_GadgetSeam_F008142A1E900BA7 {}
				}
				"""],
				"Up": ["Up.swift": """
				extension Inner {
				    nonisolated public enum SafeDIScope_Service {
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

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_serviceBuilder: SafeDIScope_Service.__safeDI_Builder<any Service>) {
				        let service: any Service = __safeDI_serviceBuilder.service(SafeDIScope_Service.service_Values())
				        self.init(service: service)
				    }
				}

				extension Inner {
				    public enum __safeDI_Inner_8DBB5EEFBE99D753 {}
				}
				"""],
			],
			inline: Self.fulfillingSeamModules(liveGadgetInMid: true),
			probes: [DifferentialValueProbe("{ let feature = Root().feature; let service = feature.inner.service as! GadgetSeam; return service.gadget is LiveGadget }()")],
		)
	}

	// MARK: Fixtures

	/// `Inner { service: any Service }` in `Up`; in `Mid`, `Feature { inner: Inner }` and `GadgetSeam: Service { gadget: any Gadget }`,
	/// both seams; only `App` fills `Gadget`.
	private static func fulfillingSeamModules(liveGadgetInMid: Bool = false) -> [ModuleFixture] {
		let liveGadget = """
		@Instantiable(fulfillingAdditionalTypes: [Gadget.self])
		public final class LiveGadget: Instantiable, Gadget {
		    public init() {}
		}
		"""
		let up = [
			"public protocol Service: AnyObject {}",
			"public protocol Gadget: AnyObject {}",
			seamFixtureType(named: "Inner", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let service: any Service"]),
		]
		var mid = [
			seamFixtureType(named: "Feature", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let inner: Inner"]),
			"""
			@Instantiable(generateDependencyTree: true, fulfillingAdditionalTypes: [Service.self])
			public final class GadgetSeam: Instantiable, Service {
			    public init(gadget: any Gadget) { self.gadget = gadget }
			    @Instantiated public let gadget: any Gadget
			}
			""",
		]
		var app = [seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let feature: Feature"])]
		if liveGadgetInMid {
			mid.append(liveGadget)
		} else {
			app.insert(liveGadget, at: 0)
		}
		return [
			ModuleFixture(name: "Up", packageName: "Shop", swiftFileContent: up),
			ModuleFixture(name: "Mid", packageName: "Shop", swiftFileContent: mid.map { "import Up\n\n" + $0 }, dependencies: ["Up"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: app.map { "import Mid\nimport Up\n\n" + $0 }, dependencies: ["Up", "Mid"]),
		]
	}

	/// `Inner` builds `Detail`, which receives `logger` and instantiates `api: any Api`; `Outer` instantiates `logger` and calls
	/// `Inner`, passing the hole up; `App` fills it with `LiveApi`, which receives `logger`.
	private static func passedUpLoggerModules(rootDeclarations: [String], liveApiInFeature: Bool = false) -> [ModuleFixture] {
		let liveApi = """
		@Instantiable(fulfillingAdditionalTypes: [Api.self])
		public final class LiveApi: Instantiable, Api {
		    public init(logger: Logger) { self.logger = logger }
		    @Received public let logger: Logger
		}
		"""
		var feature = [
			"public protocol Api: AnyObject {}",
			"""
			@Instantiable
			public final class Logger: Instantiable { public init() {} }
			""",
			"""
			@Instantiable
			public final class Detail: Instantiable {
			    public init(logger: Logger, api: any Api) { self.logger = logger; self.api = api }
			    @Received public let logger: Logger
			    @Instantiated public let api: any Api
			}
			""",
			seamFixtureType(named: "Inner", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let detail: Detail"]),
			seamFixtureType(named: "Outer", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let logger: Logger", "@Instantiated public let inner: Inner"]),
		]
		var app = [seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: rootDeclarations)]
		if liveApiInFeature {
			feature.append(liveApi)
		} else {
			app.insert(liveApi, at: 0)
		}
		return Self.modules(feature: feature, app: app)
	}

	/// `Outer` instantiates `logger` and calls `Middle`, which instantiates `tag` and calls `Inner`, whose `Detail` receives
	/// both, `tag` only if available, and instantiates `api: any Api`, which only `App` fills, with a `LiveApi` that receives
	/// both the same way.
	private static func twoLevelPassUpModules(liveApiInFeature: Bool = false) -> [ModuleFixture] {
		let liveApi = """
		@Instantiable(fulfillingAdditionalTypes: [Api.self])
		public final class LiveApi: Instantiable, Api {
		    public init(logger: Logger, tag: Tag?) { self.logger = logger; self.tag = tag }
		    @Received public let logger: Logger
		    @Received(onlyIfAvailable: true) public let tag: Tag?
		}
		"""
		var feature = [
			"public protocol Api: AnyObject {}",
			"""
			@Instantiable
			public final class Logger: Instantiable { public init() {} }
			""",
			"""
			@Instantiable
			public final class Tag: Instantiable { public init() {} }
			""",
			"""
			@Instantiable
			public final class Detail: Instantiable {
			    public init(logger: Logger, tag: Tag?, api: any Api) { self.logger = logger; self.tag = tag; self.api = api }
			    @Received public let logger: Logger
			    @Received(onlyIfAvailable: true) public let tag: Tag?
			    @Instantiated public let api: any Api
			}
			""",
			seamFixtureType(named: "Inner", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let detailBuilder: Instantiator<Detail>"]),
			seamFixtureType(named: "Middle", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let tag: Tag", "@Instantiated public let inner: Inner"]),
			seamFixtureType(named: "Outer", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let logger: Logger", "@Instantiated public let middle: Middle"]),
		]
		var app = [seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let logger: Logger", "@Instantiated public let tag: Tag", "@Instantiated public let outer: Outer"])]
		if liveApiInFeature {
			feature.append(liveApi)
		} else {
			app.insert(liveApi, at: 0)
		}
		return Self.modules(feature: feature, app: app)
	}

	/// `Inner { api: any Api }` in `Feature`, called by `Outer` in `Middle` through `outerDeclaration` (and by `Top`, which calls
	/// `Outer`, where `top` says so); only `App` fills `Api`.
	private static func handedOnModules(outerDeclaration: String, isSendable: Bool = false, top: Bool = false, liveApiInFeature: Bool = false) -> [ModuleFixture] {
		let api = isSendable ? "public protocol Api: Sendable {}" : "public protocol Api {}"
		let liveApi = """
		@Instantiable(fulfillingAdditionalTypes: [Api.self])
		public struct LiveApi: Instantiable, Api {
		    public init() {}
		}
		"""
		var feature = [api, seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated public let api: any Api"])]
		var middle = [seamFixtureType(named: "Outer", isSeam: true, declarations: [outerDeclaration])]
		if top {
			middle.append(seamFixtureType(named: "Top", isSeam: true, declarations: ["@Instantiated public let outer: Outer"]))
		}
		var app = [seamFixtureType(named: "Root", isRoot: true, declarations: [top ? "@Instantiated public let top: Top" : "@Instantiated public let outer: Outer"])]
		if liveApiInFeature {
			feature.append(liveApi)
		} else {
			app.insert(liveApi, at: 0)
		}
		return [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature),
			ModuleFixture(name: "Middle", packageName: "Shop", swiftFileContent: middle.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: app.map { "import Feature\nimport Middle\n\n" + $0 }, dependencies: ["Feature", "Middle"]),
		]
	}

	/// `Home { api: any Api; screenBuilder: Instantiator<Screen> }`, a seam, whose `Screen` builds `Home` again through
	/// `homeBuilder: Instantiator<Home>`; only `App` fills `Api`.
	private static func reenteringModules(liveApiInFeature: Bool = false) -> [ModuleFixture] {
		let liveApi = """
		@Instantiable(fulfillingAdditionalTypes: [Api.self])
		public final class LiveApi: Instantiable, Api {
		    public init() {}
		}
		"""
		var feature = [
			"public protocol Api: AnyObject {}",
			seamFixtureType(named: "Home", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let api: any Api", "@Instantiated public let screenBuilder: Instantiator<Screen>"]),
			seamFixtureType(named: "Screen", isFinalClass: true, declarations: ["@Instantiated public let homeBuilder: Instantiator<Home>"]),
		]
		var app = [seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let home: Home"])]
		if liveApiInFeature {
			feature.append(liveApi)
		} else {
			app.insert(liveApi, at: 0)
		}
		return Self.modules(feature: feature, app: app)
	}

	/// `Inner { service: any Service }` in `Feature`; in `Middle`, `Outer { tag; inner: Inner }` and `DefaultService`, which
	/// receives `logger`, instantiates its own `logger` before, and holds `gadget: any Gadget`, which only `App` fills, with a
	/// `LiveGadget` that receives `tag` and `logger`.
	private static func carriedModules(isSendable: Bool = false, fulfillersInFeature: Bool = false) -> [ModuleFixture] {
		let sendable = isSendable ? ", Sendable" : ""
		let defaultService = """
		@Instantiable(fulfillingAdditionalTypes: [Service.self])
		public final class DefaultService: Instantiable, Service {
		    public init(logger: Logger, gadget: any Gadget) { self.logger = logger; self.gadget = gadget }
		    @Instantiated public let logger: Logger
		    @Instantiated public let gadget: any Gadget
		}
		"""
		// Inside the `@Sendable` function that builds `Inner`, a fill reads only what that function binds.
		let liveGadget = isSendable ? """
		@Instantiable(fulfillingAdditionalTypes: [Gadget.self])
		public final class LiveGadget: Instantiable, Gadget {
		    public init(logger: Logger) { self.logger = logger }
		    @Received public let logger: Logger
		}
		""" : """
		@Instantiable(fulfillingAdditionalTypes: [Gadget.self])
		public final class LiveGadget: Instantiable, Gadget {
		    public init(tag: Tag, logger: Logger) { self.tag = tag; self.logger = logger }
		    @Received public let tag: Tag
		    @Received public let logger: Logger
		}
		"""
		var feature = [
			"public protocol Service: AnyObject\(sendable) {}",
			"public protocol Gadget: AnyObject\(sendable) {}",
			"""
			@Instantiable
			public final class Logger: Instantiable\(sendable) { public init() {} }
			""",
			"""
			@Instantiable
			public final class Tag: Instantiable\(sendable) { public init() {} }
			""",
			seamFixtureType(named: "Inner", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let service: any Service"], conformances: sendable),
		]
		var middle = [seamFixtureType(named: "Outer", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let tag: Tag", isSendable ? "@Instantiated public let innerBuilder: SendableInstantiator<Inner>" : "@Instantiated public let inner: Inner"])]
		var app = [seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let outer: Outer"])]
		if fulfillersInFeature {
			feature += [defaultService, liveGadget]
		} else {
			middle.insert(defaultService, at: 0)
			app.insert(liveGadget, at: 0)
		}
		return [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature),
			ModuleFixture(name: "Middle", packageName: "Shop", swiftFileContent: middle.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: app.map { "import Feature\nimport Middle\n\n" + $0 }, dependencies: ["Feature", "Middle"]),
		]
	}

	/// Three seams deep: `Inner { navigator; innermost: Innermost }` and `Innermost { logger; detailBuilder: Instantiator<Detail> }`
	/// in `Feature`, `Detail { service: any Service }`; in `Middle`, `Outer { tag; inner: Inner }` and `DefaultService`, which
	/// receives `logger` and holds `gadget: any Gadget`, which only `App` fills, with a `LiveGadget` that receives `tag` and
	/// `logger`.
	private static func deepModules(fulfillersInFeature: Bool = false) -> [ModuleFixture] {
		let defaultService = """
		@Instantiable(fulfillingAdditionalTypes: [Service.self])
		public final class DefaultService: Instantiable, Service {
		    public init(logger: Logger, gadget: any Gadget) { self.logger = logger; self.gadget = gadget }
		    @Received public let logger: Logger
		    @Instantiated public let gadget: any Gadget
		}
		"""
		let liveGadget = """
		@Instantiable(fulfillingAdditionalTypes: [Gadget.self])
		public final class LiveGadget: Instantiable, Gadget {
		    public init(tag: Tag, logger: Logger) { self.tag = tag; self.logger = logger }
		    @Received public let tag: Tag
		    @Received public let logger: Logger
		}
		"""
		var feature = [
			"public protocol Service: AnyObject {}",
			"public protocol Gadget: AnyObject {}",
			"""
			@Instantiable
			public final class Navigator: Instantiable { public init() {} }
			""",
			"""
			@Instantiable
			public final class Logger: Instantiable { public init() {} }
			""",
			"""
			@Instantiable
			public final class Tag: Instantiable { public init() {} }
			""",
			seamFixtureType(named: "Detail", isFinalClass: true, declarations: ["@Instantiated public let service: any Service"]),
			seamFixtureType(named: "Innermost", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let logger: Logger", "@Instantiated public let detailBuilder: Instantiator<Detail>"]),
			seamFixtureType(named: "Inner", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let navigator: Navigator", "@Instantiated public let innermost: Innermost"]),
		]
		var middle = [seamFixtureType(named: "Outer", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let tag: Tag", "@Instantiated public let inner: Inner"])]
		var app = [seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let outer: Outer"])]
		if fulfillersInFeature {
			feature += [defaultService, liveGadget]
		} else {
			middle.insert(defaultService, at: 0)
			app.insert(liveGadget, at: 0)
		}
		return [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature),
			ModuleFixture(name: "Middle", packageName: "Shop", swiftFileContent: middle.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: app.map { "import Feature\nimport Middle\n\n" + $0 }, dependencies: ["Feature", "Middle"]),
		]
	}

	private static func modules(feature: [String], app: [String]) -> [ModuleFixture] {
		SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: app)
	}

	/// Expects each module's generated files to equal `expected`, every module to compile, and the values `probes` describe to
	/// equal those of `inline`, the same graph with every fulfiller where the seams can build it.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectOutput(
		of modules: [ModuleFixture],
		_ expected: [String: [String: String]],
		inline: [ModuleFixture],
		probes: [DifferentialValueProbe],
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		for (moduleName, files) in expected {
			#expect(output.modules[moduleName]?.generatedFiles == files.mapValues { generatedFileHeader + $0 }, sourceLocation: sourceLocation)
		}
		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation, sourceLocation: sourceLocation)
		#expect(compilation.modules.map(\.exitCode) == output.moduleNames.map { _ in 0 }, sourceLocation: sourceLocation)
		for module in compilation.modules where module.exitCode != 0 {
			Issue.record(Comment(rawValue: module.standardError), sourceLocation: sourceLocation)
		}
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inline, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		try await expectDifferentialValuesAgree(
			feature: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: output, modules: modules),
			knownRight: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: inlineOutput, modules: inline),
			probes: probes,
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}

	private var filesToDelete: [URL]
}
