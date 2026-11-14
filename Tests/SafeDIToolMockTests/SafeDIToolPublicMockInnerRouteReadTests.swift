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
/// farther out, and a case of the called mock's enum for a fill of a mock it calls carries that mock's scope, whose
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
	mutating func generate_passesPlaceUpOnRouteWhereCallingMocksLevelBindsLabelLater_whenOneCaseOfCalledMockStandsForTwoPlacesOneRouteOfWhichHoldsValue() async throws {
		// `Inner` builds `Model`, whose `service` is a hole, in `Page`, which binds `token` before it, and at its root: one case
		// of `Inner`'s stands for both places. `Outer` calls `Inner` inside `wrapper`, fills `service` with `DefaultService`,
		// whose `gadget` only `App` can build, and binds `token: Receipt` after `wrapper`. `LiveGadget` requires `token:
		// Token`: on the `page` route a level of `Inner`'s holds it; on the other none does, and `Outer`'s `wrapper` case
		// binds `token` later, which hides every value farther out, so `App` passes `nil` on and passes the place up there.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modules([
				("Feature", [
					"public protocol Service {}\npublic protocol Gadget {}",
					seamFixtureType(named: "Token", isFinalClass: true, declarations: []),
					seamFixtureType(named: "Model", declarations: ["@Instantiated public let service: any Service"]),
					seamFixtureType(named: "Page", declarations: ["@Instantiated public let token: Token", "@Instantiated public let model: Model"]),
					Self.publicMockType(named: "Inner", declarations: ["@Instantiated public let page: Page", "@Instantiated public let model: Model"]),
				]),
				("Middle", [
					seamFixtureType(named: "Receipt", isFinalClass: true, declarations: ["@Received public let wrapper: Wrapper"]),
					Self.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let gadget: any Gadget"]),
					seamFixtureType(named: "Wrapper", declarations: ["@Instantiated public let inner: Inner"]),
					Self.publicMockType(named: "Outer", declarations: ["@Instantiated public let wrapper: Wrapper", "@Instantiated public let token: Receipt"]),
				]),
				("App", [
					Self.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received public let token: Token"]),
					Self.mockedRoot(declarations: ["@Instantiated public let outer: Outer"]),
				]),
			]),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Middle"]?.generatedFiles["Middle.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		#if DEBUG
		extension Outer {
		    @frozen public enum SafeDIMockScope_Gadget {
		        case wrapper(wrapper_Values, SafeDIMockScope_Gadget.Wrapper_Scope)

		        public struct wrapper_Values {}

		        @frozen public enum Wrapper_Scope {
		            case inner_serviceBuilder(inner_serviceBuilder_Values, Inner.SafeDIMockScope_Service, SafeDIMockScope_Gadget.DefaultService_Scope)

		            public struct inner_serviceBuilder_Values {}
		        }

		        @frozen public enum DefaultService_Scope {
		            case gadget(gadget_Values)

		            public struct gadget_Values {}
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            wrapper: __safeDI_Middle_Wrapper_MockConfiguration = .init(),
		            token: ((Wrapper) -> Receipt)? = nil
		        ) {
		            self.wrapper = wrapper
		            self.token = token
		        }

		        public let wrapper: __safeDI_Middle_Wrapper_MockConfiguration
		        public let token: ((Wrapper) -> Receipt)?
		    }

		    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module's SafeDI dependencies.
		    public static func mock(
		        gadgetBuilder: @escaping (Outer.SafeDIMockScope_Gadget) -> any Gadget,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Outer {
		        let __safeDI_gadgetBuilder = gadgetBuilder
		        let __safeDI_gadgetValues_wrapper = SafeDIMockScope_Gadget.wrapper_Values()
		        func __safeDI_wrapper() -> Wrapper {
		            let __safeDI_gadgetValues_inner_serviceBuilder = SafeDIMockScope_Gadget.Wrapper_Scope.inner_serviceBuilder_Values()
		            func __safeDI_inner() -> Inner {
		                func __safeDI_serviceBuilder_Inner(_ __safeDI_inner_serviceBuilder: Inner.SafeDIMockScope_Service) -> any Service {
		                    switch __safeDI_inner_serviceBuilder {
		                    case let .page(_, scope): return __safeDI_serviceBuilder_Inner_Page_Scope(scope, __safeDI_inner_serviceBuilder: __safeDI_inner_serviceBuilder)
		                    case let .model(_, scope): return __safeDI_serviceBuilder_Inner_Model_Scope(scope, __safeDI_inner_serviceBuilder: __safeDI_inner_serviceBuilder)
		                    }
		                }
		                func __safeDI_serviceBuilder_Inner_Page_Scope(_ scope: Inner.SafeDIMockScope_Service.Page_Scope, __safeDI_inner_serviceBuilder: Inner.SafeDIMockScope_Service) -> any Service {
		                    switch scope {
		                    case let .model(_, scope): return __safeDI_serviceBuilder_Inner_Model_Scope(scope, __safeDI_inner_serviceBuilder: __safeDI_inner_serviceBuilder)
		                    }
		                }
		                func __safeDI_serviceBuilder_Inner_Model_Scope(_ scope: Inner.SafeDIMockScope_Service.Model_Scope, __safeDI_inner_serviceBuilder: Inner.SafeDIMockScope_Service) -> any Service {
		                    switch scope {
		                    case .service:
		                        func __safeDI_service() -> DefaultService {
		                            let gadget: any Gadget = __safeDI_gadgetBuilder(.wrapper(__safeDI_gadgetValues_wrapper, .inner_serviceBuilder(__safeDI_gadgetValues_inner_serviceBuilder, __safeDI_inner_serviceBuilder, .gadget(SafeDIMockScope_Gadget.DefaultService_Scope.gadget_Values()))))
		                            return DefaultService(gadget: gadget)
		                        }
		                        let service: any Service = __safeDI_service()
		                        return service
		                    }
		                }
		                _ = Inner.__safeDI_Inner_mock_9A3489C424741DFE.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                return Inner.mock(serviceBuilder: __safeDI_serviceBuilder_Inner, safeDIOverrides: safeDIOverrides.wrapper.inner)
		            }
		            let inner: Inner = __safeDI_inner()
		            return Wrapper.__safeDI_init(inner: inner, safeDIBuilder: safeDIOverrides.wrapper.safeDIBuilder)
		        }
		        let wrapper: Wrapper = __safeDI_wrapper()
		        let token = if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder(wrapper) } else { Receipt(wrapper: wrapper) }
		        return Outer(wrapper: wrapper, token: token)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_mock_C42A1AC8873F627D {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `Wrapper` is constructed within the public mock trees of module `Middle`.
		nonisolated public struct __safeDI_Middle_Wrapper_MockConfiguration {
		    public init(
		        inner: Inner.SafeDIOverrides = .init(),
		        _ safeDIBuilder: ((Inner) -> Wrapper)? = nil
		    ) {
		        self.inner = inner
		        self.safeDIBuilder = safeDIBuilder
		    }

		    public let inner: Inner.SafeDIOverrides
		    /// Overrides how `Wrapper` is constructed. Parameters match the type’s initializer or custom mock method.
		    public let safeDIBuilder: ((Inner) -> Wrapper)?
		}

		extension Wrapper {
		    static func __safeDI_init(inner: Inner, safeDIBuilder: ((Inner) -> Wrapper)?) -> Wrapper {
		        if let safeDIBuilder { safeDIBuilder(inner) } else { Wrapper(inner: inner) }
		    }
		}
		#endif

		""")
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
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
		            self.outer = outer
		        }

		        let outer: Outer.SafeDIOverrides
		    }

		    static func mock(
		        gadgetBuilder: @escaping (Outer.SafeDIMockScope_Gadget) -> any Gadget,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_outer() -> Outer {
		            func __safeDI_gadgetBuilder_Outer_DefaultService_Scope_gadget(_ scope: Outer.SafeDIMockScope_Gadget.DefaultService_Scope.gadget_Values, token: Token) -> any Gadget {
		                let gadget: any Gadget = LiveGadget(token: token)
		                return gadget
		            }
		            func __safeDI_gadgetBuilder_Outer(_ scope: Outer.SafeDIMockScope_Gadget, passUp: () -> any Gadget) -> any Gadget {
		                switch scope {
		                case let .wrapper(_, scope): return __safeDI_gadgetBuilder_Outer_Wrapper_Scope(scope, token: nil, passUp: passUp)
		                }
		            }
		            func __safeDI_gadgetBuilder_Outer_Wrapper_Scope(_ scope: Outer.SafeDIMockScope_Gadget.Wrapper_Scope, token: Token?, passUp: () -> any Gadget) -> any Gadget {
		                switch scope {
		                case let .inner_serviceBuilder(_, innerScope, scope): return __safeDI_gadgetBuilder_Outer_DefaultService_Scope(scope, token: __safeDI_token_Inner_SafeDIMockScope_Service(innerScope) ?? token, passUp: passUp)
		                }
		            }
		            func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(_ scope: Outer.SafeDIMockScope_Gadget.DefaultService_Scope, token: Token?, passUp: () -> any Gadget) -> any Gadget {
		                switch scope {
		                case let .gadget(scope): if let token { return __safeDI_gadgetBuilder_Outer_DefaultService_Scope_gadget(scope, token: token) } else { return passUp() }
		                }
		            }
		            func __safeDI_token_Inner_SafeDIMockScope_Service(_ scope: Inner.SafeDIMockScope_Service) -> Token? {
		                switch scope {
		                case let .page(_, scope): return __safeDI_token_Inner_Page_Scope(scope)
		                case .model: return nil
		                }
		            }
		            func __safeDI_token_Inner_Page_Scope(_ scope: Inner.SafeDIMockScope_Service.Page_Scope) -> Token {
		                switch scope {
		                case let .model(values, _): return values.token
		                }
		            }
		            _ = Outer.__safeDI_Outer_mock_C42A1AC8873F627D.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Outer.mock(gadgetBuilder: { scope in __safeDI_gadgetBuilder_Outer(scope, passUp: { gadgetBuilder(scope) }) }, safeDIOverrides: safeDIOverrides.outer)
		        }
		        let outer: Outer = __safeDI_outer()
		        return Root(outer: outer)
		    }
		}
		#endif
		""")
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
		    @frozen public enum SafeDIMockScope_Gadget {
		        case deeper_widgetBuilder(deeper_widgetBuilder_Values, Deeper.SafeDIMockScope_Widget, SafeDIMockScope_Gadget.DefaultWidget_Scope)

		        public struct deeper_widgetBuilder_Values {}

		        @frozen public enum DefaultWidget_Scope {
		            case gadget(gadget_Values)

		            public struct gadget_Values {}
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            deeper: Deeper.SafeDIOverrides = .init()
		        ) {
		            self.deeper = deeper
		        }

		        public let deeper: Deeper.SafeDIOverrides
		    }

		    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module's SafeDI dependencies.
		    public static func mock(
		        gadgetBuilder: @escaping (Inner.SafeDIMockScope_Gadget) -> any Gadget,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Inner {
		        let __safeDI_gadgetBuilder = gadgetBuilder
		        let __safeDI_gadgetValues_deeper_widgetBuilder = SafeDIMockScope_Gadget.deeper_widgetBuilder_Values()
		        func __safeDI_deeper() -> Deeper {
		            func __safeDI_widgetBuilder_Deeper(_ __safeDI_deeper_widgetBuilder: Deeper.SafeDIMockScope_Widget) -> any Widget {
		                switch __safeDI_deeper_widgetBuilder {
		                case let .screenBuilder(_, scope): return __safeDI_widgetBuilder_Deeper_Screen_Scope(scope, __safeDI_deeper_widgetBuilder: __safeDI_deeper_widgetBuilder)
		                }
		            }
		            func __safeDI_widgetBuilder_Deeper_Screen_Scope(_ scope: Deeper.SafeDIMockScope_Widget.Screen_Scope, __safeDI_deeper_widgetBuilder: Deeper.SafeDIMockScope_Widget) -> any Widget {
		                switch scope {
		                case .widget:
		                    func __safeDI_widget() -> DefaultWidget {
		                        let gadget: any Gadget = __safeDI_gadgetBuilder(.deeper_widgetBuilder(__safeDI_gadgetValues_deeper_widgetBuilder, __safeDI_deeper_widgetBuilder, .gadget(SafeDIMockScope_Gadget.DefaultWidget_Scope.gadget_Values())))
		                        return DefaultWidget(gadget: gadget)
		                    }
		                    let widget: any Widget = __safeDI_widget()
		                    return widget
		                }
		            }
		            _ = Deeper.__safeDI_Deeper_mock_B307990F5E8CC787.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Deeper.mock(widgetBuilder: __safeDI_widgetBuilder_Deeper, safeDIOverrides: safeDIOverrides.deeper)
		        }
		        let deeper: Deeper = __safeDI_deeper()
		        return Inner(deeper: deeper)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_mock_8125A45FD8C4BDDC {}
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
		    @frozen public enum SafeDIMockScope_Thing {
		        case inner_gadgetBuilder(inner_gadgetBuilder_Values, Inner.SafeDIMockScope_Gadget, SafeDIMockScope_Thing.DefaultGadget_Scope)

		        public struct inner_gadgetBuilder_Values {}

		        @frozen public enum DefaultGadget_Scope {
		            case thing(thing_Values)

		            public struct thing_Values {}
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            inner: Inner.SafeDIOverrides = .init()
		        ) {
		            self.inner = inner
		        }

		        public let inner: Inner.SafeDIOverrides
		    }

		    // SafeDI counts `Thing` as `public`: no module it reads declares it narrower. If `Thing` is `package` in a first-party module, run SafeDI on that module and list it among this module's SafeDI dependencies.
		    public static func mock(
		        thingBuilder: @escaping (Outer.SafeDIMockScope_Thing) -> any Thing,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Outer {
		        let __safeDI_thingBuilder = thingBuilder
		        let __safeDI_thingValues_inner_gadgetBuilder = SafeDIMockScope_Thing.inner_gadgetBuilder_Values()
		        func __safeDI_inner() -> Inner {
		            func __safeDI_gadgetBuilder_Inner(_ __safeDI_inner_gadgetBuilder: Inner.SafeDIMockScope_Gadget) -> any Gadget {
		                switch __safeDI_inner_gadgetBuilder {
		                case let .deeper_widgetBuilder(_, _, scope): return __safeDI_gadgetBuilder_Inner_DefaultWidget_Scope(scope, __safeDI_inner_gadgetBuilder: __safeDI_inner_gadgetBuilder)
		                }
		            }
		            func __safeDI_gadgetBuilder_Inner_DefaultWidget_Scope(_ scope: Inner.SafeDIMockScope_Gadget.DefaultWidget_Scope, __safeDI_inner_gadgetBuilder: Inner.SafeDIMockScope_Gadget) -> any Gadget {
		                switch scope {
		                case .gadget:
		                    func __safeDI_gadget() -> DefaultGadget {
		                        let thing: any Thing = __safeDI_thingBuilder(.inner_gadgetBuilder(__safeDI_thingValues_inner_gadgetBuilder, __safeDI_inner_gadgetBuilder, .thing(SafeDIMockScope_Thing.DefaultGadget_Scope.thing_Values())))
		                        return DefaultGadget(thing: thing)
		                    }
		                    let gadget: any Gadget = __safeDI_gadget()
		                    return gadget
		                }
		            }
		            _ = Inner.__safeDI_Inner_mock_8125A45FD8C4BDDC.self // If this line does not compile, compile the code SafeDI generates for module Inside into Inside: under Bazel, add Inside's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Inner.mock(gadgetBuilder: __safeDI_gadgetBuilder_Inner, safeDIOverrides: safeDIOverrides.inner)
		        }
		        let inner: Inner = __safeDI_inner()
		        return Outer(inner: inner)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_mock_0D3CC60523CC6213 {}
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
		            self.outer = outer
		        }

		        let outer: Outer.SafeDIOverrides
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_outer() -> Outer {
		            func __safeDI_thingBuilder_Outer(_ scope: Outer.SafeDIMockScope_Thing) -> any Thing {
		                switch scope {
		                case let .inner_gadgetBuilder(_, innerScope, scope): return __safeDI_thingBuilder_Outer_DefaultGadget_Scope(scope, token: __safeDI_token_Inner_SafeDIMockScope_Gadget(innerScope))
		                }
		            }
		            func __safeDI_thingBuilder_Outer_DefaultGadget_Scope(_ scope: Outer.SafeDIMockScope_Thing.DefaultGadget_Scope, token: Token?) -> any Thing {
		                switch scope {
		                case .thing:
		                    let thing: any Thing = LiveThing(token: token)
		                    return thing
		                }
		            }
		            func __safeDI_token_Inner_SafeDIMockScope_Gadget(_ scope: Inner.SafeDIMockScope_Gadget) -> Token {
		                switch scope {
		                case let .deeper_widgetBuilder(_, innerScope, _): return __safeDI_token_Deeper_SafeDIMockScope_Widget(innerScope)
		                }
		            }
		            func __safeDI_token_Deeper_SafeDIMockScope_Widget(_ scope: Deeper.SafeDIMockScope_Widget) -> Token {
		                switch scope {
		                case let .screenBuilder(_, scope): return __safeDI_token_Deeper_Screen_Scope(scope)
		                }
		            }
		            func __safeDI_token_Deeper_Screen_Scope(_ scope: Deeper.SafeDIMockScope_Widget.Screen_Scope) -> Token {
		                switch scope {
		                case let .widget(values): return values.token
		                }
		            }
		            _ = Outer.__safeDI_Outer_mock_0D3CC60523CC6213.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Outer.mock(thingBuilder: __safeDI_thingBuilder_Outer, safeDIOverrides: safeDIOverrides.outer)
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
