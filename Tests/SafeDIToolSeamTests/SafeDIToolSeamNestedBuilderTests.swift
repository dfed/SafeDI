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
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
			        public let panel: __safeDI_ServiceCarrier_Panel<__safeDI_Built>

			        public init(panel: __safeDI_ServiceCarrier_Panel<__safeDI_Built>) {
			            self.panel = panel
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(panel: .init(__safeDI_noScope: __safeDI_builder))
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceCarrier_Panel<__safeDI_Built> {
			        public let service: () -> __safeDI_Built

			        public init(service: @escaping () -> __safeDI_Built) {
			            self.service = service
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(service: { __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
			        let __safeDI_serviceBuilder_panel = __safeDI_serviceBuilder.panel
			        func __safeDI_panel() -> Panel {
			            let service: any Service = __safeDI_serviceBuilder_panel.service()
			            return Panel(service: service)
			        }
			        let panel: Panel = __safeDI_panel()
			        self.init(panel: panel)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_87413095D2DB8935 {}
			}
			"""],
			"App": ["App.swift": """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_serviceBuilder_Host() -> Host.__safeDI_ServiceCarrier<any Service> {
			            .init(panel: __safeDI_serviceBuilder_Host_Panel_Scope())
			        }
			        func __safeDI_serviceBuilder_Host_Panel_Scope() -> Host.__safeDI_ServiceCarrier_Panel<any Service> {
			            .init(service: {
			                let service: any Service = DefaultService()
			                return service
			            })
			        }
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_87413095D2DB8935.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Host(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Host())
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
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
			        public let panel: __safeDI_ServiceCarrier_Panel<__safeDI_Built>
			        public let row: (Panel) -> __safeDI_ServiceCarrier_Row<__safeDI_Built>

			        public init(panel: __safeDI_ServiceCarrier_Panel<__safeDI_Built>, row: @escaping (Panel) -> __safeDI_ServiceCarrier_Row<__safeDI_Built>) {
			            self.panel = panel
			            self.row = row
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(panel: .init(__safeDI_noScope: __safeDI_builder), row: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceCarrier_Panel<__safeDI_Built> {
			        public let service: () -> __safeDI_Built

			        public init(service: @escaping () -> __safeDI_Built) {
			            self.service = service
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(service: { __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceCarrier_Row<__safeDI_Built> {
			        public let service: () -> __safeDI_Built

			        public init(service: @escaping () -> __safeDI_Built) {
			            self.service = service
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(service: { __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
			        let __safeDI_serviceBuilder_panel = __safeDI_serviceBuilder.panel
			        func __safeDI_panel() -> Panel {
			            let service: any Service = __safeDI_serviceBuilder_panel.service()
			            return Panel(service: service)
			        }
			        let panel: Panel = __safeDI_panel()
			        let __safeDI_serviceBuilder_row = __safeDI_serviceBuilder.row(panel)
			        func __safeDI_row() -> Row {
			            let service: any Service = __safeDI_serviceBuilder_row.service()
			            return Row(service: service)
			        }
			        let row: Row = __safeDI_row()
			        self.init(panel: panel, row: row)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_61BEE9F915B4B25B {}
			}
			"""],
			"App": ["App.swift": """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_serviceBuilder_Host() -> Host.__safeDI_ServiceCarrier<any Service> {
			            .init(panel: __safeDI_serviceBuilder_Host_Panel_Scope(), row: { values_panel in __safeDI_serviceBuilder_Host_Row_Scope() })
			        }
			        func __safeDI_serviceBuilder_Host_Panel_Scope() -> Host.__safeDI_ServiceCarrier_Panel<any Service> {
			            .init(service: {
			                let service: any Service = DefaultService()
			                return service
			            })
			        }
			        func __safeDI_serviceBuilder_Host_Row_Scope() -> Host.__safeDI_ServiceCarrier_Row<any Service> {
			            .init(service: {
			                let service: any Service = DefaultService()
			                return service
			            })
			        }
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_61BEE9F915B4B25B.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Host(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Host())
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
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
			        public let first: __safeDI_ServiceCarrier_Panel<__safeDI_Built>
			        public let second: (Panel) -> __safeDI_ServiceCarrier_Panel<__safeDI_Built>

			        public init(first: __safeDI_ServiceCarrier_Panel<__safeDI_Built>, second: @escaping (Panel) -> __safeDI_ServiceCarrier_Panel<__safeDI_Built>) {
			            self.first = first
			            self.second = second
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(first: .init(__safeDI_noScope: __safeDI_builder), second: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceCarrier_Panel<__safeDI_Built> {
			        public let service: () -> __safeDI_Built

			        public init(service: @escaping () -> __safeDI_Built) {
			            self.service = service
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(service: { __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
			        let __safeDI_serviceBuilder_first = __safeDI_serviceBuilder.first
			        func __safeDI_first() -> Panel {
			            let service: any Service = __safeDI_serviceBuilder_first.service()
			            return Panel(service: service)
			        }
			        let first: Panel = __safeDI_first()
			        let __safeDI_serviceBuilder_second = __safeDI_serviceBuilder.second(first)
			        func __safeDI_second() -> Panel {
			            let service: any Service = __safeDI_serviceBuilder_second.service()
			            return Panel(service: service)
			        }
			        let second: Panel = __safeDI_second()
			        self.init(first: first, second: second)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_E9D5672A61B00041 {}
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
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
			        public let first: () -> __safeDI_Built
			        public let second: (any Service) -> __safeDI_Built

			        public init(first: @escaping () -> __safeDI_Built, second: @escaping (any Service) -> __safeDI_Built) {
			            self.first = first
			            self.second = second
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(first: { __safeDI_builder() }, second: { _ in __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
			        let first: any Service = __safeDI_serviceBuilder.first()
			        let second: any Service = __safeDI_serviceBuilder.second(first)
			        self.init(first: first, second: second)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_E8233D5EEF2D7EE6 {}
			}
			"""],
			"App": ["App.swift": """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_serviceBuilder_Host() -> Host.__safeDI_ServiceCarrier<any Service> {
			            .init(
			                first: {
			                    let first: any Service = DefaultService()
			                    return first
			                },
			                second: { scope_first in
			                    let second: any Service = DefaultService()
			                    return second
			                }
			            )
			        }
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_E8233D5EEF2D7EE6.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Host(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Host())
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
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_GadgetCarrier<__safeDI_Built> {
			        public let gadget: (any Service) -> __safeDI_Built

			        public init(gadget: @escaping (any Service) -> __safeDI_Built) {
			            self.gadget = gadget
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(gadget: { _ in __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
			        public let service: () -> __safeDI_Built

			        public init(service: @escaping () -> __safeDI_Built) {
			            self.service = service
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(service: { __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_gadgetBuilder: __safeDI_GadgetCarrier<any Gadget>, __safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
			        let service: any Service = __safeDI_serviceBuilder.service()
			        let gadget: any Gadget = __safeDI_gadgetBuilder.gadget(service)
			        self.init(service: service, gadget: gadget)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_34C6967D52BE233C {}
			}
			"""],
			"App": ["App.swift": """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_gadgetBuilder_Host() -> Host.__safeDI_GadgetCarrier<any Gadget> {
			            .init(gadget: { scope_service in
			                let gadget: any Gadget = DefaultGadget()
			                return gadget
			            })
			        }
			        func __safeDI_serviceBuilder_Host() -> Host.__safeDI_ServiceCarrier<any Service> {
			            .init(service: {
			                let service: any Service = DefaultService()
			                return service
			            })
			        }
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_34C6967D52BE233C.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Host(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Host(), __safeDI_serviceBuilder: __safeDI_serviceBuilder_Host())
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
	mutating func generate_labelsEachBuilderByFillingAndReturnedType_whenOneFillingTypeIsBuiltAsTwoTypes() async throws {
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_Impl_AnyServiceCarrier<__safeDI_Built> {
		        public let erased: (any Service) -> __safeDI_Built

		        public init(erased: @escaping (any Service) -> __safeDI_Built) {
		            self.erased = erased
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(erased: { _ in __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_Impl_ServiceCarrier<__safeDI_Built> {
		        public let plain: () -> __safeDI_Built

		        public init(plain: @escaping () -> __safeDI_Built) {
		            self.plain = plain
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(plain: { __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_impl_AnyServiceBuilder: __safeDI_Impl_AnyServiceCarrier<AnyService>, __safeDI_impl_ServiceBuilder: __safeDI_Impl_ServiceCarrier<any Service>) {
		        let plain: any Service = __safeDI_impl_ServiceBuilder.plain()
		        let erased: AnyService = __safeDI_impl_AnyServiceBuilder.erased(plain)
		        self.init(plain: plain, erased: erased)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_10281EB478B2B3DF {}
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesApartOnlyTheStemWhosePlainLabelIsTaken_whenAStemEqualsAnothersSendableLabel() async throws {
		let feature = [
			Self.service,
			"public protocol ServiceSendable {}",
			Self.type("Host", seam: true, ["@Instantiated public let service: any Service", "@Instantiated public let other: any ServiceSendable"]),
		]
		let output = try await compiledOutput(of: [ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature)])
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
		        public let service: () -> __safeDI_Built

		        public init(service: @escaping () -> __safeDI_Built) {
		            self.service = service
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(service: { __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ServiceSendable_ServiceSendableCarrier<__safeDI_Built> {
		        public let other: (any Service) -> __safeDI_Built

		        public init(other: @escaping (any Service) -> __safeDI_Built) {
		            self.other = other
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(other: { _ in __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>, __safeDI_serviceSendable_ServiceSendableBuilder: __safeDI_ServiceSendable_ServiceSendableCarrier<any ServiceSendable>) {
		        let service: any Service = __safeDI_serviceBuilder.service()
		        let other: any ServiceSendable = __safeDI_serviceSendable_ServiceSendableBuilder.other(service)
		        self.init(service: service, other: other)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_A84B5F7ABDBB30F0 {}
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_Box__PCarrier<__safeDI_Built> {
		        public let first: () -> __safeDI_Built
		        public let second: (Box<any P>) -> __safeDI_Built

		        public init(first: @escaping () -> __safeDI_Built, second: @escaping (Box<any P>) -> __safeDI_Built) {
		            self.first = first
		            self.second = second
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(first: { __safeDI_builder() }, second: { _ in __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_box__PBuilder: __safeDI_Box__PCarrier<Box<any P>>) {
		        let first: Box<any P> = __safeDI_box__PBuilder.first()
		        let second: Box<P> = __safeDI_box__PBuilder.second(first)
		        self.init(first: first, second: second)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_24C4E5A75F07F858 {}
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_P_and_QCarrier<__safeDI_Built> {
		        public let first: () -> __safeDI_Built
		        public let second: (any (P & Q)) -> __safeDI_Built

		        public init(first: @escaping () -> __safeDI_Built, second: @escaping (any (P & Q)) -> __safeDI_Built) {
		            self.first = first
		            self.second = second
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(first: { __safeDI_builder() }, second: { _ in __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_p_and_QBuilder: __safeDI_P_and_QCarrier<any (P & Q)>) {
		        let first: any (P & Q) = __safeDI_p_and_QBuilder.first()
		        let second: any (Q & P) = __safeDI_p_and_QBuilder.second(first)
		        self.init(first: first, second: second)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_F149F8842A3AC4C7 {}
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
			case .generic: "__safeDI_Host_B2F20BACD8E2E614"
			case .nested: "__safeDI_Host_EDDB58D3204D366E"
			case .optional: "__safeDI_Host_D1B52E2D0EA4CF51"
			case .array: "__safeDI_Host_355028C29E0F0B8E"
			case .dictionary: "__safeDI_Host_921C024104A53455"
			case .tuple: "__safeDI_Host_EB720F2C01C27E94"
			case .closure: "__safeDI_Host_C4035316039A583B"
			case .attributed: "__safeDI_Host_034039386D8B8EC2"
			case .metatype: "__safeDI_Host_7AE83676236C142D"
			case .variadic: "__safeDI_Host_8EC1F21F7E07BC03"
			case .void: "__safeDI_Host_9AB36D8C49EF771B"
			}
		}
	}

	@Test(arguments: OneHoleTypeSpelledTwoWays.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesOneHoleTypeByItsCanonicalSpelling_whenPlacesSpellItTwoWaysInsideAType(spelling: OneHoleTypeSpelledTwoWays) async throws {
		// The builder's struct is over the most explicit of the two spellings: `Void` is longer than `()`, and of two orders of a
		// composition, one shape, the one whose spelling sorts first (`TypeDescription.mostExplicitSpelling(among:)`).
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_\(spelling.stem)Carrier<__safeDI_Built> {
		        public let first: () -> __safeDI_Built
		        public let second: (\(spelling.spelledFirst)) -> __safeDI_Built

		        public init(first: @escaping () -> __safeDI_Built, second: @escaping (\(spelling.spelledFirst)) -> __safeDI_Built) {
		            self.first = first
		            self.second = second
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(first: { __safeDI_builder() }, second: { _ in __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_\(spelling.label): __safeDI_\(spelling.stem)Carrier<\(spelling.spelledSecond)>) {
		        let first: \(spelling.spelledFirst) = __safeDI_\(spelling.label).first()
		        let second: \(spelling.spelledSecond) = __safeDI_\(spelling.label).second(first)
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_Box__P_and_Q_Optional_AnyServiceCarrier<__safeDI_Built> {
		        public let first: () -> __safeDI_Built
		        public let second: (AnyService) -> __safeDI_Built

		        public init(first: @escaping () -> __safeDI_Built, second: @escaping (AnyService) -> __safeDI_Built) {
		            self.first = first
		            self.second = second
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(first: { __safeDI_builder() }, second: { _ in __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_box__P_and_Q_Optional_AnyServiceBuilder: __safeDI_Box__P_and_Q_Optional_AnyServiceCarrier<AnyService>) {
		        let first: AnyService = __safeDI_box__P_and_Q_Optional_AnyServiceBuilder.first()
		        let second: AnyService = __safeDI_box__P_and_Q_Optional_AnyServiceBuilder.second(first)
		        self.init(first: first, second: second)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_89777005DE002592 {}
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
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
			        public let inner: Inner.__safeDI_ServiceCarrier<__safeDI_Built>
			        public let service: (Inner) -> __safeDI_Built

			        public init(inner: Inner.__safeDI_ServiceCarrier<__safeDI_Built>, service: @escaping (Inner) -> __safeDI_Built) {
			            self.inner = inner
			            self.service = service
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(inner: .init(__safeDI_noScope: __safeDI_builder), service: { _ in __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
			        func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_99BD917DA5EDFC3D.self
			            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder.inner)
			        }
			        let inner: Inner = __safeDI_inner()
			        let service: any Service = __safeDI_serviceBuilder.service(inner)
			        self.init(inner: inner, service: service)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_B2B431110653F981 {}
			}

			extension Inner {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
			        public let service: () -> __safeDI_Built

			        public init(service: @escaping () -> __safeDI_Built) {
			            self.service = service
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(service: { __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
			        let service: any Service = __safeDI_serviceBuilder.service()
			        self.init(service: service)
			    }
			}

			extension Inner {
			    public enum __safeDI_Inner_99BD917DA5EDFC3D {}
			}
			"""],
			"App": ["App.swift": """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_serviceBuilder_Host() -> Host.__safeDI_ServiceCarrier<any Service> {
			            .init(
			                inner: __safeDI_serviceBuilder_Inner(),
			                service: { scope_inner in
			                    let service: any Service = DefaultService()
			                    return service
			                }
			            )
			        }
			        func __safeDI_serviceBuilder_Inner() -> Inner.__safeDI_ServiceCarrier<any Service> {
			            .init(service: {
			                let service: any Service = DefaultService()
			                return service
			            })
			        }
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_B2B431110653F981.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Host(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Host())
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
	mutating func generate_buildsEachPlaceFromHandWrittenBuilder_whenInnerSeamHoldsPlaceOfSeamsHoleType() async throws {
		// `Host`'s builder struct reaches `Inner`'s place through a level, so its enum declares no case a person could switch
		// over: the readable initializer takes the one builder, and `Host` and the `Inner` it calls each build their place
		// from it.
		let feature = [
			Self.service,
			Self.type("Inner", seam: true, ["@Instantiated public let service: any Service"]),
			Self.type("Host", seam: true, ["@Instantiated public let inner: Inner", "@Instantiated public let service: any Service"]),
		]
		let modules = Self.modules(feature: feature, app: [Self.handWritten("""
		struct CountedService: Service {
		    let count: Int
		}

		func host() -> Host {
		    var count = 0
		    return Host(serviceBuilder: {
		        count += 1
		        return CountedService(count: count)
		    })
		}
		""")], featureConfiguration: plainDependencyTreeInitializersConfiguration)
		let output = try await compiledOutput(of: modules)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
		        public let inner: Inner.__safeDI_ServiceCarrier<__safeDI_Built>
		        public let service: (Inner) -> __safeDI_Built

		        public init(inner: Inner.__safeDI_ServiceCarrier<__safeDI_Built>, service: @escaping (Inner) -> __safeDI_Built) {
		            self.inner = inner
		            self.service = service
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(inner: .init(__safeDI_noScope: __safeDI_builder), service: { _ in __safeDI_builder() })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public init(serviceBuilder: @escaping () -> any Service) {
		        self.init(__safeDI_serviceBuilder: .init(__safeDI_noScope: serviceBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_99BD917DA5EDFC3D.self
		            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder.inner)
		        }
		        let inner: Inner = __safeDI_inner()
		        let service: any Service = __safeDI_serviceBuilder.service(inner)
		        self.init(inner: inner, service: service)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_B2B431110653F981 {}
		}

		extension Inner {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
		        public let service: () -> __safeDI_Built

		        public init(service: @escaping () -> __safeDI_Built) {
		            self.service = service
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(service: { __safeDI_builder() })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public init(serviceBuilder: @escaping () -> any Service) {
		        self.init(__safeDI_serviceBuilder: .init(__safeDI_noScope: serviceBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
		        let service: any Service = __safeDI_serviceBuilder.service()
		        self.init(service: service)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_99BD917DA5EDFC3D {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader])

		let description = try await DifferentialValueOracle.describe(DifferentialValuePath(output: output, modules: modules), probes: [DifferentialValueProbe("host()")], filesToDelete: &filesToDelete)

		if compileVerificationIsEnabled {
			#expect(description == """
			probe host()
			Host
			  inner: Inner
			    service: CountedService
			      count: Int 1
			  service: CountedService
			    count: Int 2

			""")
		}
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
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
			        public let first: Inner.__safeDI_ServiceCarrier<__safeDI_Built>
			        public let second: Inner.__safeDI_ServiceCarrier<__safeDI_Built>

			        public init(first: Inner.__safeDI_ServiceCarrier<__safeDI_Built>, second: Inner.__safeDI_ServiceCarrier<__safeDI_Built>) {
			            self.first = first
			            self.second = second
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(first: .init(__safeDI_noScope: __safeDI_builder), second: .init(__safeDI_noScope: __safeDI_builder))
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
			        func __safeDI_first() -> Inner {
			            _ = Inner.__safeDI_Inner_99BD917DA5EDFC3D.self
			            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder.first)
			        }
			        let first: Inner = __safeDI_first()
			        func __safeDI_second() -> Inner {
			            _ = Inner.__safeDI_Inner_99BD917DA5EDFC3D.self
			            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder.second)
			        }
			        let second: Inner = __safeDI_second()
			        self.init(first: first, second: second)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_10E1F3F1E8CC3D0D {}
			}

			extension Inner {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
			        public let service: () -> __safeDI_Built

			        public init(service: @escaping () -> __safeDI_Built) {
			            self.service = service
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(service: { __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
			        let service: any Service = __safeDI_serviceBuilder.service()
			        self.init(service: service)
			    }
			}

			extension Inner {
			    public enum __safeDI_Inner_99BD917DA5EDFC3D {}
			}
			"""],
			"App": ["App.swift": """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_serviceBuilder_Host() -> Host.__safeDI_ServiceCarrier<any Service> {
			            .init(first: __safeDI_serviceBuilder_Inner(), second: __safeDI_serviceBuilder_Inner())
			        }
			        func __safeDI_serviceBuilder_Inner() -> Inner.__safeDI_ServiceCarrier<any Service> {
			            .init(service: {
			                let service: any Service = DefaultService()
			                return service
			            })
			        }
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_10E1F3F1E8CC3D0D.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Host(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Host())
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
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
			        public let service: () -> __safeDI_Built

			        public init(service: @escaping () -> __safeDI_Built) {
			            self.service = service
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(service: { __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
			        let service: any Service = __safeDI_serviceBuilder.service()
			        self.init(service: service)
			    }
			}

			extension Deep {
			    public enum __safeDI_Deep_24C4D6B7262EE267 {}
			}

			extension Host {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
			        public let mid: Mid.__safeDI_ServiceCarrier<__safeDI_Built>

			        public init(mid: Mid.__safeDI_ServiceCarrier<__safeDI_Built>) {
			            self.mid = mid
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(mid: .init(__safeDI_noScope: __safeDI_builder))
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
			        func __safeDI_mid() -> Mid {
			            _ = Mid.__safeDI_Mid_14E719AD28B2294D.self
			            return Mid(__safeDI_serviceBuilder: __safeDI_serviceBuilder.mid)
			        }
			        let mid: Mid = __safeDI_mid()
			        self.init(mid: mid)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_00B80B51F1C0DBBF {}
			}

			extension Mid {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
			        public let deep: Deep.__safeDI_ServiceCarrier<__safeDI_Built>

			        public init(deep: Deep.__safeDI_ServiceCarrier<__safeDI_Built>) {
			            self.deep = deep
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(deep: .init(__safeDI_noScope: __safeDI_builder))
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
			        func __safeDI_deep() -> Deep {
			            _ = Deep.__safeDI_Deep_24C4D6B7262EE267.self
			            return Deep(__safeDI_serviceBuilder: __safeDI_serviceBuilder.deep)
			        }
			        let deep: Deep = __safeDI_deep()
			        self.init(deep: deep)
			    }
			}

			extension Mid {
			    public enum __safeDI_Mid_14E719AD28B2294D {}
			}
			"""],
			"App": ["App.swift": """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_serviceBuilder_Host() -> Host.__safeDI_ServiceCarrier<any Service> {
			            .init(mid: __safeDI_serviceBuilder_Mid())
			        }
			        func __safeDI_serviceBuilder_Mid() -> Mid.__safeDI_ServiceCarrier<any Service> {
			            .init(deep: __safeDI_serviceBuilder_Deep())
			        }
			        func __safeDI_serviceBuilder_Deep() -> Deep.__safeDI_ServiceCarrier<any Service> {
			            .init(service: {
			                let service: any Service = DefaultService()
			                return service
			            })
			        }
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_00B80B51F1C0DBBF.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Host(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Host())
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
		        public let deep: Deep.__safeDI_ServiceCarrier<__safeDI_Built>

		        public init(deep: Deep.__safeDI_ServiceCarrier<__safeDI_Built>) {
		            self.deep = deep
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(deep: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
		        func __safeDI_deep() -> Deep {
		            _ = Deep.__safeDI_Deep_24C4D6B7262EE267.self // If this line does not compile, compile the code SafeDI generates for module Lower into Lower: under Bazel, add Lower’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Deep(__safeDI_serviceBuilder: __safeDI_serviceBuilder.deep)
		        }
		        let deep: Deep = __safeDI_deep()
		        self.init(deep: deep)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_0E589766B056A983 {}
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
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
			        public let plain: Inner.__safeDI_ServiceCarrier<__safeDI_Built>

			        public init(plain: Inner.__safeDI_ServiceCarrier<__safeDI_Built>) {
			            self.plain = plain
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(plain: .init(__safeDI_noScope: __safeDI_builder))
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceSendableCarrier<__safeDI_Built>: Sendable {
			        public let held: @Sendable () -> Inner.__safeDI_ServiceCarrier<__safeDI_Built>

			        public init(held: @escaping @Sendable () -> Inner.__safeDI_ServiceCarrier<__safeDI_Built>) {
			            self.held = held
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			            self.init(held: { .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>, __safeDI_serviceSendableBuilder: __safeDI_ServiceSendableCarrier<any Service>) {
			        func __safeDI_plain() -> Inner {
			            _ = Inner.__safeDI_Inner_99BD917DA5EDFC3D.self
			            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder.plain)
			        }
			        let plain: Inner = __safeDI_plain()
			        @Sendable nonisolated func __safeDI_held() -> Inner {
			            _ = Inner.__safeDI_Inner_99BD917DA5EDFC3D.self
			            return Inner(__safeDI_serviceBuilder: __safeDI_serviceSendableBuilder.held())
			        }
			        let held = SendableInstantiator<Inner>(__safeDI_held)
			        self.init(plain: plain, held: held)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_9550B0BEF688A6B7 {}
			}

			extension Inner {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
			        public let service: () -> __safeDI_Built

			        public init(service: @escaping () -> __safeDI_Built) {
			            self.service = service
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(service: { __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
			        let service: any Service = __safeDI_serviceBuilder.service()
			        self.init(service: service)
			    }
			}

			extension Inner {
			    public enum __safeDI_Inner_99BD917DA5EDFC3D {}
			}
			"""],
			"App": ["App.swift": """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_serviceBuilder_Host() -> Host.__safeDI_ServiceCarrier<any Service> {
			            .init(plain: __safeDI_serviceBuilder_Inner())
			        }
			        @Sendable nonisolated func __safeDI_serviceBuilder_Inner() -> Inner.__safeDI_ServiceCarrier<any Service> {
			            .init(service: {
			                let service: any Service = DefaultService()
			                return service
			            })
			        }
			        @Sendable nonisolated func __safeDI_serviceSendableBuilder_Host() -> Host.__safeDI_ServiceSendableCarrier<any Service> {
			            .init(held: { __safeDI_serviceBuilder_Inner() })
			        }
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_9550B0BEF688A6B7.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Host(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Host(), __safeDI_serviceSendableBuilder: __safeDI_serviceSendableBuilder_Host())
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
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
			        public let service: () -> __safeDI_Built

			        public init(service: @escaping () -> __safeDI_Built) {
			            self.service = service
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(service: { __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
			        let service: any Service = __safeDI_serviceBuilder.service()
			        self.init(service: service)
			    }
			}

			extension Deep {
			    public enum __safeDI_Deep_24C4D6B7262EE267 {}
			}

			extension Host {
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

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceSendableCarrier<__safeDI_Built>: Sendable {
			        public let inner_Sendable: Inner.__safeDI_ServiceSendableCarrier<__safeDI_Built>

			        public init(inner_Sendable: Inner.__safeDI_ServiceSendableCarrier<__safeDI_Built>) {
			            self.inner_Sendable = inner_Sendable
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			            self.init(inner_Sendable: .init(__safeDI_noScope: __safeDI_builder))
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>, __safeDI_serviceSendableBuilder: __safeDI_ServiceSendableCarrier<any Service>) {
			        func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_68297CC35FF95BC7.self
			            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder.inner, __safeDI_serviceSendableBuilder: __safeDI_serviceSendableBuilder.inner_Sendable)
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(inner: inner)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_A7DF80B9E6DEF022 {}
			}

			extension Inner {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
			        public let plain: Deep.__safeDI_ServiceCarrier<__safeDI_Built>

			        public init(plain: Deep.__safeDI_ServiceCarrier<__safeDI_Built>) {
			            self.plain = plain
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(plain: .init(__safeDI_noScope: __safeDI_builder))
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceSendableCarrier<__safeDI_Built>: Sendable {
			        public let held: @Sendable () -> Deep.__safeDI_ServiceCarrier<__safeDI_Built>

			        public init(held: @escaping @Sendable () -> Deep.__safeDI_ServiceCarrier<__safeDI_Built>) {
			            self.held = held
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			            self.init(held: { .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>, __safeDI_serviceSendableBuilder: __safeDI_ServiceSendableCarrier<any Service>) {
			        func __safeDI_plain() -> Deep {
			            _ = Deep.__safeDI_Deep_24C4D6B7262EE267.self
			            return Deep(__safeDI_serviceBuilder: __safeDI_serviceBuilder.plain)
			        }
			        let plain: Deep = __safeDI_plain()
			        @Sendable nonisolated func __safeDI_held() -> Deep {
			            _ = Deep.__safeDI_Deep_24C4D6B7262EE267.self
			            return Deep(__safeDI_serviceBuilder: __safeDI_serviceSendableBuilder.held())
			        }
			        let held = SendableInstantiator<Deep>(__safeDI_held)
			        self.init(plain: plain, held: held)
			    }
			}

			extension Inner {
			    public enum __safeDI_Inner_68297CC35FF95BC7 {}
			}
			"""],
			"App": ["App.swift": """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_serviceBuilder_Host() -> Host.__safeDI_ServiceCarrier<any Service> {
			            .init(inner: __safeDI_serviceBuilder_Inner())
			        }
			        func __safeDI_serviceBuilder_Inner() -> Inner.__safeDI_ServiceCarrier<any Service> {
			            .init(plain: __safeDI_serviceBuilder_Deep())
			        }
			        @Sendable nonisolated func __safeDI_serviceBuilder_Deep() -> Deep.__safeDI_ServiceCarrier<any Service> {
			            .init(service: {
			                let service: any Service = DefaultService()
			                return service
			            })
			        }
			        @Sendable nonisolated func __safeDI_serviceSendableBuilder_Host() -> Host.__safeDI_ServiceSendableCarrier<any Service> {
			            .init(inner_Sendable: __safeDI_serviceSendableBuilder_Inner())
			        }
			        @Sendable nonisolated func __safeDI_serviceSendableBuilder_Inner() -> Inner.__safeDI_ServiceSendableCarrier<any Service> {
			            .init(held: { __safeDI_serviceBuilder_Deep() })
			        }
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_A7DF80B9E6DEF022.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Host(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Host(), __safeDI_serviceSendableBuilder: __safeDI_serviceSendableBuilder_Host())
			        }
			        let host: Host = __safeDI_host()
			        self.init(host: host)
			    }
			}
			"""],
		], visible: Self.modules(feature: feature + [fulfiller], app: [root]))
	}

	// MARK: 5. Places inside `@Sendable` functions

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesSendableBuilder_whenPlaceIsBuiltInsideASendableFunction() async throws {
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
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceCarrier_Job<__safeDI_Built> {
			        public let service: () -> __safeDI_Built

			        public init(service: @escaping () -> __safeDI_Built) {
			            self.service = service
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(service: { __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceSendableCarrier<__safeDI_Built>: Sendable {
			        public let job: @Sendable () -> __safeDI_ServiceCarrier_Job<__safeDI_Built>

			        public init(job: @escaping @Sendable () -> __safeDI_ServiceCarrier_Job<__safeDI_Built>) {
			            self.job = job
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			            self.init(job: { .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_serviceSendableBuilder: __safeDI_ServiceSendableCarrier<any Service>) {
			        @Sendable nonisolated func __safeDI_job() -> Job {
			            let __safeDI_serviceSendableBuilder_job = __safeDI_serviceSendableBuilder.job()
			            let service: any Service = __safeDI_serviceSendableBuilder_job.service()
			            return Job(service: service)
			        }
			        let job = SendableInstantiator<Job>(__safeDI_job)
			        self.init(job: job)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_61618E265A173DF6 {}
			}
			"""],
			"App": ["App.swift": """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        @Sendable nonisolated func __safeDI_serviceSendableBuilder_Host() -> Host.__safeDI_ServiceSendableCarrier<any Service> {
			            .init(job: { __safeDI_serviceBuilder_Host_Job_Scope() })
			        }
			        @Sendable nonisolated func __safeDI_serviceBuilder_Host_Job_Scope() -> Host.__safeDI_ServiceCarrier_Job<any Service> {
			            .init(service: {
			                let service: any Service = DefaultService()
			                return service
			            })
			        }
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_61618E265A173DF6.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Host(__safeDI_serviceSendableBuilder: __safeDI_serviceSendableBuilder_Host())
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
	mutating func generate_passesInnerSendableEnumUp_whenPlaceOfInnerSeamIsInsideSendableFunction(declaration: String, route: String) async throws {
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
		// `Inner`'s place is inside its own `@Sendable` function, so `Host` takes a `Sendable` carrier whose `let` child of
		// each call's property is `Inner`'s `Sendable` carrier, wherever the call is.
		let hostExtension = SafeDIToolSeamBuilderParameterTests.seamExtension(in: generated, named: "Host")
		let expectedHostExtensions = [
			"plain": """
			extension Host {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceSendableCarrier<__safeDI_Built>: Sendable {
			        public let inner_Sendable: Inner.__safeDI_ServiceSendableCarrier<__safeDI_Built>

			        public init(inner_Sendable: Inner.__safeDI_ServiceSendableCarrier<__safeDI_Built>) {
			            self.inner_Sendable = inner_Sendable
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			            self.init(inner_Sendable: .init(__safeDI_noScope: __safeDI_builder))
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_serviceSendableBuilder: __safeDI_ServiceSendableCarrier<any Service>) {
			        func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_307337C475868692.self
			            return Inner(__safeDI_serviceSendableBuilder: __safeDI_serviceSendableBuilder.inner_Sendable)
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(inner: inner)
			    }
			}
			""",
			"sendable": """
			extension Host {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceSendableCarrier<__safeDI_Built>: Sendable {
			        public let held_Sendable: Inner.__safeDI_ServiceSendableCarrier<__safeDI_Built>

			        public init(held_Sendable: Inner.__safeDI_ServiceSendableCarrier<__safeDI_Built>) {
			            self.held_Sendable = held_Sendable
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			            self.init(held_Sendable: .init(__safeDI_noScope: __safeDI_builder))
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_serviceSendableBuilder: __safeDI_ServiceSendableCarrier<any Service>) {
			        @Sendable nonisolated func __safeDI_held() -> Inner {
			            _ = Inner.__safeDI_Inner_307337C475868692.self
			            return Inner(__safeDI_serviceSendableBuilder: __safeDI_serviceSendableBuilder.held_Sendable)
			        }
			        let held = SendableInstantiator<Inner>(__safeDI_held)
			        self.init(held: held)
			    }
			}
			""",
			"both": """
			extension Host {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceSendableCarrier<__safeDI_Built>: Sendable {
			        public let inner_Sendable: Inner.__safeDI_ServiceSendableCarrier<__safeDI_Built>
			        public let held_Sendable: Inner.__safeDI_ServiceSendableCarrier<__safeDI_Built>

			        public init(inner_Sendable: Inner.__safeDI_ServiceSendableCarrier<__safeDI_Built>, held_Sendable: Inner.__safeDI_ServiceSendableCarrier<__safeDI_Built>) {
			            self.inner_Sendable = inner_Sendable
			            self.held_Sendable = held_Sendable
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			            self.init(inner_Sendable: .init(__safeDI_noScope: __safeDI_builder), held_Sendable: .init(__safeDI_noScope: __safeDI_builder))
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_serviceSendableBuilder: __safeDI_ServiceSendableCarrier<any Service>) {
			        func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_307337C475868692.self
			            return Inner(__safeDI_serviceSendableBuilder: __safeDI_serviceSendableBuilder.inner_Sendable)
			        }
			        let inner: Inner = __safeDI_inner()
			        @Sendable nonisolated func __safeDI_held() -> Inner {
			            _ = Inner.__safeDI_Inner_307337C475868692.self
			            return Inner(__safeDI_serviceSendableBuilder: __safeDI_serviceSendableBuilder.held_Sendable)
			        }
			        let held = SendableInstantiator<Inner>(__safeDI_held)
			        self.init(inner: inner, held: held)
			    }
			}
			""",
		]
		#expect(hostExtension == expectedHostExtensions[route], "\(generated)")
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
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
			        public let service: (Instantiator<B>) -> __safeDI_Built
			        public let bBuilder: () -> B.__safeDI_ServiceCarrier<__safeDI_Built>

			        public init(service: @escaping (Instantiator<B>) -> __safeDI_Built, bBuilder: @escaping () -> B.__safeDI_ServiceCarrier<__safeDI_Built>) {
			            self.service = service
			            self.bBuilder = bBuilder
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(service: { _ in __safeDI_builder() }, bBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
			        func __safeDI_bBuilder() -> B {
			            _ = B.__safeDI_B_4310AAFCAAE5697A.self
			            return B(__safeDI_serviceBuilder: __safeDI_serviceBuilder.bBuilder())
			        }
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        let service: any Service = __safeDI_serviceBuilder.service(bBuilder)
			        self.init(service: service, bBuilder: bBuilder)
			    }
			}

			extension A {
			    public enum __safeDI_A_4310AAFCAAE5697A {}
			}

			extension B {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
			        public let aBuilder: () -> A.__safeDI_ServiceCarrier<__safeDI_Built>

			        public init(aBuilder: @escaping () -> A.__safeDI_ServiceCarrier<__safeDI_Built>) {
			            self.aBuilder = aBuilder
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(aBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
			        func __safeDI_aBuilder() -> A {
			            _ = A.__safeDI_A_4310AAFCAAE5697A.self
			            return A(__safeDI_serviceBuilder: __safeDI_serviceBuilder.aBuilder())
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			        self.init(aBuilder: aBuilder)
			    }
			}

			extension B {
			    public enum __safeDI_B_4310AAFCAAE5697A {}
			}
			"""],
			"App": ["App.swift": """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_serviceBuilder_A() -> A.__safeDI_ServiceCarrier<any Service> {
			            .init(
			                service: { scope_bBuilder in
			                    let service: any Service = DefaultService()
			                    return service
			                },
			                bBuilder: { __safeDI_serviceBuilder_B() }
			            )
			        }
			        func __safeDI_serviceBuilder_B() -> B.__safeDI_ServiceCarrier<any Service> {
			            .init(aBuilder: { __safeDI_serviceBuilder_A() })
			        }
			        func __safeDI_a() -> A {
			            _ = A.__safeDI_A_4310AAFCAAE5697A.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return A(__safeDI_serviceBuilder: __safeDI_serviceBuilder_A())
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
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
			        public let service: (Instantiator<B>) -> __safeDI_Built

			        public init(service: @escaping (Instantiator<B>) -> __safeDI_Built) {
			            self.service = service
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(service: { _ in __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceSendableCarrier<__safeDI_Built>: Sendable {
			        public let bBuilder_Sendable: @Sendable () -> B.__safeDI_ServiceSendableCarrier<__safeDI_Built>

			        public init(bBuilder_Sendable: @escaping @Sendable () -> B.__safeDI_ServiceSendableCarrier<__safeDI_Built>) {
			            self.bBuilder_Sendable = bBuilder_Sendable
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			            self.init(bBuilder_Sendable: { .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>, __safeDI_serviceSendableBuilder: __safeDI_ServiceSendableCarrier<any Service>) {
			        func __safeDI_bBuilder() -> B {
			            _ = B.__safeDI_B_1FF857DACA85E0C8.self
			            return B(__safeDI_serviceSendableBuilder: __safeDI_serviceSendableBuilder.bBuilder_Sendable())
			        }
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        let service: any Service = __safeDI_serviceBuilder.service(bBuilder)
			        self.init(service: service, bBuilder: bBuilder)
			    }
			}

			extension A {
			    public enum __safeDI_A_0CBC6A899F21E707 {}
			}

			extension B {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceSendableCarrier<__safeDI_Built>: Sendable {
			        public let aBuilder: @Sendable () -> A.__safeDI_ServiceCarrier<__safeDI_Built>
			        public let aBuilder_Sendable: @Sendable () -> A.__safeDI_ServiceSendableCarrier<__safeDI_Built>

			        public init(aBuilder: @escaping @Sendable () -> A.__safeDI_ServiceCarrier<__safeDI_Built>, aBuilder_Sendable: @escaping @Sendable () -> A.__safeDI_ServiceSendableCarrier<__safeDI_Built>) {
			            self.aBuilder = aBuilder
			            self.aBuilder_Sendable = aBuilder_Sendable
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			            self.init(aBuilder: { .init(__safeDI_noScope: __safeDI_builder) }, aBuilder_Sendable: { .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_serviceSendableBuilder: __safeDI_ServiceSendableCarrier<any Service>) {
			        @Sendable nonisolated func __safeDI_aBuilder() -> A {
			            _ = A.__safeDI_A_0CBC6A899F21E707.self
			            return A(__safeDI_serviceBuilder: __safeDI_serviceSendableBuilder.aBuilder(), __safeDI_serviceSendableBuilder: __safeDI_serviceSendableBuilder.aBuilder_Sendable())
			        }
			        let aBuilder = SendableInstantiator<A>(__safeDI_aBuilder)
			        self.init(aBuilder: aBuilder)
			    }
			}

			extension B {
			    public enum __safeDI_B_1FF857DACA85E0C8 {}
			}
			"""],
			"App": ["App.swift": """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        @Sendable nonisolated func __safeDI_serviceBuilder_A() -> A.__safeDI_ServiceCarrier<any Service> {
			            .init(service: { scope_bBuilder in
			                let service: any Service = DefaultService()
			                return service
			            })
			        }
			        @Sendable nonisolated func __safeDI_serviceSendableBuilder_A() -> A.__safeDI_ServiceSendableCarrier<any Service> {
			            .init(bBuilder_Sendable: { __safeDI_serviceSendableBuilder_B() })
			        }
			        @Sendable nonisolated func __safeDI_serviceSendableBuilder_B() -> B.__safeDI_ServiceSendableCarrier<any Service> {
			            .init(aBuilder: { __safeDI_serviceBuilder_A() }, aBuilder_Sendable: { __safeDI_serviceSendableBuilder_A() })
			        }
			        func __safeDI_a() -> A {
			            _ = A.__safeDI_A_0CBC6A899F21E707.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return A(__safeDI_serviceBuilder: __safeDI_serviceBuilder_A(), __safeDI_serviceSendableBuilder: __safeDI_serviceSendableBuilder_A())
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
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
			        public let service: (Instantiator<S>) -> __safeDI_Built
			        public let nextBuilder: () -> S.__safeDI_ServiceCarrier<__safeDI_Built>

			        public init(service: @escaping (Instantiator<S>) -> __safeDI_Built, nextBuilder: @escaping () -> S.__safeDI_ServiceCarrier<__safeDI_Built>) {
			            self.service = service
			            self.nextBuilder = nextBuilder
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(service: { _ in __safeDI_builder() }, nextBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
			        func __safeDI_nextBuilder() -> S {
			            _ = S.__safeDI_S_004BE8E9F6F4AA37.self
			            return S(__safeDI_serviceBuilder: __safeDI_serviceBuilder.nextBuilder())
			        }
			        let nextBuilder = Instantiator<S>(__safeDI_nextBuilder)
			        let service: any Service = __safeDI_serviceBuilder.service(nextBuilder)
			        self.init(service: service, nextBuilder: nextBuilder)
			    }
			}

			extension S {
			    public enum __safeDI_S_004BE8E9F6F4AA37 {}
			}
			"""],
			"App": ["App.swift": """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_serviceBuilder_S() -> S.__safeDI_ServiceCarrier<any Service> {
			            .init(
			                service: { scope_nextBuilder in
			                    let service: any Service = DefaultService()
			                    return service
			                },
			                nextBuilder: { __safeDI_serviceBuilder_S() }
			            )
			        }
			        func __safeDI_s() -> S {
			            _ = S.__safeDI_S_004BE8E9F6F4AA37.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return S(__safeDI_serviceBuilder: __safeDI_serviceBuilder_S())
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
	mutating func generate_holdsItsOwnEnumIndirectlyInTheChildsEnum_whenATypeTheSeamBuildsReentersTheSeam() async throws {
		let feature = [
			Self.service,
			Self.type("Step", ["@Instantiated public let sBuilder: Instantiator<S>"]),
			Self.type("S", seam: true, ["@Instantiated public let service: any Service", "@Instantiated public let step: Step"]),
		]
		let fulfiller = Self.fulfilling("DefaultService", "Service")
		let root = Self.root(["@Instantiated public let s: S"])
		try await expectOutput(of: Self.modules(feature: feature, app: [fulfiller, root]), [
			"Feature": ["Feature.swift": """
			extension S {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
			        public let service: (Step) -> __safeDI_Built
			        public let step: () -> __safeDI_ServiceCarrier_Step<__safeDI_Built>

			        public init(service: @escaping (Step) -> __safeDI_Built, step: @escaping () -> __safeDI_ServiceCarrier_Step<__safeDI_Built>) {
			            self.service = service
			            self.step = step
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(service: { _ in __safeDI_builder() }, step: { .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceCarrier_Step<__safeDI_Built> {
			        public let sBuilder: () -> S.__safeDI_ServiceCarrier<__safeDI_Built>

			        public init(sBuilder: @escaping () -> S.__safeDI_ServiceCarrier<__safeDI_Built>) {
			            self.sBuilder = sBuilder
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(sBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
			        let __safeDI_serviceBuilder_step = __safeDI_serviceBuilder.step()
			        func __safeDI_step() -> Step {
			            func __safeDI_sBuilder() -> S {
			                _ = S.__safeDI_S_2503D99080B73F48.self
			                return S(__safeDI_serviceBuilder: __safeDI_serviceBuilder_step.sBuilder())
			            }
			            let sBuilder = Instantiator<S>(__safeDI_sBuilder)
			            return Step(sBuilder: sBuilder)
			        }
			        let step: Step = __safeDI_step()
			        let service: any Service = __safeDI_serviceBuilder.service(step)
			        self.init(service: service, step: step)
			    }
			}

			extension S {
			    public enum __safeDI_S_2503D99080B73F48 {}
			}
			"""],
			"App": ["App.swift": """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_serviceBuilder_S() -> S.__safeDI_ServiceCarrier<any Service> {
			            .init(
			                service: { scope_step in
			                    let service: any Service = DefaultService()
			                    return service
			                },
			                step: { __safeDI_serviceBuilder_S_Step_Scope() }
			            )
			        }
			        func __safeDI_serviceBuilder_S_Step_Scope() -> S.__safeDI_ServiceCarrier_Step<any Service> {
			            .init(sBuilder: { __safeDI_serviceBuilder_S() })
			        }
			        func __safeDI_s() -> S {
			            _ = S.__safeDI_S_2503D99080B73F48.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return S(__safeDI_serviceBuilder: __safeDI_serviceBuilder_S())
			        }
			        let s: S = __safeDI_s()
			        self.init(s: s)
			    }
			}
			"""],
		], visible: Self.modules(feature: feature + [fulfiller], app: [root]), probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().s.step.sBuilder.instantiate().step.sBuilder.instantiate()")])
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
		        public let bBuilder: () -> B.__safeDI_ServiceCarrier<__safeDI_Built>
		        public let c: C.__safeDI_ServiceCarrier<__safeDI_Built>

		        public init(bBuilder: @escaping () -> B.__safeDI_ServiceCarrier<__safeDI_Built>, c: C.__safeDI_ServiceCarrier<__safeDI_Built>) {
		            self.bBuilder = bBuilder
		            self.c = c
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(bBuilder: { .init(__safeDI_noScope: __safeDI_builder) }, c: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
		        func __safeDI_bBuilder() -> B {
		            _ = B.__safeDI_B_60CD4BBEB4782A0F.self
		            return B(__safeDI_serviceBuilder: __safeDI_serviceBuilder.bBuilder())
		        }
		        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		        func __safeDI_c() -> C {
		            _ = C.__safeDI_C_04E4814C5A0B918A.self
		            return C(__safeDI_serviceBuilder: __safeDI_serviceBuilder.c)
		        }
		        let c: C = __safeDI_c()
		        self.init(bBuilder: bBuilder, c: c)
		    }
		}

		extension A {
		    public enum __safeDI_A_60CD4BBEB4782A0F {}
		}

		extension B {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
		        public let aBuilder: () -> A.__safeDI_ServiceCarrier<__safeDI_Built>

		        public init(aBuilder: @escaping () -> A.__safeDI_ServiceCarrier<__safeDI_Built>) {
		            self.aBuilder = aBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(aBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
		        func __safeDI_aBuilder() -> A {
		            _ = A.__safeDI_A_60CD4BBEB4782A0F.self
		            return A(__safeDI_serviceBuilder: __safeDI_serviceBuilder.aBuilder())
		        }
		        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		        self.init(aBuilder: aBuilder)
		    }
		}

		extension B {
		    public enum __safeDI_B_60CD4BBEB4782A0F {}
		}

		extension C {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
		        public let service: () -> __safeDI_Built

		        public init(service: @escaping () -> __safeDI_Built) {
		            self.service = service
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(service: { __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
		        let service: any Service = __safeDI_serviceBuilder.service()
		        self.init(service: service)
		    }
		}

		extension C {
		    public enum __safeDI_C_04E4814C5A0B918A {}
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
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_NamedGadget_AnyGadgetCarrier<__safeDI_Built> {
			        public let maker: () -> ErasedInstantiator<(count: Int, name: Name), __safeDI_Built>.Builder

			        public init(maker: @escaping () -> ErasedInstantiator<(count: Int, name: Name), __safeDI_Built>.Builder) {
			            self.maker = maker
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<(count: Int, name: Name), __safeDI_Built>.Builder) {
			            self.init(maker: { __safeDI_builder })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_namedGadget_AnyGadgetBuilder: __safeDI_NamedGadget_AnyGadgetCarrier<AnyGadget>) {
			        let maker = ErasedInstantiator<(count: Int, name: Name), AnyGadget>(__safeDI_namedGadget_AnyGadgetBuilder.maker())
			        self.init(maker: maker)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_CA1A5978999B46CD {}
			}
			"""],
			"App": ["App.swift": """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_namedGadget_AnyGadgetBuilder_Host_maker() -> ErasedInstantiator<(count: Int, name: Name), AnyGadget>.Builder {
			            return __safeDI_fillBody_60F13CDE44B58A54()
			        }
			        func __safeDI_fillBody_60F13CDE44B58A54() -> ErasedInstantiator<(count: Int, name: Name), AnyGadget>.Builder {
			            func __safeDI_maker(count: Int, name: Name) -> NamedGadget {
			                NamedGadget(name: name, count: count)
			            }
			            return { forwarded in AnyGadget(__safeDI_maker(count: forwarded.count, name: forwarded.name)) }
			        }
			        func __safeDI_namedGadget_AnyGadgetBuilder_Host() -> Host.__safeDI_NamedGadget_AnyGadgetCarrier<AnyGadget> {
			            .init(maker: { __safeDI_namedGadget_AnyGadgetBuilder_Host_maker() })
			        }
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_CA1A5978999B46CD.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Host(__safeDI_namedGadget_AnyGadgetBuilder: __safeDI_namedGadget_AnyGadgetBuilder_Host())
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
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
			        public let `default`: () -> __safeDI_Built
			        public let `my leaf`: (any Service) -> __safeDI_Built

			        public init(`default`: @escaping () -> __safeDI_Built, `my leaf`: @escaping (any Service) -> __safeDI_Built) {
			            self.`default` = `default`
			            self.`my leaf` = `my leaf`
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(default: { __safeDI_builder() }, `my leaf`: { _ in __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
			        let `default`: any Service = __safeDI_serviceBuilder.`default`()
			        let `my leaf`: any Service = __safeDI_serviceBuilder.`my leaf`(`default`)
			        self.init(default: `default`, `my leaf`: `my leaf`)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_565B301CC85E713B {}
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_KPCarrier<__safeDI_Built> {
		        public let kp: (any URLLoader) -> __safeDI_Built

		        public init(kp: @escaping (any URLLoader) -> __safeDI_Built) {
		            self.kp = kp
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(kp: { _ in __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_URLLoaderCarrier<__safeDI_Built> {
		        public let loader: () -> __safeDI_Built

		        public init(loader: @escaping () -> __safeDI_Built) {
		            self.loader = loader
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(loader: { __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_kpBuilder: __safeDI_KPCarrier<any KP>, __safeDI_urlLoaderBuilder: __safeDI_URLLoaderCarrier<any URLLoader>) {
		        let loader: any URLLoader = __safeDI_urlLoaderBuilder.loader()
		        let kp: any KP = __safeDI_kpBuilder.kp(loader)
		        self.init(loader: loader, kp: kp)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_0F78EA8EE826A127 {}
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_lowersLeadingCapitalsKeepingTheLastBeforeALowercaseLetter_whenTypeNameIsNotASCII() async throws {
		let feature = [
			"public protocol ÄÖLoader {}",
			Self.type("Host", seam: true, ["@Instantiated public let loader: any ÄÖLoader"]),
		]
		let output = try await compiledOutput(of: [ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature)])
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ÄÖLoaderCarrier<__safeDI_Built> {
		        public let loader: () -> __safeDI_Built

		        public init(loader: @escaping () -> __safeDI_Built) {
		            self.loader = loader
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(loader: { __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_äöLoaderBuilder: __safeDI_ÄÖLoaderCarrier<any ÄÖLoader>) {
		        let loader: any ÄÖLoader = __safeDI_äöLoaderBuilder.loader()
		        self.init(loader: loader)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_9F6159AF378F031D {}
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
		        public let service: (Int) -> __safeDI_Built

		        public init(service: @escaping (Int) -> __safeDI_Built) {
		            self.service = service
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(service: { _ in __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_serviceBuilder serviceBuilder: Int, __safeDI_serviceBuilder_: __safeDI_ServiceCarrier<any Service>) {
		        let service: any Service = __safeDI_serviceBuilder_.service(serviceBuilder)
		        self.init(serviceBuilder: serviceBuilder, service: service)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_15A006FCA81B23DA {}
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
		        public let service: () -> __safeDI_Built
		        public let service_Values: (any Service) -> __safeDI_Built

		        public init(service: @escaping () -> __safeDI_Built, service_Values: @escaping (any Service) -> __safeDI_Built) {
		            self.service = service
		            self.service_Values = service_Values
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(service: { __safeDI_builder() }, service_Values: { _ in __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
		        let service: any Service = __safeDI_serviceBuilder.service()
		        let service_Values: any Service = __safeDI_serviceBuilder.service_Values(service)
		        self.init(service: service, service_Values: service_Values)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_A795FA68FD94379A {}
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesHoleTypesApartByTheirTypes_whenTwoTypesAreSpelledAsOneIdentifier() async throws {
		// `Outer.Thing` and `Outer_Thing` are spelled as one identifier, so their stems are equal and each is named by its types.
		let feature = [
			"public enum Outer {\n    public struct Thing {}\n}",
			"public struct Outer_Thing {}",
			Self.type("Host", seam: true, ["@Instantiated public let nested: Outer.Thing", "@Instantiated public let joined: Outer_Thing"]),
		]
		let output = try await compiledOutput(of: [ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature)])
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_Outer_Thing_Outer_ThingCarrier<__safeDI_Built> {
		        public let nested: () -> __safeDI_Built

		        public init(nested: @escaping () -> __safeDI_Built) {
		            self.nested = nested
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(nested: { __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_Outer_Thing_Outer_Thing_Carrier<__safeDI_Built> {
		        public let joined: (Outer.Thing) -> __safeDI_Built

		        public init(joined: @escaping (Outer.Thing) -> __safeDI_Built) {
		            self.joined = joined
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(joined: { _ in __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_outer_Thing_Outer_ThingBuilder: __safeDI_Outer_Thing_Outer_ThingCarrier<Outer.Thing>, __safeDI_outer_Thing_Outer_Thing_Builder: __safeDI_Outer_Thing_Outer_Thing_Carrier<Outer_Thing>) {
		        let nested: Outer.Thing = __safeDI_outer_Thing_Outer_ThingBuilder.nested()
		        let joined: Outer_Thing = __safeDI_outer_Thing_Outer_Thing_Builder.joined(nested)
		        self.init(nested: nested, joined: joined)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_F9F08EA56D668604 {}
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_appendsUnderscoreToALabel_whenItEqualsAParametersAfterNamingByTypes() async throws {
		// As the previous test, with a parameter labeled as the builder of `Outer.Thing` is once named by its types: that
		// builder's label takes `_`, and its enum keeps its name.
		let feature = [
			"public enum Outer {\n    public struct Thing {}\n}",
			"public struct Outer_Thing {}",
			Self.type("Host", seam: true, [
				"@Received public let outer_Thing_Outer_ThingBuilder: Int",
				"@Instantiated public let nested: Outer.Thing",
				"@Instantiated public let joined: Outer_Thing",
			]),
		]
		let output = try await compiledOutput(of: [ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature)])
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_Outer_Thing_Outer_ThingCarrier<__safeDI_Built> {
		        public let nested: (Int) -> __safeDI_Built

		        public init(nested: @escaping (Int) -> __safeDI_Built) {
		            self.nested = nested
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(nested: { _ in __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_Outer_Thing_Outer_Thing_Carrier<__safeDI_Built> {
		        public let joined: (Int, Outer.Thing) -> __safeDI_Built

		        public init(joined: @escaping (Int, Outer.Thing) -> __safeDI_Built) {
		            self.joined = joined
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(joined: { _, _ in __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_outer_Thing_Outer_ThingBuilder outer_Thing_Outer_ThingBuilder: Int, __safeDI_outer_Thing_Outer_ThingBuilder_: __safeDI_Outer_Thing_Outer_ThingCarrier<Outer.Thing>, __safeDI_outer_Thing_Outer_Thing_Builder: __safeDI_Outer_Thing_Outer_Thing_Carrier<Outer_Thing>) {
		        let nested: Outer.Thing = __safeDI_outer_Thing_Outer_ThingBuilder_.nested(outer_Thing_Outer_ThingBuilder)
		        let joined: Outer_Thing = __safeDI_outer_Thing_Outer_Thing_Builder.joined(outer_Thing_Outer_ThingBuilder, nested)
		        self.init(outer_Thing_Outer_ThingBuilder: outer_Thing_Outer_ThingBuilder, nested: nested, joined: joined)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_EA011CE24EDCB3BD {}
		}
		"""])
	}

	// MARK: B. One allocation of names per generated scope

	@Test(arguments: [
		["inner", "innerJob", "staged"], ["inner", "staged", "innerJob"], ["innerJob", "inner", "staged"], ["innerJob", "staged", "inner"], ["staged", "inner", "innerJob"], ["staged", "innerJob", "inner"],
	])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesGeneratedFunctionsApart_whenADispatcherEqualsAFillsNameInAnyDeclarationOrder(order: [String]) async throws {
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
		#expect(declaredNames.count == 8)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesGeneratedFunctionsApart_whenADispatcherEqualsAFillsName() async throws {
		// `Inner`'s place `job` fills as `__safeDI_serviceBuilder_Inner_Inner_job`, which is also the dispatcher of
		// `Inner_Inner_job`'s enum. The fills are claimed first, in the order the builders reach them, so the dispatcher is
		// renamed. `Staged`'s place, inside a `@Sendable` function, is reached through the `@Sendable` builder's dispatchers.
		try await expectOutput(of: Self.collidingNamesModules(order: ["inner", "innerJob", "staged"]), [
			"App": ["App.swift": """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_serviceBuilder_Inner_Inner_job(_ scope__scope: Token) -> any Service {
			            let job: any Service = DefaultService()
			            return job
			        }
			        func __safeDI_serviceBuilder_Host() -> Host.__safeDI_ServiceCarrier<any Service> {
			            .init(inner: __safeDI_serviceBuilder_Inner(), innerJob: __safeDI_serviceBuilder_Inner_Inner_job_())
			        }
			        func __safeDI_serviceBuilder_Inner() -> Inner.__safeDI_ServiceCarrier<any Service> {
			            .init(job: { scope_scope in __safeDI_serviceBuilder_Inner_Inner_job(scope_scope) })
			        }
			        func __safeDI_serviceBuilder_Inner_Inner_job_() -> Inner_Inner_job.__safeDI_ServiceCarrier<any Service> {
			            .init(service: {
			                let service: any Service = DefaultService()
			                return service
			            })
			        }
			        @Sendable nonisolated func __safeDI_serviceSendableBuilder_Host() -> Host.__safeDI_ServiceSendableCarrier<any Service> {
			            .init(staged_Sendable: __safeDI_serviceSendableBuilder_Staged())
			        }
			        @Sendable nonisolated func __safeDI_serviceSendableBuilder_Staged() -> Staged.__safeDI_ServiceSendableCarrier<any Service> {
			            .init(pod: { __safeDI_serviceBuilder_Staged_Job_Scope() })
			        }
			        @Sendable nonisolated func __safeDI_serviceBuilder_Staged_Job_Scope() -> Staged.__safeDI_ServiceCarrier_Job<any Service> {
			            .init(service: {
			                let service: any Service = DefaultService()
			                return service
			            })
			        }
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_21F652AED089ABCB.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Host(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Host(), __safeDI_serviceSendableBuilder: __safeDI_serviceSendableBuilder_Host())
			        }
			        let host: Host = __safeDI_host()
			        self.init(host: host)
			    }
			}
			"""],
		])
	}

	/// `Host` calls `Inner`, `Inner_Inner_job` and `Staged` in `order`, and `App` fills every place: `Inner`'s fill of `job`
	/// and `Inner_Inner_job`'s dispatcher share a name. The place of `Inner` carries a field labeled `scope`, which names its
	/// fill's parameter apart and so keeps it a function of its own rather than the body of the dispatcher case that calls it.
	private static func collidingNamesModules(order: [String]) -> [ModuleFixture] {
		let declarationsByKey = [
			"inner": "@Instantiated public let inner: Inner",
			"innerJob": "@Instantiated public let innerJob: Inner_Inner_job",
			"staged": "@Instantiated public let staged: Staged",
		]
		let feature = [
			Self.sendableService,
			Self.type("Token", conformances: ", Sendable"),
			Self.type("Job", ["@Instantiated public let service: any Service"], conformances: ", Sendable"),
			Self.type("Inner", seam: true, ["@Instantiated public let scope: Token", "@Instantiated public let job: any Service"]),
			Self.type("Inner_Inner_job", seam: true, ["@Instantiated public let service: any Service"]),
			Self.type("Staged", seam: true, ["@Instantiated public let pod: SendableInstantiator<Job>"]),
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
			\(fixtures["Feature"]!["Host.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Host`: its generated `public` initializer, which `Host`’s `public` access requires, cannot take `serviceBuilder: @escaping () -> any Service`, whose builder struct holds the builders of `Inner`, a seam visible only at `package` access. `Inner`’s own `@Instantiable` declaration is `package`. Declare `Host` at `package` access, or make `Inner` `public`.
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
		    package init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_BEC663BFAF038116.self
		            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder.inner)
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(inner: inner)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_CEE8657298FBF14C {}
		}

		extension Inner {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
		        public let service: () -> __safeDI_Built

		        public init(service: @escaping () -> __safeDI_Built) {
		            self.service = service
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(service: { __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    package init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
		        let service: any Service = __safeDI_serviceBuilder.service()
		        self.init(service: service)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_BEC663BFAF038116 {}
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsTierOmitsBuilder_whenPublicSeamsPlaceForwardsAnInternalType() async {
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Host.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Host`: its generated `public` initializer, which `Host`’s `public` access requires, cannot take `hiddenGadget_GadgetBuilder: @escaping ErasedInstantiator<Hidden, any Gadget>.Builder`, the builder for `Host`’s `maker: ErasedInstantiator<Hidden, any Gadget>`, which no @Instantiable declaration that module `Feature` can see fulfills. `Hidden` is declared `internal`. Declare `Hidden` `public`; declare `Host` `internal`; declare an @Instantiable type that fulfills `HiddenGadget` in module `Feature` or a module it lists among its SafeDI dependencies, so `Host`’s tree builds it; or declare the dependency tree on an `internal` type that instantiates `Host`.
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
		        public let deep: Deep.__safeDI_ServiceCarrier<__safeDI_Built>

		        public init(deep: Deep.__safeDI_ServiceCarrier<__safeDI_Built>) {
		            self.deep = deep
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(deep: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    // SafeDI counts `Service` as `public`: no module it reads declares it narrower. If `Service` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
		        func __safeDI_deep() -> Deep {
		            _ = Deep.__safeDI_Deep_24C4D6B7262EE267.self // If this line does not compile, compile the code SafeDI generates for module Lower into Lower: under Bazel, add Lower’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Deep(__safeDI_serviceBuilder: __safeDI_serviceBuilder.deep)
		        }
		        let deep: Deep = __safeDI_deep()
		        self.init(deep: deep)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_0E589766B056A983 {}
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_importsBuiltTypesModulePublicly_whenOnlyASendablePlacesBuilderNamesIt() async throws {
		// `Host`'s own file imports `Base` internally, and of the declarations `Host`'s generated file spells `public`, only
		// the `@Sendable` builder's signature names `AnyGadget`, which `Base` declares, as its `GadgetBox` records: the builder
		// returns it, and its enum's case carries the forwarded `String`.
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
		    public init(__safeDI_namedGadget_AnyGadgetSendableBuilder: __safeDI_NamedGadget_AnyGadgetSendableCarrier<AnyGadget>) {
		        let part = SendableErasedInstantiator<String, AnyGadget>(__safeDI_namedGadget_AnyGadgetSendableBuilder.part())
		        self.init(part: part)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_E248084040575509 {}
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
		        func __safeDI_serviceBuilder_Host() -> Host.__safeDI_ServiceCarrier<any Service> {
		            .init(deep: __safeDI_serviceBuilder_Deep())
		        }
		        func __safeDI_serviceBuilder_Deep() -> Deep.__safeDI_ServiceCarrier<any Service> {
		            .init(service: {
		                let service: any Service = DefaultService()
		                return service
		            })
		        }
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_0E589766B056A983.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Host(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Host())
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
			        func __safeDI_serviceBuilder_Inner_service(_ scope_deep: Deep) -> any Service {
			            return __safeDI_fillBody_220E4FCEBC0CCEE2()
			        }
			        func __safeDI_fillBody_220E4FCEBC0CCEE2() -> any Service {
			            func __safeDI_service() -> DefaultService {
			                let gadget: any Gadget = DefaultGadget()
			                return DefaultService(gadget: gadget)
			            }
			            let service: any Service = __safeDI_service()
			            return service
			        }
			        func __safeDI_gadgetBuilder_Host() -> Host.__safeDI_GadgetCarrier<any Gadget> {
			            .init(inner: __safeDI_gadgetBuilder_Inner())
			        }
			        func __safeDI_gadgetBuilder_Inner() -> Inner.__safeDI_GadgetCarrier<any Gadget> {
			            .init(deep: __safeDI_gadgetBuilder_Deep())
			        }
			        func __safeDI_gadgetBuilder_Deep() -> Deep.__safeDI_GadgetCarrier<any Gadget> {
			            .init(gadget: {
			                let gadget: any Gadget = DefaultGadget()
			                return gadget
			            })
			        }
			        func __safeDI_serviceBuilder_Host() -> Host.__safeDI_ServiceCarrier<any Service> {
			            .init(inner: __safeDI_serviceBuilder_Inner())
			        }
			        func __safeDI_serviceBuilder_Inner() -> Inner.__safeDI_ServiceCarrier<any Service> {
			            .init(service: { scope_deep in __safeDI_serviceBuilder_Inner_service(scope_deep) })
			        }
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_6C150D4BF5C855DE.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Host(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Host(), __safeDI_serviceBuilder: __safeDI_serviceBuilder_Host())
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
			        func __safeDI_serviceBuilder_Folder() -> Folder.__safeDI_ServiceCarrier<any Service> {
			            .init(
			                folderBuilder: { __safeDI_serviceBuilder_Folder() },
			                fileBuilder: { __safeDI_serviceBuilder_File() },
			                service: { scope_folderBuilder, scope_fileBuilder in
			                    let service: any Service = DefaultService()
			                    return service
			                }
			            )
			        }
			        func __safeDI_serviceBuilder_File() -> File.__safeDI_ServiceCarrier<any Service> {
			            .init(folderBuilder: { __safeDI_serviceBuilder_Folder() }, fileBuilder: { __safeDI_serviceBuilder_File() })
			        }
			        func __safeDI_folder() -> Folder {
			            _ = Folder.__safeDI_Folder_6509345684BCE60B.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Folder(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Folder())
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
			        func __safeDI_serviceBuilder_Home() -> Home.__safeDI_ServiceCarrier<any Service> {
			            .init(
			                listBuilder: { __safeDI_serviceBuilder_List() },
			                service: { scope_listBuilder in
			                    let service: any Service = DefaultService()
			                    return service
			                }
			            )
			        }
			        func __safeDI_serviceBuilder_List() -> List.__safeDI_ServiceCarrier<any Service> {
			            .init(detailBuilder: { __safeDI_serviceBuilder_Detail() })
			        }
			        func __safeDI_serviceBuilder_Detail() -> Detail.__safeDI_ServiceCarrier<any Service> {
			            .init(homeBuilder: { __safeDI_serviceBuilder_Home() }, settingsBuilder: { __safeDI_serviceBuilder_Settings() })
			        }
			        func __safeDI_serviceBuilder_Settings() -> Settings.__safeDI_ServiceCarrier<any Service> {
			            .init(
			                homeBuilder: { __safeDI_serviceBuilder_Home() },
			                detailBuilder: { __safeDI_serviceBuilder_Detail() },
			                service: { scope_homeBuilder, scope_detailBuilder in
			                    let service: any Service = DefaultService()
			                    return service
			                }
			            )
			        }
			        func __safeDI_home() -> Home {
			            _ = Home.__safeDI_Home_57C6AD0678D98E67.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Home(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Home())
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
			        func __safeDI_serviceBuilder_S0() -> S0.__safeDI_ServiceCarrier<any Service> {
			            .init(
			                to1: { __safeDI_serviceBuilder_S1() },
			                to3: { __safeDI_serviceBuilder_S3() },
			                service: { scope_to1, scope_to3 in
			                    let service: any Service = DefaultService()
			                    return service
			                }
			            )
			        }
			        func __safeDI_serviceBuilder_S1() -> S1.__safeDI_ServiceCarrier<any Service> {
			            .init(
			                to0: { __safeDI_serviceBuilder_S0() },
			                to2: { __safeDI_serviceBuilder_S2() },
			                service: { scope_to0, scope_to2 in
			                    let service: any Service = DefaultService()
			                    return service
			                }
			            )
			        }
			        func __safeDI_serviceBuilder_S2() -> S2.__safeDI_ServiceCarrier<any Service> {
			            .init(to0: { __safeDI_serviceBuilder_S0() }, to3: { __safeDI_serviceBuilder_S3() })
			        }
			        func __safeDI_serviceBuilder_S3() -> S3.__safeDI_ServiceCarrier<any Service> {
			            .init(
			                to0: { __safeDI_serviceBuilder_S0() },
			                to1: { __safeDI_serviceBuilder_S1() },
			                to2: { __safeDI_serviceBuilder_S2() },
			                service: { scope_to0, scope_to1, scope_to2 in
			                    let service: any Service = DefaultService()
			                    return service
			                }
			            )
			        }
			        func __safeDI_s0() -> S0 {
			            _ = S0.__safeDI_S0_1574D6F39CB45E94.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return S0(__safeDI_serviceBuilder: __safeDI_serviceBuilder_S0())
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
		    Host(impl_ServiceBuilder: { callback in
		        callback()
		        return CallingService()
		    })
		}
		""")], featureConfiguration: plainDependencyTreeInitializersConfiguration))
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_Impl_ServiceCarrier<__safeDI_Built> {
		        public let maker: () -> ErasedInstantiator<Callback, __safeDI_Built>.Builder

		        public init(maker: @escaping () -> ErasedInstantiator<Callback, __safeDI_Built>.Builder) {
		            self.maker = maker
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Callback, __safeDI_Built>.Builder) {
		            self.init(maker: { __safeDI_builder })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public init(impl_ServiceBuilder: @escaping ErasedInstantiator<Callback, any Service>.Builder) {
		        self.init(__safeDI_impl_ServiceBuilder: .init(__safeDI_noScope: impl_ServiceBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public init(__safeDI_impl_ServiceBuilder: __safeDI_Impl_ServiceCarrier<any Service>) {
		        let maker = ErasedInstantiator<Callback, any Service>(__safeDI_impl_ServiceBuilder.maker())
		        self.init(maker: maker)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_80707EF569D1A73C {}
		}
		"""])
	}

	// MARK: 8b. Names that a type the seam spells could resolve to

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
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
			        public let zsvc: (Kind, Name) -> __safeDI_Built

			        public init(zsvc: @escaping (Kind, Name) -> __safeDI_Built) {
			            self.zsvc = zsvc
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(zsvc: { _, _ in __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceCarrier_Job<__safeDI_Built> {
			        public let service: () -> __safeDI_Built

			        public init(service: @escaping () -> __safeDI_Built) {
			            self.service = service
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(service: { __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceSendableCarrier<__safeDI_Built>: Sendable {
			        public let job: @Sendable () -> __safeDI_ServiceCarrier_Job<__safeDI_Built>

			        public init(job: @escaping @Sendable () -> __safeDI_ServiceCarrier_Job<__safeDI_Built>) {
			            self.job = job
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			            self.init(job: { .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_Type Type: Kind, __safeDI_init `init`: Name, __safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>, __safeDI_serviceSendableBuilder: __safeDI_ServiceSendableCarrier<any Service>) {
			        let zsvc: any Service = __safeDI_serviceBuilder.zsvc(Type, `init`)
			        @Sendable nonisolated func __safeDI_job() -> Job {
			            let __safeDI_serviceSendableBuilder_job = __safeDI_serviceSendableBuilder.job()
			            let service: any Service = __safeDI_serviceSendableBuilder_job.service()
			            return Job(service: service)
			        }
			        let job = SendableInstantiator<Job>(__safeDI_job)
			        self.init(Type: Type, init: `init`, zsvc: zsvc, job: job)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_577F52FE7B7A69E6 {}
			}
			"""],
			"App": ["App.swift": """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_serviceBuilder_Host() -> Host.__safeDI_ServiceCarrier<any Service> {
			            .init(zsvc: { scope_Type, scope_init in
			                let Type = scope_Type
			                let `init` = scope_init
			                let zsvc: any Service = DefaultService(Type: Type, init: `init`)
			                return zsvc
			            })
			        }
			        let Type = Kind()
			        let `init` = Name()
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_577F52FE7B7A69E6.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            @Sendable nonisolated func __safeDI_serviceSendableBuilder_Host() -> Host.__safeDI_ServiceSendableCarrier<any Service> {
			                .init(job: { __safeDI_serviceBuilder_Host_Job_Scope() })
			            }
			            @Sendable nonisolated func __safeDI_serviceBuilder_Host_Job_Scope() -> Host.__safeDI_ServiceCarrier_Job<any Service> {
			                .init(service: {
			                    let service: any Service = DefaultService(Type: Type, init: `init`)
			                    return service
			                })
			            }
			            return Host(__safeDI_Type: Type, __safeDI_init: `init`, __safeDI_serviceBuilder: __safeDI_serviceBuilder_Host(), __safeDI_serviceSendableBuilder: __safeDI_serviceSendableBuilder_Host())
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
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
			        public let service: () -> __safeDI_Built

			        public init(service: @escaping () -> __safeDI_Built) {
			            self.service = service
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(service: { __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
			        let service: any Service = __safeDI_serviceBuilder.service()
			        self.init(service: service)
			    }
			}

			extension `My Inner` {
			    public enum `__safeDI_My Inner_A1B351F30D3C02C7` {}
			}

			extension Host {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
			        public let inner: `My Inner`.__safeDI_ServiceCarrier<__safeDI_Built>

			        public init(inner: `My Inner`.__safeDI_ServiceCarrier<__safeDI_Built>) {
			            self.inner = inner
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(inner: .init(__safeDI_noScope: __safeDI_builder))
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
			        func __safeDI_inner() -> `My Inner` {
			            _ = `My Inner`.`__safeDI_My Inner_A1B351F30D3C02C7`.self
			            return `My Inner`(__safeDI_serviceBuilder: __safeDI_serviceBuilder.inner)
			        }
			        let inner: `My Inner` = __safeDI_inner()
			        self.init(inner: inner)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_55C4240F519A7BB9 {}
			}
			"""],
			"App": ["App.swift": """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_serviceBuilder_Host() -> Host.__safeDI_ServiceCarrier<any Service> {
			            .init(inner: `__safeDI_serviceBuilder_My Inner`())
			        }
			        func `__safeDI_serviceBuilder_My Inner`() -> `My Inner`.__safeDI_ServiceCarrier<any Service> {
			            .init(service: {
			                let service: any Service = DefaultService()
			                return service
			            })
			        }
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_55C4240F519A7BB9.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Host(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Host())
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
			        func __safeDI_p_and_QBuilder_Host() -> Host.__safeDI_P_and_QCarrier<any (P & Q)> {
			            .init(
			                p01: {
			                    let p01: any (P & Q) = DefaultPQ()
			                    return p01
			                },
			                p02: { scope in
			                    let p02: any (Q & P) = DefaultPQ()
			                    return p02
			                },
			                p03: { scope in
			                    let p03: any (Q & P) = DefaultPQ()
			                    return p03
			                },
			                p04: { scope in
			                    let p04: any (Q & P) = DefaultPQ()
			                    return p04
			                },
			                p05: { scope in
			                    let p05: any (Q & P) = DefaultPQ()
			                    return p05
			                },
			                p06: { scope in
			                    let p06: any (Q & P) = DefaultPQ()
			                    return p06
			                },
			                p07: { scope in
			                    let p07: any (Q & P) = DefaultPQ()
			                    return p07
			                },
			                p08: { scope in
			                    let p08: any (Q & P) = DefaultPQ()
			                    return p08
			                },
			                p09: { scope in
			                    let p09: any (Q & P) = DefaultPQ()
			                    return p09
			                },
			                p10: { scope in
			                    let p10: any (Q & P) = DefaultPQ()
			                    return p10
			                },
			                p11: { scope in
			                    let p11: any (Q & P) = DefaultPQ()
			                    return p11
			                },
			                p12: { scope in
			                    let p12: any (Q & P) = DefaultPQ()
			                    return p12
			                },
			                p13: { scope in
			                    let p13: any (Q & P) = DefaultPQ()
			                    return p13
			                },
			                p14: { scope in
			                    let p14: any (Q & P) = DefaultPQ()
			                    return p14
			                },
			                p15: { scope in
			                    let p15: any (Q & P) = DefaultPQ()
			                    return p15
			                },
			                p16: { scope in
			                    let p16: any (Q & P) = DefaultPQ()
			                    return p16
			                },
			                p17: { scope in
			                    let p17: any (Q & P) = DefaultPQ()
			                    return p17
			                },
			                p18: { scope in
			                    let p18: any (Q & P) = DefaultPQ()
			                    return p18
			                },
			                p19: { scope in
			                    let p19: any (Q & P) = DefaultPQ()
			                    return p19
			                },
			                p20: { scope in
			                    let p20: any (Q & P) = DefaultPQ()
			                    return p20
			                }
			            )
			        }
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_D6AD75169F7A13E4.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Host(__safeDI_p_and_QBuilder: __safeDI_p_and_QBuilder_Host())
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
			\(fixtures["Feature"]!["Host.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Host`: its generated `public` initializer, which `Host`’s `public` access requires, cannot take `serviceSendableBuilder: @escaping @Sendable () -> any Service`, the builder for `Deep`’s `service: any Service`, which no @Instantiable declaration that module `Feature` can see fulfills. `Deep`’s own `@Instantiable` declaration is `package`. Declare `Deep` `public`; declare `Host` `package`; declare an @Instantiable type that fulfills `Service` in module `Feature` or a module it lists among its SafeDI dependencies, so `Host` fills the builder itself; or declare the dependency tree on a `package` type that instantiates `Host`.
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
			\(fixtures["App"]!["DefaultService.swift"]):11:5: error: `DefaultService` receives `user: User`, which `Mid` builds where it calls `Helper`, but `Mid` passes the builder for `Helper`’s `gadget: any Gadget` (`gadget` of `gadgetBuilder`) on from its own caller, which cannot hand it `Mid`’s values. Declare `@Received let user: User` on `Helper`, so SafeDI hands it to the builder, or declare an @Instantiable type that fulfills `Gadget` in module `Middle` or a module it lists among its SafeDI dependencies, so `Mid` fills the builder itself.
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
			        func __safeDI_serviceBuilder_Host() -> Host.SafeDIScope_Service.__safeDI_Builder<any Service> {
			            .init(mid_gadgetBuilder: { _ in __safeDI_serviceBuilder_Host_Mid() })
			        }
			        func __safeDI_serviceBuilder_Host_FeatureGadget_Scope(user: User) -> Host.SafeDIScope_Service.FeatureGadget_Scope.__safeDI_Builder<any Service> {
			            .init(service: { _ in
			                let service: any Service = DefaultService(user: user)
			                return service
			            })
			        }
			        func __safeDI_serviceBuilder_Host_Mid() -> Mid.__safeDI_GadgetCarrier<Host.SafeDIScope_Service.FeatureGadget_Scope.__safeDI_Builder<any Service>> {
			            .init(helper: __safeDI_serviceBuilder_Host_Helper())
			        }
			        func __safeDI_serviceBuilder_Host_Helper() -> Helper.__safeDI_GadgetCarrier<Host.SafeDIScope_Service.FeatureGadget_Scope.__safeDI_Builder<any Service>> {
			            .init(gadget: { values_user in __safeDI_serviceBuilder_Host_FeatureGadget_Scope(user: values_user) })
			        }
			        let user = User()
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_BDCE36EA0B3ADBC3.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Host(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Host())
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_Missing_ServiceCarrier<__safeDI_Built> {
		        public let maker: () -> ErasedInstantiator<Unread, __safeDI_Built>.Builder

		        public init(maker: @escaping () -> ErasedInstantiator<Unread, __safeDI_Built>.Builder) {
		            self.maker = maker
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Unread, __safeDI_Built>.Builder) {
		            self.init(maker: { __safeDI_builder })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    internal init(__safeDI_missing_ServiceBuilder: __safeDI_Missing_ServiceCarrier<any Service>) {
		        let maker = ErasedInstantiator<Unread, any Service>(__safeDI_missing_ServiceBuilder.maker())
		        self.init(maker: maker)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_DA15FB85DE2A9BEC {}
		}
		"""])
		if compileVerificationIsEnabled {
			let compilation = try #require(output.compilation)
			#expect(compilation.modules.map(\.exitCode) == output.moduleNames.map { _ in 0 })
		}
	}

	private var filesToDelete: [URL]
}
