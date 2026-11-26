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

/// How a public mock's caller reads a value for a place inside its fill of another module's public mock, on the routes of
/// the called mock's enum: a level of the calling mock that binds the label only after the place hides every value
/// farther out, which the twin reports and so the calling mock reports too, and a case of the called mock's enum for a fill of a mock it calls carries that mock's scope, whose
/// levels hold the value. Each test compiles every module.
struct SafeDIToolPublicMockInnerRouteReadTests: ~Copyable {
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
	mutating func generate_reportsTwinsHiddenReceiveError_whenCallingMocksLevelBindsLabelAfterTheCallThatBuildsThePlace() async {
		// `Inner` builds `Model`, whose `service` is a hole, in `Page`, which binds `token` before it, and at its root: one case
		// of `Inner`'s stands for both places. `Outer` calls `Inner` inside `wrapper`, fills `service` with `DefaultService`,
		// whose `gadget` only `App` can build, and binds `token: Receipt` after `wrapper`. `LiveGadget` requires `token:
		// Token`, which `Outer`'s `token` hides on the route through `Inner`'s root. The twin reports the receive hidden, so
		// the calling mock reports the same.
		let modules = { (form: (String) -> String) in
			Self.modules([
				("Feature", [
					"public protocol Service {}\npublic protocol Gadget {}",
					seamFixtureType(named: "Token", isFinalClass: true, declarations: []),
					seamFixtureType(named: "Model", declarations: ["@Instantiated public let service: any Service"]),
					seamFixtureType(named: "Page", declarations: ["@Instantiated public let token: Token", "@Instantiated public let model: Model"]),
					Self.publicMockType(named: "Inner", declarations: ["@Instantiated public let page: Page", "@Instantiated public let model: Model"]),
				].map(form)),
				("Middle", [
					seamFixtureType(named: "Receipt", isFinalClass: true, declarations: ["@Received public let wrapper: Wrapper"]),
					Self.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let gadget: any Gadget"]),
					seamFixtureType(named: "Wrapper", declarations: ["@Instantiated public let inner: Inner"]),
					Self.publicMockType(named: "Outer", declarations: ["@Instantiated public let wrapper: Wrapper", "@Instantiated public let token: Receipt"]),
				].map(form)),
				("App", [
					Self.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received public let token: Token"]),
					Self.mockedRoot(declarations: ["@Instantiated public let outer: Outer"]),
				].map(form)),
			])
		}
		let diagnostics = { (fixtures: [String: FixturePaths]) in
			"""
			\(fixtures["App"]!["LiveGadget.swift"]):10:5: error: @Received property `token: Token` is hidden in chain: Root -> Outer -> Wrapper -> Inner -> Model -> any Service -> LiveGadget. `Outer` declares `token: Receipt` with the same label, so the types below `Outer` receive `token: Receipt` instead. Give `token: Receipt` on `Outer` a different label to fix.
			\(fixtures["Middle"]!["Outer.swift"]):11:5: note: `token: Receipt` is declared here
			"""
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: diagnostics) {
			try await executeSafeDIToolMultiModuleTest(modules: modules { $0 }, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: diagnostics) {
			try await executeSafeDIToolMultiModuleTest(modules: modules(callingMockProductionTwin(of:)), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsValueThroughScopeOfMockCalledByCalledMock_whenPlaceIsInsideFillOfCalledMocksPassedUpPlace() async throws {
		// `Deeper`'s `Screen` forwards `token` and builds `widget`, a hole. `Inner` calls `Deeper` and fills `widget` with
		// `DefaultWidget`, whose `gadget` it passes up: `Inner`'s case `deeper_widgetBuilder` carries `Deeper`'s scope.
		// `Outer` calls `Inner` and fills `gadget` with `DefaultGadget`, whose `thing` only `App` can build. `LiveThing`
		// reads `token`, which no level of `Inner`'s holds but `Deeper`'s scope, carried by `Inner`'s case, holds on every
		// route: `App` reads it through that scope and fills the place.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modules([
				("Feature", [
					"public protocol Widget {}\npublic protocol Gadget {}\npublic protocol Thing {}",
					seamFixtureType(named: "Token", isFinalClass: true, declarations: []),
					seamFixtureType(named: "Screen", declarations: ["@Forwarded public let token: Token", "@Instantiated public let widget: any Widget"]),
					Self.publicMockType(named: "Deeper", declarations: ["@Instantiated public let screenBuilder: Instantiator<Screen>"]),
				]),
				("Inside", [
					Self.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: ["@Instantiated public let gadget: any Gadget"]),
					Self.publicMockType(named: "Inner", declarations: ["@Instantiated public let deeper: Deeper"]),
				]),
				("Middle", [
					Self.fulfillingType(named: "DefaultGadget", fulfilling: "Gadget", declarations: ["@Instantiated public let thing: any Thing"]),
					Self.publicMockType(named: "Outer", declarations: ["@Instantiated public let inner: Inner"]),
				]),
				("App", [
					Self.fulfillingType(named: "LiveThing", fulfilling: "Thing", declarations: ["@Received(onlyIfAvailable: true) public let token: Token?"]),
					Self.mockedRoot(declarations: ["@Instantiated public let outer: Outer"]),
				]),
			]),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Inside"]?.generatedFiles["Inside.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		#if DEBUG
		extension Inner {
		    nonisolated public enum SafeDIMockScope_Gadget {
		        nonisolated public struct deeper_widgetBuilder_Values {}

		        nonisolated public enum DefaultWidget_Scope {
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
		            public let deeper_widgetBuilder: (deeper_widgetBuilder_Values) -> Deeper.SafeDIMockScope_Widget.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(deeper_widgetBuilder: @escaping (deeper_widgetBuilder_Values) -> Deeper.SafeDIMockScope_Widget.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.deeper_widgetBuilder = deeper_widgetBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(deeper_widgetBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            deeper: Deeper.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                deeper: deeper
		            )
		        }

		        public var deeper: Deeper.SafeDIOverrides { __safeDI_storage.deeper }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                deeper: Deeper.SafeDIOverrides
		            ) {
		                self.deeper = deeper
		            }

		            let deeper: Deeper.SafeDIOverrides
		        }
		    }

		    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    public static func mock(
		        gadgetBuilder: @escaping () -> any Gadget,
		        widgetBuilder: (() -> any Widget)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Inner {
		        Inner.__safeDI_mock(gadgetBuilder: .init(__safeDI_noScope: gadgetBuilder), widgetBuilder: widgetBuilder, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        gadgetBuilder __safeDI_gadgetBuilder: Inner.SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget>,
		        widgetBuilder __safeDI_widgetBuilder: (() -> any Widget)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Inner {
		        let __safeDI_gadgetBuilder_deeper_widgetBuilder = __safeDI_gadgetBuilder.deeper_widgetBuilder(SafeDIMockScope_Gadget.deeper_widgetBuilder_Values())
		        func __safeDI_deeper() -> Deeper {
		            func __safeDI_widgetBuilder_Deeper_Screen_Scope_widget(_ scope: Deeper.SafeDIMockScope_Widget.Screen_Scope.widget_Values, __safeDI_deeper_widgetBuilder: SafeDIMockScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>) -> any Widget {
		                func __safeDI_widget() -> DefaultWidget {
		                    let gadget: any Gadget = __safeDI_deeper_widgetBuilder.gadget(SafeDIMockScope_Gadget.DefaultWidget_Scope.gadget_Values())
		                    return DefaultWidget(gadget: gadget)
		                }
		                let widget: any Widget = __safeDI_widget()
		                return widget
		            }
		            func __safeDI_widgetBuilder_Deeper(up: Deeper.SafeDIMockScope_Widget.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>>) -> Deeper.SafeDIMockScope_Widget.__safeDI_Builder<any Widget> {
		                .init(screenBuilder: { values in __safeDI_widgetBuilder_Deeper_Screen_Scope(up: up.screenBuilder(values)) })
		            }
		            func __safeDI_widgetBuilder_Deeper_Screen_Scope(up: Deeper.SafeDIMockScope_Widget.Screen_Scope.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>>) -> Deeper.SafeDIMockScope_Widget.Screen_Scope.__safeDI_Builder<any Widget> {
		                .init(widget: { scope in __safeDI_widgetBuilder_Deeper_Screen_Scope_widget(scope, __safeDI_deeper_widgetBuilder: up.widget(scope)) })
		            }
		            _ = Deeper.__safeDI_Deeper_mock_B7E2C56CDBAB0D93.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Deeper.__safeDI_mock(widgetBuilder: __safeDI_widgetBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_widgetBuilder_Deeper(up: __safeDI_gadgetBuilder_deeper_widgetBuilder), safeDIOverrides: safeDIOverrides.deeper)
		        }
		        let deeper: Deeper = __safeDI_deeper()
		        return Inner(deeper: deeper)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_mock_AFEDDAFF5380CF79 {}
		}
		#endif
		""")
		#expect(output.modules["Middle"]?.generatedFiles["Middle.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Inside)
		import Inside
		#endif

		#if DEBUG
		extension Outer {
		    nonisolated public enum SafeDIMockScope_Thing {
		        nonisolated public struct inner_gadgetBuilder_Values {}

		        nonisolated public enum DefaultGadget_Scope {
		            nonisolated public struct thing_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let thing: (thing_Values) -> __safeDI_Built

		                public init(thing: @escaping (thing_Values) -> __safeDI_Built) {
		                    self.thing = thing
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(thing: { _ in __safeDI_builder() })
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let inner_gadgetBuilder: (inner_gadgetBuilder_Values) -> Inner.SafeDIMockScope_Gadget.__safeDI_Builder<SafeDIMockScope_Thing.DefaultGadget_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(inner_gadgetBuilder: @escaping (inner_gadgetBuilder_Values) -> Inner.SafeDIMockScope_Gadget.__safeDI_Builder<SafeDIMockScope_Thing.DefaultGadget_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.inner_gadgetBuilder = inner_gadgetBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(inner_gadgetBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
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

		    // SafeDI counts `Gadget` and `Thing` as `public`: no module it reads declares them narrower. If one is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    public static func mock(
		        thingBuilder: @escaping () -> any Thing,
		        gadgetBuilder: (() -> any Gadget)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Outer {
		        Outer.__safeDI_mock(thingBuilder: .init(__safeDI_noScope: thingBuilder), gadgetBuilder: gadgetBuilder, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        thingBuilder __safeDI_thingBuilder: Outer.SafeDIMockScope_Thing.__safeDI_Builder<any Thing>,
		        gadgetBuilder __safeDI_gadgetBuilder: (() -> any Gadget)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Outer {
		        let __safeDI_thingBuilder_inner_gadgetBuilder = __safeDI_thingBuilder.inner_gadgetBuilder(SafeDIMockScope_Thing.inner_gadgetBuilder_Values())
		        func __safeDI_inner() -> Inner {
		            func __safeDI_gadgetBuilder_Inner_DefaultWidget_Scope_gadget(_ scope: Inner.SafeDIMockScope_Gadget.DefaultWidget_Scope.gadget_Values, __safeDI_inner_gadgetBuilder: SafeDIMockScope_Thing.DefaultGadget_Scope.__safeDI_Builder<any Thing>) -> any Gadget {
		                func __safeDI_gadget() -> DefaultGadget {
		                    let thing: any Thing = __safeDI_inner_gadgetBuilder.thing(SafeDIMockScope_Thing.DefaultGadget_Scope.thing_Values())
		                    return DefaultGadget(thing: thing)
		                }
		                let gadget: any Gadget = __safeDI_gadget()
		                return gadget
		            }
		            func __safeDI_gadgetBuilder_Inner(up: Inner.SafeDIMockScope_Gadget.__safeDI_Builder<SafeDIMockScope_Thing.DefaultGadget_Scope.__safeDI_Builder<any Thing>>) -> Inner.SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget> {
		                .init(deeper_widgetBuilder: { values in __safeDI_gadgetBuilder_Inner_Deeper(up: up.deeper_widgetBuilder(values)) })
		            }
		            func __safeDI_gadgetBuilder_Inner_Deeper(up: Deeper.SafeDIMockScope_Widget.__safeDI_Builder<Inner.SafeDIMockScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<SafeDIMockScope_Thing.DefaultGadget_Scope.__safeDI_Builder<any Thing>>>) -> Deeper.SafeDIMockScope_Widget.__safeDI_Builder<Inner.SafeDIMockScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>> {
		                .init(screenBuilder: { values in __safeDI_gadgetBuilder_Inner_Deeper_Screen_Scope(up: up.screenBuilder(values)) })
		            }
		            func __safeDI_gadgetBuilder_Inner_Deeper_Screen_Scope(up: Deeper.SafeDIMockScope_Widget.Screen_Scope.__safeDI_Builder<Inner.SafeDIMockScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<SafeDIMockScope_Thing.DefaultGadget_Scope.__safeDI_Builder<any Thing>>>) -> Deeper.SafeDIMockScope_Widget.Screen_Scope.__safeDI_Builder<Inner.SafeDIMockScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>> {
		                .init(widget: { values in __safeDI_gadgetBuilder_Inner_DefaultWidget_Scope(up: up.widget(values)) })
		            }
		            func __safeDI_gadgetBuilder_Inner_DefaultWidget_Scope(up: Inner.SafeDIMockScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<SafeDIMockScope_Thing.DefaultGadget_Scope.__safeDI_Builder<any Thing>>) -> Inner.SafeDIMockScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget> {
		                .init(gadget: { scope in __safeDI_gadgetBuilder_Inner_DefaultWidget_Scope_gadget(scope, __safeDI_inner_gadgetBuilder: up.gadget(scope)) })
		            }
		            _ = Inner.__safeDI_Inner_mock_AFEDDAFF5380CF79.self // If this line does not compile, compile the code SafeDI generates for module Inside into Inside: under Bazel, add Inside’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Inner.__safeDI_mock(gadgetBuilder: __safeDI_gadgetBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_gadgetBuilder_Inner(up: __safeDI_thingBuilder_inner_gadgetBuilder), safeDIOverrides: safeDIOverrides.inner)
		        }
		        let inner: Inner = __safeDI_inner()
		        return Outer(inner: inner)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_mock_81539147E67FF5F4 {}
		}
		#endif
		""")
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Inside)
		import Inside
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
		        thingBuilder: (() -> any Thing)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_fillBody_C1AA9D91E87720F2(token: Token?) -> any Thing {
		            let thing: any Thing = LiveThing(token: token)
		            return thing
		        }
		        func __safeDI_outer() -> Outer {
		            func __safeDI_thingBuilder_Outer_DefaultGadget_Scope_thing(_ scope: Outer.SafeDIMockScope_Thing.DefaultGadget_Scope.thing_Values, token: Token?) -> any Thing {
		                return __safeDI_fillBody_C1AA9D91E87720F2(token: token)
		            }
		            func __safeDI_thingBuilder_Outer() -> Outer.SafeDIMockScope_Thing.__safeDI_Builder<any Thing> {
		                .init(inner_gadgetBuilder: { _ in __safeDI_thingBuilder_Outer_Inner() })
		            }
		            func __safeDI_thingBuilder_Outer_Inner() -> Inner.SafeDIMockScope_Gadget.__safeDI_Builder<Outer.SafeDIMockScope_Thing.DefaultGadget_Scope.__safeDI_Builder<any Thing>> {
		                .init(deeper_widgetBuilder: { _ in __safeDI_gadgetBuilder_Inner_Deeper() })
		            }
		            func __safeDI_gadgetBuilder_Inner_Deeper() -> Deeper.SafeDIMockScope_Widget.__safeDI_Builder<Inner.SafeDIMockScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<Outer.SafeDIMockScope_Thing.DefaultGadget_Scope.__safeDI_Builder<any Thing>>> {
		                .init(screenBuilder: { _ in __safeDI_gadgetBuilder_Inner_Deeper_Screen_Scope() })
		            }
		            func __safeDI_gadgetBuilder_Inner_Deeper_Screen_Scope() -> Deeper.SafeDIMockScope_Widget.Screen_Scope.__safeDI_Builder<Inner.SafeDIMockScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<Outer.SafeDIMockScope_Thing.DefaultGadget_Scope.__safeDI_Builder<any Thing>>> {
		                .init(widget: { values in __safeDI_thingBuilder_Outer_Inner_DefaultWidget_Scope(token: values.token) })
		            }
		            func __safeDI_thingBuilder_Outer_Inner_DefaultWidget_Scope(token: Token) -> Inner.SafeDIMockScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<Outer.SafeDIMockScope_Thing.DefaultGadget_Scope.__safeDI_Builder<any Thing>> {
		                .init(gadget: { _ in __safeDI_thingBuilder_Outer_DefaultGadget_Scope(token: token) })
		            }
		            func __safeDI_thingBuilder_Outer_DefaultGadget_Scope(token: Token) -> Outer.SafeDIMockScope_Thing.DefaultGadget_Scope.__safeDI_Builder<any Thing> {
		                .init(thing: { scope in __safeDI_thingBuilder_Outer_DefaultGadget_Scope_thing(scope, token: token) })
		            }
		            _ = Outer.__safeDI_Outer_mock_81539147E67FF5F4.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Outer.__safeDI_mock(thingBuilder: thingBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_thingBuilder_Outer(), safeDIOverrides: safeDIOverrides.outer)
		        }
		        let outer: Outer = __safeDI_outer()
		        return Root(outer: outer)
		    }
		}
		#endif
		""")
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// A public struct named `name` that generates a public mock, whose initializer is `package`: no module of another
	/// package can build it inline, so each calls its mock.
	private static func publicMockType(named name: String, declarations: [String]) -> String {
		seamFixtureType(named: name, declarations: declarations)
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(generateMock: .public)\n")
			.replacingOccurrences(of: "    public init(", with: "    package init(")
	}

	/// `Root`, which generates an internal mock, with `declarations`.
	private static func mockedRoot(declarations: [String]) -> String {
		seamFixtureType(named: "Root", declarations: declarations)
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(generateMock: true)\n")
	}

	private static func fulfillingType(named name: String, fulfilling fulfilledType: String, declarations: [String]) -> String {
		seamFixtureType(named: name, declarations: declarations, conformances: ", \(fulfilledType)")
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [\(fulfilledType).self])\n")
	}

	/// Each module of `files`, in order, in a package of its own, depending on and importing every module before it.
	private static func modules(_ files: [(name: String, swiftFileContent: [String])]) -> [ModuleFixture] {
		files.enumerated().map { index, module in
			let dependencies = files[..<index].map(\.name)
			let imports = dependencies.map { "import \($0)\n" }.joined()
			return ModuleFixture(
				name: module.name,
				packageName: "\(module.name)Package",
				swiftFileContent: module.swiftFileContent.map { imports.isEmpty ? $0 : imports + "\n" + $0 },
				dependencies: dependencies,
			)
		}
	}
}
