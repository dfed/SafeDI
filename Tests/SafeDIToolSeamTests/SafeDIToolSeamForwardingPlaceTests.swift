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

/// A seam's place held in an instantiator: the builder a person writes takes what the place forwards and returns the
/// value, its type the wrapper's own `Builder`; the builder struct's member for the place returns that builder, which the
/// seam builds the wrapper around; and the calling module's level function hands the place's function each value it
/// reads, so the builder it returns keeps nothing but what it reads. Places of one builder must forward one value.
struct SafeDIToolSeamForwardingPlaceTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: One place

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesWrapperBuildersAndPlaceFunctionsSpreadForwardedValues_whenInstantiatorsForwardLabeledPair() async throws {
		let fulfillers = [Self.pairGadget, Self.defaultPairPanel]
		let hostDeclarations = [
			"@Instantiated public let navigator: Navigator",
			"@Instantiated let analytics: Analytics",
			#"@Instantiated(fulfilledByType: "PairGadget") public let erased: ErasedInstantiator<(count: Int, name: String), any Gadget>"#,
			"@Instantiated public let held: Instantiator<PairPanel>",
		]
		let modules = Self.modules(hostDeclarations: hostDeclarations, app: fulfillers + [Self.root, Self.navigatorProbe])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen nonisolated public enum SafeDIScope_PairGadget_Gadget {
		        case erased(erased_Values, (count: Int, name: String))

		        nonisolated public struct erased_Values {
		            public let navigator: Navigator
		            public let analytics: Analytics
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let erased: (erased_Values) -> ErasedInstantiator<(count: Int, name: String), __safeDI_Built>.Builder

		            public init(erased: @escaping (erased_Values) -> ErasedInstantiator<(count: Int, name: String), __safeDI_Built>.Builder) {
		                self.erased = erased
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<(count: Int, name: String), __safeDI_Built>.Builder) {
		                self.erased = { _ in __safeDI_builder }
		            }
		        }
		    }

		    @frozen nonisolated public enum SafeDIScope_PairPanel {
		        case held(held_Values, PairPanel.ForwardedProperties)

		        nonisolated public struct held_Values {
		            public let navigator: Navigator
		            public let analytics: Analytics
		            public let erased: ErasedInstantiator<(count: Int, name: String), any Gadget>
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let held: (held_Values) -> ErasedInstantiator<PairPanel.ForwardedProperties, __safeDI_Built>.Builder

		            public init(held: @escaping (held_Values) -> ErasedInstantiator<PairPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		                self.held = held
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<PairPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		                self.held = { _ in __safeDI_builder }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(pairGadget_GadgetBuilder: @escaping ErasedInstantiator<(count: Int, name: String), any Gadget>.Builder, pairPanelBuilder: @escaping Instantiator<PairPanel>.Builder) {
		        self.init(__safeDI_pairGadget_GadgetBuilder: .init(__safeDI_noScope: pairGadget_GadgetBuilder), __safeDI_pairPanelBuilder: .init(__safeDI_noScope: pairPanelBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_pairGadget_GadgetBuilder: SafeDIScope_PairGadget_Gadget.__safeDI_Builder<any Gadget>, __safeDI_pairPanelBuilder: SafeDIScope_PairPanel.__safeDI_Builder<PairPanel>) {
		        let navigator = Navigator()
		        let analytics = Analytics()
		        let erased = ErasedInstantiator<(count: Int, name: String), any Gadget>(__safeDI_pairGadget_GadgetBuilder.erased(SafeDIScope_PairGadget_Gadget.erased_Values(navigator: navigator, analytics: analytics)))
		        let held = Instantiator<PairPanel>(__safeDI_pairPanelBuilder.held(SafeDIScope_PairPanel.held_Values(navigator: navigator, analytics: analytics, erased: erased)))
		        self.init(navigator: navigator, analytics: analytics, erased: erased, held: held)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_AB1A779F46EFBE2C {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_AB1A779F46EFBE2C.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_pairGadget_GadgetBuilder_Host_erased(analytics: Analytics) -> ErasedInstantiator<(count: Int, name: String), any Gadget>.Builder {
		                func __safeDI_erased(count: Int, name: String) -> PairGadget {
		                    PairGadget(count: count, name: name, analytics: analytics)
		                }
		                return { forwarded in __safeDI_erased(count: forwarded.count, name: forwarded.name) }
		            }
		            func __safeDI_pairPanelBuilder_Host_held(analytics: Analytics) -> Instantiator<PairPanel>.Builder {
		                func __safeDI_held(count: Int, name: String) -> DefaultPairPanel {
		                    DefaultPairPanel(count: count, name: name, analytics: analytics)
		                }
		                return { forwarded in __safeDI_held(count: forwarded.count, name: forwarded.name) }
		            }
		            func __safeDI_pairGadget_GadgetBuilder_Host() -> Host.SafeDIScope_PairGadget_Gadget.__safeDI_Builder<any Gadget> {
		                .init(erased: { values in __safeDI_pairGadget_GadgetBuilder_Host_erased(analytics: values.analytics) })
		            }
		            func __safeDI_pairPanelBuilder_Host() -> Host.SafeDIScope_PairPanel.__safeDI_Builder<PairPanel> {
		                .init(held: { values in __safeDI_pairPanelBuilder_Host_held(analytics: values.analytics) })
		            }
		            return Host(__safeDI_pairGadget_GadgetBuilder: __safeDI_pairGadget_GadgetBuilder_Host(), __safeDI_pairPanelBuilder: __safeDI_pairPanelBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		try Self.expectCompiles(output)
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(hostDeclarations: hostDeclarations, featureTypes: fulfillers, app: [Self.root, Self.navigatorProbe]), probes: [
			#"Root().host.erased.instantiate((count: 2, name: "two"))"#,
			#"Root().host.held.instantiate((count: 3, name: "three"))"#,
			#"navigatorIsFreed(holding: { $0.erased }, calling: { _ = $0.instantiate((count: 1, name: "one")) })"#,
			#"navigatorIsFreed(holding: { $0.held }, calling: { _ = $0.instantiate((count: 1, name: "one")) })"#,
		])
		try await expectProbes(of: output, modules: modules, describe: [
			#"navigatorIsFreed(holding: { $0.erased }, calling: { _ = $0.instantiate((count: 1, name: "one")) })"#: "Bool true",
			#"navigatorIsFreed(holding: { $0.held }, calling: { _ = $0.instantiate((count: 1, name: "one")) })"#: "Bool true",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsPlaceFunctionEachValueItReads_whenErasedPlaceIsTwoLevelsBeneathSeam() async throws {
		let featureTypes = [
			seamFixtureType(named: "Theme", isFinalClass: true, declarations: [], conformances: ", Sendable"),
			seamFixtureType(named: "Style", isFinalClass: true, declarations: [], conformances: ", Sendable"),
			seamFixtureType(named: "Toolbar", isFinalClass: true, declarations: [#"@Instantiated(fulfilledByType: "LiveGadget", erasedToConcreteExistential: true) public let panelBuilder: ErasedInstantiator<String, AnyGadget>"#]),
			seamFixtureType(named: "Shell", isFinalClass: true, declarations: ["@Instantiated public let style: Style", "@Instantiated public let toolbar: Toolbar"]),
		]
		let hostDeclarations = ["@Instantiated public let navigator: Navigator", "@Instantiated public let theme: Theme", "@Instantiated public let shell: Shell"]
		let fulfillers = [seamFixtureType(named: "LiveGadget", declarations: ["@Forwarded let title: String", "@Received let theme: Theme", "@Received let style: Style"], conformances: ", Gadget")]
		let modules = Self.modules(hostDeclarations: hostDeclarations, featureTypes: featureTypes, app: fulfillers + [Self.root, Self.navigatorProbe])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen nonisolated public enum SafeDIScope_LiveGadget_AnyGadget {
		        case shell(shell_Values, SafeDIScope_LiveGadget_AnyGadget.Shell_Scope)

		        nonisolated public struct shell_Values {
		            public let navigator: Navigator
		            public let theme: Theme
		        }

		        @frozen nonisolated public enum Shell_Scope {
		            case toolbar(toolbar_Values, SafeDIScope_LiveGadget_AnyGadget.Toolbar_Scope)

		            nonisolated public struct toolbar_Values {
		                public let style: Style
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let toolbar: (toolbar_Values) -> SafeDIScope_LiveGadget_AnyGadget.Toolbar_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(toolbar: @escaping (toolbar_Values) -> SafeDIScope_LiveGadget_AnyGadget.Toolbar_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.toolbar = toolbar
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<String, __safeDI_Built>.Builder) {
		                    self.toolbar = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        @frozen nonisolated public enum Toolbar_Scope {
		            case panelBuilder(panelBuilder_Values, String)

		            nonisolated public struct panelBuilder_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let panelBuilder: (panelBuilder_Values) -> ErasedInstantiator<String, __safeDI_Built>.Builder

		                public init(panelBuilder: @escaping (panelBuilder_Values) -> ErasedInstantiator<String, __safeDI_Built>.Builder) {
		                    self.panelBuilder = panelBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<String, __safeDI_Built>.Builder) {
		                    self.panelBuilder = { _ in __safeDI_builder }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let shell: (shell_Values) -> SafeDIScope_LiveGadget_AnyGadget.Shell_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(shell: @escaping (shell_Values) -> SafeDIScope_LiveGadget_AnyGadget.Shell_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.shell = shell
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<String, __safeDI_Built>.Builder) {
		                self.shell = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(liveGadget_AnyGadgetBuilder: @escaping ErasedInstantiator<String, AnyGadget>.Builder) {
		        self.init(__safeDI_liveGadget_AnyGadgetBuilder: .init(__safeDI_noScope: liveGadget_AnyGadgetBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_liveGadget_AnyGadgetBuilder: SafeDIScope_LiveGadget_AnyGadget.__safeDI_Builder<AnyGadget>) {
		        let navigator = Navigator()
		        let theme = Theme()
		        let __safeDI_liveGadget_AnyGadgetBuilder_shell = __safeDI_liveGadget_AnyGadgetBuilder.shell(SafeDIScope_LiveGadget_AnyGadget.shell_Values(navigator: navigator, theme: theme))
		        func __safeDI_shell() -> Shell {
		            let style = Style()
		            let __safeDI_liveGadget_AnyGadgetBuilder_toolbar = __safeDI_liveGadget_AnyGadgetBuilder_shell.toolbar(SafeDIScope_LiveGadget_AnyGadget.Shell_Scope.toolbar_Values(style: style))
		            func __safeDI_toolbar() -> Toolbar {
		                let panelBuilder = ErasedInstantiator<String, AnyGadget>(__safeDI_liveGadget_AnyGadgetBuilder_toolbar.panelBuilder(SafeDIScope_LiveGadget_AnyGadget.Toolbar_Scope.panelBuilder_Values()))
		                return Toolbar(panelBuilder: panelBuilder)
		            }
		            let toolbar: Toolbar = __safeDI_toolbar()
		            return Shell(style: style, toolbar: toolbar)
		        }
		        let shell: Shell = __safeDI_shell()
		        self.init(navigator: navigator, theme: theme, shell: shell)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_52C4475E6AACEE7B {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_52C4475E6AACEE7B.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_liveGadget_AnyGadgetBuilder_Host_Toolbar_Scope_panelBuilder(theme: Theme, style: Style) -> ErasedInstantiator<String, AnyGadget>.Builder {
		                func __safeDI_panelBuilder(title: String) -> LiveGadget {
		                    LiveGadget(title: title, theme: theme, style: style)
		                }
		                return { forwarded in AnyGadget(__safeDI_panelBuilder(title: forwarded)) }
		            }
		            func __safeDI_liveGadget_AnyGadgetBuilder_Host() -> Host.SafeDIScope_LiveGadget_AnyGadget.__safeDI_Builder<AnyGadget> {
		                .init(shell: { values in __safeDI_liveGadget_AnyGadgetBuilder_Host_Shell_Scope(theme: values.theme) })
		            }
		            func __safeDI_liveGadget_AnyGadgetBuilder_Host_Shell_Scope(theme: Theme) -> Host.SafeDIScope_LiveGadget_AnyGadget.Shell_Scope.__safeDI_Builder<AnyGadget> {
		                .init(toolbar: { values in __safeDI_liveGadget_AnyGadgetBuilder_Host_Toolbar_Scope(style: values.style, theme: theme) })
		            }
		            func __safeDI_liveGadget_AnyGadgetBuilder_Host_Toolbar_Scope(style: Style, theme: Theme) -> Host.SafeDIScope_LiveGadget_AnyGadget.Toolbar_Scope.__safeDI_Builder<AnyGadget> {
		                .init(panelBuilder: { _ in __safeDI_liveGadget_AnyGadgetBuilder_Host_Toolbar_Scope_panelBuilder(theme: theme, style: style) })
		            }
		            return Host(__safeDI_liveGadget_AnyGadgetBuilder: __safeDI_liveGadget_AnyGadgetBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		try Self.expectCompiles(output)
		let probe = #"navigatorIsFreed(holding: { $0.shell.toolbar.panelBuilder }, calling: { _ = $0.instantiate("title") })"#
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(hostDeclarations: hostDeclarations, featureTypes: featureTypes + fulfillers, app: [Self.root, Self.navigatorProbe]), probes: [
			#"Root().host.shell.toolbar.panelBuilder.instantiate("title")"#,
			probe,
		])
		try await expectProbes(of: output, modules: modules, describe: [probe: "Bool true"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillReturnsBuilderTakingForwardedValue_whenSubclassFillsInstantiatorOfHandConformingType() async throws {
		let hostDeclarations = ["@Instantiated public let navigator: Navigator", "@Instantiated let analytics: Analytics", "@Instantiated public let held: Instantiator<Panel>"]
		let modules = Self.modules(hostDeclarations: hostDeclarations, app: [Self.defaultPanel, Self.root, Self.navigatorProbe])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen nonisolated public enum SafeDIScope_Panel {
		        case held(held_Values, Panel.ForwardedProperties)

		        nonisolated public struct held_Values {
		            public let navigator: Navigator
		            public let analytics: Analytics
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let held: (held_Values) -> ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder

		            public init(held: @escaping (held_Values) -> ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
		                self.held = held
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
		                self.held = { _ in __safeDI_builder }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(panelBuilder: @escaping Instantiator<Panel>.Builder) {
		        self.init(__safeDI_panelBuilder: .init(__safeDI_noScope: panelBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_panelBuilder: SafeDIScope_Panel.__safeDI_Builder<Panel>) {
		        let navigator = Navigator()
		        let analytics = Analytics()
		        let held = Instantiator<Panel>(__safeDI_panelBuilder.held(SafeDIScope_Panel.held_Values(navigator: navigator, analytics: analytics)))
		        self.init(navigator: navigator, analytics: analytics, held: held)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_E48FA49D3288E9EE {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_E48FA49D3288E9EE.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_panelBuilder_Host_held(analytics: Analytics) -> Instantiator<Panel>.Builder {
		                func __safeDI_held(name: String) -> DefaultPanel {
		                    DefaultPanel(name: name, analytics: analytics)
		                }
		                return { forwarded in __safeDI_held(name: forwarded) }
		            }
		            func __safeDI_panelBuilder_Host() -> Host.SafeDIScope_Panel.__safeDI_Builder<Panel> {
		                .init(held: { values in __safeDI_panelBuilder_Host_held(analytics: values.analytics) })
		            }
		            return Host(__safeDI_panelBuilder: __safeDI_panelBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		try Self.expectCompiles(output)
		let probe = #"navigatorIsFreed(holding: { $0.held }, calling: { _ = $0.instantiate("name") })"#
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(hostDeclarations: hostDeclarations, featureTypes: [Self.defaultPanel], app: [Self.root, Self.navigatorProbe]), probes: [
			#"Root().host.held.instantiate("name")"#,
			probe,
		])
		try await expectProbes(of: output, modules: modules, describe: [probe: "Bool true"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillReturnsBuilderTakingNothing_whenSubclassFillsInstantiatorOfTypeForwardingNothing() async throws {
		let hostDeclarations = ["@Instantiated public let navigator: Navigator", "@Instantiated let analytics: Analytics", "@Instantiated public let held: Instantiator<EmptyPanel>"]
		let modules = Self.modules(hostDeclarations: hostDeclarations, app: [Self.defaultEmptyPanel, Self.root, Self.navigatorProbe])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen nonisolated public enum SafeDIScope_EmptyPanel {
		        case held(held_Values, EmptyPanel.ForwardedProperties)

		        nonisolated public struct held_Values {
		            public let navigator: Navigator
		            public let analytics: Analytics
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let held: (held_Values) -> ErasedInstantiator<EmptyPanel.ForwardedProperties, __safeDI_Built>.Builder

		            public init(held: @escaping (held_Values) -> ErasedInstantiator<EmptyPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		                self.held = held
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<EmptyPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		                self.held = { _ in __safeDI_builder }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(emptyPanelBuilder: @escaping Instantiator<EmptyPanel>.Builder) {
		        self.init(__safeDI_emptyPanelBuilder: .init(__safeDI_noScope: emptyPanelBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_emptyPanelBuilder: SafeDIScope_EmptyPanel.__safeDI_Builder<EmptyPanel>) {
		        let navigator = Navigator()
		        let analytics = Analytics()
		        let held = Instantiator<EmptyPanel>(__safeDI_emptyPanelBuilder.held(SafeDIScope_EmptyPanel.held_Values(navigator: navigator, analytics: analytics)))
		        self.init(navigator: navigator, analytics: analytics, held: held)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_07D80BE277F2E82D {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_07D80BE277F2E82D.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_emptyPanelBuilder_Host_held(analytics: Analytics) -> Instantiator<EmptyPanel>.Builder {
		                func __safeDI_held() -> DefaultEmptyPanel {
		                    DefaultEmptyPanel(analytics: analytics)
		                }
		                return { _ in __safeDI_held() }
		            }
		            func __safeDI_emptyPanelBuilder_Host() -> Host.SafeDIScope_EmptyPanel.__safeDI_Builder<EmptyPanel> {
		                .init(held: { values in __safeDI_emptyPanelBuilder_Host_held(analytics: values.analytics) })
		            }
		            return Host(__safeDI_emptyPanelBuilder: __safeDI_emptyPanelBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		try Self.expectCompiles(output)
		let probe = "navigatorIsFreed(holding: { $0.held }, calling: { _ = $0.instantiate() })"
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(hostDeclarations: hostDeclarations, featureTypes: [Self.defaultEmptyPanel], app: [Self.root, Self.navigatorProbe]), probes: [
			"Root().host.held.instantiate()",
			probe,
		])
		try await expectProbes(of: output, modules: modules, describe: [probe: "Bool true"])
	}

	// MARK: The @Sendable family

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesSendableErasedBuilder_whenPlainInstantiatorInsideSendableFunctionIsBesideSendableInstantiator() async throws {
		let featureTypes = [seamFixtureType(named: "Owner", isFinalClass: true, declarations: ["@Instantiated public let held: Instantiator<Panel>"])]
		let hostDeclarations = [
			"@Instantiated public let navigator: Navigator",
			"@Received let analytics: Analytics",
			"@Instantiated public let held: SendableInstantiator<Panel>",
			"@Instantiated public let ownerBuilder: SendableInstantiator<Owner>",
		]
		let modules = Self.modules(hostDeclarations: hostDeclarations, featureTypes: featureTypes, app: [Self.defaultPanel, Self.rootInstantiatingAnalytics, Self.navigatorProbe])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen nonisolated public enum SafeDIScope_Panel {
		        @frozen nonisolated public enum Owner_Scope {
		            case held(held_Values, Panel.ForwardedProperties)

		            nonisolated public struct held_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let held: (held_Values) -> ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder

		                public init(held: @escaping (held_Values) -> ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
		                    self.held = held
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
		                    self.held = { _ in __safeDI_builder }
		                }
		            }
		        }
		    }

		    @frozen nonisolated public enum SafeDISendableScope_Panel {
		        case held(Panel.ForwardedProperties)
		        case ownerBuilder(SafeDIScope_Panel.Owner_Scope)

		        nonisolated public struct held_Values: Sendable {}

		        nonisolated public struct ownerBuilder_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
		            public let held: @Sendable (held_Values) -> SendableErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder
		            public let ownerBuilder: @Sendable (ownerBuilder_Values) -> SafeDIScope_Panel.Owner_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(held: @escaping @Sendable (held_Values) -> SendableErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder, ownerBuilder: @escaping @Sendable (ownerBuilder_Values) -> SafeDIScope_Panel.Owner_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.held = held
		                self.ownerBuilder = ownerBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
		                self.held = { _ in __safeDI_builder }
		                self.ownerBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(analytics: Analytics, panelSendableBuilder: @escaping SendableErasedInstantiator<Panel.ForwardedProperties, Panel>.Builder) {
		        self.init(__safeDI_analytics: analytics, __safeDI_panelSendableBuilder: .init(__safeDI_noScope: panelSendableBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_analytics analytics: Analytics, __safeDI_panelSendableBuilder: SafeDISendableScope_Panel.__safeDI_Builder<Panel>) {
		        let navigator = Navigator()
		        let held = SendableInstantiator<Panel>(__safeDI_panelSendableBuilder.held(SafeDISendableScope_Panel.held_Values()))
		        @Sendable nonisolated func __safeDI_ownerBuilder() -> Owner {
		            let __safeDI_panelSendableBuilder_ownerBuilder = __safeDI_panelSendableBuilder.ownerBuilder(SafeDISendableScope_Panel.ownerBuilder_Values())
		            let held = Instantiator<Panel>(__safeDI_panelSendableBuilder_ownerBuilder.held(SafeDIScope_Panel.Owner_Scope.held_Values()))
		            return Owner(held: held)
		        }
		        let ownerBuilder = SendableInstantiator<Owner>(__safeDI_ownerBuilder)
		        self.init(navigator: navigator, analytics: analytics, held: held, ownerBuilder: ownerBuilder)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_268828B862BEF25E {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        let analytics = Analytics()
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_268828B862BEF25E.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            @Sendable nonisolated func __safeDI_panelSendableBuilder_Host_held() -> SendableInstantiator<Panel>.Builder {
		                @Sendable nonisolated func __safeDI_held(name: String) -> DefaultPanel {
		                    DefaultPanel(name: name, analytics: analytics)
		                }
		                return { forwarded in __safeDI_held(name: forwarded) }
		            }
		            @Sendable nonisolated func __safeDI_panelSendableBuilder_Host_Owner_Scope_held() -> Instantiator<Panel>.Builder {
		                func __safeDI_held(name: String) -> DefaultPanel {
		                    DefaultPanel(name: name, analytics: analytics)
		                }
		                return { forwarded in __safeDI_held(name: forwarded) }
		            }
		            @Sendable nonisolated func __safeDI_panelSendableBuilder_Host() -> Host.SafeDISendableScope_Panel.__safeDI_Builder<Panel> {
		                .init(held: { _ in __safeDI_panelSendableBuilder_Host_held() }, ownerBuilder: { _ in __safeDI_panelBuilder_Host_Owner_Scope() })
		            }
		            @Sendable nonisolated func __safeDI_panelBuilder_Host_Owner_Scope() -> Host.SafeDIScope_Panel.Owner_Scope.__safeDI_Builder<Panel> {
		                .init(held: { _ in __safeDI_panelSendableBuilder_Host_Owner_Scope_held() })
		            }
		            return Host(__safeDI_analytics: analytics, __safeDI_panelSendableBuilder: __safeDI_panelSendableBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(analytics: analytics, host: host)
		    }
		}
		"""])
		try Self.expectCompiles(output)
		let probe = #"navigatorIsFreed(holding: { $0.ownerBuilder }, calling: { _ = $0.instantiate().held.instantiate("name") })"#
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(hostDeclarations: hostDeclarations, featureTypes: featureTypes + [Self.defaultPanel], app: [Self.rootInstantiatingAnalytics, Self.navigatorProbe]), probes: [
			#"Root().host.held.instantiate("one")"#,
			#"Root().host.ownerBuilder.instantiate().held.instantiate("two")"#,
			probe,
		])
		try await expectProbes(of: output, modules: modules, describe: [probe: "Bool true"])
	}

	// MARK: One builder, several places

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesErasedBuilderAndAcceptsForwardedPropertiesOfFilledType_whenInstantiatorIsBesideErasedInstantiatorOfItsForwardedProperties() async throws {
		// The subclass forwards what the class's own `ForwardedProperties` says, which the erased place names: the calling
		// module trusts that conformance, as at the `Instantiator` place.
		let hostDeclarations = [
			"@Instantiated public let navigator: Navigator",
			"@Instantiated let analytics: Analytics",
			"@Instantiated public let held: Instantiator<Panel>",
			#"@Instantiated(fulfilledByType: "Panel") public let erased: ErasedInstantiator<Panel.ForwardedProperties, Panel>"#,
		]
		let modules = Self.modules(hostDeclarations: hostDeclarations, app: [Self.defaultPanel, Self.root, Self.navigatorProbe])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen nonisolated public enum SafeDIScope_Panel {
		        case held(held_Values, Panel.ForwardedProperties)
		        case erased(erased_Values, Panel.ForwardedProperties)

		        nonisolated public struct held_Values {
		            public let navigator: Navigator
		            public let analytics: Analytics
		        }

		        nonisolated public struct erased_Values {
		            public let navigator: Navigator
		            public let analytics: Analytics
		            public let held: Instantiator<Panel>
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let held: (held_Values) -> ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder
		            public let erased: (erased_Values) -> ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder

		            public init(held: @escaping (held_Values) -> ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder, erased: @escaping (erased_Values) -> ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
		                self.held = held
		                self.erased = erased
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
		                self.held = { _ in __safeDI_builder }
		                self.erased = { _ in __safeDI_builder }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(panelBuilder: @escaping ErasedInstantiator<Panel.ForwardedProperties, Panel>.Builder) {
		        self.init(__safeDI_panelBuilder: .init(__safeDI_noScope: panelBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_panelBuilder: SafeDIScope_Panel.__safeDI_Builder<Panel>) {
		        let navigator = Navigator()
		        let analytics = Analytics()
		        let held = Instantiator<Panel>(__safeDI_panelBuilder.held(SafeDIScope_Panel.held_Values(navigator: navigator, analytics: analytics)))
		        let erased = ErasedInstantiator<Panel.ForwardedProperties, Panel>(__safeDI_panelBuilder.erased(SafeDIScope_Panel.erased_Values(navigator: navigator, analytics: analytics, held: held)))
		        self.init(navigator: navigator, analytics: analytics, held: held, erased: erased)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_10DB09D5D2682AE0 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_10DB09D5D2682AE0.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_panelBuilder_Host_held(analytics: Analytics) -> Instantiator<Panel>.Builder {
		                func __safeDI_held(name: String) -> DefaultPanel {
		                    DefaultPanel(name: name, analytics: analytics)
		                }
		                return { forwarded in __safeDI_held(name: forwarded) }
		            }
		            func __safeDI_panelBuilder_Host_erased(analytics: Analytics) -> ErasedInstantiator<Panel.ForwardedProperties, Panel>.Builder {
		                func __safeDI_erased(name: String) -> DefaultPanel {
		                    DefaultPanel(name: name, analytics: analytics)
		                }
		                return { forwarded in __safeDI_erased(name: forwarded) }
		            }
		            func __safeDI_panelBuilder_Host() -> Host.SafeDIScope_Panel.__safeDI_Builder<Panel> {
		                .init(held: { values in __safeDI_panelBuilder_Host_held(analytics: values.analytics) }, erased: { values in __safeDI_panelBuilder_Host_erased(analytics: values.analytics) })
		            }
		            return Host(__safeDI_panelBuilder: __safeDI_panelBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		try Self.expectCompiles(output)
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(hostDeclarations: hostDeclarations, featureTypes: [Self.defaultPanel], app: [Self.root, Self.navigatorProbe]), probes: [
			#"Root().host.held.instantiate("two")"#,
			#"Root().host.erased.instantiate("two")"#,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spreadsForwardedPairByLabel_whenErasedInstantiatorOfForwardedPropertiesIsBesideInstantiatorOfTypeForwardingPair() async throws {
		let hostDeclarations = [
			"@Instantiated public let navigator: Navigator",
			"@Instantiated let analytics: Analytics",
			"@Instantiated public let held: Instantiator<PairPanel>",
			#"@Instantiated(fulfilledByType: "PairPanel") public let erased: ErasedInstantiator<PairPanel.ForwardedProperties, PairPanel>"#,
		]
		let modules = Self.modules(hostDeclarations: hostDeclarations, app: [Self.defaultPairPanel, Self.root, Self.navigatorProbe])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen nonisolated public enum SafeDIScope_PairPanel {
		        case held(held_Values, PairPanel.ForwardedProperties)
		        case erased(erased_Values, PairPanel.ForwardedProperties)

		        nonisolated public struct held_Values {
		            public let navigator: Navigator
		            public let analytics: Analytics
		        }

		        nonisolated public struct erased_Values {
		            public let navigator: Navigator
		            public let analytics: Analytics
		            public let held: Instantiator<PairPanel>
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let held: (held_Values) -> ErasedInstantiator<PairPanel.ForwardedProperties, __safeDI_Built>.Builder
		            public let erased: (erased_Values) -> ErasedInstantiator<PairPanel.ForwardedProperties, __safeDI_Built>.Builder

		            public init(held: @escaping (held_Values) -> ErasedInstantiator<PairPanel.ForwardedProperties, __safeDI_Built>.Builder, erased: @escaping (erased_Values) -> ErasedInstantiator<PairPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		                self.held = held
		                self.erased = erased
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<PairPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		                self.held = { _ in __safeDI_builder }
		                self.erased = { _ in __safeDI_builder }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(pairPanelBuilder: @escaping ErasedInstantiator<PairPanel.ForwardedProperties, PairPanel>.Builder) {
		        self.init(__safeDI_pairPanelBuilder: .init(__safeDI_noScope: pairPanelBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_pairPanelBuilder: SafeDIScope_PairPanel.__safeDI_Builder<PairPanel>) {
		        let navigator = Navigator()
		        let analytics = Analytics()
		        let held = Instantiator<PairPanel>(__safeDI_pairPanelBuilder.held(SafeDIScope_PairPanel.held_Values(navigator: navigator, analytics: analytics)))
		        let erased = ErasedInstantiator<PairPanel.ForwardedProperties, PairPanel>(__safeDI_pairPanelBuilder.erased(SafeDIScope_PairPanel.erased_Values(navigator: navigator, analytics: analytics, held: held)))
		        self.init(navigator: navigator, analytics: analytics, held: held, erased: erased)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_51873D98E40B41FC {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_51873D98E40B41FC.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_pairPanelBuilder_Host_held(analytics: Analytics) -> Instantiator<PairPanel>.Builder {
		                func __safeDI_held(count: Int, name: String) -> DefaultPairPanel {
		                    DefaultPairPanel(count: count, name: name, analytics: analytics)
		                }
		                return { forwarded in __safeDI_held(count: forwarded.count, name: forwarded.name) }
		            }
		            func __safeDI_pairPanelBuilder_Host_erased(analytics: Analytics) -> ErasedInstantiator<PairPanel.ForwardedProperties, PairPanel>.Builder {
		                func __safeDI_erased(count: Int, name: String) -> DefaultPairPanel {
		                    DefaultPairPanel(count: count, name: name, analytics: analytics)
		                }
		                return { forwarded in __safeDI_erased(count: forwarded.count, name: forwarded.name) }
		            }
		            func __safeDI_pairPanelBuilder_Host() -> Host.SafeDIScope_PairPanel.__safeDI_Builder<PairPanel> {
		                .init(held: { values in __safeDI_pairPanelBuilder_Host_held(analytics: values.analytics) }, erased: { values in __safeDI_pairPanelBuilder_Host_erased(analytics: values.analytics) })
		            }
		            return Host(__safeDI_pairPanelBuilder: __safeDI_pairPanelBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		try Self.expectCompiles(output)
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(hostDeclarations: hostDeclarations, featureTypes: [Self.defaultPairPanel], app: [Self.root, Self.navigatorProbe]), probes: [
			#"Root().host.held.instantiate((count: 2, name: "two"))"#,
			#"Root().host.erased.instantiate((count: 3, name: "three"))"#,
		])
	}

	@Test(arguments: [["A", "B", "C"], ["A", "C", "B"], ["B", "A", "C"], ["B", "C", "A"], ["C", "A", "B"], ["C", "B", "A"]])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsBuildersForwardedValueAsFirstDeclaredPlaceSpellsIt_whenPlacesSpellOneValueTwoWays(order: [String]) async throws {
		// `C` spells the value `Swift.Int`, `A` and `B` spell it `Int`: one value, which the builder takes as the place declared
		// first spells it.
		let placesFile = order.map { name in
			let spelling = name == "C" ? "Swift.Int" : "Int"
			return seamFixtureType(named: name, isFinalClass: true, declarations: [#"@Instantiated(fulfilledByType: "IntGadget") public let place: ErasedInstantiator<\#(spelling), any Gadget>"#])
		}.joined(separator: "\n\n")
		let forwarded = order[0] == "C" ? "Swift.Int" : "Int"
		let modules = [
			ModuleFixture(
				name: "Feature",
				packageName: "Shop",
				swiftFileContent: Self.featureFiles + [seamFixtureType(named: "Host", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let a: A", "@Instantiated public let b: B", "@Instantiated public let c: C"])],
				swiftFileContentByFilePath: plainDependencyTreeInitializersConfiguration.merging(["Places.swift": placesFile]) { first, _ in first },
			),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [Self.intGadget, Self.root].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen nonisolated public enum SafeDIScope_IntGadget_Gadget {
		        case a(a_Values, SafeDIScope_IntGadget_Gadget.A_Scope)
		        case b(b_Values, SafeDIScope_IntGadget_Gadget.B_Scope)
		        case c(c_Values, SafeDIScope_IntGadget_Gadget.C_Scope)

		        nonisolated public struct a_Values {}

		        nonisolated public struct b_Values {
		            public let a: A
		        }

		        nonisolated public struct c_Values {
		            public let a: A
		            public let b: B
		        }

		        @frozen nonisolated public enum A_Scope {
		            case place(place_Values, Int)

		            nonisolated public struct place_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let place: (place_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder

		                public init(place: @escaping (place_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                    self.place = place
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                    self.place = { _ in __safeDI_builder }
		                }
		            }
		        }

		        @frozen nonisolated public enum B_Scope {
		            case place(place_Values, Int)

		            nonisolated public struct place_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let place: (place_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder

		                public init(place: @escaping (place_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                    self.place = place
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                    self.place = { _ in __safeDI_builder }
		                }
		            }
		        }

		        @frozen nonisolated public enum C_Scope {
		            case place(place_Values, Swift.Int)

		            nonisolated public struct place_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let place: (place_Values) -> ErasedInstantiator<Swift.Int, __safeDI_Built>.Builder

		                public init(place: @escaping (place_Values) -> ErasedInstantiator<Swift.Int, __safeDI_Built>.Builder) {
		                    self.place = place
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Swift.Int, __safeDI_Built>.Builder) {
		                    self.place = { _ in __safeDI_builder }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let a: (a_Values) -> SafeDIScope_IntGadget_Gadget.A_Scope.__safeDI_Builder<__safeDI_Built>
		            public let b: (b_Values) -> SafeDIScope_IntGadget_Gadget.B_Scope.__safeDI_Builder<__safeDI_Built>
		            public let c: (c_Values) -> SafeDIScope_IntGadget_Gadget.C_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(a: @escaping (a_Values) -> SafeDIScope_IntGadget_Gadget.A_Scope.__safeDI_Builder<__safeDI_Built>, b: @escaping (b_Values) -> SafeDIScope_IntGadget_Gadget.B_Scope.__safeDI_Builder<__safeDI_Built>, c: @escaping (c_Values) -> SafeDIScope_IntGadget_Gadget.C_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.a = a
		                self.b = b
		                self.c = c
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<\(forwarded), __safeDI_Built>.Builder) {
		                self.a = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                self.b = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                self.c = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(intGadget_GadgetBuilder: @escaping ErasedInstantiator<\(forwarded), any Gadget>.Builder) {
		        self.init(__safeDI_intGadget_GadgetBuilder: .init(__safeDI_noScope: intGadget_GadgetBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_intGadget_GadgetBuilder: SafeDIScope_IntGadget_Gadget.__safeDI_Builder<any Gadget>) {
		        let __safeDI_intGadget_GadgetBuilder_a = __safeDI_intGadget_GadgetBuilder.a(SafeDIScope_IntGadget_Gadget.a_Values())
		        func __safeDI_a() -> A {
		            let place = ErasedInstantiator<Int, any Gadget>(__safeDI_intGadget_GadgetBuilder_a.place(SafeDIScope_IntGadget_Gadget.A_Scope.place_Values()))
		            return A(place: place)
		        }
		        let a: A = __safeDI_a()
		        let __safeDI_intGadget_GadgetBuilder_b = __safeDI_intGadget_GadgetBuilder.b(SafeDIScope_IntGadget_Gadget.b_Values(a: a))
		        func __safeDI_b() -> B {
		            let place = ErasedInstantiator<Int, any Gadget>(__safeDI_intGadget_GadgetBuilder_b.place(SafeDIScope_IntGadget_Gadget.B_Scope.place_Values()))
		            return B(place: place)
		        }
		        let b: B = __safeDI_b()
		        let __safeDI_intGadget_GadgetBuilder_c = __safeDI_intGadget_GadgetBuilder.c(SafeDIScope_IntGadget_Gadget.c_Values(a: a, b: b))
		        func __safeDI_c() -> C {
		            let place = ErasedInstantiator<Swift.Int, any Gadget>(__safeDI_intGadget_GadgetBuilder_c.place(SafeDIScope_IntGadget_Gadget.C_Scope.place_Values()))
		            return C(place: place)
		        }
		        let c: C = __safeDI_c()
		        self.init(a: a, b: b, c: c)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_13AB3195FCAFFFA9 {}
		}
		"""])
		try Self.expectCompiles(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesBuilderTakingNothing_whenPlainLazyAndErasedPlacesForwardNothing() async throws {
		let hostDeclarations = [
			"@Instantiated public let navigator: Navigator",
			"@Instantiated let analytics: Analytics",
			#"@Instantiated(fulfilledByType: "DefaultGadget") public let now: any Gadget"#,
			#"@Instantiated(fulfilledByType: "DefaultGadget") public let lazy: LazilyInstantiated<any Gadget>"#,
			#"@Instantiated(fulfilledByType: "DefaultGadget") public let later: ErasedInstantiator<(), any Gadget>"#,
		]
		let modules = Self.modules(hostDeclarations: hostDeclarations, app: [Self.defaultGadget, Self.root, Self.navigatorProbe])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen nonisolated public enum SafeDIScope_DefaultGadget_Gadget {
		        case now(now_Values)
		        case lazy(lazy_Values)
		        case later(later_Values)

		        nonisolated public struct now_Values {
		            public let navigator: Navigator
		            public let analytics: Analytics
		        }

		        nonisolated public struct lazy_Values {
		            public let navigator: Navigator
		            public let analytics: Analytics
		            public let now: any Gadget
		        }

		        nonisolated public struct later_Values {
		            public let navigator: Navigator
		            public let analytics: Analytics
		            public let now: any Gadget
		            public let lazy: LazilyInstantiated<any Gadget>
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let now: (now_Values) -> __safeDI_Built
		            public let lazy: (lazy_Values) -> __safeDI_Built
		            public let later: (later_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder

		            public init(now: @escaping (now_Values) -> __safeDI_Built, lazy: @escaping (lazy_Values) -> __safeDI_Built, later: @escaping (later_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder) {
		                self.now = now
		                self.lazy = lazy
		                self.later = later
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.now = { _ in __safeDI_builder() }
		                self.lazy = { _ in __safeDI_builder() }
		                self.later = { _ in { _ in __safeDI_builder() } }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(defaultGadget_GadgetBuilder: @escaping () -> any Gadget) {
		        self.init(__safeDI_defaultGadget_GadgetBuilder: .init(__safeDI_noScope: defaultGadget_GadgetBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_defaultGadget_GadgetBuilder: SafeDIScope_DefaultGadget_Gadget.__safeDI_Builder<any Gadget>) {
		        let navigator = Navigator()
		        let analytics = Analytics()
		        let now: any Gadget = __safeDI_defaultGadget_GadgetBuilder.now(SafeDIScope_DefaultGadget_Gadget.now_Values(navigator: navigator, analytics: analytics))
		        func __safeDI_lazy() -> any Gadget {
		            __safeDI_defaultGadget_GadgetBuilder.lazy(SafeDIScope_DefaultGadget_Gadget.lazy_Values(navigator: navigator, analytics: analytics, now: now))
		        }
		        let lazy = LazilyInstantiated<any Gadget>(__safeDI_lazy)
		        let later = ErasedInstantiator<(), any Gadget>(__safeDI_defaultGadget_GadgetBuilder.later(SafeDIScope_DefaultGadget_Gadget.later_Values(navigator: navigator, analytics: analytics, now: now, lazy: lazy)))
		        self.init(navigator: navigator, analytics: analytics, now: now, lazy: lazy, later: later)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_997B93888F6BD160 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_997B93888F6BD160.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_defaultGadget_GadgetBuilder_Host_lazy(_ scope: Host.SafeDIScope_DefaultGadget_Gadget.lazy_Values) -> any Gadget {
		                let analytics = scope.analytics
		                func __safeDI_lazy() -> DefaultGadget {
		                    DefaultGadget(analytics: analytics)
		                }
		                return __safeDI_lazy()
		            }
		            func __safeDI_defaultGadget_GadgetBuilder_Host_later(analytics: Analytics) -> ErasedInstantiator<(), any Gadget>.Builder {
		                func __safeDI_later() -> DefaultGadget {
		                    DefaultGadget(analytics: analytics)
		                }
		                return { _ in __safeDI_later() }
		            }
		            func __safeDI_defaultGadget_GadgetBuilder_Host() -> Host.SafeDIScope_DefaultGadget_Gadget.__safeDI_Builder<any Gadget> {
		                .init(
		                    now: { scope in
		                        let analytics = scope.analytics
		                        let now: any Gadget = DefaultGadget(analytics: analytics)
		                        return now
		                    },
		                    lazy: { scope in __safeDI_defaultGadget_GadgetBuilder_Host_lazy(scope) },
		                    later: { values in __safeDI_defaultGadget_GadgetBuilder_Host_later(analytics: values.analytics) }
		                )
		            }
		            return Host(__safeDI_defaultGadget_GadgetBuilder: __safeDI_defaultGadget_GadgetBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		try Self.expectCompiles(output)
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(hostDeclarations: hostDeclarations, featureTypes: [Self.defaultGadget], app: [Self.root, Self.navigatorProbe]), probes: [
			"Root().host.lazy.instance",
			"Root().host.later.instantiate()",
			"navigatorIsFreed(holding: { $0.later }, calling: { _ = $0.instantiate() })",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesBuilderTakingNothing_whenPlainPlaceIsBesideInstantiatorOfTypeForwardingNothing() async throws {
		let hostDeclarations = ["@Instantiated let analytics: Analytics", "@Instantiated public let now: EmptyPanel", "@Instantiated public let held: Instantiator<EmptyPanel>"]
		let modules = Self.modules(hostDeclarations: hostDeclarations, app: [Self.defaultEmptyPanel, Self.root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen nonisolated public enum SafeDIScope_EmptyPanel {
		        case now(now_Values)
		        case held(held_Values, EmptyPanel.ForwardedProperties)

		        nonisolated public struct now_Values {
		            public let analytics: Analytics
		        }

		        nonisolated public struct held_Values {
		            public let analytics: Analytics
		            public let now: EmptyPanel
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let now: (now_Values) -> __safeDI_Built
		            public let held: (held_Values) -> ErasedInstantiator<EmptyPanel.ForwardedProperties, __safeDI_Built>.Builder

		            public init(now: @escaping (now_Values) -> __safeDI_Built, held: @escaping (held_Values) -> ErasedInstantiator<EmptyPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		                self.now = now
		                self.held = held
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.now = { _ in __safeDI_builder() }
		                self.held = { _ in { _ in __safeDI_builder() } }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(emptyPanelBuilder: @escaping () -> EmptyPanel) {
		        self.init(__safeDI_emptyPanelBuilder: .init(__safeDI_noScope: emptyPanelBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_emptyPanelBuilder: SafeDIScope_EmptyPanel.__safeDI_Builder<EmptyPanel>) {
		        let analytics = Analytics()
		        let now: EmptyPanel = __safeDI_emptyPanelBuilder.now(SafeDIScope_EmptyPanel.now_Values(analytics: analytics))
		        let held = Instantiator<EmptyPanel>(__safeDI_emptyPanelBuilder.held(SafeDIScope_EmptyPanel.held_Values(analytics: analytics, now: now)))
		        self.init(analytics: analytics, now: now, held: held)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_4F1965B634823272 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_4F1965B634823272.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_emptyPanelBuilder_Host_held(analytics: Analytics) -> Instantiator<EmptyPanel>.Builder {
		                func __safeDI_held() -> DefaultEmptyPanel {
		                    DefaultEmptyPanel(analytics: analytics)
		                }
		                return { _ in __safeDI_held() }
		            }
		            func __safeDI_emptyPanelBuilder_Host() -> Host.SafeDIScope_EmptyPanel.__safeDI_Builder<EmptyPanel> {
		                .init(
		                    now: { scope in
		                        let analytics = scope.analytics
		                        let now: EmptyPanel = DefaultEmptyPanel(analytics: analytics)
		                        return now
		                    },
		                    held: { values in __safeDI_emptyPanelBuilder_Host_held(analytics: values.analytics) }
		                )
		            }
		            return Host(__safeDI_emptyPanelBuilder: __safeDI_emptyPanelBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		try Self.expectCompiles(output)
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(hostDeclarations: hostDeclarations, featureTypes: [Self.defaultEmptyPanel], app: [Self.root]), probes: ["Root().host.held.instantiate()"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesErasedBuilderTakingEmptyTuple_whenErasedPlacesSpellNothingTwoWays() async throws {
		let hostDeclarations = [
			"@Instantiated let analytics: Analytics",
			#"@Instantiated(fulfilledByType: "DefaultGadget") public let tuple: ErasedInstantiator<(), any Gadget>"#,
			#"@Instantiated(fulfilledByType: "DefaultGadget") public let void: ErasedInstantiator<Void, any Gadget>"#,
		]
		let modules = Self.modules(hostDeclarations: hostDeclarations, app: [Self.defaultGadget, Self.root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen nonisolated public enum SafeDIScope_DefaultGadget_Gadget {
		        case tuple(tuple_Values)
		        case void(void_Values)

		        nonisolated public struct tuple_Values {
		            public let analytics: Analytics
		        }

		        nonisolated public struct void_Values {
		            public let analytics: Analytics
		            public let tuple: ErasedInstantiator<(), any Gadget>
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let tuple: (tuple_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder
		            public let void: (void_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder

		            public init(tuple: @escaping (tuple_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder, void: @escaping (void_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder) {
		                self.tuple = tuple
		                self.void = void
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<(), __safeDI_Built>.Builder) {
		                self.tuple = { _ in __safeDI_builder }
		                self.void = { _ in __safeDI_builder }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(defaultGadget_GadgetBuilder: @escaping ErasedInstantiator<(), any Gadget>.Builder) {
		        self.init(__safeDI_defaultGadget_GadgetBuilder: .init(__safeDI_noScope: defaultGadget_GadgetBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_defaultGadget_GadgetBuilder: SafeDIScope_DefaultGadget_Gadget.__safeDI_Builder<any Gadget>) {
		        let analytics = Analytics()
		        let tuple = ErasedInstantiator<(), any Gadget>(__safeDI_defaultGadget_GadgetBuilder.tuple(SafeDIScope_DefaultGadget_Gadget.tuple_Values(analytics: analytics)))
		        let void = ErasedInstantiator<Void, any Gadget>(__safeDI_defaultGadget_GadgetBuilder.void(SafeDIScope_DefaultGadget_Gadget.void_Values(analytics: analytics, tuple: tuple)))
		        self.init(analytics: analytics, tuple: tuple, void: void)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_3A27C626B5357609 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_3A27C626B5357609.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_defaultGadget_GadgetBuilder_Host_tuple(analytics: Analytics) -> ErasedInstantiator<(), any Gadget>.Builder {
		                func __safeDI_tuple() -> DefaultGadget {
		                    DefaultGadget(analytics: analytics)
		                }
		                return { _ in __safeDI_tuple() }
		            }
		            func __safeDI_defaultGadget_GadgetBuilder_Host_void(analytics: Analytics) -> ErasedInstantiator<Void, any Gadget>.Builder {
		                func __safeDI_void() -> DefaultGadget {
		                    DefaultGadget(analytics: analytics)
		                }
		                return { _ in __safeDI_void() }
		            }
		            func __safeDI_defaultGadget_GadgetBuilder_Host() -> Host.SafeDIScope_DefaultGadget_Gadget.__safeDI_Builder<any Gadget> {
		                .init(tuple: { values in __safeDI_defaultGadget_GadgetBuilder_Host_tuple(analytics: values.analytics) }, void: { values in __safeDI_defaultGadget_GadgetBuilder_Host_void(analytics: values.analytics) })
		            }
		            return Host(__safeDI_defaultGadget_GadgetBuilder: __safeDI_defaultGadget_GadgetBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		try Self.expectCompiles(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsInstantiatorsMemberBuilderOfEmptyTuple_whenInstantiatorIsBesideErasedInstantiatorForwardingNothing() async throws {
		let hostDeclarations = [
			"@Instantiated let analytics: Analytics",
			"@Instantiated public let held: Instantiator<EmptyPanel>",
			#"@Instantiated(fulfilledByType: "EmptyPanel") public let later: ErasedInstantiator<(), EmptyPanel>"#,
		]
		let modules = Self.modules(hostDeclarations: hostDeclarations, app: [Self.defaultEmptyPanel, Self.root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen nonisolated public enum SafeDIScope_EmptyPanel {
		        case held(held_Values, EmptyPanel.ForwardedProperties)
		        case later(later_Values)

		        nonisolated public struct held_Values {
		            public let analytics: Analytics
		        }

		        nonisolated public struct later_Values {
		            public let analytics: Analytics
		            public let held: Instantiator<EmptyPanel>
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let held: (held_Values) -> ErasedInstantiator<EmptyPanel.ForwardedProperties, __safeDI_Built>.Builder
		            public let later: (later_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder

		            public init(held: @escaping (held_Values) -> ErasedInstantiator<EmptyPanel.ForwardedProperties, __safeDI_Built>.Builder, later: @escaping (later_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder) {
		                self.held = held
		                self.later = later
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<(), __safeDI_Built>.Builder) {
		                self.held = { _ in { _ in __safeDI_builder(()) } }
		                self.later = { _ in __safeDI_builder }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(emptyPanelBuilder: @escaping ErasedInstantiator<(), EmptyPanel>.Builder) {
		        self.init(__safeDI_emptyPanelBuilder: .init(__safeDI_noScope: emptyPanelBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_emptyPanelBuilder: SafeDIScope_EmptyPanel.__safeDI_Builder<EmptyPanel>) {
		        let analytics = Analytics()
		        let held = Instantiator<EmptyPanel>(__safeDI_emptyPanelBuilder.held(SafeDIScope_EmptyPanel.held_Values(analytics: analytics)))
		        let later = ErasedInstantiator<(), EmptyPanel>(__safeDI_emptyPanelBuilder.later(SafeDIScope_EmptyPanel.later_Values(analytics: analytics, held: held)))
		        self.init(analytics: analytics, held: held, later: later)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_1B7B4491D9F2886B {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_1B7B4491D9F2886B.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_emptyPanelBuilder_Host_held(analytics: Analytics) -> Instantiator<EmptyPanel>.Builder {
		                func __safeDI_held() -> DefaultEmptyPanel {
		                    DefaultEmptyPanel(analytics: analytics)
		                }
		                return { _ in __safeDI_held() }
		            }
		            func __safeDI_emptyPanelBuilder_Host_later(analytics: Analytics) -> ErasedInstantiator<(), EmptyPanel>.Builder {
		                func __safeDI_later() -> DefaultEmptyPanel {
		                    DefaultEmptyPanel(analytics: analytics)
		                }
		                return { _ in __safeDI_later() }
		            }
		            func __safeDI_emptyPanelBuilder_Host() -> Host.SafeDIScope_EmptyPanel.__safeDI_Builder<EmptyPanel> {
		                .init(held: { values in __safeDI_emptyPanelBuilder_Host_held(analytics: values.analytics) }, later: { values in __safeDI_emptyPanelBuilder_Host_later(analytics: values.analytics) })
		            }
		            return Host(__safeDI_emptyPanelBuilder: __safeDI_emptyPanelBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		try Self.expectCompiles(output)
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(hostDeclarations: hostDeclarations, featureTypes: [Self.defaultEmptyPanel], app: [Self.root]), probes: [
			"Root().host.held.instantiate()",
			"Root().host.later.instantiate()",
		])
	}

	// MARK: Places that forward other values

	/// A pair of places of one builder that forward different values, and the diagnostic the seam's module reports.
	struct OtherValues: CustomTestStringConvertible, Sendable {
		let name: String
		let hostDeclarations: [String]
		/// The diagnostics, given the path of `Host.swift`.
		let diagnostics: @Sendable (String) -> String

		var testDescription: String {
			name
		}
	}

	static let otherValues = [
		OtherValues(
			name: "two written types",
			hostDeclarations: [
				#"@Instantiated(fulfilledByType: "Impl") let a: ErasedInstantiator<Int, any Gadget>"#,
				#"@Instantiated(fulfilledByType: "Impl") let b: ErasedInstantiator<String, any Gadget>"#,
			],
			diagnostics: { host in
				"""
				\(host):9:5: error: `b: ErasedInstantiator<String, any Gadget>` on `Host` forwards `String`, and `a: ErasedInstantiator<Int, any Gadget>` on `Host` forwards `Int`. `Host` takes one builder for both, since `Impl` fills each and each returns `any Gadget`, and a builder’s places must forward the same values. Give both the same first generic argument, or name another type in the `fulfilledByType` of one.
				"""
			},
		),
		OtherValues(
			name: "nothing beside a type",
			hostDeclarations: [
				#"@Instantiated(fulfilledByType: "Impl") let now: any Gadget"#,
				#"@Instantiated(fulfilledByType: "Impl") let later: ErasedInstantiator<String, any Gadget>"#,
			],
			diagnostics: { host in
				"""
				\(host):9:5: error: `later: ErasedInstantiator<String, any Gadget>` on `Host` forwards `String`, and `now: any Gadget` on `Host` forwards nothing. `Host` takes one builder for both, since `Impl` fills each and each returns `any Gadget`, and a builder’s places must forward the same values. Declare `later`’s first generic argument `()`, or name another type in its `fulfilledByType`.
				"""
			},
		),
		OtherValues(
			name: "ForwardedProperties beside a written type",
			hostDeclarations: [
				"@Instantiated let held: Instantiator<Panel>",
				#"@Instantiated(fulfilledByType: "Panel") let erased: ErasedInstantiator<String, Panel>"#,
			],
			diagnostics: { host in
				"""
				\(host):9:5: error: `erased: ErasedInstantiator<String, Panel>` on `Host` forwards `String`, and `held: Instantiator<Panel>` on `Host` forwards `Panel.ForwardedProperties`. `Host` takes one builder for both, since `Panel` fills each and each returns `Panel`, and a builder’s places must forward the same values. Declare `erased` as `ErasedInstantiator<Panel.ForwardedProperties, Panel>`, or name another type in its `fulfilledByType`.
				"""
			},
		),
		OtherValues(
			name: "one of three places",
			hostDeclarations: [
				#"@Instantiated(fulfilledByType: "Impl") let a: ErasedInstantiator<Int, any Gadget>"#,
				#"@Instantiated(fulfilledByType: "Impl") let b: ErasedInstantiator<String, any Gadget>"#,
				#"@Instantiated(fulfilledByType: "Impl") let c: ErasedInstantiator<Int, any Gadget>"#,
			],
			diagnostics: { host in
				"""
				\(host):10:5: error: `b: ErasedInstantiator<String, any Gadget>` on `Host` forwards `String`, and `a: ErasedInstantiator<Int, any Gadget>` on `Host` forwards `Int`. `Host` takes one builder for both, since `Impl` fills each and each returns `any Gadget`, and a builder’s places must forward the same values. Give both the same first generic argument, or name another type in the `fulfilledByType` of one.
				"""
			},
		),
		OtherValues(
			name: "the @Sendable family",
			hostDeclarations: [
				#"@Instantiated(fulfilledByType: "Impl") let a: SendableErasedInstantiator<Int, any Gadget>"#,
				#"@Instantiated(fulfilledByType: "Impl") let b: SendableErasedInstantiator<String, any Gadget>"#,
			],
			diagnostics: { host in
				"""
				\(host):9:5: error: `b: SendableErasedInstantiator<String, any Gadget>` on `Host` forwards `String`, and `a: SendableErasedInstantiator<Int, any Gadget>` on `Host` forwards `Int`. `Host` takes one `@Sendable` builder for both, since `Impl` fills each and each returns `any Gadget`, and a builder’s places must forward the same values. Give both the same first generic argument, or name another type in the `fulfilledByType` of one.
				"""
			},
		),
	]

	@Test(arguments: otherValues)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsAtEachPlaceForwardingAnotherValueThanTheFirst_whenPlacesOfOneBuilderForwardOtherValues(otherValues: OtherValues) async {
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			otherValues.diagnostics(fixtures["Feature"]!["Host.swift"])
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(hostDeclarations: otherValues.hostDeclarations, app: [Self.root]),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	/// A remedy an error about places that forward other values names, applied: the places, and what `App` fills them with.
	struct Remedy: CustomTestStringConvertible, Sendable {
		let name: String
		let hostDeclarations: [String]
		let fulfillers: [String]
		let probes: [String]

		var testDescription: String {
			name
		}
	}

	static let remedies = [
		Remedy(
			name: "the same first generic argument",
			hostDeclarations: [
				#"@Instantiated(fulfilledByType: "IntGadget") public let a: ErasedInstantiator<Int, any Gadget>"#,
				#"@Instantiated(fulfilledByType: "IntGadget") public let b: ErasedInstantiator<Int, any Gadget>"#,
			],
			fulfillers: [intGadget],
			probes: ["Root().host.a.instantiate(1)", "Root().host.b.instantiate(2)"],
		),
		Remedy(
			name: "another fulfilledByType",
			hostDeclarations: [
				#"@Instantiated(fulfilledByType: "IntGadget") public let a: ErasedInstantiator<Int, any Gadget>"#,
				#"@Instantiated(fulfilledByType: "NamedGadget") public let b: ErasedInstantiator<String, any Gadget>"#,
			],
			fulfillers: [intGadget, namedGadget],
			probes: ["Root().host.a.instantiate(1)", #"Root().host.b.instantiate("two")"#],
		),
		Remedy(
			name: "nothing, spelled ()",
			hostDeclarations: [
				"@Instantiated let analytics: Analytics",
				#"@Instantiated(fulfilledByType: "DefaultGadget") public let now: any Gadget"#,
				#"@Instantiated(fulfilledByType: "DefaultGadget") public let later: ErasedInstantiator<(), any Gadget>"#,
			],
			fulfillers: [defaultGadget],
			probes: ["Root().host.later.instantiate()"],
		),
		Remedy(
			name: "the @Sendable family's same first generic argument",
			hostDeclarations: [
				#"@Instantiated(fulfilledByType: "IntGadget") public let a: SendableErasedInstantiator<Int, any Gadget>"#,
				#"@Instantiated(fulfilledByType: "IntGadget") public let b: SendableErasedInstantiator<Int, any Gadget>"#,
			],
			fulfillers: [intGadget],
			probes: ["Root().host.a.instantiate(1)", "Root().host.b.instantiate(2)"],
		),
	]

	@Test(arguments: remedies)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsInlineValues_whenRemedyOfPlacesForwardingOtherValuesIsApplied(remedy: Remedy) async throws {
		let modules = Self.modules(hostDeclarations: remedy.hostDeclarations, app: remedy.fulfillers + [Self.root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		try Self.expectCompiles(output)
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(hostDeclarations: remedy.hostDeclarations, featureTypes: remedy.fulfillers, app: [Self.root]), probes: remedy.probes)
	}

	// MARK: Places of other modules

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsInGeneratingModuleAtOuterSeamsProperty_whenInnerSeamOfAnotherModulePassesUpPlaceForwardingAnotherValue(innerSeamIsDeclaredFirst: Bool) async {
		// The inner seam's place is located at `inner`, the property of `Outer` through which `Outer`'s tree reaches it: the
		// build reports in a file of the module it generates, never another module's.
		let innerSeam = "@Instantiated let inner: Inner"
		let ownPlace = #"@Instantiated(fulfilledByType: "Impl") let b: ErasedInstantiator<String, any Gadget>"#
		await assertThrowsMultiModuleError(inModule: "Middle", diagnostics: { fixtures in
			let outer = fixtures["Middle"]!["Outer.swift"]
			return innerSeamIsDeclaredFirst ? """
			\(outer):11:5: error: `b: ErasedInstantiator<String, any Gadget>` on `Outer` forwards `String`, and `a: ErasedInstantiator<Int, any Gadget>` on `Inner` forwards `Int`. `Outer` takes one builder for both, since `Impl` fills each and each returns `any Gadget`, and a builder’s places must forward the same values. Give both the same first generic argument, or name another type in the `fulfilledByType` of one.
			""" : """
			\(outer):11:5: error: `a: ErasedInstantiator<Int, any Gadget>` on `Inner` forwards `Int`, and `b: ErasedInstantiator<String, any Gadget>` on `Outer` forwards `String`. `Outer` takes one builder for both, since `Impl` fills each and each returns `any Gadget`, and a builder’s places must forward the same values. Give both the same first generic argument, or name another type in the `fulfilledByType` of one.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.innerSeamModules(
					innerSeams: ["Inner": [#"@Instantiated(fulfilledByType: "Impl") public let a: ErasedInstantiator<Int, any Gadget>"#]],
					outerDeclarations: innerSeamIsDeclaredFirst ? [innerSeam, ownPlace] : [ownPlace, innerSeam],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsAtSecondInnerSeamsProperty_whenTwoInnerSeamsOfAnotherModulePassUpPlacesForwardingOtherValues() async {
		await assertThrowsMultiModuleError(inModule: "Middle", diagnostics: { fixtures in
			"""
			\(fixtures["Middle"]!["Outer.swift"]):11:5: error: `b: ErasedInstantiator<String, any Gadget>` on `OtherInner` forwards `String`, and `a: ErasedInstantiator<Int, any Gadget>` on `Inner` forwards `Int`. `Outer` takes one builder for both, since `Impl` fills each and each returns `any Gadget`, and a builder’s places must forward the same values. Give both the same first generic argument, or name another type in the `fulfilledByType` of one.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.innerSeamModules(
					innerSeams: [
						"Inner": [#"@Instantiated(fulfilledByType: "Impl") public let a: ErasedInstantiator<Int, any Gadget>"#],
						"OtherInner": [#"@Instantiated(fulfilledByType: "Impl") public let b: ErasedInstantiator<String, any Gadget>"#],
					],
					outerDeclarations: ["@Instantiated let inner: Inner", "@Instantiated let otherInner: OtherInner"],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: ["DefaultService", "ServiceImpl"])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsAtPlaceDeclaredLater_whenPlaceInFillOfInnerSeamsHoleForwardsAnotherValue(fulfillerName: String) async {
		// `Middle` fills `Inner`'s `service` with the fulfiller, whose place `a` is one of `Outer`'s builder, reached through a
		// case for the builder the call fills: it forwards another value than `Outer`'s own place `b`, and the error is at
		// whichever of the two is declared later, by file path.
		await assertThrowsMultiModuleError(inModule: "Middle", diagnostics: { fixtures in
			fulfillerName == "DefaultService" ? """
			\(fixtures["Middle"]!["Outer.swift"]):11:5: error: `b: ErasedInstantiator<String, any Gadget>` on `Outer` forwards `String`, and `a: ErasedInstantiator<Int, any Gadget>` on `DefaultService` forwards `Int`. `Outer` takes one builder for both, since `Impl` fills each and each returns `any Gadget`, and a builder’s places must forward the same values. Give both the same first generic argument, or name another type in the `fulfilledByType` of one.
			""" : """
			\(fixtures["Middle"]!["ServiceImpl.swift"]):9:5: error: `a: ErasedInstantiator<Int, any Gadget>` on `ServiceImpl` forwards `Int`, and `b: ErasedInstantiator<String, any Gadget>` on `Outer` forwards `String`. `Outer` takes one builder for both, since `Impl` fills each and each returns `any Gadget`, and a builder’s places must forward the same values. Give both the same first generic argument, or name another type in the `fulfilledByType` of one.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: Self.featureFiles + [
						"public protocol Service {}",
						seamFixtureType(named: "Inner", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let service: any Service"]),
					]),
					ModuleFixture(name: "Middle", packageName: "Other", swiftFileContent: [
						SafeDIToolSeamBuilderParameterTests.fulfillingType(named: fulfillerName, fulfilling: "Service", declarations: [#"@Instantiated(fulfilledByType: "Impl") public let a: ErasedInstantiator<Int, any Gadget>"#]),
						seamFixtureType(named: "Outer", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let inner: Inner", #"@Instantiated(fulfilledByType: "Impl") let b: ErasedInstantiator<String, any Gadget>"#]),
					].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
					ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let outer: Outer"])].map { "import Feature\nimport Middle\n\n" + $0 }, dependencies: ["Feature", "Middle"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	/// Three declarations, in one file, of places of one builder, as one of the orders of their types, the forwarded type
	/// of each, and how the types and the place's label are named.
	struct PlacesInOneFile: CustomTestStringConvertible, Sendable {
		let forwardedTypeByIndex: [String]
		let typeNames: [String]
		let label: String

		var testDescription: String {
			"\(forwardedTypeByIndex.joined(separator: ", ")) on \(typeNames.joined(separator: ", "))"
		}
	}

	static let placesInOneFile = [
		PlacesInOneFile(forwardedTypeByIndex: ["Int", "Int", "String"], typeNames: ["A", "B", "C"], label: "place"),
		PlacesInOneFile(forwardedTypeByIndex: ["Int", "Int", "String"], typeNames: ["Zed", "Yak", "Xin"], label: "spot"),
		PlacesInOneFile(forwardedTypeByIndex: ["Int", "String", "Double"], typeNames: ["A", "B", "C"], label: "place"),
		PlacesInOneFile(forwardedTypeByIndex: ["Int", "String", "Double"], typeNames: ["Zed", "Yak", "Xin"], label: "spot"),
	]

	@Test(arguments: [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]], placesInOneFile)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesFirstDeclaredPlaceAsReferenceAndReportsEachOtherValue_whenPlacesInOneFileForwardOtherValues(order: [Int], places: PlacesInOneFile) async {
		// The places are declared in `order`, each the only declaration of its type, so the `index`th declared one is at line
		// 7 + 9 × index.
		let placesFile = order.map { index in
			seamFixtureType(named: places.typeNames[index], isFinalClass: true, declarations: [#"@Instantiated(fulfilledByType: "Impl") public let \#(places.label): ErasedInstantiator<\#(places.forwardedTypeByIndex[index]), any Gadget>"#])
		}.joined(separator: "\n\n")
		let reference = order[0]
		func clause(of index: Int) -> String {
			"`\(places.label): ErasedInstantiator<\(places.forwardedTypeByIndex[index]), any Gadget>` on `\(places.typeNames[index])` forwards `\(places.forwardedTypeByIndex[index])`"
		}
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			order.enumerated().filter { places.forwardedTypeByIndex[$0.element] != places.forwardedTypeByIndex[reference] }.map { position, index in
				"\(fixtures["Feature"]!["Places.swift"]):\(7 + 9 * position):5: error: \(clause(of: index)), and \(clause(of: reference)). `Host` takes one builder for both, since `Impl` fills each and each returns `any Gadget`, and a builder’s places must forward the same values. Give both the same first generic argument, or name another type in the `fulfilledByType` of one."
			}.joined(separator: "\n")
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(
						name: "Feature",
						packageName: "Shop",
						swiftFileContent: Self.featureFiles + [seamFixtureType(named: "Host", isSeam: true, isFinalClass: true, declarations: places.typeNames.map { "@Instantiated let \($0.lowercased()): \($0)" })],
						swiftFileContentByFilePath: ["Places.swift": placesFile],
					),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: A seam that keeps its closure over its enum

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsInnerSeamBuildersTakingForwardedValue_whenKeptSeamPassesUpForwardingPlacesOfBothFamilies() async throws {
		let featureTypes = [
			seamFixtureType(named: "Inner", isSeam: true, isFinalClass: true, declarations: ["@Received let analytics: Analytics", "@Instantiated public let part: Instantiator<Panel>", "@Instantiated public let sendablePart: SendableInstantiator<Panel>"]),
			seamFixtureType(named: "Outer", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let navigator: Navigator", "@Instantiated public let inner: Inner"]),
		]
		let modules = Self.modules(featureTypes: featureTypes, app: [Self.defaultPanel, Self.rootOfOuter])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Inner {
		    @frozen nonisolated public enum SafeDIScope_Panel {
		        case part(part_Values, Panel.ForwardedProperties)

		        nonisolated public struct part_Values {
		            public let analytics: Analytics
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let part: (part_Values) -> ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder

		            public init(part: @escaping (part_Values) -> ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
		                self.part = part
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
		                self.part = { _ in __safeDI_builder }
		            }
		        }
		    }

		    @frozen nonisolated public enum SafeDISendableScope_Panel {
		        case sendablePart(Panel.ForwardedProperties)

		        nonisolated public struct sendablePart_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
		            public let sendablePart: @Sendable (sendablePart_Values) -> SendableErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder

		            public init(sendablePart: @escaping @Sendable (sendablePart_Values) -> SendableErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
		                self.sendablePart = sendablePart
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
		                self.sendablePart = { _ in __safeDI_builder }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(analytics: Analytics, panelBuilder: @escaping Instantiator<Panel>.Builder, panelSendableBuilder: @escaping SendableInstantiator<Panel>.Builder) {
		        self.init(__safeDI_analytics: analytics, __safeDI_panelBuilder: .init(__safeDI_noScope: panelBuilder), __safeDI_panelSendableBuilder: .init(__safeDI_noScope: panelSendableBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_analytics analytics: Analytics, __safeDI_panelBuilder: SafeDIScope_Panel.__safeDI_Builder<Panel>, __safeDI_panelSendableBuilder: SafeDISendableScope_Panel.__safeDI_Builder<Panel>) {
		        let part = Instantiator<Panel>(__safeDI_panelBuilder.part(SafeDIScope_Panel.part_Values(analytics: analytics)))
		        let sendablePart = SendableInstantiator<Panel>(__safeDI_panelSendableBuilder.sendablePart(SafeDISendableScope_Panel.sendablePart_Values()))
		        self.init(analytics: analytics, part: part, sendablePart: sendablePart)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_CE2BE999BED711F9 {}
		}

		extension Outer {
		    @frozen public enum SafeDIScope_Panel {
		        case inner(Inner.SafeDIScope_Panel)
		    }

		    @frozen public enum SafeDISendableScope_Panel {
		        case inner_Sendable(Inner.SafeDISendableScope_Panel)
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(analytics: Analytics, panelBuilder: @escaping (SafeDIScope_Panel) -> Panel, panelSendableBuilder: @escaping @Sendable (SafeDISendableScope_Panel) -> Panel) {
		        self.init(__safeDI_analytics: analytics, __safeDI_panelBuilder: panelBuilder, __safeDI_panelSendableBuilder: panelSendableBuilder)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_analytics: @autoclosure @escaping () -> Analytics, __safeDI_panelBuilder: @escaping (SafeDIScope_Panel) -> Panel, __safeDI_panelSendableBuilder: @escaping @Sendable (SafeDISendableScope_Panel) -> Panel) {
		        let analytics = LazilyInstantiated<Analytics>(__safeDI_analytics)
		        let navigator = Navigator()
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_CE2BE999BED711F9.self
		            return Inner(__safeDI_analytics: analytics.instance, __safeDI_panelBuilder: .init(part: { __safeDI_partValues in { forwarded in __safeDI_panelBuilder(.inner(.part(__safeDI_partValues, forwarded))) } }), __safeDI_panelSendableBuilder: .init(sendablePart: { _ in { forwarded in __safeDI_panelSendableBuilder(.inner_Sendable(.sendablePart(forwarded))) } }))
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(navigator: navigator, inner: inner)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_DD82D811C70A37AA {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        let analytics = Analytics()
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_DD82D811C70A37AA.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_panelBuilder_Outer(_ scope: Outer.SafeDIScope_Panel) -> Panel {
		                switch scope {
		                case let .inner(scope): return __safeDI_panelBuilder_Inner(scope)
		                }
		            }
		            func __safeDI_panelBuilder_Inner(_ scope: Inner.SafeDIScope_Panel) -> Panel {
		                switch scope {
		                case let .part(scope, __safeDI_forwarded):
		                    let analytics = scope.analytics
		                    func __safeDI_part(name: String) -> DefaultPanel {
		                        DefaultPanel(name: name, analytics: analytics)
		                    }
		                    return __safeDI_part(name: __safeDI_forwarded)
		                }
		            }
		            @Sendable func __safeDI_panelSendableBuilder_Outer(_ scope: Outer.SafeDISendableScope_Panel) -> Panel {
		                switch scope {
		                case let .inner_Sendable(scope): return __safeDI_panelSendableBuilder_Inner(scope)
		                }
		            }
		            @Sendable func __safeDI_panelSendableBuilder_Inner(_ scope: Inner.SafeDISendableScope_Panel) -> Panel {
		                switch scope {
		                case let .sendablePart(__safeDI_forwarded):
		                    @Sendable func __safeDI_sendablePart(name: String) -> DefaultPanel {
		                        DefaultPanel(name: name, analytics: analytics)
		                    }
		                    return __safeDI_sendablePart(name: __safeDI_forwarded)
		                }
		            }
		            return Outer(__safeDI_analytics: analytics, __safeDI_panelBuilder: __safeDI_panelBuilder_Outer, __safeDI_panelSendableBuilder: __safeDI_panelSendableBuilder_Outer)
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(analytics: analytics, outer: outer)
		    }
		}
		"""])
		try Self.expectCompiles(output)
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(featureTypes: featureTypes + [Self.defaultPanel], app: [Self.rootOfOuter]), probes: [
			#"Root().outer.inner.part.instantiate("one")"#,
			#"Root().outer.inner.sendablePart.instantiate("two")"#,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsInnerSeamBuildersTakingNothing_whenKeptSeamPassesUpErasedPlacesForwardingNothing() async throws {
		let featureTypes = [
			seamFixtureType(named: "Inner", isSeam: true, isFinalClass: true, declarations: [
				"@Received let analytics: Analytics",
				#"@Instantiated(fulfilledByType: "DefaultGadget") public let later: ErasedInstantiator<(), any Gadget>"#,
				#"@Instantiated(fulfilledByType: "DefaultGadget") public let sendableLater: SendableErasedInstantiator<(), any Gadget>"#,
			]),
			seamFixtureType(named: "Outer", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let navigator: Navigator", "@Instantiated public let inner: Inner"]),
		]
		let modules = Self.modules(featureTypes: featureTypes, app: [Self.defaultGadget, Self.rootOfOuter])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Inner {
		    @frozen nonisolated public enum SafeDIScope_DefaultGadget_Gadget {
		        case later(later_Values)

		        nonisolated public struct later_Values {
		            public let analytics: Analytics
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let later: (later_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder

		            public init(later: @escaping (later_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder) {
		                self.later = later
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<(), __safeDI_Built>.Builder) {
		                self.later = { _ in __safeDI_builder }
		            }
		        }
		    }

		    @frozen nonisolated public enum SafeDISendableScope_DefaultGadget_Gadget {
		        case sendableLater

		        nonisolated public struct sendableLater_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
		            public let sendableLater: @Sendable (sendableLater_Values) -> SendableErasedInstantiator<(), __safeDI_Built>.Builder

		            public init(sendableLater: @escaping @Sendable (sendableLater_Values) -> SendableErasedInstantiator<(), __safeDI_Built>.Builder) {
		                self.sendableLater = sendableLater
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<(), __safeDI_Built>.Builder) {
		                self.sendableLater = { _ in __safeDI_builder }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(analytics: Analytics, defaultGadget_GadgetBuilder: @escaping ErasedInstantiator<(), any Gadget>.Builder, defaultGadget_GadgetSendableBuilder: @escaping SendableErasedInstantiator<(), any Gadget>.Builder) {
		        self.init(__safeDI_analytics: analytics, __safeDI_defaultGadget_GadgetBuilder: .init(__safeDI_noScope: defaultGadget_GadgetBuilder), __safeDI_defaultGadget_GadgetSendableBuilder: .init(__safeDI_noScope: defaultGadget_GadgetSendableBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_analytics analytics: Analytics, __safeDI_defaultGadget_GadgetBuilder: SafeDIScope_DefaultGadget_Gadget.__safeDI_Builder<any Gadget>, __safeDI_defaultGadget_GadgetSendableBuilder: SafeDISendableScope_DefaultGadget_Gadget.__safeDI_Builder<any Gadget>) {
		        let later = ErasedInstantiator<(), any Gadget>(__safeDI_defaultGadget_GadgetBuilder.later(SafeDIScope_DefaultGadget_Gadget.later_Values(analytics: analytics)))
		        let sendableLater = SendableErasedInstantiator<(), any Gadget>(__safeDI_defaultGadget_GadgetSendableBuilder.sendableLater(SafeDISendableScope_DefaultGadget_Gadget.sendableLater_Values()))
		        self.init(analytics: analytics, later: later, sendableLater: sendableLater)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_53C7090FF45E9DD2 {}
		}

		extension Outer {
		    @frozen public enum SafeDIScope_DefaultGadget_Gadget {
		        case inner(Inner.SafeDIScope_DefaultGadget_Gadget)
		    }

		    @frozen public enum SafeDISendableScope_DefaultGadget_Gadget {
		        case inner_Sendable(Inner.SafeDISendableScope_DefaultGadget_Gadget)
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(analytics: Analytics, defaultGadget_GadgetBuilder: @escaping (SafeDIScope_DefaultGadget_Gadget) -> any Gadget, defaultGadget_GadgetSendableBuilder: @escaping @Sendable (SafeDISendableScope_DefaultGadget_Gadget) -> any Gadget) {
		        self.init(__safeDI_analytics: analytics, __safeDI_defaultGadget_GadgetBuilder: defaultGadget_GadgetBuilder, __safeDI_defaultGadget_GadgetSendableBuilder: defaultGadget_GadgetSendableBuilder)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_analytics: @autoclosure @escaping () -> Analytics, __safeDI_defaultGadget_GadgetBuilder: @escaping (SafeDIScope_DefaultGadget_Gadget) -> any Gadget, __safeDI_defaultGadget_GadgetSendableBuilder: @escaping @Sendable (SafeDISendableScope_DefaultGadget_Gadget) -> any Gadget) {
		        let analytics = LazilyInstantiated<Analytics>(__safeDI_analytics)
		        let navigator = Navigator()
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_53C7090FF45E9DD2.self
		            return Inner(__safeDI_analytics: analytics.instance, __safeDI_defaultGadget_GadgetBuilder: .init(later: { __safeDI_laterValues in { _ in __safeDI_defaultGadget_GadgetBuilder(.inner(.later(__safeDI_laterValues))) } }), __safeDI_defaultGadget_GadgetSendableBuilder: .init(sendableLater: { _ in { _ in __safeDI_defaultGadget_GadgetSendableBuilder(.inner_Sendable(.sendableLater)) } }))
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(navigator: navigator, inner: inner)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_07508FED33FD805D {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        let analytics = Analytics()
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_07508FED33FD805D.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_defaultGadget_GadgetBuilder_Outer(_ scope: Outer.SafeDIScope_DefaultGadget_Gadget) -> any Gadget {
		                switch scope {
		                case let .inner(scope): return __safeDI_defaultGadget_GadgetBuilder_Inner(scope)
		                }
		            }
		            func __safeDI_defaultGadget_GadgetBuilder_Inner(_ scope: Inner.SafeDIScope_DefaultGadget_Gadget) -> any Gadget {
		                switch scope {
		                case let .later(scope):
		                    let analytics = scope.analytics
		                    func __safeDI_later() -> DefaultGadget {
		                        DefaultGadget(analytics: analytics)
		                    }
		                    return __safeDI_later()
		                }
		            }
		            @Sendable func __safeDI_defaultGadget_GadgetSendableBuilder_Outer(_ scope: Outer.SafeDISendableScope_DefaultGadget_Gadget) -> any Gadget {
		                switch scope {
		                case let .inner_Sendable(scope): return __safeDI_defaultGadget_GadgetSendableBuilder_Inner(scope)
		                }
		            }
		            @Sendable func __safeDI_defaultGadget_GadgetSendableBuilder_Inner(_ scope: Inner.SafeDISendableScope_DefaultGadget_Gadget) -> any Gadget {
		                switch scope {
		                case .sendableLater:
		                    @Sendable func __safeDI_sendableLater() -> DefaultGadget {
		                        DefaultGadget(analytics: analytics)
		                    }
		                    return __safeDI_sendableLater()
		                }
		            }
		            return Outer(__safeDI_analytics: analytics, __safeDI_defaultGadget_GadgetBuilder: __safeDI_defaultGadget_GadgetBuilder_Outer, __safeDI_defaultGadget_GadgetSendableBuilder: __safeDI_defaultGadget_GadgetSendableBuilder_Outer)
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(analytics: analytics, outer: outer)
		    }
		}
		"""])
		try Self.expectCompiles(output)
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(featureTypes: featureTypes + [Self.defaultGadget], app: [Self.rootOfOuter]), probes: [
			"Root().outer.inner.later.instantiate()",
			"Root().outer.inner.sendableLater.instantiate()",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsSwitchedSeamsForwardingBuilderWithLevelFunctions_whenKeptSeamFillsItOutright() async throws {
		// `Outer` keeps its closure over its enum for `Inner`'s `service`, which `Inner` passes up, and fills `Inner`'s place
		// `part` itself, with `DefaultPanel`: no case of `Outer`'s carries `Inner`'s scope for it, so `Outer` hands `Inner` the
		// level functions any calling module writes, whose builder takes the title `part` forwards.
		let innerSeamFiles = [
			"public protocol Service {}",
			seamFixtureType(named: "Inner", isSeam: true, isFinalClass: true, declarations: ["@Received let analytics: Analytics", "@Instantiated public let service: any Service", "@Instantiated public let part: Instantiator<Panel>"]),
		]
		let outer = seamFixtureType(named: "Outer", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let navigator: Navigator", "@Instantiated public let inner: Inner"])
		let liveService = SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LiveService", fulfilling: "Service", declarations: [])
		let probe = """
		func navigatorIsFreedWhilePartLives() -> Bool {
		    weak var weakNavigator: Navigator?
		    var part: Instantiator<Panel>?
		    do {
		        let outer = Root().outer
		        weakNavigator = outer.navigator
		        part = outer.inner.part
		    }
		    if let part {
		        _ = part.instantiate("one")
		        _ = part.instantiate("two")
		    }
		    return withExtendedLifetime(part) { weakNavigator == nil }
		}
		"""
		func modules(feature: [String] = [], middle: [String], app: [String]) -> [ModuleFixture] {
			[
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: Self.featureFiles + innerSeamFiles + feature),
				ModuleFixture(name: "Middle", packageName: "Other", swiftFileContent: middle.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
				ModuleFixture(name: "App", packageName: "Other", swiftFileContent: app.map { "import Feature\nimport Middle\n\n" + $0 }, dependencies: ["Feature", "Middle"]),
			]
		}
		let seamModules = modules(middle: [Self.defaultPanel, outer], app: [liveService, Self.rootOfOuter, probe])
		let output = try await executeSafeDIToolMultiModuleTest(modules: seamModules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Middle"]?.generatedFiles == ["Middle.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Outer {
		    @frozen public enum SafeDIScope_Service {
		        case inner(Inner.SafeDIScope_Service)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_analytics: @autoclosure @escaping () -> Analytics, __safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
		        let analytics = LazilyInstantiated<Analytics>(__safeDI_analytics)
		        let navigator = Navigator()
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_2BCAAD392DCFF05A.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_panelBuilder_Inner_part(analytics: Analytics) -> Instantiator<Panel>.Builder {
		                func __safeDI_part(name: String) -> DefaultPanel {
		                    DefaultPanel(name: name, analytics: analytics)
		                }
		                return { forwarded in __safeDI_part(name: forwarded) }
		            }
		            func __safeDI_panelBuilder_Inner() -> Inner.SafeDIScope_Panel.__safeDI_Builder<Panel> {
		                .init(part: { values in __safeDI_panelBuilder_Inner_part(analytics: values.analytics) })
		            }
		            return Inner(__safeDI_analytics: analytics.instance, __safeDI_panelBuilder: __safeDI_panelBuilder_Inner(), __safeDI_serviceBuilder: .init(service: { __safeDI_serviceValues in __safeDI_serviceBuilder(.inner(.service(__safeDI_serviceValues))) }))
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(navigator: navigator, inner: inner)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_7764F5DC75EFEEA8 {}
		}
		"""])
		try Self.expectCompiles(output)
		// Every fulfiller in `Feature`, which builds `Inner`'s tree inline.
		try await expectValuesEqualVisibleBuild(output, modules: seamModules, visibleModules: modules(feature: [Self.defaultPanel, liveService], middle: [outer], app: [Self.rootOfOuter, probe]), probes: [
			#"Root().outer.inner.part.instantiate("title")"#,
			"navigatorIsFreedWhilePartLives()",
		])
	}

	// MARK: A level that opens again

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsEachDepthsValueToPlace_whenForwardingPlaceIsOnLevelThatOpensAgain() async throws {
		let (modules, visibleModules) = Self.screenModules(throughKeptSeam: false)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Home {
		    @frozen nonisolated public enum SafeDIScope_LiveGadget_Gadget {
		        case screenBuilder(screenBuilder_Values, SafeDIScope_LiveGadget_Gadget.Screen_Scope)

		        nonisolated public struct screenBuilder_Values {}

		        @frozen nonisolated public enum Screen_Scope {
		            case panel(panel_Values, String)
		            indirect case next(next_Values, SafeDIScope_LiveGadget_Gadget.Screen_Scope)

		            nonisolated public struct panel_Values {
		                public let id: Int
		            }

		            nonisolated public struct next_Values {
		                public let id: Int
		                public let panel: ErasedInstantiator<String, any Gadget>
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let panel: (panel_Values) -> ErasedInstantiator<String, __safeDI_Built>.Builder
		                public let next: (next_Values) -> SafeDIScope_LiveGadget_Gadget.Screen_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(panel: @escaping (panel_Values) -> ErasedInstantiator<String, __safeDI_Built>.Builder, next: @escaping (next_Values) -> SafeDIScope_LiveGadget_Gadget.Screen_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.panel = panel
		                    self.next = next
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<String, __safeDI_Built>.Builder) {
		                    self.panel = { _ in __safeDI_builder }
		                    self.next = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let screenBuilder: (screenBuilder_Values) -> SafeDIScope_LiveGadget_Gadget.Screen_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(screenBuilder: @escaping (screenBuilder_Values) -> SafeDIScope_LiveGadget_Gadget.Screen_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.screenBuilder = screenBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<String, __safeDI_Built>.Builder) {
		                self.screenBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(liveGadget_GadgetBuilder: @escaping ErasedInstantiator<String, any Gadget>.Builder) {
		        self.init(__safeDI_liveGadget_GadgetBuilder: .init(__safeDI_noScope: liveGadget_GadgetBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_liveGadget_GadgetBuilder: SafeDIScope_LiveGadget_Gadget.__safeDI_Builder<any Gadget>) {
		        let __safeDI_liveGadget_GadgetBuilder_screenBuilder = __safeDI_liveGadget_GadgetBuilder.screenBuilder(SafeDIScope_LiveGadget_Gadget.screenBuilder_Values())
		        func __safeDI_screenBuilder(id: Int) -> Screen {
		            let panel = ErasedInstantiator<String, any Gadget>(__safeDI_liveGadget_GadgetBuilder_screenBuilder.panel(SafeDIScope_LiveGadget_Gadget.Screen_Scope.panel_Values(id: id)))
		            let __safeDI_liveGadget_GadgetBuilder_next = __safeDI_liveGadget_GadgetBuilder_screenBuilder.next(SafeDIScope_LiveGadget_Gadget.Screen_Scope.next_Values(id: id, panel: panel))
		            func __safeDI_next(id: Int) -> Screen {
		                let panel = ErasedInstantiator<String, any Gadget>(__safeDI_liveGadget_GadgetBuilder_next.panel(SafeDIScope_LiveGadget_Gadget.Screen_Scope.panel_Values(id: id)))
		                let next = Instantiator<Screen> {
		                    __safeDI_next(id: $0)
		                }
		                return Screen(id: id, panel: panel, next: next)
		            }
		            let next = Instantiator<Screen> {
		                __safeDI_next(id: $0)
		            }
		            return Screen(id: id, panel: panel, next: next)
		        }
		        let screenBuilder = Instantiator<Screen> {
		            __safeDI_screenBuilder(id: $0)
		        }
		        self.init(screenBuilder: screenBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_DC6A8484651460B6 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_DC6A8484651460B6.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_liveGadget_GadgetBuilder_Home_Screen_Scope_panel(id: Int) -> ErasedInstantiator<String, any Gadget>.Builder {
		                func __safeDI_panel(title: String) -> LiveGadget {
		                    LiveGadget(title: title, id: id)
		                }
		                return { forwarded in __safeDI_panel(title: forwarded) }
		            }
		            func __safeDI_liveGadget_GadgetBuilder_Home() -> Home.SafeDIScope_LiveGadget_Gadget.__safeDI_Builder<any Gadget> {
		                .init(screenBuilder: { _ in __safeDI_liveGadget_GadgetBuilder_Home_Screen_Scope() })
		            }
		            func __safeDI_liveGadget_GadgetBuilder_Home_Screen_Scope() -> Home.SafeDIScope_LiveGadget_Gadget.Screen_Scope.__safeDI_Builder<any Gadget> {
		                .init(panel: { values in __safeDI_liveGadget_GadgetBuilder_Home_Screen_Scope_panel(id: values.id) }, next: { _ in __safeDI_liveGadget_GadgetBuilder_Home_Screen_Scope() })
		            }
		            return Home(__safeDI_liveGadget_GadgetBuilder: __safeDI_liveGadget_GadgetBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		"""])
		try Self.expectCompiles(output)
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: visibleModules, probes: [
			#"Root().home.screenBuilder.instantiate(1).next.instantiate(2).next.instantiate(3).panel.instantiate("t")"#,
			"firstScreenIsFreed(holdingDepth: 4)",
			"firstScreenIsFreed(holdingDepth: 8)",
		])
		try await expectProbes(of: output, modules: modules, describe: ["firstScreenIsFreed(holdingDepth: 4)": "Bool true", "firstScreenIsFreed(holdingDepth: 8)": "Bool true"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_rebuildsCaseAroundForwardedValueOncePerFirstOpening_whenKeptSeamPassesUpForwardingPlaceOnLevelThatOpensAgain() async throws {
		// A kept `Outer` passes `Home`'s place up through one conversion function per first opening of `Screen`'s level, whose
		// place's member hands `Outer`'s builder the case rebuilt around the value it forwards.
		let (modules, visibleModules) = Self.screenModules(throughKeptSeam: true)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Home {
		    @frozen nonisolated public enum SafeDIScope_LiveGadget_Gadget {
		        case screenBuilder(screenBuilder_Values, SafeDIScope_LiveGadget_Gadget.Screen_Scope)

		        nonisolated public struct screenBuilder_Values {}

		        @frozen nonisolated public enum Screen_Scope {
		            case panel(panel_Values, String)
		            indirect case next(next_Values, SafeDIScope_LiveGadget_Gadget.Screen_Scope)

		            nonisolated public struct panel_Values {
		                public let id: Int
		            }

		            nonisolated public struct next_Values {
		                public let id: Int
		                public let panel: ErasedInstantiator<String, any Gadget>
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let panel: (panel_Values) -> ErasedInstantiator<String, __safeDI_Built>.Builder
		                public let next: (next_Values) -> SafeDIScope_LiveGadget_Gadget.Screen_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(panel: @escaping (panel_Values) -> ErasedInstantiator<String, __safeDI_Built>.Builder, next: @escaping (next_Values) -> SafeDIScope_LiveGadget_Gadget.Screen_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.panel = panel
		                    self.next = next
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<String, __safeDI_Built>.Builder) {
		                    self.panel = { _ in __safeDI_builder }
		                    self.next = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let screenBuilder: (screenBuilder_Values) -> SafeDIScope_LiveGadget_Gadget.Screen_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(screenBuilder: @escaping (screenBuilder_Values) -> SafeDIScope_LiveGadget_Gadget.Screen_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.screenBuilder = screenBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<String, __safeDI_Built>.Builder) {
		                self.screenBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(liveGadget_GadgetBuilder: @escaping ErasedInstantiator<String, any Gadget>.Builder) {
		        self.init(__safeDI_liveGadget_GadgetBuilder: .init(__safeDI_noScope: liveGadget_GadgetBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_liveGadget_GadgetBuilder: SafeDIScope_LiveGadget_Gadget.__safeDI_Builder<any Gadget>) {
		        let __safeDI_liveGadget_GadgetBuilder_screenBuilder = __safeDI_liveGadget_GadgetBuilder.screenBuilder(SafeDIScope_LiveGadget_Gadget.screenBuilder_Values())
		        func __safeDI_screenBuilder(id: Int) -> Screen {
		            let panel = ErasedInstantiator<String, any Gadget>(__safeDI_liveGadget_GadgetBuilder_screenBuilder.panel(SafeDIScope_LiveGadget_Gadget.Screen_Scope.panel_Values(id: id)))
		            let __safeDI_liveGadget_GadgetBuilder_next = __safeDI_liveGadget_GadgetBuilder_screenBuilder.next(SafeDIScope_LiveGadget_Gadget.Screen_Scope.next_Values(id: id, panel: panel))
		            func __safeDI_next(id: Int) -> Screen {
		                let panel = ErasedInstantiator<String, any Gadget>(__safeDI_liveGadget_GadgetBuilder_next.panel(SafeDIScope_LiveGadget_Gadget.Screen_Scope.panel_Values(id: id)))
		                let next = Instantiator<Screen> {
		                    __safeDI_next(id: $0)
		                }
		                return Screen(id: id, panel: panel, next: next)
		            }
		            let next = Instantiator<Screen> {
		                __safeDI_next(id: $0)
		            }
		            return Screen(id: id, panel: panel, next: next)
		        }
		        let screenBuilder = Instantiator<Screen> {
		            __safeDI_screenBuilder(id: $0)
		        }
		        self.init(screenBuilder: screenBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_DC6A8484651460B6 {}
		}

		extension Outer {
		    @frozen public enum SafeDIScope_LiveGadget_Gadget {
		        case home(Home.SafeDIScope_LiveGadget_Gadget)
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(liveGadget_GadgetBuilder: @escaping (SafeDIScope_LiveGadget_Gadget) -> any Gadget) {
		        self.init(__safeDI_liveGadget_GadgetBuilder: liveGadget_GadgetBuilder)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_liveGadget_GadgetBuilder: @escaping (SafeDIScope_LiveGadget_Gadget) -> any Gadget) {
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_DC6A8484651460B6.self
		            func __safeDI_liveGadget_GadgetBuilder_Home(_ __safeDI_liveGadget_GadgetBuilder_Home_wrap: @escaping (Home.SafeDIScope_LiveGadget_Gadget) -> Home.SafeDIScope_LiveGadget_Gadget) -> Home.SafeDIScope_LiveGadget_Gadget.__safeDI_Builder<any Gadget> {
		                .init(screenBuilder: { __safeDI_screenBuilderValues in __safeDI_liveGadget_GadgetBuilder_Home_Screen_Scope({ __safeDI_liveGadget_GadgetBuilder_Home_wrap(.screenBuilder(__safeDI_screenBuilderValues, $0)) }) })
		            }
		            func __safeDI_liveGadget_GadgetBuilder_Home_Screen_Scope(_ __safeDI_liveGadget_GadgetBuilder_Home_Screen_Scope_wrap: @escaping (Home.SafeDIScope_LiveGadget_Gadget.Screen_Scope) -> Home.SafeDIScope_LiveGadget_Gadget) -> Home.SafeDIScope_LiveGadget_Gadget.Screen_Scope.__safeDI_Builder<any Gadget> {
		                .init(panel: { __safeDI_panelValues in { forwarded in __safeDI_liveGadget_GadgetBuilder(.home(__safeDI_liveGadget_GadgetBuilder_Home_Screen_Scope_wrap(.panel(__safeDI_panelValues, forwarded)))) } }, next: { _ in __safeDI_liveGadget_GadgetBuilder_Home_Screen_Scope(__safeDI_liveGadget_GadgetBuilder_Home_Screen_Scope_wrap) })
		            }
		            return Home(__safeDI_liveGadget_GadgetBuilder: __safeDI_liveGadget_GadgetBuilder_Home({ $0 }))
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_B6A7D07D647AC717 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_B6A7D07D647AC717.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_liveGadget_GadgetBuilder_Outer(_ scope: Outer.SafeDIScope_LiveGadget_Gadget) -> any Gadget {
		                switch scope {
		                case let .home(scope): return __safeDI_liveGadget_GadgetBuilder_Home(scope)
		                }
		            }
		            func __safeDI_liveGadget_GadgetBuilder_Home(_ scope: Home.SafeDIScope_LiveGadget_Gadget) -> any Gadget {
		                switch scope {
		                case let .screenBuilder(_, scope): return __safeDI_liveGadget_GadgetBuilder_Home_Screen_Scope(scope)
		                }
		            }
		            func __safeDI_liveGadget_GadgetBuilder_Home_Screen_Scope(_ scope: Home.SafeDIScope_LiveGadget_Gadget.Screen_Scope) -> any Gadget {
		                switch scope {
		                case let .panel(scope, __safeDI_forwarded):
		                    let id = scope.id
		                    func __safeDI_panel(title: String) -> LiveGadget {
		                        LiveGadget(title: title, id: id)
		                    }
		                    return __safeDI_panel(title: __safeDI_forwarded)
		                case let .next(_, scope): return __safeDI_liveGadget_GadgetBuilder_Home_Screen_Scope(scope)
		                }
		            }
		            return Outer(__safeDI_liveGadget_GadgetBuilder: __safeDI_liveGadget_GadgetBuilder_Outer)
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(outer: outer)
		    }
		}
		"""])
		try Self.expectCompiles(output)
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: visibleModules, probes: [
			#"Root().outer.home.screenBuilder.instantiate(1).next.instantiate(2).next.instantiate(3).panel.instantiate("t")"#,
			"firstScreenIsFreed(holdingDepth: 4)",
			"firstScreenIsFreed(holdingDepth: 8)",
		])
		try await expectProbes(of: output, modules: modules, describe: ["firstScreenIsFreed(holdingDepth: 4)": "Bool true", "firstScreenIsFreed(holdingDepth: 8)": "Bool true"])
	}

	// MARK: Names

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsUsersTypeNamedBuiltApartFromBuilderStructsParameter_whenPlacesForwardBuilt() async throws {
		let featureTypes = ["public struct Built: Sendable {\n    public init(value: Int) {\n        self.value = value\n    }\n\n    public let value: Int\n}"]
		let hostDeclarations = [
			#"@Instantiated(fulfilledByType: "BuiltGadget") public let built: ErasedInstantiator<Built, any Gadget>"#,
			#"@Instantiated(fulfilledByType: "PairBuiltGadget") public let pair: SendableErasedInstantiator<(built: Built, count: Int), any Gadget>"#,
		]
		let fulfillers = [
			seamFixtureType(named: "BuiltGadget", declarations: ["@Forwarded let built: Built"], conformances: ", Gadget"),
			seamFixtureType(named: "PairBuiltGadget", declarations: ["@Forwarded let built: Built", "@Forwarded let count: Int"], conformances: ", Gadget"),
		]
		let modules = Self.modules(hostDeclarations: hostDeclarations, featureTypes: featureTypes, app: fulfillers + [Self.root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen nonisolated public enum SafeDIScope_BuiltGadget_Gadget {
		        case built(built_Values, Built)

		        nonisolated public struct built_Values {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let built: (built_Values) -> ErasedInstantiator<Built, __safeDI_Built>.Builder

		            public init(built: @escaping (built_Values) -> ErasedInstantiator<Built, __safeDI_Built>.Builder) {
		                self.built = built
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Built, __safeDI_Built>.Builder) {
		                self.built = { _ in __safeDI_builder }
		            }
		        }
		    }

		    @frozen nonisolated public enum SafeDISendableScope_PairBuiltGadget_Gadget {
		        case pair((built: Built, count: Int))

		        nonisolated public struct pair_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
		            public let pair: @Sendable (pair_Values) -> SendableErasedInstantiator<(built: Built, count: Int), __safeDI_Built>.Builder

		            public init(pair: @escaping @Sendable (pair_Values) -> SendableErasedInstantiator<(built: Built, count: Int), __safeDI_Built>.Builder) {
		                self.pair = pair
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<(built: Built, count: Int), __safeDI_Built>.Builder) {
		                self.pair = { _ in __safeDI_builder }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(builtGadget_GadgetBuilder: @escaping ErasedInstantiator<Built, any Gadget>.Builder, pairBuiltGadget_GadgetSendableBuilder: @escaping SendableErasedInstantiator<(built: Built, count: Int), any Gadget>.Builder) {
		        self.init(__safeDI_builtGadget_GadgetBuilder: .init(__safeDI_noScope: builtGadget_GadgetBuilder), __safeDI_pairBuiltGadget_GadgetSendableBuilder: .init(__safeDI_noScope: pairBuiltGadget_GadgetSendableBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_builtGadget_GadgetBuilder: SafeDIScope_BuiltGadget_Gadget.__safeDI_Builder<any Gadget>, __safeDI_pairBuiltGadget_GadgetSendableBuilder: SafeDISendableScope_PairBuiltGadget_Gadget.__safeDI_Builder<any Gadget>) {
		        let built = ErasedInstantiator<Built, any Gadget>(__safeDI_builtGadget_GadgetBuilder.built(SafeDIScope_BuiltGadget_Gadget.built_Values()))
		        let pair = SendableErasedInstantiator<(built: Built, count: Int), any Gadget>(__safeDI_pairBuiltGadget_GadgetSendableBuilder.pair(SafeDISendableScope_PairBuiltGadget_Gadget.pair_Values()))
		        self.init(built: built, pair: pair)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_98A13D52CE9A19C3 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_98A13D52CE9A19C3.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_builtGadget_GadgetBuilder_Host_built() -> ErasedInstantiator<Built, any Gadget>.Builder {
		                func __safeDI_built(built: Built) -> BuiltGadget {
		                    BuiltGadget(built: built)
		                }
		                return { forwarded in __safeDI_built(built: forwarded) }
		            }
		            @Sendable nonisolated func __safeDI_pairBuiltGadget_GadgetSendableBuilder_Host_pair() -> SendableErasedInstantiator<(built: Built, count: Int), any Gadget>.Builder {
		                @Sendable nonisolated func __safeDI_pair(built: Built, count: Int) -> PairBuiltGadget {
		                    PairBuiltGadget(built: built, count: count)
		                }
		                return { forwarded in __safeDI_pair(built: forwarded.built, count: forwarded.count) }
		            }
		            func __safeDI_builtGadget_GadgetBuilder_Host() -> Host.SafeDIScope_BuiltGadget_Gadget.__safeDI_Builder<any Gadget> {
		                .init(built: { _ in __safeDI_builtGadget_GadgetBuilder_Host_built() })
		            }
		            @Sendable nonisolated func __safeDI_pairBuiltGadget_GadgetSendableBuilder_Host() -> Host.SafeDISendableScope_PairBuiltGadget_Gadget.__safeDI_Builder<any Gadget> {
		                .init(pair: { _ in __safeDI_pairBuiltGadget_GadgetSendableBuilder_Host_pair() })
		            }
		            return Host(__safeDI_builtGadget_GadgetBuilder: __safeDI_builtGadget_GadgetBuilder_Host(), __safeDI_pairBuiltGadget_GadgetSendableBuilder: __safeDI_pairBuiltGadget_GadgetSendableBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		try Self.expectCompiles(output)
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(hostDeclarations: hostDeclarations, featureTypes: featureTypes + fulfillers, app: [Self.root]), probes: [
			"Root().host.built.instantiate(Built(value: 1))",
			"Root().host.pair.instantiate((built: Built(value: 2), count: 3))",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsUsersTypeNamedBuiltApartFromBuilderStructsParameter_whenInstantiatorsBuildBuilt() async throws {
		let featureTypes = [
			"""
			open class Built: Instantiable, @unchecked Sendable {
			    public typealias ForwardedProperties = String

			    public init(name: String) {
			        self.name = name
			    }

			    public let name: String
			}
			""",
		]
		let hostDeclarations = ["@Instantiated public let held: Instantiator<Built>", "@Instantiated public let sendableHeld: SendableInstantiator<Built>"]
		let fulfillers = [
			"""
			@Instantiable(fulfillingAdditionalTypes: [Built.self], conformsElsewhere: true)
			public final class DefaultBuilt: Built, @unchecked Sendable {
			    public init(title: String) {
			        self.title = title
			        super.init(name: title)
			    }

			    @Forwarded let title: String
			}
			""",
		]
		let modules = Self.modules(hostDeclarations: hostDeclarations, featureTypes: featureTypes, app: fulfillers + [Self.root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen nonisolated public enum SafeDIScope_Built {
		        case held(held_Values, Built.ForwardedProperties)

		        nonisolated public struct held_Values {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let held: (held_Values) -> ErasedInstantiator<Built.ForwardedProperties, __safeDI_Built>.Builder

		            public init(held: @escaping (held_Values) -> ErasedInstantiator<Built.ForwardedProperties, __safeDI_Built>.Builder) {
		                self.held = held
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Built.ForwardedProperties, __safeDI_Built>.Builder) {
		                self.held = { _ in __safeDI_builder }
		            }
		        }
		    }

		    @frozen nonisolated public enum SafeDISendableScope_Built {
		        case sendableHeld(Built.ForwardedProperties)

		        nonisolated public struct sendableHeld_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
		            public let sendableHeld: @Sendable (sendableHeld_Values) -> SendableErasedInstantiator<Built.ForwardedProperties, __safeDI_Built>.Builder

		            public init(sendableHeld: @escaping @Sendable (sendableHeld_Values) -> SendableErasedInstantiator<Built.ForwardedProperties, __safeDI_Built>.Builder) {
		                self.sendableHeld = sendableHeld
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<Built.ForwardedProperties, __safeDI_Built>.Builder) {
		                self.sendableHeld = { _ in __safeDI_builder }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(builtBuilder: @escaping Instantiator<Built>.Builder, builtSendableBuilder: @escaping SendableInstantiator<Built>.Builder) {
		        self.init(__safeDI_builtBuilder: .init(__safeDI_noScope: builtBuilder), __safeDI_builtSendableBuilder: .init(__safeDI_noScope: builtSendableBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_builtBuilder: SafeDIScope_Built.__safeDI_Builder<Built>, __safeDI_builtSendableBuilder: SafeDISendableScope_Built.__safeDI_Builder<Built>) {
		        let held = Instantiator<Built>(__safeDI_builtBuilder.held(SafeDIScope_Built.held_Values()))
		        let sendableHeld = SendableInstantiator<Built>(__safeDI_builtSendableBuilder.sendableHeld(SafeDISendableScope_Built.sendableHeld_Values()))
		        self.init(held: held, sendableHeld: sendableHeld)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_D811878096AC4563 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_D811878096AC4563.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_builtBuilder_Host_held() -> Instantiator<Built>.Builder {
		                func __safeDI_held(title: String) -> DefaultBuilt {
		                    DefaultBuilt(title: title)
		                }
		                return { forwarded in __safeDI_held(title: forwarded) }
		            }
		            @Sendable nonisolated func __safeDI_builtSendableBuilder_Host_sendableHeld() -> SendableInstantiator<Built>.Builder {
		                @Sendable nonisolated func __safeDI_sendableHeld(title: String) -> DefaultBuilt {
		                    DefaultBuilt(title: title)
		                }
		                return { forwarded in __safeDI_sendableHeld(title: forwarded) }
		            }
		            func __safeDI_builtBuilder_Host() -> Host.SafeDIScope_Built.__safeDI_Builder<Built> {
		                .init(held: { _ in __safeDI_builtBuilder_Host_held() })
		            }
		            @Sendable nonisolated func __safeDI_builtSendableBuilder_Host() -> Host.SafeDISendableScope_Built.__safeDI_Builder<Built> {
		                .init(sendableHeld: { _ in __safeDI_builtSendableBuilder_Host_sendableHeld() })
		            }
		            return Host(__safeDI_builtBuilder: __safeDI_builtBuilder_Host(), __safeDI_builtSendableBuilder: __safeDI_builtSendableBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		try Self.expectCompiles(output)
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(hostDeclarations: hostDeclarations, featureTypes: featureTypes + fulfillers, app: [Self.root]), probes: [
			#"Root().host.held.instantiate("one").name"#,
			#"Root().host.sendableHeld.instantiate("two").name"#,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesBuildersForwardedValueApartFromCycleParameter_whenLazyCycleOfFillPassesValueLabeledForwarded() async throws {
		// `LoopPanel` builds itself again through `Tangle`, whose `forwarded` `MarkReader` reads only if available, so its
		// builder function takes `forwarded`, which the first build reads from `Host`'s level: the closure the place
		// function returns names the value `held` forwards apart from it.
		let hostDeclarations = ["@Instantiated let forwarded: Mark", "@Instantiated public let held: Instantiator<Panel>"]
		let markFiles = [seamFixtureType(named: "Mark", isFinalClass: true, declarations: [])]
		let loopFiles = [
			"""
			@Instantiable(fulfillingAdditionalTypes: [Panel.self], conformsElsewhere: true)
			public final class LoopPanel: Panel, @unchecked Sendable {
			    public init(name: String, reader: MarkReader, tangleBuilder: Instantiator<Tangle>) {
			        self.name = name
			        self.reader = reader
			        self.tangleBuilder = tangleBuilder
			        super.init(title: name)
			    }

			    @Forwarded let name: String
			    @Instantiated let reader: MarkReader
			    @Instantiated let tangleBuilder: Instantiator<Tangle>
			}
			""",
			seamFixtureType(named: "MarkReader", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let forwarded: Mark?"]),
			seamFixtureType(named: "Tangle", isFinalClass: true, declarations: ["@Instantiated let forwarded: Mark", "@Instantiated let held: Instantiator<Panel>"]),
		]
		let modules = Self.modules(hostDeclarations: hostDeclarations, featureTypes: markFiles, app: loopFiles + [Self.root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_CCB2A408B42921B2.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_panelBuilder_Host_held(forwarded: Mark) -> Instantiator<Panel>.Builder {
		                func __safeDI_held(name: String, forwarded: Mark?) -> LoopPanel {
		                    let reader = MarkReader(forwarded: forwarded)
		                    func __safeDI_tangleBuilder() -> Tangle {
		                        let forwarded = Mark()
		                        let held = Instantiator<Panel> {
		                            __safeDI_held(name: $0, forwarded: forwarded)
		                        }
		                        return Tangle(forwarded: forwarded, held: held)
		                    }
		                    let tangleBuilder = Instantiator<Tangle>(__safeDI_tangleBuilder)
		                    return LoopPanel(name: name, reader: reader, tangleBuilder: tangleBuilder)
		                }
		                return { forwarded_ in __safeDI_held(name: forwarded_, forwarded: forwarded) }
		            }
		            func __safeDI_panelBuilder_Host() -> Host.SafeDIScope_Panel.__safeDI_Builder<Panel> {
		                .init(held: { values in __safeDI_panelBuilder_Host_held(forwarded: values.forwarded) })
		            }
		            return Host(__safeDI_panelBuilder: __safeDI_panelBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		""")
		try Self.expectCompiles(output)
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(hostDeclarations: hostDeclarations, featureTypes: markFiles + loopFiles, app: [Self.root]), probes: [
			#"Root().host.held.instantiate("one")"#,
		])
	}

	// MARK: What the route holds

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsPlaceFunctionLazilyInstantiatedValueItReadsInstanceOf_whenForwardingFillReadsLazilyHeldValue() async throws {
		let featureTypes = [
			"nonisolated(unsafe) public var themesCreated = 0",
			"""
			@Instantiable
			public final class Theme: Instantiable, Sendable {
			    public init() {
			        themesCreated += 1
			    }
			}
			""",
		]
		let hostDeclarations = [
			"@Instantiated public let theme: LazilyInstantiated<Theme>",
			#"@Instantiated(fulfilledByType: "ThemedGadget") public let panel: ErasedInstantiator<String, any Gadget>"#,
		]
		let fulfillers = [seamFixtureType(named: "ThemedGadget", declarations: ["@Forwarded let title: String", "@Received let theme: Theme"], conformances: ", Gadget")]
		let probe = """
		func themesCreatedBeforeAndAfterPanel() -> String {
		    let host = Root().host
		    let before = themesCreated
		    _ = host.panel.instantiate("title")
		    return "\\(themesCreated - before) of \\(themesCreated)"
		}
		"""
		let modules = Self.modules(hostDeclarations: hostDeclarations, featureTypes: featureTypes, app: fulfillers + [Self.root, probe])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen nonisolated public enum SafeDIScope_ThemedGadget_Gadget {
		        case panel(panel_Values, String)

		        nonisolated public struct panel_Values {
		            public let theme: LazilyInstantiated<Theme>
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let panel: (panel_Values) -> ErasedInstantiator<String, __safeDI_Built>.Builder

		            public init(panel: @escaping (panel_Values) -> ErasedInstantiator<String, __safeDI_Built>.Builder) {
		                self.panel = panel
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<String, __safeDI_Built>.Builder) {
		                self.panel = { _ in __safeDI_builder }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(themedGadget_GadgetBuilder: @escaping ErasedInstantiator<String, any Gadget>.Builder) {
		        self.init(__safeDI_themedGadget_GadgetBuilder: .init(__safeDI_noScope: themedGadget_GadgetBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_themedGadget_GadgetBuilder: SafeDIScope_ThemedGadget_Gadget.__safeDI_Builder<any Gadget>) {
		        func __safeDI_theme() -> Theme {
		            Theme()
		        }
		        let theme = LazilyInstantiated<Theme>(__safeDI_theme)
		        let panel = ErasedInstantiator<String, any Gadget>(__safeDI_themedGadget_GadgetBuilder.panel(SafeDIScope_ThemedGadget_Gadget.panel_Values(theme: theme)))
		        self.init(theme: theme, panel: panel)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_67D7840B1BDF2C29 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_67D7840B1BDF2C29.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_themedGadget_GadgetBuilder_Host_panel(theme: LazilyInstantiated<Theme>) -> ErasedInstantiator<String, any Gadget>.Builder {
		                func __safeDI_panel(title: String) -> ThemedGadget {
		                    ThemedGadget(title: title, theme: theme.instance)
		                }
		                return { forwarded in __safeDI_panel(title: forwarded) }
		            }
		            func __safeDI_themedGadget_GadgetBuilder_Host() -> Host.SafeDIScope_ThemedGadget_Gadget.__safeDI_Builder<any Gadget> {
		                .init(panel: { values in __safeDI_themedGadget_GadgetBuilder_Host_panel(theme: values.theme) })
		            }
		            return Host(__safeDI_themedGadget_GadgetBuilder: __safeDI_themedGadget_GadgetBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		try Self.expectCompiles(output)
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(hostDeclarations: hostDeclarations, featureTypes: featureTypes + fulfillers, app: [Self.root, probe]), probes: [
			"themesCreatedBeforeAndAfterPanel()",
		])
	}

	// MARK: Both families over one level

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_typesSharedLevelForItsOwnFamily_whenBothFamiliesReachPlainLevelHoldingInstantiator() async throws {
		let featureTypes = [seamFixtureType(named: "Owner", isFinalClass: true, declarations: ["@Instantiated public let held: Instantiator<EmptyPanel>"])]
		let hostDeclarations = [
			"@Received let analytics: Analytics",
			"@Instantiated public let now: EmptyPanel",
			"@Instantiated public let owner: Owner",
			"@Instantiated public let ownerBuilder: SendableInstantiator<Owner>",
		]
		let modules = Self.modules(hostDeclarations: hostDeclarations, featureTypes: featureTypes, app: [Self.defaultEmptyPanel, Self.rootInstantiatingAnalytics])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen nonisolated public enum SafeDIScope_EmptyPanel {
		        case now(now_Values)
		        case owner(owner_Values, SafeDIScope_EmptyPanel.Owner_Scope)

		        nonisolated public struct now_Values {
		            public let analytics: Analytics
		        }

		        nonisolated public struct owner_Values {
		            public let analytics: Analytics
		            public let now: EmptyPanel
		        }

		        @frozen nonisolated public enum Owner_Scope {
		            case held(held_Values, EmptyPanel.ForwardedProperties)

		            nonisolated public struct held_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let held: (held_Values) -> ErasedInstantiator<EmptyPanel.ForwardedProperties, __safeDI_Built>.Builder

		                public init(held: @escaping (held_Values) -> ErasedInstantiator<EmptyPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		                    self.held = held
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<EmptyPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		                    self.held = { _ in __safeDI_builder }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let now: (now_Values) -> __safeDI_Built
		            public let owner: (owner_Values) -> SafeDIScope_EmptyPanel.Owner_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(now: @escaping (now_Values) -> __safeDI_Built, owner: @escaping (owner_Values) -> SafeDIScope_EmptyPanel.Owner_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.now = now
		                self.owner = owner
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.now = { _ in __safeDI_builder() }
		                self.owner = { _ in .init(__safeDI_noScope: { _ in __safeDI_builder() }) }
		            }
		        }
		    }

		    @frozen nonisolated public enum SafeDISendableScope_EmptyPanel {
		        case ownerBuilder(SafeDIScope_EmptyPanel.Owner_Scope)

		        nonisolated public struct ownerBuilder_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
		            public let ownerBuilder: @Sendable (ownerBuilder_Values) -> SafeDIScope_EmptyPanel.Owner_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(ownerBuilder: @escaping @Sendable (ownerBuilder_Values) -> SafeDIScope_EmptyPanel.Owner_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.ownerBuilder = ownerBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<EmptyPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		                self.ownerBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(analytics: Analytics, emptyPanelBuilder: @escaping () -> EmptyPanel, emptyPanelSendableBuilder: @escaping SendableInstantiator<EmptyPanel>.Builder) {
		        self.init(__safeDI_analytics: analytics, __safeDI_emptyPanelBuilder: .init(__safeDI_noScope: emptyPanelBuilder), __safeDI_emptyPanelSendableBuilder: .init(__safeDI_noScope: emptyPanelSendableBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_analytics analytics: Analytics, __safeDI_emptyPanelBuilder: SafeDIScope_EmptyPanel.__safeDI_Builder<EmptyPanel>, __safeDI_emptyPanelSendableBuilder: SafeDISendableScope_EmptyPanel.__safeDI_Builder<EmptyPanel>) {
		        let now: EmptyPanel = __safeDI_emptyPanelBuilder.now(SafeDIScope_EmptyPanel.now_Values(analytics: analytics))
		        let __safeDI_emptyPanelBuilder_owner = __safeDI_emptyPanelBuilder.owner(SafeDIScope_EmptyPanel.owner_Values(analytics: analytics, now: now))
		        func __safeDI_owner() -> Owner {
		            let held = Instantiator<EmptyPanel>(__safeDI_emptyPanelBuilder_owner.held(SafeDIScope_EmptyPanel.Owner_Scope.held_Values()))
		            return Owner(held: held)
		        }
		        let owner: Owner = __safeDI_owner()
		        @Sendable nonisolated func __safeDI_ownerBuilder() -> Owner {
		            let __safeDI_emptyPanelSendableBuilder_ownerBuilder = __safeDI_emptyPanelSendableBuilder.ownerBuilder(SafeDISendableScope_EmptyPanel.ownerBuilder_Values())
		            let held = Instantiator<EmptyPanel>(__safeDI_emptyPanelSendableBuilder_ownerBuilder.held(SafeDIScope_EmptyPanel.Owner_Scope.held_Values()))
		            return Owner(held: held)
		        }
		        let ownerBuilder = SendableInstantiator<Owner>(__safeDI_ownerBuilder)
		        self.init(analytics: analytics, now: now, owner: owner, ownerBuilder: ownerBuilder)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_DCB1A084C0CDBC62 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        let analytics = Analytics()
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_DCB1A084C0CDBC62.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            @Sendable nonisolated func __safeDI_emptyPanelBuilder_Host_Owner_Scope_held(analytics: Analytics) -> Instantiator<EmptyPanel>.Builder {
		                func __safeDI_held() -> DefaultEmptyPanel {
		                    DefaultEmptyPanel(analytics: analytics)
		                }
		                return { _ in __safeDI_held() }
		            }
		            func __safeDI_emptyPanelBuilder_Host() -> Host.SafeDIScope_EmptyPanel.__safeDI_Builder<EmptyPanel> {
		                .init(
		                    now: { scope in
		                        let analytics = scope.analytics
		                        let now: EmptyPanel = DefaultEmptyPanel(analytics: analytics)
		                        return now
		                    },
		                    owner: { values in __safeDI_emptyPanelBuilder_Host_Owner_Scope(analytics: values.analytics) }
		                )
		            }
		            @Sendable nonisolated func __safeDI_emptyPanelBuilder_Host_Owner_Scope(analytics: Analytics) -> Host.SafeDIScope_EmptyPanel.Owner_Scope.__safeDI_Builder<EmptyPanel> {
		                .init(held: { _ in __safeDI_emptyPanelBuilder_Host_Owner_Scope_held(analytics: analytics) })
		            }
		            @Sendable nonisolated func __safeDI_emptyPanelSendableBuilder_Host() -> Host.SafeDISendableScope_EmptyPanel.__safeDI_Builder<EmptyPanel> {
		                .init(ownerBuilder: { _ in __safeDI_emptyPanelBuilder_Host_Owner_Scope(analytics: analytics) })
		            }
		            return Host(__safeDI_analytics: analytics, __safeDI_emptyPanelBuilder: __safeDI_emptyPanelBuilder_Host(), __safeDI_emptyPanelSendableBuilder: __safeDI_emptyPanelSendableBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(analytics: analytics, host: host)
		    }
		}
		"""])
		try Self.expectCompiles(output)
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(hostDeclarations: hostDeclarations, featureTypes: featureTypes + [Self.defaultEmptyPanel], app: [Self.rootInstantiatingAnalytics]), probes: [
			"Root().host.owner.held.instantiate()",
			"Root().host.ownerBuilder.instantiate().held.instantiate()",
		])
	}

	// MARK: A type whose own ForwardedProperties is more than its fulfiller forwards

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsPlacesOfForwardedPropertiesBuilderOfEmptyTuple_whenErasedPlaceForwardingNothingIsBesideThem() async throws {
		// `StringPanel` declares that it forwards a `String`, and its fulfiller forwards nothing: the builder takes `()`, so
		// the places of `StringPanel.ForwardedProperties`, on its level and on the level beneath, are handed one that ignores
		// what they forward. Inline builds no control here: `Instantiator<StringPanel>` of a function that takes nothing does
		// not compile.
		let modules = Self.stringPanelModules(hostDeclarations: [
			#"@Instantiated(fulfilledByType: "StringPanel") public let later: ErasedInstantiator<(), StringPanel>"#,
			#"@Instantiated(fulfilledByType: "StringPanel") public let same: ErasedInstantiator<StringPanel.ForwardedProperties, StringPanel>"#,
			"@Instantiated public let owner: Owner",
		])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen nonisolated public enum SafeDIScope_StringPanel {
		        case later(later_Values)
		        case same(same_Values, StringPanel.ForwardedProperties)
		        case owner(owner_Values, SafeDIScope_StringPanel.Owner_Scope)

		        nonisolated public struct later_Values {}

		        nonisolated public struct same_Values {
		            public let later: ErasedInstantiator<(), StringPanel>
		        }

		        nonisolated public struct owner_Values {
		            public let later: ErasedInstantiator<(), StringPanel>
		            public let same: ErasedInstantiator<StringPanel.ForwardedProperties, StringPanel>
		        }

		        @frozen nonisolated public enum Owner_Scope {
		            case held(held_Values, StringPanel.ForwardedProperties)

		            nonisolated public struct held_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let held: (held_Values) -> ErasedInstantiator<StringPanel.ForwardedProperties, __safeDI_Built>.Builder

		                public init(held: @escaping (held_Values) -> ErasedInstantiator<StringPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		                    self.held = held
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<StringPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		                    self.held = { _ in __safeDI_builder }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let later: (later_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder
		            public let same: (same_Values) -> ErasedInstantiator<StringPanel.ForwardedProperties, __safeDI_Built>.Builder
		            public let owner: (owner_Values) -> SafeDIScope_StringPanel.Owner_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(later: @escaping (later_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder, same: @escaping (same_Values) -> ErasedInstantiator<StringPanel.ForwardedProperties, __safeDI_Built>.Builder, owner: @escaping (owner_Values) -> SafeDIScope_StringPanel.Owner_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.later = later
		                self.same = same
		                self.owner = owner
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<(), __safeDI_Built>.Builder) {
		                self.later = { _ in __safeDI_builder }
		                self.same = { _ in { _ in __safeDI_builder(()) } }
		                self.owner = { _ in .init(__safeDI_noScope: { _ in __safeDI_builder(()) }) }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(stringPanelBuilder: @escaping ErasedInstantiator<(), StringPanel>.Builder) {
		        self.init(__safeDI_stringPanelBuilder: .init(__safeDI_noScope: stringPanelBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_stringPanelBuilder: SafeDIScope_StringPanel.__safeDI_Builder<StringPanel>) {
		        let later = ErasedInstantiator<(), StringPanel>(__safeDI_stringPanelBuilder.later(SafeDIScope_StringPanel.later_Values()))
		        let same = ErasedInstantiator<StringPanel.ForwardedProperties, StringPanel>(__safeDI_stringPanelBuilder.same(SafeDIScope_StringPanel.same_Values(later: later)))
		        let __safeDI_stringPanelBuilder_owner = __safeDI_stringPanelBuilder.owner(SafeDIScope_StringPanel.owner_Values(later: later, same: same))
		        func __safeDI_owner() -> Owner {
		            let held = Instantiator<StringPanel>(__safeDI_stringPanelBuilder_owner.held(SafeDIScope_StringPanel.Owner_Scope.held_Values()))
		            return Owner(held: held)
		        }
		        let owner: Owner = __safeDI_owner()
		        self.init(later: later, same: same, owner: owner)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_F468402A66A45816 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_F468402A66A45816.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_stringPanelBuilder_Host_later() -> ErasedInstantiator<(), StringPanel>.Builder {
		                func __safeDI_later() -> DefaultStringPanel {
		                    DefaultStringPanel()
		                }
		                return { _ in __safeDI_later() }
		            }
		            func __safeDI_stringPanelBuilder_Host_same() -> ErasedInstantiator<StringPanel.ForwardedProperties, StringPanel>.Builder {
		                func __safeDI_same() -> DefaultStringPanel {
		                    DefaultStringPanel()
		                }
		                return { _ in __safeDI_same() }
		            }
		            func __safeDI_stringPanelBuilder_Host_Owner_Scope_held() -> Instantiator<StringPanel>.Builder {
		                func __safeDI_held() -> DefaultStringPanel {
		                    DefaultStringPanel()
		                }
		                return { _ in __safeDI_held() }
		            }
		            func __safeDI_stringPanelBuilder_Host() -> Host.SafeDIScope_StringPanel.__safeDI_Builder<StringPanel> {
		                .init(later: { _ in __safeDI_stringPanelBuilder_Host_later() }, same: { _ in __safeDI_stringPanelBuilder_Host_same() }, owner: { _ in __safeDI_stringPanelBuilder_Host_Owner_Scope() })
		            }
		            func __safeDI_stringPanelBuilder_Host_Owner_Scope() -> Host.SafeDIScope_StringPanel.Owner_Scope.__safeDI_Builder<StringPanel> {
		                .init(held: { _ in __safeDI_stringPanelBuilder_Host_Owner_Scope_held() })
		            }
		            return Host(__safeDI_stringPanelBuilder: __safeDI_stringPanelBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		try Self.expectCompiles(output)
		try await expectProbes(of: output, modules: modules, describe: [
			"Root().host.later.instantiate() is DefaultStringPanel": "Bool true",
			#"Root().host.same.instantiate("ignored") is DefaultStringPanel"#: "Bool true",
			#"Root().host.owner.held.instantiate("ignored") is DefaultStringPanel"#: "Bool true",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsSharedPlainLevelBuilderOfEmptyTuple_whenSendableErasedPlaceForwardingNothingIsAboveInstantiatorOfForwardedProperties() async throws {
		let modules = Self.stringPanelModules(hostDeclarations: [
			#"@Instantiated(fulfilledByType: "StringPanel") public let later: SendableErasedInstantiator<(), StringPanel>"#,
			"@Instantiated public let ownerBuilder: SendableInstantiator<Owner>",
		])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen nonisolated public enum SafeDIScope_StringPanel {
		        @frozen nonisolated public enum Owner_Scope {
		            case held(held_Values, StringPanel.ForwardedProperties)

		            nonisolated public struct held_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let held: (held_Values) -> ErasedInstantiator<StringPanel.ForwardedProperties, __safeDI_Built>.Builder

		                public init(held: @escaping (held_Values) -> ErasedInstantiator<StringPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		                    self.held = held
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<StringPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		                    self.held = { _ in __safeDI_builder }
		                }
		            }
		        }
		    }

		    @frozen nonisolated public enum SafeDISendableScope_StringPanel {
		        case later
		        case ownerBuilder(SafeDIScope_StringPanel.Owner_Scope)

		        nonisolated public struct later_Values: Sendable {}

		        nonisolated public struct ownerBuilder_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
		            public let later: @Sendable (later_Values) -> SendableErasedInstantiator<(), __safeDI_Built>.Builder
		            public let ownerBuilder: @Sendable (ownerBuilder_Values) -> SafeDIScope_StringPanel.Owner_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(later: @escaping @Sendable (later_Values) -> SendableErasedInstantiator<(), __safeDI_Built>.Builder, ownerBuilder: @escaping @Sendable (ownerBuilder_Values) -> SafeDIScope_StringPanel.Owner_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.later = later
		                self.ownerBuilder = ownerBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<(), __safeDI_Built>.Builder) {
		                self.later = { _ in __safeDI_builder }
		                self.ownerBuilder = { _ in .init(__safeDI_noScope: { _ in __safeDI_builder(()) }) }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(stringPanelSendableBuilder: @escaping SendableErasedInstantiator<(), StringPanel>.Builder) {
		        self.init(__safeDI_stringPanelSendableBuilder: .init(__safeDI_noScope: stringPanelSendableBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_stringPanelSendableBuilder: SafeDISendableScope_StringPanel.__safeDI_Builder<StringPanel>) {
		        let later = SendableErasedInstantiator<(), StringPanel>(__safeDI_stringPanelSendableBuilder.later(SafeDISendableScope_StringPanel.later_Values()))
		        @Sendable nonisolated func __safeDI_ownerBuilder() -> Owner {
		            let __safeDI_stringPanelSendableBuilder_ownerBuilder = __safeDI_stringPanelSendableBuilder.ownerBuilder(SafeDISendableScope_StringPanel.ownerBuilder_Values())
		            let held = Instantiator<StringPanel>(__safeDI_stringPanelSendableBuilder_ownerBuilder.held(SafeDIScope_StringPanel.Owner_Scope.held_Values()))
		            return Owner(held: held)
		        }
		        let ownerBuilder = SendableInstantiator<Owner>(__safeDI_ownerBuilder)
		        self.init(later: later, ownerBuilder: ownerBuilder)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_DFB23EACC4F96C85 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_DFB23EACC4F96C85.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            @Sendable nonisolated func __safeDI_stringPanelSendableBuilder_Host_later() -> SendableErasedInstantiator<(), StringPanel>.Builder {
		                @Sendable nonisolated func __safeDI_later() -> DefaultStringPanel {
		                    DefaultStringPanel()
		                }
		                return { _ in __safeDI_later() }
		            }
		            @Sendable nonisolated func __safeDI_stringPanelSendableBuilder_Host_Owner_Scope_held() -> Instantiator<StringPanel>.Builder {
		                func __safeDI_held() -> DefaultStringPanel {
		                    DefaultStringPanel()
		                }
		                return { _ in __safeDI_held() }
		            }
		            @Sendable nonisolated func __safeDI_stringPanelSendableBuilder_Host() -> Host.SafeDISendableScope_StringPanel.__safeDI_Builder<StringPanel> {
		                .init(later: { _ in __safeDI_stringPanelSendableBuilder_Host_later() }, ownerBuilder: { _ in __safeDI_stringPanelBuilder_Host_Owner_Scope() })
		            }
		            @Sendable nonisolated func __safeDI_stringPanelBuilder_Host_Owner_Scope() -> Host.SafeDIScope_StringPanel.Owner_Scope.__safeDI_Builder<StringPanel> {
		                .init(held: { _ in __safeDI_stringPanelSendableBuilder_Host_Owner_Scope_held() })
		            }
		            return Host(__safeDI_stringPanelSendableBuilder: __safeDI_stringPanelSendableBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		try Self.expectCompiles(output)
		try await expectProbes(of: output, modules: modules, describe: [
			"Root().host.later.instantiate() is DefaultStringPanel": "Bool true",
			#"Root().host.ownerBuilder.instantiate().held.instantiate("ignored") is DefaultStringPanel"#: "Bool true",
		])
	}

	// MARK: The calling module's check of an erased instantiator

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsErasedInstantiatorOfForwardedPropertiesOfFilledType_whenOneModuleBuildsItInline() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.featureFiles + [
				Self.defaultPanel,
				seamFixtureType(named: "Host", isRoot: true, isFinalClass: true, declarations: [
					"@Instantiated let analytics: Analytics",
					#"@Instantiated(fulfilledByType: "Panel") let erased: ErasedInstantiator<Panel.ForwardedProperties, Panel>"#,
				]),
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.dependencyTreeFiles == [
			"Host+SafeDI.swift": generatedFileHeader + """
			extension Host {
			    public convenience init() {
			        let analytics = Analytics()
			        func __safeDI_erased(name: String) -> DefaultPanel {
			            DefaultPanel(name: name, analytics: analytics)
			        }
			        let erased = ErasedInstantiator<Panel.ForwardedProperties, Panel> {
			            __safeDI_erased(name: $0)
			        }
			        self.init(analytics: analytics, erased: erased)
			    }
			}
			""",
		])
	}

	// MARK: Code a person writes

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_compilesHandWrittenBuilders_whenPersonCallsReadableInitializerWithEachForm() async throws {
		let hostDeclarations = ["@Instantiated let analytics: Analytics", "@Instantiated public let held: Instantiator<Panel>", "@Instantiated public let pair: Instantiator<PairPanel>"]
		let handWritten = """
		public final class HandPanel: Panel, @unchecked Sendable {
		    public init(name: String) {
		        super.init(title: name)
		    }
		}

		public final class HandPairPanel: PairPanel, @unchecked Sendable {
		    public init(count: Int, name: String) {
		        self.count = count
		        self.name = name
		        super.init()
		    }

		    public let count: Int
		    public let name: String
		}

		func makeHosts() -> [Host] {
		    let storedPanelBuilder: Instantiator<Panel>.Builder = { name in HandPanel(name: name) }
		    let storedPairBuilder: Instantiator<PairPanel>.Builder = { HandPairPanel(count: $0.count, name: $0.name) }
		    return [
		        Host(pairPanelBuilder: { (count, name) in HandPairPanel(count: count, name: name) }, panelBuilder: { name in HandPanel(name: name) }),
		        Host(pairPanelBuilder: { HandPairPanel(count: $0.count, name: $0.name) }, panelBuilder: HandPanel.init),
		        Host(pairPanelBuilder: storedPairBuilder, panelBuilder: storedPanelBuilder),
		    ]
		}
		"""
		let modules = Self.modules(hostDeclarations: hostDeclarations, app: [Self.defaultPanel, Self.defaultPairPanel, Self.root, handWritten])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen nonisolated public enum SafeDIScope_PairPanel {
		        case pair(pair_Values, PairPanel.ForwardedProperties)

		        nonisolated public struct pair_Values {
		            public let analytics: Analytics
		            public let held: Instantiator<Panel>
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let pair: (pair_Values) -> ErasedInstantiator<PairPanel.ForwardedProperties, __safeDI_Built>.Builder

		            public init(pair: @escaping (pair_Values) -> ErasedInstantiator<PairPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		                self.pair = pair
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<PairPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		                self.pair = { _ in __safeDI_builder }
		            }
		        }
		    }

		    @frozen nonisolated public enum SafeDIScope_Panel {
		        case held(held_Values, Panel.ForwardedProperties)

		        nonisolated public struct held_Values {
		            public let analytics: Analytics
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let held: (held_Values) -> ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder

		            public init(held: @escaping (held_Values) -> ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
		                self.held = held
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
		                self.held = { _ in __safeDI_builder }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(pairPanelBuilder: @escaping Instantiator<PairPanel>.Builder, panelBuilder: @escaping Instantiator<Panel>.Builder) {
		        self.init(__safeDI_pairPanelBuilder: .init(__safeDI_noScope: pairPanelBuilder), __safeDI_panelBuilder: .init(__safeDI_noScope: panelBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_pairPanelBuilder: SafeDIScope_PairPanel.__safeDI_Builder<PairPanel>, __safeDI_panelBuilder: SafeDIScope_Panel.__safeDI_Builder<Panel>) {
		        let analytics = Analytics()
		        let held = Instantiator<Panel>(__safeDI_panelBuilder.held(SafeDIScope_Panel.held_Values(analytics: analytics)))
		        let pair = Instantiator<PairPanel>(__safeDI_pairPanelBuilder.pair(SafeDIScope_PairPanel.pair_Values(analytics: analytics, held: held)))
		        self.init(analytics: analytics, held: held, pair: pair)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_4AE5B5A6C466ABEB {}
		}
		"""])
		try Self.expectCompiles(output)
		try await expectProbes(of: output, modules: modules, describe: [
			#"makeHosts().map { $0.held.instantiate("name").title }"#: """
			Array<String>
			  0: String "name"
			  1: String "name"
			  2: String "name"
			""",
		])
	}

	// MARK: Isolation

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_compilesInModulesDefaultingToMainActor_whenMainActorSeamHoldsForwardingPlacesOfBothFamilies() async throws {
		let feature = [
			"""
			nonisolated open class MainPanel: Instantiable, @unchecked Sendable {
			    public typealias ForwardedProperties = String

			    public init() {}
			}
			""",
			"""
			@MainActor
			@Instantiable(generateDependencyTree: true)
			public final class Host: Instantiable {
			    public init(held: Instantiator<MainPanel>, sendableHeld: SendableInstantiator<MainPanel>) {
			        self.held = held
			        self.sendableHeld = sendableHeld
			    }

			    @Instantiated public let held: Instantiator<MainPanel>
			    @Instantiated public let sendableHeld: SendableInstantiator<MainPanel>
			}
			""",
		]
		let app = [
			"""
			@Instantiable(fulfillingAdditionalTypes: [MainPanel.self], conformsElsewhere: true)
			nonisolated public final class DefaultMainPanel: MainPanel, @unchecked Sendable {
			    public init(name: String) {
			        self.name = name
			        super.init()
			    }

			    @Forwarded let name: String
			}
			""",
			"""
			@MainActor
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(host: Host) {
			        self.host = host
			    }

			    @Instantiated public let host: Host
			}
			""",
		]
		let mainActorByDefault = SafeDIToolSeamBuilderStructMatrixTests.mainActorByDefault
		let modules = [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature, swiftFileContentByFilePath: plainDependencyTreeInitializersConfiguration, compilerSettings: mainActorByDefault),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: app.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"], compilerSettings: mainActorByDefault),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen nonisolated public enum SafeDIScope_MainPanel {
		        case held(held_Values, MainPanel.ForwardedProperties)

		        nonisolated public struct held_Values {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let held: (held_Values) -> ErasedInstantiator<MainPanel.ForwardedProperties, __safeDI_Built>.Builder

		            public init(held: @escaping (held_Values) -> ErasedInstantiator<MainPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		                self.held = held
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<MainPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		                self.held = { _ in __safeDI_builder }
		            }
		        }
		    }

		    @frozen nonisolated public enum SafeDISendableScope_MainPanel {
		        case sendableHeld(MainPanel.ForwardedProperties)

		        nonisolated public struct sendableHeld_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
		            public let sendableHeld: @Sendable (sendableHeld_Values) -> SendableErasedInstantiator<MainPanel.ForwardedProperties, __safeDI_Built>.Builder

		            public init(sendableHeld: @escaping @Sendable (sendableHeld_Values) -> SendableErasedInstantiator<MainPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		                self.sendableHeld = sendableHeld
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<MainPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		                self.sendableHeld = { _ in __safeDI_builder }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(mainPanelBuilder: @escaping Instantiator<MainPanel>.Builder, mainPanelSendableBuilder: @escaping SendableInstantiator<MainPanel>.Builder) {
		        self.init(__safeDI_mainPanelBuilder: .init(__safeDI_noScope: mainPanelBuilder), __safeDI_mainPanelSendableBuilder: .init(__safeDI_noScope: mainPanelSendableBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_mainPanelBuilder: SafeDIScope_MainPanel.__safeDI_Builder<MainPanel>, __safeDI_mainPanelSendableBuilder: SafeDISendableScope_MainPanel.__safeDI_Builder<MainPanel>) {
		        let held = Instantiator<MainPanel>(__safeDI_mainPanelBuilder.held(SafeDIScope_MainPanel.held_Values()))
		        let sendableHeld = SendableInstantiator<MainPanel>(__safeDI_mainPanelSendableBuilder.sendableHeld(SafeDISendableScope_MainPanel.sendableHeld_Values()))
		        self.init(held: held, sendableHeld: sendableHeld)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_59180E402C6F265D {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_59180E402C6F265D.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_mainPanelBuilder_Host_held() -> Instantiator<MainPanel>.Builder {
		                func __safeDI_held(name: String) -> DefaultMainPanel {
		                    DefaultMainPanel(name: name)
		                }
		                return { forwarded in __safeDI_held(name: forwarded) }
		            }
		            @Sendable nonisolated func __safeDI_mainPanelSendableBuilder_Host_sendableHeld() -> SendableInstantiator<MainPanel>.Builder {
		                @Sendable nonisolated func __safeDI_sendableHeld(name: String) -> DefaultMainPanel {
		                    DefaultMainPanel(name: name)
		                }
		                return { forwarded in __safeDI_sendableHeld(name: forwarded) }
		            }
		            func __safeDI_mainPanelBuilder_Host() -> Host.SafeDIScope_MainPanel.__safeDI_Builder<MainPanel> {
		                .init(held: { _ in __safeDI_mainPanelBuilder_Host_held() })
		            }
		            @Sendable nonisolated func __safeDI_mainPanelSendableBuilder_Host() -> Host.SafeDISendableScope_MainPanel.__safeDI_Builder<MainPanel> {
		                .init(sendableHeld: { _ in __safeDI_mainPanelSendableBuilder_Host_sendableHeld() })
		            }
		            return Host(__safeDI_mainPanelBuilder: __safeDI_mainPanelBuilder_Host(), __safeDI_mainPanelSendableBuilder: __safeDI_mainPanelSendableBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		try await expectCompiles(output, inlineControl: [ModuleFixture(name: "App", packageName: "Other", swiftFileContent: inlineFixture(feature + app), compilerSettings: mainActorByDefault)])
	}

	// MARK: Access

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesInternalLevelByItsIdentifier_whenPublicSeamsForwardingPlaceIsOnInternalType() async throws {
		let feature = Self.featureFiles + [
			"""
			@Instantiable
			struct Owner: Instantiable {
			    init(held: Instantiator<Panel>) {
			        self.held = held
			    }

			    @Instantiated let held: Instantiator<Panel>
			}
			""",
			"""
			@Instantiable(generateDependencyTree: true)
			public final class Host: Instantiable {
			    init(analytics: Analytics, owner: Owner) {
			        self.analytics = analytics
			        self.owner = owner
			    }

			    @Instantiated let analytics: Analytics
			    @Instantiated let owner: Owner
			}
			""",
		]
		let modules = [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature, swiftFileContentByFilePath: plainDependencyTreeInitializersConfiguration),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [Self.defaultPanel, Self.root].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen nonisolated public enum SafeDIScope_Panel {
		        case owner(owner_Values, SafeDIScope_Panel.Owner_Scope)

		        nonisolated public struct owner_Values {
		            public let analytics: Analytics
		        }

		        @frozen nonisolated public enum Owner_Scope {
		            case held(held_Values, Panel.ForwardedProperties)

		            nonisolated public struct held_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let held: (held_Values) -> ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder

		                public init(held: @escaping (held_Values) -> ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
		                    self.held = held
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
		                    self.held = { _ in __safeDI_builder }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let owner: (owner_Values) -> SafeDIScope_Panel.Owner_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(owner: @escaping (owner_Values) -> SafeDIScope_Panel.Owner_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.owner = owner
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
		                self.owner = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(panelBuilder: @escaping Instantiator<Panel>.Builder) {
		        self.init(__safeDI_panelBuilder: .init(__safeDI_noScope: panelBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_panelBuilder: SafeDIScope_Panel.__safeDI_Builder<Panel>) {
		        let analytics = Analytics()
		        let __safeDI_panelBuilder_owner = __safeDI_panelBuilder.owner(SafeDIScope_Panel.owner_Values(analytics: analytics))
		        func __safeDI_owner() -> Owner {
		            let held = Instantiator<Panel>(__safeDI_panelBuilder_owner.held(SafeDIScope_Panel.Owner_Scope.held_Values()))
		            return Owner(held: held)
		        }
		        let owner: Owner = __safeDI_owner()
		        self.init(analytics: analytics, owner: owner)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_1FBAE61BBABF95D2 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_1FBAE61BBABF95D2.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_panelBuilder_Host_Owner_Scope_held(analytics: Analytics) -> Instantiator<Panel>.Builder {
		                func __safeDI_held(name: String) -> DefaultPanel {
		                    DefaultPanel(name: name, analytics: analytics)
		                }
		                return { forwarded in __safeDI_held(name: forwarded) }
		            }
		            func __safeDI_panelBuilder_Host() -> Host.SafeDIScope_Panel.__safeDI_Builder<Panel> {
		                .init(owner: { values in __safeDI_panelBuilder_Host_Owner_Scope(analytics: values.analytics) })
		            }
		            func __safeDI_panelBuilder_Host_Owner_Scope(analytics: Analytics) -> Host.SafeDIScope_Panel.Owner_Scope.__safeDI_Builder<Panel> {
		                .init(held: { _ in __safeDI_panelBuilder_Host_Owner_Scope_held(analytics: analytics) })
		            }
		            return Host(__safeDI_panelBuilder: __safeDI_panelBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		try Self.expectCompiles(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesBuilderAtPackageTier_whenPackageSeamsPlaceForwardsPackageType() async throws {
		let feature = Self.featureFiles + [
			"package struct Token: Sendable {\n    package init() {}\n}",
			"""
			@Instantiable(generateDependencyTree: true)
			package final class Host: Instantiable {
			    package init(erased: ErasedInstantiator<Token, any Gadget>) {
			        self.erased = erased
			    }

			    @Instantiated(fulfilledByType: "TokenGadget") package let erased: ErasedInstantiator<Token, any Gadget>
			}
			""",
		]
		let app = [
			"@Instantiable\npackage struct TokenGadget: Instantiable, Gadget {\n    package init(token: Token) {\n        self.token = token\n    }\n\n    @Forwarded let token: Token\n}",
			"@Instantiable(isRoot: true)\npackage final class Root: Instantiable {\n    package init(host: Host) {\n        self.host = host\n    }\n\n    @Instantiated package let host: Host\n}",
		]
		let modules = [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature, swiftFileContentByFilePath: plainDependencyTreeInitializersConfiguration),
			ModuleFixture(name: "App", packageName: "Shop", swiftFileContent: app.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen nonisolated public enum SafeDIScope_TokenGadget_Gadget {
		        case erased(erased_Values, Token)

		        nonisolated public struct erased_Values {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let erased: (erased_Values) -> ErasedInstantiator<Token, __safeDI_Built>.Builder

		            public init(erased: @escaping (erased_Values) -> ErasedInstantiator<Token, __safeDI_Built>.Builder) {
		                self.erased = erased
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Token, __safeDI_Built>.Builder) {
		                self.erased = { _ in __safeDI_builder }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    package convenience init(tokenGadget_GadgetBuilder: @escaping ErasedInstantiator<Token, any Gadget>.Builder) {
		        self.init(__safeDI_tokenGadget_GadgetBuilder: .init(__safeDI_noScope: tokenGadget_GadgetBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    package convenience init(__safeDI_tokenGadget_GadgetBuilder: SafeDIScope_TokenGadget_Gadget.__safeDI_Builder<any Gadget>) {
		        let erased = ErasedInstantiator<Token, any Gadget>(__safeDI_tokenGadget_GadgetBuilder.erased(SafeDIScope_TokenGadget_Gadget.erased_Values()))
		        self.init(erased: erased)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_75DE63A00786B844 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_75DE63A00786B844.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_tokenGadget_GadgetBuilder_Host_erased() -> ErasedInstantiator<Token, any Gadget>.Builder {
		                func __safeDI_erased(token: Token) -> TokenGadget {
		                    TokenGadget(token: token)
		                }
		                return { forwarded in __safeDI_erased(token: forwarded) }
		            }
		            func __safeDI_tokenGadget_GadgetBuilder_Host() -> Host.SafeDIScope_TokenGadget_Gadget.__safeDI_Builder<any Gadget> {
		                .init(erased: { _ in __safeDI_tokenGadget_GadgetBuilder_Host_erased() })
		            }
		            return Host(__safeDI_tokenGadget_GadgetBuilder: __safeDI_tokenGadget_GadgetBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		try Self.expectCompiles(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsTierOmitsBuilderPrintingWrapperBuilder_whenPlaceForwardsTypeNarrowerThanSeam() async {
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Host.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Host`: its generated `public` initializer, which `Host`’s `public` access requires, cannot take `secretGadget_GadgetBuilder: @escaping ErasedInstantiator<Secret, any Gadget>.Builder`, the builder for `Host`’s `erased: ErasedInstantiator<Secret, any Gadget>`, which no @Instantiable declaration that module `Feature` can see fulfills. `Secret` is declared `internal`. Declare `Secret` `public`; declare `Host` `internal`; declare an @Instantiable type that fulfills `SecretGadget` in module `Feature` or a module it lists among its SafeDI dependencies, so `Host`’s tree builds it; or declare the dependency tree on an `internal` type that instantiates `Host`.
			\(fixtures["Feature"]!["Secret.swift"]):1:1: note: `Secret` is declared `internal` here.
			\(fixtures["Feature"]!["Secret.swift"]):1:1-1:1: fixit: public\u{20}
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(
						name: "Feature",
						packageName: "Shop",
						swiftFileContent: Self.featureFiles + ["struct Secret: Sendable {}", seamFixtureType(named: "Host", isSeam: true, isFinalClass: true, declarations: [#"@Instantiated(fulfilledByType: "SecretGadget") let erased: ErasedInstantiator<Secret, any Gadget>"#])],
						swiftFileContentByFilePath: plainDependencyTreeInitializersConfiguration,
					),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Spellings of another module's types

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsNeverSeeingThroughModuleQualifier_whenTwoModulesDeclareForwardedTypeOfOneName() async {
		// `Base.Token` and `Feature.Token` are two types, whatever the module names that qualify them.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Host.swift"]):11:5: error: `b: ErasedInstantiator<Feature.Token, any Gadget>` on `Host` forwards `Feature.Token`, and `a: ErasedInstantiator<Base.Token, any Gadget>` on `Host` forwards `Base.Token`. `Host` takes one builder for both, since `Impl` fills each and each returns `any Gadget`, and a builder’s places must forward the same values. Give both the same first generic argument, or name another type in the `fulfilledByType` of one.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Base", packageName: "Shop", swiftFileContent: ["public struct Token: Sendable {}"]),
					ModuleFixture(
						name: "Feature",
						packageName: "Shop",
						swiftFileContent: Self.featureFiles + ["public struct Token: Sendable {}", seamFixtureType(named: "Host", isSeam: true, isFinalClass: true, declarations: [
							#"@Instantiated(fulfilledByType: "Impl") let a: ErasedInstantiator<Base.Token, any Gadget>"#,
							#"@Instantiated(fulfilledByType: "Impl") let b: ErasedInstantiator<Feature.Token, any Gadget>"#,
						])].map { "import Base\n\n" + $0 },
						dependencies: ["Base"],
					),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// Expects every module of `output` to have compiled, and its generated code to have drawn no warning, where compile
	/// verification is enabled.
	private static func expectCompiles(_ output: MultiModuleTestOutput, sourceLocation: SourceLocation = #_sourceLocation) throws {
		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation, sourceLocation: sourceLocation)
		for module in compilation.modules {
			#expect(module.result.exitCode == 0, "\(module.moduleName): \(module.result.stderr)", sourceLocation: sourceLocation)
			#expect(module.generatedCodeWarnings.isEmpty, "\(module.moduleName): \(module.generatedCodeWarnings)", sourceLocation: sourceLocation)
		}
	}

	/// Expects every module of `output` to have compiled, and its generated code to have drawn no warning, where compile
	/// verification is enabled, and compiles `inlineControl`, the same graph built in one module, as a control: a failure
	/// the inline build shares is one of every module whose declarations default to the main actor (issue #661), which
	/// the message says.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectCompiles(_ output: MultiModuleTestOutput, inlineControl: [ModuleFixture], sourceLocation: SourceLocation = #_sourceLocation) async throws {
		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation, sourceLocation: sourceLocation)
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inlineControl, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		let inlineCompilation = try #require(inlineOutput.compilation, sourceLocation: sourceLocation)
		let inlineFailure = inlineCompilation.failure.map { "\nThe same graph built in one module fails too (issue #661): \($0.result.stderr)" } ?? ""
		for module in compilation.modules {
			#expect(module.result.exitCode == 0, "\(module.moduleName): \(module.result.stderr)\(inlineFailure)", sourceLocation: sourceLocation)
			#expect(module.generatedCodeWarnings.isEmpty, "\(module.moduleName): \(module.generatedCodeWarnings)", sourceLocation: sourceLocation)
		}
	}

	/// Expects `output`, the seam build of `modules`, to build the values `visibleModules` build for `probes`, where
	/// compile verification is enabled: the same types, with every fulfiller in the seam's module, which builds its tree
	/// inline.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectValuesEqualVisibleBuild(
		_ output: MultiModuleTestOutput,
		modules: [ModuleFixture],
		visibleModules: [ModuleFixture],
		probes: [String],
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		guard compileVerificationIsEnabled else { return }
		let visibleOutput = try await executeSafeDIToolMultiModuleTest(modules: visibleModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		try await expectDifferentialValuesAgree(
			feature: DifferentialValuePath(output: output, modules: modules),
			knownRight: DifferentialValuePath(output: visibleOutput, modules: visibleModules),
			probes: probes.map(DifferentialValueProbe.init),
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}

	/// Expects each probe of `describe` to describe as its value says in `output`, the build of `modules`, where compile
	/// verification is enabled: a retention probe's count, which the comparison with the inline build checks too.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectProbes(of output: MultiModuleTestOutput, modules: [ModuleFixture], describe probes: [String: String], sourceLocation: SourceLocation = #_sourceLocation) async throws {
		let orderedProbes = probes.keys.sorted()
		let description = try await DifferentialValueOracle.describe(
			DifferentialValuePath(output: output, modules: modules),
			probes: orderedProbes.map(DifferentialValueProbe.init),
			filesToDelete: &filesToDelete,
		)
		guard compileVerificationIsEnabled else { return }
		#expect(description == orderedProbes.map { "probe \($0)\n\(probes[$0] ?? "")\n" }.joined(), sourceLocation: sourceLocation)
	}

	/// `Feature`, whose seam `Host` declares `hostDeclarations` beside the types `featureTypes` declares, and which code a
	/// person writes calls through its readable initializer; and `App`, which declares `app`.
	private static func modules(hostDeclarations: [String], featureTypes: [String] = [], app: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(
				name: "Feature",
				packageName: "Shop",
				swiftFileContent: featureFiles + featureTypes + [seamFixtureType(named: "Host", isSeam: true, isFinalClass: true, declarations: hostDeclarations)],
				swiftFileContentByFilePath: plainDependencyTreeInitializersConfiguration,
			),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: app.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		]
	}

	/// `Feature`, which declares `featureTypes` and whose code a person writes calls through readable initializers, and
	/// `App`, which declares `app`.
	private static func modules(featureTypes: [String], app: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: featureFiles + featureTypes, swiftFileContentByFilePath: plainDependencyTreeInitializersConfiguration),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: app.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		]
	}

	/// `Feature`, which declares `innerSeams`, each with its declarations; `Middle`, whose seam `Outer` declares
	/// `outerDeclarations`; and `App`, whose root holds an `Outer`.
	private static func innerSeamModules(innerSeams: [String: [String]], outerDeclarations: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: featureFiles + innerSeams.keys.sorted().map { seamFixtureType(named: $0, isSeam: true, isFinalClass: true, declarations: innerSeams[$0] ?? []) }),
			ModuleFixture(name: "Middle", packageName: "Other", swiftFileContent: [seamFixtureType(named: "Outer", isSeam: true, isFinalClass: true, declarations: outerDeclarations)].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let outer: Outer"])].map { "import Feature\nimport Middle\n\n" + $0 }, dependencies: ["Feature", "Middle"]),
		]
	}

	/// A root that instantiates the `analytics` an `Inner` receives and the `Outer` that holds it.
	private static let rootOfOuter = seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let analytics: Analytics", "@Instantiated public let outer: Outer"])

	/// `Feature`'s seam `Home`, whose `Screen` builds itself again beside a place that reads its forwarded `id`, held by a kept
	/// seam `Outer` where `throughKeptSeam`; `App`, whose `LiveGadget` fills the place; and the same types with `LiveGadget`
	/// in `Feature`, which builds the tree inline.
	private static func screenModules(throughKeptSeam: Bool) -> (modules: [ModuleFixture], visibleModules: [ModuleFixture]) {
		var featureTypes = [
			seamFixtureType(named: "Screen", isFinalClass: true, declarations: [
				"@Forwarded public let id: Int",
				#"@Instantiated(fulfilledByType: "LiveGadget") public let panel: ErasedInstantiator<String, any Gadget>"#,
				"@Instantiated public let next: Instantiator<Screen>",
			]),
			seamFixtureType(named: "Home", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let screenBuilder: Instantiator<Screen>"]),
		]
		if throughKeptSeam {
			featureTypes.append(seamFixtureType(named: "Outer", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let home: Home"]))
		}
		let root = seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: [throughKeptSeam ? "@Instantiated public let outer: Outer" : "@Instantiated public let home: Home"])
		let probe = """
		func firstScreenIsFreed(holdingDepth depth: Int) -> Bool {
		    weak var firstScreen: Screen?
		    var heldScreen: Screen?
		    do {
		        var screen = \(throughKeptSeam ? "Root().outer.home" : "Root().home").screenBuilder.instantiate(1)
		        firstScreen = screen
		        for id in 2...depth {
		            screen = screen.next.instantiate(id)
		        }
		        _ = screen.panel.instantiate("title")
		        heldScreen = screen
		    }
		    return withExtendedLifetime(heldScreen) { firstScreen == nil }
		}
		"""
		let liveGadget = seamFixtureType(named: "LiveGadget", declarations: ["@Forwarded let title: String", "@Received let id: Int"], conformances: ", Gadget")
		return (modules(featureTypes: featureTypes, app: [liveGadget, root, probe]), modules(featureTypes: featureTypes + [liveGadget], app: [root, probe]))
	}

	/// `Feature`, whose `StringPanel` conforms to `Instantiable` by hand declaring that it forwards a `String`, whose `Owner`
	/// holds an `Instantiator<StringPanel>`, and whose seam `Host` declares `hostDeclarations`; and `App`, whose fulfiller of
	/// `StringPanel` forwards nothing.
	private static func stringPanelModules(hostDeclarations: [String]) -> [ModuleFixture] {
		modules(
			hostDeclarations: hostDeclarations,
			featureTypes: [
				"""
				open class StringPanel: Instantiable, @unchecked Sendable {
				    public typealias ForwardedProperties = String

				    public init() {}
				}
				""",
				seamFixtureType(named: "Owner", isFinalClass: true, declarations: ["@Instantiated public let held: Instantiator<StringPanel>"]),
			],
			app: [
				"""
				@Instantiable(fulfillingAdditionalTypes: [StringPanel.self], conformsElsewhere: true)
				public final class DefaultStringPanel: StringPanel, @unchecked Sendable {
				    public override init() {
				        super.init()
				    }
				}
				""",
				root,
			],
		)
	}

	/// What `Feature` declares beside its seam: a `Gadget` no declaration fulfills, an eraser of it, classes that conform to
	/// `Instantiable` by hand, as a type held in an `Instantiator` must – `Panel` forwards a `String`, `PairPanel` a labeled
	/// pair, `EmptyPanel` nothing – and `Navigator`, which no fill reads, so a builder that kept it would be seen to.
	private static let featureFiles = [
		"public protocol Gadget: Sendable {}",
		"""
		public struct AnyGadget: Gadget {
		    public init(_ base: any Gadget) {
		        self.base = base
		    }

		    let base: any Gadget
		}
		""",
		"""
		open class Panel: Instantiable, @unchecked Sendable {
		    public typealias ForwardedProperties = String

		    public init(title: String) {
		        self.title = title
		    }

		    public let title: String
		}
		""",
		"""
		open class PairPanel: Instantiable, @unchecked Sendable {
		    public typealias ForwardedProperties = (count: Int, name: String)

		    public init() {}
		}
		""",
		"""
		open class EmptyPanel: Instantiable, @unchecked Sendable {
		    public init() {}
		}
		""",
		seamFixtureType(named: "Analytics", isFinalClass: true, declarations: [], conformances: ", Sendable"),
		seamFixtureType(named: "Navigator", isFinalClass: true, declarations: []),
	]

	private static let root = seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let host: Host"])

	/// A root that instantiates the `analytics` its `Host` receives, which a fill inside a `@Sendable` function reads from the
	/// root's own scope.
	private static let rootInstantiatingAnalytics = seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let analytics: Analytics", "@Instantiated public let host: Host"])

	/// Whether `Host`'s `navigator` is freed while only `hold`'s wrapper of it is kept, after `call` called it twice.
	private static let navigatorProbe = """
	func navigatorIsFreed<Wrapper>(holding hold: (Host) -> Wrapper, calling call: (Wrapper) -> Void) -> Bool {
	    weak var weakNavigator: Navigator?
	    var wrapper: Wrapper?
	    do {
	        let host = Root().host
	        weakNavigator = host.navigator
	        wrapper = hold(host)
	    }
	    if let wrapper {
	        call(wrapper)
	        call(wrapper)
	    }
	    return withExtendedLifetime(wrapper) { weakNavigator == nil }
	}
	"""

	private static let defaultGadget = SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultGadget", fulfilling: "Gadget", declarations: ["@Received let analytics: Analytics"])

	private static let intGadget = seamFixtureType(named: "IntGadget", declarations: ["@Forwarded let value: Int"], conformances: ", Gadget")

	private static let namedGadget = seamFixtureType(named: "NamedGadget", declarations: ["@Forwarded let name: String"], conformances: ", Gadget")

	private static let pairGadget = seamFixtureType(named: "PairGadget", declarations: ["@Forwarded let count: Int", "@Forwarded let name: String", "@Received let analytics: Analytics"], conformances: ", Gadget")

	private static let defaultPanel = """
	@Instantiable(fulfillingAdditionalTypes: [Panel.self], conformsElsewhere: true)
	public final class DefaultPanel: Panel, @unchecked Sendable {
	    public init(name: String, analytics: Analytics) {
	        self.name = name
	        self.analytics = analytics
	        super.init(title: name)
	    }

	    @Forwarded let name: String
	    @Received let analytics: Analytics
	}
	"""

	private static let defaultPairPanel = """
	@Instantiable(fulfillingAdditionalTypes: [PairPanel.self], conformsElsewhere: true)
	public final class DefaultPairPanel: PairPanel, @unchecked Sendable {
	    public init(count: Int, name: String, analytics: Analytics) {
	        self.count = count
	        self.name = name
	        self.analytics = analytics
	        super.init()
	    }

	    @Forwarded let count: Int
	    @Forwarded let name: String
	    @Received let analytics: Analytics
	}
	"""

	private static let defaultEmptyPanel = """
	@Instantiable(fulfillingAdditionalTypes: [EmptyPanel.self], conformsElsewhere: true)
	public final class DefaultEmptyPanel: EmptyPanel, @unchecked Sendable {
	    public init(analytics: Analytics) {
	        self.analytics = analytics
	        super.init()
	    }

	    @Received let analytics: Analytics
	}
	"""
}
