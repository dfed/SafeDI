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
@testable import SafeDIToolLibrary
@testable import SafeDIToolTestSupport

struct SafeDIToolPhaseTimesTests: ~Copyable {
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
	mutating func generate_writesOneLinePerSpanInOrder_whenPhaseTimesOutputNamesAFile() async throws {
		let phaseTimesFile = TestTemporaryDirectory.uniquePath(prefix: "phase-times-", pathExtension: "tsv")
		filesToDelete.append(phaseTimesFile)
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.fixture,
			buildSwiftOutputDirectory: true,
			buildDOTFileOutput: true,
			filesToDelete: &filesToDelete,
			moduleMembershipArguments: ["--module-name", "App"],
			environment: ["SAFEDI_PHASE_TIMES_OUTPUT": phaseTimesFile.path],
		)

		#expect(output.dotTree?.isEmpty == false)
		let lines = try String(contentsOf: phaseTimesFile, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
		#expect(lines.last == "")
		let fields = lines.dropLast().map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
		#expect(fields.map(\.count) == Array(repeating: 4, count: 7))
		#expect(fields.map(\.first) == [
			"validation + signatures + production construction",
			"whole-module gates",
			"production output",
			"mock plans + mock construction",
			"whole-module gates",
			"mock output",
			"DOT",
		])
		for spanFields in fields where spanFields.count == 4 {
			let wallSeconds = try #require(Double(spanFields[1]))
			let processorSeconds = try #require(Double(spanFields[2]))
			let peakResidentBytes = try #require(Int(spanFields[3]))
			#expect(wallSeconds >= 0)
			#expect(processorSeconds >= 0)
			#expect(peakResidentBytes > 0)
			// Six decimal places.
			#expect(spanFields[1].split(separator: ".").last?.count == 6)
			#expect(spanFields[2].split(separator: ".").last?.count == 6)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_writesNoFile_whenPhaseTimesOutputIsUnset() async throws {
		let phaseTimesFile = TestTemporaryDirectory.uniquePath(prefix: "phase-times-", pathExtension: "tsv")
		_ = try await executeSafeDIToolTest(
			swiftFileContent: Self.fixture,
			buildSwiftOutputDirectory: true,
			buildDOTFileOutput: true,
			filesToDelete: &filesToDelete,
			moduleMembershipArguments: ["--module-name", "App"],
			environment: ["SAFEDI_PHASE_TIMES_OUTPUT_UNRELATED": phaseTimesFile.path],
		)

		#expect(!FileManager.default.fileExists(atPath: phaseTimesFile.path))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_writesTheSameOutputAsWithoutTheVariable_whenPhaseTimesOutputNamesAFileInADirectoryThatDoesNotExist() async throws {
		let missingDirectory = TestTemporaryDirectory.uniquePath(prefix: "missing-")
		let phaseTimesFile = missingDirectory.appendingPathComponent("phase-times.tsv")
		let outputWithVariable = try await executeSafeDIToolTest(
			swiftFileContent: Self.fixture,
			buildSwiftOutputDirectory: true,
			buildDOTFileOutput: true,
			filesToDelete: &filesToDelete,
			skipCompileVerification: true,
			moduleMembershipArguments: ["--module-name", "App"],
			environment: ["SAFEDI_PHASE_TIMES_OUTPUT": phaseTimesFile.path],
		)
		let outputWithoutVariable = try await executeSafeDIToolTest(
			swiftFileContent: Self.fixture,
			buildSwiftOutputDirectory: true,
			buildDOTFileOutput: true,
			filesToDelete: &filesToDelete,
			skipCompileVerification: true,
			moduleMembershipArguments: ["--module-name", "App"],
			environment: [:],
		)

		#expect(!FileManager.default.fileExists(atPath: missingDirectory.path))
		#expect(outputWithVariable.generatedFiles?.isEmpty == false)
		#expect(outputWithVariable.generatedFiles == outputWithoutVariable.generatedFiles)
		#expect(outputWithVariable.dotTree == outputWithoutVariable.dotTree)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// Two production roots, a seam, and two types with generated mocks, in one module.
	private static let fixture = [
		"""
		@Instantiable(isRoot: true)
		public struct Root: Instantiable {
		    public init(screen: Screen, logger: Logger) {
		        self.screen = screen
		        self.logger = logger
		    }

		    @Instantiated let screen: Screen
		    @Instantiated let logger: Logger
		}
		""",
		"""
		@Instantiable(isRoot: true)
		public struct SecondRoot: Instantiable {
		    public init(logger: Logger) {
		        self.logger = logger
		    }

		    @Instantiated let logger: Logger
		}
		""",
		"""
		@Instantiable(generateDependencyTree: true)
		public struct Screen: Instantiable {
		    public init(detail: Detail) {
		        self.detail = detail
		    }

		    @Instantiated let detail: Detail
		}
		""",
		"""
		@Instantiable(generateMock: true)
		public struct Detail: Instantiable {
		    public init() {}
		}
		""",
		"""
		@Instantiable(generateMock: true)
		public final class Logger: Instantiable {
		    public init() {}
		}
		""",
	]
}
