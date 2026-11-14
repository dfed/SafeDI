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
private func seamCallComment(seam: String, module: String = "Feature") -> String {
	MultiModuleIntegration.moduleInfo.seamCallComment(type: seam, declaringModule: module)
}

/// A hole held in a wrapper: the builder returns the plain value, the seam builds the wrapper around it, and an
/// instantiator's forwarded value reaches the builder as a second argument.
struct SafeDIToolSeamBuiltWrapperTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Each wrapper kind

	enum WrapperKind: CaseIterable, CustomTestStringConvertible {
		case lazilyInstantiated
		case sendableLazilyInstantiated
		case instantiator
		case sendableInstantiator
		case erasedInstantiator
		case sendableErasedInstantiator

		var testDescription: String {
			switch self {
			case .lazilyInstantiated: "LazilyInstantiated"
			case .sendableLazilyInstantiated: "SendableLazilyInstantiated"
			case .instantiator: "Instantiator"
			case .sendableInstantiator: "SendableInstantiator"
			case .erasedInstantiator: "ErasedInstantiator"
			case .sendableErasedInstantiator: "SendableErasedInstantiator"
			}
		}

		var declaration: String {
			switch self {
			case .lazilyInstantiated:
				"@Instantiated let part: LazilyInstantiated<any Gadget>"
			case .sendableLazilyInstantiated:
				"@Instantiated let part: SendableLazilyInstantiated<any Gadget>"
			case .instantiator:
				"@Instantiated let part: Instantiator<Panel>"
			case .sendableInstantiator:
				"@Instantiated let part: SendableInstantiator<Panel>"
			case .erasedInstantiator:
				#"@Instantiated(fulfilledByType: "NamedGadget", erasedToConcreteExistential: true) let part: ErasedInstantiator<String, AnyGadget>"#
			case .sendableErasedInstantiator:
				#"@Instantiated(fulfilledByType: "NamedGadget", erasedToConcreteExistential: true) let part: SendableErasedInstantiator<String, AnyGadget>"#
			}
		}

		/// The expression that reads what the wrapper builds, off `Root().host.part`.
		var probe: String {
			switch self {
			case .lazilyInstantiated, .sendableLazilyInstantiated:
				"Root().host.part.instance"
			case .instantiator, .sendableInstantiator, .erasedInstantiator, .sendableErasedInstantiator:
				#"Root().host.part.instantiate("name")"#
			}
		}

		/// The name of the guard enum `Host` generates.
		var guardName: String {
			switch self {
			case .lazilyInstantiated: "__safeDI_Host_9B8BA77C92B219CB"
			case .sendableLazilyInstantiated: "__safeDI_Host_E32638A1B37D9B10"
			case .instantiator: "__safeDI_Host_C853E827EA721EA0"
			case .sendableInstantiator: "__safeDI_Host_0830438FF9BAA4FD"
			case .erasedInstantiator: "__safeDI_Host_BF69399EFF57D7FC"
			case .sendableErasedInstantiator: "__safeDI_Host_58303B264F50232B"
			}
		}

		var seamBody: String {
			switch self {
			case .lazilyInstantiated:
				"""
				extension Host {
				    @frozen public enum SafeDIScope_Gadget {
				        case part(part_Values)

				        public struct part_Values {
				            public let analytics: Analytics
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public init(__safeDI_analytics analytics: Analytics, __safeDI_gadgetBuilder: @escaping (SafeDIScope_Gadget) -> any Gadget) {
				        func __safeDI_part() -> any Gadget {
				            __safeDI_gadgetBuilder(.part(SafeDIScope_Gadget.part_Values(analytics: analytics)))
				        }
				        let part = LazilyInstantiated<any Gadget>(__safeDI_part)
				        self.init(analytics: analytics, part: part)
				    }
				}
				"""
			case .sendableLazilyInstantiated:
				"""
				extension Host {
				    @frozen public enum SafeDISendableScope_Gadget {
				        case part
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public init(__safeDI_analytics analytics: Analytics, __safeDI_gadgetSendableBuilder: @escaping @Sendable (SafeDISendableScope_Gadget) -> any Gadget) {
				        @Sendable func __safeDI_part() -> any Gadget {
				            __safeDI_gadgetSendableBuilder(.part)
				        }
				        let part = SendableLazilyInstantiated<any Gadget>(__safeDI_part)
				        self.init(analytics: analytics, part: part)
				    }
				}
				"""
			case .instantiator:
				"""
				extension Host {
				    @frozen public enum SafeDIScope_Panel {
				        case part(part_Values, Panel.ForwardedProperties)

				        public struct part_Values {
				            public let analytics: Analytics
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public init(__safeDI_analytics analytics: Analytics, __safeDI_panelBuilder: @escaping (SafeDIScope_Panel) -> Panel) {
				        let part = Instantiator<Panel> {
				            __safeDI_panelBuilder(.part(SafeDIScope_Panel.part_Values(analytics: analytics), $0))
				        }
				        self.init(analytics: analytics, part: part)
				    }
				}
				"""
			case .sendableInstantiator:
				"""
				extension Host {
				    @frozen public enum SafeDISendableScope_Panel {
				        case part(Panel.ForwardedProperties)
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public init(__safeDI_analytics analytics: Analytics, __safeDI_panelSendableBuilder: @escaping @Sendable (SafeDISendableScope_Panel) -> Panel) {
				        let part = SendableInstantiator<Panel> {
				            __safeDI_panelSendableBuilder(.part($0))
				        }
				        self.init(analytics: analytics, part: part)
				    }
				}
				"""
			case .erasedInstantiator:
				"""
				extension Host {
				    @frozen public enum SafeDIScope_NamedGadget {
				        case part(part_Values, String)

				        public struct part_Values {
				            public let analytics: Analytics
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public init(__safeDI_analytics analytics: Analytics, __safeDI_namedGadgetBuilder: @escaping (SafeDIScope_NamedGadget) -> AnyGadget) {
				        let part = ErasedInstantiator<String, AnyGadget> {
				            __safeDI_namedGadgetBuilder(.part(SafeDIScope_NamedGadget.part_Values(analytics: analytics), $0))
				        }
				        self.init(analytics: analytics, part: part)
				    }
				}
				"""
			case .sendableErasedInstantiator:
				"""
				extension Host {
				    @frozen public enum SafeDISendableScope_NamedGadget {
				        case part(String)
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public init(__safeDI_analytics analytics: Analytics, __safeDI_namedGadgetSendableBuilder: @escaping @Sendable (SafeDISendableScope_NamedGadget) -> AnyGadget) {
				        let part = SendableErasedInstantiator<String, AnyGadget> {
				            __safeDI_namedGadgetSendableBuilder(.part($0))
				        }
				        self.init(analytics: analytics, part: part)
				    }
				}
				"""
			}
		}

		var fillCode: String {
			switch self {
			case .lazilyInstantiated:
				"""
				            func __safeDI_gadgetBuilder_Host(_ scope: Host.SafeDIScope_Gadget) -> any Gadget {
				                switch scope {
				                case let .part(scope):
				                    let analytics = scope.analytics
				                    func __safeDI_part() -> DefaultGadget {
				                        DefaultGadget(analytics: analytics)
				                    }
				                    return __safeDI_part()
				                }
				            }
				            return Host(__safeDI_analytics: analytics, __safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Host)
				"""
			case .sendableLazilyInstantiated:
				"""
				            @Sendable func __safeDI_gadgetSendableBuilder_Host(_ scope: Host.SafeDISendableScope_Gadget) -> any Gadget {
				                switch scope {
				                case .part:
				                    @Sendable func __safeDI_part() -> DefaultGadget {
				                        DefaultGadget(analytics: analytics)
				                    }
				                    return __safeDI_part()
				                }
				            }
				            return Host(__safeDI_analytics: analytics, __safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_Host)
				"""
			case .instantiator:
				"""
				            func __safeDI_panelBuilder_Host(_ scope: Host.SafeDIScope_Panel) -> Panel {
				                switch scope {
				                case let .part(scope, __safeDI_forwarded):
				                    let analytics = scope.analytics
				                    func __safeDI_part(name: String) -> DefaultPanel {
				                        DefaultPanel(name: name, analytics: analytics)
				                    }
				                    return __safeDI_part(name: __safeDI_forwarded)
				                }
				            }
				            return Host(__safeDI_analytics: analytics, __safeDI_panelBuilder: __safeDI_panelBuilder_Host)
				"""
			case .sendableInstantiator:
				"""
				            @Sendable func __safeDI_panelSendableBuilder_Host(_ scope: Host.SafeDISendableScope_Panel) -> Panel {
				                switch scope {
				                case let .part(__safeDI_forwarded):
				                    @Sendable func __safeDI_part(name: String) -> DefaultPanel {
				                        DefaultPanel(name: name, analytics: analytics)
				                    }
				                    return __safeDI_part(name: __safeDI_forwarded)
				                }
				            }
				            return Host(__safeDI_analytics: analytics, __safeDI_panelSendableBuilder: __safeDI_panelSendableBuilder_Host)
				"""
			case .erasedInstantiator:
				"""
				            func __safeDI_namedGadgetBuilder_Host(_ scope: Host.SafeDIScope_NamedGadget) -> AnyGadget {
				                switch scope {
				                case let .part(scope, __safeDI_forwarded):
				                    let analytics = scope.analytics
				                    func __safeDI_part(name: String) -> NamedGadget {
				                        NamedGadget(name: name, analytics: analytics)
				                    }
				                    return AnyGadget(__safeDI_part(name: __safeDI_forwarded))
				                }
				            }
				            return Host(__safeDI_analytics: analytics, __safeDI_namedGadgetBuilder: __safeDI_namedGadgetBuilder_Host)
				"""
			case .sendableErasedInstantiator:
				"""
				            @Sendable func __safeDI_namedGadgetSendableBuilder_Host(_ scope: Host.SafeDISendableScope_NamedGadget) -> AnyGadget {
				                switch scope {
				                case let .part(__safeDI_forwarded):
				                    @Sendable func __safeDI_part(name: String) -> NamedGadget {
				                        NamedGadget(name: name, analytics: analytics)
				                    }
				                    return AnyGadget(__safeDI_part(name: __safeDI_forwarded))
				                }
				            }
				            return Host(__safeDI_analytics: analytics, __safeDI_namedGadgetSendableBuilder: __safeDI_namedGadgetSendableBuilder_Host)
				"""
			}
		}
	}

	@Test(arguments: WrapperKind.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsWrapperAroundBuilderThatReturnsPlainValue_whenHoleIsHeldInWrapper(wrapper: WrapperKind) async throws {
		let feature = Self.featureFiles(hostDeclarations: ["@Received let analytics: Analytics", wrapper.declaration])
		let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: Self.fulfillers + [Self.rootInstantiatingAnalytics])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + """
		\(wrapper.seamBody)

		extension Host {
		    public enum \(wrapper.guardName) {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, SafeDIToolSeamBuilderParameterTests.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        let analytics = Analytics()
		        func __safeDI_host() -> Host {
		            _ = Host.\(wrapper.guardName).self\(seamCallComment(seam: "Host"))
		\(wrapper.fillCode)
		        }
		        let host: Host = __safeDI_host()
		        self.init(analytics: analytics, host: host)
		    }
		}
		"""]))
		try await expectValuesEqualVisibleBuild(
			output,
			modules: modules,
			visibleModules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature + Self.fulfillers, app: [Self.rootInstantiatingAnalytics]),
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe(wrapper.probe)],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_annotatesWrapperItBuildsAndEscapesForwardedValue_whenInstantiatorForwardsNonisolatedNonsendingFunction() async throws {
		// Swift's expression parser does not read `nonisolated(nonsending)` in a generic argument, so the type is on the
		// declaration; and a forwarded function escapes, as the instantiated type holds it.
		let feature = Self.featureFiles(hostDeclarations: [
			"@Instantiated let analytics: Analytics",
			#"@Instantiated(fulfilledByType: "ActionGadget") let part: ErasedInstantiator<nonisolated(nonsending) () async -> Void, any Gadget>"#,
		])
		let fulfillers = [
			"""
			@Instantiable
			public struct ActionGadget: Instantiable, Gadget, @unchecked Sendable {
			    public init(run: nonisolated(nonsending) @escaping () async -> Void, analytics: Analytics) {
			        self.run = run
			        self.analytics = analytics
			    }

			    @Forwarded let run: nonisolated(nonsending) () async -> Void
			    @Received let analytics: Analytics
			}
			""",
		]
		let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: fulfillers + [Self.root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen public enum SafeDIScope_ActionGadget {
		        case part(part_Values, _ forwarded: nonisolated(nonsending) () async -> Void)

		        public struct part_Values {
		            public let analytics: Analytics
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_actionGadgetBuilder: @escaping (SafeDIScope_ActionGadget) -> any Gadget) {
		        let analytics = Analytics()
		        let part: ErasedInstantiator<nonisolated(nonsending) () async -> Void, any Gadget> = ErasedInstantiator {
		            __safeDI_actionGadgetBuilder(.part(SafeDIScope_ActionGadget.part_Values(analytics: analytics), $0))
		        }
		        self.init(analytics: analytics, part: part)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_5BA86AD11D2C29CA {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, SafeDIToolSeamBuilderParameterTests.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_5BA86AD11D2C29CA.self\(seamCallComment(seam: "Host"))
		            func __safeDI_actionGadgetBuilder_Host(_ scope: Host.SafeDIScope_ActionGadget) -> any Gadget {
		                switch scope {
		                case let .part(scope, __safeDI_forwarded):
		                    let analytics = scope.analytics
		                    func __safeDI_part(run: nonisolated(nonsending) @escaping () async -> Void) -> ActionGadget {
		                        ActionGadget(run: run, analytics: analytics)
		                    }
		                    return __safeDI_part(run: __safeDI_forwarded)
		                }
		            }
		            return Host(__safeDI_actionGadgetBuilder: __safeDI_actionGadgetBuilder_Host)
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""]))
	}

	// MARK: Forwarded values

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsBuilderForwardedTupleAndFillSpreadsIt_whenInstantiatorForwardsSeveralValues() async throws {
		let feature = Self.featureFiles(hostDeclarations: [
			"@Instantiated let analytics: Analytics",
			#"@Instantiated(fulfilledByType: "PairGadget") let erased: ErasedInstantiator<(count: Int, name: String), any Gadget>"#,
			"@Instantiated let held: Instantiator<PairPanel>",
		])
		let fulfillers = [
			seamFixtureType(named: "PairGadget", declarations: ["@Forwarded let count: Int", "@Forwarded let name: String", "@Received let analytics: Analytics"], conformances: ", Gadget"),
			"""
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
			""",
		]
		let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: fulfillers + [Self.root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen public enum SafeDIScope_PairGadget {
		        case erased(erased_Values, (count: Int, name: String))

		        public struct erased_Values {
		            public let analytics: Analytics
		        }
		    }

		    @frozen public enum SafeDIScope_PairPanel {
		        case held(held_Values, PairPanel.ForwardedProperties)

		        public struct held_Values {
		            public let analytics: Analytics
		            public let erased: ErasedInstantiator<(count: Int, name: String), any Gadget>
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_pairGadgetBuilder: @escaping (SafeDIScope_PairGadget) -> any Gadget, __safeDI_pairPanelBuilder: @escaping (SafeDIScope_PairPanel) -> PairPanel) {
		        let analytics = Analytics()
		        let erased = ErasedInstantiator<(count: Int, name: String), any Gadget> {
		            __safeDI_pairGadgetBuilder(.erased(SafeDIScope_PairGadget.erased_Values(analytics: analytics), $0))
		        }
		        let held = Instantiator<PairPanel> {
		            __safeDI_pairPanelBuilder(.held(SafeDIScope_PairPanel.held_Values(analytics: analytics, erased: erased), $0))
		        }
		        self.init(analytics: analytics, erased: erased, held: held)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_BF5BA56FCD20D4A7 {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, SafeDIToolSeamBuilderParameterTests.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_BF5BA56FCD20D4A7.self\(seamCallComment(seam: "Host"))
		            func __safeDI_pairGadgetBuilder_Host(_ scope: Host.SafeDIScope_PairGadget) -> any Gadget {
		                switch scope {
		                case let .erased(scope, __safeDI_forwarded):
		                    let analytics = scope.analytics
		                    func __safeDI_erased(count: Int, name: String) -> PairGadget {
		                        PairGadget(count: count, name: name, analytics: analytics)
		                    }
		                    return __safeDI_erased(count: __safeDI_forwarded.count, name: __safeDI_forwarded.name)
		                }
		            }
		            func __safeDI_pairPanelBuilder_Host(_ scope: Host.SafeDIScope_PairPanel) -> PairPanel {
		                switch scope {
		                case let .held(scope, __safeDI_forwarded):
		                    let analytics = scope.analytics
		                    func __safeDI_held(count: Int, name: String) -> DefaultPairPanel {
		                        DefaultPairPanel(count: count, name: name, analytics: analytics)
		                    }
		                    return __safeDI_held(count: __safeDI_forwarded.count, name: __safeDI_forwarded.name)
		                }
		            }
		            return Host(__safeDI_pairGadgetBuilder: __safeDI_pairGadgetBuilder_Host, __safeDI_pairPanelBuilder: __safeDI_pairPanelBuilder_Host)
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""]))
		try await expectValuesEqualVisibleBuild(
			output,
			modules: modules,
			visibleModules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature + fulfillers, app: [Self.root]),
			probes: [
				DifferentialValueProbe("Root()"),
				DifferentialValueProbe(#"Root().host.erased.instantiate((count: 2, name: "two"))"#),
				DifferentialValueProbe(#"Root().host.held.instantiate((count: 3, name: "three"))"#),
			],
		)
	}

	@Test(arguments: ["()", "Void"])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesNoForwardedValue_whenErasedInstantiatorForwardsSpelledEmpty(spelling: String) async throws {
		let feature = Self.featureFiles(hostDeclarations: [
			"@Instantiated let analytics: Analytics",
			#"@Instantiated(fulfilledByType: "DefaultGadget") let part: ErasedInstantiator<\#(spelling), any Gadget>"#,
		])
		let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: Self.fulfillers + [Self.root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen public enum SafeDIScope_DefaultGadget {
		        case part(part_Values)

		        public struct part_Values {
		            public let analytics: Analytics
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_defaultGadgetBuilder: @escaping (SafeDIScope_DefaultGadget) -> any Gadget) {
		        let analytics = Analytics()
		        func __safeDI_part() -> any Gadget {
		            __safeDI_defaultGadgetBuilder(.part(SafeDIScope_DefaultGadget.part_Values(analytics: analytics)))
		        }
		        let part = ErasedInstantiator<\(spelling), any Gadget>(__safeDI_part)
		        self.init(analytics: analytics, part: part)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_1FA9019FE93E5E4C {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, SafeDIToolSeamBuilderParameterTests.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_1FA9019FE93E5E4C.self\(seamCallComment(seam: "Host"))
		            func __safeDI_defaultGadgetBuilder_Host(_ scope: Host.SafeDIScope_DefaultGadget) -> any Gadget {
		                switch scope {
		                case let .part(scope):
		                    let analytics = scope.analytics
		                    func __safeDI_part() -> DefaultGadget {
		                        DefaultGadget(analytics: analytics)
		                    }
		                    return __safeDI_part()
		                }
		            }
		            return Host(__safeDI_defaultGadgetBuilder: __safeDI_defaultGadgetBuilder_Host)
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""]))
		try await expectValuesEqualVisibleBuild(
			output,
			modules: modules,
			visibleModules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature + Self.fulfillers, app: [Self.root]),
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().host.part.instantiate()")],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_carriesForwardedPropertiesOfVoid_whenInstantiatorsTypeForwardsNothing() async throws {
		// The seam cannot see whether the type forwards anything, so `Instantiator<T>` always takes `T.ForwardedProperties`.
		let feature = Self.featureFiles(hostDeclarations: ["@Instantiated let analytics: Analytics", "@Instantiated let held: Instantiator<EmptyPanel>"])
		let fulfillers = [
			"""
			@Instantiable(fulfillingAdditionalTypes: [EmptyPanel.self], conformsElsewhere: true)
			public final class DefaultEmptyPanel: EmptyPanel, @unchecked Sendable {
			    public init(analytics: Analytics) {
			        self.analytics = analytics
			        super.init()
			    }

			    @Received let analytics: Analytics
			}
			""",
		]
		let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: fulfillers + [Self.root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen public enum SafeDIScope_EmptyPanel {
		        case held(held_Values, EmptyPanel.ForwardedProperties)

		        public struct held_Values {
		            public let analytics: Analytics
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_emptyPanelBuilder: @escaping (SafeDIScope_EmptyPanel) -> EmptyPanel) {
		        let analytics = Analytics()
		        let held = Instantiator<EmptyPanel> {
		            __safeDI_emptyPanelBuilder(.held(SafeDIScope_EmptyPanel.held_Values(analytics: analytics), $0))
		        }
		        self.init(analytics: analytics, held: held)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_CA10D85E14C0AF30 {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, SafeDIToolSeamBuilderParameterTests.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_CA10D85E14C0AF30.self\(seamCallComment(seam: "Host"))
		            func __safeDI_emptyPanelBuilder_Host(_ scope: Host.SafeDIScope_EmptyPanel) -> EmptyPanel {
		                switch scope {
		                case let .held(scope, _):
		                    let analytics = scope.analytics
		                    func __safeDI_held() -> DefaultEmptyPanel {
		                        DefaultEmptyPanel(analytics: analytics)
		                    }
		                    return __safeDI_held()
		                }
		            }
		            return Host(__safeDI_emptyPanelBuilder: __safeDI_emptyPanelBuilder_Host)
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""]))
		try await expectValuesEqualVisibleBuild(
			output,
			modules: modules,
			visibleModules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature + fulfillers, app: [Self.root]),
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().host.held.instantiate()")],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesFillsForwardedParameterApartFromBuilderFunction_whenWrapperPropertyIsLabeledForwarded() async throws {
		// The property's builder function would otherwise hide the fill's parameter on the fill's last line.
		let feature = Self.featureFiles(hostDeclarations: ["@Instantiated let analytics: Analytics", "@Instantiated let forwarded: Instantiator<Panel>"])
		let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: Self.fulfillers + [Self.root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, SafeDIToolSeamBuilderParameterTests.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_90B07FAED07A2781.self\(seamCallComment(seam: "Host"))
		            func __safeDI_panelBuilder_Host(_ scope: Host.SafeDIScope_Panel) -> Panel {
		                switch scope {
		                case let .forwarded(scope, __safeDI_forwarded_):
		                    let analytics = scope.analytics
		                    func __safeDI_forwarded(name: String) -> DefaultPanel {
		                        DefaultPanel(name: name, analytics: analytics)
		                    }
		                    return __safeDI_forwarded(name: __safeDI_forwarded_)
		                }
		            }
		            return Host(__safeDI_panelBuilder: __safeDI_panelBuilder_Host)
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""]))
		try await expectValuesEqualVisibleBuild(
			output,
			modules: modules,
			visibleModules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature + Self.fulfillers, app: [Self.root]),
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe(#"Root().host.forwarded.instantiate("name")"#)],
		)
	}

	// MARK: A fulfiller that repeats the wrapper property

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_closesCycleOnFillsBuilderFunction_whenFulfillerRepeatsWrapperProperty(isSendable: Bool) async throws {
		let wrapper = isSendable ? "SendableErasedInstantiator" : "ErasedInstantiator"
		let feature = Self.featureFiles(hostDeclarations: [#"@Instantiated(fulfilledByType: "LoopingGadget") let again: \#(wrapper)<String, any Gadget>"#])
		let fulfillers = [
			seamFixtureType(named: "LoopingGadget", declarations: ["@Forwarded let name: String", #"@Instantiated(fulfilledByType: "LoopingGadget") let again: \#(wrapper)<String, any Gadget>"#], conformances: ", Gadget, @unchecked Sendable"),
		]
		let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: fulfillers + [Self.root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, SafeDIToolSeamBuilderParameterTests.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": isSendable ? """
		extension Root {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_B7E9B110589C6933.self\(seamCallComment(seam: "Host"))
		            @Sendable func __safeDI_loopingGadgetSendableBuilder_Host(_ scope: Host.SafeDISendableScope_LoopingGadget) -> any Gadget {
		                switch scope {
		                case let .again(__safeDI_forwarded):
		                    @Sendable func __safeDI_again(name: String) -> LoopingGadget {
		                        let again = SendableErasedInstantiator<String, any Gadget> {
		                            __safeDI_again(name: $0)
		                        }
		                        return LoopingGadget(name: name, again: again)
		                    }
		                    return __safeDI_again(name: __safeDI_forwarded)
		                }
		            }
		            return Host(__safeDI_loopingGadgetSendableBuilder: __safeDI_loopingGadgetSendableBuilder_Host)
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		""" : """
		extension Root {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_9C11E6151230103C.self\(seamCallComment(seam: "Host"))
		            func __safeDI_loopingGadgetBuilder_Host(_ scope: Host.SafeDIScope_LoopingGadget) -> any Gadget {
		                switch scope {
		                case let .again(_, __safeDI_forwarded):
		                    func __safeDI_again(name: String) -> LoopingGadget {
		                        let again = ErasedInstantiator<String, any Gadget> {
		                            __safeDI_again(name: $0)
		                        }
		                        return LoopingGadget(name: name, again: again)
		                    }
		                    return __safeDI_again(name: __safeDI_forwarded)
		                }
		            }
		            return Host(__safeDI_loopingGadgetBuilder: __safeDI_loopingGadgetBuilder_Host)
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""]))
		try await expectValuesEqualVisibleBuild(
			output,
			modules: modules,
			visibleModules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature + fulfillers, app: [Self.root]),
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe(#"Root().host.again.instantiate("name")"#)],
		)
	}

	// MARK: A wrapper hole inside a `@Sendable` function

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_carriesForwardedValueInCase_whenPlainWrapperHoleIsInsideSendableFunction() async throws {
		let feature = Self.featureFiles(hostDeclarations: [
			"@Received let analytics: Analytics",
			"@Instantiated let ownerBuilder: SendableInstantiator<Owner>",
		], otherFiles: [
			seamFixtureType(named: "Owner", declarations: ["@Instantiated let held: Instantiator<Panel>"], conformances: ", @unchecked Sendable"),
		])
		let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: Self.fulfillers + [Self.rootInstantiatingAnalytics])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen public enum SafeDIScope_Panel {
		        @frozen public enum Owner_Scope {
		            case held(held_Values, Panel.ForwardedProperties)

		            public struct held_Values {}
		        }
		    }

		    @frozen public enum SafeDISendableScope_Panel {
		        case ownerBuilder(SafeDIScope_Panel.Owner_Scope)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_analytics analytics: Analytics, __safeDI_panelSendableBuilder: @escaping @Sendable (SafeDISendableScope_Panel) -> Panel) {
		        @Sendable func __safeDI_ownerBuilder() -> Owner {
		            let held = Instantiator<Panel> {
		                __safeDI_panelSendableBuilder(.ownerBuilder(.held(SafeDIScope_Panel.Owner_Scope.held_Values(), $0)))
		            }
		            return Owner(held: held)
		        }
		        let ownerBuilder = SendableInstantiator<Owner>(__safeDI_ownerBuilder)
		        self.init(analytics: analytics, ownerBuilder: ownerBuilder)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_638E6CAD02119102 {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, SafeDIToolSeamBuilderParameterTests.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        let analytics = Analytics()
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_638E6CAD02119102.self\(seamCallComment(seam: "Host"))
		            @Sendable func __safeDI_panelSendableBuilder_Host(_ scope: Host.SafeDISendableScope_Panel) -> Panel {
		                switch scope {
		                case let .ownerBuilder(scope): return __safeDI_panelBuilder_Host_Owner_Scope(scope)
		                }
		            }
		            @Sendable func __safeDI_panelBuilder_Host_Owner_Scope(_ scope: Host.SafeDIScope_Panel.Owner_Scope) -> Panel {
		                switch scope {
		                case let .held(_, __safeDI_forwarded):
		                    func __safeDI_held(name: String) -> DefaultPanel {
		                        DefaultPanel(name: name, analytics: analytics)
		                    }
		                    return __safeDI_held(name: __safeDI_forwarded)
		                }
		            }
		            return Host(__safeDI_analytics: analytics, __safeDI_panelSendableBuilder: __safeDI_panelSendableBuilder_Host)
		        }
		        let host: Host = __safeDI_host()
		        self.init(analytics: analytics, host: host)
		    }
		}
		"""]))
		try await expectValuesEqualVisibleBuild(
			output,
			modules: modules,
			visibleModules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature + Self.fulfillers, app: [Self.rootInstantiatingAnalytics]),
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe(#"Root().host.ownerBuilder.instantiate().held.instantiate("name")"#)],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_carriesNothingInWrappersCase_whenSendableWrapperHoleIsInsideSendableFunction() async throws {
		let feature = Self.featureFiles(hostDeclarations: [
			"@Received let analytics: Analytics",
			"@Instantiated let ownerBuilder: SendableInstantiator<Owner>",
		], otherFiles: [
			seamFixtureType(named: "Tally", isFinalClass: true, declarations: [], conformances: ", Sendable"),
			seamFixtureType(named: "Owner", declarations: ["@Instantiated let tally: Tally", "@Instantiated let held: SendableInstantiator<Panel>"], conformances: ", Sendable"),
		])
		let fulfillers = [
			"""
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
			""",
		]
		let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: fulfillers + [Self.rootInstantiatingAnalytics])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen public enum SafeDISendableScope_Panel {
		        case ownerBuilder_Sendable(SafeDISendableScope_Panel.Owner_Scope)

		        @frozen public enum Owner_Scope {
		            case held(Panel.ForwardedProperties)
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_analytics analytics: Analytics, __safeDI_panelSendableBuilder: @escaping @Sendable (SafeDISendableScope_Panel) -> Panel) {
		        @Sendable func __safeDI_ownerBuilder() -> Owner {
		            let tally = Tally()
		            let held = SendableInstantiator<Panel> {
		                __safeDI_panelSendableBuilder(.ownerBuilder_Sendable(.held($0)))
		            }
		            return Owner(tally: tally, held: held)
		        }
		        let ownerBuilder = SendableInstantiator<Owner>(__safeDI_ownerBuilder)
		        self.init(analytics: analytics, ownerBuilder: ownerBuilder)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_6A52DAF3E354F43E {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, SafeDIToolSeamBuilderParameterTests.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        let analytics = Analytics()
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_6A52DAF3E354F43E.self\(seamCallComment(seam: "Host"))
		            @Sendable func __safeDI_panelSendableBuilder_Host(_ scope: Host.SafeDISendableScope_Panel) -> Panel {
		                switch scope {
		                case let .ownerBuilder_Sendable(scope): return __safeDI_panelSendableBuilder_Host_Owner_Scope(scope)
		                }
		            }
		            @Sendable func __safeDI_panelSendableBuilder_Host_Owner_Scope(_ scope: Host.SafeDISendableScope_Panel.Owner_Scope) -> Panel {
		                switch scope {
		                case let .held(__safeDI_forwarded):
		                    @Sendable func __safeDI_held(name: String) -> DefaultPanel {
		                        DefaultPanel(name: name, analytics: analytics)
		                    }
		                    return __safeDI_held(name: __safeDI_forwarded)
		                }
		            }
		            return Host(__safeDI_analytics: analytics, __safeDI_panelSendableBuilder: __safeDI_panelSendableBuilder_Host)
		        }
		        let host: Host = __safeDI_host()
		        self.init(analytics: analytics, host: host)
		    }
		}
		"""]))
		try await expectValuesEqualVisibleBuild(
			output,
			modules: modules,
			visibleModules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature + fulfillers, app: [Self.rootInstantiatingAnalytics]),
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe(#"Root().host.ownerBuilder.instantiate().held.instantiate("name")"#)],
		)
	}

	// MARK: Passed up and filled by a seam

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesUpBuilderThatReturnsPlainValue_whenInnerSeamsHoleIsHeldInWrapper() async throws {
		let feature = [
			"""
			open class Panel: Instantiable, @unchecked Sendable {
			    public typealias ForwardedProperties = String

			    public init(title: String) {
			        self.title = title
			    }

			    public let title: String
			}
			""",
			seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated let part: Instantiator<Panel>"]),
			seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated let inner: Inner"]),
		]
		let fulfillers = [
			"""
			@Instantiable(fulfillingAdditionalTypes: [Panel.self], conformsElsewhere: true)
			public final class DefaultPanel: Panel, @unchecked Sendable {
			    public init(name: String) {
			        self.name = name
			        super.init(title: name)
			    }

			    @Forwarded let name: String
			}
			""",
		]
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let outer: Outer"])
		let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: fulfillers + [root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + """
		extension Inner {
		    @frozen public enum SafeDIScope_Panel {
		        case part(part_Values, Panel.ForwardedProperties)

		        public struct part_Values {}
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_panelBuilder: @escaping (SafeDIScope_Panel) -> Panel) {
		        let part = Instantiator<Panel> {
		            __safeDI_panelBuilder(.part(SafeDIScope_Panel.part_Values(), $0))
		        }
		        self.init(part: part)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_0D39F8A8EF1A9F4A {}
		}

		extension Outer {
		    @frozen public enum SafeDIScope_Panel {
		        case inner(inner_Values, Inner.SafeDIScope_Panel)

		        public struct inner_Values {}
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_panelBuilder: @escaping (SafeDIScope_Panel) -> Panel) {
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_0D39F8A8EF1A9F4A.self
		            return Inner(__safeDI_panelBuilder: { __safeDI_panelBuilder(.inner(SafeDIScope_Panel.inner_Values(), $0)) })
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(inner: inner)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_28D7A7F2559D6961 {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, SafeDIToolSeamBuilderParameterTests.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_28D7A7F2559D6961.self\(seamCallComment(seam: "Outer"))
		            func __safeDI_panelBuilder_Outer(_ scope: Outer.SafeDIScope_Panel) -> Panel {
		                switch scope {
		                case let .inner(_, scope): return __safeDI_panelBuilder_Inner(scope)
		                }
		            }
		            func __safeDI_panelBuilder_Inner(_ scope: Inner.SafeDIScope_Panel) -> Panel {
		                switch scope {
		                case let .part(_, __safeDI_forwarded):
		                    func __safeDI_part(name: String) -> DefaultPanel {
		                        DefaultPanel(name: name)
		                    }
		                    return __safeDI_part(name: __safeDI_forwarded)
		                }
		            }
		            return Outer(__safeDI_panelBuilder: __safeDI_panelBuilder_Outer)
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(outer: outer)
		    }
		}
		"""]))
		try await expectValuesEqualVisibleBuild(
			output,
			modules: modules,
			visibleModules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature + fulfillers, app: [root]),
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe(#"Root().outer.inner.part.instantiate("name")"#)],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesSendableCaseForPlaceInsideFill_whenSeamFillsInnerSeamsHoleHeldInSendableWrapper() async throws {
		// `Host` fills `Inner`'s hole, held in a `Sendable` wrapper, with `DefaultWidget`, whose own hole `Host` passes up: the
		// fill is a `@Sendable` function, so that place is a case of its builder's `@Sendable` enum.
		let feature = [
			"public protocol Widget: Sendable {}",
			"public protocol Gadget: Sendable {}",
			seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated let widget: SendableLazilyInstantiated<any Widget>"]),
		]
		let middle = [
			"import Feature\n\n" + SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: ["@Instantiated let gadget: any Gadget"]),
			"import Feature\n\n" + seamFixtureType(named: "Host", isSeam: true, declarations: ["@Instantiated let inner: Inner"]),
		]
		let app = [
			SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultGadget", fulfilling: "Gadget", declarations: []),
			seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let host: Host"]),
		].map { "import Feature\nimport Middle\n\n" + $0 }
		let modules = [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature),
			ModuleFixture(name: "Middle", packageName: "Shop", swiftFileContent: middle, dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: app, dependencies: ["Feature", "Middle"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, SafeDIToolSeamBuilderParameterTests.generatedFiles(module: "Middle", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Host": """
		extension Host {
		    @frozen public enum SafeDIScope_Gadget {
		        @frozen public enum DefaultWidget_Scope {
		            case gadget(gadget_Values)

		            public struct gadget_Values {}
		        }
		    }

		    @frozen public enum SafeDISendableScope_Gadget {
		        case inner_widgetSendableBuilder(SafeDIScope_Gadget.DefaultWidget_Scope)
		    }

		    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_gadgetSendableBuilder: @escaping @Sendable (SafeDISendableScope_Gadget) -> any Gadget) {
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_6C2AA56F3C357B96.self\(seamCallComment(seam: "Inner"))
		            @Sendable func __safeDI_widgetSendableBuilder_Inner(_ scope: Inner.SafeDISendableScope_Widget) -> any Widget {
		                switch scope {
		                case .widget:
		                    @Sendable func __safeDI_widget() -> DefaultWidget {
		                        let gadget: any Gadget = __safeDI_gadgetSendableBuilder(.inner_widgetSendableBuilder(.gadget(SafeDIScope_Gadget.DefaultWidget_Scope.gadget_Values())))
		                        return DefaultWidget(gadget: gadget)
		                    }
		                    return __safeDI_widget()
		                }
		            }
		            return Inner(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Inner)
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(inner: inner)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_4C72CB4C58FBDC50 {}
		}
		"""]))
		try await expectValuesEqualVisibleBuild(
			output,
			modules: modules,
			visibleModules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature + [
					SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultGadget", fulfilling: "Gadget", declarations: []),
					SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: ["@Instantiated let gadget: any Gadget"]),
					seamFixtureType(named: "Host", isSeam: true, declarations: ["@Instantiated let inner: Inner"]),
				]),
				ModuleFixture(name: "App", packageName: "Other", swiftFileContent: ["import Feature\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let host: Host"])], dependencies: ["Feature"]),
			],
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().host.inner.widget.instance")],
		)
	}

	// MARK: Access

	@Test(arguments: ["public", "package"])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesBuilderAtSeamsAccess_whenWrapperHoleForwardsValueOfThatAccess(access: String) async throws {
		// The `App` of a `package` seam is in the seam's package, as it must be to read the `package` types the fill names.
		let packageOfApp = access == "package" ? "Shop" : "Other"
		let feature = [
			"\(access) protocol Gadget {}",
			"\(access) final class Label {\n    \(access) init() {}\n}",
			"""
			@Instantiable
			\(access) final class Analytics: Instantiable {
			    \(access) init() {}
			}
			""",
			"""
			@Instantiable(generateDependencyTree: true)
			\(access) struct Host: Instantiable {
			    \(access) init(analytics: Analytics, part: ErasedInstantiator<Label, any Gadget>) {
			        self.analytics = analytics
			        self.part = part
			    }

			    @Instantiated let analytics: Analytics
			    @Instantiated(fulfilledByType: "LabeledGadget") let part: ErasedInstantiator<Label, any Gadget>
			}
			""",
		]
		let fulfiller = """
		@Instantiable
		\(access) struct LabeledGadget: Instantiable, Gadget {
		    \(access) init(label: Label, analytics: Analytics) {
		        self.label = label
		        self.analytics = analytics
		    }

		    @Forwarded let label: Label
		    @Received let analytics: Analytics
		}
		"""
		let root = """
		@Instantiable(isRoot: true)
		\(access) struct Root: Instantiable {
		    \(access) init(host: Host) {
		        self.host = host
		    }

		    @Instantiated let host: Host
		}
		"""
		let modules = [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature),
			ModuleFixture(name: "App", packageName: packageOfApp, swiftFileContent: [fulfiller, root].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + (access == "public" ? """
		extension Host {
		    @frozen public enum SafeDIScope_LabeledGadget {
		        case part(part_Values, Label)

		        public struct part_Values {
		            public let analytics: Analytics
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_labeledGadgetBuilder: @escaping (SafeDIScope_LabeledGadget) -> any Gadget) {
		        let analytics = Analytics()
		        let part = ErasedInstantiator<Label, any Gadget> {
		            __safeDI_labeledGadgetBuilder(.part(SafeDIScope_LabeledGadget.part_Values(analytics: analytics), $0))
		        }
		        self.init(analytics: analytics, part: part)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_E08E0AA2DA391A90 {}
		}
		""" : """
		extension Host {
		    @frozen public enum SafeDIScope_LabeledGadget {
		        case part(part_Values, Label)

		        public struct part_Values {
		            package let analytics: Analytics
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    package init(__safeDI_labeledGadgetBuilder: @escaping (SafeDIScope_LabeledGadget) -> any Gadget) {
		        let analytics = Analytics()
		        let part = ErasedInstantiator<Label, any Gadget> {
		            __safeDI_labeledGadgetBuilder(.part(SafeDIScope_LabeledGadget.part_Values(analytics: analytics), $0))
		        }
		        self.init(analytics: analytics, part: part)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_50AF5FC9E4A60DE4 {}
		}
		""")])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, SafeDIToolSeamBuilderParameterTests.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": access == "public" ? """
		extension Root {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_E08E0AA2DA391A90.self\(seamCallComment(seam: "Host"))
		            func __safeDI_labeledGadgetBuilder_Host(_ scope: Host.SafeDIScope_LabeledGadget) -> any Gadget {
		                switch scope {
		                case let .part(scope, __safeDI_forwarded):
		                    let analytics = scope.analytics
		                    func __safeDI_part(label: Label) -> LabeledGadget {
		                        LabeledGadget(label: label, analytics: analytics)
		                    }
		                    return __safeDI_part(label: __safeDI_forwarded)
		                }
		            }
		            return Host(__safeDI_labeledGadgetBuilder: __safeDI_labeledGadgetBuilder_Host)
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		""" : """
		extension Root {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_50AF5FC9E4A60DE4.self\(seamCallComment(seam: "Host"))
		            func __safeDI_labeledGadgetBuilder_Host(_ scope: Host.SafeDIScope_LabeledGadget) -> any Gadget {
		                switch scope {
		                case let .part(scope, __safeDI_forwarded):
		                    let analytics = scope.analytics
		                    func __safeDI_part(label: Label) -> LabeledGadget {
		                        LabeledGadget(label: label, analytics: analytics)
		                    }
		                    return __safeDI_part(label: __safeDI_forwarded)
		                }
		            }
		            return Host(__safeDI_labeledGadgetBuilder: __safeDI_labeledGadgetBuilder_Host)
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""]))
		try await expectValuesEqualVisibleBuild(
			output,
			modules: modules,
			visibleModules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature + [fulfiller]),
				ModuleFixture(name: "App", packageName: packageOfApp, swiftFileContent: ["import Feature\n\n" + root], dependencies: ["Feature"]),
			],
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().host.part.instantiate(Label())")],
		)
	}

	// MARK: A hand-written call

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_compilesHandWrittenClosuresThatReturnPlainValues_whenCallerFillsWrapperHoles() async throws {
		let feature = Self.featureFiles(hostDeclarations: [
			"@Instantiated let lazy: LazilyInstantiated<any Gadget>",
			"@Instantiated let held: Instantiator<Panel>",
			"@Instantiated let sendableHeld: SendableInstantiator<Panel>",
		])
		let caller = """
		import Feature

		struct PlainGadget: Gadget {}

		func makeHost() -> Host {
		    Host(
		        gadgetBuilder: { _ in PlainGadget() },
		        panelBuilder: { scope in switch scope { case let .held(_, title): Panel(title: title) } },
		        panelSendableBuilder: { scope in switch scope { case let .sendableHeld(title): Panel(title: title) } }
		    )
		}
		"""
		_ = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature, swiftFileContentByFilePath: ["SafeDIConfiguration.swift": "#SafeDIConfiguration(generatePlainDependencyTreeInitializers: true)\n"]),
				ModuleFixture(name: "App", packageName: "Other", swiftFileContentByFilePath: ["Caller.swift": caller], dependencies: ["Feature"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
	}

	// MARK: Cycle-closing names

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesHolesBuilderFunctionApart_whenCycleClosingScopeBeneathWouldResolveToIt() async throws {
		// `Middle` holds a wrapper hole labeled as the instantiator of `Middle` above it, and the type beneath `Middle` closes
		// the cycle on that instantiator's builder function, which the hole's function would otherwise hide.
		let feature = [
			"public protocol Gadget {}",
			seamFixtureType(named: "Beneath", declarations: ["@Instantiated let again: Instantiator<Middle>"]),
			seamFixtureType(named: "Middle", declarations: ["@Instantiated let again: LazilyInstantiated<any Gadget>", "@Instantiated let beneath: Beneath"]),
			seamFixtureType(named: "Host", isSeam: true, declarations: ["@Instantiated let again: Instantiator<Middle>"]),
		]
		let fulfillers = [SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultGadget", fulfilling: "Gadget", declarations: [])]
		let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: fulfillers + [Self.root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen public enum SafeDIScope_Gadget {
		        case again(again_Values, SafeDIScope_Gadget.Middle_Scope)

		        public struct again_Values {}

		        @frozen public enum Middle_Scope {
		            case again(again_Values)

		            public struct again_Values {
		                public let beneath: Beneath
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_gadgetBuilder: @escaping (SafeDIScope_Gadget) -> any Gadget) {
		        let __safeDI_gadgetValues_again = SafeDIScope_Gadget.again_Values()
		        func __safeDI_again() -> Middle {
		            func __safeDI_beneath() -> Beneath {
		                let again = Instantiator<Middle>(__safeDI_again)
		                return Beneath(again: again)
		            }
		            let beneath: Beneath = __safeDI_beneath()
		            func __safeDI_again_Gadget() -> any Gadget {
		                __safeDI_gadgetBuilder(.again(__safeDI_gadgetValues_again, .again(SafeDIScope_Gadget.Middle_Scope.again_Values(beneath: beneath))))
		            }
		            let again = LazilyInstantiated<any Gadget>(__safeDI_again_Gadget)
		            return Middle(again: again, beneath: beneath)
		        }
		        let again = Instantiator<Middle>(__safeDI_again)
		        self.init(again: again)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_1ECC73081BC3B233 {}
		}
		"""])
	}

	// MARK: Public mocks

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_publicMockBuildsSendableWrapper_whenHoleIsHeldInSendableWrapper() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				open class Panel: Instantiable, @unchecked Sendable {
				    public typealias ForwardedProperties = String
				    public init(title: String) {
				        self.title = title
				    }

				    public let title: String
				}

				@Instantiable
				public final class Analytics: Instantiable, Sendable {
				    public init() {}
				}

				@Instantiable(generateMock: .public)
				public struct Service: Instantiable {
				    public init(analytics: Analytics, part: SendableInstantiator<Panel>) {
				        self.analytics = analytics
				        self.part = part
				    }

				    @Instantiated let analytics: Analytics
				    @Instantiated let part: SendableInstantiator<Panel>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Analytics+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    @frozen public enum SafeDISendableMockScope_Panel {
			        case part(Panel.ForwardedProperties)
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            analytics: (() -> Analytics)? = nil
			        ) {
			            self.analytics = analytics
			        }

			        public let analytics: (() -> Analytics)?
			    }

			    public static func mock(
			        panelSendableBuilder: @escaping @Sendable (Service.SafeDISendableMockScope_Panel) -> Panel,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Service {
			        let __safeDI_panelSendableBuilder = panelSendableBuilder
			        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
			        let part = SendableInstantiator<Panel> {
			            __safeDI_panelSendableBuilder(.part($0))
			        }
			        return Service(analytics: analytics, part: part)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_mock_27AF017839E8B473 {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesPublicMocksHoleFunctionApart_whenCycleClosingScopeBeneathWouldResolveToIt() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public protocol Gadget {}

				@Instantiable
				public struct Beneath: Instantiable {
				    public init(again: Instantiator<Middle>) {
				        self.again = again
				    }

				    @Instantiated let again: Instantiator<Middle>
				}

				@Instantiable
				public struct Middle: Instantiable {
				    public init(again: LazilyInstantiated<any Gadget>, beneath: Beneath) {
				        self.again = again
				        self.beneath = beneath
				    }

				    @Instantiated let again: LazilyInstantiated<any Gadget>
				    @Instantiated let beneath: Beneath
				}

				@Instantiable(generateMock: .public)
				public struct Service: Instantiable {
				    public init(again: Instantiator<Middle>) {
				        self.again = again
				    }

				    @Instantiated let again: Instantiator<Middle>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		let generated = try #require(output.generatedFiles?["Beneath+SafeDIMock.swift"])
		#expect(generated == generatedFileHeader + """
		#if DEBUG
		extension Service {
		    @frozen public enum SafeDIMockScope_Gadget {
		        case again(again_Values, SafeDIMockScope_Gadget.Middle_Scope)

		        public struct again_Values {}

		        @frozen public enum Middle_Scope {
		            case again(again_Values)

		            public struct again_Values {
		                public let beneath: Beneath
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            again: __safeDI_Middle_MockConfiguration = .init()
		        ) {
		            self.again = again
		        }

		        public let again: __safeDI_Middle_MockConfiguration
		    }

		    public static func mock(
		        gadgetBuilder: @escaping (Service.SafeDIMockScope_Gadget) -> any Gadget,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Service {
		        let __safeDI_gadgetBuilder = gadgetBuilder
		        let __safeDI_gadgetValues_again = SafeDIMockScope_Gadget.again_Values()
		        func __safeDI_again() -> Middle {
		            func __safeDI_beneath() -> Beneath {
		                let again = Instantiator<Middle>(__safeDI_again)
		                return Beneath.__safeDI_init(again: again, safeDIBuilder: nil)
		            }
		            let beneath: Beneath = __safeDI_beneath()
		            func __safeDI_again_Gadget() -> any Gadget {
		                __safeDI_gadgetBuilder(.again(__safeDI_gadgetValues_again, .again(SafeDIMockScope_Gadget.Middle_Scope.again_Values(beneath: beneath))))
		            }
		            let again = LazilyInstantiated<any Gadget>(__safeDI_again_Gadget)
		            return Middle.__safeDI_init(again: again, beneath: beneath, safeDIBuilder: safeDIOverrides.again.safeDIBuilder)
		        }
		        let again = Instantiator<Middle>(__safeDI_again)
		        return Service(again: again)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_mock_00BD27B0A51ED46F {}
		}
		#endif
		""")
	}

	// MARK: A forwarded function

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_escapesForwardedFunction_whenInstantiatorsTypeForwardsOneFunction() async throws {
		let feature = Self.featureFiles(hostDeclarations: [
			"@Instantiated let analytics: Analytics",
			"@Instantiated let part: Instantiator<ActionPanel>",
		], otherFiles: [Self.actionPanel(forwarding: "() -> Void")])
		let fulfillers = [Self.defaultActionPanel(forwarding: "() -> Void")]
		let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: fulfillers + [Self.root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen public enum SafeDIScope_ActionPanel {
		        case part(part_Values, ActionPanel.ForwardedProperties)

		        public struct part_Values {
		            public let analytics: Analytics
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_actionPanelBuilder: @escaping (SafeDIScope_ActionPanel) -> ActionPanel) {
		        let analytics = Analytics()
		        let part = Instantiator<ActionPanel> {
		            __safeDI_actionPanelBuilder(.part(SafeDIScope_ActionPanel.part_Values(analytics: analytics), $0))
		        }
		        self.init(analytics: analytics, part: part)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_6B078CAA0BFA4063 {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, SafeDIToolSeamBuilderParameterTests.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_6B078CAA0BFA4063.self\(seamCallComment(seam: "Host"))
		            func __safeDI_actionPanelBuilder_Host(_ scope: Host.SafeDIScope_ActionPanel) -> ActionPanel {
		                switch scope {
		                case let .part(scope, __safeDI_forwarded):
		                    let analytics = scope.analytics
		                    func __safeDI_part(forwardedAction: @escaping () -> Void) -> DefaultActionPanel {
		                        DefaultActionPanel(forwardedAction: forwardedAction, analytics: analytics)
		                    }
		                    return __safeDI_part(forwardedAction: __safeDI_forwarded)
		                }
		            }
		            return Host(__safeDI_actionPanelBuilder: __safeDI_actionPanelBuilder_Host)
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""]))
		try await expectValuesEqualVisibleBuild(
			output,
			modules: modules,
			visibleModules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature + fulfillers, app: [Self.root]),
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().host.part.instantiate({})")],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_escapesForwardedFunction_whenSendableInstantiatorsTypeForwardsOneFunction() async throws {
		let feature = Self.featureFiles(hostDeclarations: [
			"@Received let analytics: Analytics",
			"@Instantiated let part: SendableInstantiator<ActionPanel>",
		], otherFiles: [Self.actionPanel(forwarding: "@Sendable () -> Void")])
		let fulfillers = [Self.defaultActionPanel(forwarding: "@Sendable () -> Void")]
		let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: fulfillers + [Self.rootInstantiatingAnalytics])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen public enum SafeDISendableScope_ActionPanel {
		        case part(ActionPanel.ForwardedProperties)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_analytics analytics: Analytics, __safeDI_actionPanelSendableBuilder: @escaping @Sendable (SafeDISendableScope_ActionPanel) -> ActionPanel) {
		        let part = SendableInstantiator<ActionPanel> {
		            __safeDI_actionPanelSendableBuilder(.part($0))
		        }
		        self.init(analytics: analytics, part: part)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_05F9E56B4D95C543 {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, SafeDIToolSeamBuilderParameterTests.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        let analytics = Analytics()
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_05F9E56B4D95C543.self\(seamCallComment(seam: "Host"))
		            @Sendable func __safeDI_actionPanelSendableBuilder_Host(_ scope: Host.SafeDISendableScope_ActionPanel) -> ActionPanel {
		                switch scope {
		                case let .part(__safeDI_forwarded):
		                    @Sendable func __safeDI_part(forwardedAction: @escaping @Sendable () -> Void) -> DefaultActionPanel {
		                        DefaultActionPanel(forwardedAction: forwardedAction, analytics: analytics)
		                    }
		                    return __safeDI_part(forwardedAction: __safeDI_forwarded)
		                }
		            }
		            return Host(__safeDI_analytics: analytics, __safeDI_actionPanelSendableBuilder: __safeDI_actionPanelSendableBuilder_Host)
		        }
		        let host: Host = __safeDI_host()
		        self.init(analytics: analytics, host: host)
		    }
		}
		"""]))
		try await expectValuesEqualVisibleBuild(
			output,
			modules: modules,
			visibleModules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature + fulfillers, app: [Self.rootInstantiatingAnalytics]),
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().host.part.instantiate({})")],
		)
	}

	// MARK: A forwarded typealias of a function

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillTakesForwardedValueEscaping_whenInstantiatorsFulfillerForwardsTypealiasOfFunctionItDeclaresEscaping() async throws {
		// The case's payload escapes, and the fill hands it to a fulfiller that declares the name `@escaping`.
		let feature = Self.featureFiles(hostDeclarations: [
			"@Instantiated let analytics: Analytics",
			"@Instantiated let part: Instantiator<ActionPanel>",
		], otherFiles: [Self.onTapDeclarations, Self.actionPanel(forwarding: "OnTap")])
		let fulfillers = [Self.defaultActionPanel(forwarding: "OnTap")]
		let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: fulfillers + [Self.root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen public enum SafeDIScope_ActionPanel {
		        case part(part_Values, ActionPanel.ForwardedProperties)

		        public struct part_Values {
		            public let analytics: Analytics
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_actionPanelBuilder: @escaping (SafeDIScope_ActionPanel) -> ActionPanel) {
		        let analytics = Analytics()
		        let part = Instantiator<ActionPanel> {
		            __safeDI_actionPanelBuilder(.part(SafeDIScope_ActionPanel.part_Values(analytics: analytics), $0))
		        }
		        self.init(analytics: analytics, part: part)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_6B078CAA0BFA4063 {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, SafeDIToolSeamBuilderParameterTests.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_6B078CAA0BFA4063.self\(seamCallComment(seam: "Host"))
		            func __safeDI_actionPanelBuilder_Host(_ scope: Host.SafeDIScope_ActionPanel) -> ActionPanel {
		                switch scope {
		                case let .part(scope, __safeDI_forwarded):
		                    let analytics = scope.analytics
		                    func __safeDI_part(forwardedAction: @escaping OnTap) -> DefaultActionPanel {
		                        DefaultActionPanel(forwardedAction: forwardedAction, analytics: analytics)
		                    }
		                    return __safeDI_part(forwardedAction: __safeDI_forwarded)
		                }
		            }
		            return Host(__safeDI_actionPanelBuilder: __safeDI_actionPanelBuilder_Host)
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""]))
		try await expectValuesEqualVisibleBuild(
			output,
			modules: modules,
			visibleModules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature + fulfillers, app: [Self.root]),
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().host.part.instantiate({})")],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillTakesForwardedValueEscaping_whenSendableInstantiatorsFulfillerForwardsTypealiasOfFunctionItDeclaresEscaping() async throws {
		// The case carries the forwarded value, and the fill takes it `@escaping`.
		let feature = Self.featureFiles(hostDeclarations: [
			"@Received let analytics: Analytics",
			"@Instantiated let part: SendableInstantiator<ActionPanel>",
		], otherFiles: [Self.onTapDeclarations, Self.actionPanel(forwarding: "SendableOnTap")])
		let fulfillers = [Self.defaultActionPanel(forwarding: "SendableOnTap")]
		let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: fulfillers + [Self.rootInstantiatingAnalytics])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen public enum SafeDISendableScope_ActionPanel {
		        case part(ActionPanel.ForwardedProperties)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_analytics analytics: Analytics, __safeDI_actionPanelSendableBuilder: @escaping @Sendable (SafeDISendableScope_ActionPanel) -> ActionPanel) {
		        let part = SendableInstantiator<ActionPanel> {
		            __safeDI_actionPanelSendableBuilder(.part($0))
		        }
		        self.init(analytics: analytics, part: part)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_05F9E56B4D95C543 {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, SafeDIToolSeamBuilderParameterTests.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        let analytics = Analytics()
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_05F9E56B4D95C543.self\(seamCallComment(seam: "Host"))
		            @Sendable func __safeDI_actionPanelSendableBuilder_Host(_ scope: Host.SafeDISendableScope_ActionPanel) -> ActionPanel {
		                switch scope {
		                case let .part(__safeDI_forwarded):
		                    @Sendable func __safeDI_part(forwardedAction: @escaping SendableOnTap) -> DefaultActionPanel {
		                        DefaultActionPanel(forwardedAction: forwardedAction, analytics: analytics)
		                    }
		                    return __safeDI_part(forwardedAction: __safeDI_forwarded)
		                }
		            }
		            return Host(__safeDI_analytics: analytics, __safeDI_actionPanelSendableBuilder: __safeDI_actionPanelSendableBuilder_Host)
		        }
		        let host: Host = __safeDI_host()
		        self.init(analytics: analytics, host: host)
		    }
		}
		"""]))
		try await expectValuesEqualVisibleBuild(
			output,
			modules: modules,
			visibleModules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature + fulfillers, app: [Self.rootInstantiatingAnalytics]),
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().host.part.instantiate({})")],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillTakesForwardedValueEscaping_whenErasedInstantiatorForwardsTypealiasOfFunctionItsFulfillerDeclaresEscaping() async throws {
		// The case carries the name as the seam spells it: a payload escapes, so it needs no `@escaping`, which a case
		// cannot spell. The fill takes it `@escaping`, as the fulfiller does.
		let feature = Self.featureFiles(hostDeclarations: [
			"@Instantiated let analytics: Analytics",
			#"@Instantiated(fulfilledByType: "TapGadget", erasedToConcreteExistential: true) let part: ErasedInstantiator<OnTap, AnyGadget>"#,
		], otherFiles: [Self.onTapDeclarations])
		let fulfillers = [Self.tapGadget(forwarding: "OnTap")]
		let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: fulfillers + [Self.root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen public enum SafeDIScope_TapGadget {
		        case part(part_Values, OnTap)

		        public struct part_Values {
		            public let analytics: Analytics
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_tapGadgetBuilder: @escaping (SafeDIScope_TapGadget) -> AnyGadget) {
		        let analytics = Analytics()
		        let part = ErasedInstantiator<OnTap, AnyGadget> {
		            __safeDI_tapGadgetBuilder(.part(SafeDIScope_TapGadget.part_Values(analytics: analytics), $0))
		        }
		        self.init(analytics: analytics, part: part)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_D04A648C5A8A7CA4 {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, SafeDIToolSeamBuilderParameterTests.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_D04A648C5A8A7CA4.self\(seamCallComment(seam: "Host"))
		            func __safeDI_tapGadgetBuilder_Host(_ scope: Host.SafeDIScope_TapGadget) -> AnyGadget {
		                switch scope {
		                case let .part(scope, __safeDI_forwarded):
		                    let analytics = scope.analytics
		                    func __safeDI_part(onTap: @escaping OnTap) -> TapGadget {
		                        TapGadget(onTap: onTap, analytics: analytics)
		                    }
		                    return AnyGadget(__safeDI_part(onTap: __safeDI_forwarded))
		                }
		            }
		            return Host(__safeDI_tapGadgetBuilder: __safeDI_tapGadgetBuilder_Host)
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""]))
		try await expectValuesEqualVisibleBuild(
			output,
			modules: modules,
			visibleModules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature + fulfillers, app: [Self.root]),
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().host.part.instantiate({})")],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_carriesForwardedTypealiasInCase_whenSendableErasedInstantiatorForwardsTypealiasOfFunctionItsFulfillerDeclaresEscaping() async throws {
		// The seam cannot tell that `SendableOnTap` names a function, so the case carries it as it is spelled, and the fill
		// keeps it.
		let feature = Self.featureFiles(hostDeclarations: [
			"@Received let analytics: Analytics",
			#"@Instantiated(fulfilledByType: "TapGadget", erasedToConcreteExistential: true) let part: SendableErasedInstantiator<SendableOnTap, AnyGadget>"#,
		], otherFiles: [Self.onTapDeclarations])
		let fulfillers = [Self.tapGadget(forwarding: "SendableOnTap")]
		let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: fulfillers + [Self.rootInstantiatingAnalytics])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen public enum SafeDISendableScope_TapGadget {
		        case part(SendableOnTap)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_analytics analytics: Analytics, __safeDI_tapGadgetSendableBuilder: @escaping @Sendable (SafeDISendableScope_TapGadget) -> AnyGadget) {
		        let part = SendableErasedInstantiator<SendableOnTap, AnyGadget> {
		            __safeDI_tapGadgetSendableBuilder(.part($0))
		        }
		        self.init(analytics: analytics, part: part)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_63629B5E2C6CC1D2 {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, SafeDIToolSeamBuilderParameterTests.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        let analytics = Analytics()
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_63629B5E2C6CC1D2.self\(seamCallComment(seam: "Host"))
		            @Sendable func __safeDI_tapGadgetSendableBuilder_Host(_ scope: Host.SafeDISendableScope_TapGadget) -> AnyGadget {
		                switch scope {
		                case let .part(__safeDI_forwarded):
		                    @Sendable func __safeDI_part(onTap: @escaping SendableOnTap) -> TapGadget {
		                        TapGadget(onTap: onTap, analytics: analytics)
		                    }
		                    return AnyGadget(__safeDI_part(onTap: __safeDI_forwarded))
		                }
		            }
		            return Host(__safeDI_analytics: analytics, __safeDI_tapGadgetSendableBuilder: __safeDI_tapGadgetSendableBuilder_Host)
		        }
		        let host: Host = __safeDI_host()
		        self.init(analytics: analytics, host: host)
		    }
		}
		"""]))
		try await expectValuesEqualVisibleBuild(
			output,
			modules: modules,
			visibleModules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature + fulfillers, app: [Self.rootInstantiatingAnalytics]),
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().host.part.instantiate({})")],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_compilesHandWrittenClosuresThatKeepForwardedTypealiasOfFunction_whenCallerFillsEachInstantiatorKind() async throws {
		// A person's closures store the forwarded value, which compiles only where it escapes: in the payloads of the plain
		// enum and of the `@Sendable` one.
		let feature = Self.featureFiles(hostDeclarations: [
			"@Instantiated let held: Instantiator<ActionPanel>",
			"@Instantiated let sendableHeld: SendableInstantiator<ActionPanel>",
			#"@Instantiated(fulfilledByType: "TapGadget", erasedToConcreteExistential: true) let erased: ErasedInstantiator<OnTap, AnyGadget>"#,
			#"@Instantiated(fulfilledByType: "SendableTapGadget", erasedToConcreteExistential: true) let sendableErased: SendableErasedInstantiator<SendableOnTap, AnyGadget>"#,
		], otherFiles: [Self.onTapDeclarations, Self.actionPanel(forwarding: "SendableOnTap")])
		let caller = """
		import Feature

		final class StoringGadget: Gadget, @unchecked Sendable {
		    init(onTap: @escaping OnTap) { self.onTap = onTap }
		    let onTap: OnTap
		}

		final class SendableStoringGadget: Gadget {
		    init(onTap: @escaping SendableOnTap) { self.onTap = onTap }
		    let onTap: SendableOnTap
		}

		func makeHost() -> Host {
		    Host(
		        actionPanelBuilder: { scope in switch scope { case let .held(_, action): ActionPanel(action: action) } },
		        actionPanelSendableBuilder: { scope in switch scope { case let .sendableHeld(action): ActionPanel(action: action) } },
		        sendableTapGadgetSendableBuilder: { scope in switch scope { case let .sendableErased(onTap): AnyGadget(SendableStoringGadget(onTap: onTap)) } },
		        tapGadgetBuilder: { scope in switch scope { case let .erased(_, onTap): AnyGadget(StoringGadget(onTap: onTap)) } }
		    )
		}
		"""
		_ = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature, swiftFileContentByFilePath: ["SafeDIConfiguration.swift": "#SafeDIConfiguration(generatePlainDependencyTreeInitializers: true)\n"]),
				ModuleFixture(name: "App", packageName: "Other", swiftFileContentByFilePath: ["Caller.swift": caller], dependencies: ["Feature"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_compilesHandWrittenClosureThatKeepsForwardedFunction_whenInstantiatorsTypeForwardsOneFunction() async throws {
		let feature = Self.featureFiles(hostDeclarations: [
			"@Instantiated let held: Instantiator<ActionPanel>",
			"@Instantiated let sendableHeld: SendableInstantiator<ActionPanel>",
		], otherFiles: [Self.actionPanel(forwarding: "() -> Void")])
		let caller = """
		import Feature

		func makeHost() -> Host {
		    Host(
		        actionPanelBuilder: { scope in switch scope { case let .held(_, action): ActionPanel(action: action) } },
		        actionPanelSendableBuilder: { scope in switch scope { case let .sendableHeld(action): ActionPanel(action: action) } }
		    )
		}
		"""
		_ = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature, swiftFileContentByFilePath: ["SafeDIConfiguration.swift": "#SafeDIConfiguration(generatePlainDependencyTreeInitializers: true)\n"]),
				ModuleFixture(name: "App", packageName: "Other", swiftFileContentByFilePath: ["Caller.swift": caller], dependencies: ["Feature"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesEscapingForwardedFunctionToFill_whenPlainInstantiatorHoleIsInsideSendableFunction() async throws {
		let feature = Self.featureFiles(hostDeclarations: [
			"@Received let analytics: Analytics",
			"@Instantiated let ownerBuilder: SendableInstantiator<Owner>",
		], otherFiles: [
			Self.actionPanel(forwarding: "() -> Void"),
			seamFixtureType(named: "Owner", declarations: ["@Instantiated let held: Instantiator<ActionPanel>"], conformances: ", @unchecked Sendable"),
		])
		let fulfillers = [Self.defaultActionPanel(forwarding: "() -> Void")]
		let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: fulfillers + [Self.rootInstantiatingAnalytics])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		try await expectValuesEqualVisibleBuild(
			output,
			modules: modules,
			visibleModules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature + fulfillers, app: [Self.rootInstantiatingAnalytics]),
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().host.ownerBuilder.instantiate().held.instantiate({})")],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_compilesPassedUpBuilder_whenInnerSeamsInstantiatorForwardsOneFunction() async throws {
		let feature = Self.featureFiles(hostDeclarations: [
			"@Instantiated let inner: Inner",
		], otherFiles: [
			Self.actionPanel(forwarding: "() -> Void"),
			seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated let part: Instantiator<ActionPanel>"]),
		])
		let fulfillers = [Self.defaultActionPanel(forwarding: "() -> Void", receivesAnalytics: false)]
		let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: fulfillers + [Self.root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		try await expectValuesEqualVisibleBuild(
			output,
			modules: modules,
			visibleModules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature + fulfillers, app: [Self.root]),
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().host.inner.part.instantiate({})")],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_publicMockTakesBuilderOfForwardedFunction_whenItsInstantiatorForwardsOneFunction() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				Self.actionPanel(forwarding: "() -> Void"),
				"""
				@Instantiable(generateMock: .public)
				public struct Service: Instantiable {
				    public init(part: Instantiator<ActionPanel>) {
				        self.part = part
				    }

				    @Instantiated let part: Instantiator<ActionPanel>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Service+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    @frozen public enum SafeDIMockScope_ActionPanel {
			        case part(part_Values, ActionPanel.ForwardedProperties)

			        public struct part_Values {}
			    }

			    public static func mock(
			        actionPanelBuilder: @escaping (Service.SafeDIMockScope_ActionPanel) -> ActionPanel
			    ) -> Service {
			        let __safeDI_actionPanelBuilder = actionPanelBuilder
			        let part = Instantiator<ActionPanel> {
			            __safeDI_actionPanelBuilder(.part(SafeDIMockScope_ActionPanel.part_Values(), $0))
			        }
			        return Service(part: part)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_mock_32BFD4F1F0E93C07 {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_compilesCallOfPublicMock_whenItsInstantiatorForwardsOneFunction(isCalledInSendableFunction: Bool) async throws {
		let feature = [
			Self.actionPanel(forwarding: "() -> Void"),
			seamFixtureType(named: "Screen", declarations: ["@Instantiated let part: Instantiator<ActionPanel>"], conformances: ", @unchecked Sendable")
				.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(generateMock: .public)\n"),
		]
		let screenType = isCalledInSendableFunction ? "SendableInstantiator<Screen>" : "Screen"
		let consumer = seamFixtureType(named: "AppScreen", declarations: ["@Instantiated let screen: \(screenType)"], conformances: ", @unchecked Sendable")
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(generateMock: true)\n")
		// A consumer that sees the fulfiller fills the builder.
		_ = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature),
				ModuleFixture(name: "App", packageName: "Other", swiftFileContent: ["import Feature\n\n" + Self.defaultActionPanel(forwarding: "() -> Void", receivesAnalytics: false), "import Feature\n\n" + consumer], dependencies: ["Feature"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		// One that does not passes the builder up, `@Sendable` when a `@Sendable` builder function makes the call.
		_ = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature),
				ModuleFixture(name: "App", packageName: "Other", swiftFileContent: ["import Feature\n\n" + consumer], dependencies: ["Feature"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
	}

	// MARK: A receive of the hole's own property

	@Test(arguments: [
		"part: LazilyInstantiated<any Gadget>?",
		"part: (any Gadget)?",
	])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNil_whenFillsTreeReceivesHolesOwnPropertyOnlyIfAvailable(receive: String) async throws {
		let feature = Self.featureFiles(hostDeclarations: ["@Instantiated let part: LazilyInstantiated<any Gadget>"])
		let fulfillers = [
			seamFixtureType(named: "Kid", declarations: ["@Received(onlyIfAvailable: true) let \(receive)"], conformances: ", @unchecked Sendable"),
			SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultGadget", fulfilling: "Gadget", declarations: ["@Instantiated let kid: Kid"]),
		]
		let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: fulfillers + [Self.root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, SafeDIToolSeamBuilderParameterTests.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_608C4A7ED2050B31.self\(seamCallComment(seam: "Host"))
		            func __safeDI_gadgetBuilder_Host(_ scope: Host.SafeDIScope_Gadget) -> any Gadget {
		                switch scope {
		                case .part:
		                    func __safeDI_part() -> DefaultGadget {
		                        let kid = Kid(part: nil)
		                        return DefaultGadget(kid: kid)
		                    }
		                    return __safeDI_part()
		                }
		            }
		            return Host(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Host)
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""]))
		try await expectValuesEqualVisibleBuild(
			output,
			modules: modules,
			visibleModules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature + fulfillers, app: [Self.root]),
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().host.part.instance")],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNil_whenFillsTreeAliasesHolesOwnPropertyOnlyIfAvailable() async throws {
		let feature = Self.featureFiles(hostDeclarations: ["@Instantiated let part: any Gadget"])
		let fulfillers = [
			seamFixtureType(named: "Kid", declarations: [#"@Received(fulfilledByDependencyNamed: "part", ofType: (any Gadget).self, onlyIfAvailable: true) let renamed: (any Gadget)?"#], conformances: ", @unchecked Sendable"),
			SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultGadget", fulfilling: "Gadget", declarations: ["@Instantiated let kid: Kid"]),
		]
		let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: fulfillers + [Self.root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		try await expectValuesEqualVisibleBuild(
			output,
			modules: modules,
			visibleModules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature + fulfillers, app: [Self.root]),
			probes: [DifferentialValueProbe("Root()")],
		)
	}

	// MARK: An erased instantiator's forwarded properties

	@Test(arguments: [
		"ErasedInstantiator<(), any Gadget>",
		"ErasedInstantiator<Void, any Gadget>",
		"ErasedInstantiator<Int, any Gadget>",
		"SendableErasedInstantiator<(), any Gadget>",
	])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsMismatchAtHole_whenErasedInstantiatorsFirstGenericIsNotFulfillersForwardedProperties(type: String) async {
		let wrapper = type.prefix { $0 != "<" }
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Host.swift"]):8:5: error: The first generic argument of `part: \(type)` on `Host` must be the @Forwarded properties of `NamedGadget`, which it builds. Declare it as `\(wrapper)<String, any Gadget>`.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: SafeDIToolSeamBuilderParameterTests.modules(
					feature: Self.featureFiles(hostDeclarations: [#"@Instantiated(fulfilledByType: "NamedGadget") let part: \#(type)"#, "@Instantiated let analytics: Analytics"]),
					app: [Self.fulfillers[1], Self.root],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: [
		(firstGeneric: "Label", forwardedType: "Feature.Label", guardName: "__safeDI_Host_A2857B3BDA29DBEE"),
		(firstGeneric: "Feature.Label", forwardedType: "Label", guardName: "__safeDI_Host_9AE4951B5692CD76"),
	])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsHole_whenSeamsModuleQualifiesOneSpellingOfForwardedProperty(firstGeneric: String, forwardedType: String, guardName _: String) async throws {
		let feature = Self.featureFiles(
			hostDeclarations: [#"@Instantiated(fulfilledByType: "NamedGadget", erasedToConcreteExistential: true) let part: ErasedInstantiator<\#(firstGeneric), AnyGadget>"#],
			otherFiles: [Self.labelDeclaration],
		)
		let fulfillers = [seamFixtureType(named: "NamedGadget", declarations: ["@Forwarded let label: \(forwardedType)"], conformances: ", Gadget")]
		let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: fulfillers + [Self.root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, SafeDIToolSeamBuilderParameterTests.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": firstGeneric == "Label" ? """
		extension Root {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_3F2E0E518C8D66DF.self\(seamCallComment(seam: "Host"))
		            func __safeDI_namedGadgetBuilder_Host(_ scope: Host.SafeDIScope_NamedGadget) -> AnyGadget {
		                switch scope {
		                case let .part(_, __safeDI_forwarded):
		                    func __safeDI_part(label: Feature.Label) -> NamedGadget {
		                        NamedGadget(label: label)
		                    }
		                    return AnyGadget(__safeDI_part(label: __safeDI_forwarded))
		                }
		            }
		            return Host(__safeDI_namedGadgetBuilder: __safeDI_namedGadgetBuilder_Host)
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		""" : """
		extension Root {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_86F2530A8C50B66F.self\(seamCallComment(seam: "Host"))
		            func __safeDI_namedGadgetBuilder_Host(_ scope: Host.SafeDIScope_NamedGadget) -> AnyGadget {
		                switch scope {
		                case let .part(_, __safeDI_forwarded):
		                    func __safeDI_part(label: Label) -> NamedGadget {
		                        NamedGadget(label: label)
		                    }
		                    return AnyGadget(__safeDI_part(label: __safeDI_forwarded))
		                }
		            }
		            return Host(__safeDI_namedGadgetBuilder: __safeDI_namedGadgetBuilder_Host)
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""]))
		try await expectValuesEqualVisibleBuild(
			output,
			modules: modules,
			visibleModules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature + fulfillers, app: [Self.root]),
			probes: [DifferentialValueProbe("Root()")],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsHole_whenSeamsModuleQualifiesForwardedPropertyUnderTheTargetGraph() async throws {
		let feature = Self.featureFiles(
			hostDeclarations: [#"@Instantiated(fulfilledByType: "NamedGadget", erasedToConcreteExistential: true) let part: ErasedInstantiator<Label, AnyGadget>"#],
			otherFiles: [Self.labelDeclaration],
		)
		let fulfillers = [seamFixtureType(named: "NamedGadget", declarations: ["@Forwarded let label: Feature.Label"], conformances: ", Gadget")]
		_ = try await executeSafeDIToolMultiModuleTest(
			modules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: fulfillers + [Self.root]),
			integration: .swiftPackagePlugin,
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsMismatchAtHole_whenHoleOwnersModuleIsNotSeamsModule() async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Owner.swift"]):7:5: error: The first generic argument of `part: ErasedInstantiator<Label, AnyGadget>` on `Owner` must be the @Forwarded properties of `NamedGadget`, which it builds. Declare it as `ErasedInstantiator<Feature.Label, AnyGadget>`.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.threeModules(
					feature: [
						seamFixtureType(named: "Owner", declarations: [#"@Instantiated(fulfilledByType: "NamedGadget", erasedToConcreteExistential: true) let part: ErasedInstantiator<Label, AnyGadget>"#]),
					],
					middle: [seamFixtureType(named: "Host", isSeam: true, declarations: ["@Instantiated let owner: Owner"])],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsMismatchAtHole_whenSeamsModuleQualifiesAnotherTypeThanForwardedProperty() async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Host.swift"]):8:5: error: The first generic argument of `part: ErasedInstantiator<Feature.OtherLabel, AnyGadget>` on `Host` must be the @Forwarded properties of `NamedGadget`, which it builds. Declare it as `ErasedInstantiator<Feature.Label, AnyGadget>`.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: SafeDIToolSeamBuilderParameterTests.modules(
					feature: Self.featureFiles(
						hostDeclarations: [#"@Instantiated(fulfilledByType: "NamedGadget", erasedToConcreteExistential: true) let part: ErasedInstantiator<Feature.OtherLabel, AnyGadget>"#, "@Instantiated let analytics: Analytics"],
						otherFiles: [Self.labelDeclaration, "public struct OtherLabel: Sendable {}"],
					),
					app: [seamFixtureType(named: "NamedGadget", declarations: ["@Forwarded let label: Feature.Label"], conformances: ", Gadget"), Self.root],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsMismatchAtHole_whenAModuleDeclaresTypeNamedAsSeamsModule() async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Host.swift"]):8:5: error: The first generic argument of `part: ErasedInstantiator<Label, AnyGadget>` on `Host` must be the @Forwarded properties of `NamedGadget`, which it builds. Declare it as `ErasedInstantiator<Feature.Label, AnyGadget>`.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: SafeDIToolSeamBuilderParameterTests.modules(
					feature: Self.featureFiles(
						hostDeclarations: [#"@Instantiated(fulfilledByType: "NamedGadget", erasedToConcreteExistential: true) let part: ErasedInstantiator<Label, AnyGadget>"#, "@Instantiated let analytics: Analytics"],
						otherFiles: [Self.labelDeclaration],
					),
					app: ["public enum Feature { public struct Label: Sendable {} }", seamFixtureType(named: "NamedGadget", declarations: ["@Forwarded let label: Feature.Label"], conformances: ", Gadget"), Self.root],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: [
		(firstGeneric: "Label", forwardedType: "Feature.Label", spellingToDeclare: "Feature.Label"),
		(firstGeneric: "Feature.Label", forwardedType: "Label", spellingToDeclare: "Label"),
	])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsMismatchAtHole_whenFillersModuleDeclaresItsOwnTypeOfQualifiedName(firstGeneric: String, forwardedType: String, spellingToDeclare: String) async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Host.swift"]):8:5: error: The first generic argument of `part: ErasedInstantiator<\(firstGeneric), AnyGadget>` on `Host` must be the @Forwarded properties of `NamedGadget`, which it builds. Declare it as `ErasedInstantiator<\(spellingToDeclare), AnyGadget>`.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: SafeDIToolSeamBuilderParameterTests.modules(
					feature: Self.featureFiles(
						hostDeclarations: [#"@Instantiated(fulfilledByType: "NamedGadget", erasedToConcreteExistential: true) let part: ErasedInstantiator<\#(firstGeneric), AnyGadget>"#, "@Instantiated let analytics: Analytics"],
						otherFiles: [Self.labelDeclaration],
					),
					app: [Self.labelDeclaration, seamFixtureType(named: "NamedGadget", declarations: ["@Forwarded let label: \(forwardedType)"], conformances: ", Gadget"), Self.root],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsMismatchAtHole_whenAnotherSeamPassesHoleUp(moduleDeclaresItsOwnType: Bool) async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["InnerSeam.swift"]):7:5: error: The first generic argument of `part: ErasedInstantiator<Label, AnyGadget>` on `InnerSeam` must be the @Forwarded properties of `NamedGadget`, which it builds. Declare it as `ErasedInstantiator<Feature.Label, AnyGadget>`.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.threeModules(
					feature: [
						seamFixtureType(named: "InnerSeam", isSeam: true, declarations: [#"@Instantiated(fulfilledByType: "NamedGadget", erasedToConcreteExistential: true) let part: ErasedInstantiator<Label, AnyGadget>"#]),
					],
					middle: (moduleDeclaresItsOwnType ? [Self.labelDeclaration] : []) + [seamFixtureType(named: "Host", isSeam: true, declarations: ["@Instantiated let inner: InnerSeam"])],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The fixtures of `Feature`: what `Host` holds, a `Gadget` no declaration fulfills, an eraser of it, and classes that
	/// conform to `Instantiable` by hand, as a type held in an `Instantiator` must.
	private static func featureFiles(hostDeclarations: [String], otherFiles: [String] = []) -> [String] {
		[
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
			seamFixtureType(named: "Host", isSeam: true, declarations: hostDeclarations),
		] + otherFiles
	}

	private static let fulfillers = [
		SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultGadget", fulfilling: "Gadget", declarations: ["@Received let analytics: Analytics"]),
		seamFixtureType(named: "NamedGadget", declarations: ["@Forwarded let name: String", "@Received let analytics: Analytics"], conformances: ", Gadget"),
		"""
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
		""",
	]

	/// A class that conforms to `Instantiable` by hand, as a type held in an `Instantiator` must, and forwards one
	/// function, of type `functionType`.
	private static func actionPanel(forwarding functionType: String) -> String {
		"""
		open class ActionPanel: Instantiable, @unchecked Sendable {
		    public typealias ForwardedProperties = \(functionType)

		    public init(action: @escaping \(functionType)) {
		        self.action = action
		    }

		    public let action: \(functionType)
		}
		"""
	}

	/// `OnTap` and `SendableOnTap`, typealiases of function types, which SafeDI cannot tell from any other name.
	private static let onTapDeclarations = """
	public typealias OnTap = () -> Void
	public typealias SendableOnTap = @Sendable () -> Void
	"""

	/// The `@Instantiable` `Gadget` that `App` declares, forwarding `onTap` of type `functionType`, a typealias of a
	/// function type its initializer declares `@escaping`.
	private static func tapGadget(forwarding functionType: String) -> String {
		"""
		@Instantiable
		public struct TapGadget: Instantiable, Gadget, @unchecked Sendable {
		    public init(onTap: @escaping \(functionType), analytics: Analytics) {
		        self.onTap = onTap
		        self.analytics = analytics
		    }

		    @Forwarded let onTap: \(functionType)
		    @Received let analytics: Analytics
		}
		"""
	}

	/// The `@Instantiable` subclass of `actionPanel(forwarding:)` that `App` declares.
	private static func defaultActionPanel(forwarding functionType: String, receivesAnalytics: Bool = true) -> String {
		"""
		@Instantiable(fulfillingAdditionalTypes: [ActionPanel.self], conformsElsewhere: true)
		public final class DefaultActionPanel: ActionPanel, @unchecked Sendable {
		    public init(forwardedAction: @escaping \(functionType)\(receivesAnalytics ? ", analytics: Analytics" : "")) {
		        self.forwardedAction = forwardedAction\(receivesAnalytics ? "\n        self.analytics = analytics" : "")
		        super.init(action: forwardedAction)
		    }

		    @Forwarded let forwardedAction: \(functionType)\(receivesAnalytics ? "\n    @Received let analytics: Analytics" : "")
		}
		"""
	}

	private static let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let host: Host"])

	/// A root that instantiates the `analytics` its `Host` receives, which a fill inside a `@Sendable` function reads from the
	/// root's own scope.
	private static let rootInstantiatingAnalytics = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let analytics: Analytics", "@Instantiated let host: Host"])

	/// An `@Instantiable` type that fulfills `fulfilledType` and is `@unchecked Sendable`, so that a `@Sendable` function can
	/// hold what it instantiates.
	private static func sendableFulfillingType(named name: String, fulfilling fulfilledType: String, declarations: [String]) -> String {
		SafeDIToolSeamBuilderParameterTests.fulfillingType(named: name, fulfilling: fulfilledType, declarations: declarations)
			.replacingOccurrences(of: ", \(fulfilledType) {", with: ", \(fulfilledType), @unchecked Sendable {")
	}

	private static let labelDeclaration = "public struct Label: Sendable {}"

	/// `feature`, which holds a hole for `NamedGadget` and declares `Label`, beneath `middle`, whose seam `Host` builds it,
	/// beneath `App`, which declares `NamedGadget`, forwarding `Feature.Label`.
	private static func threeModules(feature: [String], middle: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: featureFiles(hostDeclarations: [], otherFiles: [labelDeclaration]).filter { !$0.contains("struct Host") } + feature),
			ModuleFixture(name: "Middle", packageName: "Other", swiftFileContent: middle.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
			ModuleFixture(
				name: "App",
				packageName: "Other",
				swiftFileContent: [seamFixtureType(named: "NamedGadget", declarations: ["@Forwarded let label: Feature.Label"], conformances: ", Gadget"), root].map { "import Feature\nimport Middle\n\n" + $0 },
				dependencies: ["Feature", "Middle"],
			),
		]
	}

	/// Expects the values `output`, the run of `modules`, builds for `Root` and each of `probes` to equal those the run of
	/// `visibleModules` builds, the same graph with every fulfilling declaration in the seam's module.
	private mutating func expectValuesEqualVisibleBuild(
		_ output: MultiModuleTestOutput,
		modules: [ModuleFixture],
		visibleModules: [ModuleFixture],
		probes: [DifferentialValueProbe],
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		guard compileVerificationIsEnabled else { return }
		let visibleOutput = try await executeSafeDIToolMultiModuleTest(modules: visibleModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		try await expectDifferentialValuesAgree(
			feature: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: output, modules: modules),
			knownRight: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: visibleOutput, modules: visibleModules),
			probes: probes,
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}

	/// Expects `generatedFiles` to equal `expected`, recording the files generated when they do not, so a failure shows
	/// the output in full.
	private func expectGeneratedFiles(_ generatedFiles: [String: String]?, _ expected: [String: String], sourceLocation: SourceLocation = #_sourceLocation) {
		#expect(generatedFiles == expected, sourceLocation: sourceLocation)
		if let generatedFiles, generatedFiles != expected {
			Issue.record(Comment(rawValue: generatedFiles.sorted { $0.key < $1.key }.map { "=== \($0.key)\n\($0.value)" }.joined(separator: "\n")), sourceLocation: sourceLocation)
		}
	}
}
