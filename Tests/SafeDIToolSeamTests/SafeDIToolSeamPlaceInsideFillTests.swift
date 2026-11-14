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

/// A place inside a fill: `Outer` fills `Inner`'s hole with a type whose tree holds a hole `Outer` cannot fill. `Outer`'s
/// enum has one case per call and builder filled, `<call>_<builder>`, holding `Outer`'s level, the scope value `Inner`
/// handed the fill, and the enum of the type the fill builds, nested by type; a fill `App` generates for the place reads a
/// value `Inner`'s levels hold through one reader per enum of `Inner`'s that leads to it, and the value `Outer`'s levels,
/// or its own scope, hold where a route of `Inner`'s holds none. Each test compiles every module and compares the values
/// the seams build with those of the same graph built inline.
struct SafeDIToolSeamPlaceInsideFillTests: ~Copyable {
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
	mutating func generate_nestsPlaceInsideFillByType_whenOuterFillsInnersHoleWithTypeHoldingHoleItCannotFill() async throws {
		// The design's example. `Inner` builds `service` at its root and in the `Screen` its `screenBuilder` builds, which
		// forwards `id`. `Outer` fills both with `DefaultService`, whose `gadget` only `App` can build: one case of
		// `Outer`'s root, `inner_serviceBuilder`, holds `Outer`'s level, `Inner`'s scope, and `DefaultService_Scope`. `App`'s
		// `LiveGadget` reads `id`, which only the `screenBuilder` route of `Inner`'s holds: the reader finds it there, and the
		// root dispatcher passes `nil`, as inline, on the other.
		try await expectPlaceInsideFill(
			feature: Self.inner(screen: ["@Forwarded public let id: Int"]),
			middle: [
				seamFixtureType(named: "Tag", isFinalClass: true, declarations: []),
				Self.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let gadget: any Gadget"]),
				seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated public let tag: Tag", "@Instantiated public let inner: Inner"]),
			],
			app: [
				Self.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received public let tag: Tag", "@Received(onlyIfAvailable: true) public let id: Int?"]),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let outer: Outer"]),
			],
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().outer.inner.screenBuilder.instantiate(7)")],
			expectedMiddle: """
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
			            _ = Inner.__safeDI_Inner_771FB74B7F0FC507.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
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
			            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner)
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(tag: tag, inner: inner)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_B543483265135986 {}
			}
			""",
			expectedApp: """
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
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_nestsEachTypeInsideFillByType_whenPlaceIsTwoTypesDeepInsideFill() async throws {
		// `DefaultService` builds `tool`, then `widget`, whose `Widget` builds `gadget`: `DefaultService_Scope`'s case
		// `widget` carries `tool` and holds `Widget_Scope`. `LiveGadget` reads `tool` from that level, `tag` from `Outer`'s,
		// and `id` through the reader of `Inner`'s.
		try await expectPlaceInsideFill(
			feature: Self.inner(screen: ["@Forwarded public let id: Int"]),
			middle: [
				seamFixtureType(named: "Tag", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Tool", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Widget", declarations: ["@Instantiated public let gadget: any Gadget"]),
				Self.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let tool: Tool", "@Instantiated public let widget: Widget"]),
				seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated public let tag: Tag", "@Instantiated public let inner: Inner"]),
			],
			app: [
				Self.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received public let tag: Tag", "@Received public let tool: Tool", "@Received(onlyIfAvailable: true) public let id: Int?"]),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let outer: Outer"]),
			],
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().outer.inner.screenBuilder.instantiate(3)")],
			expectedMiddle: """
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
			            case widget(widget_Values, SafeDIScope_Gadget.Widget_Scope)

