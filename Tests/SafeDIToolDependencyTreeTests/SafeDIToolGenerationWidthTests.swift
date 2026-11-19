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

struct SafeDIToolGenerationWidthTests: ~Copyable {
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
	mutating func generate_writesTheSameBytesAtEveryWidth_whenTheModuleHoldsRootsASeamAndMocks() async throws {
		var outputsByWidth = [Int: (generatedFiles: [String: String]?, moduleInfo: Data, dotTree: String?)]()
		for width in [1, 2, 32] {
			let output = try await GenerationJobs.$width.withValue(width) {
				try await executeSafeDIToolTest(
					swiftFileContent: Self.fixture,
					buildSwiftOutputDirectory: true,
					buildDOTFileOutput: true,
					filesToDelete: &filesToDelete,
					// The generated code compiles at one width, which every other width must match byte for byte.
					skipCompileVerification: width != 1,
					moduleMembershipArguments: ["--module-name", "App"],
				)
			}
			let moduleInfoPath = try #require(output.moduleInfoOutputPath)
			// Each run writes the fixture to a directory of its own, whose path the module info records with each
			// declaration: the one thing the runs' inputs differ in. So the file's bytes are compared with that path
			// replaced in its body, and without the header's last field (bytes 22 to 30), the checksum of that body.
			let fixtureDirectory = try (#require(output.fixtures.writtenPath(of: "Root.swift")) as NSString).deletingLastPathComponent
			let moduleInfoBytes = try Data(contentsOf: URL(fileURLWithPath: moduleInfoPath))
			let moduleInfo = Data(moduleInfoBytes.prefix(22))
				+ Data(moduleInfoBytes.dropFirst(30)).replacingOccurrences(of: Data(fixtureDirectory.utf8), with: Data("FIXTURE_DIRECTORY".utf8))
			outputsByWidth[width] = (output.generatedFiles, moduleInfo, output.dotTree)
		}

		let narrowest = try #require(outputsByWidth[1])
		#expect(narrowest.generatedFiles?.keys.sorted() == [
			"Detail+SafeDIMock.swift",
			"Logger+SafeDIMock.swift",
			"Panel+SafeDIMock.swift",
			"Root+SafeDI.swift",
			"SafeDIMockConfiguration.swift",
			"Screen+SafeDI.swift",
			"SecondRoot+SafeDI.swift",
			"Settings+SafeDIMock.swift",
			"ThirdRoot+SafeDI.swift",
		])
		#expect(narrowest.moduleInfo.count > 30)
		#expect(narrowest.dotTree?.isEmpty == false)
		for width in [2, 32] {
			let output = try #require(outputsByWidth[width])
			#expect(output.generatedFiles == narrowest.generatedFiles, "width \(width)")
			#expect(output.moduleInfo == narrowest.moduleInfo, "width \(width)")
			#expect(output.dotTree == narrowest.dotTree, "width \(width)")
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// Three production roots, a seam, and four types with generated mocks, in one module.
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
		    public init(logger: Logger, settings: Settings) {
		        self.logger = logger
		        self.settings = settings
		    }

		    @Instantiated let logger: Logger
		    @Instantiated let settings: Settings
		}
		""",
		"""
		@Instantiable(isRoot: true)
		public struct ThirdRoot: Instantiable {
		    public init(settings: Settings) {
		        self.settings = settings
		    }

		    @Instantiated let settings: Settings
		}
		""",
		"""
		@Instantiable(generateDependencyTree: true)
		public struct Screen: Instantiable {
		    public init(detail: Detail, logger: Logger) {
		        self.detail = detail
		        self.logger = logger
		    }

		    @Instantiated let detail: Detail
		    @Received let logger: Logger
		}
		""",
		"""
		@Instantiable(generateMock: true)
		public struct Detail: Instantiable {
		    public init(settings: Settings) {
		        self.settings = settings
		    }

		    @Instantiated let settings: Settings
		}
		""",
		"""
		@Instantiable(generateMock: true)
		public final class Logger: Instantiable {
		    public init() {}
		}
		""",
		"""
		@Instantiable(generateMock: true)
		public final class Settings: Instantiable {
		    public init() {}
		}
		""",
		"""
		@Instantiable(generateMock: true)
		public struct Panel: Instantiable {
		    public init(logger: Logger) {
		        self.logger = logger
		    }

		    @Received let logger: Logger
		}
		""",
	]
}

extension Data {
	/// This data with every occurrence of `target` replaced by `replacement`.
	fileprivate func replacingOccurrences(of target: Data, with replacement: Data) -> Data {
		var result = Data()
		var remainder = self[...]
		while let range = remainder.range(of: target) {
			result.append(remainder[remainder.startIndex..<range.lowerBound])
			result.append(replacement)
			remainder = remainder[range.upperBound...]
		}
		result.append(remainder)
		return result
	}
}
