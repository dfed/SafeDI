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
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_WidgetCarrier<__safeDI_Built> {
			        public let shell: __safeDI_WidgetCarrier_Shell<__safeDI_Built>

			        public init(shell: __safeDI_WidgetCarrier_Shell<__safeDI_Built>) {
			            self.shell = shell
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(shell: .init(__safeDI_noScope: __safeDI_builder))
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_WidgetCarrier_Shell<__safeDI_Built> {
			        public let widget: (Part, SendableInstantiator<Panel>) -> __safeDI_Built

			        public init(widget: @escaping (Part, SendableInstantiator<Panel>) -> __safeDI_Built) {
			            self.widget = widget
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(widget: { _, _ in __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_WidgetCarrier_Panel<__safeDI_Built> {
			        public let widget: (String, Part) -> __safeDI_Built

			        public init(widget: @escaping (String, Part) -> __safeDI_Built) {
			            self.widget = widget
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(widget: { _, _ in __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_WidgetSendableCarrier<__safeDI_Built>: Sendable {
			        public let shell_Sendable: __safeDI_WidgetSendableCarrier_Shell<__safeDI_Built>

			        public init(shell_Sendable: __safeDI_WidgetSendableCarrier_Shell<__safeDI_Built>) {
			            self.shell_Sendable = shell_Sendable
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			            self.init(shell_Sendable: .init(__safeDI_noScope: __safeDI_builder))
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_WidgetSendableCarrier_Shell<__safeDI_Built>: Sendable {
			        public let panelBuilder: @Sendable () -> __safeDI_WidgetCarrier_Panel<__safeDI_Built>

			        public init(panelBuilder: @escaping @Sendable () -> __safeDI_WidgetCarrier_Panel<__safeDI_Built>) {
			            self.panelBuilder = panelBuilder
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			            self.init(panelBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_widgetBuilder: __safeDI_WidgetCarrier<any Widget>, __safeDI_widgetSendableBuilder: __safeDI_WidgetSendableCarrier<any Widget>) {
			        let __safeDI_widgetBuilder_shell = __safeDI_widgetBuilder.shell
			        let __safeDI_widgetSendableBuilder_shell_Sendable = __safeDI_widgetSendableBuilder.shell_Sendable
			        @inline(never) @Sendable nonisolated func __safeDI_panelBuilder(name: String) -> Panel {
			            let __safeDI_widgetSendableBuilder_panelBuilder = __safeDI_widgetSendableBuilder_shell_Sendable.panelBuilder()
			            let part = Part()
			            let widget: any Widget = __safeDI_widgetSendableBuilder_panelBuilder.widget(name, part)
			            return Panel(name: name, part: part, widget: widget)
			        }
			        @inline(never) func __safeDI_shell() -> Shell {
			            let part = Part()
			            let panelBuilder = SendableInstantiator<Panel> {
			                __safeDI_panelBuilder(name: $0)
			            }
			            let widget: any Widget = __safeDI_widgetBuilder_shell.widget(part, panelBuilder)
			            return Shell(part: part, panelBuilder: panelBuilder, widget: widget)
			        }
			        let shell: Shell = __safeDI_shell()
			        self.init(shell: shell)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_1054A2F0CEAA6AB2 {}
			}
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        @Sendable nonisolated func __safeDI_widgetSendableBuilder_Host() -> Host.__safeDI_WidgetSendableCarrier<any Widget> {
			            .init(shell_Sendable: __safeDI_widgetSendableBuilder_Host_Shell_Scope())
			        }
			        @Sendable nonisolated func __safeDI_widgetSendableBuilder_Host_Shell_Scope() -> Host.__safeDI_WidgetSendableCarrier_Shell<any Widget> {
			            .init(panelBuilder: { __safeDI_widgetBuilder_Host_Panel_Scope() })
			        }
			        @Sendable nonisolated func __safeDI_widgetBuilder_Host_Panel_Scope() -> Host.__safeDI_WidgetCarrier_Panel<any Widget> {
			            .init(widget: { scope_name, scope_part in
			                let name = scope_name
			                let part = scope_part
			                let widget: any Widget = DefaultWidget(part: part, name: name)
			                return widget
			            })
			        }
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_1054A2F0CEAA6AB2.self // \(Self.moduleInfoComment)
			            func __safeDI_widgetBuilder_Host() -> Host.__safeDI_WidgetCarrier<any Widget> {
			                .init(shell: __safeDI_widgetBuilder_Host_Shell_Scope())
			            }
			            func __safeDI_widgetBuilder_Host_Shell_Scope() -> Host.__safeDI_WidgetCarrier_Shell<any Widget> {
			                .init(widget: { scope_part, scope_panelBuilder in
			                    let part = scope_part
			                    let widget: any Widget = DefaultWidget(part: part, name: nil)
			                    return widget
			                })
			            }
			            return Host(__safeDI_widgetBuilder: __safeDI_widgetBuilder_Host(), __safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Host())
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
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_DefaultWidget_WidgetSendableCarrier<__safeDI_Built>: Sendable {
			        public let shell_Sendable: __safeDI_DefaultWidget_WidgetSendableCarrier_Shell<__safeDI_Built>

			        public init(shell_Sendable: __safeDI_DefaultWidget_WidgetSendableCarrier_Shell<__safeDI_Built>) {
			            self.shell_Sendable = shell_Sendable
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<Int, __safeDI_Built>.Builder) {
			            self.init(shell_Sendable: .init(__safeDI_noScope: __safeDI_builder))
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_DefaultWidget_WidgetSendableCarrier_Shell<__safeDI_Built>: Sendable {
			        public let widgetBuilder: @Sendable () -> SendableErasedInstantiator<Int, __safeDI_Built>.Builder

			        public init(widgetBuilder: @escaping @Sendable () -> SendableErasedInstantiator<Int, __safeDI_Built>.Builder) {
			            self.widgetBuilder = widgetBuilder
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<Int, __safeDI_Built>.Builder) {
			            self.init(widgetBuilder: { __safeDI_builder })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_defaultWidget_WidgetSendableBuilder: __safeDI_DefaultWidget_WidgetSendableCarrier<any Widget>) {
			        let __safeDI_defaultWidget_WidgetSendableBuilder_shell_Sendable = __safeDI_defaultWidget_WidgetSendableBuilder.shell_Sendable
			        @inline(never) func __safeDI_shell() -> Shell {
			            let widgetBuilder = SendableErasedInstantiator<Int, any Widget>(__safeDI_defaultWidget_WidgetSendableBuilder_shell_Sendable.widgetBuilder())
			            return Shell(widgetBuilder: widgetBuilder)
			        }
			        let shell: Shell = __safeDI_shell()
			        self.init(shell: shell)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_00A8B34CF50EF9A9 {}
			}
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        @Sendable nonisolated func __safeDI_defaultWidget_WidgetSendableBuilder_Host_Shell_Scope_widgetBuilder() -> SendableErasedInstantiator<Int, any Widget>.Builder {
			            return __safeDI_fillBody_2766CFCBD48DBBAE()
			        }
			        @Sendable nonisolated func __safeDI_fillBody_2766CFCBD48DBBAE() -> SendableErasedInstantiator<Int, any Widget>.Builder {
			            @Sendable nonisolated func __safeDI_widgetBuilder(id: Int) -> DefaultWidget {
			                DefaultWidget(id: id)
			            }
			            return { forwarded in __safeDI_widgetBuilder(id: forwarded) }
			        }
			        @Sendable nonisolated func __safeDI_defaultWidget_WidgetSendableBuilder_Host() -> Host.__safeDI_DefaultWidget_WidgetSendableCarrier<any Widget> {
			            .init(shell_Sendable: __safeDI_defaultWidget_WidgetSendableBuilder_Host_Shell_Scope())
			        }
			        @Sendable nonisolated func __safeDI_defaultWidget_WidgetSendableBuilder_Host_Shell_Scope() -> Host.__safeDI_DefaultWidget_WidgetSendableCarrier_Shell<any Widget> {
			            .init(widgetBuilder: { __safeDI_defaultWidget_WidgetSendableBuilder_Host_Shell_Scope_widgetBuilder() })
			        }
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_00A8B34CF50EF9A9.self // \(Self.moduleInfoComment)
			            return Host(__safeDI_defaultWidget_WidgetSendableBuilder: __safeDI_defaultWidget_WidgetSendableBuilder_Host())
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
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_WidgetCarrier<__safeDI_Built> {
			        public let shell: __safeDI_WidgetCarrier_Shell<__safeDI_Built>

			        public init(shell: __safeDI_WidgetCarrier_Shell<__safeDI_Built>) {
			            self.shell = shell
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(shell: .init(__safeDI_noScope: __safeDI_builder))
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_WidgetCarrier_Shell<__safeDI_Built> {
			        public let plainPanelBuilder: (SendableInstantiator<Panel>) -> __safeDI_WidgetCarrier_Panel<__safeDI_Built>

			        public init(plainPanelBuilder: @escaping (SendableInstantiator<Panel>) -> __safeDI_WidgetCarrier_Panel<__safeDI_Built>) {
			            self.plainPanelBuilder = plainPanelBuilder
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(plainPanelBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_WidgetCarrier_Panel<__safeDI_Built> {
			        public let widget: (String) -> __safeDI_Built

			        public init(widget: @escaping (String) -> __safeDI_Built) {
			            self.widget = widget
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(widget: { _ in __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_WidgetSendableCarrier<__safeDI_Built>: Sendable {
			        public let shell_Sendable: __safeDI_WidgetSendableCarrier_Shell<__safeDI_Built>

			        public init(shell_Sendable: __safeDI_WidgetSendableCarrier_Shell<__safeDI_Built>) {
			            self.shell_Sendable = shell_Sendable
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			            self.init(shell_Sendable: .init(__safeDI_noScope: __safeDI_builder))
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_WidgetSendableCarrier_Shell<__safeDI_Built>: Sendable {
			        public let panelBuilder: @Sendable () -> __safeDI_WidgetCarrier_Panel<__safeDI_Built>

			        public init(panelBuilder: @escaping @Sendable () -> __safeDI_WidgetCarrier_Panel<__safeDI_Built>) {
			            self.panelBuilder = panelBuilder
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			            self.init(panelBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_widgetBuilder: __safeDI_WidgetCarrier<any Widget>, __safeDI_widgetSendableBuilder: __safeDI_WidgetSendableCarrier<any Widget>) {
			        let __safeDI_widgetBuilder_shell = __safeDI_widgetBuilder.shell
			        let __safeDI_widgetSendableBuilder_shell_Sendable = __safeDI_widgetSendableBuilder.shell_Sendable
			        @inline(never) @Sendable nonisolated func __safeDI_panelBuilder(name: String) -> Panel {
			            let __safeDI_widgetSendableBuilder_panelBuilder = __safeDI_widgetSendableBuilder_shell_Sendable.panelBuilder()
			            let widget: any Widget = __safeDI_widgetSendableBuilder_panelBuilder.widget(name)
			            return Panel(name: name, widget: widget)
			        }
			        @inline(never) func __safeDI_plainPanelBuilder(name: String, __safeDI_widgetBuilder_plainPanelBuilder: __safeDI_WidgetCarrier_Panel<any Widget>) -> Panel {
			            let widget: any Widget = __safeDI_widgetBuilder_plainPanelBuilder.widget(name)
			            return Panel(name: name, widget: widget)
			        }
			        @inline(never) func __safeDI_shell() -> Shell {
			            let panelBuilder = SendableInstantiator<Panel> {
			                __safeDI_panelBuilder(name: $0)
			            }
			            let __safeDI_widgetBuilder_plainPanelBuilder = __safeDI_widgetBuilder_shell.plainPanelBuilder(panelBuilder)
			            let plainPanelBuilder = Instantiator<Panel> {
			                __safeDI_plainPanelBuilder(name: $0, __safeDI_widgetBuilder_plainPanelBuilder: __safeDI_widgetBuilder_plainPanelBuilder)
			            }
			            return Shell(panelBuilder: panelBuilder, plainPanelBuilder: plainPanelBuilder)
			        }
			        let shell: Shell = __safeDI_shell()
			        self.init(shell: shell)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_8DD5BD7AB71038C2 {}
			}
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_widgetBuilder_Host() -> Host.__safeDI_WidgetCarrier<any Widget> {
			            .init(shell: __safeDI_widgetBuilder_Host_Shell_Scope())
			        }
			        func __safeDI_widgetBuilder_Host_Shell_Scope() -> Host.__safeDI_WidgetCarrier_Shell<any Widget> {
			            .init(plainPanelBuilder: { values_panelBuilder in __safeDI_widgetBuilder_Host_Panel_Scope() })
			        }
			        @Sendable nonisolated func __safeDI_widgetBuilder_Host_Panel_Scope() -> Host.__safeDI_WidgetCarrier_Panel<any Widget> {
			            .init(widget: { scope_name in
			                let name = scope_name
			                let widget: any Widget = DefaultWidget(name: name)
			                return widget
			            })
			        }
			        @Sendable nonisolated func __safeDI_widgetSendableBuilder_Host() -> Host.__safeDI_WidgetSendableCarrier<any Widget> {
			            .init(shell_Sendable: __safeDI_widgetSendableBuilder_Host_Shell_Scope())
			        }
			        @Sendable nonisolated func __safeDI_widgetSendableBuilder_Host_Shell_Scope() -> Host.__safeDI_WidgetSendableCarrier_Shell<any Widget> {
			            .init(panelBuilder: { __safeDI_widgetBuilder_Host_Panel_Scope() })
			        }
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_8DD5BD7AB71038C2.self // \(Self.moduleInfoComment)
			            return Host(__safeDI_widgetBuilder: __safeDI_widgetBuilder_Host(), __safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Host())
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
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_WidgetCarrier_Panel<__safeDI_Built> {
			        public let widget: (String) -> __safeDI_Built

			        public init(widget: @escaping (String) -> __safeDI_Built) {
			            self.widget = widget
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(widget: { _ in __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_WidgetSendableCarrier<__safeDI_Built>: Sendable {
			        public let panelBuilder: @Sendable () -> __safeDI_WidgetCarrier_Panel<__safeDI_Built>

			        public init(panelBuilder: @escaping @Sendable () -> __safeDI_WidgetCarrier_Panel<__safeDI_Built>) {
			            self.panelBuilder = panelBuilder
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			            self.init(panelBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_theme theme: Theme, __safeDI_widgetSendableBuilder: __safeDI_WidgetSendableCarrier<any Widget>) {
			        @inline(never) @Sendable nonisolated func __safeDI_panelBuilder(name: String) -> Panel {
			            let __safeDI_widgetSendableBuilder_panelBuilder = __safeDI_widgetSendableBuilder.panelBuilder()
			            let widget: any Widget = __safeDI_widgetSendableBuilder_panelBuilder.widget(name)
			            return Panel(name: name, widget: widget)
			        }
			        let panelBuilder = SendableInstantiator<Panel> {
			            __safeDI_panelBuilder(name: $0)
			        }
			        self.init(theme: theme, panelBuilder: panelBuilder)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_A72EE49399699E0E {}
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
			            _ = Host.__safeDI_Host_A72EE49399699E0E.self // \(Self.moduleInfoComment)
			            @Sendable nonisolated func __safeDI_widgetSendableBuilder_Host() -> Host.__safeDI_WidgetSendableCarrier<any Widget> {
			                .init(panelBuilder: { __safeDI_widgetBuilder_Host_Panel_Scope() })
			            }
			            @Sendable nonisolated func __safeDI_widgetBuilder_Host_Panel_Scope() -> Host.__safeDI_WidgetCarrier_Panel<any Widget> {
			                .init(widget: { scope_name in
			                    let widget: any Widget = DefaultWidget(theme: theme)
			                    return widget
			                })
			            }
			            return Host(__safeDI_theme: theme, __safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Host())
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
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_WidgetCarrier_Panel<__safeDI_Built> {
			        public let widget: (String) -> __safeDI_Built

			        public init(widget: @escaping (String) -> __safeDI_Built) {
			            self.widget = widget
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(widget: { _ in __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_WidgetSendableCarrier<__safeDI_Built>: Sendable {
			        public let shell_Sendable: __safeDI_WidgetSendableCarrier_Shell<__safeDI_Built>

			        public init(shell_Sendable: __safeDI_WidgetSendableCarrier_Shell<__safeDI_Built>) {
			            self.shell_Sendable = shell_Sendable
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			            self.init(shell_Sendable: .init(__safeDI_noScope: __safeDI_builder))
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_WidgetSendableCarrier_Shell<__safeDI_Built>: Sendable {
			        public let screen_Sendable_: __safeDI_WidgetSendableCarrier_Screen<__safeDI_Built>
			        public let screen_Sendable: @Sendable () -> __safeDI_WidgetCarrier_Panel<__safeDI_Built>

			        public init(screen_Sendable_: __safeDI_WidgetSendableCarrier_Screen<__safeDI_Built>, screen_Sendable: @escaping @Sendable () -> __safeDI_WidgetCarrier_Panel<__safeDI_Built>) {
			            self.screen_Sendable_ = screen_Sendable_
			            self.screen_Sendable = screen_Sendable
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			            self.init(screen_Sendable_: .init(__safeDI_noScope: __safeDI_builder), screen_Sendable: { .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_WidgetSendableCarrier_Screen<__safeDI_Built>: Sendable {
			        public let panelBuilder: @Sendable () -> __safeDI_WidgetCarrier_Panel<__safeDI_Built>

			        public init(panelBuilder: @escaping @Sendable () -> __safeDI_WidgetCarrier_Panel<__safeDI_Built>) {
			            self.panelBuilder = panelBuilder
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			            self.init(panelBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_widgetSendableBuilder: __safeDI_WidgetSendableCarrier<any Widget>) {
			        let __safeDI_widgetSendableBuilder_shell_Sendable = __safeDI_widgetSendableBuilder.shell_Sendable
			        @inline(never) func __safeDI_screen(__safeDI_widgetSendableBuilder_screen_Sendable_: __safeDI_WidgetSendableCarrier_Screen<any Widget>) -> Screen {
			            let panelBuilder = SendableInstantiator<Panel> {
			                __safeDI_panelBuilder(name: $0, __safeDI_widgetSendableBuilder_screen_Sendable_: __safeDI_widgetSendableBuilder_screen_Sendable_)
			            }
			            return Screen(panelBuilder: panelBuilder)
			        }
			        @inline(never) @Sendable nonisolated func __safeDI_panelBuilder(name: String, __safeDI_widgetSendableBuilder_screen_Sendable_: __safeDI_WidgetSendableCarrier_Screen<any Widget>) -> Panel {
			            let __safeDI_widgetSendableBuilder_panelBuilder = __safeDI_widgetSendableBuilder_screen_Sendable_.panelBuilder()
			            let widget: any Widget = __safeDI_widgetSendableBuilder_panelBuilder.widget(name)
			            return Panel(name: name, widget: widget)
			        }
			        @inline(never) @Sendable nonisolated func __safeDI_screen_Sendable(name: String) -> Panel {
			            let __safeDI_widgetSendableBuilder_screen_Sendable = __safeDI_widgetSendableBuilder_shell_Sendable.screen_Sendable()
			            let widget: any Widget = __safeDI_widgetSendableBuilder_screen_Sendable.widget(name)
			            return Panel(name: name, widget: widget)
			        }
			        @inline(never) func __safeDI_shell() -> Shell {
			            let __safeDI_widgetSendableBuilder_screen_Sendable_ = __safeDI_widgetSendableBuilder_shell_Sendable.screen_Sendable_
			            let screen: Screen = __safeDI_screen(__safeDI_widgetSendableBuilder_screen_Sendable_: __safeDI_widgetSendableBuilder_screen_Sendable_)
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
			    public enum __safeDI_Host_46E182016EE13C1D {}
			}
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        @Sendable nonisolated func __safeDI_widgetSendableBuilder_Host() -> Host.__safeDI_WidgetSendableCarrier<any Widget> {
			            .init(shell_Sendable: __safeDI_widgetSendableBuilder_Host_Shell_Scope())
			        }
			        @Sendable nonisolated func __safeDI_widgetSendableBuilder_Host_Shell_Scope() -> Host.__safeDI_WidgetSendableCarrier_Shell<any Widget> {
			            .init(screen_Sendable_: __safeDI_widgetSendableBuilder_Host_Screen_Scope(), screen_Sendable: { __safeDI_widgetBuilder_Host_Panel_Scope() })
			        }
			        @Sendable nonisolated func __safeDI_widgetSendableBuilder_Host_Screen_Scope() -> Host.__safeDI_WidgetSendableCarrier_Screen<any Widget> {
			            .init(panelBuilder: { __safeDI_widgetBuilder_Host_Panel_Scope() })
			        }
			        @Sendable nonisolated func __safeDI_widgetBuilder_Host_Panel_Scope() -> Host.__safeDI_WidgetCarrier_Panel<any Widget> {
			            .init(widget: { scope_name in
			                let name = scope_name
			                let widget: any Widget = DefaultWidget(name: name)
			                return widget
			            })
			        }
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_46E182016EE13C1D.self // \(Self.moduleInfoComment)
			            return Host(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Host())
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
			\(fixtures["App"]!["DefaultWidget.swift"]):9:5: error: `DefaultWidget` receives `part: Part`, which `Shell` declares outside the `@Sendable` function that builds `panelBuilder: SendableInstantiator<Panel>`, and SafeDI hands the builder for `Panel`’s `widget: any Widget` (`widget` of `widgetSendableBuilder`) only what that function binds. Declare `@Forwarded let part: Part` on `Panel`, so that function binds it, or declare an @Instantiable type that fulfills `Widget` in module `Feature` or a module it lists among its SafeDI dependencies.
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
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `service: Service`, which `Home` receives as the caller’s `appService` outside the `@Sendable` function that builds `screenBuilder: SendableInstantiator<Screen>`, and SafeDI hands the builder for `Screen`’s `api: any Api` (`api` of `apiSendableBuilder`) only what that function binds. Declare `@Received let service: Service` on `Home` without `fulfilledByDependencyNamed: "appService"`, so the builder’s caller reads its own, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
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
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `service: Service`, which `Mid` receives as `appService` outside the `@Sendable` function that builds `screenBuilder: SendableInstantiator<Screen>`, and SafeDI hands the builder for `Screen`’s `api: any Api` (`api` of `apiSendableBuilder`) only what that function binds. Declare `@Received let service: Service` on `Mid` without `fulfilledByDependencyNamed: "appService"`, and instantiate `service` outside `Home`, so the builder’s caller reads its own, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
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
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiCarrier_Screen<__safeDI_Built> {
			        public let api: () -> __safeDI_Built

			        public init(api: @escaping () -> __safeDI_Built) {
			            self.api = api
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(api: { __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiSendableCarrier<__safeDI_Built>: Sendable {
			        public let mid_Sendable: __safeDI_ApiSendableCarrier_Mid<__safeDI_Built>

			        public init(mid_Sendable: __safeDI_ApiSendableCarrier_Mid<__safeDI_Built>) {
			            self.mid_Sendable = mid_Sendable
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			            self.init(mid_Sendable: .init(__safeDI_noScope: __safeDI_builder))
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiSendableCarrier_Mid<__safeDI_Built>: Sendable {
			        public let screenBuilder: @Sendable () -> __safeDI_ApiCarrier_Screen<__safeDI_Built>

			        public init(screenBuilder: @escaping @Sendable () -> __safeDI_ApiCarrier_Screen<__safeDI_Built>) {
			            self.screenBuilder = screenBuilder
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			            self.init(screenBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_service: @autoclosure @escaping () -> Service, __safeDI_apiSendableBuilder: __safeDI_ApiSendableCarrier<any Api>) {
			        let service = LazilyInstantiated<Service>(__safeDI_service)
			        let appService = Service()
			        let __safeDI_apiSendableBuilder_mid_Sendable = __safeDI_apiSendableBuilder.mid_Sendable
			        @inline(never) @Sendable nonisolated func __safeDI_screenBuilder() -> Screen {
			            let __safeDI_apiSendableBuilder_screenBuilder = __safeDI_apiSendableBuilder_mid_Sendable.screenBuilder()
			            let api: any Api = __safeDI_apiSendableBuilder_screenBuilder.api()
			            return Screen(api: api)
			        }
			        @inline(never) func __safeDI_mid() -> Mid {
			            let screenBuilder = SendableInstantiator<Screen>(__safeDI_screenBuilder)
			            return Mid(service: service.instance, screenBuilder: screenBuilder)
			        }
			        let mid: Mid = __safeDI_mid()
			        self.init(appService: appService, mid: mid)
			    }
			}

			extension Home {
			    public enum __safeDI_Home_D5E84A21E646C521 {}
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
			            _ = Home.__safeDI_Home_D5E84A21E646C521.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            @Sendable nonisolated func __safeDI_apiSendableBuilder_Home() -> Home.__safeDI_ApiSendableCarrier<any Api> {
			                .init(mid_Sendable: __safeDI_apiSendableBuilder_Home_Mid_Scope())
			            }
			            @Sendable nonisolated func __safeDI_apiSendableBuilder_Home_Mid_Scope() -> Home.__safeDI_ApiSendableCarrier_Mid<any Api> {
			                .init(screenBuilder: { __safeDI_apiBuilder_Home_Screen_Scope() })
			            }
			            @Sendable nonisolated func __safeDI_apiBuilder_Home_Screen_Scope() -> Home.__safeDI_ApiCarrier_Screen<any Api> {
			                .init(api: {
			                    let api: any Api = LiveApi(service: service)
			                    return api
			                })
			            }
			            return Home(__safeDI_service: service, __safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_Home())
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
			\(fixtures["App"]!["DefaultWidget.swift"]):9:5: error: `DefaultWidget` receives `tabName: String?`, which `Tab` forwards outside the `@Sendable` function that builds `detailBuilder: SendableInstantiator<Detail>`, and SafeDI hands the builder for `Detail`’s `widget: any Widget` (`widget` of `widgetSendableBuilder`) only what that function binds. Declare `@Forwarded let tabName: String` on `Detail` too, so that function binds it, or declare an @Instantiable type that fulfills `Widget` in module `Feature` or a module it lists among its SafeDI dependencies.
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
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `tag: Tag?`, which `A`’s builder function takes as a parameter outside the `@Sendable` function that builds `cBuilder: SendableInstantiator<C>`, because a cycle inside `A`’s tree passes it (`B` forwards `tag: Tag`), and SafeDI hands the builder for `C`’s `api: any Api` (`api` of `apiSendableBuilder`) only what that function binds. Declare `@Forwarded let tag: Tag` on `C` too, so that function binds it, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
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
	mutating func generate_namesInstantiatedDeclarationOfSecondCycle_whenItPrecedesForwardedDeclarationOfTypeBetweenInSourceOrder() async {
		// `B` forwards `tag` and builds `A` again; `AStep`, which `B` also builds, instantiates a `tag` of its own and builds
		// `B` again. So two declarations of `tag` are between `A` and the `A` built again, `B`'s and, through `B`'s cycle,
		// `AStep`'s, and the parameter of `A`'s function is traced to the one first in source order: `AStep`'s, instantiated.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `tag: Tag?`, which `A`’s builder function takes as a parameter outside the `@Sendable` function that builds `cBuilder: SendableInstantiator<C>`, because a cycle inside `A`’s tree passes it (`AStep` declares `tag: Tag`), and SafeDI hands the builder for `C`’s `api: any Api` (`api` of `apiSendableBuilder`) only what that function binds. Declare `@Forwarded let tag: Tag` on `C` too, so that function binds it, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["AStep.swift"]):8:5: note: `AStep` declares `tag: Tag` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: SafeDIToolSeamBuilderParameterTests.modules(
					feature: Self.secondCycleThroughSendableFunction(typeBuildingBAgain: "AStep"),
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
	mutating func generate_namesForwardedDeclarationOfTypeBetween_whenItPrecedesInstantiatedDeclarationOfSecondCycleInSourceOrder() async {
		// As above with the type that builds `B` again named `Step`, whose file follows `B`'s: the parameter is traced to
		// `B`'s declaration, forwarded.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `tag: Tag?`, which `A`’s builder function takes as a parameter outside the `@Sendable` function that builds `cBuilder: SendableInstantiator<C>`, because a cycle inside `A`’s tree passes it (`B` forwards `tag: Tag`), and SafeDI hands the builder for `C`’s `api: any Api` (`api` of `apiSendableBuilder`) only what that function binds. Declare `@Forwarded let tag: Tag` on `C` too, so that function binds it, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["B.swift"]):9:5: note: `B` forwards `tag: Tag` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: SafeDIToolSeamBuilderParameterTests.modules(
					feature: Self.secondCycleThroughSendableFunction(typeBuildingBAgain: "Step"),
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
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiCarrier_C<__safeDI_Built> {
			        public let api: (Tag) -> __safeDI_Built

			        public init(api: @escaping (Tag) -> __safeDI_Built) {
			            self.api = api
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(api: { _ in __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiSendableCarrier<__safeDI_Built>: Sendable {
			        public let aBuilder_Sendable: __safeDI_ApiSendableCarrier_A<__safeDI_Built>

			        public init(aBuilder_Sendable: __safeDI_ApiSendableCarrier_A<__safeDI_Built>) {
			            self.aBuilder_Sendable = aBuilder_Sendable
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			            self.init(aBuilder_Sendable: .init(__safeDI_noScope: __safeDI_builder))
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiSendableCarrier_A<__safeDI_Built>: Sendable {
			        public let cBuilder: @Sendable () -> __safeDI_ApiCarrier_C<__safeDI_Built>

			        public init(cBuilder: @escaping @Sendable () -> __safeDI_ApiCarrier_C<__safeDI_Built>) {
			            self.cBuilder = cBuilder
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			            self.init(cBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_tag: @autoclosure @escaping () -> Tag, __safeDI_apiSendableBuilder: __safeDI_ApiSendableCarrier<any Api>) {
			        let tag = LazilyInstantiated<Tag>(__safeDI_tag)
			        let __safeDI_apiSendableBuilder_aBuilder_Sendable = __safeDI_apiSendableBuilder.aBuilder_Sendable
			        @inline(never) func __safeDI_aBuilder(tag: LazilyInstantiated<Tag>) -> A {
			            let reader = TagReader(tag: tag.instance)
			            let bBuilder = Instantiator<B> {
			                __safeDI_bBuilder(tag: $0)
			            }
			            let cBuilder = SendableInstantiator<C> {
			                __safeDI_cBuilder(tag: $0)
			            }
			            return A(reader: reader, cBuilder: cBuilder, bBuilder: bBuilder)
			        }
			        @inline(never) func __safeDI_bBuilder(tag: Tag) -> B {
			            let aBuilder = Instantiator<A> {
			                __safeDI_aBuilder(tag: LazilyInstantiated<Tag> { tag })
			            }
			            return B(tag: tag, aBuilder: aBuilder)
			        }
			        @inline(never) @Sendable nonisolated func __safeDI_cBuilder(tag: Tag) -> C {
			            let __safeDI_apiSendableBuilder_cBuilder = __safeDI_apiSendableBuilder_aBuilder_Sendable.cBuilder()
			            let api: any Api = __safeDI_apiSendableBuilder_cBuilder.api(tag)
			            return C(tag: tag, api: api)
			        }
			        let aBuilder = Instantiator<A> {
			            __safeDI_aBuilder(tag: tag)
			        }
			        self.init(aBuilder: aBuilder)
			    }
			}

			extension Hub {
			    public enum __safeDI_Hub_A09E0102113C11C1 {}
			}
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        @Sendable nonisolated func __safeDI_apiSendableBuilder_Hub() -> Hub.__safeDI_ApiSendableCarrier<any Api> {
			            .init(aBuilder_Sendable: __safeDI_apiSendableBuilder_Hub_A_Scope())
			        }
			        @Sendable nonisolated func __safeDI_apiSendableBuilder_Hub_A_Scope() -> Hub.__safeDI_ApiSendableCarrier_A<any Api> {
			            .init(cBuilder: { __safeDI_apiBuilder_Hub_C_Scope() })
			        }
			        @Sendable nonisolated func __safeDI_apiBuilder_Hub_C_Scope() -> Hub.__safeDI_ApiCarrier_C<any Api> {
			            .init(api: { scope_tag in
			                let tag = scope_tag
			                let api: any Api = LiveApi(tag: tag)
			                return api
			            })
			        }
			        let tag = Tag()
			        func __safeDI_hub() -> Hub {
			            _ = Hub.__safeDI_Hub_A09E0102113C11C1.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Hub(__safeDI_tag: tag, __safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_Hub())
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
			\(fixtures["App"]!["DefaultWidget.swift"]):11:5: error: `DefaultWidget` receives `tag: Tag?`, which `A`’s builder function takes as a parameter outside the `@Sendable` function that builds `widgetBuilder: SendableErasedInstantiator<Int, any Widget>`, because a cycle inside `A`’s tree passes it (`B` forwards `tag: Tag`), and SafeDI hands the builder for `A`’s `widgetBuilder: SendableErasedInstantiator<Int, any Widget>` (`widgetBuilder` of `defaultWidget_WidgetSendableBuilder`) only what that function binds. Declare an @Instantiable type that fulfills `DefaultWidget` in module `Feature` or a module it lists among its SafeDI dependencies.
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
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `mark: Mark?`, which `C` declares outside the `@Sendable` function that builds `tBuilder: SendableInstantiator<T>`, and SafeDI hands the builder for `T`’s `api: any Api` (`api` of `apiSendableBuilder`) only what that function binds. Declare `@Forwarded let mark: Mark` on `T`, so that function binds it, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
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
			\(fixtures["App"]!["LiveApi.swift"]):10:5: error: `LiveApi` receives `tag: Tag?`, which `Mid` builds where it calls `Hub`, but `Mid` passes the builder for `A`’s `api: any Api` (`api` of `apiSendableBuilder`) on from its own caller, which cannot hand it `Mid`’s values. Instantiate `tag` outside `Mid` and declare `@Received let tag: Tag` on `Mid`, so the builder’s caller reads its own, or declare an @Instantiable type that fulfills `Api` in module `Middle` or a module it lists among its SafeDI dependencies, so `Mid` fills the builder itself.
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

	@Test(arguments: ["declarationOrder", "reversedFileNames"])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsOneErrorNamingBothPlaces_whenPassingSeamCallsTwoSeamsEachPassingUpSendablePlaceThatReadsItsValue(fileNames: String) async {
		// `Mid` instantiates `tag` and calls `Hub` and `Hub2`, each of whose places a `@Sendable` function builds, and passes
		// both builders up: one error names both calls and both places, whatever order the files are in.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LiveApi.swift"]):10:5: error: `LiveApi` receives `tag: Tag?`, which `Mid` builds where it calls `Hub` and `Hub2`, but `Mid` passes the builders for `A`’s `api: any Api` (`api` of `apiSendableBuilder`) in `Hub`’s tree and `B`’s `api: any Api` (`api` of `apiSendableBuilder`) in `Hub2`’s tree on from its own caller, which cannot hand them `Mid`’s values. Instantiate `tag` outside `Mid` and declare `@Received let tag: Tag` on `Mid`, so the builders’ caller reads its own, or declare an @Instantiable type that fulfills `Api` in module `Middle` or a module it lists among its SafeDI dependencies, so `Mid` fills the builders itself.
			\(fixtures["Middle"]!["Mid.swift"]):11:5: note: `Mid` declares `tag: Tag` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.twoPassingUpModules(swapsOwners: false, reversesFileNames: fileNames == "reversedFileNames"),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesPassedUpPlacesOfOneCaseByOneBuilderLabel_whenPlacesInAndOutsideInstantiatorReadValueThePassingSeamInstantiates() async {
		// `Hub` builds `Owner`, whose `service` a `@Sendable` builder builds, once in an `Instantiator` and once as a value:
		// two places of one case, which `Outer` and then `Mid` pass up to `Root`. `Mid` instantiates the `logger` the fill
		// reads, so the fill is an error, and the error names both places by the one label their builder has,
		// `serviceSendableBuilder`, not a label per place.
		let feature = [
			"public protocol Service: Sendable {}",
			seamFixtureType(named: "Logger", isFinalClass: true, declarations: [], conformances: ", Sendable"),
			seamFixtureType(named: "Owner", isFinalClass: true, declarations: ["@Received public let logger: Logger", "@Instantiated public let service: SendableLazilyInstantiated<any Service>"], conformances: ", Sendable"),
			seamFixtureType(named: "Hub", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let ownerBuilder: Instantiator<Owner>", "@Instantiated public let owner: Owner"]),
		]
		let middle = [
			seamFixtureType(named: "Outer", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let hub: Hub"]),
			seamFixtureType(named: "Mid", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let logger: Logger", "@Instantiated public let outer: Outer"]),
		]
		let app = [
			SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LiveService", fulfilling: "Service", declarations: ["@Received public let logger: Logger"]),
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let logger: Logger", "@Instantiated public let mid: Mid"]),
		]
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LiveService.swift"]):10:5: error: `LiveService` receives `logger: Logger`, which `Mid` builds where it calls `Hub`, but `Mid` passes the builder for `Owner`’s `service: SendableLazilyInstantiated<any Service>` (`service` of `serviceSendableBuilder`) on from its own caller, which cannot hand it `Mid`’s values. Instantiate `logger` outside `Mid` and declare `@Received let logger: Logger` on `Mid`, so the builder’s caller reads its own, or declare an @Instantiable type that fulfills `Service` in module `Middle` or a module it lists among its SafeDI dependencies, so `Mid` fills the builder itself.
			\(fixtures["Middle"]!["Mid.swift"]):10:5: note: `Mid` declares `logger: Logger` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature),
					ModuleFixture(name: "Middle", packageName: "Other", swiftFileContent: middle.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
					ModuleFixture(name: "App", packageName: "Other", swiftFileContent: app.map { "import Feature\nimport Middle\n\n" + $0 }, dependencies: ["Feature", "Middle"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: ["declarationOrder", "reversedFileNames"])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsEveryFindingOfReader_whenPlacesOneFillFillsLoseItsValueForDifferentReasons(fileNames: String) async {
		// `Mid` instantiates `tag`, builds `D`, whose place `api` its own `@Sendable` function builds, and calls `Hub`, whose
		// place `A`'s `api` a `@Sendable` function builds, which it passes up. `App`'s `LiveApi` fills both and reads `tag`:
		// `D`'s place is built outside the function that binds `tag`, and `A`'s is passed up by `Mid`, which cannot hand its
		// caller `Mid`'s `tag`. Both errors are reported, whatever order `Feature`'s files are in, in source order.
		let reversesFileNames = fileNames == "reversedFileNames"
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let boundByPassingUpSeam = """
			\(fixtures["App"]!["LiveApi.swift"]):10:5: error: `LiveApi` receives `tag: Tag?`, which `Mid` builds where it calls `Hub`, but `Mid` passes the builder for `A`’s `api: any Api` (`api` of `apiSendableBuilder`) on from its own caller, which cannot hand it `Mid`’s values. Instantiate `tag` outside `Mid` and declare `@Received let tag: Tag` on `Mid`, so the builder’s caller reads its own, or declare an @Instantiable type that fulfills `Api` in module `Middle` or a module it lists among its SafeDI dependencies, so `Mid` fills the builder itself.
			\(fixtures["Middle"]!["Mid.swift"]):11:5: note: `Mid` declares `tag: Tag` here.
			"""
			let boundOutsideSendableFunction = """
			\(fixtures["App"]!["LiveApi.swift"]):10:5: error: `LiveApi` receives `tag: Tag?`, which `Mid` declares outside the `@Sendable` function that builds `dBuilder: SendableInstantiator<D>`, and SafeDI hands the builder for `D`’s `api: any Api` (`api` of `apiSendableBuilder`) only what that function binds. Instantiate `tag` outside `Mid` and declare `@Received let tag: Tag` on `Mid`, so the builder’s caller reads its own, or declare an @Instantiable type that fulfills `Api` in module `Middle` or a module it lists among its SafeDI dependencies.
			\(fixtures["Middle"]!["Mid.swift"]):11:5: note: `Mid` declares `tag: Tag` here.
			"""
			return reversesFileNames ? boundOutsideSendableFunction + "\n" + boundByPassingUpSeam : boundByPassingUpSeam + "\n" + boundOutsideSendableFunction
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.passingUpAndSendablePlaceModules(reversesFileNames: reversesFileNames),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsOneErrorNamingBothPlaces_whenTwoSeamsPassingUpSendablePlacesHoldEachOthersOwnerType() async {
		// As above, with `Hub` holding `B` and `Hub2` holding `A`: the error names the places by the seams that hold them.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LiveApi.swift"]):10:5: error: `LiveApi` receives `tag: Tag?`, which `Mid` builds where it calls `Hub2` and `Hub`, but `Mid` passes the builders for `A`’s `api: any Api` (`api` of `apiSendableBuilder`) in `Hub2`’s tree and `B`’s `api: any Api` (`api` of `apiSendableBuilder`) in `Hub`’s tree on from its own caller, which cannot hand them `Mid`’s values. Instantiate `tag` outside `Mid` and declare `@Received let tag: Tag` on `Mid`, so the builders’ caller reads its own, or declare an @Instantiable type that fulfills `Api` in module `Middle` or a module it lists among its SafeDI dependencies, so `Mid` fills the builders itself.
			\(fixtures["Middle"]!["Mid.swift"]):11:5: note: `Mid` declares `tag: Tag` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.twoPassingUpModules(swapsOwners: true, reversesFileNames: false),
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiSendableCarrier<__safeDI_Built>: Sendable {
		        public let hub_Sendable: Hub.__safeDI_ApiSendableCarrier<__safeDI_Built>

		        public init(hub_Sendable: Hub.__safeDI_ApiSendableCarrier<__safeDI_Built>) {
		            self.hub_Sendable = hub_Sendable
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(hub_Sendable: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_tag tag: Tag, __safeDI_apiSendableBuilder: __safeDI_ApiSendableCarrier<any Api>) {
		        @inline(never) func __safeDI_hub() -> Hub {
		            _ = Hub.__safeDI_Hub_4CD39108CC4EA7E7.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Hub(__safeDI_tag: tag, __safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder.hub_Sendable)
		        }
		        let hub: Hub = __safeDI_hub()
		        self.init(tag: tag, hub: hub)
		    }
		}

		extension Mid {
		    public enum __safeDI_Mid_BE96EBDB32B38C91 {}
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
		            _ = Mid.__safeDI_Mid_BE96EBDB32B38C91.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            @Sendable nonisolated func __safeDI_apiSendableBuilder_Mid() -> Mid.__safeDI_ApiSendableCarrier<any Api> {
		                .init(hub_Sendable: __safeDI_apiSendableBuilder_Hub())
		            }
		            @Sendable nonisolated func __safeDI_apiSendableBuilder_Hub() -> Hub.__safeDI_ApiSendableCarrier<any Api> {
		                .init(aBuilder: { __safeDI_apiBuilder_Hub_A_Scope() })
		            }
		            @Sendable nonisolated func __safeDI_apiBuilder_Hub_A_Scope() -> Hub.__safeDI_ApiCarrier_A<any Api> {
		                .init(api: {
		                    let api: any Api = LiveApi(tag: tag)
		                    return api
		                })
		            }
		            return Mid(__safeDI_tag: tag, __safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_Mid())
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
			\(fixtures["App"]!["DefaultWidget.swift"]):11:5: error: `DefaultWidget` receives `title: String?`, which `Shell` forwards outside the `@Sendable` function that builds `widgetBuilder: SendableErasedInstantiator<Int, any Widget>`, and SafeDI hands the builder for `Shell`’s `widgetBuilder: SendableErasedInstantiator<Int, any Widget>` (`widgetBuilder` of `defaultWidget_WidgetSendableBuilder`) only what that function binds. Declare an @Instantiable type that fulfills `DefaultWidget` in module `Feature` or a module it lists among its SafeDI dependencies.
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
			\(fixtures["App"]!["DefaultWidget.swift"]):11:5: error: `DefaultWidget` receives `part: Part`, which `Shell` declares outside the `@Sendable` function that builds `widgetBuilder: SendableErasedInstantiator<Int, any Widget>`, and SafeDI hands the builder for `Shell`’s `widgetBuilder: SendableErasedInstantiator<Int, any Widget>` (`widgetBuilder` of `defaultWidget_WidgetSendableBuilder`) only what that function binds. Declare an @Instantiable type that fulfills `DefaultWidget` in module `Feature` or a module it lists among its SafeDI dependencies.
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
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `name: String?`, which `A` forwards outside the `@Sendable` function that builds `bBuilder: SendableInstantiator<B>`, and SafeDI hands the builder for `B`’s `api: any Api` (`api` of `apiSendableBuilder`) only what that function binds. Declare `@Forwarded let name: String` on `B` too, so that function binds it, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
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
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_DefaultWidget_WidgetSendableCarrier<__safeDI_Built>: Sendable {
			        public let shell_Sendable: __safeDI_DefaultWidget_WidgetSendableCarrier_Shell_Scope_<__safeDI_Built>

			        public init(shell_Sendable: __safeDI_DefaultWidget_WidgetSendableCarrier_Shell_Scope_<__safeDI_Built>) {
			            self.shell_Sendable = shell_Sendable
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<Shell_Scope, __safeDI_Built>.Builder) {
			            self.init(shell_Sendable: .init(__safeDI_noScope: __safeDI_builder))
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_DefaultWidget_WidgetSendableCarrier_Shell_Scope_<__safeDI_Built>: Sendable {
			        public let widgetBuilder: @Sendable () -> SendableErasedInstantiator<Shell_Scope, __safeDI_Built>.Builder

			        public init(widgetBuilder: @escaping @Sendable () -> SendableErasedInstantiator<Shell_Scope, __safeDI_Built>.Builder) {
			            self.widgetBuilder = widgetBuilder
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<Shell_Scope, __safeDI_Built>.Builder) {
			            self.init(widgetBuilder: { __safeDI_builder })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_defaultWidget_WidgetSendableBuilder: __safeDI_DefaultWidget_WidgetSendableCarrier<any Widget>) {
			        let __safeDI_defaultWidget_WidgetSendableBuilder_shell_Sendable = __safeDI_defaultWidget_WidgetSendableBuilder.shell_Sendable
			        @inline(never) func __safeDI_shell() -> Shell {
			            let widgetBuilder = SendableErasedInstantiator<Shell_Scope, any Widget>(__safeDI_defaultWidget_WidgetSendableBuilder_shell_Sendable.widgetBuilder())
			            return Shell(widgetBuilder: widgetBuilder)
			        }
			        let shell: Shell = __safeDI_shell()
			        self.init(shell: shell)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_F60E1113BFAC8782 {}
			}
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        @Sendable nonisolated func __safeDI_defaultWidget_WidgetSendableBuilder_Host_Shell_Scope__widgetBuilder() -> SendableErasedInstantiator<Shell_Scope, any Widget>.Builder {
			            return __safeDI_fillBody_4CFCCAACE99E98C4()
			        }
			        @Sendable nonisolated func __safeDI_fillBody_4CFCCAACE99E98C4() -> SendableErasedInstantiator<Shell_Scope, any Widget>.Builder {
			            @Sendable nonisolated func __safeDI_widgetBuilder(scope: Shell_Scope) -> DefaultWidget {
			                DefaultWidget(scope: scope)
			            }
			            return { forwarded in __safeDI_widgetBuilder(scope: forwarded) }
			        }
			        @Sendable nonisolated func __safeDI_defaultWidget_WidgetSendableBuilder_Host() -> Host.__safeDI_DefaultWidget_WidgetSendableCarrier<any Widget> {
			            .init(shell_Sendable: __safeDI_defaultWidget_WidgetSendableBuilder_Host_Shell_Scope_())
			        }
			        @Sendable nonisolated func __safeDI_defaultWidget_WidgetSendableBuilder_Host_Shell_Scope_() -> Host.__safeDI_DefaultWidget_WidgetSendableCarrier_Shell_Scope_<any Widget> {
			            .init(widgetBuilder: { __safeDI_defaultWidget_WidgetSendableBuilder_Host_Shell_Scope__widgetBuilder() })
			        }
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_F60E1113BFAC8782.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Host(__safeDI_defaultWidget_WidgetSendableBuilder: __safeDI_defaultWidget_WidgetSendableBuilder_Host())
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

	/// `cycleThroughSendableFunction(c: [])` with a second cycle inside the first: `B` also builds `typeBuildingBAgain`,
	/// which instantiates a `tag` of its own and builds `B` again. The type's name decides whether its file precedes `B`'s.
	private static func secondCycleThroughSendableFunction(typeBuildingBAgain: String) -> [String] {
		[
			"public protocol Api {}",
			tag,
			seamFixtureType(named: "TagReader", declarations: ["@Received public let tag: Tag"]),
			seamFixtureType(named: "A", declarations: ["@Instantiated public let reader: TagReader", "@Instantiated public let cBuilder: SendableInstantiator<C>", "@Instantiated public let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "B", declarations: ["@Forwarded public let tag: Tag", "@Instantiated public let stepBuilder: Instantiator<\(typeBuildingBAgain)>", "@Instantiated public let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: typeBuildingBAgain, declarations: ["@Instantiated public let tag: Tag", "@Instantiated public let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "C", declarations: ["@Instantiated public let api: any Api"]),
			seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated public let aBuilder: Instantiator<A>"]),
		]
	}

	/// `Hub`, a seam of `Feature` that receives `tag` and holds the place `api` in a `@Sendable` function; `Mid`, a seam of
	/// `Middle` with `midDeclarations`, which calls `Hub` and passes its builder up; and `App`'s root, which holds a `tag` of
	/// its own, and `LiveApi`, which reads `tag` only if available and fulfills `Api` in `App`, or in `Feature` where
	/// `fulfillerInFeature`.
	/// `Mid` instantiates `tag` and calls `Hub` and `Hub2`, which each receive `tag` and build `A`'s or `B`'s `api: any Api`
	/// in a `SendableInstantiator`, `Hub` `A` unless `swapsOwners`; `App` fills both with `LiveApi`, which reads `tag`. With
	/// `reversesFileNames`, `Feature`'s files are named so their order reverses.
	private static func twoPassingUpModules(swapsOwners: Bool, reversesFileNames: Bool) -> [ModuleFixture] {
		let liveApi = SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: ["@Received(onlyIfAvailable: true) public let tag: Tag?"])
		let (hubOwner, hub2Owner) = swapsOwners ? ("B", "A") : ("A", "B")
		let feature = [
			("Api", "public protocol Api {}"),
			("Tag", tag),
			("A", seamFixtureType(named: "A", declarations: ["@Instantiated public let api: any Api"])),
			("B", seamFixtureType(named: "B", declarations: ["@Instantiated public let api: any Api"])),
			("Hub", seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Received public let tag: Tag", "@Instantiated public let ownerBuilder: SendableInstantiator<\(hubOwner)>"])),
			("Hub2", seamFixtureType(named: "Hub2", isSeam: true, declarations: ["@Received public let tag: Tag", "@Instantiated public let ownerBuilder: SendableInstantiator<\(hub2Owner)>"])),
		]
		let featureModule = if reversesFileNames {
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [], swiftFileContentByFilePath: Dictionary(uniqueKeysWithValues: feature.enumerated().map { ("File\(feature.count - $0.offset).swift", $0.element.1) }))
		} else {
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature.map(\.1))
		}
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let mid: Mid"])
		return [
			featureModule,
			ModuleFixture(name: "Middle", packageName: "Other", swiftFileContent: ["import Feature\n\n" + seamFixtureType(named: "Mid", isSeam: true, declarations: ["@Instantiated public let tag: Tag", "@Instantiated public let hub: Hub", "@Instantiated public let hub2: Hub2"])], dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [liveApi, root].map { "import Feature\nimport Middle\n\n" + $0 }, dependencies: ["Feature", "Middle"]),
		]
	}

	/// `Hub`, a seam of `Feature` that receives `tag` and builds `A`'s place `api` in a `SendableInstantiator`, and `D`, which
	/// holds the place `api`; `Mid`, a seam of `Middle` that instantiates `tag`, builds `D` in a `SendableInstantiator` and
	/// calls `Hub`, passing its builder up; and `App`'s `LiveApi`, which fills `Api` and reads `tag`. With `reversesFileNames`,
	/// `Feature`'s files are named so their order reverses, which puts `D`'s place before `A`'s.
	private static func passingUpAndSendablePlaceModules(reversesFileNames: Bool) -> [ModuleFixture] {
		let liveApi = SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: ["@Received(onlyIfAvailable: true) public let tag: Tag?"])
		let feature = [
			"public protocol Api {}",
			tag,
			seamFixtureType(named: "A", declarations: ["@Instantiated public let api: any Api"]),
			seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Received public let tag: Tag", "@Instantiated public let aBuilder: SendableInstantiator<A>"]),
			seamFixtureType(named: "D", declarations: ["@Instantiated public let api: any Api"]),
		]
		let featureModule = ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [], swiftFileContentByFilePath: Dictionary(uniqueKeysWithValues: feature.enumerated().map { ("File\(reversesFileNames ? feature.count - $0.offset : $0.offset + 1).swift", $0.element) }))
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let mid: Mid"])
		return [
			featureModule,
			ModuleFixture(name: "Middle", packageName: "Other", swiftFileContent: ["import Feature\n\n" + seamFixtureType(named: "Mid", isSeam: true, declarations: ["@Instantiated public let tag: Tag", "@Instantiated public let dBuilder: SendableInstantiator<D>", "@Instantiated public let hub: Hub"])], dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [liveApi, root].map { "import Feature\nimport Middle\n\n" + $0 }, dependencies: ["Feature", "Middle"]),
		]
	}

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

	private static let moduleInfoComment = "If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes."

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
