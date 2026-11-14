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
		    @frozen public enum SafeDIScope_NamedGadget {
		        case panel(panel_Values, SafeDIScope_NamedGadget.Panel_Scope)

		        public struct panel_Values {}

		        @frozen public enum Panel_Scope {
		            case maker(maker_Values, Name)

		            public struct maker_Values {
		                public let scope: Value
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_namedGadgetBuilder: @escaping (SafeDIScope_NamedGadget) -> AnyGadget) {
		        let __safeDI_namedGadgetValues_panel = SafeDIScope_NamedGadget.panel_Values()
		        func __safeDI_panel() -> Panel {
		            let scope = Value()
		            let maker = ErasedInstantiator<Name, AnyGadget> {
		                __safeDI_namedGadgetBuilder(.panel(__safeDI_namedGadgetValues_panel, .maker(SafeDIScope_NamedGadget.Panel_Scope.maker_Values(scope: scope), $0)))
		            }
		            return Panel(scope: scope, maker: maker)
		        }
		        let panel: Panel = __safeDI_panel()
		        self.init(panel: panel)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_2E0D2BE6C266127C {}
		}
		""")
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_2E0D2BE6C266127C.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_namedGadgetBuilder_Host_Panel_Scope_maker(_ scope_: Host.SafeDIScope_NamedGadget.Panel_Scope.maker_Values, _ __safeDI_forwarded: Name) -> AnyGadget {
		                let scope = scope_.scope
		                func __safeDI_maker(name: Name) -> NamedGadget {
		                    NamedGadget(name: name, scope: scope)
		                }
		                return AnyGadget(__safeDI_maker(name: __safeDI_forwarded))
		            }
		            func __safeDI_namedGadgetBuilder_Host(_ scope: Host.SafeDIScope_NamedGadget) -> AnyGadget {
		                switch scope {
		                case let .panel(_, scope): return __safeDI_namedGadgetBuilder_Host_Panel_Scope(scope)
		                }
		            }
		            func __safeDI_namedGadgetBuilder_Host_Panel_Scope(_ scope: Host.SafeDIScope_NamedGadget.Panel_Scope) -> AnyGadget {
		                switch scope {
		                case let .maker(scope, __safeDI_forwarded): return __safeDI_namedGadgetBuilder_Host_Panel_Scope_maker(scope, __safeDI_forwarded)
		                }
		            }
		            return Host(__safeDI_namedGadgetBuilder: __safeDI_namedGadgetBuilder_Host)
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
