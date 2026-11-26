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

/// A fill of a seam's hole is written once per root as a function of the fields it reads, which each fill of the same tree
/// calls with what its case binds (`ScopeGenerator.sharesFillBody(handedParameterFields:)`), and the function's body is laid
/// out by type. A fill whose tree reads anything its fields do not carry keeps its own body: a value the caller binds, a
/// function a cycle closes on outside the fill, and a value the fill's case leaves unavailable, which its text spells.
///
/// `Feature` declares `F0` and `F1`, seams that receive `service` and instantiate `api: any Api`, a hole `App` fills with
/// `LiveApi`, whose tree builds `C`.
struct SafeDIToolSeamSharedFillBodyTests: ~Copyable {
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
	mutating func generate_declaresFillBodyOnce_whenTwoSeamCallsFillHoleWithSameTree() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Fixture().modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, ["App.swift": ""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresFillBodyPerCase_whenOneCaseLeavesValueTreeReadsUnavailable() async throws {
		// `F0` receives `extra`, which its fill's tree reads where available; `F1` does not, so its fill passes `nil`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Fixture(
				featureTypes: ["@Instantiable public final class Extra: Instantiable { public init() {} }"],
				f0Declarations: Fixture.seamDeclarations + ["@Received public let extra: Extra"],
				liveApiDeclarations: Fixture.liveApiDeclarations + ["@Received(onlyIfAvailable: true) let extra: Extra?"],
				rootDeclarations: Fixture.rootDeclarations + ["@Instantiated let extra: Extra"],
			).modules,
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, ["App.swift": ""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsFillBodyInFill_whenFillTreeReadsValueCallerBinds() async throws {
		// `LiveApi` receives `x`, which `Root` binds and neither seam receives: the fill reads it from the caller.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Fixture(
				appTypes: ["@Instantiable public final class X: Instantiable { public init() {} }"],
				liveApiDeclarations: Fixture.liveApiDeclarations + ["@Received let x: X"],
				rootDeclarations: ["@Instantiated let x: X"] + Fixture.rootDeclarations,
			).modules,
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, ["App.swift": ""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsFillBodyInFill_whenFillTreeClosesCycleOnFunctionOutsideFill() async throws {
		// `C` builds `F0` again through an instantiator, closing a cycle on `Root`'s builder function of `f0`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Fixture(
				cDeclarations: Fixture.cDeclarations + ["@Instantiated let f0Builder: Instantiator<F0>"],
			).modules,
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, ["App.swift": ""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresFillBodyPerSendability_whenOneCallIsInsideSendableBuilder() async throws {
		// `Root` builds `F1` through a `SendableInstantiator`, so `F1`'s fill is `@Sendable`; `F0`'s is not.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Fixture(
				isSendable: true,
				rootDeclarations: ["@Instantiated let service: Service", "@Instantiated let f0: F0", "@Instantiated let f1Builder: SendableInstantiator<F1>"],
			).modules,
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, ["App.swift": ""])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private struct Fixture {
		static let seamDeclarations = ["@Received public let service: Service", "@Instantiated public let api: any Api"]
		static let liveApiDeclarations = ["@Received let service: Service", "@Instantiated let c: C"]
		static let cDeclarations = ["@Received let service: Service"]
		static let rootDeclarations = ["@Instantiated let service: Service", "@Instantiated let f0: F0", "@Instantiated let f1: F1"]

		init(
			isSendable: Bool = false,
			featureTypes: [String] = [],
			f0Declarations: [String] = seamDeclarations,
			f1Declarations: [String] = seamDeclarations,
			appTypes: [String] = [],
			liveApiDeclarations: [String] = liveApiDeclarations,
			cDeclarations: [String] = cDeclarations,
			rootDeclarations: [String] = rootDeclarations,
		) {
			let sendable = isSendable ? ", Sendable" : ""
			feature = [
				"public protocol Api\(isSendable ? ": Sendable" : "") {}\n\n@Instantiable public final class Service: Instantiable\(sendable) { public init() {} }",
				Self.type(named: "F0", attribute: "@Instantiable(generateDependencyTree: true)", conformances: sendable, declarations: f0Declarations),
				Self.type(named: "F1", attribute: "@Instantiable(generateDependencyTree: true)", conformances: sendable, declarations: f1Declarations),
			] + featureTypes
			app = appTypes + [
				Self.type(named: "LiveApi", attribute: "@Instantiable(fulfillingAdditionalTypes: [Api.self])", conformances: ", Api\(sendable)", declarations: liveApiDeclarations),
				Self.type(named: "C", attribute: "@Instantiable", conformances: sendable, declarations: cDeclarations),
				Self.type(named: "Root", attribute: "@Instantiable(isRoot: true)", conformances: "", declarations: rootDeclarations),
			]
		}

		var modules: [ModuleFixture] {
			[
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: app, dependencies: ["Feature"]),
			]
		}

		/// A final class with a memberwise initializer of `declarations`, each `@Attribute [public] let label: Type`.
		private static func type(named name: String, attribute: String, conformances: String, declarations: [String]) -> String {
			let properties = declarations.map { declaration in
				let parts = declaration.components(separatedBy: " let ")
				let labelAndType = parts[1].components(separatedBy: ": ")
				return (label: labelAndType[0], type: labelAndType[1...].joined(separator: ": "))
			}
			let parameters = properties.map { "\($0.label): \($0.type)" }.joined(separator: ", ")
			let assignments = properties.map { "self.\($0.label) = \($0.label)" }.joined(separator: "; ")
			return """
			\(attribute) public final class \(name): Instantiable\(conformances) {
				public init(\(parameters)) { \(assignments) }
			\(declarations.map { "\t\($0)" }.joined(separator: "\n"))
			}
			"""
		}

		private let feature: [String]
		private let app: [String]
	}

	private func expectGeneratedFiles(_ generatedFiles: [String: String]?, _ expected: [String: String], sourceLocation: SourceLocation = #_sourceLocation) {
		#expect(generatedFiles == expected, sourceLocation: sourceLocation)
		if let generatedFiles, generatedFiles != expected {
			Issue.record(Comment(rawValue: generatedFiles.sorted { $0.key < $1.key }.map { "=== \($0.key)\n\($0.value)" }.joined(separator: "\n")), sourceLocation: sourceLocation)
		}
	}
}
