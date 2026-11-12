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
			case .lazilyInstantiated: "__safeDI_Host_5204B43135531518"
			case .sendableLazilyInstantiated: "__safeDI_Host_59B87934D6DE9D4C"
			case .instantiator: "__safeDI_Host_AEA317A3D7F1BB51"
			case .sendableInstantiator: "__safeDI_Host_7148C830203559E9"
			case .erasedInstantiator: "__safeDI_Host_92556D6EC2528817"
			case .sendableErasedInstantiator: "__safeDI_Host_6EAEEE6F2A37D68B"
			}
		}

		var seamBody: String {
			switch self {
			case .lazilyInstantiated:
				"""
				extension Host {
				    public struct SafeDIScope_Host_part {
				        public let analytics: Analytics
				    }

				    public init(partBuilder: @escaping (SafeDIScope_Host_part) -> any Gadget) {
				        let __safeDI_partBuilder = partBuilder
				        let analytics = Analytics()
				        func __safeDI_part() -> any Gadget {
				            __safeDI_partBuilder(SafeDIScope_Host_part(analytics: analytics))
				        }
				        let part = LazilyInstantiated<any Gadget>(__safeDI_part)
				        self.init(analytics: analytics, part: part)
				    }
				}
				"""
			case .sendableLazilyInstantiated:
				"""
				extension Host {
				    public enum SafeDIScope_Host_part {
				        public struct Outer {
				            public let analytics: Analytics
				        }

				        public struct Inner {}
				    }

				    public init(partBuilder: @escaping (SafeDIScope_Host_part.Outer) -> @Sendable (SafeDIScope_Host_part.Inner) -> any Gadget) {
				        let __safeDI_partBuilder = partBuilder
				        let analytics = Analytics()
				        let __safeDI_partBuilder_Inner = __safeDI_partBuilder(SafeDIScope_Host_part.Outer(analytics: analytics))
				        @Sendable func __safeDI_part() -> any Gadget {
				            __safeDI_partBuilder_Inner(SafeDIScope_Host_part.Inner())
				        }
				        let part = SendableLazilyInstantiated<any Gadget>(__safeDI_part)
				        self.init(analytics: analytics, part: part)
				    }
				}
				"""
			case .instantiator:
				"""
				extension Host {
				    public struct SafeDIScope_Host_part {
				        public let analytics: Analytics
				    }

				    public init(partBuilder: @escaping Instantiator<Panel>.SeamBuilder<SafeDIScope_Host_part>) {
				        let __safeDI_partBuilder = partBuilder
				        let analytics = Analytics()
				        let part = Instantiator<Panel> {
				            __safeDI_partBuilder(SafeDIScope_Host_part(analytics: analytics), $0)
				        }
				        self.init(analytics: analytics, part: part)
				    }
				}
				"""
			case .sendableInstantiator:
				"""
				extension Host {
				    public enum SafeDIScope_Host_part {
				        public struct Outer {
				            public let analytics: Analytics
				        }

				        public struct Inner {}
				    }

				    public init(partBuilder: @escaping (SafeDIScope_Host_part.Outer) -> Instantiator<Panel>.SendableSeamBuilder<SafeDIScope_Host_part.Inner>) {
				        let __safeDI_partBuilder = partBuilder
				        let analytics = Analytics()
				        let __safeDI_partBuilder_Inner = __safeDI_partBuilder(SafeDIScope_Host_part.Outer(analytics: analytics))
				        let part = SendableInstantiator<Panel> {
				            __safeDI_partBuilder_Inner(SafeDIScope_Host_part.Inner(), $0)
				        }
				        self.init(analytics: analytics, part: part)
				    }
				}
				"""
			case .erasedInstantiator:
				"""
				extension Host {
				    public struct SafeDIScope_Host_part {
				        public let analytics: Analytics
				    }

				    public init(partBuilder: @escaping (SafeDIScope_Host_part, String) -> AnyGadget) {
				        let __safeDI_partBuilder = partBuilder
				        let analytics = Analytics()
				        func __safeDI_part(__safeDI_forwarded: String) -> AnyGadget {
				            __safeDI_partBuilder(SafeDIScope_Host_part(analytics: analytics), __safeDI_forwarded)
				        }
				        let part = ErasedInstantiator<String, AnyGadget>(__safeDI_part)
				        self.init(analytics: analytics, part: part)
				    }
				}
				"""
			case .sendableErasedInstantiator:
				"""
				extension Host {
				    public enum SafeDIScope_Host_part {
				        public struct Outer {
				            public let analytics: Analytics
				        }

				        public struct Inner {}
				    }

				    public init(partBuilder: @escaping (SafeDIScope_Host_part.Outer) -> @Sendable (SafeDIScope_Host_part.Inner, String) -> AnyGadget) {
				        let __safeDI_partBuilder = partBuilder
				        let analytics = Analytics()
				        let __safeDI_partBuilder_Inner = __safeDI_partBuilder(SafeDIScope_Host_part.Outer(analytics: analytics))
				        @Sendable func __safeDI_part(__safeDI_forwarded: String) -> AnyGadget {
				            __safeDI_partBuilder_Inner(SafeDIScope_Host_part.Inner(), __safeDI_forwarded)
				        }
				        let part = SendableErasedInstantiator<String, AnyGadget>(__safeDI_part)
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
				            func __safeDI_partBuilder(_ scope: Host.SafeDIScope_Host_part) -> any Gadget {
				                let analytics = scope.analytics
				                func __safeDI_part() -> DefaultGadget {
				                    DefaultGadget(analytics: analytics)
				                }
				                return __safeDI_part()
				            }
				"""
			case .sendableLazilyInstantiated:
				"""
				            func __safeDI_partBuilder(_ scope: Host.SafeDIScope_Host_part.Outer) -> @Sendable (Host.SafeDIScope_Host_part.Inner) -> any Gadget {
				                let analytics = scope.analytics
				                @Sendable func __safeDI_partBuilder_Inner(_ scope: Host.SafeDIScope_Host_part.Inner) -> any Gadget {
				                    @Sendable func __safeDI_part() -> DefaultGadget {
				                        DefaultGadget(analytics: analytics)
				                    }
				                    return __safeDI_part()
				                }
				                return __safeDI_partBuilder_Inner
				            }
				"""
			case .instantiator:
				"""
				            func __safeDI_partBuilder(_ scope: Host.SafeDIScope_Host_part, _ __safeDI_forwarded: Panel.ForwardedProperties) -> Panel {
				                let analytics = scope.analytics
				                func __safeDI_part(name: String) -> DefaultPanel {
				                    DefaultPanel(name: name, analytics: analytics)
				                }
				                return __safeDI_part(name: __safeDI_forwarded)
				            }
				"""
			case .sendableInstantiator:
				"""
				            func __safeDI_partBuilder(_ scope: Host.SafeDIScope_Host_part.Outer) -> Instantiator<Panel>.SendableSeamBuilder<Host.SafeDIScope_Host_part.Inner> {
				                let analytics = scope.analytics
				                @Sendable func __safeDI_partBuilder_Inner(_ scope: Host.SafeDIScope_Host_part.Inner, _ __safeDI_forwarded: Panel.ForwardedProperties) -> Panel {
				                    @Sendable func __safeDI_part(name: String) -> DefaultPanel {
				                        DefaultPanel(name: name, analytics: analytics)
				                    }
				                    return __safeDI_part(name: __safeDI_forwarded)
				                }
				                return __safeDI_partBuilder_Inner
				            }
				"""
			case .erasedInstantiator:
				"""
				            func __safeDI_partBuilder(_ scope: Host.SafeDIScope_Host_part, _ __safeDI_forwarded: String) -> AnyGadget {
				                let analytics = scope.analytics
				                func __safeDI_part(name: String) -> NamedGadget {
				                    NamedGadget(name: name, analytics: analytics)
				                }
				                return AnyGadget(__safeDI_part(name: __safeDI_forwarded))
				            }
				"""
			case .sendableErasedInstantiator:
				"""
				            func __safeDI_partBuilder(_ scope: Host.SafeDIScope_Host_part.Outer) -> @Sendable (Host.SafeDIScope_Host_part.Inner, String) -> AnyGadget {
				                let analytics = scope.analytics
				                @Sendable func __safeDI_partBuilder_Inner(_ scope: Host.SafeDIScope_Host_part.Inner, _ __safeDI_forwarded: String) -> AnyGadget {
				                    @Sendable func __safeDI_part(name: String) -> NamedGadget {
				                        NamedGadget(name: name, analytics: analytics)
				                    }
				                    return AnyGadget(__safeDI_part(name: __safeDI_forwarded))
				                }
				                return __safeDI_partBuilder_Inner
				            }
				"""
			}
		}
	}

	@Test(arguments: WrapperKind.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsWrapperAroundBuilderThatReturnsPlainValue_whenHoleIsHeldInWrapper(wrapper: WrapperKind) async throws {
		let feature = Self.featureFiles(hostDeclarations: ["@Instantiated let analytics: Analytics", wrapper.declaration])
		let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: Self.fulfillers + [Self.root])
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
		        func __safeDI_host() -> Host {
		            _ = Host.\(wrapper.guardName).self\(seamCallComment(seam: "Host"))
		\(wrapper.fillCode)
		            return Host(partBuilder: __safeDI_partBuilder)
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""]))
		try expectEveryModuleCompiled(output)
		try await expectValuesEqualVisibleBuild(
			output,
			modules: modules,
			visibleModules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature + Self.fulfillers, app: [Self.root]),
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
		let guardName = "__safeDI_Host_69AD7BD4575A9B42"
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + """
		extension Host {
		    public struct SafeDIScope_Host_part {
		        public let analytics: Analytics
		    }

		    public init(partBuilder: @escaping (SafeDIScope_Host_part, nonisolated(nonsending) @escaping () async -> Void) -> any Gadget) {
		        let __safeDI_partBuilder = partBuilder
		        let analytics = Analytics()
		        func __safeDI_part(__safeDI_forwarded: nonisolated(nonsending) @escaping () async -> Void) -> any Gadget {
		            __safeDI_partBuilder(SafeDIScope_Host_part(analytics: analytics), __safeDI_forwarded)
		        }
		        let part: ErasedInstantiator<nonisolated(nonsending) () async -> Void, any Gadget> = ErasedInstantiator(__safeDI_part)
		        self.init(analytics: analytics, part: part)
		    }
		}

		extension Host {
		    public enum \(guardName) {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, SafeDIToolSeamBuilderParameterTests.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.\(guardName).self\(seamCallComment(seam: "Host"))
		            func __safeDI_partBuilder(_ scope: Host.SafeDIScope_Host_part, _ __safeDI_forwarded: nonisolated(nonsending) @escaping () async -> Void) -> any Gadget {
		                let analytics = scope.analytics
		                func __safeDI_part(run: nonisolated(nonsending) @escaping () async -> Void) -> ActionGadget {
		                    ActionGadget(run: run, analytics: analytics)
		                }
		                return __safeDI_part(run: __safeDI_forwarded)
		            }
		            return Host(partBuilder: __safeDI_partBuilder)
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""]))
		try expectEveryModuleCompiled(output)
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
		    public struct SafeDIScope_Host_erased {
		        public let analytics: Analytics
		    }

		    public struct SafeDIScope_Host_held {
		        public let analytics: Analytics
		        public let erased: ErasedInstantiator<(count: Int, name: String), any Gadget>
		    }

		    public init(erasedBuilder: @escaping (SafeDIScope_Host_erased, (count: Int, name: String)) -> any Gadget, heldBuilder: @escaping Instantiator<PairPanel>.SeamBuilder<SafeDIScope_Host_held>) {
		        let __safeDI_erasedBuilder = erasedBuilder
		        let __safeDI_heldBuilder = heldBuilder
		        let analytics = Analytics()
		        func __safeDI_erased(__safeDI_forwarded: (count: Int, name: String)) -> any Gadget {
		            __safeDI_erasedBuilder(SafeDIScope_Host_erased(analytics: analytics), __safeDI_forwarded)
		        }
		        let erased = ErasedInstantiator<(count: Int, name: String), any Gadget>(__safeDI_erased)
		        let held = Instantiator<PairPanel> {
		            __safeDI_heldBuilder(SafeDIScope_Host_held(analytics: analytics, erased: erased), $0)
		        }
		        self.init(analytics: analytics, erased: erased, held: held)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_056CB6B1CFACC9AC {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, SafeDIToolSeamBuilderParameterTests.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_056CB6B1CFACC9AC.self\(seamCallComment(seam: "Host"))
		            func __safeDI_erasedBuilder(_ scope: Host.SafeDIScope_Host_erased, _ __safeDI_forwarded: (count: Int, name: String)) -> any Gadget {
		                let analytics = scope.analytics
		                func __safeDI_erased(count: Int, name: String) -> PairGadget {
		                    PairGadget(count: count, name: name, analytics: analytics)
		                }
		                return __safeDI_erased(count: __safeDI_forwarded.count, name: __safeDI_forwarded.name)
		            }
		            func __safeDI_heldBuilder(_ scope: Host.SafeDIScope_Host_held, _ __safeDI_forwarded: PairPanel.ForwardedProperties) -> PairPanel {
		                let analytics = scope.analytics
		                func __safeDI_held(count: Int, name: String) -> DefaultPairPanel {
		                    DefaultPairPanel(count: count, name: name, analytics: analytics)
		                }
		                return __safeDI_held(count: __safeDI_forwarded.count, name: __safeDI_forwarded.name)
		            }
		            return Host(erasedBuilder: __safeDI_erasedBuilder, heldBuilder: __safeDI_heldBuilder)
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""]))
		try expectEveryModuleCompiled(output)
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
		let guardName = "__safeDI_Host_5204B43135531518"
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + """
		extension Host {
		    public struct SafeDIScope_Host_part {
		        public let analytics: Analytics
		    }

		    public init(partBuilder: @escaping (SafeDIScope_Host_part) -> any Gadget) {
		        let __safeDI_partBuilder = partBuilder
		        let analytics = Analytics()
		        func __safeDI_part() -> any Gadget {
		            __safeDI_partBuilder(SafeDIScope_Host_part(analytics: analytics))
		        }
		        let part = ErasedInstantiator<\(spelling), any Gadget>(__safeDI_part)
		        self.init(analytics: analytics, part: part)
		    }
		}

		extension Host {
		    public enum \(guardName) {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, SafeDIToolSeamBuilderParameterTests.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.\(guardName).self\(seamCallComment(seam: "Host"))
		            func __safeDI_partBuilder(_ scope: Host.SafeDIScope_Host_part) -> any Gadget {
		                let analytics = scope.analytics
		                func __safeDI_part() -> DefaultGadget {
		                    DefaultGadget(analytics: analytics)
		                }
		                return __safeDI_part()
		            }
		            return Host(partBuilder: __safeDI_partBuilder)
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""]))
		try expectEveryModuleCompiled(output)
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
		    public struct SafeDIScope_Host_held {
		        public let analytics: Analytics
		    }

		    public init(heldBuilder: @escaping Instantiator<EmptyPanel>.SeamBuilder<SafeDIScope_Host_held>) {
		        let __safeDI_heldBuilder = heldBuilder
		        let analytics = Analytics()
		        let held = Instantiator<EmptyPanel> {
		            __safeDI_heldBuilder(SafeDIScope_Host_held(analytics: analytics), $0)
		        }
		        self.init(analytics: analytics, held: held)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_66B4A294E25BEE8E {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, SafeDIToolSeamBuilderParameterTests.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_66B4A294E25BEE8E.self\(seamCallComment(seam: "Host"))
		            func __safeDI_heldBuilder(_ scope: Host.SafeDIScope_Host_held, _ __safeDI_forwarded: EmptyPanel.ForwardedProperties) -> EmptyPanel {
		                let analytics = scope.analytics
		                func __safeDI_held() -> DefaultEmptyPanel {
		                    DefaultEmptyPanel(analytics: analytics)
		                }
		                return __safeDI_held()
		            }
		            return Host(heldBuilder: __safeDI_heldBuilder)
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""]))
		try expectEveryModuleCompiled(output)
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
		            _ = Host.__safeDI_Host_38709253223EA9EF.self\(seamCallComment(seam: "Host"))
		            func __safeDI_forwardedBuilder(_ scope: Host.SafeDIScope_Host_forwarded, _ __safeDI_forwarded_: Panel.ForwardedProperties) -> Panel {
		                let analytics = scope.analytics
		                func __safeDI_forwarded(name: String) -> DefaultPanel {
		                    DefaultPanel(name: name, analytics: analytics)
		                }
		                return __safeDI_forwarded(name: __safeDI_forwarded_)
		            }
		            return Host(forwardedBuilder: __safeDI_forwardedBuilder)
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""]))
		try expectEveryModuleCompiled(output)
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
		let guardName = isSendable ? "__safeDI_Host_128B4EB0210AFB80" : "__safeDI_Host_166739A5D2E808B3"
		let fill = if isSendable {
			"""
			            func __safeDI_againBuilder(_ scope: Host.SafeDIScope_Host_again.Outer) -> @Sendable (Host.SafeDIScope_Host_again.Inner, String) -> any Gadget {
			                @Sendable func __safeDI_againBuilder_Inner(_ scope: Host.SafeDIScope_Host_again.Inner, _ __safeDI_forwarded: String) -> any Gadget {
			                    @Sendable func __safeDI_again(name: String) -> LoopingGadget {
			                        let again = SendableErasedInstantiator<String, any Gadget> {
			                            __safeDI_again(name: $0)
			                        }
			                        return LoopingGadget(name: name, again: again)
			                    }
			                    return __safeDI_again(name: __safeDI_forwarded)
			                }
			                return __safeDI_againBuilder_Inner
			            }
			"""
		} else {
			"""
			            func __safeDI_againBuilder(_ scope: Host.SafeDIScope_Host_again, _ __safeDI_forwarded: String) -> any Gadget {
			                func __safeDI_again(name: String) -> LoopingGadget {
			                    let again = ErasedInstantiator<String, any Gadget> {
			                        __safeDI_again(name: $0)
			                    }
			                    return LoopingGadget(name: name, again: again)
			                }
			                return __safeDI_again(name: __safeDI_forwarded)
			            }
			"""
		}
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, SafeDIToolSeamBuilderParameterTests.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.\(guardName).self\(seamCallComment(seam: "Host"))
		\(fill)
		            return Host(againBuilder: __safeDI_againBuilder)
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""]))
		try expectEveryModuleCompiled(output)
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
	mutating func generate_callsLastStageWithForwardedValue_whenPlainWrapperHoleIsInsideSendableFunction() async throws {
		let feature = Self.featureFiles(hostDeclarations: [
			"@Instantiated let analytics: Analytics",
			"@Instantiated let ownerBuilder: SendableInstantiator<Owner>",
		], otherFiles: [
			seamFixtureType(named: "Owner", declarations: ["@Instantiated let held: Instantiator<Panel>"], conformances: ", @unchecked Sendable"),
		])
		let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: Self.fulfillers + [Self.root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + """
		extension Host {
		    public enum SafeDIScope_Owner_held {
		        public struct Outer {
		            public let analytics: Analytics
		        }

		        public struct Inner {}
		    }

		    public init(heldBuilder: @escaping (SafeDIScope_Owner_held.Outer) -> Instantiator<Panel>.SendableSeamBuilder<SafeDIScope_Owner_held.Inner>) {
		        let __safeDI_heldBuilder = heldBuilder
		        let analytics = Analytics()
		        let __safeDI_heldBuilder_Inner = __safeDI_heldBuilder(SafeDIScope_Owner_held.Outer(analytics: analytics))
		        @Sendable func __safeDI_ownerBuilder() -> Owner {
		            let held = Instantiator<Panel> {
		                __safeDI_heldBuilder_Inner(SafeDIScope_Owner_held.Inner(), $0)
		            }
		            return Owner(held: held)
		        }
		        let ownerBuilder = SendableInstantiator<Owner>(__safeDI_ownerBuilder)
		        self.init(analytics: analytics, ownerBuilder: ownerBuilder)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_C122002960AC2C21 {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, SafeDIToolSeamBuilderParameterTests.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_C122002960AC2C21.self\(seamCallComment(seam: "Host"))
		            func __safeDI_heldBuilder(_ scope: Host.SafeDIScope_Owner_held.Outer) -> Instantiator<Panel>.SendableSeamBuilder<Host.SafeDIScope_Owner_held.Inner> {
		                let analytics = scope.analytics
		                @Sendable func __safeDI_heldBuilder_Inner(_ scope: Host.SafeDIScope_Owner_held.Inner, _ __safeDI_forwarded: Panel.ForwardedProperties) -> Panel {
		                    func __safeDI_held(name: String) -> DefaultPanel {
		                        DefaultPanel(name: name, analytics: analytics)
		                    }
		                    return __safeDI_held(name: __safeDI_forwarded)
		                }
		                return __safeDI_heldBuilder_Inner
		            }
		            return Host(heldBuilder: __safeDI_heldBuilder)
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""]))
		try expectEveryModuleCompiled(output)
		try await expectValuesEqualVisibleBuild(
			output,
			modules: modules,
			visibleModules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature + Self.fulfillers, app: [Self.root]),
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe(#"Root().host.ownerBuilder.instantiate().held.instantiate("name")"#)],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_addsStageForWrappersOwnFunction_whenSendableWrapperHoleIsInsideSendableFunction() async throws {
		let feature = Self.featureFiles(hostDeclarations: [
			"@Instantiated let analytics: Analytics",
			"@Instantiated let ownerBuilder: SendableInstantiator<Owner>",
		], otherFiles: [
			seamFixtureType(named: "Tally", isFinalClass: true, declarations: [], conformances: ", Sendable"),
			seamFixtureType(named: "Owner", declarations: ["@Instantiated let tally: Tally", "@Instantiated let held: SendableInstantiator<Panel>"], conformances: ", Sendable"),
		])
		let fulfillers = [
			"""
			@Instantiable(fulfillingAdditionalTypes: [Panel.self], conformsElsewhere: true)
			public final class DefaultPanel: Panel, @unchecked Sendable {
			    public init(name: String, analytics: Analytics, tally: Tally) {
			        self.name = name
			        self.analytics = analytics
			        self.tally = tally
			        super.init(title: name)
			    }

			    @Forwarded let name: String
			    @Received let analytics: Analytics
			    @Received let tally: Tally
			}
			""",
		]
		let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: fulfillers + [Self.root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + """
		extension Host {
		    public enum SafeDIScope_Owner_held {
		        public struct Outer {
		            public let analytics: Analytics
		        }

		        public struct Inner {
		            public let tally: Tally
		        }

		        public struct Inner2 {}
		    }

		    public init(heldBuilder: @escaping (SafeDIScope_Owner_held.Outer) -> @Sendable (SafeDIScope_Owner_held.Inner) -> Instantiator<Panel>.SendableSeamBuilder<SafeDIScope_Owner_held.Inner2>) {
		        let __safeDI_heldBuilder = heldBuilder
		        let analytics = Analytics()
		        let __safeDI_heldBuilder_Inner = __safeDI_heldBuilder(SafeDIScope_Owner_held.Outer(analytics: analytics))
		        @Sendable func __safeDI_ownerBuilder() -> Owner {
		            let tally = Tally()
		            let __safeDI_heldBuilder_Inner2 = __safeDI_heldBuilder_Inner(SafeDIScope_Owner_held.Inner(tally: tally))
		            let held = SendableInstantiator<Panel> {
		                __safeDI_heldBuilder_Inner2(SafeDIScope_Owner_held.Inner2(), $0)
		            }
		            return Owner(tally: tally, held: held)
		        }
		        let ownerBuilder = SendableInstantiator<Owner>(__safeDI_ownerBuilder)
		        self.init(analytics: analytics, ownerBuilder: ownerBuilder)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_3F90F20F4B40FD1F {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, SafeDIToolSeamBuilderParameterTests.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_3F90F20F4B40FD1F.self\(seamCallComment(seam: "Host"))
		            func __safeDI_heldBuilder(_ scope: Host.SafeDIScope_Owner_held.Outer) -> @Sendable (Host.SafeDIScope_Owner_held.Inner) -> Instantiator<Panel>.SendableSeamBuilder<Host.SafeDIScope_Owner_held.Inner2> {
		                let analytics = scope.analytics
		                @Sendable func __safeDI_heldBuilder_Inner(_ scope: Host.SafeDIScope_Owner_held.Inner) -> Instantiator<Panel>.SendableSeamBuilder<Host.SafeDIScope_Owner_held.Inner2> {
		                    let tally = scope.tally
		                    @Sendable func __safeDI_heldBuilder_Inner2(_ scope: Host.SafeDIScope_Owner_held.Inner2, _ __safeDI_forwarded: Panel.ForwardedProperties) -> Panel {
		                        @Sendable func __safeDI_held(name: String) -> DefaultPanel {
		                            DefaultPanel(name: name, analytics: analytics, tally: tally)
		                        }
		                        return __safeDI_held(name: __safeDI_forwarded)
		                    }
		                    return __safeDI_heldBuilder_Inner2
		                }
		                return __safeDI_heldBuilder_Inner
		            }
		            return Host(heldBuilder: __safeDI_heldBuilder)
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""]))
		try expectEveryModuleCompiled(output)
		try await expectValuesEqualVisibleBuild(
			output,
			modules: modules,
			visibleModules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature + fulfillers, app: [Self.root]),
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
		    public struct SafeDIScope_Inner_part {}

		    public init(partBuilder: @escaping Instantiator<Panel>.SeamBuilder<SafeDIScope_Inner_part>) {
		        let __safeDI_partBuilder = partBuilder
		        let part = Instantiator<Panel> {
		            __safeDI_partBuilder(SafeDIScope_Inner_part(), $0)
		        }
		        self.init(part: part)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_C60F145FCBDAF73F {}
		}

		extension Outer {
		    public init(partBuilder: @escaping Instantiator<Panel>.SeamBuilder<Inner.SafeDIScope_Inner_part>) {
		        let __safeDI_partBuilder = partBuilder
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_C60F145FCBDAF73F.self
		            return Inner(partBuilder: __safeDI_partBuilder)
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(inner: inner)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_C60F145FCBDAF73F {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, SafeDIToolSeamBuilderParameterTests.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_C60F145FCBDAF73F.self\(seamCallComment(seam: "Outer"))
		            func __safeDI_partBuilder(_ scope: Inner.SafeDIScope_Inner_part, _ __safeDI_forwarded: Panel.ForwardedProperties) -> Panel {
		                func __safeDI_part(name: String) -> DefaultPanel {
		                    DefaultPanel(name: name)
		                }
		                return __safeDI_part(name: __safeDI_forwarded)
		            }
		            return Outer(partBuilder: __safeDI_partBuilder)
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(outer: outer)
		    }
		}
		"""]))
		try expectEveryModuleCompiled(output)
		try await expectValuesEqualVisibleBuild(
			output,
			modules: modules,
			visibleModules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature + fulfillers, app: [root]),
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe(#"Root().outer.inner.part.instantiate("name")"#)],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_stagesPlaceInsideFill_whenSeamFillsInnerSeamsHoleHeldInSendableWrapper() async throws {
		// `Host` fills `Inner`'s hole, held in a `Sendable` wrapper, with `DefaultWidget`, whose own hole `Host` passes up: the
		// fill's last stage and the wrapper's builder function each start a stage of that place's builder.
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
		    public enum SafeDIScope_DefaultWidget_gadget {
		        public struct Outer {}

		        public struct Inner {}

		        public struct Inner2 {}
		    }

		    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module's SafeDI dependencies.
		    public init(gadgetBuilder: @escaping (SafeDIScope_DefaultWidget_gadget.Outer) -> @Sendable (SafeDIScope_DefaultWidget_gadget.Inner) -> @Sendable (SafeDIScope_DefaultWidget_gadget.Inner2) -> any Gadget) {
		        let __safeDI_gadgetBuilder = gadgetBuilder
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_9755C944EE7EEB47.self\(seamCallComment(seam: "Inner"))
		            func __safeDI_widgetBuilder(_ scope: Inner.SafeDIScope_Inner_widget.Outer) -> @Sendable (Inner.SafeDIScope_Inner_widget.Inner) -> any Widget {
		                let __safeDI_gadgetBuilder_Inner = __safeDI_gadgetBuilder(SafeDIScope_DefaultWidget_gadget.Outer())
		                @Sendable func __safeDI_widgetBuilder_Inner(_ scope: Inner.SafeDIScope_Inner_widget.Inner) -> any Widget {
		                    let __safeDI_gadgetBuilder_Inner2 = __safeDI_gadgetBuilder_Inner(SafeDIScope_DefaultWidget_gadget.Inner())
		                    @Sendable func __safeDI_widget() -> DefaultWidget {
		                        let gadget: any Gadget = __safeDI_gadgetBuilder_Inner2(SafeDIScope_DefaultWidget_gadget.Inner2())
		                        return DefaultWidget(gadget: gadget)
		                    }
		                    return __safeDI_widget()
		                }
		                return __safeDI_widgetBuilder_Inner
		            }
		            return Inner(widgetBuilder: __safeDI_widgetBuilder)
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(inner: inner)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_5F279E100A486146 {}
		}
		"""]))
		try expectEveryModuleCompiled(output)
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
		let guardName = access == "public" ? "__safeDI_Host_A69A85FB94534A2C" : "__safeDI_Host_19252FA46311315C"
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + """
		extension Host {
		    public struct SafeDIScope_Host_part {
		        \(access) let analytics: Analytics
		    }

		    \(access) init(partBuilder: @escaping (SafeDIScope_Host_part, Label) -> any Gadget) {
		        let __safeDI_partBuilder = partBuilder
		        let analytics = Analytics()
		        func __safeDI_part(__safeDI_forwarded: Label) -> any Gadget {
		            __safeDI_partBuilder(SafeDIScope_Host_part(analytics: analytics), __safeDI_forwarded)
		        }
		        let part = ErasedInstantiator<Label, any Gadget>(__safeDI_part)
		        self.init(analytics: analytics, part: part)
		    }
		}

		extension Host {
		    public enum \(guardName) {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, SafeDIToolSeamBuilderParameterTests.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.\(guardName).self\(seamCallComment(seam: "Host"))
		            func __safeDI_partBuilder(_ scope: Host.SafeDIScope_Host_part, _ __safeDI_forwarded: Label) -> any Gadget {
		                let analytics = scope.analytics
		                func __safeDI_part(label: Label) -> LabeledGadget {
		                    LabeledGadget(label: label, analytics: analytics)
		                }
		                return __safeDI_part(label: __safeDI_forwarded)
		            }
		            return Host(partBuilder: __safeDI_partBuilder)
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""]))
		try expectEveryModuleCompiled(output)
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
		        heldBuilder: { _, title in Panel(title: title) },
		        lazyBuilder: { _ in PlainGadget() },
		        sendableHeldBuilder: { _ in { _, title in Panel(title: title) } }
		    )
		}
		"""
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature),
				ModuleFixture(name: "App", packageName: "Other", swiftFileContentByFilePath: ["Caller.swift": caller], dependencies: ["Feature"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		try expectEveryModuleCompiled(output)
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
		    public struct SafeDIScope_Middle_again {
		        public let beneath: Beneath
		    }

		    public init(againBuilder: @escaping (SafeDIScope_Middle_again) -> any Gadget) {
		        let __safeDI_againBuilder = againBuilder
		        func __safeDI_again() -> Middle {
		            func __safeDI_beneath() -> Beneath {
		                let again = Instantiator<Middle>(__safeDI_again)
		                return Beneath(again: again)
		            }
		            let beneath: Beneath = __safeDI_beneath()
		            func __safeDI_again_Gadget() -> any Gadget {
		                __safeDI_againBuilder(SafeDIScope_Middle_again(beneath: beneath))
		            }
		            let again = LazilyInstantiated<any Gadget>(__safeDI_again_Gadget)
		            return Middle(again: again, beneath: beneath)
		        }
		        let again = Instantiator<Middle>(__safeDI_again)
		        self.init(again: again)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_6E3BEED7B33B7C0D {}
		}
		"""])
		try expectEveryModuleCompiled(output)
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
			    public enum SafeDIMockScope_Service_part {
			        public struct Outer {
			            public let analytics: Analytics
			        }

			        public struct Inner {}
			    }

			    /// Overrides for the mock dependency tree.
			    public struct SafeDIOverrides {
			        public init(
			            analytics: (() -> Analytics)? = nil
			        ) {
			            self.analytics = analytics
			        }

			        public let analytics: (() -> Analytics)?
			    }

			    public static func mock(
			        partBuilder: @escaping (Service.SafeDIMockScope_Service_part.Outer) -> Instantiator<Panel>.SendableSeamBuilder<Service.SafeDIMockScope_Service_part.Inner>,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Service {
			        let __safeDI_partBuilder = partBuilder
			        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
			        let __safeDI_partBuilder_Inner = __safeDI_partBuilder(SafeDIMockScope_Service_part.Outer(analytics: analytics))
			        let part = SendableInstantiator<Panel> {
			            __safeDI_partBuilder_Inner(SafeDIMockScope_Service_part.Inner(), $0)
			        }
			        return Service(analytics: analytics, part: part)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_mock_2FE820C28F9E4089 {}
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
		    public struct SafeDIMockScope_Middle_again {
		        public let beneath: Beneath
		    }

		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init(
		            again: __safeDI_Middle_MockConfiguration = .init()
		        ) {
		            self.again = again
		        }

		        public let again: __safeDI_Middle_MockConfiguration
		    }

		    public static func mock(
		        againBuilder: @escaping (Service.SafeDIMockScope_Middle_again) -> any Gadget,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Service {
		        let __safeDI_againBuilder = againBuilder
		        func __safeDI_again() -> Middle {
		            func __safeDI_beneath() -> Beneath {
		                let again = Instantiator<Middle>(__safeDI_again)
		                return Beneath.__safeDI_init(again: again, safeDIBuilder: nil)
		            }
		            let beneath: Beneath = __safeDI_beneath()
		            func __safeDI_again_Gadget() -> any Gadget {
		                __safeDI_againBuilder(SafeDIMockScope_Middle_again(beneath: beneath))
		            }
		            let again = LazilyInstantiated<any Gadget>(__safeDI_again_Gadget)
		            return Middle.__safeDI_init(again: again, beneath: beneath, safeDIBuilder: safeDIOverrides.again.safeDIBuilder)
		        }
		        let again = Instantiator<Middle>(__safeDI_again)
		        return Service(again: again)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_mock_4E24CBC42CC24810 {}
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
		let guardName = "__safeDI_Host_24EDA2047005C6EB"
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + """
		extension Host {
		    public struct SafeDIScope_Host_part {
		        public let analytics: Analytics
		    }

		    public init(partBuilder: @escaping Instantiator<ActionPanel>.SeamBuilder<SafeDIScope_Host_part>) {
		        let __safeDI_partBuilder = partBuilder
		        let analytics = Analytics()
		        let part = Instantiator<ActionPanel> {
		            __safeDI_partBuilder(SafeDIScope_Host_part(analytics: analytics), $0)
		        }
		        self.init(analytics: analytics, part: part)
		    }
		}

		extension Host {
		    public enum \(guardName) {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, SafeDIToolSeamBuilderParameterTests.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.\(guardName).self\(seamCallComment(seam: "Host"))
		            func __safeDI_partBuilder(_ scope: Host.SafeDIScope_Host_part, _ __safeDI_forwarded: @escaping ActionPanel.ForwardedProperties) -> ActionPanel {
		                let analytics = scope.analytics
		                func __safeDI_part(forwardedAction: @escaping () -> Void) -> DefaultActionPanel {
		                    DefaultActionPanel(forwardedAction: forwardedAction, analytics: analytics)
		                }
		                return __safeDI_part(forwardedAction: __safeDI_forwarded)
		            }
		            return Host(partBuilder: __safeDI_partBuilder)
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""]))
		try expectEveryModuleCompiled(output)
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
			"@Instantiated let analytics: Analytics",
			"@Instantiated let part: SendableInstantiator<ActionPanel>",
		], otherFiles: [Self.actionPanel(forwarding: "@Sendable () -> Void")])
		let fulfillers = [Self.defaultActionPanel(forwarding: "@Sendable () -> Void")]
		let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: fulfillers + [Self.root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		let guardName = "__safeDI_Host_1F8DE7327D10AA4F"
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + """
		extension Host {
		    public enum SafeDIScope_Host_part {
		        public struct Outer {
		            public let analytics: Analytics
		        }

		        public struct Inner {}
		    }

		    public init(partBuilder: @escaping (SafeDIScope_Host_part.Outer) -> Instantiator<ActionPanel>.SendableSeamBuilder<SafeDIScope_Host_part.Inner>) {
		        let __safeDI_partBuilder = partBuilder
		        let analytics = Analytics()
		        let __safeDI_partBuilder_Inner = __safeDI_partBuilder(SafeDIScope_Host_part.Outer(analytics: analytics))
		        let part = SendableInstantiator<ActionPanel> {
		            __safeDI_partBuilder_Inner(SafeDIScope_Host_part.Inner(), $0)
		        }
		        self.init(analytics: analytics, part: part)
		    }
		}

		extension Host {
		    public enum \(guardName) {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, SafeDIToolSeamBuilderParameterTests.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.\(guardName).self\(seamCallComment(seam: "Host"))
		            func __safeDI_partBuilder(_ scope: Host.SafeDIScope_Host_part.Outer) -> Instantiator<ActionPanel>.SendableSeamBuilder<Host.SafeDIScope_Host_part.Inner> {
		                let analytics = scope.analytics
		                @Sendable func __safeDI_partBuilder_Inner(_ scope: Host.SafeDIScope_Host_part.Inner, _ __safeDI_forwarded: @escaping ActionPanel.ForwardedProperties) -> ActionPanel {
		                    @Sendable func __safeDI_part(forwardedAction: @escaping @Sendable () -> Void) -> DefaultActionPanel {
		                        DefaultActionPanel(forwardedAction: forwardedAction, analytics: analytics)
		                    }
		                    return __safeDI_part(forwardedAction: __safeDI_forwarded)
		                }
		                return __safeDI_partBuilder_Inner
		            }
		            return Host(partBuilder: __safeDI_partBuilder)
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""]))
		try expectEveryModuleCompiled(output)
		try await expectValuesEqualVisibleBuild(
			output,
			modules: modules,
			visibleModules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature + fulfillers, app: [Self.root]),
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().host.part.instantiate({})")],
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
		        heldBuilder: { _, action in ActionPanel(action: action) },
		        sendableHeldBuilder: { _ in { _, action in ActionPanel(action: action) } }
		    )
		}
		"""
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature),
				ModuleFixture(name: "App", packageName: "Other", swiftFileContentByFilePath: ["Caller.swift": caller], dependencies: ["Feature"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesEscapingForwardedFunctionToLastStage_whenPlainInstantiatorHoleIsInsideSendableFunction() async throws {
		let feature = Self.featureFiles(hostDeclarations: [
			"@Instantiated let analytics: Analytics",
			"@Instantiated let ownerBuilder: SendableInstantiator<Owner>",
		], otherFiles: [
			Self.actionPanel(forwarding: "() -> Void"),
			seamFixtureType(named: "Owner", declarations: ["@Instantiated let held: Instantiator<ActionPanel>"], conformances: ", @unchecked Sendable"),
		])
		let fulfillers = [Self.defaultActionPanel(forwarding: "() -> Void")]
		let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: fulfillers + [Self.root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		try expectEveryModuleCompiled(output)
		try await expectValuesEqualVisibleBuild(
			output,
			modules: modules,
			visibleModules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature + fulfillers, app: [Self.root]),
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
		try expectEveryModuleCompiled(output)
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
			    public struct SafeDIMockScope_Service_part {}

			    public static func mock(
			        partBuilder: @escaping Instantiator<ActionPanel>.SeamBuilder<Service.SafeDIMockScope_Service_part>
			    ) -> Service {
			        let __safeDI_partBuilder = partBuilder
			        let part = Instantiator<ActionPanel> {
			            __safeDI_partBuilder(SafeDIMockScope_Service_part(), $0)
			        }
			        return Service(part: part)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_mock_A05841FE97D6B5D6 {}
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
		let filling = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature),
				ModuleFixture(name: "App", packageName: "Other", swiftFileContent: ["import Feature\n\n" + Self.defaultActionPanel(forwarding: "() -> Void", receivesAnalytics: false), "import Feature\n\n" + consumer], dependencies: ["Feature"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		try expectEveryModuleCompiled(filling)
		// One that does not passes the builder up, `@Sendable` when a `@Sendable` builder function makes the call.
		let passingUp = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature),
				ModuleFixture(name: "App", packageName: "Other", swiftFileContent: ["import Feature\n\n" + consumer], dependencies: ["Feature"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		try expectEveryModuleCompiled(passingUp)
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
		let guardName = "__safeDI_Host_CDC16861A247125A"
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, SafeDIToolSeamBuilderParameterTests.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.\(guardName).self\(seamCallComment(seam: "Host"))
		            func __safeDI_partBuilder(_ scope: Host.SafeDIScope_Host_part) -> any Gadget {
		                func __safeDI_part() -> DefaultGadget {
		                    let kid = Kid(part: nil)
		                    return DefaultGadget(kid: kid)
		                }
		                return __safeDI_part()
		            }
		            return Host(partBuilder: __safeDI_partBuilder)
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""]))
		try expectEveryModuleCompiled(output)
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
		try expectEveryModuleCompiled(output)
		try await expectValuesEqualVisibleBuild(
			output,
			modules: modules,
			visibleModules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature + fulfillers, app: [Self.root]),
			probes: [DifferentialValueProbe("Root()")],
		)
	}

	// MARK: A stage function named like a sibling's builder function

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesBuilderApart_whenSiblingWrapperHolesBuilderFunctionWouldTakeItsStagesName() async throws {
		let feature = Self.featureFiles(hostDeclarations: [
			"@Instantiated let analytics: Analytics",
			"@Instantiated let slazy: SendableLazilyInstantiated<any Gadget>",
			"@Instantiated let slazyBuilder_Inner: LazilyInstantiated<any Gadget>",
		])
		let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: Self.fulfillers + [Self.root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		let guardName = "__safeDI_Host_50439E52EEF7BA77"
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + """
		extension Host {
		    public enum SafeDIScope_Host_slazy {
		        public struct Outer {
		            public let analytics: Analytics
		        }

		        public struct Inner {}
		    }

		    public struct SafeDIScope_Host_slazyBuilder_Inner {
		        public let analytics: Analytics
		        public let slazy: SendableLazilyInstantiated<any Gadget>
		    }

		    public init(slazyBuilder: @escaping (SafeDIScope_Host_slazy.Outer) -> @Sendable (SafeDIScope_Host_slazy.Inner) -> any Gadget, slazyBuilder_InnerBuilder: @escaping (SafeDIScope_Host_slazyBuilder_Inner) -> any Gadget) {
		        let __safeDI_slazyBuilder_ = slazyBuilder
		        let __safeDI_slazyBuilder_InnerBuilder = slazyBuilder_InnerBuilder
		        let analytics = Analytics()
		        let __safeDI_slazyBuilder__Inner = __safeDI_slazyBuilder_(SafeDIScope_Host_slazy.Outer(analytics: analytics))
		        @Sendable func __safeDI_slazy() -> any Gadget {
		            __safeDI_slazyBuilder__Inner(SafeDIScope_Host_slazy.Inner())
		        }
		        let slazy = SendableLazilyInstantiated<any Gadget>(__safeDI_slazy)
		        func __safeDI_slazyBuilder_Inner() -> any Gadget {
		            __safeDI_slazyBuilder_InnerBuilder(SafeDIScope_Host_slazyBuilder_Inner(analytics: analytics, slazy: slazy))
		        }
		        let slazyBuilder_Inner = LazilyInstantiated<any Gadget>(__safeDI_slazyBuilder_Inner)
		        self.init(analytics: analytics, slazy: slazy, slazyBuilder_Inner: slazyBuilder_Inner)
		    }
		}

		extension Host {
		    public enum \(guardName) {}
		}
		"""])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesBuilderApart_whenItsStagesNameWouldEqualAnotherBuildersInternalName() async throws {
		let feature = [
			"public protocol Gadget: Sendable {}",
			seamFixtureType(named: "Inner", declarations: ["@Instantiated let a: any Gadget"], conformances: ", @unchecked Sendable"),
			seamFixtureType(named: "X", declarations: ["@Instantiated let a: any Gadget"], conformances: ", @unchecked Sendable"),
			seamFixtureType(named: "InnerSeam", isSeam: true, declarations: ["@Instantiated let i: Inner", "@Instantiated let x: X"], conformances: ", @unchecked Sendable"),
			seamFixtureType(named: "Host", isSeam: true, declarations: ["@Instantiated let a: SendableLazilyInstantiated<any Gadget>", "@Instantiated let s: InnerSeam"], conformances: ", @unchecked Sendable"),
		]
		let fulfillers = [SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultGadget", fulfilling: "Gadget", declarations: [])]
		let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: fulfillers + [Self.root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + """
		extension Host {
		    public enum SafeDIScope_Host_a {
		        public struct Outer {
		            public let s: InnerSeam
		        }

		        public struct Inner {}
		    }

		    public init(aBuilder: @escaping (SafeDIScope_Host_a.Outer) -> @Sendable (SafeDIScope_Host_a.Inner) -> any Gadget, aBuilder_Inner: @escaping (InnerSeam.SafeDIScope_Inner_a) -> any Gadget, aBuilder_X: @escaping (InnerSeam.SafeDIScope_X_a) -> any Gadget) {
		        let __safeDI_aBuilder_ = aBuilder
		        let __safeDI_aBuilder_Inner = aBuilder_Inner
		        let __safeDI_aBuilder_X = aBuilder_X
		        func __safeDI_s() -> InnerSeam {
		            _ = InnerSeam.__safeDI_InnerSeam_D8582838F657C276.self
		            return InnerSeam(aBuilder_Inner: __safeDI_aBuilder_Inner, aBuilder_X: __safeDI_aBuilder_X)
		        }
		        let s: InnerSeam = __safeDI_s()
		        let __safeDI_aBuilder__Inner = __safeDI_aBuilder_(SafeDIScope_Host_a.Outer(s: s))
		        @Sendable func __safeDI_a() -> any Gadget {
		            __safeDI_aBuilder__Inner(SafeDIScope_Host_a.Inner())
		        }
		        let a = SendableLazilyInstantiated<any Gadget>(__safeDI_a)
		        self.init(a: a, s: s)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_D125A6654CC3822C {}
		}

		extension InnerSeam {
		    public struct SafeDIScope_Inner_a {}

		    public struct SafeDIScope_X_a {
		        public let i: Inner
		    }

		    public init(aBuilder_Inner: @escaping (SafeDIScope_Inner_a) -> any Gadget, aBuilder_X: @escaping (SafeDIScope_X_a) -> any Gadget) {
		        let __safeDI_aBuilder_Inner = aBuilder_Inner
		        let __safeDI_aBuilder_X = aBuilder_X
		        func __safeDI_i() -> Inner {
		            let a: any Gadget = __safeDI_aBuilder_Inner(SafeDIScope_Inner_a())
		            return Inner(a: a)
		        }
		        let i: Inner = __safeDI_i()
		        func __safeDI_x() -> X {
		            let a: any Gadget = __safeDI_aBuilder_X(SafeDIScope_X_a(i: i))
		            return X(a: a)
		        }
		        let x: X = __safeDI_x()
		        self.init(i: i, x: x)
		    }
		}

		extension InnerSeam {
		    public enum __safeDI_InnerSeam_D8582838F657C276 {}
		}
		"""])
		try expectEveryModuleCompiled(output)
		try await expectValuesEqualVisibleBuild(
			output,
			modules: modules,
			visibleModules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature + fulfillers, app: [Self.root]),
			probes: [DifferentialValueProbe("Root()")],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesFillApart_whenItsStageWouldEqualSiblingFillThatCallInsideItPasses() async throws {
		let feature = [
			"public protocol Gadget: Sendable {}",
			seamFixtureType(named: "Inner", declarations: ["@Instantiated let a: any Gadget"], conformances: ", @unchecked Sendable"),
			seamFixtureType(named: "X", declarations: ["@Instantiated let a: any Gadget"], conformances: ", @unchecked Sendable"),
			seamFixtureType(named: "InnerSeam", isSeam: true, declarations: ["@Instantiated let i: Inner", "@Instantiated let x: X"], conformances: ", @unchecked Sendable"),
			seamFixtureType(named: "Host", isSeam: true, declarations: ["@Instantiated let a: SendableLazilyInstantiated<any Gadget>", "@Instantiated let s: InnerSeam"], conformances: ", @unchecked Sendable"),
		]
		let fulfillers = [Self.sendableFulfillingType(named: "DefaultGadget", fulfilling: "Gadget", declarations: ["@Instantiated let hostMaker: SendableInstantiator<Host>"])]
		let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: fulfillers + [Self.root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, SafeDIToolSeamBuilderParameterTests.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_D125A6654CC3822C.self\(seamCallComment(seam: "Host"))
		            @Sendable func __safeDI_aBuilder_(_ scope: Host.SafeDIScope_Host_a.Outer) -> @Sendable (Host.SafeDIScope_Host_a.Inner) -> any Gadget {
		                @Sendable func __safeDI_aBuilder__Inner(_ scope: Host.SafeDIScope_Host_a.Inner) -> any Gadget {
		                    @Sendable func __safeDI_a() -> DefaultGadget {
		                        @Sendable func __safeDI_hostMaker() -> Host {
		                            _ = Host.__safeDI_Host_D125A6654CC3822C.self\(seamCallComment(seam: "Host"))
		                            return Host(aBuilder: __safeDI_aBuilder_, aBuilder_Inner: __safeDI_aBuilder_Inner, aBuilder_X: __safeDI_aBuilder_X)
		                        }
		                        let hostMaker = SendableInstantiator<Host>(__safeDI_hostMaker)
		                        return DefaultGadget(hostMaker: hostMaker)
		                    }
		                    return __safeDI_a()
		                }
		                return __safeDI_aBuilder__Inner
		            }
		            @Sendable func __safeDI_aBuilder_Inner(_ scope: InnerSeam.SafeDIScope_Inner_a) -> any Gadget {
		                func __safeDI_a() -> DefaultGadget {
		                    @Sendable func __safeDI_hostMaker() -> Host {
		                        _ = Host.__safeDI_Host_D125A6654CC3822C.self\(seamCallComment(seam: "Host"))
		                        return Host(aBuilder: __safeDI_aBuilder_, aBuilder_Inner: __safeDI_aBuilder_Inner, aBuilder_X: __safeDI_aBuilder_X)
		                    }
		                    let hostMaker = SendableInstantiator<Host>(__safeDI_hostMaker)
		                    return DefaultGadget(hostMaker: hostMaker)
		                }
		                let a: any Gadget = __safeDI_a()
		                return a
		            }
		            @Sendable func __safeDI_aBuilder_X(_ scope: InnerSeam.SafeDIScope_X_a) -> any Gadget {
		                func __safeDI_a() -> DefaultGadget {
		                    @Sendable func __safeDI_hostMaker() -> Host {
		                        _ = Host.__safeDI_Host_D125A6654CC3822C.self\(seamCallComment(seam: "Host"))
		                        return Host(aBuilder: __safeDI_aBuilder_, aBuilder_Inner: __safeDI_aBuilder_Inner, aBuilder_X: __safeDI_aBuilder_X)
		                    }
		                    let hostMaker = SendableInstantiator<Host>(__safeDI_hostMaker)
		                    return DefaultGadget(hostMaker: hostMaker)
		                }
		                let a: any Gadget = __safeDI_a()
		                return a
		            }
		            return Host(aBuilder: __safeDI_aBuilder_, aBuilder_Inner: __safeDI_aBuilder_Inner, aBuilder_X: __safeDI_aBuilder_X)
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""]))
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesFillApart_whenItsNameWouldEqualStageOfBuilderSeamTakes() async throws {
		let feature = [
			"public protocol P1: Sendable {}",
			"public protocol P2: Sendable {}",
			"public protocol Gadget: Sendable {}",
			seamFixtureType(named: "Inner", declarations: ["@Instantiated let a: any P1"], conformances: ", @unchecked Sendable"),
			seamFixtureType(named: "X", declarations: ["@Instantiated let a: any P2"], conformances: ", @unchecked Sendable"),
			seamFixtureType(named: "InnerSeam", isSeam: true, declarations: ["@Instantiated let i: Inner", "@Instantiated let x: X"], conformances: ", @unchecked Sendable"),
		]
		let middle = [
			Self.sendableFulfillingType(named: "P1Impl", fulfilling: "P1", declarations: ["@Instantiated let a: SendableLazilyInstantiated<any Gadget>", "@Instantiated let maker: SendableInstantiator<InnerSeam>"]),
			Self.sendableFulfillingType(named: "P2Impl", fulfilling: "P2", declarations: []),
			seamFixtureType(named: "Host", isSeam: true, declarations: ["@Instantiated let s: InnerSeam"], conformances: ", @unchecked Sendable"),
		]
		let gadgetFulfiller = Self.sendableFulfillingType(named: "DefaultGadget", fulfilling: "Gadget", declarations: [])
		func modules(middle: [String], app: [String]) -> [ModuleFixture] {
			[
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature),
				ModuleFixture(name: "Middle", packageName: "Other", swiftFileContent: middle.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
				ModuleFixture(name: "App", packageName: "Other", swiftFileContent: app.map { "import Feature\nimport Middle\n\n" + $0 }, dependencies: ["Feature", "Middle"]),
			]
		}
		let holeModules = modules(middle: middle, app: [gadgetFulfiller, Self.root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: holeModules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, SafeDIToolSeamBuilderParameterTests.generatedFiles(module: "Middle", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Host": """
		extension Host {
		    public enum SafeDIScope_P1Impl_a {
		        public struct Outer {}

		        public struct Inner {
		            public let maker: SendableInstantiator<InnerSeam>
		        }

		        public struct Inner2 {}
		    }

		    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module's SafeDI dependencies.
		    public init(aBuilder: @escaping (SafeDIScope_P1Impl_a.Outer) -> @Sendable (SafeDIScope_P1Impl_a.Inner) -> @Sendable (SafeDIScope_P1Impl_a.Inner2) -> any Gadget) {
		        let __safeDI_aBuilder = aBuilder
		        func __safeDI_s() -> InnerSeam {
		            _ = InnerSeam.__safeDI_InnerSeam_70461E97B05074C1.self\(seamCallComment(seam: "InnerSeam"))
		            @Sendable func __safeDI_aBuilder_X(_ scope: InnerSeam.SafeDIScope_X_a) -> any P2 {
		                let a: any P2 = P2Impl()
		                return a
		            }
		            let __safeDI_aBuilder_Inner = __safeDI_aBuilder(SafeDIScope_P1Impl_a.Outer())
		            @Sendable func __safeDI_aBuilder_Inner_(_ scope: InnerSeam.SafeDIScope_Inner_a) -> any P1 {
		                func __safeDI_a() -> P1Impl {
		                    @Sendable func __safeDI_maker() -> InnerSeam {
		                        _ = InnerSeam.__safeDI_InnerSeam_70461E97B05074C1.self\(seamCallComment(seam: "InnerSeam"))
		                        return InnerSeam(aBuilder_Inner: __safeDI_aBuilder_Inner_, aBuilder_X: __safeDI_aBuilder_X)
		                    }
		                    let maker = SendableInstantiator<InnerSeam>(__safeDI_maker)
		                    let __safeDI_aBuilder_Inner2 = __safeDI_aBuilder_Inner(SafeDIScope_P1Impl_a.Inner(maker: maker))
		                    @Sendable func __safeDI_a() -> any Gadget {
		                        __safeDI_aBuilder_Inner2(SafeDIScope_P1Impl_a.Inner2())
		                    }
		                    let a = SendableLazilyInstantiated<any Gadget>(__safeDI_a)
		                    return P1Impl(a: a, maker: maker)
		                }
		                let a: any P1 = __safeDI_a()
		                return a
		            }
		            return InnerSeam(aBuilder_Inner: __safeDI_aBuilder_Inner_, aBuilder_X: __safeDI_aBuilder_X)
		        }
		        let s: InnerSeam = __safeDI_s()
		        self.init(s: s)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_D146B8EBCA8586BA {}
		}
		"""]))
		try expectEveryModuleCompiled(output)
		try await expectValuesEqualVisibleBuild(
			output,
			modules: holeModules,
			visibleModules: modules(middle: middle + [gadgetFulfiller], app: [Self.root]),
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
	mutating func generate_fillsHole_whenSeamsModuleQualifiesOneSpellingOfForwardedProperty(firstGeneric: String, forwardedType: String, guardName: String) async throws {
		let feature = Self.featureFiles(
			hostDeclarations: [#"@Instantiated(fulfilledByType: "NamedGadget", erasedToConcreteExistential: true) let part: ErasedInstantiator<\#(firstGeneric), AnyGadget>"#],
			otherFiles: [Self.labelDeclaration],
		)
		let fulfillers = [seamFixtureType(named: "NamedGadget", declarations: ["@Forwarded let label: \(forwardedType)"], conformances: ", Gadget")]
		let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: fulfillers + [Self.root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, SafeDIToolSeamBuilderParameterTests.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.\(guardName).self\(seamCallComment(seam: "Host"))
		            func __safeDI_partBuilder(_ scope: Host.SafeDIScope_Host_part, _ __safeDI_forwarded: \(firstGeneric)) -> AnyGadget {
		                func __safeDI_part(label: \(forwardedType)) -> NamedGadget {
		                    NamedGadget(label: label)
		                }
		                return AnyGadget(__safeDI_part(label: __safeDI_forwarded))
		            }
		            return Host(partBuilder: __safeDI_partBuilder)
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""]))
		try expectEveryModuleCompiled(output)
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
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: fulfillers + [Self.root]),
			integration: .swiftPackagePlugin,
			filesToDelete: &filesToDelete,
		)
		try expectEveryModuleCompiled(output)
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
		try expectDifferentialValuesAgree(
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

	/// Expects every module to have compiled, when compile verification runs.
	private func expectEveryModuleCompiled(_ output: MultiModuleTestOutput, sourceLocation: SourceLocation = #_sourceLocation) throws {
		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation, sourceLocation: sourceLocation)
		#expect(compilation.modules.map(\.exitCode) == output.moduleNames.map { _ in 0 }, sourceLocation: sourceLocation)
	}
}
