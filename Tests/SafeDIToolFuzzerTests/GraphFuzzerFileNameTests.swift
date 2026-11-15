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

import Testing
@testable import SafeDIToolTestSupport

/// How the graph fuzzer's harness names a fixture's files: a file it cannot name is reported, never dropped, since
/// every reader pairs the names with the files by position.
struct GraphFuzzerFileNameTests {
	@Test
	func fileNames_namesTheFileAfterItsType_whenInstantiableIsWrittenAboveMainActor() throws {
		let fixture = GraphFuzzerFixture(seed: 9, swiftFileContent: [
			Self.rootFile,
			Self.homeFileWithInstantiableAboveMainActor,
		])

		#expect(try fixture.fileNames == ["S9_Root.swift", "S9_Home.swift"])
	}

	@Test
	func fileNames_reportsTheFile_whenItDeclaresNoType() {
		let fixture = GraphFuzzerFixture(seed: 9, swiftFileContent: [
			Self.rootFile,
			Self.fileDeclaringNoType,
		])

		#expect {
			try fixture.fileNames
		} throws: { error in
			"\(error)" == "The test harness cannot name file 2 of seed 9, which declares no type and names itself on no `// file: ` line: `let s9Value = 1`."
		}
	}

	@Test
	func toolOutcome_runsTheTool_whenASplitGraphWritesInstantiableAboveMainActor() async throws {
		let fixture = GraphFuzzerFixture(seed: 9, swiftFileContent: [
			"// module: FuzzApp\n" + Self.rootFile,
			"// module: FuzzFeature\n" + Self.homeFileWithInstantiableAboveMainActor,
		])

		_ = try await GraphFuzzerOracle.toolOutcome(of: fixture)
	}

	@Test
	func toolOutcome_reportsTheFile_whenASplitGraphHasAFileItCannotName() async {
		let fixture = GraphFuzzerFixture(seed: 9, swiftFileContent: [
			"// module: FuzzApp\n" + Self.rootFile,
			"// module: FuzzFeature\n" + Self.homeFile,
			"// module: FuzzFeature\n" + Self.fileDeclaringNoType,
		])

		await #expect {
			try await GraphFuzzerOracle.toolOutcome(of: fixture)
		} throws: { error in
			error is GraphFuzzerInfrastructureError && "\(error)".hasPrefix("The test harness cannot name file 3 of seed 9,")
		}
	}

	@Test
	func toolOutcome_reportsTheMismatch_whenASplitGraphIsGivenFewerFileNamesThanFiles() async {
		let fixture = GraphFuzzerFixture(seed: 9, swiftFileContent: [
			"// module: FuzzApp\n" + Self.rootFile,
			"// module: FuzzFeature\n" + Self.homeFile,
		])

		await #expect {
			try await GraphFuzzerOracle.toolOutcome(of: fixture, fileNames: ["S9_Root.swift"])
		} throws: { error in
			"\(error)" == "The test harness was given 1 file name for the 2 files of seed 9."
		}
	}

	// MARK: Private

	private static let rootFile = """
	@Instantiable(isRoot: true)
	public final class S9_Root: Instantiable {
		public init(home: S9_Home) {
			self.home = home
		}

		@Instantiated let home: S9_Home
	}
	"""

	private static let homeFile = """
	@MainActor
	@Instantiable
	public final class S9_Home: Instantiable {
		public init() {}
	}
	"""

	private static let homeFileWithInstantiableAboveMainActor = """
	@Instantiable
	@MainActor
	final class S9_Home: Instantiable {
		init() {}
	}
	"""

	private static let fileDeclaringNoType = """
	let s9Value = 1
	"""
}
