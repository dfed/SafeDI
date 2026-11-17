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

/// A place inside a public mock's fill: `Outer`'s public mock calls `Inner`'s and fills `Inner`'s hole with a type whose
/// tree holds a hole `Outer` cannot fill. `Outer`'s enum has one case per call and builder filled, `<call>_<builder>`,
/// holding `Outer`'s level, the scope value `Inner`'s mock handed the fill, and the enum of the type the fill builds,
/// nested by type, as a seam's place inside a fill is (`SafeDIToolSeamPlaceInsideFillTests`). A module that calls
/// `Outer`'s mock reads a value `Inner`'s levels hold through one reader per enum of `Inner`'s that leads to it, and fills
/// or passes up per route. Each test compiles every module and compares the values the mocks build with those of the same
/// graph's mock built inline, every public mock internal.
struct SafeDIToolPublicMockPlaceInsideFillTests: ~Copyable {
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
	mutating func generate_nestsPlaceInsideFillByType_whenPublicMockFillsCalledMocksHoleWithTypeHoldingHoleItCannotFill() async throws {
		// `Inner`'s mock builds `service` at its root and in the `Screen` its `screenBuilder` builds, which forwards `id`.
		// `Outer`'s mock fills both with `DefaultService`, whose `gadget` only `App` can build: one case of `Outer`'s root,
		// `inner_serviceBuilder`, holds `Outer`'s level, `Inner`'s scope, and `DefaultService_Scope`. `App`'s `LiveGadget`
		// reads `id` only if available, which only the `screenBuilder` route of `Inner`'s holds: the reader finds it there,
		// and `App` fills the place. On `Inner`'s root route, where inline hands `nil`, `App` passes the place up, as a public
		// mock's caller passes up each place whose route lacks a value its fill reads, so its mock takes a builder for it.
		try await expectPlaceInsideFill(
			feature: Self.inner(screen: ["@Forwarded public let id: Int"]),
			middle: [
				seamFixtureType(named: "Tag", isFinalClass: true, declarations: []),
				Self.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let gadget: any Gadget"]),
				Self.publicMockType(named: "Outer", declarations: ["@Instantiated public let tag: Tag", "@Instantiated public let inner: Inner"]),
			],
			app: [
				Self.passedUpGadget,
				Self.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received public let tag: Tag", "@Received(onlyIfAvailable: true) public let id: Int?"]),
				Self.mockedRoot(declarations: ["@Instantiated public let outer: Outer"]),
			],
			probes: [Self.probe(".outer.inner.screenBuilder.instantiate(7)", builders: "gadgetBuilder: { PassedUpGadget() }")],
			expectedMiddle: """
			#if canImport(Feature)
			import Feature
			#endif

			#if DEBUG
			extension Outer {
			    nonisolated public enum SafeDIMockScope_Gadget {
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
			            public let inner_serviceBuilder: (inner_serviceBuilder_Values) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(inner_serviceBuilder: @escaping (inner_serviceBuilder_Values) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.inner_serviceBuilder = inner_serviceBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.inner_serviceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            tag: (() -> Tag)? = nil,
			            inner: Inner.SafeDIOverrides = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                tag: tag,
			                inner: inner
			            )
			        }

			        public var tag: (() -> Tag)? { __safeDI_storage.tag }
			        public var inner: Inner.SafeDIOverrides { __safeDI_storage.inner }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                tag: (() -> Tag)?,
			                inner: Inner.SafeDIOverrides
			            ) {
			                self.tag = tag
			                self.inner = inner
			            }

			            let tag: (() -> Tag)?
			            let inner: Inner.SafeDIOverrides
			        }
			    }

			    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    public static func mock(
			        gadgetBuilder: @escaping () -> any Gadget,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Outer {
			        Outer.__safeDI_mock(gadgetBuilder: .init(__safeDI_noScope: gadgetBuilder), safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        gadgetBuilder __safeDI_gadgetBuilder: Outer.SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget>,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Outer {
			        let tag = if let safeDIBuilder = safeDIOverrides.tag { safeDIBuilder() } else { Tag() }
			        let __safeDI_gadgetBuilder_inner_serviceBuilder = __safeDI_gadgetBuilder.inner_serviceBuilder(SafeDIMockScope_Gadget.inner_serviceBuilder_Values(tag: tag))
			        func __safeDI_inner() -> Inner {
			            func __safeDI_serviceBuilder_Inner_service(_ scope: Inner.SafeDIMockScope_Service.service_Values, __safeDI_inner_serviceBuilder: SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let gadget: any Gadget = __safeDI_inner_serviceBuilder.gadget(SafeDIMockScope_Gadget.DefaultService_Scope.gadget_Values())
			                    return DefaultService(gadget: gadget)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Inner_Screen_Scope_service(_ scope: Inner.SafeDIMockScope_Service.Screen_Scope.service_Values, __safeDI_inner_serviceBuilder: SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let gadget: any Gadget = __safeDI_inner_serviceBuilder.gadget(SafeDIMockScope_Gadget.DefaultService_Scope.gadget_Values())
			                    return DefaultService(gadget: gadget)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Inner(up: Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(screenBuilder: { values in __safeDI_serviceBuilder_Inner_Screen_Scope(up: up.screenBuilder(values)) }, service: { scope in __safeDI_serviceBuilder_Inner_service(scope, __safeDI_inner_serviceBuilder: up.service(scope)) })
			            }
			            func __safeDI_serviceBuilder_Inner_Screen_Scope(up: Inner.SafeDIMockScope_Service.Screen_Scope.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDIMockScope_Service.Screen_Scope.__safeDI_Builder<any Service> {
			                .init(service: { scope in __safeDI_serviceBuilder_Inner_Screen_Scope_service(scope, __safeDI_inner_serviceBuilder: up.service(scope)) })
			            }
			            _ = Inner.__safeDI_Inner_mock_3EBB13A82C3BF964.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Inner.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder_Inner(up: __safeDI_gadgetBuilder_inner_serviceBuilder), safeDIOverrides: safeDIOverrides.inner)
			        }
			        let inner: Inner = __safeDI_inner()
			        return Outer(tag: tag, inner: inner)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_mock_CF3D8E43405F88BA {}
			}
			#endif
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            outer: Outer.SafeDIOverrides = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                outer: outer
			            )
			        }

			        var outer: Outer.SafeDIOverrides { __safeDI_storage.outer }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                outer: Outer.SafeDIOverrides
			            ) {
			                self.outer = outer
			            }

			            let outer: Outer.SafeDIOverrides
			        }
			    }

			    static func mock(
			        gadgetBuilder: @escaping () -> any Gadget,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_outer() -> Outer {
			            func __safeDI_gadgetBuilder_Outer_DefaultService_Scope_gadget(_ scope: Outer.SafeDIMockScope_Gadget.DefaultService_Scope.gadget_Values, tag: Tag, id: Int?) -> any Gadget {
			                let gadget: any Gadget = LiveGadget(tag: tag, id: id)
			                return gadget
			            }
			            func __safeDI_gadgetBuilder_Outer(up: Outer.SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget>) -> Outer.SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget> {
			                .init(inner_serviceBuilder: { values in __safeDI_gadgetBuilder_Outer_Inner(up: up.inner_serviceBuilder(values), tag: values.tag) })
			            }
			            func __safeDI_gadgetBuilder_Outer_Inner(up: Inner.SafeDIMockScope_Service.__safeDI_Builder<Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>, tag: Tag) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			                .init(screenBuilder: { _ in __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope(tag: tag) }, service: { values in __safeDI_gadgetBuilder_Outer_DefaultService_Scope_(up: up.service(values), tag: tag) })
			            }
			            func __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope(tag: Tag) -> Inner.SafeDIMockScope_Service.Screen_Scope.__safeDI_Builder<Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			                .init(service: { values in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: values.id, tag: tag) })
			            }
			            func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: Int, tag: Tag) -> Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
			                .init(gadget: { scope in __safeDI_gadgetBuilder_Outer_DefaultService_Scope_gadget(scope, tag: tag, id: id) })
			            }
			            func __safeDI_gadgetBuilder_Outer_DefaultService_Scope_(up: Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>, tag: Tag) -> Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
			                .init(gadget: up.gadget)
			            }
			            _ = Outer.__safeDI_Outer_mock_CF3D8E43405F88BA.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Outer.__safeDI_mock(gadgetBuilder: __safeDI_gadgetBuilder_Outer(up: .init(__safeDI_noScope: gadgetBuilder)), safeDIOverrides: safeDIOverrides.outer)
			        }
			        let outer: Outer = __safeDI_outer()
			        return Root(outer: outer)
			    }
			}
			#endif
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsOuterLevelWhereNoInnerLevelHoldsValue_whenOneRouteOfCalledMockHoldsValuePublicMocksFillReads() async throws {
		// `Screen` forwards `session`, and `Outer` builds its own before `inner`: on the `screenBuilder` route `LiveGadget`
		// reads `Screen`'s, nearer, through the reader of `Inner`'s levels, and on the other `Outer`'s, which `Outer`'s level
		// carries. Every route binds `session`, so `App` fills both and passes nothing up.
		try await expectPlaceInsideFill(
			feature: [seamFixtureType(named: "Session", isFinalClass: true, declarations: [])] + Self.inner(screen: ["@Forwarded public let session: Session"]),
			middle: [
				Self.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let gadget: any Gadget"]),
				Self.publicMockType(named: "Outer", declarations: ["@Instantiated public let session: Session", "@Instantiated public let inner: Inner"]),
			],
			app: [
				Self.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received public let session: Session"]),
				Self.mockedRoot(declarations: ["@Instantiated public let outer: Outer"]),
			],
			probes: [DifferentialValueProbe("Root.mock()"), DifferentialValueProbe("Root.mock().outer.inner.screenBuilder.instantiate(Session())")],
			expectedMiddle: """
			#if canImport(Feature)
			import Feature
			#endif

			#if DEBUG
			extension Outer {
			    nonisolated public enum SafeDIMockScope_Gadget {
			        nonisolated public struct inner_serviceBuilder_Values {
			            public let session: Session
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
			            public let inner_serviceBuilder: (inner_serviceBuilder_Values) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(inner_serviceBuilder: @escaping (inner_serviceBuilder_Values) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.inner_serviceBuilder = inner_serviceBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.inner_serviceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            session: (() -> Session)? = nil,
			            inner: Inner.SafeDIOverrides = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                session: session,
			                inner: inner
			            )
			        }

			        public var session: (() -> Session)? { __safeDI_storage.session }
			        public var inner: Inner.SafeDIOverrides { __safeDI_storage.inner }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                session: (() -> Session)?,
			                inner: Inner.SafeDIOverrides
			            ) {
			                self.session = session
			                self.inner = inner
			            }

			            let session: (() -> Session)?
			            let inner: Inner.SafeDIOverrides
			        }
			    }

			    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    public static func mock(
			        gadgetBuilder: @escaping () -> any Gadget,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Outer {
			        Outer.__safeDI_mock(gadgetBuilder: .init(__safeDI_noScope: gadgetBuilder), safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        gadgetBuilder __safeDI_gadgetBuilder: Outer.SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget>,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Outer {
			        let session = if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session() }
			        let __safeDI_gadgetBuilder_inner_serviceBuilder = __safeDI_gadgetBuilder.inner_serviceBuilder(SafeDIMockScope_Gadget.inner_serviceBuilder_Values(session: session))
			        func __safeDI_inner() -> Inner {
			            func __safeDI_serviceBuilder_Inner_service(_ scope: Inner.SafeDIMockScope_Service.service_Values, __safeDI_inner_serviceBuilder: SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let gadget: any Gadget = __safeDI_inner_serviceBuilder.gadget(SafeDIMockScope_Gadget.DefaultService_Scope.gadget_Values())
			                    return DefaultService(gadget: gadget)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Inner_Screen_Scope_service(_ scope: Inner.SafeDIMockScope_Service.Screen_Scope.service_Values, __safeDI_inner_serviceBuilder: SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let gadget: any Gadget = __safeDI_inner_serviceBuilder.gadget(SafeDIMockScope_Gadget.DefaultService_Scope.gadget_Values())
			                    return DefaultService(gadget: gadget)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Inner(up: Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(screenBuilder: { values in __safeDI_serviceBuilder_Inner_Screen_Scope(up: up.screenBuilder(values)) }, service: { scope in __safeDI_serviceBuilder_Inner_service(scope, __safeDI_inner_serviceBuilder: up.service(scope)) })
			            }
			            func __safeDI_serviceBuilder_Inner_Screen_Scope(up: Inner.SafeDIMockScope_Service.Screen_Scope.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDIMockScope_Service.Screen_Scope.__safeDI_Builder<any Service> {
			                .init(service: { scope in __safeDI_serviceBuilder_Inner_Screen_Scope_service(scope, __safeDI_inner_serviceBuilder: up.service(scope)) })
			            }
			            _ = Inner.__safeDI_Inner_mock_5720E82B2981644A.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Inner.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder_Inner(up: __safeDI_gadgetBuilder_inner_serviceBuilder), safeDIOverrides: safeDIOverrides.inner)
			        }
			        let inner: Inner = __safeDI_inner()
			        return Outer(session: session, inner: inner)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_mock_3D4C1B9F5288ACC0 {}
			}
			#endif
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            outer: Outer.SafeDIOverrides = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                outer: outer
			            )
			        }

			        var outer: Outer.SafeDIOverrides { __safeDI_storage.outer }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                outer: Outer.SafeDIOverrides
			            ) {
			                self.outer = outer
			            }

			            let outer: Outer.SafeDIOverrides
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_outer() -> Outer {
			            func __safeDI_gadgetBuilder_Outer() -> Outer.SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget> {
			                .init(inner_serviceBuilder: { values in __safeDI_gadgetBuilder_Outer_Inner(session: values.session) })
			            }
			            func __safeDI_gadgetBuilder_Outer_Inner(session: Session) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			                .init(screenBuilder: { _ in __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope() }, service: { _ in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(session: session) })
			            }
			            func __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope() -> Inner.SafeDIMockScope_Service.Screen_Scope.__safeDI_Builder<Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			                .init(service: { values in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(session: values.session) })
			            }
			            func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(session: Session) -> Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
			                .init(gadget: { _ in
			                    let gadget: any Gadget = LiveGadget(session: session)
			                    return gadget
			                })
			            }
			            _ = Outer.__safeDI_Outer_mock_3D4C1B9F5288ACC0.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Outer.__safeDI_mock(gadgetBuilder: __safeDI_gadgetBuilder_Outer(), safeDIOverrides: safeDIOverrides.outer)
			        }
			        let outer: Outer = __safeDI_outer()
			        return Root(outer: outer)
			    }
			}
			#endif
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsPlaceOnRouteWhoseInnerLevelHoldsValueAndPassesItUpOnOther_whenFillRequiresValueOneRouteOfCalledMockHolds() async throws {
		// As above, but `LiveGadget` requires `id`, which only the `screenBuilder` route of `Inner`'s holds: one case of
		// `Outer`'s stands for both places, and `App` fills it on the route whose reader finds `id` and passes it up on the
		// other, which its mock takes a builder for, as the per-place decision fills one place and passes the other up.
		try await expectPlaceInsideFill(
			feature: Self.inner(screen: ["@Forwarded public let id: Int"]),
			middle: [
				Self.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let gadget: any Gadget"]),
				Self.publicMockType(named: "Outer", declarations: ["@Instantiated public let inner: Inner"]),
			],
			app: [
				Self.passedUpGadget,
				Self.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received public let id: Int"]),
				Self.mockedRoot(declarations: ["@Instantiated public let outer: Outer"]),
			],
			probes: [Self.probe(".outer.inner.screenBuilder.instantiate(7)", builders: "gadgetBuilder: { PassedUpGadget() }", knownRightArguments: "id: 0")],
			expectedMiddle: """
			#if canImport(Feature)
			import Feature
			#endif

			#if DEBUG
			extension Outer {
			    nonisolated public enum SafeDIMockScope_Gadget {
			        nonisolated public struct inner_serviceBuilder_Values {}

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
			            public let inner_serviceBuilder: (inner_serviceBuilder_Values) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(inner_serviceBuilder: @escaping (inner_serviceBuilder_Values) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.inner_serviceBuilder = inner_serviceBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.inner_serviceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            inner: Inner.SafeDIOverrides = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                inner: inner
			            )
			        }

			        public var inner: Inner.SafeDIOverrides { __safeDI_storage.inner }

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

			    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    public static func mock(
			        gadgetBuilder: @escaping () -> any Gadget,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Outer {
			        Outer.__safeDI_mock(gadgetBuilder: .init(__safeDI_noScope: gadgetBuilder), safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        gadgetBuilder __safeDI_gadgetBuilder: Outer.SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget>,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Outer {
			        let __safeDI_gadgetBuilder_inner_serviceBuilder = __safeDI_gadgetBuilder.inner_serviceBuilder(SafeDIMockScope_Gadget.inner_serviceBuilder_Values())
			        func __safeDI_inner() -> Inner {
			            func __safeDI_serviceBuilder_Inner_service(_ scope: Inner.SafeDIMockScope_Service.service_Values, __safeDI_inner_serviceBuilder: SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let gadget: any Gadget = __safeDI_inner_serviceBuilder.gadget(SafeDIMockScope_Gadget.DefaultService_Scope.gadget_Values())
			                    return DefaultService(gadget: gadget)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Inner_Screen_Scope_service(_ scope: Inner.SafeDIMockScope_Service.Screen_Scope.service_Values, __safeDI_inner_serviceBuilder: SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let gadget: any Gadget = __safeDI_inner_serviceBuilder.gadget(SafeDIMockScope_Gadget.DefaultService_Scope.gadget_Values())
			                    return DefaultService(gadget: gadget)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Inner(up: Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(screenBuilder: { values in __safeDI_serviceBuilder_Inner_Screen_Scope(up: up.screenBuilder(values)) }, service: { scope in __safeDI_serviceBuilder_Inner_service(scope, __safeDI_inner_serviceBuilder: up.service(scope)) })
			            }
			            func __safeDI_serviceBuilder_Inner_Screen_Scope(up: Inner.SafeDIMockScope_Service.Screen_Scope.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDIMockScope_Service.Screen_Scope.__safeDI_Builder<any Service> {
			                .init(service: { scope in __safeDI_serviceBuilder_Inner_Screen_Scope_service(scope, __safeDI_inner_serviceBuilder: up.service(scope)) })
			            }
			            _ = Inner.__safeDI_Inner_mock_3EBB13A82C3BF964.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Inner.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder_Inner(up: __safeDI_gadgetBuilder_inner_serviceBuilder), safeDIOverrides: safeDIOverrides.inner)
			        }
			        let inner: Inner = __safeDI_inner()
			        return Outer(inner: inner)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_mock_6728D9B2241EC30D {}
			}
			#endif
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            outer: Outer.SafeDIOverrides = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                outer: outer
			            )
			        }

			        var outer: Outer.SafeDIOverrides { __safeDI_storage.outer }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                outer: Outer.SafeDIOverrides
			            ) {
			                self.outer = outer
			            }

			            let outer: Outer.SafeDIOverrides
			        }
			    }

			    static func mock(
			        gadgetBuilder: @escaping () -> any Gadget,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_outer() -> Outer {
			            func __safeDI_gadgetBuilder_Outer_DefaultService_Scope_gadget(_ scope: Outer.SafeDIMockScope_Gadget.DefaultService_Scope.gadget_Values, id: Int) -> any Gadget {
			                let gadget: any Gadget = LiveGadget(id: id)
			                return gadget
			            }
			            func __safeDI_gadgetBuilder_Outer(up: Outer.SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget>) -> Outer.SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget> {
			                .init(inner_serviceBuilder: { values in __safeDI_gadgetBuilder_Outer_Inner(up: up.inner_serviceBuilder(values)) })
			            }
			            func __safeDI_gadgetBuilder_Outer_Inner(up: Inner.SafeDIMockScope_Service.__safeDI_Builder<Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			                .init(screenBuilder: { _ in __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope() }, service: { values in __safeDI_gadgetBuilder_Outer_DefaultService_Scope_(up: up.service(values)) })
			            }
			            func __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope() -> Inner.SafeDIMockScope_Service.Screen_Scope.__safeDI_Builder<Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			                .init(service: { values in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: values.id) })
			            }
			            func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: Int) -> Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
			                .init(gadget: { scope in __safeDI_gadgetBuilder_Outer_DefaultService_Scope_gadget(scope, id: id) })
			            }
			            func __safeDI_gadgetBuilder_Outer_DefaultService_Scope_(up: Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
			                .init(gadget: up.gadget)
			            }
			            _ = Outer.__safeDI_Outer_mock_6728D9B2241EC30D.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Outer.__safeDI_mock(gadgetBuilder: __safeDI_gadgetBuilder_Outer(up: .init(__safeDI_noScope: gadgetBuilder)), safeDIOverrides: safeDIOverrides.outer)
			        }
			        let outer: Outer = __safeDI_outer()
			        return Root(outer: outer)
			    }
			}
			#endif
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesPlaceUpOnRouteWhoseInnerLevelHidesValue_whenCalledMocksLevelHoldsFillsLabelInAnotherForm() async throws {
		// `Outer` builds `id: Code` before `inner`, and `Inner`'s `Screen` forwards `id: String`. `LiveGadget` reads
		// `id: Code`: on `Inner`'s root route no level of `Inner`'s holds `id`, so `App` fills the place with `Outer`'s; on the
		// `screenBuilder` route `Screen`'s `id` hides `Outer`'s, as Swift's lookup hides it, so the place is passed up there.
		// Inline rejects the receive as hidden, so no value is compared.
		try await expectPlaceInsideFill(
			feature: Self.inner(screen: ["@Forwarded public let id: String"]),
			middle: [
				seamFixtureType(named: "Code", isFinalClass: true, declarations: []),
				Self.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let gadget: any Gadget"]),
				Self.publicMockType(named: "Outer", declarations: ["@Instantiated public let id: Code", "@Instantiated public let inner: Inner"]),
			],
			app: [
				Self.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received public let id: Code"]),
				Self.mockedRoot(declarations: ["@Instantiated public let outer: Outer"]),
			],
			probes: [],
			expectedMiddle: """
			#if canImport(Feature)
			import Feature
			#endif

			#if DEBUG
			extension Outer {
			    nonisolated public enum SafeDIMockScope_Gadget {
			        nonisolated public struct inner_serviceBuilder_Values {
			            public let id: Code
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
			            public let inner_serviceBuilder: (inner_serviceBuilder_Values) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(inner_serviceBuilder: @escaping (inner_serviceBuilder_Values) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.inner_serviceBuilder = inner_serviceBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.inner_serviceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            id: (() -> Code)? = nil,
			            inner: Inner.SafeDIOverrides = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                id: id,
			                inner: inner
			            )
			        }

			        public var id: (() -> Code)? { __safeDI_storage.id }
			        public var inner: Inner.SafeDIOverrides { __safeDI_storage.inner }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                id: (() -> Code)?,
			                inner: Inner.SafeDIOverrides
			            ) {
			                self.id = id
			                self.inner = inner
			            }

			            let id: (() -> Code)?
			            let inner: Inner.SafeDIOverrides
			        }
			    }

			    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    public static func mock(
			        gadgetBuilder: @escaping () -> any Gadget,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Outer {
			        Outer.__safeDI_mock(gadgetBuilder: .init(__safeDI_noScope: gadgetBuilder), safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        gadgetBuilder __safeDI_gadgetBuilder: Outer.SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget>,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Outer {
			        let id = if let safeDIBuilder = safeDIOverrides.id { safeDIBuilder() } else { Code() }
			        let __safeDI_gadgetBuilder_inner_serviceBuilder = __safeDI_gadgetBuilder.inner_serviceBuilder(SafeDIMockScope_Gadget.inner_serviceBuilder_Values(id: id))
			        func __safeDI_inner() -> Inner {
			            func __safeDI_serviceBuilder_Inner_service(_ scope: Inner.SafeDIMockScope_Service.service_Values, __safeDI_inner_serviceBuilder: SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let gadget: any Gadget = __safeDI_inner_serviceBuilder.gadget(SafeDIMockScope_Gadget.DefaultService_Scope.gadget_Values())
			                    return DefaultService(gadget: gadget)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Inner_Screen_Scope_service(_ scope: Inner.SafeDIMockScope_Service.Screen_Scope.service_Values, __safeDI_inner_serviceBuilder: SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let gadget: any Gadget = __safeDI_inner_serviceBuilder.gadget(SafeDIMockScope_Gadget.DefaultService_Scope.gadget_Values())
			                    return DefaultService(gadget: gadget)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Inner(up: Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(screenBuilder: { values in __safeDI_serviceBuilder_Inner_Screen_Scope(up: up.screenBuilder(values)) }, service: { scope in __safeDI_serviceBuilder_Inner_service(scope, __safeDI_inner_serviceBuilder: up.service(scope)) })
			            }
			            func __safeDI_serviceBuilder_Inner_Screen_Scope(up: Inner.SafeDIMockScope_Service.Screen_Scope.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDIMockScope_Service.Screen_Scope.__safeDI_Builder<any Service> {
			                .init(service: { scope in __safeDI_serviceBuilder_Inner_Screen_Scope_service(scope, __safeDI_inner_serviceBuilder: up.service(scope)) })
			            }
			            _ = Inner.__safeDI_Inner_mock_718C21DDAD65EAF2.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Inner.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder_Inner(up: __safeDI_gadgetBuilder_inner_serviceBuilder), safeDIOverrides: safeDIOverrides.inner)
			        }
			        let inner: Inner = __safeDI_inner()
			        return Outer(id: id, inner: inner)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_mock_EC7E20025BEDA1D4 {}
			}
			#endif
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            outer: Outer.SafeDIOverrides = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                outer: outer
			            )
			        }

			        var outer: Outer.SafeDIOverrides { __safeDI_storage.outer }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                outer: Outer.SafeDIOverrides
			            ) {
			                self.outer = outer
			            }

			            let outer: Outer.SafeDIOverrides
			        }
			    }

			    static func mock(
			        gadgetBuilder: @escaping () -> any Gadget,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_outer() -> Outer {
			            func __safeDI_gadgetBuilder_Outer_DefaultService_Scope_gadget(_ scope: Outer.SafeDIMockScope_Gadget.DefaultService_Scope.gadget_Values, id: Code) -> any Gadget {
			                let gadget: any Gadget = LiveGadget(id: id)
			                return gadget
			            }
			            func __safeDI_gadgetBuilder_Outer(up: Outer.SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget>) -> Outer.SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget> {
			                .init(inner_serviceBuilder: { values in __safeDI_gadgetBuilder_Outer_Inner(up: up.inner_serviceBuilder(values), id: values.id) })
			            }
			            func __safeDI_gadgetBuilder_Outer_Inner(up: Inner.SafeDIMockScope_Service.__safeDI_Builder<Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>, id: Code) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			                .init(screenBuilder: { values in __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope(up: up.screenBuilder(values)) }, service: { _ in __safeDI_gadgetBuilder_Outer_DefaultService_Scope_(id: id) })
			            }
			            func __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope(up: Inner.SafeDIMockScope_Service.Screen_Scope.__safeDI_Builder<Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDIMockScope_Service.Screen_Scope.__safeDI_Builder<Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			                .init(service: { values in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(up: up.service(values), id: values.id) })
			            }
			            func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(up: Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>, id: String) -> Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
			                .init(gadget: up.gadget)
			            }
			            func __safeDI_gadgetBuilder_Outer_DefaultService_Scope_(id: Code) -> Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
			                .init(gadget: { scope in __safeDI_gadgetBuilder_Outer_DefaultService_Scope_gadget(scope, id: id) })
			            }
			            _ = Outer.__safeDI_Outer_mock_EC7E20025BEDA1D4.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Outer.__safeDI_mock(gadgetBuilder: __safeDI_gadgetBuilder_Outer(up: .init(__safeDI_noScope: gadgetBuilder)), safeDIOverrides: safeDIOverrides.outer)
			        }
			        let outer: Outer = __safeDI_outer()
			        return Root(outer: outer)
			    }
			}
			#endif
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsPlaceOnRouteOfCalledMockThatHoldsValueAndPassesItUpOnOther_whenOneCaseOfCalledMockStandsForTwoPlacesOneRouteOfWhichHoldsValue() async throws {
		// `Inner` builds `Model`, whose `service` is a hole, in `Page`, which binds `token` before it, and at its root: one case
		// of `Inner`'s, `Model_Scope.service`, stands for both places, and `Outer` fills it with one fill, so one place of
		// `Outer`'s, `gadget`, is reached on both routes. `LiveGadget` requires `token`, which only the `page` route holds: `App`
		// fills the place on that route and passes it up on the other, so its mock takes a builder for it.
		try await expectPlaceInsideFill(
			feature: [
				"public protocol Service {}\npublic protocol Gadget {}",
				seamFixtureType(named: "Token", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Model", declarations: ["@Instantiated public let service: any Service"]),
				seamFixtureType(named: "Page", declarations: ["@Instantiated public let token: Token", "@Instantiated public let model: Model"]),
				Self.publicMockType(named: "Inner", declarations: ["@Instantiated public let page: Page", "@Instantiated public let model: Model"]),
			],
			middle: [
				Self.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let gadget: any Gadget"]),
				Self.publicMockType(named: "Outer", declarations: ["@Instantiated public let inner: Inner"]),
			],
			app: [
				Self.passedUpGadget,
				Self.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received public let token: Token"]),
				Self.mockedRoot(declarations: ["@Instantiated public let outer: Outer"]),
			],
			probes: [Self.probe(".outer.inner.page", builders: "gadgetBuilder: { PassedUpGadget() }")],
			expectedMiddle: """
			#if canImport(Feature)
			import Feature
			#endif

			#if DEBUG
			extension Outer {
			    nonisolated public enum SafeDIMockScope_Gadget {
			        nonisolated public struct inner_serviceBuilder_Values {}

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
			            public let inner_serviceBuilder: (inner_serviceBuilder_Values) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(inner_serviceBuilder: @escaping (inner_serviceBuilder_Values) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.inner_serviceBuilder = inner_serviceBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.inner_serviceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            inner: Inner.SafeDIOverrides = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                inner: inner
			            )
			        }

			        public var inner: Inner.SafeDIOverrides { __safeDI_storage.inner }

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

			    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    public static func mock(
			        gadgetBuilder: @escaping () -> any Gadget,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Outer {
			        Outer.__safeDI_mock(gadgetBuilder: .init(__safeDI_noScope: gadgetBuilder), safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        gadgetBuilder __safeDI_gadgetBuilder: Outer.SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget>,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Outer {
			        let __safeDI_gadgetBuilder_inner_serviceBuilder = __safeDI_gadgetBuilder.inner_serviceBuilder(SafeDIMockScope_Gadget.inner_serviceBuilder_Values())
			        func __safeDI_inner() -> Inner {
			            func __safeDI_serviceBuilder_Inner_Model_Scope_service(_ scope: Inner.SafeDIMockScope_Service.Model_Scope.service_Values, __safeDI_inner_serviceBuilder: SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let gadget: any Gadget = __safeDI_inner_serviceBuilder.gadget(SafeDIMockScope_Gadget.DefaultService_Scope.gadget_Values())
			                    return DefaultService(gadget: gadget)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Inner(up: Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(page: { values in __safeDI_serviceBuilder_Inner_Page_Scope(up: up.page(values)) }, model: { values in __safeDI_serviceBuilder_Inner_Model_Scope(up: up.model(values)) })
			            }
			            func __safeDI_serviceBuilder_Inner_Page_Scope(up: Inner.SafeDIMockScope_Service.Page_Scope.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDIMockScope_Service.Page_Scope.__safeDI_Builder<any Service> {
			                .init(model: { values in __safeDI_serviceBuilder_Inner_Model_Scope(up: up.model(values)) })
			            }
			            func __safeDI_serviceBuilder_Inner_Model_Scope(up: Inner.SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<any Service> {
			                .init(service: { scope in __safeDI_serviceBuilder_Inner_Model_Scope_service(scope, __safeDI_inner_serviceBuilder: up.service(scope)) })
			            }
			            _ = Inner.__safeDI_Inner_mock_C638028EA3E6E9BE.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Inner.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder_Inner(up: __safeDI_gadgetBuilder_inner_serviceBuilder), safeDIOverrides: safeDIOverrides.inner)
			        }
			        let inner: Inner = __safeDI_inner()
			        return Outer(inner: inner)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_mock_A608CCDC9FD8CDC3 {}
			}
			#endif
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            outer: Outer.SafeDIOverrides = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                outer: outer
			            )
			        }

			        var outer: Outer.SafeDIOverrides { __safeDI_storage.outer }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                outer: Outer.SafeDIOverrides
			            ) {
			                self.outer = outer
			            }

			            let outer: Outer.SafeDIOverrides
			        }
			    }

			    static func mock(
			        gadgetBuilder: @escaping () -> any Gadget,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_outer() -> Outer {
			            func __safeDI_gadgetBuilder_Outer_DefaultService_Scope_gadget(_ scope: Outer.SafeDIMockScope_Gadget.DefaultService_Scope.gadget_Values, token: Token) -> any Gadget {
			                let gadget: any Gadget = LiveGadget(token: token)
			                return gadget
			            }
			            func __safeDI_gadgetBuilder_Outer(up: Outer.SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget>) -> Outer.SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget> {
			                .init(inner_serviceBuilder: { values in __safeDI_gadgetBuilder_Outer_Inner(up: up.inner_serviceBuilder(values)) })
			            }
			            func __safeDI_gadgetBuilder_Outer_Inner(up: Inner.SafeDIMockScope_Service.__safeDI_Builder<Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			                .init(page: { _ in __safeDI_gadgetBuilder_Outer_Inner_Page_Scope() }, model: { values in __safeDI_gadgetBuilder_Outer_Inner_Model_Scope_(up: up.model(values)) })
			            }
			            func __safeDI_gadgetBuilder_Outer_Inner_Page_Scope() -> Inner.SafeDIMockScope_Service.Page_Scope.__safeDI_Builder<Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			                .init(model: { values in __safeDI_gadgetBuilder_Outer_Inner_Model_Scope(token: values.token) })
			            }
			            func __safeDI_gadgetBuilder_Outer_Inner_Model_Scope(token: Token) -> Inner.SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			                .init(service: { _ in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(token: token) })
			            }
			            func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(token: Token) -> Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
			                .init(gadget: { scope in __safeDI_gadgetBuilder_Outer_DefaultService_Scope_gadget(scope, token: token) })
			            }
			            func __safeDI_gadgetBuilder_Outer_Inner_Model_Scope_(up: Inner.SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			                .init(service: { values in __safeDI_gadgetBuilder_Outer_DefaultService_Scope_(up: up.service(values)) })
			            }
			            func __safeDI_gadgetBuilder_Outer_DefaultService_Scope_(up: Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
			                .init(gadget: up.gadget)
			            }
			            _ = Outer.__safeDI_Outer_mock_A608CCDC9FD8CDC3.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Outer.__safeDI_mock(gadgetBuilder: __safeDI_gadgetBuilder_Outer(up: .init(__safeDI_noScope: gadgetBuilder)), safeDIOverrides: safeDIOverrides.outer)
			        }
			        let outer: Outer = __safeDI_outer()
			        return Root(outer: outer)
			    }
			}
			#endif
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesNoBuilderOfPlainRoutes_whenOnlyPlaceInsideSendableFunctionOfPublicMocksFillLacksValueItsFillRequires() async throws {
		// `Inner` builds `service`, a hole, at its root and in the `Screen` its `SendableInstantiator` builds, and `Outer`
		// fills both with `DefaultService`, whose `gadget` only `App` can build: `DefaultService_Scope` is held by `Outer`'s
		// plain root enum and by its `@Sendable` one. `LiveGadget` requires `tag`, which `Outer` binds outside the `@Sendable`
		// function: `App` fills the place on the plain routes and passes it up on the `@Sendable` ones, so each root has a
		// dispatcher of `DefaultService_Scope` of its own, and the mock takes a builder for the `@Sendable` routes only.
		try await expectPlaceInsideFill(
			feature: Self.inner(screen: ["@Forwarded public let id: Int"], innerScreenBuilder: "SendableInstantiator<Screen>", conformances: ", Sendable"),
			middle: [
				seamFixtureType(named: "Tag", isFinalClass: true, declarations: [], conformances: ", Sendable"),
				Self.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let gadget: any Gadget"], conformances: ", Sendable"),
				Self.publicMockType(named: "Outer", declarations: ["@Instantiated public let tag: Tag", "@Instantiated public let inner: Inner"], conformances: ", Sendable"),
			],
			app: [
				Self.passedUpGadget,
				Self.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received public let tag: Tag"], conformances: ", Sendable"),
				Self.mockedRoot(declarations: ["@Instantiated public let outer: Outer"]),
			],
			probes: [Self.probe(".outer.inner.service", builders: "gadgetSendableBuilder: { PassedUpGadget() }")],
			expectedMiddle: """
			#if canImport(Feature)
			import Feature
			#endif

			#if DEBUG
			extension Outer {
			    nonisolated public enum SafeDIMockScope_Gadget {
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
			            public let inner_serviceBuilder: (inner_serviceBuilder_Values) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(inner_serviceBuilder: @escaping (inner_serviceBuilder_Values) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.inner_serviceBuilder = inner_serviceBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.inner_serviceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
			            }
			        }
			    }

			    nonisolated public enum SafeDISendableMockScope_Gadget {
			        nonisolated public struct inner_serviceSendableBuilder_Values: Sendable {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			            public let inner_serviceSendableBuilder: @Sendable (inner_serviceSendableBuilder_Values) -> Inner.SafeDISendableMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(inner_serviceSendableBuilder: @escaping @Sendable (inner_serviceSendableBuilder_Values) -> Inner.SafeDISendableMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.inner_serviceSendableBuilder = inner_serviceSendableBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                self.inner_serviceSendableBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            tag: (() -> Tag)? = nil,
			            inner: Inner.SafeDIOverrides = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                tag: tag,
			                inner: inner
			            )
			        }

			        public var tag: (() -> Tag)? { __safeDI_storage.tag }
			        public var inner: Inner.SafeDIOverrides { __safeDI_storage.inner }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                tag: (() -> Tag)?,
			                inner: Inner.SafeDIOverrides
			            ) {
			                self.tag = tag
			                self.inner = inner
			            }

			            let tag: (() -> Tag)?
			            let inner: Inner.SafeDIOverrides
			        }
			    }

			    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    public static func mock(
			        gadgetBuilder: @escaping () -> any Gadget,
			        gadgetSendableBuilder: @escaping @Sendable () -> any Gadget,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Outer {
			        Outer.__safeDI_mock(gadgetBuilder: .init(__safeDI_noScope: gadgetBuilder), gadgetSendableBuilder: .init(__safeDI_noScope: gadgetSendableBuilder), safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        gadgetBuilder __safeDI_gadgetBuilder: Outer.SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget>,
			        gadgetSendableBuilder __safeDI_gadgetSendableBuilder: Outer.SafeDISendableMockScope_Gadget.__safeDI_Builder<any Gadget>,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Outer {
			        let tag = if let safeDIBuilder = safeDIOverrides.tag { safeDIBuilder() } else { Tag() }
			        let __safeDI_gadgetBuilder_inner_serviceBuilder = __safeDI_gadgetBuilder.inner_serviceBuilder(SafeDIMockScope_Gadget.inner_serviceBuilder_Values(tag: tag))
			        func __safeDI_inner() -> Inner {
			            let __safeDI_gadgetSendableBuilder_inner_serviceSendableBuilder = __safeDI_gadgetSendableBuilder.inner_serviceSendableBuilder(SafeDISendableMockScope_Gadget.inner_serviceSendableBuilder_Values())
			            func __safeDI_serviceBuilder_Inner_service(_ scope: Inner.SafeDIMockScope_Service.service_Values, __safeDI_inner_serviceBuilder: SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let gadget: any Gadget = __safeDI_inner_serviceBuilder.gadget(SafeDIMockScope_Gadget.DefaultService_Scope.gadget_Values())
			                    return DefaultService(gadget: gadget)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            @Sendable func __safeDI_serviceSendableBuilder_Inner_Screen_Scope_service(_ scope: Inner.SafeDIMockScope_Service.Screen_Scope.service_Values, __safeDI_inner_serviceSendableBuilder: SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let gadget: any Gadget = __safeDI_inner_serviceSendableBuilder.gadget(SafeDIMockScope_Gadget.DefaultService_Scope.gadget_Values())
			                    return DefaultService(gadget: gadget)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Inner(up: Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(service: { scope in __safeDI_serviceBuilder_Inner_service(scope, __safeDI_inner_serviceBuilder: up.service(scope)) })
			            }
			            @Sendable nonisolated func __safeDI_serviceSendableBuilder_Inner(up: Inner.SafeDISendableMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDISendableMockScope_Service.__safeDI_Builder<any Service> {
			                .init(screenBuilder: { values in __safeDI_serviceBuilder_Inner_Screen_Scope(up: up.screenBuilder(values)) })
			            }
			            @Sendable nonisolated func __safeDI_serviceBuilder_Inner_Screen_Scope(up: Inner.SafeDIMockScope_Service.Screen_Scope.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDIMockScope_Service.Screen_Scope.__safeDI_Builder<any Service> {
			                .init(service: { scope in __safeDI_serviceSendableBuilder_Inner_Screen_Scope_service(scope, __safeDI_inner_serviceSendableBuilder: up.service(scope)) })
			            }
			            _ = Inner.__safeDI_Inner_mock_64ACDFE38FB4BDEE.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Inner.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder_Inner(up: __safeDI_gadgetBuilder_inner_serviceBuilder), serviceSendableBuilder: __safeDI_serviceSendableBuilder_Inner(up: __safeDI_gadgetSendableBuilder_inner_serviceSendableBuilder), safeDIOverrides: safeDIOverrides.inner)
			        }
			        let inner: Inner = __safeDI_inner()
			        return Outer(tag: tag, inner: inner)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_mock_B539772B579C669F {}
			}
			#endif
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            outer: Outer.SafeDIOverrides = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                outer: outer
			            )
			        }

			        var outer: Outer.SafeDIOverrides { __safeDI_storage.outer }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                outer: Outer.SafeDIOverrides
			            ) {
			                self.outer = outer
			            }

			            let outer: Outer.SafeDIOverrides
			        }
			    }

			    static func mock(
			        gadgetSendableBuilder: @escaping @Sendable () -> any Gadget,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_outer() -> Outer {
			            func __safeDI_gadgetBuilder_Outer() -> Outer.SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget> {
			                .init(inner_serviceBuilder: { values in __safeDI_gadgetBuilder_Outer_Inner(tag: values.tag) })
			            }
			            func __safeDI_gadgetBuilder_Outer_Inner(tag: Tag) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			                .init(service: { _ in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(tag: tag) })
			            }
			            func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(tag: Tag) -> Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
			                .init(gadget: { _ in
			                    let gadget: any Gadget = LiveGadget(tag: tag)
			                    return gadget
			                })
			            }
			            _ = Outer.__safeDI_Outer_mock_B539772B579C669F.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Outer.__safeDI_mock(gadgetBuilder: __safeDI_gadgetBuilder_Outer(), gadgetSendableBuilder: .init(__safeDI_noScope: gadgetSendableBuilder), safeDIOverrides: safeDIOverrides.outer)
			        }
			        let outer: Outer = __safeDI_outer()
			        return Root(outer: outer)
			    }
			}
			#endif
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresDispatcherOfEachRootsRoutes_whenEnumBothRootsHoldPassesPlaceUpOnlyOnSendableRoutes() async throws {
		// As above, but `DefaultService` also builds `Helper`, which binds `tag` before its own `gadget`: on the `@Sendable`
		// routes `App` fills `Helper`'s place and passes `DefaultService`'s up, and on the plain routes it fills both. Each root
		// has a dispatcher of `DefaultService_Scope` of its own, the plain one with no `passUp`, and both share
		// `Helper_Scope`'s.
		try await expectPlaceInsideFill(
			feature: Self.inner(screen: ["@Forwarded public let id: Int"], innerScreenBuilder: "SendableInstantiator<Screen>", conformances: ", Sendable"),
			middle: [
				seamFixtureType(named: "Tag", isFinalClass: true, declarations: [], conformances: ", Sendable"),
				seamFixtureType(named: "Helper", declarations: ["@Instantiated public let tag: Tag", "@Instantiated public let gadget: any Gadget"], conformances: ", Sendable"),
				Self.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let gadget: any Gadget", "@Instantiated public let helper: Helper"], conformances: ", Sendable"),
				Self.publicMockType(named: "Outer", declarations: ["@Instantiated public let tag: Tag", "@Instantiated public let inner: Inner"], conformances: ", Sendable"),
			],
			app: [
				Self.passedUpGadget,
				Self.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received public let tag: Tag"], conformances: ", Sendable"),
				Self.mockedRoot(declarations: ["@Instantiated public let outer: Outer"]),
			],
			probes: [Self.probe(".outer.inner.service", builders: "gadgetSendableBuilder: { PassedUpGadget() }")],
			expectedMiddle: """
			#if canImport(Feature)
			import Feature
			#endif

			#if DEBUG
			extension Outer {
			    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    nonisolated public enum SafeDIMockScope_Gadget {
			        nonisolated public struct inner_serviceBuilder_Values {
			            public let tag: Tag
			        }

			        nonisolated public enum DefaultService_Scope {
			            nonisolated public struct gadget_Values {}

			            nonisolated public struct helper_Values {
			                public let gadget: any Gadget
			            }

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let gadget: (gadget_Values) -> __safeDI_Built
			                public let helper: (helper_Values) -> SafeDIMockScope_Gadget.Helper_Scope.__safeDI_Builder<__safeDI_Built>

			                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built, helper: @escaping (helper_Values) -> SafeDIMockScope_Gadget.Helper_Scope.__safeDI_Builder<__safeDI_Built>) {
			                    self.gadget = gadget
			                    self.helper = helper
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.gadget = { _ in __safeDI_builder() }
			                    self.helper = { _ in .init(__safeDI_noScope: __safeDI_builder) }
			                }
			            }
			        }

			        nonisolated public enum Helper_Scope {
			            nonisolated public struct gadget_Values {
			                public let tag: Tag
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
			            public let inner_serviceBuilder: (inner_serviceBuilder_Values) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(inner_serviceBuilder: @escaping (inner_serviceBuilder_Values) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.inner_serviceBuilder = inner_serviceBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.inner_serviceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
			            }
			        }
			    }

			    nonisolated public enum SafeDISendableMockScope_Gadget {
			        nonisolated public struct inner_serviceSendableBuilder_Values: Sendable {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			            public let inner_serviceSendableBuilder: @Sendable (inner_serviceSendableBuilder_Values) -> Inner.SafeDISendableMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(inner_serviceSendableBuilder: @escaping @Sendable (inner_serviceSendableBuilder_Values) -> Inner.SafeDISendableMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.inner_serviceSendableBuilder = inner_serviceSendableBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                self.inner_serviceSendableBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            tag: (() -> Tag)? = nil,
			            inner: Inner.SafeDIOverrides = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                tag: tag,
			                inner: inner
			            )
			        }

			        public var tag: (() -> Tag)? { __safeDI_storage.tag }
			        public var inner: Inner.SafeDIOverrides { __safeDI_storage.inner }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                tag: (() -> Tag)?,
			                inner: Inner.SafeDIOverrides
			            ) {
			                self.tag = tag
			                self.inner = inner
			            }

			            let tag: (() -> Tag)?
			            let inner: Inner.SafeDIOverrides
			        }
			    }

			    public static func mock(
			        gadgetBuilder: @escaping () -> any Gadget,
			        gadgetSendableBuilder: @escaping @Sendable () -> any Gadget,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Outer {
			        Outer.__safeDI_mock(gadgetBuilder: .init(__safeDI_noScope: gadgetBuilder), gadgetSendableBuilder: .init(__safeDI_noScope: gadgetSendableBuilder), safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        gadgetBuilder __safeDI_gadgetBuilder: Outer.SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget>,
			        gadgetSendableBuilder __safeDI_gadgetSendableBuilder: Outer.SafeDISendableMockScope_Gadget.__safeDI_Builder<any Gadget>,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Outer {
			        let tag = if let safeDIBuilder = safeDIOverrides.tag { safeDIBuilder() } else { Tag() }
			        let __safeDI_gadgetBuilder_inner_serviceBuilder = __safeDI_gadgetBuilder.inner_serviceBuilder(SafeDIMockScope_Gadget.inner_serviceBuilder_Values(tag: tag))
			        func __safeDI_inner() -> Inner {
			            let __safeDI_gadgetSendableBuilder_inner_serviceSendableBuilder = __safeDI_gadgetSendableBuilder.inner_serviceSendableBuilder(SafeDISendableMockScope_Gadget.inner_serviceSendableBuilder_Values())
			            func __safeDI_serviceBuilder_Inner_service(_ scope: Inner.SafeDIMockScope_Service.service_Values, __safeDI_inner_serviceBuilder: SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let gadget: any Gadget = __safeDI_inner_serviceBuilder.gadget(SafeDIMockScope_Gadget.DefaultService_Scope.gadget_Values())
			                    let __safeDI_gadgetBuilder_helper = __safeDI_inner_serviceBuilder.helper(SafeDIMockScope_Gadget.DefaultService_Scope.helper_Values(gadget: gadget))
			                    func __safeDI_helper() -> Helper {
			                        let tag = Tag()
			                        let gadget: any Gadget = __safeDI_gadgetBuilder_helper.gadget(SafeDIMockScope_Gadget.Helper_Scope.gadget_Values(tag: tag))
			                        return Helper(tag: tag, gadget: gadget)
			                    }
			                    let helper: Helper = __safeDI_helper()
			                    return DefaultService(gadget: gadget, helper: helper)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            @Sendable func __safeDI_serviceSendableBuilder_Inner_Screen_Scope_service(_ scope: Inner.SafeDIMockScope_Service.Screen_Scope.service_Values, __safeDI_inner_serviceSendableBuilder: SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let gadget: any Gadget = __safeDI_inner_serviceSendableBuilder.gadget(SafeDIMockScope_Gadget.DefaultService_Scope.gadget_Values())
			                    let __safeDI_gadgetSendableBuilder_helper = __safeDI_inner_serviceSendableBuilder.helper(SafeDIMockScope_Gadget.DefaultService_Scope.helper_Values(gadget: gadget))
			                    func __safeDI_helper() -> Helper {
			                        let tag = Tag()
			                        let gadget: any Gadget = __safeDI_gadgetSendableBuilder_helper.gadget(SafeDIMockScope_Gadget.Helper_Scope.gadget_Values(tag: tag))
			                        return Helper(tag: tag, gadget: gadget)
			                    }
			                    let helper: Helper = __safeDI_helper()
			                    return DefaultService(gadget: gadget, helper: helper)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Inner(up: Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(service: { scope in __safeDI_serviceBuilder_Inner_service(scope, __safeDI_inner_serviceBuilder: up.service(scope)) })
			            }
			            @Sendable nonisolated func __safeDI_serviceSendableBuilder_Inner(up: Inner.SafeDISendableMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDISendableMockScope_Service.__safeDI_Builder<any Service> {
			                .init(screenBuilder: { values in __safeDI_serviceBuilder_Inner_Screen_Scope(up: up.screenBuilder(values)) })
			            }
			            @Sendable nonisolated func __safeDI_serviceBuilder_Inner_Screen_Scope(up: Inner.SafeDIMockScope_Service.Screen_Scope.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDIMockScope_Service.Screen_Scope.__safeDI_Builder<any Service> {
			                .init(service: { scope in __safeDI_serviceSendableBuilder_Inner_Screen_Scope_service(scope, __safeDI_inner_serviceSendableBuilder: up.service(scope)) })
			            }
			            _ = Inner.__safeDI_Inner_mock_64ACDFE38FB4BDEE.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Inner.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder_Inner(up: __safeDI_gadgetBuilder_inner_serviceBuilder), serviceSendableBuilder: __safeDI_serviceSendableBuilder_Inner(up: __safeDI_gadgetSendableBuilder_inner_serviceSendableBuilder), safeDIOverrides: safeDIOverrides.inner)
			        }
			        let inner: Inner = __safeDI_inner()
			        return Outer(tag: tag, inner: inner)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_mock_9DB730503EBBD30C {}
			}
			#endif
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            outer: Outer.SafeDIOverrides = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                outer: outer
			            )
			        }

			        var outer: Outer.SafeDIOverrides { __safeDI_storage.outer }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                outer: Outer.SafeDIOverrides
			            ) {
			                self.outer = outer
			            }

			            let outer: Outer.SafeDIOverrides
			        }
			    }

			    static func mock(
			        gadgetSendableBuilder: @escaping @Sendable () -> any Gadget,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_outer() -> Outer {
			            func __safeDI_gadgetBuilder_Outer() -> Outer.SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget> {
			                .init(inner_serviceBuilder: { values in __safeDI_gadgetBuilder_Outer_Inner(tag: values.tag) })
			            }
			            func __safeDI_gadgetBuilder_Outer_Inner(tag: Tag) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			                .init(service: { _ in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(tag: tag) })
			            }
			            @Sendable nonisolated func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(tag: Tag) -> Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
			                .init(
			                    gadget: { _ in
			                        let gadget: any Gadget = LiveGadget(tag: tag)
			                        return gadget
			                    },
			                    helper: { _ in __safeDI_gadgetBuilder_Outer_Helper_Scope() }
			                )
			            }
			            @Sendable nonisolated func __safeDI_gadgetBuilder_Outer_Helper_Scope() -> Outer.SafeDIMockScope_Gadget.Helper_Scope.__safeDI_Builder<any Gadget> {
			                .init(gadget: { scope in
			                    let tag = scope.tag
			                    let gadget: any Gadget = LiveGadget(tag: tag)
			                    return gadget
			                })
			            }
			            @Sendable nonisolated func __safeDI_gadgetSendableBuilder_Outer(up: Outer.SafeDISendableMockScope_Gadget.__safeDI_Builder<any Gadget>) -> Outer.SafeDISendableMockScope_Gadget.__safeDI_Builder<any Gadget> {
			                .init(inner_serviceSendableBuilder: { values in __safeDI_gadgetBuilder_Outer_Inner_(up: up.inner_serviceSendableBuilder(values)) })
			            }
			            @Sendable nonisolated func __safeDI_gadgetBuilder_Outer_Inner_(up: Inner.SafeDISendableMockScope_Service.__safeDI_Builder<Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDISendableMockScope_Service.__safeDI_Builder<Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			                .init(screenBuilder: { values in __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope(up: up.screenBuilder(values)) })
			            }
			            @Sendable nonisolated func __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope(up: Inner.SafeDIMockScope_Service.Screen_Scope.__safeDI_Builder<Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDIMockScope_Service.Screen_Scope.__safeDI_Builder<Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			                .init(service: { values in __safeDI_gadgetBuilder_Outer_DefaultService_Scope_(up: up.service(values)) })
			            }
			            @Sendable nonisolated func __safeDI_gadgetBuilder_Outer_DefaultService_Scope_(up: Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
			                .init(gadget: up.gadget, helper: { _ in __safeDI_gadgetBuilder_Outer_Helper_Scope() })
			            }
			            _ = Outer.__safeDI_Outer_mock_9DB730503EBBD30C.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Outer.__safeDI_mock(gadgetBuilder: __safeDI_gadgetBuilder_Outer(), gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_Outer(up: .init(__safeDI_noScope: gadgetSendableBuilder)), safeDIOverrides: safeDIOverrides.outer)
			        }
			        let outer: Outer = __safeDI_outer()
			        return Root(outer: outer)
			    }
			}
			#endif
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_nestsEachTypeInsideFillByType_whenPublicMocksPlaceIsTwoTypesDeepInsideFill() async throws {
		// `DefaultService` builds `Widget`, which binds `tool` before its `gadget`: `DefaultService_Scope` holds
		// `Widget_Scope`, whose level carries `tool`.
		try await expectPlaceInsideFill(
			feature: Self.inner(screen: ["@Forwarded public let id: Int"]),
			middle: [
				seamFixtureType(named: "Tag", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Tool", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Widget", declarations: ["@Instantiated public let tool: Tool", "@Instantiated public let gadget: any Gadget"]),
				Self.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let widget: Widget"]),
				Self.publicMockType(named: "Outer", declarations: ["@Instantiated public let tag: Tag", "@Instantiated public let inner: Inner"]),
			],
			app: [
				Self.passedUpGadget,
				Self.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received public let tag: Tag", "@Received public let tool: Tool", "@Received(onlyIfAvailable: true) public let id: Int?"]),
				Self.mockedRoot(declarations: ["@Instantiated public let outer: Outer"]),
			],
			probes: [Self.probe(".outer.inner.screenBuilder.instantiate(3)", builders: "gadgetBuilder: { PassedUpGadget() }")],
			expectedMiddle: """
			#if canImport(Feature)
			import Feature
			#endif

			#if DEBUG
			extension Outer {
			    nonisolated public enum SafeDIMockScope_Gadget {
			        nonisolated public struct inner_serviceBuilder_Values {
			            public let tag: Tag
			        }

			        nonisolated public enum DefaultService_Scope {
			            nonisolated public struct widget_Values {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let widget: (widget_Values) -> SafeDIMockScope_Gadget.Widget_Scope.__safeDI_Builder<__safeDI_Built>

			                public init(widget: @escaping (widget_Values) -> SafeDIMockScope_Gadget.Widget_Scope.__safeDI_Builder<__safeDI_Built>) {
			                    self.widget = widget
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.widget = { _ in .init(__safeDI_noScope: __safeDI_builder) }
			                }
			            }
			        }

			        nonisolated public enum Widget_Scope {
			            nonisolated public struct gadget_Values {
			                public let tool: Tool
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
			            public let inner_serviceBuilder: (inner_serviceBuilder_Values) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(inner_serviceBuilder: @escaping (inner_serviceBuilder_Values) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.inner_serviceBuilder = inner_serviceBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.inner_serviceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            tag: (() -> Tag)? = nil,
			            inner: Inner.SafeDIOverrides = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                tag: tag,
			                inner: inner
			            )
			        }

			        public var tag: (() -> Tag)? { __safeDI_storage.tag }
			        public var inner: Inner.SafeDIOverrides { __safeDI_storage.inner }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                tag: (() -> Tag)?,
			                inner: Inner.SafeDIOverrides
			            ) {
			                self.tag = tag
			                self.inner = inner
			            }

			            let tag: (() -> Tag)?
			            let inner: Inner.SafeDIOverrides
			        }
			    }

			    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    public static func mock(
			        gadgetBuilder: @escaping () -> any Gadget,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Outer {
			        Outer.__safeDI_mock(gadgetBuilder: .init(__safeDI_noScope: gadgetBuilder), safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        gadgetBuilder __safeDI_gadgetBuilder: Outer.SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget>,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Outer {
			        let tag = if let safeDIBuilder = safeDIOverrides.tag { safeDIBuilder() } else { Tag() }
			        let __safeDI_gadgetBuilder_inner_serviceBuilder = __safeDI_gadgetBuilder.inner_serviceBuilder(SafeDIMockScope_Gadget.inner_serviceBuilder_Values(tag: tag))
			        func __safeDI_inner() -> Inner {
			            func __safeDI_serviceBuilder_Inner_service(_ scope: Inner.SafeDIMockScope_Service.service_Values, __safeDI_inner_serviceBuilder: SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let __safeDI_gadgetBuilder_widget = __safeDI_inner_serviceBuilder.widget(SafeDIMockScope_Gadget.DefaultService_Scope.widget_Values())
			                    func __safeDI_widget() -> Widget {
			                        let tool = Tool()
			                        let gadget: any Gadget = __safeDI_gadgetBuilder_widget.gadget(SafeDIMockScope_Gadget.Widget_Scope.gadget_Values(tool: tool))
			                        return Widget(tool: tool, gadget: gadget)
			                    }
			                    let widget: Widget = __safeDI_widget()
			                    return DefaultService(widget: widget)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Inner_Screen_Scope_service(_ scope: Inner.SafeDIMockScope_Service.Screen_Scope.service_Values, __safeDI_inner_serviceBuilder: SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let __safeDI_gadgetBuilder_widget = __safeDI_inner_serviceBuilder.widget(SafeDIMockScope_Gadget.DefaultService_Scope.widget_Values())
			                    func __safeDI_widget() -> Widget {
			                        let tool = Tool()
			                        let gadget: any Gadget = __safeDI_gadgetBuilder_widget.gadget(SafeDIMockScope_Gadget.Widget_Scope.gadget_Values(tool: tool))
			                        return Widget(tool: tool, gadget: gadget)
			                    }
			                    let widget: Widget = __safeDI_widget()
			                    return DefaultService(widget: widget)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Inner(up: Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(screenBuilder: { values in __safeDI_serviceBuilder_Inner_Screen_Scope(up: up.screenBuilder(values)) }, service: { scope in __safeDI_serviceBuilder_Inner_service(scope, __safeDI_inner_serviceBuilder: up.service(scope)) })
			            }
			            func __safeDI_serviceBuilder_Inner_Screen_Scope(up: Inner.SafeDIMockScope_Service.Screen_Scope.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDIMockScope_Service.Screen_Scope.__safeDI_Builder<any Service> {
			                .init(service: { scope in __safeDI_serviceBuilder_Inner_Screen_Scope_service(scope, __safeDI_inner_serviceBuilder: up.service(scope)) })
			            }
			            _ = Inner.__safeDI_Inner_mock_3EBB13A82C3BF964.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Inner.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder_Inner(up: __safeDI_gadgetBuilder_inner_serviceBuilder), safeDIOverrides: safeDIOverrides.inner)
			        }
			        let inner: Inner = __safeDI_inner()
			        return Outer(tag: tag, inner: inner)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_mock_C15463E4215F6B6A {}
			}
			#endif
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            outer: Outer.SafeDIOverrides = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                outer: outer
			            )
			        }

			        var outer: Outer.SafeDIOverrides { __safeDI_storage.outer }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                outer: Outer.SafeDIOverrides
			            ) {
			                self.outer = outer
			            }

			            let outer: Outer.SafeDIOverrides
			        }
			    }

			    static func mock(
			        gadgetBuilder: @escaping () -> any Gadget,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_outer() -> Outer {
			            func __safeDI_gadgetBuilder_Outer_Widget_Scope_gadget(_ scope: Outer.SafeDIMockScope_Gadget.Widget_Scope.gadget_Values, tag: Tag, id: Int?) -> any Gadget {
			                let tool = scope.tool
			                let gadget: any Gadget = LiveGadget(tag: tag, tool: tool, id: id)
			                return gadget
			            }
			            func __safeDI_gadgetBuilder_Outer(up: Outer.SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget>) -> Outer.SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget> {
			                .init(inner_serviceBuilder: { values in __safeDI_gadgetBuilder_Outer_Inner(up: up.inner_serviceBuilder(values), tag: values.tag) })
			            }
			            func __safeDI_gadgetBuilder_Outer_Inner(up: Inner.SafeDIMockScope_Service.__safeDI_Builder<Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>, tag: Tag) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			                .init(screenBuilder: { _ in __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope(tag: tag) }, service: { values in __safeDI_gadgetBuilder_Outer_DefaultService_Scope_(up: up.service(values), tag: tag) })
			            }
			            func __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope(tag: Tag) -> Inner.SafeDIMockScope_Service.Screen_Scope.__safeDI_Builder<Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			                .init(service: { values in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: values.id, tag: tag) })
			            }
			            func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: Int, tag: Tag) -> Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
			                .init(widget: { _ in __safeDI_gadgetBuilder_Outer_Widget_Scope(id: id, tag: tag) })
			            }
			            func __safeDI_gadgetBuilder_Outer_Widget_Scope(id: Int, tag: Tag) -> Outer.SafeDIMockScope_Gadget.Widget_Scope.__safeDI_Builder<any Gadget> {
			                .init(gadget: { scope in __safeDI_gadgetBuilder_Outer_Widget_Scope_gadget(scope, tag: tag, id: id) })
			            }
			            func __safeDI_gadgetBuilder_Outer_DefaultService_Scope_(up: Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>, tag: Tag) -> Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
			                .init(widget: { values in __safeDI_gadgetBuilder_Outer_Widget_Scope_(up: up.widget(values), tag: tag) })
			            }
			            func __safeDI_gadgetBuilder_Outer_Widget_Scope_(up: Outer.SafeDIMockScope_Gadget.Widget_Scope.__safeDI_Builder<any Gadget>, tag: Tag) -> Outer.SafeDIMockScope_Gadget.Widget_Scope.__safeDI_Builder<any Gadget> {
			                .init(gadget: up.gadget)
			            }
			            _ = Outer.__safeDI_Outer_mock_C15463E4215F6B6A.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Outer.__safeDI_mock(gadgetBuilder: __safeDI_gadgetBuilder_Outer(up: .init(__safeDI_noScope: gadgetBuilder)), safeDIOverrides: safeDIOverrides.outer)
			        }
			        let outer: Outer = __safeDI_outer()
			        return Root(outer: outer)
			    }
			}
			#endif
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_holdsCallsCaseInFulfillersEnum_whenPublicMocksPlaceIsInsideFillOfCallInsideFill() async throws {
		// `DefaultService`, which fills `Inner`'s hole, calls `Holder`'s public mock, whose hole `Outer` fills with
		// `DefaultPart`, whose `gadget` only `App` can build: `DefaultService_Scope` has the case `holder_partBuilder`, which
		// holds `Holder`'s scope and `DefaultPart_Scope`. `LiveGadget` reads `label` through the reader of `Holder`'s levels
		// and `id` through the reader of `Inner`'s.
		try await expectPlaceInsideFill(
			feature: Self.inner(screen: ["@Forwarded public let id: Int"]) + [
				"public protocol Part {}",
				seamFixtureType(named: "Label", isFinalClass: true, declarations: []),
				Self.publicMockType(named: "Holder", declarations: ["@Instantiated public let label: Label", "@Instantiated public let part: any Part"]),
			],
			middle: [
				Self.fulfillingType(named: "DefaultPart", fulfilling: "Part", declarations: ["@Instantiated public let gadget: any Gadget"]),
				Self.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let holder: Holder"]),
				Self.publicMockType(named: "Outer", declarations: ["@Instantiated public let inner: Inner"]),
			],
			app: [
				Self.passedUpGadget,
				Self.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received public let label: Label", "@Received(onlyIfAvailable: true) public let id: Int?"]),
				Self.mockedRoot(declarations: ["@Instantiated public let outer: Outer"]),
			],
			probes: [Self.probe(".outer.inner.screenBuilder.instantiate(5)", builders: "gadgetBuilder: { PassedUpGadget() }")],
			expectedMiddle: """
			#if canImport(Feature)
			import Feature
			#endif

			#if DEBUG
			extension Outer {
			    nonisolated public enum SafeDIMockScope_Gadget {
			        nonisolated public struct inner_serviceBuilder_Values {}

			        nonisolated public enum DefaultService_Scope {
			            nonisolated public struct holder_partBuilder_Values {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let holder_partBuilder: (holder_partBuilder_Values) -> Holder.SafeDIMockScope_Part.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultPart_Scope.__safeDI_Builder<__safeDI_Built>>

			                public init(holder_partBuilder: @escaping (holder_partBuilder_Values) -> Holder.SafeDIMockScope_Part.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultPart_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                    self.holder_partBuilder = holder_partBuilder
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.holder_partBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
			                }
			            }
			        }

			        nonisolated public enum DefaultPart_Scope {
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
			            public let inner_serviceBuilder: (inner_serviceBuilder_Values) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(inner_serviceBuilder: @escaping (inner_serviceBuilder_Values) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.inner_serviceBuilder = inner_serviceBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.inner_serviceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            inner: Inner.SafeDIOverrides = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                inner: inner
			            )
			        }

			        public var inner: Inner.SafeDIOverrides { __safeDI_storage.inner }

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

			    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    public static func mock(
			        gadgetBuilder: @escaping () -> any Gadget,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Outer {
			        Outer.__safeDI_mock(gadgetBuilder: .init(__safeDI_noScope: gadgetBuilder), safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        gadgetBuilder __safeDI_gadgetBuilder: Outer.SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget>,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Outer {
			        let __safeDI_gadgetBuilder_inner_serviceBuilder = __safeDI_gadgetBuilder.inner_serviceBuilder(SafeDIMockScope_Gadget.inner_serviceBuilder_Values())
			        func __safeDI_inner() -> Inner {
			            func __safeDI_serviceBuilder_Inner_service(_ scope: Inner.SafeDIMockScope_Service.service_Values, __safeDI_inner_serviceBuilder: SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let __safeDI_gadgetBuilder_holder_partBuilder = __safeDI_inner_serviceBuilder.holder_partBuilder(SafeDIMockScope_Gadget.DefaultService_Scope.holder_partBuilder_Values())
			                    func __safeDI_holder() -> Holder {
			                        func __safeDI_partBuilder_Holder_part(_ scope: Holder.SafeDIMockScope_Part.part_Values, __safeDI_holder_partBuilder: SafeDIMockScope_Gadget.DefaultPart_Scope.__safeDI_Builder<any Gadget>) -> any Part {
			                            func __safeDI_part() -> DefaultPart {
			                                let gadget: any Gadget = __safeDI_holder_partBuilder.gadget(SafeDIMockScope_Gadget.DefaultPart_Scope.gadget_Values())
			                                return DefaultPart(gadget: gadget)
			                            }
			                            let part: any Part = __safeDI_part()
			                            return part
			                        }
			                        func __safeDI_partBuilder_Holder(up: Holder.SafeDIMockScope_Part.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultPart_Scope.__safeDI_Builder<any Gadget>>) -> Holder.SafeDIMockScope_Part.__safeDI_Builder<any Part> {
			                            .init(part: { scope in __safeDI_partBuilder_Holder_part(scope, __safeDI_holder_partBuilder: up.part(scope)) })
			                        }
			                        return Holder.__safeDI_mock(partBuilder: __safeDI_partBuilder_Holder(up: __safeDI_gadgetBuilder_holder_partBuilder))
			                    }
			                    let holder: Holder = __safeDI_holder()
			                    return DefaultService(holder: holder)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Inner_Screen_Scope_service(_ scope: Inner.SafeDIMockScope_Service.Screen_Scope.service_Values, __safeDI_inner_serviceBuilder: SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let __safeDI_gadgetBuilder_holder_partBuilder = __safeDI_inner_serviceBuilder.holder_partBuilder(SafeDIMockScope_Gadget.DefaultService_Scope.holder_partBuilder_Values())
			                    func __safeDI_holder() -> Holder {
			                        func __safeDI_partBuilder_Holder_part(_ scope: Holder.SafeDIMockScope_Part.part_Values, __safeDI_holder_partBuilder: SafeDIMockScope_Gadget.DefaultPart_Scope.__safeDI_Builder<any Gadget>) -> any Part {
			                            func __safeDI_part() -> DefaultPart {
			                                let gadget: any Gadget = __safeDI_holder_partBuilder.gadget(SafeDIMockScope_Gadget.DefaultPart_Scope.gadget_Values())
			                                return DefaultPart(gadget: gadget)
			                            }
			                            let part: any Part = __safeDI_part()
			                            return part
			                        }
			                        func __safeDI_partBuilder_Holder(up: Holder.SafeDIMockScope_Part.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultPart_Scope.__safeDI_Builder<any Gadget>>) -> Holder.SafeDIMockScope_Part.__safeDI_Builder<any Part> {
			                            .init(part: { scope in __safeDI_partBuilder_Holder_part(scope, __safeDI_holder_partBuilder: up.part(scope)) })
			                        }
			                        return Holder.__safeDI_mock(partBuilder: __safeDI_partBuilder_Holder(up: __safeDI_gadgetBuilder_holder_partBuilder))
			                    }
			                    let holder: Holder = __safeDI_holder()
			                    return DefaultService(holder: holder)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Inner(up: Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(screenBuilder: { values in __safeDI_serviceBuilder_Inner_Screen_Scope(up: up.screenBuilder(values)) }, service: { scope in __safeDI_serviceBuilder_Inner_service(scope, __safeDI_inner_serviceBuilder: up.service(scope)) })
			            }
			            func __safeDI_serviceBuilder_Inner_Screen_Scope(up: Inner.SafeDIMockScope_Service.Screen_Scope.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDIMockScope_Service.Screen_Scope.__safeDI_Builder<any Service> {
			                .init(service: { scope in __safeDI_serviceBuilder_Inner_Screen_Scope_service(scope, __safeDI_inner_serviceBuilder: up.service(scope)) })
			            }
			            _ = Inner.__safeDI_Inner_mock_3EBB13A82C3BF964.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Inner.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder_Inner(up: __safeDI_gadgetBuilder_inner_serviceBuilder), safeDIOverrides: safeDIOverrides.inner)
			        }
			        let inner: Inner = __safeDI_inner()
			        return Outer(inner: inner)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_mock_1D8B1AD505C8727C {}
			}
			#endif
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            outer: Outer.SafeDIOverrides = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                outer: outer
			            )
			        }

			        var outer: Outer.SafeDIOverrides { __safeDI_storage.outer }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                outer: Outer.SafeDIOverrides
			            ) {
			                self.outer = outer
			            }

			            let outer: Outer.SafeDIOverrides
			        }
			    }

			    static func mock(
			        gadgetBuilder: @escaping () -> any Gadget,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_outer() -> Outer {
			            func __safeDI_gadgetBuilder_Outer_DefaultPart_Scope_gadget(_ scope: Outer.SafeDIMockScope_Gadget.DefaultPart_Scope.gadget_Values, id: Int?, label: Label) -> any Gadget {
			                let gadget: any Gadget = LiveGadget(label: label, id: id)
			                return gadget
			            }
			            func __safeDI_gadgetBuilder_Outer(up: Outer.SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget>) -> Outer.SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget> {
			                .init(inner_serviceBuilder: { values in __safeDI_gadgetBuilder_Outer_Inner(up: up.inner_serviceBuilder(values)) })
			            }
			            func __safeDI_gadgetBuilder_Outer_Inner(up: Inner.SafeDIMockScope_Service.__safeDI_Builder<Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			                .init(screenBuilder: { _ in __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope() }, service: { values in __safeDI_gadgetBuilder_Outer_DefaultService_Scope_(up: up.service(values)) })
			            }
			            func __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope() -> Inner.SafeDIMockScope_Service.Screen_Scope.__safeDI_Builder<Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			                .init(service: { values in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: values.id) })
			            }
			            func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: Int) -> Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
			                .init(holder_partBuilder: { _ in __safeDI_gadgetBuilder_Outer_Holder(id: id) })
			            }
			            func __safeDI_gadgetBuilder_Outer_Holder(id: Int) -> Holder.SafeDIMockScope_Part.__safeDI_Builder<Outer.SafeDIMockScope_Gadget.DefaultPart_Scope.__safeDI_Builder<any Gadget>> {
			                .init(part: { values in __safeDI_gadgetBuilder_Outer_DefaultPart_Scope(id: id, label: values.label) })
			            }
			            func __safeDI_gadgetBuilder_Outer_DefaultPart_Scope(id: Int, label: Label) -> Outer.SafeDIMockScope_Gadget.DefaultPart_Scope.__safeDI_Builder<any Gadget> {
			                .init(gadget: { scope in __safeDI_gadgetBuilder_Outer_DefaultPart_Scope_gadget(scope, id: id, label: label) })
			            }
			            func __safeDI_gadgetBuilder_Outer_DefaultService_Scope_(up: Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
			                .init(holder_partBuilder: { values in __safeDI_gadgetBuilder_Outer_Holder_(up: up.holder_partBuilder(values)) })
			            }
			            func __safeDI_gadgetBuilder_Outer_Holder_(up: Holder.SafeDIMockScope_Part.__safeDI_Builder<Outer.SafeDIMockScope_Gadget.DefaultPart_Scope.__safeDI_Builder<any Gadget>>) -> Holder.SafeDIMockScope_Part.__safeDI_Builder<Outer.SafeDIMockScope_Gadget.DefaultPart_Scope.__safeDI_Builder<any Gadget>> {
			                .init(part: { values in __safeDI_gadgetBuilder_Outer_DefaultPart_Scope_(up: up.part(values), label: values.label) })
			            }
			            func __safeDI_gadgetBuilder_Outer_DefaultPart_Scope_(up: Outer.SafeDIMockScope_Gadget.DefaultPart_Scope.__safeDI_Builder<any Gadget>, label: Label) -> Outer.SafeDIMockScope_Gadget.DefaultPart_Scope.__safeDI_Builder<any Gadget> {
			                .init(gadget: up.gadget)
			            }
			            _ = Outer.__safeDI_Outer_mock_1D8B1AD505C8727C.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Outer.__safeDI_mock(gadgetBuilder: __safeDI_gadgetBuilder_Outer(up: .init(__safeDI_noScope: gadgetBuilder)), safeDIOverrides: safeDIOverrides.outer)
			        }
			        let outer: Outer = __safeDI_outer()
			        return Root(outer: outer)
			    }
			}
			#endif
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_holdsCalledMocksSendableScopeInCase_whenPublicMocksFillOfPlaceInsideSendableFunctionHoldsPlace() async throws {
		// `Inner` builds `Screen` in a `SendableInstantiator`, so its `service` there is built by `Inner`'s `@Sendable`
		// builder and `Outer`'s fill of it is `@Sendable`: the `gadget` inside it is a case that holds `Inner`'s `@Sendable`
		// scope and `DefaultService_Scope`. `LiveGadget` reads `id` through the readers of `Inner`'s `@Sendable` enum and of
		// the plain enum it holds, which find it on every `@Sendable` route, so `App` fills the place there. No plain route
		// holds `id`, so `App` passes the place up on each, and its mock takes a builder for the plain routes only.
		try await expectPlaceInsideFill(
			feature: Self.inner(screen: ["@Forwarded public let id: Int"], innerScreenBuilder: "SendableInstantiator<Screen>", conformances: ", Sendable"),
			middle: [
				Self.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let gadget: any Gadget"], conformances: ", Sendable"),
				Self.publicMockType(named: "Outer", declarations: ["@Instantiated public let inner: Inner"], conformances: ", Sendable"),
			],
			app: [
				Self.passedUpGadget,
				Self.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received(onlyIfAvailable: true) public let id: Int?"], conformances: ", Sendable"),
				Self.mockedRoot(declarations: ["@Instantiated public let outer: Outer"]),
			],
			probes: [Self.probe(".outer.inner.screenBuilder.instantiate(7)", builders: "gadgetBuilder: { PassedUpGadget() }")],
			expectedMiddle: """
			#if canImport(Feature)
			import Feature
			#endif

			#if DEBUG
			extension Outer {
			    nonisolated public enum SafeDIMockScope_Gadget {
			        nonisolated public struct inner_serviceBuilder_Values {}

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
			            public let inner_serviceBuilder: (inner_serviceBuilder_Values) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(inner_serviceBuilder: @escaping (inner_serviceBuilder_Values) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.inner_serviceBuilder = inner_serviceBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.inner_serviceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
			            }
			        }
			    }

			    nonisolated public enum SafeDISendableMockScope_Gadget {
			        nonisolated public struct inner_serviceSendableBuilder_Values: Sendable {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			            public let inner_serviceSendableBuilder: @Sendable (inner_serviceSendableBuilder_Values) -> Inner.SafeDISendableMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(inner_serviceSendableBuilder: @escaping @Sendable (inner_serviceSendableBuilder_Values) -> Inner.SafeDISendableMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.inner_serviceSendableBuilder = inner_serviceSendableBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                self.inner_serviceSendableBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            inner: Inner.SafeDIOverrides = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                inner: inner
			            )
			        }

			        public var inner: Inner.SafeDIOverrides { __safeDI_storage.inner }

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

			    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    public static func mock(
			        gadgetBuilder: @escaping () -> any Gadget,
			        gadgetSendableBuilder: @escaping @Sendable () -> any Gadget,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Outer {
			        Outer.__safeDI_mock(gadgetBuilder: .init(__safeDI_noScope: gadgetBuilder), gadgetSendableBuilder: .init(__safeDI_noScope: gadgetSendableBuilder), safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        gadgetBuilder __safeDI_gadgetBuilder: Outer.SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget>,
			        gadgetSendableBuilder __safeDI_gadgetSendableBuilder: Outer.SafeDISendableMockScope_Gadget.__safeDI_Builder<any Gadget>,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Outer {
			        let __safeDI_gadgetBuilder_inner_serviceBuilder = __safeDI_gadgetBuilder.inner_serviceBuilder(SafeDIMockScope_Gadget.inner_serviceBuilder_Values())
			        func __safeDI_inner() -> Inner {
			            let __safeDI_gadgetSendableBuilder_inner_serviceSendableBuilder = __safeDI_gadgetSendableBuilder.inner_serviceSendableBuilder(SafeDISendableMockScope_Gadget.inner_serviceSendableBuilder_Values())
			            func __safeDI_serviceBuilder_Inner_service(_ scope: Inner.SafeDIMockScope_Service.service_Values, __safeDI_inner_serviceBuilder: SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let gadget: any Gadget = __safeDI_inner_serviceBuilder.gadget(SafeDIMockScope_Gadget.DefaultService_Scope.gadget_Values())
			                    return DefaultService(gadget: gadget)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            @Sendable func __safeDI_serviceSendableBuilder_Inner_Screen_Scope_service(_ scope: Inner.SafeDIMockScope_Service.Screen_Scope.service_Values, __safeDI_inner_serviceSendableBuilder: SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let gadget: any Gadget = __safeDI_inner_serviceSendableBuilder.gadget(SafeDIMockScope_Gadget.DefaultService_Scope.gadget_Values())
			                    return DefaultService(gadget: gadget)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Inner(up: Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(service: { scope in __safeDI_serviceBuilder_Inner_service(scope, __safeDI_inner_serviceBuilder: up.service(scope)) })
			            }
			            @Sendable nonisolated func __safeDI_serviceSendableBuilder_Inner(up: Inner.SafeDISendableMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDISendableMockScope_Service.__safeDI_Builder<any Service> {
			                .init(screenBuilder: { values in __safeDI_serviceBuilder_Inner_Screen_Scope(up: up.screenBuilder(values)) })
			            }
			            @Sendable nonisolated func __safeDI_serviceBuilder_Inner_Screen_Scope(up: Inner.SafeDIMockScope_Service.Screen_Scope.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDIMockScope_Service.Screen_Scope.__safeDI_Builder<any Service> {
			                .init(service: { scope in __safeDI_serviceSendableBuilder_Inner_Screen_Scope_service(scope, __safeDI_inner_serviceSendableBuilder: up.service(scope)) })
			            }
			            _ = Inner.__safeDI_Inner_mock_64ACDFE38FB4BDEE.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Inner.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder_Inner(up: __safeDI_gadgetBuilder_inner_serviceBuilder), serviceSendableBuilder: __safeDI_serviceSendableBuilder_Inner(up: __safeDI_gadgetSendableBuilder_inner_serviceSendableBuilder), safeDIOverrides: safeDIOverrides.inner)
			        }
			        let inner: Inner = __safeDI_inner()
			        return Outer(inner: inner)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_mock_5841E886557B9256 {}
			}
			#endif
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            outer: Outer.SafeDIOverrides = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                outer: outer
			            )
			        }

			        var outer: Outer.SafeDIOverrides { __safeDI_storage.outer }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                outer: Outer.SafeDIOverrides
			            ) {
			                self.outer = outer
			            }

			            let outer: Outer.SafeDIOverrides
			        }
			    }

			    static func mock(
			        gadgetBuilder: @escaping () -> any Gadget,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_outer() -> Outer {
			            @Sendable func __safeDI_gadgetSendableBuilder_Outer_DefaultService_Scope_gadget(_ scope: Outer.SafeDIMockScope_Gadget.DefaultService_Scope.gadget_Values, id: Int?) -> any Gadget {
			                let gadget: any Gadget = LiveGadget(id: id)
			                return gadget
			            }
			            @Sendable nonisolated func __safeDI_gadgetSendableBuilder_Outer() -> Outer.SafeDISendableMockScope_Gadget.__safeDI_Builder<any Gadget> {
			                .init(inner_serviceSendableBuilder: { _ in __safeDI_gadgetBuilder_Outer_Inner() })
			            }
			            @Sendable nonisolated func __safeDI_gadgetBuilder_Outer_Inner() -> Inner.SafeDISendableMockScope_Service.__safeDI_Builder<Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			                .init(screenBuilder: { _ in __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope() })
			            }
			            @Sendable nonisolated func __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope() -> Inner.SafeDIMockScope_Service.Screen_Scope.__safeDI_Builder<Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			                .init(service: { values in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: values.id) })
			            }
			            @Sendable nonisolated func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: Int) -> Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
			                .init(gadget: { scope in __safeDI_gadgetSendableBuilder_Outer_DefaultService_Scope_gadget(scope, id: id) })
			            }
			            _ = Outer.__safeDI_Outer_mock_5841E886557B9256.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Outer.__safeDI_mock(gadgetBuilder: .init(__safeDI_noScope: gadgetBuilder), gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_Outer(), safeDIOverrides: safeDIOverrides.outer)
			        }
			        let outer: Outer = __safeDI_outer()
			        return Root(outer: outer)
			    }
			}
			#endif
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsPlaceTheValueTheFunctionWasPassed_whenPublicMocksPlaceInsideFillIsBeneathCycleThatTakesCycleParameter() async throws {
		// The graph fuzzer's seed 605 inside a public mock's fill. `DefaultService` builds `T` and `C`, each of which builds
		// the other; `T`'s `reader` receives `mark`, so the function that builds `DefaultService`'s `T` takes it, while the
		// `T` that its `C` builds reads `C`'s. `T_Scope`'s level carries `mark` bound from the parameter where the function
		// takes it, and from `C`'s where it does not. `Inner` binds `mark` before `service`, so the fill reads only what
		// `Inner`'s case carries, and `Outer`'s mock fills it.
		try await expectPlaceInsideFill(
			feature: [
				"public protocol Service {}\npublic protocol Api {}",
				seamFixtureType(named: "Mark", declarations: []),
				Self.publicMockType(named: "Inner", declarations: ["@Instantiated public let mark: Mark", "@Instantiated public let service: any Service"]),
			],
			middle: [
				seamFixtureType(named: "MarkReader", declarations: ["@Received(onlyIfAvailable: true) public let mark: Mark?"]),
				seamFixtureType(named: "T", declarations: ["@Instantiated public let reader: MarkReader", "@Instantiated public let cBuilder: Instantiator<C>", "@Instantiated public let api: any Api"]),
				seamFixtureType(named: "C", declarations: ["@Instantiated public let mark: Mark", "@Instantiated public let tBuilder: Instantiator<T>"]),
				Self.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let tBuilder: Instantiator<T>", "@Instantiated public let cBuilder: Instantiator<C>"]),
				Self.publicMockType(named: "Outer", declarations: ["@Instantiated public let inner: Inner"]),
			],
			app: [
				Self.fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: ["@Received(onlyIfAvailable: true) public let mark: Mark?"]),
				Self.mockedRoot(declarations: ["@Instantiated public let outer: Outer"]),
			],
			probes: [DifferentialValueProbe(
				name: "T's api at each build",
				expression: """
				{ () -> [String] in
				    let service = Root.mock().outer.inner.service as! DefaultService
				    let t = service.tBuilder.instantiate()
				    return [t.api, t.cBuilder.instantiate().tBuilder.instantiate().api, service.cBuilder.instantiate().tBuilder.instantiate().api].map { "\\($0)" }
				}()
				""",
			)],
			expectedMiddle: """
			#if canImport(Feature)
			import Feature
			#endif

			#if DEBUG
			extension Outer {
			    nonisolated public enum SafeDIMockScope_Api {
			        nonisolated public struct inner_serviceBuilder_Values {}

			        nonisolated public enum DefaultService_Scope {
			            nonisolated public struct tBuilder_Values {}

			            nonisolated public struct cBuilder_Values {
			                public let tBuilder: Instantiator<T>
			            }

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let tBuilder: (tBuilder_Values) -> SafeDIMockScope_Api.T_Scope.__safeDI_Builder<__safeDI_Built>
			                public let cBuilder: (cBuilder_Values) -> SafeDIMockScope_Api.C_Scope.__safeDI_Builder<__safeDI_Built>

			                public init(tBuilder: @escaping (tBuilder_Values) -> SafeDIMockScope_Api.T_Scope.__safeDI_Builder<__safeDI_Built>, cBuilder: @escaping (cBuilder_Values) -> SafeDIMockScope_Api.C_Scope.__safeDI_Builder<__safeDI_Built>) {
			                    self.tBuilder = tBuilder
			                    self.cBuilder = cBuilder
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.tBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
			                    self.cBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
			                }
			            }
			        }

			        nonisolated public enum T_Scope {
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
			                public let cBuilder: (cBuilder_Values) -> SafeDIMockScope_Api.C_Scope.__safeDI_Builder<__safeDI_Built>
			                public let api: (api_Values) -> __safeDI_Built

			                public init(cBuilder: @escaping (cBuilder_Values) -> SafeDIMockScope_Api.C_Scope.__safeDI_Builder<__safeDI_Built>, api: @escaping (api_Values) -> __safeDI_Built) {
			                    self.cBuilder = cBuilder
			                    self.api = api
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.cBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
			                    self.api = { _ in __safeDI_builder() }
			                }
			            }
			        }

			        nonisolated public enum C_Scope {
			            nonisolated public struct tBuilder_Values {
			                public let mark: Mark
			            }

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let tBuilder: (tBuilder_Values) -> SafeDIMockScope_Api.T_Scope.__safeDI_Builder<__safeDI_Built>

			                public init(tBuilder: @escaping (tBuilder_Values) -> SafeDIMockScope_Api.T_Scope.__safeDI_Builder<__safeDI_Built>) {
			                    self.tBuilder = tBuilder
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.tBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
			                }
			            }
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let inner_serviceBuilder: (inner_serviceBuilder_Values) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Api.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(inner_serviceBuilder: @escaping (inner_serviceBuilder_Values) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Api.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.inner_serviceBuilder = inner_serviceBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.inner_serviceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            inner: Inner.SafeDIOverrides = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                inner: inner
			            )
			        }

			        public var inner: Inner.SafeDIOverrides { __safeDI_storage.inner }

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

			    // SafeDI counts `Api` as `public`: no module it reads declares it narrower. If `Api` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    public static func mock(
			        apiBuilder: @escaping () -> any Api,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Outer {
			        Outer.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        apiBuilder __safeDI_apiBuilder: Outer.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Outer {
			        let __safeDI_apiBuilder_inner_serviceBuilder = __safeDI_apiBuilder.inner_serviceBuilder(SafeDIMockScope_Api.inner_serviceBuilder_Values())
			        func __safeDI_inner() -> Inner {
			            func __safeDI_serviceBuilder_Inner_service(_ scope: Inner.SafeDIMockScope_Service.service_Values, __safeDI_inner_serviceBuilder: SafeDIMockScope_Api.DefaultService_Scope.__safeDI_Builder<any Api>) -> any Service {
			                let mark = scope.mark
			                func __safeDI_service() -> DefaultService {
			                    let __safeDI_apiBuilder_tBuilder = __safeDI_inner_serviceBuilder.tBuilder(SafeDIMockScope_Api.DefaultService_Scope.tBuilder_Values())
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
			                        let api: any Api = __safeDI_apiBuilder_tBuilder.api(SafeDIMockScope_Api.T_Scope.api_Values(mark: mark, reader: reader, cBuilder: cBuilder))
			                        return T(reader: reader, cBuilder: cBuilder, api: api)
			                    }
			                    let tBuilder = Instantiator<T> {
			                        __safeDI_tBuilder(mark: mark)
			                    }
			                    let __safeDI_apiBuilder_cBuilder = __safeDI_inner_serviceBuilder.cBuilder(SafeDIMockScope_Api.DefaultService_Scope.cBuilder_Values(tBuilder: tBuilder))
			                    func __safeDI_cBuilder() -> C {
			                        let mark = Mark()
			                        let __safeDI_apiBuilder_tBuilder = __safeDI_apiBuilder_cBuilder.tBuilder(SafeDIMockScope_Api.C_Scope.tBuilder_Values(mark: mark))
			                        func __safeDI_tBuilder() -> T {
			                            let reader = MarkReader(mark: mark)
			                            let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			                            let api: any Api = __safeDI_apiBuilder_tBuilder.api(SafeDIMockScope_Api.T_Scope.api_Values(mark: mark, reader: reader, cBuilder: cBuilder))
			                            return T(reader: reader, cBuilder: cBuilder, api: api)
			                        }
			                        let tBuilder = Instantiator<T>(__safeDI_tBuilder)
			                        return C(mark: mark, tBuilder: tBuilder)
			                    }
			                    let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			                    return DefaultService(tBuilder: tBuilder, cBuilder: cBuilder)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Inner(up: Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Api.DefaultService_Scope.__safeDI_Builder<any Api>>) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(service: { scope in __safeDI_serviceBuilder_Inner_service(scope, __safeDI_inner_serviceBuilder: up.service(scope)) })
			            }
			            _ = Inner.__safeDI_Inner_mock_42B604434A0DC066.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Inner.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder_Inner(up: __safeDI_apiBuilder_inner_serviceBuilder), safeDIOverrides: safeDIOverrides.inner)
			        }
			        let inner: Inner = __safeDI_inner()
			        return Outer(inner: inner)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_mock_9EB6ABB8BABB976E {}
			}
			#endif
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            outer: Outer.SafeDIOverrides = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                outer: outer
			            )
			        }

			        var outer: Outer.SafeDIOverrides { __safeDI_storage.outer }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                outer: Outer.SafeDIOverrides
			            ) {
			                self.outer = outer
			            }

			            let outer: Outer.SafeDIOverrides
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_outer() -> Outer {
			            func __safeDI_apiBuilder_Outer() -> Outer.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
			                .init(inner_serviceBuilder: { _ in __safeDI_apiBuilder_Outer_Inner() })
			            }
			            func __safeDI_apiBuilder_Outer_Inner() -> Inner.SafeDIMockScope_Service.__safeDI_Builder<Outer.SafeDIMockScope_Api.DefaultService_Scope.__safeDI_Builder<any Api>> {
			                .init(service: { _ in __safeDI_apiBuilder_Outer_DefaultService_Scope() })
			            }
			            func __safeDI_apiBuilder_Outer_DefaultService_Scope() -> Outer.SafeDIMockScope_Api.DefaultService_Scope.__safeDI_Builder<any Api> {
			                .init(tBuilder: { _ in __safeDI_apiBuilder_Outer_T_Scope() }, cBuilder: { _ in __safeDI_apiBuilder_Outer_C_Scope() })
			            }
			            func __safeDI_apiBuilder_Outer_T_Scope() -> Outer.SafeDIMockScope_Api.T_Scope.__safeDI_Builder<any Api> {
			                .init(
			                    cBuilder: { _ in __safeDI_apiBuilder_Outer_C_Scope() },
			                    api: { scope in
			                        let mark = scope.mark
			                        let api: any Api = LiveApi(mark: mark)
			                        return api
			                    }
			                )
			            }
			            func __safeDI_apiBuilder_Outer_C_Scope() -> Outer.SafeDIMockScope_Api.C_Scope.__safeDI_Builder<any Api> {
			                .init(tBuilder: { _ in __safeDI_apiBuilder_Outer_T_Scope() })
			            }
			            _ = Outer.__safeDI_Outer_mock_9EB6ABB8BABB976E.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Outer.__safeDI_mock(apiBuilder: __safeDI_apiBuilder_Outer(), safeDIOverrides: safeDIOverrides.outer)
			        }
			        let outer: Outer = __safeDI_outer()
			        return Root(outer: outer)
			    }
			}
			#endif
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsFillValueTheMockBindsAgainAboveCall_whenPublicMocksPlaceInsideFillReadsReceiveBoundAgainInAnotherForm() async throws {
		// `Outer` receives `user: User` and `b`, whose `B` receives `user: Draft`, which `Outer`'s mock binds again from
		// `user_Draft` before `B` calls `Inner`'s mock. `LiveGadget`, filling the `gadget` inside `Outer`'s fill of `Inner`'s
		// hole, reads `user: Draft`, which `B`'s level carries in the call's case, as inline hands it the value `B` received.
		// `B`'s initializer is `package`, so `App` passes `b: nil` and `Outer`'s mock builds it.
		try await expectPlaceInsideFill(
			feature: Self.inner(screen: ["@Forwarded public let id: Int"]),
			middle: [
				seamFixtureType(named: "User", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Draft", isFinalClass: true, declarations: []),
				Self.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let gadget: any Gadget"]),
				seamFixtureType(named: "B", declarations: ["@Received public let user: Draft", "@Instantiated public let inner: Inner"])
					.replacingOccurrences(of: "    public init(", with: "    package init("),
				Self.publicMockType(named: "Outer", declarations: ["@Received public let user: User", "@Received public let b: B"]),
			],
			app: [
				Self.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received public let user: Draft"]),
				Self.mockedRoot(declarations: ["@Instantiated public let outer: Outer"]),
			],
			probes: [DifferentialValueProbe("Root.mock().outer.b"), DifferentialValueProbe("Root.mock().outer.b.inner.screenBuilder.instantiate(7)")],
			expectedMiddle: """
			#if canImport(Feature)
			import Feature
			#endif

			#if DEBUG
			extension Outer {
			    nonisolated public enum SafeDIMockScope_Gadget {
			        nonisolated public struct b_Values {}

			        nonisolated public enum B_Scope {
			            nonisolated public struct inner_serviceBuilder_Values {
			                public let user: Draft
			            }

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let inner_serviceBuilder: (inner_serviceBuilder_Values) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			                public init(inner_serviceBuilder: @escaping (inner_serviceBuilder_Values) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                    self.inner_serviceBuilder = inner_serviceBuilder
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.inner_serviceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
			                }
			            }
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
			            public let b: (b_Values) -> SafeDIMockScope_Gadget.B_Scope.__safeDI_Builder<__safeDI_Built>

			            public init(b: @escaping (b_Values) -> SafeDIMockScope_Gadget.B_Scope.__safeDI_Builder<__safeDI_Built>) {
			                self.b = b
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.b = { _ in .init(__safeDI_noScope: __safeDI_builder) }
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            user_User: (() -> User)? = nil,
			            user_Draft: (() -> Draft)? = nil,
			            b: __safeDI_Middle_B_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                user_User: user_User,
			                user_Draft: user_Draft,
			                b: b
			            )
			        }

			        public var user_User: (() -> User)? { __safeDI_storage.user_User }
			        public var user_Draft: (() -> Draft)? { __safeDI_storage.user_Draft }
			        public var b: __safeDI_Middle_B_MockConfiguration { __safeDI_storage.b }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                user_User: (() -> User)?,
			                user_Draft: (() -> Draft)?,
			                b: __safeDI_Middle_B_MockConfiguration
			            ) {
			                self.user_User = user_User
			                self.user_Draft = user_Draft
			                self.b = b
			            }

			            let user_User: (() -> User)?
			            let user_Draft: (() -> Draft)?
			            let b: __safeDI_Middle_B_MockConfiguration
			        }
			    }

			    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    public static func mock(
			        gadgetBuilder: @escaping () -> any Gadget,
			        b: B? = nil,
			        user_Draft: Draft? = nil,
			        user_User: User? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Outer {
			        Outer.__safeDI_mock(gadgetBuilder: .init(__safeDI_noScope: gadgetBuilder), b: b, user_Draft: user_Draft, user_User: user_User, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        gadgetBuilder __safeDI_gadgetBuilder: Outer.SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget>,
			        b: B? = nil,
			        user_Draft: Draft? = nil,
			        user_User: User? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Outer {
			        let user_User = if let user_User { user_User } else if let safeDIBuilder = safeDIOverrides.user_User { safeDIBuilder() } else { User() }
			        let user_Draft = if let user_Draft { user_Draft } else if let safeDIBuilder = safeDIOverrides.user_Draft { safeDIBuilder() } else { Draft() }
			        let __safeDI_gadgetBuilder_b = __safeDI_gadgetBuilder.b(SafeDIMockScope_Gadget.b_Values())
			        func __safeDI_b() -> B {
			            let user: Draft = user_Draft
			            let __safeDI_gadgetBuilder_inner_serviceBuilder = __safeDI_gadgetBuilder_b.inner_serviceBuilder(SafeDIMockScope_Gadget.B_Scope.inner_serviceBuilder_Values(user: user))
			            func __safeDI_inner() -> Inner {
			                func __safeDI_serviceBuilder_Inner_service(_ scope: Inner.SafeDIMockScope_Service.service_Values, __safeDI_inner_serviceBuilder: SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                    func __safeDI_service() -> DefaultService {
			                        let gadget: any Gadget = __safeDI_inner_serviceBuilder.gadget(SafeDIMockScope_Gadget.DefaultService_Scope.gadget_Values())
			                        return DefaultService(gadget: gadget)
			                    }
			                    let service: any Service = __safeDI_service()
			                    return service
			                }
			                func __safeDI_serviceBuilder_Inner_Screen_Scope_service(_ scope: Inner.SafeDIMockScope_Service.Screen_Scope.service_Values, __safeDI_inner_serviceBuilder: SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                    func __safeDI_service() -> DefaultService {
			                        let gadget: any Gadget = __safeDI_inner_serviceBuilder.gadget(SafeDIMockScope_Gadget.DefaultService_Scope.gadget_Values())
			                        return DefaultService(gadget: gadget)
			                    }
			                    let service: any Service = __safeDI_service()
			                    return service
			                }
			                func __safeDI_serviceBuilder_Inner(up: Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                    .init(screenBuilder: { values in __safeDI_serviceBuilder_Inner_Screen_Scope(up: up.screenBuilder(values)) }, service: { scope in __safeDI_serviceBuilder_Inner_service(scope, __safeDI_inner_serviceBuilder: up.service(scope)) })
			                }
			                func __safeDI_serviceBuilder_Inner_Screen_Scope(up: Inner.SafeDIMockScope_Service.Screen_Scope.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDIMockScope_Service.Screen_Scope.__safeDI_Builder<any Service> {
			                    .init(service: { scope in __safeDI_serviceBuilder_Inner_Screen_Scope_service(scope, __safeDI_inner_serviceBuilder: up.service(scope)) })
			                }
			                _ = Inner.__safeDI_Inner_mock_3EBB13A82C3BF964.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			                return Inner.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder_Inner(up: __safeDI_gadgetBuilder_inner_serviceBuilder), safeDIOverrides: safeDIOverrides.b.inner)
			            }
			            let inner: Inner = __safeDI_inner()
			            return B.__safeDI_init(user: user, inner: inner, safeDIBuilder: safeDIOverrides.b.safeDIBuilder)
			        }
			        let b: B = if let b { b } else { __safeDI_b() }
			        return Outer(user: user_User, b: b)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_mock_2EF335B9F25BB5E8 {}
			}
			#endif

			#if DEBUG
			/// Configuration for how `B` is constructed within the public mock trees of module `Middle`.
			nonisolated public struct __safeDI_Middle_B_MockConfiguration {
			    public init(
			        inner: Inner.SafeDIOverrides = .init(),
			        _ safeDIBuilder: ((Draft, Inner) -> B)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            inner: inner,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    public var inner: Inner.SafeDIOverrides { __safeDI_storage.inner }
			    /// Overrides how `B` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((Draft, Inner) -> B)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            inner: Inner.SafeDIOverrides,
			            safeDIBuilder: ((Draft, Inner) -> B)?
			        ) {
			            self.inner = inner
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let inner: Inner.SafeDIOverrides
			        let safeDIBuilder: ((Draft, Inner) -> B)?
			    }
			}

			extension B {
			    static func __safeDI_init(user: Draft, inner: Inner, safeDIBuilder: ((Draft, Inner) -> B)?) -> B {
			        if let safeDIBuilder { safeDIBuilder(user, inner) } else { B(user: user, inner: inner) }
			    }
			}
			#endif

			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            user: (() -> Draft)? = nil,
			            outer: Outer.SafeDIOverrides = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                user: user,
			                outer: outer
			            )
			        }

			        var user: (() -> Draft)? { __safeDI_storage.user }
			        var outer: Outer.SafeDIOverrides { __safeDI_storage.outer }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                user: (() -> Draft)?,
			                outer: Outer.SafeDIOverrides
			            ) {
			                self.user = user
			                self.outer = outer
			            }

			            let user: (() -> Draft)?
			            let outer: Outer.SafeDIOverrides
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let user = if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { Draft() }
			        func __safeDI_outer() -> Outer {
			            func __safeDI_gadgetBuilder_Outer() -> Outer.SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget> {
			                .init(b: { _ in __safeDI_gadgetBuilder_Outer_B_Scope() })
			            }
			            func __safeDI_gadgetBuilder_Outer_B_Scope() -> Outer.SafeDIMockScope_Gadget.B_Scope.__safeDI_Builder<any Gadget> {
			                .init(inner_serviceBuilder: { values in __safeDI_gadgetBuilder_Outer_Inner(user: values.user) })
			            }
			            func __safeDI_gadgetBuilder_Outer_Inner(user: Draft) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			                .init(screenBuilder: { _ in __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope(user: user) }, service: { _ in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(user: user) })
			            }
			            func __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope(user: Draft) -> Inner.SafeDIMockScope_Service.Screen_Scope.__safeDI_Builder<Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			                .init(service: { _ in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(user: user) })
			            }
			            func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(user: Draft) -> Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
			                .init(gadget: { _ in
			                    let gadget: any Gadget = LiveGadget(user: user)
			                    return gadget
			                })
			            }
			            _ = Outer.__safeDI_Outer_mock_2EF335B9F25BB5E8.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Outer.__safeDI_mock(gadgetBuilder: __safeDI_gadgetBuilder_Outer(), b: nil, user_Draft: user, safeDIOverrides: safeDIOverrides.outer)
			        }
			        let outer: Outer = __safeDI_outer()
			        return Root(outer: outer)
			    }
			}
			#endif
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsFillReceiversOwnBinding_whenPublicMockRootNamesApartLabelThatPlaceInsideFillReads() async throws {
		// `Outer`'s `A` receives `user: User` and its `B` receives `user: Draft`, both types SafeDI can instantiate, so
		// `Outer`'s mock names both apart and its root declares neither. `B` binds `user: Draft` again before it calls
		// `Inner`'s mock, and `LiveGadget`, filling the `gadget` inside `Outer`'s fill of `Inner`'s hole, reads it from `B`'s
		// level in the call's case.
		try await expectPlaceInsideFill(
			feature: Self.inner(screen: ["@Forwarded public let id: Int"]),
			middle: [
				seamFixtureType(named: "User", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Draft", isFinalClass: true, declarations: []),
				Self.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let gadget: any Gadget"]),
				seamFixtureType(named: "A", declarations: ["@Received public let user: User"]),
				seamFixtureType(named: "B", declarations: ["@Received public let user: Draft", "@Instantiated public let inner: Inner"]),
				Self.publicMockType(named: "Outer", declarations: ["@Instantiated public let a: A", "@Instantiated public let b: B"]),
			],
			app: [
				Self.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received public let user: Draft"]),
				Self.mockedRoot(declarations: ["@Instantiated public let outer: Outer"]),
			],
			probes: [DifferentialValueProbe("Root.mock().outer.b"), DifferentialValueProbe("Root.mock().outer.b.inner.screenBuilder.instantiate(7)")],
			expectedMiddle: """
			#if canImport(Feature)
			import Feature
			#endif

			#if DEBUG
			extension Outer {
			    nonisolated public enum SafeDIMockScope_Gadget {
			        nonisolated public struct b_Values {
			            public let a: A
			        }

			        nonisolated public enum B_Scope {
			            nonisolated public struct inner_serviceBuilder_Values {
			                public let user: Draft
			            }

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let inner_serviceBuilder: (inner_serviceBuilder_Values) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			                public init(inner_serviceBuilder: @escaping (inner_serviceBuilder_Values) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                    self.inner_serviceBuilder = inner_serviceBuilder
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.inner_serviceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
			                }
			            }
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
			            public let b: (b_Values) -> SafeDIMockScope_Gadget.B_Scope.__safeDI_Builder<__safeDI_Built>

			            public init(b: @escaping (b_Values) -> SafeDIMockScope_Gadget.B_Scope.__safeDI_Builder<__safeDI_Built>) {
			                self.b = b
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.b = { _ in .init(__safeDI_noScope: __safeDI_builder) }
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            user_User: (() -> User)? = nil,
			            a: ((User) -> A)? = nil,
			            user_Draft: (() -> Draft)? = nil,
			            b: __safeDI_Middle_B_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                user_User: user_User,
			                a: a,
			                user_Draft: user_Draft,
			                b: b
			            )
			        }

			        public var user_User: (() -> User)? { __safeDI_storage.user_User }
			        public var a: ((User) -> A)? { __safeDI_storage.a }
			        public var user_Draft: (() -> Draft)? { __safeDI_storage.user_Draft }
			        public var b: __safeDI_Middle_B_MockConfiguration { __safeDI_storage.b }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                user_User: (() -> User)?,
			                a: ((User) -> A)?,
			                user_Draft: (() -> Draft)?,
			                b: __safeDI_Middle_B_MockConfiguration
			            ) {
			                self.user_User = user_User
			                self.a = a
			                self.user_Draft = user_Draft
			                self.b = b
			            }

			            let user_User: (() -> User)?
			            let a: ((User) -> A)?
			            let user_Draft: (() -> Draft)?
			            let b: __safeDI_Middle_B_MockConfiguration
			        }
			    }

			    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    public static func mock(
			        gadgetBuilder: @escaping () -> any Gadget,
			        user_Draft: Draft? = nil,
			        user_User: User? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Outer {
			        Outer.__safeDI_mock(gadgetBuilder: .init(__safeDI_noScope: gadgetBuilder), user_Draft: user_Draft, user_User: user_User, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        gadgetBuilder __safeDI_gadgetBuilder: Outer.SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget>,
			        user_Draft: Draft? = nil,
			        user_User: User? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Outer {
			        let user_User = if let user_User { user_User } else if let safeDIBuilder = safeDIOverrides.user_User { safeDIBuilder() } else { User() }
			        func __safeDI_a() -> A {
			            let user: User = user_User
			            return if let safeDIBuilder = safeDIOverrides.a { safeDIBuilder(user) } else { A(user: user) }
			        }
			        let a: A = __safeDI_a()
			        let user_Draft = if let user_Draft { user_Draft } else if let safeDIBuilder = safeDIOverrides.user_Draft { safeDIBuilder() } else { Draft() }
			        let __safeDI_gadgetBuilder_b = __safeDI_gadgetBuilder.b(SafeDIMockScope_Gadget.b_Values(a: a))
			        func __safeDI_b() -> B {
			            let user: Draft = user_Draft
			            let __safeDI_gadgetBuilder_inner_serviceBuilder = __safeDI_gadgetBuilder_b.inner_serviceBuilder(SafeDIMockScope_Gadget.B_Scope.inner_serviceBuilder_Values(user: user))
			            func __safeDI_inner() -> Inner {
			                func __safeDI_serviceBuilder_Inner_service(_ scope: Inner.SafeDIMockScope_Service.service_Values, __safeDI_inner_serviceBuilder: SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                    func __safeDI_service() -> DefaultService {
			                        let gadget: any Gadget = __safeDI_inner_serviceBuilder.gadget(SafeDIMockScope_Gadget.DefaultService_Scope.gadget_Values())
			                        return DefaultService(gadget: gadget)
			                    }
			                    let service: any Service = __safeDI_service()
			                    return service
			                }
			                func __safeDI_serviceBuilder_Inner_Screen_Scope_service(_ scope: Inner.SafeDIMockScope_Service.Screen_Scope.service_Values, __safeDI_inner_serviceBuilder: SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                    func __safeDI_service() -> DefaultService {
			                        let gadget: any Gadget = __safeDI_inner_serviceBuilder.gadget(SafeDIMockScope_Gadget.DefaultService_Scope.gadget_Values())
			                        return DefaultService(gadget: gadget)
			                    }
			                    let service: any Service = __safeDI_service()
			                    return service
			                }
			                func __safeDI_serviceBuilder_Inner(up: Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                    .init(screenBuilder: { values in __safeDI_serviceBuilder_Inner_Screen_Scope(up: up.screenBuilder(values)) }, service: { scope in __safeDI_serviceBuilder_Inner_service(scope, __safeDI_inner_serviceBuilder: up.service(scope)) })
			                }
			                func __safeDI_serviceBuilder_Inner_Screen_Scope(up: Inner.SafeDIMockScope_Service.Screen_Scope.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDIMockScope_Service.Screen_Scope.__safeDI_Builder<any Service> {
			                    .init(service: { scope in __safeDI_serviceBuilder_Inner_Screen_Scope_service(scope, __safeDI_inner_serviceBuilder: up.service(scope)) })
			                }
			                _ = Inner.__safeDI_Inner_mock_3EBB13A82C3BF964.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			                return Inner.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder_Inner(up: __safeDI_gadgetBuilder_inner_serviceBuilder), safeDIOverrides: safeDIOverrides.b.inner)
			            }
			            let inner: Inner = __safeDI_inner()
			            return B.__safeDI_init(user: user, inner: inner, safeDIBuilder: safeDIOverrides.b.safeDIBuilder)
			        }
			        let b: B = __safeDI_b()
			        return Outer(a: a, b: b)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_mock_33AE69DEC51696B4 {}
			}
			#endif

			#if DEBUG
			/// Configuration for how `B` is constructed within the public mock trees of module `Middle`.
			nonisolated public struct __safeDI_Middle_B_MockConfiguration {
			    public init(
			        inner: Inner.SafeDIOverrides = .init(),
			        _ safeDIBuilder: ((Draft, Inner) -> B)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            inner: inner,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    public var inner: Inner.SafeDIOverrides { __safeDI_storage.inner }
			    /// Overrides how `B` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((Draft, Inner) -> B)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            inner: Inner.SafeDIOverrides,
			            safeDIBuilder: ((Draft, Inner) -> B)?
			        ) {
			            self.inner = inner
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let inner: Inner.SafeDIOverrides
			        let safeDIBuilder: ((Draft, Inner) -> B)?
			    }
			}

			extension B {
			    static func __safeDI_init(user: Draft, inner: Inner, safeDIBuilder: ((Draft, Inner) -> B)?) -> B {
			        if let safeDIBuilder { safeDIBuilder(user, inner) } else { B(user: user, inner: inner) }
			    }
			}
			#endif

			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            user: (() -> Draft)? = nil,
			            outer: Outer.SafeDIOverrides = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                user: user,
			                outer: outer
			            )
			        }

			        var user: (() -> Draft)? { __safeDI_storage.user }
			        var outer: Outer.SafeDIOverrides { __safeDI_storage.outer }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                user: (() -> Draft)?,
			                outer: Outer.SafeDIOverrides
			            ) {
			                self.user = user
			                self.outer = outer
			            }

			            let user: (() -> Draft)?
			            let outer: Outer.SafeDIOverrides
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let user = if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { Draft() }
			        func __safeDI_outer() -> Outer {
			            func __safeDI_gadgetBuilder_Outer() -> Outer.SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget> {
			                .init(b: { _ in __safeDI_gadgetBuilder_Outer_B_Scope() })
			            }
			            func __safeDI_gadgetBuilder_Outer_B_Scope() -> Outer.SafeDIMockScope_Gadget.B_Scope.__safeDI_Builder<any Gadget> {
			                .init(inner_serviceBuilder: { values in __safeDI_gadgetBuilder_Outer_Inner(user: values.user) })
			            }
			            func __safeDI_gadgetBuilder_Outer_Inner(user: Draft) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			                .init(screenBuilder: { _ in __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope(user: user) }, service: { _ in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(user: user) })
			            }
			            func __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope(user: Draft) -> Inner.SafeDIMockScope_Service.Screen_Scope.__safeDI_Builder<Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			                .init(service: { _ in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(user: user) })
			            }
			            func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(user: Draft) -> Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
			                .init(gadget: { _ in
			                    let gadget: any Gadget = LiveGadget(user: user)
			                    return gadget
			                })
			            }
			            _ = Outer.__safeDI_Outer_mock_33AE69DEC51696B4.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Outer.__safeDI_mock(gadgetBuilder: __safeDI_gadgetBuilder_Outer(), user_Draft: user, safeDIOverrides: safeDIOverrides.outer)
			        }
			        let outer: Outer = __safeDI_outer()
			        return Root(outer: outer)
			    }
			}
			#endif
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_holdsTheRootEnumInTheCallsCaseForTheBuilderItFills_whenPublicMockFillsCalledMocksHoleWithTheMockedType() async throws {
		// `Outer` fulfills `Service`, so its mock fills `Inner`'s `service` with `Outer` itself, built again inside the fill
		// through `innerBuilder`, and the `gadget` of that `Outer` is a place only `App` can build.
		try await expectPlaceInsideFill(
			feature: [
				"public protocol Service {}\npublic protocol Gadget {}",
				Self.publicMockType(named: "Inner", declarations: ["@Instantiated public let service: any Service"]),
			],
			middle: [
				Self.publicMockType(named: "Outer", declarations: ["@Instantiated public let gadget: any Gadget", "@Instantiated public let innerBuilder: Instantiator<Inner>"], conformances: ", Service")
					.replacingOccurrences(of: "@Instantiable(generateMock: .public)\n", with: "@Instantiable(fulfillingAdditionalTypes: [Service.self], generateMock: .public)\n"),
			],
			app: [
				Self.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: []),
				Self.mockedRoot(declarations: ["@Instantiated public let outer: Outer"]),
			],
			probes: [Self.probe(".outer.innerBuilder.instantiate().service", builders: "")],
			expectedMiddle: """
			#if canImport(Feature)
			import Feature
			#endif

			#if DEBUG
			extension Outer {
			    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    nonisolated public enum SafeDIMockScope_Gadget {
			        nonisolated public struct gadget_Values {}

			        nonisolated public struct innerBuilder_serviceBuilder_Values {
			            public let gadget: any Gadget
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let gadget: (gadget_Values) -> __safeDI_Built
			            public let innerBuilder_serviceBuilder: (innerBuilder_serviceBuilder_Values) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.__safeDI_Builder<__safeDI_Built>>

			            public init(gadget: @escaping (gadget_Values) -> __safeDI_Built, innerBuilder_serviceBuilder: @escaping (innerBuilder_serviceBuilder_Values) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.__safeDI_Builder<__safeDI_Built>>) {
			                self.gadget = gadget
			                self.innerBuilder_serviceBuilder = innerBuilder_serviceBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.gadget = { _ in __safeDI_builder() }
			                self.innerBuilder_serviceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            innerBuilder: ((@escaping () -> any Service) -> Inner)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                innerBuilder: innerBuilder
			            )
			        }

			        public var innerBuilder: ((@escaping () -> any Service) -> Inner)? { __safeDI_storage.innerBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                innerBuilder: ((@escaping () -> any Service) -> Inner)?
			            ) {
			                self.innerBuilder = innerBuilder
			            }

			            let innerBuilder: ((@escaping () -> any Service) -> Inner)?
			        }
			    }

			    public static func mock(
			        gadgetBuilder: @escaping () -> any Gadget,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Outer {
			        Outer.__safeDI_mock(gadgetBuilder: .init(__safeDI_noScope: gadgetBuilder), safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        gadgetBuilder __safeDI_gadgetBuilder: Outer.SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget>,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Outer {
			        let gadget: any Gadget = __safeDI_gadgetBuilder.gadget(SafeDIMockScope_Gadget.gadget_Values())
			        let __safeDI_gadgetBuilder_innerBuilder_serviceBuilder = __safeDI_gadgetBuilder.innerBuilder_serviceBuilder(SafeDIMockScope_Gadget.innerBuilder_serviceBuilder_Values(gadget: gadget))
			        func __safeDI_innerBuilder() -> Inner {
			            func __safeDI_serviceBuilder_Inner_service(_ scope: Inner.SafeDIMockScope_Service.service_Values, __safeDI_innerBuilder_serviceBuilder: SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget>) -> any Service {
			                func __safeDI_service() -> Outer {
			                    let gadget: any Gadget = __safeDI_innerBuilder_serviceBuilder.gadget(SafeDIMockScope_Gadget.gadget_Values())
			                    let __safeDI_gadgetBuilder_innerBuilder_serviceBuilder_ = __safeDI_innerBuilder_serviceBuilder.innerBuilder_serviceBuilder(SafeDIMockScope_Gadget.innerBuilder_serviceBuilder_Values(gadget: gadget))
			                    func __safeDI_innerBuilder() -> Inner {
			                        Inner.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder_Inner(up: __safeDI_gadgetBuilder_innerBuilder_serviceBuilder_))
			                    }
			                    let innerBuilder = Instantiator<Inner>(__safeDI_innerBuilder)
			                    return Outer(gadget: gadget, innerBuilder: innerBuilder)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Inner(up: Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget>>) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(service: { scope in __safeDI_serviceBuilder_Inner_service(scope, __safeDI_innerBuilder_serviceBuilder: up.service(scope)) })
			            }
			            _ = Inner.__safeDI_Inner_mock_E789692848368FB8.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Inner.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder_Inner(up: __safeDI_gadgetBuilder_innerBuilder_serviceBuilder))
			        }
			        let innerBuilder = Instantiator<Inner>(__safeDI_innerBuilder)
			        return Outer(gadget: gadget, innerBuilder: innerBuilder)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_mock_87651F347F368DFC {}
			}
			#endif
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            outer: Outer.SafeDIOverrides = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                outer: outer
			            )
			        }

			        var outer: Outer.SafeDIOverrides { __safeDI_storage.outer }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                outer: Outer.SafeDIOverrides
			            ) {
			                self.outer = outer
			            }

			            let outer: Outer.SafeDIOverrides
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_outer() -> Outer {
			            func __safeDI_gadgetBuilder_Outer() -> Outer.SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget> {
			                .init(
			                    gadget: { _ in
			                        let gadget: any Gadget = LiveGadget()
			                        return gadget
			                    },
			                    innerBuilder_serviceBuilder: { _ in __safeDI_gadgetBuilder_Outer_Inner() }
			                )
			            }
			            func __safeDI_gadgetBuilder_Outer_Inner() -> Inner.SafeDIMockScope_Service.__safeDI_Builder<Outer.SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget>> {
			                .init(service: { _ in __safeDI_gadgetBuilder_Outer() })
			            }
			            _ = Outer.__safeDI_Outer_mock_87651F347F368DFC.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Outer.__safeDI_mock(gadgetBuilder: __safeDI_gadgetBuilder_Outer(), safeDIOverrides: safeDIOverrides.outer)
			        }
			        let outer: Outer = __safeDI_outer()
			        return Root(outer: outer)
			    }
			}
			#endif
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsEachLoopMembersPayloadInALetOfItsOwn_whenPublicMocksFillHoldsLoopOfBuildersAroundPlaces() async throws {
		// `Outer`'s mock fills `Inner`'s `service` with `DefaultService`, which instantiates the builders of `LoopA` and
		// `LoopB`, each of which receives the other's and holds `gadget`, a place only `App` can build: a loop of builders
		// inside a public mock's fill, whose members' payloads the mock binds in a `let` each, as every public mock's loop does
		// (`SafeDIToolSeamLoopLevelsTests` holds a seam's in one box).
		try await expectPlaceInsideFill(
			feature: [
				"public protocol Service {}\npublic protocol Gadget {}",
				Self.publicMockType(named: "Inner", declarations: ["@Instantiated public let service: any Service"]),
			],
			middle: [
				seamFixtureType(named: "Tag", isFinalClass: true, declarations: []),
				Self.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let aBuilder: Instantiator<LoopA>", "@Instantiated public let bBuilder: Instantiator<LoopB>"]),
				seamFixtureType(named: "LoopA", declarations: ["@Instantiated public let gadget: any Gadget", "@Received public let bBuilder: Instantiator<LoopB>"]),
				seamFixtureType(named: "LoopB", declarations: ["@Instantiated public let gadget: any Gadget", "@Received public let aBuilder: Instantiator<LoopA>"]),
				Self.publicMockType(named: "Outer", declarations: ["@Instantiated public let tag: Tag", "@Instantiated public let inner: Inner"]),
			],
			app: [
				Self.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: []),
				Self.mockedRoot(declarations: ["@Instantiated public let outer: Outer"]),
			],
			probes: [Self.probe(".outer.inner.service", builders: "")],
			expectedMiddle: """
			#if canImport(Feature)
			import Feature
			#endif

			#if DEBUG
			extension Outer {
			    @frozen public enum SafeDIMockScope_Gadget {
			        case inner_serviceBuilder(inner_serviceBuilder_Values, Inner.SafeDIMockScope_Service, SafeDIMockScope_Gadget.DefaultService_Scope)

			        public struct inner_serviceBuilder_Values {
			            public let tag: Tag
			        }

			        @frozen public enum DefaultService_Scope {
			            case aBuilder(aBuilder_Values, SafeDIMockScope_Gadget.LoopA_Scope)
			            case bBuilder(bBuilder_Values, SafeDIMockScope_Gadget.LoopB_Scope)

			            public struct aBuilder_Values {}

			            public struct bBuilder_Values {}
			        }

			        @frozen public enum LoopA_Scope {
			            case gadget(gadget_Values)

			            public struct gadget_Values {
			                public let bBuilder: Instantiator<LoopB>
			            }
			        }

			        @frozen public enum LoopB_Scope {
			            case gadget(gadget_Values)

			            public struct gadget_Values {
			                public let aBuilder: Instantiator<LoopA>
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            tag: (() -> Tag)? = nil,
			            inner: ((@escaping (Inner.SafeDIMockScope_Service) -> any Service) -> Inner)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                tag: tag,
			                inner: inner
			            )
			        }

			        public var tag: (() -> Tag)? { __safeDI_storage.tag }
			        public var inner: ((@escaping (Inner.SafeDIMockScope_Service) -> any Service) -> Inner)? { __safeDI_storage.inner }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                tag: (() -> Tag)?,
			                inner: ((@escaping (Inner.SafeDIMockScope_Service) -> any Service) -> Inner)?
			            ) {
			                self.tag = tag
			                self.inner = inner
			            }

			            let tag: (() -> Tag)?
			            let inner: ((@escaping (Inner.SafeDIMockScope_Service) -> any Service) -> Inner)?
			        }
			    }

			    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    public static func mock(
			        gadgetBuilder: @escaping (Outer.SafeDIMockScope_Gadget) -> any Gadget,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Outer {
			        let __safeDI_gadgetBuilder = gadgetBuilder
			        let tag = if let safeDIBuilder = safeDIOverrides.tag { safeDIBuilder() } else { Tag() }
			        let __safeDI_gadgetValues_inner_serviceBuilder = SafeDIMockScope_Gadget.inner_serviceBuilder_Values(tag: tag)
			        func __safeDI_inner() -> Inner {
			            func __safeDI_serviceBuilder_Inner(_ __safeDI_inner_serviceBuilder: Inner.SafeDIMockScope_Service) -> any Service {
			                switch __safeDI_inner_serviceBuilder {
			                case .service:
			                    func __safeDI_service() -> DefaultService {
			                        let __safeDI_gadgetValues_aBuilder = SafeDIMockScope_Gadget.DefaultService_Scope.aBuilder_Values()
			                        let __safeDI_gadgetValues_bBuilder = SafeDIMockScope_Gadget.DefaultService_Scope.bBuilder_Values()
			                        func __safeDI_aBuilder() -> LoopA {
			                            let bBuilder = Instantiator<LoopB>(__safeDI_bBuilder)
			                            let gadget: any Gadget = __safeDI_gadgetBuilder(.inner_serviceBuilder(__safeDI_gadgetValues_inner_serviceBuilder, __safeDI_inner_serviceBuilder, .aBuilder(__safeDI_gadgetValues_aBuilder, .gadget(SafeDIMockScope_Gadget.LoopA_Scope.gadget_Values(bBuilder: bBuilder)))))
			                            return LoopA(gadget: gadget, bBuilder: bBuilder)
			                        }
			                        let aBuilder = Instantiator<LoopA>(__safeDI_aBuilder)
			                        func __safeDI_bBuilder() -> LoopB {
			                            let aBuilder = Instantiator<LoopA>(__safeDI_aBuilder)
			                            let gadget: any Gadget = __safeDI_gadgetBuilder(.inner_serviceBuilder(__safeDI_gadgetValues_inner_serviceBuilder, __safeDI_inner_serviceBuilder, .bBuilder(__safeDI_gadgetValues_bBuilder, .gadget(SafeDIMockScope_Gadget.LoopB_Scope.gadget_Values(aBuilder: aBuilder)))))
			                            return LoopB(gadget: gadget, aBuilder: aBuilder)
			                        }
			                        let bBuilder = Instantiator<LoopB>(__safeDI_bBuilder)
			                        return DefaultService(aBuilder: aBuilder, bBuilder: bBuilder)
			                    }
			                    let service: any Service = __safeDI_service()
			                    return service
			                }
			            }
			            _ = Inner.__safeDI_Inner_mock_E789692848368FB8.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return if let safeDIBuilder = safeDIOverrides.inner { safeDIBuilder(__safeDI_serviceBuilder_Inner) } else { Inner.__safeDI_mock(serviceBuilder: .init(service: { __safeDI_serviceValues in __safeDI_serviceBuilder_Inner(.service(__safeDI_serviceValues)) })) }
			        }
			        let inner: Inner = __safeDI_inner()
			        return Outer(tag: tag, inner: inner)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_mock_3585558781D5ADA4 {}
			}
			#endif
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            outer: Outer.SafeDIOverrides = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                outer: outer
			            )
			        }

			        var outer: Outer.SafeDIOverrides { __safeDI_storage.outer }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                outer: Outer.SafeDIOverrides
			            ) {
			                self.outer = outer
			            }

			            let outer: Outer.SafeDIOverrides
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_outer() -> Outer {
			            func __safeDI_gadgetBuilder_Outer(_ scope: Outer.SafeDIMockScope_Gadget) -> any Gadget {
			                switch scope {
			                case let .inner_serviceBuilder(_, _, scope): return __safeDI_gadgetBuilder_Outer_DefaultService_Scope(scope)
			                }
			            }
			            func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(_ scope: Outer.SafeDIMockScope_Gadget.DefaultService_Scope) -> any Gadget {
			                switch scope {
			                case let .aBuilder(_, scope): return __safeDI_gadgetBuilder_Outer_LoopA_Scope(scope)
			                case let .bBuilder(_, scope): return __safeDI_gadgetBuilder_Outer_LoopB_Scope(scope)
			                }
			            }
			            func __safeDI_gadgetBuilder_Outer_LoopA_Scope(_ scope: Outer.SafeDIMockScope_Gadget.LoopA_Scope) -> any Gadget {
			                switch scope {
			                case .gadget:
			                    let gadget: any Gadget = LiveGadget()
			                    return gadget
			                }
			            }
			            func __safeDI_gadgetBuilder_Outer_LoopB_Scope(_ scope: Outer.SafeDIMockScope_Gadget.LoopB_Scope) -> any Gadget {
			                switch scope {
			                case .gadget:
			                    let gadget: any Gadget = LiveGadget()
			                    return gadget
			                }
			            }
			            _ = Outer.__safeDI_Outer_mock_3585558781D5ADA4.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Outer.mock(gadgetBuilder: __safeDI_gadgetBuilder_Outer, safeDIOverrides: safeDIOverrides.outer)
			        }
			        let outer: Outer = __safeDI_outer()
			        return Root(outer: outer)
			    }
			}
			#endif
			""",
		)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// What a probe's builder hands `Outer`'s mock for a place passed up.
	private static let passedUpGadget = "public struct PassedUpGadget: Gadget {\n    public init() {}\n}"

	/// A probe of `path` from `Root`'s mock, which takes `builders` for the places passed up, where the same graph's mock
	/// built inline, which passes none up, takes `knownRightArguments`.
	private static func probe(_ path: String, builders: String, knownRightArguments: String = "") -> DifferentialValueProbe {
		DifferentialValueProbe(name: "Root.mock()\(path)", expression: "Root.mock(\(builders))\(path)", knownRightExpression: "Root.mock(\(knownRightArguments))\(path)")
	}

	/// `Inner`, a public mock that builds `service`, a hole, at its root and in the `Screen` its `screenBuilder` builds,
	/// which also declares `screen`; and the protocols `Service` and `Gadget`.
	private static func inner(screen: [String], innerScreenBuilder: String = "Instantiator<Screen>", conformances: String = "") -> [String] {
		[
			"public protocol Service\(conformances.isEmpty ? "" : ": Sendable") {}\npublic protocol Gadget\(conformances.isEmpty ? "" : ": Sendable") {}",
			seamFixtureType(named: "Screen", declarations: screen + ["@Instantiated public let service: any Service"], conformances: conformances),
			publicMockType(named: "Inner", declarations: ["@Instantiated public let screenBuilder: \(innerScreenBuilder)", "@Instantiated public let service: any Service"], conformances: conformances),
		]
	}

	/// A public struct named `name` that generates a public mock, whose initializer is `package`: no module of another
	/// package can build it inline, so each calls its mock.
	private static func publicMockType(named name: String, declarations: [String], conformances: String = "") -> String {
		seamFixtureType(named: name, declarations: declarations, conformances: conformances)
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(generateMock: .public)\n")
			.replacingOccurrences(of: "    public init(", with: "    package init(")
	}

	/// `Root`, which generates an internal mock, with `declarations`.
	private static func mockedRoot(declarations: [String]) -> String {
		seamFixtureType(named: "Root", declarations: declarations)
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(generateMock: true)\n")
	}

	private static func fulfillingType(named name: String, fulfilling fulfilledType: String, declarations: [String], conformances: String = "") -> String {
		seamFixtureType(named: name, declarations: declarations, conformances: ", \(fulfilledType)\(conformances)")
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [\(fulfilledType).self])\n")
	}

	/// `Feature`, which declares `Inner`; `Middle`, another package, which declares `Outer` and what fills `Inner`'s holes;
	/// and `App`, a third package, which fills `Outer`'s places inside those fills.
	private static func modules(feature: [String], middle: [String], app: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature),
			ModuleFixture(name: "Middle", packageName: "Mid", swiftFileContent: middle.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: app.map { "import Feature\nimport Middle\n\n" + $0 }, dependencies: ["Feature", "Middle"]),
		]
	}

	/// Expects `Middle`'s and `App`'s generated files to be exactly `expectedMiddle` and `expectedApp`, each after the file
	/// header, every module to compile, and `App`'s mock to build, for each of `probes`, the values the same graph's mock
	/// builds inline: every declaration in one module, every public mock internal. No probe compares values where inline
	/// rejects the graph.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectPlaceInsideFill(
		feature: [String],
		middle: [String],
		app: [String],
		probes: [DifferentialValueProbe],
		expectedMiddle: String,
		expectedApp: String,
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		let modules = Self.modules(feature: feature, middle: middle, app: app)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete, sourceLocation: sourceLocation)
		for (module, expected) in [("Middle", expectedMiddle), ("App", expectedApp)] {
			let generated = output.modules[module]?.generatedFiles["\(module).swift"]
			#expect(generated == generatedFileHeader + expected, sourceLocation: sourceLocation)
			if let generated, generated != generatedFileHeader + expected {
				Issue.record(Comment(rawValue: "=== \(module).swift\n" + generated.dropFirst(generatedFileHeader.count)), sourceLocation: sourceLocation)
			}
		}
		guard compileVerificationIsEnabled, !probes.isEmpty else { return }
		let inlineModules = [ModuleFixture(
			name: "Feature",
			packageName: "Shop",
			swiftFileContent: (feature + middle + app).map { $0.replacingOccurrences(of: "generateMock: .public", with: "generateMock: true") },
		)]
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inlineModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete, sourceLocation: sourceLocation)
		try await expectDifferentialValuesAgree(
			feature: DifferentialValuePath(output: output, modules: modules),
			knownRight: DifferentialValuePath(output: inlineOutput, modules: inlineModules),
			probes: probes,
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}
}
