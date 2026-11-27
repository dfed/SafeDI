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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_PairGadget_GadgetCarrier<__safeDI_Built> {
		        public let erased: (Navigator, Analytics) -> ErasedInstantiator<(count: Int, name: String), __safeDI_Built>.Builder

		        public init(erased: @escaping (Navigator, Analytics) -> ErasedInstantiator<(count: Int, name: String), __safeDI_Built>.Builder) {
		            self.erased = erased
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<(count: Int, name: String), __safeDI_Built>.Builder) {
		            self.init(erased: { _, _ in __safeDI_builder })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_PairPanelCarrier<__safeDI_Built> {
		        public let held: (Navigator, Analytics, ErasedInstantiator<(count: Int, name: String), any Gadget>) -> ErasedInstantiator<PairPanel.ForwardedProperties, __safeDI_Built>.Builder

		        public init(held: @escaping (Navigator, Analytics, ErasedInstantiator<(count: Int, name: String), any Gadget>) -> ErasedInstantiator<PairPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.held = held
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<PairPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.init(held: { _, _, _ in __safeDI_builder })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(pairGadget_GadgetBuilder: @escaping ErasedInstantiator<(count: Int, name: String), any Gadget>.Builder, pairPanelBuilder: @escaping Instantiator<PairPanel>.Builder) {
		        self.init(__safeDI_pairGadget_GadgetBuilder: .init(__safeDI_noScope: pairGadget_GadgetBuilder), __safeDI_pairPanelBuilder: .init(__safeDI_noScope: pairPanelBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_pairGadget_GadgetBuilder: __safeDI_PairGadget_GadgetCarrier<any Gadget>, __safeDI_pairPanelBuilder: __safeDI_PairPanelCarrier<PairPanel>) {
		        let navigator = Navigator()
		        let analytics = Analytics()
		        let erased = ErasedInstantiator<(count: Int, name: String), any Gadget>(__safeDI_pairGadget_GadgetBuilder.erased(navigator, analytics))
		        let held = Instantiator<PairPanel>(__safeDI_pairPanelBuilder.held(navigator, analytics, erased))
		        self.init(navigator: navigator, analytics: analytics, erased: erased, held: held)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_DCEBCFDE6FCC78B2 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_DCEBCFDE6FCC78B2.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
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
		            func __safeDI_pairGadget_GadgetBuilder_Host() -> Host.__safeDI_PairGadget_GadgetCarrier<any Gadget> {
		                .init(erased: { values_navigator, values_analytics in __safeDI_pairGadget_GadgetBuilder_Host_erased(analytics: values_analytics) })
		            }
		            func __safeDI_pairPanelBuilder_Host() -> Host.__safeDI_PairPanelCarrier<PairPanel> {
		                .init(held: { values_navigator, values_analytics, values_erased in __safeDI_pairPanelBuilder_Host_held(analytics: values_analytics) })
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_LiveGadget_AnyGadgetCarrier<__safeDI_Built> {
		        public let shell: (Navigator, Theme) -> __safeDI_LiveGadget_AnyGadgetCarrier_Shell<__safeDI_Built>

		        public init(shell: @escaping (Navigator, Theme) -> __safeDI_LiveGadget_AnyGadgetCarrier_Shell<__safeDI_Built>) {
		            self.shell = shell
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<String, __safeDI_Built>.Builder) {
		            self.init(shell: { _, _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_LiveGadget_AnyGadgetCarrier_Shell<__safeDI_Built> {
		        public let toolbar: (Style) -> __safeDI_LiveGadget_AnyGadgetCarrier_Toolbar<__safeDI_Built>

		        public init(toolbar: @escaping (Style) -> __safeDI_LiveGadget_AnyGadgetCarrier_Toolbar<__safeDI_Built>) {
		            self.toolbar = toolbar
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<String, __safeDI_Built>.Builder) {
		            self.init(toolbar: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_LiveGadget_AnyGadgetCarrier_Toolbar<__safeDI_Built> {
		        public let panelBuilder: () -> ErasedInstantiator<String, __safeDI_Built>.Builder

		        public init(panelBuilder: @escaping () -> ErasedInstantiator<String, __safeDI_Built>.Builder) {
		            self.panelBuilder = panelBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<String, __safeDI_Built>.Builder) {
		            self.init(panelBuilder: { __safeDI_builder })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(liveGadget_AnyGadgetBuilder: @escaping ErasedInstantiator<String, AnyGadget>.Builder) {
		        self.init(__safeDI_liveGadget_AnyGadgetBuilder: .init(__safeDI_noScope: liveGadget_AnyGadgetBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_liveGadget_AnyGadgetBuilder: __safeDI_LiveGadget_AnyGadgetCarrier<AnyGadget>) {
		        let navigator = Navigator()
		        let theme = Theme()
		        let __safeDI_liveGadget_AnyGadgetBuilder_shell = __safeDI_liveGadget_AnyGadgetBuilder.shell(navigator, theme)
		        @inline(never) func __safeDI_toolbar(__safeDI_liveGadget_AnyGadgetBuilder_toolbar: __safeDI_LiveGadget_AnyGadgetCarrier_Toolbar<AnyGadget>) -> Toolbar {
		            let panelBuilder = ErasedInstantiator<String, AnyGadget>(__safeDI_liveGadget_AnyGadgetBuilder_toolbar.panelBuilder())
		            return Toolbar(panelBuilder: panelBuilder)
		        }
		        @inline(never) func __safeDI_shell() -> Shell {
		            let style = Style()
		            let __safeDI_liveGadget_AnyGadgetBuilder_toolbar = __safeDI_liveGadget_AnyGadgetBuilder_shell.toolbar(style)
		            let toolbar: Toolbar = __safeDI_toolbar(__safeDI_liveGadget_AnyGadgetBuilder_toolbar: __safeDI_liveGadget_AnyGadgetBuilder_toolbar)
		            return Shell(style: style, toolbar: toolbar)
		        }
		        let shell: Shell = __safeDI_shell()
		        self.init(navigator: navigator, theme: theme, shell: shell)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_BCD415DCFDB56A23 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_BCD415DCFDB56A23.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_liveGadget_AnyGadgetBuilder_Host_Toolbar_Scope_panelBuilder(theme: Theme, style: Style) -> ErasedInstantiator<String, AnyGadget>.Builder {
		                func __safeDI_panelBuilder(title: String) -> LiveGadget {
		                    LiveGadget(title: title, theme: theme, style: style)
		                }
		                return { forwarded in AnyGadget(__safeDI_panelBuilder(title: forwarded)) }
		            }
		            func __safeDI_liveGadget_AnyGadgetBuilder_Host() -> Host.__safeDI_LiveGadget_AnyGadgetCarrier<AnyGadget> {
		                .init(shell: { values_navigator, values_theme in __safeDI_liveGadget_AnyGadgetBuilder_Host_Shell_Scope(theme: values_theme) })
		            }
		            func __safeDI_liveGadget_AnyGadgetBuilder_Host_Shell_Scope(theme: Theme) -> Host.__safeDI_LiveGadget_AnyGadgetCarrier_Shell<AnyGadget> {
		                .init(toolbar: { values_style in __safeDI_liveGadget_AnyGadgetBuilder_Host_Toolbar_Scope(style: values_style, theme: theme) })
		            }
		            func __safeDI_liveGadget_AnyGadgetBuilder_Host_Toolbar_Scope(style: Style, theme: Theme) -> Host.__safeDI_LiveGadget_AnyGadgetCarrier_Toolbar<AnyGadget> {
		                .init(panelBuilder: { __safeDI_liveGadget_AnyGadgetBuilder_Host_Toolbar_Scope_panelBuilder(theme: theme, style: style) })
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_PanelCarrier<__safeDI_Built> {
		        public let held: (Navigator, Analytics) -> ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder

		        public init(held: @escaping (Navigator, Analytics) -> ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.held = held
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.init(held: { _, _ in __safeDI_builder })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(panelBuilder: @escaping Instantiator<Panel>.Builder) {
		        self.init(__safeDI_panelBuilder: .init(__safeDI_noScope: panelBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_panelBuilder: __safeDI_PanelCarrier<Panel>) {
		        let navigator = Navigator()
		        let analytics = Analytics()
		        let held = Instantiator<Panel>(__safeDI_panelBuilder.held(navigator, analytics))
		        self.init(navigator: navigator, analytics: analytics, held: held)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_3579F61D065CC7F8 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_3579F61D065CC7F8.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_panelBuilder_Host_held(analytics: Analytics) -> Instantiator<Panel>.Builder {
		                func __safeDI_held(name: String) -> DefaultPanel {
		                    DefaultPanel(name: name, analytics: analytics)
		                }
		                return { forwarded in __safeDI_held(name: forwarded) }
		            }
		            func __safeDI_panelBuilder_Host() -> Host.__safeDI_PanelCarrier<Panel> {
		                .init(held: { values_navigator, values_analytics in __safeDI_panelBuilder_Host_held(analytics: values_analytics) })
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_EmptyPanelCarrier<__safeDI_Built> {
		        public let held: (Navigator, Analytics) -> ErasedInstantiator<EmptyPanel.ForwardedProperties, __safeDI_Built>.Builder

		        public init(held: @escaping (Navigator, Analytics) -> ErasedInstantiator<EmptyPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.held = held
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<EmptyPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.init(held: { _, _ in __safeDI_builder })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(emptyPanelBuilder: @escaping Instantiator<EmptyPanel>.Builder) {
		        self.init(__safeDI_emptyPanelBuilder: .init(__safeDI_noScope: emptyPanelBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_emptyPanelBuilder: __safeDI_EmptyPanelCarrier<EmptyPanel>) {
		        let navigator = Navigator()
		        let analytics = Analytics()
		        let held = Instantiator<EmptyPanel>(__safeDI_emptyPanelBuilder.held(navigator, analytics))
		        self.init(navigator: navigator, analytics: analytics, held: held)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_A74361A4F13BEE57 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_A74361A4F13BEE57.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_emptyPanelBuilder_Host_held(analytics: Analytics) -> Instantiator<EmptyPanel>.Builder {
		                func __safeDI_held() -> DefaultEmptyPanel {
		                    DefaultEmptyPanel(analytics: analytics)
		                }
		                return { _ in __safeDI_held() }
		            }
		            func __safeDI_emptyPanelBuilder_Host() -> Host.__safeDI_EmptyPanelCarrier<EmptyPanel> {
		                .init(held: { values_navigator, values_analytics in __safeDI_emptyPanelBuilder_Host_held(analytics: values_analytics) })
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_PanelCarrier_Owner<__safeDI_Built> {
		        public let held: () -> ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder

		        public init(held: @escaping () -> ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.held = held
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.init(held: { __safeDI_builder })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_PanelSendableCarrier<__safeDI_Built>: Sendable {
		        public let held: @Sendable () -> SendableErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder
		        public let ownerBuilder: @Sendable () -> __safeDI_PanelCarrier_Owner<__safeDI_Built>

		        public init(held: @escaping @Sendable () -> SendableErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder, ownerBuilder: @escaping @Sendable () -> __safeDI_PanelCarrier_Owner<__safeDI_Built>) {
		            self.held = held
		            self.ownerBuilder = ownerBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.init(held: { __safeDI_builder }, ownerBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(analytics: Analytics, panelSendableBuilder: @escaping SendableErasedInstantiator<Panel.ForwardedProperties, Panel>.Builder) {
		        self.init(__safeDI_analytics: analytics, __safeDI_panelSendableBuilder: .init(__safeDI_noScope: panelSendableBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_analytics analytics: Analytics, __safeDI_panelSendableBuilder: __safeDI_PanelSendableCarrier<Panel>) {
		        let navigator = Navigator()
		        let held = SendableInstantiator<Panel>(__safeDI_panelSendableBuilder.held())
		        @inline(never) @Sendable nonisolated func __safeDI_ownerBuilder() -> Owner {
		            let __safeDI_panelSendableBuilder_ownerBuilder = __safeDI_panelSendableBuilder.ownerBuilder()
		            let held = Instantiator<Panel>(__safeDI_panelSendableBuilder_ownerBuilder.held())
		            return Owner(held: held)
		        }
		        let ownerBuilder = SendableInstantiator<Owner>(__safeDI_ownerBuilder)
		        self.init(navigator: navigator, analytics: analytics, held: held, ownerBuilder: ownerBuilder)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_506AC31C70C00C46 {}
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
		            _ = Host.__safeDI_Host_506AC31C70C00C46.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
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
		            @Sendable nonisolated func __safeDI_panelSendableBuilder_Host() -> Host.__safeDI_PanelSendableCarrier<Panel> {
		                .init(held: { __safeDI_panelSendableBuilder_Host_held() }, ownerBuilder: { __safeDI_panelBuilder_Host_Owner_Scope() })
		            }
		            @Sendable nonisolated func __safeDI_panelBuilder_Host_Owner_Scope() -> Host.__safeDI_PanelCarrier_Owner<Panel> {
		                .init(held: { __safeDI_panelSendableBuilder_Host_Owner_Scope_held() })
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_PanelCarrier<__safeDI_Built> {
		        public let held: (Navigator, Analytics) -> ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder
		        public let erased: (Navigator, Analytics, Instantiator<Panel>) -> ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder

		        public init(held: @escaping (Navigator, Analytics) -> ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder, erased: @escaping (Navigator, Analytics, Instantiator<Panel>) -> ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.held = held
		            self.erased = erased
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.init(held: { _, _ in __safeDI_builder }, erased: { _, _, _ in __safeDI_builder })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(panelBuilder: @escaping ErasedInstantiator<Panel.ForwardedProperties, Panel>.Builder) {
		        self.init(__safeDI_panelBuilder: .init(__safeDI_noScope: panelBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_panelBuilder: __safeDI_PanelCarrier<Panel>) {
		        let navigator = Navigator()
		        let analytics = Analytics()
		        let held = Instantiator<Panel>(__safeDI_panelBuilder.held(navigator, analytics))
		        let erased = ErasedInstantiator<Panel.ForwardedProperties, Panel>(__safeDI_panelBuilder.erased(navigator, analytics, held))
		        self.init(navigator: navigator, analytics: analytics, held: held, erased: erased)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_F940D7E3A6BF3A52 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_F940D7E3A6BF3A52.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
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
		            func __safeDI_panelBuilder_Host() -> Host.__safeDI_PanelCarrier<Panel> {
		                .init(held: { values_navigator, values_analytics in __safeDI_panelBuilder_Host_held(analytics: values_analytics) }, erased: { values_navigator, values_analytics, values_held in __safeDI_panelBuilder_Host_erased(analytics: values_analytics) })
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_PairPanelCarrier<__safeDI_Built> {
		        public let held: (Navigator, Analytics) -> ErasedInstantiator<PairPanel.ForwardedProperties, __safeDI_Built>.Builder
		        public let erased: (Navigator, Analytics, Instantiator<PairPanel>) -> ErasedInstantiator<PairPanel.ForwardedProperties, __safeDI_Built>.Builder

		        public init(held: @escaping (Navigator, Analytics) -> ErasedInstantiator<PairPanel.ForwardedProperties, __safeDI_Built>.Builder, erased: @escaping (Navigator, Analytics, Instantiator<PairPanel>) -> ErasedInstantiator<PairPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.held = held
		            self.erased = erased
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<PairPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.init(held: { _, _ in __safeDI_builder }, erased: { _, _, _ in __safeDI_builder })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(pairPanelBuilder: @escaping ErasedInstantiator<PairPanel.ForwardedProperties, PairPanel>.Builder) {
		        self.init(__safeDI_pairPanelBuilder: .init(__safeDI_noScope: pairPanelBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_pairPanelBuilder: __safeDI_PairPanelCarrier<PairPanel>) {
		        let navigator = Navigator()
		        let analytics = Analytics()
		        let held = Instantiator<PairPanel>(__safeDI_pairPanelBuilder.held(navigator, analytics))
		        let erased = ErasedInstantiator<PairPanel.ForwardedProperties, PairPanel>(__safeDI_pairPanelBuilder.erased(navigator, analytics, held))
		        self.init(navigator: navigator, analytics: analytics, held: held, erased: erased)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_BC602462D77F598A {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_BC602462D77F598A.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
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
		            func __safeDI_pairPanelBuilder_Host() -> Host.__safeDI_PairPanelCarrier<PairPanel> {
		                .init(held: { values_navigator, values_analytics in __safeDI_pairPanelBuilder_Host_held(analytics: values_analytics) }, erased: { values_navigator, values_analytics, values_held in __safeDI_pairPanelBuilder_Host_erased(analytics: values_analytics) })
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
	mutating func generate_spellsBuildersForwardedValueAsMostExplicitPlaceSpellsIt_whenPlacesInOneFileSpellOneValueTwoWays(order: [String]) async throws {
		// `C` spells the value `Swift.Int`, `A` and `B` spell it `Int`: one value, which the builder takes as its most explicit
		// spelling, `Swift.Int`, whichever place is declared first.
		let placesFile = order.map { name in
			let spelling = name == "C" ? "Swift.Int" : "Int"
			return seamFixtureType(named: name, isFinalClass: true, declarations: [#"@Instantiated(fulfilledByType: "IntGadget") public let place: ErasedInstantiator<\#(spelling), any Gadget>"#])
		}.joined(separator: "\n\n")
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_IntGadget_GadgetCarrier<__safeDI_Built> {
		        public let a: __safeDI_IntGadget_GadgetCarrier_A<__safeDI_Built>
		        public let b: (A) -> __safeDI_IntGadget_GadgetCarrier_B<__safeDI_Built>
		        public let c: (A, B) -> __safeDI_IntGadget_GadgetCarrier_C<__safeDI_Built>

		        public init(a: __safeDI_IntGadget_GadgetCarrier_A<__safeDI_Built>, b: @escaping (A) -> __safeDI_IntGadget_GadgetCarrier_B<__safeDI_Built>, c: @escaping (A, B) -> __safeDI_IntGadget_GadgetCarrier_C<__safeDI_Built>) {
		            self.a = a
		            self.b = b
		            self.c = c
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Swift.Int, __safeDI_Built>.Builder) {
		            self.init(a: .init(__safeDI_noScope: __safeDI_builder), b: { _ in .init(__safeDI_noScope: __safeDI_builder) }, c: { _, _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_IntGadget_GadgetCarrier_A<__safeDI_Built> {
		        public let place: () -> ErasedInstantiator<Int, __safeDI_Built>.Builder

		        public init(place: @escaping () -> ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		            self.place = place
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		            self.init(place: { __safeDI_builder })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_IntGadget_GadgetCarrier_B<__safeDI_Built> {
		        public let place: () -> ErasedInstantiator<Int, __safeDI_Built>.Builder

		        public init(place: @escaping () -> ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		            self.place = place
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		            self.init(place: { __safeDI_builder })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_IntGadget_GadgetCarrier_C<__safeDI_Built> {
		        public let place: () -> ErasedInstantiator<Swift.Int, __safeDI_Built>.Builder

		        public init(place: @escaping () -> ErasedInstantiator<Swift.Int, __safeDI_Built>.Builder) {
		            self.place = place
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Swift.Int, __safeDI_Built>.Builder) {
		            self.init(place: { __safeDI_builder })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(intGadget_GadgetBuilder: @escaping ErasedInstantiator<Swift.Int, any Gadget>.Builder) {
		        self.init(__safeDI_intGadget_GadgetBuilder: .init(__safeDI_noScope: intGadget_GadgetBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_intGadget_GadgetBuilder: __safeDI_IntGadget_GadgetCarrier<any Gadget>) {
		        let __safeDI_intGadget_GadgetBuilder_a = __safeDI_intGadget_GadgetBuilder.a
		        @inline(never) func __safeDI_a() -> A {
		            let place = ErasedInstantiator<Int, any Gadget>(__safeDI_intGadget_GadgetBuilder_a.place())
		            return A(place: place)
		        }
		        let a: A = __safeDI_a()
		        let __safeDI_intGadget_GadgetBuilder_b = __safeDI_intGadget_GadgetBuilder.b(a)
		        @inline(never) func __safeDI_b() -> B {
		            let place = ErasedInstantiator<Int, any Gadget>(__safeDI_intGadget_GadgetBuilder_b.place())
		            return B(place: place)
		        }
		        let b: B = __safeDI_b()
		        let __safeDI_intGadget_GadgetBuilder_c = __safeDI_intGadget_GadgetBuilder.c(a, b)
		        @inline(never) func __safeDI_c() -> C {
		            let place = ErasedInstantiator<Swift.Int, any Gadget>(__safeDI_intGadget_GadgetBuilder_c.place())
		            return C(place: place)
		        }
		        let c: C = __safeDI_c()
		        self.init(a: a, b: b, c: c)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_B0DB29786B6ABA95 {}
		}
		"""])
		try Self.expectCompiles(output)
	}

	@Test(arguments: [["A", "B", "C"], ["A", "C", "B"], ["B", "A", "C"], ["B", "C", "A"], ["C", "A", "B"], ["C", "B", "A"]])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsBuildersForwardedValueAsMostExplicitPlaceSpellsIt_whenPlacesInThreeFilesSpellOneValueTwoWays(order: [String]) async throws {
		// `C` spells the value `Swift.Int`, `A` and `B` spell it `Int`, each in a file of its own, `File1.swift` holding
		// `order[0]`: one value, which the builder takes as its most explicit spelling, `Swift.Int`, whichever file sorts first.
		var placeFiles = [String: String]()
		for (index, name) in order.enumerated() {
			let spelling = name == "C" ? "Swift.Int" : "Int"
			placeFiles["File\(index + 1).swift"] = seamFixtureType(named: name, isFinalClass: true, declarations: [#"@Instantiated(fulfilledByType: "IntGadget") public let place: ErasedInstantiator<\#(spelling), any Gadget>"#])
		}
		let modules = [
			ModuleFixture(
				name: "Feature",
				packageName: "Shop",
				swiftFileContent: Self.featureFiles + [seamFixtureType(named: "Host", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let a: A", "@Instantiated public let b: B", "@Instantiated public let c: C"])],
				swiftFileContentByFilePath: plainDependencyTreeInitializersConfiguration.merging(placeFiles) { first, _ in first },
			),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [Self.intGadget, Self.root].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_IntGadget_GadgetCarrier<__safeDI_Built> {
		        public let a: __safeDI_IntGadget_GadgetCarrier_A<__safeDI_Built>
		        public let b: (A) -> __safeDI_IntGadget_GadgetCarrier_B<__safeDI_Built>
		        public let c: (A, B) -> __safeDI_IntGadget_GadgetCarrier_C<__safeDI_Built>

		        public init(a: __safeDI_IntGadget_GadgetCarrier_A<__safeDI_Built>, b: @escaping (A) -> __safeDI_IntGadget_GadgetCarrier_B<__safeDI_Built>, c: @escaping (A, B) -> __safeDI_IntGadget_GadgetCarrier_C<__safeDI_Built>) {
		            self.a = a
		            self.b = b
		            self.c = c
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Swift.Int, __safeDI_Built>.Builder) {
		            self.init(a: .init(__safeDI_noScope: __safeDI_builder), b: { _ in .init(__safeDI_noScope: __safeDI_builder) }, c: { _, _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_IntGadget_GadgetCarrier_A<__safeDI_Built> {
		        public let place: () -> ErasedInstantiator<Int, __safeDI_Built>.Builder

		        public init(place: @escaping () -> ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		            self.place = place
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		            self.init(place: { __safeDI_builder })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_IntGadget_GadgetCarrier_B<__safeDI_Built> {
		        public let place: () -> ErasedInstantiator<Int, __safeDI_Built>.Builder

		        public init(place: @escaping () -> ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		            self.place = place
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		            self.init(place: { __safeDI_builder })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_IntGadget_GadgetCarrier_C<__safeDI_Built> {
		        public let place: () -> ErasedInstantiator<Swift.Int, __safeDI_Built>.Builder

		        public init(place: @escaping () -> ErasedInstantiator<Swift.Int, __safeDI_Built>.Builder) {
		            self.place = place
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Swift.Int, __safeDI_Built>.Builder) {
		            self.init(place: { __safeDI_builder })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(intGadget_GadgetBuilder: @escaping ErasedInstantiator<Swift.Int, any Gadget>.Builder) {
		        self.init(__safeDI_intGadget_GadgetBuilder: .init(__safeDI_noScope: intGadget_GadgetBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_intGadget_GadgetBuilder: __safeDI_IntGadget_GadgetCarrier<any Gadget>) {
		        let __safeDI_intGadget_GadgetBuilder_a = __safeDI_intGadget_GadgetBuilder.a
		        @inline(never) func __safeDI_a() -> A {
		            let place = ErasedInstantiator<Int, any Gadget>(__safeDI_intGadget_GadgetBuilder_a.place())
		            return A(place: place)
		        }
		        let a: A = __safeDI_a()
		        let __safeDI_intGadget_GadgetBuilder_b = __safeDI_intGadget_GadgetBuilder.b(a)
		        @inline(never) func __safeDI_b() -> B {
		            let place = ErasedInstantiator<Int, any Gadget>(__safeDI_intGadget_GadgetBuilder_b.place())
		            return B(place: place)
		        }
		        let b: B = __safeDI_b()
		        let __safeDI_intGadget_GadgetBuilder_c = __safeDI_intGadget_GadgetBuilder.c(a, b)
		        @inline(never) func __safeDI_c() -> C {
		            let place = ErasedInstantiator<Swift.Int, any Gadget>(__safeDI_intGadget_GadgetBuilder_c.place())
		            return C(place: place)
		        }
		        let c: C = __safeDI_c()
		        self.init(a: a, b: b, c: c)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_B0DB29786B6ABA95 {}
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_DefaultGadget_GadgetCarrier<__safeDI_Built> {
		        public let now: (Navigator, Analytics) -> __safeDI_Built
		        public let lazy: (Navigator, Analytics, any Gadget) -> __safeDI_Built
		        public let later: (Navigator, Analytics, any Gadget, LazilyInstantiated<any Gadget>) -> ErasedInstantiator<(), __safeDI_Built>.Builder

		        public init(now: @escaping (Navigator, Analytics) -> __safeDI_Built, lazy: @escaping (Navigator, Analytics, any Gadget) -> __safeDI_Built, later: @escaping (Navigator, Analytics, any Gadget, LazilyInstantiated<any Gadget>) -> ErasedInstantiator<(), __safeDI_Built>.Builder) {
		            self.now = now
		            self.lazy = lazy
		            self.later = later
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(now: { _, _ in __safeDI_builder() }, lazy: { _, _, _ in __safeDI_builder() }, later: { _, _, _, _ in { _ in __safeDI_builder() } })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(defaultGadget_GadgetBuilder: @escaping () -> any Gadget) {
		        self.init(__safeDI_defaultGadget_GadgetBuilder: .init(__safeDI_noScope: defaultGadget_GadgetBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_defaultGadget_GadgetBuilder: __safeDI_DefaultGadget_GadgetCarrier<any Gadget>) {
		        let navigator = Navigator()
		        let analytics = Analytics()
		        let now: any Gadget = __safeDI_defaultGadget_GadgetBuilder.now(navigator, analytics)
		        @inline(never) func __safeDI_lazy() -> any Gadget {
		            __safeDI_defaultGadget_GadgetBuilder.lazy(navigator, analytics, now)
		        }
		        let lazy = LazilyInstantiated<any Gadget>(__safeDI_lazy)
		        let later = ErasedInstantiator<(), any Gadget>(__safeDI_defaultGadget_GadgetBuilder.later(navigator, analytics, now, lazy))
		        self.init(navigator: navigator, analytics: analytics, now: now, lazy: lazy, later: later)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_ACD71CE8CCB8ADDC {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_ACD71CE8CCB8ADDC.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_defaultGadget_GadgetBuilder_Host_lazy(_ scope_navigator: Navigator, _ scope_analytics: Analytics, _ scope_now: any Gadget) -> any Gadget {
		                let analytics = scope_analytics
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
		            func __safeDI_defaultGadget_GadgetBuilder_Host() -> Host.__safeDI_DefaultGadget_GadgetCarrier<any Gadget> {
		                .init(
		                    now: { scope_navigator, scope_analytics in
		                        let analytics = scope_analytics
		                        let now: any Gadget = DefaultGadget(analytics: analytics)
		                        return now
		                    },
		                    lazy: { scope_navigator, scope_analytics, scope_now in __safeDI_defaultGadget_GadgetBuilder_Host_lazy(scope_navigator, scope_analytics, scope_now) },
		                    later: { values_navigator, values_analytics, values_now, values_lazy in __safeDI_defaultGadget_GadgetBuilder_Host_later(analytics: values_analytics) }
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_EmptyPanelCarrier<__safeDI_Built> {
		        public let now: (Analytics) -> __safeDI_Built
		        public let held: (Analytics, EmptyPanel) -> ErasedInstantiator<EmptyPanel.ForwardedProperties, __safeDI_Built>.Builder

		        public init(now: @escaping (Analytics) -> __safeDI_Built, held: @escaping (Analytics, EmptyPanel) -> ErasedInstantiator<EmptyPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.now = now
		            self.held = held
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(now: { _ in __safeDI_builder() }, held: { _, _ in { _ in __safeDI_builder() } })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(emptyPanelBuilder: @escaping () -> EmptyPanel) {
		        self.init(__safeDI_emptyPanelBuilder: .init(__safeDI_noScope: emptyPanelBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_emptyPanelBuilder: __safeDI_EmptyPanelCarrier<EmptyPanel>) {
		        let analytics = Analytics()
		        let now: EmptyPanel = __safeDI_emptyPanelBuilder.now(analytics)
		        let held = Instantiator<EmptyPanel>(__safeDI_emptyPanelBuilder.held(analytics, now))
		        self.init(analytics: analytics, now: now, held: held)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_A36506A93772F608 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_A36506A93772F608.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_emptyPanelBuilder_Host_held(analytics: Analytics) -> Instantiator<EmptyPanel>.Builder {
		                func __safeDI_held() -> DefaultEmptyPanel {
		                    DefaultEmptyPanel(analytics: analytics)
		                }
		                return { _ in __safeDI_held() }
		            }
		            func __safeDI_emptyPanelBuilder_Host() -> Host.__safeDI_EmptyPanelCarrier<EmptyPanel> {
		                .init(
		                    now: { scope_analytics in
		                        let analytics = scope_analytics
		                        let now: EmptyPanel = DefaultEmptyPanel(analytics: analytics)
		                        return now
		                    },
		                    held: { values_analytics, values_now in __safeDI_emptyPanelBuilder_Host_held(analytics: values_analytics) }
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
	mutating func generate_takesBuilderThatTakesNothing_whenErasedPlacesSpellNothingTwoWays() async throws {
		let hostDeclarations = [
			"@Instantiated let analytics: Analytics",
			#"@Instantiated(fulfilledByType: "DefaultGadget") public let tuple: ErasedInstantiator<(), any Gadget>"#,
			#"@Instantiated(fulfilledByType: "DefaultGadget") public let void: ErasedInstantiator<Void, any Gadget>"#,
		]
		let modules = Self.modules(hostDeclarations: hostDeclarations, app: [Self.defaultGadget, Self.root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_DefaultGadget_GadgetCarrier<__safeDI_Built> {
		        public let tuple: (Analytics) -> ErasedInstantiator<(), __safeDI_Built>.Builder
		        public let void: (Analytics, ErasedInstantiator<(), any Gadget>) -> ErasedInstantiator<(), __safeDI_Built>.Builder

		        public init(tuple: @escaping (Analytics) -> ErasedInstantiator<(), __safeDI_Built>.Builder, void: @escaping (Analytics, ErasedInstantiator<(), any Gadget>) -> ErasedInstantiator<(), __safeDI_Built>.Builder) {
		            self.tuple = tuple
		            self.void = void
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(tuple: { _ in { _ in __safeDI_builder() } }, void: { _, _ in { _ in __safeDI_builder() } })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(defaultGadget_GadgetBuilder: @escaping () -> any Gadget) {
		        self.init(__safeDI_defaultGadget_GadgetBuilder: .init(__safeDI_noScope: defaultGadget_GadgetBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_defaultGadget_GadgetBuilder: __safeDI_DefaultGadget_GadgetCarrier<any Gadget>) {
		        let analytics = Analytics()
		        let tuple = ErasedInstantiator<(), any Gadget>(__safeDI_defaultGadget_GadgetBuilder.tuple(analytics))
		        let void = ErasedInstantiator<Void, any Gadget>(__safeDI_defaultGadget_GadgetBuilder.void(analytics, tuple))
		        self.init(analytics: analytics, tuple: tuple, void: void)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_6A2DE84FCC3C8625 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_6A2DE84FCC3C8625.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
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
		            func __safeDI_defaultGadget_GadgetBuilder_Host() -> Host.__safeDI_DefaultGadget_GadgetCarrier<any Gadget> {
		                .init(tuple: { values_analytics in __safeDI_defaultGadget_GadgetBuilder_Host_tuple(analytics: values_analytics) }, void: { values_analytics, values_tuple in __safeDI_defaultGadget_GadgetBuilder_Host_void(analytics: values_analytics) })
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
	mutating func generate_handsInstantiatorsMemberBuilderThatTakesNothing_whenInstantiatorIsBesideErasedInstantiatorForwardingNothing() async throws {
		let hostDeclarations = [
			"@Instantiated let analytics: Analytics",
			"@Instantiated public let held: Instantiator<EmptyPanel>",
			#"@Instantiated(fulfilledByType: "EmptyPanel") public let later: ErasedInstantiator<(), EmptyPanel>"#,
		]
		let modules = Self.modules(hostDeclarations: hostDeclarations, app: [Self.defaultEmptyPanel, Self.root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_EmptyPanelCarrier<__safeDI_Built> {
		        public let held: (Analytics) -> ErasedInstantiator<EmptyPanel.ForwardedProperties, __safeDI_Built>.Builder
		        public let later: (Analytics, Instantiator<EmptyPanel>) -> ErasedInstantiator<(), __safeDI_Built>.Builder

		        public init(held: @escaping (Analytics) -> ErasedInstantiator<EmptyPanel.ForwardedProperties, __safeDI_Built>.Builder, later: @escaping (Analytics, Instantiator<EmptyPanel>) -> ErasedInstantiator<(), __safeDI_Built>.Builder) {
		            self.held = held
		            self.later = later
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(held: { _ in { _ in __safeDI_builder() } }, later: { _, _ in { _ in __safeDI_builder() } })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(emptyPanelBuilder: @escaping () -> EmptyPanel) {
		        self.init(__safeDI_emptyPanelBuilder: .init(__safeDI_noScope: emptyPanelBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_emptyPanelBuilder: __safeDI_EmptyPanelCarrier<EmptyPanel>) {
		        let analytics = Analytics()
		        let held = Instantiator<EmptyPanel>(__safeDI_emptyPanelBuilder.held(analytics))
		        let later = ErasedInstantiator<(), EmptyPanel>(__safeDI_emptyPanelBuilder.later(analytics, held))
		        self.init(analytics: analytics, held: held, later: later)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_95CA33EFFEB5D3F9 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_95CA33EFFEB5D3F9.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
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
		            func __safeDI_emptyPanelBuilder_Host() -> Host.__safeDI_EmptyPanelCarrier<EmptyPanel> {
		                .init(held: { values_analytics in __safeDI_emptyPanelBuilder_Host_held(analytics: values_analytics) }, later: { values_analytics, values_held in __safeDI_emptyPanelBuilder_Host_later(analytics: values_analytics) })
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

	// MARK: A seam that passes up an inner seam’s places

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsInnerSeamBuildersTakingForwardedValue_whenOuterSeamPassesUpForwardingPlacesOfBothFamilies() async throws {
		let featureTypes = [
			seamFixtureType(named: "Inner", isSeam: true, isFinalClass: true, declarations: ["@Received let analytics: Analytics", "@Instantiated public let part: Instantiator<Panel>", "@Instantiated public let sendablePart: SendableInstantiator<Panel>"]),
			seamFixtureType(named: "Outer", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let navigator: Navigator", "@Instantiated public let inner: Inner"]),
		]
		let modules = Self.modules(featureTypes: featureTypes, app: [Self.defaultPanel, Self.rootOfOuter])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Inner {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_PanelCarrier<__safeDI_Built> {
		        public let part: (Analytics) -> ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder

		        public init(part: @escaping (Analytics) -> ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.part = part
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.init(part: { _ in __safeDI_builder })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_PanelSendableCarrier<__safeDI_Built>: Sendable {
		        public let sendablePart: @Sendable () -> SendableErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder

		        public init(sendablePart: @escaping @Sendable () -> SendableErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.sendablePart = sendablePart
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.init(sendablePart: { __safeDI_builder })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(analytics: Analytics, panelBuilder: @escaping Instantiator<Panel>.Builder, panelSendableBuilder: @escaping SendableInstantiator<Panel>.Builder) {
		        self.init(__safeDI_analytics: analytics, __safeDI_panelBuilder: .init(__safeDI_noScope: panelBuilder), __safeDI_panelSendableBuilder: .init(__safeDI_noScope: panelSendableBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_analytics analytics: Analytics, __safeDI_panelBuilder: __safeDI_PanelCarrier<Panel>, __safeDI_panelSendableBuilder: __safeDI_PanelSendableCarrier<Panel>) {
		        let part = Instantiator<Panel>(__safeDI_panelBuilder.part(analytics))
		        let sendablePart = SendableInstantiator<Panel>(__safeDI_panelSendableBuilder.sendablePart())
		        self.init(analytics: analytics, part: part, sendablePart: sendablePart)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_8561866D0B8BB04F {}
		}

		extension Outer {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_PanelCarrier<__safeDI_Built> {
		        public let inner: Inner.__safeDI_PanelCarrier<__safeDI_Built>

		        public init(inner: Inner.__safeDI_PanelCarrier<__safeDI_Built>) {
		            self.inner = inner
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.init(inner: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_PanelSendableCarrier<__safeDI_Built>: Sendable {
		        public let inner_Sendable: Inner.__safeDI_PanelSendableCarrier<__safeDI_Built>

		        public init(inner_Sendable: Inner.__safeDI_PanelSendableCarrier<__safeDI_Built>) {
		            self.inner_Sendable = inner_Sendable
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.init(inner_Sendable: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(analytics: Analytics, panelBuilder: @escaping Instantiator<Panel>.Builder, panelSendableBuilder: @escaping SendableInstantiator<Panel>.Builder) {
		        self.init(__safeDI_analytics: analytics, __safeDI_panelBuilder: .init(__safeDI_noScope: panelBuilder), __safeDI_panelSendableBuilder: .init(__safeDI_noScope: panelSendableBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_analytics: @autoclosure @escaping () -> Analytics, __safeDI_panelBuilder: __safeDI_PanelCarrier<Panel>, __safeDI_panelSendableBuilder: __safeDI_PanelSendableCarrier<Panel>) {
		        let analytics = LazilyInstantiated<Analytics>(__safeDI_analytics)
		        let navigator = Navigator()
		        @inline(never) func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_8561866D0B8BB04F.self
		            return Inner(__safeDI_analytics: analytics.instance, __safeDI_panelBuilder: __safeDI_panelBuilder.inner, __safeDI_panelSendableBuilder: __safeDI_panelSendableBuilder.inner_Sendable)
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(navigator: navigator, inner: inner)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_17A2541A54A1BA64 {}
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
		            _ = Outer.__safeDI_Outer_17A2541A54A1BA64.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_panelBuilder_Inner_part(analytics: Analytics) -> Instantiator<Panel>.Builder {
		                func __safeDI_part(name: String) -> DefaultPanel {
		                    DefaultPanel(name: name, analytics: analytics)
		                }
		                return { forwarded in __safeDI_part(name: forwarded) }
		            }
		            @Sendable nonisolated func __safeDI_panelSendableBuilder_Inner_sendablePart() -> SendableInstantiator<Panel>.Builder {
		                @Sendable nonisolated func __safeDI_sendablePart(name: String) -> DefaultPanel {
		                    DefaultPanel(name: name, analytics: analytics)
		                }
		                return { forwarded in __safeDI_sendablePart(name: forwarded) }
		            }
		            func __safeDI_panelBuilder_Outer() -> Outer.__safeDI_PanelCarrier<Panel> {
		                .init(inner: __safeDI_panelBuilder_Inner())
		            }
		            func __safeDI_panelBuilder_Inner() -> Inner.__safeDI_PanelCarrier<Panel> {
		                .init(part: { values_analytics in __safeDI_panelBuilder_Inner_part(analytics: values_analytics) })
		            }
		            @Sendable nonisolated func __safeDI_panelSendableBuilder_Outer() -> Outer.__safeDI_PanelSendableCarrier<Panel> {
		                .init(inner_Sendable: __safeDI_panelSendableBuilder_Inner())
		            }
		            @Sendable nonisolated func __safeDI_panelSendableBuilder_Inner() -> Inner.__safeDI_PanelSendableCarrier<Panel> {
		                .init(sendablePart: { __safeDI_panelSendableBuilder_Inner_sendablePart() })
		            }
		            return Outer(__safeDI_analytics: analytics, __safeDI_panelBuilder: __safeDI_panelBuilder_Outer(), __safeDI_panelSendableBuilder: __safeDI_panelSendableBuilder_Outer())
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
	mutating func generate_handsInnerSeamBuildersTakingNothing_whenOuterSeamPassesUpErasedPlacesForwardingNothing() async throws {
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_DefaultGadget_GadgetCarrier<__safeDI_Built> {
		        public let later: (Analytics) -> ErasedInstantiator<(), __safeDI_Built>.Builder

		        public init(later: @escaping (Analytics) -> ErasedInstantiator<(), __safeDI_Built>.Builder) {
		            self.later = later
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(later: { _ in { _ in __safeDI_builder() } })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_DefaultGadget_GadgetSendableCarrier<__safeDI_Built>: Sendable {
		        public let sendableLater: @Sendable () -> SendableErasedInstantiator<(), __safeDI_Built>.Builder

		        public init(sendableLater: @escaping @Sendable () -> SendableErasedInstantiator<(), __safeDI_Built>.Builder) {
		            self.sendableLater = sendableLater
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(sendableLater: { { _ in __safeDI_builder() } })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(analytics: Analytics, defaultGadget_GadgetBuilder: @escaping () -> any Gadget, defaultGadget_GadgetSendableBuilder: @escaping @Sendable () -> any Gadget) {
		        self.init(__safeDI_analytics: analytics, __safeDI_defaultGadget_GadgetBuilder: .init(__safeDI_noScope: defaultGadget_GadgetBuilder), __safeDI_defaultGadget_GadgetSendableBuilder: .init(__safeDI_noScope: defaultGadget_GadgetSendableBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_analytics analytics: Analytics, __safeDI_defaultGadget_GadgetBuilder: __safeDI_DefaultGadget_GadgetCarrier<any Gadget>, __safeDI_defaultGadget_GadgetSendableBuilder: __safeDI_DefaultGadget_GadgetSendableCarrier<any Gadget>) {
		        let later = ErasedInstantiator<(), any Gadget>(__safeDI_defaultGadget_GadgetBuilder.later(analytics))
		        let sendableLater = SendableErasedInstantiator<(), any Gadget>(__safeDI_defaultGadget_GadgetSendableBuilder.sendableLater())
		        self.init(analytics: analytics, later: later, sendableLater: sendableLater)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_7C21330034BD4506 {}
		}

		extension Outer {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_DefaultGadget_GadgetCarrier<__safeDI_Built> {
		        public let inner: Inner.__safeDI_DefaultGadget_GadgetCarrier<__safeDI_Built>

		        public init(inner: Inner.__safeDI_DefaultGadget_GadgetCarrier<__safeDI_Built>) {
		            self.inner = inner
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(inner: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_DefaultGadget_GadgetSendableCarrier<__safeDI_Built>: Sendable {
		        public let inner_Sendable: Inner.__safeDI_DefaultGadget_GadgetSendableCarrier<__safeDI_Built>

		        public init(inner_Sendable: Inner.__safeDI_DefaultGadget_GadgetSendableCarrier<__safeDI_Built>) {
		            self.inner_Sendable = inner_Sendable
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(inner_Sendable: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(analytics: Analytics, defaultGadget_GadgetBuilder: @escaping () -> any Gadget, defaultGadget_GadgetSendableBuilder: @escaping @Sendable () -> any Gadget) {
		        self.init(__safeDI_analytics: analytics, __safeDI_defaultGadget_GadgetBuilder: .init(__safeDI_noScope: defaultGadget_GadgetBuilder), __safeDI_defaultGadget_GadgetSendableBuilder: .init(__safeDI_noScope: defaultGadget_GadgetSendableBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_analytics: @autoclosure @escaping () -> Analytics, __safeDI_defaultGadget_GadgetBuilder: __safeDI_DefaultGadget_GadgetCarrier<any Gadget>, __safeDI_defaultGadget_GadgetSendableBuilder: __safeDI_DefaultGadget_GadgetSendableCarrier<any Gadget>) {
		        let analytics = LazilyInstantiated<Analytics>(__safeDI_analytics)
		        let navigator = Navigator()
		        @inline(never) func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_7C21330034BD4506.self
		            return Inner(__safeDI_analytics: analytics.instance, __safeDI_defaultGadget_GadgetBuilder: __safeDI_defaultGadget_GadgetBuilder.inner, __safeDI_defaultGadget_GadgetSendableBuilder: __safeDI_defaultGadget_GadgetSendableBuilder.inner_Sendable)
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(navigator: navigator, inner: inner)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_3122D8C9B6F7918D {}
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
		            _ = Outer.__safeDI_Outer_3122D8C9B6F7918D.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_defaultGadget_GadgetBuilder_Inner_later(analytics: Analytics) -> ErasedInstantiator<(), any Gadget>.Builder {
		                func __safeDI_later() -> DefaultGadget {
		                    DefaultGadget(analytics: analytics)
		                }
		                return { _ in __safeDI_later() }
		            }
		            @Sendable nonisolated func __safeDI_defaultGadget_GadgetSendableBuilder_Inner_sendableLater() -> SendableErasedInstantiator<(), any Gadget>.Builder {
		                @Sendable nonisolated func __safeDI_sendableLater() -> DefaultGadget {
		                    DefaultGadget(analytics: analytics)
		                }
		                return { _ in __safeDI_sendableLater() }
		            }
		            func __safeDI_defaultGadget_GadgetBuilder_Outer() -> Outer.__safeDI_DefaultGadget_GadgetCarrier<any Gadget> {
		                .init(inner: __safeDI_defaultGadget_GadgetBuilder_Inner())
		            }
		            func __safeDI_defaultGadget_GadgetBuilder_Inner() -> Inner.__safeDI_DefaultGadget_GadgetCarrier<any Gadget> {
		                .init(later: { values_analytics in __safeDI_defaultGadget_GadgetBuilder_Inner_later(analytics: values_analytics) })
		            }
		            @Sendable nonisolated func __safeDI_defaultGadget_GadgetSendableBuilder_Outer() -> Outer.__safeDI_DefaultGadget_GadgetSendableCarrier<any Gadget> {
		                .init(inner_Sendable: __safeDI_defaultGadget_GadgetSendableBuilder_Inner())
		            }
		            @Sendable nonisolated func __safeDI_defaultGadget_GadgetSendableBuilder_Inner() -> Inner.__safeDI_DefaultGadget_GadgetSendableCarrier<any Gadget> {
		                .init(sendableLater: { __safeDI_defaultGadget_GadgetSendableBuilder_Inner_sendableLater() })
		            }
		            return Outer(__safeDI_analytics: analytics, __safeDI_defaultGadget_GadgetBuilder: __safeDI_defaultGadget_GadgetBuilder_Outer(), __safeDI_defaultGadget_GadgetSendableBuilder: __safeDI_defaultGadget_GadgetSendableBuilder_Outer())
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
	mutating func generate_fillsSwitchedSeamsForwardingBuilderWithLevelFunctions_whenOuterSeamFillsItOutright() async throws {
		// `Outer` passes up `Inner`'s `service`, which `Inner` passes up, and fills `Inner`'s place
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
		        public let inner: Inner.__safeDI_ServiceCarrier<__safeDI_Built>

		        public init(inner: Inner.__safeDI_ServiceCarrier<__safeDI_Built>) {
		            self.inner = inner
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(inner: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_analytics: @autoclosure @escaping () -> Analytics, __safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
		        let analytics = LazilyInstantiated<Analytics>(__safeDI_analytics)
		        let navigator = Navigator()
		        @inline(never) func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_00C173140CDE351A.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            @inline(never) func __safeDI_panelBuilder_Inner_part(analytics: Analytics) -> Instantiator<Panel>.Builder {
		                @inline(never) func __safeDI_part(name: String) -> DefaultPanel {
		                    DefaultPanel(name: name, analytics: analytics)
		                }
		                return { forwarded in __safeDI_part(name: forwarded) }
		            }
		            @inline(never) func __safeDI_panelBuilder_Inner() -> Inner.__safeDI_PanelCarrier<Panel> {
		                .init(part: { values_analytics, values_service in __safeDI_panelBuilder_Inner_part(analytics: values_analytics) })
		            }
		            return Inner(__safeDI_analytics: analytics.instance, __safeDI_panelBuilder: __safeDI_panelBuilder_Inner(), __safeDI_serviceBuilder: __safeDI_serviceBuilder.inner)
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(navigator: navigator, inner: inner)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_03F869DE55B7DB3E {}
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
		let (modules, visibleModules) = Self.screenModules(throughOuterSeam: false)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Home {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_LiveGadget_GadgetCarrier<__safeDI_Built> {
		        public let screenBuilder: __safeDI_LiveGadget_GadgetCarrier_Screen<__safeDI_Built>

		        public init(screenBuilder: __safeDI_LiveGadget_GadgetCarrier_Screen<__safeDI_Built>) {
		            self.screenBuilder = screenBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<String, __safeDI_Built>.Builder) {
		            self.init(screenBuilder: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_LiveGadget_GadgetCarrier_Screen<__safeDI_Built> {
		        public let panel: (Int) -> ErasedInstantiator<String, __safeDI_Built>.Builder
		        public let next: (Int, ErasedInstantiator<String, any Gadget>) -> __safeDI_LiveGadget_GadgetCarrier_Screen<__safeDI_Built>

		        public init(panel: @escaping (Int) -> ErasedInstantiator<String, __safeDI_Built>.Builder, next: @escaping (Int, ErasedInstantiator<String, any Gadget>) -> __safeDI_LiveGadget_GadgetCarrier_Screen<__safeDI_Built>) {
		            self.panel = panel
		            self.next = next
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<String, __safeDI_Built>.Builder) {
		            self.init(panel: { _ in __safeDI_builder }, next: { _, _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(liveGadget_GadgetBuilder: @escaping ErasedInstantiator<String, any Gadget>.Builder) {
		        self.init(__safeDI_liveGadget_GadgetBuilder: .init(__safeDI_noScope: liveGadget_GadgetBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_liveGadget_GadgetBuilder: __safeDI_LiveGadget_GadgetCarrier<any Gadget>) {
		        let __safeDI_liveGadget_GadgetBuilder_screenBuilder = __safeDI_liveGadget_GadgetBuilder.screenBuilder
		        @inline(never) func __safeDI_next(id: Int, __safeDI_liveGadget_GadgetBuilder_next: __safeDI_LiveGadget_GadgetCarrier_Screen<any Gadget>) -> Screen {
		            let panel = ErasedInstantiator<String, any Gadget>(__safeDI_liveGadget_GadgetBuilder_next.panel(id))
		            let next = Instantiator<Screen> {
		                __safeDI_next(id: $0, __safeDI_liveGadget_GadgetBuilder_next: __safeDI_liveGadget_GadgetBuilder_next)
		            }
		            return Screen(id: id, panel: panel, next: next)
		        }
		        @inline(never) func __safeDI_screenBuilder(id: Int) -> Screen {
		            let panel = ErasedInstantiator<String, any Gadget>(__safeDI_liveGadget_GadgetBuilder_screenBuilder.panel(id))
		            let __safeDI_liveGadget_GadgetBuilder_next = __safeDI_liveGadget_GadgetBuilder_screenBuilder.next(id, panel)
		            let next = Instantiator<Screen> {
		                __safeDI_next(id: $0, __safeDI_liveGadget_GadgetBuilder_next: __safeDI_liveGadget_GadgetBuilder_next)
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
		    public enum __safeDI_Home_FA2271C05D02DC50 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_FA2271C05D02DC50.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_liveGadget_GadgetBuilder_Home_Screen_Scope_panel(id: Int) -> ErasedInstantiator<String, any Gadget>.Builder {
		                func __safeDI_panel(title: String) -> LiveGadget {
		                    LiveGadget(title: title, id: id)
		                }
		                return { forwarded in __safeDI_panel(title: forwarded) }
		            }
		            func __safeDI_liveGadget_GadgetBuilder_Home() -> Home.__safeDI_LiveGadget_GadgetCarrier<any Gadget> {
		                .init(screenBuilder: __safeDI_liveGadget_GadgetBuilder_Home_Screen_Scope())
		            }
		            func __safeDI_liveGadget_GadgetBuilder_Home_Screen_Scope() -> Home.__safeDI_LiveGadget_GadgetCarrier_Screen<any Gadget> {
		                .init(panel: { values_id in __safeDI_liveGadget_GadgetBuilder_Home_Screen_Scope_panel(id: values_id) }, next: { values_id, values_panel in __safeDI_liveGadget_GadgetBuilder_Home_Screen_Scope() })
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
	mutating func generate_rebuildsCaseAroundForwardedValueOncePerFirstOpening_whenOuterSeamPassesUpForwardingPlaceOnLevelThatOpensAgain() async throws {
		// `Outer` passes `Home`'s place up through one conversion function per first opening of `Screen`'s level, whose
		// place's member hands `Outer`'s builder the case rebuilt around the value it forwards.
		let (modules, visibleModules) = Self.screenModules(throughOuterSeam: true)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Home {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_LiveGadget_GadgetCarrier<__safeDI_Built> {
		        public let screenBuilder: __safeDI_LiveGadget_GadgetCarrier_Screen<__safeDI_Built>

		        public init(screenBuilder: __safeDI_LiveGadget_GadgetCarrier_Screen<__safeDI_Built>) {
		            self.screenBuilder = screenBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<String, __safeDI_Built>.Builder) {
		            self.init(screenBuilder: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_LiveGadget_GadgetCarrier_Screen<__safeDI_Built> {
		        public let panel: (Int) -> ErasedInstantiator<String, __safeDI_Built>.Builder
		        public let next: (Int, ErasedInstantiator<String, any Gadget>) -> __safeDI_LiveGadget_GadgetCarrier_Screen<__safeDI_Built>

		        public init(panel: @escaping (Int) -> ErasedInstantiator<String, __safeDI_Built>.Builder, next: @escaping (Int, ErasedInstantiator<String, any Gadget>) -> __safeDI_LiveGadget_GadgetCarrier_Screen<__safeDI_Built>) {
		            self.panel = panel
		            self.next = next
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<String, __safeDI_Built>.Builder) {
		            self.init(panel: { _ in __safeDI_builder }, next: { _, _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(liveGadget_GadgetBuilder: @escaping ErasedInstantiator<String, any Gadget>.Builder) {
		        self.init(__safeDI_liveGadget_GadgetBuilder: .init(__safeDI_noScope: liveGadget_GadgetBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_liveGadget_GadgetBuilder: __safeDI_LiveGadget_GadgetCarrier<any Gadget>) {
		        let __safeDI_liveGadget_GadgetBuilder_screenBuilder = __safeDI_liveGadget_GadgetBuilder.screenBuilder
		        @inline(never) func __safeDI_next(id: Int, __safeDI_liveGadget_GadgetBuilder_next: __safeDI_LiveGadget_GadgetCarrier_Screen<any Gadget>) -> Screen {
		            let panel = ErasedInstantiator<String, any Gadget>(__safeDI_liveGadget_GadgetBuilder_next.panel(id))
		            let next = Instantiator<Screen> {
		                __safeDI_next(id: $0, __safeDI_liveGadget_GadgetBuilder_next: __safeDI_liveGadget_GadgetBuilder_next)
		            }
		            return Screen(id: id, panel: panel, next: next)
		        }
		        @inline(never) func __safeDI_screenBuilder(id: Int) -> Screen {
		            let panel = ErasedInstantiator<String, any Gadget>(__safeDI_liveGadget_GadgetBuilder_screenBuilder.panel(id))
		            let __safeDI_liveGadget_GadgetBuilder_next = __safeDI_liveGadget_GadgetBuilder_screenBuilder.next(id, panel)
		            let next = Instantiator<Screen> {
		                __safeDI_next(id: $0, __safeDI_liveGadget_GadgetBuilder_next: __safeDI_liveGadget_GadgetBuilder_next)
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
		    public enum __safeDI_Home_FA2271C05D02DC50 {}
		}

		extension Outer {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_LiveGadget_GadgetCarrier<__safeDI_Built> {
		        public let home: Home.__safeDI_LiveGadget_GadgetCarrier<__safeDI_Built>

		        public init(home: Home.__safeDI_LiveGadget_GadgetCarrier<__safeDI_Built>) {
		            self.home = home
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<String, __safeDI_Built>.Builder) {
		            self.init(home: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(liveGadget_GadgetBuilder: @escaping ErasedInstantiator<String, any Gadget>.Builder) {
		        self.init(__safeDI_liveGadget_GadgetBuilder: .init(__safeDI_noScope: liveGadget_GadgetBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_liveGadget_GadgetBuilder: __safeDI_LiveGadget_GadgetCarrier<any Gadget>) {
		        @inline(never) func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_FA2271C05D02DC50.self
		            return Home(__safeDI_liveGadget_GadgetBuilder: __safeDI_liveGadget_GadgetBuilder.home)
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_050544FCB3C79E0B {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_050544FCB3C79E0B.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_liveGadget_GadgetBuilder_screenBuilder_Home_Screen_Scope_panel(id: Int) -> ErasedInstantiator<String, any Gadget>.Builder {
		                func __safeDI_panel(title: String) -> LiveGadget {
		                    LiveGadget(title: title, id: id)
		                }
		                return { forwarded in __safeDI_panel(title: forwarded) }
		            }
		            func __safeDI_liveGadget_GadgetBuilder_Outer() -> Outer.__safeDI_LiveGadget_GadgetCarrier<any Gadget> {
		                .init(home: __safeDI_liveGadget_GadgetBuilder_Home())
		            }
		            func __safeDI_liveGadget_GadgetBuilder_Home() -> Home.__safeDI_LiveGadget_GadgetCarrier<any Gadget> {
		                .init(screenBuilder: __safeDI_liveGadget_GadgetBuilder_Home_Screen_Scope())
		            }
		            func __safeDI_liveGadget_GadgetBuilder_Home_Screen_Scope() -> Home.__safeDI_LiveGadget_GadgetCarrier_Screen<any Gadget> {
		                .init(panel: { values_id in __safeDI_liveGadget_GadgetBuilder_screenBuilder_Home_Screen_Scope_panel(id: values_id) }, next: { values_id, values_panel in __safeDI_liveGadget_GadgetBuilder_Home_Screen_Scope() })
		            }
		            return Outer(__safeDI_liveGadget_GadgetBuilder: __safeDI_liveGadget_GadgetBuilder_Outer())
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_BuiltGadget_GadgetCarrier<__safeDI_Built> {
		        public let built: () -> ErasedInstantiator<Built, __safeDI_Built>.Builder

		        public init(built: @escaping () -> ErasedInstantiator<Built, __safeDI_Built>.Builder) {
		            self.built = built
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Built, __safeDI_Built>.Builder) {
		            self.init(built: { __safeDI_builder })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_PairBuiltGadget_GadgetSendableCarrier<__safeDI_Built>: Sendable {
		        public let pair: @Sendable () -> SendableErasedInstantiator<(built: Built, count: Int), __safeDI_Built>.Builder

		        public init(pair: @escaping @Sendable () -> SendableErasedInstantiator<(built: Built, count: Int), __safeDI_Built>.Builder) {
		            self.pair = pair
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<(built: Built, count: Int), __safeDI_Built>.Builder) {
		            self.init(pair: { __safeDI_builder })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(builtGadget_GadgetBuilder: @escaping ErasedInstantiator<Built, any Gadget>.Builder, pairBuiltGadget_GadgetSendableBuilder: @escaping SendableErasedInstantiator<(built: Built, count: Int), any Gadget>.Builder) {
		        self.init(__safeDI_builtGadget_GadgetBuilder: .init(__safeDI_noScope: builtGadget_GadgetBuilder), __safeDI_pairBuiltGadget_GadgetSendableBuilder: .init(__safeDI_noScope: pairBuiltGadget_GadgetSendableBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_builtGadget_GadgetBuilder: __safeDI_BuiltGadget_GadgetCarrier<any Gadget>, __safeDI_pairBuiltGadget_GadgetSendableBuilder: __safeDI_PairBuiltGadget_GadgetSendableCarrier<any Gadget>) {
		        let built = ErasedInstantiator<Built, any Gadget>(__safeDI_builtGadget_GadgetBuilder.built())
		        let pair = SendableErasedInstantiator<(built: Built, count: Int), any Gadget>(__safeDI_pairBuiltGadget_GadgetSendableBuilder.pair())
		        self.init(built: built, pair: pair)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_0A9531797AE452B1 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_0A9531797AE452B1.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
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
		            func __safeDI_builtGadget_GadgetBuilder_Host() -> Host.__safeDI_BuiltGadget_GadgetCarrier<any Gadget> {
		                .init(built: { __safeDI_builtGadget_GadgetBuilder_Host_built() })
		            }
		            @Sendable nonisolated func __safeDI_pairBuiltGadget_GadgetSendableBuilder_Host() -> Host.__safeDI_PairBuiltGadget_GadgetSendableCarrier<any Gadget> {
		                .init(pair: { __safeDI_pairBuiltGadget_GadgetSendableBuilder_Host_pair() })
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_BuiltCarrier<__safeDI_Built> {
		        public let held: () -> ErasedInstantiator<Built.ForwardedProperties, __safeDI_Built>.Builder

		        public init(held: @escaping () -> ErasedInstantiator<Built.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.held = held
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Built.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.init(held: { __safeDI_builder })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_BuiltSendableCarrier<__safeDI_Built>: Sendable {
		        public let sendableHeld: @Sendable () -> SendableErasedInstantiator<Built.ForwardedProperties, __safeDI_Built>.Builder

		        public init(sendableHeld: @escaping @Sendable () -> SendableErasedInstantiator<Built.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.sendableHeld = sendableHeld
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<Built.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.init(sendableHeld: { __safeDI_builder })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(builtBuilder: @escaping Instantiator<Built>.Builder, builtSendableBuilder: @escaping SendableInstantiator<Built>.Builder) {
		        self.init(__safeDI_builtBuilder: .init(__safeDI_noScope: builtBuilder), __safeDI_builtSendableBuilder: .init(__safeDI_noScope: builtSendableBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_builtBuilder: __safeDI_BuiltCarrier<Built>, __safeDI_builtSendableBuilder: __safeDI_BuiltSendableCarrier<Built>) {
		        let held = Instantiator<Built>(__safeDI_builtBuilder.held())
		        let sendableHeld = SendableInstantiator<Built>(__safeDI_builtSendableBuilder.sendableHeld())
		        self.init(held: held, sendableHeld: sendableHeld)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_1C91A3D63DD12B71 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_1C91A3D63DD12B71.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
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
		            func __safeDI_builtBuilder_Host() -> Host.__safeDI_BuiltCarrier<Built> {
		                .init(held: { __safeDI_builtBuilder_Host_held() })
		            }
		            @Sendable nonisolated func __safeDI_builtSendableBuilder_Host() -> Host.__safeDI_BuiltSendableCarrier<Built> {
		                .init(sendableHeld: { __safeDI_builtSendableBuilder_Host_sendableHeld() })
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
		            _ = Host.__safeDI_Host_CF31C504C391FFF4.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
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
		            func __safeDI_panelBuilder_Host() -> Host.__safeDI_PanelCarrier<Panel> {
		                .init(held: { values_forwarded in __safeDI_panelBuilder_Host_held(forwarded: values_forwarded) })
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ThemedGadget_GadgetCarrier<__safeDI_Built> {
		        public let panel: (LazilyInstantiated<Theme>) -> ErasedInstantiator<String, __safeDI_Built>.Builder

		        public init(panel: @escaping (LazilyInstantiated<Theme>) -> ErasedInstantiator<String, __safeDI_Built>.Builder) {
		            self.panel = panel
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<String, __safeDI_Built>.Builder) {
		            self.init(panel: { _ in __safeDI_builder })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(themedGadget_GadgetBuilder: @escaping ErasedInstantiator<String, any Gadget>.Builder) {
		        self.init(__safeDI_themedGadget_GadgetBuilder: .init(__safeDI_noScope: themedGadget_GadgetBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_themedGadget_GadgetBuilder: __safeDI_ThemedGadget_GadgetCarrier<any Gadget>) {
		        @inline(never) func __safeDI_theme() -> Theme {
		            Theme()
		        }
		        let theme = LazilyInstantiated<Theme>(__safeDI_theme)
		        let panel = ErasedInstantiator<String, any Gadget>(__safeDI_themedGadget_GadgetBuilder.panel(theme))
		        self.init(theme: theme, panel: panel)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_4504BB2CCED29B61 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_4504BB2CCED29B61.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_themedGadget_GadgetBuilder_Host_panel(theme: LazilyInstantiated<Theme>) -> ErasedInstantiator<String, any Gadget>.Builder {
		                func __safeDI_panel(title: String) -> ThemedGadget {
		                    ThemedGadget(title: title, theme: theme.instance)
		                }
		                return { forwarded in __safeDI_panel(title: forwarded) }
		            }
		            func __safeDI_themedGadget_GadgetBuilder_Host() -> Host.__safeDI_ThemedGadget_GadgetCarrier<any Gadget> {
		                .init(panel: { values_theme in __safeDI_themedGadget_GadgetBuilder_Host_panel(theme: values_theme) })
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_EmptyPanelCarrier<__safeDI_Built> {
		        public let now: (Analytics) -> __safeDI_Built
		        public let owner: (Analytics, EmptyPanel) -> __safeDI_EmptyPanelCarrier_Owner<__safeDI_Built>

		        public init(now: @escaping (Analytics) -> __safeDI_Built, owner: @escaping (Analytics, EmptyPanel) -> __safeDI_EmptyPanelCarrier_Owner<__safeDI_Built>) {
		            self.now = now
		            self.owner = owner
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(now: { _ in __safeDI_builder() }, owner: { _, _ in .init(__safeDI_noScope: { _ in __safeDI_builder() }) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_EmptyPanelCarrier_Owner<__safeDI_Built> {
		        public let held: () -> ErasedInstantiator<EmptyPanel.ForwardedProperties, __safeDI_Built>.Builder

		        public init(held: @escaping () -> ErasedInstantiator<EmptyPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.held = held
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<EmptyPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.init(held: { __safeDI_builder })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_EmptyPanelSendableCarrier<__safeDI_Built>: Sendable {
		        public let ownerBuilder: @Sendable () -> __safeDI_EmptyPanelCarrier_Owner<__safeDI_Built>

		        public init(ownerBuilder: @escaping @Sendable () -> __safeDI_EmptyPanelCarrier_Owner<__safeDI_Built>) {
		            self.ownerBuilder = ownerBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<EmptyPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.init(ownerBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(analytics: Analytics, emptyPanelBuilder: @escaping () -> EmptyPanel, emptyPanelSendableBuilder: @escaping SendableInstantiator<EmptyPanel>.Builder) {
		        self.init(__safeDI_analytics: analytics, __safeDI_emptyPanelBuilder: .init(__safeDI_noScope: emptyPanelBuilder), __safeDI_emptyPanelSendableBuilder: .init(__safeDI_noScope: emptyPanelSendableBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_analytics analytics: Analytics, __safeDI_emptyPanelBuilder: __safeDI_EmptyPanelCarrier<EmptyPanel>, __safeDI_emptyPanelSendableBuilder: __safeDI_EmptyPanelSendableCarrier<EmptyPanel>) {
		        let now: EmptyPanel = __safeDI_emptyPanelBuilder.now(analytics)
		        let __safeDI_emptyPanelBuilder_owner = __safeDI_emptyPanelBuilder.owner(analytics, now)
		        @inline(never) func __safeDI_owner() -> Owner {
		            let held = Instantiator<EmptyPanel>(__safeDI_emptyPanelBuilder_owner.held())
		            return Owner(held: held)
		        }
		        let owner: Owner = __safeDI_owner()
		        @inline(never) @Sendable nonisolated func __safeDI_ownerBuilder() -> Owner {
		            let __safeDI_emptyPanelSendableBuilder_ownerBuilder = __safeDI_emptyPanelSendableBuilder.ownerBuilder()
		            let held = Instantiator<EmptyPanel>(__safeDI_emptyPanelSendableBuilder_ownerBuilder.held())
		            return Owner(held: held)
		        }
		        let ownerBuilder = SendableInstantiator<Owner>(__safeDI_ownerBuilder)
		        self.init(analytics: analytics, now: now, owner: owner, ownerBuilder: ownerBuilder)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_186A330777B1EAFE {}
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
		            _ = Host.__safeDI_Host_186A330777B1EAFE.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            @Sendable nonisolated func __safeDI_emptyPanelBuilder_Host_Owner_Scope_held(analytics: Analytics) -> Instantiator<EmptyPanel>.Builder {
		                func __safeDI_held() -> DefaultEmptyPanel {
		                    DefaultEmptyPanel(analytics: analytics)
		                }
		                return { _ in __safeDI_held() }
		            }
		            func __safeDI_emptyPanelBuilder_Host() -> Host.__safeDI_EmptyPanelCarrier<EmptyPanel> {
		                .init(
		                    now: { scope_analytics in
		                        let analytics = scope_analytics
		                        let now: EmptyPanel = DefaultEmptyPanel(analytics: analytics)
		                        return now
		                    },
		                    owner: { values_analytics, values_now in __safeDI_emptyPanelBuilder_Host_Owner_Scope(analytics: values_analytics) }
		                )
		            }
		            @Sendable nonisolated func __safeDI_emptyPanelBuilder_Host_Owner_Scope(analytics: Analytics) -> Host.__safeDI_EmptyPanelCarrier_Owner<EmptyPanel> {
		                .init(held: { __safeDI_emptyPanelBuilder_Host_Owner_Scope_held(analytics: analytics) })
		            }
		            @Sendable nonisolated func __safeDI_emptyPanelSendableBuilder_Host() -> Host.__safeDI_EmptyPanelSendableCarrier<EmptyPanel> {
		                .init(ownerBuilder: { __safeDI_emptyPanelBuilder_Host_Owner_Scope(analytics: analytics) })
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
	mutating func generate_handsPlacesOfForwardedPropertiesBuilderThatTakesNothing_whenErasedPlaceForwardingNothingIsBesideThem() async throws {
		// `StringPanel` declares that it forwards a `String`, and its fulfiller forwards nothing: the builder takes nothing, so
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_StringPanelCarrier<__safeDI_Built> {
		        public let later: () -> ErasedInstantiator<(), __safeDI_Built>.Builder
		        public let same: (ErasedInstantiator<(), StringPanel>) -> ErasedInstantiator<StringPanel.ForwardedProperties, __safeDI_Built>.Builder
		        public let owner: (ErasedInstantiator<(), StringPanel>, ErasedInstantiator<StringPanel.ForwardedProperties, StringPanel>) -> __safeDI_StringPanelCarrier_Owner<__safeDI_Built>

		        public init(later: @escaping () -> ErasedInstantiator<(), __safeDI_Built>.Builder, same: @escaping (ErasedInstantiator<(), StringPanel>) -> ErasedInstantiator<StringPanel.ForwardedProperties, __safeDI_Built>.Builder, owner: @escaping (ErasedInstantiator<(), StringPanel>, ErasedInstantiator<StringPanel.ForwardedProperties, StringPanel>) -> __safeDI_StringPanelCarrier_Owner<__safeDI_Built>) {
		            self.later = later
		            self.same = same
		            self.owner = owner
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(later: { { _ in __safeDI_builder() } }, same: { _ in { _ in __safeDI_builder() } }, owner: { _, _ in .init(__safeDI_noScope: { _ in __safeDI_builder() }) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_StringPanelCarrier_Owner<__safeDI_Built> {
		        public let held: () -> ErasedInstantiator<StringPanel.ForwardedProperties, __safeDI_Built>.Builder

		        public init(held: @escaping () -> ErasedInstantiator<StringPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.held = held
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<StringPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.init(held: { __safeDI_builder })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(stringPanelBuilder: @escaping () -> StringPanel) {
		        self.init(__safeDI_stringPanelBuilder: .init(__safeDI_noScope: stringPanelBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_stringPanelBuilder: __safeDI_StringPanelCarrier<StringPanel>) {
		        let later = ErasedInstantiator<(), StringPanel>(__safeDI_stringPanelBuilder.later())
		        let same = ErasedInstantiator<StringPanel.ForwardedProperties, StringPanel>(__safeDI_stringPanelBuilder.same(later))
		        let __safeDI_stringPanelBuilder_owner = __safeDI_stringPanelBuilder.owner(later, same)
		        @inline(never) func __safeDI_owner() -> Owner {
		            let held = Instantiator<StringPanel>(__safeDI_stringPanelBuilder_owner.held())
		            return Owner(held: held)
		        }
		        let owner: Owner = __safeDI_owner()
		        self.init(later: later, same: same, owner: owner)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_189626ACC022E750 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_189626ACC022E750.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
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
		            func __safeDI_stringPanelBuilder_Host() -> Host.__safeDI_StringPanelCarrier<StringPanel> {
		                .init(later: { __safeDI_stringPanelBuilder_Host_later() }, same: { values_later in __safeDI_stringPanelBuilder_Host_same() }, owner: { values_later, values_same in __safeDI_stringPanelBuilder_Host_Owner_Scope() })
		            }
		            func __safeDI_stringPanelBuilder_Host_Owner_Scope() -> Host.__safeDI_StringPanelCarrier_Owner<StringPanel> {
		                .init(held: { __safeDI_stringPanelBuilder_Host_Owner_Scope_held() })
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
	mutating func generate_handsSharedPlainLevelBuilderThatTakesNothing_whenSendableErasedPlaceForwardingNothingIsAboveInstantiatorOfForwardedProperties() async throws {
		let modules = Self.stringPanelModules(hostDeclarations: [
			#"@Instantiated(fulfilledByType: "StringPanel") public let later: SendableErasedInstantiator<(), StringPanel>"#,
			"@Instantiated public let ownerBuilder: SendableInstantiator<Owner>",
		])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_StringPanelCarrier_Owner<__safeDI_Built> {
		        public let held: () -> ErasedInstantiator<StringPanel.ForwardedProperties, __safeDI_Built>.Builder

		        public init(held: @escaping () -> ErasedInstantiator<StringPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.held = held
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<StringPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.init(held: { __safeDI_builder })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_StringPanelSendableCarrier<__safeDI_Built>: Sendable {
		        public let later: @Sendable () -> SendableErasedInstantiator<(), __safeDI_Built>.Builder
		        public let ownerBuilder: @Sendable () -> __safeDI_StringPanelCarrier_Owner<__safeDI_Built>

		        public init(later: @escaping @Sendable () -> SendableErasedInstantiator<(), __safeDI_Built>.Builder, ownerBuilder: @escaping @Sendable () -> __safeDI_StringPanelCarrier_Owner<__safeDI_Built>) {
		            self.later = later
		            self.ownerBuilder = ownerBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(later: { { _ in __safeDI_builder() } }, ownerBuilder: { .init(__safeDI_noScope: { _ in __safeDI_builder() }) })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(stringPanelSendableBuilder: @escaping @Sendable () -> StringPanel) {
		        self.init(__safeDI_stringPanelSendableBuilder: .init(__safeDI_noScope: stringPanelSendableBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_stringPanelSendableBuilder: __safeDI_StringPanelSendableCarrier<StringPanel>) {
		        let later = SendableErasedInstantiator<(), StringPanel>(__safeDI_stringPanelSendableBuilder.later())
		        @inline(never) @Sendable nonisolated func __safeDI_ownerBuilder() -> Owner {
		            let __safeDI_stringPanelSendableBuilder_ownerBuilder = __safeDI_stringPanelSendableBuilder.ownerBuilder()
		            let held = Instantiator<StringPanel>(__safeDI_stringPanelSendableBuilder_ownerBuilder.held())
		            return Owner(held: held)
		        }
		        let ownerBuilder = SendableInstantiator<Owner>(__safeDI_ownerBuilder)
		        self.init(later: later, ownerBuilder: ownerBuilder)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_78716D203C47A583 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_78716D203C47A583.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
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
		            @Sendable nonisolated func __safeDI_stringPanelSendableBuilder_Host() -> Host.__safeDI_StringPanelSendableCarrier<StringPanel> {
		                .init(later: { __safeDI_stringPanelSendableBuilder_Host_later() }, ownerBuilder: { __safeDI_stringPanelBuilder_Host_Owner_Scope() })
		            }
		            @Sendable nonisolated func __safeDI_stringPanelBuilder_Host_Owner_Scope() -> Host.__safeDI_StringPanelCarrier_Owner<StringPanel> {
		                .init(held: { __safeDI_stringPanelSendableBuilder_Host_Owner_Scope_held() })
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_PairPanelCarrier<__safeDI_Built> {
		        public let pair: (Analytics, Instantiator<Panel>) -> ErasedInstantiator<PairPanel.ForwardedProperties, __safeDI_Built>.Builder

		        public init(pair: @escaping (Analytics, Instantiator<Panel>) -> ErasedInstantiator<PairPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.pair = pair
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<PairPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.init(pair: { _, _ in __safeDI_builder })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_PanelCarrier<__safeDI_Built> {
		        public let held: (Analytics) -> ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder

		        public init(held: @escaping (Analytics) -> ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.held = held
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.init(held: { _ in __safeDI_builder })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(pairPanelBuilder: @escaping Instantiator<PairPanel>.Builder, panelBuilder: @escaping Instantiator<Panel>.Builder) {
		        self.init(__safeDI_pairPanelBuilder: .init(__safeDI_noScope: pairPanelBuilder), __safeDI_panelBuilder: .init(__safeDI_noScope: panelBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_pairPanelBuilder: __safeDI_PairPanelCarrier<PairPanel>, __safeDI_panelBuilder: __safeDI_PanelCarrier<Panel>) {
		        let analytics = Analytics()
		        let held = Instantiator<Panel>(__safeDI_panelBuilder.held(analytics))
		        let pair = Instantiator<PairPanel>(__safeDI_pairPanelBuilder.pair(analytics, held))
		        self.init(analytics: analytics, held: held, pair: pair)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_8541F2DDF6B038CF {}
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_MainPanelCarrier<__safeDI_Built> {
		        public let held: () -> ErasedInstantiator<MainPanel.ForwardedProperties, __safeDI_Built>.Builder

		        public init(held: @escaping () -> ErasedInstantiator<MainPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.held = held
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<MainPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.init(held: { __safeDI_builder })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_MainPanelSendableCarrier<__safeDI_Built>: Sendable {
		        public let sendableHeld: @Sendable () -> SendableErasedInstantiator<MainPanel.ForwardedProperties, __safeDI_Built>.Builder

		        public init(sendableHeld: @escaping @Sendable () -> SendableErasedInstantiator<MainPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.sendableHeld = sendableHeld
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<MainPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.init(sendableHeld: { __safeDI_builder })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(mainPanelBuilder: @escaping Instantiator<MainPanel>.Builder, mainPanelSendableBuilder: @escaping SendableInstantiator<MainPanel>.Builder) {
		        self.init(__safeDI_mainPanelBuilder: .init(__safeDI_noScope: mainPanelBuilder), __safeDI_mainPanelSendableBuilder: .init(__safeDI_noScope: mainPanelSendableBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_mainPanelBuilder: __safeDI_MainPanelCarrier<MainPanel>, __safeDI_mainPanelSendableBuilder: __safeDI_MainPanelSendableCarrier<MainPanel>) {
		        let held = Instantiator<MainPanel>(__safeDI_mainPanelBuilder.held())
		        let sendableHeld = SendableInstantiator<MainPanel>(__safeDI_mainPanelSendableBuilder.sendableHeld())
		        self.init(held: held, sendableHeld: sendableHeld)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_8A0068669CCAF7BD {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_8A0068669CCAF7BD.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
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
		            func __safeDI_mainPanelBuilder_Host() -> Host.__safeDI_MainPanelCarrier<MainPanel> {
		                .init(held: { __safeDI_mainPanelBuilder_Host_held() })
		            }
		            @Sendable nonisolated func __safeDI_mainPanelSendableBuilder_Host() -> Host.__safeDI_MainPanelSendableCarrier<MainPanel> {
		                .init(sendableHeld: { __safeDI_mainPanelSendableBuilder_Host_sendableHeld() })
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_PanelCarrier<__safeDI_Built> {
		        public let owner: (Analytics) -> __safeDI_PanelCarrier_Owner<__safeDI_Built>

		        public init(owner: @escaping (Analytics) -> __safeDI_PanelCarrier_Owner<__safeDI_Built>) {
		            self.owner = owner
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.init(owner: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_PanelCarrier_Owner<__safeDI_Built> {
		        public let held: () -> ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder

		        public init(held: @escaping () -> ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.held = held
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.init(held: { __safeDI_builder })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(panelBuilder: @escaping Instantiator<Panel>.Builder) {
		        self.init(__safeDI_panelBuilder: .init(__safeDI_noScope: panelBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_panelBuilder: __safeDI_PanelCarrier<Panel>) {
		        let analytics = Analytics()
		        let __safeDI_panelBuilder_owner = __safeDI_panelBuilder.owner(analytics)
		        @inline(never) func __safeDI_owner() -> Owner {
		            let held = Instantiator<Panel>(__safeDI_panelBuilder_owner.held())
		            return Owner(held: held)
		        }
		        let owner: Owner = __safeDI_owner()
		        self.init(analytics: analytics, owner: owner)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_3FD0696F93E2AF30 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_3FD0696F93E2AF30.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_panelBuilder_Host_Owner_Scope_held(analytics: Analytics) -> Instantiator<Panel>.Builder {
		                func __safeDI_held(name: String) -> DefaultPanel {
		                    DefaultPanel(name: name, analytics: analytics)
		                }
		                return { forwarded in __safeDI_held(name: forwarded) }
		            }
		            func __safeDI_panelBuilder_Host() -> Host.__safeDI_PanelCarrier<Panel> {
		                .init(owner: { values_analytics in __safeDI_panelBuilder_Host_Owner_Scope(analytics: values_analytics) })
		            }
		            func __safeDI_panelBuilder_Host_Owner_Scope(analytics: Analytics) -> Host.__safeDI_PanelCarrier_Owner<Panel> {
		                .init(held: { __safeDI_panelBuilder_Host_Owner_Scope_held(analytics: analytics) })
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_TokenGadget_GadgetCarrier<__safeDI_Built> {
		        public let erased: () -> ErasedInstantiator<Token, __safeDI_Built>.Builder

		        public init(erased: @escaping () -> ErasedInstantiator<Token, __safeDI_Built>.Builder) {
		            self.erased = erased
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Token, __safeDI_Built>.Builder) {
		            self.init(erased: { __safeDI_builder })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    package convenience init(tokenGadget_GadgetBuilder: @escaping ErasedInstantiator<Token, any Gadget>.Builder) {
		        self.init(__safeDI_tokenGadget_GadgetBuilder: .init(__safeDI_noScope: tokenGadget_GadgetBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    package convenience init(__safeDI_tokenGadget_GadgetBuilder: __safeDI_TokenGadget_GadgetCarrier<any Gadget>) {
		        let erased = ErasedInstantiator<Token, any Gadget>(__safeDI_tokenGadget_GadgetBuilder.erased())
		        self.init(erased: erased)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_19C2FF16BD4AB24A {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_19C2FF16BD4AB24A.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_tokenGadget_GadgetBuilder_Host_erased() -> ErasedInstantiator<Token, any Gadget>.Builder {
		                func __safeDI_erased(token: Token) -> TokenGadget {
		                    TokenGadget(token: token)
		                }
		                return { forwarded in __safeDI_erased(token: forwarded) }
		            }
		            func __safeDI_tokenGadget_GadgetBuilder_Host() -> Host.__safeDI_TokenGadget_GadgetCarrier<any Gadget> {
		                .init(erased: { __safeDI_tokenGadget_GadgetBuilder_Host_erased() })
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

	/// `Feature`'s seam `Home`, whose `Screen` builds itself again beside a place that reads its forwarded `id`, held by a seam
	/// `Outer` where `throughOuterSeam`; `App`, whose `LiveGadget` fills the place; and the same types with `LiveGadget`
	/// in `Feature`, which builds the tree inline.
	private static func screenModules(throughOuterSeam: Bool) -> (modules: [ModuleFixture], visibleModules: [ModuleFixture]) {
		var featureTypes = [
			seamFixtureType(named: "Screen", isFinalClass: true, declarations: [
				"@Forwarded public let id: Int",
				#"@Instantiated(fulfilledByType: "LiveGadget") public let panel: ErasedInstantiator<String, any Gadget>"#,
				"@Instantiated public let next: Instantiator<Screen>",
			]),
			seamFixtureType(named: "Home", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let screenBuilder: Instantiator<Screen>"]),
		]
		if throughOuterSeam {
			featureTypes.append(seamFixtureType(named: "Outer", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let home: Home"]))
		}
		let root = seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: [throughOuterSeam ? "@Instantiated public let outer: Outer" : "@Instantiated public let home: Home"])
		let probe = """
		func firstScreenIsFreed(holdingDepth depth: Int) -> Bool {
		    weak var firstScreen: Screen?
		    var heldScreen: Screen?
		    do {
		        var screen = \(throughOuterSeam ? "Root().outer.home" : "Root().home").screenBuilder.instantiate(1)
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
