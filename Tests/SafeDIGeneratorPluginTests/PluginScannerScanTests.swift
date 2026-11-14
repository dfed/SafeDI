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

/// `PluginScanner.scan`, the plugin's fallback when it cannot run `SafeDITool scan`, run over fixture projects.
struct PluginScannerScanTests {
	@Test
	func scan_plansRootDependencyTreeAndMockOutputs_whenFilesDeclareThem() throws {
		let project = try FixtureProject(files: [
			"Root.swift": """
			@Instantiable(isRoot: true)
			public struct Root: Instantiable {}
			""",
			"Screen.swift": """
			@Instantiable(generateDependencyTree: true)
			public struct Screen: Instantiable {}
			""",
			"Service.swift": """
			@Instantiable(generateMock: true)
			public struct Service: Instantiable {}
			""",
			"Plain.swift": """
			@Instantiable
			public struct Plain: Instantiable {}
			""",
			"Helper.swift": """
			struct Helper {}
			""",
		])
		defer { project.remove() }

		let result = PluginScanner.scan(
			swiftFiles: project.fileURLs,
			mockScopedSwiftFiles: project.fileURLs,
			relativeTo: project.root,
			outputDirectory: project.outputDirectory,
		)

		#expect(result.outputFiles == [
			project.outputDirectory.appendingPathComponent("Root+SafeDI.swift"),
			project.outputDirectory.appendingPathComponent("Screen+SafeDI.swift"),
			project.outputDirectory.appendingPathComponent("Service+SafeDIMock.swift"),
			project.outputDirectory.appendingPathComponent("SafeDIMockConfiguration.swift"),
		])
		#expect(result.additionalInputFiles == [])
	}

	@Test
	func scan_plansNoMockConfiguration_whenNoFileGeneratesAMock() throws {
		let project = try FixtureProject(files: [
			"Root.swift": """
			@Instantiable(isRoot: true)
			public struct Root: Instantiable {}
			""",
		])
		defer { project.remove() }

		let result = PluginScanner.scan(
			swiftFiles: project.fileURLs,
			mockScopedSwiftFiles: project.fileURLs,
			relativeTo: project.root,
			outputDirectory: project.outputDirectory,
		)

		#expect(result.outputFiles == [project.outputDirectory.appendingPathComponent("Root+SafeDI.swift")])
	}

	@Test
	func scan_plansEachAdditionalDirectoryAndMockOnce_whenEveryConfigurationClauseListsThem() throws {
		let project = try FixtureProject(files: [
			"Configuration.swift": """
			#if DEBUG
			#SafeDIConfiguration(
				additionalDirectoriesToInclude: ["Extra"],
				additionalMocksToGenerate: ["Client"],
			)
			#else
			#SafeDIConfiguration(
				additionalDirectoriesToInclude: ["Extra"],
				additionalMocksToGenerate: ["Client"],
			)
			#endif
			""",
			"Helper.swift": """
			struct Helper {}
			""",
		], additionalFiles: [
			"Extra/ExtraRoot.swift": """
			@Instantiable(isRoot: true)
			public struct ExtraRoot: Instantiable {}
			""",
			"Extra/Notes.md": """
			@Instantiable(isRoot: true) in a file that is not Swift.
			""",
		])
		defer { project.remove() }

		let result = PluginScanner.scan(
			swiftFiles: project.fileURLs,
			mockScopedSwiftFiles: project.fileURLs,
			relativeTo: project.root,
			outputDirectory: project.outputDirectory,
		)

		#expect(result.outputFiles == [
			project.outputDirectory.appendingPathComponent("ExtraRoot+SafeDI.swift"),
			project.outputDirectory.appendingPathComponent("Client+SafeDIMock.swift"),
			project.outputDirectory.appendingPathComponent("SafeDIMockConfiguration.swift"),
		])
		#expect(result.additionalInputFiles.map(\.lastPathComponent) == ["ExtraRoot.swift"])
	}

	@Test
	func scan_findsAdditionalDirectoryInsideProjectRoot_whenProjectRootLacksATrailingSlash() throws {
		let project = try FixtureProject(files: [
			"Configuration.swift": """
			#SafeDIConfiguration(additionalDirectoriesToInclude: ["Extra"])
			""",
		], additionalFiles: [
			"Extra/ExtraRoot.swift": """
			@Instantiable(isRoot: true)
			public struct ExtraRoot: Instantiable {}
			""",
		])
		defer { project.remove() }
		// Resolved against a root without a trailing slash, `Extra` would name a sibling of the project.
		let projectRoot = URL(fileURLWithPath: project.root.path(percentEncoded: false), isDirectory: false)
		#expect(!projectRoot.hasDirectoryPath)

		let result = PluginScanner.scan(
			swiftFiles: project.fileURLs,
			mockScopedSwiftFiles: project.fileURLs,
			relativeTo: projectRoot,
			outputDirectory: project.outputDirectory,
		)

		#expect(result.outputFiles == [project.outputDirectory.appendingPathComponent("ExtraRoot+SafeDI.swift")])
		#expect(result.additionalInputFiles.map(\.lastPathComponent) == ["ExtraRoot.swift"])
	}

	@Test
	func scan_plansNoAdditionalInput_whenAdditionalDirectoryDoesNotExist() throws {
		let project = try FixtureProject(files: [
			"Configuration.swift": """
			#SafeDIConfiguration(additionalDirectoriesToInclude: ["Missing"])
			""",
		])
		defer { project.remove() }

		let result = PluginScanner.scan(
			swiftFiles: project.fileURLs,
			mockScopedSwiftFiles: project.fileURLs,
			relativeTo: project.root,
			outputDirectory: project.outputDirectory,
		)

		#expect(result.outputFiles == [])
		#expect(result.additionalInputFiles == [])
	}

	@Test
	func scan_plansNothingForAFile_whenItCannotBeRead() throws {
		let project = try FixtureProject(files: [:])
		defer { project.remove() }
		let missingFile = project.root.appendingPathComponent("Missing.swift")

		let result = PluginScanner.scan(
			swiftFiles: [missingFile],
			mockScopedSwiftFiles: [missingFile],
			relativeTo: project.root,
			outputDirectory: project.outputDirectory,
		)

		#expect(result.outputFiles == [])
		#expect(result.additionalInputFiles == [])
	}
}

/// A project directory under `TestTemporaryDirectory.root` holding the given files, and an output directory beside it.
private struct FixtureProject {
	/// The project's directory, as a directory URL.
	let root: URL
	let outputDirectory: URL
	/// The URLs of `files`, in path order.
	let fileURLs: [URL]

	/// Writes `files` and `additionalFiles`, each keyed by its path inside the project; only `files` are in `fileURLs`.
	init(files: [String: String], additionalFiles: [String: String] = [:]) throws {
		let directory = TestTemporaryDirectory.uniquePath(prefix: "PluginScanner-")
		let root = directory.appendingPathComponent("Project", isDirectory: true)
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		for (path, contents) in files.merging(additionalFiles, uniquingKeysWith: { file, _ in file }) {
			let fileURL = root.appendingPathComponent(path)
			try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
			try Data(contents.utf8).write(to: fileURL)
		}
		self.root = root
		outputDirectory = directory.appendingPathComponent("Output", isDirectory: true)
		fileURLs = files.keys.sorted().map { root.appendingPathComponent($0) }
	}

	func remove() {
		try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
	}
}
