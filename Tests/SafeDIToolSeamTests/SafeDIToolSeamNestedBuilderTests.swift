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

/// A hole type takes one builder per family over an enum of the places it builds, and inner seams nest as cases.
struct SafeDIToolSeamNestedBuilderTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Fixtures

	private static let service = "public protocol Service {}"
	private static let sendableService = "public protocol Service: Sendable {}"

	private static func type(_ name: String, seam: Bool = false, _ declarations: [String] = [], conformances: String = "") -> String {
		seamFixtureType(named: name, isSeam: seam, declarations: declarations, conformances: conformances)
	}

	private static func root(_ declarations: [String]) -> String {
		seamFixtureType(named: "Root", isRoot: true, declarations: declarations)
	}

	private static func fulfilling(_ name: String, _ fulfilled: String, _ declarations: [String] = [], conformances: String = "") -> String {
		seamFixtureType(named: name, declarations: declarations, conformances: ", \(fulfilled)\(conformances)")
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [\(fulfilled).self])\n")
	}

	private static func modules(feature: [String], app: [String], featureConfiguration: [String: String] = [:]) -> [ModuleFixture] {
		SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: app, featureConfiguration: featureConfiguration)
	}

	/// Expects each module's generated files to equal `expected` (each file after the generated header), every module to
	/// compile, and, when `visible` is given, the values built to equal those of the graph with every fulfiller in the seam's
	/// module.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectOutput(
		of modules: [ModuleFixture],
		_ expected: [String: [String: String]],
		visible: [ModuleFixture]? = nil,
		probes: [DifferentialValueProbe] = [DifferentialValueProbe("Root()")],
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		for (moduleName, files) in expected {
			let generatedFiles = output.modules[moduleName]?.generatedFiles
			let expectedFiles = files.mapValues { generatedFileHeader + $0 }
			#expect(generatedFiles == expectedFiles, sourceLocation: sourceLocation)
		}
		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation, sourceLocation: sourceLocation)
		#expect(compilation.modules.map(\.exitCode) == output.moduleNames.map { _ in 0 }, sourceLocation: sourceLocation)
		if let visible {
			let visibleOutput = try await executeSafeDIToolMultiModuleTest(modules: visible, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
			try await expectDifferentialValuesAgree(
				feature: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: output, modules: modules),
				knownRight: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: visibleOutput, modules: visible),
				probes: probes,
				filesToDelete: &filesToDelete,
				sourceLocation: sourceLocation,
			)
		}
	}

	/// The output of `modules`, each module's files compiling.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func compiledOutput(of modules: [ModuleFixture], sourceLocation: SourceLocation = #_sourceLocation) async throws -> MultiModuleTestOutput {
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		guard compileVerificationIsEnabled else { return output }
		let compilation = try #require(output.compilation, sourceLocation: sourceLocation)
		#expect(compilation.modules.map(\.exitCode) == output.moduleNames.map { _ in 0 }, sourceLocation: sourceLocation)
		return output
	}

	/// The module named `App` with a hand-written caller of `Host`, which must compile beside the generated code.
	private static func handWritten(_ source: String) -> String {
		"import SafeDI\n\n" + source
	}

	// MARK: 1. Places

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesOneBuilderOverAnEnum_whenSeamHasOnePlace() async throws {
		let feature = [Self.service, Self.type("Panel", ["@Instantiated public let service: any Service"]), Self.type("Host", seam: true, ["@Instantiated public let panel: Panel"])]
		let fulfiller = Self.fulfilling("DefaultService", "Service")
		let root = Self.root(["@Instantiated public let host: Host"])
		try await expectOutput(of: Self.modules(feature: feature, app: [fulfiller, root]), [
			"Feature": ["Feature.swift": """
			extension Host {
			    @frozen public enum SafeDIScope_Service {
			        case panel_service(panel_service_Values)

			        public struct panel_service_Values {}
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
			        func __safeDI_panel() -> Panel {
			            let service: any Service = __safeDI_serviceBuilder(.panel_service(SafeDIScope_Service.panel_service_Values()))
			            return Panel(service: service)
			        }
			        let panel: Panel = __safeDI_panel()
			        self.init(panel: panel)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_0BF22C17CAA744E6 {}
			}
			"""],
			"App": ["App.swift": """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_0BF22C17CAA744E6.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_serviceBuilder_Host(_ scope: Host.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case .panel_service:
			                    let service: any Service = DefaultService()
			                    return service
			                }
			            }
			            return Host(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Host)
			        }
			        let host: Host = __safeDI_host()
			        self.init(host: host)
			    }
			}
			"""],
		], visible: Self.modules(feature: feature + [fulfiller], app: [root]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_addsCaseToOneEnum_whenSeamHasTwoPlacesOfOneType() async throws {
		let feature = [
			Self.service,
			Self.type("Panel", ["@Instantiated public let service: any Service"]),
			Self.type("Row", ["@Instantiated public let service: any Service"]),
			Self.type("Host", seam: true, ["@Instantiated public let panel: Panel", "@Instantiated public let row: Row"]),
		]
		let fulfiller = Self.fulfilling("DefaultService", "Service")
		let root = Self.root(["@Instantiated public let host: Host"])
		try await expectOutput(of: Self.modules(feature: feature, app: [fulfiller, root]), [
			"Feature": ["Feature.swift": """
			extension Host {
			    @frozen public enum SafeDIScope_Service {
			        case panel_service(panel_service_Values)
			        case row_service(row_service_Values)

			        public struct panel_service_Values {}

			        public struct row_service_Values {
			            public let panel: Panel
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
			        func __safeDI_panel() -> Panel {
			            let service: any Service = __safeDI_serviceBuilder(.panel_service(SafeDIScope_Service.panel_service_Values()))
			            return Panel(service: service)
			        }
			        let panel: Panel = __safeDI_panel()
			        func __safeDI_row() -> Row {
			            let service: any Service = __safeDI_serviceBuilder(.row_service(SafeDIScope_Service.row_service_Values(panel: panel)))
			            return Row(service: service)
			        }
			        let row: Row = __safeDI_row()
			        self.init(panel: panel, row: row)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_CF0662E355CA8233 {}
			}
			"""],
			"App": ["App.swift": """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_CF0662E355CA8233.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_serviceBuilder_Host(_ scope: Host.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case .panel_service:
			                    let service: any Service = DefaultService()
			                    return service
			                case .row_service:
			                    let service: any Service = DefaultService()
			                    return service
			                }
			            }
			            return Host(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Host)
			        }
			        let host: Host = __safeDI_host()
			        self.init(host: host)
			    }
			}
			"""],
		], visible: Self.modules(feature: feature + [fulfiller], app: [root]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesEachPlaceByItsPath_whenSameTypeIsBuiltTwice() async throws {
		let feature = [
			Self.service,
			Self.type("Panel", ["@Instantiated public let service: any Service"]),
			Self.type("Host", seam: true, ["@Instantiated public let first: Panel", "@Instantiated public let second: Panel"]),
		]
		let fulfiller = Self.fulfilling("DefaultService", "Service")
		let root = Self.root(["@Instantiated public let host: Host"])
		try await expectOutput(of: Self.modules(feature: feature, app: [fulfiller, root]), [
			"Feature": ["Feature.swift": """
			extension Host {
			    @frozen public enum SafeDIScope_Service {
			        case first_service(first_service_Values)
			        case second_service(second_service_Values)

			        public struct first_service_Values {}

			        public struct second_service_Values {
			            public let first: Panel
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
			        func __safeDI_first() -> Panel {
			            let service: any Service = __safeDI_serviceBuilder(.first_service(SafeDIScope_Service.first_service_Values()))
			            return Panel(service: service)
			        }
			        let first: Panel = __safeDI_first()
			        func __safeDI_second() -> Panel {
			            let service: any Service = __safeDI_serviceBuilder(.second_service(SafeDIScope_Service.second_service_Values(first: first)))
			            return Panel(service: service)
			        }
			        let second: Panel = __safeDI_second()
			        self.init(first: first, second: second)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_F06EA57CC92F553F {}
			}
			"""],
		], visible: Self.modules(feature: feature + [fulfiller], app: [root]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesOneBuilder_whenTwoLabelsBuildOneType() async throws {
		let feature = [
			Self.service,
			Self.type("Host", seam: true, ["@Instantiated public let first: any Service", "@Instantiated public let second: any Service"]),
		]
		let fulfiller = Self.fulfilling("DefaultService", "Service")
		let root = Self.root(["@Instantiated public let host: Host"])
		try await expectOutput(of: Self.modules(feature: feature, app: [fulfiller, root]), [
			"Feature": ["Feature.swift": """
			extension Host {
			    @frozen public enum SafeDIScope_Service {
			        case first(first_Values)
			        case second(second_Values)

			        public struct first_Values {}

			        public struct second_Values {
			            public let first: any Service
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
			        let first: any Service = __safeDI_serviceBuilder(.first(SafeDIScope_Service.first_Values()))
			        let second: any Service = __safeDI_serviceBuilder(.second(SafeDIScope_Service.second_Values(first: first)))
			        self.init(first: first, second: second)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_8E4067105E97376A {}
			}
			"""],
			"App": ["App.swift": """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_8E4067105E97376A.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_serviceBuilder_Host(_ scope: Host.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case .first:
			                    let first: any Service = DefaultService()
			                    return first
			                case .second:
			                    let second: any Service = DefaultService()
			                    return second
			                }
			            }
			            return Host(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Host)
			        }
			        let host: Host = __safeDI_host()
			        self.init(host: host)
			    }
			}
			"""],
		], visible: Self.modules(feature: feature + [fulfiller], app: [root]))
	}

	// MARK: 2. Hole types

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesABuilderPerHoleType_whenSeamHasTwoHoleTypes() async throws {
		let feature = [
			Self.service,
			"public protocol Gadget {}",
			Self.type("Host", seam: true, ["@Instantiated public let service: any Service", "@Instantiated public let gadget: any Gadget"]),
		]
		let fulfillers = [Self.fulfilling("DefaultService", "Service"), Self.fulfilling("DefaultGadget", "Gadget")]
		let root = Self.root(["@Instantiated public let host: Host"])
		try await expectOutput(of: Self.modules(feature: feature, app: fulfillers + [root]), [
			"Feature": ["Feature.swift": """
			extension Host {
			    @frozen public enum SafeDIScope_Gadget {
			        case gadget(gadget_Values)

			        public struct gadget_Values {
			            public let service: any Service
			        }
			    }

			    @frozen public enum SafeDIScope_Service {
			        case service(service_Values)

			        public struct service_Values {}
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_gadgetBuilder: @escaping (SafeDIScope_Gadget) -> any Gadget, __safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
			        let service: any Service = __safeDI_serviceBuilder(.service(SafeDIScope_Service.service_Values()))
			        let gadget: any Gadget = __safeDI_gadgetBuilder(.gadget(SafeDIScope_Gadget.gadget_Values(service: service)))
			        self.init(service: service, gadget: gadget)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_09BAD0C2B9C44619 {}
			}
			"""],
			"App": ["App.swift": """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_09BAD0C2B9C44619.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_gadgetBuilder_Host(_ scope: Host.SafeDIScope_Gadget) -> any Gadget {
			                switch scope {
			                case .gadget:
			                    let gadget: any Gadget = DefaultGadget()
			                    return gadget
			                }
			            }
			            func __safeDI_serviceBuilder_Host(_ scope: Host.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case .service:
			                    let service: any Service = DefaultService()
			                    return service
			                }
			            }
			            return Host(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Host, __safeDI_serviceBuilder: __safeDI_serviceBuilder_Host)
			        }
			        let host: Host = __safeDI_host()
			        self.init(host: host)
			    }
			}
			"""],
		], visible: Self.modules(feature: feature + fulfillers, app: [root]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesHoleTypesApartByReturnedType_whenOneInstantiatedTypeIsBuiltAsTwoTypes() async throws {
		let feature = [
			Self.service,
			"""
			public struct AnyService: Service {
			    public init(_ base: any Service) {
			        self.base = base
			    }

			    let base: any Service
			}
			""",
			Self.type("Host", seam: true, [
				#"@Instantiated(fulfilledByType: "Impl") public let plain: any Service"#,
				#"@Instantiated(fulfilledByType: "Impl", erasedToConcreteExistential: true) public let erased: AnyService"#,
			]),
		]
		let output = try await compiledOutput(of: [ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature)])
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen public enum SafeDIScope_Impl_AnyService {
		        case erased(erased_Values)

		        public struct erased_Values {
		            public let plain: any Service
		        }
		    }

		    @frozen public enum SafeDIScope_Impl_Service {
		        case plain(plain_Values)

		        public struct plain_Values {}
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_impl_AnyServiceBuilder: @escaping (SafeDIScope_Impl_AnyService) -> AnyService, __safeDI_impl_ServiceBuilder: @escaping (SafeDIScope_Impl_Service) -> any Service) {
		        let plain: any Service = __safeDI_impl_ServiceBuilder(.plain(SafeDIScope_Impl_Service.plain_Values()))
		        let erased: AnyService = __safeDI_impl_AnyServiceBuilder(.erased(SafeDIScope_Impl_AnyService.erased_Values(plain: plain)))
		        self.init(plain: plain, erased: erased)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_25C856E8DF33718D {}
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesBothHoleTypesApart_whenAStemEqualsAnothersSendableLabel() async throws {
		let feature = [
			Self.service,
			"public protocol ServiceSendable {}",
			Self.type("Host", seam: true, ["@Instantiated public let service: any Service", "@Instantiated public let other: any ServiceSendable"]),
		]
		let output = try await compiledOutput(of: [ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature)])
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen public enum SafeDIScope_ServiceSendable_ServiceSendable {
		        case other(other_Values)

		        public struct other_Values {
		            public let service: any Service
		        }
		    }

		    @frozen public enum SafeDIScope_Service_Service {
		        case service(service_Values)

		        public struct service_Values {}
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_serviceSendable_ServiceSendableBuilder: @escaping (SafeDIScope_ServiceSendable_ServiceSendable) -> any ServiceSendable, __safeDI_service_ServiceBuilder: @escaping (SafeDIScope_Service_Service) -> any Service) {
		        let service: any Service = __safeDI_service_ServiceBuilder(.service(SafeDIScope_Service_Service.service_Values()))
		        let other: any ServiceSendable = __safeDI_serviceSendable_ServiceSendableBuilder(.other(SafeDIScope_ServiceSendable_ServiceSendable.other_Values(service: service)))
		        self.init(service: service, other: other)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_4483A7CE600E2725 {}
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_treatsSpellingsOfOneTypeAsOneHoleType_whenOneSpellingWritesAny() async throws {
		let feature = [
			"public protocol P {}",
			"public struct Box<T> {}",
			Self.type("Host", seam: true, ["@Instantiated public let first: Box<any P>", "@Instantiated public let second: Box<P>"]),
		]
		let output = try await compiledOutput(of: [ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature)])
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen public enum SafeDIScope_Box__P {
		        case first(first_Values)
		        case second(second_Values)

		        public struct first_Values {}

		        public struct second_Values {
		            public let first: Box<any P>
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_box__PBuilder: @escaping (SafeDIScope_Box__P) -> Box<any P>) {
		        let first: Box<any P> = __safeDI_box__PBuilder(.first(SafeDIScope_Box__P.first_Values()))
		        let second: Box<P> = __safeDI_box__PBuilder(.second(SafeDIScope_Box__P.second_Values(first: first)))
		        self.init(first: first, second: second)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_FCFA835EEA361C8C {}
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_treatsCompositionsAsOneHoleType_whenMembersAreWrittenInEitherOrder() async throws {
		let feature = [
			"public protocol P {}",
			"public protocol Q {}",
			Self.type("Host", seam: true, ["@Instantiated public let first: any P & Q", "@Instantiated public let second: any Q & P"]),
		]
		let output = try await compiledOutput(of: [ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature)])
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen public enum SafeDIScope_P_and_Q {
		        case first(first_Values)
		        case second(second_Values)

		        public struct first_Values {}

		        public struct second_Values {
		            public let first: any (P & Q)
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_p_and_QBuilder: @escaping (SafeDIScope_P_and_Q) -> any (P & Q)) {
		        let first: any (P & Q) = __safeDI_p_and_QBuilder(.first(SafeDIScope_P_and_Q.first_Values()))
		        let second: any (Q & P) = __safeDI_p_and_QBuilder(.second(SafeDIScope_P_and_Q.second_Values(first: first)))
		        self.init(first: first, second: second)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_A9ACCDA29E16190D {}
		}
		"""])
	}

	/// A hole type spelled two ways that are one type: a composition's members in either order, at a depth inside each kind
	/// of type a hole type can spell, and `Void` as `Void` and `()`.
	enum OneHoleTypeSpelledTwoWays: CaseIterable, CustomTestStringConvertible {
		case generic
		case nested
		case optional
		case array
		case dictionary
		case tuple
		case closure
		case attributed
		case metatype
		case variadic
		case void

		var testDescription: String {
			"\(self)"
		}

		/// The spelling of the first place, which writes the members in the order their identifiers do not sort in.
		var first: String {
			switch self {
			case .generic: "Box<any Q & P>"
			case .nested: "Outer.Box<any Q & P>"
			case .optional: "Box<(any Q & P)?>"
			case .array: "Box<[any Q & P]>"
			case .dictionary: "Box<[String: any Q & P]>"
			case .tuple: "Box<(Int, any Q & P)>"
			case .closure: "Box<(any Q & P) -> Void>"
			case .attributed: "Box<@Sendable (any Q & P) -> Void>"
			case .metatype: "Box<(any Q & P).Type>"
			case .variadic: "Box<((any Q & P)...) -> Void>"
			case .void: "Box<()>"
			}
		}

		var second: String {
			switch self {
			case .generic: "Box<any P & Q>"
			case .nested: "Outer.Box<any P & Q>"
			case .optional: "Box<(any P & Q)?>"
			case .array: "Box<[any P & Q]>"
			case .dictionary: "Box<[String: any P & Q]>"
			case .tuple: "Box<(Int, any P & Q)>"
			case .closure: "Box<(any P & Q) -> Void>"
			case .attributed: "Box<@Sendable (any P & Q) -> Void>"
			case .metatype: "Box<(any P & Q).Type>"
			case .variadic: "Box<((any P & Q)...) -> Void>"
			case .void: "Box<Void>"
			}
		}

		/// The type of the place `first`, as generated code spells it.
		var spelledFirst: String {
			switch self {
			case .generic: "Box<any (Q & P)>"
			case .nested: "Outer.Box<any (Q & P)>"
			case .optional: "Box<(any (Q & P))?>"
			case .array: "Box<[any (Q & P)]>"
			case .dictionary: "Box<[String: any (Q & P)]>"
			case .tuple: "Box<(Int, any (Q & P))>"
			case .closure: "Box<(any (Q & P)) -> Void>"
			case .attributed: "Box<@Sendable (any (Q & P)) -> Void>"
			case .metatype: "Box<(any (Q & P)).Type>"
			case .variadic: "Box<((any (Q & P))...) -> Void>"
			case .void: "Box<()>"
			}
		}

		/// The type of the place `second`, as generated code spells it.
		var spelledSecond: String {
			switch self {
			case .generic: "Box<any (P & Q)>"
			case .nested: "Outer.Box<any (P & Q)>"
			case .optional: "Box<(any (P & Q))?>"
			case .array: "Box<[any (P & Q)]>"
			case .dictionary: "Box<[String: any (P & Q)]>"
			case .tuple: "Box<(Int, any (P & Q))>"
			case .closure: "Box<(any (P & Q)) -> Void>"
			case .attributed: "Box<@Sendable (any (P & Q)) -> Void>"
			case .metatype: "Box<(any (P & Q)).Type>"
			case .variadic: "Box<((any (P & Q))...) -> Void>"
			case .void: "Box<Void>"
			}
		}

		/// The hole type's stem, whose composition lists its members in the order of their identifiers.
		var stem: String {
			switch self {
			case .generic: "Box__P_and_Q"
			case .nested: "Outer_Box__P_and_Q"
			case .optional: "Box__P_and_Q_Optional"
			case .array: "Box__Array_P_and_Q"
			case .dictionary: "Box__Dictionary_String_P_and_Q"
			case .tuple: "Box__Int_and_P_and_Q"
			case .closure: "Box__P_and_Q_to_Void"
			case .attributed: "Box__Sendable_P_and_Q_to_Void"
			case .metatype: "Box__P_and_Q_Protocol"
			case .variadic: "Box__P_and_Q_Variadic_to_Void"
			case .void: "Box__Void"
			}
		}

		/// The builder's label: the stem with its one leading capital lowered, then `Builder`.
		var label: String {
			"\(stem.prefix(1).lowercased())\(stem.dropFirst())Builder"
		}

		/// The name of the guard enum `Host` generates.
		var guardName: String {
			switch self {
			case .generic: "__safeDI_Host_C958AF46DF9F0DA2"
			case .nested: "__safeDI_Host_39C8FEDB3D447816"
			case .optional: "__safeDI_Host_61EE4F90382702AD"
			case .array: "__safeDI_Host_AB28E2BAAFAFCFBC"
			case .dictionary: "__safeDI_Host_3CC21A8E26BC58D7"
			case .tuple: "__safeDI_Host_6CD0A1F4585476DE"
			case .closure: "__safeDI_Host_740244B68A4F283F"
			case .attributed: "__safeDI_Host_DF621FF3F24A758C"
			case .metatype: "__safeDI_Host_4269FB220FE5BF43"
			case .variadic: "__safeDI_Host_F2F8E168B44DDBAD"
			case .void: "__safeDI_Host_654CB7C86458DE66"
			}
		}
	}

	@Test(arguments: OneHoleTypeSpelledTwoWays.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesOneHoleTypeByItsCanonicalSpelling_whenPlacesSpellItTwoWaysInsideAType(spelling: OneHoleTypeSpelledTwoWays) async throws {
		let feature = [
			"public protocol P {}",
			"public protocol Q {}",
			"public struct Box<T> {}",
			"public enum Outer {\n    public struct Box<T> {}\n}",
			Self.type("Host", seam: true, ["@Instantiated public let first: \(spelling.first)", "@Instantiated public let second: \(spelling.second)"]),
		]
		let output = try await compiledOutput(of: [ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature)])
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen public enum SafeDIScope_\(spelling.stem) {
		        case first(first_Values)
		        case second(second_Values)

		        public struct first_Values {}

		        public struct second_Values {
		            public let first: \(spelling.spelledFirst)
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_\(spelling.label): @escaping (SafeDIScope_\(spelling.stem)) -> \(spelling.spelledFirst)) {
		        let first: \(spelling.spelledFirst) = __safeDI_\(spelling.label)(.first(SafeDIScope_\(spelling.stem).first_Values()))
		        let second: \(spelling.spelledSecond) = __safeDI_\(spelling.label)(.second(SafeDIScope_\(spelling.stem).second_Values(first: first)))
		        self.init(first: first, second: second)
		    }
		}

		extension Host {
		    public enum \(spelling.guardName) {}
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesOneHoleTypeByItsCanonicalSpelling_whenRenamesSpellItTwoWaysInsideAnImplicitlyUnwrappedOptional() async throws {
		// The macro rejects `!` at the top of a `fulfilledByType:` string, but not inside a generic argument of the type it
		// names, so two renames can spell one hole type with a composition inside `!` written in either order.
		let feature = [
			"public protocol P {}",
			"public protocol Q {}",
			"public struct Box<T> {}",
			Self.service,
			"public struct AnyService: Service {\n    public init(_ service: any Service) {\n        self.service = service\n    }\n\n    public let service: any Service\n}",
			Self.type("Host", seam: true, [
				#"@Instantiated(fulfilledByType: "Box<(any Q & P)!>", erasedToConcreteExistential: true) public let first: AnyService"#,
				#"@Instantiated(fulfilledByType: "Box<(any P & Q)!>", erasedToConcreteExistential: true) public let second: AnyService"#,
			]),
		]
		let output = try await compiledOutput(of: [ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature)])
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen public enum SafeDIScope_Box__P_and_Q_Optional {
		        case first(first_Values)
		        case second(second_Values)

		        public struct first_Values {}

		        public struct second_Values {
		            public let first: AnyService
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_box__P_and_Q_OptionalBuilder: @escaping (SafeDIScope_Box__P_and_Q_Optional) -> AnyService) {
		        let first: AnyService = __safeDI_box__P_and_Q_OptionalBuilder(.first(SafeDIScope_Box__P_and_Q_Optional.first_Values()))
		        let second: AnyService = __safeDI_box__P_and_Q_OptionalBuilder(.second(SafeDIScope_Box__P_and_Q_Optional.second_Values(first: first)))
		        self.init(first: first, second: second)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_789D42BD1D7D0BC4 {}
		}
		"""])
	}

	// MARK: 3. Inner seams

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_nestsInnerSeamsEnumAsACase_whenSeamPassesItUp() async throws {
		let feature = [
			Self.service,
			Self.type("Inner", seam: true, ["@Instantiated public let service: any Service"]),
			Self.type("Host", seam: true, ["@Instantiated public let inner: Inner", "@Instantiated public let service: any Service"]),
		]
		let fulfiller = Self.fulfilling("DefaultService", "Service")
		let root = Self.root(["@Instantiated public let host: Host"])
		try await expectOutput(of: Self.modules(feature: feature, app: [fulfiller, root]), [
			"Feature": ["Feature.swift": """
			extension Host {
			    @frozen public enum SafeDIScope_Service {
			        case inner(Inner.SafeDIScope_Service)
			        case service(service_Values)

			        public struct service_Values {
			            public let inner: Inner
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
			        func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_C117FA38A959D655.self
			            return Inner(__safeDI_serviceBuilder: { __safeDI_serviceBuilder(.inner($0)) })
			        }
			        let inner: Inner = __safeDI_inner()
			        let service: any Service = __safeDI_serviceBuilder(.service(SafeDIScope_Service.service_Values(inner: inner)))
			        self.init(inner: inner, service: service)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_3A6CCB353921C199 {}
			}

			extension Inner {
			    @frozen public enum SafeDIScope_Service {
			        case service(service_Values)

			        public struct service_Values {}
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
			        let service: any Service = __safeDI_serviceBuilder(.service(SafeDIScope_Service.service_Values()))
			        self.init(service: service)
			    }
			}

			extension Inner {
			    public enum __safeDI_Inner_C117FA38A959D655 {}
			}
			"""],
			"App": ["App.swift": """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_3A6CCB353921C199.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_serviceBuilder_Host(_ scope: Host.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case let .inner(scope): return __safeDI_serviceBuilder_Inner(scope)
			                case .service:
			                    let service: any Service = DefaultService()
			                    return service
			                }
			            }
			            func __safeDI_serviceBuilder_Inner(_ scope: Inner.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case .service:
			                    let service: any Service = DefaultService()
			                    return service
			                }
			            }
			            return Host(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Host)
			        }
			        let host: Host = __safeDI_host()
			        self.init(host: host)
			    }
			}
			"""],
		], visible: Self.modules(feature: feature + [fulfiller], app: [root]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_compilesHandWrittenSwitch_whenCallerOpensOrLeavesAnInnerSeam() async throws {
		let feature = [
			Self.service,
			Self.type("Inner", seam: true, ["@Instantiated public let service: any Service"]),
			Self.type("Host", seam: true, ["@Instantiated public let inner: Inner", "@Instantiated public let service: any Service"]),
		]
		_ = try await compiledOutput(of: Self.modules(feature: feature, app: [
			"""
			struct DefaultService: Service {}

			func opened() -> Host {
			    Host(serviceBuilder: { scope in
			        switch scope {
			        case .service: DefaultService()
			        case let .inner(inner):
			            switch inner {
			            case .service: DefaultService()
			            }
			        }
			    })
			}

			func notOpened() -> Host {
			    Host(serviceBuilder: { scope in
			        switch scope {
			        case .service, .inner: DefaultService()
			        }
			    })
			}

			func ignored() -> Host {
			    Host(serviceBuilder: { _ in DefaultService() })
			}
			""",
		], featureConfiguration: plainDependencyTreeInitializersConfiguration))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_sharesOneDispatcher_whenTwoRoutesReachOneInnerSeam() async throws {
		let feature = [
			Self.service,
			Self.type("Inner", seam: true, ["@Instantiated public let service: any Service"]),
			Self.type("Host", seam: true, ["@Instantiated public let first: Inner", "@Instantiated public let second: Inner"]),
		]
		let fulfiller = Self.fulfilling("DefaultService", "Service")
		let root = Self.root(["@Instantiated public let host: Host"])
		try await expectOutput(of: Self.modules(feature: feature, app: [fulfiller, root]), [
			"Feature": ["Feature.swift": """
			extension Host {
			    @frozen public enum SafeDIScope_Service {
			        case first(Inner.SafeDIScope_Service)
			        case second(Inner.SafeDIScope_Service)
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
			        func __safeDI_first() -> Inner {
			            _ = Inner.__safeDI_Inner_C117FA38A959D655.self
			            return Inner(__safeDI_serviceBuilder: { __safeDI_serviceBuilder(.first($0)) })
			        }
			        let first: Inner = __safeDI_first()
			        func __safeDI_second() -> Inner {
			            _ = Inner.__safeDI_Inner_C117FA38A959D655.self
			            return Inner(__safeDI_serviceBuilder: { __safeDI_serviceBuilder(.second($0)) })
			        }
			        let second: Inner = __safeDI_second()
			        self.init(first: first, second: second)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_FEF1C828E21BA477 {}
			}

			extension Inner {
			    @frozen public enum SafeDIScope_Service {
			        case service(service_Values)

			        public struct service_Values {}
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
			        let service: any Service = __safeDI_serviceBuilder(.service(SafeDIScope_Service.service_Values()))
			        self.init(service: service)
			    }
			}

			extension Inner {
			    public enum __safeDI_Inner_C117FA38A959D655 {}
			}
			"""],
			"App": ["App.swift": """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_FEF1C828E21BA477.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_serviceBuilder_Host(_ scope: Host.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case let .first(scope): return __safeDI_serviceBuilder_Inner(scope)
			                case let .second(scope): return __safeDI_serviceBuilder_Inner(scope)
			                }
			            }
			            func __safeDI_serviceBuilder_Inner(_ scope: Inner.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case .service:
			                    let service: any Service = DefaultService()
			                    return service
			                }
			            }
			            return Host(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Host)
			        }
			        let host: Host = __safeDI_host()
			        self.init(host: host)
			    }
			}
			"""],
		], visible: Self.modules(feature: feature + [fulfiller], app: [root]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_nestsEnums_whenThreeSeamsPassAHoleUp() async throws {
		let feature = [
			Self.service,
			Self.type("Deep", seam: true, ["@Instantiated public let service: any Service"]),
			Self.type("Mid", seam: true, ["@Instantiated public let deep: Deep"]),
			Self.type("Host", seam: true, ["@Instantiated public let mid: Mid"]),
		]
		let fulfiller = Self.fulfilling("DefaultService", "Service")
		let root = Self.root(["@Instantiated public let host: Host"])
		try await expectOutput(of: Self.modules(feature: feature, app: [fulfiller, root]), [
			"Feature": ["Feature.swift": """
			extension Deep {
			    @frozen public enum SafeDIScope_Service {
			        case service(service_Values)

			        public struct service_Values {}
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
			        let service: any Service = __safeDI_serviceBuilder(.service(SafeDIScope_Service.service_Values()))
			        self.init(service: service)
			    }
			}

			extension Deep {
			    public enum __safeDI_Deep_D1509515408C937F {}
			}

			extension Host {
			    @frozen public enum SafeDIScope_Service {
			        case mid(Mid.SafeDIScope_Service)
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
			        func __safeDI_mid() -> Mid {
			            _ = Mid.__safeDI_Mid_86BEA98CCD6C1EE5.self
			            return Mid(__safeDI_serviceBuilder: { __safeDI_serviceBuilder(.mid($0)) })
			        }
			        let mid: Mid = __safeDI_mid()
			        self.init(mid: mid)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_846D40D38B63A7C7 {}
			}

			extension Mid {
			    @frozen public enum SafeDIScope_Service {
			        case deep(Deep.SafeDIScope_Service)
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
			        func __safeDI_deep() -> Deep {
			            _ = Deep.__safeDI_Deep_D1509515408C937F.self
			            return Deep(__safeDI_serviceBuilder: { __safeDI_serviceBuilder(.deep($0)) })
			        }
			        let deep: Deep = __safeDI_deep()
			        self.init(deep: deep)
			    }
			}

			extension Mid {
			    public enum __safeDI_Mid_86BEA98CCD6C1EE5 {}
			}
			"""],
			"App": ["App.swift": """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_846D40D38B63A7C7.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_serviceBuilder_Host(_ scope: Host.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case let .mid(scope): return __safeDI_serviceBuilder_Mid(scope)
			                }
			            }
			            func __safeDI_serviceBuilder_Mid(_ scope: Mid.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case let .deep(scope): return __safeDI_serviceBuilder_Deep(scope)
			                }
			            }
			            func __safeDI_serviceBuilder_Deep(_ scope: Deep.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case .service:
			                    let service: any Service = DefaultService()
			                    return service
			                }
			            }
			            return Host(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Host)
			        }
			        let host: Host = __safeDI_host()
			        self.init(host: host)
			    }
			}
			"""],
		], visible: Self.modules(feature: feature + [fulfiller], app: [root]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsThroughFeature_whenOnlyTheFulfillersFileImportsTheLowestModule() async throws {
		let output = try await compiledOutput(of: [
			ModuleFixture(name: "Lower", packageName: "Shop", swiftFileContent: [Self.service, Self.type("Deep", seam: true, ["@Instantiated public let service: any Service"])]),
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: ["import Lower\n\n" + Self.type("Host", seam: true, ["@Instantiated public let deep: Deep"])], dependencies: ["Lower"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: ["import Lower\nimport Feature\n\n" + Self.fulfilling("DefaultService", "Service"), "import Feature\n\n" + Self.root(["@Instantiated public let host: Host"])], dependencies: ["Lower", "Feature"]),
		])
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(Lower)
		import Lower
		#endif

		extension Host {
		    @frozen public enum SafeDIScope_Service {
		        case deep(Deep.SafeDIScope_Service)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
		        func __safeDI_deep() -> Deep {
		            _ = Deep.__safeDI_Deep_D1509515408C937F.self // If this line does not compile, compile the code SafeDI generates for module Lower into Lower: under Bazel, add Lower's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Deep(__safeDI_serviceBuilder: { __safeDI_serviceBuilder(.deep($0)) })
		        }
		        let deep: Deep = __safeDI_deep()
		        self.init(deep: deep)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_FD7FE53C0027BE07 {}
		}
		"""])
	}

	// MARK: 4. Families

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_addsSendableBuilder_whenPlainAndSendableRoutesReachOneInnerSeam() async throws {
		let feature = [
			Self.sendableService,
			Self.type("Inner", seam: true, ["@Instantiated public let service: any Service"], conformances: ", Sendable"),
			Self.type("Host", seam: true, ["@Instantiated public let plain: Inner", "@Instantiated public let held: SendableInstantiator<Inner>"]),
		]
		let fulfiller = Self.fulfilling("DefaultService", "Service", conformances: ", Sendable")
		let root = Self.root(["@Instantiated public let host: Host"])
		try await expectOutput(of: Self.modules(feature: feature, app: [fulfiller, root]), [
			"Feature": ["Feature.swift": """
			extension Host {
			    @frozen public enum SafeDIScope_Service {
			        case plain(Inner.SafeDIScope_Service)
			    }

			    @frozen public enum SafeDISendableScope_Service {
			        case held(Inner.SafeDIScope_Service)
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service, __safeDI_serviceSendableBuilder: @escaping @Sendable (SafeDISendableScope_Service) -> any Service) {
			        func __safeDI_plain() -> Inner {
			            _ = Inner.__safeDI_Inner_C117FA38A959D655.self
			            return Inner(__safeDI_serviceBuilder: { __safeDI_serviceBuilder(.plain($0)) })
			        }
			        let plain: Inner = __safeDI_plain()
			        @Sendable func __safeDI_held() -> Inner {
			            _ = Inner.__safeDI_Inner_C117FA38A959D655.self
			            return Inner(__safeDI_serviceBuilder: { __safeDI_serviceSendableBuilder(.held($0)) })
			        }
			        let held = SendableInstantiator<Inner>(__safeDI_held)
			        self.init(plain: plain, held: held)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_17391BAF62D9ED43 {}
			}

			extension Inner {
			    @frozen public enum SafeDIScope_Service {
			        case service(service_Values)

			        public struct service_Values {}
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
			        let service: any Service = __safeDI_serviceBuilder(.service(SafeDIScope_Service.service_Values()))
			        self.init(service: service)
			    }
			}

			extension Inner {
			    public enum __safeDI_Inner_C117FA38A959D655 {}
			}
			"""],
			"App": ["App.swift": """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_17391BAF62D9ED43.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_serviceBuilder_Host(_ scope: Host.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case let .plain(scope): return __safeDI_serviceBuilder_Inner(scope)
			                }
			            }
			            @Sendable func __safeDI_serviceBuilder_Inner(_ scope: Inner.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case .service:
			                    let service: any Service = DefaultService()
			                    return service
			                }
			            }
			            @Sendable func __safeDI_serviceSendableBuilder_Host(_ scope: Host.SafeDISendableScope_Service) -> any Service {
			                switch scope {
			                case let .held(scope): return __safeDI_serviceBuilder_Inner(scope)
			                }
			            }
			            return Host(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Host, __safeDI_serviceSendableBuilder: __safeDI_serviceSendableBuilder_Host)
			        }
			        let host: Host = __safeDI_host()
			        self.init(host: host)
			    }
			}
			"""],
		], visible: Self.modules(feature: feature + [fulfiller], app: [root]), probes: [DifferentialValueProbe("Root().host.held.instantiate()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_nameTheSendableCase_whenInnerSeamHasBothEnums() async throws {
		let feature = [
			Self.sendableService,
			Self.type("Deep", seam: true, ["@Instantiated public let service: any Service"], conformances: ", Sendable"),
			Self.type("Inner", seam: true, ["@Instantiated public let plain: Deep", "@Instantiated public let held: SendableInstantiator<Deep>"], conformances: ", Sendable"),
			Self.type("Host", seam: true, ["@Instantiated public let inner: Inner"]),
		]
		let fulfiller = Self.fulfilling("DefaultService", "Service", conformances: ", Sendable")
		let root = Self.root(["@Instantiated public let host: Host"])
		try await expectOutput(of: Self.modules(feature: feature, app: [fulfiller, root]), [
			"Feature": ["Feature.swift": """
			extension Deep {
			    @frozen public enum SafeDIScope_Service {
			        case service(service_Values)

			        public struct service_Values {}
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
			        let service: any Service = __safeDI_serviceBuilder(.service(SafeDIScope_Service.service_Values()))
			        self.init(service: service)
			    }
			}

			extension Deep {
			    public enum __safeDI_Deep_D1509515408C937F {}
			}

			extension Host {
			    @frozen public enum SafeDIScope_Service {
			        case inner(Inner.SafeDIScope_Service)
			    }

			    @frozen public enum SafeDISendableScope_Service {
			        case inner_Sendable(Inner.SafeDISendableScope_Service)
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service, __safeDI_serviceSendableBuilder: @escaping @Sendable (SafeDISendableScope_Service) -> any Service) {
			        func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_91C828612ADD5C41.self
			            return Inner(__safeDI_serviceBuilder: { __safeDI_serviceBuilder(.inner($0)) }, __safeDI_serviceSendableBuilder: { __safeDI_serviceSendableBuilder(.inner_Sendable($0)) })
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(inner: inner)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_98800A582E48D066 {}
			}

			extension Inner {
			    @frozen public enum SafeDIScope_Service {
			        case plain(Deep.SafeDIScope_Service)
			    }

			    @frozen public enum SafeDISendableScope_Service {
			        case held(Deep.SafeDIScope_Service)
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service, __safeDI_serviceSendableBuilder: @escaping @Sendable (SafeDISendableScope_Service) -> any Service) {
			        func __safeDI_plain() -> Deep {
			            _ = Deep.__safeDI_Deep_D1509515408C937F.self
			            return Deep(__safeDI_serviceBuilder: { __safeDI_serviceBuilder(.plain($0)) })
			        }
			        let plain: Deep = __safeDI_plain()
			        @Sendable func __safeDI_held() -> Deep {
			            _ = Deep.__safeDI_Deep_D1509515408C937F.self
			            return Deep(__safeDI_serviceBuilder: { __safeDI_serviceSendableBuilder(.held($0)) })
			        }
			        let held = SendableInstantiator<Deep>(__safeDI_held)
			        self.init(plain: plain, held: held)
			    }
			}

			extension Inner {
			    public enum __safeDI_Inner_91C828612ADD5C41 {}
			}
			"""],
			"App": ["App.swift": """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_98800A582E48D066.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_serviceBuilder_Host(_ scope: Host.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case let .inner(scope): return __safeDI_serviceBuilder_Inner(scope)
			                }
			            }
			            func __safeDI_serviceBuilder_Inner(_ scope: Inner.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case let .plain(scope): return __safeDI_serviceBuilder_Deep(scope)
			                }
			            }
			            @Sendable func __safeDI_serviceBuilder_Deep(_ scope: Deep.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case .service:
			                    let service: any Service = DefaultService()
			                    return service
			                }
			            }
			            @Sendable func __safeDI_serviceSendableBuilder_Host(_ scope: Host.SafeDISendableScope_Service) -> any Service {
			                switch scope {
			                case let .inner_Sendable(scope): return __safeDI_serviceSendableBuilder_Inner(scope)
			                }
			            }
			            @Sendable func __safeDI_serviceSendableBuilder_Inner(_ scope: Inner.SafeDISendableScope_Service) -> any Service {
			                switch scope {
			                case let .held(scope): return __safeDI_serviceBuilder_Deep(scope)
			                }
			            }
			            return Host(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Host, __safeDI_serviceSendableBuilder: __safeDI_serviceSendableBuilder_Host)
			        }
			        let host: Host = __safeDI_host()
			        self.init(host: host)
			    }
			}
			"""],
		], visible: Self.modules(feature: feature + [fulfiller], app: [root]))
	}

	// MARK: 5. Staged places

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesAStagedBuilder_whenPlaceIsBuiltInsideASendableFunction() async throws {
		let feature = [
			Self.sendableService,
			Self.type("Job", ["@Instantiated public let service: any Service"], conformances: ", Sendable"),
			Self.type("Host", seam: true, ["@Instantiated public let job: SendableInstantiator<Job>"]),
		]
		let fulfiller = Self.fulfilling("DefaultService", "Service", conformances: ", Sendable")
		let root = Self.root(["@Instantiated public let host: Host"])
		try await expectOutput(of: Self.modules(feature: feature, app: [fulfiller, root]), [
			"Feature": ["Feature.swift": """
			extension Host {
			    public enum SafeDIStagedScope_Service_job_service {
			        public struct Stage1 {}

			        public struct Stage2 {}
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder_job_service: @escaping (SafeDIStagedScope_Service_job_service.Stage1) -> @Sendable (SafeDIStagedScope_Service_job_service.Stage2) -> any Service) {
			        let __safeDI_serviceBuilder_job_service_Stage2 = __safeDI_serviceBuilder_job_service(SafeDIStagedScope_Service_job_service.Stage1())
			        @Sendable func __safeDI_job() -> Job {
			            let service: any Service = __safeDI_serviceBuilder_job_service_Stage2(SafeDIStagedScope_Service_job_service.Stage2())
			            return Job(service: service)
			        }
			        let job = SendableInstantiator<Job>(__safeDI_job)
			        self.init(job: job)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_BA388D81BCFF9A39 {}
			}
			"""],
			"App": ["App.swift": """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_BA388D81BCFF9A39.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_serviceBuilder_job_service(_ scope: Host.SafeDIStagedScope_Service_job_service.Stage1) -> @Sendable (Host.SafeDIStagedScope_Service_job_service.Stage2) -> any Service {
			                @Sendable func __safeDI_serviceBuilder_job_service_Stage2(_ scope: Host.SafeDIStagedScope_Service_job_service.Stage2) -> any Service {
			                    let service: any Service = DefaultService()
			                    return service
			                }
			                return __safeDI_serviceBuilder_job_service_Stage2
			            }
			            return Host(__safeDI_serviceBuilder_job_service: __safeDI_serviceBuilder_job_service)
			        }
			        let host: Host = __safeDI_host()
			        self.init(host: host)
			    }
			}
			"""],
		], visible: Self.modules(feature: feature + [fulfiller], app: [root]), probes: [DifferentialValueProbe("Root().host.job.instantiate()")])
	}

	@Test(arguments: [
		("@Instantiated public let inner: Inner", "plain"),
		("@Instantiated public let held: SendableInstantiator<Inner>", "sendable"),
		("@Instantiated public let inner: Inner\", \"@Instantiated public let held: SendableInstantiator<Inner>", "both"),
	])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesAStagedBuilderUp_whenAPlaceOfAnInnerSeamIsStaged(declaration: String, route: String) async throws {
		let declarations = declaration.components(separatedBy: "\", \"")
		let feature = [
			Self.sendableService,
			Self.type("Job", ["@Instantiated public let service: any Service"], conformances: ", Sendable"),
			Self.type("Inner", seam: true, ["@Instantiated public let job: SendableInstantiator<Job>"], conformances: ", Sendable"),
			Self.type("Host", seam: true, declarations),
		]
		let fulfiller = Self.fulfilling("DefaultService", "Service", conformances: ", Sendable")
		let root = Self.root(["@Instantiated public let host: Host"])
		let output = try await compiledOutput(of: Self.modules(feature: feature, app: [fulfiller, root]))
		let generated = try #require(output.modules["Feature"]?.generatedFiles["Feature.swift"])
		// Its first stage is `@Sendable` when any route presents it from inside a `@Sendable` function.
		#expect(generated.contains("serviceBuilder_Inner_job_service: @escaping \(route == "plain" ? "" : "@Sendable ")(Inner.SafeDIStagedScope_Service_job_service.Stage1) -> @Sendable (Inner.SafeDIStagedScope_Service_job_service.Stage2) -> any Service"), "\(generated)")
		try await expectDifferentialValuesMatch(output, feature: feature, fulfillers: [fulfiller], root: root)
	}

	/// Expects the values built for `Root()` to equal those of the graph with `fulfillers` in `Feature`.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectDifferentialValuesMatch(_ output: MultiModuleTestOutput, feature: [String], fulfillers: [String], root: String, sourceLocation: SourceLocation = #_sourceLocation) async throws {
		guard compileVerificationIsEnabled else { return }
		let visible = Self.modules(feature: feature + fulfillers, app: [root])
		let visibleOutput = try await executeSafeDIToolMultiModuleTest(modules: visible, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		try await expectDifferentialValuesAgree(
			feature: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: output, modules: Self.modules(feature: feature, app: fulfillers + [root])),
			knownRight: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: visibleOutput, modules: visible),
			probes: [DifferentialValueProbe("Root()")],
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}

	// MARK: 6. Cycles

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_marksEachCaseOfTheCycleIndirect_whenTwoSeamsReachEachOther() async throws {
		let feature = [
			Self.service,
			Self.type("A", seam: true, ["@Instantiated public let service: any Service", "@Instantiated public let bBuilder: Instantiator<B>"]),
			Self.type("B", seam: true, ["@Instantiated public let aBuilder: Instantiator<A>"]),
		]
		let fulfiller = Self.fulfilling("DefaultService", "Service")
		let root = Self.root(["@Instantiated public let a: A"])
		try await expectOutput(of: Self.modules(feature: feature, app: [fulfiller, root]), [
			"Feature": ["Feature.swift": """
			extension A {
			    @frozen public enum SafeDIScope_Service {
			        indirect case bBuilder(B.SafeDIScope_Service)
			        case service(service_Values)

			        public struct service_Values {
			            public let bBuilder: Instantiator<B>
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
			        func __safeDI_bBuilder() -> B {
			            _ = B.__safeDI_B_35DA1361808F923C.self
			            return B(__safeDI_serviceBuilder: { __safeDI_serviceBuilder(.bBuilder($0)) })
			        }
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        let service: any Service = __safeDI_serviceBuilder(.service(SafeDIScope_Service.service_Values(bBuilder: bBuilder)))
			        self.init(service: service, bBuilder: bBuilder)
			    }
			}

			extension A {
			    public enum __safeDI_A_35DA1361808F923C {}
			}

			extension B {
			    @frozen public enum SafeDIScope_Service {
			        indirect case aBuilder(A.SafeDIScope_Service)
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
			        func __safeDI_aBuilder() -> A {
			            _ = A.__safeDI_A_35DA1361808F923C.self
			            return A(__safeDI_serviceBuilder: { __safeDI_serviceBuilder(.aBuilder($0)) })
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			        self.init(aBuilder: aBuilder)
			    }
			}

			extension B {
			    public enum __safeDI_B_35DA1361808F923C {}
			}
			"""],
			"App": ["App.swift": """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_a() -> A {
			            _ = A.__safeDI_A_35DA1361808F923C.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_serviceBuilder_A(_ scope: A.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case let .bBuilder(scope): return __safeDI_serviceBuilder_B(scope)
			                case .service:
			                    let service: any Service = DefaultService()
			                    return service
			                }
			            }
			            func __safeDI_serviceBuilder_B(_ scope: B.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case let .aBuilder(scope): return __safeDI_serviceBuilder_A(scope)
			                }
			            }
			            return A(__safeDI_serviceBuilder: __safeDI_serviceBuilder_A)
			        }
			        let a: A = __safeDI_a()
			        self.init(a: a)
			    }
			}
			"""],
		], visible: Self.modules(feature: feature + [fulfiller], app: [root]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_marksTheSendableComponentIndirect_whenACycleHasASendableEdge() async throws {
		let feature = [
			Self.sendableService,
			Self.type("A", seam: true, ["@Instantiated public let service: any Service", "@Instantiated public let bBuilder: Instantiator<B>"], conformances: ", @unchecked Sendable"),
			Self.type("B", seam: true, ["@Instantiated public let aBuilder: SendableInstantiator<A>"], conformances: ", @unchecked Sendable"),
		]
		let fulfiller = Self.fulfilling("DefaultService", "Service", conformances: ", Sendable")
		let root = Self.root(["@Instantiated public let a: A"])
		try await expectOutput(of: Self.modules(feature: feature, app: [fulfiller, root]), [
			"Feature": ["Feature.swift": """
			extension A {
			    @frozen public enum SafeDIScope_Service {
			        case service(service_Values)

			        public struct service_Values {
			            public let bBuilder: Instantiator<B>
			        }
			    }

			    @frozen public enum SafeDISendableScope_Service {
			        indirect case bBuilder_Sendable(B.SafeDISendableScope_Service)
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service, __safeDI_serviceSendableBuilder: @escaping @Sendable (SafeDISendableScope_Service) -> any Service) {
			        func __safeDI_bBuilder() -> B {
			            _ = B.__safeDI_B_B7E40983965734C6.self
			            return B(__safeDI_serviceSendableBuilder: { __safeDI_serviceSendableBuilder(.bBuilder_Sendable($0)) })
			        }
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        let service: any Service = __safeDI_serviceBuilder(.service(SafeDIScope_Service.service_Values(bBuilder: bBuilder)))
			        self.init(service: service, bBuilder: bBuilder)
			    }
			}

			extension A {
			    public enum __safeDI_A_106E557EBC4D65C3 {}
			}

			extension B {
			    @frozen public enum SafeDISendableScope_Service {
			        case aBuilder(A.SafeDIScope_Service)
			        indirect case aBuilder_Sendable(A.SafeDISendableScope_Service)
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_serviceSendableBuilder: @escaping @Sendable (SafeDISendableScope_Service) -> any Service) {
			        @Sendable func __safeDI_aBuilder() -> A {
			            _ = A.__safeDI_A_106E557EBC4D65C3.self
			            return A(__safeDI_serviceBuilder: { __safeDI_serviceSendableBuilder(.aBuilder($0)) }, __safeDI_serviceSendableBuilder: { __safeDI_serviceSendableBuilder(.aBuilder_Sendable($0)) })
			        }
			        let aBuilder = SendableInstantiator<A>(__safeDI_aBuilder)
			        self.init(aBuilder: aBuilder)
			    }
			}

			extension B {
			    public enum __safeDI_B_B7E40983965734C6 {}
			}
			"""],
			"App": ["App.swift": """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_a() -> A {
			            _ = A.__safeDI_A_106E557EBC4D65C3.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            @Sendable func __safeDI_serviceBuilder_A(_ scope: A.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case .service:
			                    let service: any Service = DefaultService()
			                    return service
			                }
			            }
			            @Sendable func __safeDI_serviceSendableBuilder_A(_ scope: A.SafeDISendableScope_Service) -> any Service {
			                switch scope {
			                case let .bBuilder_Sendable(scope): return __safeDI_serviceSendableBuilder_B(scope)
			                }
			            }
			            @Sendable func __safeDI_serviceSendableBuilder_B(_ scope: B.SafeDISendableScope_Service) -> any Service {
			                switch scope {
			                case let .aBuilder(scope): return __safeDI_serviceBuilder_A(scope)
			                case let .aBuilder_Sendable(scope): return __safeDI_serviceSendableBuilder_A(scope)
			                }
			            }
			            return A(__safeDI_serviceBuilder: __safeDI_serviceBuilder_A, __safeDI_serviceSendableBuilder: __safeDI_serviceSendableBuilder_A)
			        }
			        let a: A = __safeDI_a()
			        self.init(a: a)
			    }
			}
			"""],
		], visible: Self.modules(feature: feature + [fulfiller], app: [root]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_holdsItsOwnEnumIndirectly_whenASeamReentersItself() async throws {
		let feature = [
			Self.service,
			Self.type("S", seam: true, ["@Instantiated public let service: any Service", "@Instantiated public let nextBuilder: Instantiator<S>"]),
		]
		let fulfiller = Self.fulfilling("DefaultService", "Service")
		let root = Self.root(["@Instantiated public let s: S"])
		try await expectOutput(of: Self.modules(feature: feature, app: [fulfiller, root]), [
			"Feature": ["Feature.swift": """
			extension S {
			    @frozen public enum SafeDIScope_Service {
			        indirect case nextBuilder(S.SafeDIScope_Service)
			        case service(service_Values)

			        public struct service_Values {
			            public let nextBuilder: Instantiator<S>
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
			        func __safeDI_nextBuilder() -> S {
			            _ = S.__safeDI_S_4FB6E221299F9411.self
			            return S(__safeDI_serviceBuilder: { __safeDI_serviceBuilder(.nextBuilder($0)) })
			        }
			        let nextBuilder = Instantiator<S>(__safeDI_nextBuilder)
			        let service: any Service = __safeDI_serviceBuilder(.service(SafeDIScope_Service.service_Values(nextBuilder: nextBuilder)))
			        self.init(service: service, nextBuilder: nextBuilder)
			    }
			}

			extension S {
			    public enum __safeDI_S_4FB6E221299F9411 {}
			}
			"""],
			"App": ["App.swift": """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_s() -> S {
			            _ = S.__safeDI_S_4FB6E221299F9411.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_serviceBuilder_S(_ scope: S.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case let .nextBuilder(scope): return __safeDI_serviceBuilder_S(scope)
			                case .service:
			                    let service: any Service = DefaultService()
			                    return service
			                }
			            }
			            return S(__safeDI_serviceBuilder: __safeDI_serviceBuilder_S)
			        }
			        let s: S = __safeDI_s()
			        self.init(s: s)
			    }
			}
			"""],
		], visible: Self.modules(feature: feature + [fulfiller], app: [root]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_marksOnlyCasesOfTheCycleIndirect_whenAThirdSeamHangsOffIt() async throws {
		let feature = [
			Self.service,
			Self.type("C", seam: true, ["@Instantiated public let service: any Service"]),
			Self.type("A", seam: true, ["@Instantiated public let bBuilder: Instantiator<B>", "@Instantiated public let c: C"]),
			Self.type("B", seam: true, ["@Instantiated public let aBuilder: Instantiator<A>"]),
		]
		let output = try await compiledOutput(of: [ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature)])
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension A {
		    @frozen public enum SafeDIScope_Service {
		        indirect case bBuilder(B.SafeDIScope_Service)
		        case c(C.SafeDIScope_Service)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
		        func __safeDI_bBuilder() -> B {
		            _ = B.__safeDI_B_B176B189487E374D.self
		            return B(__safeDI_serviceBuilder: { __safeDI_serviceBuilder(.bBuilder($0)) })
		        }
		        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		        func __safeDI_c() -> C {
		            _ = C.__safeDI_C_FCB1E1A0B21B374C.self
		            return C(__safeDI_serviceBuilder: { __safeDI_serviceBuilder(.c($0)) })
		        }
		        let c: C = __safeDI_c()
		        self.init(bBuilder: bBuilder, c: c)
		    }
		}

		extension A {
		    public enum __safeDI_A_B176B189487E374D {}
		}

		extension B {
		    @frozen public enum SafeDIScope_Service {
		        indirect case aBuilder(A.SafeDIScope_Service)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
		        func __safeDI_aBuilder() -> A {
		            _ = A.__safeDI_A_B176B189487E374D.self
		            return A(__safeDI_serviceBuilder: { __safeDI_serviceBuilder(.aBuilder($0)) })
		        }
		        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		        self.init(aBuilder: aBuilder)
		    }
		}

		extension B {
		    public enum __safeDI_B_B176B189487E374D {}
		}

		extension C {
		    @frozen public enum SafeDIScope_Service {
		        case service(service_Values)

		        public struct service_Values {}
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
		        let service: any Service = __safeDI_serviceBuilder(.service(SafeDIScope_Service.service_Values()))
		        self.init(service: service)
		    }
		}

		extension C {
		    public enum __safeDI_C_FCB1E1A0B21B374C {}
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesNoBuilder_whenCycleOfSeamsHasNoPlace() async throws {
		let feature = [
			Self.type("A", seam: true, ["@Instantiated public let bBuilder: Instantiator<B>"]),
			Self.type("B", seam: true, ["@Instantiated public let aBuilder: Instantiator<A>"]),
		]
		let output = try await compiledOutput(of: [ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature)])
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension A {
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public init() {
		        func __safeDI_bBuilder() -> B {
		            _ = B.__safeDI_B_CBF29CE484222325.self
		            return B()
		        }
		        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		        self.init(bBuilder: bBuilder)
		    }
		}

		extension A {
		    public enum __safeDI_A_CBF29CE484222325 {}
		}

		extension B {
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public init() {
		        func __safeDI_aBuilder() -> A {
		            _ = A.__safeDI_A_CBF29CE484222325.self
		            return A()
		        }
		        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		        self.init(aBuilder: aBuilder)
		    }
		}

		extension B {
		    public enum __safeDI_B_CBF29CE484222325 {}
		}
		"""])
	}

	// MARK: 7. Forwarded values

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_carriesForwardedValueInTheCase_whenInstantiatorForwardsSeveralValues() async throws {
		let feature = [
			"public protocol Gadget {}",
			"public struct Name: Sendable { public init() {} }",
			Self.type("Host", seam: true, [
				#"@Instantiated(fulfilledByType: "NamedGadget", erasedToConcreteExistential: true) public let maker: ErasedInstantiator<(count: Int, name: Name), AnyGadget>"#,
			]),
			"""
			public struct AnyGadget: Gadget {
			    public init(_ base: any Gadget) {
			        self.base = base
			    }

			    let base: any Gadget
			}
			""",
		]
		let fulfiller = """
		@Instantiable
		public struct NamedGadget: Instantiable, Gadget {
		    public init(name: Name, count: Int) {
		        self.name = name
		        self.count = count
		    }

		    @Forwarded let name: Name
		    @Forwarded let count: Int
		}
		"""
		try await expectOutput(of: Self.modules(feature: feature, app: [fulfiller, Self.root(["@Instantiated public let host: Host"])]), [
			"Feature": ["Feature.swift": """
			extension Host {
			    @frozen public enum SafeDIScope_NamedGadget {
			        case maker(maker_Values, (count: Int, name: Name))

			        public struct maker_Values {}
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_namedGadgetBuilder: @escaping (SafeDIScope_NamedGadget) -> AnyGadget) {
			        let maker = ErasedInstantiator<(count: Int, name: Name), AnyGadget> {
			            __safeDI_namedGadgetBuilder(.maker(SafeDIScope_NamedGadget.maker_Values(), $0))
			        }
			        self.init(maker: maker)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_0A1C69DAC4362311 {}
			}
			"""],
			"App": ["App.swift": """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_0A1C69DAC4362311.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_namedGadgetBuilder_Host(_ scope: Host.SafeDIScope_NamedGadget) -> AnyGadget {
			                switch scope {
			                case let .maker(_, __safeDI_forwarded):
			                    func __safeDI_maker(count: Int, name: Name) -> NamedGadget {
			                        NamedGadget(name: name, count: count)
			                    }
			                    return AnyGadget(__safeDI_maker(count: __safeDI_forwarded.count, name: __safeDI_forwarded.name))
			                }
			            }
			            return Host(__safeDI_namedGadgetBuilder: __safeDI_namedGadgetBuilder_Host)
			        }
			        let host: Host = __safeDI_host()
			        self.init(host: host)
			    }
			}
			"""],
		])
	}

	// MARK: 8. Names

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsCases_whenLabelsAreKeywordsOrRawIdentifiers() async throws {
		let feature = [
			Self.service,
			Self.type("Host", seam: true, ["@Instantiated public let `default`: any Service", "@Instantiated public let `my leaf`: any Service"]),
		]
		let fulfiller = Self.fulfilling("DefaultService", "Service")
		let root = Self.root(["@Instantiated public let host: Host"])
		try await expectOutput(of: Self.modules(feature: feature, app: [fulfiller, root]), [
			"Feature": ["Feature.swift": """
			extension Host {
			    @frozen public enum SafeDIScope_Service {
			        case `default`(default_Values)
			        case `my leaf`(`my leaf_Values`)

			        public struct default_Values {}

			        public struct `my leaf_Values` {
			            public let `default`: any Service
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
			        let `default`: any Service = __safeDI_serviceBuilder(.`default`(SafeDIScope_Service.default_Values()))
			        let `my leaf`: any Service = __safeDI_serviceBuilder(.`my leaf`(SafeDIScope_Service.`my leaf_Values`(default: `default`)))
			        self.init(default: `default`, `my leaf`: `my leaf`)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_C58B164E2C2F9752 {}
			}
			"""],
		])
	}

	@Test(arguments: ["Inner", "Outer", "Stage1"])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesStageStructsApart_whenAFieldIsTypedLikeOne(typeName: String) async throws {
		let feature = [
			Self.sendableService,
			Self.type(typeName, [], conformances: ", Sendable"),
			Self.type("Job", ["@Instantiated public let service: any Service"], conformances: ", Sendable"),
			Self.type("Host", seam: true, ["@Received public let field: \(typeName)", "@Instantiated public let job: SendableInstantiator<Job>"]),
		]
		let fulfiller = Self.fulfilling("DefaultService", "Service", conformances: ", Sendable")
		_ = try await compiledOutput(of: Self.modules(feature: feature, app: [fulfiller, Self.root(["@Instantiated public let field: \(typeName)", "@Instantiated public let host: Host"])]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_lowersLeadingCapitalsKeepingTheLastBeforeALowercaseLetter_whenTypeIsAnAcronym() async throws {
		let feature = [
			"public protocol URLLoader {}",
			"public protocol KP {}",
			Self.type("Host", seam: true, ["@Instantiated public let loader: any URLLoader", "@Instantiated public let kp: any KP"]),
		]
		let output = try await compiledOutput(of: [ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature)])
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen public enum SafeDIScope_KP {
		        case kp(kp_Values)

		        public struct kp_Values {
		            public let loader: any URLLoader
		        }
		    }

		    @frozen public enum SafeDIScope_URLLoader {
		        case loader(loader_Values)

		        public struct loader_Values {}
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_kpBuilder: @escaping (SafeDIScope_KP) -> any KP, __safeDI_urlLoaderBuilder: @escaping (SafeDIScope_URLLoader) -> any URLLoader) {
		        let loader: any URLLoader = __safeDI_urlLoaderBuilder(.loader(SafeDIScope_URLLoader.loader_Values()))
		        let kp: any KP = __safeDI_kpBuilder(.kp(SafeDIScope_KP.kp_Values(loader: loader)))
		        self.init(loader: loader, kp: kp)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_9992B7F4A9148AC7 {}
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsAParametersLabel_whenABuilderLabelEqualsIt() async throws {
		let feature = [
			Self.service,
			Self.type("Host", seam: true, ["@Received public let serviceBuilder: Int", "@Instantiated public let service: any Service"]),
		]
		let output = try await compiledOutput(of: [ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature)])
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen public enum SafeDIScope_Service_Service {
		        case service(service_Values)

		        public struct service_Values {
		            public let serviceBuilder: Int
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_serviceBuilder serviceBuilder: Int, __safeDI_service_ServiceBuilder: @escaping (SafeDIScope_Service_Service) -> any Service) {
		        let service: any Service = __safeDI_service_ServiceBuilder(.service(SafeDIScope_Service_Service.service_Values(serviceBuilder: serviceBuilder)))
		        self.init(serviceBuilder: serviceBuilder, service: service)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_59649173957AB809 {}
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesAPayloadStructApart_whenAnotherCaseOfItsEnumIsNamedLikeIt() async throws {
		let feature = [
			Self.service,
			Self.type("Host", seam: true, ["@Instantiated public let service: any Service", "@Instantiated public let service_Values: any Service"]),
		]
		let output = try await compiledOutput(of: [ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature)])
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen public enum SafeDIScope_Service {
		        case service(service_Values_)
		        case service_Values(service_Values_Values)

		        public struct service_Values_ {}

		        public struct service_Values_Values {
		            public let service: any Service
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
		        let service: any Service = __safeDI_serviceBuilder(.service(SafeDIScope_Service.service_Values_()))
		        let service_Values: any Service = __safeDI_serviceBuilder(.service_Values(SafeDIScope_Service.service_Values_Values(service: service)))
		        self.init(service: service, service_Values: service_Values)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_15D2DF35FE672BE8 {}
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesStagedBuildersAndScopeTypesApart_whenTwoStagedPlacesJoinTheirPathsToOneName() async throws {
		// `job_service` and `job`'s `service` are staged places of one hole type whose paths join to one case name.
		let feature = [
			Self.sendableService,
			Self.type("Job", ["@Instantiated public let service: any Service"], conformances: ", Sendable"),
			Self.type("Host", seam: true, ["@Instantiated public let job: SendableInstantiator<Job>", "@Instantiated public let job_service: SendableLazilyInstantiated<any Service>"]),
		]
		let output = try await compiledOutput(of: Self.modules(feature: feature, app: [Self.fulfilling("DefaultService", "Service", conformances: ", Sendable"), Self.root(["@Instantiated public let host: Host"])]))
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    public enum SafeDIStagedScope_Service_job_service {
		        public struct Stage1 {}

		        public struct Stage2 {}
		    }

		    public enum SafeDIStagedScope_Service_job_service_ {
		        public struct Stage1 {
		            public let job: SendableInstantiator<Job>
		        }

		        public struct Stage2 {}
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_serviceBuilder_job_service: @escaping (SafeDIStagedScope_Service_job_service.Stage1) -> @Sendable (SafeDIStagedScope_Service_job_service.Stage2) -> any Service, __safeDI_serviceBuilder_job_service_: @escaping (SafeDIStagedScope_Service_job_service_.Stage1) -> @Sendable (SafeDIStagedScope_Service_job_service_.Stage2) -> any Service) {
		        let __safeDI_serviceBuilder_job_service_Stage2 = __safeDI_serviceBuilder_job_service(SafeDIStagedScope_Service_job_service.Stage1())
		        @Sendable func __safeDI_job() -> Job {
		            let service: any Service = __safeDI_serviceBuilder_job_service_Stage2(SafeDIStagedScope_Service_job_service.Stage2())
		            return Job(service: service)
		        }
		        let job = SendableInstantiator<Job>(__safeDI_job)
		        let __safeDI_serviceBuilder_job_service__Stage2 = __safeDI_serviceBuilder_job_service_(SafeDIStagedScope_Service_job_service_.Stage1(job: job))
		        @Sendable func __safeDI_job_service() -> any Service {
		            __safeDI_serviceBuilder_job_service__Stage2(SafeDIStagedScope_Service_job_service_.Stage2())
		        }
		        let job_service = SendableLazilyInstantiated<any Service>(__safeDI_job_service)
		        self.init(job: job, job_service: job_service)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_E1D01980E2E34812 {}
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesHoleTypesApartByTheirTypes_whenStemsStillCollideWithTheReturnedTypesStem() async throws {
		// `Outer.Thing` and `Outer_Thing` are spelled as one identifier, as are the types their builders return.
		let feature = [
			"public enum Outer {\n    public struct Thing {}\n}",
			"public struct Outer_Thing {}",
			Self.type("Host", seam: true, ["@Instantiated public let nested: Outer.Thing", "@Instantiated public let joined: Outer_Thing"]),
		]
		let output = try await compiledOutput(of: [ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature)])
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen public enum SafeDIScope_Outer_Thing_Outer_Thing_Outer_Thing {
		        case nested(nested_Values)

		        public struct nested_Values {}
		    }

		    @frozen public enum SafeDIScope_Outer_Thing_Outer_Thing_Outer_Thing_ {
		        case joined(joined_Values)

		        public struct joined_Values {
		            public let nested: Outer.Thing
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_outer_Thing_Outer_Thing_Outer_ThingBuilder: @escaping (SafeDIScope_Outer_Thing_Outer_Thing_Outer_Thing) -> Outer.Thing, __safeDI_outer_Thing_Outer_Thing_Outer_Thing_Builder: @escaping (SafeDIScope_Outer_Thing_Outer_Thing_Outer_Thing_) -> Outer_Thing) {
		        let nested: Outer.Thing = __safeDI_outer_Thing_Outer_Thing_Outer_ThingBuilder(.nested(SafeDIScope_Outer_Thing_Outer_Thing_Outer_Thing.nested_Values()))
		        let joined: Outer_Thing = __safeDI_outer_Thing_Outer_Thing_Outer_Thing_Builder(.joined(SafeDIScope_Outer_Thing_Outer_Thing_Outer_Thing_.joined_Values(nested: nested)))
		        self.init(nested: nested, joined: joined)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_A8F2A94BBDC1E9C2 {}
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_appendsUnderscoresToAStem_whenItsLabelStillEqualsAParametersAfterNamingByTypes() async throws {
		// As the previous test, with a parameter labeled as the builder of `Outer.Thing` would be once named by its types.
		let feature = [
			"public enum Outer {\n    public struct Thing {}\n}",
			"public struct Outer_Thing {}",
			Self.type("Host", seam: true, [
				"@Received public let outer_Thing_Outer_Thing_Outer_ThingBuilder: Int",
				"@Instantiated public let nested: Outer.Thing",
				"@Instantiated public let joined: Outer_Thing",
			]),
		]
		let output = try await compiledOutput(of: [ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature)])
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen public enum SafeDIScope_Outer_Thing_Outer_Thing_Outer_Thing_ {
		        case joined(joined_Values)

		        public struct joined_Values {
		            public let outer_Thing_Outer_Thing_Outer_ThingBuilder: Int
		            public let nested: Outer.Thing
		        }
		    }

		    @frozen public enum SafeDIScope_Outer_Thing_Outer_Thing_Outer_Thing__ {
		        case nested(nested_Values)

		        public struct nested_Values {
		            public let outer_Thing_Outer_Thing_Outer_ThingBuilder: Int
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_outer_Thing_Outer_Thing_Outer_ThingBuilder outer_Thing_Outer_Thing_Outer_ThingBuilder: Int, __safeDI_outer_Thing_Outer_Thing_Outer_Thing_Builder: @escaping (SafeDIScope_Outer_Thing_Outer_Thing_Outer_Thing_) -> Outer_Thing, __safeDI_outer_Thing_Outer_Thing_Outer_Thing__Builder: @escaping (SafeDIScope_Outer_Thing_Outer_Thing_Outer_Thing__) -> Outer.Thing) {
		        let nested: Outer.Thing = __safeDI_outer_Thing_Outer_Thing_Outer_Thing__Builder(.nested(SafeDIScope_Outer_Thing_Outer_Thing_Outer_Thing__.nested_Values(outer_Thing_Outer_Thing_Outer_ThingBuilder: outer_Thing_Outer_Thing_Outer_ThingBuilder)))
		        let joined: Outer_Thing = __safeDI_outer_Thing_Outer_Thing_Outer_Thing_Builder(.joined(SafeDIScope_Outer_Thing_Outer_Thing_Outer_Thing_.joined_Values(outer_Thing_Outer_Thing_Outer_ThingBuilder: outer_Thing_Outer_Thing_Outer_ThingBuilder, nested: nested)))
		        self.init(outer_Thing_Outer_Thing_Outer_ThingBuilder: outer_Thing_Outer_Thing_Outer_ThingBuilder, nested: nested, joined: joined)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_6D0C4CC04F02A70F {}
		}
		"""])
	}

	// MARK: B. One allocation of names per generated scope

	@Test(arguments: [
		["inner", "innerJob", "staged"], ["inner", "staged", "innerJob"], ["innerJob", "inner", "staged"], ["innerJob", "staged", "inner"], ["staged", "inner", "innerJob"], ["staged", "innerJob", "inner"],
	])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesGeneratedFunctionsApart_whenADispatcherOrAStageBindingEqualsAFillsNameInAnyDeclarationOrder(order: [String]) async throws {
		// Swift overloads two local functions of one name by their parameter types, so compiling shows nothing: each name
		// the filler's body declares must be declared once.
		let output = try await compiledOutput(of: Self.collidingNamesModules(order: order))
		let generated = try #require(output.modules["App"]?.generatedFiles["App.swift"])
		var declaredNames = Set<String>()
		var namesDeclaredAgain = [String]()
		for line in generated.components(separatedBy: "\n") {
			guard let range = line.range(of: "func ") else { continue }
			let name = String(line[range.upperBound...].prefix { $0 != "(" })
			if !declaredNames.insert(name).inserted {
				namesDeclaredAgain.append(name)
			}
		}
		#expect(namesDeclaredAgain == [])
		#expect(declaredNames.count == 9)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesGeneratedFunctionsApart_whenADispatcherOrAStageBindingEqualsAFillsName() async throws {
		// `Inner`'s place `job` fills as `__safeDI_serviceBuilder_Inner_job`, which is also the dispatcher of `Inner_job`'s enum;
		// `Staged`'s place `pod_service_Stage2` fills as the name the second stage of `Staged`'s staged fill binds. The fills
		// are claimed first, in the order the builders reach them, so the dispatcher and the staged fill are renamed.
		try await expectOutput(of: Self.collidingNamesModules(order: ["inner", "innerJob", "staged"]), [
			"App": ["App.swift": """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_D0CC0D12F26D6118.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_serviceBuilder_Inner_job(_ scope_: Inner.SafeDIScope_Service.job_Values) -> any Service {
			                let job: any Service = DefaultService()
			                return job
			            }
			            func __safeDI_serviceBuilder_Staged_pod_service_Stage2(_ scope_: Staged.SafeDIScope_Service.pod_service_Stage2_Values) -> any Service {
			                let pod_service_Stage2: any Service = DefaultService()
			                return pod_service_Stage2
			            }
			            func __safeDI_serviceBuilder_Staged_pod_service_(_ scope_: Staged.SafeDIStagedScope_Service_pod_service.Stage1) -> @Sendable (Staged.SafeDIStagedScope_Service_pod_service.Stage2) -> any Service {
			                @Sendable func __safeDI_serviceBuilder_Staged_pod_service__Stage2(_ scope_: Staged.SafeDIStagedScope_Service_pod_service.Stage2) -> any Service {
			                    let service: any Service = DefaultService()
			                    return service
			                }
			                return __safeDI_serviceBuilder_Staged_pod_service__Stage2
			            }
			            func __safeDI_serviceBuilder_Host(_ scope: Host.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case let .inner(scope): return __safeDI_serviceBuilder_Inner(scope)
			                case let .innerJob(scope): return __safeDI_serviceBuilder_Inner_job_(scope)
			                case let .staged(scope): return __safeDI_serviceBuilder_Staged(scope)
			                }
			            }
			            func __safeDI_serviceBuilder_Inner(_ scope: Inner.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case let .job(scope): return __safeDI_serviceBuilder_Inner_job(scope)
			                }
			            }
			            func __safeDI_serviceBuilder_Inner_job_(_ scope: Inner_job.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case .service:
			                    let service: any Service = DefaultService()
			                    return service
			                }
			            }
			            func __safeDI_serviceBuilder_Staged(_ scope: Staged.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case let .pod_service_Stage2(scope): return __safeDI_serviceBuilder_Staged_pod_service_Stage2(scope)
			                }
			            }
			            return Host(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Host, __safeDI_serviceBuilder_Staged_pod_service: __safeDI_serviceBuilder_Staged_pod_service_)
			        }
			        let host: Host = __safeDI_host()
			        self.init(host: host)
			    }
			}
			"""],
		])
	}

	/// `Host` calls `Inner`, `Inner_job` and `Staged` in `order`, and `App` fills every place: `Inner`'s fill of `job` and
	/// `Inner_job`'s dispatcher share a name, as do `Staged`'s fill of `pod_service_Stage2` and its staged fill's second stage.
	/// The places of `Inner` and `Staged` carry a field labeled `scope`, which names their fills' parameters apart and so
	/// keeps each a function of its own rather than the body of the dispatcher case that calls it.
	private static func collidingNamesModules(order: [String]) -> [ModuleFixture] {
		let declarationsByKey = [
			"inner": "@Instantiated public let inner: Inner",
			"innerJob": "@Instantiated public let innerJob: Inner_job",
			"staged": "@Instantiated public let staged: Staged",
		]
		let feature = [
			Self.sendableService,
			Self.type("Token", conformances: ", Sendable"),
			Self.type("Job", ["@Instantiated public let service: any Service"], conformances: ", Sendable"),
			Self.type("Inner", seam: true, ["@Instantiated public let scope: Token", "@Instantiated public let job: any Service"]),
			Self.type("Inner_job", seam: true, ["@Instantiated public let service: any Service"]),
			Self.type("Staged", seam: true, ["@Instantiated public let scope: Token", "@Instantiated public let pod: SendableInstantiator<Job>", "@Instantiated public let pod_service_Stage2: any Service"]),
			Self.type("Host", seam: true, order.compactMap { declarationsByKey[$0] }),
		]
		return Self.modules(feature: feature, app: [Self.fulfilling("DefaultService", "Service", conformances: ", Sendable"), Self.root(["@Instantiated public let host: Host"])])
	}

	// MARK: 9. Access

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsTierOmitsBuilder_namingTheInnerSeam_whenPublicSeamHoldsAPackageSeamsEnum() async {
		// `Deep` is `public` and holds the place, so only the `package` seam between it and `Host`, whose enum `Host`'s holds,
		// narrows `Host`'s builder.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Host.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Host`: its generated `public` initializer, which `Host`'s `public` access requires, cannot take `serviceBuilder: @escaping (SafeDIScope_Service) -> any Service`, whose scope holds the builders of `Inner`, a seam visible only at `package` access. `Inner`'s own `@Instantiable` declaration is `package`. Declare `Host` at `package` access, or make `Inner` `public`.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					Self.service,
					Self.type("Deep", seam: true, ["@Instantiated public let service: any Service"]),
					"""
					@Instantiable(generateDependencyTree: true)
					package struct Inner: Instantiable {
					    package init(deep: Deep) {
					        self.deep = deep
					    }

					    @Instantiated package let deep: Deep
					}
					""",
					Self.type("Host", seam: true, ["@Instantiated public let inner: Inner"]),
				])],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_compilesPublicEnumInsidePackageSeam_whenPackageSeamHoldsAPackageSeamsEnum() async throws {
		let package = { (name: String, declaration: String) -> String in
			"""
			@Instantiable(generateDependencyTree: true)
			package struct \(name): Instantiable {
			    package init(\(declaration)) {
			        self.\(declaration.prefix { $0 != ":" }) = \(declaration.prefix { $0 != ":" })
			    }

			    @Instantiated package let \(declaration)
			}
			"""
		}
		let output = try await compiledOutput(of: [ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
			Self.service,
			package("Inner", "service: any Service"),
			package("Host", "inner: Inner"),
		])])
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen public enum SafeDIScope_Service {
		        case inner(Inner.SafeDIScope_Service)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    package init(__safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_1AA197A3D8ED5990.self
		            return Inner(__safeDI_serviceBuilder: { __safeDI_serviceBuilder(.inner($0)) })
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(inner: inner)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_4EF4163FC58A74E6 {}
		}

		extension Inner {
		    @frozen public enum SafeDIScope_Service {
		        case service(service_Values)

		        public struct service_Values {}
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    package init(__safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
		        let service: any Service = __safeDI_serviceBuilder(.service(SafeDIScope_Service.service_Values()))
		        self.init(service: service)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_1AA197A3D8ED5990 {}
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsTierOmitsBuilder_whenPublicSeamsPlaceForwardsAnInternalType() async {
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Host.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Host`: its generated `public` initializer, which `Host`'s `public` access requires, cannot take `hiddenGadgetBuilder: @escaping (SafeDIScope_HiddenGadget) -> any Gadget`, the builder for `Host`'s `maker: ErasedInstantiator<Hidden, any Gadget>`, which no @Instantiable declaration that module `Feature` can see fulfills. `Hidden` is declared `internal`. Declare `Hidden` `public`; declare `Host` `internal`; make an @Instantiable declaration that fulfills `HiddenGadget` one module `Feature` reads, so `Host`'s tree builds it; or declare the dependency tree on an `internal` type that instantiates `Host`.
			\(fixtures["Feature"]!["Hidden.swift"]):1:1: note: `Hidden` is declared `internal` here.
			\(fixtures["Feature"]!["Hidden.swift"]):1:1-1:1: fixit: public\(" ")
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					"public protocol Gadget {}",
					"struct Hidden {}",
					"public struct HiddenGadget: Gadget { public init() {} }",
					#"""
					@Instantiable(generateDependencyTree: true)
					public struct Host: Instantiable {
					    public init(maker: ErasedInstantiator<Hidden, any Gadget>) {
					        self.maker = maker
					    }

					    @Instantiated(fulfilledByType: "HiddenGadget") let maker: ErasedInstantiator<Hidden, any Gadget>
					}
					"""#,
				])],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_importsInnerSeamsModuleAtTheEnumsAccess_whenModuleSpellsImportLevels() async throws {
		// `Host` names `Deep` in no `public` declaration of its own, so its file imports `Lower` internally; only the case of
		// the generated `public` enum names `Deep`'s enum, and `Service` is `Base`'s.
		let output = try await compiledOutput(of: [
			ModuleFixture(name: "Base", packageName: "Shop", swiftFileContent: [Self.service]),
			ModuleFixture(name: "Lower", packageName: "Shop", swiftFileContent: ["import Base\n\n" + Self.type("Deep", seam: true, ["@Instantiated public let service: any Service"])], dependencies: ["Base"]),
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: ["""
			public import Base
			internal import Lower

			@Instantiable(generateDependencyTree: true)
			public struct Host: Instantiable {
			    init(deep: Deep) {
			        self.deep = deep
			    }

			    @Instantiated let deep: Deep
			}
			"""], dependencies: ["Base", "Lower"]),
		])
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(Base)
		public import Base
		#endif
		#if canImport(Lower)
		public import Lower
		#endif

		extension Host {
		    @frozen public enum SafeDIScope_Service {
		        case deep(Deep.SafeDIScope_Service)
		    }

		    // SafeDI counts `Service` as `public`: no module it reads declares it narrower. If `Service` is `package` in a first-party module, run SafeDI on that module and list it among this module's SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
		        func __safeDI_deep() -> Deep {
		            _ = Deep.__safeDI_Deep_D1509515408C937F.self // If this line does not compile, compile the code SafeDI generates for module Lower into Lower: under Bazel, add Lower's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Deep(__safeDI_serviceBuilder: { __safeDI_serviceBuilder(.deep($0)) })
		        }
		        let deep: Deep = __safeDI_deep()
		        self.init(deep: deep)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_FD7FE53C0027BE07 {}
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_importsBuiltTypesModulePublicly_whenOnlyAStagedPlacesLastStageAliasNamesIt() async throws {
		// `Host`'s own file imports `Base` internally, and of the declarations `Host`'s generated file spells `public`, only
		// the alias that spells the staged place's last stage names `AnyGadget`, which `Base` declares, as its `GadgetBox`
		// records: the builder takes the alias over the forwarded `String`.
		let output = try await compiledOutput(of: [
			ModuleFixture(name: "Base", packageName: "Shop", swiftFileContent: [
				"public protocol Gadget: Sendable {}",
				"""
				public struct AnyGadget: Gadget {
				    public init(_ base: any Gadget) {
				        self.base = base
				    }

				    let base: any Gadget
				}
				""",
				Self.type("GadgetBox", ["@Forwarded public let gadget: AnyGadget"]),
			]),
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [#"""
			internal import Base

			@Instantiable(generateDependencyTree: true)
			public struct Host: Instantiable {
			    init(part: SendableErasedInstantiator<String, AnyGadget>) {
			        self.part = part
			    }

			    @Instantiated(fulfilledByType: "NamedGadget", erasedToConcreteExistential: true) let part: SendableErasedInstantiator<String, AnyGadget>
			}
			"""#], dependencies: ["Base"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				"import Base\n\n" + Self.type("NamedGadget", ["@Forwarded let name: String"], conformances: ", Gadget"),
				"import Feature\n\n" + Self.root(["@Instantiated public let host: Host"]),
			], dependencies: ["Base", "Feature"]),
		])
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(Base)
		public import Base
		#endif

		extension Host {
		    public enum SafeDIStagedScope_NamedGadget_part {
		        public struct Stage1 {}

		        public struct Stage2 {}

		        public typealias SendableLastStage<__safeDI_Forwarded> = @Sendable (Stage2, __safeDI_Forwarded) -> AnyGadget
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_namedGadgetBuilder_part: @escaping (SafeDIStagedScope_NamedGadget_part.Stage1) -> SafeDIStagedScope_NamedGadget_part.SendableLastStage<String>) {
		        let __safeDI_namedGadgetBuilder_part_Stage2 = __safeDI_namedGadgetBuilder_part(SafeDIStagedScope_NamedGadget_part.Stage1())
		        let part = SendableErasedInstantiator<String, AnyGadget> {
		            __safeDI_namedGadgetBuilder_part_Stage2(SafeDIStagedScope_NamedGadget_part.Stage2(), $0)
		        }
		        self.init(part: part)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_2B6B7835411CF665 {}
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_importsTheLowestModule_whenNoFileOfTheFillingModuleImportsIt() async throws {
		// `App`'s dispatchers name `Deep`'s enum, of module `Lower`, which no file of `App` imports.
		let output = try await compiledOutput(of: [
			ModuleFixture(name: "Base", packageName: "Shop", swiftFileContent: [Self.service]),
			ModuleFixture(name: "Lower", packageName: "Shop", swiftFileContent: ["import Base\n\n" + Self.type("Deep", seam: true, ["@Instantiated public let service: any Service"])], dependencies: ["Base"]),
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: ["import Lower\n\n" + Self.type("Host", seam: true, ["@Instantiated public let deep: Deep"])], dependencies: ["Lower"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				"import Base\n\n" + Self.fulfilling("DefaultService", "Service"),
				"import Feature\n\n" + Self.root(["@Instantiated public let host: Host"]),
			], dependencies: ["Base", "Lower", "Feature"]),
		])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Base)
		import Base
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Lower)
		import Lower
		#endif

		extension Root {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_FD7FE53C0027BE07.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_serviceBuilder_Host(_ scope: Host.SafeDIScope_Service) -> any Service {
		                switch scope {
		                case let .deep(scope): return __safeDI_serviceBuilder_Deep(scope)
		                }
		            }
		            func __safeDI_serviceBuilder_Deep(_ scope: Deep.SafeDIScope_Service) -> any Service {
		                switch scope {
		                case .service:
		                    let service: any Service = DefaultService()
		                    return service
		                }
		            }
		            return Host(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Host)
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
	}

	// MARK: 11. Dispatchers that reach fills of two seams

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesOneDispatcherInAFill_whenItReachesFillsOfTwoSeams() async throws {
		let feature = [
			Self.service,
			"public protocol Gadget {}",
			Self.type("Deep", seam: true, ["@Instantiated public let gadget: any Gadget"]),
			Self.type("Inner", seam: true, ["@Instantiated public let service: any Service", "@Instantiated public let deep: Deep"]),
			Self.type("Host", seam: true, ["@Instantiated public let inner: Inner"]),
		]
		let fulfillers = [
			Self.fulfilling("DefaultService", "Service", ["@Instantiated public let gadget: any Gadget"]),
			Self.fulfilling("DefaultGadget", "Gadget"),
		]
		let root = Self.root(["@Instantiated public let host: Host"])
		try await expectOutput(of: Self.modules(feature: feature, app: fulfillers + [root]), [
			"App": ["App.swift": """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_7F521A1E22A902B9.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_gadgetBuilder_Host(_ scope: Host.SafeDIScope_Gadget) -> any Gadget {
			                switch scope {
			                case let .inner(scope): return __safeDI_gadgetBuilder_Inner(scope)
			                }
			            }
			            func __safeDI_gadgetBuilder_Inner(_ scope: Inner.SafeDIScope_Gadget) -> any Gadget {
			                switch scope {
			                case let .deep(scope): return __safeDI_gadgetBuilder_Deep(scope)
			                }
			            }
			            func __safeDI_gadgetBuilder_Deep(_ scope: Deep.SafeDIScope_Gadget) -> any Gadget {
			                switch scope {
			                case .gadget:
			                    let gadget: any Gadget = DefaultGadget()
			                    return gadget
			                }
			            }
			            func __safeDI_serviceBuilder_Host(_ scope: Host.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case let .inner(scope): return __safeDI_serviceBuilder_Inner(scope)
			                }
			            }
			            func __safeDI_serviceBuilder_Inner(_ scope: Inner.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case .service:
			                    func __safeDI_service() -> DefaultService {
			                        let gadget: any Gadget = DefaultGadget()
			                        return DefaultService(gadget: gadget)
			                    }
			                    let service: any Service = __safeDI_service()
			                    return service
			                }
			            }
			            return Host(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Host, __safeDI_serviceBuilder: __safeDI_serviceBuilder_Host)
			        }
			        let host: Host = __safeDI_host()
			        self.init(host: host)
			    }
			}
			"""],
		], visible: Self.modules(feature: feature + fulfillers, app: [root]))
	}

	// MARK: 13. Guards

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_changesTheOuterSeamsGuard_whenAnInnerSeamGainsAPlace() async throws {
		func guardOfHost(_ innerDeclarations: [String]) async throws -> String {
			let output = try await executeSafeDIToolMultiModuleTest(
				modules: [ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					Self.service,
					Self.type("Inner", seam: true, innerDeclarations),
					Self.type("Host", seam: true, ["@Instantiated public let inner: Inner"]),
				])],
				integration: .moduleInfo,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
			let generated = try #require(output.modules["Feature"]?.generatedFiles["Feature.swift"])
			return try #require(generated.components(separatedBy: "\n").first { $0.contains("enum __safeDI_Host_") })
		}
		let onePlace = try await guardOfHost(["@Instantiated public let service: any Service"])
		let twoPlaces = try await guardOfHost(["@Instantiated public let service: any Service", "@Instantiated public let other: any Service"])
		#expect(onePlace != twoPlaces)
	}

	// MARK: 6b. Cycles settle on each seam's own enums

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_dispatchesEveryCaseOfEachEnum_whenSeamsOfOneModuleReachOneAnotherAndThemselves() async throws {
		// `Folder` and `File` re-enter themselves and each other. Each reads the other's enum from the other's own signature,
		// never from a copy a neighbor carried from an earlier pass, which would lack a case the seam's module declares.
		let feature = [
			Self.service,
			Self.type("Folder", seam: true, ["@Instantiated public let folderBuilder: Instantiator<Folder>", "@Instantiated public let fileBuilder: Instantiator<File>", "@Instantiated public let service: any Service"]),
			Self.type("File", seam: true, ["@Instantiated public let folderBuilder: Instantiator<Folder>", "@Instantiated public let fileBuilder: Instantiator<File>"]),
		]
		let fulfiller = Self.fulfilling("DefaultService", "Service")
		let root = Self.root(["@Instantiated public let folder: Folder"])
		try await expectOutput(of: Self.modules(feature: feature, app: [fulfiller, root]), [
			"App": ["App.swift": """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_folder() -> Folder {
			            _ = Folder.__safeDI_Folder_205E44AA896703D5.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_serviceBuilder_Folder(_ scope: Folder.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case let .folderBuilder(scope): return __safeDI_serviceBuilder_Folder(scope)
			                case let .fileBuilder(scope): return __safeDI_serviceBuilder_File(scope)
			                case .service:
			                    let service: any Service = DefaultService()
			                    return service
			                }
			            }
			            func __safeDI_serviceBuilder_File(_ scope: File.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case let .folderBuilder(scope): return __safeDI_serviceBuilder_Folder(scope)
			                case let .fileBuilder(scope): return __safeDI_serviceBuilder_File(scope)
			                }
			            }
			            return Folder(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Folder)
			        }
			        let folder: Folder = __safeDI_folder()
			        self.init(folder: folder)
			    }
			}
			"""],
		], visible: Self.modules(feature: feature + [fulfiller], app: [root]), probes: [DifferentialValueProbe("Root().folder.fileBuilder.instantiate().folderBuilder.instantiate().service")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_settlesSignatures_whenFourSeamsReachOneAnotherThroughEachOthersEnums() async throws {
		// Each seam reaches the enums of the others through a neighbor; copies of different ages taken from different
		// neighbors would change some signature on every pass.
		let feature = [
			Self.service,
			Self.type("Home", seam: true, ["@Instantiated public let listBuilder: Instantiator<List>", "@Instantiated public let service: any Service"]),
			Self.type("List", seam: true, ["@Instantiated public let detailBuilder: Instantiator<Detail>"]),
			Self.type("Detail", seam: true, ["@Instantiated public let homeBuilder: Instantiator<Home>", "@Instantiated public let settingsBuilder: Instantiator<Settings>"]),
			Self.type("Settings", seam: true, ["@Instantiated public let homeBuilder: Instantiator<Home>", "@Instantiated public let detailBuilder: Instantiator<Detail>", "@Instantiated public let service: any Service"]),
		]
		let fulfiller = Self.fulfilling("DefaultService", "Service")
		let root = Self.root(["@Instantiated public let home: Home"])
		try await expectOutput(of: Self.modules(feature: feature, app: [fulfiller, root]), [
			"App": ["App.swift": """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_home() -> Home {
			            _ = Home.__safeDI_Home_8A97B8B21F077ACD.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_serviceBuilder_Home(_ scope: Home.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case let .listBuilder(scope): return __safeDI_serviceBuilder_List(scope)
			                case .service:
			                    let service: any Service = DefaultService()
			                    return service
			                }
			            }
			            func __safeDI_serviceBuilder_List(_ scope: List.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case let .detailBuilder(scope): return __safeDI_serviceBuilder_Detail(scope)
			                }
			            }
			            func __safeDI_serviceBuilder_Detail(_ scope: Detail.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case let .homeBuilder(scope): return __safeDI_serviceBuilder_Home(scope)
			                case let .settingsBuilder(scope): return __safeDI_serviceBuilder_Settings(scope)
			                }
			            }
			            func __safeDI_serviceBuilder_Settings(_ scope: Settings.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case let .homeBuilder(scope): return __safeDI_serviceBuilder_Home(scope)
			                case let .detailBuilder(scope): return __safeDI_serviceBuilder_Detail(scope)
			                case .service:
			                    let service: any Service = DefaultService()
			                    return service
			                }
			            }
			            return Home(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Home)
			        }
			        let home: Home = __safeDI_home()
			        self.init(home: home)
			    }
			}
			"""],
		], visible: Self.modules(feature: feature + [fulfiller], app: [root]), probes: [DifferentialValueProbe("Root().home.listBuilder.instantiate().detailBuilder.instantiate().settingsBuilder.instantiate().service")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_settlesSignatures_whenFourSeamsFormSeveralCyclesOfInstantiators() async throws {
		let feature = [
			Self.service,
			Self.type("S0", seam: true, ["@Instantiated public let to1: Instantiator<S1>", "@Instantiated public let to3: Instantiator<S3>", "@Instantiated public let service: any Service"]),
			Self.type("S1", seam: true, ["@Instantiated public let to0: Instantiator<S0>", "@Instantiated public let to2: Instantiator<S2>", "@Instantiated public let service: any Service"]),
			Self.type("S2", seam: true, ["@Instantiated public let to0: Instantiator<S0>", "@Instantiated public let to3: Instantiator<S3>"]),
			Self.type("S3", seam: true, ["@Instantiated public let to0: Instantiator<S0>", "@Instantiated public let to1: Instantiator<S1>", "@Instantiated public let to2: Instantiator<S2>", "@Instantiated public let service: any Service"]),
		]
		let fulfiller = Self.fulfilling("DefaultService", "Service")
		let root = Self.root(["@Instantiated public let s0: S0"])
		try await expectOutput(of: Self.modules(feature: feature, app: [fulfiller, root]), [
			"App": ["App.swift": """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_s0() -> S0 {
			            _ = S0.__safeDI_S0_64F713BB0197568C.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_serviceBuilder_S0(_ scope: S0.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case let .to1(scope): return __safeDI_serviceBuilder_S1(scope)
			                case let .to3(scope): return __safeDI_serviceBuilder_S3(scope)
			                case .service:
			                    let service: any Service = DefaultService()
			                    return service
			                }
			            }
			            func __safeDI_serviceBuilder_S1(_ scope: S1.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case let .to0(scope): return __safeDI_serviceBuilder_S0(scope)
			                case let .to2(scope): return __safeDI_serviceBuilder_S2(scope)
			                case .service:
			                    let service: any Service = DefaultService()
			                    return service
			                }
			            }
			            func __safeDI_serviceBuilder_S2(_ scope: S2.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case let .to0(scope): return __safeDI_serviceBuilder_S0(scope)
			                case let .to3(scope): return __safeDI_serviceBuilder_S3(scope)
			                }
			            }
			            func __safeDI_serviceBuilder_S3(_ scope: S3.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case let .to0(scope): return __safeDI_serviceBuilder_S0(scope)
			                case let .to1(scope): return __safeDI_serviceBuilder_S1(scope)
			                case let .to2(scope): return __safeDI_serviceBuilder_S2(scope)
			                case .service:
			                    let service: any Service = DefaultService()
			                    return service
			                }
			            }
			            return S0(__safeDI_serviceBuilder: __safeDI_serviceBuilder_S0)
			        }
			        let s0: S0 = __safeDI_s0()
			        self.init(s0: s0)
			    }
			}
			"""],
		], visible: Self.modules(feature: feature + [fulfiller], app: [root]), probes: [DifferentialValueProbe("Root().s0.to3.instantiate().to2.instantiate().to3.instantiate().service")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsTheOuterSeamsGuard_whenAPlaceOfAnInnerSeamItFillsGainsASibling() async throws {
		// `Host` fills `Deep`'s `Gadget` places and passes its `Service` place up: no builder of `Host` reaches the enum it fills,
		// so a place added to that enum changes nothing a caller of `Host` passes.
		func guardOfHost(_ deepDeclarations: [String]) async throws -> String {
			let output = try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Lower", packageName: "Shop", swiftFileContent: [Self.service, "public protocol Gadget {}", Self.type("Deep", seam: true, deepDeclarations)]),
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
						"import Lower\n\n" + Self.fulfilling("DefaultGadget", "Gadget"),
						"import Lower\n\n" + Self.type("Host", seam: true, ["@Instantiated public let deep: Deep"]),
					], dependencies: ["Lower"]),
				],
				integration: .moduleInfo,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
			let generated = try #require(output.modules["Feature"]?.generatedFiles["Feature.swift"])
			return try #require(generated.components(separatedBy: "\n").first { $0.contains("enum __safeDI_Host_") })
		}
		let onePlace = try await guardOfHost(["@Instantiated public let service: any Service", "@Instantiated public let gadget: any Gadget"])
		let twoPlaces = try await guardOfHost(["@Instantiated public let service: any Service", "@Instantiated public let gadget: any Gadget", "@Instantiated public let gadget2: any Gadget"])
		#expect(onePlace == twoPlaces)
	}

	// MARK: 7b. Wrappers that forward a value

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsTheWrapperAroundAClosure_whenAnErasedInstantiatorForwardsATypealiasOfAFunction() async throws {
		// A parameter typed `Callback` would not escape into the case, which a function type spelled as such would.
		let feature = [
			Self.service,
			"public typealias Callback = () -> Void",
			Self.type("Host", seam: true, [#"@Instantiated(fulfilledByType: "Impl") public let maker: ErasedInstantiator<Callback, any Service>"#]),
		]
		let output = try await compiledOutput(of: Self.modules(feature: feature, app: [Self.handWritten("""
		struct CallingService: Service {}

		func host() -> Host {
		    Host(implBuilder: { scope in
		        switch scope {
		        case let .maker(_, callback):
		            callback()
		            return CallingService()
		        }
		    })
		}
		""")], featureConfiguration: plainDependencyTreeInitializersConfiguration))
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen public enum SafeDIScope_Impl {
		        case maker(maker_Values, Callback)

		        public struct maker_Values {}
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public init(implBuilder: @escaping (SafeDIScope_Impl) -> any Service) {
		        self.init(__safeDI_implBuilder: implBuilder)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public init(__safeDI_implBuilder: @escaping (SafeDIScope_Impl) -> any Service) {
		        let maker = ErasedInstantiator<Callback, any Service> {
		            __safeDI_implBuilder(.maker(SafeDIScope_Impl.maker_Values(), $0))
		        }
		        self.init(maker: maker)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_33280E6166340459 {}
		}
		"""])
	}

	// MARK: 8b. Names that a type the seam spells could resolve to

	@Test(arguments: ["Stage1", "Stage2"])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesStageStructsApart_whenTheBuiltTypeIsNamedLikeOne(typeName: String) async throws {
		// The last stage's generic alias spells the built type inside the scope type, beside the stage structs.
		let panel = """
		open class \(typeName): Instantiable, @unchecked Sendable {
		    public typealias ForwardedProperties = String
		    public init() {}
		}
		"""
		let feature = [panel, Self.type("Host", seam: true, ["@Instantiated public let job: SendableInstantiator<\(typeName)>"], conformances: ", Sendable")]
		let fulfiller = """
		@Instantiable(fulfillingAdditionalTypes: [\(typeName).self], conformsElsewhere: true)
		public final class Sub: \(typeName), @unchecked Sendable {
		    public init(title: String) {
		        self.title = title
		        super.init()
		    }

		    @Forwarded public let title: String
		}
		"""
		let root = Self.root(["@Instantiated public let host: Host"])
		let expectedByTypeName = [
			"Stage1": """
			extension Host {
			    public enum SafeDIStagedScope_Stage1_job {
			        public struct Stage1_ {}

			        public struct Stage2 {}

			        public typealias SendableLastStage<__safeDI_Forwarded> = @Sendable (Stage2, __safeDI_Forwarded) -> Stage1
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_stage1Builder_job: @escaping (SafeDIStagedScope_Stage1_job.Stage1_) -> SafeDIStagedScope_Stage1_job.SendableLastStage<Stage1.ForwardedProperties>) {
			        let __safeDI_stage1Builder_job_Stage2 = __safeDI_stage1Builder_job(SafeDIStagedScope_Stage1_job.Stage1_())
			        let job = SendableInstantiator<Stage1> {
			            __safeDI_stage1Builder_job_Stage2(SafeDIStagedScope_Stage1_job.Stage2(), $0)
			        }
			        self.init(job: job)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_F2FC28E7E76E96E1 {}
			}
			""",
			"Stage2": """
			extension Host {
			    public enum SafeDIStagedScope_Stage2_job {
			        public struct Stage1 {}

			        public struct Stage2_ {}

			        public typealias SendableLastStage<__safeDI_Forwarded> = @Sendable (Stage2_, __safeDI_Forwarded) -> Stage2
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_stage2Builder_job: @escaping (SafeDIStagedScope_Stage2_job.Stage1) -> SafeDIStagedScope_Stage2_job.SendableLastStage<Stage2.ForwardedProperties>) {
			        let __safeDI_stage2Builder_job_Stage2_ = __safeDI_stage2Builder_job(SafeDIStagedScope_Stage2_job.Stage1())
			        let job = SendableInstantiator<Stage2> {
			            __safeDI_stage2Builder_job_Stage2_(SafeDIStagedScope_Stage2_job.Stage2_(), $0)
			        }
			        self.init(job: job)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_65D936A167D93A30 {}
			}
			""",
		]
		try await expectOutput(
			of: Self.modules(feature: feature, app: [fulfiller, root]),
			["Feature": ["Feature.swift": try #require(expectedByTypeName[typeName])]],
			visible: Self.modules(feature: feature + [fulfiller], app: [root]),
			probes: [DifferentialValueProbe(#"(Root().host.job.instantiate("title") as! Sub).title"#)],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesLastStageAliasApart_whenTheBuiltTypeIsNamedLikeIt() async throws {
		// The last stage's generic alias spells the built type inside the scope type, so the alias takes a trailing
		// underscore rather than shadow the built type it returns.
		let panel = """
		open class SendableLastStage: Instantiable, @unchecked Sendable {
		    public typealias ForwardedProperties = String
		    public init() {}
		}
		"""
		let feature = [panel, Self.type("Host", seam: true, ["@Instantiated public let job: SendableInstantiator<SendableLastStage>"], conformances: ", Sendable")]
		let fulfiller = """
		@Instantiable(fulfillingAdditionalTypes: [SendableLastStage.self], conformsElsewhere: true)
		public final class Sub: SendableLastStage, @unchecked Sendable {
		    public init(title: String) {
		        self.title = title
		        super.init()
		    }

		    @Forwarded public let title: String
		}
		"""
		let root = Self.root(["@Instantiated public let host: Host"])
		try await expectOutput(
			of: Self.modules(feature: feature, app: [fulfiller, root]),
			["Feature": ["Feature.swift": """
			extension Host {
			    public enum SafeDIStagedScope_SendableLastStage_job {
			        public struct Stage1 {}

			        public struct Stage2 {}

			        public typealias SendableLastStage_<__safeDI_Forwarded> = @Sendable (Stage2, __safeDI_Forwarded) -> SendableLastStage
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_sendableLastStageBuilder_job: @escaping (SafeDIStagedScope_SendableLastStage_job.Stage1) -> SafeDIStagedScope_SendableLastStage_job.SendableLastStage_<SendableLastStage.ForwardedProperties>) {
			        let __safeDI_sendableLastStageBuilder_job_Stage2 = __safeDI_sendableLastStageBuilder_job(SafeDIStagedScope_SendableLastStage_job.Stage1())
			        let job = SendableInstantiator<SendableLastStage> {
			            __safeDI_sendableLastStageBuilder_job_Stage2(SafeDIStagedScope_SendableLastStage_job.Stage2(), $0)
			        }
			        self.init(job: job)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_15443CBA48D84BCD {}
			}
			"""]],
			visible: Self.modules(feature: feature + [fulfiller], app: [root]),
			probes: [DifferentialValueProbe(#"(Root().host.job.instantiate("title") as! Sub).title"#)],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsScopeFields_whenLabelsAreTypeAndInit() async throws {
		// A member named `Type` is declared in backticks, and one named `init` is read in backticks.
		let feature = [
			Self.sendableService,
			Self.type("Kind", conformances: ", Sendable"),
			Self.type("Name", conformances: ", Sendable"),
			Self.type("Job", ["@Instantiated public let service: any Service"], conformances: ", Sendable"),
			Self.type("Host", seam: true, ["@Received public let `Type`: Kind", "@Received public let `init`: Name", "@Instantiated public let zsvc: any Service", "@Instantiated public let job: SendableInstantiator<Job>"]),
		]
		let fulfiller = Self.fulfilling("DefaultService", "Service", ["@Received public let `Type`: Kind", "@Received public let `init`: Name"], conformances: ", Sendable")
		let root = Self.root(["@Instantiated public let `Type`: Kind", "@Instantiated public let `init`: Name", "@Instantiated public let host: Host"])
		try await expectOutput(of: Self.modules(feature: feature, app: [fulfiller, root]), [
			"Feature": ["Feature.swift": """
			extension Host {
			    @frozen public enum SafeDIScope_Service {
			        case zsvc(zsvc_Values)

			        public struct zsvc_Values {
			            public let `Type`: Kind
			            public let `init`: Name
			        }
			    }

			    public enum SafeDIStagedScope_Service_job_service {
			        public struct Stage1 {
			            public let `Type`: Kind
			            public let `init`: Name
			            public let zsvc: any Service
			        }

			        public struct Stage2 {}
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_Type Type: Kind, __safeDI_init `init`: Name, __safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service, __safeDI_serviceBuilder_job_service: @escaping (SafeDIStagedScope_Service_job_service.Stage1) -> @Sendable (SafeDIStagedScope_Service_job_service.Stage2) -> any Service) {
			        let zsvc: any Service = __safeDI_serviceBuilder(.zsvc(SafeDIScope_Service.zsvc_Values(Type: Type, init: `init`)))
			        let __safeDI_serviceBuilder_job_service_Stage2 = __safeDI_serviceBuilder_job_service(SafeDIStagedScope_Service_job_service.Stage1(Type: Type, init: `init`, zsvc: zsvc))
			        @Sendable func __safeDI_job() -> Job {
			            let service: any Service = __safeDI_serviceBuilder_job_service_Stage2(SafeDIStagedScope_Service_job_service.Stage2())
			            return Job(service: service)
			        }
			        let job = SendableInstantiator<Job>(__safeDI_job)
			        self.init(Type: Type, init: `init`, zsvc: zsvc, job: job)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_67FF3A9CE97D9C3A {}
			}
			"""],
			"App": ["App.swift": """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        let Type = Kind()
			        let `init` = Name()
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_67FF3A9CE97D9C3A.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_serviceBuilder_job_service(_ scope: Host.SafeDIStagedScope_Service_job_service.Stage1) -> @Sendable (Host.SafeDIStagedScope_Service_job_service.Stage2) -> any Service {
			                let Type = scope.Type
			                let `init` = scope.`init`
			                @Sendable func __safeDI_serviceBuilder_job_service_Stage2(_ scope: Host.SafeDIStagedScope_Service_job_service.Stage2) -> any Service {
			                    let service: any Service = DefaultService(Type: Type, init: `init`)
			                    return service
			                }
			                return __safeDI_serviceBuilder_job_service_Stage2
			            }
			            func __safeDI_serviceBuilder_Host(_ scope: Host.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case let .zsvc(scope):
			                    let Type = scope.Type
			                    let `init` = scope.`init`
			                    let zsvc: any Service = DefaultService(Type: Type, init: `init`)
			                    return zsvc
			                }
			            }
			            return Host(__safeDI_Type: Type, __safeDI_init: `init`, __safeDI_serviceBuilder: __safeDI_serviceBuilder_Host, __safeDI_serviceBuilder_job_service: __safeDI_serviceBuilder_job_service)
			        }
			        let host: Host = __safeDI_host()
			        self.init(Type: Type, init: `init`, host: host)
			    }
			}
			"""],
		], visible: Self.modules(feature: feature + [fulfiller], app: [root]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsGuardFillsAndDispatchersAsOneIdentifier_whenAnInnerSeamsNameIsARawIdentifier() async throws {
		let feature = [
			Self.service,
			Self.type("`My Inner`", seam: true, ["@Instantiated public let service: any Service"]),
			Self.type("Host", seam: true, ["@Instantiated public let inner: `My Inner`"]),
		]
		let fulfiller = Self.fulfilling("DefaultService", "Service")
		let root = Self.root(["@Instantiated public let host: Host"])
		try await expectOutput(of: Self.modules(feature: feature, app: [fulfiller, root]), [
			"Feature": ["Feature.swift": """
			extension `My Inner` {
			    @frozen public enum SafeDIScope_Service {
			        case service(service_Values)

			        public struct service_Values {}
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
			        let service: any Service = __safeDI_serviceBuilder(.service(SafeDIScope_Service.service_Values()))
			        self.init(service: service)
			    }
			}

			extension `My Inner` {
			    public enum `__safeDI_My Inner_E8B99B2FD15008A7` {}
			}

			extension Host {
			    @frozen public enum SafeDIScope_Service {
			        case inner(`My Inner`.SafeDIScope_Service)
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
			        func __safeDI_inner() -> `My Inner` {
			            _ = `My Inner`.`__safeDI_My Inner_E8B99B2FD15008A7`.self
			            return `My Inner`(__safeDI_serviceBuilder: { __safeDI_serviceBuilder(.inner($0)) })
			        }
			        let inner: `My Inner` = __safeDI_inner()
			        self.init(inner: inner)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_1ABD90FF9CCB0097 {}
			}
			"""],
			"App": ["App.swift": """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_1ABD90FF9CCB0097.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_serviceBuilder_Host(_ scope: Host.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case let .inner(scope): return `__safeDI_serviceBuilder_My Inner`(scope)
			                }
			            }
			            func `__safeDI_serviceBuilder_My Inner`(_ scope: `My Inner`.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case .service:
			                    let service: any Service = DefaultService()
			                    return service
			                }
			            }
			            return Host(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Host)
			        }
			        let host: Host = __safeDI_host()
			        self.init(host: host)
			    }
			}
			"""],
		], visible: Self.modules(feature: feature + [fulfiller], app: [root]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsTheDispatchersReturnTypeAsTheFirstPlaceSpellsIt_whenPlacesSpellACompositionInEitherOrder() async throws {
		// Twenty places of one hole type, the first spelled `any P & Q` and the rest `any Q & P`: a choice that read an
		// unordered collection would pick the first place on only one run in twenty.
		var declarations = ["@Instantiated public let p01: any P & Q"]
		for index in 2...20 {
			declarations.append("@Instantiated public let p\(index < 10 ? "0" : "")\(index): any Q & P")
		}
		let feature = ["public protocol P {}", "public protocol Q {}", Self.type("Host", seam: true, declarations)]
		let fulfiller = """
		@Instantiable(fulfillingAdditionalTypes: [(any P & Q).self])
		public struct DefaultPQ: Instantiable, P, Q {
		    public init() {}
		}
		"""
		try await expectOutput(of: Self.modules(feature: feature, app: [fulfiller, Self.root(["@Instantiated public let host: Host"])]), [
			"App": ["App.swift": """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_201B8E35D57D7D7A.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_p_and_QBuilder_Host(_ scope: Host.SafeDIScope_P_and_Q) -> any (P & Q) {
			                switch scope {
			                case .p01:
			                    let p01: any (P & Q) = DefaultPQ()
			                    return p01
			                case .p02:
			                    let p02: any (Q & P) = DefaultPQ()
			                    return p02
			                case .p03:
			                    let p03: any (Q & P) = DefaultPQ()
			                    return p03
			                case .p04:
			                    let p04: any (Q & P) = DefaultPQ()
			                    return p04
			                case .p05:
			                    let p05: any (Q & P) = DefaultPQ()
			                    return p05
			                case .p06:
			                    let p06: any (Q & P) = DefaultPQ()
			                    return p06
			                case .p07:
			                    let p07: any (Q & P) = DefaultPQ()
			                    return p07
			                case .p08:
			                    let p08: any (Q & P) = DefaultPQ()
			                    return p08
			                case .p09:
			                    let p09: any (Q & P) = DefaultPQ()
			                    return p09
			                case .p10:
			                    let p10: any (Q & P) = DefaultPQ()
			                    return p10
			                case .p11:
			                    let p11: any (Q & P) = DefaultPQ()
			                    return p11
			                case .p12:
			                    let p12: any (Q & P) = DefaultPQ()
			                    return p12
			                case .p13:
			                    let p13: any (Q & P) = DefaultPQ()
			                    return p13
			                case .p14:
			                    let p14: any (Q & P) = DefaultPQ()
			                    return p14
			                case .p15:
			                    let p15: any (Q & P) = DefaultPQ()
			                    return p15
			                case .p16:
			                    let p16: any (Q & P) = DefaultPQ()
			                    return p16
			                case .p17:
			                    let p17: any (Q & P) = DefaultPQ()
			                    return p17
			                case .p18:
			                    let p18: any (Q & P) = DefaultPQ()
			                    return p18
			                case .p19:
			                    let p19: any (Q & P) = DefaultPQ()
			                    return p19
			                case .p20:
			                    let p20: any (Q & P) = DefaultPQ()
			                    return p20
			                }
			            }
			            return Host(__safeDI_p_and_QBuilder: __safeDI_p_and_QBuilder_Host)
			        }
			        let host: Host = __safeDI_host()
			        self.init(host: host)
			    }
			}
			"""],
		])
	}

	// MARK: 13b. Errors name what reaches the place

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsOneTierOmitsBuilder_namingTheSendableBuilder_whenOnlyASendableRouteReachesAPackageSeamsPlace() async {
		// `Host` reaches `Deep`'s place only inside the `@Sendable` function of its `SendableInstantiator`, so its one builder is
		// `serviceSendableBuilder`, which the place's `package` scope narrows.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Host.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Host`: its generated `public` initializer, which `Host`'s `public` access requires, cannot take `serviceSendableBuilder: @escaping @Sendable (SafeDISendableScope_Service) -> any Service`, the builder for `Deep`'s `service: any Service`, which no @Instantiable declaration that module `Feature` can see fulfills. `Deep`'s own `@Instantiable` declaration is `package`. Declare `Deep` `public`; declare `Host` `package`; make an @Instantiable declaration that fulfills `Service` one module `Feature` reads, so `Host` fills the builder itself; or declare the dependency tree on a `package` type that instantiates `Host`.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					Self.sendableService,
					"""
					@Instantiable(generateDependencyTree: true)
					package struct Deep: Instantiable, Sendable {
					    package init(service: any Service) {
					        self.service = service
					    }

					    @Instantiated package let service: any Service
					}
					""",
					"""
					@Instantiable
					public struct DeepHolder: Instantiable, Sendable {
					    package init(deep: Deep) {
					        self.deep = deep
					    }

					    @Instantiated package let deep: Deep
					}
					""",
					Self.type("Host", seam: true, ["@Instantiated public let held: SendableInstantiator<DeepHolder>"]),
				])],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsDeclarationBoundAfterSite_namingTheFilledPlacesSeam_whenAPlaceInsideAFillReadsALabelAPassingUpSeamBinds() async {
		// `Host` fills `Helper`'s `gadget`, which `Mid` passes up, with `FeatureGadget`, whose own `service` `App` fills with a
		// type that receives `user`. Inline, that is `Mid`'s `user`, bound where `Mid` calls `Helper`: the remedy is on
		// `Helper`, whose place the fill fills, not on `Host`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["DefaultService.swift"]):11:5: error: `DefaultService` receives `user: User`, which `Mid` builds where it calls `Helper`, but `Mid` passes the builder for `Helper`'s `gadget: any Gadget` (case `gadget` of `gadgetBuilder`) on from its own caller, which cannot hand it `Mid`'s values. Declare `@Received let user: User` on `Helper`, so the builder's scope carries it, or make an @Instantiable declaration that fulfills `Gadget` one module `Middle` reads, so `Mid` fills the builder itself.
			\(fixtures["Middle"]!["Mid.swift"]):10:5: note: `Mid` declares `user: User` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.placeInsideAFillModules(helperDeclarations: []), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsTheValueInlineBuilds_whenTheFilledPlacesSeamReceivesTheLabelThePlaceInsideTheFillReads() async throws {
		// The remedy the error above names: `Helper` receives `user`, so its scope carries `Mid`'s `user` to the fill, and
		// `DefaultService` holds the instance `Mid` holds, as inline.
		try await expectOutput(
			of: Self.placeInsideAFillModules(helperDeclarations: ["@Received public let user: User"]),
			["App": ["App.swift": """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Lower)
			import Lower
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			extension Root {
			    public init() {
			        let user = User()
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_99305A554F65E2EB.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_serviceBuilder_Host(_ scope: Host.SafeDIScope_Service) -> any Service {
			                switch scope {
			                case let .mid_Helper_gadget_service(scope):
			                    let user = scope.user
			                    let service: any Service = DefaultService(user: user)
			                    return service
			                }
			            }
			            return Host(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Host)
			        }
			        let host: Host = __safeDI_host()
			        self.init(user: user, host: host)
			    }
			}
			"""]],
			visible: Self.placeInsideAFillModules(helperDeclarations: ["@Received public let user: User"], isInline: true),
		)
	}

	/// `Helper`, in `Lower`, has a place `gadget` that `Mid`, in `Middle`, passes up after declaring `user`; `Host`, in
	/// `Feature`, fills it with `FeatureGadget`, whose place `service` `App` fills with `DefaultService`, which receives `user`.
	/// With `isInline`, no type is a seam, so every tree is built inline.
	private static func placeInsideAFillModules(helperDeclarations: [String], isInline: Bool = false) -> [ModuleFixture] {
		let user = """
		@Instantiable
		public final class User: Instantiable {
		    public init() {}
		}
		"""
		let defaultService = Self.fulfilling("DefaultService", "Service", ["@Received public let user: User"])
		let modules = [
			ModuleFixture(name: "Lower", packageName: "Shop", swiftFileContent: ["public protocol Gadget {}\npublic protocol Service {}", user, Self.type("Helper", seam: true, helperDeclarations + ["@Instantiated public let gadget: any Gadget"])]),
			ModuleFixture(name: "Middle", packageName: "Shop", swiftFileContent: ["import Lower\n\n" + Self.type("Mid", seam: true, ["@Instantiated public let user: User", "@Instantiated public let helper: Helper"])], dependencies: ["Lower"]),
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"import Lower\n\n" + Self.fulfilling("FeatureGadget", "Gadget", ["@Instantiated public let service: any Service"]),
				"import Lower\nimport Middle\n\n" + Self.type("Host", seam: true, ["@Instantiated public let mid: Mid"]),
			], dependencies: ["Lower", "Middle"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				"import Lower\nimport Middle\nimport Feature\n\n" + defaultService,
				"import Lower\nimport Feature\n\n" + Self.root(["@Instantiated public let user: User", "@Instantiated public let host: Host"]),
			], dependencies: ["Lower", "Middle", "Feature"]),
		]
		guard isInline else { return modules }
		return modules.map { ModuleFixture(name: $0.name, packageName: $0.packageName, swiftFileContent: inlineFixture($0.swiftFileContent), dependencies: $0.dependencies) }
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesNoForwardedTypeInTheUnreadTypeComment_whenTheSeamIsNotPublic() async throws {
		// The enum is spelled `public`, but an `internal` seam's enum is no wider than the seam, so no other package names
		// `Unread` through it.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Kit", packageName: "Shop", swiftFileContent: ["public struct Unread: Sendable {\n    public init() {}\n}\n\npublic protocol Service {}"], runsSafeDI: false),
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: ["""
				import Kit

				@Instantiable(generateDependencyTree: true)
				struct Host: Instantiable {
				    init(maker: ErasedInstantiator<Unread, any Service>) {
				        self.maker = maker
				    }

				    @Instantiated(fulfilledByType: "Missing") let maker: ErasedInstantiator<Unread, any Service>
				}
				"""], dependencies: ["Kit"]),
			],
			integration: .moduleInfo,
			compileVerification: .returningOutcomeOnly,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(Kit)
		import Kit
		#endif

		extension Host {
		    @frozen public enum SafeDIScope_Missing {
		        case maker(maker_Values, Unread)

		        public struct maker_Values {}
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    internal init(__safeDI_missingBuilder: @escaping (SafeDIScope_Missing) -> any Service) {
		        let maker = ErasedInstantiator<Unread, any Service> {
		            __safeDI_missingBuilder(.maker(SafeDIScope_Missing.maker_Values(), $0))
		        }
		        self.init(maker: maker)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_EF7E3B49BE6E9791 {}
		}
		"""])
		if compileVerificationIsEnabled {
			let compilation = try #require(output.compilation)
			#expect(compilation.modules.map(\.exitCode) == output.moduleNames.map { _ in 0 })
		}
	}

	private var filesToDelete: [URL]
}
