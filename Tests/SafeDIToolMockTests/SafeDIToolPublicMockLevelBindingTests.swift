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
/// builders whose members each wrap the others again, and a label the mock's root names apart because its tree receives it
/// as two types. Each test compiles both modules and compares the values the mock builds through the public mock with those
/// the same graph's mock builds inline.
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
			    @frozen public enum SafeDIMockScope_Widget {
			        case aBuilder(aBuilder_Values, SafeDIMockScope_Widget.A_Scope)
			        case bBuilder(bBuilder_Values, SafeDIMockScope_Widget.B_Scope)

			        public struct aBuilder_Values {}

			        public struct bBuilder_Values {}

			        @frozen public enum A_Scope {
			            case widget(widget_Values)

			            public struct widget_Values {
			                public let bBuilder: Instantiator<B>
			                public let mark: Mark
			            }
			        }

			        @frozen public enum B_Scope {
			            case widget(widget_Values)

			            public struct widget_Values {
			                public let aBuilder: Instantiator<A>
			                public let mark: Mark
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            aBuilder: __safeDI_Feature_A_MockConfiguration = .init(),
			            bBuilder: __safeDI_Feature_B_MockConfiguration = .init()
			        ) {
			            self.aBuilder = aBuilder
			            self.bBuilder = bBuilder
			        }

			        public let aBuilder: __safeDI_Feature_A_MockConfiguration
			        public let bBuilder: __safeDI_Feature_B_MockConfiguration
			    }

			    public static func mock(
			        widgetBuilder: @escaping (Flow.SafeDIMockScope_Widget) -> any Widget,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Flow {
			        let __safeDI_widgetBuilder = widgetBuilder
			        let __safeDI_widgetValues_aBuilder = SafeDIMockScope_Widget.aBuilder_Values()
			        let __safeDI_widgetValues_bBuilder = SafeDIMockScope_Widget.bBuilder_Values()
			        func __safeDI_aBuilder() -> A {
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            let mark = if let safeDIBuilder = safeDIOverrides.aBuilder.mark { safeDIBuilder() } else { Mark() }
			            let widget: any Widget = __safeDI_widgetBuilder(.aBuilder(__safeDI_widgetValues_aBuilder, .widget(SafeDIMockScope_Widget.A_Scope.widget_Values(bBuilder: bBuilder, mark: mark))))
			            return A.__safeDI_init(mark: mark, bBuilder: bBuilder, widget: widget, safeDIBuilder: safeDIOverrides.aBuilder.safeDIBuilder)
			        }
			        func __safeDI_bBuilder() -> B {
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            let mark = if let safeDIBuilder = safeDIOverrides.bBuilder.mark { safeDIBuilder() } else { Mark() }
			            let widget: any Widget = __safeDI_widgetBuilder(.bBuilder(__safeDI_widgetValues_bBuilder, .widget(SafeDIMockScope_Widget.B_Scope.widget_Values(aBuilder: aBuilder, mark: mark))))
			            return B.__safeDI_init(mark: mark, aBuilder: aBuilder, widget: widget, safeDIBuilder: safeDIOverrides.bBuilder.safeDIBuilder)
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        return Flow(aBuilder: aBuilder, bBuilder: bBuilder)
			    }
			}

			extension Flow {
			    public enum __safeDI_Flow_mock_D97AB904D6745B47 {}
			}
			#endif

			#if DEBUG
			/// Configuration for how `A` is constructed within the public mock trees of module `Feature`.
			nonisolated public struct __safeDI_Feature_A_MockConfiguration {
			    public init(
			        mark: (() -> Mark)? = nil,
			        _ safeDIBuilder: ((Mark, Instantiator<B>, any Widget) -> A)? = nil
			    ) {
			        self.mark = mark
			        self.safeDIBuilder = safeDIBuilder
			    }

			    public let mark: (() -> Mark)?
			    /// Overrides how `A` is constructed. Parameters match the type’s initializer or custom mock method.
			    public let safeDIBuilder: ((Mark, Instantiator<B>, any Widget) -> A)?
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
			        self.mark = mark
			        self.safeDIBuilder = safeDIBuilder
			    }

			    public let mark: (() -> Mark)?
			    /// Overrides how `B` is constructed. Parameters match the type’s initializer or custom mock method.
			    public let safeDIBuilder: ((Mark, Instantiator<A>, any Widget) -> B)?
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
			    @frozen public enum SafeDIMockScope_Widget {
			        case flow(flow_Values, SafeDIMockScope_Widget.Flow_Scope)
			        case a(a_Values, SafeDIMockScope_Widget.A_Scope)

			        public struct flow_Values {}

			        public struct a_Values {
			            public let flow: Flow
			        }

			        @frozen public enum Flow_Scope {
			            case aBuilder(aBuilder_Values, SafeDIMockScope_Widget.A_Scope)

			            public struct aBuilder_Values {}
			        }

			        @frozen public enum A_Scope {
			            case widget(widget_Values)

			            public struct widget_Values {
			                public let bBuilder: Instantiator<B>?
			                public let mark: Mark
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            flow: __safeDI_Feature_Flow_MockConfiguration = .init(),
			            a: __safeDI_Feature_A_MockConfiguration = .init()
			        ) {
			            self.flow = flow
			            self.a = a
			        }

			        public let flow: __safeDI_Feature_Flow_MockConfiguration
			        public let a: __safeDI_Feature_A_MockConfiguration
			    }

			    public static func mock(
			        widgetBuilder: @escaping (Hub.SafeDIMockScope_Widget) -> any Widget,
			        bBuilder: Instantiator<B>? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Hub {
			        let __safeDI_widgetBuilder = widgetBuilder
			        let __safeDI_widgetValues_flow = SafeDIMockScope_Widget.flow_Values()
			        func __safeDI_flow() -> Flow {
			            let __safeDI_widgetValues_aBuilder = SafeDIMockScope_Widget.Flow_Scope.aBuilder_Values()
			            func __safeDI_aBuilder() -> A {
			                let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			                let mark = if let safeDIBuilder = safeDIOverrides.flow.aBuilder.mark { safeDIBuilder() } else { Mark() }
			                let widget: any Widget = __safeDI_widgetBuilder(.flow(__safeDI_widgetValues_flow, .aBuilder(__safeDI_widgetValues_aBuilder, .widget(SafeDIMockScope_Widget.A_Scope.widget_Values(bBuilder: bBuilder, mark: mark)))))
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
			        let __safeDI_widgetValues_a = SafeDIMockScope_Widget.a_Values(flow: flow)
			        func __safeDI_a() -> A {
			            let mark = if let safeDIBuilder = safeDIOverrides.a.mark { safeDIBuilder() } else { Mark() }
			            let widget: any Widget = __safeDI_widgetBuilder(.a(__safeDI_widgetValues_a, .widget(SafeDIMockScope_Widget.A_Scope.widget_Values(bBuilder: bBuilder, mark: mark))))
			            return A.__safeDI_init(mark: mark, bBuilder: bBuilder, widget: widget, safeDIBuilder: safeDIOverrides.a.safeDIBuilder)
			        }
			        let a: A = __safeDI_a()
			        return Hub(flow: flow, a: a)
			    }
			}

			extension Hub {
			    public enum __safeDI_Hub_mock_65B4D688D954D01D {}
			}
			#endif

			#if DEBUG
			/// Configuration for how `A` is constructed within the public mock trees of module `Feature`.
			nonisolated public struct __safeDI_Feature_A_MockConfiguration {
			    public init(
			        mark: (() -> Mark)? = nil,
			        _ safeDIBuilder: ((Mark, Instantiator<B>?, any Widget) -> A)? = nil
			    ) {
			        self.mark = mark
			        self.safeDIBuilder = safeDIBuilder
			    }

			    public let mark: (() -> Mark)?
			    /// Overrides how `A` is constructed. Parameters match the type’s initializer or custom mock method.
			    public let safeDIBuilder: ((Mark, Instantiator<B>?, any Widget) -> A)?
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
			        self.aBuilder = aBuilder
			        self.bBuilder = bBuilder
			        self.safeDIBuilder = safeDIBuilder
			    }

			    public let aBuilder: __safeDI_Feature_A_MockConfiguration
			    public let bBuilder: ((Instantiator<A>) -> B)?
			    /// Overrides how `Flow` is constructed. Parameters match the type’s initializer or custom mock method.
			    public let safeDIBuilder: ((Instantiator<A>, Instantiator<B>) -> Flow)?
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
			    @frozen public enum SafeDIMockScope_Api {
			        case a(a_Values, SafeDIMockScope_Api.A_Scope)
			        case b(b_Values, SafeDIMockScope_Api.B_Scope)

			        public struct a_Values {}

			        public struct b_Values {
			            public let a: A
			        }

			        @frozen public enum A_Scope {
			            case api(api_Values)

			            public struct api_Values {
			                public let user: User
			            }
			        }

			        @frozen public enum B_Scope {
			            case api(api_Values)

			            public struct api_Values {
			                public let user: Draft
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            user_User: (() -> User)? = nil,
			            user_Draft: (() -> Draft)? = nil,
			            a: ((User, any Api) -> A)? = nil,
			            b: ((Draft, any Api) -> B)? = nil
			        ) {
			            self.user_User = user_User
			            self.user_Draft = user_Draft
			            self.a = a
			            self.b = b
			        }

			        public let user_User: (() -> User)?
			        public let user_Draft: (() -> Draft)?
			        public let a: ((User, any Api) -> A)?
			        public let b: ((Draft, any Api) -> B)?
			    }

			    public static func mock(
			        apiBuilder: @escaping (Hub.SafeDIMockScope_Api) -> any Api,
			        user_Draft: Draft? = nil,
			        user_User: User? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Hub {
			        let __safeDI_apiBuilder = apiBuilder
			        let user_User = if let user_User { user_User } else if let safeDIBuilder = safeDIOverrides.user_User { safeDIBuilder() } else { User() }
			        let user_Draft = if let user_Draft { user_Draft } else if let safeDIBuilder = safeDIOverrides.user_Draft { safeDIBuilder() } else { Draft() }
			        let __safeDI_apiValues_a = SafeDIMockScope_Api.a_Values()
			        func __safeDI_a() -> A {
			            let user: User = user_User
			            let api: any Api = __safeDI_apiBuilder(.a(__safeDI_apiValues_a, .api(SafeDIMockScope_Api.A_Scope.api_Values(user: user))))
			            return if let safeDIBuilder = safeDIOverrides.a { safeDIBuilder(user, api) } else { A(user: user, api: api) }
			        }
			        let a: A = __safeDI_a()
			        let __safeDI_apiValues_b = SafeDIMockScope_Api.b_Values(a: a)
			        func __safeDI_b() -> B {
			            let user: Draft = user_Draft
			            let api: any Api = __safeDI_apiBuilder(.b(__safeDI_apiValues_b, .api(SafeDIMockScope_Api.B_Scope.api_Values(user: user))))
			            return if let safeDIBuilder = safeDIOverrides.b { safeDIBuilder(user, api) } else { B(user: user, api: api) }
			        }
			        let b: B = __safeDI_b()
			        return Hub(a: a, b: b)
			    }
			}

			extension Hub {
			    public enum __safeDI_Hub_mock_C4D8D6859CD38C0B {}
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
			    @frozen public enum SafeDIMockScope_Api {
			        case bBuilder(bBuilder_Values, SafeDIMockScope_Api.B_Scope)

			        public struct bBuilder_Values {}

			        @frozen public enum B_Scope {
			            case api(api_Values)

			            public struct api_Values {
			                public let user: Draft
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
			            self.user_User = user_User
			            self.user_Draft = user_Draft
			            self.bBuilder = bBuilder
			        }

			        public let user_User: (() -> User)?
			        public let user_Draft: (() -> Draft)?
			        public let bBuilder: ((any Api, Draft) -> B)?
			    }

			    public static func mock(
			        apiBuilder: @escaping (Hub.SafeDIMockScope_Api) -> any Api,
			        bBuilder: Instantiator<B>? = nil,
			        user_Draft: Draft? = nil,
			        user_User: User? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Hub {
			        let __safeDI_apiBuilder = apiBuilder
			        let user_User = if let user_User { user_User } else if let safeDIBuilder = safeDIOverrides.user_User { safeDIBuilder() } else { User() }
			        let user_Draft = if let user_Draft { user_Draft } else if let safeDIBuilder = safeDIOverrides.user_Draft { safeDIBuilder() } else { Draft() }
			        let __safeDI_apiValues_bBuilder = SafeDIMockScope_Api.bBuilder_Values()
			        func __safeDI_bBuilder() -> B {
			            let user: Draft = user_Draft
			            let api: any Api = __safeDI_apiBuilder(.bBuilder(__safeDI_apiValues_bBuilder, .api(SafeDIMockScope_Api.B_Scope.api_Values(user: user))))
			            return if let safeDIBuilder = safeDIOverrides.bBuilder { safeDIBuilder(api, user) } else { B(api: api, user: user) }
			        }
			        let bBuilder = if let bBuilder { bBuilder } else { Instantiator<B>(__safeDI_bBuilder) }
			        return Hub(user: user_User, bBuilder: bBuilder)
			    }
			}

			extension Hub {
			    public enum __safeDI_Hub_mock_F2C8DEB90E138D31 {}
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
