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
import Testing
@testable import SafeDICore
@testable import SafeDIToolLibrary
@testable import SafeDIToolTestSupport

/// A production tree whose lazy cycles' parameters a first pass leaves unsettled is built once more with the parameters
/// `CycleParameterPlan` settles on the first pass's tree. Each test here generates a module with the plan and without it
/// and expects the same files; `executeSafeDIToolTest` also builds every tree without the plan and the memo and compares
/// them by reflection, path by path.
struct SafeDIToolCycleParameterPlanTests: ~Copyable {
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
	mutating func generate_generatesSameFilesWithSettledParametersAsWithout_whenScreensOpenEachOtherThroughBuilders() async throws {
		// Issue #646's graph at eight screens: each screen opens three others through builders, so lazy cycles nest
		// inside one another, and two screens declare `context`, which others receive only if available. Without the
		// plan the tree takes four passes, each settling one more depth of nested functions; the plan settles them on
		// the first pass's tree in four rounds, over places a screen reached by many paths shares.
		let files = try await expectSameFilesWithPlanAsWithout(of: Self.screens)
		#expect(files.count == 1)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesSameFilesWithSettledParametersAsWithout_whenRoundRebuildsEqualMapOfRedeclaredLabels() async throws {
		// Four screens that each open the other three through builders; `Screen1` declares `context` again, which
		// `Screen2` receives only if available. As a round changes the parameters of a function nested inside another, the
		// places above search again and build maps of the labels redeclared on the functions anew, holding the same labels
		// as the round before. The plan counts each as found anew, so the places above search once more, and the parameters
		// still settle where the passes without the plan end.
		let files = try await expectSameFilesWithPlanAsWithout(of: Self.screens(
			opened: [[1, 2, 3], [0, 2, 3], [0, 1, 3], [0, 1, 2]],
			context: [1: "@Instantiated let context: Context", 2: "@Received(onlyIfAvailable: true) let context: Context?"],
		))
		#expect(files.count == 1)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The graph `make_screens.py` (the generate benchmark's) draws at eight screens with seed 6.
	private static var screens: [String] {
		screens(
			opened: [[1, 5, 7], [0, 3, 7], [1, 5, 6], [2, 6, 7], [0, 2, 7], [1, 3, 7], [1, 4, 5], [0, 4, 5]],
			context: [1: "@Instantiated let context: Context", 5: "@Instantiated let context: Context", 3: "@Received(onlyIfAvailable: true) let context: Context?", 6: "@Received(onlyIfAvailable: true) let context: Context?"],
		)
	}

	/// Screens that each open the screens `opened` lists through builders, and declare `context` as `context` lists.
	private static func screens(opened: [[Int]], context: [Int: String]) -> [String] {
		var files = opened.enumerated().map { index, screens in
			var declarations = ["@Forwarded let id: String", "@Received let service: Service"]
			if let declaration = context[index] {
				declarations.append(declaration)
			}
			declarations += screens.map { "@Instantiated let screen\($0)Builder: Instantiator<Screen\($0)>" }
			return seamFixtureType(named: "Screen\(index)", isFinalClass: true, declarations: declarations)
		}
		files.append(seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let service: Service", "@Instantiated let context: Context", "@Instantiated let screen0Builder: Instantiator<Screen0>"]))
		files.append(seamFixtureType(named: "Service", isFinalClass: true, declarations: []))
		files.append(seamFixtureType(named: "Context", isFinalClass: true, declarations: []))
		return files
	}

	private mutating func expectSameFilesWithPlanAsWithout(of fixture: [String]) async throws -> [String: String] {
		let withPlan = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let withoutPlan = try await CycleParameterPlan.$isEnabled.withValue(false) { [fixture] in
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(withPlan.dependencyTreeFiles == withoutPlan.dependencyTreeFiles)
		return withPlan.dependencyTreeFiles
	}
}
