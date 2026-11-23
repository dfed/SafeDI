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

/// A place of a seam's enum nested by type that an instantiator builds takes the value the instantiator forwards: the
/// dispatcher of the place's type hands its case's forwarded value on to the fill beside the case's payload.
struct SafeDIToolSeamScopeByTypeForwardedValueTests: ~Copyable {
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
	mutating func generate_handsForwardedValueToFillOfCaseNestedByType_whenFillKeepsItsFunction() async throws {
		// `Panel`, nested in `Host`'s tree, builds `maker`, an erased instantiator `App` fills with `NamedGadget`, which
		// `maker` forwards a `Name`. `NamedGadget` receives `scope`, so its fill keeps its function, whose scope parameter is
		// named apart, and `Panel_Scope`'s dispatcher hands that function the case's payload and the forwarded `Name`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: SafeDIToolSeamBuilderParameterTests.modules(
				feature: [
					"public protocol Gadget {}",
					"public struct Name: Sendable {\n    public init() {}\n}",
					"""
					public struct AnyGadget: Gadget {
					    public init(_ base: any Gadget) {
					        self.base = base
					    }

					    let base: any Gadget
					}
					""",
					seamFixtureType(named: "Value", isFinalClass: true, declarations: []),
					seamFixtureType(named: "Panel", declarations: ["@Instantiated let scope: Value", #"@Instantiated(fulfilledByType: "NamedGadget", erasedToConcreteExistential: true) let maker: ErasedInstantiator<Name, AnyGadget>"#]),
					seamFixtureType(named: "Host", isSeam: true, declarations: ["@Instantiated let panel: Panel"]),
				],
				app: [
					"""
					@Instantiable
					public struct NamedGadget: Instantiable, Gadget {
					    public init(name: Name, scope: Value) {
					        self.name = name
					        self.scope = scope
					    }

					    @Forwarded let name: Name
					    @Received let scope: Value
					}
					""",
					seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let host: Host"]),
				],
			),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles["Feature.swift"] == generatedFileHeader + """
		extension Host {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_NamedGadget_AnyGadgetCarrier<__safeDI_Built> {
		        public let panel: __safeDI_NamedGadget_AnyGadgetCarrier_Panel<__safeDI_Built>

		        public init(panel: __safeDI_NamedGadget_AnyGadgetCarrier_Panel<__safeDI_Built>) {
		            self.panel = panel
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Name, __safeDI_Built>.Builder) {
		            self.init(panel: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_NamedGadget_AnyGadgetCarrier_Panel<__safeDI_Built> {
		        public let maker: (Value) -> ErasedInstantiator<Name, __safeDI_Built>.Builder

		        public init(maker: @escaping (Value) -> ErasedInstantiator<Name, __safeDI_Built>.Builder) {
		            self.maker = maker
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Name, __safeDI_Built>.Builder) {
		            self.init(maker: { _ in __safeDI_builder })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_namedGadget_AnyGadgetBuilder: __safeDI_NamedGadget_AnyGadgetCarrier<AnyGadget>) {
		        let __safeDI_namedGadget_AnyGadgetBuilder_panel = __safeDI_namedGadget_AnyGadgetBuilder.panel
		        func __safeDI_panel() -> Panel {
		            let scope = Value()
		            let maker = ErasedInstantiator<Name, AnyGadget>(__safeDI_namedGadget_AnyGadgetBuilder_panel.maker(scope))
		            return Panel(scope: scope, maker: maker)
		        }
		        let panel: Panel = __safeDI_panel()
		        self.init(panel: panel)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_04EE2D5F328FE7B3 {}
		}
		""")
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_04EE2D5F328FE7B3.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_namedGadget_AnyGadgetBuilder_Host_Panel_Scope_maker(scope: Value) -> ErasedInstantiator<Name, AnyGadget>.Builder {
		                func __safeDI_maker(name: Name) -> NamedGadget {
		                    NamedGadget(name: name, scope: scope)
		                }
		                return { forwarded in AnyGadget(__safeDI_maker(name: forwarded)) }
		            }
		            func __safeDI_namedGadget_AnyGadgetBuilder_Host() -> Host.__safeDI_NamedGadget_AnyGadgetCarrier<AnyGadget> {
		                .init(panel: __safeDI_namedGadget_AnyGadgetBuilder_Host_Panel_Scope())
		            }
		            func __safeDI_namedGadget_AnyGadgetBuilder_Host_Panel_Scope() -> Host.__safeDI_NamedGadget_AnyGadgetCarrier_Panel<AnyGadget> {
		                .init(maker: { values_scope in __safeDI_namedGadget_AnyGadgetBuilder_Host_Panel_Scope_maker(scope: values_scope) })
		            }
		            return Host(__safeDI_namedGadget_AnyGadgetBuilder: __safeDI_namedGadget_AnyGadgetBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		""")
	}

	// MARK: Private

	private var filesToDelete: [URL]
}
