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

/// The detectors of a tree's plan (`PerTypePlan.mayHoldUnpassableCycleLabel`): a plan has no cycle-closing scope, so a
/// root whose plan's detector fires is built per path, where today's tree finds the label. Every test's tree is checked
/// for a detector that misses what its tree finds (`PerTypePlanDetectorChecks`); these tests check what a detector answers.
struct SafeDIToolPerTypePlanDetectorTests: ~Copyable {
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
	mutating func generate_detectsUnpassableCycleLabel_whenTypeOnCycleDeclaresLabelTheCycleReceivesInTwoForms() async throws {
		// `S`, on the cycle through `A`, declares `x`, which `B` and `C` inside the tree `A`'s function builds receive as
		// `X?` and `Y?`: no one parameter of that function carries both, which today's tree reports.
		let answers = try await detectorAnswers(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let b: B", "@Instantiated let c: C", "@Instantiated let sBuilder: Instantiator<S>"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let x: X?"]),
			seamFixtureType(named: "C", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let x: Y?"]),
			seamFixtureType(named: "S", isFinalClass: true, declarations: ["@Instantiated let x: Y", "@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
		])

		#expect(answers == ["Root: may hold an unpassable cycle label; today’s tree holds [x]"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_detectsNoUnpassableCycleLabel_whenOnlyTypeOffTheCycleDeclaresLabelTheCycleReceivesInTwoForms() async throws {
		// The cycle through `A` receives `x` as `X?`, `Y?` and `Y`, but only `D`, which is on no cycle, declares it: no cycle
		// closes around that declaration, so no function's parameter has to carry the forms, which a test of the whole
		// tree (`DependencyTreeGenerator.canHoldUnpassableCycleLabel(inTreeRootedAt:)`) would not tell.
		let answers = try await detectorAnswers(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let b: B", "@Instantiated let c: C", "@Instantiated let d: D", "@Instantiated let sBuilder: Instantiator<S>"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let x: X?"]),
			seamFixtureType(named: "C", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let x: Y?"]),
			seamFixtureType(named: "D", isFinalClass: true, declarations: ["@Instantiated let x: Y", "@Instantiated let e: E"]),
			seamFixtureType(named: "E", isFinalClass: true, declarations: ["@Received let x: Y"]),
			seamFixtureType(named: "S", isFinalClass: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
		])

		#expect(answers == ["Root: may hold no unpassable cycle label; today’s tree holds []"])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// What the detectors of each production tree's plan `generate` builds from `swiftFileContent` answer, beside what
	/// the tree finds, each distinct answer once, in the order first built. Whether generation succeeds is not this
	/// test's subject: a tree that holds an unpassable label fails it.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func detectorAnswers(of swiftFileContent: [String]) async throws -> [String] {
		let (stream, continuation) = AsyncStream.makeStream(of: String.self)
		await PerTypePlanDetectorObservation.$observer.withValue({ answers in
			continuation.yield("\(answers.rootType): may hold \(answers.mayHoldUnpassableCycleLabel ? "an" : "no") unpassable cycle label; today’s tree holds \(answers.unpassableCycleLabelsInTree)")
		}) {
			_ = try? await executeSafeDIToolTest(
				swiftFileContent: swiftFileContent,
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		continuation.finish()
		var answers = [String]()
		for await answer in stream where !answers.contains(answer) {
			answers.append(answer)
		}
		return answers
	}
}
