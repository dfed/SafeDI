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
				        func __safeDI_apiBuilder_Outer() -> Outer.__safeDI_ApiCarrier<any Api> {
				            .init(inner: __safeDI_apiBuilder_Inner())
				        }
				        func __safeDI_apiBuilder_Inner() -> Inner.__safeDI_ApiCarrier<any Api> {
				            .init(detail: { values_logger in __safeDI_apiBuilder_Inner_Detail_Scope(logger: values_logger) })
				        }
				        func __safeDI_apiBuilder_Inner_Detail_Scope(logger: LazilyInstantiated<Logger>) -> Inner.__safeDI_ApiCarrier_Detail<any Api> {
				            .init(api: {
				                let api: any Api = LiveApi(logger: logger.instance)
				                return api
				            })
				        }
				        func __safeDI_outer() -> Outer {
				            _ = Outer.__safeDI_Outer_334999E8DAB184F7.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return Outer(__safeDI_apiBuilder: __safeDI_apiBuilder_Outer())
				        }
				        let outer: Outer = __safeDI_outer()
				        self.init(outer: outer)
				    }
				}
				"""],
				"Feature": ["Feature.swift": """
				extension Inner {
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

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_logger: @autoclosure @escaping () -> Logger, __safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
				        let logger = LazilyInstantiated<Logger>(__safeDI_logger)
				        let __safeDI_apiBuilder_detail = __safeDI_apiBuilder.detail(logger)
				        func __safeDI_detail() -> Detail {
				            let api: any Api = __safeDI_apiBuilder_detail.api()
				            return Detail(logger: logger.instance, api: api)
				        }
				        let detail: Detail = __safeDI_detail()
				        self.init(detail: detail)
				    }
				}

				extension Inner {
				    public enum __safeDI_Inner_A787746832C659F0 {}
				}

				extension Outer {
				    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
				        public let inner: Inner.__safeDI_ApiCarrier<__safeDI_Built>

				        public init(inner: Inner.__safeDI_ApiCarrier<__safeDI_Built>) {
				            self.inner = inner
				        }

				        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				            self.init(inner: .init(__safeDI_noScope: __safeDI_builder))
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
				        let logger = Logger()
				        func __safeDI_inner() -> Inner {
				            _ = Inner.__safeDI_Inner_A787746832C659F0.self
				            return Inner(__safeDI_logger: logger, __safeDI_apiBuilder: __safeDI_apiBuilder.inner)
				        }
				        let inner: Inner = __safeDI_inner()
				        self.init(logger: logger, inner: inner)
				    }
				}

				extension Outer {
				    public enum __safeDI_Outer_334999E8DAB184F7 {}
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
				        func __safeDI_apiBuilder_Outer() -> Outer.__safeDI_ApiCarrier<any Api> {
				            .init(inner: __safeDI_apiBuilder_Inner())
				        }
				        func __safeDI_apiBuilder_Inner() -> Inner.__safeDI_ApiCarrier<any Api> {
				            .init(detail: { values_logger in __safeDI_apiBuilder_Inner_Detail_Scope(logger: values_logger) })
				        }
				        func __safeDI_apiBuilder_Inner_Detail_Scope(logger: LazilyInstantiated<Logger>) -> Inner.__safeDI_ApiCarrier_Detail<any Api> {
				            .init(api: {
				                let api: any Api = LiveApi(logger: logger.instance)
				                return api
				            })
				        }
				        let logger = Logger()
				        func __safeDI_outer() -> Outer {
				            _ = Outer.__safeDI_Outer_334999E8DAB184F7.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return Outer(__safeDI_apiBuilder: __safeDI_apiBuilder_Outer())
				        }
				        let outer: Outer = __safeDI_outer()
				        self.init(logger: logger, outer: outer)
				    }
				}
				"""],
				"Feature": ["Feature.swift": """
				extension Inner {
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

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_logger: @autoclosure @escaping () -> Logger, __safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
				        let logger = LazilyInstantiated<Logger>(__safeDI_logger)
				        let __safeDI_apiBuilder_detail = __safeDI_apiBuilder.detail(logger)
				        func __safeDI_detail() -> Detail {
				            let api: any Api = __safeDI_apiBuilder_detail.api()
				            return Detail(logger: logger.instance, api: api)
				        }
				        let detail: Detail = __safeDI_detail()
				        self.init(detail: detail)
				    }
				}

				extension Inner {
				    public enum __safeDI_Inner_A787746832C659F0 {}
				}

				extension Outer {
				    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
				        public let inner: Inner.__safeDI_ApiCarrier<__safeDI_Built>

				        public init(inner: Inner.__safeDI_ApiCarrier<__safeDI_Built>) {
				            self.inner = inner
				        }

				        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				            self.init(inner: .init(__safeDI_noScope: __safeDI_builder))
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
				        let logger = Logger()
				        func __safeDI_inner() -> Inner {
				            _ = Inner.__safeDI_Inner_A787746832C659F0.self
				            return Inner(__safeDI_logger: logger, __safeDI_apiBuilder: __safeDI_apiBuilder.inner)
				        }
				        let inner: Inner = __safeDI_inner()
				        self.init(logger: logger, inner: inner)
				    }
				}

				extension Outer {
				    public enum __safeDI_Outer_334999E8DAB184F7 {}
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
				        func __safeDI_apiBuilder_Outer() -> Outer.__safeDI_ApiCarrier<any Api> {
				            .init(middle: __safeDI_apiBuilder_Middle())
				        }
				        func __safeDI_apiBuilder_Middle() -> Middle.__safeDI_ApiCarrier<any Api> {
				            .init(inner: __safeDI_apiBuilder_Inner())
				        }
				        func __safeDI_apiBuilder_Inner() -> Inner.__safeDI_ApiCarrier<any Api> {
				            .init(detailBuilder: { values_logger, values_tag in __safeDI_apiBuilder_Inner_Detail_Scope(logger: values_logger, tag: values_tag) })
				        }
				        func __safeDI_apiBuilder_Inner_Detail_Scope(logger: LazilyInstantiated<Logger>, tag: LazilyInstantiated<Tag?>) -> Inner.__safeDI_ApiCarrier_Detail<any Api> {
				            .init(api: {
				                let api: any Api = LiveApi(logger: logger.instance, tag: tag.instance)
				                return api
				            })
				        }
				        let logger = Logger()
				        let tag = Tag()
				        func __safeDI_outer() -> Outer {
				            _ = Outer.__safeDI_Outer_F31B0E4228C1597F.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return Outer(__safeDI_apiBuilder: __safeDI_apiBuilder_Outer())
				        }
				        let outer: Outer = __safeDI_outer()
				        self.init(logger: logger, tag: tag, outer: outer)
				    }
				}
				"""],
				"Feature": ["Feature.swift": """
				extension Inner {
				    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
				        public let detailBuilder: (LazilyInstantiated<Logger>, LazilyInstantiated<Tag?>) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>

				        public init(detailBuilder: @escaping (LazilyInstantiated<Logger>, LazilyInstantiated<Tag?>) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>) {
				            self.detailBuilder = detailBuilder
				        }

				        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				            self.init(detailBuilder: { _, _ in .init(__safeDI_noScope: __safeDI_builder) })
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

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_logger: @autoclosure @escaping () -> Logger, __safeDI_tag: @autoclosure @escaping () -> Tag?, __safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
				        let logger = LazilyInstantiated<Logger>(__safeDI_logger)
				        let tag = LazilyInstantiated<Tag?>(__safeDI_tag)
				        let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder.detailBuilder(logger, tag)
				        func __safeDI_detailBuilder() -> Detail {
				            let api: any Api = __safeDI_apiBuilder_detailBuilder.api()
				            return Detail(logger: logger.instance, tag: tag.instance, api: api)
				        }
				        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
				        self.init(detailBuilder: detailBuilder)
				    }
				}

				extension Inner {
				    public enum __safeDI_Inner_0A154B51BC26C0CC {}
				}

				extension Middle {
				    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
				        public let inner: Inner.__safeDI_ApiCarrier<__safeDI_Built>

				        public init(inner: Inner.__safeDI_ApiCarrier<__safeDI_Built>) {
				            self.inner = inner
				        }

				        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				            self.init(inner: .init(__safeDI_noScope: __safeDI_builder))
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_logger: @autoclosure @escaping () -> Logger, __safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
				        let logger = LazilyInstantiated<Logger>(__safeDI_logger)
				        let tag = Tag()
				        func __safeDI_inner() -> Inner {
				            _ = Inner.__safeDI_Inner_0A154B51BC26C0CC.self
				            return Inner(__safeDI_logger: logger.instance, __safeDI_tag: tag, __safeDI_apiBuilder: __safeDI_apiBuilder.inner)
				        }
				        let inner: Inner = __safeDI_inner()
				        self.init(tag: tag, inner: inner)
				    }
				}

				extension Middle {
				    public enum __safeDI_Middle_A3A5659060C2908C {}
				}

				extension Outer {
				    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
				        public let middle: Middle.__safeDI_ApiCarrier<__safeDI_Built>

				        public init(middle: Middle.__safeDI_ApiCarrier<__safeDI_Built>) {
				            self.middle = middle
				        }

				        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				            self.init(middle: .init(__safeDI_noScope: __safeDI_builder))
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
				        let logger = Logger()
				        func __safeDI_middle() -> Middle {
				            _ = Middle.__safeDI_Middle_A3A5659060C2908C.self
				            return Middle(__safeDI_logger: logger, __safeDI_apiBuilder: __safeDI_apiBuilder.middle)
				        }
				        let middle: Middle = __safeDI_middle()
				        self.init(logger: logger, middle: middle)
				    }
				}

				extension Outer {
				    public enum __safeDI_Outer_F31B0E4228C1597F {}
				}
				"""],
			],
			inline: Self.twoLevelPassUpModules(liveApiInFeature: true),
			probes: [
				DifferentialValueProbe("{ let root = Root(); let detail = root.outer.middle.inner.detailBuilder.instantiate(); let api = detail.api as! LiveApi; return [api.logger === root.outer.logger, api.tag === root.outer.middle.tag, detail.tag === root.outer.middle.tag] }()"),
			],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_createsPassingUpSeamsLazyValuesWhereFillReadsThem_whenTwoSeamsPassThePlaceUpFromLazyDeclarations() async throws {
		// The fill binds both memos, the optional one included, and reads each instance where it builds `LiveApi`, so neither
		// value is created before `detailBuilder` builds `Detail`, as inline.
		try await expectOutput(
			of: Self.twoLevelPassUpModules(lazyOrigins: true),
			[
				"App": ["App.swift": """
				#if canImport(Feature)
				import Feature
				#endif

				extension Root {
				    public convenience init() {
				        func __safeDI_apiBuilder_Outer() -> Outer.__safeDI_ApiCarrier<any Api> {
				            .init(middle: __safeDI_apiBuilder_Middle())
				        }
				        func __safeDI_apiBuilder_Middle() -> Middle.__safeDI_ApiCarrier<any Api> {
				            .init(inner: __safeDI_apiBuilder_Inner())
				        }
				        func __safeDI_apiBuilder_Inner() -> Inner.__safeDI_ApiCarrier<any Api> {
				            .init(detailBuilder: { values_logger, values_tag in __safeDI_apiBuilder_Inner_Detail_Scope(logger: values_logger, tag: values_tag) })
				        }
				        func __safeDI_apiBuilder_Inner_Detail_Scope(logger: LazilyInstantiated<Logger>, tag: LazilyInstantiated<Tag?>) -> Inner.__safeDI_ApiCarrier_Detail<any Api> {
				            .init(api: {
				                let api: any Api = LiveApi(logger: logger.instance, tag: tag.instance)
				                return api
				            })
				        }
				        let logger = Logger()
				        let tag = Tag()
				        func __safeDI_outer() -> Outer {
				            _ = Outer.__safeDI_Outer_F31B0E4228C1597F.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return Outer(__safeDI_apiBuilder: __safeDI_apiBuilder_Outer())
				        }
				        let outer: Outer = __safeDI_outer()
				        self.init(logger: logger, tag: tag, outer: outer)
				    }
				}
				"""],
				"Feature": ["Feature.swift": """
				extension Inner {
				    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
				        public let detailBuilder: (LazilyInstantiated<Logger>, LazilyInstantiated<Tag?>) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>

				        public init(detailBuilder: @escaping (LazilyInstantiated<Logger>, LazilyInstantiated<Tag?>) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>) {
				            self.detailBuilder = detailBuilder
				        }

				        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				            self.init(detailBuilder: { _, _ in .init(__safeDI_noScope: __safeDI_builder) })
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

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_logger: @autoclosure @escaping () -> Logger, __safeDI_tag: @autoclosure @escaping () -> Tag?, __safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
				        let logger = LazilyInstantiated<Logger>(__safeDI_logger)
				        let tag = LazilyInstantiated<Tag?>(__safeDI_tag)
				        let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder.detailBuilder(logger, tag)
				        func __safeDI_detailBuilder() -> Detail {
				            let api: any Api = __safeDI_apiBuilder_detailBuilder.api()
				            return Detail(logger: logger.instance, tag: tag.instance, api: api)
				        }
				        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
				        self.init(detailBuilder: detailBuilder)
				    }
				}

				extension Inner {
				    public enum __safeDI_Inner_0A154B51BC26C0CC {}
				}

				extension Middle {
				    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
				        public let inner: Inner.__safeDI_ApiCarrier<__safeDI_Built>

				        public init(inner: Inner.__safeDI_ApiCarrier<__safeDI_Built>) {
				            self.inner = inner
				        }

				        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				            self.init(inner: .init(__safeDI_noScope: __safeDI_builder))
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_logger: @autoclosure @escaping () -> Logger, __safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
				        let logger = LazilyInstantiated<Logger>(__safeDI_logger)
				        func __safeDI_tag() -> Tag {
				            Tag()
				        }
				        let tag = LazilyInstantiated<Tag>(__safeDI_tag)
				        func __safeDI_inner() -> Inner {
				            _ = Inner.__safeDI_Inner_0A154B51BC26C0CC.self
				            return Inner(__safeDI_logger: logger.instance, __safeDI_tag: tag.instance, __safeDI_apiBuilder: __safeDI_apiBuilder.inner)
				        }
				        let inner: Inner = __safeDI_inner()
				        self.init(tag: tag, inner: inner)
				    }
				}

				extension Middle {
				    public enum __safeDI_Middle_A3A5659060C2908C {}
				}

				extension Outer {
				    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
				        public let middle: Middle.__safeDI_ApiCarrier<__safeDI_Built>

				        public init(middle: Middle.__safeDI_ApiCarrier<__safeDI_Built>) {
				            self.middle = middle
				        }

				        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				            self.init(middle: .init(__safeDI_noScope: __safeDI_builder))
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
				        func __safeDI_logger() -> Logger {
				            Logger()
				        }
				        let logger = LazilyInstantiated<Logger>(__safeDI_logger)
				        func __safeDI_middle() -> Middle {
				            _ = Middle.__safeDI_Middle_A3A5659060C2908C.self
				            return Middle(__safeDI_logger: logger.instance, __safeDI_apiBuilder: __safeDI_apiBuilder.middle)
				        }
				        let middle: Middle = __safeDI_middle()
				        self.init(logger: logger, middle: middle)
				    }
				}

				extension Outer {
				    public enum __safeDI_Outer_F31B0E4228C1597F {}
				}
				"""],
			],
			inline: Self.twoLevelPassUpModules(liveApiInFeature: true, lazyOrigins: true),
			probes: [
				DifferentialValueProbe("{ let root = Root(); let before = Stamp.next(); let detail = root.outer.middle.inner.detailBuilder.instantiate(); let api = detail.api as! LiveApi; return [before, api.logger.differentialValueCreationStamp, api.tag?.differentialValueCreationStamp ?? 0, detail.logger.differentialValueCreationStamp, detail.tag?.differentialValueCreationStamp ?? 0] }()"),
				DifferentialValueProbe("{ let root = Root(); let detail = root.outer.middle.inner.detailBuilder.instantiate(); let api = detail.api as! LiveApi; return [api.logger === root.outer.logger.instance, api.tag === root.outer.middle.tag.instance, detail.tag === root.outer.middle.tag.instance] }()"),
				DifferentialValueProbe("Root()"),
			],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsWithPassingUpSeamsValue_whenPlaceInsideFillOfCalledSeamsHoleReadsIt() async throws {
		try await expectOutput(
			of: Self.passedUpPlaceInsideFillModules(),
			[
				"App": ["App.swift": """
				#if canImport(Feature)
				import Feature
				#endif
				#if canImport(Session)
				import Session
				#endif

				extension Root {
				    public convenience init() {
				        func __safeDI_apiBuilder_Outer() -> Outer.__safeDI_ApiCarrier<any Api> {
				            .init(inner: __safeDI_apiBuilder_Inner())
				        }
				        func __safeDI_apiBuilder_Inner() -> Inner.SafeDIScope_Api.__safeDI_Builder<any Api> {
				            .init(nest_serviceBuilder: { values in __safeDI_apiBuilder_Inner_Nest(logger: values.__safeDI_logger) })
				        }
				        func __safeDI_apiBuilder_Inner_NestImpl_Scope(logger: LazilyInstantiated<Logger>) -> Inner.SafeDIScope_Api.NestImpl_Scope.__safeDI_Builder<any Api> {
				            .init(api: { _ in
				                let api: any Api = LiveApi(logger: logger.instance)
				                return api
				            })
				        }
				        func __safeDI_apiBuilder_Inner_Nest(logger: LazilyInstantiated<Logger>) -> Nest.__safeDI_ServiceCarrier<Inner.SafeDIScope_Api.NestImpl_Scope.__safeDI_Builder<any Api>> {
				            .init(service: { __safeDI_apiBuilder_Inner_NestImpl_Scope(logger: logger) })
				        }
				        let logger = Logger()
				        func __safeDI_outer() -> Outer {
				            _ = Outer.__safeDI_Outer_D3729F9DB5C5AFBA.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return Outer(__safeDI_apiBuilder: __safeDI_apiBuilder_Outer())
				        }
				        let outer: Outer = __safeDI_outer()
				        self.init(logger: logger, outer: outer)
				    }
				}
				"""],
				"Feature": ["Feature.swift": """
				#if canImport(Session)
				import Session
				#endif

				extension Inner {
				    nonisolated public enum SafeDIScope_Api {
				        nonisolated public struct nest_serviceBuilder_Values {
				            public var logger: Logger { __safeDI_logger.instance }
				            public let detail: Detail
				            public let __safeDI_logger: LazilyInstantiated<Logger>

				            init(logger: LazilyInstantiated<Logger>, detail: Detail) {
				                __safeDI_logger = logger
				                self.detail = detail
				            }
				        }

				        nonisolated public enum NestImpl_Scope {
				            nonisolated public struct api_Values {}

				            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				                public let api: (api_Values) -> __safeDI_Built

				                public init(api: @escaping (api_Values) -> __safeDI_Built) {
				                    self.api = api
				                }

				                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                    self.init(api: { _ in __safeDI_builder() })
				                }
				            }
				        }

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let nest_serviceBuilder: (nest_serviceBuilder_Values) -> Nest.__safeDI_ServiceCarrier<SafeDIScope_Api.NestImpl_Scope.__safeDI_Builder<__safeDI_Built>>

				            public init(nest_serviceBuilder: @escaping (nest_serviceBuilder_Values) -> Nest.__safeDI_ServiceCarrier<SafeDIScope_Api.NestImpl_Scope.__safeDI_Builder<__safeDI_Built>>) {
				                self.nest_serviceBuilder = nest_serviceBuilder
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.init(nest_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
				            }
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_logger: @autoclosure @escaping () -> Logger, __safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
				        let logger = LazilyInstantiated<Logger>(__safeDI_logger)
				        let detail = Detail(logger: logger.instance)
				        let __safeDI_apiBuilder_nest_serviceBuilder = __safeDI_apiBuilder.nest_serviceBuilder(SafeDIScope_Api.nest_serviceBuilder_Values(logger: logger, detail: detail))
				        func __safeDI_nest() -> Nest {
				            _ = Nest.__safeDI_Nest_798DEDE6CA20D0EB.self // If this line does not compile, compile the code SafeDI generates for module Session into Session: under Bazel, add Session’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            func __safeDI_serviceBuilder_Nest_service(__safeDI_nest_serviceBuilder: SafeDIScope_Api.NestImpl_Scope.__safeDI_Builder<any Api>) -> any Service {
				                func __safeDI_service() -> NestImpl {
				                    let api: any Api = __safeDI_nest_serviceBuilder.api(SafeDIScope_Api.NestImpl_Scope.api_Values())
				                    return NestImpl(api: api)
				                }
				                let service: any Service = __safeDI_service()
				                return service
				            }
				            func __safeDI_serviceBuilder_Nest(up: Nest.__safeDI_ServiceCarrier<SafeDIScope_Api.NestImpl_Scope.__safeDI_Builder<any Api>>) -> Nest.__safeDI_ServiceCarrier<any Service> {
				                .init(service: { __safeDI_serviceBuilder_Nest_service(__safeDI_nest_serviceBuilder: up.service()) })
				            }
				            return Nest(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Nest(up: __safeDI_apiBuilder_nest_serviceBuilder))
				        }
				        let nest: Nest = __safeDI_nest()
				        self.init(detail: detail, nest: nest)
				    }
				}

				extension Inner {
				    public enum __safeDI_Inner_97CBE63D6BAF6B81 {}
				}

				extension Outer {
				    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
				        public let inner: Inner.SafeDIScope_Api.__safeDI_Builder<__safeDI_Built>

				        public init(inner: Inner.SafeDIScope_Api.__safeDI_Builder<__safeDI_Built>) {
				            self.inner = inner
				        }

				        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				            self.init(inner: .init(__safeDI_noScope: __safeDI_builder))
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
				        let logger = Logger()
				        func __safeDI_inner() -> Inner {
				            _ = Inner.__safeDI_Inner_97CBE63D6BAF6B81.self
				            return Inner(__safeDI_logger: logger, __safeDI_apiBuilder: __safeDI_apiBuilder.inner)
				        }
				        let inner: Inner = __safeDI_inner()
				        self.init(logger: logger, inner: inner)
				    }
				}

				extension Outer {
				    public enum __safeDI_Outer_D3729F9DB5C5AFBA {}
				}
				"""],
				"Session": ["Session.swift": """
				extension Nest {
				    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
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
				        let service: any Service = __safeDI_serviceBuilder.service()
				        self.init(service: service)
				    }
				}

				extension Nest {
				    public enum __safeDI_Nest_798DEDE6CA20D0EB {}
				}
				"""],
			],
			inline: Self.passedUpPlaceInsideFillModules(liveApiInFeature: true),
			// `Logger` is stamped, so the comparison sees when each logger is created as well as which one is read.
			probes: [DifferentialValueProbe("Root()")],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_createsPassingUpSeamsLazyValueWhereFillReadsIt_whenReaderIsBeneathInstantiatorInsideFill() async throws {
		try await expectOutput(
			of: Self.passedUpLazyLoggerModules(),
			[
				"App": ["App.swift": """
				#if canImport(Feature)
				import Feature
				#endif

				extension Root {
				    public convenience init() {
				        func __safeDI_outer() -> Outer {
				            _ = Outer.__safeDI_Outer_596630904AB994DF.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            func __safeDI_apiBuilder_Inner_Detail_Scope_api(_ scope_readerBuilder: Instantiator<Reader>, logger: LazilyInstantiated<Logger>) -> any Api {
				                func __safeDI_api() -> LiveApi {
				                    func __safeDI_jobBuilder() -> Job {
				                        Job(logger: logger.instance)
				                    }
				                    let jobBuilder = Instantiator<Job>(__safeDI_jobBuilder)
				                    return LiveApi(jobBuilder: jobBuilder)
				                }
				                let api: any Api = __safeDI_api()
				                return api
				            }
				            func __safeDI_apiBuilder_Outer() -> Outer.__safeDI_ApiCarrier<any Api> {
				                .init(inner: __safeDI_apiBuilder_Inner())
				            }
				            func __safeDI_apiBuilder_Inner() -> Inner.__safeDI_ApiCarrier<any Api> {
				                .init(detail: { values_logger in __safeDI_apiBuilder_Inner_Detail_Scope(logger: values_logger) })
				            }
				            func __safeDI_apiBuilder_Inner_Detail_Scope(logger: LazilyInstantiated<Logger>) -> Inner.__safeDI_ApiCarrier_Detail<any Api> {
				                .init(api: { scope_readerBuilder in __safeDI_apiBuilder_Inner_Detail_Scope_api(scope_readerBuilder, logger: logger) })
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
				        public let api: (Instantiator<Reader>) -> __safeDI_Built

				        public init(api: @escaping (Instantiator<Reader>) -> __safeDI_Built) {
				            self.api = api
				        }

				        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				            self.init(api: { _ in __safeDI_builder() })
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_logger: @autoclosure @escaping () -> Logger, __safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
				        let logger = LazilyInstantiated<Logger>(__safeDI_logger)
				        let __safeDI_apiBuilder_detail = __safeDI_apiBuilder.detail(logger)
				        func __safeDI_readerBuilder() -> Reader {
				            Reader(logger: logger.instance)
				        }
				        func __safeDI_detail() -> Detail {
				            let readerBuilder = Instantiator<Reader>(__safeDI_readerBuilder)
				            let api: any Api = __safeDI_apiBuilder_detail.api(readerBuilder)
				            return Detail(api: api, readerBuilder: readerBuilder)
				        }
				        let detail: Detail = __safeDI_detail()
				        self.init(detail: detail)
				    }
				}

				extension Inner {
				    public enum __safeDI_Inner_0E42011CE0D78A8C {}
				}

				extension Outer {
				    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
				        public let inner: Inner.__safeDI_ApiCarrier<__safeDI_Built>

				        public init(inner: Inner.__safeDI_ApiCarrier<__safeDI_Built>) {
				            self.inner = inner
				        }

				        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				            self.init(inner: .init(__safeDI_noScope: __safeDI_builder))
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
				        func __safeDI_logger() -> Logger {
				            Logger()
				        }
				        let logger = LazilyInstantiated<Logger>(__safeDI_logger)
				        func __safeDI_inner() -> Inner {
				            _ = Inner.__safeDI_Inner_0E42011CE0D78A8C.self
				            return Inner(__safeDI_logger: logger.instance, __safeDI_apiBuilder: __safeDI_apiBuilder.inner)
				        }
				        let inner: Inner = __safeDI_inner()
				        self.init(logger: logger, inner: inner)
				    }
				}

				extension Outer {
				    public enum __safeDI_Outer_596630904AB994DF {}
				}
				"""],
			],
			inline: Self.passedUpLazyLoggerModules(liveApiInFeature: true),
			// `Logger` is stamped, so the comparison sees when the logger is created as well as which one is read.
			probes: [DifferentialValueProbe("Root()")],
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
				        func __safeDI_apiBuilder_Outer() -> Outer.__safeDI_ApiCarrier<any Api> {
				            .init(inner: __safeDI_apiBuilder_Inner())
				        }
				        func __safeDI_apiBuilder_Inner() -> Inner.__safeDI_ApiCarrier<any Api> {
				            .init(api: {
				                let api: any Api = LiveApi()
				                return api
				            })
				        }
				        func __safeDI_outer() -> Outer {
				            _ = Outer.__safeDI_Outer_BED03DDA7301F4EB.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return Outer(__safeDI_apiBuilder: __safeDI_apiBuilder_Outer())
				        }
				        let outer: Outer = __safeDI_outer()
				        self.init(outer: outer)
				    }
				}
				"""],
				"Feature": ["Feature.swift": """
				extension Inner {
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

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
				        let api: any Api = __safeDI_apiBuilder.api()
				        self.init(api: api)
				    }
				}

				extension Inner {
				    public enum __safeDI_Inner_41C26D1D60F916DF {}
				}
				"""],
				"Middle": ["Middle.swift": """
				#if canImport(Feature)
				import Feature
				#endif

				extension Outer {
				    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
				        public let inner: Inner.__safeDI_ApiCarrier<__safeDI_Built>

				        public init(inner: Inner.__safeDI_ApiCarrier<__safeDI_Built>) {
				            self.inner = inner
				        }

				        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				            self.init(inner: .init(__safeDI_noScope: __safeDI_builder))
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
				        func __safeDI_inner() -> Inner {
				            _ = Inner.__safeDI_Inner_41C26D1D60F916DF.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return Inner(__safeDI_apiBuilder: __safeDI_apiBuilder.inner)
				        }
				        let inner: Inner = __safeDI_inner()
				        self.init(inner: inner)
				    }
				}

				extension Outer {
				    public enum __safeDI_Outer_BED03DDA7301F4EB {}
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
				        @Sendable nonisolated func __safeDI_apiSendableBuilder_Outer() -> Outer.__safeDI_ApiSendableCarrier<any Api> {
				            .init(innerBuilder: { __safeDI_apiBuilder_Inner() })
				        }
				        @Sendable nonisolated func __safeDI_apiBuilder_Inner() -> Inner.__safeDI_ApiCarrier<any Api> {
				            .init(api: {
				                let api: any Api = LiveApi()
				                return api
				            })
				        }
				        func __safeDI_outer() -> Outer {
				            _ = Outer.__safeDI_Outer_3DAAD0B15EB1B508.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return Outer(__safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_Outer())
				        }
				        let outer: Outer = __safeDI_outer()
				        self.init(outer: outer)
				    }
				}
				"""],
				"Feature": ["Feature.swift": """
				extension Inner {
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

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
				        let api: any Api = __safeDI_apiBuilder.api()
				        self.init(api: api)
				    }
				}

				extension Inner {
				    public enum __safeDI_Inner_41C26D1D60F916DF {}
				}
				"""],
				"Middle": ["Middle.swift": """
				#if canImport(Feature)
				import Feature
				#endif

				extension Outer {
				    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				    nonisolated public final class __safeDI_ApiSendableCarrier<__safeDI_Built>: Sendable {
				        public let innerBuilder: @Sendable () -> Inner.__safeDI_ApiCarrier<__safeDI_Built>

				        public init(innerBuilder: @escaping @Sendable () -> Inner.__safeDI_ApiCarrier<__safeDI_Built>) {
				            self.innerBuilder = innerBuilder
				        }

				        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
				            self.init(innerBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public init(__safeDI_apiSendableBuilder: __safeDI_ApiSendableCarrier<any Api>) {
				        @Sendable nonisolated func __safeDI_innerBuilder() -> Inner {
				            _ = Inner.__safeDI_Inner_41C26D1D60F916DF.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return Inner(__safeDI_apiBuilder: __safeDI_apiSendableBuilder.innerBuilder())
				        }
				        let innerBuilder = SendableInstantiator<Inner>(__safeDI_innerBuilder)
				        self.init(innerBuilder: innerBuilder)
				    }
				}

				extension Outer {
				    public enum __safeDI_Outer_3DAAD0B15EB1B508 {}
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
				        func __safeDI_apiBuilder_Top() -> Top.__safeDI_ApiCarrier<any Api> {
				            .init(outer: __safeDI_apiBuilder_Outer())
				        }
				        func __safeDI_apiBuilder_Outer() -> Outer.__safeDI_ApiCarrier<any Api> {
				            .init(inner: __safeDI_apiBuilder_Inner())
				        }
				        func __safeDI_apiBuilder_Inner() -> Inner.__safeDI_ApiCarrier<any Api> {
				            .init(api: {
				                let api: any Api = LiveApi()
				                return api
				            })
				        }
				        func __safeDI_top() -> Top {
				            _ = Top.__safeDI_Top_30457C7A3385D6DB.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return Top(__safeDI_apiBuilder: __safeDI_apiBuilder_Top())
				        }
				        let top: Top = __safeDI_top()
				        self.init(top: top)
				    }
				}
				"""],
				"Feature": ["Feature.swift": """
				extension Inner {
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

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
				        let api: any Api = __safeDI_apiBuilder.api()
				        self.init(api: api)
				    }
				}

				extension Inner {
				    public enum __safeDI_Inner_41C26D1D60F916DF {}
				}
				"""],
				"Middle": ["Middle.swift": """
				#if canImport(Feature)
				import Feature
				#endif

				extension Outer {
				    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
				        public let inner: Inner.__safeDI_ApiCarrier<__safeDI_Built>

				        public init(inner: Inner.__safeDI_ApiCarrier<__safeDI_Built>) {
				            self.inner = inner
				        }

				        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				            self.init(inner: .init(__safeDI_noScope: __safeDI_builder))
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
				        func __safeDI_inner() -> Inner {
				            _ = Inner.__safeDI_Inner_41C26D1D60F916DF.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return Inner(__safeDI_apiBuilder: __safeDI_apiBuilder.inner)
				        }
				        let inner: Inner = __safeDI_inner()
				        self.init(inner: inner)
				    }
				}

				extension Outer {
				    public enum __safeDI_Outer_BED03DDA7301F4EB {}
				}

				extension Top {
				    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
				        public let outer: Outer.__safeDI_ApiCarrier<__safeDI_Built>

				        public init(outer: Outer.__safeDI_ApiCarrier<__safeDI_Built>) {
				            self.outer = outer
				        }

				        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				            self.init(outer: .init(__safeDI_noScope: __safeDI_builder))
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
				        func __safeDI_outer() -> Outer {
				            _ = Outer.__safeDI_Outer_BED03DDA7301F4EB.self
				            return Outer(__safeDI_apiBuilder: __safeDI_apiBuilder.outer)
				        }
				        let outer: Outer = __safeDI_outer()
				        self.init(outer: outer)
				    }
				}

				extension Top {
				    public enum __safeDI_Top_30457C7A3385D6DB {}
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
				        func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
				            .init(
				                api: { scope_screenBuilder in
				                    let api: any Api = LiveApi()
				                    return api
				                },
				                screenBuilder: { __safeDI_apiBuilder_Home_Screen_Scope() }
				            )
				        }
				        func __safeDI_apiBuilder_Home_Screen_Scope() -> Home.__safeDI_ApiCarrier_Screen<any Api> {
				            .init(homeBuilder: { __safeDI_apiBuilder_Home() })
				        }
				        func __safeDI_home() -> Home {
				            _ = Home.__safeDI_Home_6F48405E060C16E3.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
				        }
				        let home: Home = __safeDI_home()
				        self.init(home: home)
				    }
				}
				"""],
				"Feature": ["Feature.swift": """
				extension Home {
				    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
				        public let api: (Instantiator<Screen>) -> __safeDI_Built
				        public let screenBuilder: () -> __safeDI_ApiCarrier_Screen<__safeDI_Built>

				        public init(api: @escaping (Instantiator<Screen>) -> __safeDI_Built, screenBuilder: @escaping () -> __safeDI_ApiCarrier_Screen<__safeDI_Built>) {
				            self.api = api
				            self.screenBuilder = screenBuilder
				        }

				        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				            self.init(api: { _ in __safeDI_builder() }, screenBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
				        }
				    }

				    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				    nonisolated public final class __safeDI_ApiCarrier_Screen<__safeDI_Built> {
				        public let homeBuilder: () -> Home.__safeDI_ApiCarrier<__safeDI_Built>

				        public init(homeBuilder: @escaping () -> Home.__safeDI_ApiCarrier<__safeDI_Built>) {
				            self.homeBuilder = homeBuilder
				        }

				        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				            self.init(homeBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
				        let __safeDI_apiBuilder_screenBuilder = __safeDI_apiBuilder.screenBuilder()
				        func __safeDI_screenBuilder() -> Screen {
				            func __safeDI_homeBuilder() -> Home {
				                _ = Home.__safeDI_Home_6F48405E060C16E3.self
				                return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_screenBuilder.homeBuilder())
				            }
				            let homeBuilder = Instantiator<Home>(__safeDI_homeBuilder)
				            return Screen(homeBuilder: homeBuilder)
				        }
				        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
				        let api: any Api = __safeDI_apiBuilder.api(screenBuilder)
				        self.init(api: api, screenBuilder: screenBuilder)
				    }
				}

				extension Home {
				    public enum __safeDI_Home_6F48405E060C16E3 {}
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
				        func __safeDI_gadgetBuilder_Outer_Inner(tag: Tag) -> Inner.__safeDI_ServiceCarrier<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
				            .init(service: { __safeDI_gadgetBuilder_Outer_DefaultService_Scope(tag: tag) })
				        }
				        func __safeDI_outer() -> Outer {
				            _ = Outer.__safeDI_Outer_EEABCDCA5EBD0A25.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return Outer(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Outer())
				        }
				        let outer: Outer = __safeDI_outer()
				        self.init(outer: outer)
				    }
				}
				"""],
				"Feature": ["Feature.swift": """
				extension Inner {
				    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
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
				        let service: any Service = __safeDI_serviceBuilder.service()
				        self.init(service: service)
				    }
				}

				extension Inner {
				    public enum __safeDI_Inner_99BD917DA5EDFC3D {}
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
				    public convenience init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
				        let tag = Tag()
				        let __safeDI_gadgetBuilder_inner_serviceBuilder = __safeDI_gadgetBuilder.inner_serviceBuilder(SafeDIScope_Gadget.inner_serviceBuilder_Values(tag: tag))
				        func __safeDI_inner() -> Inner {
				            _ = Inner.__safeDI_Inner_99BD917DA5EDFC3D.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            func __safeDI_serviceBuilder_Inner_service(__safeDI_inner_serviceBuilder: SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
				                func __safeDI_service() -> DefaultService {
				                    let logger = Logger()
				                    let gadget: any Gadget = __safeDI_inner_serviceBuilder.gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values(logger: logger))
				                    return DefaultService(logger: logger, gadget: gadget)
				                }
				                let service: any Service = __safeDI_service()
				                return service
				            }
				            func __safeDI_serviceBuilder_Inner(up: Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_ServiceCarrier<any Service> {
				                .init(service: { __safeDI_serviceBuilder_Inner_service(__safeDI_inner_serviceBuilder: up.service()) })
				            }
				            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner(up: __safeDI_gadgetBuilder_inner_serviceBuilder))
				        }
				        let inner: Inner = __safeDI_inner()
				        self.init(tag: tag, inner: inner)
				    }
				}

				extension Outer {
				    public enum __safeDI_Outer_EEABCDCA5EBD0A25 {}
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
				        @Sendable nonisolated func __safeDI_gadgetBuilder_Outer_Inner() -> Inner.__safeDI_ServiceCarrier<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
				            .init(service: { __safeDI_gadgetBuilder_Outer_DefaultService_Scope() })
				        }
				        func __safeDI_outer() -> Outer {
				            _ = Outer.__safeDI_Outer_2EC1B83F167BADED.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return Outer(__safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_Outer())
				        }
				        let outer: Outer = __safeDI_outer()
				        self.init(outer: outer)
				    }
				}
				"""],
				"Feature": ["Feature.swift": """
				extension Inner {
				    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
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
				        let service: any Service = __safeDI_serviceBuilder.service()
				        self.init(service: service)
				    }
				}

				extension Inner {
				    public enum __safeDI_Inner_99BD917DA5EDFC3D {}
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
				                    self.init(gadget: { _ in __safeDI_builder() })
				                }
				            }
				        }
				    }

				    nonisolated public enum SafeDISendableScope_Gadget {
				        nonisolated public struct innerBuilder_serviceBuilder_Values: Sendable {}

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
				            public let innerBuilder_serviceBuilder: @Sendable (innerBuilder_serviceBuilder_Values) -> Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

				            public init(innerBuilder_serviceBuilder: @escaping @Sendable (innerBuilder_serviceBuilder_Values) -> Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
				                self.innerBuilder_serviceBuilder = innerBuilder_serviceBuilder
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
				                self.init(innerBuilder_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
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
				            _ = Inner.__safeDI_Inner_99BD917DA5EDFC3D.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            func __safeDI_serviceBuilder_Inner_service(__safeDI_innerBuilder_serviceBuilder: SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
				                func __safeDI_service() -> DefaultService {
				                    let logger = Logger()
				                    let gadget: any Gadget = __safeDI_innerBuilder_serviceBuilder.gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values(logger: logger))
				                    return DefaultService(logger: logger, gadget: gadget)
				                }
				                let service: any Service = __safeDI_service()
				                return service
				            }
				            func __safeDI_serviceBuilder_Inner(up: Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_ServiceCarrier<any Service> {
				                .init(service: { __safeDI_serviceBuilder_Inner_service(__safeDI_innerBuilder_serviceBuilder: up.service()) })
				            }
				            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner(up: __safeDI_gadgetSendableBuilder_innerBuilder_serviceBuilder))
				        }
				        let innerBuilder = SendableInstantiator<Inner>(__safeDI_innerBuilder)
				        self.init(tag: tag, innerBuilder: innerBuilder)
				    }
				}

				extension Outer {
				    public enum __safeDI_Outer_2EC1B83F167BADED {}
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
				        func __safeDI_gadgetBuilder_Outer() -> Outer.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
				            .init(inner_serviceBuilder: { values in __safeDI_gadgetBuilder_Outer_Inner(tag: values.tag) })
				        }
				        func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(logger: Logger, tag: Tag) -> Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
				            .init(gadget: { _ in
				                let gadget: any Gadget = LiveGadget(tag: tag, logger: logger)
				                return gadget
				            })
				        }
				        func __safeDI_gadgetBuilder_Outer_Inner(tag: Tag) -> Inner.__safeDI_ServiceCarrier<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
				            .init(innermost: __safeDI_gadgetBuilder_Outer_Innermost(tag: tag))
				        }
				        func __safeDI_gadgetBuilder_Outer_Innermost(tag: Tag) -> Innermost.__safeDI_ServiceCarrier<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
				            .init(detailBuilder: { values_logger in __safeDI_gadgetBuilder_Outer_Innermost_Detail_Scope(logger: values_logger, tag: tag) })
				        }
				        func __safeDI_gadgetBuilder_Outer_Innermost_Detail_Scope(logger: Logger, tag: Tag) -> Innermost.__safeDI_ServiceCarrier_Detail<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
				            .init(service: { __safeDI_gadgetBuilder_Outer_DefaultService_Scope(logger: logger, tag: tag) })
				        }
				        func __safeDI_outer() -> Outer {
				            _ = Outer.__safeDI_Outer_1058A0A102D4F575.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return Outer(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Outer())
				        }
				        let outer: Outer = __safeDI_outer()
				        self.init(outer: outer)
				    }
				}
				"""],
				"Feature": ["Feature.swift": """
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
				        func __safeDI_innermost() -> Innermost {
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
				        func __safeDI_detailBuilder() -> Detail {
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
				    public convenience init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
				        let tag = Tag()
				        let __safeDI_gadgetBuilder_inner_serviceBuilder = __safeDI_gadgetBuilder.inner_serviceBuilder(SafeDIScope_Gadget.inner_serviceBuilder_Values(tag: tag))
				        func __safeDI_inner() -> Inner {
				            _ = Inner.__safeDI_Inner_6B37CE7AAF7A1362.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            func __safeDI_serviceBuilder_Innermost_Detail_Scope_service(logger: Logger, __safeDI_inner_serviceBuilder: SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
				                func __safeDI_service() -> DefaultService {
				                    let gadget: any Gadget = __safeDI_inner_serviceBuilder.gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values())
				                    return DefaultService(logger: logger, gadget: gadget)
				                }
				                let service: any Service = __safeDI_service()
				                return service
				            }
				            func __safeDI_serviceBuilder_Inner(up: Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_ServiceCarrier<any Service> {
				                .init(innermost: __safeDI_serviceBuilder_Innermost(up: up.innermost))
				            }
				            func __safeDI_serviceBuilder_Innermost(up: Innermost.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Innermost.__safeDI_ServiceCarrier<any Service> {
				                .init(detailBuilder: { values_logger in __safeDI_serviceBuilder_Innermost_Detail_Scope(up: up.detailBuilder(values_logger), logger: values_logger) })
				            }
				            func __safeDI_serviceBuilder_Innermost_Detail_Scope(up: Innermost.__safeDI_ServiceCarrier_Detail<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>, logger: Logger) -> Innermost.__safeDI_ServiceCarrier_Detail<any Service> {
				                .init(service: { __safeDI_serviceBuilder_Innermost_Detail_Scope_service(logger: logger, __safeDI_inner_serviceBuilder: up.service()) })
				            }
				            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner(up: __safeDI_gadgetBuilder_inner_serviceBuilder))
				        }
				        let inner: Inner = __safeDI_inner()
				        self.init(tag: tag, inner: inner)
				    }
				}

				extension Outer {
				    public enum __safeDI_Outer_1058A0A102D4F575 {}
				}
				"""],
			],
			inline: Self.deepModules(fulfillersInFeature: true),
			probes: [DifferentialValueProbe("{ let outer = Root().outer; let innermost = outer.inner.innermost; let first = innermost.detailBuilder.instantiate(); let second = innermost.detailBuilder.instantiate(); let service = first.service as! DefaultService; let gadget = service.gadget as! LiveGadget; return [service.logger === innermost.logger, gadget.tag === outer.tag, gadget.logger === innermost.logger, first.service !== second.service] }()")],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_carriesInnerSeamsStructPerHoleType_whenFillOfInnerSeamsHoleHoldsPlacesOfTwoHoleTypes() async throws {
		try await expectOutput(
			of: Self.carriedModules(holdsWidget: true),
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
				        func __safeDI_widgetBuilder_Outer() -> Outer.SafeDIScope_Widget.__safeDI_Builder<any Widget> {
				            .init(inner_serviceBuilder: { values in __safeDI_widgetBuilder_Outer_Inner(tag: values.tag) })
				        }
				        func __safeDI_widgetBuilder_Outer_DefaultService_Scope(tag: Tag) -> Outer.SafeDIScope_Widget.DefaultService_Scope.__safeDI_Builder<any Widget> {
				            .init(widget: { scope in
				                let logger = scope.logger
				                let widget: any Widget = LiveWidget(tag: tag, logger: logger)
				                return widget
				            })
				        }
				        func __safeDI_gadgetBuilder_Outer_Inner(tag: Tag) -> Inner.__safeDI_ServiceCarrier<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
				            .init(service: { __safeDI_gadgetBuilder_Outer_DefaultService_Scope(tag: tag) })
				        }
				        func __safeDI_widgetBuilder_Outer_Inner(tag: Tag) -> Inner.__safeDI_ServiceCarrier<Outer.SafeDIScope_Widget.DefaultService_Scope.__safeDI_Builder<any Widget>> {
				            .init(service: { __safeDI_widgetBuilder_Outer_DefaultService_Scope(tag: tag) })
				        }
				        func __safeDI_outer() -> Outer {
				            _ = Outer.__safeDI_Outer_F67A34659D4062C5.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return Outer(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Outer(), __safeDI_widgetBuilder: __safeDI_widgetBuilder_Outer())
				        }
				        let outer: Outer = __safeDI_outer()
				        self.init(outer: outer)
				    }
				}
				"""],
				"Feature": ["Feature.swift": """
				extension Inner {
				    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
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
				        let service: any Service = __safeDI_serviceBuilder.service()
				        self.init(service: service)
				    }
				}

				extension Inner {
				    public enum __safeDI_Inner_99BD917DA5EDFC3D {}
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

				    // SafeDI counts `Gadget` and `Widget` as `public`: no module it reads declares them narrower. If one is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
				    nonisolated public enum SafeDIScope_Widget {
				        nonisolated public struct inner_serviceBuilder_Values {
				            public let tag: Tag
				        }

				        nonisolated public enum DefaultService_Scope {
				            nonisolated public struct widget_Values {
				                public let logger: Logger
				                public let gadget: any Gadget
				            }

				            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				                public let widget: (widget_Values) -> __safeDI_Built

				                public init(widget: @escaping (widget_Values) -> __safeDI_Built) {
				                    self.widget = widget
				                }

				                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                    self.init(widget: { _ in __safeDI_builder() })
				                }
				            }
				        }

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let inner_serviceBuilder: (inner_serviceBuilder_Values) -> Inner.__safeDI_ServiceCarrier<SafeDIScope_Widget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

				            public init(inner_serviceBuilder: @escaping (inner_serviceBuilder_Values) -> Inner.__safeDI_ServiceCarrier<SafeDIScope_Widget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
				                self.inner_serviceBuilder = inner_serviceBuilder
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.init(inner_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
				            }
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>, __safeDI_widgetBuilder: SafeDIScope_Widget.__safeDI_Builder<any Widget>) {
				        let tag = Tag()
				        let __safeDI_gadgetBuilder_inner_serviceBuilder = __safeDI_gadgetBuilder.inner_serviceBuilder(SafeDIScope_Gadget.inner_serviceBuilder_Values(tag: tag))
				        let __safeDI_widgetBuilder_inner_serviceBuilder = __safeDI_widgetBuilder.inner_serviceBuilder(SafeDIScope_Widget.inner_serviceBuilder_Values(tag: tag))
				        func __safeDI_inner() -> Inner {
				            _ = Inner.__safeDI_Inner_99BD917DA5EDFC3D.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            func __safeDI_serviceBuilder_Inner_service(__safeDI_inner_serviceBuilder_gadgetBuilder: SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>, __safeDI_inner_serviceBuilder_widgetBuilder: SafeDIScope_Widget.DefaultService_Scope.__safeDI_Builder<any Widget>) -> any Service {
				                func __safeDI_service() -> DefaultService {
				                    let logger = Logger()
				                    let gadget: any Gadget = __safeDI_inner_serviceBuilder_gadgetBuilder.gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values(logger: logger))
				                    let widget: any Widget = __safeDI_inner_serviceBuilder_widgetBuilder.widget(SafeDIScope_Widget.DefaultService_Scope.widget_Values(logger: logger, gadget: gadget))
				                    return DefaultService(logger: logger, gadget: gadget, widget: widget)
				                }
				                let service: any Service = __safeDI_service()
				                return service
				            }
				            func __safeDI_serviceBuilder_Inner(up_inner_serviceBuilder_gadgetBuilder: Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>, up_inner_serviceBuilder_widgetBuilder: Inner.__safeDI_ServiceCarrier<SafeDIScope_Widget.DefaultService_Scope.__safeDI_Builder<any Widget>>) -> Inner.__safeDI_ServiceCarrier<any Service> {
				                .init(service: { __safeDI_serviceBuilder_Inner_service(__safeDI_inner_serviceBuilder_gadgetBuilder: up_inner_serviceBuilder_gadgetBuilder.service(), __safeDI_inner_serviceBuilder_widgetBuilder: up_inner_serviceBuilder_widgetBuilder.service()) })
				            }
				            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner(up_inner_serviceBuilder_gadgetBuilder: __safeDI_gadgetBuilder_inner_serviceBuilder, up_inner_serviceBuilder_widgetBuilder: __safeDI_widgetBuilder_inner_serviceBuilder))
				        }
				        let inner: Inner = __safeDI_inner()
				        self.init(tag: tag, inner: inner)
				    }
				}

				extension Outer {
				    public enum __safeDI_Outer_F67A34659D4062C5 {}
				}
				"""],
			],
			inline: Self.carriedModules(fulfillersInFeature: true, holdsWidget: true),
			probes: [DifferentialValueProbe("{ let outer = Root().outer; let service = outer.inner.service as! DefaultService; let gadget = service.gadget as! LiveGadget; let widget = service.widget as! LiveWidget; return [gadget.tag === outer.tag, gadget.logger === service.logger, widget.tag === outer.tag, widget.logger === service.logger] }()")],
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
				        func __safeDI_gadgetBuilder_Feature() -> Feature.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
				            .init(inner_serviceBuilder: { _ in __safeDI_gadgetBuilder_GadgetSeam_Inner() })
				        }
				        func __safeDI_gadgetBuilder_GadgetSeam() -> GadgetSeam.__safeDI_GadgetCarrier<any Gadget> {
				            .init(gadget: {
				                let gadget: any Gadget = LiveGadget()
				                return gadget
				            })
				        }
				        func __safeDI_gadgetBuilder_GadgetSeam_Inner() -> Inner.__safeDI_ServiceCarrier<GadgetSeam.__safeDI_GadgetCarrier<any Gadget>> {
				            .init(service: { __safeDI_gadgetBuilder_GadgetSeam() })
				        }
				        func __safeDI_feature() -> Feature {
				            _ = Feature.__safeDI_Feature_A4111B92CE60BA82.self // If this line does not compile, compile the code SafeDI generates for module Mid into Mid: under Bazel, add Mid’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
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
				            public let inner_serviceBuilder: (inner_serviceBuilder_Values) -> Inner.__safeDI_ServiceCarrier<GadgetSeam.__safeDI_GadgetCarrier<__safeDI_Built>>

				            public init(inner_serviceBuilder: @escaping (inner_serviceBuilder_Values) -> Inner.__safeDI_ServiceCarrier<GadgetSeam.__safeDI_GadgetCarrier<__safeDI_Built>>) {
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
				    public convenience init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
				        let __safeDI_gadgetBuilder_inner_serviceBuilder = __safeDI_gadgetBuilder.inner_serviceBuilder(SafeDIScope_Gadget.inner_serviceBuilder_Values())
				        func __safeDI_inner() -> Inner {
				            _ = Inner.__safeDI_Inner_99BD917DA5EDFC3D.self // If this line does not compile, compile the code SafeDI generates for module Up into Up: under Bazel, add Up’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            func __safeDI_serviceBuilder_Inner_service(__safeDI_inner_serviceBuilder: GadgetSeam.__safeDI_GadgetCarrier<any Gadget>) -> any Service {
				                func __safeDI_service() -> GadgetSeam {
				                    _ = GadgetSeam.__safeDI_GadgetSeam_09F393EA155A8685.self
				                    return GadgetSeam(__safeDI_gadgetBuilder: __safeDI_inner_serviceBuilder)
				                }
				                let service: any Service = __safeDI_service()
				                return service
				            }
				            func __safeDI_serviceBuilder_Inner(up: Inner.__safeDI_ServiceCarrier<GadgetSeam.__safeDI_GadgetCarrier<any Gadget>>) -> Inner.__safeDI_ServiceCarrier<any Service> {
				                .init(service: { __safeDI_serviceBuilder_Inner_service(__safeDI_inner_serviceBuilder: up.service()) })
				            }
				            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner(up: __safeDI_gadgetBuilder_inner_serviceBuilder))
				        }
				        let inner: Inner = __safeDI_inner()
				        self.init(inner: inner)
				    }
				}

				extension Feature {
				    public enum __safeDI_Feature_A4111B92CE60BA82 {}
				}

				extension GadgetSeam {
				    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				    nonisolated public final class __safeDI_GadgetCarrier<__safeDI_Built> {
				        public let gadget: () -> __safeDI_Built

				        public init(gadget: @escaping () -> __safeDI_Built) {
				            self.gadget = gadget
				        }

				        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				            self.init(gadget: { __safeDI_builder() })
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_gadgetBuilder: __safeDI_GadgetCarrier<any Gadget>) {
				        let gadget: any Gadget = __safeDI_gadgetBuilder.gadget()
				        self.init(gadget: gadget)
				    }
				}

				extension GadgetSeam {
				    public enum __safeDI_GadgetSeam_09F393EA155A8685 {}
				}
				"""],
				"Up": ["Up.swift": """
				extension Inner {
				    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
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
				        let service: any Service = __safeDI_serviceBuilder.service()
				        self.init(service: service)
				    }
				}

				extension Inner {
				    public enum __safeDI_Inner_99BD917DA5EDFC3D {}
				}
				"""],
			],
			inline: Self.fulfillingSeamModules(liveGadgetInMid: true),
			probes: [DifferentialValueProbe("{ let feature = Root().feature; let service = feature.inner.service as! GadgetSeam; return service.gadget is LiveGadget }()")],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsFulfillingSeamItsSendableStruct_whenFulfillingSeamsHoleIsHeldInSendableWrapper() async throws {
		try await expectOutput(
			of: Self.fulfillingSeamModules(gadgetPlace: "sendableWrapper"),
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
				            _ = Feature.__safeDI_Feature_5C1A0D75D74A217D.self // If this line does not compile, compile the code SafeDI generates for module Mid into Mid: under Bazel, add Mid’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            @Sendable nonisolated func __safeDI_gadgetSendableBuilder_GadgetSeam_gadget() -> any Gadget {
				                @Sendable nonisolated func __safeDI_gadget() -> LiveGadget {
				                    LiveGadget()
				                }
				                return __safeDI_gadget()
				            }
				            @Sendable nonisolated func __safeDI_gadgetSendableBuilder_Feature() -> Feature.SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget> {
				                .init(inner_serviceBuilder_Sendable: { _ in __safeDI_gadgetSendableBuilder_GadgetSeam() })
				            }
				            @Sendable nonisolated func __safeDI_gadgetSendableBuilder_GadgetSeam() -> GadgetSeam.__safeDI_GadgetSendableCarrier<any Gadget> {
				                .init(gadget: { __safeDI_gadgetSendableBuilder_GadgetSeam_gadget() })
				            }
				            return Feature(__safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_Feature())
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
				    nonisolated public enum SafeDISendableScope_Gadget {
				        nonisolated public struct inner_serviceBuilder_Sendable_Values: Sendable {}

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
				            public let inner_serviceBuilder_Sendable: @Sendable (inner_serviceBuilder_Sendable_Values) -> GadgetSeam.__safeDI_GadgetSendableCarrier<__safeDI_Built>

				            public init(inner_serviceBuilder_Sendable: @escaping @Sendable (inner_serviceBuilder_Sendable_Values) -> GadgetSeam.__safeDI_GadgetSendableCarrier<__safeDI_Built>) {
				                self.inner_serviceBuilder_Sendable = inner_serviceBuilder_Sendable
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
				                self.init(inner_serviceBuilder_Sendable: { _ in .init(__safeDI_noScope: __safeDI_builder) })
				            }
				        }
				    }

				    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_gadgetSendableBuilder: SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget>) {
				        let __safeDI_gadgetSendableBuilder_inner_serviceBuilder_Sendable = __safeDI_gadgetSendableBuilder.inner_serviceBuilder_Sendable(SafeDISendableScope_Gadget.inner_serviceBuilder_Sendable_Values())
				        func __safeDI_inner() -> Inner {
				            _ = Inner.__safeDI_Inner_99BD917DA5EDFC3D.self // If this line does not compile, compile the code SafeDI generates for module Up into Up: under Bazel, add Up’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            func __safeDI_serviceBuilder_Inner_service() -> any Service {
				                func __safeDI_service() -> GadgetSeam {
				                    _ = GadgetSeam.__safeDI_GadgetSeam_A69ACCD78B556826.self
				                    return GadgetSeam(__safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_inner_serviceBuilder_Sendable)
				                }
				                let service: any Service = __safeDI_service()
				                return service
				            }
				            func __safeDI_serviceBuilder_Inner() -> Inner.__safeDI_ServiceCarrier<any Service> {
				                .init(service: { __safeDI_serviceBuilder_Inner_service() })
				            }
				            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner())
				        }
				        let inner: Inner = __safeDI_inner()
				        self.init(inner: inner)
				    }
				}

				extension Feature {
				    public enum __safeDI_Feature_5C1A0D75D74A217D {}
				}

				extension GadgetSeam {
				    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				    nonisolated public final class __safeDI_GadgetSendableCarrier<__safeDI_Built>: Sendable {
				        public let gadget: @Sendable () -> __safeDI_Built

				        public init(gadget: @escaping @Sendable () -> __safeDI_Built) {
				            self.gadget = gadget
				        }

				        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
				            self.init(gadget: { __safeDI_builder() })
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_gadgetSendableBuilder: __safeDI_GadgetSendableCarrier<any Gadget>) {
				        @Sendable nonisolated func __safeDI_gadget() -> any Gadget {
				            __safeDI_gadgetSendableBuilder.gadget()
				        }
				        let gadget = SendableLazilyInstantiated<any Gadget>(__safeDI_gadget)
				        self.init(gadget: gadget)
				    }
				}

				extension GadgetSeam {
				    public enum __safeDI_GadgetSeam_A69ACCD78B556826 {}
				}
				"""],
				"Up": ["Up.swift": """
				extension Inner {
				    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
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
				        let service: any Service = __safeDI_serviceBuilder.service()
				        self.init(service: service)
				    }
				}

				extension Inner {
				    public enum __safeDI_Inner_99BD917DA5EDFC3D {}
				}
				"""],
			],
			inline: Self.fulfillingSeamModules(liveGadgetInMid: true, gadgetPlace: "sendableWrapper"),
			probes: [DifferentialValueProbe("Root()")],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsFulfillingSeamItsStruct_whenFulfillingSeamIsBuiltInSendableFill() async throws {
		try await expectOutput(
			of: Self.fulfillingSeamModules(gadgetPlace: "sendableFill"),
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
				        @Sendable nonisolated func __safeDI_gadgetSendableBuilder_Feature() -> Feature.SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget> {
				            .init(inner_serviceSendableBuilder: { _ in __safeDI_gadgetBuilder_GadgetSeam() })
				        }
				        @Sendable nonisolated func __safeDI_gadgetBuilder_GadgetSeam() -> GadgetSeam.__safeDI_GadgetCarrier<any Gadget> {
				            .init(gadget: {
				                let gadget: any Gadget = LiveGadget()
				                return gadget
				            })
				        }
				        func __safeDI_feature() -> Feature {
				            _ = Feature.__safeDI_Feature_1C1E099801D33DF1.self // If this line does not compile, compile the code SafeDI generates for module Mid into Mid: under Bazel, add Mid’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return Feature(__safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_Feature())
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
				    nonisolated public enum SafeDISendableScope_Gadget {
				        nonisolated public struct inner_serviceSendableBuilder_Values: Sendable {}

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
				            public let inner_serviceSendableBuilder: @Sendable (inner_serviceSendableBuilder_Values) -> GadgetSeam.__safeDI_GadgetCarrier<__safeDI_Built>

				            public init(inner_serviceSendableBuilder: @escaping @Sendable (inner_serviceSendableBuilder_Values) -> GadgetSeam.__safeDI_GadgetCarrier<__safeDI_Built>) {
				                self.inner_serviceSendableBuilder = inner_serviceSendableBuilder
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
				                self.init(inner_serviceSendableBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
				            }
				        }
				    }

				    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_gadgetSendableBuilder: SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget>) {
				        func __safeDI_inner() -> Inner {
				            _ = Inner.__safeDI_Inner_A122B03294DB720B.self // If this line does not compile, compile the code SafeDI generates for module Up into Up: under Bazel, add Up’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            @Sendable nonisolated func __safeDI_serviceSendableBuilder_Inner_service() -> any Service {
				                @Sendable nonisolated func __safeDI_service() -> GadgetSeam {
				                    let __safeDI_gadgetSendableBuilder_inner_serviceSendableBuilder = __safeDI_gadgetSendableBuilder.inner_serviceSendableBuilder(SafeDISendableScope_Gadget.inner_serviceSendableBuilder_Values())
				                    _ = GadgetSeam.__safeDI_GadgetSeam_09F393EA155A8685.self
				                    return GadgetSeam(__safeDI_gadgetBuilder: __safeDI_gadgetSendableBuilder_inner_serviceSendableBuilder)
				                }
				                return __safeDI_service()
				            }
				            @Sendable nonisolated func __safeDI_serviceSendableBuilder_Inner() -> Inner.__safeDI_ServiceSendableCarrier<any Service> {
				                .init(service: { __safeDI_serviceSendableBuilder_Inner_service() })
				            }
				            return Inner(__safeDI_serviceSendableBuilder: __safeDI_serviceSendableBuilder_Inner())
				        }
				        let inner: Inner = __safeDI_inner()
				        self.init(inner: inner)
				    }
				}

				extension Feature {
				    public enum __safeDI_Feature_1C1E099801D33DF1 {}
				}

				extension GadgetSeam {
				    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				    nonisolated public final class __safeDI_GadgetCarrier<__safeDI_Built> {
				        public let gadget: () -> __safeDI_Built

				        public init(gadget: @escaping () -> __safeDI_Built) {
				            self.gadget = gadget
				        }

				        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				            self.init(gadget: { __safeDI_builder() })
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_gadgetBuilder: __safeDI_GadgetCarrier<any Gadget>) {
				        let gadget: any Gadget = __safeDI_gadgetBuilder.gadget()
				        self.init(gadget: gadget)
				    }
				}

				extension GadgetSeam {
				    public enum __safeDI_GadgetSeam_09F393EA155A8685 {}
				}
				"""],
				"Up": ["Up.swift": """
				extension Inner {
				    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				    nonisolated public final class __safeDI_ServiceSendableCarrier<__safeDI_Built>: Sendable {
				        public let service: @Sendable () -> __safeDI_Built

				        public init(service: @escaping @Sendable () -> __safeDI_Built) {
				            self.service = service
				        }

				        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
				            self.init(service: { __safeDI_builder() })
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_serviceSendableBuilder: __safeDI_ServiceSendableCarrier<any Service>) {
				        @Sendable nonisolated func __safeDI_service() -> any Service {
				            __safeDI_serviceSendableBuilder.service()
				        }
				        let service = SendableLazilyInstantiated<any Service>(__safeDI_service)
				        self.init(service: service)
				    }
				}

				extension Inner {
				    public enum __safeDI_Inner_A122B03294DB720B {}
				}
				"""],
			],
			inline: Self.fulfillingSeamModules(liveGadgetInMid: true, gadgetPlace: "sendableFill"),
			probes: [DifferentialValueProbe("Root()")],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesCarriedStructApartFromLevelsValue_whenInnerSeamsLevelHoldsValueLabeledUp() async throws {
		// `Inner` binds `up` before `screenBuilder`, and the fill of `Screen`'s `service`, which `Outer` makes, reads it and
		// holds `Outer`'s place `gadget`. The level function for `Screen_Scope` on the carried route takes `Inner`'s `up`
		// beside the struct of its level, which takes another name: two parameters named `up` do not compile.
		try await expectOutput(
			of: Self.upLabelModules(liveGadgetInMiddle: false),
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
				        func __safeDI_gadgetBuilder_Outer() -> Outer.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
				            .init(inner_serviceBuilder: { values in __safeDI_gadgetBuilder_Outer_Inner(tag: values.tag) })
				        }
				        func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(tag: Tag) -> Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
				            .init(gadget: { _ in
				                let gadget: any Gadget = LiveGadget(tag: tag)
				                return gadget
				            })
				        }
				        func __safeDI_gadgetBuilder_Outer_Inner(tag: Tag) -> Inner.__safeDI_ServiceCarrier<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
				            .init(screenBuilder: { values_up in __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope(tag: tag) }, service: { values_up, values_screenBuilder in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(tag: tag) })
				        }
				        func __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope(tag: Tag) -> Inner.__safeDI_ServiceCarrier_Screen<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
				            .init(service: { values_id in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(tag: tag) })
				        }
				        func __safeDI_outer() -> Outer {
				            _ = Outer.__safeDI_Outer_44DBB836D87B51F4.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return Outer(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Outer())
				        }
				        let outer: Outer = __safeDI_outer()
				        self.init(outer: outer)
				    }
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
				        func __safeDI_inner() -> Inner {
				            _ = Inner.__safeDI_Inner_9DCB9CF5F4F9B43F.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            func __safeDI_serviceBuilder_Inner_service(_ scope_up: Up, _ scope_screenBuilder: Instantiator<Screen>, __safeDI_inner_serviceBuilder: SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
				                let up = scope_up
				                func __safeDI_service() -> DefaultService {
				                    let gadget: any Gadget = __safeDI_inner_serviceBuilder.gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values())
				                    return DefaultService(up: up, gadget: gadget)
				                }
				                let service: any Service = __safeDI_service()
				                return service
				            }
				            func __safeDI_serviceBuilder_Inner_Screen_Scope_service(_ scope_id: Int, up: Up, __safeDI_inner_serviceBuilder: SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
				                func __safeDI_service() -> DefaultService {
				                    let gadget: any Gadget = __safeDI_inner_serviceBuilder.gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values())
				                    return DefaultService(up: up, gadget: gadget)
				                }
				                let service: any Service = __safeDI_service()
				                return service
				            }
				            func __safeDI_serviceBuilder_Inner(up_: Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_ServiceCarrier<any Service> {
				                .init(screenBuilder: { values_up in __safeDI_serviceBuilder_Inner_Screen_Scope(up_: up_.screenBuilder(values_up), up: values_up) }, service: { scope_up, scope_screenBuilder in __safeDI_serviceBuilder_Inner_service(scope_up, scope_screenBuilder, __safeDI_inner_serviceBuilder: up_.service(scope_up, scope_screenBuilder)) })
				            }
				            func __safeDI_serviceBuilder_Inner_Screen_Scope(up_: Inner.__safeDI_ServiceCarrier_Screen<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>, up: Up) -> Inner.__safeDI_ServiceCarrier_Screen<any Service> {
				                .init(service: { scope_id in __safeDI_serviceBuilder_Inner_Screen_Scope_service(scope_id, up: up, __safeDI_inner_serviceBuilder: up_.service(scope_id)) })
				            }
				            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner(up_: __safeDI_gadgetBuilder_inner_serviceBuilder))
				        }
				        let inner: Inner = __safeDI_inner()
				        self.init(tag: tag, inner: inner)
				    }
				}

				extension Outer {
				    public enum __safeDI_Outer_44DBB836D87B51F4 {}
				}
				"""],
				"Feature": ["Feature.swift": """
				extension Inner {
				    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
				        public let screenBuilder: (Up) -> __safeDI_ServiceCarrier_Screen<__safeDI_Built>
				        public let service: (Up, Instantiator<Screen>) -> __safeDI_Built

				        public init(screenBuilder: @escaping (Up) -> __safeDI_ServiceCarrier_Screen<__safeDI_Built>, service: @escaping (Up, Instantiator<Screen>) -> __safeDI_Built) {
				            self.screenBuilder = screenBuilder
				            self.service = service
				        }

				        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				            self.init(screenBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) }, service: { _, _ in __safeDI_builder() })
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
				        let up = Up()
				        let __safeDI_serviceBuilder_screenBuilder = __safeDI_serviceBuilder.screenBuilder(up)
				        func __safeDI_screenBuilder(id: Int) -> Screen {
				            let service: any Service = __safeDI_serviceBuilder_screenBuilder.service(id)
				            return Screen(id: id, service: service)
				        }
				        let screenBuilder = Instantiator<Screen> {
				            __safeDI_screenBuilder(id: $0)
				        }
				        let service: any Service = __safeDI_serviceBuilder.service(up, screenBuilder)
				        self.init(up: up, screenBuilder: screenBuilder, service: service)
				    }
				}

				extension Inner {
				    public enum __safeDI_Inner_9DCB9CF5F4F9B43F {}
				}
				"""],
			],
			inline: Self.upLabelModules(liveGadgetInMiddle: true),
			probes: [DifferentialValueProbe("Root()")],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsFulfillingSeamItsSendableStruct_whenFulfillingSeamsHoleIsBeneathSendableBuilder() async throws {
		try await expectOutput(
			of: Self.fulfillingSeamModules(gadgetPlace: "sendableBuilder"),
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
				        @Sendable nonisolated func __safeDI_gadgetSendableBuilder_Feature() -> Feature.SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget> {
				            .init(inner_serviceBuilder_Sendable: { _ in __safeDI_gadgetSendableBuilder_GadgetSeam() })
				        }
				        @Sendable nonisolated func __safeDI_gadgetSendableBuilder_GadgetSeam() -> GadgetSeam.__safeDI_GadgetSendableCarrier<any Gadget> {
				            .init(holderBuilder: { __safeDI_gadgetBuilder_GadgetSeam_GadgetHolder_Scope() })
				        }
				        @Sendable nonisolated func __safeDI_gadgetBuilder_GadgetSeam_GadgetHolder_Scope() -> GadgetSeam.__safeDI_GadgetCarrier_GadgetHolder<any Gadget> {
				            .init(gadget: {
				                let gadget: any Gadget = LiveGadget()
				                return gadget
				            })
				        }
				        func __safeDI_feature() -> Feature {
				            _ = Feature.__safeDI_Feature_48D1BBC130E19C16.self // If this line does not compile, compile the code SafeDI generates for module Mid into Mid: under Bazel, add Mid’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return Feature(__safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_Feature())
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
				    nonisolated public enum SafeDISendableScope_Gadget {
				        nonisolated public struct inner_serviceBuilder_Sendable_Values: Sendable {}

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
				            public let inner_serviceBuilder_Sendable: @Sendable (inner_serviceBuilder_Sendable_Values) -> GadgetSeam.__safeDI_GadgetSendableCarrier<__safeDI_Built>

				            public init(inner_serviceBuilder_Sendable: @escaping @Sendable (inner_serviceBuilder_Sendable_Values) -> GadgetSeam.__safeDI_GadgetSendableCarrier<__safeDI_Built>) {
				                self.inner_serviceBuilder_Sendable = inner_serviceBuilder_Sendable
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
				                self.init(inner_serviceBuilder_Sendable: { _ in .init(__safeDI_noScope: __safeDI_builder) })
				            }
				        }
				    }

				    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_gadgetSendableBuilder: SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget>) {
				        let __safeDI_gadgetSendableBuilder_inner_serviceBuilder_Sendable = __safeDI_gadgetSendableBuilder.inner_serviceBuilder_Sendable(SafeDISendableScope_Gadget.inner_serviceBuilder_Sendable_Values())
				        func __safeDI_inner() -> Inner {
				            _ = Inner.__safeDI_Inner_99BD917DA5EDFC3D.self // If this line does not compile, compile the code SafeDI generates for module Up into Up: under Bazel, add Up’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            func __safeDI_serviceBuilder_Inner_service() -> any Service {
				                func __safeDI_service() -> GadgetSeam {
				                    _ = GadgetSeam.__safeDI_GadgetSeam_DE6E94D5EE83F41C.self
				                    return GadgetSeam(__safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_inner_serviceBuilder_Sendable)
				                }
				                let service: any Service = __safeDI_service()
				                return service
				            }
				            func __safeDI_serviceBuilder_Inner() -> Inner.__safeDI_ServiceCarrier<any Service> {
				                .init(service: { __safeDI_serviceBuilder_Inner_service() })
				            }
				            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner())
				        }
				        let inner: Inner = __safeDI_inner()
				        self.init(inner: inner)
				    }
				}

				extension Feature {
				    public enum __safeDI_Feature_48D1BBC130E19C16 {}
				}

				extension GadgetSeam {
				    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				    nonisolated public final class __safeDI_GadgetCarrier_GadgetHolder<__safeDI_Built> {
				        public let gadget: () -> __safeDI_Built

				        public init(gadget: @escaping () -> __safeDI_Built) {
				            self.gadget = gadget
				        }

				        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				            self.init(gadget: { __safeDI_builder() })
				        }
				    }

				    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				    nonisolated public final class __safeDI_GadgetSendableCarrier<__safeDI_Built>: Sendable {
				        public let holderBuilder: @Sendable () -> __safeDI_GadgetCarrier_GadgetHolder<__safeDI_Built>

				        public init(holderBuilder: @escaping @Sendable () -> __safeDI_GadgetCarrier_GadgetHolder<__safeDI_Built>) {
				            self.holderBuilder = holderBuilder
				        }

				        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
				            self.init(holderBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_gadgetSendableBuilder: __safeDI_GadgetSendableCarrier<any Gadget>) {
				        @Sendable nonisolated func __safeDI_holderBuilder() -> GadgetHolder {
				            let __safeDI_gadgetSendableBuilder_holderBuilder = __safeDI_gadgetSendableBuilder.holderBuilder()
				            let gadget: any Gadget = __safeDI_gadgetSendableBuilder_holderBuilder.gadget()
				            return GadgetHolder(gadget: gadget)
				        }
				        let holderBuilder = SendableInstantiator<GadgetHolder>(__safeDI_holderBuilder)
				        self.init(holderBuilder: holderBuilder)
				    }
				}

				extension GadgetSeam {
				    public enum __safeDI_GadgetSeam_DE6E94D5EE83F41C {}
				}
				"""],
				"Up": ["Up.swift": """
				extension Inner {
				    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
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
				        let service: any Service = __safeDI_serviceBuilder.service()
				        self.init(service: service)
				    }
				}

				extension Inner {
				    public enum __safeDI_Inner_99BD917DA5EDFC3D {}
				}
				"""],
			],
			inline: Self.fulfillingSeamModules(liveGadgetInMid: true, gadgetPlace: "sendableBuilder"),
			probes: [DifferentialValueProbe("Root()")],
		)
	}

	// MARK: Fixtures

	/// `Inner { service: any Service }` in `Up`; in `Mid`, `Feature { inner: Inner }` and `GadgetSeam: Service { gadget: any Gadget }`,
	/// both seams; only `App` fills `Gadget`.
	/// `Feature`'s seam `Inner`, which binds `up`, then `screenBuilder`, whose `Screen` forwards `id` and holds
	/// `service: any Service`, then `service`; `Middle`'s seam `Outer`, which calls `Inner` and fills `Service` with
	/// `DefaultService`, which reads `up` and holds `gadget: any Gadget`, which `App` fills with `LiveGadget`, or `Middle`
	/// where `liveGadgetInMiddle`.
	private static func upLabelModules(liveGadgetInMiddle: Bool) -> [ModuleFixture] {
		let liveGadget = SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received public let tag: Tag"])
		let feature = [
			"public protocol Service {}\npublic protocol Gadget {}",
			seamFixtureType(named: "Up", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Screen", declarations: ["@Forwarded public let id: Int", "@Instantiated public let service: any Service"]),
			seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated public let up: Up", "@Instantiated public let screenBuilder: Instantiator<Screen>", "@Instantiated public let service: any Service"]),
		]
		var middle = [
			seamFixtureType(named: "Tag", isFinalClass: true, declarations: []),
			SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Received public let up: Up", "@Instantiated public let gadget: any Gadget"]),
			seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated public let tag: Tag", "@Instantiated public let inner: Inner"]),
		]
		var app = [seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let outer: Outer"])]
		if liveGadgetInMiddle {
			middle.append(liveGadget)
		} else {
			app.insert(liveGadget, at: 0)
		}
		return [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature),
			ModuleFixture(name: "Middle", packageName: "Other", swiftFileContent: middle.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: app.map { "import Feature\nimport Middle\n\n" + $0 }, dependencies: ["Feature", "Middle"]),
		]
	}

	/// `gadgetPlace` is `nil` for `GadgetSeam`'s plain place `gadget`, `"sendableWrapper"` for `gadget` held in a
	/// `SendableLazilyInstantiated`, `"sendableBuilder"` for `gadget` on `GadgetHolder`, which `GadgetSeam` builds through
	/// a `SendableInstantiator`, and `"sendableFill"` for the plain place with `Inner` holding `service` in a
	/// `SendableLazilyInstantiated`, so the fill that builds `GadgetSeam` is `@Sendable`.
	private static func fulfillingSeamModules(liveGadgetInMid: Bool = false, gadgetPlace: String? = nil) -> [ModuleFixture] {
		let sendable = gadgetPlace == nil ? "" : ", Sendable"
		let liveGadget = """
		@Instantiable(fulfillingAdditionalTypes: [Gadget.self])
		public final class LiveGadget: Instantiable, Gadget {
		    public init() {}
		}
		"""
		let up = [
			"public protocol Service: AnyObject\(sendable) {}",
			"public protocol Gadget: AnyObject\(sendable) {}",
			seamFixtureType(named: "Inner", isSeam: true, isFinalClass: true, declarations: [gadgetPlace == "sendableFill" ? "@Instantiated public let service: SendableLazilyInstantiated<any Service>" : "@Instantiated public let service: any Service"]),
		]
		let gadgetSeam = switch gadgetPlace {
		case "sendableWrapper":
			"""
			@Instantiable(generateDependencyTree: true, fulfillingAdditionalTypes: [Service.self])
			public final class GadgetSeam: Instantiable, Service {
			    public init(gadget: SendableLazilyInstantiated<any Gadget>) { self.gadget = gadget }
			    @Instantiated public let gadget: SendableLazilyInstantiated<any Gadget>
			}
			"""
		case "sendableBuilder":
			"""
			@Instantiable
			public final class GadgetHolder: Instantiable, Sendable {
			    public init(gadget: any Gadget) { self.gadget = gadget }
			    @Instantiated public let gadget: any Gadget
			}

			@Instantiable(generateDependencyTree: true, fulfillingAdditionalTypes: [Service.self])
			public final class GadgetSeam: Instantiable, Service {
			    public init(holderBuilder: SendableInstantiator<GadgetHolder>) { self.holderBuilder = holderBuilder }
			    @Instantiated public let holderBuilder: SendableInstantiator<GadgetHolder>
			}
			"""
		default:
			"""
			@Instantiable(generateDependencyTree: true, fulfillingAdditionalTypes: [Service.self])
			public final class GadgetSeam: Instantiable, Service {
			    public init(gadget: any Gadget) { self.gadget = gadget }
			    @Instantiated public let gadget: any Gadget
			}
			"""
		}
		var mid = [
			seamFixtureType(named: "Feature", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let inner: Inner"]),
			gadgetSeam,
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

	/// `Outer` declares `logger` lazily and calls `Inner`, whose `Detail` instantiates `api: any Api` before it receives
	/// `logger` through an instantiator, so `Inner` takes it as a parameter; `App` fills `api` with a `LiveApi` whose `Job`,
	/// built through `jobBuilder`, receives `logger`. `Logger` is stamped with the order it is created in.
	private static func passedUpLazyLoggerModules(liveApiInFeature: Bool = false) -> [ModuleFixture] {
		let liveApi = [
			"""
			@Instantiable
			public final class Job: Instantiable {
			    public init(logger: Logger) { self.logger = logger }
			    @Received public let logger: Logger
			}
			""",
			"""
			@Instantiable(fulfillingAdditionalTypes: [Api.self])
			public final class LiveApi: Instantiable, Api {
			    public init(jobBuilder: Instantiator<Job>) { self.jobBuilder = jobBuilder }
			    @Instantiated public let jobBuilder: Instantiator<Job>
			}
			""",
		]
		var feature = [
			"public protocol Api: AnyObject {}\n\n" + DifferentialValueCreationStamp.counterDeclaration(named: "Stamp"),
			"""
			@Instantiable
			public final class Logger: Instantiable {
			    \(DifferentialValueCreationStamp.property(counterNamed: "Stamp"))

			    public init() {}
			}
			""",
			"""
			@Instantiable
			public final class Reader: Instantiable {
			    public init(logger: Logger) { self.logger = logger }
			    @Received public let logger: Logger
			}
			""",
			"""
			@Instantiable
			public final class Detail: Instantiable {
			    public init(api: any Api, readerBuilder: Instantiator<Reader>) { self.api = api; self.readerBuilder = readerBuilder }
			    @Instantiated public let api: any Api
			    @Instantiated public let readerBuilder: Instantiator<Reader>
			}
			""",
			seamFixtureType(named: "Inner", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let detail: Detail"]),
			seamFixtureType(named: "Outer", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let logger: LazilyInstantiated<Logger>", "@Instantiated public let inner: Inner"]),
		]
		var app = [seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let outer: Outer"])]
		if liveApiInFeature {
			feature += liveApi
		} else {
			app.insert(contentsOf: liveApi, at: 0)
		}
		return Self.modules(feature: feature, app: app)
	}

	/// `Outer` (a seam) declares `logger` and calls `Inner` (a seam), whose `Detail` receives it, so `Inner` takes it as a
	/// parameter, and whose call of `Nest`, a seam of `Session`, fills `Nest`'s hole with `NestImpl`, whose `api: any Api` only
	/// `App` fills, with a `LiveApi` that receives `logger`. `App`'s root declares a `logger` of its own.
	private static func passedUpPlaceInsideFillModules(liveApiInFeature: Bool = false) -> [ModuleFixture] {
		let liveApi = """
		@Instantiable(fulfillingAdditionalTypes: [Api.self])
		public final class LiveApi: Instantiable, Api {
		    public init(logger: Logger) { self.logger = logger }
		    @Received public let logger: Logger
		}
		"""
		let session = [
			"public protocol Service: AnyObject {}",
			seamFixtureType(named: "Nest", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let service: any Service"]),
		]
		var feature = [
			"public protocol Api: AnyObject {}\n\n" + DifferentialValueCreationStamp.counterDeclaration(named: "Stamp"),
			"""
			@Instantiable
			public final class Logger: Instantiable {
			    \(DifferentialValueCreationStamp.property(counterNamed: "Stamp"))

			    public init() {}
			}
			""",
			seamFixtureType(named: "Detail", isFinalClass: true, declarations: ["@Received public let logger: Logger"]),
			"""
			@Instantiable(fulfillingAdditionalTypes: [Service.self])
			public final class NestImpl: Instantiable, Service {
			    public init(api: any Api) { self.api = api }
			    @Instantiated public let api: any Api
			}
			""",
			seamFixtureType(named: "Inner", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let detail: Detail", "@Instantiated public let nest: Nest"]),
			seamFixtureType(named: "Outer", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let logger: Logger", "@Instantiated public let inner: Inner"]),
		]
		var app = [seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let logger: Logger", "@Instantiated public let outer: Outer"])]
		if liveApiInFeature {
			feature.append(liveApi)
		} else {
			app.insert(liveApi, at: 0)
		}
		return [
			ModuleFixture(name: "Session", packageName: "Shop", swiftFileContent: session),
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature.map { "import Session\n\n" + $0 }, dependencies: ["Session"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: app.map { "import Feature\nimport Session\n\n" + $0 }, dependencies: ["Session", "Feature"]),
		]
	}

	/// `Outer` instantiates `logger` and calls `Middle`, which instantiates `tag` and calls `Inner`, whose `Detail` receives
	/// both, `tag` only if available, and instantiates `api: any Api`, which only `App` fills, with a `LiveApi` that receives
	/// both the same way. Where `lazyOrigins`, `Outer` and `Middle` declare them lazily, and `Logger` and `Tag` are stamped
	/// with the order they are created in.
	private static func twoLevelPassUpModules(liveApiInFeature: Bool = false, lazyOrigins: Bool = false) -> [ModuleFixture] {
		let liveApi = """
		@Instantiable(fulfillingAdditionalTypes: [Api.self])
		public final class LiveApi: Instantiable, Api {
		    public init(logger: Logger, tag: Tag?) { self.logger = logger; self.tag = tag }
		    @Received public let logger: Logger
		    @Received(onlyIfAvailable: true) public let tag: Tag?
		}
		"""
		let stamp = lazyOrigins ? "\n    \(DifferentialValueCreationStamp.property(counterNamed: "Stamp"))\n\n    " : " "
		var feature = [
			lazyOrigins ? "public protocol Api: AnyObject {}\n\n" + DifferentialValueCreationStamp.counterDeclaration(named: "Stamp") : "public protocol Api: AnyObject {}",
			"""
			@Instantiable
			public final class Logger: Instantiable {\(stamp)public init() {}\(lazyOrigins ? "\n" : " ")}
			""",
			"""
			@Instantiable
			public final class Tag: Instantiable {\(stamp)public init() {}\(lazyOrigins ? "\n" : " ")}
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
			seamFixtureType(named: "Middle", isSeam: true, isFinalClass: true, declarations: [lazyOrigins ? "@Instantiated public let tag: LazilyInstantiated<Tag>" : "@Instantiated public let tag: Tag", "@Instantiated public let inner: Inner"]),
			seamFixtureType(named: "Outer", isSeam: true, isFinalClass: true, declarations: [lazyOrigins ? "@Instantiated public let logger: LazilyInstantiated<Logger>" : "@Instantiated public let logger: Logger", "@Instantiated public let middle: Middle"]),
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
	private static func carriedModules(isSendable: Bool = false, fulfillersInFeature: Bool = false, holdsWidget: Bool = false) -> [ModuleFixture] {
		let sendable = isSendable ? ", Sendable" : ""
		let defaultService = holdsWidget ? """
		@Instantiable(fulfillingAdditionalTypes: [Service.self])
		public final class DefaultService: Instantiable, Service {
		    public init(logger: Logger, gadget: any Gadget, widget: any Widget) { self.logger = logger; self.gadget = gadget; self.widget = widget }
		    @Instantiated public let logger: Logger
		    @Instantiated public let gadget: any Gadget
		    @Instantiated public let widget: any Widget
		}
		""" : """
		@Instantiable(fulfillingAdditionalTypes: [Service.self])
		public final class DefaultService: Instantiable, Service {
		    public init(logger: Logger, gadget: any Gadget) { self.logger = logger; self.gadget = gadget }
		    @Instantiated public let logger: Logger
		    @Instantiated public let gadget: any Gadget
		}
		"""
		let liveWidget = """
		@Instantiable(fulfillingAdditionalTypes: [Widget.self])
		public final class LiveWidget: Instantiable, Widget {
		    public init(tag: Tag, logger: Logger) { self.tag = tag; self.logger = logger }
		    @Received public let tag: Tag
		    @Received public let logger: Logger
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
		if holdsWidget {
			feature.insert("public protocol Widget: AnyObject\(sendable) {}", at: 2)
		}
		var middle = [seamFixtureType(named: "Outer", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let tag: Tag", isSendable ? "@Instantiated public let innerBuilder: SendableInstantiator<Inner>" : "@Instantiated public let inner: Inner"])]
		var app = [seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let outer: Outer"])]
		let liveFulfillers = holdsWidget ? [liveGadget, liveWidget] : [liveGadget]
		if fulfillersInFeature {
			feature += [defaultService] + liveFulfillers
		} else {
			middle.insert(defaultService, at: 0)
			app.insert(contentsOf: liveFulfillers, at: 0)
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
		try await expectOutput(of: modules, { _ in expected }, inline: inline, probes: probes, sourceLocation: sourceLocation)
	}

	/// As above, with the expected files of each module given the run's output, for a literal that names a fixture's path.
	private mutating func expectOutput(
		of modules: [ModuleFixture],
		_ expectedGivenOutput: (MultiModuleTestOutput) throws -> [String: [String: String]],
		inline: [ModuleFixture],
		probes: [DifferentialValueProbe],
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		for (moduleName, files) in try expectedGivenOutput(output) {
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