			            public struct widget_Values {
			                public let tool: Tool
			            }
			        }

			        @frozen public enum Widget_Scope {
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
			            _ = Inner.__safeDI_Inner_771FB74B7F0FC507.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_serviceBuilder_Inner(_ __safeDI_inner_serviceBuilder: Inner.SafeDIScope_Service) -> any Service {
			                switch __safeDI_inner_serviceBuilder {
			                case let .screenBuilder(_, scope): return __safeDI_serviceBuilder_Inner_Screen_Scope(scope, __safeDI_inner_serviceBuilder: __safeDI_inner_serviceBuilder)
			                case .service:
			                    func __safeDI_service() -> DefaultService {
			                        let tool = Tool()
			                        let __safeDI_gadgetValues_widget = SafeDIScope_Gadget.DefaultService_Scope.widget_Values(tool: tool)
			                        func __safeDI_widget() -> Widget {
			                            let gadget: any Gadget = __safeDI_gadgetBuilder(.inner_serviceBuilder(__safeDI_gadgetValues_inner_serviceBuilder, __safeDI_inner_serviceBuilder, .widget(__safeDI_gadgetValues_widget, .gadget(SafeDIScope_Gadget.Widget_Scope.gadget_Values()))))
			                            return Widget(gadget: gadget)
			                        }
			                        let widget: Widget = __safeDI_widget()
			                        return DefaultService(tool: tool, widget: widget)
			                    }
			                    let service: any Service = __safeDI_service()
			                    return service
			                }
			            }
			            func __safeDI_serviceBuilder_Inner_Screen_Scope(_ scope: Inner.SafeDIScope_Service.Screen_Scope, __safeDI_inner_serviceBuilder: Inner.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case .service:
			                    func __safeDI_service() -> DefaultService {
			                        let tool = Tool()
			                        let __safeDI_gadgetValues_widget = SafeDIScope_Gadget.DefaultService_Scope.widget_Values(tool: tool)
			                        func __safeDI_widget() -> Widget {
			                            let gadget: any Gadget = __safeDI_gadgetBuilder(.inner_serviceBuilder(__safeDI_gadgetValues_inner_serviceBuilder, __safeDI_inner_serviceBuilder, .widget(__safeDI_gadgetValues_widget, .gadget(SafeDIScope_Gadget.Widget_Scope.gadget_Values()))))
			                            return Widget(gadget: gadget)
			                        }
			                        let widget: Widget = __safeDI_widget()
			                        return DefaultService(tool: tool, widget: widget)
			                    }
			                    let service: any Service = __safeDI_service()
			                    return service
			                }
			            }
			            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner)
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(tag: tag, inner: inner)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_AF9CCD43B046AE8D {}
			}
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			extension Root {
			    public init() {
			        func __safeDI_outer() -> Outer {
			            _ = Outer.__safeDI_Outer_AF9CCD43B046AE8D.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_gadgetBuilder_Outer(_ scope: Outer.SafeDIScope_Gadget) -> any Gadget {
			                switch scope {
			                case let .inner_serviceBuilder(values, innerScope, scope): return __safeDI_gadgetBuilder_Outer_DefaultService_Scope(scope, id: __safeDI_id_Inner_SafeDIScope_Service(innerScope), tag: values.tag)
			                }
			            }
			            func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(_ scope: Outer.SafeDIScope_Gadget.DefaultService_Scope, id: Int?, tag: Tag) -> any Gadget {
			                switch scope {
			                case let .widget(values, scope): return __safeDI_gadgetBuilder_Outer_Widget_Scope(scope, id: id, tag: tag, tool: values.tool)
			                }
			            }
			            func __safeDI_gadgetBuilder_Outer_Widget_Scope(_ scope: Outer.SafeDIScope_Gadget.Widget_Scope, id: Int?, tag: Tag, tool: Tool) -> any Gadget {
			                switch scope {
			                case .gadget:
			                    let gadget: any Gadget = LiveGadget(tag: tag, tool: tool, id: id)
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
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_holdsCallsCaseInFulfillersEnum_whenPlaceIsInsideFillOfCallInsideFill() async throws {
		// `DefaultService`, which fills `Inner`'s hole, calls `Part`'s seam `Holder`, whose hole `Outer` fills with
		// `DefaultPart`, whose `gadget` only `App` can build: `DefaultService_Scope` has the case `holder_partBuilder`, which
		// holds `Holder`'s scope and `DefaultPart_Scope`. `LiveGadget` reads `label` through the reader of `Holder`'s levels
		// and `id` through the reader of `Inner`'s.
		try await expectPlaceInsideFill(
			feature: Self.inner(screen: ["@Forwarded public let id: Int"]) + [
				"public protocol Part {}",
				seamFixtureType(named: "Label", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Holder", isSeam: true, declarations: ["@Instantiated public let label: Label", "@Instantiated public let part: any Part"]),
			],
			middle: [
				Self.fulfillingType(named: "DefaultPart", fulfilling: "Part", declarations: ["@Instantiated public let gadget: any Gadget"]),
				Self.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let holder: Holder"]),
				seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated public let inner: Inner"]),
			],
			app: [
				Self.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received public let label: Label", "@Received(onlyIfAvailable: true) public let id: Int?"]),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let outer: Outer"]),
			],
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().outer.inner.screenBuilder.instantiate(5)")],
			expectedMiddle: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Outer {
			    @frozen public enum SafeDIScope_Gadget {
			        case inner_serviceBuilder(inner_serviceBuilder_Values, Inner.SafeDIScope_Service, SafeDIScope_Gadget.DefaultService_Scope)

			        public struct inner_serviceBuilder_Values {}

			        @frozen public enum DefaultService_Scope {
			            case holder_partBuilder(holder_partBuilder_Values, Holder.SafeDIScope_Part, SafeDIScope_Gadget.DefaultPart_Scope)

			            public struct holder_partBuilder_Values {}
			        }

			        @frozen public enum DefaultPart_Scope {
			            case gadget(gadget_Values)

			            public struct gadget_Values {}
			        }
			    }

			    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_gadgetBuilder: @escaping (SafeDIScope_Gadget) -> any Gadget) {
			        let __safeDI_gadgetValues_inner_serviceBuilder = SafeDIScope_Gadget.inner_serviceBuilder_Values()
			        func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_771FB74B7F0FC507.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_serviceBuilder_Inner(_ __safeDI_inner_serviceBuilder: Inner.SafeDIScope_Service) -> any Service {
			                switch __safeDI_inner_serviceBuilder {
			                case let .screenBuilder(_, scope): return __safeDI_serviceBuilder_Inner_Screen_Scope(scope, __safeDI_inner_serviceBuilder: __safeDI_inner_serviceBuilder)
			                case .service:
			                    func __safeDI_service() -> DefaultService {
			                        let __safeDI_gadgetValues_holder_partBuilder = SafeDIScope_Gadget.DefaultService_Scope.holder_partBuilder_Values()
			                        func __safeDI_holder() -> Holder {
			                            _ = Holder.__safeDI_Holder_DB2DD03F4E75166E.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			                            func __safeDI_partBuilder_Holder(_ __safeDI_holder_partBuilder: Holder.SafeDIScope_Part) -> any Part {
			                                switch __safeDI_holder_partBuilder {
			                                case .part:
			                                    func __safeDI_part() -> DefaultPart {
			                                        let gadget: any Gadget = __safeDI_gadgetBuilder(.inner_serviceBuilder(__safeDI_gadgetValues_inner_serviceBuilder, __safeDI_inner_serviceBuilder, .holder_partBuilder(__safeDI_gadgetValues_holder_partBuilder, __safeDI_holder_partBuilder, .gadget(SafeDIScope_Gadget.DefaultPart_Scope.gadget_Values()))))
			                                        return DefaultPart(gadget: gadget)
			                                    }
			                                    let part: any Part = __safeDI_part()
			                                    return part
			                                }
			                            }
			                            return Holder(__safeDI_partBuilder: __safeDI_partBuilder_Holder)
			                        }
			                        let holder: Holder = __safeDI_holder()
			                        return DefaultService(holder: holder)
			                    }
			                    let service: any Service = __safeDI_service()
			                    return service
			                }
			            }
			            func __safeDI_serviceBuilder_Inner_Screen_Scope(_ scope: Inner.SafeDIScope_Service.Screen_Scope, __safeDI_inner_serviceBuilder: Inner.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case .service:
			                    func __safeDI_service() -> DefaultService {
			                        let __safeDI_gadgetValues_holder_partBuilder = SafeDIScope_Gadget.DefaultService_Scope.holder_partBuilder_Values()
			                        func __safeDI_holder() -> Holder {
			                            _ = Holder.__safeDI_Holder_DB2DD03F4E75166E.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			                            func __safeDI_partBuilder_Holder(_ __safeDI_holder_partBuilder: Holder.SafeDIScope_Part) -> any Part {
			                                switch __safeDI_holder_partBuilder {
			                                case .part:
			                                    func __safeDI_part() -> DefaultPart {
			                                        let gadget: any Gadget = __safeDI_gadgetBuilder(.inner_serviceBuilder(__safeDI_gadgetValues_inner_serviceBuilder, __safeDI_inner_serviceBuilder, .holder_partBuilder(__safeDI_gadgetValues_holder_partBuilder, __safeDI_holder_partBuilder, .gadget(SafeDIScope_Gadget.DefaultPart_Scope.gadget_Values()))))
			                                        return DefaultPart(gadget: gadget)
			                                    }
			                                    let part: any Part = __safeDI_part()
			                                    return part
			                                }
			                            }
			                            return Holder(__safeDI_partBuilder: __safeDI_partBuilder_Holder)
			                        }
			                        let holder: Holder = __safeDI_holder()
			                        return DefaultService(holder: holder)
			                    }
			                    let service: any Service = __safeDI_service()
			                    return service
			                }
			            }
			            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner)
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(inner: inner)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_B5C153CF6CD6E2AF {}
			}
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			extension Root {
			    public init() {
			        func __safeDI_outer() -> Outer {
			            _ = Outer.__safeDI_Outer_B5C153CF6CD6E2AF.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_gadgetBuilder_Outer(_ scope: Outer.SafeDIScope_Gadget) -> any Gadget {
			                switch scope {
			                case let .inner_serviceBuilder(_, innerScope, scope): return __safeDI_gadgetBuilder_Outer_DefaultService_Scope(scope, id: __safeDI_id_Inner_SafeDIScope_Service(innerScope))
			                }
			            }
			            func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(_ scope: Outer.SafeDIScope_Gadget.DefaultService_Scope, id: Int?) -> any Gadget {
			                switch scope {
			                case let .holder_partBuilder(_, innerScope, scope): return __safeDI_gadgetBuilder_Outer_DefaultPart_Scope(scope, id: id, label: __safeDI_label_Holder_SafeDIScope_Part(innerScope))
			                }
			            }
			            func __safeDI_gadgetBuilder_Outer_DefaultPart_Scope(_ scope: Outer.SafeDIScope_Gadget.DefaultPart_Scope, id: Int?, label: Label) -> any Gadget {
			                switch scope {
			                case .gadget:
			                    let gadget: any Gadget = LiveGadget(label: label, id: id)
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
			            func __safeDI_label_Holder_SafeDIScope_Part(_ scope: Holder.SafeDIScope_Part) -> Label {
			                switch scope {
			                case let .part(values): return values.label
			                }
			            }
			            return Outer(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Outer)
			        }
			        let outer: Outer = __safeDI_outer()
			        self.init(outer: outer)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsOuterLevelWhereNoInnerLevelHoldsValue_whenOneRouteOfInnersHoldsIt() async throws {
		// `Screen` forwards `session`, and `Outer` builds its own before `inner`: on the `screenBuilder` route `LiveGadget`
		// reads `Screen`'s, nearer, and on the other `Outer`'s, which `Outer`'s level carries.
		try await expectPlaceInsideFill(
			feature: [seamFixtureType(named: "Session", isFinalClass: true, declarations: [])] + Self.inner(screen: ["@Forwarded public let session: Session"]),
			middle: [
				Self.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let gadget: any Gadget"]),
				seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated public let session: Session", "@Instantiated public let inner: Inner"]),
			],
			app: [
				Self.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received public let session: Session"]),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let outer: Outer"]),
			],
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().outer.inner.screenBuilder.instantiate(Session())")],
			expectedMiddle: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Outer {
			    @frozen public enum SafeDIScope_Gadget {
			        case inner_serviceBuilder(inner_serviceBuilder_Values, Inner.SafeDIScope_Service, SafeDIScope_Gadget.DefaultService_Scope)

			        public struct inner_serviceBuilder_Values {
			            public let session: Session
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
			        let session = Session()
			        let __safeDI_gadgetValues_inner_serviceBuilder = SafeDIScope_Gadget.inner_serviceBuilder_Values(session: session)
			        func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_2575B7DB3A5974A3.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
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
			            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner)
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(session: session, inner: inner)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_1597480E63586288 {}
			}
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			extension Root {
			    public init() {
			        func __safeDI_outer() -> Outer {
			            _ = Outer.__safeDI_Outer_1597480E63586288.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_gadgetBuilder_Outer(_ scope: Outer.SafeDIScope_Gadget) -> any Gadget {
			                switch scope {
			                case let .inner_serviceBuilder(values, innerScope, scope): return __safeDI_gadgetBuilder_Outer_DefaultService_Scope(scope, session: __safeDI_session_Inner_SafeDIScope_Service(innerScope) ?? values.session)
			                }
			            }
			            func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(_ scope: Outer.SafeDIScope_Gadget.DefaultService_Scope, session: Session) -> any Gadget {
			                switch scope {
			                case .gadget:
			                    let gadget: any Gadget = LiveGadget(session: session)
			                    return gadget
			                }
			            }
			            func __safeDI_session_Inner_SafeDIScope_Service(_ scope: Inner.SafeDIScope_Service) -> Session? {
			                switch scope {
			                case let .screenBuilder(_, scope): return __safeDI_session_Inner_Screen_Scope(scope)
			                case .service: return nil
			                }
			            }
			            func __safeDI_session_Inner_Screen_Scope(_ scope: Inner.SafeDIScope_Service.Screen_Scope) -> Session {
			                switch scope {
			                case let .service(values): return values.session
			                }
			            }
			            return Outer(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Outer)
			        }
			        let outer: Outer = __safeDI_outer()
			        self.init(outer: outer)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsCallersDeclarationWhereNoLevelHoldsValue_whenOneRouteOfInnersHoldsIt() async throws {
		// As above, but `Outer` builds no `session`: on the `service` route no level holds it, so the root dispatcher passes
		// `Root`'s, as inline.
		try await expectPlaceInsideFill(
			feature: [seamFixtureType(named: "Session", isFinalClass: true, declarations: [])] + Self.inner(screen: ["@Forwarded public let session: Session"]),
			middle: [
				Self.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let gadget: any Gadget"]),
				seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated public let inner: Inner"]),
			],
			app: [
				Self.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received public let session: Session"]),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let session: Session", "@Instantiated public let outer: Outer"]),
			],
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().outer.inner.screenBuilder.instantiate(Session())")],
			expectedMiddle: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Outer {
			    @frozen public enum SafeDIScope_Gadget {
			        case inner_serviceBuilder(inner_serviceBuilder_Values, Inner.SafeDIScope_Service, SafeDIScope_Gadget.DefaultService_Scope)

			        public struct inner_serviceBuilder_Values {}

			        @frozen public enum DefaultService_Scope {
			            case gadget(gadget_Values)

			            public struct gadget_Values {}
			        }
			    }

			    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_gadgetBuilder: @escaping (SafeDIScope_Gadget) -> any Gadget) {
			        let __safeDI_gadgetValues_inner_serviceBuilder = SafeDIScope_Gadget.inner_serviceBuilder_Values()
			        func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_2575B7DB3A5974A3.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
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
			            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner)
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(inner: inner)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_82EC2B084D26E195 {}
			}
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			extension Root {
			    public init() {
			        let session = Session()
			        func __safeDI_outer() -> Outer {
			            _ = Outer.__safeDI_Outer_82EC2B084D26E195.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_gadgetBuilder_Outer(_ scope: Outer.SafeDIScope_Gadget) -> any Gadget {
			                switch scope {
			                case let .inner_serviceBuilder(_, innerScope, scope): return __safeDI_gadgetBuilder_Outer_DefaultService_Scope(scope, session: __safeDI_session_Inner_SafeDIScope_Service(innerScope) ?? session)
			                }
			            }
			            func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(_ scope: Outer.SafeDIScope_Gadget.DefaultService_Scope, session: Session) -> any Gadget {
			                switch scope {
			                case .gadget:
			                    let gadget: any Gadget = LiveGadget(session: session)
			                    return gadget
			                }
			            }
			            func __safeDI_session_Inner_SafeDIScope_Service(_ scope: Inner.SafeDIScope_Service) -> Session? {
			                switch scope {
			                case let .screenBuilder(_, scope): return __safeDI_session_Inner_Screen_Scope(scope)
			                case .service: return nil
			                }
			            }
			            func __safeDI_session_Inner_Screen_Scope(_ scope: Inner.SafeDIScope_Service.Screen_Scope) -> Session {
			                switch scope {
			                case let .service(values): return values.session
			                }
			            }
			            return Outer(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Outer)
			        }
			        let outer: Outer = __safeDI_outer()
			        self.init(session: session, outer: outer)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_holdsInnersSendableScopeInSendableCase_whenFillOfPlaceInsideSendableFunctionHoldsPlace() async throws {
		// `Inner` builds `Screen` in a `SendableInstantiator`, so its `service` there is built by `Inner`'s `@Sendable`
		// builder and `Outer`'s fill of it is `@Sendable`: the `gadget` inside it is a case of `Outer`'s `@Sendable` enum,
		// `inner_serviceSendableBuilder`, which holds `Inner`'s `@Sendable` scope and `DefaultService_Scope`, and carries
		// no value `Outer` binds outside the fill. `LiveGadget` reads `id` through the readers of `Inner`'s `@Sendable` enum
		// and of the plain enum it holds.
		try await expectPlaceInsideFill(
			feature: Self.inner(screen: ["@Forwarded public let id: Int"], innerScreenBuilder: "SendableInstantiator<Screen>", conformances: ", Sendable"),
			middle: [
				Self.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let gadget: any Gadget"], conformances: ", Sendable"),
				seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated public let inner: Inner"], conformances: ", Sendable"),
			],
			app: [
				Self.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received(onlyIfAvailable: true) public let id: Int?"], conformances: ", Sendable"),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let outer: Outer"]),
			],
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().outer.inner.screenBuilder.instantiate(7)")],
			expectedMiddle: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Outer {
			    @frozen public enum SafeDIScope_Gadget {
			        case inner_serviceBuilder(inner_serviceBuilder_Values, Inner.SafeDIScope_Service, SafeDIScope_Gadget.DefaultService_Scope)

			        public struct inner_serviceBuilder_Values {}

			        @frozen public enum DefaultService_Scope {
			            case gadget(gadget_Values)

			            public struct gadget_Values {}
			        }
			    }

			    @frozen public enum SafeDISendableScope_Gadget {
			        case inner_serviceSendableBuilder(Inner.SafeDISendableScope_Service, SafeDIScope_Gadget.DefaultService_Scope)
			    }

			    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_gadgetBuilder: @escaping (SafeDIScope_Gadget) -> any Gadget, __safeDI_gadgetSendableBuilder: @escaping @Sendable (SafeDISendableScope_Gadget) -> any Gadget) {
			        let __safeDI_gadgetValues_inner_serviceBuilder = SafeDIScope_Gadget.inner_serviceBuilder_Values()
			        func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_6E35742E61C645A0.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_serviceBuilder_Inner(_ __safeDI_inner_serviceBuilder: Inner.SafeDIScope_Service) -> any Service {
			                switch __safeDI_inner_serviceBuilder {
			                case .service:
			                    func __safeDI_service() -> DefaultService {
			                        let gadget: any Gadget = __safeDI_gadgetBuilder(.inner_serviceBuilder(__safeDI_gadgetValues_inner_serviceBuilder, __safeDI_inner_serviceBuilder, .gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values())))
			                        return DefaultService(gadget: gadget)
			                    }
			                    let service: any Service = __safeDI_service()
			                    return service
			                }
			            }
			            @Sendable func __safeDI_serviceSendableBuilder_Inner(_ __safeDI_inner_serviceSendableBuilder: Inner.SafeDISendableScope_Service) -> any Service {
			                switch __safeDI_inner_serviceSendableBuilder {
			                case let .screenBuilder(scope): return __safeDI_serviceBuilder_Inner_Screen_Scope(scope, __safeDI_inner_serviceSendableBuilder: __safeDI_inner_serviceSendableBuilder)
			                }
			            }
			            @Sendable func __safeDI_serviceBuilder_Inner_Screen_Scope(_ scope: Inner.SafeDIScope_Service.Screen_Scope, __safeDI_inner_serviceSendableBuilder: Inner.SafeDISendableScope_Service) -> any Service {
			                switch scope {
			                case .service:
			                    func __safeDI_service() -> DefaultService {
			                        let gadget: any Gadget = __safeDI_gadgetSendableBuilder(.inner_serviceSendableBuilder(__safeDI_inner_serviceSendableBuilder, .gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values())))
			                        return DefaultService(gadget: gadget)
			                    }
			                    let service: any Service = __safeDI_service()
			                    return service
			                }
			            }
			            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner, __safeDI_serviceSendableBuilder: __safeDI_serviceSendableBuilder_Inner)
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(inner: inner)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_3F3B8A55B5803693 {}
			}
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			extension Root {
			    public init() {
			        func __safeDI_outer() -> Outer {
			            _ = Outer.__safeDI_Outer_3F3B8A55B5803693.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_gadgetBuilder_Outer(_ scope: Outer.SafeDIScope_Gadget) -> any Gadget {
			                switch scope {
			                case let .inner_serviceBuilder(_, _, scope): return __safeDI_gadgetBuilder_Outer_DefaultService_Scope(scope, id: nil)
			                }
			            }
			            @Sendable func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(_ scope: Outer.SafeDIScope_Gadget.DefaultService_Scope, id: Int?) -> any Gadget {
			                switch scope {
			                case .gadget:
			                    let gadget: any Gadget = LiveGadget(id: id)
			                    return gadget
			                }
			            }
			            @Sendable func __safeDI_gadgetSendableBuilder_Outer(_ scope: Outer.SafeDISendableScope_Gadget) -> any Gadget {
			                switch scope {
			                case let .inner_serviceSendableBuilder(innerScope, scope): return __safeDI_gadgetBuilder_Outer_DefaultService_Scope(scope, id: __safeDI_id_Inner_SafeDISendableScope_Service(innerScope))
			                }
			            }
			            @Sendable func __safeDI_id_Inner_SafeDISendableScope_Service(_ scope: Inner.SafeDISendableScope_Service) -> Int {
			                switch scope {
			                case let .screenBuilder(scope): return __safeDI_id_Inner_Screen_Scope(scope)
			                }
			            }
			            @Sendable func __safeDI_id_Inner_Screen_Scope(_ scope: Inner.SafeDIScope_Service.Screen_Scope) -> Int {
			                switch scope {
			                case let .service(values): return values.id
			                }
			            }
			            return Outer(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Outer, __safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_Outer)
			        }
			        let outer: Outer = __safeDI_outer()
			        self.init(outer: outer)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsPlaceTheValueTheFunctionWasPassed_whenPlaceInsideFillIsBeneathCycleThatTakesCycleParameter() async throws {
		// The graph fuzzer's seed 605 inside a fill, by the ruling that a place built inside a function that takes cycle
		// parameters carries that function's values, never the caller's. `DefaultService` builds `T` and `C`, each of which
		// builds the other; `T`'s `reader` receives `mark`, so the function that builds `DefaultService`'s `T` takes it,
		// while the `T` that its `C` builds reads `C`'s. `T_Scope`'s level carries `mark` bound from the parameter where the
		// function takes it, and from `C`'s where it does not.
		try await expectPlaceInsideFill(
			feature: [
				"public protocol Service {}\npublic protocol Api {}",
				seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated public let service: any Service"]),
			],
			middle: [
				seamFixtureType(named: "Mark", declarations: []),
				seamFixtureType(named: "MarkReader", declarations: ["@Received(onlyIfAvailable: true) public let mark: Mark?"]),
				seamFixtureType(named: "T", declarations: ["@Instantiated public let reader: MarkReader", "@Instantiated public let cBuilder: Instantiator<C>", "@Instantiated public let api: any Api"]),
				seamFixtureType(named: "C", declarations: ["@Instantiated public let mark: Mark", "@Instantiated public let tBuilder: Instantiator<T>"]),
				Self.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let tBuilder: Instantiator<T>", "@Instantiated public let cBuilder: Instantiator<C>"]),
				seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated public let inner: Inner"]),
			],
			app: [
				Self.fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: ["@Received(onlyIfAvailable: true) public let mark: Mark?"]),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let outer: Outer"]),
			],
			probes: [DifferentialValueProbe(
				name: "T's api at each build",
				expression: """
				{ () -> [String] in
				    let service = Root().outer.inner.service as! DefaultService
				    let t = service.tBuilder.instantiate()
				    return [t.api, t.cBuilder.instantiate().tBuilder.instantiate().api, service.cBuilder.instantiate().tBuilder.instantiate().api].map { "\\($0)" }
				}()
				""",
			)],
			expectedMiddle: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Outer {
			    @frozen public enum SafeDIScope_Api {
			        case inner_serviceBuilder(inner_serviceBuilder_Values, Inner.SafeDIScope_Service, SafeDIScope_Api.DefaultService_Scope)

			        public struct inner_serviceBuilder_Values {
			            public var mark: Mark? { __safeDI_mark.instance }
			            let __safeDI_mark: LazilyInstantiated<Mark?>

			            init(mark: LazilyInstantiated<Mark?>) {
			                __safeDI_mark = mark
			            }
			        }

			        @frozen public enum DefaultService_Scope {
			            case tBuilder(tBuilder_Values, SafeDIScope_Api.T_Scope)
			            case cBuilder(cBuilder_Values, SafeDIScope_Api.C_Scope)

			            public struct tBuilder_Values {}

			            public struct cBuilder_Values {
			                public let tBuilder: Instantiator<T>
			            }
			        }

			        @frozen public enum T_Scope {
			            indirect case cBuilder(cBuilder_Values, SafeDIScope_Api.C_Scope)
			            case api(api_Values)

			            public struct cBuilder_Values {
			                public let mark: Mark?
			                public let reader: MarkReader
			            }

			            public struct api_Values {
			                public let mark: Mark?
			                public let reader: MarkReader
			                public let cBuilder: Instantiator<C>
			            }
			        }

			        @frozen public enum C_Scope {
			            indirect case tBuilder(tBuilder_Values, SafeDIScope_Api.T_Scope)

			            public struct tBuilder_Values {
			                public let mark: Mark
			            }
			        }
			    }

			    // SafeDI counts `Api` as `public`: no module it reads declares it narrower. If `Api` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_mark __safeDI_mark_: @autoclosure @escaping () -> Mark?, __safeDI_apiBuilder: @escaping (SafeDIScope_Api) -> any Api) {
			        let mark = LazilyInstantiated<Mark?>(__safeDI_mark_)
			        let __safeDI_apiValues_inner_serviceBuilder = SafeDIScope_Api.inner_serviceBuilder_Values(mark: mark)
			        func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_9615B48675B70733.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_serviceBuilder_Inner(_ __safeDI_inner_serviceBuilder: Inner.SafeDIScope_Service) -> any Service {
			                switch __safeDI_inner_serviceBuilder {
			                case .service:
			                    func __safeDI_service() -> DefaultService {
			                        let __safeDI_apiValues_tBuilder = SafeDIScope_Api.DefaultService_Scope.tBuilder_Values()
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
			                            let api: any Api = __safeDI_apiBuilder(.inner_serviceBuilder(__safeDI_apiValues_inner_serviceBuilder, __safeDI_inner_serviceBuilder, .tBuilder(__safeDI_apiValues_tBuilder, .api(SafeDIScope_Api.T_Scope.api_Values(mark: mark, reader: reader, cBuilder: cBuilder)))))
			                            return T(reader: reader, cBuilder: cBuilder, api: api)
			                        }
			                        let tBuilder = Instantiator<T> {
			                            __safeDI_tBuilder(mark: mark.instance)
			                        }
			                        let __safeDI_apiValues_cBuilder = SafeDIScope_Api.DefaultService_Scope.cBuilder_Values(tBuilder: tBuilder)
			                        func __safeDI_cBuilder() -> C {
			                            let mark = Mark()
			                            let __safeDI_apiValues_tBuilder = SafeDIScope_Api.C_Scope.tBuilder_Values(mark: mark)
			                            func __safeDI_tBuilder() -> T {
			                                let reader = MarkReader(mark: mark)
			                                let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			                                let api: any Api = __safeDI_apiBuilder(.inner_serviceBuilder(__safeDI_apiValues_inner_serviceBuilder, __safeDI_inner_serviceBuilder, .cBuilder(__safeDI_apiValues_cBuilder, .tBuilder(__safeDI_apiValues_tBuilder, .api(SafeDIScope_Api.T_Scope.api_Values(mark: mark, reader: reader, cBuilder: cBuilder))))))
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
			            }
			            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner)
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(inner: inner)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_A13A32A43D23D20E {}
			}
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			extension Root {
			    public init() {
			        func __safeDI_outer() -> Outer {
			            _ = Outer.__safeDI_Outer_A13A32A43D23D20E.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_apiBuilder_Outer(_ scope: Outer.SafeDIScope_Api) -> any Api {
			                switch scope {
			                case let .inner_serviceBuilder(_, _, scope): return __safeDI_apiBuilder_Outer_DefaultService_Scope(scope)
			                }
			            }
			            func __safeDI_apiBuilder_Outer_DefaultService_Scope(_ scope: Outer.SafeDIScope_Api.DefaultService_Scope) -> any Api {
			                switch scope {
			                case let .tBuilder(_, scope): return __safeDI_apiBuilder_Outer_T_Scope(scope)
			                case let .cBuilder(_, scope): return __safeDI_apiBuilder_Outer_C_Scope(scope)
			                }
			            }
			            func __safeDI_apiBuilder_Outer_T_Scope(_ scope: Outer.SafeDIScope_Api.T_Scope) -> any Api {
			                switch scope {
			                case let .cBuilder(_, scope): return __safeDI_apiBuilder_Outer_C_Scope(scope)
			                case let .api(scope):
			                    let mark = scope.mark
			                    let api: any Api = LiveApi(mark: mark)
			                    return api
			                }
			            }
			            func __safeDI_apiBuilder_Outer_C_Scope(_ scope: Outer.SafeDIScope_Api.C_Scope) -> any Api {
			                switch scope {
			                case let .tBuilder(_, scope): return __safeDI_apiBuilder_Outer_T_Scope(scope)
			                }
			            }
			            return Outer(__safeDI_mark: nil, __safeDI_apiBuilder: __safeDI_apiBuilder_Outer)
			        }
			        let outer: Outer = __safeDI_outer()
			        self.init(outer: outer)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesCallsCaseAndInnerScopeApart_whenPlaceAndBuilderFunctionHaveTheirName() async throws {
		// `Outer`'s place `inner_serviceBuilder` keeps its label, so the case of `inner` for `serviceBuilder` takes `_`, as
		// does the payload binding named after it; `DefaultService`'s builder function of its own `inner_serviceBuilder`
		// would hide the inner scope's parameter inside the fill, so that takes `_` too.
		try await expectPlaceInsideFill(
			feature: Self.inner(screen: ["@Forwarded public let id: Int"]),
			middle: [
				seamFixtureType(named: "Widget", declarations: []),
				Self.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let inner_serviceBuilder: Instantiator<Widget>", "@Instantiated public let gadget: any Gadget"]),
				seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated public let inner: Inner", "@Instantiated public let inner_serviceBuilder: any Gadget"]),
			],
			app: [
				Self.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received(onlyIfAvailable: true) public let id: Int?"]),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let outer: Outer"]),
			],
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().outer.inner.screenBuilder.instantiate(2)")],
			expectedMiddle: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Outer {
			    @frozen public enum SafeDIScope_Gadget {
			        case inner_serviceBuilder_(inner_serviceBuilder__Values, Inner.SafeDIScope_Service, SafeDIScope_Gadget.DefaultService_Scope)
			        case inner_serviceBuilder(inner_serviceBuilder_Values)

			        public struct inner_serviceBuilder__Values {}

			        public struct inner_serviceBuilder_Values {
			            public let inner: Inner
			        }

			        @frozen public enum DefaultService_Scope {
			            case gadget(gadget_Values)

			            public struct gadget_Values {
			                public let inner_serviceBuilder: Instantiator<Widget>
			            }
			        }
			    }

			    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_gadgetBuilder: @escaping (SafeDIScope_Gadget) -> any Gadget) {
			        let __safeDI_gadgetValues_inner_serviceBuilder_ = SafeDIScope_Gadget.inner_serviceBuilder__Values()
			        func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_771FB74B7F0FC507.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_serviceBuilder_Inner(_ __safeDI_inner_serviceBuilder_: Inner.SafeDIScope_Service) -> any Service {
			                switch __safeDI_inner_serviceBuilder_ {
			                case let .screenBuilder(_, scope): return __safeDI_serviceBuilder_Inner_Screen_Scope(scope, __safeDI_inner_serviceBuilder_: __safeDI_inner_serviceBuilder_)
			                case .service:
			                    func __safeDI_service() -> DefaultService {
			                        func __safeDI_inner_serviceBuilder() -> Widget {
			                            Widget()
			                        }
			                        let inner_serviceBuilder = Instantiator<Widget>(__safeDI_inner_serviceBuilder)
			                        let gadget: any Gadget = __safeDI_gadgetBuilder(.inner_serviceBuilder_(__safeDI_gadgetValues_inner_serviceBuilder_, __safeDI_inner_serviceBuilder_, .gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values(inner_serviceBuilder: inner_serviceBuilder))))
			                        return DefaultService(inner_serviceBuilder: inner_serviceBuilder, gadget: gadget)
			                    }
			                    let service: any Service = __safeDI_service()
			                    return service
			                }
			            }
			            func __safeDI_serviceBuilder_Inner_Screen_Scope(_ scope: Inner.SafeDIScope_Service.Screen_Scope, __safeDI_inner_serviceBuilder_: Inner.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case .service:
			                    func __safeDI_service() -> DefaultService {
			                        func __safeDI_inner_serviceBuilder() -> Widget {
			                            Widget()
			                        }
			                        let inner_serviceBuilder = Instantiator<Widget>(__safeDI_inner_serviceBuilder)
			                        let gadget: any Gadget = __safeDI_gadgetBuilder(.inner_serviceBuilder_(__safeDI_gadgetValues_inner_serviceBuilder_, __safeDI_inner_serviceBuilder_, .gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values(inner_serviceBuilder: inner_serviceBuilder))))
			                        return DefaultService(inner_serviceBuilder: inner_serviceBuilder, gadget: gadget)
			                    }
			                    let service: any Service = __safeDI_service()
			                    return service
			                }
			            }
			            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner)
			        }
			        let inner: Inner = __safeDI_inner()
			        let inner_serviceBuilder: any Gadget = __safeDI_gadgetBuilder(.inner_serviceBuilder(SafeDIScope_Gadget.inner_serviceBuilder_Values(inner: inner)))
			        self.init(inner: inner, inner_serviceBuilder: inner_serviceBuilder)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_AAA41DD84632EACD {}
			}
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			extension Root {
			    public init() {
			        func __safeDI_outer() -> Outer {
			            _ = Outer.__safeDI_Outer_AAA41DD84632EACD.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_gadgetBuilder_Outer(_ scope: Outer.SafeDIScope_Gadget) -> any Gadget {
			                switch scope {
			                case let .inner_serviceBuilder_(_, innerScope, scope): return __safeDI_gadgetBuilder_Outer_DefaultService_Scope(scope, id: __safeDI_id_Inner_SafeDIScope_Service(innerScope))
			                case .inner_serviceBuilder:
			                    let inner_serviceBuilder: any Gadget = LiveGadget(id: nil)
			                    return inner_serviceBuilder
			                }
			            }
			            func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(_ scope: Outer.SafeDIScope_Gadget.DefaultService_Scope, id: Int?) -> any Gadget {
			                switch scope {
			                case .gadget:
			                    let gadget: any Gadget = LiveGadget(id: id)
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
			""",
		)
	}

	// MARK: One case of the inner seam's for several places

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsValueThroughReaderOnRouteThatHoldsIt_whenFirstPlaceOfInnersCaseHoldsNone() async throws {
		// `Inner` builds `Panel` at its root, then in the `Screen` its `screenBuilder` builds, which forwards `id`: one case of
		// `Inner`'s, `Panel_Scope.service`, stands for both places, and `Outer` fills it once. The place inside that fill reads
		// `id` through `Inner`'s scope, which only the `screenBuilder` route holds, though the case's first place, at `Inner`'s
		// root, holds none: `App` passes `nil` on the other route, as inline.
		try await expectPlaceInsideFill(
			feature: Self.panelInner(rootDeclarations: ["@Instantiated public let panel: Panel", "@Instantiated public let screenBuilder: Instantiator<Screen>"]),
			middle: Self.panelMiddle,
			app: [
				Self.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received(onlyIfAvailable: true) public let id: Int?"]),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let outer: Outer"]),
			],
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().outer.inner.screenBuilder.instantiate(7)")],
			expectedMiddle: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Outer {
			    @frozen public enum SafeDIScope_Gadget {
			        case inner_serviceBuilder(inner_serviceBuilder_Values, Inner.SafeDIScope_Service, SafeDIScope_Gadget.DefaultService_Scope)

			        public struct inner_serviceBuilder_Values {}

			        @frozen public enum DefaultService_Scope {
			            case gadget(gadget_Values)

			            public struct gadget_Values {}
			        }
			    }

			    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_gadgetBuilder: @escaping (SafeDIScope_Gadget) -> any Gadget) {
			        let __safeDI_gadgetValues_inner_serviceBuilder = SafeDIScope_Gadget.inner_serviceBuilder_Values()
			        func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_F28A6DFAF3F34332.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_serviceBuilder_Inner(_ __safeDI_inner_serviceBuilder: Inner.SafeDIScope_Service) -> any Service {
			                switch __safeDI_inner_serviceBuilder {
			                case let .panel(_, scope): return __safeDI_serviceBuilder_Inner_Panel_Scope(scope, __safeDI_inner_serviceBuilder: __safeDI_inner_serviceBuilder)
			                case let .screenBuilder(_, scope): return __safeDI_serviceBuilder_Inner_Screen_Scope(scope, __safeDI_inner_serviceBuilder: __safeDI_inner_serviceBuilder)
			                }
			            }
			            func __safeDI_serviceBuilder_Inner_Panel_Scope(_ scope: Inner.SafeDIScope_Service.Panel_Scope, __safeDI_inner_serviceBuilder: Inner.SafeDIScope_Service) -> any Service {
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
			            func __safeDI_serviceBuilder_Inner_Screen_Scope(_ scope: Inner.SafeDIScope_Service.Screen_Scope, __safeDI_inner_serviceBuilder: Inner.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case let .panel(_, scope): return __safeDI_serviceBuilder_Inner_Panel_Scope(scope, __safeDI_inner_serviceBuilder: __safeDI_inner_serviceBuilder)
			                }
			            }
			            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner)
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(inner: inner)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_55E4D7C14C382E8E {}
			}
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			extension Root {
			    public init() {
			        func __safeDI_outer() -> Outer {
			            _ = Outer.__safeDI_Outer_55E4D7C14C382E8E.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_gadgetBuilder_Outer(_ scope: Outer.SafeDIScope_Gadget) -> any Gadget {
			                switch scope {
			                case let .inner_serviceBuilder(_, innerScope, scope): return __safeDI_gadgetBuilder_Outer_DefaultService_Scope(scope, id: __safeDI_id_Inner_SafeDIScope_Service(innerScope))
			                }
			            }
			            func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(_ scope: Outer.SafeDIScope_Gadget.DefaultService_Scope, id: Int?) -> any Gadget {
			                switch scope {
			                case .gadget:
			                    let gadget: any Gadget = LiveGadget(id: id)
			                    return gadget
			                }
			            }
			            func __safeDI_id_Inner_SafeDIScope_Service(_ scope: Inner.SafeDIScope_Service) -> Int? {
			                switch scope {
			                case .panel: return nil
			                case let .screenBuilder(_, scope): return __safeDI_id_Inner_Screen_Scope(scope)
			                }
			            }
			            func __safeDI_id_Inner_Screen_Scope(_ scope: Inner.SafeDIScope_Service.Screen_Scope) -> Int {
			                switch scope {
			                case let .panel(values, _): return values.id
			                }
			            }
			            return Outer(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Outer)
			        }
			        let outer: Outer = __safeDI_outer()
			        self.init(outer: outer)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsCallersDeclarationOnRouteThatHoldsNone_whenFirstPlaceOfInnersCaseHoldsTheValue() async throws {
		// As above, with `screenBuilder` declared first, so the case's first place is the one beneath `Screen`, which forwards
		// `session`. `LiveGadget` requires `session`: the reader finds `Screen`'s on that route, and `App` passes `Root`'s own
		// on the route at `Inner`'s root, as inline.
		try await expectPlaceInsideFill(
			feature: Self.panelInner(
				screenDeclarations: ["@Forwarded public let session: Session"],
				rootDeclarations: ["@Instantiated public let screenBuilder: Instantiator<Screen>", "@Instantiated public let panel: Panel"],
			),
			middle: Self.panelMiddle,
			app: [
				Self.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received public let session: Session"]),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let session: Session", "@Instantiated public let outer: Outer"]),
			],
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().outer.inner.screenBuilder.instantiate(Session())")],
			expectedMiddle: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Outer {
			    @frozen public enum SafeDIScope_Gadget {
			        case inner_serviceBuilder(inner_serviceBuilder_Values, Inner.SafeDIScope_Service, SafeDIScope_Gadget.DefaultService_Scope)

			        public struct inner_serviceBuilder_Values {}

			        @frozen public enum DefaultService_Scope {
			            case gadget(gadget_Values)

			            public struct gadget_Values {}
			        }
			    }

			    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_gadgetBuilder: @escaping (SafeDIScope_Gadget) -> any Gadget) {
			        let __safeDI_gadgetValues_inner_serviceBuilder = SafeDIScope_Gadget.inner_serviceBuilder_Values()
			        func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_01F389B0473D8201.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_serviceBuilder_Inner(_ __safeDI_inner_serviceBuilder: Inner.SafeDIScope_Service) -> any Service {
			                switch __safeDI_inner_serviceBuilder {
			                case let .screenBuilder(_, scope): return __safeDI_serviceBuilder_Inner_Screen_Scope(scope, __safeDI_inner_serviceBuilder: __safeDI_inner_serviceBuilder)
			                case let .panel(_, scope): return __safeDI_serviceBuilder_Inner_Panel_Scope(scope, __safeDI_inner_serviceBuilder: __safeDI_inner_serviceBuilder)
			                }
			            }
			            func __safeDI_serviceBuilder_Inner_Screen_Scope(_ scope: Inner.SafeDIScope_Service.Screen_Scope, __safeDI_inner_serviceBuilder: Inner.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case let .panel(_, scope): return __safeDI_serviceBuilder_Inner_Panel_Scope(scope, __safeDI_inner_serviceBuilder: __safeDI_inner_serviceBuilder)
			                }
			            }
			            func __safeDI_serviceBuilder_Inner_Panel_Scope(_ scope: Inner.SafeDIScope_Service.Panel_Scope, __safeDI_inner_serviceBuilder: Inner.SafeDIScope_Service) -> any Service {
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
			            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner)
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(inner: inner)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_5196B51D142D52E9 {}
			}
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			extension Root {
			    public init() {
			        let session = Session()
			        func __safeDI_outer() -> Outer {
			            _ = Outer.__safeDI_Outer_5196B51D142D52E9.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_gadgetBuilder_Outer(_ scope: Outer.SafeDIScope_Gadget) -> any Gadget {
			                switch scope {
			                case let .inner_serviceBuilder(_, innerScope, scope): return __safeDI_gadgetBuilder_Outer_DefaultService_Scope(scope, session: __safeDI_session_Inner_SafeDIScope_Service(innerScope) ?? session)
			                }
			            }
			            func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(_ scope: Outer.SafeDIScope_Gadget.DefaultService_Scope, session: Session) -> any Gadget {
			                switch scope {
			                case .gadget:
			                    let gadget: any Gadget = LiveGadget(session: session)
			                    return gadget
			                }
			            }
			            func __safeDI_session_Inner_SafeDIScope_Service(_ scope: Inner.SafeDIScope_Service) -> Session? {
			                switch scope {
			                case let .screenBuilder(_, scope): return __safeDI_session_Inner_Screen_Scope(scope)
			                case .panel: return nil
			                }
			            }
			            func __safeDI_session_Inner_Screen_Scope(_ scope: Inner.SafeDIScope_Service.Screen_Scope) -> Session {
			                switch scope {
			                case let .panel(values, _): return values.session
			                }
			            }
			            return Outer(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Outer)
			        }
			        let outer: Outer = __safeDI_outer()
			        self.init(session: session, outer: outer)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsValueThroughEveryInnerSeamsReader_whenPlaceIsInsideFillOfPlaceInsideFillOfCaseOfTwoPlaces() async throws {
		// `Top`, in `Upper`, fills `Outer`'s `gadget` with `DefaultGadget`, whose `gizmo` only `App` can build. `Outer`'s case
		// for `gadget` stands for the places inside both of `Inner`'s routes, only one of which holds `id`: `App` reads it
		// through `Outer`'s scope, then `Inner`'s, and passes `nil` on the other route, as inline.
		let feature = Self.inner(screen: ["@Forwarded public let id: Int"]) + ["public protocol Gizmo {}"]
		let middle = [
			Self.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let gadget: any Gadget"]),
			seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated public let inner: Inner"]),
		]
		let upper = [
			Self.fulfillingType(named: "DefaultGadget", fulfilling: "Gadget", declarations: ["@Instantiated public let gizmo: any Gizmo"]),
			seamFixtureType(named: "Top", isSeam: true, declarations: ["@Instantiated public let outer: Outer"]),
		]
		let app = [
			Self.fulfillingType(named: "LiveGizmo", fulfilling: "Gizmo", declarations: ["@Received(onlyIfAvailable: true) public let id: Int?"]),
			seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let top: Top"]),
		]
		func modules(feature: [String], middle: [String], upper: [String], app: [String]) -> [ModuleFixture] {
			[
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature),
				ModuleFixture(name: "Middle", packageName: "Other", swiftFileContent: middle.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
				ModuleFixture(name: "Upper", packageName: "Other", swiftFileContent: upper.map { "import Feature\nimport Middle\n\n" + $0 }, dependencies: ["Feature", "Middle"]),
				ModuleFixture(name: "App", packageName: "Other", swiftFileContent: app.map { "import Feature\nimport Middle\nimport Upper\n\n" + $0 }, dependencies: ["Feature", "Middle", "Upper"]),
			]
		}
		let seamModules = modules(feature: feature, middle: middle, upper: upper, app: app)
		let output = try await executeSafeDIToolMultiModuleTest(modules: seamModules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		for (module, expected) in [("Upper", """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Middle)
		import Middle
		#endif

		extension Top {
		    @frozen public enum SafeDIScope_Gizmo {
		        case outer_gadgetBuilder(outer_gadgetBuilder_Values, Outer.SafeDIScope_Gadget, SafeDIScope_Gizmo.DefaultGadget_Scope)

		        public struct outer_gadgetBuilder_Values {}

		        @frozen public enum DefaultGadget_Scope {
		            case gizmo(gizmo_Values)

		            public struct gizmo_Values {}
		        }
		    }

		    // SafeDI counts `Gizmo` as `public`: no module it reads declares it narrower. If `Gizmo` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_gizmoBuilder: @escaping (SafeDIScope_Gizmo) -> any Gizmo) {
		        let __safeDI_gizmoValues_outer_gadgetBuilder = SafeDIScope_Gizmo.outer_gadgetBuilder_Values()
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_5CA049A6FBBAD743.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_gadgetBuilder_Outer(_ __safeDI_outer_gadgetBuilder: Outer.SafeDIScope_Gadget) -> any Gadget {
		                switch __safeDI_outer_gadgetBuilder {
		                case let .inner_serviceBuilder(_, _, scope): return __safeDI_gadgetBuilder_Outer_DefaultService_Scope(scope, __safeDI_outer_gadgetBuilder: __safeDI_outer_gadgetBuilder)
		                }
		            }
		            func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(_ scope: Outer.SafeDIScope_Gadget.DefaultService_Scope, __safeDI_outer_gadgetBuilder: Outer.SafeDIScope_Gadget) -> any Gadget {
		                switch scope {
		                case .gadget:
		                    func __safeDI_gadget() -> DefaultGadget {
		                        let gizmo: any Gizmo = __safeDI_gizmoBuilder(.outer_gadgetBuilder(__safeDI_gizmoValues_outer_gadgetBuilder, __safeDI_outer_gadgetBuilder, .gizmo(SafeDIScope_Gizmo.DefaultGadget_Scope.gizmo_Values())))
		                        return DefaultGadget(gizmo: gizmo)
		                    }
		                    let gadget: any Gadget = __safeDI_gadget()
		                    return gadget
		                }
		            }
		            return Outer(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Outer)
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(outer: outer)
		    }
		}

		extension Top {
		    public enum __safeDI_Top_B68CEC7CBE0B32E2 {}
		}
		"""), ("App", """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Middle)
		import Middle
		#endif
		#if canImport(Upper)
		import Upper
		#endif

		extension Root {
		    public init() {
		        func __safeDI_top() -> Top {
		            _ = Top.__safeDI_Top_B68CEC7CBE0B32E2.self // If this line does not compile, compile the code SafeDI generates for module Upper into Upper: under Bazel, add Upper’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_gizmoBuilder_Top(_ scope: Top.SafeDIScope_Gizmo) -> any Gizmo {
		                switch scope {
		                case let .outer_gadgetBuilder(_, innerScope, scope): return __safeDI_gizmoBuilder_Top_DefaultGadget_Scope(scope, id: __safeDI_id_Outer_SafeDIScope_Gadget(innerScope))
		                }
		            }
		            func __safeDI_gizmoBuilder_Top_DefaultGadget_Scope(_ scope: Top.SafeDIScope_Gizmo.DefaultGadget_Scope, id: Int?) -> any Gizmo {
		                switch scope {
		                case .gizmo:
		                    let gizmo: any Gizmo = LiveGizmo(id: id)
		                    return gizmo
		                }
		            }
		            func __safeDI_id_Outer_SafeDIScope_Gadget(_ scope: Outer.SafeDIScope_Gadget) -> Int? {
		                switch scope {
		                case let .inner_serviceBuilder(_, innerScope, _): return __safeDI_id_Inner_SafeDIScope_Service(innerScope)
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
		            return Top(__safeDI_gizmoBuilder: __safeDI_gizmoBuilder_Top)
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}
		""")] {
			let generated = output.modules[module]?.generatedFiles["\(module).swift"]
			#expect(generated == generatedFileHeader + expected)
			if let generated, generated != generatedFileHeader + expected {
				Issue.record(Comment(rawValue: "=== \(module).swift\n" + generated.dropFirst(generatedFileHeader.count)))
			}
		}
		guard compileVerificationIsEnabled else { return }
		let inlineModules = modules(feature: inlineFixture(feature), middle: inlineFixture(middle), upper: inlineFixture(upper), app: inlineFixture(app))
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inlineModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		try await expectDifferentialValuesAgree(
			feature: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: output, modules: seamModules),
			knownRight: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: inlineOutput, modules: inlineModules),
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().top.outer.inner.screenBuilder.instantiate(7)")],
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsNoPayloadOfCallsCase_whenReaderFindsValueOnEveryRouteOfInners() async throws {
		// `Outer`, `Inner` and `Screen` each forward `id`, so every route of `Inner`'s holds one, nearer than `Outer`'s: the
		// case for `innerBuilder` hands the reader's value on and binds no payload of its own.
		try await expectPlaceInsideFill(
			feature: [
				"public protocol Service {}\npublic protocol Gadget {}",
				seamFixtureType(named: "Screen", declarations: ["@Forwarded public let id: Int", "@Instantiated public let service: any Service"]),
				seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Forwarded public let id: Int", "@Instantiated public let screenBuilder: Instantiator<Screen>", "@Instantiated public let service: any Service"]),
			],
			middle: [
				Self.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let gadget: any Gadget"]),
				seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Forwarded public let id: Int", "@Instantiated public let innerBuilder: Instantiator<Inner>"]),
			],
			app: [
				Self.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received public let id: Int"]),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let outerBuilder: Instantiator<Outer>"]),
			],
			probes: [
				DifferentialValueProbe("Root().outerBuilder.instantiate(1).innerBuilder.instantiate(2)"),
				DifferentialValueProbe("Root().outerBuilder.instantiate(1).innerBuilder.instantiate(2).screenBuilder.instantiate(3)"),
			],
			expectedMiddle: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Outer {
			    @frozen public enum SafeDIScope_Gadget {
			        case innerBuilder_serviceBuilder(innerBuilder_serviceBuilder_Values, Inner.SafeDIScope_Service, SafeDIScope_Gadget.DefaultService_Scope)

			        public struct innerBuilder_serviceBuilder_Values {
			            public let id: Int
			        }

			        @frozen public enum DefaultService_Scope {
			            case gadget(gadget_Values)

			            public struct gadget_Values {}
			        }
			    }

			    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_id id: Int, __safeDI_gadgetBuilder: @escaping (SafeDIScope_Gadget) -> any Gadget) {
			        let __safeDI_gadgetValues_innerBuilder_serviceBuilder = SafeDIScope_Gadget.innerBuilder_serviceBuilder_Values(id: id)
			        func __safeDI_innerBuilder(id: Int) -> Inner {
			            _ = Inner.__safeDI_Inner_16160F1C1D563048.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_serviceBuilder_Inner(_ __safeDI_innerBuilder_serviceBuilder: Inner.SafeDIScope_Service) -> any Service {
			                switch __safeDI_innerBuilder_serviceBuilder {
			                case let .screenBuilder(_, scope): return __safeDI_serviceBuilder_Inner_Screen_Scope(scope, __safeDI_innerBuilder_serviceBuilder: __safeDI_innerBuilder_serviceBuilder)
			                case .service:
			                    func __safeDI_service() -> DefaultService {
			                        let gadget: any Gadget = __safeDI_gadgetBuilder(.innerBuilder_serviceBuilder(__safeDI_gadgetValues_innerBuilder_serviceBuilder, __safeDI_innerBuilder_serviceBuilder, .gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values())))
			                        return DefaultService(gadget: gadget)
			                    }
			                    let service: any Service = __safeDI_service()
			                    return service
			                }
			            }
			            func __safeDI_serviceBuilder_Inner_Screen_Scope(_ scope: Inner.SafeDIScope_Service.Screen_Scope, __safeDI_innerBuilder_serviceBuilder: Inner.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case .service:
			                    func __safeDI_service() -> DefaultService {
			                        let gadget: any Gadget = __safeDI_gadgetBuilder(.innerBuilder_serviceBuilder(__safeDI_gadgetValues_innerBuilder_serviceBuilder, __safeDI_innerBuilder_serviceBuilder, .gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values())))
			                        return DefaultService(gadget: gadget)
			                    }
			                    let service: any Service = __safeDI_service()
			                    return service
			                }
			            }
			            return Inner(__safeDI_id: id, __safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner)
			        }
			        let innerBuilder = Instantiator<Inner> {
			            __safeDI_innerBuilder(id: $0)
			        }
			        self.init(id: id, innerBuilder: innerBuilder)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_1B5D3F18BFE8ED9D {}
			}
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			extension Root {
			    public init() {
			        func __safeDI_outerBuilder(id: Int) -> Outer {
			            _ = Outer.__safeDI_Outer_1B5D3F18BFE8ED9D.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_gadgetBuilder_Outer(_ scope: Outer.SafeDIScope_Gadget) -> any Gadget {
			                switch scope {
			                case let .innerBuilder_serviceBuilder(_, innerScope, scope): return __safeDI_gadgetBuilder_Outer_DefaultService_Scope(scope, id: __safeDI_id_Inner_SafeDIScope_Service(innerScope))
			                }
			            }
			            func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(_ scope: Outer.SafeDIScope_Gadget.DefaultService_Scope, id: Int) -> any Gadget {
			                switch scope {
			                case .gadget:
			                    let gadget: any Gadget = LiveGadget(id: id)
			                    return gadget
			                }
			            }
			            func __safeDI_id_Inner_SafeDIScope_Service(_ scope: Inner.SafeDIScope_Service) -> Int {
			                switch scope {
			                case let .screenBuilder(_, scope): return __safeDI_id_Inner_Screen_Scope(scope)
			                case let .service(values): return values.id
			                }
			            }
			            func __safeDI_id_Inner_Screen_Scope(_ scope: Inner.SafeDIScope_Service.Screen_Scope) -> Int {
			                switch scope {
			                case let .service(values): return values.id
			                }
			            }
			            return Outer(__safeDI_id: id, __safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Outer)
			        }
			        let outerBuilder = Instantiator<Outer> {
			            __safeDI_outerBuilder(id: $0)
			        }
			        self.init(outerBuilder: outerBuilder)
			    }
			}
			""",
		)
	}

	// MARK: Places a seam the called seam calls passes up

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesCallsCaseAfterSeamThatHoldsPlace_whenCalledSeamPassesUpPlacesOfTwoSeams() async throws {
		// `Inner` builds `service` itself and calls `DeepB` and `DeepA`, which each hold one it passes up. The fill of each holds
		// the scope value of the seam whose tree holds its place – the value every call of that seam hands a fill passed for it
		// – so `Outer` has a case for each seam, named after it: adding a call to `Inner` renames none.
		try await expectPlaceInsideFill(
			feature: [
				"public protocol Service {}\npublic protocol Gadget {}",
				seamFixtureType(named: "Screen", declarations: ["@Forwarded public let id: Int", "@Instantiated public let service: any Service"]),
				seamFixtureType(named: "DeepB", isSeam: true, declarations: ["@Instantiated public let screenBuilder: Instantiator<Screen>"]),
				seamFixtureType(named: "DeepA", isSeam: true, declarations: ["@Instantiated public let service: any Service"]),
				seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated public let deepB: DeepB", "@Instantiated public let service: any Service", "@Instantiated public let deepA: DeepA"]),
			],
			middle: Self.panelMiddle,
			app: [
				Self.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received(onlyIfAvailable: true) public let id: Int?"]),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let outer: Outer"]),
			],
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().outer.inner.deepB.screenBuilder.instantiate(7)")],
			expectedMiddle: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Outer {
			    @frozen public enum SafeDIScope_Gadget {
			        case inner_serviceBuilder(inner_serviceBuilder_Values, Inner.SafeDIScope_Service, SafeDIScope_Gadget.DefaultService_Scope)
			        case inner_serviceBuilder_DeepB(inner_serviceBuilder_DeepB_Values, DeepB.SafeDIScope_Service, SafeDIScope_Gadget.DefaultService_Scope)
			        case inner_serviceBuilder_DeepA(inner_serviceBuilder_DeepA_Values, DeepA.SafeDIScope_Service, SafeDIScope_Gadget.DefaultService_Scope)

			        public struct inner_serviceBuilder_Values {}

			        public struct inner_serviceBuilder_DeepB_Values {}

			        public struct inner_serviceBuilder_DeepA_Values {}

			        @frozen public enum DefaultService_Scope {
			            case gadget(gadget_Values)

			            public struct gadget_Values {}
			        }
			    }

			    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_gadgetBuilder: @escaping (SafeDIScope_Gadget) -> any Gadget) {
			        let __safeDI_gadgetValues_inner_serviceBuilder = SafeDIScope_Gadget.inner_serviceBuilder_Values()
			        let __safeDI_gadgetValues_inner_serviceBuilder_DeepA = SafeDIScope_Gadget.inner_serviceBuilder_DeepA_Values()
			        let __safeDI_gadgetValues_inner_serviceBuilder_DeepB = SafeDIScope_Gadget.inner_serviceBuilder_DeepB_Values()
			        func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_49AAF66E32A4BA77.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_serviceBuilder_Inner(_ __safeDI_inner_serviceBuilder__: Inner.SafeDIScope_Service) -> any Service {
			                switch __safeDI_inner_serviceBuilder__ {
			                case let .deepB(_, scope): return __safeDI_serviceBuilder_DeepB(scope)
			                case .service:
			                    func __safeDI_service() -> DefaultService {
			                        let gadget: any Gadget = __safeDI_gadgetBuilder(.inner_serviceBuilder(__safeDI_gadgetValues_inner_serviceBuilder, __safeDI_inner_serviceBuilder__, .gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values())))
			                        return DefaultService(gadget: gadget)
			                    }
			                    let service: any Service = __safeDI_service()
			                    return service
			                case let .deepA(_, scope): return __safeDI_serviceBuilder_DeepA(scope)
			                }
			            }
			            func __safeDI_serviceBuilder_DeepB(_ __safeDI_inner_serviceBuilder_: DeepB.SafeDIScope_Service) -> any Service {
			                switch __safeDI_inner_serviceBuilder_ {
			                case let .screenBuilder(_, scope): return __safeDI_serviceBuilder_DeepB_Screen_Scope(scope, __safeDI_inner_serviceBuilder_: __safeDI_inner_serviceBuilder_)
			                }
			            }
			            func __safeDI_serviceBuilder_DeepB_Screen_Scope(_ scope: DeepB.SafeDIScope_Service.Screen_Scope, __safeDI_inner_serviceBuilder_: DeepB.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case .service:
			                    func __safeDI_service() -> DefaultService {
			                        let gadget: any Gadget = __safeDI_gadgetBuilder(.inner_serviceBuilder_DeepB(__safeDI_gadgetValues_inner_serviceBuilder_DeepB, __safeDI_inner_serviceBuilder_, .gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values())))
			                        return DefaultService(gadget: gadget)
			                    }
			                    let service: any Service = __safeDI_service()
			                    return service
			                }
			            }
			            func __safeDI_serviceBuilder_DeepA(_ __safeDI_inner_serviceBuilder: DeepA.SafeDIScope_Service) -> any Service {
			                switch __safeDI_inner_serviceBuilder {
			                case .service:
			                    func __safeDI_service() -> DefaultService {
			                        let gadget: any Gadget = __safeDI_gadgetBuilder(.inner_serviceBuilder_DeepA(__safeDI_gadgetValues_inner_serviceBuilder_DeepA, __safeDI_inner_serviceBuilder, .gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values())))
			                        return DefaultService(gadget: gadget)
			                    }
			                    let service: any Service = __safeDI_service()
			                    return service
			                }
			            }
			            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner)
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(inner: inner)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_44A9EE567889C1AC {}
			}
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			extension Root {
			    public init() {
			        func __safeDI_outer() -> Outer {
			            _ = Outer.__safeDI_Outer_44A9EE567889C1AC.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_gadgetBuilder_Outer(_ scope: Outer.SafeDIScope_Gadget) -> any Gadget {
			                switch scope {
			                case let .inner_serviceBuilder(_, innerScope, scope): return __safeDI_gadgetBuilder_Outer_DefaultService_Scope(scope, id: __safeDI_id_Inner_SafeDIScope_Service(innerScope))
			                case let .inner_serviceBuilder_DeepB(_, innerScope, scope): return __safeDI_gadgetBuilder_Outer_DefaultService_Scope(scope, id: __safeDI_id_DeepB_SafeDIScope_Service(innerScope))
			                case let .inner_serviceBuilder_DeepA(_, _, scope): return __safeDI_gadgetBuilder_Outer_DefaultService_Scope(scope, id: nil)
			                }
			            }
			            func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(_ scope: Outer.SafeDIScope_Gadget.DefaultService_Scope, id: Int?) -> any Gadget {
			                switch scope {
			                case .gadget:
			                    let gadget: any Gadget = LiveGadget(id: id)
			                    return gadget
			                }
			            }
			            func __safeDI_id_Inner_SafeDIScope_Service(_ scope: Inner.SafeDIScope_Service) -> Int? {
			                switch scope {
			                case let .deepB(_, scope): return __safeDI_id_DeepB_SafeDIScope_Service(scope)
			                case .service: return nil
			                case .deepA: return nil
			                }
			            }
			            func __safeDI_id_DeepB_SafeDIScope_Service(_ scope: DeepB.SafeDIScope_Service) -> Int {
			                switch scope {
			                case let .screenBuilder(_, scope): return __safeDI_id_DeepB_Screen_Scope(scope)
			                }
			            }
			            func __safeDI_id_DeepB_Screen_Scope(_ scope: DeepB.SafeDIScope_Service.Screen_Scope) -> Int {
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
			""",
		)
	}

	// MARK: Fills of one builder that differ in whether they carry the inner scope

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesCaseThatCarriesNoInnerScope_whenOneFillOfBuilderBuildsItsTypeInSendableWrapper() async throws {
		// `Inner`'s `makeService` holds a `DefaultService` in a `SendableErasedInstantiator`, whose `@Sendable` function binds
		// nothing the fill was handed, while the one beneath `Screen` is built in plain code inside `Inner`'s `@Sendable`
		// builder. The two fills of `Outer`'s builder take a case each: only the second carries `Inner`'s scope, which a
		// `@Sendable` function could not capture.
		try await expectPlaceInsideFill(
			feature: [
				"public protocol Service: Sendable {}\npublic protocol Gadget: Sendable {}\npublic struct AnyService: Sendable {\n    public init(_ service: some Service) { self.service = service }\n    public let service: any Service\n}",
				seamFixtureType(named: "Screen", declarations: ["@Forwarded public let id: Int", "@Instantiated(fulfilledByType: \"DefaultService\", erasedToConcreteExistential: true) public let service: AnyService"], conformances: ", Sendable"),
				seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated public let screenBuilder: SendableInstantiator<Screen>", "@Instantiated(fulfilledByType: \"DefaultService\", erasedToConcreteExistential: true) public let makeService: SendableErasedInstantiator<(), AnyService>"], conformances: ", Sendable"),
			],
			middle: [
				seamFixtureType(named: "DefaultService", declarations: ["@Instantiated public let gadget: any Gadget"], conformances: ", Service, Sendable"),
				seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated public let inner: Inner"], conformances: ", Sendable"),
			],
			app: [
				Self.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received(onlyIfAvailable: true) public let id: Int?"], conformances: ", Sendable"),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let outer: Outer"]),
			],
			probes: [
				DifferentialValueProbe("Root()"),
				DifferentialValueProbe("Root().outer.inner.screenBuilder.instantiate(7)"),
				DifferentialValueProbe("Root().outer.inner.makeService.instantiate()"),
			],
			expectedMiddle: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Outer {
			    @frozen public enum SafeDIScope_Gadget {
			        @frozen public enum DefaultService_Scope {
			            case gadget(gadget_Values)

			            public struct gadget_Values {}
			        }
			    }

			    @frozen public enum SafeDISendableScope_Gadget {
			        case inner_defaultServiceSendableBuilder(Inner.SafeDISendableScope_DefaultService, SafeDIScope_Gadget.DefaultService_Scope)
			        case inner_defaultServiceSendableBuilder_(SafeDIScope_Gadget.DefaultService_Scope)
			    }

			    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_gadgetSendableBuilder: @escaping @Sendable (SafeDISendableScope_Gadget) -> any Gadget) {
			        func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_A737F22266594EF3.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            @Sendable func __safeDI_defaultServiceSendableBuilder_Inner(_ __safeDI_inner_defaultServiceSendableBuilder: Inner.SafeDISendableScope_DefaultService) -> AnyService {
			                switch __safeDI_inner_defaultServiceSendableBuilder {
			                case let .screenBuilder(scope): return __safeDI_defaultServiceBuilder_Inner_Screen_Scope(scope, __safeDI_inner_defaultServiceSendableBuilder: __safeDI_inner_defaultServiceSendableBuilder)
			                case .makeService:
			                    @Sendable func __safeDI_makeService() -> DefaultService {
			                        let gadget: any Gadget = __safeDI_gadgetSendableBuilder(.inner_defaultServiceSendableBuilder_(.gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values())))
			                        return DefaultService(gadget: gadget)
			                    }
			                    return AnyService(__safeDI_makeService())
			                }
			            }
			            @Sendable func __safeDI_defaultServiceBuilder_Inner_Screen_Scope(_ scope: Inner.SafeDIScope_DefaultService.Screen_Scope, __safeDI_inner_defaultServiceSendableBuilder: Inner.SafeDISendableScope_DefaultService) -> AnyService {
			                switch scope {
			                case .service:
			                    func __safeDI_service() -> DefaultService {
			                        let gadget: any Gadget = __safeDI_gadgetSendableBuilder(.inner_defaultServiceSendableBuilder(__safeDI_inner_defaultServiceSendableBuilder, .gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values())))
			                        return DefaultService(gadget: gadget)
			                    }
			                    let service = AnyService(__safeDI_service())
			                    return service
			                }
			            }
			            return Inner(__safeDI_defaultServiceSendableBuilder: __safeDI_defaultServiceSendableBuilder_Inner)
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(inner: inner)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_F869736AF2F5AAA3 {}
			}
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			extension Root {
			    public init() {
			        func __safeDI_outer() -> Outer {
			            _ = Outer.__safeDI_Outer_F869736AF2F5AAA3.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            @Sendable func __safeDI_gadgetSendableBuilder_Outer(_ scope: Outer.SafeDISendableScope_Gadget) -> any Gadget {
			                switch scope {
			                case let .inner_defaultServiceSendableBuilder(innerScope, scope): return __safeDI_gadgetBuilder_Outer_DefaultService_Scope(scope, id: __safeDI_id_Inner_SafeDISendableScope_DefaultService(innerScope))
			                case let .inner_defaultServiceSendableBuilder_(scope): return __safeDI_gadgetBuilder_Outer_DefaultService_Scope(scope, id: nil)
			                }
			            }
			            @Sendable func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(_ scope: Outer.SafeDIScope_Gadget.DefaultService_Scope, id: Int?) -> any Gadget {
			                switch scope {
			                case .gadget:
			                    let gadget: any Gadget = LiveGadget(id: id)
			                    return gadget
			                }
			            }
			            @Sendable func __safeDI_id_Inner_SafeDISendableScope_DefaultService(_ scope: Inner.SafeDISendableScope_DefaultService) -> Int? {
			                switch scope {
			                case let .screenBuilder(scope): return __safeDI_id_Inner_Screen_Scope(scope)
			                case .makeService: return nil
			                }
			            }
			            @Sendable func __safeDI_id_Inner_Screen_Scope(_ scope: Inner.SafeDIScope_DefaultService.Screen_Scope) -> Int {
			                switch scope {
			                case let .service(values): return values.id
			                }
			            }
			            return Outer(__safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_Outer)
			        }
			        let outer: Outer = __safeDI_outer()
			        self.init(outer: outer)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_skipsForwardedValueInReadersPattern_whenInnersPlaceIsHeldByInstantiatorThatForwardsValue() async throws {
		// `Inner`'s place is `Screen`'s `serviceBuilder`, an erased instantiator that forwards a `String`, so its case carries
		// the forwarded value after its payload. `Outer` fills it with `DefaultService`, whose `gadget` only `App` can build,
		// and `LiveGadget` reads `id`, which `Screen` forwards: the reader over `Inner`'s `Screen_Scope` binds the payload and
		// skips the forwarded value.
		try await expectPlaceInsideFill(
			feature: Self.forwardingInner(rootDeclarations: ["@Instantiated public let screenBuilder: Instantiator<Screen>"]),
			middle: Self.forwardingMiddle,
			app: Self.forwardingApp,
			probes: [
				DifferentialValueProbe("Root()"),
				DifferentialValueProbe(#"Root().outer.inner.screenBuilder.instantiate(4).serviceBuilder.instantiate("n")"#),
			],
			expectedMiddle: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Outer {
			    @frozen public enum SafeDIScope_Gadget {
			        case inner_defaultServiceBuilder(inner_defaultServiceBuilder_Values, Inner.SafeDIScope_DefaultService, SafeDIScope_Gadget.DefaultService_Scope)

			        public struct inner_defaultServiceBuilder_Values {
			            public let tag: Tag
			        }

			        @frozen public enum DefaultService_Scope {
			            case gadget(gadget_Values)

			            public struct gadget_Values {
			                public let name: String
			            }
			        }
			    }

			    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public convenience init(__safeDI_gadgetBuilder: @escaping (SafeDIScope_Gadget) -> any Gadget) {
			        let tag = Tag()
			        let __safeDI_gadgetValues_inner_defaultServiceBuilder = SafeDIScope_Gadget.inner_defaultServiceBuilder_Values(tag: tag)
			        func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_0D398D5CC2F694EB.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_defaultServiceBuilder_Inner(_ __safeDI_inner_defaultServiceBuilder: Inner.SafeDIScope_DefaultService) -> any Service {
			                switch __safeDI_inner_defaultServiceBuilder {
			                case let .screenBuilder(_, scope): return __safeDI_defaultServiceBuilder_Inner_Screen_Scope(scope, __safeDI_inner_defaultServiceBuilder: __safeDI_inner_defaultServiceBuilder)
			                }
			            }
			            func __safeDI_defaultServiceBuilder_Inner_Screen_Scope(_ scope: Inner.SafeDIScope_DefaultService.Screen_Scope, __safeDI_inner_defaultServiceBuilder: Inner.SafeDIScope_DefaultService) -> any Service {
			                switch scope {
			                case let .serviceBuilder(_, __safeDI_forwarded):
			                    func __safeDI_serviceBuilder(name: String) -> DefaultService {
			                        let gadget: any Gadget = __safeDI_gadgetBuilder(.inner_defaultServiceBuilder(__safeDI_gadgetValues_inner_defaultServiceBuilder, __safeDI_inner_defaultServiceBuilder, .gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values(name: name))))
			                        return DefaultService(name: name, gadget: gadget)
			                    }
			                    return __safeDI_serviceBuilder(name: __safeDI_forwarded)
			                }
			            }
			            return Inner(__safeDI_defaultServiceBuilder: __safeDI_defaultServiceBuilder_Inner)
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(tag: tag, inner: inner)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_73BDE7504B17B655 {}
			}
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			extension Root {
			    public convenience init() {
			        func __safeDI_outer() -> Outer {
			            _ = Outer.__safeDI_Outer_73BDE7504B17B655.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_gadgetBuilder_Outer(_ scope: Outer.SafeDIScope_Gadget) -> any Gadget {
			                switch scope {
			                case let .inner_defaultServiceBuilder(values, innerScope, scope): return __safeDI_gadgetBuilder_Outer_DefaultService_Scope(scope, id: __safeDI_id_Inner_SafeDIScope_DefaultService(innerScope), tag: values.tag)
			                }
			            }
			            func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(_ scope: Outer.SafeDIScope_Gadget.DefaultService_Scope, id: Int, tag: Tag) -> any Gadget {
			                switch scope {
			                case let .gadget(scope):
			                    let name = scope.name
			                    let gadget: any Gadget = LiveGadget(id: id, name: name, tag: tag)
			                    return gadget
			                }
			            }
			            func __safeDI_id_Inner_SafeDIScope_DefaultService(_ scope: Inner.SafeDIScope_DefaultService) -> Int {
			                switch scope {
			                case let .screenBuilder(_, scope): return __safeDI_id_Inner_Screen_Scope(scope)
			                }
			            }
			            func __safeDI_id_Inner_Screen_Scope(_ scope: Inner.SafeDIScope_DefaultService.Screen_Scope) -> Int {
			                switch scope {
			                case let .serviceBuilder(values, _): return values.id
			                }
			            }
			            return Outer(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Outer)
			        }
			        let outer: Outer = __safeDI_outer()
			        self.init(outer: outer)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_skipsForwardedValueInReadersPattern_whenInnerAlsoHoldsPlaceHeldByInstantiatorThatForwardsValueAtItsRoot() async throws {
		// As above, and `Inner` holds the place at its root too, where no level holds `id`: the root's reader returns `nil`
		// there, and `LiveGadget` is handed `nil`, as inline.
		try await expectPlaceInsideFill(
			feature: Self.forwardingInner(rootDeclarations: [
				"@Instantiated public let screenBuilder: Instantiator<Screen>",
				#"@Instantiated(fulfilledByType: "DefaultService") public let serviceBuilder: ErasedInstantiator<String, any Service>"#,
			]),
			middle: Self.forwardingMiddle,
			app: Self.forwardingApp,
			probes: [
				DifferentialValueProbe("Root()"),
				DifferentialValueProbe(#"Root().outer.inner.screenBuilder.instantiate(4).serviceBuilder.instantiate("n")"#),
				DifferentialValueProbe(#"Root().outer.inner.serviceBuilder.instantiate("m")"#),
			],
			expectedMiddle: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Outer {
			    @frozen public enum SafeDIScope_Gadget {
			        case inner_defaultServiceBuilder(inner_defaultServiceBuilder_Values, Inner.SafeDIScope_DefaultService, SafeDIScope_Gadget.DefaultService_Scope)

			        public struct inner_defaultServiceBuilder_Values {
			            public let tag: Tag
			        }

			        @frozen public enum DefaultService_Scope {
			            case gadget(gadget_Values)

			            public struct gadget_Values {
			                public let name: String
			            }
			        }
			    }

			    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public convenience init(__safeDI_gadgetBuilder: @escaping (SafeDIScope_Gadget) -> any Gadget) {
			        let tag = Tag()
			        let __safeDI_gadgetValues_inner_defaultServiceBuilder = SafeDIScope_Gadget.inner_defaultServiceBuilder_Values(tag: tag)
			        func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_47C65AF68615D8F5.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_defaultServiceBuilder_Inner(_ __safeDI_inner_defaultServiceBuilder: Inner.SafeDIScope_DefaultService) -> any Service {
			                switch __safeDI_inner_defaultServiceBuilder {
			                case let .screenBuilder(_, scope): return __safeDI_defaultServiceBuilder_Inner_Screen_Scope(scope, __safeDI_inner_defaultServiceBuilder: __safeDI_inner_defaultServiceBuilder)
			                case let .serviceBuilder(_, __safeDI_forwarded):
			                    func __safeDI_serviceBuilder(name: String) -> DefaultService {
			                        let gadget: any Gadget = __safeDI_gadgetBuilder(.inner_defaultServiceBuilder(__safeDI_gadgetValues_inner_defaultServiceBuilder, __safeDI_inner_defaultServiceBuilder, .gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values(name: name))))
			                        return DefaultService(name: name, gadget: gadget)
			                    }
			                    return __safeDI_serviceBuilder(name: __safeDI_forwarded)
			                }
			            }
			            func __safeDI_defaultServiceBuilder_Inner_Screen_Scope(_ scope: Inner.SafeDIScope_DefaultService.Screen_Scope, __safeDI_inner_defaultServiceBuilder: Inner.SafeDIScope_DefaultService) -> any Service {
			                switch scope {
			                case let .serviceBuilder(_, __safeDI_forwarded):
			                    func __safeDI_serviceBuilder(name: String) -> DefaultService {
			                        let gadget: any Gadget = __safeDI_gadgetBuilder(.inner_defaultServiceBuilder(__safeDI_gadgetValues_inner_defaultServiceBuilder, __safeDI_inner_defaultServiceBuilder, .gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values(name: name))))
			                        return DefaultService(name: name, gadget: gadget)
			                    }
			                    return __safeDI_serviceBuilder(name: __safeDI_forwarded)
			                }
			            }
			            return Inner(__safeDI_defaultServiceBuilder: __safeDI_defaultServiceBuilder_Inner)
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(tag: tag, inner: inner)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_A9AE8E64032459F4 {}
			}
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			extension Root {
			    public convenience init() {
			        func __safeDI_outer() -> Outer {
			            _ = Outer.__safeDI_Outer_A9AE8E64032459F4.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_gadgetBuilder_Outer(_ scope: Outer.SafeDIScope_Gadget) -> any Gadget {
			                switch scope {
			                case let .inner_defaultServiceBuilder(values, innerScope, scope): return __safeDI_gadgetBuilder_Outer_DefaultService_Scope(scope, id: __safeDI_id_Inner_SafeDIScope_DefaultService(innerScope), tag: values.tag)
			                }
			            }
			            func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(_ scope: Outer.SafeDIScope_Gadget.DefaultService_Scope, id: Int?, tag: Tag) -> any Gadget {
			                switch scope {
			                case let .gadget(scope):
			                    let name = scope.name
			                    let gadget: any Gadget = LiveGadget(id: id, name: name, tag: tag)
			                    return gadget
			                }
			            }
			            func __safeDI_id_Inner_SafeDIScope_DefaultService(_ scope: Inner.SafeDIScope_DefaultService) -> Int? {
			                switch scope {
			                case let .screenBuilder(_, scope): return __safeDI_id_Inner_Screen_Scope(scope)
			                case .serviceBuilder: return nil
			                }
			            }
			            func __safeDI_id_Inner_Screen_Scope(_ scope: Inner.SafeDIScope_DefaultService.Screen_Scope) -> Int {
			                switch scope {
			                case let .serviceBuilder(values, _): return values.id
			                }
			            }
			            return Outer(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Outer)
			        }
			        let outer: Outer = __safeDI_outer()
			        self.init(outer: outer)
			    }
			}
			""",
		)
	}

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsPlaceInsideFillOfCaseOfBothRootEnums_whenInnerBuildsTypeHoldingPlaceInsideAndOutsideSendableFunction(screenInstantiatesMark: Bool) async {
		// `Inner` builds `Panel` at its root and inside the `@Sendable` function of its `screenBuilder`, so `Panel`'s `service`
		// is a case both of `Inner`'s root enums reach. `Outer` fills it with `DefaultService`, whose `gadget` only `App` can
		// build: the one function that fills the case would be handed a scope of either root enum, and the case of `gadget`
		// can carry only one, so SafeDI reports the shape.
		let screenDeclarations = ["@Forwarded public let id: Int"] + (screenInstantiatesMark ? ["@Instantiated public let mark: Mark"] : []) + ["@Instantiated public let panel: Panel"]
		await assertThrowsMultiModuleError(inModule: "Middle", diagnostics: { fixtures in
			"""
			\(fixtures["Middle"]!["DefaultService.swift"]):9:5: error: SafeDI fills every place of the builder for `Panel`’s `service: any Service` (case `Panel_Scope.service` of `serviceBuilder`) with one function, whose tree builds `DefaultService`’s `gadget: any Gadget`, which no type that module `Middle` can see fulfills. `Inner` builds `Panel` both inside and outside a `@Sendable` function, so that function is handed a scope of either of `Inner`’s two root enums, and the case of `DefaultService`’s `gadget: any Gadget` can carry only one. To fill it, declare an @Instantiable type that fulfills `Gadget` in module `Middle` or a module it lists among its SafeDI dependencies, or declare an @Instantiable type that fulfills `Service` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["Panel.swift"]):7:5: note: `Panel` instantiates `service: any Service` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: [
						"public protocol Service: Sendable {}\npublic protocol Gadget: Sendable {}",
						seamFixtureType(named: "Mark", isFinalClass: true, declarations: [], conformances: ", Sendable"),
						seamFixtureType(named: "Panel", declarations: ["@Instantiated public let service: any Service"], conformances: ", Sendable"),
						seamFixtureType(named: "Screen", declarations: screenDeclarations, conformances: ", Sendable"),
						seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated public let panel: Panel", "@Instantiated public let screenBuilder: SendableInstantiator<Screen>"], conformances: ", Sendable"),
					],
					middle: [
						Self.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let gadget: any Gadget"], conformances: ", Sendable"),
						seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated public let inner: Inner"], conformances: ", Sendable"),
					],
					app: [
						Self.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received(onlyIfAvailable: true) public let id: Int?", "@Received(onlyIfAvailable: true) public let mark: Mark?"], conformances: ", Sendable"),
						seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let outer: Outer"], conformances: ", Sendable"),
					],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Inner`, a seam whose `rootDeclarations` build `Panel`, which builds `service`, a hole, at its root, and, through
	/// `screenBuilder`, in the `Screen` it builds, which declares `screenDeclarations` before its own `panel`: one case of
	/// `Inner`'s, `Panel_Scope.service`, stands for both places. Beside it, the protocols `Service` and `Gadget`, and `Session`.
	private static func panelInner(screenDeclarations: [String] = ["@Forwarded public let id: Int"], rootDeclarations: [String]) -> [String] {
		[
			"public protocol Service {}\npublic protocol Gadget {}",
			seamFixtureType(named: "Session", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Panel", declarations: ["@Instantiated public let service: any Service"]),
			seamFixtureType(named: "Screen", declarations: screenDeclarations + ["@Instantiated public let panel: Panel"]),
			seamFixtureType(named: "Inner", isSeam: true, declarations: rootDeclarations),
		]
	}

	/// `Outer`, which calls `Inner`, and `DefaultService`, which fills `Inner`'s `service` and holds `gadget`, a place only
	/// `App` can build.
	private static let panelMiddle = [
		fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let gadget: any Gadget"]),
		seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated public let inner: Inner"]),
	]

	/// `Inner`, a seam that builds `service`, a hole, at its root and in the `Screen` its `screenBuilder` builds, which also
	/// declares `screen`; and the protocols `Service` and `Gadget`.
	private static func inner(screen: [String], innerScreenBuilder: String = "Instantiator<Screen>", conformances: String = "") -> [String] {
		[
			"public protocol Service\(conformances.isEmpty ? "" : ": Sendable") {}\npublic protocol Gadget\(conformances.isEmpty ? "" : ": Sendable") {}",
			seamFixtureType(named: "Screen", declarations: screen + ["@Instantiated public let service: any Service"], conformances: conformances),
			seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated public let screenBuilder: \(innerScreenBuilder)", "@Instantiated public let service: any Service"], conformances: conformances),
		]
	}

	/// `Inner`, a seam whose `Screen` forwards `id` and holds `serviceBuilder`, an erased instantiator of the hole `Service`
	/// that forwards a `String`, with `rootDeclarations`.
	private static func forwardingInner(rootDeclarations: [String]) -> [String] {
		[
			"public protocol Service {}\npublic protocol Gadget {}",
			seamFixtureType(named: "Tag", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Screen", isFinalClass: true, declarations: ["@Forwarded public let id: Int", #"@Instantiated(fulfilledByType: "DefaultService") public let serviceBuilder: ErasedInstantiator<String, any Service>"#]),
			seamFixtureType(named: "Inner", isSeam: true, isFinalClass: true, declarations: rootDeclarations),
		]
	}

	/// `Outer`, which instantiates `tag` and calls `Inner`, and `DefaultService`, which fills `Inner`'s `serviceBuilder`,
	/// forwards `name` and holds `gadget`, a place only `App` can build.
	private static let forwardingMiddle = [
		seamFixtureType(named: "DefaultService", isFinalClass: true, declarations: ["@Forwarded public let name: String", "@Instantiated public let gadget: any Gadget"], conformances: ", Service")
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [Service.self])\n"),
		seamFixtureType(named: "Outer", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let tag: Tag", "@Instantiated public let inner: Inner"]),
	]

	/// `LiveGadget`, which fills `gadget` and reads `tag`, and `id` and `name` only if available, and `Root`.
	private static let forwardingApp = [
		seamFixtureType(named: "LiveGadget", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) public let id: Int?", "@Received(onlyIfAvailable: true) public let name: String?", "@Received public let tag: Tag"], conformances: ", Gadget")
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [Gadget.self])\n"),
		seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let outer: Outer"]),
	]

	private static func fulfillingType(named name: String, fulfilling fulfilledType: String, declarations: [String], conformances: String = "") -> String {
		seamFixtureType(named: name, declarations: declarations, conformances: ", \(fulfilledType)\(conformances)")
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [\(fulfilledType).self])\n")
	}

	/// `Feature`, which declares `Inner`; `Middle`, which declares `Outer` and what fills `Inner`'s holes; and `App`, which
	/// fills `Outer`'s places inside those fills.
	private static func modules(feature: [String], middle: [String], app: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature),
			ModuleFixture(name: "Middle", packageName: "Other", swiftFileContent: middle.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: app.map { "import Feature\nimport Middle\n\n" + $0 }, dependencies: ["Feature", "Middle"]),
		]
	}

	/// Expects `Middle`'s and `App`'s generated files to be exactly `expectedMiddle` and `expectedApp`, each after the file
	/// header, and the modules to build, for each of `probes`, the values the same graph builds with no seam, every tree
	/// built inline.
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
		guard compileVerificationIsEnabled else { return }
		let inlineModules = Self.modules(feature: inlineFixture(feature), middle: inlineFixture(middle), app: inlineFixture(app))
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inlineModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete, sourceLocation: sourceLocation)
		try await expectDifferentialValuesAgree(
			feature: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: output, modules: modules),
			knownRight: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: inlineOutput, modules: inlineModules),
			probes: probes,
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}
}
