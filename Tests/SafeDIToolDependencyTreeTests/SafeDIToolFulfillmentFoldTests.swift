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

/// The fold over the facts of each type decides whether any route of a module's trees is walked
/// (`DependencyTreeGenerator.FulfillmentFold`). These tests run `generate` as the tool does, without the comparison that
/// makes the walk run on every graph, and count the scopes the walk validates.
struct SafeDIToolFulfillmentFoldTests: ~Copyable {
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

	@Test(arguments: [35, 78] as [UInt64])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_validatesNoScope_whenLayersReachRootsOfAcceptedFuzzerDrawAlongEveryPath(seed: UInt64) async throws {
		// The two draws of the graph fuzzer's base corpus on which the walk's keys of a subtree grew with the paths: each
		// draw beneath layers of two types, every type of a layer instantiating both types of the next and the last layer
		// every root of the draw, so the draw is reached along 2^layers paths. The tool accepts both, so no route is walked.
		for layerCount in [3, 6] {
			let fixture = try Self.fuzzerDraw(forSeed: seed, beneathLayers: layerCount)
			let (stream, continuation) = AsyncStream.makeStream(of: ValidationWalkObservation.self)
			_ = try await FulfillmentFoldChecks.$comparesFoldWithWalk.withValue(false) {
				try await ValidationWalkObservation.$observer.withValue({ continuation.yield($0) }) {
					try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete, skipCompileVerification: true)
				}
			}
			continuation.finish()
			var validatedScopeCount = 0
			for await observation in stream {
				switch observation {
				case .validatedScope:
					validatedScopeCount += 1
				case .skippedCleanSubtree, .collectedReceivedPropertiesOfScope, .keyedSubtree:
					break
				}
			}
			#expect(validatedScopeCount == 0, "\(layerCount) layers")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsReceiveHidden_whenLapsNearestDeclarationIsItsLabelInAnotherFormThanFirstBuilds() async throws {
		// `Screen` is first built beneath `Root`, whose `token: Token` its receive reads. `Detail`, inside `Screen`, declares
		// `token` as an instantiator and builds `Screen` again, so on that lap the nearest declaration of the label is
		// another form than the first build's, which hides the receive. A verdict of the lap that took the first build's
		// answer from the lap's nearest declaration would find the receive hidden on both builds and report nothing.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let token: Token", "@Instantiated let screenBuilder: Instantiator<Screen>"]),
			seamFixtureType(named: "Token", declarations: []),
			seamFixtureType(named: "Screen", declarations: ["@Received let token: Token", "@Instantiated let detail: Detail"]),
			seamFixtureType(named: "Detail", declarations: ["@Instantiated let token: Instantiator<Token>", "@Instantiated let screenBuilder: Instantiator<Screen>"]),
		]
		let (stream, continuation) = AsyncStream.makeStream(of: FulfillmentFoldComparison.self)
		let errorDescription: String? = try await ValidationWalkObservation.$foldComparison.withValue({ continuation.yield($0) }) {
			do {
				_ = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
				return nil
			} catch let error as SafeDIToolTestError {
				// Each diagnostic's location without its fixture's directory, which every run names anew.
				return error.description.split(separator: "\n", omittingEmptySubsequences: false).map { line in
					if let swiftRange = line.range(of: ".swift:"), let slash = line[..<swiftRange.lowerBound].lastIndex(of: "/") {
						String(line[line.index(after: slash)...])
					} else {
						String(line)
					}
				}.joined(separator: "\n")
			}
		}
		continuation.finish()
		var routesThatMayFailWhereWalkRejected = [String?]()
		for await comparison in stream where comparison.walkRejected {
			routesThatMayFailWhereWalkRejected.append(comparison.routeThatMayFail)
		}
		#expect(errorDescription == """
		Screen.swift:8:5: error: @Received property `token: Token` is hidden in chain: Root -> Instantiator<Screen> -> Detail -> Screen. `Detail` declares `token: Instantiator<Token>` with the same label, so the types below `Detail` receive `token: Instantiator<Token>` instead. Give `token: Instantiator<Token>` on `Detail` a different label to fix.
		Detail.swift:8:5: note: `token: Instantiator<Token>` is declared here
		""")
		// The fold errs toward the walk: its hidden-receive question, which asks of no route, sends these trees there.
		#expect(routesThatMayFailWhereWalkRejected == ["hiddenReceive"])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The files of the base corpus's draw for `seed` with its roots no longer roots, and `layerCount` layers of two types
	/// above them: the first type of the first layer is the one root.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private static func fuzzerDraw(forSeed seed: UInt64, beneathLayers layerCount: Int) throws -> [String] {
		let rootDeclaration = try Regex(#"@Instantiable\(isRoot: true[^)]*\)\s*public (?:final class|struct|actor) (\w+)"#)
		var rootNames = [String]()
		var files = [String]()
		for file in GraphFuzzerGenerator.fixture(forSeed: seed).swiftFileContent {
			for match in file.matches(of: rootDeclaration) {
				if let name = match.output[1].substring {
					rootNames.append(String(name))
				}
			}
			files.append(file.replacingOccurrences(of: "@Instantiable(isRoot: true)", with: "@Instantiable").replacingOccurrences(of: "isRoot: true, ", with: ""))
		}
		for layer in 0..<layerCount {
			let declarations = layer + 1 < layerCount
				? (0..<2).map { "@Instantiated let next\($0): Layer\(layer + 1)_\($0)" }
				: rootNames.enumerated().map { "@Instantiated let root\($0.offset): \($0.element)" }
			for index in 0..<2 {
				files.append(seamFixtureType(named: "Layer\(layer)_\(index)", isRoot: layer == 0 && index == 0, isFinalClass: true, declarations: declarations))
			}
		}
		return files
	}
}
