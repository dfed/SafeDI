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

/// A place built inside a `@Sendable` function is a case of its hole type's `@Sendable` enum, nested by type as the plain
/// enum is: the `@Sendable` builder is handed the chain of cases from the seam to the innermost `@Sendable` function that
/// builds the place, which carry no values, and beneath it the plain enum of the type that function builds, whose cases
/// carry what the function binds. A fill that reads a value bound outside that function is an error; the seam's
/// parameters it reads from the caller's own scope. These tests hold the values each fill builds to those of the same
/// graph built inline.
struct SafeDIToolSeamSendableScopeByTypeTests: ~Copyable {
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
	mutating func generate_holdsPlainEnumOfFunctionsTypeInSendableCase_whenPlaceIsInsideSendableBuilderFunction() async throws {
		// `Shell` builds `widget` in plain code and `Panel` behind `panelBuilder: SendableInstantiator<Panel>`, whose function
		// builds another `widget`. The plain enum describes `Shell`; the `@Sendable` enum's `shell_Sendable` case leads to
		// `Shell`'s `@Sendable` enum, whose `panelBuilder` case holds `Panel`'s plain enum, whose case carries what the
		// function binds: `name` and its own `part`.
		try await expectSeam(
			feature: [
				"public protocol Widget {}",
				seamFixtureType(named: "Part", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Panel", declarations: ["@Forwarded public let name: String", "@Instantiated public let part: Part", "@Instantiated public let widget: any Widget"]),
				seamFixtureType(named: "Shell", declarations: ["@Instantiated public let part: Part", "@Instantiated public let panelBuilder: SendableInstantiator<Panel>", "@Instantiated public let widget: any Widget"]),
				seamFixtureType(named: "Host", isSeam: true, declarations: ["@Instantiated public let shell: Shell"]),
			],
			fulfillers: [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: ["@Received public let part: Part", "@Received(onlyIfAvailable: true) public let name: String?"]),
			],
			root: seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let host: Host"]),
			probes: [
				DifferentialValueProbe("Root()"),
				DifferentialValueProbe(#"Root().host.shell.panelBuilder.instantiate("panel")"#),
			],
			expectedFeature: """
			extension Host {
			    @frozen public enum SafeDIScope_Widget {
			        case shell(shell_Values, SafeDIScope_Widget.Shell_Scope)

			        public struct shell_Values {}

			        @frozen public enum Shell_Scope {
			            case widget(widget_Values)

			            public struct widget_Values {
			                public let part: Part
			                public let panelBuilder: SendableInstantiator<Panel>
			            }
			        }

			        @frozen public enum Panel_Scope {
			            case widget(widget_Values)

			            public struct widget_Values {
			                public let name: String
			                public let part: Part
			            }
			        }
			    }

			    @frozen public enum SafeDISendableScope_Widget {
			        case shell_Sendable(SafeDISendableScope_Widget.Shell_Scope)

			        @frozen public enum Shell_Scope {
			            case panelBuilder(SafeDIScope_Widget.Panel_Scope)
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_widgetBuilder: @escaping (SafeDIScope_Widget) -> any Widget, __safeDI_widgetSendableBuilder: @escaping @Sendable (SafeDISendableScope_Widget) -> any Widget) {
			        let __safeDI_widgetValues_shell = SafeDIScope_Widget.shell_Values()
			        func __safeDI_shell() -> Shell {
			            let part = Part()
			            @Sendable func __safeDI_panelBuilder(name: String) -> Panel {
			                let part = Part()
			                let widget: any Widget = __safeDI_widgetSendableBuilder(.shell_Sendable(.panelBuilder(.widget(SafeDIScope_Widget.Panel_Scope.widget_Values(name: name, part: part)))))
			                return Panel(name: name, part: part, widget: widget)
			            }
			            let panelBuilder = SendableInstantiator<Panel> {
			                __safeDI_panelBuilder(name: $0)
			            }
			            let widget: any Widget = __safeDI_widgetBuilder(.shell(__safeDI_widgetValues_shell, .widget(SafeDIScope_Widget.Shell_Scope.widget_Values(part: part, panelBuilder: panelBuilder))))
			            return Shell(part: part, panelBuilder: panelBuilder, widget: widget)
			        }
			        let shell: Shell = __safeDI_shell()
			        self.init(shell: shell)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_27F192DC6292D590 {}
			}
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_27F192DC6292D590.self // \(Self.moduleInfoComment)
			            func __safeDI_widgetBuilder_Host(_ scope: Host.SafeDIScope_Widget) -> any Widget {
			                switch scope {
			                case let .shell(_, scope): return __safeDI_widgetBuilder_Host_Shell_Scope(scope)
			                }
			            }
			            func __safeDI_widgetBuilder_Host_Shell_Scope(_ scope: Host.SafeDIScope_Widget.Shell_Scope) -> any Widget {
			                switch scope {
			                case let .widget(scope):
			                    let part = scope.part
			                    let widget: any Widget = DefaultWidget(part: part, name: nil)
			                    return widget
			                }
			            }
			            @Sendable func __safeDI_widgetSendableBuilder_Host(_ scope: Host.SafeDISendableScope_Widget) -> any Widget {
			                switch scope {
			                case let .shell_Sendable(scope): return __safeDI_widgetSendableBuilder_Host_Shell_Scope(scope)
			                }
			            }
			            @Sendable func __safeDI_widgetSendableBuilder_Host_Shell_Scope(_ scope: Host.SafeDISendableScope_Widget.Shell_Scope) -> any Widget {
			                switch scope {
			                case let .panelBuilder(scope): return __safeDI_widgetBuilder_Host_Panel_Scope(scope)
			                }
			            }
			            @Sendable func __safeDI_widgetBuilder_Host_Panel_Scope(_ scope: Host.SafeDIScope_Widget.Panel_Scope) -> any Widget {
			                switch scope {
			                case let .widget(scope):
			                    let name = scope.name
			                    let part = scope.part
			                    let widget: any Widget = DefaultWidget(part: part, name: name)
			                    return widget
			                }
			            }
			            return Host(__safeDI_widgetBuilder: __safeDI_widgetBuilder_Host, __safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Host)
			        }
			        let host: Host = __safeDI_host()
			        self.init(host: host)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_carriesOnlyForwardedValue_whenPlaceIsHeldInSendableWrapper() async throws {
		// `widgetBuilder: SendableErasedInstantiator<Int, any Widget>` is a place of the `@Sendable` enum: the wrapper's
		// function binds nothing, so its case carries only the value the instantiator forwards.
		try await expectSeam(
			feature: [
				"public protocol Widget: Sendable {}",
				seamFixtureType(named: "Shell", declarations: [#"@Instantiated(fulfilledByType: "DefaultWidget") public let widgetBuilder: SendableErasedInstantiator<Int, any Widget>"#]),
				seamFixtureType(named: "Host", isSeam: true, declarations: ["@Instantiated public let shell: Shell"]),
			],
			fulfillers: [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: ["@Forwarded public let id: Int"]),
			],
			root: seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let host: Host"]),
			probes: [
				DifferentialValueProbe("Root()"),
				DifferentialValueProbe("Root().host.shell.widgetBuilder.instantiate(7)"),
			],
			expectedFeature: """
			extension Host {
			    @frozen public enum SafeDISendableScope_DefaultWidget {
			        case shell_Sendable(SafeDISendableScope_DefaultWidget.Shell_Scope)

			        @frozen public enum Shell_Scope {
			            case widgetBuilder(Int)
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_defaultWidgetSendableBuilder: @escaping @Sendable (SafeDISendableScope_DefaultWidget) -> any Widget) {
			        func __safeDI_shell() -> Shell {
			            let widgetBuilder = SendableErasedInstantiator<Int, any Widget> {
			                __safeDI_defaultWidgetSendableBuilder(.shell_Sendable(.widgetBuilder($0)))
			            }
			            return Shell(widgetBuilder: widgetBuilder)
			        }
			        let shell: Shell = __safeDI_shell()
			        self.init(shell: shell)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_8099453269670052 {}
			}
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_8099453269670052.self // \(Self.moduleInfoComment)
			            @Sendable func __safeDI_defaultWidgetSendableBuilder_Host(_ scope: Host.SafeDISendableScope_DefaultWidget) -> any Widget {
			                switch scope {
			                case let .shell_Sendable(scope): return __safeDI_defaultWidgetSendableBuilder_Host_Shell_Scope(scope)
			                }
			            }
			            @Sendable func __safeDI_defaultWidgetSendableBuilder_Host_Shell_Scope(_ scope: Host.SafeDISendableScope_DefaultWidget.Shell_Scope) -> any Widget {
			                switch scope {
			                case let .widgetBuilder(__safeDI_forwarded):
			                    @Sendable func __safeDI_widgetBuilder(id: Int) -> DefaultWidget {
			                        DefaultWidget(id: id)
			                    }
			                    return __safeDI_widgetBuilder(id: __safeDI_forwarded)
			                }
			            }
			            return Host(__safeDI_defaultWidgetSendableBuilder: __safeDI_defaultWidgetSendableBuilder_Host)
			        }
			        let host: Host = __safeDI_host()
			        self.init(host: host)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsPlainAndSendableRoutesWithOneFill_whenTypeIsBuiltInPlainCodeAndInSendableFunction() async throws {
		// `Panel` is built in plain code under `plainPanel` and behind `panelBuilder: SendableInstantiator<Panel>`: one case
		// of `Panel`'s plain enum stands for both places, its one fill is `@Sendable`, and each route hands it `Panel`'s own
		// `name`.
		try await expectSeam(
			feature: [
				"public protocol Widget {}",
				seamFixtureType(named: "Panel", declarations: ["@Forwarded public let name: String", "@Instantiated public let widget: any Widget"]),
				seamFixtureType(named: "Shell", declarations: ["@Instantiated public let panelBuilder: SendableInstantiator<Panel>", "@Instantiated public let plainPanelBuilder: Instantiator<Panel>"]),
				seamFixtureType(named: "Host", isSeam: true, declarations: ["@Instantiated public let shell: Shell"]),
			],
			fulfillers: [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: ["@Received public let name: String"]),
			],
			root: seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let host: Host"]),
			probes: [
				DifferentialValueProbe(#"Root().host.shell.panelBuilder.instantiate("sendable")"#),
				DifferentialValueProbe(#"Root().host.shell.plainPanelBuilder.instantiate("plain")"#),
			],
			expectedFeature: """
			extension Host {
			    @frozen public enum SafeDIScope_Widget {
			        case shell(shell_Values, SafeDIScope_Widget.Shell_Scope)

			        public struct shell_Values {}

			        @frozen public enum Shell_Scope {
			            case plainPanelBuilder(plainPanelBuilder_Values, SafeDIScope_Widget.Panel_Scope)

			            public struct plainPanelBuilder_Values {
			                public let panelBuilder: SendableInstantiator<Panel>
			            }
			        }

			        @frozen public enum Panel_Scope {
			            case widget(widget_Values)

			            public struct widget_Values {
			                public let name: String
			            }
			        }
			    }

			    @frozen public enum SafeDISendableScope_Widget {
			        case shell_Sendable(SafeDISendableScope_Widget.Shell_Scope)

			        @frozen public enum Shell_Scope {
			            case panelBuilder(SafeDIScope_Widget.Panel_Scope)
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_widgetBuilder: @escaping (SafeDIScope_Widget) -> any Widget, __safeDI_widgetSendableBuilder: @escaping @Sendable (SafeDISendableScope_Widget) -> any Widget) {
			        let __safeDI_widgetValues_shell = SafeDIScope_Widget.shell_Values()
			        func __safeDI_shell() -> Shell {
			            @Sendable func __safeDI_panelBuilder(name: String) -> Panel {
			                let widget: any Widget = __safeDI_widgetSendableBuilder(.shell_Sendable(.panelBuilder(.widget(SafeDIScope_Widget.Panel_Scope.widget_Values(name: name)))))
			                return Panel(name: name, widget: widget)
			            }
			            let panelBuilder = SendableInstantiator<Panel> {
			                __safeDI_panelBuilder(name: $0)
			            }
			            let __safeDI_widgetValues_plainPanelBuilder = SafeDIScope_Widget.Shell_Scope.plainPanelBuilder_Values(panelBuilder: panelBuilder)
			            func __safeDI_plainPanelBuilder(name: String) -> Panel {
			                let widget: any Widget = __safeDI_widgetBuilder(.shell(__safeDI_widgetValues_shell, .plainPanelBuilder(__safeDI_widgetValues_plainPanelBuilder, .widget(SafeDIScope_Widget.Panel_Scope.widget_Values(name: name)))))
			                return Panel(name: name, widget: widget)
			            }
			            let plainPanelBuilder = Instantiator<Panel> {
			                __safeDI_plainPanelBuilder(name: $0)
			            }
			            return Shell(panelBuilder: panelBuilder, plainPanelBuilder: plainPanelBuilder)
			        }
			        let shell: Shell = __safeDI_shell()
			        self.init(shell: shell)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_0A15B5874FB87940 {}
			}
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_0A15B5874FB87940.self // \(Self.moduleInfoComment)
			            func __safeDI_widgetBuilder_Host(_ scope: Host.SafeDIScope_Widget) -> any Widget {
			                switch scope {
			                case let .shell(_, scope): return __safeDI_widgetBuilder_Host_Shell_Scope(scope)
			                }
			            }
			            func __safeDI_widgetBuilder_Host_Shell_Scope(_ scope: Host.SafeDIScope_Widget.Shell_Scope) -> any Widget {
			                switch scope {
			                case let .plainPanelBuilder(_, scope): return __safeDI_widgetBuilder_Host_Panel_Scope(scope)
			                }
			            }
			            @Sendable func __safeDI_widgetBuilder_Host_Panel_Scope(_ scope: Host.SafeDIScope_Widget.Panel_Scope) -> any Widget {
			                switch scope {
			                case let .widget(scope):
			                    let name = scope.name
			                    let widget: any Widget = DefaultWidget(name: name)
			                    return widget
			                }
			            }
			            @Sendable func __safeDI_widgetSendableBuilder_Host(_ scope: Host.SafeDISendableScope_Widget) -> any Widget {
			                switch scope {
			                case let .shell_Sendable(scope): return __safeDI_widgetSendableBuilder_Host_Shell_Scope(scope)
			                }
			            }
			            @Sendable func __safeDI_widgetSendableBuilder_Host_Shell_Scope(_ scope: Host.SafeDISendableScope_Widget.Shell_Scope) -> any Widget {
			                switch scope {
			                case let .panelBuilder(scope): return __safeDI_widgetBuilder_Host_Panel_Scope(scope)
			                }
			            }
			            return Host(__safeDI_widgetBuilder: __safeDI_widgetBuilder_Host, __safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Host)
			        }
			        let host: Host = __safeDI_host()
			        self.init(host: host)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillReadsCallersValue_whenPlaceInsideSendableFunctionReadsSeamParameter() async throws {
		// `Host` receives `theme`, which the place inside `panelBuilder`'s function reads: a parameter of the seam is no field
		// of a place built in a `@Sendable` function, and the fill reads `Root`'s own `theme`, as inline reads the value the
		// call passes.
		try await expectSeam(
			feature: [
				"public protocol Widget {}",
				seamFixtureType(named: "Theme", isFinalClass: true, declarations: [], conformances: ", @unchecked Sendable"),
				seamFixtureType(named: "Panel", declarations: ["@Forwarded public let name: String", "@Instantiated public let widget: any Widget"]),
				seamFixtureType(named: "Host", isSeam: true, declarations: ["@Received public let theme: Theme", "@Instantiated public let panelBuilder: SendableInstantiator<Panel>"]),
			],
			fulfillers: [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: ["@Received public let theme: Theme"]),
			],
			root: seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let theme: Theme", "@Instantiated public let host: Host"]),
			probes: [
				DifferentialValueProbe(#"Root().host.panelBuilder.instantiate("panel")"#),
			],
			expectedFeature: """
			extension Host {
			    @frozen public enum SafeDIScope_Widget {
			        @frozen public enum Panel_Scope {
			            case widget(widget_Values)

			            public struct widget_Values {
			                public let name: String
			            }
			        }
			    }

			    @frozen public enum SafeDISendableScope_Widget {
			        case panelBuilder(SafeDIScope_Widget.Panel_Scope)
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_theme theme: Theme, __safeDI_widgetSendableBuilder: @escaping @Sendable (SafeDISendableScope_Widget) -> any Widget) {
			        @Sendable func __safeDI_panelBuilder(name: String) -> Panel {
			            let widget: any Widget = __safeDI_widgetSendableBuilder(.panelBuilder(.widget(SafeDIScope_Widget.Panel_Scope.widget_Values(name: name))))
			            return Panel(name: name, widget: widget)
			        }
			        let panelBuilder = SendableInstantiator<Panel> {
			            __safeDI_panelBuilder(name: $0)
			        }
			        self.init(theme: theme, panelBuilder: panelBuilder)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_89A03981E5B9A3C2 {}
			}
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        let theme = Theme()
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_89A03981E5B9A3C2.self // \(Self.moduleInfoComment)
			            @Sendable func __safeDI_widgetSendableBuilder_Host(_ scope: Host.SafeDISendableScope_Widget) -> any Widget {
			                switch scope {
			                case let .panelBuilder(scope): return __safeDI_widgetBuilder_Host_Panel_Scope(scope)
			                }
			            }
			            @Sendable func __safeDI_widgetBuilder_Host_Panel_Scope(_ scope: Host.SafeDIScope_Widget.Panel_Scope) -> any Widget {
			                switch scope {
			                case .widget:
			                    let widget: any Widget = DefaultWidget(theme: theme)
			                    return widget
			                }
			            }
			            return Host(__safeDI_theme: theme, __safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Host)
			        }
			        let host: Host = __safeDI_host()
			        self.init(theme: theme, host: host)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesSendableBeneathCaseApart_whenTypeDeclaresPropertyOfThatName() async throws {
		// `Shell`'s `screen` builds `Screen`, beneath which a `@Sendable` function builds a place: its case would be
		// `screen_Sendable`, which `Shell`'s own `screen_Sendable`, a `@Sendable` function holding a place, names. A case keeps
		// its label, so the case of `screen` takes `_`.
		try await expectSeam(
			feature: [
				"public protocol Widget {}",
				seamFixtureType(named: "Panel", declarations: ["@Forwarded public let name: String", "@Instantiated public let widget: any Widget"]),
				seamFixtureType(named: "Screen", declarations: ["@Instantiated public let panelBuilder: SendableInstantiator<Panel>"]),
				seamFixtureType(named: "Shell", declarations: ["@Instantiated public let screen: Screen", "@Instantiated public let screen_Sendable: SendableInstantiator<Panel>"]),
				seamFixtureType(named: "Host", isSeam: true, declarations: ["@Instantiated public let shell: Shell"]),
			],
			fulfillers: [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: ["@Received public let name: String"]),
			],
			root: seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let host: Host"]),
			probes: [
				DifferentialValueProbe(#"Root().host.shell.screen.panelBuilder.instantiate("beneath")"#),
				DifferentialValueProbe(#"Root().host.shell.screen_Sendable.instantiate("own")"#),
			],
			expectedFeature: """
			extension Host {
			    @frozen public enum SafeDIScope_Widget {
			        @frozen public enum Panel_Scope {
			            case widget(widget_Values)

			            public struct widget_Values {
			                public let name: String
			            }
			        }
			    }

			    @frozen public enum SafeDISendableScope_Widget {
			        case shell_Sendable(SafeDISendableScope_Widget.Shell_Scope)

			        @frozen public enum Shell_Scope {
			            case screen_Sendable_(SafeDISendableScope_Widget.Screen_Scope)
			            case screen_Sendable(SafeDIScope_Widget.Panel_Scope)
			        }

			        @frozen public enum Screen_Scope {
			            case panelBuilder(SafeDIScope_Widget.Panel_Scope)
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_widgetSendableBuilder: @escaping @Sendable (SafeDISendableScope_Widget) -> any Widget) {
			        func __safeDI_shell() -> Shell {
			            func __safeDI_screen() -> Screen {
			                @Sendable func __safeDI_panelBuilder(name: String) -> Panel {
			                    let widget: any Widget = __safeDI_widgetSendableBuilder(.shell_Sendable(.screen_Sendable_(.panelBuilder(.widget(SafeDIScope_Widget.Panel_Scope.widget_Values(name: name))))))
			                    return Panel(name: name, widget: widget)
			                }
			                let panelBuilder = SendableInstantiator<Panel> {
			                    __safeDI_panelBuilder(name: $0)
			                }
			                return Screen(panelBuilder: panelBuilder)
			            }
			            let screen: Screen = __safeDI_screen()
			            @Sendable func __safeDI_screen_Sendable(name: String) -> Panel {
			                let widget: any Widget = __safeDI_widgetSendableBuilder(.shell_Sendable(.screen_Sendable(.widget(SafeDIScope_Widget.Panel_Scope.widget_Values(name: name)))))
			                return Panel(name: name, widget: widget)
			            }
			            let screen_Sendable = SendableInstantiator<Panel> {
			                __safeDI_screen_Sendable(name: $0)
			            }
			            return Shell(screen: screen, screen_Sendable: screen_Sendable)
			        }
			        let shell: Shell = __safeDI_shell()
			        self.init(shell: shell)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_6B9F163F29D27A81 {}
			}
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_6B9F163F29D27A81.self // \(Self.moduleInfoComment)
			            @Sendable func __safeDI_widgetSendableBuilder_Host(_ scope: Host.SafeDISendableScope_Widget) -> any Widget {
			                switch scope {
			                case let .shell_Sendable(scope): return __safeDI_widgetSendableBuilder_Host_Shell_Scope(scope)
			                }
			            }
			            @Sendable func __safeDI_widgetSendableBuilder_Host_Shell_Scope(_ scope: Host.SafeDISendableScope_Widget.Shell_Scope) -> any Widget {
			                switch scope {
			                case let .screen_Sendable_(scope): return __safeDI_widgetSendableBuilder_Host_Screen_Scope(scope)
			                case let .screen_Sendable(scope): return __safeDI_widgetBuilder_Host_Panel_Scope(scope)
			                }
			            }
			            @Sendable func __safeDI_widgetSendableBuilder_Host_Screen_Scope(_ scope: Host.SafeDISendableScope_Widget.Screen_Scope) -> any Widget {
			                switch scope {
			                case let .panelBuilder(scope): return __safeDI_widgetBuilder_Host_Panel_Scope(scope)
			                }
			            }
			            @Sendable func __safeDI_widgetBuilder_Host_Panel_Scope(_ scope: Host.SafeDIScope_Widget.Panel_Scope) -> any Widget {
			                switch scope {
			                case let .widget(scope):
			                    let name = scope.name
			                    let widget: any Widget = DefaultWidget(name: name)
			                    return widget
			                }
			            }
			            return Host(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Host)
			        }
			        let host: Host = __safeDI_host()
			        self.init(host: host)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsValueBoundOutsideSendableFunction_whenFillRequiresValueTheSeamInstantiatesOutsideIt() async {
		// `DefaultWidget` requires `part`, which `Shell` instantiates outside the `@Sendable` function that builds `Panel`:
		// a place is handed only what that function binds.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["DefaultWidget.swift"]):9:5: error: `DefaultWidget` receives `part: Part`, which `Shell` declares outside the `@Sendable` function that builds `panelBuilder: SendableInstantiator<Panel>`, and the scope SafeDI hands the builder for `Panel`’s `widget: any Widget` (case `Panel_Scope.widget` of `widgetSendableBuilder`) carries only what that function binds. Instantiate `part` outside `Host` and declare `@Received let part: Part` on `Host`, so the builder’s caller reads its own, or declare an @Instantiable type that fulfills `Widget` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["Shell.swift"]):8:5: note: `Shell` declares `part: Part` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: SafeDIToolSeamBuilderParameterTests.modules(
					feature: [
						"public protocol Widget {}",
						seamFixtureType(named: "Part", isFinalClass: true, declarations: []),
						seamFixtureType(named: "Panel", declarations: ["@Forwarded public let name: String", "@Instantiated public let widget: any Widget"]),
						seamFixtureType(named: "Shell", declarations: ["@Instantiated public let part: Part", "@Instantiated public let panelBuilder: SendableInstantiator<Panel>"]),
						seamFixtureType(named: "Host", isSeam: true, declarations: ["@Instantiated public let shell: Shell"]),
					],
					app: [
						SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: ["@Received public let part: Part"]),
						seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let host: Host"]),
					],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsReceiveWithoutAliasOnSeam_whenFillInsideSendableFunctionReadsLabelTheSeamAliases() async {
		// `Home` receives `service` fulfilled by the caller's `appService`, outside the `@Sendable` function that builds
		// `Screen`. Inline, `LiveApi` would read `Home`'s `service`, the caller's `appService`; the caller's own `service` is
		// another value, so the read is an error, whose remedy drops the alias rather than receiving `service` again.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `service: Service`, which `Home` receives as the caller’s `appService` outside the `@Sendable` function that builds `screenBuilder: SendableInstantiator<Screen>`, and the scope SafeDI hands the builder for `Screen`’s `api: any Api` (case `Screen_Scope.api` of `apiSendableBuilder`) carries only what that function binds. Declare `@Received let service: Service` on `Home` without `fulfilledByDependencyNamed: "appService"`, so the builder’s caller reads its own, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["Home.swift"]):8:5: note: `Home` receives `service: Service` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: SafeDIToolSeamBuilderParameterTests.modules(
					feature: [
						"public protocol Api: Sendable {}",
						seamFixtureType(named: "Service", isFinalClass: true, declarations: [], conformances: ", Sendable"),
						seamFixtureType(named: "Screen", declarations: ["@Instantiated public let api: any Api"], conformances: ", Sendable"),
						seamFixtureType(named: "Home", isSeam: true, declarations: [#"@Received(fulfilledByDependencyNamed: "appService", ofType: Service.self) public let service: Service"#, "@Instantiated public let screenBuilder: SendableInstantiator<Screen>"], conformances: ", Sendable"),
					],
					app: [
						SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: ["@Received public let service: Service"]),
						seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let appService: Service", "@Instantiated public let service: Service", "@Instantiated public let home: Home"]),
					],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsReceiveWithoutAliasOnInnerType_whenFillInsideSendableFunctionReadsLabelATypeInTheSeamsTreeAliases() async {
		// `Mid`, in `Home`'s tree, receives `service` fulfilled by `Home`'s `appService`, outside the `@Sendable` function
		// that builds `Screen`. Inline, `LiveApi` would read `Mid`'s `service`, `Home`'s `appService`; the caller's own
		// `service` is another value. Receiving `service` on `Home` would leave `Mid`'s alias in place, so the remedy drops
		// the alias on `Mid` and has `service` instantiated outside `Home`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `service: Service`, which `Mid` receives as `appService` outside the `@Sendable` function that builds `screenBuilder: SendableInstantiator<Screen>`, and the scope SafeDI hands the builder for `Screen`’s `api: any Api` (case `Screen_Scope.api` of `apiSendableBuilder`) carries only what that function binds. Declare `@Received let service: Service` on `Mid` without `fulfilledByDependencyNamed: "appService"`, and instantiate `service` outside `Home`, so the builder’s caller reads its own, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["Mid.swift"]):8:5: note: `Mid` receives `service: Service` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: SafeDIToolSeamBuilderParameterTests.modules(
					feature: Self.innerAliasFeature(midService: #"@Received(fulfilledByDependencyNamed: "appService", ofType: Service.self) public let service: Service"#),
					app: [
						SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: ["@Received public let service: Service"]),
						seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let service: Service", "@Instantiated public let home: Home"]),
					],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillReadsCallersValue_whenTypeInSeamsTreeReceivesLabelWithoutAliasAsTheRemedySays() async throws {
		// As above, with the remedy followed: `Mid` receives `service` without the alias, and `Root` instantiates it, so
		// `Home` takes it from its caller and `Root`'s fill reads `Root`'s `service`, which inline is `Mid`'s too.
		try await expectSeam(
			feature: Self.innerAliasFeature(midService: "@Received public let service: Service"),
			fulfillers: [SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: ["@Received public let service: Service"])],
			root: seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let service: Service", "@Instantiated public let home: Home"]),
			probes: [DifferentialValueProbe("{ () -> [Any] in let root = Root(); return [root, root.home.mid.screenBuilder.instantiate()] }()")],
			expectedFeature: """
			extension Home {
			    @frozen public enum SafeDIScope_Api {
			        @frozen public enum Screen_Scope {
			            case api(api_Values)

			            public struct api_Values {}
			        }
			    }

			    @frozen public enum SafeDISendableScope_Api {
			        case mid_Sendable(SafeDISendableScope_Api.Mid_Scope)

			        @frozen public enum Mid_Scope {
			            case screenBuilder(SafeDIScope_Api.Screen_Scope)
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_service: @autoclosure @escaping () -> Service, __safeDI_apiSendableBuilder: @escaping @Sendable (SafeDISendableScope_Api) -> any Api) {
			        let service = LazilyInstantiated<Service>(__safeDI_service)
			        let appService = Service()
			        func __safeDI_mid() -> Mid {
			            @Sendable func __safeDI_screenBuilder() -> Screen {
			                let api: any Api = __safeDI_apiSendableBuilder(.mid_Sendable(.screenBuilder(.api(SafeDIScope_Api.Screen_Scope.api_Values()))))
			                return Screen(api: api)
			            }
			            let screenBuilder = SendableInstantiator<Screen>(__safeDI_screenBuilder)
			            return Mid(service: service.instance, screenBuilder: screenBuilder)
			        }
			        let mid: Mid = __safeDI_mid()
			        self.init(appService: appService, mid: mid)
			    }
			}

			extension Home {
			    public enum __safeDI_Home_11049848DD7A39A1 {}
			}
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        let service = Service()
			        func __safeDI_home() -> Home {
			            _ = Home.__safeDI_Home_11049848DD7A39A1.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            @Sendable func __safeDI_apiSendableBuilder_Home(_ scope: Home.SafeDISendableScope_Api) -> any Api {
			                switch scope {
			                case let .mid_Sendable(scope): return __safeDI_apiSendableBuilder_Home_Mid_Scope(scope)
			                }
			            }
			            @Sendable func __safeDI_apiSendableBuilder_Home_Mid_Scope(_ scope: Home.SafeDISendableScope_Api.Mid_Scope) -> any Api {
			                switch scope {
			                case let .screenBuilder(scope): return __safeDI_apiBuilder_Home_Screen_Scope(scope)
			                }
			            }
			            @Sendable func __safeDI_apiBuilder_Home_Screen_Scope(_ scope: Home.SafeDIScope_Api.Screen_Scope) -> any Api {
			                switch scope {
			                case .api:
			                    let api: any Api = LiveApi(service: service)
			                    return api
			                }
			            }
			            return Home(__safeDI_service: service, __safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_Home)
			        }
			        let home: Home = __safeDI_home()
			        self.init(service: service, home: home)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsValueBoundOutsideSendableFunction_whenFillReadsForwardedValueOfEnclosingTypeOnlyIfAvailable() async {
		// `DefaultWidget` reads `tabName` only if available, which `Tab` forwards outside the `@Sendable` function that builds
		// `Detail`: inline it reads `Tab`'s, which the place is not handed, so it is an error rather than a silent `nil`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["DefaultWidget.swift"]):9:5: error: `DefaultWidget` receives `tabName: String?`, which `Tab` forwards outside the `@Sendable` function that builds `detailBuilder: SendableInstantiator<Detail>`, and the scope SafeDI hands the builder for `Detail`’s `widget: any Widget` (case `Detail_Scope.widget` of `widgetSendableBuilder`) carries only what that function binds. Declare `@Forwarded let tabName: String` on `Detail` too, so that function binds it, or declare an @Instantiable type that fulfills `Widget` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["Tab.swift"]):8:5: note: `Tab` declares `tabName: String` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: SafeDIToolSeamBuilderParameterTests.modules(
					feature: [
						"public protocol Widget {}",
						seamFixtureType(named: "Detail", declarations: ["@Instantiated public let widget: any Widget"]),
						seamFixtureType(named: "Tab", declarations: ["@Forwarded public let tabName: String", "@Instantiated public let detailBuilder: SendableInstantiator<Detail>"]),
						seamFixtureType(named: "Host", isSeam: true, declarations: ["@Instantiated public let tabBuilder: Instantiator<Tab>"]),
					],
					app: [
						SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: ["@Received(onlyIfAvailable: true) public let tabName: String?"]),
						seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let host: Host"]),
					],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsCycleParameterOutsideSendableFunction_whenFillReadsValueCycleInEnclosingTypePasses() async {
		// `A`'s `reader` requires `tag`, which `B` forwards before it builds `A` again, so the function that builds `A` takes
		// `tag` as a parameter. `C`, built in a `@Sendable` function inside `A`'s, holds the place: that parameter is bound
		// outside the function, and only forwarding `tag` into `C` binds it there.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `tag: Tag?`, which `A`’s builder function takes as a parameter outside the `@Sendable` function that builds `cBuilder: SendableInstantiator<C>`, because a cycle inside `A`’s tree passes it (`B` forwards `tag: Tag`), and the scope SafeDI hands the builder for `C`’s `api: any Api` (case `C_Scope.api` of `apiSendableBuilder`) carries only what that function binds. Declare `@Forwarded let tag: Tag` on `C` too, so that function binds it, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["B.swift"]):8:5: note: `B` forwards `tag: Tag` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: SafeDIToolSeamBuilderParameterTests.modules(
					feature: Self.cycleThroughSendableFunction(c: []),
					app: [
						SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: ["@Received(onlyIfAvailable: true) public let tag: Tag?"]),
						seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let tag: Tag", "@Instantiated public let hub: Hub"]),
					],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillReadsValueTheFunctionForwards_whenTypeTheSendableFunctionBuildsForwardsCycleParameterLabel() async throws {
		// As above, with the remedy followed: `C` forwards `tag`, so the `@Sendable` function binds it and the case carries it.
		try await expectSeam(
			feature: Self.cycleThroughSendableFunction(c: ["@Forwarded public let tag: Tag"]),
			fulfillers: [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: ["@Received(onlyIfAvailable: true) public let tag: Tag?"]),
			],
			root: seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let tag: Tag", "@Instantiated public let hub: Hub"]),
			probes: [
				DifferentialValueProbe(#"{ () -> [String] in let a = Root().hub.aBuilder.instantiate(); let again = a.bBuilder.instantiate(Tag(value: "b")).aBuilder.instantiate(); return [a.cBuilder.instantiate(Tag(value: "c")).api, again.cBuilder.instantiate(Tag(value: "d")).api].map { "\($0)" } }()"#),
			],
			expectedFeature: """
			extension Hub {
			    @frozen public enum SafeDIScope_Api {
			        @frozen public enum C_Scope {
			            case api(api_Values)

			            public struct api_Values {
			                public let tag: Tag
			            }
			        }
			    }

			    @frozen public enum SafeDISendableScope_Api {
			        case aBuilder_Sendable(SafeDISendableScope_Api.A_Scope)

			        @frozen public enum A_Scope {
			            case cBuilder(SafeDIScope_Api.C_Scope)
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_tag: @autoclosure @escaping () -> Tag, __safeDI_apiSendableBuilder: @escaping @Sendable (SafeDISendableScope_Api) -> any Api) {
			        let tag = LazilyInstantiated<Tag>(__safeDI_tag)
			        func __safeDI_aBuilder(tag: Tag) -> A {
			            let reader = TagReader(tag: tag)
			            func __safeDI_bBuilder(tag: Tag) -> B {
			                let aBuilder = Instantiator<A> {
			                    __safeDI_aBuilder(tag: tag)
			                }
			                return B(tag: tag, aBuilder: aBuilder)
			            }
			            let bBuilder = Instantiator<B> {
			                __safeDI_bBuilder(tag: $0)
			            }
			            @Sendable func __safeDI_cBuilder(tag: Tag) -> C {
			                let api: any Api = __safeDI_apiSendableBuilder(.aBuilder_Sendable(.cBuilder(.api(SafeDIScope_Api.C_Scope.api_Values(tag: tag)))))
			                return C(tag: tag, api: api)
			            }
			            let cBuilder = SendableInstantiator<C> {
			                __safeDI_cBuilder(tag: $0)
			            }
			            return A(reader: reader, cBuilder: cBuilder, bBuilder: bBuilder)
			        }
			        let aBuilder = Instantiator<A> {
			            __safeDI_aBuilder(tag: tag.instance)
			        }
			        self.init(aBuilder: aBuilder)
			    }
			}

			extension Hub {
			    public enum __safeDI_Hub_1C1E843EB2E86EBF {}
			}
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        let tag = Tag()
			        func __safeDI_hub() -> Hub {
			            _ = Hub.__safeDI_Hub_1C1E843EB2E86EBF.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            @Sendable func __safeDI_apiSendableBuilder_Hub(_ scope: Hub.SafeDISendableScope_Api) -> any Api {
			                switch scope {
			                case let .aBuilder_Sendable(scope): return __safeDI_apiSendableBuilder_Hub_A_Scope(scope)
			                }
			            }
			            @Sendable func __safeDI_apiSendableBuilder_Hub_A_Scope(_ scope: Hub.SafeDISendableScope_Api.A_Scope) -> any Api {
			                switch scope {
			                case let .cBuilder(scope): return __safeDI_apiBuilder_Hub_C_Scope(scope)
			                }
			            }
			            @Sendable func __safeDI_apiBuilder_Hub_C_Scope(_ scope: Hub.SafeDIScope_Api.C_Scope) -> any Api {
			                switch scope {
			                case let .api(scope):
			                    let tag = scope.tag
			                    let api: any Api = LiveApi(tag: tag)
			                    return api
			                }
			            }
			            return Hub(__safeDI_tag: tag, __safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_Hub)
			        }
			        let hub: Hub = __safeDI_hub()
			        self.init(tag: tag, hub: hub)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsCycleParameterOutsideSendableWrapper_whenPlaceHeldInWrapperReadsValueCycleInEnclosingTypePasses() async {
		// `A`'s function takes `tag` as a parameter, and `A` holds the place in a `Sendable` wrapper, whose function binds
		// nothing, so no forwarded property can carry `tag` into it.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["DefaultWidget.swift"]):11:5: error: `DefaultWidget` receives `tag: Tag?`, which `A`’s builder function takes as a parameter outside the `@Sendable` function that builds `widgetBuilder: SendableErasedInstantiator<Int, any Widget>`, because a cycle inside `A`’s tree passes it (`B` forwards `tag: Tag`), and the scope SafeDI hands the builder for `A`’s `widgetBuilder: SendableErasedInstantiator<Int, any Widget>` (case `A_Scope.widgetBuilder` of `defaultWidgetSendableBuilder`) carries only what that function binds. Declare an @Instantiable type that fulfills `DefaultWidget` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["B.swift"]):8:5: note: `B` forwards `tag: Tag` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: SafeDIToolSeamBuilderParameterTests.modules(
					feature: [
						"public protocol Widget: Sendable {}",
						Self.tag,
						seamFixtureType(named: "TagReader", declarations: ["@Received public let tag: Tag"]),
						seamFixtureType(named: "A", declarations: ["@Instantiated public let reader: TagReader", #"@Instantiated(fulfilledByType: "DefaultWidget") public let widgetBuilder: SendableErasedInstantiator<Int, any Widget>"#, "@Instantiated public let bBuilder: Instantiator<B>"]),
						seamFixtureType(named: "B", declarations: ["@Forwarded public let tag: Tag", "@Instantiated public let aBuilder: Instantiator<A>"]),
						seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated public let aBuilder: Instantiator<A>"]),
					],
					app: [
						SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: ["@Forwarded public let id: Int", "@Received(onlyIfAvailable: true) public let tag: Tag?"]),
						seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let tag: Tag", "@Instantiated public let hub: Hub"]),
					],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsValueBoundOutsideSendableFunction_whenSendableInstantiatorTangleBuildsTypeAgainBeneathTypeThatDeclaresValue() async {
		// The tangle of the graph fuzzer's seed 605 through a `SendableInstantiator`: the `T` that `C` builds again reads
		// `C`'s `mark` inline, which `C` declares outside the `@Sendable` function that builds that `T`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `mark: Mark?`, which `C` declares outside the `@Sendable` function that builds `tBuilder: SendableInstantiator<T>`, and the scope SafeDI hands the builder for `T`’s `api: any Api` (case `T_Scope.api` of `apiSendableBuilder`) carries only what that function binds. Instantiate `mark` outside `Hub` and declare `@Received let mark: Mark` on `Hub`, so the builder’s caller reads its own, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["C.swift"]):8:5: note: `C` declares `mark: Mark` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: SafeDIToolSeamBuilderParameterTests.modules(
					feature: [
						"public protocol Api {}",
						seamFixtureType(named: "Mark", declarations: []),
						seamFixtureType(named: "MarkReader", declarations: ["@Received(onlyIfAvailable: true) public let mark: Mark?"]),
						seamFixtureType(named: "T", declarations: ["@Instantiated public let reader: MarkReader", "@Instantiated public let cBuilder: Instantiator<C>", "@Instantiated public let api: any Api"]),
						seamFixtureType(named: "C", declarations: ["@Instantiated public let mark: Mark", "@Instantiated public let tBuilder: SendableInstantiator<T>"]),
						seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated public let tBuilder: SendableInstantiator<T>", "@Instantiated public let cBuilder: Instantiator<C>"]),
					],
					app: [
						SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: ["@Received(onlyIfAvailable: true) public let mark: Mark?"]),
						seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let hub: Hub"]),
					],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsReceiveOnPassingSeam_whenPassedUpSendablePlaceReadsValueThePassingSeamInstantiates() async {
		// `Mid` instantiates `tag` and calls `Hub`, whose place a `@Sendable` function builds, and passes the builder up to
		// `Root`. The place is handed only what that function binds, so receiving `tag` on `Hub` would not help: `Mid` must
		// receive it, so `Root`'s fill reads its own, which inline is the same value.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LiveApi.swift"]):10:5: error: `LiveApi` receives `tag: Tag?`, which `Mid` builds where it calls `Hub`, but `Mid` passes the builder for `A`'s `api: any Api` (case `A_Scope.api` of `apiSendableBuilder`) on from its own caller, which cannot hand it `Mid`'s values. Instantiate `tag` outside `Mid` and declare `@Received let tag: Tag` on `Mid`, so the builder’s caller reads its own, or declare an @Instantiable type that fulfills `Api` in module `Middle` or a module it lists among its SafeDI dependencies, so `Mid` fills the builder itself.
			\(fixtures["Middle"]!["Mid.swift"]):10:5: note: `Mid` declares `tag: Tag` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.passingUpModules(midDeclarations: ["@Instantiated public let tag: Tag"]),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillReadsCallersValue_whenSeamThatPassesSendablePlaceUpReceivesTheValue() async throws {
		// As above, with the remedy followed: `Mid` receives `tag`, so `Root`'s fill reads `Root`'s `tag`, which inline is
		// `Hub`'s too.
		let modules = Self.passingUpModules(midDeclarations: ["@Received public let tag: Tag"])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Middle"]?.generatedFiles["Middle.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Mid {
		    @frozen public enum SafeDISendableScope_Api {
		        case hub_Sendable(Hub.SafeDISendableScope_Api)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_tag tag: Tag, __safeDI_apiSendableBuilder: @escaping @Sendable (SafeDISendableScope_Api) -> any Api) {
		        func __safeDI_hub() -> Hub {
		            _ = Hub.__safeDI_Hub_8A02327A64DD342F.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Hub(__safeDI_tag: tag, __safeDI_apiSendableBuilder: { __safeDI_apiSendableBuilder(.hub_Sendable($0)) })
		        }
		        let hub: Hub = __safeDI_hub()
		        self.init(tag: tag, hub: hub)
		    }
		}

		extension Mid {
		    public enum __safeDI_Mid_ED297296080C8B89 {}
		}
		""")
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Middle)
		import Middle
		#endif

		extension Root {
		    public init() {
		        let tag = Tag()
		        func __safeDI_mid() -> Mid {
		            _ = Mid.__safeDI_Mid_ED297296080C8B89.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            @Sendable func __safeDI_apiSendableBuilder_Mid(_ scope: Mid.SafeDISendableScope_Api) -> any Api {
		                switch scope {
		                case let .hub_Sendable(scope): return __safeDI_apiSendableBuilder_Hub(scope)
		                }
		            }
		            @Sendable func __safeDI_apiSendableBuilder_Hub(_ scope: Hub.SafeDISendableScope_Api) -> any Api {
		                switch scope {
		                case let .aBuilder(scope): return __safeDI_apiBuilder_Hub_A_Scope(scope)
		                }
		            }
		            @Sendable func __safeDI_apiBuilder_Hub_A_Scope(_ scope: Hub.SafeDIScope_Api.A_Scope) -> any Api {
		                switch scope {
		                case .api:
		                    let api: any Api = LiveApi(tag: tag)
		                    return api
		                }
		            }
		            return Mid(__safeDI_tag: tag, __safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_Mid)
		        }
		        let mid: Mid = __safeDI_mid()
		        self.init(tag: tag, mid: mid)
		    }
		}
		""")
		guard compileVerificationIsEnabled else { return }
		let inlineModules = Self.passingUpModules(midDeclarations: ["@Received public let tag: Tag"], fulfillerInFeature: true)
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inlineModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		try await expectDifferentialValuesAgree(
			feature: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: output, modules: modules),
			knownRight: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: inlineOutput, modules: inlineModules),
			probes: [DifferentialValueProbe(#"{ () -> [String] in let root = Root(); return [root.mid.hub.tag, root.mid.hub.aBuilder.instantiate().api].map { "\($0)" } }()"#)],
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsValueBoundOutsideSendableWrapper_whenPlaceHeldInWrapperReadsValueItsOwnerForwards() async {
		// `Shell` forwards `title` and holds the place in a `Sendable` wrapper, whose function binds nothing, so no forwarded
		// property can carry `title` into it.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["DefaultWidget.swift"]):11:5: error: `DefaultWidget` receives `title: String?`, which `Shell` forwards outside the `@Sendable` function that builds `widgetBuilder: SendableErasedInstantiator<Int, any Widget>`, and the scope SafeDI hands the builder for `Shell`’s `widgetBuilder: SendableErasedInstantiator<Int, any Widget>` (case `Shell_Scope.widgetBuilder` of `defaultWidgetSendableBuilder`) carries only what that function binds. Declare an @Instantiable type that fulfills `DefaultWidget` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["Shell.swift"]):8:5: note: `Shell` declares `title: String` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.wrapperModules(shell: ["@Forwarded public let title: String"], widgetReads: "@Received(onlyIfAvailable: true) public let title: String?", host: ["@Instantiated public let shellBuilder: Instantiator<Shell>"]),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsValueBoundOutsideSendableWrapper_whenPlaceHeldInWrapperReadsValueItsOwnerInstantiates() async {
		// `Shell` instantiates `part` and holds the place in a `Sendable` wrapper: the seam's caller reads its own only where
		// `Host` receives it.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["DefaultWidget.swift"]):11:5: error: `DefaultWidget` receives `part: Part`, which `Shell` declares outside the `@Sendable` function that builds `widgetBuilder: SendableErasedInstantiator<Int, any Widget>`, and the scope SafeDI hands the builder for `Shell`’s `widgetBuilder: SendableErasedInstantiator<Int, any Widget>` (case `Shell_Scope.widgetBuilder` of `defaultWidgetSendableBuilder`) carries only what that function binds. Instantiate `part` outside `Host` and declare `@Received let part: Part` on `Host`, so the builder’s caller reads its own, or declare an @Instantiable type that fulfills `DefaultWidget` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["Shell.swift"]):8:5: note: `Shell` declares `part: Part` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.wrapperModules(shell: ["@Instantiated public let part: Part"], widgetReads: "@Received public let part: Part", host: ["@Instantiated public let shell: Shell"]),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsValueBoundOutsideSendableFunction_whenFillReadsValueTheOuterOfTwoSendableFunctionsForwards() async {
		// `B` is built in a `@Sendable` function inside the one that builds `A`: the place is handed only what the inner
		// function binds, so `A`'s `name` is outside it.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `name: String?`, which `A` forwards outside the `@Sendable` function that builds `bBuilder: SendableInstantiator<B>`, and the scope SafeDI hands the builder for `B`’s `api: any Api` (case `B_Scope.api` of `apiSendableBuilder`) carries only what that function binds. Declare `@Forwarded let name: String` on `B` too, so that function binds it, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["A.swift"]):8:5: note: `A` declares `name: String` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: SafeDIToolSeamBuilderParameterTests.modules(
					feature: [
						"public protocol Api {}",
						seamFixtureType(named: "A", declarations: ["@Forwarded public let name: String", "@Instantiated public let bBuilder: SendableInstantiator<B>"]),
						seamFixtureType(named: "B", declarations: ["@Forwarded public let count: Int", "@Instantiated public let api: any Api"]),
						seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated public let aBuilder: SendableInstantiator<A>"]),
					],
					app: [
						SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: ["@Received(onlyIfAvailable: true) public let name: String?"]),
						seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let hub: Hub"]),
					],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesSendableNestedEnumApart_whenWrapperForwardsTypeOfItsName() async throws {
		// `Shell`'s wrapper forwards a `Shell_Scope`, which the `@Sendable` enum's case spells inside the root enum, so the
		// nested enum for `Shell` takes `_` rather than shadow it.
		try await expectSeam(
			feature: [
				"public protocol Widget: Sendable {}",
				"public struct Shell_Scope: Sendable {\n    public init(id: Int) { self.id = id }\n    public let id: Int\n}",
				seamFixtureType(named: "Shell", declarations: [#"@Instantiated(fulfilledByType: "DefaultWidget") public let widgetBuilder: SendableErasedInstantiator<Shell_Scope, any Widget>"#]),
				seamFixtureType(named: "Host", isSeam: true, declarations: ["@Instantiated public let shell: Shell"]),
			],
			fulfillers: [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: ["@Forwarded public let scope: Shell_Scope"]),
			],
			root: seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let host: Host"]),
			probes: [
				DifferentialValueProbe("Root().host.shell.widgetBuilder.instantiate(Shell_Scope(id: 7))"),
			],
			expectedFeature: """
			extension Host {
			    @frozen public enum SafeDISendableScope_DefaultWidget {
			        case shell_Sendable(SafeDISendableScope_DefaultWidget.Shell_Scope_)

			        @frozen public enum Shell_Scope_ {
			            case widgetBuilder(Shell_Scope)
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_defaultWidgetSendableBuilder: @escaping @Sendable (SafeDISendableScope_DefaultWidget) -> any Widget) {
			        func __safeDI_shell() -> Shell {
			            let widgetBuilder = SendableErasedInstantiator<Shell_Scope, any Widget> {
			                __safeDI_defaultWidgetSendableBuilder(.shell_Sendable(.widgetBuilder($0)))
			            }
			            return Shell(widgetBuilder: widgetBuilder)
			        }
			        let shell: Shell = __safeDI_shell()
			        self.init(shell: shell)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_7209700C34D575D7 {}
			}
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_7209700C34D575D7.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            @Sendable func __safeDI_defaultWidgetSendableBuilder_Host(_ scope: Host.SafeDISendableScope_DefaultWidget) -> any Widget {
			                switch scope {
			                case let .shell_Sendable(scope): return __safeDI_defaultWidgetSendableBuilder_Host_Shell_Scope_(scope)
			                }
			            }
			            @Sendable func __safeDI_defaultWidgetSendableBuilder_Host_Shell_Scope_(_ scope: Host.SafeDISendableScope_DefaultWidget.Shell_Scope_) -> any Widget {
			                switch scope {
			                case let .widgetBuilder(__safeDI_forwarded):
			                    @Sendable func __safeDI_widgetBuilder(scope: Shell_Scope) -> DefaultWidget {
			                        DefaultWidget(scope: scope)
			                    }
			                    return __safeDI_widgetBuilder(scope: __safeDI_forwarded)
			                }
			            }
			            return Host(__safeDI_defaultWidgetSendableBuilder: __safeDI_defaultWidgetSendableBuilder_Host)
			        }
			        let host: Host = __safeDI_host()
			        self.init(host: host)
			    }
			}
			""",
		)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private static let tag = """
	@Instantiable
	public struct Tag: Instantiable, Sendable, CustomStringConvertible {
	    public init() { value = "root" }
	    public init(value: String) { self.value = value }
	    public let value: String
	    public var description: String { value }
	}
	"""

	/// `Api`, `Tag`, `TagReader`, `A`, `B`, `C` and `Hub`: `A`'s `reader` requires `tag`, which `B` forwards before it builds
	/// `A` again, so the function that builds `A` takes `tag`; `A` builds `C`, with `c`'s declarations, in a `@Sendable`
	/// function, and `C` holds the hole `api`.
	private static func cycleThroughSendableFunction(c: [String]) -> [String] {
		[
			"public protocol Api {}",
			tag,
			seamFixtureType(named: "TagReader", declarations: ["@Received public let tag: Tag"]),
			seamFixtureType(named: "A", declarations: ["@Instantiated public let reader: TagReader", "@Instantiated public let cBuilder: SendableInstantiator<C>", "@Instantiated public let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "B", declarations: ["@Forwarded public let tag: Tag", "@Instantiated public let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "C", declarations: c + ["@Instantiated public let api: any Api"]),
			seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated public let aBuilder: Instantiator<A>"]),
		]
	}

	/// `Hub`, a seam of `Feature` that receives `tag` and holds the place `api` in a `@Sendable` function; `Mid`, a seam of
	/// `Middle` with `midDeclarations`, which calls `Hub` and passes its builder up; and `App`'s root, which holds a `tag` of
	/// its own, and `LiveApi`, which reads `tag` only if available and fulfills `Api` in `App`, or in `Feature` where
	/// `fulfillerInFeature`.
	private static func passingUpModules(midDeclarations: [String], fulfillerInFeature: Bool = false) -> [ModuleFixture] {
		let liveApi = SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: ["@Received(onlyIfAvailable: true) public let tag: Tag?"])
		let feature = [
			"public protocol Api {}",
			tag,
			seamFixtureType(named: "A", declarations: ["@Instantiated public let api: any Api"]),
			seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Received public let tag: Tag", "@Instantiated public let aBuilder: SendableInstantiator<A>"]),
		]
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let tag: Tag", "@Instantiated public let mid: Mid"])
		return [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature + (fulfillerInFeature ? [liveApi] : [])),
			ModuleFixture(name: "Middle", packageName: "Other", swiftFileContent: ["import Feature\n\n" + seamFixtureType(named: "Mid", isSeam: true, declarations: midDeclarations + ["@Instantiated public let hub: Hub"])], dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: (fulfillerInFeature ? [root] : [liveApi, root]).map { "import Feature\nimport Middle\n\n" + $0 }, dependencies: ["Feature", "Middle"]),
		]
	}

	/// `Widget`, `Part`, `Shell`, with `shell`'s declarations and the place `widgetBuilder` held in a `Sendable` wrapper,
	/// and `Host`, a seam with `host`'s declarations; `App`'s `DefaultWidget`, which reads `widgetReads`, and its root.
	private static func wrapperModules(shell: [String], widgetReads: String, host: [String]) -> [ModuleFixture] {
		SafeDIToolSeamBuilderParameterTests.modules(
			feature: [
				"public protocol Widget: Sendable {}",
				seamFixtureType(named: "Part", isFinalClass: true, declarations: [], conformances: ", Sendable"),
				seamFixtureType(named: "Shell", declarations: shell + [#"@Instantiated(fulfilledByType: "DefaultWidget") public let widgetBuilder: SendableErasedInstantiator<Int, any Widget>"#]),
				seamFixtureType(named: "Host", isSeam: true, declarations: host),
			],
			app: [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: ["@Forwarded public let id: Int", widgetReads]),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let host: Host"]),
			],
		)
	}

	/// `Feature`, where the seam `Home` instantiates `appService` and `mid`, whose `screenBuilder` builds `Screen`, which holds
	/// a place of `Api`, in a `@Sendable` function. `Mid` declares `service` as `midService` says.
	private static func innerAliasFeature(midService: String) -> [String] {
		[
			"public protocol Api: Sendable {}",
			seamFixtureType(named: "Service", isFinalClass: true, declarations: [], conformances: ", Sendable"),
			seamFixtureType(named: "Screen", declarations: ["@Instantiated public let api: any Api"], conformances: ", Sendable"),
			seamFixtureType(named: "Mid", declarations: [midService, "@Instantiated public let screenBuilder: SendableInstantiator<Screen>"], conformances: ", Sendable"),
			seamFixtureType(named: "Home", isSeam: true, declarations: ["@Instantiated public let appService: Service", "@Instantiated public let mid: Mid"], conformances: ", Sendable"),
		]
	}

	private static let moduleInfoComment = "If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes."

	/// Expects `feature`'s seam and `App`'s fill of it, the fulfillers and the root in `App`, to generate `expectedFeature`
	/// and `expectedApp`, and the values `probes` read to equal those of the same graph built with every fulfiller in
	/// `Feature`, where no hole is left.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectSeam(
		feature: [String],
		fulfillers: [String],
		root: String,
		probes: [DifferentialValueProbe],
		expectedFeature: String,
		expectedApp: String,
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: fulfillers + [root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles["Feature.swift"] == generatedFileHeader + expectedFeature, sourceLocation: sourceLocation)
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + expectedApp, sourceLocation: sourceLocation)
		guard compileVerificationIsEnabled else { return }
		let visibleModules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature + fulfillers, app: [root])
		let visibleOutput = try await executeSafeDIToolMultiModuleTest(modules: visibleModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		try await expectDifferentialValuesAgree(
			feature: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: output, modules: modules),
			knownRight: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: visibleOutput, modules: visibleModules),
			probes: probes,
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}
}
