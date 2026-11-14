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

/// A hole beneath more `@Sendable` functions than a concurrency thread's stack could recurse over. The `@Sendable` enum has
/// one level per `@Sendable` function, and tests run on such threads, half a megabyte on Apple platforms, where a debug
/// build spends kilobytes of stack on a level of a recursive walk.
struct SafeDIToolSeamDeepStageTests: ~Copyable {
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
	mutating func run_nestsSendableEnumOneLevelPerCarrier_whenHoleIsBeneathTwoHundredSendableInstantiators() async throws {
		let carrierCount = 200
		var files = [
			"public protocol Gadget: Sendable {}",
			Self.carrier(named: "Host", isSeam: true, holding: "L0"),
			seamFixtureType(named: "L\(carrierCount)", declarations: ["@Instantiated let held: SendableLazilyInstantiated<any Gadget>"], conformances: ", @unchecked Sendable"),
		]
		files += (0..<carrierCount).map { Self.carrier(named: "L\($0)", isSeam: false, holding: "L\($0 + 1)") }
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: SafeDIToolSeamBuilderParameterTests.modules(feature: files, app: [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultGadget", fulfilling: "Gadget", declarations: []),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let host: Host"]),
			]),
			integration: .moduleInfo,
			// The time the compiler takes for nested builder functions grows exponentially with their depth.
			compileVerification: .skipped,
			filesToDelete: &filesToDelete,
		)

		// One `carried_Sendable` case for each `@Sendable` function on the path but the wrapper's own, whose case is `held`.
		let route = String(repeating: ".carried_Sendable(", count: carrierCount + 1) + ".held" + String(repeating: ")", count: carrierCount + 1)
		let generatedSeam = try #require(output.modules["Feature"]?.generatedFiles["Feature.swift"])
		let seamLines = generatedSeam.split(separator: "\n").map(String.init)
		#expect(seamLines.filter { $0.contains("public init(") } == [
			"    public init(__safeDI_gadgetSendableBuilder: @escaping @Sendable (SafeDISendableScope_Gadget) -> any Gadget) {",
		])
		#expect(seamLines.filter { $0.contains("__safeDI_gadgetSendableBuilder(.") }.map { $0.trimmingCharacters(in: .whitespaces) } == [
			"__safeDI_gadgetSendableBuilder(\(route))",
		])
		// One dispatcher for the root enum and one for each carrier's enum.
		let generatedFill = try #require(output.modules["App"]?.generatedFiles["App.swift"])
		#expect(generatedFill.split(separator: "\n").filter { $0.contains("@Sendable func __safeDI_gadgetSendableBuilder_Host") }.count == carrierCount + 2)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private static func carrier(named name: String, isSeam: Bool, holding heldType: String) -> String {
		seamFixtureType(named: name, isSeam: isSeam, declarations: ["@Instantiated let carried: SendableInstantiator<\(heldType)>"], conformances: ", @unchecked Sendable")
	}
}
