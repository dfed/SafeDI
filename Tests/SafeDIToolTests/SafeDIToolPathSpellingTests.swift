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
@testable import SafeDITool

/// How `scan` and `generate` spell the paths of a project that a build system reports through a symbolic link
/// this test creates, while the tool's working directory, which `getcwd(3)` reports resolved, reaches the same
/// files without it. Each test runs the commands with the project root spelled through the link and spelled
/// resolved, so it holds wherever the checkout lives and does not rely on `/tmp` or `/var` being links.
///
/// The project's configuration includes, relative to the working directory, a directory holding a root and a
/// directory the inputs also list, as a package's configuration that names a dependency module's sources does.
struct SafeDIToolPathSpellingTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests

	@Test(arguments: [ProjectRootSpelling.throughSymbolicLink, .resolved])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func scan_namesFilesRelativeToProjectRoot_whenProjectRootIsReportedEitherWay(projectRootSpelling: ProjectRootSpelling) async throws {
		let project = try makeProject()

		let manifest = try await project.scan(reportingProjectRoot: projectRootSpelling)

		#expect(manifest.dependencyTreeGeneration.map(\.inputFilePath) == ["Extra/InnerRoot.swift"])
		#expect(manifest.configurationFilePaths == ["Target/SafeDIConfiguration.swift"])
		#expect(manifest.mockScopedFilePaths == ["Target/SafeDIConfiguration.swift"])
	}

	@Test(arguments: [ProjectRootSpelling.throughSymbolicLink, .resolved])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func scan_listsAdditionalDirectoryFilesAsBuildInputsUnderReportedProjectRoot_whenProjectRootIsReportedEitherWay(projectRootSpelling: ProjectRootSpelling) async throws {
		let project = try makeProject()

		let manifest = try await project.scan(reportingProjectRoot: projectRootSpelling)

		// The build system spells the files inside the project root as it reported the root, which is how the plugin
		// hands it these inputs.
		let reportedProjectRoot = project.projectRoot(spelled: projectRootSpelling)
		#expect(manifest.additionalInputFiles == [
			"\(reportedProjectRoot)/Extra/InnerRoot.swift",
			"\(reportedProjectRoot)/Shared/Dependency.swift",
		])
	}

	@Test(arguments: [ProjectRootSpelling.throughSymbolicLink, .resolved])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresInputInAdditionalDirectoryOnce_whenProjectRootIsReportedEitherWay(projectRootSpelling: ProjectRootSpelling) async throws {
		let project = try makeProject()
		_ = try await project.scan(reportingProjectRoot: projectRootSpelling)

		try await project.generate()

		#expect(try project.removingGeneratedFiles() == Self.expectedOutput)
	}

	@Test(arguments: [ProjectRootSpelling.throughSymbolicLink, .resolved])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresInputInAdditionalDirectoryOnce_whenProjectRootIsReportedEitherWayAndScanCacheIsDeleted(projectRootSpelling: ProjectRootSpelling) async throws {
		let project = try makeProject()
		_ = try await project.scan(reportingProjectRoot: projectRootSpelling)
		try FileManager.default.removeItem(at: scannedModuleInfoURL(forManifestPath: project.manifestFile.path))

		try await project.generate()

		#expect(try project.removingGeneratedFiles() == Self.expectedOutput)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The code generated for the root, which declares the dependency the input file and the additional
	/// directory both hold. Declaring it twice fails generation.
	private static let expectedOutput = [
		"InnerRoot+SafeDI.swift": """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		extension InnerRoot {
		    public init() {
		        let dependency = Dependency()
		        self.init(dependency: dependency)
		    }
		}
		""",
	]

	/// How the build system reports the project root to the tool.
	enum ProjectRootSpelling: CaseIterable, CustomTestStringConvertible {
		/// Through a symbolic link to the project directory.
		case throughSymbolicLink
		/// As `realpath(3)` resolves it, which is how the working directory reaches it.
		case resolved

		var testDescription: String {
			switch self {
			case .throughSymbolicLink:
				"through a symbolic link"
			case .resolved:
				"resolved"
			}
		}
	}

	private struct Project {
		/// The project directory, resolved.
		let resolvedDirectory: String
		/// A symbolic link to the project directory.
		let symbolicLink: String
		let outputDirectory: URL
		let manifestFile: URL
		let swiftFileCSV: URL

		func projectRoot(spelled projectRootSpelling: ProjectRootSpelling) -> String {
			switch projectRootSpelling {
			case .throughSymbolicLink:
				symbolicLink
			case .resolved:
				resolvedDirectory
			}
		}

		/// Runs `scan` as a build tool plugin runs it, naming the inputs and the target's files under the project
		/// root as reported, and returns the manifest it writes.
		func scan(reportingProjectRoot projectRootSpelling: ProjectRootSpelling) async throws -> SafeDIToolManifest {
			let projectRoot = projectRoot(spelled: projectRootSpelling)
			try ["Target/SafeDIConfiguration.swift", "Shared/Dependency.swift"]
				.map { "\(projectRoot)/\($0)" }
				.joined(separator: ",")
				.write(to: swiftFileCSV, atomically: true, encoding: .utf8)
			try await Scan.parse([
				"--input-sources-file", swiftFileCSV.path,
				"--project-root", projectRoot,
				"--output-directory", outputDirectory.path,
				"--manifest-file", manifestFile.path,
				"--mock-scoped-files", "\(projectRoot)/Target/SafeDIConfiguration.swift",
			]).run()
			return try JSONDecoder().decode(SafeDIToolManifest.self, from: Data(contentsOf: manifestFile))
		}

		/// Runs `generate` with the manifest `scan` wrote.
		func generate() async throws {
			try await Generate.parse([
				swiftFileCSV.path,
				"--swift-manifest", manifestFile.path,
			]).generate()
		}

		/// The Swift files `generate` wrote, keyed by file name.
		func removingGeneratedFiles() throws -> [String: String] {
			var generatedFiles = [String: String]()
			for fileName in try FileManager.default.contentsOfDirectory(atPath: outputDirectory.path) where fileName.hasSuffix(".swift") {
				generatedFiles[fileName] = try String(contentsOf: outputDirectory.appendingPathComponent(fileName), encoding: .utf8)
			}
			return generatedFiles
		}
	}

	/// A project under the working directory, so its configuration can name its directories relative to the
	/// working directory as a build tool plugin's configuration does, with a symbolic link to it beside it.
	private mutating func makeProject() throws -> Project {
		let fixtureDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
			.appendingPathComponent(".build")
			.appendingPathComponent("SafeDIToolTestFixtures")
			.appendingPathComponent(UUID().uuidString)
		let projectDirectory = fixtureDirectory.appendingPathComponent("Project")
		for directory in ["Target", "Shared", "Extra", "Output"] {
			try FileManager.default.createDirectory(at: projectDirectory.appendingPathComponent(directory), withIntermediateDirectories: true)
		}
		let symbolicLink = fixtureDirectory.appendingPathComponent("Link")
		try FileManager.default.createSymbolicLink(at: symbolicLink, withDestinationURL: projectDirectory)
		filesToDelete.append(fixtureDirectory)

		let projectDirectoryFromWorkingDirectory = currentDirectoryRelativePath(to: projectDirectory)
		try """
		#SafeDIConfiguration(
		    additionalDirectoriesToInclude: ["\(projectDirectoryFromWorkingDirectory)/Extra", "\(projectDirectoryFromWorkingDirectory)/Shared"]
		)
		""".write(to: projectDirectory.appendingPathComponent("Target/SafeDIConfiguration.swift"), atomically: true, encoding: .utf8)
		try """
		@Instantiable
		public struct Dependency: Instantiable {
		    public init() {}
		}
		""".write(to: projectDirectory.appendingPathComponent("Shared/Dependency.swift"), atomically: true, encoding: .utf8)
		try """
		@Instantiable(isRoot: true)
		public struct InnerRoot: Instantiable {
		    public init(dependency: Dependency) {
		        self.dependency = dependency
		    }

		    @Instantiated let dependency: Dependency
		}
		""".write(to: projectDirectory.appendingPathComponent("Extra/InnerRoot.swift"), atomically: true, encoding: .utf8)

		return try Project(
			resolvedDirectory: realPath(of: projectDirectory),
			symbolicLink: symbolicLink.path,
			outputDirectory: projectDirectory.appendingPathComponent("Output"),
			manifestFile: fixtureDirectory.appendingPathComponent("SafeDIManifest.json"),
			swiftFileCSV: fixtureDirectory.appendingPathComponent("InputSwiftFiles.csv"),
		)
	}
}
