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

/// The comment a call of `seam`, a seam of `module`, carries under `.moduleInfo`.
private func seamCallComment(seam: String, module: String) -> String {
	MultiModuleIntegration.moduleInfo.seamCallComment(type: seam, declaringModule: module)
}

/// A seam that fills another seam's hole, with a place, or a call of a further seam, inside the fill. When the fill is a
/// `@Sendable` function, what it holds is inside a `@Sendable` function as it is inside a `@Sendable` builder function:
/// a place there is a case of the `@Sendable` enum, and a builder a call inside it passes up is `@Sendable`.
struct SafeDIToolSeamSendableFillTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: A place and an inner call inside a fill

	/// How `Feature` presents the hole `Middle` fills, which decides which functions of the fill are `@Sendable`.
	enum FillRoute: CaseIterable, CustomTestStringConvertible {
		/// `Host` calls `Inner`, which builds `widget` in plain code: the fill is plain.
		case plain
		/// `Host` calls `Shell`, which builds `Inner` in a `SendableInstantiator`: `Shell` takes the builder `@Sendable`.
		case sendableByRoute
		/// `Host` calls `Inner`, which builds `widget` in a `SendableInstantiator`: the fill is `@Sendable`.
		case placeInsideSendableFunction
		/// Both: the fill is `@Sendable`.
		case placeInsideSendableFunctionTakenSendable

		var testDescription: String {
			switch self {
			case .plain:
				"plain"
			case .sendableByRoute:
				"sendableByRoute"
			case .placeInsideSendableFunction:
				"placeInsideSendableFunction"
			case .placeInsideSendableFunctionTakenSendable:
				"placeInsideSendableFunctionTakenSendable"
			}
		}

		var isInsideSendableFunction: Bool {
			switch self {
			case .plain, .sendableByRoute:
				false
			case .placeInsideSendableFunction, .placeInsideSendableFunctionTakenSendable:
				true
			}
		}

		var isThroughShell: Bool {
			switch self {
			case .plain, .placeInsideSendableFunction:
				false
			case .sendableByRoute, .placeInsideSendableFunctionTakenSendable:
				true
			}
		}

		var featureTypes: [String] {
			let leaves = [
				"public protocol Widget: Sendable {}",
				seamFixtureType(named: "Analytics", declarations: [], conformances: ", Sendable"),
				seamFixtureType(named: "Clock", declarations: [], conformances: ", Sendable"),
			]
			let inner = isInsideSendableFunction
				? [
					seamFixtureType(named: "Panel", declarations: ["@Instantiated let analytics: Analytics", "@Instantiated let clock: Clock", "@Instantiated let widget: any Widget"], conformances: ", Sendable"),
					seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated let analytics: Analytics", "@Instantiated let panelBuilder: SendableInstantiator<Panel>"], conformances: ", Sendable"),
				]
				: [seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated let analytics: Analytics", "@Instantiated let widget: any Widget"], conformances: ", Sendable")]
			let shell = isThroughShell ? [seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Instantiated let innerBuilder: SendableInstantiator<Inner>"], conformances: ", Sendable")] : []
			return leaves + inner + shell
		}

		var hostDeclaration: String {
			isThroughShell ? "@Instantiated let shell: Shell" : "@Instantiated let inner: Inner"
		}

		/// The `Host` initializer and guard `Middle` generates when the fill holds a place and a call of `Part`.
		var hostCode: String {
			switch self {
			case .plain:
				"""
				extension Host {
				    @frozen public enum SafeDIScope_Gadget {
				        case inner_widget_gadget(inner_widget_gadget_Values)

				        public struct inner_widget_gadget_Values {
				            public let session: Session
				            public let analytics: Analytics
				            public let part: Part
				        }
				    }

				    @frozen public enum SafeDIScope_Gear {
				        case inner_widget_part(Part.SafeDIScope_Gear)
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public init(__safeDI_session session: Session, __safeDI_gadgetBuilder: @escaping (SafeDIScope_Gadget) -> any Gadget, __safeDI_gearBuilder: @escaping (SafeDIScope_Gear) -> any Gear) {
				        func __safeDI_inner() -> Inner {
				            _ = Inner.__safeDI_Inner_318A87E8A50EC522.self\(seamCallComment(seam: "Inner", module: "Feature"))
				            func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
				                switch scope {
				                case let .widget(scope):
				                    let analytics = scope.analytics
				                    func __safeDI_widget() -> DefaultWidget {
				                        func __safeDI_part() -> Part {
				                            _ = Part.__safeDI_Part_F870B0D7B6455852.self\(seamCallComment(seam: "Inner", module: "Feature"))
				                            return Part(__safeDI_gearBuilder: { __safeDI_gearBuilder(.inner_widget_part($0)) })
				                        }
				                        let part: Part = __safeDI_part()
				                        let gadget: any Gadget = __safeDI_gadgetBuilder(.inner_widget_gadget(SafeDIScope_Gadget.inner_widget_gadget_Values(session: session, analytics: analytics, part: part)))
				                        return DefaultWidget(analytics: analytics, gadget: gadget, part: part)
				                    }
				                    let widget: any Widget = __safeDI_widget()
				                    return widget
				                }
				            }
				            return Inner(__safeDI_widgetBuilder: __safeDI_widgetBuilder_Inner)
				        }
				        let inner: Inner = __safeDI_inner()
				        self.init(session: session, inner: inner)
				    }
				}

				extension Host {
				    public enum __safeDI_Host_465241F01D0011B9 {}
				}
				"""
			case .sendableByRoute:
				"""
				extension Host {
				    @frozen public enum SafeDISendableScope_Gadget {
				        case shell_Inner_widget_gadget(shell_Inner_widget_gadget_Values)

				        public struct shell_Inner_widget_gadget_Values {
				            public let analytics: Analytics
				            public let part: Part
				        }
				    }

				    @frozen public enum SafeDISendableScope_Gear {
				        case shell_Inner_widget_part(Part.SafeDIScope_Gear)
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public init(__safeDI_session session: Session, __safeDI_gadgetSendableBuilder: @escaping @Sendable (SafeDISendableScope_Gadget) -> any Gadget, __safeDI_gearSendableBuilder: @escaping @Sendable (SafeDISendableScope_Gear) -> any Gear) {
				        func __safeDI_shell() -> Shell {
				            _ = Shell.__safeDI_Shell_F559842BF1A90246.self\(seamCallComment(seam: "Shell", module: "Feature"))
				            @Sendable func __safeDI_widgetSendableBuilder_Shell(_ scope: Shell.SafeDISendableScope_Widget) -> any Widget {
				                switch scope {
				                case let .innerBuilder(scope): return __safeDI_widgetBuilder_Inner(scope)
				                }
				            }
				            @Sendable func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
				                switch scope {
				                case let .widget(scope):
				                    let analytics = scope.analytics
				                    func __safeDI_widget() -> DefaultWidget {
				                        func __safeDI_part() -> Part {
				                            _ = Part.__safeDI_Part_F870B0D7B6455852.self\(seamCallComment(seam: "Part", module: "Feature"))
				                            return Part(__safeDI_gearBuilder: { __safeDI_gearSendableBuilder(.shell_Inner_widget_part($0)) })
				                        }
				                        let part: Part = __safeDI_part()
				                        let gadget: any Gadget = __safeDI_gadgetSendableBuilder(.shell_Inner_widget_gadget(SafeDISendableScope_Gadget.shell_Inner_widget_gadget_Values(analytics: analytics, part: part)))
				                        return DefaultWidget(analytics: analytics, gadget: gadget, part: part)
				                    }
				                    let widget: any Widget = __safeDI_widget()
				                    return widget
				                }
				            }
				            return Shell(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell)
				        }
				        let shell: Shell = __safeDI_shell()
				        self.init(session: session, shell: shell)
				    }
				}

				extension Host {
				    public enum __safeDI_Host_D678AA17A8F1FF30 {}
				}
				"""
			case .placeInsideSendableFunction:
				"""
				extension Host {
				    @frozen public enum SafeDISendableScope_Gadget {
				        case inner_panelBuilder_widget_gadget(inner_panelBuilder_widget_gadget_Values)

				        public struct inner_panelBuilder_widget_gadget_Values {
				            public let analytics: Analytics
				            public let clock: Clock
				            public let part: Part
				        }
				    }

				    @frozen public enum SafeDISendableScope_Gear {
				        case inner_panelBuilder_widget_part(Part.SafeDIScope_Gear)
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public init(__safeDI_session session: Session, __safeDI_gadgetSendableBuilder: @escaping @Sendable (SafeDISendableScope_Gadget) -> any Gadget, __safeDI_gearSendableBuilder: @escaping @Sendable (SafeDISendableScope_Gear) -> any Gear) {
				        func __safeDI_inner() -> Inner {
				            _ = Inner.__safeDI_Inner_6288FB023CC267A8.self\(seamCallComment(seam: "Inner", module: "Feature"))
				            @Sendable func __safeDI_widgetSendableBuilder_Inner(_ scope: Inner.SafeDISendableScope_Widget) -> any Widget {
				                switch scope {
				                case let .panelBuilder(scope): return __safeDI_widgetBuilder_Inner_Panel_Scope(scope)
				                }
				            }
				            @Sendable func __safeDI_widgetBuilder_Inner_Panel_Scope(_ scope: Inner.SafeDIScope_Widget.Panel_Scope) -> any Widget {
				                switch scope {
				                case let .widget(scope):
				                    let analytics = scope.analytics
				                    let clock = scope.clock
				                    func __safeDI_widget() -> DefaultWidget {
				                        func __safeDI_part() -> Part {
				                            _ = Part.__safeDI_Part_F870B0D7B6455852.self\(seamCallComment(seam: "Inner", module: "Feature"))
				                            return Part(__safeDI_gearBuilder: { __safeDI_gearSendableBuilder(.inner_panelBuilder_widget_part($0)) })
				                        }
				                        let part: Part = __safeDI_part()
				                        let gadget: any Gadget = __safeDI_gadgetSendableBuilder(.inner_panelBuilder_widget_gadget(SafeDISendableScope_Gadget.inner_panelBuilder_widget_gadget_Values(analytics: analytics, clock: clock, part: part)))
				                        return DefaultWidget(analytics: analytics, gadget: gadget, part: part)
				                    }
				                    let widget: any Widget = __safeDI_widget()
				                    return widget
				                }
				            }
				            return Inner(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Inner)
				        }
				        let inner: Inner = __safeDI_inner()
				        self.init(session: session, inner: inner)
				    }
				}

				extension Host {
				    public enum __safeDI_Host_4B269D48E6459923 {}
				}
				"""
			case .placeInsideSendableFunctionTakenSendable:
				"""
				extension Host {
				    @frozen public enum SafeDISendableScope_Gadget {
				        case shell_Inner_panelBuilder_widget_gadget(shell_Inner_panelBuilder_widget_gadget_Values)

				        public struct shell_Inner_panelBuilder_widget_gadget_Values {
				            public let analytics: Analytics
				            public let clock: Clock
				            public let part: Part
				        }
				    }

				    @frozen public enum SafeDISendableScope_Gear {
				        case shell_Inner_panelBuilder_widget_part(Part.SafeDIScope_Gear)
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public init(__safeDI_session session: Session, __safeDI_gadgetSendableBuilder: @escaping @Sendable (SafeDISendableScope_Gadget) -> any Gadget, __safeDI_gearSendableBuilder: @escaping @Sendable (SafeDISendableScope_Gear) -> any Gear) {
				        func __safeDI_shell() -> Shell {
				            _ = Shell.__safeDI_Shell_9506931DF49A6B00.self\(seamCallComment(seam: "Shell", module: "Feature"))
				            @Sendable func __safeDI_widgetSendableBuilder_Shell(_ scope: Shell.SafeDISendableScope_Widget) -> any Widget {
				                switch scope {
				                case let .innerBuilder_Sendable(scope): return __safeDI_widgetSendableBuilder_Inner(scope)
				                }
				            }
				            @Sendable func __safeDI_widgetSendableBuilder_Inner(_ scope: Inner.SafeDISendableScope_Widget) -> any Widget {
				                switch scope {
				                case let .panelBuilder(scope): return __safeDI_widgetBuilder_Inner_Panel_Scope(scope)
				                }
				            }
				            @Sendable func __safeDI_widgetBuilder_Inner_Panel_Scope(_ scope: Inner.SafeDIScope_Widget.Panel_Scope) -> any Widget {
				                switch scope {
				                case let .widget(scope):
				                    let analytics = scope.analytics
				                    let clock = scope.clock
				                    func __safeDI_widget() -> DefaultWidget {
				                        func __safeDI_part() -> Part {
				                            _ = Part.__safeDI_Part_F870B0D7B6455852.self\(seamCallComment(seam: "Shell", module: "Feature"))
				                            return Part(__safeDI_gearBuilder: { __safeDI_gearSendableBuilder(.shell_Inner_panelBuilder_widget_part($0)) })
				                        }
				                        let part: Part = __safeDI_part()
				                        let gadget: any Gadget = __safeDI_gadgetSendableBuilder(.shell_Inner_panelBuilder_widget_gadget(SafeDISendableScope_Gadget.shell_Inner_panelBuilder_widget_gadget_Values(analytics: analytics, clock: clock, part: part)))
				                        return DefaultWidget(analytics: analytics, gadget: gadget, part: part)
				                    }
				                    let widget: any Widget = __safeDI_widget()
				                    return widget
				                }
				            }
				            return Shell(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell)
				        }
				        let shell: Shell = __safeDI_shell()
				        self.init(session: session, shell: shell)
				    }
				}

				extension Host {
				    public enum __safeDI_Host_19109AFB4F6C7B5D {}
				}
				"""
			}
		}

		/// The `Root` initializer `App` generates, which fills what `Host` passes up.
		var rootCode: String {
			switch self {
			case .plain:
				"""
				extension Root {
				    public init() {
				        let session = Session()
				        func __safeDI_host() -> Host {
				            _ = Host.__safeDI_Host_465241F01D0011B9.self\(seamCallComment(seam: "Host", module: "Middle"))
				            func __safeDI_gadgetBuilder_Host(_ scope: Host.SafeDIScope_Gadget) -> any Gadget {
				                switch scope {
				                case let .inner_widget_gadget(scope):
				                    let session = scope.session
				                    let analytics = scope.analytics
				                    let gadget: any Gadget = DefaultGadget(session: session, analytics: analytics)
				                    return gadget
				                }
				            }
				            func __safeDI_gearBuilder_Host(_ scope: Host.SafeDIScope_Gear) -> any Gear {
				                switch scope {
				                case let .inner_widget_part(scope): return __safeDI_gearBuilder_Part(scope)
				                }
				            }
				            func __safeDI_gearBuilder_Part(_ scope: Part.SafeDIScope_Gear) -> any Gear {
				                switch scope {
				                case .gear:
				                    let gear: any Gear = DefaultGear()
				                    return gear
				                }
				            }
				            return Host(__safeDI_session: session, __safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Host, __safeDI_gearBuilder: __safeDI_gearBuilder_Host)
				        }
				        let host: Host = __safeDI_host()
				        self.init(session: session, host: host)
				    }
				}
				"""
			case .sendableByRoute:
				"""
				extension Root {
				    public init() {
				        let session = Session()
				        func __safeDI_host() -> Host {
				            _ = Host.__safeDI_Host_D678AA17A8F1FF30.self\(seamCallComment(seam: "Host", module: "Middle"))
				            @Sendable func __safeDI_gadgetSendableBuilder_Host(_ scope: Host.SafeDISendableScope_Gadget) -> any Gadget {
				                switch scope {
				                case let .shell_Inner_widget_gadget(scope):
				                    let analytics = scope.analytics
				                    let gadget: any Gadget = DefaultGadget(session: session, analytics: analytics)
				                    return gadget
				                }
				            }
				            @Sendable func __safeDI_gearSendableBuilder_Host(_ scope: Host.SafeDISendableScope_Gear) -> any Gear {
				                switch scope {
				                case let .shell_Inner_widget_part(scope): return __safeDI_gearBuilder_Part(scope)
				                }
				            }
				            @Sendable func __safeDI_gearBuilder_Part(_ scope: Part.SafeDIScope_Gear) -> any Gear {
				                switch scope {
				                case .gear:
				                    let gear: any Gear = DefaultGear()
				                    return gear
				                }
				            }
				            return Host(__safeDI_session: session, __safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_Host, __safeDI_gearSendableBuilder: __safeDI_gearSendableBuilder_Host)
				        }
				        let host: Host = __safeDI_host()
				        self.init(session: session, host: host)
				    }
				}
				"""
			case .placeInsideSendableFunction:
				"""
				extension Root {
				    public init() {
				        let session = Session()
				        func __safeDI_host() -> Host {
				            _ = Host.__safeDI_Host_4B269D48E6459923.self\(seamCallComment(seam: "Host", module: "Middle"))
				            @Sendable func __safeDI_gadgetSendableBuilder_Host(_ scope: Host.SafeDISendableScope_Gadget) -> any Gadget {
				                switch scope {
				                case let .inner_panelBuilder_widget_gadget(scope):
				                    let analytics = scope.analytics
				                    let gadget: any Gadget = DefaultGadget(session: session, analytics: analytics)
				                    return gadget
				                }
				            }
				            @Sendable func __safeDI_gearSendableBuilder_Host(_ scope: Host.SafeDISendableScope_Gear) -> any Gear {
				                switch scope {
				                case let .inner_panelBuilder_widget_part(scope): return __safeDI_gearBuilder_Part(scope)
				                }
				            }
				            @Sendable func __safeDI_gearBuilder_Part(_ scope: Part.SafeDIScope_Gear) -> any Gear {
				                switch scope {
				                case .gear:
				                    let gear: any Gear = DefaultGear()
				                    return gear
				                }
				            }
				            return Host(__safeDI_session: session, __safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_Host, __safeDI_gearSendableBuilder: __safeDI_gearSendableBuilder_Host)
				        }
				        let host: Host = __safeDI_host()
				        self.init(session: session, host: host)
				    }
				}
				"""
			case .placeInsideSendableFunctionTakenSendable:
				"""
				extension Root {
				    public init() {
				        let session = Session()
				        func __safeDI_host() -> Host {
				            _ = Host.__safeDI_Host_19109AFB4F6C7B5D.self\(seamCallComment(seam: "Host", module: "Middle"))
				            @Sendable func __safeDI_gadgetSendableBuilder_Host(_ scope: Host.SafeDISendableScope_Gadget) -> any Gadget {
				                switch scope {
				                case let .shell_Inner_panelBuilder_widget_gadget(scope):
				                    let analytics = scope.analytics
				                    let gadget: any Gadget = DefaultGadget(session: session, analytics: analytics)
				                    return gadget
				                }
				            }
				            @Sendable func __safeDI_gearSendableBuilder_Host(_ scope: Host.SafeDISendableScope_Gear) -> any Gear {
				                switch scope {
				                case let .shell_Inner_panelBuilder_widget_part(scope): return __safeDI_gearBuilder_Part(scope)
				                }
				            }
				            @Sendable func __safeDI_gearBuilder_Part(_ scope: Part.SafeDIScope_Gear) -> any Gear {
				                switch scope {
				                case .gear:
				                    let gear: any Gear = DefaultGear()
				                    return gear
				                }
				            }
				            return Host(__safeDI_session: session, __safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_Host, __safeDI_gearSendableBuilder: __safeDI_gearSendableBuilder_Host)
				        }
				        let host: Host = __safeDI_host()
				        self.init(session: session, host: host)
				    }
				}
				"""
			}
		}
	}

	/// The types of a fixture, in the modules that declare them.
	private struct ThreeModules {
		let feature: [String]
		let middle: [String]
		let app: [String]
		let root: String

		/// `Feature` (package `Shop`), `Middle` (package `Mid`), which depends on it, and `App` (package `Other`), which
		/// depends on both.
		var modules: [ModuleFixture] {
			[
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature),
				ModuleFixture(name: "Middle", packageName: "Mid", swiftFileContent: middle.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
				ModuleFixture(name: "App", packageName: "Other", swiftFileContent: (app + [root]).map { "import Feature\nimport Middle\n\n" + $0 }, dependencies: ["Feature", "Middle"]),
			]
		}

		/// The same graph with every declaration but the root in one module, so no seam has a hole.
		var visibleModules: [ModuleFixture] {
			SafeDIToolSeamBuilderParameterTests.modules(feature: feature + middle + app, app: [root])
		}
	}

	private static let gadget = "public protocol Gadget: Sendable {}"
	private static let session = seamFixtureType(named: "Session", declarations: [], conformances: ", Sendable")
	private static let gear = [
		"public protocol Gear: Sendable {}",
		seamFixtureType(named: "Part", isSeam: true, declarations: ["@Instantiated let gear: any Gear"], conformances: ", Sendable"),
	]
	private static let defaultGadget = SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultGadget", fulfilling: "Gadget", declarations: ["@Received let session: Session", "@Received let analytics: Analytics"])
	private static let defaultGear = SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultGear", fulfilling: "Gear", declarations: [])
	/// A `DefaultGadget` that reads only the `session` its seam receives, which a place held in a `Sendable` wrapper reads from
	/// the caller's scope.
	private static let defaultGadgetReadingSession = SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultGadget", fulfilling: "Gadget", declarations: ["@Received let session: Session"])
	private static let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let host: Host"])
	/// A root that instantiates the `session` its `Host` receives, which a fill inside a `@Sendable` function reads from the
	/// root's own scope.
	private static let rootWithSession = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let session: Session", "@Instantiated let host: Host"])

	/// `Feature` declares `route`'s types; `Middle`'s `Host` fills `Widget`'s hole with `DefaultWidget`, whose declarations
	/// are `widgetDeclarations`; and `App` fills what `Host` passes up.
	private static func fixture(
		route: FillRoute,
		featureTypes: [String] = [],
		middleTypes: [String] = [],
		widgetDeclarations: [String] = ["@Received let analytics: Analytics", "@Instantiated let gadget: any Gadget", "@Instantiated let part: Part"],
		appTypes: [String] = [defaultGadget, defaultGear],
		root: String = rootWithSession,
		widgetConformances: String = "Instantiable, Widget",
	) -> ThreeModules {
		ThreeModules(
			feature: route.featureTypes + gear + featureTypes,
			middle: [gadget, session] + middleTypes + [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: widgetDeclarations)
					.replacingOccurrences(of: "Instantiable, Widget", with: widgetConformances),
				seamFixtureType(named: "Host", isSeam: true, declarations: ["@Received let session: Session", route.hostDeclaration]),
			],
			app: appTypes,
			root: root,
		)
	}

	@Test(arguments: FillRoute.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_treatsFillAsTheFunctionItIs_whenFillHoldsPlaceAndInnerCall(route: FillRoute) async throws {
		// `DefaultWidget` fills `Widget`'s hole in `Host`'s tree, and builds `gadget`, a place of `Host`, and calls `Part`,
		// whose builder `Host` passes up. Each `@Sendable` function of the fill starts a stage of `gadgetBuilder`, called
		// just before it, and `gearBuilder` is `@Sendable` when the call is in one.
		let fixture = Self.fixture(route: route)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "Middle", imports: ["Feature"], rootFiles: ["Host": route.hostCode])
		expectGeneratedCode(of: output, module: "App", imports: ["Feature", "Middle"], rootFiles: ["Root": route.rootCode])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	// MARK: A place in a fill, beneath further `@Sendable` functions

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesSendableCase_whenPlaceIsBeneathSendableBuilderFunctionInsideSendableFill() async throws {
		// The fill is `@Sendable` by route, and `Holder` is built inside it in a `@Sendable` builder function.
		let fixture = Self.fixture(
			route: .sendableByRoute,
			middleTypes: [seamFixtureType(named: "Holder", declarations: ["@Instantiated let analytics: Analytics", "@Instantiated let gadget: any Gadget"], conformances: ", Sendable")],
			widgetDeclarations: ["@Received let analytics: Analytics", "@Instantiated let holderBuilder: SendableInstantiator<Holder>"],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "Middle", imports: ["Feature"], rootFiles: ["Host": """
		extension Host {
		    @frozen public enum SafeDISendableScope_Gadget {
		        case shell_Inner_widget_holderBuilder_gadget(shell_Inner_widget_holderBuilder_gadget_Values)

		        public struct shell_Inner_widget_holderBuilder_gadget_Values {
		            public let analytics: Analytics
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_session session: Session, __safeDI_gadgetSendableBuilder: @escaping @Sendable (SafeDISendableScope_Gadget) -> any Gadget) {
		        func __safeDI_shell() -> Shell {
		            _ = Shell.__safeDI_Shell_F559842BF1A90246.self\(seamCallComment(seam: "Shell", module: "Feature"))
		            @Sendable func __safeDI_widgetSendableBuilder_Shell(_ scope: Shell.SafeDISendableScope_Widget) -> any Widget {
		                switch scope {
		                case let .innerBuilder(scope): return __safeDI_widgetBuilder_Inner(scope)
		                }
		            }
		            @Sendable func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
		                switch scope {
		                case let .widget(scope):
		                    let analytics = scope.analytics
		                    func __safeDI_widget() -> DefaultWidget {
		                        @Sendable func __safeDI_holderBuilder() -> Holder {
		                            let analytics = Analytics()
		                            let gadget: any Gadget = __safeDI_gadgetSendableBuilder(.shell_Inner_widget_holderBuilder_gadget(SafeDISendableScope_Gadget.shell_Inner_widget_holderBuilder_gadget_Values(analytics: analytics)))
		                            return Holder(analytics: analytics, gadget: gadget)
		                        }
		                        let holderBuilder = SendableInstantiator<Holder>(__safeDI_holderBuilder)
		                        return DefaultWidget(analytics: analytics, holderBuilder: holderBuilder)
		                    }
		                    let widget: any Widget = __safeDI_widget()
		                    return widget
		                }
		            }
		            return Shell(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell)
		        }
		        let shell: Shell = __safeDI_shell()
		        self.init(session: session, shell: shell)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_8C4DFB9859D6F5E5 {}
		}
		"""])
		expectGeneratedCode(of: output, module: "App", imports: ["Feature", "Middle"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        let session = Session()
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_8C4DFB9859D6F5E5.self\(seamCallComment(seam: "Host", module: "Middle"))
		            @Sendable func __safeDI_gadgetSendableBuilder_Host(_ scope: Host.SafeDISendableScope_Gadget) -> any Gadget {
		                switch scope {
		                case let .shell_Inner_widget_holderBuilder_gadget(scope):
		                    let analytics = scope.analytics
		                    let gadget: any Gadget = DefaultGadget(session: session, analytics: analytics)
		                    return gadget
		                }
		            }
		            return Host(__safeDI_session: session, __safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_Host)
		        }
		        let host: Host = __safeDI_host()
		        self.init(session: session, host: host)
		    }
		}
		"""])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesSendableCase_whenPlaceIsInsideFillOfCallInsideAnotherSendableFill() async throws {
		// `DefaultWidget`'s fill calls `DeepShell`, which `Middle` also fills, with `DefaultYarn`, inside whose fill `gadget`
		// is built: the path to the place crosses two `@Sendable` fills.
		let fixture = Self.fixture(
			route: .sendableByRoute,
			featureTypes: [
				"public protocol Yarn: Sendable {}",
				seamFixtureType(named: "Deep", isSeam: true, declarations: ["@Instantiated let yarn: any Yarn"], conformances: ", Sendable"),
				seamFixtureType(named: "DeepShell", isSeam: true, declarations: ["@Instantiated let deepBuilder: SendableInstantiator<Deep>"], conformances: ", Sendable"),
			],
			middleTypes: [SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultYarn", fulfilling: "Yarn", declarations: ["@Instantiated let gadget: any Gadget"])],
			widgetDeclarations: ["@Instantiated let deepShell: DeepShell"],
			appTypes: [SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultGadget", fulfilling: "Gadget", declarations: ["@Received let session: Session"])],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "Middle", imports: ["Feature"], rootFiles: ["Host": """
		extension Host {
		    @frozen public enum SafeDISendableScope_Gadget {
		        case shell_Inner_widget_deepShell_Deep_yarn_gadget(shell_Inner_widget_deepShell_Deep_yarn_gadget_Values)

		        public struct shell_Inner_widget_deepShell_Deep_yarn_gadget_Values {}
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_session session: Session, __safeDI_gadgetSendableBuilder: @escaping @Sendable (SafeDISendableScope_Gadget) -> any Gadget) {
		        func __safeDI_shell() -> Shell {
		            _ = Shell.__safeDI_Shell_F559842BF1A90246.self\(seamCallComment(seam: "Shell", module: "Feature"))
		            @Sendable func __safeDI_widgetSendableBuilder_Shell(_ scope: Shell.SafeDISendableScope_Widget) -> any Widget {
		                switch scope {
		                case let .innerBuilder(scope): return __safeDI_widgetBuilder_Inner(scope)
		                }
		            }
		            @Sendable func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
		                switch scope {
		                case .widget:
		                    func __safeDI_widget() -> DefaultWidget {
		                        func __safeDI_deepShell() -> DeepShell {
		                            _ = DeepShell.__safeDI_DeepShell_05B00017D0D03AEB.self\(seamCallComment(seam: "Shell", module: "Feature"))
		                            @Sendable func __safeDI_yarnSendableBuilder_DeepShell(_ scope: DeepShell.SafeDISendableScope_Yarn) -> any Yarn {
		                                switch scope {
		                                case let .deepBuilder(scope): return __safeDI_yarnBuilder_Deep(scope)
		                                }
		                            }
		                            @Sendable func __safeDI_yarnBuilder_Deep(_ scope: Deep.SafeDIScope_Yarn) -> any Yarn {
		                                switch scope {
		                                case .yarn:
		                                    func __safeDI_yarn() -> DefaultYarn {
		                                        let gadget: any Gadget = __safeDI_gadgetSendableBuilder(.shell_Inner_widget_deepShell_Deep_yarn_gadget(SafeDISendableScope_Gadget.shell_Inner_widget_deepShell_Deep_yarn_gadget_Values()))
		                                        return DefaultYarn(gadget: gadget)
		                                    }
		                                    let yarn: any Yarn = __safeDI_yarn()
		                                    return yarn
		                                }
		                            }
		                            return DeepShell(__safeDI_yarnSendableBuilder: __safeDI_yarnSendableBuilder_DeepShell)
		                        }
		                        let deepShell: DeepShell = __safeDI_deepShell()
		                        return DefaultWidget(deepShell: deepShell)
		                    }
		                    let widget: any Widget = __safeDI_widget()
		                    return widget
		                }
		            }
		            return Shell(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell)
		        }
		        let shell: Shell = __safeDI_shell()
		        self.init(session: session, shell: shell)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_ACD1B3AEE5841AA3 {}
		}
		"""])
		expectGeneratedCode(of: output, module: "App", imports: ["Feature", "Middle"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        let session = Session()
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_ACD1B3AEE5841AA3.self\(seamCallComment(seam: "Host", module: "Middle"))
		            @Sendable func __safeDI_gadgetSendableBuilder_Host(_ scope: Host.SafeDISendableScope_Gadget) -> any Gadget {
		                switch scope {
		                case .shell_Inner_widget_deepShell_Deep_yarn_gadget:
		                    let gadget: any Gadget = DefaultGadget(session: session)
		                    return gadget
		                }
		            }
		            return Host(__safeDI_session: session, __safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_Host)
		        }
		        let host: Host = __safeDI_host()
		        self.init(session: session, host: host)
		    }
		}
		"""])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	/// A wrapper of a place inside a `@Sendable` fill, which the seam builds around the place's builder.
	enum PlaceWrapper: CaseIterable, CustomTestStringConvertible {
		case lazilyInstantiated
		case sendableLazilyInstantiated

		var testDescription: String {
			switch self {
			case .lazilyInstantiated:
				"lazilyInstantiated"
			case .sendableLazilyInstantiated:
				"sendableLazilyInstantiated"
			}
		}

		var declaration: String {
			switch self {
			case .lazilyInstantiated:
				"@Instantiated let gadget: LazilyInstantiated<any Gadget>"
			case .sendableLazilyInstantiated:
				"@Instantiated let gadget: SendableLazilyInstantiated<any Gadget>"
			}
		}

		var hostCode: String {
			switch self {
			case .lazilyInstantiated:
				"""
				extension Host {
				    @frozen public enum SafeDISendableScope_Gadget {
				        case shell_Inner_widget_gadget(shell_Inner_widget_gadget_Values)

				        public struct shell_Inner_widget_gadget_Values {
				            public let analytics: Analytics
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public init(__safeDI_session session: Session, __safeDI_gadgetSendableBuilder: @escaping @Sendable (SafeDISendableScope_Gadget) -> any Gadget) {
				        func __safeDI_shell() -> Shell {
				            _ = Shell.__safeDI_Shell_F559842BF1A90246.self\(seamCallComment(seam: "Shell", module: "Feature"))
				            @Sendable func __safeDI_widgetSendableBuilder_Shell(_ scope: Shell.SafeDISendableScope_Widget) -> any Widget {
				                switch scope {
				                case let .innerBuilder(scope): return __safeDI_widgetBuilder_Inner(scope)
				                }
				            }
				            @Sendable func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
				                switch scope {
				                case let .widget(scope):
				                    let analytics = scope.analytics
				                    func __safeDI_widget() -> DefaultWidget {
				                        func __safeDI_gadget() -> any Gadget {
				                            __safeDI_gadgetSendableBuilder(.shell_Inner_widget_gadget(SafeDISendableScope_Gadget.shell_Inner_widget_gadget_Values(analytics: analytics)))
				                        }
				                        let gadget = LazilyInstantiated<any Gadget>(__safeDI_gadget)
				                        return DefaultWidget(analytics: analytics, gadget: gadget)
				                    }
				                    let widget: any Widget = __safeDI_widget()
				                    return widget
				                }
				            }
				            return Shell(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell)
				        }
				        let shell: Shell = __safeDI_shell()
				        self.init(session: session, shell: shell)
				    }
				}

				extension Host {
				    public enum __safeDI_Host_EA5718A38EED3127 {}
				}
				"""
			case .sendableLazilyInstantiated:
				"""
				extension Host {
				    @frozen public enum SafeDISendableScope_Gadget {
				        case shell_Inner_widget_gadget(shell_Inner_widget_gadget_Values)

				        public struct shell_Inner_widget_gadget_Values {}
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public init(__safeDI_session session: Session, __safeDI_gadgetSendableBuilder: @escaping @Sendable (SafeDISendableScope_Gadget) -> any Gadget) {
				        func __safeDI_shell() -> Shell {
				            _ = Shell.__safeDI_Shell_F559842BF1A90246.self\(seamCallComment(seam: "Shell", module: "Feature"))
				            @Sendable func __safeDI_widgetSendableBuilder_Shell(_ scope: Shell.SafeDISendableScope_Widget) -> any Widget {
				                switch scope {
				                case let .innerBuilder(scope): return __safeDI_widgetBuilder_Inner(scope)
				                }
				            }
				            @Sendable func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
				                switch scope {
				                case let .widget(scope):
				                    let analytics = scope.analytics
				                    func __safeDI_widget() -> DefaultWidget {
				                        @Sendable func __safeDI_gadget() -> any Gadget {
				                            __safeDI_gadgetSendableBuilder(.shell_Inner_widget_gadget(SafeDISendableScope_Gadget.shell_Inner_widget_gadget_Values()))
				                        }
				                        let gadget = SendableLazilyInstantiated<any Gadget>(__safeDI_gadget)
				                        return DefaultWidget(analytics: analytics, gadget: gadget)
				                    }
				                    let widget: any Widget = __safeDI_widget()
				                    return widget
				                }
				            }
				            return Shell(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell)
				        }
				        let shell: Shell = __safeDI_shell()
				        self.init(session: session, shell: shell)
				    }
				}

				extension Host {
				    public enum __safeDI_Host_A120EE0B62DD5584 {}
				}
				"""
			}
		}

		var rootCode: String {
			switch self {
			case .lazilyInstantiated:
				"""
				extension Root {
				    public init() {
				        let session = Session()
				        func __safeDI_host() -> Host {
				            _ = Host.__safeDI_Host_EA5718A38EED3127.self\(seamCallComment(seam: "Host", module: "Middle"))
				            @Sendable func __safeDI_gadgetSendableBuilder_Host(_ scope: Host.SafeDISendableScope_Gadget) -> any Gadget {
				                switch scope {
				                case .shell_Inner_widget_gadget:
				                    func __safeDI_gadget() -> DefaultGadget {
				                        DefaultGadget(session: session)
				                    }
				                    return __safeDI_gadget()
				                }
				            }
				            return Host(__safeDI_session: session, __safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_Host)
				        }
				        let host: Host = __safeDI_host()
				        self.init(session: session, host: host)
				    }
				}
				"""
			case .sendableLazilyInstantiated:
				"""
				extension Root {
				    public init() {
				        let session = Session()
				        func __safeDI_host() -> Host {
				            _ = Host.__safeDI_Host_A120EE0B62DD5584.self\(seamCallComment(seam: "Host", module: "Middle"))
				            @Sendable func __safeDI_gadgetSendableBuilder_Host(_ scope: Host.SafeDISendableScope_Gadget) -> any Gadget {
				                switch scope {
				                case .shell_Inner_widget_gadget:
				                    @Sendable func __safeDI_gadget() -> DefaultGadget {
				                        DefaultGadget(session: session)
				                    }
				                    return __safeDI_gadget()
				                }
				            }
				            return Host(__safeDI_session: session, __safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_Host)
				        }
				        let host: Host = __safeDI_host()
				        self.init(session: session, host: host)
				    }
				}
				"""
			}
		}
	}

	@Test(arguments: PlaceWrapper.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesSendableCaseOfWrapper_whenPlaceInsideSendableFillIsWrapper(wrapper: PlaceWrapper) async throws {
		let fixture = Self.fixture(route: .sendableByRoute, widgetDeclarations: ["@Received let analytics: Analytics", wrapper.declaration], appTypes: [Self.defaultGadgetReadingSession, Self.defaultGear])
		// `@unchecked`, as the fuzzer's mixed-wrapper graphs mark their types: `DefaultWidget` holds a `LazilyInstantiated`.
		let adjusted = ThreeModules(feature: fixture.feature, middle: fixture.middle.map { $0.replacingOccurrences(of: "Instantiable, Widget", with: "Instantiable, Widget, @unchecked Sendable") }, app: fixture.app, root: fixture.root)
		let output = try await executeSafeDIToolMultiModuleTest(modules: adjusted.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "Middle", imports: ["Feature"], rootFiles: ["Host": wrapper.hostCode])
		expectGeneratedCode(of: output, module: "App", imports: ["Feature", "Middle"], rootFiles: ["Root": wrapper.rootCode])
	}

	// MARK: Which fills are `@Sendable`

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresFillsSendable_whenSendableFillRefersToThemInChain() async throws {
		// `Top` takes `firstBuilder` `@Sendable`. The fill of `first` calls `SubB`, passing the fill of `second`, which calls
		// `SubC`, passing the fill of `third`: each is referred to from a `@Sendable` function that does not enclose it.
		let feature = [
			"public protocol First: Sendable {}",
			"public protocol Second: Sendable {}",
			"public protocol Third: Sendable {}",
			seamFixtureType(named: "SubA", isSeam: true, declarations: ["@Instantiated let first: any First"], conformances: ", Sendable"),
			seamFixtureType(named: "SubB", isSeam: true, declarations: ["@Instantiated let second: any Second"], conformances: ", Sendable"),
			seamFixtureType(named: "SubC", isSeam: true, declarations: ["@Instantiated let third: any Third"], conformances: ", Sendable"),
			seamFixtureType(named: "Top", isSeam: true, declarations: ["@Instantiated let subABuilder: SendableInstantiator<SubA>", "@Instantiated let subB: SubB", "@Instantiated let subC: SubC"]),
		]
		let fulfillers = [
			SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultFirst", fulfilling: "First", declarations: ["@Instantiated let subB: SubB"]),
			SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultSecond", fulfilling: "Second", declarations: ["@Instantiated let subC: SubC"]),
			SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultThird", fulfilling: "Third", declarations: []),
		]
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let top: Top"])
		let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: fulfillers + [root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "App", imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_top() -> Top {
		            _ = Top.__safeDI_Top_17CE8E8CEED8205D.self\(seamCallComment(seam: "Top", module: "Feature"))
		            @Sendable func __safeDI_firstSendableBuilder_Top(_ scope: Top.SafeDISendableScope_First) -> any First {
		                switch scope {
		                case let .subABuilder(scope): return __safeDI_firstBuilder_SubA(scope)
		                }
		            }
		            @Sendable func __safeDI_firstBuilder_SubA(_ scope: SubA.SafeDIScope_First) -> any First {
		                switch scope {
		                case .first:
		                    func __safeDI_first() -> DefaultFirst {
		                        func __safeDI_subB() -> SubB {
		                            _ = SubB.__safeDI_SubB_A7A1248AE74D4399.self\(seamCallComment(seam: "Top", module: "Feature"))
		                            return SubB(__safeDI_secondBuilder: __safeDI_secondBuilder_SubB)
		                        }
		                        let subB: SubB = __safeDI_subB()
		                        return DefaultFirst(subB: subB)
		                    }
		                    let first: any First = __safeDI_first()
		                    return first
		                }
		            }
		            func __safeDI_secondBuilder_Top(_ scope: Top.SafeDIScope_Second) -> any Second {
		                switch scope {
		                case let .subB(_, scope): return __safeDI_secondBuilder_SubB(scope)
		                }
		            }
		            @Sendable func __safeDI_secondBuilder_SubB(_ scope: SubB.SafeDIScope_Second) -> any Second {
		                switch scope {
		                case .second:
		                    func __safeDI_second() -> DefaultSecond {
		                        func __safeDI_subC() -> SubC {
		                            _ = SubC.__safeDI_SubC_001B892A3C89DF8C.self\(seamCallComment(seam: "Top", module: "Feature"))
		                            return SubC(__safeDI_thirdBuilder: __safeDI_thirdBuilder_SubC)
		                        }
		                        let subC: SubC = __safeDI_subC()
		                        return DefaultSecond(subC: subC)
		                    }
		                    let second: any Second = __safeDI_second()
		                    return second
		                }
		            }
		            func __safeDI_thirdBuilder_Top(_ scope: Top.SafeDIScope_Third) -> any Third {
		                switch scope {
		                case let .subC(_, scope): return __safeDI_thirdBuilder_SubC(scope)
		                }
		            }
		            @Sendable func __safeDI_thirdBuilder_SubC(_ scope: SubC.SafeDIScope_Third) -> any Third {
		                switch scope {
		                case .third:
		                    let third: any Third = DefaultThird()
		                    return third
		                }
		            }
		            return Top(__safeDI_firstSendableBuilder: __safeDI_firstSendableBuilder_Top, __safeDI_secondBuilder: __safeDI_secondBuilder_Top, __safeDI_thirdBuilder: __safeDI_thirdBuilder_Top)
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}
		"""])
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature + fulfillers, app: [root]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresEnclosingCallsFillSendable_whenSendableFillOfCallInsideAnotherFillRefersToIt() async throws {
		// `App`'s fill of `third`, declared for the call of `ThirdShell` inside the fill of `first`, is `@Sendable` because
		// `ThirdShell` takes it so. It calls `SubB`, passing the fill of `second`, of the enclosing call of `Top`, which it does
		// not enclose: `second`'s fill is `@Sendable` while `first`'s, which encloses the reference, stays plain.
		let feature = [
			"public protocol First: Sendable {}",
			"public protocol Second: Sendable {}",
			"public protocol Third: Sendable {}",
			seamFixtureType(named: "SubA", isSeam: true, declarations: ["@Instantiated let first: any First"], conformances: ", Sendable"),
			seamFixtureType(named: "SubB", isSeam: true, declarations: ["@Instantiated let second: any Second"], conformances: ", Sendable"),
			seamFixtureType(named: "SubC", isSeam: true, declarations: ["@Instantiated let third: any Third"], conformances: ", Sendable"),
			seamFixtureType(named: "ThirdShell", isSeam: true, declarations: ["@Instantiated let subCBuilder: SendableInstantiator<SubC>"], conformances: ", Sendable"),
			seamFixtureType(named: "Top", isSeam: true, declarations: ["@Instantiated let subA: SubA", "@Instantiated let subB: SubB"]),
		]
		let fulfillers = [
			SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultFirst", fulfilling: "First", declarations: ["@Instantiated let thirdShell: ThirdShell"]),
			SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultSecond", fulfilling: "Second", declarations: []),
			SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultThird", fulfilling: "Third", declarations: ["@Instantiated let subB: SubB"]),
		]
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let top: Top"])
		let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: fulfillers + [root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "App", imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_top() -> Top {
		            _ = Top.__safeDI_Top_9F8DEF3089EB537C.self\(seamCallComment(seam: "Top", module: "Feature"))
		            func __safeDI_firstBuilder_Top(_ scope: Top.SafeDIScope_First) -> any First {
		                switch scope {
		                case let .subA(_, scope): return __safeDI_firstBuilder_SubA(scope)
		                }
		            }
		            func __safeDI_firstBuilder_SubA(_ scope: SubA.SafeDIScope_First) -> any First {
		                switch scope {
		                case .first:
		                    func __safeDI_first() -> DefaultFirst {
		                        func __safeDI_thirdShell() -> ThirdShell {
		                            _ = ThirdShell.__safeDI_ThirdShell_1B67A58944CFBC72.self\(seamCallComment(seam: "Top", module: "Feature"))
		                            @Sendable func __safeDI_thirdSendableBuilder_ThirdShell(_ scope: ThirdShell.SafeDISendableScope_Third) -> any Third {
		                                switch scope {
		                                case let .subCBuilder(scope): return __safeDI_thirdBuilder_SubC(scope)
		                                }
		                            }
		                            @Sendable func __safeDI_thirdBuilder_SubC(_ scope: SubC.SafeDIScope_Third) -> any Third {
		                                switch scope {
		                                case .third:
		                                    func __safeDI_third() -> DefaultThird {
		                                        func __safeDI_subB() -> SubB {
		                                            _ = SubB.__safeDI_SubB_A7A1248AE74D4399.self\(seamCallComment(seam: "Top", module: "Feature"))
		                                            return SubB(__safeDI_secondBuilder: __safeDI_secondBuilder_SubB)
		                                        }
		                                        let subB: SubB = __safeDI_subB()
		                                        return DefaultThird(subB: subB)
		                                    }
		                                    let third: any Third = __safeDI_third()
		                                    return third
		                                }
		                            }
		                            return ThirdShell(__safeDI_thirdSendableBuilder: __safeDI_thirdSendableBuilder_ThirdShell)
		                        }
		                        let thirdShell: ThirdShell = __safeDI_thirdShell()
		                        return DefaultFirst(thirdShell: thirdShell)
		                    }
		                    let first: any First = __safeDI_first()
		                    return first
		                }
		            }
		            func __safeDI_secondBuilder_Top(_ scope: Top.SafeDIScope_Second) -> any Second {
		                switch scope {
		                case let .subB(_, scope): return __safeDI_secondBuilder_SubB(scope)
		                }
		            }
		            @Sendable func __safeDI_secondBuilder_SubB(_ scope: SubB.SafeDIScope_Second) -> any Second {
		                switch scope {
		                case .second:
		                    let second: any Second = DefaultSecond()
		                    return second
		                }
		            }
		            return Top(__safeDI_firstBuilder: __safeDI_firstBuilder_Top, __safeDI_secondBuilder: __safeDI_secondBuilder_Top)
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}
		"""])
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature + fulfillers, app: [root]))
	}

	// MARK: What a seam reads beside a `@Sendable` fill

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsDeferredParameterPlain_whenOnlyPlaceInsideSendableFillReadsIt() async throws {
		// `gadget`'s first stage carries `user`, `Host`'s deferred parameter, and is called before the `@Sendable` fill, so
		// `Host` takes it as a plain autoclosure. `DefaultGadget` is built in a later stage, so `App`'s fill reads `Root`'s
		// declaration inside a `@Sendable` function, as inline, which is why it is the `Sendable` wrapper.
		let fixture = ThreeModules(
			feature: FillRoute.sendableByRoute.featureTypes,
			middle: [Self.gadget, seamFixtureType(named: "User", declarations: [], conformances: ", Sendable"), seamFixtureType(named: "Session", declarations: ["@Received let user: User"], conformances: ", Sendable")] + [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: ["@Instantiated let gadget: any Gadget"]),
				seamFixtureType(named: "Host", isSeam: true, declarations: ["@Received let session: Session", FillRoute.sendableByRoute.hostDeclaration]),
			],
			app: [SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultGadget", fulfilling: "Gadget", declarations: ["@Received let user: User"])],
			root: seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let session: Session", "@Instantiated let user: SendableLazilyInstantiated<User>", "@Instantiated let host: Host"]),
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "Middle", imports: ["Feature"], rootFiles: ["Host": """
		extension Host {
		    @frozen public enum SafeDISendableScope_Gadget {
		        case shell_Inner_widget_gadget(shell_Inner_widget_gadget_Values)

		        public struct shell_Inner_widget_gadget_Values {
		            public let analytics: Analytics
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_session session: Session, __safeDI_gadgetSendableBuilder: @escaping @Sendable (SafeDISendableScope_Gadget) -> any Gadget) {
		        func __safeDI_shell() -> Shell {
		            _ = Shell.__safeDI_Shell_F559842BF1A90246.self\(seamCallComment(seam: "Shell", module: "Feature"))
		            @Sendable func __safeDI_widgetSendableBuilder_Shell(_ scope: Shell.SafeDISendableScope_Widget) -> any Widget {
		                switch scope {
		                case let .innerBuilder(scope): return __safeDI_widgetBuilder_Inner(scope)
		                }
		            }
		            @Sendable func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
		                switch scope {
		                case let .widget(scope):
		                    let analytics = scope.analytics
		                    func __safeDI_widget() -> DefaultWidget {
		                        let gadget: any Gadget = __safeDI_gadgetSendableBuilder(.shell_Inner_widget_gadget(SafeDISendableScope_Gadget.shell_Inner_widget_gadget_Values(analytics: analytics)))
		                        return DefaultWidget(gadget: gadget)
		                    }
		                    let widget: any Widget = __safeDI_widget()
		                    return widget
		                }
		            }
		            return Shell(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell)
		        }
		        let shell: Shell = __safeDI_shell()
		        self.init(session: session, shell: shell)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_EA5718A38EED3127 {}
		}
		"""])
		expectGeneratedCode(of: output, module: "App", imports: ["Feature", "Middle"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        @Sendable func __safeDI_user() -> User {
		            User()
		        }
		        let user = SendableLazilyInstantiated<User>(__safeDI_user)
		        let session = Session(user: user.instance)
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_EA5718A38EED3127.self\(seamCallComment(seam: "Host", module: "Middle"))
		            @Sendable func __safeDI_gadgetSendableBuilder_Host(_ scope: Host.SafeDISendableScope_Gadget) -> any Gadget {
		                switch scope {
		                case .shell_Inner_widget_gadget:
		                    let gadget: any Gadget = DefaultGadget(user: user.instance)
		                    return gadget
		                }
		            }
		            return Host(__safeDI_session: session, __safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_Host)
		        }
		        let host: Host = __safeDI_host()
		        self.init(session: session, user: user, host: host)
		    }
		}
		"""])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesOwnBuilderSendable_whenCallInsideSendableFillReentersSeam() async throws {
		// A call of `Host` inside the `@Sendable` fill, in a plain `Instantiator`, passes the builder `Host` takes for its own
		// `gadget`, which the fill captures.
		let fixture = ThreeModules(
			feature: FillRoute.sendableByRoute.featureTypes,
			middle: [
				Self.gadget,
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: ["@Instantiated let hostBuilder: Instantiator<Host>"])
					.replacingOccurrences(of: "Instantiable, Widget", with: "Instantiable, Widget, @unchecked Sendable"),
				seamFixtureType(named: "Host", isSeam: true, declarations: ["@Instantiated let gadget: any Gadget", FillRoute.sendableByRoute.hostDeclaration], conformances: ", @unchecked Sendable"),
			],
			app: [SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultGadget", fulfilling: "Gadget", declarations: [])],
			root: Self.root,
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "Middle", imports: ["Feature"], rootFiles: ["Host": """
		extension Host {
		    @frozen public enum SafeDIScope_Gadget {
		        case gadget(gadget_Values)

		        public struct gadget_Values {
		            public let shell: Shell
		        }
		    }

		    @frozen public enum SafeDISendableScope_Gadget {
		        case shell_Inner_widget_hostBuilder(Host.SafeDIScope_Gadget)
		        indirect case shell_Inner_widget_hostBuilder_Sendable(Host.SafeDISendableScope_Gadget)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_gadgetBuilder: @escaping (SafeDIScope_Gadget) -> any Gadget, __safeDI_gadgetSendableBuilder: @escaping @Sendable (SafeDISendableScope_Gadget) -> any Gadget) {
		        func __safeDI_shell() -> Shell {
		            _ = Shell.__safeDI_Shell_F559842BF1A90246.self\(seamCallComment(seam: "Shell", module: "Feature"))
		            @Sendable func __safeDI_widgetSendableBuilder_Shell(_ scope: Shell.SafeDISendableScope_Widget) -> any Widget {
		                switch scope {
		                case let .innerBuilder(scope): return __safeDI_widgetBuilder_Inner(scope)
		                }
		            }
		            @Sendable func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
		                switch scope {
		                case .widget:
		                    func __safeDI_widget() -> DefaultWidget {
		                        func __safeDI_hostBuilder() -> Host {
		                            _ = Host.__safeDI_Host_E4A10F533350FBBA.self
		                            return Host(__safeDI_gadgetBuilder: { __safeDI_gadgetSendableBuilder(.shell_Inner_widget_hostBuilder($0)) }, __safeDI_gadgetSendableBuilder: { __safeDI_gadgetSendableBuilder(.shell_Inner_widget_hostBuilder_Sendable($0)) })
		                        }
		                        let hostBuilder = Instantiator<Host>(__safeDI_hostBuilder)
		                        return DefaultWidget(hostBuilder: hostBuilder)
		                    }
		                    let widget: any Widget = __safeDI_widget()
		                    return widget
		                }
		            }
		            return Shell(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell)
		        }
		        let shell: Shell = __safeDI_shell()
		        let gadget: any Gadget = __safeDI_gadgetBuilder(.gadget(SafeDIScope_Gadget.gadget_Values(shell: shell)))
		        self.init(gadget: gadget, shell: shell)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_E4A10F533350FBBA {}
		}
		"""])
		expectGeneratedCode(of: output, module: "App", imports: ["Feature", "Middle"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_E4A10F533350FBBA.self\(seamCallComment(seam: "Host", module: "Middle"))
		            @Sendable func __safeDI_gadgetBuilder_Host(_ scope: Host.SafeDIScope_Gadget) -> any Gadget {
		                switch scope {
		                case .gadget:
		                    let gadget: any Gadget = DefaultGadget()
		                    return gadget
		                }
		            }
		            @Sendable func __safeDI_gadgetSendableBuilder_Host(_ scope: Host.SafeDISendableScope_Gadget) -> any Gadget {
		                switch scope {
		                case let .shell_Inner_widget_hostBuilder(scope): return __safeDI_gadgetBuilder_Host(scope)
		                case let .shell_Inner_widget_hostBuilder_Sendable(scope): return __safeDI_gadgetSendableBuilder_Host(scope)
		                }
		            }
		            return Host(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Host, __safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_Host)
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
	}

	// MARK: Shapes beside these, which compiled before a fill counted as a `@Sendable` function

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsPlaceInPlainEnum_whenPlaceIsBeneathPlainInstantiatorInsidePlainFill() async throws {
		let fixture = Self.fixture(
			route: .plain,
			middleTypes: [seamFixtureType(named: "Holder", declarations: ["@Received let analytics: Analytics", "@Instantiated let gadget: any Gadget"])],
			widgetDeclarations: ["@Received let analytics: Analytics", "@Instantiated let holderBuilder: Instantiator<Holder>"],
		)
		let adjusted = ThreeModules(feature: fixture.feature, middle: fixture.middle.map { $0.replacingOccurrences(of: "Instantiable, Widget", with: "Instantiable, Widget, @unchecked Sendable") }, app: fixture.app, root: fixture.root)
		let output = try await executeSafeDIToolMultiModuleTest(modules: adjusted.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "Middle", imports: ["Feature"], rootFiles: ["Host": """
		extension Host {
		    @frozen public enum SafeDIScope_Gadget {
		        case inner_widget_holderBuilder_gadget(inner_widget_holderBuilder_gadget_Values)

		        public struct inner_widget_holderBuilder_gadget_Values {
		            public let session: Session
		            public let analytics: Analytics
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_session session: Session, __safeDI_gadgetBuilder: @escaping (SafeDIScope_Gadget) -> any Gadget) {
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_318A87E8A50EC522.self\(seamCallComment(seam: "Inner", module: "Feature"))
		            func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
		                switch scope {
		                case let .widget(scope):
		                    let analytics = scope.analytics
		                    func __safeDI_widget() -> DefaultWidget {
		                        func __safeDI_holderBuilder() -> Holder {
		                            let gadget: any Gadget = __safeDI_gadgetBuilder(.inner_widget_holderBuilder_gadget(SafeDIScope_Gadget.inner_widget_holderBuilder_gadget_Values(session: session, analytics: analytics)))
		                            return Holder(analytics: analytics, gadget: gadget)
		                        }
		                        let holderBuilder = Instantiator<Holder>(__safeDI_holderBuilder)
		                        return DefaultWidget(analytics: analytics, holderBuilder: holderBuilder)
		                    }
		                    let widget: any Widget = __safeDI_widget()
		                    return widget
		                }
		            }
		            return Inner(__safeDI_widgetBuilder: __safeDI_widgetBuilder_Inner)
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(session: session, inner: inner)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_2128A7095B153AAF {}
		}
		"""])
		expectGeneratedCode(of: output, module: "App", imports: ["Feature", "Middle"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        let session = Session()
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_2128A7095B153AAF.self\(seamCallComment(seam: "Host", module: "Middle"))
		            func __safeDI_gadgetBuilder_Host(_ scope: Host.SafeDIScope_Gadget) -> any Gadget {
		                switch scope {
		                case let .inner_widget_holderBuilder_gadget(scope):
		                    let session = scope.session
		                    let analytics = scope.analytics
		                    let gadget: any Gadget = DefaultGadget(session: session, analytics: analytics)
		                    return gadget
		                }
		            }
		            return Host(__safeDI_session: session, __safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Host)
		        }
		        let host: Host = __safeDI_host()
		        self.init(session: session, host: host)
		    }
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesSendableCase_whenPlaceIsBeneathSendableBuilderFunctionInsidePlainFill() async throws {
		let fixture = Self.fixture(
			route: .plain,
			middleTypes: [seamFixtureType(named: "Holder", declarations: ["@Instantiated let analytics: Analytics", "@Instantiated let gadget: any Gadget"], conformances: ", Sendable")],
			widgetDeclarations: ["@Received let analytics: Analytics", "@Instantiated let holderBuilder: SendableInstantiator<Holder>"],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "Middle", imports: ["Feature"], rootFiles: ["Host": """
		extension Host {
		    @frozen public enum SafeDISendableScope_Gadget {
		        case inner_widget_holderBuilder_gadget(inner_widget_holderBuilder_gadget_Values)

		        public struct inner_widget_holderBuilder_gadget_Values {
		            public let analytics: Analytics
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_session session: Session, __safeDI_gadgetSendableBuilder: @escaping @Sendable (SafeDISendableScope_Gadget) -> any Gadget) {
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_318A87E8A50EC522.self\(seamCallComment(seam: "Inner", module: "Feature"))
		            func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
		                switch scope {
		                case let .widget(scope):
		                    let analytics = scope.analytics
		                    func __safeDI_widget() -> DefaultWidget {
		                        @Sendable func __safeDI_holderBuilder() -> Holder {
		                            let analytics = Analytics()
		                            let gadget: any Gadget = __safeDI_gadgetSendableBuilder(.inner_widget_holderBuilder_gadget(SafeDISendableScope_Gadget.inner_widget_holderBuilder_gadget_Values(analytics: analytics)))
		                            return Holder(analytics: analytics, gadget: gadget)
		                        }
		                        let holderBuilder = SendableInstantiator<Holder>(__safeDI_holderBuilder)
		                        return DefaultWidget(analytics: analytics, holderBuilder: holderBuilder)
		                    }
		                    let widget: any Widget = __safeDI_widget()
		                    return widget
		                }
		            }
		            return Inner(__safeDI_widgetBuilder: __safeDI_widgetBuilder_Inner)
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(session: session, inner: inner)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_F1BCF68389F1787A {}
		}
		"""])
		expectGeneratedCode(of: output, module: "App", imports: ["Feature", "Middle"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        let session = Session()
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_F1BCF68389F1787A.self\(seamCallComment(seam: "Host", module: "Middle"))
		            @Sendable func __safeDI_gadgetSendableBuilder_Host(_ scope: Host.SafeDISendableScope_Gadget) -> any Gadget {
		                switch scope {
		                case let .inner_widget_holderBuilder_gadget(scope):
		                    let analytics = scope.analytics
		                    let gadget: any Gadget = DefaultGadget(session: session, analytics: analytics)
		                    return gadget
		                }
		            }
		            return Host(__safeDI_session: session, __safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_Host)
		        }
		        let host: Host = __safeDI_host()
		        self.init(session: session, host: host)
		    }
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsNestedFillPlain_whenSendableFillCallsSeamItFillsItself() async throws {
		// `Middle` also sees `DefaultGear`, so the fill calls `Part` with a fill of its own, which nothing refers to from a
		// `@Sendable` function it does not enclose.
		let fixture = Self.fixture(
			route: .sendableByRoute,
			middleTypes: [Self.defaultGear],
			widgetDeclarations: ["@Instantiated let part: Part"],
			appTypes: [],
			root: Self.rootWithSession,
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "Middle", imports: ["Feature"], rootFiles: ["Host": """
		extension Host {
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_session session: Session) {
		        func __safeDI_shell() -> Shell {
		            _ = Shell.__safeDI_Shell_F559842BF1A90246.self\(seamCallComment(seam: "Shell", module: "Feature"))
		            @Sendable func __safeDI_widgetSendableBuilder_Shell(_ scope: Shell.SafeDISendableScope_Widget) -> any Widget {
		                switch scope {
		                case let .innerBuilder(scope): return __safeDI_widgetBuilder_Inner(scope)
		                }
		            }
		            @Sendable func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
		                switch scope {
		                case .widget:
		                    func __safeDI_widget() -> DefaultWidget {
		                        func __safeDI_part() -> Part {
		                            _ = Part.__safeDI_Part_F870B0D7B6455852.self\(seamCallComment(seam: "Shell", module: "Feature"))
		                            func __safeDI_gearBuilder_Part(_ scope: Part.SafeDIScope_Gear) -> any Gear {
		                                switch scope {
		                                case .gear:
		                                    let gear: any Gear = DefaultGear()
		                                    return gear
		                                }
		                            }
		                            return Part(__safeDI_gearBuilder: __safeDI_gearBuilder_Part)
		                        }
		                        let part: Part = __safeDI_part()
		                        return DefaultWidget(part: part)
		                    }
		                    let widget: any Widget = __safeDI_widget()
		                    return widget
		                }
		            }
		            return Shell(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell)
		        }
		        let shell: Shell = __safeDI_shell()
		        self.init(session: session, shell: shell)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_13A4BC800B514232 {}
		}
		"""])
		expectGeneratedCode(of: output, module: "App", imports: ["Feature", "Middle"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        let session = Session()
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_13A4BC800B514232.self\(seamCallComment(seam: "Host", module: "Middle"))
		            return Host(__safeDI_session: session)
		        }
		        let host: Host = __safeDI_host()
		        self.init(session: session, host: host)
		    }
		}
		"""])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsSendablePlaceWithPlainBody_whenFillHoldsNoPlaceOrCall() async throws {
		let fixture = Self.fixture(route: .placeInsideSendableFunction, widgetDeclarations: ["@Received let analytics: Analytics", "@Received let clock: Clock"], appTypes: [])
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "Middle", imports: ["Feature"], rootFiles: ["Host": """
		extension Host {
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_session session: Session) {
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_6288FB023CC267A8.self\(seamCallComment(seam: "Inner", module: "Feature"))
		            @Sendable func __safeDI_widgetSendableBuilder_Inner(_ scope: Inner.SafeDISendableScope_Widget) -> any Widget {
		                switch scope {
		                case let .panelBuilder(scope): return __safeDI_widgetBuilder_Inner_Panel_Scope(scope)
		                }
		            }
		            @Sendable func __safeDI_widgetBuilder_Inner_Panel_Scope(_ scope: Inner.SafeDIScope_Widget.Panel_Scope) -> any Widget {
		                switch scope {
		                case let .widget(scope):
		                    let analytics = scope.analytics
		                    let clock = scope.clock
		                    let widget: any Widget = DefaultWidget(analytics: analytics, clock: clock)
		                    return widget
		                }
		            }
		            return Inner(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Inner)
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(session: session, inner: inner)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_13A4BC800B514232 {}
		}
		"""])
		expectGeneratedCode(of: output, module: "App", imports: ["Feature", "Middle"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        let session = Session()
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_13A4BC800B514232.self\(seamCallComment(seam: "Host", module: "Middle"))
		            return Host(__safeDI_session: session)
		        }
		        let host: Host = __safeDI_host()
		        self.init(session: session, host: host)
		    }
		}
		"""])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	// MARK: A fill no `@Sendable` function outside it refers to

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsFillPlain_whenPlainFillInsideSendableBuilderFunctionIsAllThatRefersToIt() async throws {
		// `Host` calls `Top` in a `SendableInstantiator`, whose builder function declares both fills. The plain fill of
		// `first` passes the fill of `second` to `SubB`, and that builder function encloses both, so neither is `@Sendable`
		// and `gadget`, a place inside the fill of `second`, takes no stage for it.
		let fixture = ThreeModules(
			feature: [
				"public protocol First: Sendable {}",
				"public protocol Second: Sendable {}",
				seamFixtureType(named: "SubA", isSeam: true, declarations: ["@Instantiated let first: any First"], conformances: ", Sendable"),
				seamFixtureType(named: "SubB", isSeam: true, declarations: ["@Instantiated let second: any Second"], conformances: ", Sendable"),
				seamFixtureType(named: "Top", isSeam: true, declarations: ["@Instantiated let subA: SubA", "@Instantiated let subB: SubB"], conformances: ", Sendable"),
			],
			middle: [
				Self.gadget,
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultFirst", fulfilling: "First", declarations: ["@Instantiated let subB: SubB"]),
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultSecond", fulfilling: "Second", declarations: ["@Instantiated let gadget: any Gadget"]),
				seamFixtureType(named: "Host", isSeam: true, declarations: ["@Instantiated let topBuilder: SendableInstantiator<Top>"]),
			],
			app: [SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultGadget", fulfilling: "Gadget", declarations: [])],
			root: Self.root,
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "Middle", imports: ["Feature"], rootFiles: ["Host": """
		extension Host {
		    @frozen public enum SafeDISendableScope_Gadget {
		        case topBuilder_SubB_second_gadget(topBuilder_SubB_second_gadget_Values)

		        public struct topBuilder_SubB_second_gadget_Values {}
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_gadgetSendableBuilder: @escaping @Sendable (SafeDISendableScope_Gadget) -> any Gadget) {
		        @Sendable func __safeDI_topBuilder() -> Top {
		            _ = Top.__safeDI_Top_9F8DEF3089EB537C.self\(seamCallComment(seam: "Top", module: "Feature"))
		            func __safeDI_firstBuilder_Top(_ scope: Top.SafeDIScope_First) -> any First {
		                switch scope {
		                case let .subA(_, scope): return __safeDI_firstBuilder_SubA(scope)
		                }
		            }
		            func __safeDI_firstBuilder_SubA(_ scope: SubA.SafeDIScope_First) -> any First {
		                switch scope {
		                case .first:
		                    func __safeDI_first() -> DefaultFirst {
		                        func __safeDI_subB() -> SubB {
		                            _ = SubB.__safeDI_SubB_A7A1248AE74D4399.self\(seamCallComment(seam: "Top", module: "Feature"))
		                            return SubB(__safeDI_secondBuilder: __safeDI_secondBuilder_SubB)
		                        }
		                        let subB: SubB = __safeDI_subB()
		                        return DefaultFirst(subB: subB)
		                    }
		                    let first: any First = __safeDI_first()
		                    return first
		                }
		            }
		            func __safeDI_secondBuilder_Top(_ scope: Top.SafeDIScope_Second) -> any Second {
		                switch scope {
		                case let .subB(_, scope): return __safeDI_secondBuilder_SubB(scope)
		                }
		            }
		            func __safeDI_secondBuilder_SubB(_ scope: SubB.SafeDIScope_Second) -> any Second {
		                switch scope {
		                case .second:
		                    func __safeDI_second() -> DefaultSecond {
		                        let gadget: any Gadget = __safeDI_gadgetSendableBuilder(.topBuilder_SubB_second_gadget(SafeDISendableScope_Gadget.topBuilder_SubB_second_gadget_Values()))
		                        return DefaultSecond(gadget: gadget)
		                    }
		                    let second: any Second = __safeDI_second()
		                    return second
		                }
		            }
		            return Top(__safeDI_firstBuilder: __safeDI_firstBuilder_Top, __safeDI_secondBuilder: __safeDI_secondBuilder_Top)
		        }
		        let topBuilder = SendableInstantiator<Top>(__safeDI_topBuilder)
		        self.init(topBuilder: topBuilder)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_222D4FA258901317 {}
		}
		"""])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresEnclosingCallsFillSendable_whenCallInSendableBuilderFunctionInsidePlainFillPassesIt() async throws {
		// The fill of `first` is plain, but it calls `SubB` in a `SendableInstantiator`: that builder function does not
		// enclose the fill of `second`, which it passes.
		let feature = [
			"public protocol First: Sendable {}",
			"public protocol Second: Sendable {}",
			seamFixtureType(named: "SubA", isSeam: true, declarations: ["@Instantiated let first: any First"], conformances: ", Sendable"),
			seamFixtureType(named: "SubB", isSeam: true, declarations: ["@Instantiated let second: any Second"], conformances: ", Sendable"),
			seamFixtureType(named: "Top", isSeam: true, declarations: ["@Instantiated let subA: SubA", "@Instantiated let subB: SubB"]),
		]
		let fulfillers = [
			SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultFirst", fulfilling: "First", declarations: ["@Instantiated let subBBuilder: SendableInstantiator<SubB>"]),
			SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultSecond", fulfilling: "Second", declarations: []),
		]
		let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: fulfillers + [seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let top: Top"])])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "App", imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_top() -> Top {
		            _ = Top.__safeDI_Top_9F8DEF3089EB537C.self\(seamCallComment(seam: "Top", module: "Feature"))
		            func __safeDI_firstBuilder_Top(_ scope: Top.SafeDIScope_First) -> any First {
		                switch scope {
		                case let .subA(_, scope): return __safeDI_firstBuilder_SubA(scope)
		                }
		            }
		            func __safeDI_firstBuilder_SubA(_ scope: SubA.SafeDIScope_First) -> any First {
		                switch scope {
		                case .first:
		                    func __safeDI_first() -> DefaultFirst {
		                        @Sendable func __safeDI_subBBuilder() -> SubB {
		                            _ = SubB.__safeDI_SubB_A7A1248AE74D4399.self\(seamCallComment(seam: "Top", module: "Feature"))
		                            return SubB(__safeDI_secondBuilder: __safeDI_secondBuilder_SubB)
		                        }
		                        let subBBuilder = SendableInstantiator<SubB>(__safeDI_subBBuilder)
		                        return DefaultFirst(subBBuilder: subBBuilder)
		                    }
		                    let first: any First = __safeDI_first()
		                    return first
		                }
		            }
		            func __safeDI_secondBuilder_Top(_ scope: Top.SafeDIScope_Second) -> any Second {
		                switch scope {
		                case let .subB(_, scope): return __safeDI_secondBuilder_SubB(scope)
		                }
		            }
		            @Sendable func __safeDI_secondBuilder_SubB(_ scope: SubB.SafeDIScope_Second) -> any Second {
		                switch scope {
		                case .second:
		                    let second: any Second = DefaultSecond()
		                    return second
		                }
		            }
		            return Top(__safeDI_firstBuilder: __safeDI_firstBuilder_Top, __safeDI_secondBuilder: __safeDI_secondBuilder_Top)
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}
		"""])
	}

	// MARK: A place in a `@Sendable` fill whose builder is `@Sendable` for another reason

	/// `Host`, which holds `hostDeclarations`, calls `Shell` with a fill by `DefaultWidget`, which holds `widgetDeclarations`
	/// and builds `gadget`, a place of `Host`, inside a `@Sendable` function.
	private static func fixtureOfSendableFillWithPlace(
		widgetConformances: String = "Instantiable, Widget",
		widgetDeclarations: [String] = ["@Received let analytics: Analytics", "@Instantiated let gadget: any Gadget"],
		middleTypes: [String] = [],
		hostDeclarations: [String] = ["@Received let session: Session", FillRoute.sendableByRoute.hostDeclaration],
		session sessionType: String = session,
		hostConformances: String = ", Sendable",
		gadgetDeclarations: [String] = ["@Received let session: Session", "@Received let analytics: Analytics"],
		root: String = rootWithSession,
	) -> ThreeModules {
		ThreeModules(
			feature: FillRoute.sendableByRoute.featureTypes,
			middle: [gadget, sessionType] + middleTypes + [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: widgetDeclarations)
					.replacingOccurrences(of: "Instantiable, Widget", with: widgetConformances),
				seamFixtureType(named: "Host", isSeam: true, declarations: hostDeclarations, conformances: hostConformances),
			],
			app: [SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultGadget", fulfilling: "Gadget", declarations: gadgetDeclarations)],
			root: root,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesSendableCase_whenBuilderIsSendableBecauseSeamCalledInFillPassesItBackSendable() async throws {
		// `Other`, called in the fill, re-enters `Host` in a `SendableInstantiator`, so it takes `gadgetBuilder` `@Sendable`.
		let fixture = Self.fixtureOfSendableFillWithPlace(
			widgetConformances: "Instantiable, Widget, @unchecked Sendable",
			widgetDeclarations: ["@Received let analytics: Analytics", "@Instantiated let gadget: any Gadget", "@Instantiated let otherBuilder: Instantiator<Other>"],
			middleTypes: [seamFixtureType(named: "Other", isSeam: true, declarations: ["@Instantiated let hostBuilder: SendableInstantiator<Host>"], conformances: ", Sendable")],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "Middle", imports: ["Feature"], rootFiles: [
			"Host": """
			extension Host {
			    @frozen public enum SafeDISendableScope_Gadget {
			        indirect case shell_Inner_widget_otherBuilder_Sendable(Other.SafeDISendableScope_Gadget)
			        case shell_Inner_widget_gadget(shell_Inner_widget_gadget_Values)

			        public struct shell_Inner_widget_gadget_Values {
			            public let analytics: Analytics
			            public let otherBuilder: Instantiator<Other>
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_session session: Session, __safeDI_gadgetSendableBuilder: @escaping @Sendable (SafeDISendableScope_Gadget) -> any Gadget) {
			        func __safeDI_shell() -> Shell {
			            _ = Shell.__safeDI_Shell_F559842BF1A90246.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            @Sendable func __safeDI_widgetSendableBuilder_Shell(_ scope: Shell.SafeDISendableScope_Widget) -> any Widget {
			                switch scope {
			                case let .innerBuilder(scope): return __safeDI_widgetBuilder_Inner(scope)
			                }
			            }
			            @Sendable func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
			                switch scope {
			                case let .widget(scope):
			                    let analytics = scope.analytics
			                    func __safeDI_widget() -> DefaultWidget {
			                        func __safeDI_otherBuilder() -> Other {
			                            _ = Other.__safeDI_Other_A493C677F6EE0739.self
			                            return Other(__safeDI_session: session, __safeDI_gadgetSendableBuilder: { __safeDI_gadgetSendableBuilder(.shell_Inner_widget_otherBuilder_Sendable($0)) })
			                        }
			                        let otherBuilder = Instantiator<Other>(__safeDI_otherBuilder)
			                        let gadget: any Gadget = __safeDI_gadgetSendableBuilder(.shell_Inner_widget_gadget(SafeDISendableScope_Gadget.shell_Inner_widget_gadget_Values(analytics: analytics, otherBuilder: otherBuilder)))
			                        return DefaultWidget(analytics: analytics, gadget: gadget, otherBuilder: otherBuilder)
			                    }
			                    let widget: any Widget = __safeDI_widget()
			                    return widget
			                }
			            }
			            return Shell(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell)
			        }
			        let shell: Shell = __safeDI_shell()
			        self.init(session: session, shell: shell)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_319305560F2D1907 {}
			}
			""",
			"Other": """
			extension Other {
			    @frozen public enum SafeDISendableScope_Gadget {
			        indirect case hostBuilder_Sendable(Host.SafeDISendableScope_Gadget)
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_session: @autoclosure @escaping @Sendable () -> Session, __safeDI_gadgetSendableBuilder: @escaping @Sendable (SafeDISendableScope_Gadget) -> any Gadget) {
			        let session = SendableLazilyInstantiated<Session>(__safeDI_session)
			        @Sendable func __safeDI_hostBuilder() -> Host {
			            _ = Host.__safeDI_Host_319305560F2D1907.self
			            return Host(__safeDI_session: session.instance, __safeDI_gadgetSendableBuilder: { __safeDI_gadgetSendableBuilder(.hostBuilder_Sendable($0)) })
			        }
			        let hostBuilder = SendableInstantiator<Host>(__safeDI_hostBuilder)
			        self.init(hostBuilder: hostBuilder)
			    }
			}

			extension Other {
			    public enum __safeDI_Other_A493C677F6EE0739 {}
			}
			""",
		])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesSendableCase_whenOnlyThatFillMakesBuilderSendable() async throws {
		// The call of `Host` inside the fill is in a plain `Instantiator`, so only the fill's own `@Sendable` function makes
		// the builder `@Sendable`, and `gadget` is staged there.
		let fixture = Self.fixtureOfSendableFillWithPlace(
			widgetConformances: "Instantiable, Widget, @unchecked Sendable",
			widgetDeclarations: ["@Received let analytics: Analytics", "@Instantiated let gadget: any Gadget", "@Instantiated let hostBuilder: Instantiator<Host>"],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "Middle", imports: ["Feature"], rootFiles: ["Host": """
		extension Host {
		    @frozen public enum SafeDISendableScope_Gadget {
		        indirect case shell_Inner_widget_hostBuilder_Sendable(Host.SafeDISendableScope_Gadget)
		        case shell_Inner_widget_gadget(shell_Inner_widget_gadget_Values)

		        public struct shell_Inner_widget_gadget_Values {
		            public let analytics: Analytics
		            public let hostBuilder: Instantiator<Host>
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_session session: Session, __safeDI_gadgetSendableBuilder: @escaping @Sendable (SafeDISendableScope_Gadget) -> any Gadget) {
		        func __safeDI_shell() -> Shell {
		            _ = Shell.__safeDI_Shell_F559842BF1A90246.self\(seamCallComment(seam: "Shell", module: "Feature"))
		            @Sendable func __safeDI_widgetSendableBuilder_Shell(_ scope: Shell.SafeDISendableScope_Widget) -> any Widget {
		                switch scope {
		                case let .innerBuilder(scope): return __safeDI_widgetBuilder_Inner(scope)
		                }
		            }
		            @Sendable func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
		                switch scope {
		                case let .widget(scope):
		                    let analytics = scope.analytics
		                    func __safeDI_widget() -> DefaultWidget {
		                        func __safeDI_hostBuilder() -> Host {
		                            _ = Host.__safeDI_Host_674A357FFC04F698.self
		                            return Host(__safeDI_session: session, __safeDI_gadgetSendableBuilder: { __safeDI_gadgetSendableBuilder(.shell_Inner_widget_hostBuilder_Sendable($0)) })
		                        }
		                        let hostBuilder = Instantiator<Host>(__safeDI_hostBuilder)
		                        let gadget: any Gadget = __safeDI_gadgetSendableBuilder(.shell_Inner_widget_gadget(SafeDISendableScope_Gadget.shell_Inner_widget_gadget_Values(analytics: analytics, hostBuilder: hostBuilder)))
		                        return DefaultWidget(analytics: analytics, gadget: gadget, hostBuilder: hostBuilder)
		                    }
		                    let widget: any Widget = __safeDI_widget()
		                    return widget
		                }
		            }
		            return Shell(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell)
		        }
		        let shell: Shell = __safeDI_shell()
		        self.init(session: session, shell: shell)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_674A357FFC04F698 {}
		}
		"""])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesDeferredParameterSendable_whenCallInSendableBuilderFunctionInsideFillReentersSeam() async throws {
		// `gadget`'s first stage reads `user`, `Host`'s deferred parameter, before the fill, but the call of `Host` in the
		// `SendableInstantiator` inside the fill reads it inside a `@Sendable` function, which needs a `@Sendable` autoclosure.
		let fixture = Self.fixtureOfSendableFillWithPlace(
			widgetDeclarations: ["@Instantiated let gadget: any Gadget", "@Instantiated let hostBuilder: SendableInstantiator<Host>"],
			middleTypes: [seamFixtureType(named: "User", declarations: [], conformances: ", Sendable"), seamFixtureType(named: "Account", declarations: ["@Received let user: User"], conformances: ", Sendable")],
			hostDeclarations: ["@Instantiated let account: Account", FillRoute.sendableByRoute.hostDeclaration],
			gadgetDeclarations: ["@Received let user: User"],
			root: seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let session: Session", "@Instantiated let user: SendableLazilyInstantiated<User>", "@Instantiated let host: Host"]),
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "Middle", imports: ["Feature"], rootFiles: ["Host": """
		extension Host {
		    @frozen public enum SafeDISendableScope_Gadget {
		        indirect case shell_Inner_widget_hostBuilder_Sendable(Host.SafeDISendableScope_Gadget)
		        case shell_Inner_widget_gadget(shell_Inner_widget_gadget_Values)

		        public struct shell_Inner_widget_gadget_Values {
		            public let analytics: Analytics
		            public let hostBuilder: SendableInstantiator<Host>
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_user: @autoclosure @escaping @Sendable () -> User, __safeDI_gadgetSendableBuilder: @escaping @Sendable (SafeDISendableScope_Gadget) -> any Gadget) {
		        let user = SendableLazilyInstantiated<User>(__safeDI_user)
		        let account = Account(user: user.instance)
		        func __safeDI_shell() -> Shell {
		            _ = Shell.__safeDI_Shell_F559842BF1A90246.self\(seamCallComment(seam: "Shell", module: "Feature"))
		            @Sendable func __safeDI_widgetSendableBuilder_Shell(_ scope: Shell.SafeDISendableScope_Widget) -> any Widget {
		                switch scope {
		                case let .innerBuilder(scope): return __safeDI_widgetBuilder_Inner(scope)
		                }
		            }
		            @Sendable func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
		                switch scope {
		                case let .widget(scope):
		                    let analytics = scope.analytics
		                    func __safeDI_widget() -> DefaultWidget {
		                        @Sendable func __safeDI_hostBuilder() -> Host {
		                            _ = Host.__safeDI_Host_201697DFF2A3B630.self
		                            return Host(__safeDI_user: user.instance, __safeDI_gadgetSendableBuilder: { __safeDI_gadgetSendableBuilder(.shell_Inner_widget_hostBuilder_Sendable($0)) })
		                        }
		                        let hostBuilder = SendableInstantiator<Host>(__safeDI_hostBuilder)
		                        let gadget: any Gadget = __safeDI_gadgetSendableBuilder(.shell_Inner_widget_gadget(SafeDISendableScope_Gadget.shell_Inner_widget_gadget_Values(analytics: analytics, hostBuilder: hostBuilder)))
		                        return DefaultWidget(gadget: gadget, hostBuilder: hostBuilder)
		                    }
		                    let widget: any Widget = __safeDI_widget()
		                    return widget
		                }
		            }
		            return Shell(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell)
		        }
		        let shell: Shell = __safeDI_shell()
		        self.init(account: account, shell: shell)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_201697DFF2A3B630 {}
		}
		"""])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	// MARK: The reason a capture in a fill gives

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorSayingFillIsPassedOn_whenFillMadeSendableByAnotherFillCapturesWrapper() async {
		// `Top` takes `firstBuilder` `@Sendable`, so its fill is `@Sendable`. That fill passes the fill of `second` to `SubB`,
		// whose tree has no `@Sendable` function, so the fill of `second` is `@Sendable` only because the first refers to it.
		let feature = [
			"public protocol First: Sendable {}",
			"public protocol Second: Sendable {}",
			seamFixtureType(named: "SubA", isSeam: true, declarations: ["@Instantiated let first: any First"], conformances: ", Sendable"),
			seamFixtureType(named: "SubB", isSeam: true, declarations: ["@Instantiated let second: any Second"], conformances: ", Sendable"),
			seamFixtureType(named: "Top", isSeam: true, declarations: ["@Instantiated let subABuilder: SendableInstantiator<SubA>", "@Instantiated let subB: SubB"]),
		]
		let app = [
			seamFixtureType(named: "Leaf", declarations: []),
			SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultFirst", fulfilling: "First", declarations: ["@Instantiated let subB: SubB"]),
			SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultSecond", fulfilling: "Second", declarations: ["@Received let leafBuilder: Instantiator<Leaf>"])
				.replacingOccurrences(of: "Instantiable, Second", with: "Instantiable, Second, @unchecked Sendable"),
			seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let leafBuilder: Instantiator<Leaf>", "@Instantiated let top: Top"]),
		]
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["DefaultSecond.swift"]):9:5: error: @Received property `leafBuilder: Instantiator<Leaf>` cannot be received inside a `@Sendable` function in chain: Root -> Top -> DefaultSecond. The function SafeDI generates to fill the builder for `second: any Second` on `SubB` is passed to a seam from inside a `@Sendable` function, or to a seam that takes it `@Sendable`, so it is `@Sendable` too, and it cannot capture `leafBuilder: Instantiator<Leaf>` on `Root`, because `Instantiator<Leaf>` is not `Sendable`. Declare `leafBuilder` on `Root`, and this property, as `SendableInstantiator<Leaf>` to fix. `SendableInstantiator<Leaf>` builds `Leaf` in a `@Sendable` function, so what the tree of `Leaf` receives from outside that function must be `Sendable` too.
			\(fixtures["App"]!["Root.swift"]):10:5: note: `leafBuilder: Instantiator<Leaf>` is declared here
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: app),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: A `@Sendable` fill beneath a `@Sendable` builder function

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesSendableCase_whenSendableFillIsBeneathSendableBuilderFunction() async throws {
		// `shellMaker` builds in a `@Sendable` function and the fill inside it is one too, so `gadgetBuilder` has a stage for
		// each. Nothing is bound between them, but how many stages a builder has follows only from the functions on the
		// path, so that binding a value between them never adds a closure to what a caller writes.
		let fixture = Self.fixtureOfSendableFillWithPlace(hostDeclarations: ["@Received let session: Session", "@Instantiated let shellMaker: SendableInstantiator<Shell>"])
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "Middle", imports: ["Feature"], rootFiles: ["Host": """
		extension Host {
		    @frozen public enum SafeDISendableScope_Gadget {
		        case shellMaker_Inner_widget_gadget(shellMaker_Inner_widget_gadget_Values)

		        public struct shellMaker_Inner_widget_gadget_Values {
		            public let analytics: Analytics
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_session session: Session, __safeDI_gadgetSendableBuilder: @escaping @Sendable (SafeDISendableScope_Gadget) -> any Gadget) {
		        @Sendable func __safeDI_shellMaker() -> Shell {
		            _ = Shell.__safeDI_Shell_F559842BF1A90246.self\(seamCallComment(seam: "Shell", module: "Feature"))
		            @Sendable func __safeDI_widgetSendableBuilder_Shell(_ scope: Shell.SafeDISendableScope_Widget) -> any Widget {
		                switch scope {
		                case let .innerBuilder(scope): return __safeDI_widgetBuilder_Inner(scope)
		                }
		            }
		            @Sendable func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
		                switch scope {
		                case let .widget(scope):
		                    let analytics = scope.analytics
		                    func __safeDI_widget() -> DefaultWidget {
		                        let gadget: any Gadget = __safeDI_gadgetSendableBuilder(.shellMaker_Inner_widget_gadget(SafeDISendableScope_Gadget.shellMaker_Inner_widget_gadget_Values(analytics: analytics)))
		                        return DefaultWidget(analytics: analytics, gadget: gadget)
		                    }
		                    let widget: any Widget = __safeDI_widget()
		                    return widget
		                }
		            }
		            return Shell(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell)
		        }
		        let shellMaker = SendableInstantiator<Shell>(__safeDI_shellMaker)
		        self.init(session: session, shellMaker: shellMaker)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_C6535CAB0ACA6015 {}
		}
		"""])
		expectGeneratedCode(of: output, module: "App", imports: ["Feature", "Middle"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        let session = Session()
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_C6535CAB0ACA6015.self\(seamCallComment(seam: "Host", module: "Middle"))
		            @Sendable func __safeDI_gadgetSendableBuilder_Host(_ scope: Host.SafeDISendableScope_Gadget) -> any Gadget {
		                switch scope {
		                case let .shellMaker_Inner_widget_gadget(scope):
		                    let analytics = scope.analytics
		                    let gadget: any Gadget = DefaultGadget(session: session, analytics: analytics)
		                    return gadget
		                }
		            }
		            return Host(__safeDI_session: session, __safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_Host)
		        }
		        let host: Host = __safeDI_host()
		        self.init(session: session, host: host)
		    }
		}
		"""])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_carriesFieldBoundInsideSendableFill_whenSendableFillIsBeneathSendableBuilderFunction() async throws {
		// `bag` is not `Sendable` and is bound between `holderMaker`'s function and the fill, so only a stage called before
		// the fill can hand it over.
		let fixture = Self.fixtureOfSendableFillWithPlace(
			widgetDeclarations: ["@Instantiated let gadget: any Gadget"],
			middleTypes: [
				seamFixtureType(named: "Bag", declarations: [], conformances: ""),
				seamFixtureType(named: "ShellHolder", declarations: ["@Instantiated let bag: Bag", "@Instantiated let shell: Shell"], conformances: ", @unchecked Sendable"),
			],
			hostDeclarations: ["@Instantiated let holderMaker: SendableInstantiator<ShellHolder>"],
			gadgetDeclarations: [],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "Middle", imports: ["Feature"], rootFiles: ["Host": """
		extension Host {
		    @frozen public enum SafeDISendableScope_Gadget {
		        case holderMaker_shell_Inner_widget_gadget(holderMaker_shell_Inner_widget_gadget_Values)

		        public struct holderMaker_shell_Inner_widget_gadget_Values {
		            public let analytics: Analytics
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_gadgetSendableBuilder: @escaping @Sendable (SafeDISendableScope_Gadget) -> any Gadget) {
		        @Sendable func __safeDI_holderMaker() -> ShellHolder {
		            let bag = Bag()
		            func __safeDI_shell() -> Shell {
		                _ = Shell.__safeDI_Shell_F559842BF1A90246.self\(seamCallComment(seam: "Shell", module: "Feature"))
		                @Sendable func __safeDI_widgetSendableBuilder_Shell(_ scope: Shell.SafeDISendableScope_Widget) -> any Widget {
		                    switch scope {
		                    case let .innerBuilder(scope): return __safeDI_widgetBuilder_Inner(scope)
		                    }
		                }
		                @Sendable func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
		                    switch scope {
		                    case let .widget(scope):
		                        let analytics = scope.analytics
		                        func __safeDI_widget() -> DefaultWidget {
		                            let gadget: any Gadget = __safeDI_gadgetSendableBuilder(.holderMaker_shell_Inner_widget_gadget(SafeDISendableScope_Gadget.holderMaker_shell_Inner_widget_gadget_Values(analytics: analytics)))
		                            return DefaultWidget(gadget: gadget)
		                        }
		                        let widget: any Widget = __safeDI_widget()
		                        return widget
		                    }
		                }
		                return Shell(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell)
		            }
		            let shell: Shell = __safeDI_shell()
		            return ShellHolder(bag: bag, shell: shell)
		        }
		        let holderMaker = SendableInstantiator<ShellHolder>(__safeDI_holderMaker)
		        self.init(holderMaker: holderMaker)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_324677F24ED427C3 {}
		}
		"""])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesSendableCase_whenBuilderIsSendableAndFieldIsNonSendableWrapper() async throws {
		// A call of `Host` in a `SendableInstantiator` inside the fill makes `gadgetBuilder` `@Sendable`, but the fill still
		// cannot capture `itemMaker`, so the first stage is called before it.
		let fixture = Self.fixtureOfSendableFillWithPlace(
			widgetDeclarations: ["@Instantiated let gadget: any Gadget", "@Instantiated let hostBuilder: SendableInstantiator<Host>"],
			middleTypes: [seamFixtureType(named: "Item", declarations: [], conformances: "")],
			hostDeclarations: ["@Instantiated let itemMaker: Instantiator<Item>", FillRoute.sendableByRoute.hostDeclaration],
			hostConformances: ", @unchecked Sendable",
			gadgetDeclarations: [],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "Middle", imports: ["Feature"], rootFiles: ["Host": """
		extension Host {
		    @frozen public enum SafeDISendableScope_Gadget {
		        indirect case shell_Inner_widget_hostBuilder_Sendable(Host.SafeDISendableScope_Gadget)
		        case shell_Inner_widget_gadget(shell_Inner_widget_gadget_Values)

		        public struct shell_Inner_widget_gadget_Values {
		            public let analytics: Analytics
		            public let hostBuilder: SendableInstantiator<Host>
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_gadgetSendableBuilder: @escaping @Sendable (SafeDISendableScope_Gadget) -> any Gadget) {
		        func __safeDI_itemMaker() -> Item {
		            Item()
		        }
		        let itemMaker = Instantiator<Item>(__safeDI_itemMaker)
		        func __safeDI_shell() -> Shell {
		            _ = Shell.__safeDI_Shell_F559842BF1A90246.self\(seamCallComment(seam: "Shell", module: "Feature"))
		            @Sendable func __safeDI_widgetSendableBuilder_Shell(_ scope: Shell.SafeDISendableScope_Widget) -> any Widget {
		                switch scope {
		                case let .innerBuilder(scope): return __safeDI_widgetBuilder_Inner(scope)
		                }
		            }
		            @Sendable func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
		                switch scope {
		                case let .widget(scope):
		                    let analytics = scope.analytics
		                    func __safeDI_widget() -> DefaultWidget {
		                        @Sendable func __safeDI_hostBuilder() -> Host {
		                            _ = Host.__safeDI_Host_0FE6B82E0ED44A9F.self
		                            return Host(__safeDI_gadgetSendableBuilder: { __safeDI_gadgetSendableBuilder(.shell_Inner_widget_hostBuilder_Sendable($0)) })
		                        }
		                        let hostBuilder = SendableInstantiator<Host>(__safeDI_hostBuilder)
		                        let gadget: any Gadget = __safeDI_gadgetSendableBuilder(.shell_Inner_widget_gadget(SafeDISendableScope_Gadget.shell_Inner_widget_gadget_Values(analytics: analytics, hostBuilder: hostBuilder)))
		                        return DefaultWidget(gadget: gadget, hostBuilder: hostBuilder)
		                    }
		                    let widget: any Widget = __safeDI_widget()
		                    return widget
		                }
		            }
		            return Shell(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell)
		        }
		        let shell: Shell = __safeDI_shell()
		        self.init(itemMaker: itemMaker, shell: shell)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_0FE6B82E0ED44A9F {}
		}
		"""])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	// MARK: Two sites of one label and type in the seam a fill fills

	/// `Feature`'s `Inner` builds `a: A` and `b: B`, each of which instantiates `widget: any Widget`, a hole, and `alpha` or
	/// `beta` beside it. `Host` calls `Inner`, or `Shell`, which builds `Inner` in a `SendableInstantiator`, and fills both
	/// holes with `DefaultWidget`, which builds `gadget`, a place of `Host`.
	private static func fixtureOfTwoSitesOfOneLabel(throughShell: Bool) -> ThreeModules {
		ThreeModules(
			feature: [
				"public protocol Widget: Sendable {}",
				seamFixtureType(named: "Alpha", declarations: [], conformances: ", Sendable"),
				seamFixtureType(named: "Beta", declarations: [], conformances: ", Sendable"),
				seamFixtureType(named: "A", declarations: ["@Instantiated let alpha: Alpha", "@Instantiated let widget: any Widget"], conformances: ", Sendable"),
				seamFixtureType(named: "B", declarations: ["@Instantiated let beta: Beta", "@Instantiated let widget: any Widget"], conformances: ", Sendable"),
				seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated let a: A", "@Instantiated let b: B"], conformances: ", Sendable"),
				seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Instantiated let innerBuilder: SendableInstantiator<Inner>"], conformances: ", Sendable"),
			],
			middle: [
				gadget,
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: ["@Instantiated let gadget: any Gadget"]),
				seamFixtureType(named: "Host", isSeam: true, declarations: [throughShell ? "@Instantiated let shell: Shell" : "@Instantiated let inner: Inner"], conformances: ", Sendable"),
			],
			app: [SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultGadget", fulfilling: "Gadget", declarations: [])],
			root: root,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesBuilderForPlaceInsideEachFill_whenFilledSeamHasTwoSitesOfOneLabelAndType() async throws {
		// The fills of `a`'s and `b`'s `widget` are different functions with different fields, so `gadget` is two places.
		let fixture = Self.fixtureOfTwoSitesOfOneLabel(throughShell: false)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "Middle", imports: ["Feature"], rootFiles: ["Host": """
		extension Host {
		    @frozen public enum SafeDIScope_Gadget {
		        case inner_a_widget_gadget(inner_a_widget_gadget_Values)
		        case inner_b_widget_gadget(inner_b_widget_gadget_Values)

		        public struct inner_a_widget_gadget_Values {
		            public let alpha: Alpha
		        }

		        public struct inner_b_widget_gadget_Values {
		            public let a: A
		            public let beta: Beta
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_gadgetBuilder: @escaping (SafeDIScope_Gadget) -> any Gadget) {
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_E1D51F90E6380F00.self\(seamCallComment(seam: "Inner", module: "Feature"))
		            func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
		                switch scope {
		                case let .a(_, scope): return __safeDI_widgetBuilder_Inner_A_Scope(scope)
		                case let .b(values, scope): return __safeDI_widgetBuilder_Inner_B_Scope(scope, a: values.a)
		                }
		            }
		            func __safeDI_widgetBuilder_Inner_A_Scope(_ scope: Inner.SafeDIScope_Widget.A_Scope) -> any Widget {
		                switch scope {
		                case let .widget(scope):
		                    let alpha = scope.alpha
		                    func __safeDI_widget() -> DefaultWidget {
		                        let gadget: any Gadget = __safeDI_gadgetBuilder(.inner_a_widget_gadget(SafeDIScope_Gadget.inner_a_widget_gadget_Values(alpha: alpha)))
		                        return DefaultWidget(gadget: gadget)
		                    }
		                    let widget: any Widget = __safeDI_widget()
		                    return widget
		                }
		            }
		            func __safeDI_widgetBuilder_Inner_B_Scope(_ scope: Inner.SafeDIScope_Widget.B_Scope, a: A) -> any Widget {
		                switch scope {
		                case let .widget(scope):
		                    let beta = scope.beta
		                    func __safeDI_widget() -> DefaultWidget {
		                        let gadget: any Gadget = __safeDI_gadgetBuilder(.inner_b_widget_gadget(SafeDIScope_Gadget.inner_b_widget_gadget_Values(a: a, beta: beta)))
		                        return DefaultWidget(gadget: gadget)
		                    }
		                    let widget: any Widget = __safeDI_widget()
		                    return widget
		                }
		            }
		            return Inner(__safeDI_widgetBuilder: __safeDI_widgetBuilder_Inner)
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(inner: inner)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_1AF2C76943211E42 {}
		}
		"""])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesSendableCaseForPlaceInsideEachFill_whenFilledSeamHasTwoSitesOfOneLabelAndTypeOnSendableRoute() async throws {
		let fixture = Self.fixtureOfTwoSitesOfOneLabel(throughShell: true)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "Middle", imports: ["Feature"], rootFiles: ["Host": """
		extension Host {
		    @frozen public enum SafeDISendableScope_Gadget {
		        case shell_Inner_a_widget_gadget(shell_Inner_a_widget_gadget_Values)
		        case shell_Inner_b_widget_gadget(shell_Inner_b_widget_gadget_Values)

		        public struct shell_Inner_a_widget_gadget_Values {
		            public let alpha: Alpha
		        }

		        public struct shell_Inner_b_widget_gadget_Values {
		            public let a: A
		            public let beta: Beta
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_gadgetSendableBuilder: @escaping @Sendable (SafeDISendableScope_Gadget) -> any Gadget) {
		        func __safeDI_shell() -> Shell {
		            _ = Shell.__safeDI_Shell_84C8B73BD373B858.self\(seamCallComment(seam: "Shell", module: "Feature"))
		            @Sendable func __safeDI_widgetSendableBuilder_Shell(_ scope: Shell.SafeDISendableScope_Widget) -> any Widget {
		                switch scope {
		                case let .innerBuilder(scope): return __safeDI_widgetBuilder_Inner(scope)
		                }
		            }
		            @Sendable func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
		                switch scope {
		                case let .a(_, scope): return __safeDI_widgetBuilder_Inner_A_Scope(scope)
		                case let .b(values, scope): return __safeDI_widgetBuilder_Inner_B_Scope(scope, a: values.a)
		                }
		            }
		            @Sendable func __safeDI_widgetBuilder_Inner_A_Scope(_ scope: Inner.SafeDIScope_Widget.A_Scope) -> any Widget {
		                switch scope {
		                case let .widget(scope):
		                    let alpha = scope.alpha
		                    func __safeDI_widget() -> DefaultWidget {
		                        let gadget: any Gadget = __safeDI_gadgetSendableBuilder(.shell_Inner_a_widget_gadget(SafeDISendableScope_Gadget.shell_Inner_a_widget_gadget_Values(alpha: alpha)))
		                        return DefaultWidget(gadget: gadget)
		                    }
		                    let widget: any Widget = __safeDI_widget()
		                    return widget
		                }
		            }
		            @Sendable func __safeDI_widgetBuilder_Inner_B_Scope(_ scope: Inner.SafeDIScope_Widget.B_Scope, a: A) -> any Widget {
		                switch scope {
		                case let .widget(scope):
		                    let beta = scope.beta
		                    func __safeDI_widget() -> DefaultWidget {
		                        let gadget: any Gadget = __safeDI_gadgetSendableBuilder(.shell_Inner_b_widget_gadget(SafeDISendableScope_Gadget.shell_Inner_b_widget_gadget_Values(a: a, beta: beta)))
		                        return DefaultWidget(gadget: gadget)
		                    }
		                    let widget: any Widget = __safeDI_widget()
		                    return widget
		                }
		            }
		            return Shell(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell)
		        }
		        let shell: Shell = __safeDI_shell()
		        self.init(shell: shell)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_A65130EABE35D8AC {}
		}
		"""])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesBuilderForPlaceInsideEachFill_whenCalledSeamPassesUpSitesOfTwoSeamsWithOnePath() async throws {
		// `Top` passes up `SubA`'s and `SubB`'s `widget`, whose paths are the same in the seam that holds each.
		let fixture = ThreeModules(
			feature: [
				"public protocol Widget: Sendable {}",
				seamFixtureType(named: "Alpha", declarations: [], conformances: ", Sendable"),
				seamFixtureType(named: "Beta", declarations: [], conformances: ", Sendable"),
				seamFixtureType(named: "SubA", isSeam: true, declarations: ["@Instantiated let alpha: Alpha", "@Instantiated let widget: any Widget"], conformances: ", Sendable"),
				seamFixtureType(named: "SubB", isSeam: true, declarations: ["@Instantiated let beta: Beta", "@Instantiated let widget: any Widget"], conformances: ", Sendable"),
				seamFixtureType(named: "Top", isSeam: true, declarations: ["@Instantiated let subA: SubA", "@Instantiated let subB: SubB"], conformances: ", Sendable"),
			],
			middle: [
				Self.gadget,
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: ["@Instantiated let gadget: any Gadget"]),
				seamFixtureType(named: "Host", isSeam: true, declarations: ["@Instantiated let top: Top"], conformances: ", Sendable"),
			],
			app: [SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultGadget", fulfilling: "Gadget", declarations: [])],
			root: Self.root,
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "Middle", imports: ["Feature"], rootFiles: ["Host": """
		extension Host {
		    @frozen public enum SafeDIScope_Gadget {
		        case top_SubA_widget_gadget(top_SubA_widget_gadget_Values)
		        case top_SubB_widget_gadget(top_SubB_widget_gadget_Values)

		        public struct top_SubA_widget_gadget_Values {
		            public let alpha: Alpha
		        }

		        public struct top_SubB_widget_gadget_Values {
		            public let beta: Beta
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_gadgetBuilder: @escaping (SafeDIScope_Gadget) -> any Gadget) {
		        func __safeDI_top() -> Top {
		            _ = Top.__safeDI_Top_302ACF23ECABA902.self\(seamCallComment(seam: "Top", module: "Feature"))
		            func __safeDI_widgetBuilder_Top(_ scope: Top.SafeDIScope_Widget) -> any Widget {
		                switch scope {
		                case let .subA(_, scope): return __safeDI_widgetBuilder_SubA(scope)
		                case let .subB(_, scope): return __safeDI_widgetBuilder_SubB(scope)
		                }
		            }
		            func __safeDI_widgetBuilder_SubA(_ scope: SubA.SafeDIScope_Widget) -> any Widget {
		                switch scope {
		                case let .widget(scope):
		                    let alpha = scope.alpha
		                    func __safeDI_widget() -> DefaultWidget {
		                        let gadget: any Gadget = __safeDI_gadgetBuilder(.top_SubA_widget_gadget(SafeDIScope_Gadget.top_SubA_widget_gadget_Values(alpha: alpha)))
		                        return DefaultWidget(gadget: gadget)
		                    }
		                    let widget: any Widget = __safeDI_widget()
		                    return widget
		                }
		            }
		            func __safeDI_widgetBuilder_SubB(_ scope: SubB.SafeDIScope_Widget) -> any Widget {
		                switch scope {
		                case let .widget(scope):
		                    let beta = scope.beta
		                    func __safeDI_widget() -> DefaultWidget {
		                        let gadget: any Gadget = __safeDI_gadgetBuilder(.top_SubB_widget_gadget(SafeDIScope_Gadget.top_SubB_widget_gadget_Values(beta: beta)))
		                        return DefaultWidget(gadget: gadget)
		                    }
		                    let widget: any Widget = __safeDI_widget()
		                    return widget
		                }
		            }
		            return Top(__safeDI_widgetBuilder: __safeDI_widgetBuilder_Top)
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_5B068A1FBECC5F0D {}
		}
		"""])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	// MARK: The reason a one-stage fill is `@Sendable`

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorSayingFillIsPassedOn_whenFillIsSendableBecauseCalledSeamBuildsSeamInSendableFunction() async {
		// `Shell` builds `Inner` in a `SendableInstantiator`, and so takes `widgetBuilder` `@Sendable`. `Inner`'s own tree
		// builds `widget` in plain code.
		let app = [
			seamFixtureType(named: "Leaf", declarations: [], conformances: ""),
			SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: ["@Received let leafBuilder: Instantiator<Leaf>"])
				.replacingOccurrences(of: "Instantiable, Widget", with: "Instantiable, Widget, @unchecked Sendable"),
			seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let leafBuilder: Instantiator<Leaf>", "@Instantiated let shell: Shell"]),
		]
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["DefaultWidget.swift"]):9:5: error: @Received property `leafBuilder: Instantiator<Leaf>` cannot be received inside a `@Sendable` function in chain: Root -> Shell -> DefaultWidget. The function SafeDI generates to fill the builder for `widget: any Widget` on `Inner` is passed to a seam from inside a `@Sendable` function, or to a seam that takes it `@Sendable`, so it is `@Sendable` too, and it cannot capture `leafBuilder: Instantiator<Leaf>` on `Root`, because `Instantiator<Leaf>` is not `Sendable`. Declare `leafBuilder` on `Root`, and this property, as `SendableInstantiator<Leaf>` to fix. `SendableInstantiator<Leaf>` builds `Leaf` in a `@Sendable` function, so what the tree of `Leaf` receives from outside that function must be `Sendable` too.
			\(fixtures["App"]!["Root.swift"]):10:5: note: `leafBuilder: Instantiator<Leaf>` is declared here
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: SafeDIToolSeamBuilderParameterTests.modules(feature: FillRoute.sendableByRoute.featureTypes, app: app),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: A stage's name, and a generic argument of an enclosing type

	// MARK: A field a site carries beneath a nearer declaration of its label

	/// The `DefaultWidget` and `Holder` shapes that declare `analytics` nearer a place than the field of the fill's struct.
	enum NearerDeclaration: CaseIterable, CustomTestStringConvertible {
		/// `DefaultWidget` instantiates `analytics` beside `gadget`.
		case besideThePlace
		/// `DefaultWidget` instantiates `analytics` beside `holder`, which builds `gadget`.
		case aboveTheOwnerOfThePlace
		/// `holderMaker: Instantiator<Holder>` is handed `analytics`, and `Holder` builds `gadget`.
		case forwardedToTheOwnerOfThePlace

		var testDescription: String {
			switch self {
			case .besideThePlace:
				"besideThePlace"
			case .aboveTheOwnerOfThePlace:
				"aboveTheOwnerOfThePlace"
			case .forwardedToTheOwnerOfThePlace:
				"forwardedToTheOwnerOfThePlace"
			}
		}

		var widgetDeclarations: [String] {
			switch self {
			case .besideThePlace:
				["@Instantiated let analytics: Analytics", "@Instantiated let gadget: any Gadget"]
			case .aboveTheOwnerOfThePlace:
				["@Instantiated let analytics: Analytics", "@Instantiated let holder: Holder"]
			case .forwardedToTheOwnerOfThePlace:
				["@Instantiated let holderMaker: Instantiator<Holder>"]
			}
		}

		var middleTypes: [String] {
			switch self {
			case .besideThePlace:
				[]
			case .aboveTheOwnerOfThePlace:
				[seamFixtureType(named: "Holder", declarations: ["@Instantiated let gadget: any Gadget"], conformances: ", Sendable")]
			case .forwardedToTheOwnerOfThePlace:
				[seamFixtureType(named: "Holder", declarations: ["@Forwarded let analytics: Analytics", "@Instantiated let gadget: any Gadget"], conformances: ", Sendable")]
			}
		}

		var hostCode: String {
			switch self {
			case .besideThePlace:
				"""
				extension Host {
				    @frozen public enum SafeDIScope_Gadget {
				        case inner_widget_gadget(inner_widget_gadget_Values)

				        public struct inner_widget_gadget_Values {
				            public let session: Session
				            public let analytics: Analytics
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public init(__safeDI_session session: Session, __safeDI_gadgetBuilder: @escaping (SafeDIScope_Gadget) -> any Gadget) {
				        func __safeDI_inner() -> Inner {
				            _ = Inner.__safeDI_Inner_318A87E8A50EC522.self\(seamCallComment(seam: "Inner", module: "Feature"))
				            func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
				                switch scope {
				                case .widget:
				                    func __safeDI_widget() -> DefaultWidget {
				                        let analytics = Analytics()
				                        let gadget: any Gadget = __safeDI_gadgetBuilder(.inner_widget_gadget(SafeDIScope_Gadget.inner_widget_gadget_Values(session: session, analytics: analytics)))
				                        return DefaultWidget(analytics: analytics, gadget: gadget)
				                    }
				                    let widget: any Widget = __safeDI_widget()
				                    return widget
				                }
				            }
				            return Inner(__safeDI_widgetBuilder: __safeDI_widgetBuilder_Inner)
				        }
				        let inner: Inner = __safeDI_inner()
				        self.init(session: session, inner: inner)
				    }
				}

				extension Host {
				    public enum __safeDI_Host_D36AC699D85AC769 {}
				}
				"""
			case .aboveTheOwnerOfThePlace:
				"""
				extension Host {
				    @frozen public enum SafeDIScope_Gadget {
				        case inner_widget_holder_gadget(inner_widget_holder_gadget_Values)

				        public struct inner_widget_holder_gadget_Values {
				            public let session: Session
				            public let analytics: Analytics
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public init(__safeDI_session session: Session, __safeDI_gadgetBuilder: @escaping (SafeDIScope_Gadget) -> any Gadget) {
				        func __safeDI_inner() -> Inner {
				            _ = Inner.__safeDI_Inner_318A87E8A50EC522.self\(seamCallComment(seam: "Inner", module: "Feature"))
				            func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
				                switch scope {
				                case .widget:
				                    func __safeDI_widget() -> DefaultWidget {
				                        let analytics = Analytics()
				                        func __safeDI_holder() -> Holder {
				                            let gadget: any Gadget = __safeDI_gadgetBuilder(.inner_widget_holder_gadget(SafeDIScope_Gadget.inner_widget_holder_gadget_Values(session: session, analytics: analytics)))
				                            return Holder(gadget: gadget)
				                        }
				                        let holder: Holder = __safeDI_holder()
				                        return DefaultWidget(analytics: analytics, holder: holder)
				                    }
				                    let widget: any Widget = __safeDI_widget()
				                    return widget
				                }
				            }
				            return Inner(__safeDI_widgetBuilder: __safeDI_widgetBuilder_Inner)
				        }
				        let inner: Inner = __safeDI_inner()
				        self.init(session: session, inner: inner)
				    }
				}

				extension Host {
				    public enum __safeDI_Host_A5B98C60AD5007E8 {}
				}
				"""
			case .forwardedToTheOwnerOfThePlace:
				"""
				extension Host {
				    @frozen public enum SafeDIScope_Gadget {
				        case inner_widget_holderMaker_gadget(inner_widget_holderMaker_gadget_Values)

				        public struct inner_widget_holderMaker_gadget_Values {
				            public let session: Session
				            public let analytics: Analytics
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public init(__safeDI_session session: Session, __safeDI_gadgetBuilder: @escaping (SafeDIScope_Gadget) -> any Gadget) {
				        func __safeDI_inner() -> Inner {
				            _ = Inner.__safeDI_Inner_318A87E8A50EC522.self\(seamCallComment(seam: "Inner", module: "Feature"))
				            func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
				                switch scope {
				                case .widget:
				                    func __safeDI_widget() -> DefaultWidget {
				                        func __safeDI_holderMaker(analytics: Analytics) -> Holder {
				                            let gadget: any Gadget = __safeDI_gadgetBuilder(.inner_widget_holderMaker_gadget(SafeDIScope_Gadget.inner_widget_holderMaker_gadget_Values(session: session, analytics: analytics)))
				                            return Holder(analytics: analytics, gadget: gadget)
				                        }
				                        let holderMaker = Instantiator<Holder> {
				                            __safeDI_holderMaker(analytics: $0)
				                        }
				                        return DefaultWidget(holderMaker: holderMaker)
				                    }
				                    let widget: any Widget = __safeDI_widget()
				                    return widget
				                }
				            }
				            return Inner(__safeDI_widgetBuilder: __safeDI_widgetBuilder_Inner)
				        }
				        let inner: Inner = __safeDI_inner()
				        self.init(session: session, inner: inner)
				    }
				}

				extension Host {
				    public enum __safeDI_Host_23BB22D94CADB3B6 {}
				}
				"""
			}
		}
	}

	@Test(arguments: NearerDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_doesNotBindCarriedField_whenFulfillerDeclaresItsLabelNearerThePlace(nearerDeclaration: NearerDeclaration) async throws {
		// The place's struct carries `analytics`, as `DefaultWidget`'s tree binds it, so the fill must not bind the field of
		// its own struct with that label, which nothing would read.
		let fixture = Self.fixture(
			route: .plain,
			middleTypes: nearerDeclaration.middleTypes,
			widgetDeclarations: nearerDeclaration.widgetDeclarations,
			appTypes: [SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultGadget", fulfilling: "Gadget", declarations: ["@Received let analytics: Analytics"])],
			widgetConformances: "Instantiable, Widget, @unchecked Sendable",
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "Middle", imports: ["Feature"], rootFiles: ["Host": nearerDeclaration.hostCode])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_doesNotBindCarriedField_whenFulfillerDeclaresItsLabelNearerThePlaceInSendableFill() async throws {
		let fixture = Self.fixtureOfSendableFillWithPlace(
			widgetDeclarations: ["@Instantiated let analytics: Analytics", "@Instantiated let gadget: any Gadget"],
			gadgetDeclarations: ["@Received let analytics: Analytics"],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "Middle", imports: ["Feature"], rootFiles: ["Host": """
		extension Host {
		    @frozen public enum SafeDISendableScope_Gadget {
		        case shell_Inner_widget_gadget(shell_Inner_widget_gadget_Values)

		        public struct shell_Inner_widget_gadget_Values {
		            public let analytics: Analytics
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_session session: Session, __safeDI_gadgetSendableBuilder: @escaping @Sendable (SafeDISendableScope_Gadget) -> any Gadget) {
		        func __safeDI_shell() -> Shell {
		            _ = Shell.__safeDI_Shell_F559842BF1A90246.self\(seamCallComment(seam: "Shell", module: "Feature"))
		            @Sendable func __safeDI_widgetSendableBuilder_Shell(_ scope: Shell.SafeDISendableScope_Widget) -> any Widget {
		                switch scope {
		                case let .innerBuilder(scope): return __safeDI_widgetBuilder_Inner(scope)
		                }
		            }
		            @Sendable func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
		                switch scope {
		                case .widget:
		                    func __safeDI_widget() -> DefaultWidget {
		                        let analytics = Analytics()
		                        let gadget: any Gadget = __safeDI_gadgetSendableBuilder(.shell_Inner_widget_gadget(SafeDISendableScope_Gadget.shell_Inner_widget_gadget_Values(analytics: analytics)))
		                        return DefaultWidget(analytics: analytics, gadget: gadget)
		                    }
		                    let widget: any Widget = __safeDI_widget()
		                    return widget
		                }
		            }
		            return Shell(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell)
		        }
		        let shell: Shell = __safeDI_shell()
		        self.init(session: session, shell: shell)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_EA5718A38EED3127 {}
		}
		"""])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	// MARK: Raw-identifier labels in the names of stages

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsSendableCaseAsIdentifier_whenPlaceInSendableFillHasRawIdentifierLabel() async throws {
		let fixture = Self.fixtureOfSendableFillWithPlace(
			widgetDeclarations: ["@Instantiated let `my gadget`: any Gadget"],
			gadgetDeclarations: ["@Received let session: Session"],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "Middle", imports: ["Feature"], rootFiles: ["Host": """
		extension Host {
		    @frozen public enum SafeDISendableScope_Gadget {
		        case `shell_Inner_widget_my gadget`(`shell_Inner_widget_my gadget_Values`)

		        public struct `shell_Inner_widget_my gadget_Values` {
		            public let analytics: Analytics
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_session session: Session, __safeDI_gadgetSendableBuilder: @escaping @Sendable (SafeDISendableScope_Gadget) -> any Gadget) {
		        func __safeDI_shell() -> Shell {
		            _ = Shell.__safeDI_Shell_F559842BF1A90246.self\(seamCallComment(seam: "Shell", module: "Feature"))
		            @Sendable func __safeDI_widgetSendableBuilder_Shell(_ scope: Shell.SafeDISendableScope_Widget) -> any Widget {
		                switch scope {
		                case let .innerBuilder(scope): return __safeDI_widgetBuilder_Inner(scope)
		                }
		            }
		            @Sendable func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
		                switch scope {
		                case let .widget(scope):
		                    let analytics = scope.analytics
		                    func __safeDI_widget() -> DefaultWidget {
		                        let `my gadget`: any Gadget = __safeDI_gadgetSendableBuilder(.`shell_Inner_widget_my gadget`(SafeDISendableScope_Gadget.`shell_Inner_widget_my gadget_Values`(analytics: analytics)))
		                        return DefaultWidget(`my gadget`: `my gadget`)
		                    }
		                    let widget: any Widget = __safeDI_widget()
		                    return widget
		                }
		            }
		            return Shell(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell)
		        }
		        let shell: Shell = __safeDI_shell()
		        self.init(session: session, shell: shell)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_A5D00FE95847C90F {}
		}
		"""])
		expectGeneratedCode(of: output, module: "App", imports: ["Feature", "Middle"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        let session = Session()
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_A5D00FE95847C90F.self\(seamCallComment(seam: "Host", module: "Middle"))
		            @Sendable func __safeDI_gadgetSendableBuilder_Host(_ scope: Host.SafeDISendableScope_Gadget) -> any Gadget {
		                switch scope {
		                case .`shell_Inner_widget_my gadget`:
		                    let `my gadget`: any Gadget = DefaultGadget(session: session)
		                    return `my gadget`
		                }
		            }
		            return Host(__safeDI_session: session, __safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_Host)
		        }
		        let host: Host = __safeDI_host()
		        self.init(session: session, host: host)
		    }
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsSendableCaseAsIdentifier_whenPlaceBeneathSendableBuilderFunctionHasRawIdentifierLabel() async throws {
		let fixture = ThreeModules(
			feature: ["public protocol Widget: Sendable {}"],
			middle: [
				Self.gadget,
				Self.session,
				seamFixtureType(named: "Holder", declarations: ["@Instantiated let `my gadget`: any Gadget"], conformances: ", Sendable"),
				seamFixtureType(named: "Host", isSeam: true, declarations: ["@Received let session: Session", "@Instantiated let holderMaker: SendableInstantiator<Holder>"], conformances: ", Sendable"),
			],
			app: [SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultGadget", fulfilling: "Gadget", declarations: ["@Received let session: Session"])],
			root: Self.rootWithSession,
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "Middle", imports: ["Feature"], rootFiles: ["Host": """
		extension Host {
		    @frozen public enum SafeDIScope_Gadget {
		        @frozen public enum Holder_Scope {
		            case `my gadget`(`my gadget_Values`)

		            public struct `my gadget_Values` {}
		        }
		    }

		    @frozen public enum SafeDISendableScope_Gadget {
		        case holderMaker(SafeDIScope_Gadget.Holder_Scope)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_session session: Session, __safeDI_gadgetSendableBuilder: @escaping @Sendable (SafeDISendableScope_Gadget) -> any Gadget) {
		        @Sendable func __safeDI_holderMaker() -> Holder {
		            let `my gadget`: any Gadget = __safeDI_gadgetSendableBuilder(.holderMaker(.`my gadget`(SafeDIScope_Gadget.Holder_Scope.`my gadget_Values`())))
		            return Holder(`my gadget`: `my gadget`)
		        }
		        let holderMaker = SendableInstantiator<Holder>(__safeDI_holderMaker)
		        self.init(session: session, holderMaker: holderMaker)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_22CCEA51CEB933EE {}
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsFillAsIdentifier_whenSendableFilledHoleHasRawIdentifierLabel() async throws {
		let fixture = ThreeModules(
			feature: [
				"public protocol Widget: Sendable {}",
				seamFixtureType(named: "Analytics", declarations: [], conformances: ", Sendable"),
				seamFixtureType(named: "Panel", declarations: ["@Instantiated let `my widget`: any Widget"], conformances: ", Sendable"),
				seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated let analytics: Analytics", "@Instantiated let panelBuilder: SendableInstantiator<Panel>"], conformances: ", Sendable"),
			],
			middle: [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: []),
				seamFixtureType(named: "Host", isSeam: true, declarations: ["@Instantiated let inner: Inner"], conformances: ", Sendable"),
			],
			app: [],
			root: Self.root,
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "Feature", imports: [], rootFiles: ["Inner": """
		extension Inner {
		    @frozen public enum SafeDIScope_Widget {
		        @frozen public enum Panel_Scope {
		            case `my widget`(`my widget_Values`)

		            public struct `my widget_Values` {}
		        }
		    }

		    @frozen public enum SafeDISendableScope_Widget {
		        case panelBuilder(SafeDIScope_Widget.Panel_Scope)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_widgetSendableBuilder: @escaping @Sendable (SafeDISendableScope_Widget) -> any Widget) {
		        let analytics = Analytics()
		        @Sendable func __safeDI_panelBuilder() -> Panel {
		            let `my widget`: any Widget = __safeDI_widgetSendableBuilder(.panelBuilder(.`my widget`(SafeDIScope_Widget.Panel_Scope.`my widget_Values`())))
		            return Panel(`my widget`: `my widget`)
		        }
		        let panelBuilder = SendableInstantiator<Panel>(__safeDI_panelBuilder)
		        self.init(analytics: analytics, panelBuilder: panelBuilder)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_49F4F850D03A197A {}
		}
		"""])
		expectGeneratedCode(of: output, module: "Middle", imports: ["Feature"], rootFiles: ["Host": """
		extension Host {
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public init() {
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_49F4F850D03A197A.self\(seamCallComment(seam: "Inner", module: "Feature"))
		            @Sendable func __safeDI_widgetSendableBuilder_Inner(_ scope: Inner.SafeDISendableScope_Widget) -> any Widget {
		                switch scope {
		                case let .panelBuilder(scope): return __safeDI_widgetBuilder_Inner_Panel_Scope(scope)
		                }
		            }
		            @Sendable func __safeDI_widgetBuilder_Inner_Panel_Scope(_ scope: Inner.SafeDIScope_Widget.Panel_Scope) -> any Widget {
		                switch scope {
		                case .`my widget`:
		                    let `my widget`: any Widget = DefaultWidget()
		                    return `my widget`
		                }
		            }
		            return Inner(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Inner)
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(inner: inner)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_CBF29CE484222325 {}
		}
		"""])
	}

	// MARK: A value labeled as the fill's parameter

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesFillsParameterApart_whenFieldIsLabeledScope() async throws {
		let fixture = ThreeModules(
			feature: [
				"public protocol Widget: Sendable {}",
				seamFixtureType(named: "Analytics", declarations: [], conformances: ", Sendable"),
				seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated let scope: Analytics", "@Instantiated let analytics: Analytics", "@Instantiated let widget: any Widget"], conformances: ", Sendable"),
			],
			middle: [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: ["@Received let scope: Analytics", "@Received let analytics: Analytics"]),
				seamFixtureType(named: "Host", isSeam: true, declarations: ["@Instantiated let inner: Inner"], conformances: ", Sendable"),
			],
			app: [],
			root: Self.root,
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "Middle", imports: ["Feature"], rootFiles: ["Host": """
		extension Host {
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public init() {
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_E331489165434869.self\(seamCallComment(seam: "Inner", module: "Feature"))
		            func __safeDI_widgetBuilder_Inner_widget(_ scope_: Inner.SafeDIScope_Widget.widget_Values) -> any Widget {
		                let scope = scope_.scope
		                let analytics = scope_.analytics
		                let widget: any Widget = DefaultWidget(scope: scope, analytics: analytics)
		                return widget
		            }
		            func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
		                switch scope {
		                case let .widget(scope): return __safeDI_widgetBuilder_Inner_widget(scope)
		                }
		            }
		            return Inner(__safeDI_widgetBuilder: __safeDI_widgetBuilder_Inner)
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(inner: inner)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_CBF29CE484222325 {}
		}
		"""])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesFillsParameterApart_whenFulfillerReceivesValueLabeledScopeFromCallersScope() async throws {
		// The fill's parameter would hide `Host`'s `scope`, which `DefaultWidget` receives and `Inner`'s struct does not carry.
		let fixture = ThreeModules(
			feature: [
				"public protocol Widget: Sendable {}",
				seamFixtureType(named: "Analytics", declarations: [], conformances: ", Sendable"),
				seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated let widget: any Widget"], conformances: ", Sendable"),
			],
			middle: [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: ["@Received let scope: Analytics"]),
				seamFixtureType(named: "Host", isSeam: true, declarations: ["@Instantiated let scope: Analytics", "@Instantiated let inner: Inner"], conformances: ", Sendable"),
			],
			app: [],
			root: Self.root,
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "Middle", imports: ["Feature"], rootFiles: ["Host": """
		extension Host {
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public init() {
		        let scope = Analytics()
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_FA27ABA7B4ABD523.self\(seamCallComment(seam: "Inner", module: "Feature"))
		            func __safeDI_widgetBuilder_Inner_widget(_ scope_: Inner.SafeDIScope_Widget.widget_Values) -> any Widget {
		                let widget: any Widget = DefaultWidget(scope: scope)
		                return widget
		            }
		            func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
		                switch scope {
		                case let .widget(scope): return __safeDI_widgetBuilder_Inner_widget(scope)
		                }
		            }
		            return Inner(__safeDI_widgetBuilder: __safeDI_widgetBuilder_Inner)
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(scope: scope, inner: inner)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_CBF29CE484222325 {}
		}
		"""])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// Expects the files `output` generated for `module` to hold `rootFiles`' code, by type.
	private func expectGeneratedCode(of output: MultiModuleTestOutput, module: String, imports: [String], rootFiles: [String: String], sourceLocation: SourceLocation = #_sourceLocation) {
		let generatedFiles = output.modules[module]?.generatedFiles
		let expected = SafeDIToolSeamBuilderParameterTests.generatedFiles(module: module, integration: .moduleInfo, imports: imports, rootFiles: rootFiles)
		#expect(generatedFiles == expected, sourceLocation: sourceLocation)
		if let generatedFiles, generatedFiles != expected {
			Issue.record(Comment(rawValue: generatedFiles.sorted { $0.key < $1.key }.map { "=== \($0.key)\n\($0.value)" }.joined(separator: "\n")), sourceLocation: sourceLocation)
		}
	}

	/// Expects the values `output`, the run of `fixture`, builds for `Root` to equal those of the same graph in one module.
	private mutating func expectValuesEqualVisibleBuild(_ output: MultiModuleTestOutput, _ fixture: ThreeModules, sourceLocation: SourceLocation = #_sourceLocation) async throws {
		try await expectValuesEqualVisibleBuild(output, modules: fixture.modules, visibleModules: fixture.visibleModules, sourceLocation: sourceLocation)
	}

	/// Expects the values `output`, the run of `modules`, builds for `Root` to equal those the run of `visibleModules` builds.
	private mutating func expectValuesEqualVisibleBuild(
		_ output: MultiModuleTestOutput,
		modules: [ModuleFixture],
		visibleModules: [ModuleFixture],
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		guard compileVerificationIsEnabled else { return }
		let visibleOutput = try await executeSafeDIToolMultiModuleTest(modules: visibleModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		try await expectDifferentialValuesAgree(
			feature: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: output, modules: modules),
			knownRight: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: visibleOutput, modules: visibleModules),
			probes: [DifferentialValueProbe("Root()")],
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}
}
