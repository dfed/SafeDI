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

/// `#SafeDIConfiguration(apiVersion:)`: every module of an app selects one form of mock API, and `generate` reports a
/// module whose setting differs from that of a module it depends on, under each integration.
struct SafeDIToolAPIVersionTests: ~Copyable {
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

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesTheSameCodeAsV2_whenEveryModuleSetsV3Unstable(integration: MultiModuleIntegration) async throws {
		let v2Output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modules(appAPIVersion: ".v2", coreAPIVersion: ".v2"),
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		let v3Output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modules(appAPIVersion: ".v3Unstable", coreAPIVersion: ".v3Unstable"),
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		for moduleName in ["Core", "App"] {
			let v2Module = try #require(v2Output.modules[moduleName])
			let v3Module = try #require(v3Output.modules[moduleName])
			#expect(!v2Module.generatedFiles.isEmpty, "\(moduleName)")
			#expect(v3Module.generatedFiles == v2Module.generatedFiles, "\(moduleName)")
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtConfiguration_whenDependencySetsOtherAPIVersion(integration: MultiModuleIntegration) async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let configurationPath = switch integration {
			case .moduleInfo:
				fixtures["App"]!["SafeDIConfiguration.swift"]
			case .swiftPackagePlugin:
				NormalizedFilePath(fixtures["App"]!.compilerPath(of: "SafeDIConfiguration.swift")).path
			}
			return """
			\(configurationPath):1:1: error: `App` sets `apiVersion: .v3Unstable`, but modules it depends on set another value: `Core` (`.v2`). Every module of an app sets the same `apiVersion` in its `#SafeDIConfiguration`, which is `.v2` where a module declares none.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(appAPIVersion: ".v3Unstable", coreAPIVersion: nil),
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingEveryDifferingModuleInNameOrder_whenModuleDeclaresNoConfiguration(integration: MultiModuleIntegration) async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { _ in
			"""
			error: `App` sets `apiVersion: .v2`, but modules it depends on set another value: `Alpha` (`.v3Unstable`), `Core` (`.v3Unstable`). Every module of an app sets the same `apiVersion` in its `#SafeDIConfiguration`, which is `.v2` where a module declares none.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					Self.core(apiVersion: ".v3Unstable"),
					// Declared after `Core` and named before it, so the error's order is the names'.
					ModuleFixture(
						name: "Alpha",
						packageName: "Pipeline",
						swiftFileContent: [
							"""
							@Instantiable
							public final class Wheel: Instantiable {
							    public init() {}
							}
							""",
						],
						swiftFileContentByFilePath: ["SafeDIConfiguration.swift": "#SafeDIConfiguration(apiVersion: .v3Unstable)\n"],
					),
					// A module that declares nothing SafeDI reads is not compared.
					ModuleFixture(
						name: "Plain",
						packageName: "Pipeline",
						swiftFileContent: [
							"""
							public struct Gear {
							    public init() {}
							}
							""",
						],
					),
					Self.app(apiVersion: nil, dependencies: ["Alpha", "Core", "Plain"]),
				],
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generates_whenDependencyThatSetsOtherAPIVersionIsUsedOnlyByModuleThatDeclaresNothing(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.core(apiVersion: ".v3Unstable"),
				// A module that declares nothing SafeDI reads generates nothing, so its dependencies' setting is not compared.
				ModuleFixture(
					name: "App",
					packageName: "Pipeline",
					swiftFileContent: [
						"""
						import Core

						public struct Car {
						    public init(engine: Engine) {
						        self.engine = engine
						    }
						    let engine: Engine
						}
						""",
					],
					dependencies: ["Core"],
				),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		#expect(output.modules["App"] != nil)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Core`, whose `Engine` has a mock, and `App`, whose root instantiates it, each with the configuration that sets the
	/// given `apiVersion`, or none for `nil`.
	private static func modules(appAPIVersion: String?, coreAPIVersion: String?) -> [ModuleFixture] {
		[core(apiVersion: coreAPIVersion), app(apiVersion: appAPIVersion, dependencies: ["Core"])]
	}

	private static func core(apiVersion: String?) -> ModuleFixture {
		ModuleFixture(
			name: "Core",
			packageName: "Pipeline",
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Engine: Instantiable {
				    public init() {}
				}
				""",
			],
			swiftFileContentByFilePath: configuration(apiVersion: apiVersion),
		)
	}

	private static func app(apiVersion: String?, dependencies: [String]) -> ModuleFixture {
		ModuleFixture(
			name: "App",
			packageName: "Pipeline",
			swiftFileContent: [
				"""
				import Core

				@Instantiable(isRoot: true, generateMock: true)
				public final class Root: Instantiable {
				    public init(engine: Engine) {
				        self.engine = engine
				    }
				    @Instantiated let engine: Engine
				}
				""",
			],
			swiftFileContentByFilePath: configuration(apiVersion: apiVersion),
			dependencies: dependencies,
		)
	}

	private static func configuration(apiVersion: String?) -> [String: String] {
		guard let apiVersion else { return [:] }
		return ["SafeDIConfiguration.swift": "#SafeDIConfiguration(apiVersion: \(apiVersion))\n"]
	}
}
