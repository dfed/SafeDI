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

/// What a public mock's levels hold where its tree binds a value other than as a declaration of the level's type: a loop of
/// builders whose members each wrap the others again, a label the mock's root names apart because its tree receives it
/// as two types, and a receive the mock passes a type by name rather than binding it again under its label. Each test
/// compiles both modules and compares the values the mock builds through the public mock with those the same graph's mock
/// builds inline.
struct SafeDIToolPublicMockLevelBindingTests: ~Copyable {
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
	mutating func generate_bindsEveryLoopMembersPayloadBeforeLoop_whenPublicMocksHoleIsBuiltInsideEachLoopMembersFunction() async throws {
		// `A` and `B` open each other and each hold a `widget` hole, which `App` fills. `bBuilder`'s function, which
		// `aBuilder`'s calls, reads `bBuilder`'s payload, so every member's payload is bound before the loop's first
		// function and holds no member of its loop.
		try await expectPublicMock(
			feature: [
				"public protocol Widget {}",
				seamFixtureType(named: "Mark", isFinalClass: true, declarations: []),
				seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated public let mark: Mark", "@Received public let bBuilder: Instantiator<B>", "@Instantiated public let widget: any Widget"]),
				seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Instantiated public let mark: Mark", "@Received public let aBuilder: Instantiator<A>", "@Instantiated public let widget: any Widget"]),
				Self.publicMockType(named: "Flow", declarations: ["@Instantiated public let aBuilder: Instantiator<A>", "@Instantiated public let bBuilder: Instantiator<B>"]),
			],
			app: [
				Self.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: ["@Received public let mark: Mark"]),
				Self.mockedRoot(declarations: ["@Instantiated public let flow: Flow"]),
			],
			probes: [
				DifferentialValueProbe("Root.mock().flow.aBuilder.instantiate()"),
				DifferentialValueProbe("Root.mock().flow.bBuilder.instantiate()"),
				DifferentialValueProbe("Root.mock().flow.aBuilder.instantiate().bBuilder.instantiate()"),
				DifferentialValueProbe("Root.mock().flow.bBuilder.instantiate().aBuilder.instantiate()"),
			],
			expectedFeature: """
			#if DEBUG
			extension Flow {
			    nonisolated public enum SafeDIMockScope_Widget {
			        nonisolated public struct aBuilder_Values {}

			        nonisolated public struct bBuilder_Values {}

			        nonisolated public enum A_Scope {
			            nonisolated public struct widget_Values {
			                public let bBuilder: Instantiator<B>
			                public let mark: Mark
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

			        nonisolated public enum B_Scope {
			            nonisolated public struct widget_Values {
			                public let aBuilder: Instantiator<A>
			                public let mark: Mark
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
			            public let aBuilder: (aBuilder_Values) -> SafeDIMockScope_Widget.A_Scope.__safeDI_Builder<__safeDI_Built>
			            public let bBuilder: (bBuilder_Values) -> SafeDIMockScope_Widget.B_Scope.__safeDI_Builder<__safeDI_Built>

			            public init(aBuilder: @escaping (aBuilder_Values) -> SafeDIMockScope_Widget.A_Scope.__safeDI_Builder<__safeDI_Built>, bBuilder: @escaping (bBuilder_Values) -> SafeDIMockScope_Widget.B_Scope.__safeDI_Builder<__safeDI_Built>) {
			                self.aBuilder = aBuilder
			                self.bBuilder = bBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(aBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) }, bBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            aBuilder: __safeDI_Feature_A_MockConfiguration = .init(),
			            bBuilder: __safeDI_Feature_B_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                aBuilder: aBuilder,
			                bBuilder: bBuilder
			            )
			        }

			        public var aBuilder: __safeDI_Feature_A_MockConfiguration { __safeDI_storage.aBuilder }
			        public var bBuilder: __safeDI_Feature_B_MockConfiguration { __safeDI_storage.bBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                aBuilder: __safeDI_Feature_A_MockConfiguration,
			                bBuilder: __safeDI_Feature_B_MockConfiguration
			            ) {
			                self.aBuilder = aBuilder
			                self.bBuilder = bBuilder
			            }

			            let aBuilder: __safeDI_Feature_A_MockConfiguration
			            let bBuilder: __safeDI_Feature_B_MockConfiguration
			        }
			    }

			    public static func mock(
			        widgetBuilder: @escaping () -> any Widget,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Flow {
			        Flow.__safeDI_mock(widgetBuilder: .init(__safeDI_noScope: widgetBuilder), safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        widgetBuilder __safeDI_widgetBuilder: Flow.SafeDIMockScope_Widget.__safeDI_Builder<any Widget>,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Flow {
			        let __safeDI_widgetBuilder_aBuilder = __safeDI_widgetBuilder.aBuilder(SafeDIMockScope_Widget.aBuilder_Values())
			        let __safeDI_widgetBuilder_bBuilder = __safeDI_widgetBuilder.bBuilder(SafeDIMockScope_Widget.bBuilder_Values())
			        func __safeDI_aBuilder() -> A {
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            let mark = if let safeDIBuilder = safeDIOverrides.aBuilder.mark { safeDIBuilder() } else { Mark() }
			            let widget: any Widget = __safeDI_widgetBuilder_aBuilder.widget(SafeDIMockScope_Widget.A_Scope.widget_Values(bBuilder: bBuilder, mark: mark))
			            return A.__safeDI_init(mark: mark, bBuilder: bBuilder, widget: widget, safeDIBuilder: safeDIOverrides.aBuilder.safeDIBuilder)
			        }
			        func __safeDI_bBuilder() -> B {
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            let mark = if let safeDIBuilder = safeDIOverrides.bBuilder.mark { safeDIBuilder() } else { Mark() }
			            let widget: any Widget = __safeDI_widgetBuilder_bBuilder.widget(SafeDIMockScope_Widget.B_Scope.widget_Values(aBuilder: aBuilder, mark: mark))
			            return B.__safeDI_init(mark: mark, aBuilder: aBuilder, widget: widget, safeDIBuilder: safeDIOverrides.bBuilder.safeDIBuilder)
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        return Flow(aBuilder: aBuilder, bBuilder: bBuilder)
			    }
			}

			extension Flow {
			    public enum __safeDI_Flow_mock_F779BF1AFD4C98EB {}
			}
			#endif

			#if DEBUG
			/// Configuration for how `A` is constructed within the public mock trees of module `Feature`.
			nonisolated public struct __safeDI_Feature_A_MockConfiguration {
			    public init(
			        mark: (() -> Mark)? = nil,
			        _ safeDIBuilder: ((Mark, Instantiator<B>, any Widget) -> A)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            mark: mark,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    public var mark: (() -> Mark)? { __safeDI_storage.mark }
			    /// Overrides how `A` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((Mark, Instantiator<B>, any Widget) -> A)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            mark: (() -> Mark)?,
			            safeDIBuilder: ((Mark, Instantiator<B>, any Widget) -> A)?
			        ) {
			            self.mark = mark
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let mark: (() -> Mark)?
			        let safeDIBuilder: ((Mark, Instantiator<B>, any Widget) -> A)?
			    }
			}

			extension A {
			    static func __safeDI_init(mark: Mark, bBuilder: Instantiator<B>, widget: any Widget, safeDIBuilder: ((Mark, Instantiator<B>, any Widget) -> A)?) -> A {
			        if let safeDIBuilder { safeDIBuilder(mark, bBuilder, widget) } else { A(mark: mark, bBuilder: bBuilder, widget: widget) }
			    }
			}

			/// Configuration for how `B` is constructed within the public mock trees of module `Feature`.
			nonisolated public struct __safeDI_Feature_B_MockConfiguration {
			    public init(
			        mark: (() -> Mark)? = nil,
			        _ safeDIBuilder: ((Mark, Instantiator<A>, any Widget) -> B)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            mark: mark,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    public var mark: (() -> Mark)? { __safeDI_storage.mark }
			    /// Overrides how `B` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((Mark, Instantiator<A>, any Widget) -> B)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            mark: (() -> Mark)?,
			            safeDIBuilder: ((Mark, Instantiator<A>, any Widget) -> B)?
			        ) {
			            self.mark = mark
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let mark: (() -> Mark)?
			        let safeDIBuilder: ((Mark, Instantiator<A>, any Widget) -> B)?
			    }
			}

			extension B {
			    static func __safeDI_init(mark: Mark, aBuilder: Instantiator<A>, widget: any Widget, safeDIBuilder: ((Mark, Instantiator<A>, any Widget) -> B)?) -> B {
			        if let safeDIBuilder { safeDIBuilder(mark, aBuilder, widget) } else { B(mark: mark, aBuilder: aBuilder, widget: widget) }
			    }
			}
			#endif

			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_givesLevelOptionalFormOfRebinding_whenPublicMocksLoopMemberReceivesInstantiatorOnlyIfAvailableAndIsAlsoBuiltByValue() async throws {
		// `A` receives `bBuilder` only if available. Inside `Flow`'s loop, `aBuilder`'s function wraps `bBuilder` again; the
		// mock also builds an `A` by value, where nothing declares `bBuilder`. `A`'s level takes the optional form, which
		// both builds bind.
		try await expectPublicMock(
			feature: [
				"public protocol Widget {}",
				seamFixtureType(named: "Mark", isFinalClass: true, declarations: []),
				seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated public let mark: Mark", "@Received(onlyIfAvailable: true) public let bBuilder: Instantiator<B>?", "@Instantiated public let widget: any Widget"]),
				seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Received public let aBuilder: Instantiator<A>"]),
				seamFixtureType(named: "Flow", isFinalClass: true, declarations: ["@Instantiated public let aBuilder: Instantiator<A>", "@Instantiated public let bBuilder: Instantiator<B>"]),
				Self.publicMockType(named: "Hub", declarations: ["@Instantiated public let flow: Flow", "@Instantiated public let a: A"]),
			],
			app: [
				Self.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: ["@Received(onlyIfAvailable: true) public let bBuilder: Instantiator<B>?", "@Received public let mark: Mark"]),
				Self.mockedRoot(declarations: ["@Instantiated public let hub: Hub"]),
			],
			probes: [
				DifferentialValueProbe("Root.mock().hub.a"),
				DifferentialValueProbe("Root.mock().hub.flow.aBuilder.instantiate()"),
			],
			expectedFeature: """
			#if DEBUG
			extension Hub {
			    nonisolated public enum SafeDIMockScope_Widget {
			        nonisolated public struct flow_Values {
			            public let bBuilder: Instantiator<B>?
			        }

			        nonisolated public struct a_Values {
			            public let bBuilder: Instantiator<B>?
			            public let flow: Flow
			        }

			        nonisolated public enum Flow_Scope {
			            nonisolated public struct aBuilder_Values {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let aBuilder: (aBuilder_Values) -> SafeDIMockScope_Widget.A_Scope.__safeDI_Builder<__safeDI_Built>

			                public init(aBuilder: @escaping (aBuilder_Values) -> SafeDIMockScope_Widget.A_Scope.__safeDI_Builder<__safeDI_Built>) {
			                    self.aBuilder = aBuilder
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(aBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			                }
			            }
			        }

			        nonisolated public enum A_Scope {
			            nonisolated public struct widget_Values {
			                public let bBuilder: Instantiator<B>?
			                public let mark: Mark
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
			            public let flow: (flow_Values) -> SafeDIMockScope_Widget.Flow_Scope.__safeDI_Builder<__safeDI_Built>
			            public let a: (a_Values) -> SafeDIMockScope_Widget.A_Scope.__safeDI_Builder<__safeDI_Built>

			            public init(flow: @escaping (flow_Values) -> SafeDIMockScope_Widget.Flow_Scope.__safeDI_Builder<__safeDI_Built>, a: @escaping (a_Values) -> SafeDIMockScope_Widget.A_Scope.__safeDI_Builder<__safeDI_Built>) {
			                self.flow = flow
			                self.a = a
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(flow: { _ in .init(__safeDI_noScope: __safeDI_builder) }, a: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            flow: __safeDI_Feature_Flow_MockConfiguration = .init(),
			            a: __safeDI_Feature_A_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                flow: flow,
			                a: a
			            )
			        }

			        public var flow: __safeDI_Feature_Flow_MockConfiguration { __safeDI_storage.flow }
			        public var a: __safeDI_Feature_A_MockConfiguration { __safeDI_storage.a }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                flow: __safeDI_Feature_Flow_MockConfiguration,
			                a: __safeDI_Feature_A_MockConfiguration
			            ) {
			                self.flow = flow
			                self.a = a
			            }

			            let flow: __safeDI_Feature_Flow_MockConfiguration
			            let a: __safeDI_Feature_A_MockConfiguration
			        }
			    }

			    public static func mock(
			        widgetBuilder: @escaping () -> any Widget,
			        bBuilder: Instantiator<B>? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Hub {
			        Hub.__safeDI_mock(widgetBuilder: .init(__safeDI_noScope: widgetBuilder), bBuilder: bBuilder, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        widgetBuilder __safeDI_widgetBuilder: Hub.SafeDIMockScope_Widget.__safeDI_Builder<any Widget>,
			        bBuilder: Instantiator<B>? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Hub {
			        let __safeDI_widgetBuilder_flow = __safeDI_widgetBuilder.flow(SafeDIMockScope_Widget.flow_Values(bBuilder: bBuilder))
			        func __safeDI_flow() -> Flow {
			            let __safeDI_widgetBuilder_aBuilder = __safeDI_widgetBuilder_flow.aBuilder(SafeDIMockScope_Widget.Flow_Scope.aBuilder_Values())
			            func __safeDI_aBuilder() -> A {
			                let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			                let mark = if let safeDIBuilder = safeDIOverrides.flow.aBuilder.mark { safeDIBuilder() } else { Mark() }
			                let widget: any Widget = __safeDI_widgetBuilder_aBuilder.widget(SafeDIMockScope_Widget.A_Scope.widget_Values(bBuilder: bBuilder, mark: mark))
			                return A.__safeDI_init(mark: mark, bBuilder: bBuilder, widget: widget, safeDIBuilder: safeDIOverrides.flow.aBuilder.safeDIBuilder)
			            }
			            func __safeDI_bBuilder() -> B {
			                let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			                return if let safeDIBuilder = safeDIOverrides.flow.bBuilder { safeDIBuilder(aBuilder) } else { B(aBuilder: aBuilder) }
			            }
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            return Flow.__safeDI_init(aBuilder: aBuilder, bBuilder: bBuilder, safeDIBuilder: safeDIOverrides.flow.safeDIBuilder)
			        }
			        let flow: Flow = __safeDI_flow()
			        let __safeDI_widgetBuilder_a = __safeDI_widgetBuilder.a(SafeDIMockScope_Widget.a_Values(bBuilder: bBuilder, flow: flow))
			        func __safeDI_a() -> A {
			            let mark = if let safeDIBuilder = safeDIOverrides.a.mark { safeDIBuilder() } else { Mark() }
			            let widget: any Widget = __safeDI_widgetBuilder_a.widget(SafeDIMockScope_Widget.A_Scope.widget_Values(bBuilder: bBuilder, mark: mark))
			            return A.__safeDI_init(mark: mark, bBuilder: bBuilder, widget: widget, safeDIBuilder: safeDIOverrides.a.safeDIBuilder)
			        }
			        let a: A = __safeDI_a()
			        return Hub(flow: flow, a: a)
			    }
			}

			extension Hub {
			    public enum __safeDI_Hub_mock_17439444E15EE307 {}
			}
			#endif

			#if DEBUG
			/// Configuration for how `A` is constructed within the public mock trees of module `Feature`.
			nonisolated public struct __safeDI_Feature_A_MockConfiguration {
			    public init(
			        mark: (() -> Mark)? = nil,
			        _ safeDIBuilder: ((Mark, Instantiator<B>?, any Widget) -> A)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            mark: mark,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    public var mark: (() -> Mark)? { __safeDI_storage.mark }
			    /// Overrides how `A` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((Mark, Instantiator<B>?, any Widget) -> A)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            mark: (() -> Mark)?,
			            safeDIBuilder: ((Mark, Instantiator<B>?, any Widget) -> A)?
			        ) {
			            self.mark = mark
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let mark: (() -> Mark)?
			        let safeDIBuilder: ((Mark, Instantiator<B>?, any Widget) -> A)?
			    }
			}

			extension A {
			    static func __safeDI_init(mark: Mark, bBuilder: Instantiator<B>?, widget: any Widget, safeDIBuilder: ((Mark, Instantiator<B>?, any Widget) -> A)?) -> A {
			        if let safeDIBuilder { safeDIBuilder(mark, bBuilder, widget) } else { A(mark: mark, bBuilder: bBuilder, widget: widget) }
			    }
			}

			/// Configuration for how `Flow` is constructed within the public mock trees of module `Feature`.
			nonisolated public struct __safeDI_Feature_Flow_MockConfiguration {
			    public init(
			        aBuilder: __safeDI_Feature_A_MockConfiguration = .init(),
			        bBuilder: ((Instantiator<A>) -> B)? = nil,
			        _ safeDIBuilder: ((Instantiator<A>, Instantiator<B>) -> Flow)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            aBuilder: aBuilder,
			            bBuilder: bBuilder,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    public var aBuilder: __safeDI_Feature_A_MockConfiguration { __safeDI_storage.aBuilder }
			    public var bBuilder: ((Instantiator<A>) -> B)? { __safeDI_storage.bBuilder }
			    /// Overrides how `Flow` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((Instantiator<A>, Instantiator<B>) -> Flow)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            aBuilder: __safeDI_Feature_A_MockConfiguration,
			            bBuilder: ((Instantiator<A>) -> B)?,
			            safeDIBuilder: ((Instantiator<A>, Instantiator<B>) -> Flow)?
			        ) {
			            self.aBuilder = aBuilder
			            self.bBuilder = bBuilder
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let aBuilder: __safeDI_Feature_A_MockConfiguration
			        let bBuilder: ((Instantiator<A>) -> B)?
			        let safeDIBuilder: ((Instantiator<A>, Instantiator<B>) -> Flow)?
			    }
			}

			extension Flow {
			    static func __safeDI_init(aBuilder: Instantiator<A>, bBuilder: Instantiator<B>, safeDIBuilder: ((Instantiator<A>, Instantiator<B>) -> Flow)?) -> Flow {
			        if let safeDIBuilder { safeDIBuilder(aBuilder, bBuilder) } else { Flow(aBuilder: aBuilder, bBuilder: bBuilder) }
			    }
			}
			#endif

			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_carriesEachReceiversOwnBinding_whenMockRootNamesApartLabelItsTreeReceivesAsTwoInstantiableTypes() async throws {
		// `A` receives `user: User` and `B` `user: Draft`, both types SafeDI can instantiate, so `Hub`'s mock builds each,
		// named apart as `user_User` and `user_Draft`, and declares no `user`. Each type's level carries the binding its
		// function makes, and the root's level holds no `user`.
		try await expectPublicMock(
			feature: [
				"public protocol Api {}",
				seamFixtureType(named: "User", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Draft", isFinalClass: true, declarations: []),
				seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Received public let user: User", "@Instantiated public let api: any Api"]),
				seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Received public let user: Draft", "@Instantiated public let api: any Api"]),
				Self.publicMockType(named: "Hub", declarations: ["@Instantiated public let a: A", "@Instantiated public let b: B"]),
			],
			app: [
				Self.fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: []),
				Self.mockedRoot(declarations: ["@Instantiated public let hub: Hub"]),
			],
			probes: [DifferentialValueProbe("Root.mock()")],
			expectedFeature: """
			#if DEBUG
			extension Hub {
			    nonisolated public enum SafeDIMockScope_Api {
			        nonisolated public struct a_Values {}

			        nonisolated public struct b_Values {
			            public let a: A
			        }

			        nonisolated public enum A_Scope {
			            nonisolated public struct api_Values {
			                public let user: User
			            }

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

			        nonisolated public enum B_Scope {
			            nonisolated public struct api_Values {
			                public let user: Draft
			            }

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
			            public let a: (a_Values) -> SafeDIMockScope_Api.A_Scope.__safeDI_Builder<__safeDI_Built>
			            public let b: (b_Values) -> SafeDIMockScope_Api.B_Scope.__safeDI_Builder<__safeDI_Built>

			            public init(a: @escaping (a_Values) -> SafeDIMockScope_Api.A_Scope.__safeDI_Builder<__safeDI_Built>, b: @escaping (b_Values) -> SafeDIMockScope_Api.B_Scope.__safeDI_Builder<__safeDI_Built>) {
			                self.a = a
			                self.b = b
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(a: { _ in .init(__safeDI_noScope: __safeDI_builder) }, b: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            user_User: (() -> User)? = nil,
			            a: ((User, any Api) -> A)? = nil,
			            user_Draft: (() -> Draft)? = nil,
			            b: ((Draft, any Api) -> B)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                user_User: user_User,
			                a: a,
			                user_Draft: user_Draft,
			                b: b
			            )
			        }

			        public var user_User: (() -> User)? { __safeDI_storage.user_User }
			        public var a: ((User, any Api) -> A)? { __safeDI_storage.a }
			        public var user_Draft: (() -> Draft)? { __safeDI_storage.user_Draft }
			        public var b: ((Draft, any Api) -> B)? { __safeDI_storage.b }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                user_User: (() -> User)?,
			                a: ((User, any Api) -> A)?,
			                user_Draft: (() -> Draft)?,
			                b: ((Draft, any Api) -> B)?
			            ) {
			                self.user_User = user_User
			                self.a = a
			                self.user_Draft = user_Draft
			                self.b = b
			            }

			            let user_User: (() -> User)?
			            let a: ((User, any Api) -> A)?
			            let user_Draft: (() -> Draft)?
			            let b: ((Draft, any Api) -> B)?
			        }
			    }

			    public static func mock(
			        apiBuilder: @escaping () -> any Api,
			        user_Draft: Draft? = nil,
			        user_User: User? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Hub {
			        Hub.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), user_Draft: user_Draft, user_User: user_User, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        apiBuilder __safeDI_apiBuilder: Hub.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
			        user_Draft: Draft? = nil,
			        user_User: User? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Hub {
			        let user_User = if let user_User { user_User } else if let safeDIBuilder = safeDIOverrides.user_User { safeDIBuilder() } else { User() }
			        let user_Draft = if let user_Draft { user_Draft } else if let safeDIBuilder = safeDIOverrides.user_Draft { safeDIBuilder() } else { Draft() }
			        let __safeDI_apiBuilder_a = __safeDI_apiBuilder.a(SafeDIMockScope_Api.a_Values())
			        func __safeDI_a() -> A {
			            let user: User = user_User
			            let api: any Api = __safeDI_apiBuilder_a.api(SafeDIMockScope_Api.A_Scope.api_Values(user: user))
			            return if let safeDIBuilder = safeDIOverrides.a { safeDIBuilder(user, api) } else { A(user: user, api: api) }
			        }
			        let a: A = __safeDI_a()
			        let __safeDI_apiBuilder_b = __safeDI_apiBuilder.b(SafeDIMockScope_Api.b_Values(a: a))
			        func __safeDI_b() -> B {
			            let user: Draft = user_Draft
			            let api: any Api = __safeDI_apiBuilder_b.api(SafeDIMockScope_Api.B_Scope.api_Values(user: user))
			            return if let safeDIBuilder = safeDIOverrides.b { safeDIBuilder(user, api) } else { B(user: user, api: api) }
			        }
			        let b: B = __safeDI_b()
			        return Hub(a: a, b: b)
			    }
			}

			extension Hub {
			    public enum __safeDI_Hub_mock_18D51B52271EA163 {}
			}
			#endif
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsFillReceiversOwnBinding_whenMockRootNamesApartLabelThatFillReadsAsOneOfTwoInstantiableTypes() async throws {
		// `Hub` receives `user: User` and `bBuilder`, whose `B` receives `user: Draft`; both are types SafeDI can
		// instantiate, so the mock names both apart. `LiveApi`, filling `B`'s `api`, reads `user: Draft`, which `B`'s level
		// carries.
		try await expectPublicMock(
			feature: [
				"public protocol Api {}",
				seamFixtureType(named: "User", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Draft", isFinalClass: true, declarations: []),
				seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Instantiated public let api: any Api", "@Received public let user: Draft"]),
				Self.publicMockType(named: "Hub", declarations: ["@Received public let user: User", "@Received public let bBuilder: Instantiator<B>"]),
			],
			app: [
				Self.fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: ["@Received public let user: Draft"]),
				Self.mockedRoot(declarations: ["@Instantiated public let hub: Hub"]),
			],
			probes: [DifferentialValueProbe("Root.mock().hub.bBuilder.instantiate()")],
			expectedFeature: """
			#if DEBUG
			extension Hub {
			    nonisolated public enum SafeDIMockScope_Api {
			        nonisolated public struct bBuilder_Values {}

			        nonisolated public enum B_Scope {
			            nonisolated public struct api_Values {
			                public let user: Draft
			            }

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
			            public let bBuilder: (bBuilder_Values) -> SafeDIMockScope_Api.B_Scope.__safeDI_Builder<__safeDI_Built>

			            public init(bBuilder: @escaping (bBuilder_Values) -> SafeDIMockScope_Api.B_Scope.__safeDI_Builder<__safeDI_Built>) {
			                self.bBuilder = bBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(bBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            user_User: (() -> User)? = nil,
			            user_Draft: (() -> Draft)? = nil,
			            bBuilder: ((any Api, Draft) -> B)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                user_User: user_User,
			                user_Draft: user_Draft,
			                bBuilder: bBuilder
			            )
			        }

			        public var user_User: (() -> User)? { __safeDI_storage.user_User }
			        public var user_Draft: (() -> Draft)? { __safeDI_storage.user_Draft }
			        public var bBuilder: ((any Api, Draft) -> B)? { __safeDI_storage.bBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                user_User: (() -> User)?,
			                user_Draft: (() -> Draft)?,
			                bBuilder: ((any Api, Draft) -> B)?
			            ) {
			                self.user_User = user_User
			                self.user_Draft = user_Draft
			                self.bBuilder = bBuilder
			            }

			            let user_User: (() -> User)?
			            let user_Draft: (() -> Draft)?
			            let bBuilder: ((any Api, Draft) -> B)?
			        }
			    }

			    public static func mock(
			        apiBuilder: @escaping () -> any Api,
			        bBuilder: Instantiator<B>? = nil,
			        user_Draft: Draft? = nil,
			        user_User: User? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Hub {
			        Hub.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), bBuilder: bBuilder, user_Draft: user_Draft, user_User: user_User, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        apiBuilder __safeDI_apiBuilder: Hub.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
			        bBuilder: Instantiator<B>? = nil,
			        user_Draft: Draft? = nil,
			        user_User: User? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Hub {
			        let user_User = if let user_User { user_User } else if let safeDIBuilder = safeDIOverrides.user_User { safeDIBuilder() } else { User() }
			        let user_Draft = if let user_Draft { user_Draft } else if let safeDIBuilder = safeDIOverrides.user_Draft { safeDIBuilder() } else { Draft() }
			        let __safeDI_apiBuilder_bBuilder = __safeDI_apiBuilder.bBuilder(SafeDIMockScope_Api.bBuilder_Values())
			        func __safeDI_bBuilder() -> B {
			            let user: Draft = user_Draft
			            let api: any Api = __safeDI_apiBuilder_bBuilder.api(SafeDIMockScope_Api.B_Scope.api_Values(user: user))
			            return if let safeDIBuilder = safeDIOverrides.bBuilder { safeDIBuilder(api, user) } else { B(api: api, user: user) }
			        }
			        let bBuilder = if let bBuilder { bBuilder } else { Instantiator<B>(__safeDI_bBuilder) }
			        return Hub(user: user_User, bBuilder: bBuilder)
			    }
			}

			extension Hub {
			    public enum __safeDI_Hub_mock_B71B400896EEB5A9 {}
			}
			#endif
			""",
		)
	}

	@Test(arguments: [[], ["@Received(onlyIfAvailable: true) public let user: User?"], ["@Received(onlyIfAvailable: true) public let user: Draft?"]])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsBindingPassedByName_whenLevelCarriesReceiveMockPassesByNameAboveTypeThatReceivesLabelAsAnotherType(fillDeclarations: [String]) async throws {
		// The mock binds `user: User`, which `Promoted` requires, beside `Hub`'s tree, and passes `Middle` its
		// `user: Draft?` by name, `user_Draft`, since `Child` beneath reads `user: User?` by name. `Middle`'s level carries
		// the `user: Draft?` it received, so its payload reads `user_Draft`, not the `user` its function does not bind
		// again. `LiveApi`, filling `Child`'s `api`, reads neither form, or either.
		try await expectPublicMock(
			feature: Self.passedByNameFeature(middle: "@Instantiated public let middle: Middle", child: "@Instantiated public let child: Child"),
			app: [
				Self.fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: fillDeclarations),
				Self.mockedRoot(declarations: ["@Received public let promoted: Promoted", "@Instantiated public let hub: Hub"]),
			],
			probes: [DifferentialValueProbe("Root.mock()")],
			expectedFeature: """
			#if DEBUG
			extension Hub {
			    nonisolated public enum SafeDIMockScope_Api {
			        nonisolated public struct middle_Values {
			            public let user: User
			            public let promoted: Promoted
			        }

			        nonisolated public enum Middle_Scope {
			            nonisolated public struct child_Values {
			                public let user: Draft?
			            }

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let child: (child_Values) -> SafeDIMockScope_Api.Child_Scope.__safeDI_Builder<__safeDI_Built>

			                public init(child: @escaping (child_Values) -> SafeDIMockScope_Api.Child_Scope.__safeDI_Builder<__safeDI_Built>) {
			                    self.child = child
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(child: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			                }
			            }
			        }

			        nonisolated public enum Child_Scope {
			            nonisolated public struct api_Values {
			                public let user: User?
			            }

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
			            public let middle: (middle_Values) -> SafeDIMockScope_Api.Middle_Scope.__safeDI_Builder<__safeDI_Built>

			            public init(middle: @escaping (middle_Values) -> SafeDIMockScope_Api.Middle_Scope.__safeDI_Builder<__safeDI_Built>) {
			                self.middle = middle
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(middle: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            user: (() -> User)? = nil,
			            middle: __safeDI_Feature_Middle_MockConfiguration = .init(),
			            promoted: ((User) -> Promoted)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                user: user,
			                middle: middle,
			                promoted: promoted
			            )
			        }

			        public var user: (() -> User)? { __safeDI_storage.user }
			        public var middle: __safeDI_Feature_Middle_MockConfiguration { __safeDI_storage.middle }
			        public var promoted: ((User) -> Promoted)? { __safeDI_storage.promoted }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                user: (() -> User)?,
			                middle: __safeDI_Feature_Middle_MockConfiguration,
			                promoted: ((User) -> Promoted)?
			            ) {
			                self.user = user
			                self.middle = middle
			                self.promoted = promoted
			            }

			            let user: (() -> User)?
			            let middle: __safeDI_Feature_Middle_MockConfiguration
			            let promoted: ((User) -> Promoted)?
			        }
			    }

			    public static func mock(
			        apiBuilder: @escaping () -> any Api,
			        promoted: Promoted? = nil,
			        user: User? = nil,
			        user_Draft: Draft? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Hub {
			        Hub.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), promoted: promoted, user: user, user_Draft: user_Draft, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        apiBuilder __safeDI_apiBuilder: Hub.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
			        promoted: Promoted? = nil,
			        user: User? = nil,
			        user_Draft: Draft? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Hub {
			        let user = if let user { user } else if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
			        let promoted = if let promoted { promoted } else if let safeDIBuilder = safeDIOverrides.promoted { safeDIBuilder(user) } else { Promoted(user: user) }
			        let __safeDI_apiBuilder_middle = __safeDI_apiBuilder.middle(SafeDIMockScope_Api.middle_Values(user: user, promoted: promoted))
			        func __safeDI_middle() -> Middle {
			            let __safeDI_apiBuilder_child = __safeDI_apiBuilder_middle.child(SafeDIMockScope_Api.Middle_Scope.child_Values(user: user_Draft))
			            func __safeDI_child() -> Child {
			                let api: any Api = __safeDI_apiBuilder_child.api(SafeDIMockScope_Api.Child_Scope.api_Values(user: user))
			                return if let safeDIBuilder = safeDIOverrides.middle.child { safeDIBuilder(user, api) } else { Child(user: user, api: api) }
			            }
			            let child: Child = __safeDI_child()
			            return Middle.__safeDI_init(user: user_Draft, child: child, safeDIBuilder: safeDIOverrides.middle.safeDIBuilder)
			        }
			        let middle: Middle = __safeDI_middle()
			        return Hub(middle: middle, promoted: promoted)
			    }
			}

			extension Hub {
			    public enum __safeDI_Hub_mock_6B6F840B20A93FB7 {}
			}
			#endif

			#if DEBUG
			/// Configuration for how `Middle` is constructed within the public mock trees of module `Feature`.
			nonisolated public struct __safeDI_Feature_Middle_MockConfiguration {
			    public init(
			        child: ((User?, any Api) -> Child)? = nil,
			        _ safeDIBuilder: ((Draft?, Child) -> Middle)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            child: child,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    public var child: ((User?, any Api) -> Child)? { __safeDI_storage.child }
			    /// Overrides how `Middle` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((Draft?, Child) -> Middle)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            child: ((User?, any Api) -> Child)?,
			            safeDIBuilder: ((Draft?, Child) -> Middle)?
			        ) {
			            self.child = child
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let child: ((User?, any Api) -> Child)?
			        let safeDIBuilder: ((Draft?, Child) -> Middle)?
			    }
			}

			extension Middle {
			    static func __safeDI_init(user: Draft?, child: Child, safeDIBuilder: ((Draft?, Child) -> Middle)?) -> Middle {
			        if let safeDIBuilder { safeDIBuilder(user, child) } else { Middle(user: user, child: child) }
			    }
			}
			#endif

			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsBindingPassedByName_whenInstantiatorsLevelCarriesReceiveMockPassesByNameAboveInstantiatorOfTypeThatReceivesLabelAsAnotherType() async throws {
		// As above, with `Middle` and `Child` each built by an instantiator: `Middle`'s payload for `childBuilder` is bound
		// before `Child`'s builder function, inside `Middle`'s.
		try await expectPublicMock(
			feature: Self.passedByNameFeature(middle: "@Instantiated public let middleBuilder: Instantiator<Middle>", child: "@Instantiated public let childBuilder: Instantiator<Child>"),
			app: [
				Self.fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: ["@Received(onlyIfAvailable: true) public let user: User?"]),
				Self.mockedRoot(declarations: ["@Received public let promoted: Promoted", "@Instantiated public let hub: Hub"]),
			],
			probes: [DifferentialValueProbe("Root.mock().hub.middleBuilder.instantiate().childBuilder.instantiate()")],
			expectedFeature: """
			#if DEBUG
			extension Hub {
			    nonisolated public enum SafeDIMockScope_Api {
			        nonisolated public struct middleBuilder_Values {
			            public let user: User
			            public let promoted: Promoted
			        }

			        nonisolated public enum Middle_Scope {
			            nonisolated public struct childBuilder_Values {
			                public let user: Draft?
			            }

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let childBuilder: (childBuilder_Values) -> SafeDIMockScope_Api.Child_Scope.__safeDI_Builder<__safeDI_Built>

			                public init(childBuilder: @escaping (childBuilder_Values) -> SafeDIMockScope_Api.Child_Scope.__safeDI_Builder<__safeDI_Built>) {
			                    self.childBuilder = childBuilder
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(childBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			                }
			            }
			        }

			        nonisolated public enum Child_Scope {
			            nonisolated public struct api_Values {
			                public let user: User?
			            }

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
			            public let middleBuilder: (middleBuilder_Values) -> SafeDIMockScope_Api.Middle_Scope.__safeDI_Builder<__safeDI_Built>

			            public init(middleBuilder: @escaping (middleBuilder_Values) -> SafeDIMockScope_Api.Middle_Scope.__safeDI_Builder<__safeDI_Built>) {
			                self.middleBuilder = middleBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(middleBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            user: (() -> User)? = nil,
			            middleBuilder: __safeDI_Feature_Middle_MockConfiguration = .init(),
			            promoted: ((User) -> Promoted)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                user: user,
			                middleBuilder: middleBuilder,
			                promoted: promoted
			            )
			        }

			        public var user: (() -> User)? { __safeDI_storage.user }
			        public var middleBuilder: __safeDI_Feature_Middle_MockConfiguration { __safeDI_storage.middleBuilder }
			        public var promoted: ((User) -> Promoted)? { __safeDI_storage.promoted }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                user: (() -> User)?,
			                middleBuilder: __safeDI_Feature_Middle_MockConfiguration,
			                promoted: ((User) -> Promoted)?
			            ) {
			                self.user = user
			                self.middleBuilder = middleBuilder
			                self.promoted = promoted
			            }

			            let user: (() -> User)?
			            let middleBuilder: __safeDI_Feature_Middle_MockConfiguration
			            let promoted: ((User) -> Promoted)?
			        }
			    }

			    public static func mock(
			        apiBuilder: @escaping () -> any Api,
			        promoted: Promoted? = nil,
			        user: User? = nil,
			        user_Draft: Draft? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Hub {
			        Hub.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), promoted: promoted, user: user, user_Draft: user_Draft, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        apiBuilder __safeDI_apiBuilder: Hub.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
			        promoted: Promoted? = nil,
			        user: User? = nil,
			        user_Draft: Draft? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Hub {
			        let user = if let user { user } else if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
			        let promoted = if let promoted { promoted } else if let safeDIBuilder = safeDIOverrides.promoted { safeDIBuilder(user) } else { Promoted(user: user) }
			        let __safeDI_apiBuilder_middleBuilder = __safeDI_apiBuilder.middleBuilder(SafeDIMockScope_Api.middleBuilder_Values(user: user, promoted: promoted))
			        func __safeDI_middleBuilder() -> Middle {
			            let __safeDI_apiBuilder_childBuilder = __safeDI_apiBuilder_middleBuilder.childBuilder(SafeDIMockScope_Api.Middle_Scope.childBuilder_Values(user: user_Draft))
			            func __safeDI_childBuilder() -> Child {
			                let api: any Api = __safeDI_apiBuilder_childBuilder.api(SafeDIMockScope_Api.Child_Scope.api_Values(user: user))
			                return if let safeDIBuilder = safeDIOverrides.middleBuilder.childBuilder { safeDIBuilder(user, api) } else { Child(user: user, api: api) }
			            }
			            let childBuilder = Instantiator<Child>(__safeDI_childBuilder)
			            return Middle.__safeDI_init(user: user_Draft, childBuilder: childBuilder, safeDIBuilder: safeDIOverrides.middleBuilder.safeDIBuilder)
			        }
			        let middleBuilder = Instantiator<Middle>(__safeDI_middleBuilder)
			        return Hub(middleBuilder: middleBuilder, promoted: promoted)
			    }
			}

			extension Hub {
			    public enum __safeDI_Hub_mock_E44ECEC04A81430F {}
			}
			#endif

			#if DEBUG
			/// Configuration for how `Middle` is constructed within the public mock trees of module `Feature`.
			nonisolated public struct __safeDI_Feature_Middle_MockConfiguration {
			    public init(
			        childBuilder: ((User?, any Api) -> Child)? = nil,
			        _ safeDIBuilder: ((Draft?, Instantiator<Child>) -> Middle)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            childBuilder: childBuilder,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    public var childBuilder: ((User?, any Api) -> Child)? { __safeDI_storage.childBuilder }
			    /// Overrides how `Middle` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((Draft?, Instantiator<Child>) -> Middle)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            childBuilder: ((User?, any Api) -> Child)?,
			            safeDIBuilder: ((Draft?, Instantiator<Child>) -> Middle)?
			        ) {
			            self.childBuilder = childBuilder
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let childBuilder: ((User?, any Api) -> Child)?
			        let safeDIBuilder: ((Draft?, Instantiator<Child>) -> Middle)?
			    }
			}

			extension Middle {
			    static func __safeDI_init(user: Draft?, childBuilder: Instantiator<Child>, safeDIBuilder: ((Draft?, Instantiator<Child>) -> Middle)?) -> Middle {
			        if let safeDIBuilder { safeDIBuilder(user, childBuilder) } else { Middle(user: user, childBuilder: childBuilder) }
			    }
			}
			#endif

			""",
		)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// A public final class named `name` that generates a public mock.
	private static func publicMockType(named name: String, declarations: [String]) -> String {
		seamFixtureType(named: name, isFinalClass: true, declarations: declarations)
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(generateMock: .public)\n")
	}

	/// `Feature`'s types where `Hub`'s mock passes `Middle` its `user: Draft?` by name: `Hub` declares `middle`, `Middle`
	/// receives `user: Draft?` only if available and declares `child`, and `Child` receives `user: User?` only if available
	/// and holds the place `api`. `Hub` receives `Promoted`, which receives the `user: User` the mock binds.
	private static func passedByNameFeature(middle: String, child: String) -> [String] {
		[
			"public protocol Api {}",
			seamFixtureType(named: "User", isFinalClass: true, declarations: []),
			"public final class Draft {}",
			seamFixtureType(named: "Child", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) public let user: User?", "@Instantiated public let api: any Api"]),
			seamFixtureType(named: "Middle", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) public let user: Draft?", child]),
			seamFixtureType(named: "Promoted", isFinalClass: true, declarations: ["@Received public let user: User"]),
			publicMockType(named: "Hub", declarations: [middle, "@Received public let promoted: Promoted"]),
		]
	}

	/// `Root`, which generates a mock, with `declarations`.
	private static func mockedRoot(declarations: [String]) -> String {
		seamFixtureType(named: "Root", isFinalClass: true, declarations: declarations)
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(generateMock: true)\n")
	}

	private static func fulfillingType(named name: String, fulfilling fulfilledType: String, declarations: [String]) -> String {
		seamFixtureType(named: name, isFinalClass: true, declarations: declarations, conformances: ", \(fulfilledType)")
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [\(fulfilledType).self])\n")
	}

	/// `Feature`, which declares the public mock, and `App`, another package, which calls it.
	private static func modules(feature: [String], app: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: app.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		]
	}

	/// Expects `Feature`'s generated file to be exactly `expectedFeature` after the file header, both modules to compile, and
	/// `App`'s mock to build, for each of `probes`, the values the same graph's mock builds with no public mock, every
	/// fulfiller in `Feature` and the tree built inline.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectPublicMock(
		feature: [String],
		app: [String],
		probes: [DifferentialValueProbe],
		expectedFeature: String,
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		let modules = Self.modules(feature: feature, app: app)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete, sourceLocation: sourceLocation)
		let generated = output.modules["Feature"]?.generatedFiles["Feature.swift"]
		#expect(generated == generatedFileHeader + expectedFeature, sourceLocation: sourceLocation)
		if let generated, generated != generatedFileHeader + expectedFeature {
			Issue.record(Comment(rawValue: "=== Feature.swift\n" + generated.dropFirst(generatedFileHeader.count)), sourceLocation: sourceLocation)
		}
		guard compileVerificationIsEnabled else { return }
		let fulfillers = app.dropLast()
		let inlineModules = Self.modules(
			feature: (feature + fulfillers).map { $0.replacingOccurrences(of: "generateMock: .public", with: "generateMock: true") },
			app: app.suffix(1),
		)
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
