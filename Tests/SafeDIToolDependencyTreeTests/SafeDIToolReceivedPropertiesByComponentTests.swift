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

/// The received properties of the scopes of a cycle are completed in passes over the cycle, once per scope and pass,
/// before any walk along the cycle's paths (`cycle-generation.md`, "Walks"). Each test runs `generate` with the passes and
/// without them and requires the same outcome, the generated code or the diagnostics, byte for byte, and counts the
/// scopes whose received properties were collected, so that a test of a shape left to the walk shows the walk ran.
struct SafeDIToolReceivedPropertiesByComponentTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – Scaling

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_collectsReceivedPropertiesInNumbersThatGrowWithTheTypes_whenEveryTypeOfCycleOpensEveryOther() async throws {
		// Each screen opens every other, so a walk along the paths enters a screen once per order of the screens before it.
		var passCounts = [Int]()
		var pathCounts = [Int]()
		for screenCount in [4, 5, 6] {
			let fixture = Self.screensOpeningEveryOther(screenCount: screenCount, lastScreenDeclarations: [])
			let inPasses = try await run(fixture, completingByComponent: true)
			let alongPaths = try await run(fixture, completingByComponent: false)
			#expect(inPasses.outcome == alongPaths.outcome)
			passCounts.append(inPasses.collectedScopeCount)
			pathCounts.append(alongPaths.collectedScopeCount)
		}
		for (smaller, larger) in zip(pathCounts, pathCounts.dropFirst()) {
			#expect(Double(larger) / Double(smaller) > 1.9, "Along the paths the walk collects \(pathCounts) scopes")
		}
		for (smaller, larger) in zip(passCounts, passCounts.dropFirst()) {
			// One more screen is one more scope in each pass.
			#expect(larger - smaller <= 8, "In passes the walk collects \(passCounts) scopes")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_collectsSameReceivedProperties_whenTypeInstantiatesInstantiatorOfItself() async throws {
		// A cycle of one scope: `Screen0` opens itself and nothing else.
		let fixture = Self.screensOpeningEveryOther(screenCount: 1, lastScreenDeclarations: ["@Instantiated let screen0Builder: Instantiator<Screen0>"])
		let inPasses = try await run(fixture, completingByComponent: true)
		let alongPaths = try await run(fixture, completingByComponent: false)
		#expect(inPasses.outcome == alongPaths.outcome)
		#expect(inPasses.outcome.isGenerated)
	}

	// MARK: Tests – Cycles left to the walk

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_collectsReceivedPropertiesAlongPaths_whenTypeOfCycleDeclaresOnlyIfAvailableAlias() async throws {
		// What a tree requires through an `onlyIfAvailable` alias is not judged property by property, so the cycle is
		// left to the walk along its paths.
		let fixture = Self.screensOpeningEveryOther(
			screenCount: 5,
			lastScreenDeclarations: ["@Received(fulfilledByDependencyNamed: \"service\", ofType: Service.self, onlyIfAvailable: true) let renamedService: Service?"],
		)
		let inPasses = try await run(fixture, completingByComponent: true)
		let alongPaths = try await run(fixture, completingByComponent: false)
		#expect(inPasses.outcome == alongPaths.outcome)
		#expect(inPasses.outcome.isGenerated)
		#expect(inPasses.collectedScopeCount == alongPaths.collectedScopeCount)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_collectsReceivedPropertiesAlongPaths_whenTreeBeneathCycleRequiresOnlyIfAvailableAlias() async throws {
		// `Reader`, beneath `Panel`, requires `Panel`'s alias of `service` only if available, so `Panel`'s tree requires
		// `service` through the alias, and the cycle above `Panel` is left to the walk along its paths.
		let fixture = Self.screensOpeningEveryOther(screenCount: 5, lastScreenDeclarations: ["@Instantiated let panel: Panel"]) + [
			seamFixtureType(named: "Panel", isFinalClass: true, declarations: [
				"@Received(fulfilledByDependencyNamed: \"service\", ofType: Service.self, onlyIfAvailable: true) let renamedService: Service?",
				"@Instantiated let reader: Reader",
			]),
			seamFixtureType(named: "Reader", isFinalClass: true, declarations: ["@Received let renamedService: Service?"]),
		]
		let inPasses = try await run(fixture, completingByComponent: true)
		let alongPaths = try await run(fixture, completingByComponent: false)
		#expect(inPasses.outcome == alongPaths.outcome)
		#expect(inPasses.outcome.isGenerated)
		#expect(inPasses.collectedScopeCount == alongPaths.collectedScopeCount)
	}

	// MARK: Tests – Diagnostics

	@Test(arguments: SafeDIToolReceivedPropertiesByComponentTests.permutations(of: ["b", "e", "pBuilder", "qBuilder"]))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsSameSiblingCycleError_whateverOrderRootDeclaresChildrenThatRequireEachOtherThroughOneCycle(order: [String]) async throws {
		// `B` receives `pBuilder` and `E` receives `qBuilder`, whose trees, one cycle of instantiators, receive `b` and
		// `e`: each of `b` and `e` requires itself through either builder. Which is reported follows no order of `Root`'s
		// children, and neither does it follow which of the cycle's scopes is collected first.
		let fixture = Self.siblingsRequiringEachOtherThroughOneCycle(order: order)
		let inPasses = try await run(fixture, completingByComponent: true)
		let alongPaths = try await run(fixture, completingByComponent: false)
		#expect(inPasses.outcome == alongPaths.outcome)
		#expect(inPasses.outcome == .error(Self.siblingsRequiringEachOtherError), "Root builds \(order)")
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// What `generate` produced: its generated files, or its diagnostics.
	private enum Outcome: Equatable {
		case generated([String: String])
		case error(String)

		var isGenerated: Bool {
			switch self {
			case .generated:
				true
			case .error:
				false
			}
		}
	}

	private struct Run {
		let outcome: Outcome
		let collectedScopeCount: Int
	}

	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func run(_ fixture: [String], completingByComponent: Bool) async throws -> Run {
		let (stream, continuation) = AsyncStream.makeStream(of: ValidationWalkObservation.self)
		let outcome: Outcome
		do {
			let output = try await ValidationWalkObservation.$completesReceivedPropertiesByComponent.withValue(completingByComponent) {
				try await ValidationWalkObservation.$observer.withValue({ continuation.yield($0) }) {
					try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
				}
			}
			outcome = .generated((output.generatedFiles ?? [:]).mapValues(Self.withFixtureNames))
		} catch let error as SafeDIToolTestError {
			outcome = .error(Self.withFixtureNames(error.description))
		}
		continuation.finish()
		var collectedScopeCount = 0
		for await observation in stream {
			switch observation {
			case .collectedReceivedPropertiesOfScope:
				collectedScopeCount += 1
			case .validatedScope,
			     .skippedCleanSubtree:
				break
			}
		}
		return Run(outcome: outcome, collectedScopeCount: collectedScopeCount)
	}

	/// `text` with each fixture's directory left out, so two runs' diagnostics, and the `#sourceLocation` directives of
	/// their generated code, compare equal.
	private static func withFixtureNames(_ text: String) -> String {
		text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
			guard let swiftRange = line.range(of: ".swift"),
			      let slash = line[..<swiftRange.lowerBound].lastIndex(of: "/"),
			      let firstSlash = line.firstIndex(of: "/")
			else { return String(line) }
			return String(line[..<firstSlash]) + String(line[line.index(after: slash)...])
		}.joined(separator: "\n")
	}

	/// Every order of `elements`.
	private static func permutations(of elements: [String]) -> [[String]] {
		guard let first = elements.first else { return [[]] }
		return permutations(of: Array(elements.dropFirst())).flatMap { permutation in
			(0...permutation.count).map { index in
				var inserted = permutation
				inserted.insert(first, at: index)
				return inserted
			}
		}
	}

	/// `screenCount` screens that each open every other and receive `service`, which `Root` instantiates beside the first
	/// screen's builder; the last screen also declares `lastScreenDeclarations`.
	private static func screensOpeningEveryOther(screenCount: Int, lastScreenDeclarations: [String]) -> [String] {
		var fixture = [String]()
		for index in 0..<screenCount {
			fixture.append(seamFixtureType(
				named: "Screen\(index)",
				isFinalClass: true,
				declarations: ["@Received let service: Service"]
					+ (0..<screenCount).filter { $0 != index }.map { "@Instantiated let screen\($0)Builder: Instantiator<Screen\($0)>" }
					+ (index == screenCount - 1 ? lastScreenDeclarations : []),
			))
		}
		fixture.append(seamFixtureType(named: "Service", isFinalClass: true, declarations: []))
		fixture.append(seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let service: Service", "@Instantiated let screen0Builder: Instantiator<Screen0>"]))
		return fixture
	}

	/// `Root` builds `b`, `e`, `pBuilder` and `qBuilder` in `order`; the builders enter one cycle of `P0`, `P1` and `P2`.
	private static func siblingsRequiringEachOtherThroughOneCycle(order: [String]) -> [String] {
		let types = ["b": "B", "e": "E", "pBuilder": "Instantiator<P0>", "qBuilder": "Instantiator<P1>"]
		return [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: order.map { "@Instantiated let \($0): \(types[$0] ?? "")" }),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Received let pBuilder: Instantiator<P0>"]),
			seamFixtureType(named: "E", isFinalClass: true, declarations: ["@Received let qBuilder: Instantiator<P1>"]),
			seamFixtureType(named: "P0", isFinalClass: true, declarations: ["@Instantiated let p1Builder: Instantiator<P1>", "@Instantiated let p2Builder: Instantiator<P2>"]),
			seamFixtureType(named: "P1", isFinalClass: true, declarations: ["@Instantiated let p0Builder: Instantiator<P0>", "@Instantiated let p2Builder: Instantiator<P2>", "@Received let e: E"]),
			seamFixtureType(named: "P2", isFinalClass: true, declarations: ["@Instantiated let p0Builder: Instantiator<P0>", "@Instantiated let p1Builder: Instantiator<P1>", "@Received let b: B"]),
		]
	}

	private static let siblingsRequiringEachOtherError = """
	E.swift:7:5: error: Dependency cycle: @Instantiated `qBuilder: Instantiator<P1>` -> @Received `e: E` -> @Received `qBuilder: Instantiator<P1>`. `qBuilder: Instantiator<P1>` is received while it is still being instantiated. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
	"""
}
