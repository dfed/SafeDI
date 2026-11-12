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
/// a place's builder is staged there, and a builder a call inside it passes up is `@Sendable`.
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
		/// `Host` calls `Inner`, which builds `widget` in a `SendableInstantiator`: the fill's last stage is `@Sendable`.
		case lastStageOfStagedFill
		/// Both: every function of the fill is `@Sendable`.
		case stagedFillTakenSendable

		var testDescription: String {
			switch self {
			case .plain:
				"plain"
			case .sendableByRoute:
				"sendableByRoute"
			case .lastStageOfStagedFill:
				"lastStageOfStagedFill"
			case .stagedFillTakenSendable:
				"stagedFillTakenSendable"
			}
		}

		var isStaged: Bool {
			switch self {
			case .plain, .sendableByRoute:
				false
			case .lastStageOfStagedFill, .stagedFillTakenSendable:
				true
			}
		}

		var isThroughShell: Bool {
			switch self {
			case .plain, .lastStageOfStagedFill:
				false
			case .sendableByRoute, .stagedFillTakenSendable:
				true
			}
		}

		var featureTypes: [String] {
			let leaves = [
				"public protocol Widget: Sendable {}",
				seamFixtureType(named: "Analytics", declarations: [], conformances: ", Sendable"),
				seamFixtureType(named: "Clock", declarations: [], conformances: ", Sendable"),
			]
			let inner = isStaged
				? [
					seamFixtureType(named: "Panel", declarations: ["@Instantiated let clock: Clock", "@Instantiated let widget: any Widget"], conformances: ", Sendable"),
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

				    public init(gadgetBuilder: @escaping (SafeDIScope_Gadget) -> any Gadget, gearBuilder: @escaping (SafeDIScope_Gear) -> any Gear) {
				        let __safeDI_gadgetBuilder = gadgetBuilder
				        let __safeDI_gearBuilder = gearBuilder
				        let session = Session()
				        func __safeDI_inner() -> Inner {
				            _ = Inner.__safeDI_Inner_A441BC75156D061F.self\(seamCallComment(seam: "Inner", module: "Feature"))
				            func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
				                switch scope {
				                case let .widget(scope):
				                    let analytics = scope.analytics
				                    func __safeDI_widget() -> DefaultWidget {
				                        func __safeDI_part() -> Part {
				                            _ = Part.__safeDI_Part_8735560374A43092.self\(seamCallComment(seam: "Inner", module: "Feature"))
				                            return Part(gearBuilder: { __safeDI_gearBuilder(.inner_widget_part($0)) })
				                        }
				                        let part: Part = __safeDI_part()
				                        let gadget: any Gadget = __safeDI_gadgetBuilder(.inner_widget_gadget(SafeDIScope_Gadget.inner_widget_gadget_Values(session: session, analytics: analytics, part: part)))
				                        return DefaultWidget(analytics: analytics, gadget: gadget, part: part)
				                    }
				                    let widget: any Widget = __safeDI_widget()
				                    return widget
				                }
				            }
				            return Inner(widgetBuilder: __safeDI_widgetBuilder_Inner)
				        }
				        let inner: Inner = __safeDI_inner()
				        self.init(session: session, inner: inner)
				    }
				}

				extension Host {
				    public enum __safeDI_Host_25297A734190213E {}
				}
				"""
			case .sendableByRoute:
				"""
				extension Host {
				    public enum SafeDIStagedScope_Gadget_shell_Inner_widget_gadget {
				        public struct Stage1 {
				            public let session: Session
				        }

				        public struct Stage2 {
				            public let analytics: Analytics
				            public let part: Part
				        }
				    }

				    @frozen public enum SafeDISendableScope_Gear {
				        case shell_Inner_widget_part(Part.SafeDIScope_Gear)
				    }

				    public init(gadgetBuilder_shell_Inner_widget_gadget: @escaping (SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage1) -> @Sendable (SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage2) -> any Gadget, gearSendableBuilder: @escaping @Sendable (SafeDISendableScope_Gear) -> any Gear) {
				        let __safeDI_gadgetBuilder_shell_Inner_widget_gadget = gadgetBuilder_shell_Inner_widget_gadget
				        let __safeDI_gearSendableBuilder = gearSendableBuilder
				        let session = Session()
				        func __safeDI_shell() -> Shell {
				            _ = Shell.__safeDI_Shell_076D60492DA3478F.self\(seamCallComment(seam: "Shell", module: "Feature"))
				            let __safeDI_gadgetBuilder_shell_Inner_widget_gadget_Stage2 = __safeDI_gadgetBuilder_shell_Inner_widget_gadget(SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage1(session: session))
				            @Sendable func __safeDI_widgetBuilder_Inner_widget(_ scope: Inner.SafeDIScope_Widget.widget_Values) -> any Widget {
				                let analytics = scope.analytics
				                func __safeDI_widget() -> DefaultWidget {
				                    func __safeDI_part() -> Part {
				                        _ = Part.__safeDI_Part_8735560374A43092.self\(seamCallComment(seam: "Shell", module: "Feature"))
				                        return Part(gearBuilder: { __safeDI_gearSendableBuilder(.shell_Inner_widget_part($0)) })
				                    }
				                    let part: Part = __safeDI_part()
				                    let gadget: any Gadget = __safeDI_gadgetBuilder_shell_Inner_widget_gadget_Stage2(SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage2(analytics: analytics, part: part))
				                    return DefaultWidget(analytics: analytics, gadget: gadget, part: part)
				                }
				                let widget: any Widget = __safeDI_widget()
				                return widget
				            }
				            @Sendable func __safeDI_widgetSendableBuilder_Shell(_ scope: Shell.SafeDISendableScope_Widget) -> any Widget {
				                switch scope {
				                case let .innerBuilder(scope): return __safeDI_widgetBuilder_Inner(scope)
				                }
				            }
				            @Sendable func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
				                switch scope {
				                case let .widget(scope): return __safeDI_widgetBuilder_Inner_widget(scope)
				                }
				            }
				            return Shell(widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell)
				        }
				        let shell: Shell = __safeDI_shell()
				        self.init(session: session, shell: shell)
				    }
				}

				extension Host {
				    public enum __safeDI_Host_F6DD5C282F7A31F3 {}
				}
				"""
			case .lastStageOfStagedFill:
				"""
				extension Host {
				    public enum SafeDIStagedScope_Gadget_inner_panelBuilder_widget_gadget {
				        public struct Stage1 {
				            public let session: Session
				            public let analytics: Analytics
				        }

				        public struct Stage2 {
				            public let clock: Clock
				            public let part: Part
				        }
				    }

				    @frozen public enum SafeDISendableScope_Gear {
				        case inner_panelBuilder_widget_part(Part.SafeDIScope_Gear)
				    }

				    public init(gadgetBuilder_inner_panelBuilder_widget_gadget: @escaping (SafeDIStagedScope_Gadget_inner_panelBuilder_widget_gadget.Stage1) -> @Sendable (SafeDIStagedScope_Gadget_inner_panelBuilder_widget_gadget.Stage2) -> any Gadget, gearSendableBuilder: @escaping @Sendable (SafeDISendableScope_Gear) -> any Gear) {
				        let __safeDI_gadgetBuilder_inner_panelBuilder_widget_gadget = gadgetBuilder_inner_panelBuilder_widget_gadget
				        let __safeDI_gearSendableBuilder = gearSendableBuilder
				        let session = Session()
				        func __safeDI_inner() -> Inner {
				            _ = Inner.__safeDI_Inner_702BBF403C09CE6C.self\(seamCallComment(seam: "Inner", module: "Feature"))
				            func __safeDI_widgetBuilder_panelBuilder_widget(_ scope: Inner.SafeDIStagedScope_Widget_panelBuilder_widget.Stage1) -> @Sendable (Inner.SafeDIStagedScope_Widget_panelBuilder_widget.Stage2) -> any Widget {
				                let analytics = scope.analytics
				                let __safeDI_gadgetBuilder_inner_panelBuilder_widget_gadget_Stage2 = __safeDI_gadgetBuilder_inner_panelBuilder_widget_gadget(SafeDIStagedScope_Gadget_inner_panelBuilder_widget_gadget.Stage1(session: session, analytics: analytics))
				                @Sendable func __safeDI_widgetBuilder_panelBuilder_widget_Stage2(_ scope: Inner.SafeDIStagedScope_Widget_panelBuilder_widget.Stage2) -> any Widget {
				                    let clock = scope.clock
				                    func __safeDI_widget() -> DefaultWidget {
				                        func __safeDI_part() -> Part {
				                            _ = Part.__safeDI_Part_8735560374A43092.self\(seamCallComment(seam: "Inner", module: "Feature"))
				                            return Part(gearBuilder: { __safeDI_gearSendableBuilder(.inner_panelBuilder_widget_part($0)) })
				                        }
				                        let part: Part = __safeDI_part()
				                        let gadget: any Gadget = __safeDI_gadgetBuilder_inner_panelBuilder_widget_gadget_Stage2(SafeDIStagedScope_Gadget_inner_panelBuilder_widget_gadget.Stage2(clock: clock, part: part))
				                        return DefaultWidget(analytics: analytics, gadget: gadget, part: part)
				                    }
				                    let widget: any Widget = __safeDI_widget()
				                    return widget
				                }
				                return __safeDI_widgetBuilder_panelBuilder_widget_Stage2
				            }
				            return Inner(widgetBuilder_panelBuilder_widget: __safeDI_widgetBuilder_panelBuilder_widget)
				        }
				        let inner: Inner = __safeDI_inner()
				        self.init(session: session, inner: inner)
				    }
				}

				extension Host {
				    public enum __safeDI_Host_056A14C28200F753 {}
				}
				"""
			case .stagedFillTakenSendable:
				"""
				extension Host {
				    public enum SafeDIStagedScope_Gadget_shell_Inner_panelBuilder_widget_gadget {
				        public struct Stage1 {
				            public let session: Session
				        }

				        public struct Stage2 {
				            public let analytics: Analytics
				        }

				        public struct Stage3 {
				            public let clock: Clock
				            public let part: Part
				        }
				    }

				    @frozen public enum SafeDISendableScope_Gear {
				        case shell_Inner_panelBuilder_widget_part(Part.SafeDIScope_Gear)
				    }

				    public init(gadgetBuilder_shell_Inner_panelBuilder_widget_gadget: @escaping (SafeDIStagedScope_Gadget_shell_Inner_panelBuilder_widget_gadget.Stage1) -> @Sendable (SafeDIStagedScope_Gadget_shell_Inner_panelBuilder_widget_gadget.Stage2) -> @Sendable (SafeDIStagedScope_Gadget_shell_Inner_panelBuilder_widget_gadget.Stage3) -> any Gadget, gearSendableBuilder: @escaping @Sendable (SafeDISendableScope_Gear) -> any Gear) {
				        let __safeDI_gadgetBuilder_shell_Inner_panelBuilder_widget_gadget = gadgetBuilder_shell_Inner_panelBuilder_widget_gadget
				        let __safeDI_gearSendableBuilder = gearSendableBuilder
				        let session = Session()
				        func __safeDI_shell() -> Shell {
				            _ = Shell.__safeDI_Shell_ADF5E6DB55D5B92B.self\(seamCallComment(seam: "Shell", module: "Feature"))
				            let __safeDI_gadgetBuilder_shell_Inner_panelBuilder_widget_gadget_Stage2 = __safeDI_gadgetBuilder_shell_Inner_panelBuilder_widget_gadget(SafeDIStagedScope_Gadget_shell_Inner_panelBuilder_widget_gadget.Stage1(session: session))
				            @Sendable func __safeDI_widgetBuilder_Inner_panelBuilder_widget(_ scope: Inner.SafeDIStagedScope_Widget_panelBuilder_widget.Stage1) -> @Sendable (Inner.SafeDIStagedScope_Widget_panelBuilder_widget.Stage2) -> any Widget {
				                let analytics = scope.analytics
				                let __safeDI_gadgetBuilder_shell_Inner_panelBuilder_widget_gadget_Stage3 = __safeDI_gadgetBuilder_shell_Inner_panelBuilder_widget_gadget_Stage2(SafeDIStagedScope_Gadget_shell_Inner_panelBuilder_widget_gadget.Stage2(analytics: analytics))
				                @Sendable func __safeDI_widgetBuilder_Inner_panelBuilder_widget_Stage2(_ scope: Inner.SafeDIStagedScope_Widget_panelBuilder_widget.Stage2) -> any Widget {
				                    let clock = scope.clock
				                    func __safeDI_widget() -> DefaultWidget {
				                        func __safeDI_part() -> Part {
				                            _ = Part.__safeDI_Part_8735560374A43092.self\(seamCallComment(seam: "Shell", module: "Feature"))
				                            return Part(gearBuilder: { __safeDI_gearSendableBuilder(.shell_Inner_panelBuilder_widget_part($0)) })
				                        }
				                        let part: Part = __safeDI_part()
				                        let gadget: any Gadget = __safeDI_gadgetBuilder_shell_Inner_panelBuilder_widget_gadget_Stage3(SafeDIStagedScope_Gadget_shell_Inner_panelBuilder_widget_gadget.Stage3(clock: clock, part: part))
				                        return DefaultWidget(analytics: analytics, gadget: gadget, part: part)
				                    }
				                    let widget: any Widget = __safeDI_widget()
				                    return widget
				                }
				                return __safeDI_widgetBuilder_Inner_panelBuilder_widget_Stage2
				            }
				            return Shell(widgetBuilder_Inner_panelBuilder_widget: __safeDI_widgetBuilder_Inner_panelBuilder_widget)
				        }
				        let shell: Shell = __safeDI_shell()
				        self.init(session: session, shell: shell)
				    }
				}

				extension Host {
				    public enum __safeDI_Host_75DD525ED99F9C65 {}
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
				        func __safeDI_host() -> Host {
				            _ = Host.__safeDI_Host_25297A734190213E.self\(seamCallComment(seam: "Host", module: "Middle"))
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
				            return Host(gadgetBuilder: __safeDI_gadgetBuilder_Host, gearBuilder: __safeDI_gearBuilder_Host)
				        }
				        let host: Host = __safeDI_host()
				        self.init(host: host)
				    }
				}
				"""
			case .sendableByRoute:
				"""
				extension Root {
				    public init() {
				        func __safeDI_host() -> Host {
				            _ = Host.__safeDI_Host_F6DD5C282F7A31F3.self\(seamCallComment(seam: "Host", module: "Middle"))
				            func __safeDI_gadgetBuilder_shell_Inner_widget_gadget(_ scope: Host.SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage1) -> @Sendable (Host.SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage2) -> any Gadget {
				                let session = scope.session
				                @Sendable func __safeDI_gadgetBuilder_shell_Inner_widget_gadget_Stage2(_ scope: Host.SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage2) -> any Gadget {
				                    let analytics = scope.analytics
				                    let gadget: any Gadget = DefaultGadget(session: session, analytics: analytics)
				                    return gadget
				                }
				                return __safeDI_gadgetBuilder_shell_Inner_widget_gadget_Stage2
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
				            return Host(gadgetBuilder_shell_Inner_widget_gadget: __safeDI_gadgetBuilder_shell_Inner_widget_gadget, gearSendableBuilder: __safeDI_gearSendableBuilder_Host)
				        }
				        let host: Host = __safeDI_host()
				        self.init(host: host)
				    }
				}
				"""
			case .lastStageOfStagedFill:
				"""
				extension Root {
				    public init() {
				        func __safeDI_host() -> Host {
				            _ = Host.__safeDI_Host_056A14C28200F753.self\(seamCallComment(seam: "Host", module: "Middle"))
				            func __safeDI_gadgetBuilder_inner_panelBuilder_widget_gadget(_ scope: Host.SafeDIStagedScope_Gadget_inner_panelBuilder_widget_gadget.Stage1) -> @Sendable (Host.SafeDIStagedScope_Gadget_inner_panelBuilder_widget_gadget.Stage2) -> any Gadget {
				                let session = scope.session
				                let analytics = scope.analytics
				                @Sendable func __safeDI_gadgetBuilder_inner_panelBuilder_widget_gadget_Stage2(_ scope: Host.SafeDIStagedScope_Gadget_inner_panelBuilder_widget_gadget.Stage2) -> any Gadget {
				                    let gadget: any Gadget = DefaultGadget(session: session, analytics: analytics)
				                    return gadget
				                }
				                return __safeDI_gadgetBuilder_inner_panelBuilder_widget_gadget_Stage2
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
				            return Host(gadgetBuilder_inner_panelBuilder_widget_gadget: __safeDI_gadgetBuilder_inner_panelBuilder_widget_gadget, gearSendableBuilder: __safeDI_gearSendableBuilder_Host)
				        }
				        let host: Host = __safeDI_host()
				        self.init(host: host)
				    }
				}
				"""
			case .stagedFillTakenSendable:
				"""
				extension Root {
				    public init() {
				        func __safeDI_host() -> Host {
				            _ = Host.__safeDI_Host_75DD525ED99F9C65.self\(seamCallComment(seam: "Host", module: "Middle"))
				            func __safeDI_gadgetBuilder_shell_Inner_panelBuilder_widget_gadget(_ scope: Host.SafeDIStagedScope_Gadget_shell_Inner_panelBuilder_widget_gadget.Stage1) -> @Sendable (Host.SafeDIStagedScope_Gadget_shell_Inner_panelBuilder_widget_gadget.Stage2) -> @Sendable (Host.SafeDIStagedScope_Gadget_shell_Inner_panelBuilder_widget_gadget.Stage3) -> any Gadget {
				                let session = scope.session
				                @Sendable func __safeDI_gadgetBuilder_shell_Inner_panelBuilder_widget_gadget_Stage2(_ scope: Host.SafeDIStagedScope_Gadget_shell_Inner_panelBuilder_widget_gadget.Stage2) -> @Sendable (Host.SafeDIStagedScope_Gadget_shell_Inner_panelBuilder_widget_gadget.Stage3) -> any Gadget {
				                    let analytics = scope.analytics
				                    @Sendable func __safeDI_gadgetBuilder_shell_Inner_panelBuilder_widget_gadget_Stage3(_ scope: Host.SafeDIStagedScope_Gadget_shell_Inner_panelBuilder_widget_gadget.Stage3) -> any Gadget {
				                        let gadget: any Gadget = DefaultGadget(session: session, analytics: analytics)
				                        return gadget
				                    }
				                    return __safeDI_gadgetBuilder_shell_Inner_panelBuilder_widget_gadget_Stage3
				                }
				                return __safeDI_gadgetBuilder_shell_Inner_panelBuilder_widget_gadget_Stage2
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
				            return Host(gadgetBuilder_shell_Inner_panelBuilder_widget_gadget: __safeDI_gadgetBuilder_shell_Inner_panelBuilder_widget_gadget, gearSendableBuilder: __safeDI_gearSendableBuilder_Host)
				        }
				        let host: Host = __safeDI_host()
				        self.init(host: host)
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
	private static let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let host: Host"])

	/// `Feature` declares `route`'s types; `Middle`'s `Host` fills `Widget`'s hole with `DefaultWidget`, whose declarations
	/// are `widgetDeclarations`; and `App` fills what `Host` passes up.
	private static func fixture(
		route: FillRoute,
		featureTypes: [String] = [],
		middleTypes: [String] = [],
		widgetDeclarations: [String] = ["@Received let analytics: Analytics", "@Instantiated let gadget: any Gadget", "@Instantiated let part: Part"],
		appTypes: [String] = [defaultGadget, defaultGear],
		root: String = root,
		widgetConformances: String = "Instantiable, Widget",
	) -> ThreeModules {
		ThreeModules(
			feature: route.featureTypes + gear + featureTypes,
			middle: [gadget, session] + middleTypes + [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: widgetDeclarations)
					.replacingOccurrences(of: "Instantiable, Widget", with: widgetConformances),
				seamFixtureType(named: "Host", isSeam: true, declarations: ["@Instantiated let session: Session", route.hostDeclaration]),
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
		try expectEveryModuleCompiled(output)
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	// MARK: A place in a fill, beneath further `@Sendable` functions

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_startsStageAtEachSendableFunction_whenPlaceIsBeneathSendableBuilderFunctionInsideSendableFill() async throws {
		// The fill is `@Sendable` by route, and `Holder` is built inside it in a `@Sendable` builder function.
		let fixture = Self.fixture(
			route: .sendableByRoute,
			middleTypes: [seamFixtureType(named: "Holder", declarations: ["@Received let analytics: Analytics", "@Instantiated let gadget: any Gadget"], conformances: ", Sendable")],
			widgetDeclarations: ["@Received let analytics: Analytics", "@Instantiated let holderBuilder: SendableInstantiator<Holder>"],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "Middle", imports: ["Feature"], rootFiles: ["Host": """
		extension Host {
		    public enum SafeDIStagedScope_Gadget_shell_Inner_widget_holderBuilder_gadget {
		        public struct Stage1 {
		            public let session: Session
		        }

		        public struct Stage2 {
		            public let analytics: Analytics
		        }

		        public struct Stage3 {}
		    }

		    public init(gadgetBuilder_shell_Inner_widget_holderBuilder_gadget: @escaping (SafeDIStagedScope_Gadget_shell_Inner_widget_holderBuilder_gadget.Stage1) -> @Sendable (SafeDIStagedScope_Gadget_shell_Inner_widget_holderBuilder_gadget.Stage2) -> @Sendable (SafeDIStagedScope_Gadget_shell_Inner_widget_holderBuilder_gadget.Stage3) -> any Gadget) {
		        let __safeDI_gadgetBuilder_shell_Inner_widget_holderBuilder_gadget = gadgetBuilder_shell_Inner_widget_holderBuilder_gadget
		        let session = Session()
		        func __safeDI_shell() -> Shell {
		            _ = Shell.__safeDI_Shell_076D60492DA3478F.self\(seamCallComment(seam: "Shell", module: "Feature"))
		            let __safeDI_gadgetBuilder_shell_Inner_widget_holderBuilder_gadget_Stage2 = __safeDI_gadgetBuilder_shell_Inner_widget_holderBuilder_gadget(SafeDIStagedScope_Gadget_shell_Inner_widget_holderBuilder_gadget.Stage1(session: session))
		            @Sendable func __safeDI_widgetBuilder_Inner_widget(_ scope: Inner.SafeDIScope_Widget.widget_Values) -> any Widget {
		                let analytics = scope.analytics
		                func __safeDI_widget() -> DefaultWidget {
		                    let __safeDI_gadgetBuilder_shell_Inner_widget_holderBuilder_gadget_Stage3 = __safeDI_gadgetBuilder_shell_Inner_widget_holderBuilder_gadget_Stage2(SafeDIStagedScope_Gadget_shell_Inner_widget_holderBuilder_gadget.Stage2(analytics: analytics))
		                    @Sendable func __safeDI_holderBuilder() -> Holder {
		                        let gadget: any Gadget = __safeDI_gadgetBuilder_shell_Inner_widget_holderBuilder_gadget_Stage3(SafeDIStagedScope_Gadget_shell_Inner_widget_holderBuilder_gadget.Stage3())
		                        return Holder(analytics: analytics, gadget: gadget)
		                    }
		                    let holderBuilder = SendableInstantiator<Holder>(__safeDI_holderBuilder)
		                    return DefaultWidget(analytics: analytics, holderBuilder: holderBuilder)
		                }
		                let widget: any Widget = __safeDI_widget()
		                return widget
		            }
		            @Sendable func __safeDI_widgetSendableBuilder_Shell(_ scope: Shell.SafeDISendableScope_Widget) -> any Widget {
		                switch scope {
		                case let .innerBuilder(scope): return __safeDI_widgetBuilder_Inner(scope)
		                }
		            }
		            @Sendable func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
		                switch scope {
		                case let .widget(scope): return __safeDI_widgetBuilder_Inner_widget(scope)
		                }
		            }
		            return Shell(widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell)
		        }
		        let shell: Shell = __safeDI_shell()
		        self.init(session: session, shell: shell)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_61C36CCD44E79BEB {}
		}
		"""])
		expectGeneratedCode(of: output, module: "App", imports: ["Feature", "Middle"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_61C36CCD44E79BEB.self\(seamCallComment(seam: "Host", module: "Middle"))
		            func __safeDI_gadgetBuilder_shell_Inner_widget_holderBuilder_gadget(_ scope: Host.SafeDIStagedScope_Gadget_shell_Inner_widget_holderBuilder_gadget.Stage1) -> @Sendable (Host.SafeDIStagedScope_Gadget_shell_Inner_widget_holderBuilder_gadget.Stage2) -> @Sendable (Host.SafeDIStagedScope_Gadget_shell_Inner_widget_holderBuilder_gadget.Stage3) -> any Gadget {
		                let session = scope.session
		                @Sendable func __safeDI_gadgetBuilder_shell_Inner_widget_holderBuilder_gadget_Stage2(_ scope: Host.SafeDIStagedScope_Gadget_shell_Inner_widget_holderBuilder_gadget.Stage2) -> @Sendable (Host.SafeDIStagedScope_Gadget_shell_Inner_widget_holderBuilder_gadget.Stage3) -> any Gadget {
		                    let analytics = scope.analytics
		                    @Sendable func __safeDI_gadgetBuilder_shell_Inner_widget_holderBuilder_gadget_Stage3(_ scope: Host.SafeDIStagedScope_Gadget_shell_Inner_widget_holderBuilder_gadget.Stage3) -> any Gadget {
		                        let gadget: any Gadget = DefaultGadget(session: session, analytics: analytics)
		                        return gadget
		                    }
		                    return __safeDI_gadgetBuilder_shell_Inner_widget_holderBuilder_gadget_Stage3
		                }
		                return __safeDI_gadgetBuilder_shell_Inner_widget_holderBuilder_gadget_Stage2
		            }
		            return Host(gadgetBuilder_shell_Inner_widget_holderBuilder_gadget: __safeDI_gadgetBuilder_shell_Inner_widget_holderBuilder_gadget)
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		try expectEveryModuleCompiled(output)
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_startsStageAtEachFill_whenPlaceIsInsideFillOfCallInsideAnotherSendableFill() async throws {
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
		    public enum SafeDIStagedScope_Gadget_shell_Inner_widget_deepShell_Deep_yarn_gadget {
		        public struct Stage1 {
		            public let session: Session
		        }

		        public struct Stage2 {
		            public let analytics: Analytics
		        }

		        public struct Stage3 {}
		    }

		    public init(gadgetBuilder_shell_Inner_widget_deepShell_Deep_yarn_gadget: @escaping (SafeDIStagedScope_Gadget_shell_Inner_widget_deepShell_Deep_yarn_gadget.Stage1) -> @Sendable (SafeDIStagedScope_Gadget_shell_Inner_widget_deepShell_Deep_yarn_gadget.Stage2) -> @Sendable (SafeDIStagedScope_Gadget_shell_Inner_widget_deepShell_Deep_yarn_gadget.Stage3) -> any Gadget) {
		        let __safeDI_gadgetBuilder_shell_Inner_widget_deepShell_Deep_yarn_gadget = gadgetBuilder_shell_Inner_widget_deepShell_Deep_yarn_gadget
		        let session = Session()
		        func __safeDI_shell() -> Shell {
		            _ = Shell.__safeDI_Shell_076D60492DA3478F.self\(seamCallComment(seam: "Shell", module: "Feature"))
		            let __safeDI_gadgetBuilder_shell_Inner_widget_deepShell_Deep_yarn_gadget_Stage2 = __safeDI_gadgetBuilder_shell_Inner_widget_deepShell_Deep_yarn_gadget(SafeDIStagedScope_Gadget_shell_Inner_widget_deepShell_Deep_yarn_gadget.Stage1(session: session))
		            @Sendable func __safeDI_widgetBuilder_Inner_widget(_ scope: Inner.SafeDIScope_Widget.widget_Values) -> any Widget {
		                let analytics = scope.analytics
		                func __safeDI_widget() -> DefaultWidget {
		                    func __safeDI_deepShell() -> DeepShell {
		                        _ = DeepShell.__safeDI_DeepShell_B58B4F4F25E9236A.self\(seamCallComment(seam: "Shell", module: "Feature"))
		                        let __safeDI_gadgetBuilder_shell_Inner_widget_deepShell_Deep_yarn_gadget_Stage3 = __safeDI_gadgetBuilder_shell_Inner_widget_deepShell_Deep_yarn_gadget_Stage2(SafeDIStagedScope_Gadget_shell_Inner_widget_deepShell_Deep_yarn_gadget.Stage2(analytics: analytics))
		                        @Sendable func __safeDI_yarnBuilder_Deep_yarn(_ scope: Deep.SafeDIScope_Yarn.yarn_Values) -> any Yarn {
		                            func __safeDI_yarn() -> DefaultYarn {
		                                let gadget: any Gadget = __safeDI_gadgetBuilder_shell_Inner_widget_deepShell_Deep_yarn_gadget_Stage3(SafeDIStagedScope_Gadget_shell_Inner_widget_deepShell_Deep_yarn_gadget.Stage3())
		                                return DefaultYarn(gadget: gadget)
		                            }
		                            let yarn: any Yarn = __safeDI_yarn()
		                            return yarn
		                        }
		                        @Sendable func __safeDI_yarnSendableBuilder_DeepShell(_ scope: DeepShell.SafeDISendableScope_Yarn) -> any Yarn {
		                            switch scope {
		                            case let .deepBuilder(scope): return __safeDI_yarnBuilder_Deep(scope)
		                            }
		                        }
		                        @Sendable func __safeDI_yarnBuilder_Deep(_ scope: Deep.SafeDIScope_Yarn) -> any Yarn {
		                            switch scope {
		                            case let .yarn(scope): return __safeDI_yarnBuilder_Deep_yarn(scope)
		                            }
		                        }
		                        return DeepShell(yarnSendableBuilder: __safeDI_yarnSendableBuilder_DeepShell)
		                    }
		                    let deepShell: DeepShell = __safeDI_deepShell()
		                    return DefaultWidget(deepShell: deepShell)
		                }
		                let widget: any Widget = __safeDI_widget()
		                return widget
		            }
		            @Sendable func __safeDI_widgetSendableBuilder_Shell(_ scope: Shell.SafeDISendableScope_Widget) -> any Widget {
		                switch scope {
		                case let .innerBuilder(scope): return __safeDI_widgetBuilder_Inner(scope)
		                }
		            }
		            @Sendable func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
		                switch scope {
		                case let .widget(scope): return __safeDI_widgetBuilder_Inner_widget(scope)
		                }
		            }
		            return Shell(widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell)
		        }
		        let shell: Shell = __safeDI_shell()
		        self.init(session: session, shell: shell)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_02867210AE3E6E25 {}
		}
		"""])
		expectGeneratedCode(of: output, module: "App", imports: ["Feature", "Middle"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_02867210AE3E6E25.self\(seamCallComment(seam: "Host", module: "Middle"))
		            func __safeDI_gadgetBuilder_shell_Inner_widget_deepShell_Deep_yarn_gadget(_ scope: Host.SafeDIStagedScope_Gadget_shell_Inner_widget_deepShell_Deep_yarn_gadget.Stage1) -> @Sendable (Host.SafeDIStagedScope_Gadget_shell_Inner_widget_deepShell_Deep_yarn_gadget.Stage2) -> @Sendable (Host.SafeDIStagedScope_Gadget_shell_Inner_widget_deepShell_Deep_yarn_gadget.Stage3) -> any Gadget {
		                let session = scope.session
		                @Sendable func __safeDI_gadgetBuilder_shell_Inner_widget_deepShell_Deep_yarn_gadget_Stage2(_ scope: Host.SafeDIStagedScope_Gadget_shell_Inner_widget_deepShell_Deep_yarn_gadget.Stage2) -> @Sendable (Host.SafeDIStagedScope_Gadget_shell_Inner_widget_deepShell_Deep_yarn_gadget.Stage3) -> any Gadget {
		                    @Sendable func __safeDI_gadgetBuilder_shell_Inner_widget_deepShell_Deep_yarn_gadget_Stage3(_ scope: Host.SafeDIStagedScope_Gadget_shell_Inner_widget_deepShell_Deep_yarn_gadget.Stage3) -> any Gadget {
		                        let gadget: any Gadget = DefaultGadget(session: session)
		                        return gadget
		                    }
		                    return __safeDI_gadgetBuilder_shell_Inner_widget_deepShell_Deep_yarn_gadget_Stage3
		                }
		                return __safeDI_gadgetBuilder_shell_Inner_widget_deepShell_Deep_yarn_gadget_Stage2
		            }
		            return Host(gadgetBuilder_shell_Inner_widget_deepShell_Deep_yarn_gadget: __safeDI_gadgetBuilder_shell_Inner_widget_deepShell_Deep_yarn_gadget)
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		try expectEveryModuleCompiled(output)
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
				    public enum SafeDIStagedScope_Gadget_shell_Inner_widget_gadget {
				        public struct Stage1 {
				            public let session: Session
				        }

				        public struct Stage2 {
				            public let analytics: Analytics
				        }
				    }

				    public init(gadgetBuilder_shell_Inner_widget_gadget: @escaping (SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage1) -> @Sendable (SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage2) -> any Gadget) {
				        let __safeDI_gadgetBuilder_shell_Inner_widget_gadget = gadgetBuilder_shell_Inner_widget_gadget
				        let session = Session()
				        func __safeDI_shell() -> Shell {
				            _ = Shell.__safeDI_Shell_076D60492DA3478F.self\(seamCallComment(seam: "Shell", module: "Feature"))
				            let __safeDI_gadgetBuilder_shell_Inner_widget_gadget_Stage2 = __safeDI_gadgetBuilder_shell_Inner_widget_gadget(SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage1(session: session))
				            @Sendable func __safeDI_widgetBuilder_Inner_widget(_ scope: Inner.SafeDIScope_Widget.widget_Values) -> any Widget {
				                let analytics = scope.analytics
				                func __safeDI_widget() -> DefaultWidget {
				                    func __safeDI_gadget() -> any Gadget {
				                        __safeDI_gadgetBuilder_shell_Inner_widget_gadget_Stage2(SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage2(analytics: analytics))
				                    }
				                    let gadget = LazilyInstantiated<any Gadget>(__safeDI_gadget)
				                    return DefaultWidget(analytics: analytics, gadget: gadget)
				                }
				                let widget: any Widget = __safeDI_widget()
				                return widget
				            }
				            @Sendable func __safeDI_widgetSendableBuilder_Shell(_ scope: Shell.SafeDISendableScope_Widget) -> any Widget {
				                switch scope {
				                case let .innerBuilder(scope): return __safeDI_widgetBuilder_Inner(scope)
				                }
				            }
				            @Sendable func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
				                switch scope {
				                case let .widget(scope): return __safeDI_widgetBuilder_Inner_widget(scope)
				                }
				            }
				            return Shell(widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell)
				        }
				        let shell: Shell = __safeDI_shell()
				        self.init(session: session, shell: shell)
				    }
				}

				extension Host {
				    public enum __safeDI_Host_C2B8446A21A9B91D {}
				}
				"""
			case .sendableLazilyInstantiated:
				"""
				extension Host {
				    public enum SafeDIStagedScope_Gadget_shell_Inner_widget_gadget {
				        public struct Stage1 {
				            public let session: Session
				        }

				        public struct Stage2 {
				            public let analytics: Analytics
				        }

				        public struct Stage3 {}
				    }

				    public init(gadgetBuilder_shell_Inner_widget_gadget: @escaping (SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage1) -> @Sendable (SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage2) -> @Sendable (SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage3) -> any Gadget) {
				        let __safeDI_gadgetBuilder_shell_Inner_widget_gadget = gadgetBuilder_shell_Inner_widget_gadget
				        let session = Session()
				        func __safeDI_shell() -> Shell {
				            _ = Shell.__safeDI_Shell_076D60492DA3478F.self\(seamCallComment(seam: "Shell", module: "Feature"))
				            let __safeDI_gadgetBuilder_shell_Inner_widget_gadget_Stage2 = __safeDI_gadgetBuilder_shell_Inner_widget_gadget(SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage1(session: session))
				            @Sendable func __safeDI_widgetBuilder_Inner_widget(_ scope: Inner.SafeDIScope_Widget.widget_Values) -> any Widget {
				                let analytics = scope.analytics
				                func __safeDI_widget() -> DefaultWidget {
				                    let __safeDI_gadgetBuilder_shell_Inner_widget_gadget_Stage3 = __safeDI_gadgetBuilder_shell_Inner_widget_gadget_Stage2(SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage2(analytics: analytics))
				                    @Sendable func __safeDI_gadget() -> any Gadget {
				                        __safeDI_gadgetBuilder_shell_Inner_widget_gadget_Stage3(SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage3())
				                    }
				                    let gadget = SendableLazilyInstantiated<any Gadget>(__safeDI_gadget)
				                    return DefaultWidget(analytics: analytics, gadget: gadget)
				                }
				                let widget: any Widget = __safeDI_widget()
				                return widget
				            }
				            @Sendable func __safeDI_widgetSendableBuilder_Shell(_ scope: Shell.SafeDISendableScope_Widget) -> any Widget {
				                switch scope {
				                case let .innerBuilder(scope): return __safeDI_widgetBuilder_Inner(scope)
				                }
				            }
				            @Sendable func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
				                switch scope {
				                case let .widget(scope): return __safeDI_widgetBuilder_Inner_widget(scope)
				                }
				            }
				            return Shell(widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell)
				        }
				        let shell: Shell = __safeDI_shell()
				        self.init(session: session, shell: shell)
				    }
				}

				extension Host {
				    public enum __safeDI_Host_198E2D9E98324E47 {}
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
				        func __safeDI_host() -> Host {
				            _ = Host.__safeDI_Host_C2B8446A21A9B91D.self\(seamCallComment(seam: "Host", module: "Middle"))
				            func __safeDI_gadgetBuilder_shell_Inner_widget_gadget(_ scope: Host.SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage1) -> @Sendable (Host.SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage2) -> any Gadget {
				                let session = scope.session
				                @Sendable func __safeDI_gadgetBuilder_shell_Inner_widget_gadget_Stage2(_ scope: Host.SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage2) -> any Gadget {
				                    let analytics = scope.analytics
				                    func __safeDI_gadget() -> DefaultGadget {
				                        DefaultGadget(session: session, analytics: analytics)
				                    }
				                    return __safeDI_gadget()
				                }
				                return __safeDI_gadgetBuilder_shell_Inner_widget_gadget_Stage2
				            }
				            return Host(gadgetBuilder_shell_Inner_widget_gadget: __safeDI_gadgetBuilder_shell_Inner_widget_gadget)
				        }
				        let host: Host = __safeDI_host()
				        self.init(host: host)
				    }
				}
				"""
			case .sendableLazilyInstantiated:
				"""
				extension Root {
				    public init() {
				        func __safeDI_host() -> Host {
				            _ = Host.__safeDI_Host_198E2D9E98324E47.self\(seamCallComment(seam: "Host", module: "Middle"))
				            func __safeDI_gadgetBuilder_shell_Inner_widget_gadget(_ scope: Host.SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage1) -> @Sendable (Host.SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage2) -> @Sendable (Host.SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage3) -> any Gadget {
				                let session = scope.session
				                @Sendable func __safeDI_gadgetBuilder_shell_Inner_widget_gadget_Stage2(_ scope: Host.SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage2) -> @Sendable (Host.SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage3) -> any Gadget {
				                    let analytics = scope.analytics
				                    @Sendable func __safeDI_gadgetBuilder_shell_Inner_widget_gadget_Stage3(_ scope: Host.SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage3) -> any Gadget {
				                        @Sendable func __safeDI_gadget() -> DefaultGadget {
				                            DefaultGadget(session: session, analytics: analytics)
				                        }
				                        return __safeDI_gadget()
				                    }
				                    return __safeDI_gadgetBuilder_shell_Inner_widget_gadget_Stage3
				                }
				                return __safeDI_gadgetBuilder_shell_Inner_widget_gadget_Stage2
				            }
				            return Host(gadgetBuilder_shell_Inner_widget_gadget: __safeDI_gadgetBuilder_shell_Inner_widget_gadget)
				        }
				        let host: Host = __safeDI_host()
				        self.init(host: host)
				    }
				}
				"""
			}
		}
	}

	@Test(arguments: PlaceWrapper.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_stagesBuilderOfWrapper_whenPlaceInsideSendableFillIsWrapper(wrapper: PlaceWrapper) async throws {
		let fixture = Self.fixture(route: .sendableByRoute, widgetDeclarations: ["@Received let analytics: Analytics", wrapper.declaration])
		// `@unchecked`, as the fuzzer's mixed-wrapper graphs mark their types: `DefaultWidget` holds a `LazilyInstantiated`.
		let adjusted = ThreeModules(feature: fixture.feature, middle: fixture.middle.map { $0.replacingOccurrences(of: "Instantiable, Widget", with: "Instantiable, Widget, @unchecked Sendable") }, app: fixture.app, root: fixture.root)
		let output = try await executeSafeDIToolMultiModuleTest(modules: adjusted.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "Middle", imports: ["Feature"], rootFiles: ["Host": wrapper.hostCode])
		expectGeneratedCode(of: output, module: "App", imports: ["Feature", "Middle"], rootFiles: ["Root": wrapper.rootCode])
		try expectEveryModuleCompiled(output)
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
		            _ = Top.__safeDI_Top_0073276940F34EB1.self\(seamCallComment(seam: "Top", module: "Feature"))
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
		                            _ = SubB.__safeDI_SubB_3FE2E3B686B63FF2.self\(seamCallComment(seam: "Top", module: "Feature"))
		                            return SubB(secondBuilder: __safeDI_secondBuilder_SubB)
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
		                case let .subB(scope): return __safeDI_secondBuilder_SubB(scope)
		                }
		            }
		            @Sendable func __safeDI_secondBuilder_SubB(_ scope: SubB.SafeDIScope_Second) -> any Second {
		                switch scope {
		                case .second:
		                    func __safeDI_second() -> DefaultSecond {
		                        func __safeDI_subC() -> SubC {
		                            _ = SubC.__safeDI_SubC_D44B97D8B84C631C.self\(seamCallComment(seam: "Top", module: "Feature"))
		                            return SubC(thirdBuilder: __safeDI_thirdBuilder_SubC)
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
		                case let .subC(scope): return __safeDI_thirdBuilder_SubC(scope)
		                }
		            }
		            @Sendable func __safeDI_thirdBuilder_SubC(_ scope: SubC.SafeDIScope_Third) -> any Third {
		                switch scope {
		                case .third:
		                    let third: any Third = DefaultThird()
		                    return third
		                }
		            }
		            return Top(firstSendableBuilder: __safeDI_firstSendableBuilder_Top, secondBuilder: __safeDI_secondBuilder_Top, thirdBuilder: __safeDI_thirdBuilder_Top)
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}
		"""])
		try expectEveryModuleCompiled(output)
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
		            _ = Top.__safeDI_Top_9DA066B47A13D238.self\(seamCallComment(seam: "Top", module: "Feature"))
		            func __safeDI_firstBuilder_Top(_ scope: Top.SafeDIScope_First) -> any First {
		                switch scope {
		                case let .subA(scope): return __safeDI_firstBuilder_SubA(scope)
		                }
		            }
		            func __safeDI_firstBuilder_SubA(_ scope: SubA.SafeDIScope_First) -> any First {
		                switch scope {
		                case .first:
		                    func __safeDI_first() -> DefaultFirst {
		                        func __safeDI_thirdShell() -> ThirdShell {
		                            _ = ThirdShell.__safeDI_ThirdShell_D1039470AE38B38A.self\(seamCallComment(seam: "Top", module: "Feature"))
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
		                                            _ = SubB.__safeDI_SubB_3FE2E3B686B63FF2.self\(seamCallComment(seam: "Top", module: "Feature"))
		                                            return SubB(secondBuilder: __safeDI_secondBuilder_SubB)
		                                        }
		                                        let subB: SubB = __safeDI_subB()
		                                        return DefaultThird(subB: subB)
		                                    }
		                                    let third: any Third = __safeDI_third()
		                                    return third
		                                }
		                            }
		                            return ThirdShell(thirdSendableBuilder: __safeDI_thirdSendableBuilder_ThirdShell)
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
		                case let .subB(scope): return __safeDI_secondBuilder_SubB(scope)
		                }
		            }
		            @Sendable func __safeDI_secondBuilder_SubB(_ scope: SubB.SafeDIScope_Second) -> any Second {
		                switch scope {
		                case .second:
		                    let second: any Second = DefaultSecond()
		                    return second
		                }
		            }
		            return Top(firstBuilder: __safeDI_firstBuilder_Top, secondBuilder: __safeDI_secondBuilder_Top)
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}
		"""])
		try expectEveryModuleCompiled(output)
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
				seamFixtureType(named: "Host", isSeam: true, declarations: ["@Instantiated let session: Session", FillRoute.sendableByRoute.hostDeclaration]),
			],
			app: [SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultGadget", fulfilling: "Gadget", declarations: ["@Received let user: User"])],
			root: seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let user: SendableLazilyInstantiated<User>", "@Instantiated let host: Host"]),
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "Middle", imports: ["Feature"], rootFiles: ["Host": """
		extension Host {
		    public enum SafeDIStagedScope_Gadget_shell_Inner_widget_gadget {
		        public struct Stage1 {
		            public var user: User { __safeDI_user.instance }
		            public let session: Session
		            let __safeDI_user: LazilyInstantiated<User>

		            init(user: LazilyInstantiated<User>, session: Session) {
		                __safeDI_user = user
		                self.session = session
		            }
		        }

		        public struct Stage2 {
		            public let analytics: Analytics
		        }
		    }

		    public init(user: User, gadgetBuilder_shell_Inner_widget_gadget: @escaping (SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage1) -> @Sendable (SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage2) -> any Gadget) {
		        self.init(__safeDI_user: user, __safeDI_gadgetBuilder_shell_Inner_widget_gadget: gadgetBuilder_shell_Inner_widget_gadget)
		    }

		    public init(__safeDI_user: @autoclosure @escaping () -> User, __safeDI_gadgetBuilder_shell_Inner_widget_gadget: @escaping (SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage1) -> @Sendable (SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage2) -> any Gadget) {
		        let user = LazilyInstantiated<User>(__safeDI_user)
		        let session = Session(user: user.instance)
		        func __safeDI_shell() -> Shell {
		            _ = Shell.__safeDI_Shell_076D60492DA3478F.self\(seamCallComment(seam: "Shell", module: "Feature"))
		            let __safeDI_gadgetBuilder_shell_Inner_widget_gadget_Stage2 = __safeDI_gadgetBuilder_shell_Inner_widget_gadget(SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage1(user: user, session: session))
		            @Sendable func __safeDI_widgetBuilder_Inner_widget(_ scope: Inner.SafeDIScope_Widget.widget_Values) -> any Widget {
		                let analytics = scope.analytics
		                func __safeDI_widget() -> DefaultWidget {
		                    let gadget: any Gadget = __safeDI_gadgetBuilder_shell_Inner_widget_gadget_Stage2(SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage2(analytics: analytics))
		                    return DefaultWidget(gadget: gadget)
		                }
		                let widget: any Widget = __safeDI_widget()
		                return widget
		            }
		            @Sendable func __safeDI_widgetSendableBuilder_Shell(_ scope: Shell.SafeDISendableScope_Widget) -> any Widget {
		                switch scope {
		                case let .innerBuilder(scope): return __safeDI_widgetBuilder_Inner(scope)
		                }
		            }
		            @Sendable func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
		                switch scope {
		                case let .widget(scope): return __safeDI_widgetBuilder_Inner_widget(scope)
		                }
		            }
		            return Shell(widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell)
		        }
		        let shell: Shell = __safeDI_shell()
		        self.init(session: session, shell: shell)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_DFBE8C3E8F0DC668 {}
		}
		"""])
		expectGeneratedCode(of: output, module: "App", imports: ["Feature", "Middle"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        @Sendable func __safeDI_user() -> User {
		            User()
		        }
		        let user = SendableLazilyInstantiated<User>(__safeDI_user)
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_DFBE8C3E8F0DC668.self\(seamCallComment(seam: "Host", module: "Middle"))
		            func __safeDI_gadgetBuilder_shell_Inner_widget_gadget(_ scope: Host.SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage1) -> @Sendable (Host.SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage2) -> any Gadget {
		                @Sendable func __safeDI_gadgetBuilder_shell_Inner_widget_gadget_Stage2(_ scope: Host.SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage2) -> any Gadget {
		                    let gadget: any Gadget = DefaultGadget(user: user.instance)
		                    return gadget
		                }
		                return __safeDI_gadgetBuilder_shell_Inner_widget_gadget_Stage2
		            }
		            return Host(__safeDI_user: user.instance, __safeDI_gadgetBuilder_shell_Inner_widget_gadget: __safeDI_gadgetBuilder_shell_Inner_widget_gadget)
		        }
		        let host: Host = __safeDI_host()
		        self.init(user: user, host: host)
		    }
		}
		"""])
		try expectEveryModuleCompiled(output)
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

		    public init(gadgetBuilder: @escaping (SafeDIScope_Gadget) -> any Gadget, gadgetSendableBuilder: @escaping @Sendable (SafeDISendableScope_Gadget) -> any Gadget) {
		        let __safeDI_gadgetBuilder = gadgetBuilder
		        let __safeDI_gadgetSendableBuilder = gadgetSendableBuilder
		        func __safeDI_shell() -> Shell {
		            _ = Shell.__safeDI_Shell_076D60492DA3478F.self\(seamCallComment(seam: "Shell", module: "Feature"))
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
		                            _ = Host.__safeDI_Host_8E411E9DE3820C17.self
		                            return Host(gadgetBuilder: { __safeDI_gadgetSendableBuilder(.shell_Inner_widget_hostBuilder($0)) }, gadgetSendableBuilder: { __safeDI_gadgetSendableBuilder(.shell_Inner_widget_hostBuilder_Sendable($0)) })
		                        }
		                        let hostBuilder = Instantiator<Host>(__safeDI_hostBuilder)
		                        return DefaultWidget(hostBuilder: hostBuilder)
		                    }
		                    let widget: any Widget = __safeDI_widget()
		                    return widget
		                }
		            }
		            return Shell(widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell)
		        }
		        let shell: Shell = __safeDI_shell()
		        let gadget: any Gadget = __safeDI_gadgetBuilder(.gadget(SafeDIScope_Gadget.gadget_Values(shell: shell)))
		        self.init(gadget: gadget, shell: shell)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_8E411E9DE3820C17 {}
		}
		"""])
		expectGeneratedCode(of: output, module: "App", imports: ["Feature", "Middle"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_8E411E9DE3820C17.self\(seamCallComment(seam: "Host", module: "Middle"))
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
		            return Host(gadgetBuilder: __safeDI_gadgetBuilder_Host, gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_Host)
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		try expectEveryModuleCompiled(output)
	}

	// MARK: Shapes beside these, which compiled before a fill counted as a `@Sendable` function

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_doesNotStagePlace_whenPlaceIsBeneathPlainInstantiatorInsidePlainFill() async throws {
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

		    public init(gadgetBuilder: @escaping (SafeDIScope_Gadget) -> any Gadget) {
		        let __safeDI_gadgetBuilder = gadgetBuilder
		        let session = Session()
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_A441BC75156D061F.self\(seamCallComment(seam: "Inner", module: "Feature"))
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
		            return Inner(widgetBuilder: __safeDI_widgetBuilder_Inner)
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(session: session, inner: inner)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_52446D1F6D568C46 {}
		}
		"""])
		expectGeneratedCode(of: output, module: "App", imports: ["Feature", "Middle"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_52446D1F6D568C46.self\(seamCallComment(seam: "Host", module: "Middle"))
		            func __safeDI_gadgetBuilder_Host(_ scope: Host.SafeDIScope_Gadget) -> any Gadget {
		                switch scope {
		                case let .inner_widget_holderBuilder_gadget(scope):
		                    let session = scope.session
		                    let analytics = scope.analytics
		                    let gadget: any Gadget = DefaultGadget(session: session, analytics: analytics)
		                    return gadget
		                }
		            }
		            return Host(gadgetBuilder: __safeDI_gadgetBuilder_Host)
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_startsStageAtBuilderFunctionOnly_whenPlaceIsBeneathSendableBuilderFunctionInsidePlainFill() async throws {
		let fixture = Self.fixture(
			route: .plain,
			middleTypes: [seamFixtureType(named: "Holder", declarations: ["@Received let analytics: Analytics", "@Instantiated let gadget: any Gadget"], conformances: ", Sendable")],
			widgetDeclarations: ["@Received let analytics: Analytics", "@Instantiated let holderBuilder: SendableInstantiator<Holder>"],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "Middle", imports: ["Feature"], rootFiles: ["Host": """
		extension Host {
		    public enum SafeDIStagedScope_Gadget_inner_widget_holderBuilder_gadget {
		        public struct Stage1 {
		            public let session: Session
		            public let analytics: Analytics
		        }

		        public struct Stage2 {}
		    }

		    public init(gadgetBuilder_inner_widget_holderBuilder_gadget: @escaping (SafeDIStagedScope_Gadget_inner_widget_holderBuilder_gadget.Stage1) -> @Sendable (SafeDIStagedScope_Gadget_inner_widget_holderBuilder_gadget.Stage2) -> any Gadget) {
		        let __safeDI_gadgetBuilder_inner_widget_holderBuilder_gadget = gadgetBuilder_inner_widget_holderBuilder_gadget
		        let session = Session()
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_A441BC75156D061F.self\(seamCallComment(seam: "Inner", module: "Feature"))
		            func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
		                switch scope {
		                case let .widget(scope):
		                    let analytics = scope.analytics
		                    func __safeDI_widget() -> DefaultWidget {
		                        let __safeDI_gadgetBuilder_inner_widget_holderBuilder_gadget_Stage2 = __safeDI_gadgetBuilder_inner_widget_holderBuilder_gadget(SafeDIStagedScope_Gadget_inner_widget_holderBuilder_gadget.Stage1(session: session, analytics: analytics))
		                        @Sendable func __safeDI_holderBuilder() -> Holder {
		                            let gadget: any Gadget = __safeDI_gadgetBuilder_inner_widget_holderBuilder_gadget_Stage2(SafeDIStagedScope_Gadget_inner_widget_holderBuilder_gadget.Stage2())
		                            return Holder(analytics: analytics, gadget: gadget)
		                        }
		                        let holderBuilder = SendableInstantiator<Holder>(__safeDI_holderBuilder)
		                        return DefaultWidget(analytics: analytics, holderBuilder: holderBuilder)
		                    }
		                    let widget: any Widget = __safeDI_widget()
		                    return widget
		                }
		            }
		            return Inner(widgetBuilder: __safeDI_widgetBuilder_Inner)
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(session: session, inner: inner)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_9AA85E597E4A6132 {}
		}
		"""])
		expectGeneratedCode(of: output, module: "App", imports: ["Feature", "Middle"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_9AA85E597E4A6132.self\(seamCallComment(seam: "Host", module: "Middle"))
		            func __safeDI_gadgetBuilder_inner_widget_holderBuilder_gadget(_ scope: Host.SafeDIStagedScope_Gadget_inner_widget_holderBuilder_gadget.Stage1) -> @Sendable (Host.SafeDIStagedScope_Gadget_inner_widget_holderBuilder_gadget.Stage2) -> any Gadget {
		                let session = scope.session
		                let analytics = scope.analytics
		                @Sendable func __safeDI_gadgetBuilder_inner_widget_holderBuilder_gadget_Stage2(_ scope: Host.SafeDIStagedScope_Gadget_inner_widget_holderBuilder_gadget.Stage2) -> any Gadget {
		                    let gadget: any Gadget = DefaultGadget(session: session, analytics: analytics)
		                    return gadget
		                }
		                return __safeDI_gadgetBuilder_inner_widget_holderBuilder_gadget_Stage2
		            }
		            return Host(gadgetBuilder_inner_widget_holderBuilder_gadget: __safeDI_gadgetBuilder_inner_widget_holderBuilder_gadget)
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		try expectEveryModuleCompiled(output)
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
			root: Self.root,
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "Middle", imports: ["Feature"], rootFiles: ["Host": """
		extension Host {
		    public init() {
		        let session = Session()
		        func __safeDI_shell() -> Shell {
		            _ = Shell.__safeDI_Shell_076D60492DA3478F.self\(seamCallComment(seam: "Shell", module: "Feature"))
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
		                            _ = Part.__safeDI_Part_8735560374A43092.self\(seamCallComment(seam: "Shell", module: "Feature"))
		                            func __safeDI_gearBuilder_Part(_ scope: Part.SafeDIScope_Gear) -> any Gear {
		                                switch scope {
		                                case .gear:
		                                    let gear: any Gear = DefaultGear()
		                                    return gear
		                                }
		                            }
		                            return Part(gearBuilder: __safeDI_gearBuilder_Part)
		                        }
		                        let part: Part = __safeDI_part()
		                        return DefaultWidget(part: part)
		                    }
		                    let widget: any Widget = __safeDI_widget()
		                    return widget
		                }
		            }
		            return Shell(widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell)
		        }
		        let shell: Shell = __safeDI_shell()
		        self.init(session: session, shell: shell)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_CBF29CE484222325 {}
		}
		"""])
		expectGeneratedCode(of: output, module: "App", imports: ["Feature", "Middle"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_CBF29CE484222325.self\(seamCallComment(seam: "Host", module: "Middle"))
		            return Host()
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		try expectEveryModuleCompiled(output)
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_addsNoStage_whenStagedFillHoldsNoPlaceOrCall() async throws {
		let fixture = Self.fixture(route: .lastStageOfStagedFill, widgetDeclarations: ["@Received let analytics: Analytics", "@Received let clock: Clock"], appTypes: [])
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "Middle", imports: ["Feature"], rootFiles: ["Host": """
		extension Host {
		    public init() {
		        let session = Session()
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_702BBF403C09CE6C.self\(seamCallComment(seam: "Inner", module: "Feature"))
		            func __safeDI_widgetBuilder_panelBuilder_widget(_ scope: Inner.SafeDIStagedScope_Widget_panelBuilder_widget.Stage1) -> @Sendable (Inner.SafeDIStagedScope_Widget_panelBuilder_widget.Stage2) -> any Widget {
		                let analytics = scope.analytics
		                @Sendable func __safeDI_widgetBuilder_panelBuilder_widget_Stage2(_ scope: Inner.SafeDIStagedScope_Widget_panelBuilder_widget.Stage2) -> any Widget {
		                    let clock = scope.clock
		                    let widget: any Widget = DefaultWidget(analytics: analytics, clock: clock)
		                    return widget
		                }
		                return __safeDI_widgetBuilder_panelBuilder_widget_Stage2
		            }
		            return Inner(widgetBuilder_panelBuilder_widget: __safeDI_widgetBuilder_panelBuilder_widget)
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(session: session, inner: inner)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_CBF29CE484222325 {}
		}
		"""])
		expectGeneratedCode(of: output, module: "App", imports: ["Feature", "Middle"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_CBF29CE484222325.self\(seamCallComment(seam: "Host", module: "Middle"))
		            return Host()
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		try expectEveryModuleCompiled(output)
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
		    public enum SafeDIStagedScope_Gadget_topBuilder_SubB_second_gadget {
		        public struct Stage1 {}

		        public struct Stage2 {}
		    }

		    public init(gadgetBuilder_topBuilder_SubB_second_gadget: @escaping (SafeDIStagedScope_Gadget_topBuilder_SubB_second_gadget.Stage1) -> @Sendable (SafeDIStagedScope_Gadget_topBuilder_SubB_second_gadget.Stage2) -> any Gadget) {
		        let __safeDI_gadgetBuilder_topBuilder_SubB_second_gadget = gadgetBuilder_topBuilder_SubB_second_gadget
		        let __safeDI_gadgetBuilder_topBuilder_SubB_second_gadget_Stage2 = __safeDI_gadgetBuilder_topBuilder_SubB_second_gadget(SafeDIStagedScope_Gadget_topBuilder_SubB_second_gadget.Stage1())
		        @Sendable func __safeDI_topBuilder() -> Top {
		            _ = Top.__safeDI_Top_9DA066B47A13D238.self\(seamCallComment(seam: "Top", module: "Feature"))
		            func __safeDI_firstBuilder_Top(_ scope: Top.SafeDIScope_First) -> any First {
		                switch scope {
		                case let .subA(scope): return __safeDI_firstBuilder_SubA(scope)
		                }
		            }
		            func __safeDI_firstBuilder_SubA(_ scope: SubA.SafeDIScope_First) -> any First {
		                switch scope {
		                case .first:
		                    func __safeDI_first() -> DefaultFirst {
		                        func __safeDI_subB() -> SubB {
		                            _ = SubB.__safeDI_SubB_3FE2E3B686B63FF2.self\(seamCallComment(seam: "Top", module: "Feature"))
		                            return SubB(secondBuilder: __safeDI_secondBuilder_SubB)
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
		                case let .subB(scope): return __safeDI_secondBuilder_SubB(scope)
		                }
		            }
		            func __safeDI_secondBuilder_SubB(_ scope: SubB.SafeDIScope_Second) -> any Second {
		                switch scope {
		                case .second:
		                    func __safeDI_second() -> DefaultSecond {
		                        let gadget: any Gadget = __safeDI_gadgetBuilder_topBuilder_SubB_second_gadget_Stage2(SafeDIStagedScope_Gadget_topBuilder_SubB_second_gadget.Stage2())
		                        return DefaultSecond(gadget: gadget)
		                    }
		                    let second: any Second = __safeDI_second()
		                    return second
		                }
		            }
		            return Top(firstBuilder: __safeDI_firstBuilder_Top, secondBuilder: __safeDI_secondBuilder_Top)
		        }
		        let topBuilder = SendableInstantiator<Top>(__safeDI_topBuilder)
		        self.init(topBuilder: topBuilder)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_9E9D9EBB91B93B33 {}
		}
		"""])
		try expectEveryModuleCompiled(output)
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
		            _ = Top.__safeDI_Top_9DA066B47A13D238.self\(seamCallComment(seam: "Top", module: "Feature"))
		            func __safeDI_firstBuilder_Top(_ scope: Top.SafeDIScope_First) -> any First {
		                switch scope {
		                case let .subA(scope): return __safeDI_firstBuilder_SubA(scope)
		                }
		            }
		            func __safeDI_firstBuilder_SubA(_ scope: SubA.SafeDIScope_First) -> any First {
		                switch scope {
		                case .first:
		                    func __safeDI_first() -> DefaultFirst {
		                        @Sendable func __safeDI_subBBuilder() -> SubB {
		                            _ = SubB.__safeDI_SubB_3FE2E3B686B63FF2.self\(seamCallComment(seam: "Top", module: "Feature"))
		                            return SubB(secondBuilder: __safeDI_secondBuilder_SubB)
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
		                case let .subB(scope): return __safeDI_secondBuilder_SubB(scope)
		                }
		            }
		            @Sendable func __safeDI_secondBuilder_SubB(_ scope: SubB.SafeDIScope_Second) -> any Second {
		                switch scope {
		                case .second:
		                    let second: any Second = DefaultSecond()
		                    return second
		                }
		            }
		            return Top(firstBuilder: __safeDI_firstBuilder_Top, secondBuilder: __safeDI_secondBuilder_Top)
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}
		"""])
		try expectEveryModuleCompiled(output)
	}

	// MARK: A place in a `@Sendable` fill whose builder is `@Sendable` for another reason

	/// `Host`, which holds `hostDeclarations`, calls `Shell` with a fill by `DefaultWidget`, which holds `widgetDeclarations`
	/// and builds `gadget`, a place of `Host`, inside a `@Sendable` function.
	private static func fixtureOfSendableFillWithPlace(
		widgetConformances: String = "Instantiable, Widget",
		widgetDeclarations: [String] = ["@Received let analytics: Analytics", "@Instantiated let gadget: any Gadget"],
		middleTypes: [String] = [],
		hostDeclarations: [String] = ["@Instantiated let session: Session", FillRoute.sendableByRoute.hostDeclaration],
		session sessionType: String = session,
		hostConformances: String = ", Sendable",
		gadgetDeclarations: [String] = ["@Received let session: Session", "@Received let analytics: Analytics"],
		root: String = root,
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
	mutating func generate_startsStageAtFill_whenBuilderIsSendableBecauseSendableBuilderFunctionInFillReentersSeam() async throws {
		// A call of `Host` in a `SendableInstantiator` inside the fill takes `gadgetBuilder` `@Sendable`, so the fill could
		// capture the builder, but it could not capture `session`, which is not `Sendable`: only a stage called before the
		// fill can hand that over, and SafeDI cannot tell which values are `Sendable`.
		let fixture = Self.fixtureOfSendableFillWithPlace(
			widgetDeclarations: ["@Received let analytics: Analytics", "@Instantiated let gadget: any Gadget", "@Instantiated let hostBuilder: SendableInstantiator<Host>"],
			session: seamFixtureType(named: "Session", declarations: [], conformances: ""),
			hostConformances: ", @unchecked Sendable",
			gadgetDeclarations: ["@Received let analytics: Analytics"],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "Middle", imports: ["Feature"], rootFiles: ["Host": """
		extension Host {
		    public enum SafeDIStagedScope_Gadget_shell_Inner_widget_gadget {
		        public struct Stage1 {
		            public let session: Session
		        }

		        public struct Stage2 {
		            public let analytics: Analytics
		            public let hostBuilder: SendableInstantiator<Host>
		        }
		    }

		    public init(gadgetBuilder_shell_Inner_widget_gadget: @escaping @Sendable (SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage1) -> @Sendable (SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage2) -> any Gadget) {
		        let __safeDI_gadgetBuilder_shell_Inner_widget_gadget = gadgetBuilder_shell_Inner_widget_gadget
		        let session = Session()
		        func __safeDI_shell() -> Shell {
		            _ = Shell.__safeDI_Shell_076D60492DA3478F.self\(seamCallComment(seam: "Shell", module: "Feature"))
		            let __safeDI_gadgetBuilder_shell_Inner_widget_gadget_Stage2 = __safeDI_gadgetBuilder_shell_Inner_widget_gadget(SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage1(session: session))
		            @Sendable func __safeDI_widgetBuilder_Inner_widget(_ scope: Inner.SafeDIScope_Widget.widget_Values) -> any Widget {
		                let analytics = scope.analytics
		                func __safeDI_widget() -> DefaultWidget {
		                    @Sendable func __safeDI_hostBuilder() -> Host {
		                        _ = Host.__safeDI_Host_F66F1171C60658AE.self
		                        return Host(gadgetBuilder_shell_Inner_widget_gadget: __safeDI_gadgetBuilder_shell_Inner_widget_gadget)
		                    }
		                    let hostBuilder = SendableInstantiator<Host>(__safeDI_hostBuilder)
		                    let gadget: any Gadget = __safeDI_gadgetBuilder_shell_Inner_widget_gadget_Stage2(SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage2(analytics: analytics, hostBuilder: hostBuilder))
		                    return DefaultWidget(analytics: analytics, gadget: gadget, hostBuilder: hostBuilder)
		                }
		                let widget: any Widget = __safeDI_widget()
		                return widget
		            }
		            @Sendable func __safeDI_widgetSendableBuilder_Shell(_ scope: Shell.SafeDISendableScope_Widget) -> any Widget {
		                switch scope {
		                case let .innerBuilder(scope): return __safeDI_widgetBuilder_Inner(scope)
		                }
		            }
		            @Sendable func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
		                switch scope {
		                case let .widget(scope): return __safeDI_widgetBuilder_Inner_widget(scope)
		                }
		            }
		            return Shell(widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell)
		        }
		        let shell: Shell = __safeDI_shell()
		        self.init(session: session, shell: shell)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_F66F1171C60658AE {}
		}
		"""])
		expectGeneratedCode(of: output, module: "App", imports: ["Feature", "Middle"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_F66F1171C60658AE.self\(seamCallComment(seam: "Host", module: "Middle"))
		            @Sendable func __safeDI_gadgetBuilder_shell_Inner_widget_gadget(_ scope: Host.SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage1) -> @Sendable (Host.SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage2) -> any Gadget {
		                @Sendable func __safeDI_gadgetBuilder_shell_Inner_widget_gadget_Stage2(_ scope: Host.SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage2) -> any Gadget {
		                    let analytics = scope.analytics
		                    let gadget: any Gadget = DefaultGadget(analytics: analytics)
		                    return gadget
		                }
		                return __safeDI_gadgetBuilder_shell_Inner_widget_gadget_Stage2
		            }
		            return Host(gadgetBuilder_shell_Inner_widget_gadget: __safeDI_gadgetBuilder_shell_Inner_widget_gadget)
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		try expectEveryModuleCompiled(output)
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_startsStageAtFill_whenBuilderIsSendableBecauseSeamCalledInFillPassesItBackSendable() async throws {
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
			    public enum SafeDIStagedScope_Gadget_shell_Inner_widget_gadget {
			        public struct Stage1 {
			            public let session: Session
			        }

			        public struct Stage2 {
			            public let analytics: Analytics
			            public let otherBuilder: Instantiator<Other>
			        }
			    }

			    public init(gadgetBuilder_shell_Inner_widget_gadget: @escaping @Sendable (SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage1) -> @Sendable (SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage2) -> any Gadget) {
			        let __safeDI_gadgetBuilder_shell_Inner_widget_gadget = gadgetBuilder_shell_Inner_widget_gadget
			        let session = Session()
			        func __safeDI_shell() -> Shell {
			            _ = Shell.__safeDI_Shell_076D60492DA3478F.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            let __safeDI_gadgetBuilder_shell_Inner_widget_gadget_Stage2 = __safeDI_gadgetBuilder_shell_Inner_widget_gadget(SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage1(session: session))
			            @Sendable func __safeDI_widgetBuilder_Inner_widget(_ scope: Inner.SafeDIScope_Widget.widget_Values) -> any Widget {
			                let analytics = scope.analytics
			                func __safeDI_widget() -> DefaultWidget {
			                    func __safeDI_otherBuilder() -> Other {
			                        _ = Other.__safeDI_Other_709165532C0D2BF1.self
			                        return Other(gadgetBuilder_Host_shell_Inner_widget_gadget: __safeDI_gadgetBuilder_shell_Inner_widget_gadget)
			                    }
			                    let otherBuilder = Instantiator<Other>(__safeDI_otherBuilder)
			                    let gadget: any Gadget = __safeDI_gadgetBuilder_shell_Inner_widget_gadget_Stage2(SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage2(analytics: analytics, otherBuilder: otherBuilder))
			                    return DefaultWidget(analytics: analytics, gadget: gadget, otherBuilder: otherBuilder)
			                }
			                let widget: any Widget = __safeDI_widget()
			                return widget
			            }
			            @Sendable func __safeDI_widgetSendableBuilder_Shell(_ scope: Shell.SafeDISendableScope_Widget) -> any Widget {
			                switch scope {
			                case let .innerBuilder(scope): return __safeDI_widgetBuilder_Inner(scope)
			                }
			            }
			            @Sendable func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
			                switch scope {
			                case let .widget(scope): return __safeDI_widgetBuilder_Inner_widget(scope)
			                }
			            }
			            return Shell(widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell)
			        }
			        let shell: Shell = __safeDI_shell()
			        self.init(session: session, shell: shell)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_1DD0F476D3B3F944 {}
			}
			""",
			"Other": """
			extension Other {
			    public init(gadgetBuilder_Host_shell_Inner_widget_gadget: @escaping @Sendable (Host.SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage1) -> @Sendable (Host.SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage2) -> any Gadget) {
			        let __safeDI_gadgetBuilder_Host_shell_Inner_widget_gadget = gadgetBuilder_Host_shell_Inner_widget_gadget
			        @Sendable func __safeDI_hostBuilder() -> Host {
			            _ = Host.__safeDI_Host_1DD0F476D3B3F944.self
			            return Host(gadgetBuilder_shell_Inner_widget_gadget: __safeDI_gadgetBuilder_Host_shell_Inner_widget_gadget)
			        }
			        let hostBuilder = SendableInstantiator<Host>(__safeDI_hostBuilder)
			        self.init(hostBuilder: hostBuilder)
			    }
			}

			extension Other {
			    public enum __safeDI_Other_709165532C0D2BF1 {}
			}
			""",
		])
		try expectEveryModuleCompiled(output)
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_startsStageAtFill_whenOnlyThatFillMakesBuilderSendable() async throws {
		// The call of `Host` inside the fill is in a plain `Instantiator`, so only the fill's own `@Sendable` function makes
		// the builder `@Sendable`, and `gadget` is staged there.
		let fixture = Self.fixtureOfSendableFillWithPlace(
			widgetConformances: "Instantiable, Widget, @unchecked Sendable",
			widgetDeclarations: ["@Received let analytics: Analytics", "@Instantiated let gadget: any Gadget", "@Instantiated let hostBuilder: Instantiator<Host>"],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "Middle", imports: ["Feature"], rootFiles: ["Host": """
		extension Host {
		    public enum SafeDIStagedScope_Gadget_shell_Inner_widget_gadget {
		        public struct Stage1 {
		            public let session: Session
		        }

		        public struct Stage2 {
		            public let analytics: Analytics
		            public let hostBuilder: Instantiator<Host>
		        }
		    }

		    public init(gadgetBuilder_shell_Inner_widget_gadget: @escaping @Sendable (SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage1) -> @Sendable (SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage2) -> any Gadget) {
		        let __safeDI_gadgetBuilder_shell_Inner_widget_gadget = gadgetBuilder_shell_Inner_widget_gadget
		        let session = Session()
		        func __safeDI_shell() -> Shell {
		            _ = Shell.__safeDI_Shell_076D60492DA3478F.self\(seamCallComment(seam: "Shell", module: "Feature"))
		            let __safeDI_gadgetBuilder_shell_Inner_widget_gadget_Stage2 = __safeDI_gadgetBuilder_shell_Inner_widget_gadget(SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage1(session: session))
		            @Sendable func __safeDI_widgetBuilder_Inner_widget(_ scope: Inner.SafeDIScope_Widget.widget_Values) -> any Widget {
		                let analytics = scope.analytics
		                func __safeDI_widget() -> DefaultWidget {
		                    func __safeDI_hostBuilder() -> Host {
		                        _ = Host.__safeDI_Host_0BE9624E3D02D360.self
		                        return Host(gadgetBuilder_shell_Inner_widget_gadget: __safeDI_gadgetBuilder_shell_Inner_widget_gadget)
		                    }
		                    let hostBuilder = Instantiator<Host>(__safeDI_hostBuilder)
		                    let gadget: any Gadget = __safeDI_gadgetBuilder_shell_Inner_widget_gadget_Stage2(SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage2(analytics: analytics, hostBuilder: hostBuilder))
		                    return DefaultWidget(analytics: analytics, gadget: gadget, hostBuilder: hostBuilder)
		                }
		                let widget: any Widget = __safeDI_widget()
		                return widget
		            }
		            @Sendable func __safeDI_widgetSendableBuilder_Shell(_ scope: Shell.SafeDISendableScope_Widget) -> any Widget {
		                switch scope {
		                case let .innerBuilder(scope): return __safeDI_widgetBuilder_Inner(scope)
		                }
		            }
		            @Sendable func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
		                switch scope {
		                case let .widget(scope): return __safeDI_widgetBuilder_Inner_widget(scope)
		                }
		            }
		            return Shell(widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell)
		        }
		        let shell: Shell = __safeDI_shell()
		        self.init(session: session, shell: shell)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_0BE9624E3D02D360 {}
		}
		"""])
		try expectEveryModuleCompiled(output)
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
			root: seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let user: SendableLazilyInstantiated<User>", "@Instantiated let host: Host"]),
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "Middle", imports: ["Feature"], rootFiles: ["Host": """
		extension Host {
		    public enum SafeDIStagedScope_Gadget_shell_Inner_widget_gadget {
		        public struct Stage1 {
		            public var user: User { __safeDI_user.instance }
		            public let account: Account
		            let __safeDI_user: SendableLazilyInstantiated<User>

		            init(user: SendableLazilyInstantiated<User>, account: Account) {
		                __safeDI_user = user
		                self.account = account
		            }
		        }

		        public struct Stage2 {
		            public let analytics: Analytics
		            public let hostBuilder: SendableInstantiator<Host>
		        }
		    }

		    public init(user: User, gadgetBuilder_shell_Inner_widget_gadget: @escaping @Sendable (SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage1) -> @Sendable (SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage2) -> any Gadget) {
		        self.init(__safeDI_user: user, __safeDI_gadgetBuilder_shell_Inner_widget_gadget: gadgetBuilder_shell_Inner_widget_gadget)
		    }

		    public init(__safeDI_user: @autoclosure @escaping @Sendable () -> User, __safeDI_gadgetBuilder_shell_Inner_widget_gadget: @escaping @Sendable (SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage1) -> @Sendable (SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage2) -> any Gadget) {
		        let user = SendableLazilyInstantiated<User>(__safeDI_user)
		        let account = Account(user: user.instance)
		        func __safeDI_shell() -> Shell {
		            _ = Shell.__safeDI_Shell_076D60492DA3478F.self\(seamCallComment(seam: "Shell", module: "Feature"))
		            let __safeDI_gadgetBuilder_shell_Inner_widget_gadget_Stage2 = __safeDI_gadgetBuilder_shell_Inner_widget_gadget(SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage1(user: user, account: account))
		            @Sendable func __safeDI_widgetBuilder_Inner_widget(_ scope: Inner.SafeDIScope_Widget.widget_Values) -> any Widget {
		                let analytics = scope.analytics
		                func __safeDI_widget() -> DefaultWidget {
		                    @Sendable func __safeDI_hostBuilder() -> Host {
		                        _ = Host.__safeDI_Host_0358E601680BB949.self
		                        return Host(__safeDI_user: user.instance, __safeDI_gadgetBuilder_shell_Inner_widget_gadget: __safeDI_gadgetBuilder_shell_Inner_widget_gadget)
		                    }
		                    let hostBuilder = SendableInstantiator<Host>(__safeDI_hostBuilder)
		                    let gadget: any Gadget = __safeDI_gadgetBuilder_shell_Inner_widget_gadget_Stage2(SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage2(analytics: analytics, hostBuilder: hostBuilder))
		                    return DefaultWidget(gadget: gadget, hostBuilder: hostBuilder)
		                }
		                let widget: any Widget = __safeDI_widget()
		                return widget
		            }
		            @Sendable func __safeDI_widgetSendableBuilder_Shell(_ scope: Shell.SafeDISendableScope_Widget) -> any Widget {
		                switch scope {
		                case let .innerBuilder(scope): return __safeDI_widgetBuilder_Inner(scope)
		                }
		            }
		            @Sendable func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
		                switch scope {
		                case let .widget(scope): return __safeDI_widgetBuilder_Inner_widget(scope)
		                }
		            }
		            return Shell(widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell)
		        }
		        let shell: Shell = __safeDI_shell()
		        self.init(account: account, shell: shell)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_0358E601680BB949 {}
		}
		"""])
		try expectEveryModuleCompiled(output)
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

	// MARK: A field whose type a stage's struct would hide

	/// A field of the first stage of a staged builder, and the types it names.
	enum FieldNamingStage: CaseIterable, CustomTestStringConvertible {
		case inner
		case outer
		case genericArgumentInner
		case nestedInOuter
		case innerAndItsRenaming
		case memberNamedInner

		var testDescription: String {
			switch self {
			case .inner:
				"inner"
			case .outer:
				"outer"
			case .genericArgumentInner:
				"genericArgumentInner"
			case .nestedInOuter:
				"nestedInOuter"
			case .innerAndItsRenaming:
				"innerAndItsRenaming"
			case .memberNamedInner:
				"memberNamedInner"
			}
		}

		var featureTypes: [String] {
			switch self {
			case .inner, .genericArgumentInner:
				[seamFixtureType(named: "Inner", declarations: [], conformances: ", Sendable")]
			case .outer:
				[seamFixtureType(named: "Outer", declarations: [], conformances: ", Sendable")]
			case .nestedInOuter:
				["public enum Outer {\n    @Instantiable\n    public struct Leaf: Instantiable, Sendable {\n        public init() {}\n    }\n}"]
			case .innerAndItsRenaming:
				[seamFixtureType(named: "Inner", declarations: [], conformances: ", Sendable"), seamFixtureType(named: "Inner_", declarations: [], conformances: ", Sendable")]
			case .memberNamedInner:
				["public enum Box {\n    @Instantiable\n    public struct Inner: Instantiable, Sendable {\n        public init() {}\n    }\n}"]
			}
		}

		var fieldDeclarations: [String] {
			switch self {
			case .inner:
				["@Instantiated let value: Inner"]
			case .outer:
				["@Instantiated let value: Outer"]
			case .genericArgumentInner:
				["@Instantiated let value: Instantiator<Inner>"]
			case .nestedInOuter:
				["@Instantiated let value: Outer.Leaf"]
			case .innerAndItsRenaming:
				["@Instantiated let value: Inner", "@Instantiated let other: Inner_"]
			case .memberNamedInner:
				["@Instantiated let value: Box.Inner"]
			}
		}

		/// The code `Feature` generates for `Seam1`.
		var seamCode: String {
			switch self {
			case .inner:
				"""
				extension Seam1 {
				    public enum SafeDIStagedScope_Widget_panelBuilder_widget {
				        public struct Stage1 {
				            public let value: Inner
				        }

				        public struct Stage2 {}
				    }

				    public init(widgetBuilder_panelBuilder_widget: @escaping (SafeDIStagedScope_Widget_panelBuilder_widget.Stage1) -> @Sendable (SafeDIStagedScope_Widget_panelBuilder_widget.Stage2) -> any Widget) {
				        let __safeDI_widgetBuilder_panelBuilder_widget = widgetBuilder_panelBuilder_widget
				        let value = Inner()
				        let __safeDI_widgetBuilder_panelBuilder_widget_Stage2 = __safeDI_widgetBuilder_panelBuilder_widget(SafeDIStagedScope_Widget_panelBuilder_widget.Stage1(value: value))
				        @Sendable func __safeDI_panelBuilder() -> Panel {
				            let widget: any Widget = __safeDI_widgetBuilder_panelBuilder_widget_Stage2(SafeDIStagedScope_Widget_panelBuilder_widget.Stage2())
				            return Panel(widget: widget)
				        }
				        let panelBuilder = SendableInstantiator<Panel>(__safeDI_panelBuilder)
				        self.init(value: value, panelBuilder: panelBuilder)
				    }
				}

				extension Seam1 {
				    public enum __safeDI_Seam1_F72248F9F157F9B3 {}
				}
				"""
			case .outer:
				"""
				extension Seam1 {
				    public enum SafeDIStagedScope_Widget_panelBuilder_widget {
				        public struct Stage1 {
				            public let value: Outer
				        }

				        public struct Stage2 {}
				    }

				    public init(widgetBuilder_panelBuilder_widget: @escaping (SafeDIStagedScope_Widget_panelBuilder_widget.Stage1) -> @Sendable (SafeDIStagedScope_Widget_panelBuilder_widget.Stage2) -> any Widget) {
				        let __safeDI_widgetBuilder_panelBuilder_widget = widgetBuilder_panelBuilder_widget
				        let value = Outer()
				        let __safeDI_widgetBuilder_panelBuilder_widget_Stage2 = __safeDI_widgetBuilder_panelBuilder_widget(SafeDIStagedScope_Widget_panelBuilder_widget.Stage1(value: value))
				        @Sendable func __safeDI_panelBuilder() -> Panel {
				            let widget: any Widget = __safeDI_widgetBuilder_panelBuilder_widget_Stage2(SafeDIStagedScope_Widget_panelBuilder_widget.Stage2())
				            return Panel(widget: widget)
				        }
				        let panelBuilder = SendableInstantiator<Panel>(__safeDI_panelBuilder)
				        self.init(value: value, panelBuilder: panelBuilder)
				    }
				}

				extension Seam1 {
				    public enum __safeDI_Seam1_9F9EA46DCF6257F8 {}
				}
				"""
			case .genericArgumentInner:
				"""
				extension Seam1 {
				    public enum SafeDIStagedScope_Widget_panelBuilder_widget {
				        public struct Stage1 {
				            public let value: Instantiator<Inner>
				        }

				        public struct Stage2 {}
				    }

				    public init(widgetBuilder_panelBuilder_widget: @escaping (SafeDIStagedScope_Widget_panelBuilder_widget.Stage1) -> @Sendable (SafeDIStagedScope_Widget_panelBuilder_widget.Stage2) -> any Widget) {
				        let __safeDI_widgetBuilder_panelBuilder_widget = widgetBuilder_panelBuilder_widget
				        func __safeDI_value() -> Inner {
				            Inner()
				        }
				        let value = Instantiator<Inner>(__safeDI_value)
				        let __safeDI_widgetBuilder_panelBuilder_widget_Stage2 = __safeDI_widgetBuilder_panelBuilder_widget(SafeDIStagedScope_Widget_panelBuilder_widget.Stage1(value: value))
				        @Sendable func __safeDI_panelBuilder() -> Panel {
				            let widget: any Widget = __safeDI_widgetBuilder_panelBuilder_widget_Stage2(SafeDIStagedScope_Widget_panelBuilder_widget.Stage2())
				            return Panel(widget: widget)
				        }
				        let panelBuilder = SendableInstantiator<Panel>(__safeDI_panelBuilder)
				        self.init(value: value, panelBuilder: panelBuilder)
				    }
				}

				extension Seam1 {
				    public enum __safeDI_Seam1_DA713AEA49C24DCD {}
				}
				"""
			case .nestedInOuter:
				"""
				extension Seam1 {
				    public enum SafeDIStagedScope_Widget_panelBuilder_widget {
				        public struct Stage1 {
				            public let value: Outer.Leaf
				        }

				        public struct Stage2 {}
				    }

				    public init(widgetBuilder_panelBuilder_widget: @escaping (SafeDIStagedScope_Widget_panelBuilder_widget.Stage1) -> @Sendable (SafeDIStagedScope_Widget_panelBuilder_widget.Stage2) -> any Widget) {
				        let __safeDI_widgetBuilder_panelBuilder_widget = widgetBuilder_panelBuilder_widget
				        let value = Outer.Leaf()
				        let __safeDI_widgetBuilder_panelBuilder_widget_Stage2 = __safeDI_widgetBuilder_panelBuilder_widget(SafeDIStagedScope_Widget_panelBuilder_widget.Stage1(value: value))
				        @Sendable func __safeDI_panelBuilder() -> Panel {
				            let widget: any Widget = __safeDI_widgetBuilder_panelBuilder_widget_Stage2(SafeDIStagedScope_Widget_panelBuilder_widget.Stage2())
				            return Panel(widget: widget)
				        }
				        let panelBuilder = SendableInstantiator<Panel>(__safeDI_panelBuilder)
				        self.init(value: value, panelBuilder: panelBuilder)
				    }
				}

				extension Seam1 {
				    public enum __safeDI_Seam1_08FBC475A74E4D1C {}
				}
				"""
			case .innerAndItsRenaming:
				"""
				extension Seam1 {
				    public enum SafeDIStagedScope_Widget_panelBuilder_widget {
				        public struct Stage1 {
				            public let value: Inner
				            public let other: Inner_
				        }

				        public struct Stage2 {}
				    }

				    public init(widgetBuilder_panelBuilder_widget: @escaping (SafeDIStagedScope_Widget_panelBuilder_widget.Stage1) -> @Sendable (SafeDIStagedScope_Widget_panelBuilder_widget.Stage2) -> any Widget) {
				        let __safeDI_widgetBuilder_panelBuilder_widget = widgetBuilder_panelBuilder_widget
				        let value = Inner()
				        let other = Inner_()
				        let __safeDI_widgetBuilder_panelBuilder_widget_Stage2 = __safeDI_widgetBuilder_panelBuilder_widget(SafeDIStagedScope_Widget_panelBuilder_widget.Stage1(value: value, other: other))
				        @Sendable func __safeDI_panelBuilder() -> Panel {
				            let widget: any Widget = __safeDI_widgetBuilder_panelBuilder_widget_Stage2(SafeDIStagedScope_Widget_panelBuilder_widget.Stage2())
				            return Panel(widget: widget)
				        }
				        let panelBuilder = SendableInstantiator<Panel>(__safeDI_panelBuilder)
				        self.init(value: value, other: other, panelBuilder: panelBuilder)
				    }
				}

				extension Seam1 {
				    public enum __safeDI_Seam1_23BC3A0C36310090 {}
				}
				"""
			case .memberNamedInner:
				"""
				extension Seam1 {
				    public enum SafeDIStagedScope_Widget_panelBuilder_widget {
				        public struct Stage1 {
				            public let value: Box.Inner
				        }

				        public struct Stage2 {}
				    }

				    public init(widgetBuilder_panelBuilder_widget: @escaping (SafeDIStagedScope_Widget_panelBuilder_widget.Stage1) -> @Sendable (SafeDIStagedScope_Widget_panelBuilder_widget.Stage2) -> any Widget) {
				        let __safeDI_widgetBuilder_panelBuilder_widget = widgetBuilder_panelBuilder_widget
				        let value = Box.Inner()
				        let __safeDI_widgetBuilder_panelBuilder_widget_Stage2 = __safeDI_widgetBuilder_panelBuilder_widget(SafeDIStagedScope_Widget_panelBuilder_widget.Stage1(value: value))
				        @Sendable func __safeDI_panelBuilder() -> Panel {
				            let widget: any Widget = __safeDI_widgetBuilder_panelBuilder_widget_Stage2(SafeDIStagedScope_Widget_panelBuilder_widget.Stage2())
				            return Panel(widget: widget)
				        }
				        let panelBuilder = SendableInstantiator<Panel>(__safeDI_panelBuilder)
				        self.init(value: value, panelBuilder: panelBuilder)
				    }
				}

				extension Seam1 {
				    public enum __safeDI_Seam1_55D020B98B292DAC {}
				}
				"""
			}
		}
	}

	@Test(arguments: FieldNamingStage.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesStageStructsApart_whenFieldTypeNamesStage(field: FieldNamingStage) async throws {
		let feature = field.featureTypes + [
			"public protocol Widget: Sendable {}",
			seamFixtureType(named: "Panel", declarations: ["@Instantiated let widget: any Widget"], conformances: ", Sendable"),
			seamFixtureType(named: "Seam1", isSeam: true, declarations: field.fieldDeclarations + ["@Instantiated let panelBuilder: SendableInstantiator<Panel>"]),
		]
		let app = [
			SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: []),
			seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let seam1: Seam1"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: app), integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "Feature", imports: [], rootFiles: ["Seam1": field.seamCode])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesLaterStageApart_whenFieldTypeNamesThirdStage() async throws {
		let feature = [
			seamFixtureType(named: "Inner2", declarations: [], conformances: ", Sendable"),
			"public protocol Widget: Sendable {}",
			seamFixtureType(named: "Panel", declarations: ["@Instantiated let widget: any Widget"], conformances: ", Sendable"),
			seamFixtureType(named: "Tray", declarations: ["@Instantiated let panelBuilder: SendableInstantiator<Panel>"], conformances: ", Sendable"),
			seamFixtureType(named: "Seam1", isSeam: true, declarations: ["@Instantiated let value: Inner2", "@Instantiated let trayBuilder: SendableInstantiator<Tray>"]),
		]
		let app = [
			SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: []),
			seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let seam1: Seam1"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: app), integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "Feature", imports: [], rootFiles: ["Seam1": """
		extension Seam1 {
		    public enum SafeDIStagedScope_Widget_trayBuilder_panelBuilder_widget {
		        public struct Stage1 {
		            public let value: Inner2
		        }

		        public struct Stage2 {}

		        public struct Stage3 {}
		    }

		    public init(widgetBuilder_trayBuilder_panelBuilder_widget: @escaping (SafeDIStagedScope_Widget_trayBuilder_panelBuilder_widget.Stage1) -> @Sendable (SafeDIStagedScope_Widget_trayBuilder_panelBuilder_widget.Stage2) -> @Sendable (SafeDIStagedScope_Widget_trayBuilder_panelBuilder_widget.Stage3) -> any Widget) {
		        let __safeDI_widgetBuilder_trayBuilder_panelBuilder_widget = widgetBuilder_trayBuilder_panelBuilder_widget
		        let value = Inner2()
		        let __safeDI_widgetBuilder_trayBuilder_panelBuilder_widget_Stage2 = __safeDI_widgetBuilder_trayBuilder_panelBuilder_widget(SafeDIStagedScope_Widget_trayBuilder_panelBuilder_widget.Stage1(value: value))
		        @Sendable func __safeDI_trayBuilder() -> Tray {
		            let __safeDI_widgetBuilder_trayBuilder_panelBuilder_widget_Stage3 = __safeDI_widgetBuilder_trayBuilder_panelBuilder_widget_Stage2(SafeDIStagedScope_Widget_trayBuilder_panelBuilder_widget.Stage2())
		            @Sendable func __safeDI_panelBuilder() -> Panel {
		                let widget: any Widget = __safeDI_widgetBuilder_trayBuilder_panelBuilder_widget_Stage3(SafeDIStagedScope_Widget_trayBuilder_panelBuilder_widget.Stage3())
		                return Panel(widget: widget)
		            }
		            let panelBuilder = SendableInstantiator<Panel>(__safeDI_panelBuilder)
		            return Tray(panelBuilder: panelBuilder)
		        }
		        let trayBuilder = SendableInstantiator<Tray>(__safeDI_trayBuilder)
		        self.init(value: value, trayBuilder: trayBuilder)
		    }
		}

		extension Seam1 {
		    public enum __safeDI_Seam1_337950EE26B83ED8 {}
		}
		"""])
		expectGeneratedCode(of: output, module: "App", imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_seam1() -> Seam1 {
		            _ = Seam1.__safeDI_Seam1_337950EE26B83ED8.self\(seamCallComment(seam: "Seam1", module: "Feature"))
		            func __safeDI_widgetBuilder_trayBuilder_panelBuilder_widget(_ scope: Seam1.SafeDIStagedScope_Widget_trayBuilder_panelBuilder_widget.Stage1) -> @Sendable (Seam1.SafeDIStagedScope_Widget_trayBuilder_panelBuilder_widget.Stage2) -> @Sendable (Seam1.SafeDIStagedScope_Widget_trayBuilder_panelBuilder_widget.Stage3) -> any Widget {
		                @Sendable func __safeDI_widgetBuilder_trayBuilder_panelBuilder_widget_Stage2(_ scope: Seam1.SafeDIStagedScope_Widget_trayBuilder_panelBuilder_widget.Stage2) -> @Sendable (Seam1.SafeDIStagedScope_Widget_trayBuilder_panelBuilder_widget.Stage3) -> any Widget {
		                    @Sendable func __safeDI_widgetBuilder_trayBuilder_panelBuilder_widget_Stage3(_ scope: Seam1.SafeDIStagedScope_Widget_trayBuilder_panelBuilder_widget.Stage3) -> any Widget {
		                        let widget: any Widget = DefaultWidget()
		                        return widget
		                    }
		                    return __safeDI_widgetBuilder_trayBuilder_panelBuilder_widget_Stage3
		                }
		                return __safeDI_widgetBuilder_trayBuilder_panelBuilder_widget_Stage2
		            }
		            return Seam1(widgetBuilder_trayBuilder_panelBuilder_widget: __safeDI_widgetBuilder_trayBuilder_panelBuilder_widget)
		        }
		        let seam1: Seam1 = __safeDI_seam1()
		        self.init(seam1: seam1)
		    }
		}
		"""])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesStageStructsApart_whenFieldOfPlaceInsideFillIsTypeNamedInner() async throws {
		// `Host` calls `Inner`, `Feature`'s seam, beside the `Shell` whose `@Sendable` fill holds `gadget`, so `gadget`'s first
		// stage has a field of the type named `Inner`.
		let fixture = Self.fixtureOfSendableFillWithPlace(hostDeclarations: ["@Instantiated let session: Session", "@Instantiated let inner: Inner", FillRoute.sendableByRoute.hostDeclaration])
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "Middle", imports: ["Feature"], rootFiles: ["Host": """
		extension Host {
		    @frozen public enum SafeDIScope_Gadget {
		        case inner_widget_gadget(inner_widget_gadget_Values)

		        public struct inner_widget_gadget_Values {
		            public let session: Session
		            public let analytics: Analytics
		        }
		    }

		    public enum SafeDIStagedScope_Gadget_shell_Inner_widget_gadget {
		        public struct Stage1 {
		            public let session: Session
		            public let inner: Inner
		        }

		        public struct Stage2 {
		            public let analytics: Analytics
		        }
		    }

		    public init(gadgetBuilder: @escaping (SafeDIScope_Gadget) -> any Gadget, gadgetBuilder_shell_Inner_widget_gadget: @escaping (SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage1) -> @Sendable (SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage2) -> any Gadget) {
		        let __safeDI_gadgetBuilder = gadgetBuilder
		        let __safeDI_gadgetBuilder_shell_Inner_widget_gadget = gadgetBuilder_shell_Inner_widget_gadget
		        let session = Session()
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_A441BC75156D061F.self\(seamCallComment(seam: "Inner", module: "Feature"))
		            func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
		                switch scope {
		                case let .widget(scope):
		                    let analytics = scope.analytics
		                    func __safeDI_widget() -> DefaultWidget {
		                        let gadget: any Gadget = __safeDI_gadgetBuilder(.inner_widget_gadget(SafeDIScope_Gadget.inner_widget_gadget_Values(session: session, analytics: analytics)))
		                        return DefaultWidget(analytics: analytics, gadget: gadget)
		                    }
		                    let widget: any Widget = __safeDI_widget()
		                    return widget
		                }
		            }
		            return Inner(widgetBuilder: __safeDI_widgetBuilder_Inner)
		        }
		        let inner: Inner = __safeDI_inner()
		        func __safeDI_shell() -> Shell {
		            _ = Shell.__safeDI_Shell_076D60492DA3478F.self\(seamCallComment(seam: "Inner", module: "Feature"))
		            let __safeDI_gadgetBuilder_shell_Inner_widget_gadget_Stage2 = __safeDI_gadgetBuilder_shell_Inner_widget_gadget(SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage1(session: session, inner: inner))
		            @Sendable func __safeDI_widgetBuilder_Inner_widget(_ scope: Inner.SafeDIScope_Widget.widget_Values) -> any Widget {
		                let analytics = scope.analytics
		                func __safeDI_widget() -> DefaultWidget {
		                    let gadget: any Gadget = __safeDI_gadgetBuilder_shell_Inner_widget_gadget_Stage2(SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage2(analytics: analytics))
		                    return DefaultWidget(analytics: analytics, gadget: gadget)
		                }
		                let widget: any Widget = __safeDI_widget()
		                return widget
		            }
		            @Sendable func __safeDI_widgetSendableBuilder_Shell(_ scope: Shell.SafeDISendableScope_Widget) -> any Widget {
		                switch scope {
		                case let .innerBuilder(scope): return __safeDI_widgetBuilder_Inner(scope)
		                }
		            }
		            @Sendable func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
		                switch scope {
		                case let .widget(scope): return __safeDI_widgetBuilder_Inner_widget(scope)
		                }
		            }
		            return Shell(widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell)
		        }
		        let shell: Shell = __safeDI_shell()
		        self.init(session: session, inner: inner, shell: shell)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_CAA239727FBFCC06 {}
		}
		"""])
		try expectEveryModuleCompiled(output)
	}

	// MARK: A `@Sendable` fill beneath a `@Sendable` builder function

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_startsStageAtFillWithEmptyStageBefore_whenSendableFillIsBeneathSendableBuilderFunction() async throws {
		// `shellMaker` builds in a `@Sendable` function and the fill inside it is one too, so `gadgetBuilder` has a stage for
		// each. Nothing is bound between them, but how many stages a builder has follows only from the functions on the
		// path, so that binding a value between them never adds a closure to what a caller writes.
		let fixture = Self.fixtureOfSendableFillWithPlace(hostDeclarations: ["@Instantiated let session: Session", "@Instantiated let shellMaker: SendableInstantiator<Shell>"])
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "Middle", imports: ["Feature"], rootFiles: ["Host": """
		extension Host {
		    public enum SafeDIStagedScope_Gadget_shellMaker_Inner_widget_gadget {
		        public struct Stage1 {
		            public let session: Session
		        }

		        public struct Stage2 {}

		        public struct Stage3 {
		            public let analytics: Analytics
		        }
		    }

		    public init(gadgetBuilder_shellMaker_Inner_widget_gadget: @escaping (SafeDIStagedScope_Gadget_shellMaker_Inner_widget_gadget.Stage1) -> @Sendable (SafeDIStagedScope_Gadget_shellMaker_Inner_widget_gadget.Stage2) -> @Sendable (SafeDIStagedScope_Gadget_shellMaker_Inner_widget_gadget.Stage3) -> any Gadget) {
		        let __safeDI_gadgetBuilder_shellMaker_Inner_widget_gadget = gadgetBuilder_shellMaker_Inner_widget_gadget
		        let session = Session()
		        let __safeDI_gadgetBuilder_shellMaker_Inner_widget_gadget_Stage2 = __safeDI_gadgetBuilder_shellMaker_Inner_widget_gadget(SafeDIStagedScope_Gadget_shellMaker_Inner_widget_gadget.Stage1(session: session))
		        @Sendable func __safeDI_shellMaker() -> Shell {
		            _ = Shell.__safeDI_Shell_076D60492DA3478F.self\(seamCallComment(seam: "Shell", module: "Feature"))
		            let __safeDI_gadgetBuilder_shellMaker_Inner_widget_gadget_Stage3 = __safeDI_gadgetBuilder_shellMaker_Inner_widget_gadget_Stage2(SafeDIStagedScope_Gadget_shellMaker_Inner_widget_gadget.Stage2())
		            @Sendable func __safeDI_widgetBuilder_Inner_widget(_ scope: Inner.SafeDIScope_Widget.widget_Values) -> any Widget {
		                let analytics = scope.analytics
		                func __safeDI_widget() -> DefaultWidget {
		                    let gadget: any Gadget = __safeDI_gadgetBuilder_shellMaker_Inner_widget_gadget_Stage3(SafeDIStagedScope_Gadget_shellMaker_Inner_widget_gadget.Stage3(analytics: analytics))
		                    return DefaultWidget(analytics: analytics, gadget: gadget)
		                }
		                let widget: any Widget = __safeDI_widget()
		                return widget
		            }
		            @Sendable func __safeDI_widgetSendableBuilder_Shell(_ scope: Shell.SafeDISendableScope_Widget) -> any Widget {
		                switch scope {
		                case let .innerBuilder(scope): return __safeDI_widgetBuilder_Inner(scope)
		                }
		            }
		            @Sendable func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
		                switch scope {
		                case let .widget(scope): return __safeDI_widgetBuilder_Inner_widget(scope)
		                }
		            }
		            return Shell(widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell)
		        }
		        let shellMaker = SendableInstantiator<Shell>(__safeDI_shellMaker)
		        self.init(session: session, shellMaker: shellMaker)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_CE8C407BD0619E01 {}
		}
		"""])
		expectGeneratedCode(of: output, module: "App", imports: ["Feature", "Middle"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_CE8C407BD0619E01.self\(seamCallComment(seam: "Host", module: "Middle"))
		            func __safeDI_gadgetBuilder_shellMaker_Inner_widget_gadget(_ scope: Host.SafeDIStagedScope_Gadget_shellMaker_Inner_widget_gadget.Stage1) -> @Sendable (Host.SafeDIStagedScope_Gadget_shellMaker_Inner_widget_gadget.Stage2) -> @Sendable (Host.SafeDIStagedScope_Gadget_shellMaker_Inner_widget_gadget.Stage3) -> any Gadget {
		                let session = scope.session
		                @Sendable func __safeDI_gadgetBuilder_shellMaker_Inner_widget_gadget_Stage2(_ scope: Host.SafeDIStagedScope_Gadget_shellMaker_Inner_widget_gadget.Stage2) -> @Sendable (Host.SafeDIStagedScope_Gadget_shellMaker_Inner_widget_gadget.Stage3) -> any Gadget {
		                    @Sendable func __safeDI_gadgetBuilder_shellMaker_Inner_widget_gadget_Stage3(_ scope: Host.SafeDIStagedScope_Gadget_shellMaker_Inner_widget_gadget.Stage3) -> any Gadget {
		                        let analytics = scope.analytics
		                        let gadget: any Gadget = DefaultGadget(session: session, analytics: analytics)
		                        return gadget
		                    }
		                    return __safeDI_gadgetBuilder_shellMaker_Inner_widget_gadget_Stage3
		                }
		                return __safeDI_gadgetBuilder_shellMaker_Inner_widget_gadget_Stage2
		            }
		            return Host(gadgetBuilder_shellMaker_Inner_widget_gadget: __safeDI_gadgetBuilder_shellMaker_Inner_widget_gadget)
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		try expectEveryModuleCompiled(output)
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_carriesNonSendableFieldInItsOwnStage_whenBoundBetweenSendableBuilderFunctionAndSendableFill() async throws {
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
		    public enum SafeDIStagedScope_Gadget_holderMaker_shell_Inner_widget_gadget {
		        public struct Stage1 {}

		        public struct Stage2 {
		            public let bag: Bag
		        }

		        public struct Stage3 {
		            public let analytics: Analytics
		        }
		    }

		    public init(gadgetBuilder_holderMaker_shell_Inner_widget_gadget: @escaping (SafeDIStagedScope_Gadget_holderMaker_shell_Inner_widget_gadget.Stage1) -> @Sendable (SafeDIStagedScope_Gadget_holderMaker_shell_Inner_widget_gadget.Stage2) -> @Sendable (SafeDIStagedScope_Gadget_holderMaker_shell_Inner_widget_gadget.Stage3) -> any Gadget) {
		        let __safeDI_gadgetBuilder_holderMaker_shell_Inner_widget_gadget = gadgetBuilder_holderMaker_shell_Inner_widget_gadget
		        let __safeDI_gadgetBuilder_holderMaker_shell_Inner_widget_gadget_Stage2 = __safeDI_gadgetBuilder_holderMaker_shell_Inner_widget_gadget(SafeDIStagedScope_Gadget_holderMaker_shell_Inner_widget_gadget.Stage1())
		        @Sendable func __safeDI_holderMaker() -> ShellHolder {
		            let bag = Bag()
		            func __safeDI_shell() -> Shell {
		                _ = Shell.__safeDI_Shell_076D60492DA3478F.self\(seamCallComment(seam: "Shell", module: "Feature"))
		                let __safeDI_gadgetBuilder_holderMaker_shell_Inner_widget_gadget_Stage3 = __safeDI_gadgetBuilder_holderMaker_shell_Inner_widget_gadget_Stage2(SafeDIStagedScope_Gadget_holderMaker_shell_Inner_widget_gadget.Stage2(bag: bag))
		                @Sendable func __safeDI_widgetBuilder_Inner_widget(_ scope: Inner.SafeDIScope_Widget.widget_Values) -> any Widget {
		                    let analytics = scope.analytics
		                    func __safeDI_widget() -> DefaultWidget {
		                        let gadget: any Gadget = __safeDI_gadgetBuilder_holderMaker_shell_Inner_widget_gadget_Stage3(SafeDIStagedScope_Gadget_holderMaker_shell_Inner_widget_gadget.Stage3(analytics: analytics))
		                        return DefaultWidget(gadget: gadget)
		                    }
		                    let widget: any Widget = __safeDI_widget()
		                    return widget
		                }
		                @Sendable func __safeDI_widgetSendableBuilder_Shell(_ scope: Shell.SafeDISendableScope_Widget) -> any Widget {
		                    switch scope {
		                    case let .innerBuilder(scope): return __safeDI_widgetBuilder_Inner(scope)
		                    }
		                }
		                @Sendable func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
		                    switch scope {
		                    case let .widget(scope): return __safeDI_widgetBuilder_Inner_widget(scope)
		                    }
		                }
		                return Shell(widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell)
		            }
		            let shell: Shell = __safeDI_shell()
		            return ShellHolder(bag: bag, shell: shell)
		        }
		        let holderMaker = SendableInstantiator<ShellHolder>(__safeDI_holderMaker)
		        self.init(holderMaker: holderMaker)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_D8B73ED70185DC4D {}
		}
		"""])
		try expectEveryModuleCompiled(output)
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_startsStageAtFill_whenBuilderIsSendableAndFieldIsNonSendableWrapper() async throws {
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
		    public enum SafeDIStagedScope_Gadget_shell_Inner_widget_gadget {
		        public struct Stage1 {
		            public let itemMaker: Instantiator<Item>
		        }

		        public struct Stage2 {
		            public let analytics: Analytics
		            public let hostBuilder: SendableInstantiator<Host>
		        }
		    }

		    public init(gadgetBuilder_shell_Inner_widget_gadget: @escaping @Sendable (SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage1) -> @Sendable (SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage2) -> any Gadget) {
		        let __safeDI_gadgetBuilder_shell_Inner_widget_gadget = gadgetBuilder_shell_Inner_widget_gadget
		        func __safeDI_itemMaker() -> Item {
		            Item()
		        }
		        let itemMaker = Instantiator<Item>(__safeDI_itemMaker)
		        func __safeDI_shell() -> Shell {
		            _ = Shell.__safeDI_Shell_076D60492DA3478F.self\(seamCallComment(seam: "Shell", module: "Feature"))
		            let __safeDI_gadgetBuilder_shell_Inner_widget_gadget_Stage2 = __safeDI_gadgetBuilder_shell_Inner_widget_gadget(SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage1(itemMaker: itemMaker))
		            @Sendable func __safeDI_widgetBuilder_Inner_widget(_ scope: Inner.SafeDIScope_Widget.widget_Values) -> any Widget {
		                let analytics = scope.analytics
		                func __safeDI_widget() -> DefaultWidget {
		                    @Sendable func __safeDI_hostBuilder() -> Host {
		                        _ = Host.__safeDI_Host_1F3370B92A0A8E82.self
		                        return Host(gadgetBuilder_shell_Inner_widget_gadget: __safeDI_gadgetBuilder_shell_Inner_widget_gadget)
		                    }
		                    let hostBuilder = SendableInstantiator<Host>(__safeDI_hostBuilder)
		                    let gadget: any Gadget = __safeDI_gadgetBuilder_shell_Inner_widget_gadget_Stage2(SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage2(analytics: analytics, hostBuilder: hostBuilder))
		                    return DefaultWidget(gadget: gadget, hostBuilder: hostBuilder)
		                }
		                let widget: any Widget = __safeDI_widget()
		                return widget
		            }
		            @Sendable func __safeDI_widgetSendableBuilder_Shell(_ scope: Shell.SafeDISendableScope_Widget) -> any Widget {
		                switch scope {
		                case let .innerBuilder(scope): return __safeDI_widgetBuilder_Inner(scope)
		                }
		            }
		            @Sendable func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
		                switch scope {
		                case let .widget(scope): return __safeDI_widgetBuilder_Inner_widget(scope)
		                }
		            }
		            return Shell(widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell)
		        }
		        let shell: Shell = __safeDI_shell()
		        self.init(itemMaker: itemMaker, shell: shell)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_1F3370B92A0A8E82 {}
		}
		"""])
		try expectEveryModuleCompiled(output)
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

		    public init(gadgetBuilder: @escaping (SafeDIScope_Gadget) -> any Gadget) {
		        let __safeDI_gadgetBuilder = gadgetBuilder
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_172F8689A03DDCFE.self\(seamCallComment(seam: "Inner", module: "Feature"))
		            func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
		                switch scope {
		                case let .a_widget(scope):
		                    let alpha = scope.alpha
		                    func __safeDI_widget() -> DefaultWidget {
		                        let gadget: any Gadget = __safeDI_gadgetBuilder(.inner_a_widget_gadget(SafeDIScope_Gadget.inner_a_widget_gadget_Values(alpha: alpha)))
		                        return DefaultWidget(gadget: gadget)
		                    }
		                    let widget: any Widget = __safeDI_widget()
		                    return widget
		                case let .b_widget(scope):
		                    let a = scope.a
		                    let beta = scope.beta
		                    func __safeDI_widget() -> DefaultWidget {
		                        let gadget: any Gadget = __safeDI_gadgetBuilder(.inner_b_widget_gadget(SafeDIScope_Gadget.inner_b_widget_gadget_Values(a: a, beta: beta)))
		                        return DefaultWidget(gadget: gadget)
		                    }
		                    let widget: any Widget = __safeDI_widget()
		                    return widget
		                }
		            }
		            return Inner(widgetBuilder: __safeDI_widgetBuilder_Inner)
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(inner: inner)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_1AF2C76943211E42 {}
		}
		"""])
		try expectEveryModuleCompiled(output)
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsEachPlacesFirstStageBeforeItsOwnFill_whenFilledSeamHasTwoSitesOfOneLabelAndTypeOnSendableRoute() async throws {
		let fixture = Self.fixtureOfTwoSitesOfOneLabel(throughShell: true)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "Middle", imports: ["Feature"], rootFiles: ["Host": """
		extension Host {
		    public enum SafeDIStagedScope_Gadget_shell_Inner_a_widget_gadget {
		        public struct Stage1 {}

		        public struct Stage2 {
		            public let alpha: Alpha
		        }
		    }

		    public enum SafeDIStagedScope_Gadget_shell_Inner_b_widget_gadget {
		        public struct Stage1 {}

		        public struct Stage2 {
		            public let a: A
		            public let beta: Beta
		        }
		    }

		    public init(gadgetBuilder_shell_Inner_a_widget_gadget: @escaping (SafeDIStagedScope_Gadget_shell_Inner_a_widget_gadget.Stage1) -> @Sendable (SafeDIStagedScope_Gadget_shell_Inner_a_widget_gadget.Stage2) -> any Gadget, gadgetBuilder_shell_Inner_b_widget_gadget: @escaping (SafeDIStagedScope_Gadget_shell_Inner_b_widget_gadget.Stage1) -> @Sendable (SafeDIStagedScope_Gadget_shell_Inner_b_widget_gadget.Stage2) -> any Gadget) {
		        let __safeDI_gadgetBuilder_shell_Inner_a_widget_gadget = gadgetBuilder_shell_Inner_a_widget_gadget
		        let __safeDI_gadgetBuilder_shell_Inner_b_widget_gadget = gadgetBuilder_shell_Inner_b_widget_gadget
		        func __safeDI_shell() -> Shell {
		            _ = Shell.__safeDI_Shell_1D90DEA21EAB29B6.self\(seamCallComment(seam: "Shell", module: "Feature"))
		            let __safeDI_gadgetBuilder_shell_Inner_a_widget_gadget_Stage2 = __safeDI_gadgetBuilder_shell_Inner_a_widget_gadget(SafeDIStagedScope_Gadget_shell_Inner_a_widget_gadget.Stage1())
		            @Sendable func __safeDI_widgetBuilder_Inner_a_widget(_ scope: Inner.SafeDIScope_Widget.a_widget_Values) -> any Widget {
		                let alpha = scope.alpha
		                func __safeDI_widget() -> DefaultWidget {
		                    let gadget: any Gadget = __safeDI_gadgetBuilder_shell_Inner_a_widget_gadget_Stage2(SafeDIStagedScope_Gadget_shell_Inner_a_widget_gadget.Stage2(alpha: alpha))
		                    return DefaultWidget(gadget: gadget)
		                }
		                let widget: any Widget = __safeDI_widget()
		                return widget
		            }
		            let __safeDI_gadgetBuilder_shell_Inner_b_widget_gadget_Stage2 = __safeDI_gadgetBuilder_shell_Inner_b_widget_gadget(SafeDIStagedScope_Gadget_shell_Inner_b_widget_gadget.Stage1())
		            @Sendable func __safeDI_widgetBuilder_Inner_b_widget(_ scope: Inner.SafeDIScope_Widget.b_widget_Values) -> any Widget {
		                let a = scope.a
		                let beta = scope.beta
		                func __safeDI_widget() -> DefaultWidget {
		                    let gadget: any Gadget = __safeDI_gadgetBuilder_shell_Inner_b_widget_gadget_Stage2(SafeDIStagedScope_Gadget_shell_Inner_b_widget_gadget.Stage2(a: a, beta: beta))
		                    return DefaultWidget(gadget: gadget)
		                }
		                let widget: any Widget = __safeDI_widget()
		                return widget
		            }
		            @Sendable func __safeDI_widgetSendableBuilder_Shell(_ scope: Shell.SafeDISendableScope_Widget) -> any Widget {
		                switch scope {
		                case let .innerBuilder(scope): return __safeDI_widgetBuilder_Inner(scope)
		                }
		            }
		            @Sendable func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
		                switch scope {
		                case let .a_widget(scope): return __safeDI_widgetBuilder_Inner_a_widget(scope)
		                case let .b_widget(scope): return __safeDI_widgetBuilder_Inner_b_widget(scope)
		                }
		            }
		            return Shell(widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell)
		        }
		        let shell: Shell = __safeDI_shell()
		        self.init(shell: shell)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_6A22390C4918F370 {}
		}
		"""])
		try expectEveryModuleCompiled(output)
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

		    public init(gadgetBuilder: @escaping (SafeDIScope_Gadget) -> any Gadget) {
		        let __safeDI_gadgetBuilder = gadgetBuilder
		        func __safeDI_top() -> Top {
		            _ = Top.__safeDI_Top_C8A5790490E40760.self\(seamCallComment(seam: "Top", module: "Feature"))
		            func __safeDI_widgetBuilder_Top(_ scope: Top.SafeDIScope_Widget) -> any Widget {
		                switch scope {
		                case let .subA(scope): return __safeDI_widgetBuilder_SubA(scope)
		                case let .subB(scope): return __safeDI_widgetBuilder_SubB(scope)
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
		            return Top(widgetBuilder: __safeDI_widgetBuilder_Top)
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_5B068A1FBECC5F0D {}
		}
		"""])
		try expectEveryModuleCompiled(output)
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	// MARK: The reason a one-stage fill is `@Sendable`

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorSayingFillIsPassedOn_whenOneStageFillIsSendableBecauseCalledSeamBuildsSeamInSendableFunction() async {
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

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesStageStructApart_whenFieldTypeNamesStageInGenericArgumentOfEnclosingType() async throws {
		// `Box<Inner>.Bar`, spelled inside the stage's enum, would read `Inner` as the stage's struct.
		let fixture = ThreeModules(
			feature: FillRoute.sendableByRoute.featureTypes + ["public struct Box<T>: Sendable {\n    public init() {}\n    public struct Bar: Sendable {\n        public init() {}\n    }\n}"],
			middle: [
				Self.gadget,
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: []),
				seamFixtureType(named: "Holder", declarations: ["@Forwarded let token: Box<Inner>.Bar", "@Instantiated let gadget: any Gadget"], conformances: ", Sendable"),
				seamFixtureType(named: "Host", isSeam: true, declarations: ["@Instantiated let holderMaker: SendableInstantiator<Holder>"], conformances: ", Sendable"),
			],
			app: [SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultGadget", fulfilling: "Gadget", declarations: [])],
			root: Self.root,
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "Middle", imports: ["Feature"], rootFiles: ["Host": """
		extension Host {
		    // SafeDI counts `Box.Bar` as `public`: no module it reads declares it narrower. If `Box.Bar` is `package` in a first-party module, run SafeDI on that module and list it among this module's SafeDI dependencies.
		    public enum SafeDIStagedScope_Gadget_holderMaker_gadget {
		        public struct Stage1 {}

		        public struct Stage2 {
		            public let token: Box<Inner>.Bar
		        }
		    }

		    public init(gadgetBuilder_holderMaker_gadget: @escaping (SafeDIStagedScope_Gadget_holderMaker_gadget.Stage1) -> @Sendable (SafeDIStagedScope_Gadget_holderMaker_gadget.Stage2) -> any Gadget) {
		        let __safeDI_gadgetBuilder_holderMaker_gadget = gadgetBuilder_holderMaker_gadget
		        let __safeDI_gadgetBuilder_holderMaker_gadget_Stage2 = __safeDI_gadgetBuilder_holderMaker_gadget(SafeDIStagedScope_Gadget_holderMaker_gadget.Stage1())
		        @Sendable func __safeDI_holderMaker(token: Box<Inner>.Bar) -> Holder {
		            let gadget: any Gadget = __safeDI_gadgetBuilder_holderMaker_gadget_Stage2(SafeDIStagedScope_Gadget_holderMaker_gadget.Stage2(token: token))
		            return Holder(token: token, gadget: gadget)
		        }
		        let holderMaker = SendableInstantiator<Holder> {
		            __safeDI_holderMaker(token: $0)
		        }
		        self.init(holderMaker: holderMaker)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_941FCAED062F4376 {}
		}
		"""])
		try expectEveryModuleCompiled(output)
	}

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

				    public init(gadgetBuilder: @escaping (SafeDIScope_Gadget) -> any Gadget) {
				        let __safeDI_gadgetBuilder = gadgetBuilder
				        let session = Session()
				        func __safeDI_inner() -> Inner {
				            _ = Inner.__safeDI_Inner_A441BC75156D061F.self\(seamCallComment(seam: "Inner", module: "Feature"))
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
				            return Inner(widgetBuilder: __safeDI_widgetBuilder_Inner)
				        }
				        let inner: Inner = __safeDI_inner()
				        self.init(session: session, inner: inner)
				    }
				}

				extension Host {
				    public enum __safeDI_Host_9C23B9AD5CDCF084 {}
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

				    public init(gadgetBuilder: @escaping (SafeDIScope_Gadget) -> any Gadget) {
				        let __safeDI_gadgetBuilder = gadgetBuilder
				        let session = Session()
				        func __safeDI_inner() -> Inner {
				            _ = Inner.__safeDI_Inner_A441BC75156D061F.self\(seamCallComment(seam: "Inner", module: "Feature"))
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
				            return Inner(widgetBuilder: __safeDI_widgetBuilder_Inner)
				        }
				        let inner: Inner = __safeDI_inner()
				        self.init(session: session, inner: inner)
				    }
				}

				extension Host {
				    public enum __safeDI_Host_C145425651CBFCDB {}
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

				    public init(gadgetBuilder: @escaping (SafeDIScope_Gadget) -> any Gadget) {
				        let __safeDI_gadgetBuilder = gadgetBuilder
				        let session = Session()
				        func __safeDI_inner() -> Inner {
				            _ = Inner.__safeDI_Inner_A441BC75156D061F.self\(seamCallComment(seam: "Inner", module: "Feature"))
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
				            return Inner(widgetBuilder: __safeDI_widgetBuilder_Inner)
				        }
				        let inner: Inner = __safeDI_inner()
				        self.init(session: session, inner: inner)
				    }
				}

				extension Host {
				    public enum __safeDI_Host_2FBF3483F498BCE7 {}
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
		try expectEveryModuleCompiled(output)
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
		    public enum SafeDIStagedScope_Gadget_shell_Inner_widget_gadget {
		        public struct Stage1 {
		            public let session: Session
		        }

		        public struct Stage2 {
		            public let analytics: Analytics
		        }
		    }

		    public init(gadgetBuilder_shell_Inner_widget_gadget: @escaping (SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage1) -> @Sendable (SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage2) -> any Gadget) {
		        let __safeDI_gadgetBuilder_shell_Inner_widget_gadget = gadgetBuilder_shell_Inner_widget_gadget
		        let session = Session()
		        func __safeDI_shell() -> Shell {
		            _ = Shell.__safeDI_Shell_076D60492DA3478F.self\(seamCallComment(seam: "Shell", module: "Feature"))
		            let __safeDI_gadgetBuilder_shell_Inner_widget_gadget_Stage2 = __safeDI_gadgetBuilder_shell_Inner_widget_gadget(SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage1(session: session))
		            @Sendable func __safeDI_widgetBuilder_Inner_widget(_ scope: Inner.SafeDIScope_Widget.widget_Values) -> any Widget {
		                func __safeDI_widget() -> DefaultWidget {
		                    let analytics = Analytics()
		                    let gadget: any Gadget = __safeDI_gadgetBuilder_shell_Inner_widget_gadget_Stage2(SafeDIStagedScope_Gadget_shell_Inner_widget_gadget.Stage2(analytics: analytics))
		                    return DefaultWidget(analytics: analytics, gadget: gadget)
		                }
		                let widget: any Widget = __safeDI_widget()
		                return widget
		            }
		            @Sendable func __safeDI_widgetSendableBuilder_Shell(_ scope: Shell.SafeDISendableScope_Widget) -> any Widget {
		                switch scope {
		                case let .innerBuilder(scope): return __safeDI_widgetBuilder_Inner(scope)
		                }
		            }
		            @Sendable func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
		                switch scope {
		                case let .widget(scope): return __safeDI_widgetBuilder_Inner_widget(scope)
		                }
		            }
		            return Shell(widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell)
		        }
		        let shell: Shell = __safeDI_shell()
		        self.init(session: session, shell: shell)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_C2B8446A21A9B91D {}
		}
		"""])
		try expectEveryModuleCompiled(output)
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	// MARK: Raw-identifier labels in the names of stages

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsStageFunctionAsOneIdentifier_whenPlaceInSendableFillHasRawIdentifierLabel() async throws {
		let fixture = Self.fixtureOfSendableFillWithPlace(
			widgetDeclarations: ["@Instantiated let `my gadget`: any Gadget"],
			gadgetDeclarations: ["@Received let session: Session"],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "Middle", imports: ["Feature"], rootFiles: ["Host": """
		extension Host {
		    public enum `SafeDIStagedScope_Gadget_shell_Inner_widget_my gadget` {
		        public struct Stage1 {
		            public let session: Session
		        }

		        public struct Stage2 {
		            public let analytics: Analytics
		        }
		    }

		    public init(`gadgetBuilder_shell_Inner_widget_my gadget`: @escaping (`SafeDIStagedScope_Gadget_shell_Inner_widget_my gadget`.Stage1) -> @Sendable (`SafeDIStagedScope_Gadget_shell_Inner_widget_my gadget`.Stage2) -> any Gadget) {
		        let `__safeDI_gadgetBuilder_shell_Inner_widget_my gadget` = `gadgetBuilder_shell_Inner_widget_my gadget`
		        let session = Session()
		        func __safeDI_shell() -> Shell {
		            _ = Shell.__safeDI_Shell_076D60492DA3478F.self\(seamCallComment(seam: "Shell", module: "Feature"))
		            let `__safeDI_gadgetBuilder_shell_Inner_widget_my gadget_Stage2` = `__safeDI_gadgetBuilder_shell_Inner_widget_my gadget`(`SafeDIStagedScope_Gadget_shell_Inner_widget_my gadget`.Stage1(session: session))
		            @Sendable func __safeDI_widgetBuilder_Inner_widget(_ scope: Inner.SafeDIScope_Widget.widget_Values) -> any Widget {
		                let analytics = scope.analytics
		                func __safeDI_widget() -> DefaultWidget {
		                    let `my gadget`: any Gadget = `__safeDI_gadgetBuilder_shell_Inner_widget_my gadget_Stage2`(`SafeDIStagedScope_Gadget_shell_Inner_widget_my gadget`.Stage2(analytics: analytics))
		                    return DefaultWidget(`my gadget`: `my gadget`)
		                }
		                let widget: any Widget = __safeDI_widget()
		                return widget
		            }
		            @Sendable func __safeDI_widgetSendableBuilder_Shell(_ scope: Shell.SafeDISendableScope_Widget) -> any Widget {
		                switch scope {
		                case let .innerBuilder(scope): return __safeDI_widgetBuilder_Inner(scope)
		                }
		            }
		            @Sendable func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
		                switch scope {
		                case let .widget(scope): return __safeDI_widgetBuilder_Inner_widget(scope)
		                }
		            }
		            return Shell(widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell)
		        }
		        let shell: Shell = __safeDI_shell()
		        self.init(session: session, shell: shell)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_F8920AFED3D541C9 {}
		}
		"""])
		expectGeneratedCode(of: output, module: "App", imports: ["Feature", "Middle"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_F8920AFED3D541C9.self\(seamCallComment(seam: "Host", module: "Middle"))
		            func `__safeDI_gadgetBuilder_shell_Inner_widget_my gadget`(_ scope: Host.`SafeDIStagedScope_Gadget_shell_Inner_widget_my gadget`.Stage1) -> @Sendable (Host.`SafeDIStagedScope_Gadget_shell_Inner_widget_my gadget`.Stage2) -> any Gadget {
		                let session = scope.session
		                @Sendable func `__safeDI_gadgetBuilder_shell_Inner_widget_my gadget_Stage2`(_ scope: Host.`SafeDIStagedScope_Gadget_shell_Inner_widget_my gadget`.Stage2) -> any Gadget {
		                    let `my gadget`: any Gadget = DefaultGadget(session: session)
		                    return `my gadget`
		                }
		                return `__safeDI_gadgetBuilder_shell_Inner_widget_my gadget_Stage2`
		            }
		            return Host(`gadgetBuilder_shell_Inner_widget_my gadget`: `__safeDI_gadgetBuilder_shell_Inner_widget_my gadget`)
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsStageFunctionAsOneIdentifier_whenPlaceBeneathSendableBuilderFunctionHasRawIdentifierLabel() async throws {
		let fixture = ThreeModules(
			feature: ["public protocol Widget: Sendable {}"],
			middle: [
				Self.gadget,
				Self.session,
				seamFixtureType(named: "Holder", declarations: ["@Instantiated let `my gadget`: any Gadget"], conformances: ", Sendable"),
				seamFixtureType(named: "Host", isSeam: true, declarations: ["@Instantiated let session: Session", "@Instantiated let holderMaker: SendableInstantiator<Holder>"], conformances: ", Sendable"),
			],
			app: [SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultGadget", fulfilling: "Gadget", declarations: ["@Received let session: Session"])],
			root: Self.root,
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "Middle", imports: ["Feature"], rootFiles: ["Host": """
		extension Host {
		    public enum `SafeDIStagedScope_Gadget_holderMaker_my gadget` {
		        public struct Stage1 {
		            public let session: Session
		        }

		        public struct Stage2 {}
		    }

		    public init(`gadgetBuilder_holderMaker_my gadget`: @escaping (`SafeDIStagedScope_Gadget_holderMaker_my gadget`.Stage1) -> @Sendable (`SafeDIStagedScope_Gadget_holderMaker_my gadget`.Stage2) -> any Gadget) {
		        let `__safeDI_gadgetBuilder_holderMaker_my gadget` = `gadgetBuilder_holderMaker_my gadget`
		        let session = Session()
		        let `__safeDI_gadgetBuilder_holderMaker_my gadget_Stage2` = `__safeDI_gadgetBuilder_holderMaker_my gadget`(`SafeDIStagedScope_Gadget_holderMaker_my gadget`.Stage1(session: session))
		        @Sendable func __safeDI_holderMaker() -> Holder {
		            let `my gadget`: any Gadget = `__safeDI_gadgetBuilder_holderMaker_my gadget_Stage2`(`SafeDIStagedScope_Gadget_holderMaker_my gadget`.Stage2())
		            return Holder(`my gadget`: `my gadget`)
		        }
		        let holderMaker = SendableInstantiator<Holder>(__safeDI_holderMaker)
		        self.init(session: session, holderMaker: holderMaker)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_D1DBA7F623008717 {}
		}
		"""])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsStageFunctionsAsOneIdentifier_whenStagedFilledHoleHasRawIdentifierLabel() async throws {
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
		    public enum `SafeDIStagedScope_Widget_panelBuilder_my widget` {
		        public struct Stage1 {
		            public let analytics: Analytics
		        }

		        public struct Stage2 {}
		    }

		    public init(`widgetBuilder_panelBuilder_my widget`: @escaping (`SafeDIStagedScope_Widget_panelBuilder_my widget`.Stage1) -> @Sendable (`SafeDIStagedScope_Widget_panelBuilder_my widget`.Stage2) -> any Widget) {
		        let `__safeDI_widgetBuilder_panelBuilder_my widget` = `widgetBuilder_panelBuilder_my widget`
		        let analytics = Analytics()
		        let `__safeDI_widgetBuilder_panelBuilder_my widget_Stage2` = `__safeDI_widgetBuilder_panelBuilder_my widget`(`SafeDIStagedScope_Widget_panelBuilder_my widget`.Stage1(analytics: analytics))
		        @Sendable func __safeDI_panelBuilder() -> Panel {
		            let `my widget`: any Widget = `__safeDI_widgetBuilder_panelBuilder_my widget_Stage2`(`SafeDIStagedScope_Widget_panelBuilder_my widget`.Stage2())
		            return Panel(`my widget`: `my widget`)
		        }
		        let panelBuilder = SendableInstantiator<Panel>(__safeDI_panelBuilder)
		        self.init(analytics: analytics, panelBuilder: panelBuilder)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_5D877CA0996E6990 {}
		}
		"""])
		expectGeneratedCode(of: output, module: "Middle", imports: ["Feature"], rootFiles: ["Host": """
		extension Host {
		    public init() {
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_5D877CA0996E6990.self\(seamCallComment(seam: "Inner", module: "Feature"))
		            func `__safeDI_widgetBuilder_panelBuilder_my widget`(_ scope: Inner.`SafeDIStagedScope_Widget_panelBuilder_my widget`.Stage1) -> @Sendable (Inner.`SafeDIStagedScope_Widget_panelBuilder_my widget`.Stage2) -> any Widget {
		                @Sendable func `__safeDI_widgetBuilder_panelBuilder_my widget_Stage2`(_ scope: Inner.`SafeDIStagedScope_Widget_panelBuilder_my widget`.Stage2) -> any Widget {
		                    let `my widget`: any Widget = DefaultWidget()
		                    return `my widget`
		                }
		                return `__safeDI_widgetBuilder_panelBuilder_my widget_Stage2`
		            }
		            return Inner(`widgetBuilder_panelBuilder_my widget`: `__safeDI_widgetBuilder_panelBuilder_my widget`)
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(inner: inner)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_CBF29CE484222325 {}
		}
		"""])
		try expectEveryModuleCompiled(output)
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
		    public init() {
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_5A8797B87FCD6716.self\(seamCallComment(seam: "Inner", module: "Feature"))
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
		            return Inner(widgetBuilder: __safeDI_widgetBuilder_Inner)
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(inner: inner)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_CBF29CE484222325 {}
		}
		"""])
		try expectEveryModuleCompiled(output)
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesEveryStagesParameterApart_whenFieldOfFirstStageIsLabeledScopeAndReadInLastStage() async throws {
		// A later stage's parameter would hide the field the first stage bound.
		let fixture = ThreeModules(
			feature: [
				"public protocol Widget: Sendable {}",
				seamFixtureType(named: "Analytics", declarations: [], conformances: ", Sendable"),
				seamFixtureType(named: "Panel", declarations: ["@Instantiated let widget: any Widget"], conformances: ", Sendable"),
				seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated let scope: Analytics", "@Instantiated let panelBuilder: SendableInstantiator<Panel>"], conformances: ", Sendable"),
			],
			middle: [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: ["@Received let scope: Analytics"]),
				seamFixtureType(named: "Host", isSeam: true, declarations: ["@Instantiated let inner: Inner"], conformances: ", Sendable"),
			],
			app: [],
			root: Self.root,
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedCode(of: output, module: "Middle", imports: ["Feature"], rootFiles: ["Host": """
		extension Host {
		    public init() {
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_00743EAB528C6956.self\(seamCallComment(seam: "Inner", module: "Feature"))
		            func __safeDI_widgetBuilder_panelBuilder_widget(_ scope_: Inner.SafeDIStagedScope_Widget_panelBuilder_widget.Stage1) -> @Sendable (Inner.SafeDIStagedScope_Widget_panelBuilder_widget.Stage2) -> any Widget {
		                let scope = scope_.scope
		                @Sendable func __safeDI_widgetBuilder_panelBuilder_widget_Stage2(_ scope_: Inner.SafeDIStagedScope_Widget_panelBuilder_widget.Stage2) -> any Widget {
		                    let widget: any Widget = DefaultWidget(scope: scope)
		                    return widget
		                }
		                return __safeDI_widgetBuilder_panelBuilder_widget_Stage2
		            }
		            return Inner(widgetBuilder_panelBuilder_widget: __safeDI_widgetBuilder_panelBuilder_widget)
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(inner: inner)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_CBF29CE484222325 {}
		}
		"""])
		try expectEveryModuleCompiled(output)
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
		    public init() {
		        let scope = Analytics()
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_0D6DF99B501922EC.self\(seamCallComment(seam: "Inner", module: "Feature"))
		            func __safeDI_widgetBuilder_Inner_widget(_ scope_: Inner.SafeDIScope_Widget.widget_Values) -> any Widget {
		                let widget: any Widget = DefaultWidget(scope: scope)
		                return widget
		            }
		            func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Widget) -> any Widget {
		                switch scope {
		                case let .widget(scope): return __safeDI_widgetBuilder_Inner_widget(scope)
		                }
		            }
		            return Inner(widgetBuilder: __safeDI_widgetBuilder_Inner)
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(scope: scope, inner: inner)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_CBF29CE484222325 {}
		}
		"""])
		try expectEveryModuleCompiled(output)
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

	/// Expects every module to have compiled, when compile verification runs.
	private func expectEveryModuleCompiled(_ output: MultiModuleTestOutput, sourceLocation: SourceLocation = #_sourceLocation) throws {
		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation, sourceLocation: sourceLocation)
		#expect(compilation.modules.map(\.exitCode) == output.moduleNames.map { _ in 0 }, sourceLocation: sourceLocation)
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
		try expectDifferentialValuesAgree(
			feature: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: output, modules: modules),
			knownRight: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: visibleOutput, modules: visibleModules),
			probes: [DifferentialValueProbe("Root()")],
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}
}
