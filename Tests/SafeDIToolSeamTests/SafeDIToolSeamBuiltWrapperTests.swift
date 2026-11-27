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
	}

	@Test(arguments: WrapperKind.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsWrapperAroundBuilderThatReturnsPlainValue_whenHoleIsHeldInWrapper(wrapper: WrapperKind) async throws {
		let feature = Self.featureFiles(hostDeclarations: ["@Received let analytics: Analytics", wrapper.declaration])
		let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: Self.fulfillers + [Self.rootInstantiatingAnalytics])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		switch wrapper {
		case .lazilyInstantiated:
			expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, [
				"Feature.swift": generatedFileHeader + """
				extension Host {
				    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				    nonisolated public final class __safeDI_GadgetCarrier<__safeDI_Built> {
				        public let part: (Analytics) -> __safeDI_Built

				        public init(part: @escaping (Analytics) -> __safeDI_Built) {
				            self.part = part
				        }

				        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				            self.init(part: { _ in __safeDI_builder() })
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public init(__safeDI_analytics analytics: Analytics, __safeDI_gadgetBuilder: __safeDI_GadgetCarrier<any Gadget>) {
				        @inline(never) func __safeDI_part() -> any Gadget {
				            __safeDI_gadgetBuilder.part(analytics)
				        }
				        let part = LazilyInstantiated<any Gadget>(__safeDI_part)
				        self.init(analytics: analytics, part: part)
				    }
				}

				extension Host {
				    public enum __safeDI_Host_D5095FC0D69E72CF {}
				}
				""",
			])
		case .sendableLazilyInstantiated:
			expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, [
				"Feature.swift": generatedFileHeader + """
				extension Host {
				    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				    nonisolated public final class __safeDI_GadgetSendableCarrier<__safeDI_Built>: Sendable {
				        public let part: @Sendable () -> __safeDI_Built

				        public init(part: @escaping @Sendable () -> __safeDI_Built) {
				            self.part = part
				        }

				        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
				            self.init(part: { __safeDI_builder() })
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public init(__safeDI_analytics analytics: Analytics, __safeDI_gadgetSendableBuilder: __safeDI_GadgetSendableCarrier<any Gadget>) {
				        @inline(never) @Sendable nonisolated func __safeDI_part() -> any Gadget {
				            __safeDI_gadgetSendableBuilder.part()
				        }
				        let part = SendableLazilyInstantiated<any Gadget>(__safeDI_part)
				        self.init(analytics: analytics, part: part)
				    }
				}

				extension Host {
				    public enum __safeDI_Host_B4E6E98A41203F72 {}
				}
				""",
			])
		case .instantiator:
			expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, [
				"Feature.swift": generatedFileHeader + """
				extension Host {
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

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public init(__safeDI_analytics analytics: Analytics, __safeDI_panelBuilder: __safeDI_PanelCarrier<Panel>) {
				        let part = Instantiator<Panel>(__safeDI_panelBuilder.part(analytics))
				        self.init(analytics: analytics, part: part)
				    }
				}

				extension Host {
				    public enum __safeDI_Host_2262779BCDF32D4C {}
				}
				""",
			])
		case .sendableInstantiator:
			expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, [
				"Feature.swift": generatedFileHeader + """
				extension Host {
				    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				    nonisolated public final class __safeDI_PanelSendableCarrier<__safeDI_Built>: Sendable {
				        public let part: @Sendable () -> SendableErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder

				        public init(part: @escaping @Sendable () -> SendableErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
				            self.part = part
				        }

				        public convenience init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
				            self.init(part: { __safeDI_builder })
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public init(__safeDI_analytics analytics: Analytics, __safeDI_panelSendableBuilder: __safeDI_PanelSendableCarrier<Panel>) {
				        let part = SendableInstantiator<Panel>(__safeDI_panelSendableBuilder.part())
				        self.init(analytics: analytics, part: part)
				    }
				}

				extension Host {
				    public enum __safeDI_Host_6FE96D89DCEFAEDB {}
				}
				""",
			])
		case .erasedInstantiator:
			expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, [
				"Feature.swift": generatedFileHeader + """
				extension Host {
				    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				    nonisolated public final class __safeDI_NamedGadget_AnyGadgetCarrier<__safeDI_Built> {
				        public let part: (Analytics) -> ErasedInstantiator<String, __safeDI_Built>.Builder

				        public init(part: @escaping (Analytics) -> ErasedInstantiator<String, __safeDI_Built>.Builder) {
				            self.part = part
				        }

				        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<String, __safeDI_Built>.Builder) {
				            self.init(part: { _ in __safeDI_builder })
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public init(__safeDI_analytics analytics: Analytics, __safeDI_namedGadget_AnyGadgetBuilder: __safeDI_NamedGadget_AnyGadgetCarrier<AnyGadget>) {
				        let part = ErasedInstantiator<String, AnyGadget>(__safeDI_namedGadget_AnyGadgetBuilder.part(analytics))
				        self.init(analytics: analytics, part: part)
				    }
				}

				extension Host {
				    public enum __safeDI_Host_AAFD5C8A3036F849 {}
				}
				""",
			])
		case .sendableErasedInstantiator:
			expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, [
				"Feature.swift": generatedFileHeader + """
				extension Host {
				    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				    nonisolated public final class __safeDI_NamedGadget_AnyGadgetSendableCarrier<__safeDI_Built>: Sendable {
				        public let part: @Sendable () -> SendableErasedInstantiator<String, __safeDI_Built>.Builder

				        public init(part: @escaping @Sendable () -> SendableErasedInstantiator<String, __safeDI_Built>.Builder) {
				            self.part = part
				        }

				        public convenience init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<String, __safeDI_Built>.Builder) {
				            self.init(part: { __safeDI_builder })
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public init(__safeDI_analytics analytics: Analytics, __safeDI_namedGadget_AnyGadgetSendableBuilder: __safeDI_NamedGadget_AnyGadgetSendableCarrier<AnyGadget>) {
				        let part = SendableErasedInstantiator<String, AnyGadget>(__safeDI_namedGadget_AnyGadgetSendableBuilder.part())
				        self.init(analytics: analytics, part: part)
				    }
				}

				extension Host {
				    public enum __safeDI_Host_3C8B12418D47A800 {}
				}
				""",
			])
		}
		switch wrapper {
		case .lazilyInstantiated:
			expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
				"App.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension Root {
				    public init() {
				        func __safeDI_gadgetBuilder_Host_part(_ scope_analytics: Analytics) -> any Gadget {
				            return __safeDI_fillBody_8B0E70A01AC9327E(analytics: scope_analytics)
				        }
				        func __safeDI_fillBody_8B0E70A01AC9327E(analytics: Analytics) -> any Gadget {
				            func __safeDI_part() -> DefaultGadget {
				                DefaultGadget(analytics: analytics)
				            }
				            return __safeDI_part()
				        }
				        func __safeDI_gadgetBuilder_Host() -> Host.__safeDI_GadgetCarrier<any Gadget> {
				            .init(part: { scope_analytics in __safeDI_gadgetBuilder_Host_part(scope_analytics) })
				        }
				        let analytics = Analytics()
				        func __safeDI_host() -> Host {
				            _ = Host.__safeDI_Host_D5095FC0D69E72CF.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return Host(__safeDI_analytics: analytics, __safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Host())
				        }
				        let host: Host = __safeDI_host()
				        self.init(analytics: analytics, host: host)
				    }
				}
				""",
			])
		case .sendableLazilyInstantiated:
			expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
				"App.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension Root {
				    public init() {
				        let analytics = Analytics()
				        func __safeDI_host() -> Host {
				            _ = Host.__safeDI_Host_B4E6E98A41203F72.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            @Sendable nonisolated func __safeDI_gadgetSendableBuilder_Host_part() -> any Gadget {
				                @Sendable nonisolated func __safeDI_part() -> DefaultGadget {
				                    DefaultGadget(analytics: analytics)
				                }
				                return __safeDI_part()
				            }
				            @Sendable nonisolated func __safeDI_gadgetSendableBuilder_Host() -> Host.__safeDI_GadgetSendableCarrier<any Gadget> {
				                .init(part: { __safeDI_gadgetSendableBuilder_Host_part() })
				            }
				            return Host(__safeDI_analytics: analytics, __safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_Host())
				        }
				        let host: Host = __safeDI_host()
				        self.init(analytics: analytics, host: host)
				    }
				}
				""",
			])
		case .instantiator:
			expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
				"App.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension Root {
				    public init() {
				        func __safeDI_panelBuilder_Host_part(analytics: Analytics) -> Instantiator<Panel>.Builder {
				            return __safeDI_fillBody_BEA678126FB96713(analytics: analytics)
				        }
				        func __safeDI_fillBody_BEA678126FB96713(analytics: Analytics) -> Instantiator<Panel>.Builder {
				            func __safeDI_part(name: String) -> DefaultPanel {
				                DefaultPanel(name: name, analytics: analytics)
				            }
				            return { forwarded in __safeDI_part(name: forwarded) }
				        }
				        func __safeDI_panelBuilder_Host() -> Host.__safeDI_PanelCarrier<Panel> {
				            .init(part: { values_analytics in __safeDI_panelBuilder_Host_part(analytics: values_analytics) })
				        }
				        let analytics = Analytics()
				        func __safeDI_host() -> Host {
				            _ = Host.__safeDI_Host_2262779BCDF32D4C.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return Host(__safeDI_analytics: analytics, __safeDI_panelBuilder: __safeDI_panelBuilder_Host())
				        }
				        let host: Host = __safeDI_host()
				        self.init(analytics: analytics, host: host)
				    }
				}
				""",
			])
		case .sendableInstantiator:
			expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
				"App.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension Root {
				    public init() {
				        let analytics = Analytics()
				        func __safeDI_host() -> Host {
				            _ = Host.__safeDI_Host_6FE96D89DCEFAEDB.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            @Sendable nonisolated func __safeDI_panelSendableBuilder_Host_part() -> SendableInstantiator<Panel>.Builder {
				                @Sendable nonisolated func __safeDI_part(name: String) -> DefaultPanel {
				                    DefaultPanel(name: name, analytics: analytics)
				                }
				                return { forwarded in __safeDI_part(name: forwarded) }
				            }
				            @Sendable nonisolated func __safeDI_panelSendableBuilder_Host() -> Host.__safeDI_PanelSendableCarrier<Panel> {
				                .init(part: { __safeDI_panelSendableBuilder_Host_part() })
				            }
				            return Host(__safeDI_analytics: analytics, __safeDI_panelSendableBuilder: __safeDI_panelSendableBuilder_Host())
				        }
				        let host: Host = __safeDI_host()
				        self.init(analytics: analytics, host: host)
				    }
				}
				""",
			])
		case .erasedInstantiator:
			expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
				"App.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension Root {
				    public init() {
				        func __safeDI_namedGadget_AnyGadgetBuilder_Host_part(analytics: Analytics) -> ErasedInstantiator<String, AnyGadget>.Builder {
				            return __safeDI_fillBody_28C282CAA634FDCF(analytics: analytics)
				        }
				        func __safeDI_fillBody_28C282CAA634FDCF(analytics: Analytics) -> ErasedInstantiator<String, AnyGadget>.Builder {
				            func __safeDI_part(name: String) -> NamedGadget {
				                NamedGadget(name: name, analytics: analytics)
				            }
				            return { forwarded in AnyGadget(__safeDI_part(name: forwarded)) }
				        }
				        func __safeDI_namedGadget_AnyGadgetBuilder_Host() -> Host.__safeDI_NamedGadget_AnyGadgetCarrier<AnyGadget> {
				            .init(part: { values_analytics in __safeDI_namedGadget_AnyGadgetBuilder_Host_part(analytics: values_analytics) })
				        }
				        let analytics = Analytics()
				        func __safeDI_host() -> Host {
				            _ = Host.__safeDI_Host_AAFD5C8A3036F849.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return Host(__safeDI_analytics: analytics, __safeDI_namedGadget_AnyGadgetBuilder: __safeDI_namedGadget_AnyGadgetBuilder_Host())
				        }
				        let host: Host = __safeDI_host()
				        self.init(analytics: analytics, host: host)
				    }
				}
				""",
			])
		case .sendableErasedInstantiator:
			expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
				"App.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension Root {
				    public init() {
				        let analytics = Analytics()
				        func __safeDI_host() -> Host {
				            _ = Host.__safeDI_Host_3C8B12418D47A800.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            @Sendable nonisolated func __safeDI_namedGadget_AnyGadgetSendableBuilder_Host_part() -> SendableErasedInstantiator<String, AnyGadget>.Builder {
				                @Sendable nonisolated func __safeDI_part(name: String) -> NamedGadget {
				                    NamedGadget(name: name, analytics: analytics)
				                }
				                return { forwarded in AnyGadget(__safeDI_part(name: forwarded)) }
				            }
				            @Sendable nonisolated func __safeDI_namedGadget_AnyGadgetSendableBuilder_Host() -> Host.__safeDI_NamedGadget_AnyGadgetSendableCarrier<AnyGadget> {
				                .init(part: { __safeDI_namedGadget_AnyGadgetSendableBuilder_Host_part() })
				            }
				            return Host(__safeDI_analytics: analytics, __safeDI_namedGadget_AnyGadgetSendableBuilder: __safeDI_namedGadget_AnyGadgetSendableBuilder_Host())
				        }
				        let host: Host = __safeDI_host()
				        self.init(analytics: analytics, host: host)
				    }
				}
				""",
			])
		}
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ActionGadget_GadgetCarrier<__safeDI_Built> {
		        public let part: (Analytics) -> ErasedInstantiator<nonisolated(nonsending) () async -> Void, __safeDI_Built>.Builder

		        public init(part: @escaping (Analytics) -> ErasedInstantiator<nonisolated(nonsending) () async -> Void, __safeDI_Built>.Builder) {
		            self.part = part
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<nonisolated(nonsending) () async -> Void, __safeDI_Built>.Builder) {
		            self.init(part: { _ in __safeDI_builder })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_actionGadget_GadgetBuilder: __safeDI_ActionGadget_GadgetCarrier<any Gadget>) {
		        let analytics = Analytics()
		        let part: ErasedInstantiator<nonisolated(nonsending) () async -> Void, any Gadget> = ErasedInstantiator(__safeDI_actionGadget_GadgetBuilder.part(analytics))
		        self.init(analytics: analytics, part: part)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_B4F72827A3ECE5F3 {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_actionGadget_GadgetBuilder_Host_part(analytics: Analytics) -> ErasedInstantiator<nonisolated(nonsending) () async -> Void, any Gadget>.Builder {
			            return __safeDI_fillBody_2B4719521591DD1A(analytics: analytics)
			        }
			        func __safeDI_fillBody_2B4719521591DD1A(analytics: Analytics) -> ErasedInstantiator<nonisolated(nonsending) () async -> Void, any Gadget>.Builder {
			            func __safeDI_part(run: nonisolated(nonsending) @escaping () async -> Void) -> ActionGadget {
			                ActionGadget(run: run, analytics: analytics)
			            }
			            return { forwarded in __safeDI_part(run: forwarded) }
			        }
			        func __safeDI_actionGadget_GadgetBuilder_Host() -> Host.__safeDI_ActionGadget_GadgetCarrier<any Gadget> {
			            .init(part: { values_analytics in __safeDI_actionGadget_GadgetBuilder_Host_part(analytics: values_analytics) })
			        }
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_B4F72827A3ECE5F3.self\(seamCallComment(seam: "Host"))
			            return Host(__safeDI_actionGadget_GadgetBuilder: __safeDI_actionGadget_GadgetBuilder_Host())
			        }
			        let host: Host = __safeDI_host()
			        self.init(host: host)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresNestedCallsFillSendableAtTheRoot_whenSendableWrapperBuilderFillKeptInItsCallCallsSeamItFillsItself() async throws {
		// `Shell` builds `Host` in a `SendableInstantiator` and passes up `Host`'s `part`, held in a plain `Instantiator`, so
		// the root's fill of it is `@Sendable` while the builder function it returns is plain. The fill reads the root's
		// `token`, which no level carries, so it stays in its call. `DefaultPanel` calls `GearHost`, whose fill captures nothing and is declared
		// at the root's top; the `@Sendable` fill calls it, through the plain builder function, so it is `@Sendable` too.
		let feature = Self.featureFiles(
			hostDeclarations: ["@Received let analytics: Analytics", "@Instantiated let part: Instantiator<Panel>"],
			otherFiles: [
				"public protocol Gear: Sendable {}",
				seamFixtureType(named: "GearHost", isSeam: true, declarations: ["@Instantiated let gear: any Gear"], conformances: ", Sendable"),
				seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Received let analytics: Analytics", "@Instantiated let hostBuilder: SendableInstantiator<Host>"], conformances: ", Sendable"),
			],
		)
		let fulfillers = [
			SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultGear", fulfilling: "Gear", declarations: []),
			seamFixtureType(named: "Token", declarations: [], conformances: ", Sendable"),
			"""
			@Instantiable(fulfillingAdditionalTypes: [Panel.self], conformsElsewhere: true)
			public final class DefaultPanel: Panel, @unchecked Sendable {
			    public init(name: String, analytics: Analytics, token: Token, gearHost: GearHost) {
			        self.name = name
			        self.analytics = analytics
			        self.token = token
			        self.gearHost = gearHost
			        super.init(title: name)
			    }

			    @Forwarded let name: String
			    @Received let analytics: Analytics
			    @Received let token: Token
			    @Instantiated let gearHost: GearHost
			}
			""",
		]
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let analytics: Analytics", "@Instantiated let token: Token", "@Instantiated let shell: Shell"])
		let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: fulfillers + [root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        @Sendable nonisolated func __safeDI_gearBuilder_GearHost() -> GearHost.__safeDI_GearCarrier<any Gear> {
			            .init(gear: {
			                let gear: any Gear = DefaultGear()
			                return gear
			            })
			        }
			        let analytics = Analytics()
			        let token = Token()
			        func __safeDI_shell() -> Shell {
			            _ = Shell.__safeDI_Shell_FAD8E6B8C1E0198E.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            @Sendable nonisolated func __safeDI_panelBuilder_Host_part(analytics: Analytics) -> Instantiator<Panel>.Builder {
			                func __safeDI_part(name: String) -> DefaultPanel {
			                    func __safeDI_gearHost() -> GearHost {
			                        _ = GearHost.__safeDI_GearHost_3306B0475BD7CA86.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			                        return GearHost(__safeDI_gearBuilder: __safeDI_gearBuilder_GearHost())
			                    }
			                    let gearHost: GearHost = __safeDI_gearHost()
			                    return DefaultPanel(name: name, analytics: analytics, token: token, gearHost: gearHost)
			                }
			                return { forwarded in __safeDI_part(name: forwarded) }
			            }
			            @Sendable nonisolated func __safeDI_panelSendableBuilder_Shell() -> Shell.__safeDI_PanelSendableCarrier<Panel> {
			                .init(hostBuilder: { __safeDI_panelBuilder_Host() })
			            }
			            @Sendable nonisolated func __safeDI_panelBuilder_Host() -> Host.__safeDI_PanelCarrier<Panel> {
			                .init(part: { values_analytics in __safeDI_panelBuilder_Host_part(analytics: values_analytics) })
			            }
			            return Shell(__safeDI_analytics: analytics, __safeDI_panelSendableBuilder: __safeDI_panelSendableBuilder_Shell())
			        }
			        let shell: Shell = __safeDI_shell()
			        self.init(analytics: analytics, token: token, shell: shell)
			    }
			}
			""",
		])
		try await expectValuesEqualVisibleBuild(
			output,
			modules: modules,
			visibleModules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature + fulfillers, app: [root]),
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe(#"Root().shell.hostBuilder.instantiate().part.instantiate("name")"#)],
		)
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_PairGadget_GadgetCarrier<__safeDI_Built> {
		        public let erased: (Analytics) -> ErasedInstantiator<(count: Int, name: String), __safeDI_Built>.Builder

		        public init(erased: @escaping (Analytics) -> ErasedInstantiator<(count: Int, name: String), __safeDI_Built>.Builder) {
		            self.erased = erased
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<(count: Int, name: String), __safeDI_Built>.Builder) {
		            self.init(erased: { _ in __safeDI_builder })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_PairPanelCarrier<__safeDI_Built> {
		        public let held: (Analytics, ErasedInstantiator<(count: Int, name: String), any Gadget>) -> ErasedInstantiator<PairPanel.ForwardedProperties, __safeDI_Built>.Builder

		        public init(held: @escaping (Analytics, ErasedInstantiator<(count: Int, name: String), any Gadget>) -> ErasedInstantiator<PairPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.held = held
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<PairPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.init(held: { _, _ in __safeDI_builder })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_pairGadget_GadgetBuilder: __safeDI_PairGadget_GadgetCarrier<any Gadget>, __safeDI_pairPanelBuilder: __safeDI_PairPanelCarrier<PairPanel>) {
		        let analytics = Analytics()
		        let erased = ErasedInstantiator<(count: Int, name: String), any Gadget>(__safeDI_pairGadget_GadgetBuilder.erased(analytics))
		        let held = Instantiator<PairPanel>(__safeDI_pairPanelBuilder.held(analytics, erased))
		        self.init(analytics: analytics, erased: erased, held: held)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_F096C02FA24133CC {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_pairGadget_GadgetBuilder_Host_erased(analytics: Analytics) -> ErasedInstantiator<(count: Int, name: String), any Gadget>.Builder {
			            return __safeDI_fillBody_F2A172BAB83DC6CB(analytics: analytics)
			        }
			        func __safeDI_fillBody_F2A172BAB83DC6CB(analytics: Analytics) -> ErasedInstantiator<(count: Int, name: String), any Gadget>.Builder {
			            func __safeDI_erased(count: Int, name: String) -> PairGadget {
			                PairGadget(count: count, name: name, analytics: analytics)
			            }
			            return { forwarded in __safeDI_erased(count: forwarded.count, name: forwarded.name) }
			        }
			        func __safeDI_pairPanelBuilder_Host_held(analytics: Analytics) -> Instantiator<PairPanel>.Builder {
			            return __safeDI_fillBody_D0ADDD197C3103A2(analytics: analytics)
			        }
			        func __safeDI_fillBody_D0ADDD197C3103A2(analytics: Analytics) -> Instantiator<PairPanel>.Builder {
			            func __safeDI_held(count: Int, name: String) -> DefaultPairPanel {
			                DefaultPairPanel(count: count, name: name, analytics: analytics)
			            }
			            return { forwarded in __safeDI_held(count: forwarded.count, name: forwarded.name) }
			        }
			        func __safeDI_pairGadget_GadgetBuilder_Host() -> Host.__safeDI_PairGadget_GadgetCarrier<any Gadget> {
			            .init(erased: { values_analytics in __safeDI_pairGadget_GadgetBuilder_Host_erased(analytics: values_analytics) })
			        }
			        func __safeDI_pairPanelBuilder_Host() -> Host.__safeDI_PairPanelCarrier<PairPanel> {
			            .init(held: { values_analytics, values_erased in __safeDI_pairPanelBuilder_Host_held(analytics: values_analytics) })
			        }
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_F096C02FA24133CC.self\(seamCallComment(seam: "Host"))
			            return Host(__safeDI_pairGadget_GadgetBuilder: __safeDI_pairGadget_GadgetBuilder_Host(), __safeDI_pairPanelBuilder: __safeDI_pairPanelBuilder_Host())
			        }
			        let host: Host = __safeDI_host()
			        self.init(host: host)
			    }
			}
			""",
		])
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
		// The fill's body is named after the hash of its text, which spells the forwarded value as written.
		let fillBodyName = spelling == "()" ? "__safeDI_fillBody_763AC7074CD87592" : "__safeDI_fillBody_8FD969695F77761B"
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + """
		extension Host {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_DefaultGadget_GadgetCarrier<__safeDI_Built> {
		        public let part: (Analytics) -> ErasedInstantiator<(), __safeDI_Built>.Builder

		        public init(part: @escaping (Analytics) -> ErasedInstantiator<(), __safeDI_Built>.Builder) {
		            self.part = part
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(part: { _ in { _ in __safeDI_builder() } })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_defaultGadget_GadgetBuilder: __safeDI_DefaultGadget_GadgetCarrier<any Gadget>) {
		        let analytics = Analytics()
		        let part = ErasedInstantiator<\(spelling), any Gadget>(__safeDI_defaultGadget_GadgetBuilder.part(analytics))
		        self.init(analytics: analytics, part: part)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_BBBB471B63CC96BB {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_defaultGadget_GadgetBuilder_Host_part(analytics: Analytics) -> ErasedInstantiator<\(spelling), any Gadget>.Builder {
			            return \(fillBodyName)(analytics: analytics)
			        }
			        func \(fillBodyName)(analytics: Analytics) -> ErasedInstantiator<\(spelling), any Gadget>.Builder {
			            func __safeDI_part() -> DefaultGadget {
			                DefaultGadget(analytics: analytics)
			            }
			            return { _ in __safeDI_part() }
			        }
			        func __safeDI_defaultGadget_GadgetBuilder_Host() -> Host.__safeDI_DefaultGadget_GadgetCarrier<any Gadget> {
			            .init(part: { values_analytics in __safeDI_defaultGadget_GadgetBuilder_Host_part(analytics: values_analytics) })
			        }
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_BBBB471B63CC96BB.self\(seamCallComment(seam: "Host"))
			            return Host(__safeDI_defaultGadget_GadgetBuilder: __safeDI_defaultGadget_GadgetBuilder_Host())
			        }
			        let host: Host = __safeDI_host()
			        self.init(host: host)
			    }
			}
			""",
		])
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_EmptyPanelCarrier<__safeDI_Built> {
		        public let held: (Analytics) -> ErasedInstantiator<EmptyPanel.ForwardedProperties, __safeDI_Built>.Builder

		        public init(held: @escaping (Analytics) -> ErasedInstantiator<EmptyPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.held = held
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<EmptyPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.init(held: { _ in __safeDI_builder })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_emptyPanelBuilder: __safeDI_EmptyPanelCarrier<EmptyPanel>) {
		        let analytics = Analytics()
		        let held = Instantiator<EmptyPanel>(__safeDI_emptyPanelBuilder.held(analytics))
		        self.init(analytics: analytics, held: held)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_F661F6F058163B02 {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_emptyPanelBuilder_Host_held(analytics: Analytics) -> Instantiator<EmptyPanel>.Builder {
			            return __safeDI_fillBody_1FAB92EF0A237880(analytics: analytics)
			        }
			        func __safeDI_fillBody_1FAB92EF0A237880(analytics: Analytics) -> Instantiator<EmptyPanel>.Builder {
			            func __safeDI_held() -> DefaultEmptyPanel {
			                DefaultEmptyPanel(analytics: analytics)
			            }
			            return { _ in __safeDI_held() }
			        }
			        func __safeDI_emptyPanelBuilder_Host() -> Host.__safeDI_EmptyPanelCarrier<EmptyPanel> {
			            .init(held: { values_analytics in __safeDI_emptyPanelBuilder_Host_held(analytics: values_analytics) })
			        }
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_F661F6F058163B02.self\(seamCallComment(seam: "Host"))
			            return Host(__safeDI_emptyPanelBuilder: __safeDI_emptyPanelBuilder_Host())
			        }
			        let host: Host = __safeDI_host()
			        self.init(host: host)
			    }
			}
			""",
		])
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
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_panelBuilder_Host_forwarded(analytics: Analytics) -> Instantiator<Panel>.Builder {
			            return __safeDI_fillBody_994C06F79EC0112D(analytics: analytics)
			        }
			        func __safeDI_fillBody_994C06F79EC0112D(analytics: Analytics) -> Instantiator<Panel>.Builder {
			            func __safeDI_forwarded(name: String) -> DefaultPanel {
			                DefaultPanel(name: name, analytics: analytics)
			            }
			            return { forwarded in __safeDI_forwarded(name: forwarded) }
			        }
			        func __safeDI_panelBuilder_Host() -> Host.__safeDI_PanelCarrier<Panel> {
			            .init(forwarded: { values_analytics in __safeDI_panelBuilder_Host_forwarded(analytics: values_analytics) })
			        }
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_F26543937F780D4F.self\(seamCallComment(seam: "Host"))
			            return Host(__safeDI_panelBuilder: __safeDI_panelBuilder_Host())
			        }
			        let host: Host = __safeDI_host()
			        self.init(host: host)
			    }
			}
			""",
		])
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
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, ["App.swift": generatedFileHeader + (isSendable ? """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        @Sendable nonisolated func __safeDI_loopingGadget_GadgetSendableBuilder_Host_again() -> SendableErasedInstantiator<String, any Gadget>.Builder {
		            return __safeDI_fillBody_69CA4B87868BAAC8()
		        }
		        @Sendable nonisolated func __safeDI_fillBody_69CA4B87868BAAC8() -> SendableErasedInstantiator<String, any Gadget>.Builder {
		            @Sendable nonisolated func __safeDI_again(name: String) -> LoopingGadget {
		                let again = SendableErasedInstantiator<String, any Gadget> {
		                    __safeDI_again(name: $0)
		                }
		                return LoopingGadget(name: name, again: again)
		            }
		            return { forwarded in __safeDI_again(name: forwarded) }
		        }
		        @Sendable nonisolated func __safeDI_loopingGadget_GadgetSendableBuilder_Host() -> Host.__safeDI_LoopingGadget_GadgetSendableCarrier<any Gadget> {
		            .init(again: { __safeDI_loopingGadget_GadgetSendableBuilder_Host_again() })
		        }
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_21623A769023CF80.self\(seamCallComment(seam: "Host"))
		            return Host(__safeDI_loopingGadget_GadgetSendableBuilder: __safeDI_loopingGadget_GadgetSendableBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		""" : """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        func __safeDI_loopingGadget_GadgetBuilder_Host_again() -> ErasedInstantiator<String, any Gadget>.Builder {
		            return __safeDI_fillBody_C21F334F68518DF4()
		        }
		        func __safeDI_fillBody_C21F334F68518DF4() -> ErasedInstantiator<String, any Gadget>.Builder {
		            func __safeDI_again(name: String) -> LoopingGadget {
		                let again = ErasedInstantiator<String, any Gadget> {
		                    __safeDI_again(name: $0)
		                }
		                return LoopingGadget(name: name, again: again)
		            }
		            return { forwarded in __safeDI_again(name: forwarded) }
		        }
		        func __safeDI_loopingGadget_GadgetBuilder_Host() -> Host.__safeDI_LoopingGadget_GadgetCarrier<any Gadget> {
		            .init(again: { __safeDI_loopingGadget_GadgetBuilder_Host_again() })
		        }
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_EA5802D3C5040509.self\(seamCallComment(seam: "Host"))
		            return Host(__safeDI_loopingGadget_GadgetBuilder: __safeDI_loopingGadget_GadgetBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		""")])
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
		        public let ownerBuilder: @Sendable () -> __safeDI_PanelCarrier_Owner<__safeDI_Built>

		        public init(ownerBuilder: @escaping @Sendable () -> __safeDI_PanelCarrier_Owner<__safeDI_Built>) {
		            self.ownerBuilder = ownerBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.init(ownerBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_analytics analytics: Analytics, __safeDI_panelSendableBuilder: __safeDI_PanelSendableCarrier<Panel>) {
		        @inline(never) @Sendable nonisolated func __safeDI_ownerBuilder() -> Owner {
		            let __safeDI_panelSendableBuilder_ownerBuilder = __safeDI_panelSendableBuilder.ownerBuilder()
		            let held = Instantiator<Panel>(__safeDI_panelSendableBuilder_ownerBuilder.held())
		            return Owner(held: held)
		        }
		        let ownerBuilder = SendableInstantiator<Owner>(__safeDI_ownerBuilder)
		        self.init(analytics: analytics, ownerBuilder: ownerBuilder)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_B82541C017DA7E0A {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        let analytics = Analytics()
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_B82541C017DA7E0A.self\(seamCallComment(seam: "Host"))
			            @Sendable nonisolated func __safeDI_panelSendableBuilder_Host_Owner_Scope_held() -> Instantiator<Panel>.Builder {
			                func __safeDI_held(name: String) -> DefaultPanel {
			                    DefaultPanel(name: name, analytics: analytics)
			                }
			                return { forwarded in __safeDI_held(name: forwarded) }
			            }
			            @Sendable nonisolated func __safeDI_panelSendableBuilder_Host() -> Host.__safeDI_PanelSendableCarrier<Panel> {
			                .init(ownerBuilder: { __safeDI_panelBuilder_Host_Owner_Scope() })
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
			""",
		])
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_PanelSendableCarrier<__safeDI_Built>: Sendable {
		        public let ownerBuilder_Sendable: __safeDI_PanelSendableCarrier_Owner<__safeDI_Built>

		        public init(ownerBuilder_Sendable: __safeDI_PanelSendableCarrier_Owner<__safeDI_Built>) {
		            self.ownerBuilder_Sendable = ownerBuilder_Sendable
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.init(ownerBuilder_Sendable: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_PanelSendableCarrier_Owner<__safeDI_Built>: Sendable {
		        public let held: @Sendable () -> SendableErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder

		        public init(held: @escaping @Sendable () -> SendableErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.held = held
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.init(held: { __safeDI_builder })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_analytics analytics: Analytics, __safeDI_panelSendableBuilder: __safeDI_PanelSendableCarrier<Panel>) {
		        @inline(never) @Sendable nonisolated func __safeDI_ownerBuilder() -> Owner {
		            let __safeDI_panelSendableBuilder_ownerBuilder_Sendable = __safeDI_panelSendableBuilder.ownerBuilder_Sendable
		            let tally = Tally()
		            let held = SendableInstantiator<Panel>(__safeDI_panelSendableBuilder_ownerBuilder_Sendable.held())
		            return Owner(tally: tally, held: held)
		        }
		        let ownerBuilder = SendableInstantiator<Owner>(__safeDI_ownerBuilder)
		        self.init(analytics: analytics, ownerBuilder: ownerBuilder)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_10DBAA62B8BDA9F8 {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        let analytics = Analytics()
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_10DBAA62B8BDA9F8.self\(seamCallComment(seam: "Host"))
			            @Sendable nonisolated func __safeDI_panelSendableBuilder_Host_Owner_Scope_held() -> SendableInstantiator<Panel>.Builder {
			                @Sendable nonisolated func __safeDI_held(name: String) -> DefaultPanel {
			                    DefaultPanel(name: name, analytics: analytics)
			                }
			                return { forwarded in __safeDI_held(name: forwarded) }
			            }
			            @Sendable nonisolated func __safeDI_panelSendableBuilder_Host() -> Host.__safeDI_PanelSendableCarrier<Panel> {
			                .init(ownerBuilder_Sendable: __safeDI_panelSendableBuilder_Host_Owner_Scope())
			            }
			            @Sendable nonisolated func __safeDI_panelSendableBuilder_Host_Owner_Scope() -> Host.__safeDI_PanelSendableCarrier_Owner<Panel> {
			                .init(held: { __safeDI_panelSendableBuilder_Host_Owner_Scope_held() })
			            }
			            return Host(__safeDI_analytics: analytics, __safeDI_panelSendableBuilder: __safeDI_panelSendableBuilder_Host())
			        }
			        let host: Host = __safeDI_host()
			        self.init(analytics: analytics, host: host)
			    }
			}
			""",
		])
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_PanelCarrier<__safeDI_Built> {
		        public let part: () -> ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder

		        public init(part: @escaping () -> ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.part = part
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.init(part: { __safeDI_builder })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_panelBuilder: __safeDI_PanelCarrier<Panel>) {
		        let part = Instantiator<Panel>(__safeDI_panelBuilder.part())
		        self.init(part: part)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_5304DA22A233A920 {}
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

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_panelBuilder: __safeDI_PanelCarrier<Panel>) {
		        @inline(never) func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_5304DA22A233A920.self
		            return Inner(__safeDI_panelBuilder: __safeDI_panelBuilder.inner)
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(inner: inner)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_39BC2731DA822B84 {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_panelBuilder_Inner_part() -> Instantiator<Panel>.Builder {
			            return __safeDI_fillBody_5576EF71E670497F()
			        }
			        func __safeDI_fillBody_5576EF71E670497F() -> Instantiator<Panel>.Builder {
			            func __safeDI_part(name: String) -> DefaultPanel {
			                DefaultPanel(name: name)
			            }
			            return { forwarded in __safeDI_part(name: forwarded) }
			        }
			        func __safeDI_panelBuilder_Outer() -> Outer.__safeDI_PanelCarrier<Panel> {
			            .init(inner: __safeDI_panelBuilder_Inner())
			        }
			        func __safeDI_panelBuilder_Inner() -> Inner.__safeDI_PanelCarrier<Panel> {
			            .init(part: { __safeDI_panelBuilder_Inner_part() })
			        }
			        func __safeDI_outer() -> Outer {
			            _ = Outer.__safeDI_Outer_39BC2731DA822B84.self\(seamCallComment(seam: "Outer"))
			            return Outer(__safeDI_panelBuilder: __safeDI_panelBuilder_Outer())
			        }
			        let outer: Outer = __safeDI_outer()
			        self.init(outer: outer)
			    }
			}
			""",
		])
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
		expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, [
			"Middle.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Host {
			    nonisolated public enum SafeDIScope_Gadget {
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
			    }

			    nonisolated public enum SafeDISendableScope_Gadget {
			        nonisolated public struct inner_widgetSendableBuilder_Values: Sendable {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			            public let inner_widgetSendableBuilder: @Sendable (inner_widgetSendableBuilder_Values) -> SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>

			            public init(inner_widgetSendableBuilder: @escaping @Sendable (inner_widgetSendableBuilder_Values) -> SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>) {
			                self.inner_widgetSendableBuilder = inner_widgetSendableBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                self.init(inner_widgetSendableBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			            }
			        }
			    }

			    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_gadgetSendableBuilder: SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget>) {
			        @inline(never) func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_6D43C09429362F02.self\(seamCallComment(seam: "Inner"))
			            @inline(never) @Sendable nonisolated func __safeDI_widgetSendableBuilder_Inner_widget() -> any Widget {
			                @inline(never) @Sendable nonisolated func __safeDI_widget() -> DefaultWidget {
			                    let __safeDI_gadgetSendableBuilder_inner_widgetSendableBuilder = __safeDI_gadgetSendableBuilder.inner_widgetSendableBuilder(SafeDISendableScope_Gadget.inner_widgetSendableBuilder_Values())
			                    let gadget: any Gadget = __safeDI_gadgetSendableBuilder_inner_widgetSendableBuilder.gadget(SafeDIScope_Gadget.DefaultWidget_Scope.gadget_Values())
			                    return DefaultWidget(gadget: gadget)
			                }
			                return __safeDI_widget()
			            }
			            @inline(never) @Sendable nonisolated func __safeDI_widgetSendableBuilder_Inner() -> Inner.__safeDI_WidgetSendableCarrier<any Widget> {
			                .init(widget: { __safeDI_widgetSendableBuilder_Inner_widget() })
			            }
			            return Inner(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Inner())
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(inner: inner)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_961FF0366D8C802E {}
			}
			""",
		])
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_LabeledGadget_GadgetCarrier<__safeDI_Built> {
		        public let part: (Analytics) -> ErasedInstantiator<Label, __safeDI_Built>.Builder

		        public init(part: @escaping (Analytics) -> ErasedInstantiator<Label, __safeDI_Built>.Builder) {
		            self.part = part
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Label, __safeDI_Built>.Builder) {
		            self.init(part: { _ in __safeDI_builder })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_labeledGadget_GadgetBuilder: __safeDI_LabeledGadget_GadgetCarrier<any Gadget>) {
		        let analytics = Analytics()
		        let part = ErasedInstantiator<Label, any Gadget>(__safeDI_labeledGadget_GadgetBuilder.part(analytics))
		        self.init(analytics: analytics, part: part)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_518400D9315C3321 {}
		}
		""" : """
		extension Host {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_LabeledGadget_GadgetCarrier<__safeDI_Built> {
		        public let part: (Analytics) -> ErasedInstantiator<Label, __safeDI_Built>.Builder

		        public init(part: @escaping (Analytics) -> ErasedInstantiator<Label, __safeDI_Built>.Builder) {
		            self.part = part
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Label, __safeDI_Built>.Builder) {
		            self.init(part: { _ in __safeDI_builder })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    package init(__safeDI_labeledGadget_GadgetBuilder: __safeDI_LabeledGadget_GadgetCarrier<any Gadget>) {
		        let analytics = Analytics()
		        let part = ErasedInstantiator<Label, any Gadget>(__safeDI_labeledGadget_GadgetBuilder.part(analytics))
		        self.init(analytics: analytics, part: part)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_85EF4B83F34F4F13 {}
		}
		""")])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, ["App.swift": generatedFileHeader + (access == "public" ? """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        func __safeDI_labeledGadget_GadgetBuilder_Host_part(analytics: Analytics) -> ErasedInstantiator<Label, any Gadget>.Builder {
		            return __safeDI_fillBody_01CABEC4B4955108(analytics: analytics)
		        }
		        func __safeDI_fillBody_01CABEC4B4955108(analytics: Analytics) -> ErasedInstantiator<Label, any Gadget>.Builder {
		            func __safeDI_part(label: Label) -> LabeledGadget {
		                LabeledGadget(label: label, analytics: analytics)
		            }
		            return { forwarded in __safeDI_part(label: forwarded) }
		        }
		        func __safeDI_labeledGadget_GadgetBuilder_Host() -> Host.__safeDI_LabeledGadget_GadgetCarrier<any Gadget> {
		            .init(part: { values_analytics in __safeDI_labeledGadget_GadgetBuilder_Host_part(analytics: values_analytics) })
		        }
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_518400D9315C3321.self\(seamCallComment(seam: "Host"))
		            return Host(__safeDI_labeledGadget_GadgetBuilder: __safeDI_labeledGadget_GadgetBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		""" : """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        func __safeDI_labeledGadget_GadgetBuilder_Host_part(analytics: Analytics) -> ErasedInstantiator<Label, any Gadget>.Builder {
		            return __safeDI_fillBody_01CABEC4B4955108(analytics: analytics)
		        }
		        func __safeDI_fillBody_01CABEC4B4955108(analytics: Analytics) -> ErasedInstantiator<Label, any Gadget>.Builder {
		            func __safeDI_part(label: Label) -> LabeledGadget {
		                LabeledGadget(label: label, analytics: analytics)
		            }
		            return { forwarded in __safeDI_part(label: forwarded) }
		        }
		        func __safeDI_labeledGadget_GadgetBuilder_Host() -> Host.__safeDI_LabeledGadget_GadgetCarrier<any Gadget> {
		            .init(part: { values_analytics in __safeDI_labeledGadget_GadgetBuilder_Host_part(analytics: values_analytics) })
		        }
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_85EF4B83F34F4F13.self\(seamCallComment(seam: "Host"))
		            return Host(__safeDI_labeledGadget_GadgetBuilder: __safeDI_labeledGadget_GadgetBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		""")])
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
		        gadgetBuilder: { PlainGadget() },
		        panelBuilder: { title in Panel(title: title) },
		        panelSendableBuilder: { title in Panel(title: title) }
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_GadgetCarrier<__safeDI_Built> {
		        public let again: __safeDI_GadgetCarrier_Middle<__safeDI_Built>

		        public init(again: __safeDI_GadgetCarrier_Middle<__safeDI_Built>) {
		            self.again = again
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(again: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_GadgetCarrier_Middle<__safeDI_Built> {
		        public let again: (Beneath) -> __safeDI_Built

		        public init(again: @escaping (Beneath) -> __safeDI_Built) {
		            self.again = again
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(again: { _ in __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_gadgetBuilder: __safeDI_GadgetCarrier<any Gadget>) {
		        let __safeDI_gadgetBuilder_again = __safeDI_gadgetBuilder.again
		        @inline(never) func __safeDI_again() -> Middle {
		            let beneath: Beneath = __safeDI_beneath()
		            @inline(never) func __safeDI_again_Gadget() -> any Gadget {
		                __safeDI_gadgetBuilder_again.again(beneath)
		            }
		            let again = LazilyInstantiated<any Gadget>(__safeDI_again_Gadget)
		            return Middle(again: again, beneath: beneath)
		        }
		        @inline(never) func __safeDI_beneath() -> Beneath {
		            let again = Instantiator<Middle>(__safeDI_again)
		            return Beneath(again: again)
		        }
		        let again = Instantiator<Middle>(__safeDI_again)
		        self.init(again: again)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_ADDE20B2EE2EC309 {}
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
			    nonisolated public enum SafeDISendableMockScope_Panel {
			        nonisolated public struct part_Values: Sendable {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			            public let part: @Sendable (part_Values) -> SendableErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder

			            public init(part: @escaping @Sendable (part_Values) -> SendableErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
			                self.part = part
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<Panel.ForwardedProperties, __safeDI_Built>.Builder) {
			                self.init(part: { _ in __safeDI_builder })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            analytics: (() -> Analytics)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                analytics: analytics
			            )
			        }

			        public var analytics: (() -> Analytics)? { __safeDI_storage.analytics }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                analytics: (() -> Analytics)?
			            ) {
			                self.analytics = analytics
			            }

			            let analytics: (() -> Analytics)?
			        }
			    }

			    public static func mock(
			        panelSendableBuilder: @escaping SendableInstantiator<Panel>.Builder,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Service {
			        Service.__safeDI_mock(panelSendableBuilder: .init(__safeDI_noScope: panelSendableBuilder), safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        panelSendableBuilder __safeDI_panelSendableBuilder: Service.SafeDISendableMockScope_Panel.__safeDI_Builder<Panel>,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Service {
			        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
			        let part = SendableInstantiator<Panel>(__safeDI_panelSendableBuilder.part(SafeDISendableMockScope_Panel.part_Values()))
			        return Service(analytics: analytics, part: part)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_mock_8F5C6DDDC76AE12D {}
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
		    nonisolated public enum SafeDIMockScope_Gadget {
		        nonisolated public struct again_Values {}

		        nonisolated public enum Middle_Scope {
		            nonisolated public struct again_Values {
		                public let beneath: Beneath
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let again: (again_Values) -> __safeDI_Built

		                public init(again: @escaping (again_Values) -> __safeDI_Built) {
		                    self.again = again
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(again: { _ in __safeDI_builder() })
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let again: (again_Values) -> SafeDIMockScope_Gadget.Middle_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(again: @escaping (again_Values) -> SafeDIMockScope_Gadget.Middle_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.again = again
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(again: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            again: __safeDI_Middle_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                again: again
		            )
		        }

		        public var again: __safeDI_Middle_MockConfiguration { __safeDI_storage.again }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                again: __safeDI_Middle_MockConfiguration
		            ) {
		                self.again = again
		            }

		            let again: __safeDI_Middle_MockConfiguration
		        }
		    }

		    public static func mock(
		        gadgetBuilder: @escaping () -> any Gadget,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Service {
		        Service.__safeDI_mock(gadgetBuilder: .init(__safeDI_noScope: gadgetBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        gadgetBuilder __safeDI_gadgetBuilder: Service.SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Service {
		        let __safeDI_gadgetBuilder_again = __safeDI_gadgetBuilder.again(SafeDIMockScope_Gadget.again_Values())
		        func __safeDI_again() -> Middle {
		            func __safeDI_beneath() -> Beneath {
		                let again = Instantiator<Middle>(__safeDI_again)
		                return Beneath.__safeDI_init(again: again, safeDIBuilder: nil)
		            }
		            let beneath: Beneath = __safeDI_beneath()
		            func __safeDI_again_Gadget() -> any Gadget {
		                __safeDI_gadgetBuilder_again.again(SafeDIMockScope_Gadget.Middle_Scope.again_Values(beneath: beneath))
		            }
		            let again = LazilyInstantiated<any Gadget>(__safeDI_again_Gadget)
		            return Middle.__safeDI_init(again: again, beneath: beneath, safeDIBuilder: safeDIOverrides.again.safeDIBuilder)
		        }
		        let again = Instantiator<Middle>(__safeDI_again)
		        return Service(again: again)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_mock_1C37BA18F474E3CB {}
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ActionPanelCarrier<__safeDI_Built> {
		        public let part: (Analytics) -> ErasedInstantiator<ActionPanel.ForwardedProperties, __safeDI_Built>.Builder

		        public init(part: @escaping (Analytics) -> ErasedInstantiator<ActionPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.part = part
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<ActionPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.init(part: { _ in __safeDI_builder })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_actionPanelBuilder: __safeDI_ActionPanelCarrier<ActionPanel>) {
		        let analytics = Analytics()
		        let part = Instantiator<ActionPanel>(__safeDI_actionPanelBuilder.part(analytics))
		        self.init(analytics: analytics, part: part)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_73A2F70A927B2DCD {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_actionPanelBuilder_Host_part(analytics: Analytics) -> Instantiator<ActionPanel>.Builder {
			            return __safeDI_fillBody_DB847B9546740658(analytics: analytics)
			        }
			        func __safeDI_fillBody_DB847B9546740658(analytics: Analytics) -> Instantiator<ActionPanel>.Builder {
			            func __safeDI_part(forwardedAction: @escaping () -> Void) -> DefaultActionPanel {
			                DefaultActionPanel(forwardedAction: forwardedAction, analytics: analytics)
			            }
			            return { forwarded in __safeDI_part(forwardedAction: forwarded) }
			        }
			        func __safeDI_actionPanelBuilder_Host() -> Host.__safeDI_ActionPanelCarrier<ActionPanel> {
			            .init(part: { values_analytics in __safeDI_actionPanelBuilder_Host_part(analytics: values_analytics) })
			        }
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_73A2F70A927B2DCD.self\(seamCallComment(seam: "Host"))
			            return Host(__safeDI_actionPanelBuilder: __safeDI_actionPanelBuilder_Host())
			        }
			        let host: Host = __safeDI_host()
			        self.init(host: host)
			    }
			}
			""",
		])
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ActionPanelSendableCarrier<__safeDI_Built>: Sendable {
		        public let part: @Sendable () -> SendableErasedInstantiator<ActionPanel.ForwardedProperties, __safeDI_Built>.Builder

		        public init(part: @escaping @Sendable () -> SendableErasedInstantiator<ActionPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.part = part
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<ActionPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.init(part: { __safeDI_builder })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_analytics analytics: Analytics, __safeDI_actionPanelSendableBuilder: __safeDI_ActionPanelSendableCarrier<ActionPanel>) {
		        let part = SendableInstantiator<ActionPanel>(__safeDI_actionPanelSendableBuilder.part())
		        self.init(analytics: analytics, part: part)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_E3684A9F860DB8D5 {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        let analytics = Analytics()
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_E3684A9F860DB8D5.self\(seamCallComment(seam: "Host"))
			            @Sendable nonisolated func __safeDI_actionPanelSendableBuilder_Host_part() -> SendableInstantiator<ActionPanel>.Builder {
			                @Sendable nonisolated func __safeDI_part(forwardedAction: @escaping @Sendable () -> Void) -> DefaultActionPanel {
			                    DefaultActionPanel(forwardedAction: forwardedAction, analytics: analytics)
			                }
			                return { forwarded in __safeDI_part(forwardedAction: forwarded) }
			            }
			            @Sendable nonisolated func __safeDI_actionPanelSendableBuilder_Host() -> Host.__safeDI_ActionPanelSendableCarrier<ActionPanel> {
			                .init(part: { __safeDI_actionPanelSendableBuilder_Host_part() })
			            }
			            return Host(__safeDI_analytics: analytics, __safeDI_actionPanelSendableBuilder: __safeDI_actionPanelSendableBuilder_Host())
			        }
			        let host: Host = __safeDI_host()
			        self.init(analytics: analytics, host: host)
			    }
			}
			""",
		])
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ActionPanelCarrier<__safeDI_Built> {
		        public let part: (Analytics) -> ErasedInstantiator<ActionPanel.ForwardedProperties, __safeDI_Built>.Builder

		        public init(part: @escaping (Analytics) -> ErasedInstantiator<ActionPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.part = part
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<ActionPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.init(part: { _ in __safeDI_builder })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_actionPanelBuilder: __safeDI_ActionPanelCarrier<ActionPanel>) {
		        let analytics = Analytics()
		        let part = Instantiator<ActionPanel>(__safeDI_actionPanelBuilder.part(analytics))
		        self.init(analytics: analytics, part: part)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_73A2F70A927B2DCD {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_actionPanelBuilder_Host_part(analytics: Analytics) -> Instantiator<ActionPanel>.Builder {
			            return __safeDI_fillBody_F26CFAD11C0AD1A6(analytics: analytics)
			        }
			        func __safeDI_fillBody_F26CFAD11C0AD1A6(analytics: Analytics) -> Instantiator<ActionPanel>.Builder {
			            func __safeDI_part(forwardedAction: @escaping OnTap) -> DefaultActionPanel {
			                DefaultActionPanel(forwardedAction: forwardedAction, analytics: analytics)
			            }
			            return { forwarded in __safeDI_part(forwardedAction: forwarded) }
			        }
			        func __safeDI_actionPanelBuilder_Host() -> Host.__safeDI_ActionPanelCarrier<ActionPanel> {
			            .init(part: { values_analytics in __safeDI_actionPanelBuilder_Host_part(analytics: values_analytics) })
			        }
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_73A2F70A927B2DCD.self\(seamCallComment(seam: "Host"))
			            return Host(__safeDI_actionPanelBuilder: __safeDI_actionPanelBuilder_Host())
			        }
			        let host: Host = __safeDI_host()
			        self.init(host: host)
			    }
			}
			""",
		])
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ActionPanelSendableCarrier<__safeDI_Built>: Sendable {
		        public let part: @Sendable () -> SendableErasedInstantiator<ActionPanel.ForwardedProperties, __safeDI_Built>.Builder

		        public init(part: @escaping @Sendable () -> SendableErasedInstantiator<ActionPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.part = part
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<ActionPanel.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.init(part: { __safeDI_builder })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_analytics analytics: Analytics, __safeDI_actionPanelSendableBuilder: __safeDI_ActionPanelSendableCarrier<ActionPanel>) {
		        let part = SendableInstantiator<ActionPanel>(__safeDI_actionPanelSendableBuilder.part())
		        self.init(analytics: analytics, part: part)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_E3684A9F860DB8D5 {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        let analytics = Analytics()
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_E3684A9F860DB8D5.self\(seamCallComment(seam: "Host"))
			            @Sendable nonisolated func __safeDI_actionPanelSendableBuilder_Host_part() -> SendableInstantiator<ActionPanel>.Builder {
			                @Sendable nonisolated func __safeDI_part(forwardedAction: @escaping SendableOnTap) -> DefaultActionPanel {
			                    DefaultActionPanel(forwardedAction: forwardedAction, analytics: analytics)
			                }
			                return { forwarded in __safeDI_part(forwardedAction: forwarded) }
			            }
			            @Sendable nonisolated func __safeDI_actionPanelSendableBuilder_Host() -> Host.__safeDI_ActionPanelSendableCarrier<ActionPanel> {
			                .init(part: { __safeDI_actionPanelSendableBuilder_Host_part() })
			            }
			            return Host(__safeDI_analytics: analytics, __safeDI_actionPanelSendableBuilder: __safeDI_actionPanelSendableBuilder_Host())
			        }
			        let host: Host = __safeDI_host()
			        self.init(analytics: analytics, host: host)
			    }
			}
			""",
		])
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_TapGadget_AnyGadgetCarrier<__safeDI_Built> {
		        public let part: (Analytics) -> ErasedInstantiator<OnTap, __safeDI_Built>.Builder

		        public init(part: @escaping (Analytics) -> ErasedInstantiator<OnTap, __safeDI_Built>.Builder) {
		            self.part = part
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<OnTap, __safeDI_Built>.Builder) {
		            self.init(part: { _ in __safeDI_builder })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_tapGadget_AnyGadgetBuilder: __safeDI_TapGadget_AnyGadgetCarrier<AnyGadget>) {
		        let analytics = Analytics()
		        let part = ErasedInstantiator<OnTap, AnyGadget>(__safeDI_tapGadget_AnyGadgetBuilder.part(analytics))
		        self.init(analytics: analytics, part: part)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_45E43E6CA8DDC64D {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_tapGadget_AnyGadgetBuilder_Host_part(analytics: Analytics) -> ErasedInstantiator<OnTap, AnyGadget>.Builder {
			            return __safeDI_fillBody_86F373E2147139ED(analytics: analytics)
			        }
			        func __safeDI_fillBody_86F373E2147139ED(analytics: Analytics) -> ErasedInstantiator<OnTap, AnyGadget>.Builder {
			            func __safeDI_part(onTap: @escaping OnTap) -> TapGadget {
			                TapGadget(onTap: onTap, analytics: analytics)
			            }
			            return { forwarded in AnyGadget(__safeDI_part(onTap: forwarded)) }
			        }
			        func __safeDI_tapGadget_AnyGadgetBuilder_Host() -> Host.__safeDI_TapGadget_AnyGadgetCarrier<AnyGadget> {
			            .init(part: { values_analytics in __safeDI_tapGadget_AnyGadgetBuilder_Host_part(analytics: values_analytics) })
			        }
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_45E43E6CA8DDC64D.self\(seamCallComment(seam: "Host"))
			            return Host(__safeDI_tapGadget_AnyGadgetBuilder: __safeDI_tapGadget_AnyGadgetBuilder_Host())
			        }
			        let host: Host = __safeDI_host()
			        self.init(host: host)
			    }
			}
			""",
		])
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_TapGadget_AnyGadgetSendableCarrier<__safeDI_Built>: Sendable {
		        public let part: @Sendable () -> SendableErasedInstantiator<SendableOnTap, __safeDI_Built>.Builder

		        public init(part: @escaping @Sendable () -> SendableErasedInstantiator<SendableOnTap, __safeDI_Built>.Builder) {
		            self.part = part
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<SendableOnTap, __safeDI_Built>.Builder) {
		            self.init(part: { __safeDI_builder })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_analytics analytics: Analytics, __safeDI_tapGadget_AnyGadgetSendableBuilder: __safeDI_TapGadget_AnyGadgetSendableCarrier<AnyGadget>) {
		        let part = SendableErasedInstantiator<SendableOnTap, AnyGadget>(__safeDI_tapGadget_AnyGadgetSendableBuilder.part())
		        self.init(analytics: analytics, part: part)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_3C800FD9223104D7 {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        let analytics = Analytics()
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_3C800FD9223104D7.self\(seamCallComment(seam: "Host"))
			            @Sendable nonisolated func __safeDI_tapGadget_AnyGadgetSendableBuilder_Host_part() -> SendableErasedInstantiator<SendableOnTap, AnyGadget>.Builder {
			                @Sendable nonisolated func __safeDI_part(onTap: @escaping SendableOnTap) -> TapGadget {
			                    TapGadget(onTap: onTap, analytics: analytics)
			                }
			                return { forwarded in AnyGadget(__safeDI_part(onTap: forwarded)) }
			            }
			            @Sendable nonisolated func __safeDI_tapGadget_AnyGadgetSendableBuilder_Host() -> Host.__safeDI_TapGadget_AnyGadgetSendableCarrier<AnyGadget> {
			                .init(part: { __safeDI_tapGadget_AnyGadgetSendableBuilder_Host_part() })
			            }
			            return Host(__safeDI_analytics: analytics, __safeDI_tapGadget_AnyGadgetSendableBuilder: __safeDI_tapGadget_AnyGadgetSendableBuilder_Host())
			        }
			        let host: Host = __safeDI_host()
			        self.init(analytics: analytics, host: host)
			    }
			}
			""",
		])
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
		// A person's closures store the forwarded value, which compiles only where it escapes: as the value each builder
		// takes, of the plain family and of the `@Sendable` one.
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
		        actionPanelBuilder: { action in ActionPanel(action: action) },
		        actionPanelSendableBuilder: { action in ActionPanel(action: action) },
		        sendableTapGadget_AnyGadgetSendableBuilder: { onTap in AnyGadget(SendableStoringGadget(onTap: onTap)) },
		        tapGadget_AnyGadgetBuilder: { onTap in AnyGadget(StoringGadget(onTap: onTap)) }
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
		        actionPanelBuilder: { action in ActionPanel(action: action) },
		        actionPanelSendableBuilder: { action in ActionPanel(action: action) }
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
			    nonisolated public enum SafeDIMockScope_ActionPanel {
			        nonisolated public struct part_Values {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let part: (part_Values) -> ErasedInstantiator<ActionPanel.ForwardedProperties, __safeDI_Built>.Builder

			            public init(part: @escaping (part_Values) -> ErasedInstantiator<ActionPanel.ForwardedProperties, __safeDI_Built>.Builder) {
			                self.part = part
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<ActionPanel.ForwardedProperties, __safeDI_Built>.Builder) {
			                self.init(part: { _ in __safeDI_builder })
			            }
			        }
			    }

			    public static func mock(
			        actionPanelBuilder: @escaping Instantiator<ActionPanel>.Builder
			    ) -> Service {
			        Service.__safeDI_mock(actionPanelBuilder: .init(__safeDI_noScope: actionPanelBuilder))
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        actionPanelBuilder __safeDI_actionPanelBuilder: Service.SafeDIMockScope_ActionPanel.__safeDI_Builder<ActionPanel>
			    ) -> Service {
			        let part = Instantiator<ActionPanel>(__safeDI_actionPanelBuilder.part(SafeDIMockScope_ActionPanel.part_Values()))
			        return Service(part: part)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_mock_F4CFA341CF5D1F83 {}
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
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_gadgetBuilder_Host_part() -> any Gadget {
			            return __safeDI_fillBody_EDDE2E21BA2B06AD()
			        }
			        func __safeDI_fillBody_EDDE2E21BA2B06AD() -> any Gadget {
			            func __safeDI_part() -> DefaultGadget {
			                let kid = Kid(part: nil)
			                return DefaultGadget(kid: kid)
			            }
			            return __safeDI_part()
			        }
			        func __safeDI_gadgetBuilder_Host() -> Host.__safeDI_GadgetCarrier<any Gadget> {
			            .init(part: { __safeDI_gadgetBuilder_Host_part() })
			        }
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_84E665108514B7F7.self\(seamCallComment(seam: "Host"))
			            return Host(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Host())
			        }
			        let host: Host = __safeDI_host()
			        self.init(host: host)
			    }
			}
			""",
		])
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
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, ["App.swift": generatedFileHeader + (firstGeneric == "Label" ? """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        func __safeDI_namedGadget_AnyGadgetBuilder_Host_part() -> ErasedInstantiator<Label, AnyGadget>.Builder {
		            return __safeDI_fillBody_7D710856D246C18D()
		        }
		        func __safeDI_fillBody_7D710856D246C18D() -> ErasedInstantiator<Label, AnyGadget>.Builder {
		            func __safeDI_part(label: Feature.Label) -> NamedGadget {
		                NamedGadget(label: label)
		            }
		            return { forwarded in AnyGadget(__safeDI_part(label: forwarded)) }
		        }
		        func __safeDI_namedGadget_AnyGadgetBuilder_Host() -> Host.__safeDI_NamedGadget_AnyGadgetCarrier<AnyGadget> {
		            .init(part: { __safeDI_namedGadget_AnyGadgetBuilder_Host_part() })
		        }
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_71934DC459E48C08.self\(seamCallComment(seam: "Host"))
		            return Host(__safeDI_namedGadget_AnyGadgetBuilder: __safeDI_namedGadget_AnyGadgetBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		""" : """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        func __safeDI_namedGadget_AnyGadgetBuilder_Host_part() -> ErasedInstantiator<Feature.Label, AnyGadget>.Builder {
		            return __safeDI_fillBody_27E6724FF37A54C9()
		        }
		        func __safeDI_fillBody_27E6724FF37A54C9() -> ErasedInstantiator<Feature.Label, AnyGadget>.Builder {
		            func __safeDI_part(label: Label) -> NamedGadget {
		                NamedGadget(label: label)
		            }
		            return { forwarded in AnyGadget(__safeDI_part(label: forwarded)) }
		        }
		        func __safeDI_namedGadget_AnyGadgetBuilder_Host() -> Host.__safeDI_NamedGadget_AnyGadgetCarrier<AnyGadget> {
		            .init(part: { __safeDI_namedGadget_AnyGadgetBuilder_Host_part() })
		        }
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_3D06EC7721D023B0.self\(seamCallComment(seam: "Host"))
		            return Host(__safeDI_namedGadget_AnyGadgetBuilder: __safeDI_namedGadget_AnyGadgetBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		""")])
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

	// MARK: A cycle closed beneath a hole’s wrapper function

	@Test
	mutating func generate_closesCycleOnItsOwnBuilderFunction_whenItsLabelSpellsTheFunctionAHoleSiteBuildsItsWrapperAround() async throws {
		// The site of `trackerBuilder` names its wrapper’s function `__safeDI_trackerBuilder_`, apart from the builder it
		// calls, which is the name of the function `trackerBuilder_` builds `B` with, and `D` closes the cycle on that one.
		let feature = [
			"public protocol Tracker {}",
			seamFixtureType(named: "Feature", isSeam: true, declarations: ["@Instantiated let trackerBuilder_: Instantiator<B>"]),
			seamFixtureType(named: "B", declarations: ["@Instantiated let cBuilder: Instantiator<C>"]),
			seamFixtureType(named: "C", declarations: ["@Instantiated let trackerBuilder: LazilyInstantiated<any Tracker>", "@Instantiated let dBuilder: Instantiator<D>"]),
			seamFixtureType(named: "D", declarations: ["@Instantiated let trackerBuilder_: Instantiator<B>"]),
		]
		let app = [
			SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultTracker", fulfilling: "Tracker", declarations: []),
			seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let feature: Feature"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: app), integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, [
			"Feature.swift": generatedFileHeader + """
			extension Feature {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_TrackerCarrier<__safeDI_Built> {
			        public let trackerBuilder_: __safeDI_TrackerCarrier_B<__safeDI_Built>

			        public init(trackerBuilder_: __safeDI_TrackerCarrier_B<__safeDI_Built>) {
			            self.trackerBuilder_ = trackerBuilder_
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(trackerBuilder_: .init(__safeDI_noScope: __safeDI_builder))
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_TrackerCarrier_B<__safeDI_Built> {
			        public let cBuilder: __safeDI_TrackerCarrier_C<__safeDI_Built>

			        public init(cBuilder: __safeDI_TrackerCarrier_C<__safeDI_Built>) {
			            self.cBuilder = cBuilder
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(cBuilder: .init(__safeDI_noScope: __safeDI_builder))
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_TrackerCarrier_C<__safeDI_Built> {
			        public let trackerBuilder: (Instantiator<D>) -> __safeDI_Built

			        public init(trackerBuilder: @escaping (Instantiator<D>) -> __safeDI_Built) {
			            self.trackerBuilder = trackerBuilder
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(trackerBuilder: { _ in __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_trackerBuilder: __safeDI_TrackerCarrier<any Tracker>) {
			        let __safeDI_trackerBuilder_trackerBuilder_ = __safeDI_trackerBuilder.trackerBuilder_
			        @inline(never) func __safeDI_trackerBuilder_() -> B {
			            let __safeDI_trackerBuilder_cBuilder = __safeDI_trackerBuilder_trackerBuilder_.cBuilder
			            let cBuilder = Instantiator<C> {
			                __safeDI_cBuilder(__safeDI_trackerBuilder_cBuilder: __safeDI_trackerBuilder_cBuilder)
			            }
			            return B(cBuilder: cBuilder)
			        }
			        @inline(never) func __safeDI_cBuilder(__safeDI_trackerBuilder_cBuilder: __safeDI_TrackerCarrier_C<any Tracker>) -> C {
			            let dBuilder = Instantiator<D>(__safeDI_dBuilder)
			            @inline(never) func __safeDI_trackerBuilder__Tracker() -> any Tracker {
			                __safeDI_trackerBuilder_cBuilder.trackerBuilder(dBuilder)
			            }
			            let trackerBuilder = LazilyInstantiated<any Tracker>(__safeDI_trackerBuilder__Tracker)
			            return C(trackerBuilder: trackerBuilder, dBuilder: dBuilder)
			        }
			        @inline(never) func __safeDI_dBuilder() -> D {
			            let trackerBuilder_ = Instantiator<B>(__safeDI_trackerBuilder_)
			            return D(trackerBuilder_: trackerBuilder_)
			        }
			        let trackerBuilder_ = Instantiator<B>(__safeDI_trackerBuilder_)
			        self.init(trackerBuilder_: trackerBuilder_)
			    }
			}

			extension Feature {
			    public enum __safeDI_Feature_099A0C5D8D989C5E {}
			}
			""",
		])
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
