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

/// How `scan` and `generate` spell the paths of a project whose root a build system may report through a symbolic
/// link this test creates, while the tool's working directory, which `getcwd(3)` reports resolved, reaches the same
/// files without it. Each test reports the root in several spellings, so it holds wherever the checkout lives and
/// does not rely on `/tmp` or `/var` being links.
///
/// The project lives in a temporary directory, and its configuration names its directories relative to the working
/// directory, as a build tool plugin's configuration does. One additional directory holds a root and another holds
/// a file the inputs also list, as a package's configuration that names a dependency module's sources does.
struct SafeDIToolPathSpellingTests: ~Copyable {
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

	@Test(arguments: ProjectRootSpelling.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func scan_namesFilesRelativeToProjectRoot_whenProjectRootIsReportedEitherWay(projectRootSpelling: ProjectRootSpelling) async throws {
		let project = try makeProject()

		let manifest = try await project.scan(reportingProjectRoot: projectRootSpelling)

		#expect(manifest.dependencyTreeGeneration.map(\.inputFilePath) == ["Extra/InnerRoot.swift"])
		#expect(manifest.configurationFilePaths == ["Target/SafeDIConfiguration.swift"])
		#expect(manifest.mockScopedFilePaths == ["Target/SafeDIConfiguration.swift"])
	}

	@Test(arguments: ProjectRootSpelling.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func scan_listsAdditionalDirectoryFilesAsBuildInputsUnderManifestProjectRoot_whenProjectRootIsReportedEitherWay(projectRootSpelling: ProjectRootSpelling) async throws {
		let project = try makeProject()

		let manifest = try await project.scan(reportingProjectRoot: projectRootSpelling)

		// The build system spells the files inside the project root as it reported the root, made absolute, which is
		// also how the manifest records the root and how `generate` spells the files for the compiler.
		let projectRoot = try #require(manifest.projectRoot)
		#expect(projectRoot == project.absoluteProjectRoot(spelled: projectRootSpelling))
		#expect(manifest.additionalInputFiles == [
			"\(projectRoot)/Extra/InnerRoot.swift",
			"\(projectRoot)/Shared/Dependency.swift",
		])
	}

	@Test(arguments: ProjectRootSpelling.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresInputInAdditionalDirectoryOnce_whenProjectRootIsReportedEitherWay(projectRootSpelling: ProjectRootSpelling) async throws {
		let project = try makeProject()
		_ = try await project.scan(reportingProjectRoot: projectRootSpelling)

		try await project.generate()

		#expect(try project.generatedFiles() == Self.expectedOutput)
	}

	@Test(arguments: ProjectRootSpelling.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresInputInAdditionalDirectoryOnce_whenProjectRootIsReportedEitherWayAndScanCacheIsDeleted(projectRootSpelling: ProjectRootSpelling) async throws {
		let project = try makeProject()
		_ = try await project.scan(reportingProjectRoot: projectRootSpelling)
		try FileManager.default.removeItem(at: scannedModuleInfoURL(forManifestPath: project.manifestFile.path))

		try await project.generate()

		#expect(try project.generatedFiles() == Self.expectedOutput)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_usesScanCache_whenAdditionalDirectoriesAreReachedThroughSymbolicLinkToProjectRoot() async throws {
		// `generate` finds the additional directories' files again to check that none was added, and they compare
		// with the files `scan` found only once both are spelled under the resolved root.
		let project = try makeProject(additionalDirectories: { project in
			["\(project.symbolicLinkFromWorkingDirectory)/Extra", "\(project.symbolicLinkFromWorkingDirectory)/Shared"]
		})
		_ = try await project.scan(reportingProjectRoot: .throughSymbolicLink)
		try project.rewriteRootKeepingModificationTime()

		try await project.generate()

		// Only a fresh parse reads the rewritten root, which instantiates nothing.
		#expect(try project.generatedFiles() == Self.expectedOutput)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_usesScanCache_whenAdditionalDirectoryIsProjectRootReportedThroughSymbolicLink() async throws {
		// A configuration in a project built from its root can name the root itself, `"."`. `generate` must find the
		// directory as `scan` did, from the working directory, rather than through the root as reported.
		let project = try makeProject(additionalDirectories: { project in
			[project.projectDirectoryFromWorkingDirectory]
		})
		_ = try await project.scan(reportingProjectRoot: .throughSymbolicLink)
		try project.rewriteRootKeepingModificationTime()

		try await project.generate()

		// Only a fresh parse reads the rewritten root, which instantiates nothing.
		#expect(try project.generatedFiles() == Self.expectedOutput)
	}

	@Test(arguments: [ProjectRootSpelling.throughSymbolicLink, .resolved])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func buildLog_namesDiagnosticFilesAsBuildSystemSpellsThem_whenProjectRootIsReportedEitherWay(projectRootSpelling: ProjectRootSpelling) async throws {
		// An IDE maps a diagnostic to the file it has open by the path the build system handed it, which is under the
		// root as reported.
		let project = try makeProject(rootDependencyType: "MissingDependency")
		_ = try await project.scan(reportingProjectRoot: projectRootSpelling)
		let buildLog = Generate.BuildLog()

		await assertThrowsError("\(project.absoluteProjectRoot(spelled: projectRootSpelling))/Extra/InnerRoot.swift:6:5: error: No @Instantiable type or extension fulfills `MissingDependency`, which @Instantiated property `dependency: MissingDependency` instantiates. Decorate `MissingDependency`, or an extension of it, with @Instantiable; list `MissingDependency` in the `fulfillingAdditionalTypes` of an @Instantiable type that conforms to it; or, if such a declaration is in another module, make that module one SafeDI reads for this target.") {
			do {
				try await project.generate(buildLog: buildLog)
			} catch let error as any SourceLocatedError {
				throw BuildLogError(description: buildLog.formatted(error.sourceDiagnostics))
			}
		}
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

	/// How the build system reports the project root to `scan`.
	enum ProjectRootSpelling: CaseIterable, CustomTestStringConvertible {
		/// Through a symbolic link to the project directory.
		case throughSymbolicLink
		/// Through a symbolic link to the project directory, with a trailing `/`.
		case throughSymbolicLinkWithTrailingSlash
		/// As `realpath(3)` resolves it, which is how the working directory reaches it.
		case resolved
		/// Relative to the working directory.
		case relativeToWorkingDirectory

		var testDescription: String {
			switch self {
			case .throughSymbolicLink:
				"through a symbolic link"
			case .throughSymbolicLinkWithTrailingSlash:
				"through a symbolic link with a trailing slash"
			case .resolved:
				"resolved"
			case .relativeToWorkingDirectory:
				"relative to the working directory"
			}
		}
	}

	/// A diagnostic formatted for the build log, thrown so `assertThrowsError` compares it.
	private struct BuildLogError: Error, CustomStringConvertible {
		let description: String
	}

	private struct Project {
		/// The project directory as the temporary directory spells it.
		let projectDirectory: URL
		/// The project directory, resolved.
		let resolvedDirectory: String
		/// A symbolic link to the project directory.
		let symbolicLink: String
		let outputDirectory: URL
		let manifestFile: URL
		let swiftFileCSV: URL

		var projectDirectoryFromWorkingDirectory: String {
			currentDirectoryRelativePath(to: projectDirectory)
		}

		var symbolicLinkFromWorkingDirectory: String {
			currentDirectoryRelativePath(to: URL(fileURLWithPath: symbolicLink))
		}

		/// The project root as `scan` is handed it.
		func projectRoot(spelled projectRootSpelling: ProjectRootSpelling) -> String {
			switch projectRootSpelling {
			case .throughSymbolicLink:
				symbolicLink
			case .throughSymbolicLinkWithTrailingSlash:
				"\(symbolicLink)/"
			case .resolved:
				resolvedDirectory
			case .relativeToWorkingDirectory:
				projectDirectoryFromWorkingDirectory
			}
		}

		/// The project root `scan` is handed, made absolute against the working directory without resolving it.
		func absoluteProjectRoot(spelled projectRootSpelling: ProjectRootSpelling) -> String {
			switch projectRootSpelling {
			case .throughSymbolicLink, .throughSymbolicLinkWithTrailingSlash:
				symbolicLink
			case .resolved:
				resolvedDirectory
			case .relativeToWorkingDirectory:
				projectDirectory.path
			}
		}

		/// Runs `scan` as a build tool plugin runs it, naming the inputs and the target's files under the project
		/// root, made absolute, and returns the manifest it writes.
		func scan(reportingProjectRoot projectRootSpelling: ProjectRootSpelling) async throws -> SafeDIToolManifest {
			let inputRoot = absoluteProjectRoot(spelled: projectRootSpelling)
			try ["Target/SafeDIConfiguration.swift", "Shared/Dependency.swift"]
				.map { "\(inputRoot)/\($0)" }
				.joined(separator: ",")
				.write(to: swiftFileCSV, atomically: true, encoding: .utf8)
			try await Scan.parse([
				"--input-sources-file", swiftFileCSV.path,
				"--project-root", projectRoot(spelled: projectRootSpelling),
				"--output-directory", outputDirectory.path,
				"--manifest-file", manifestFile.path,
				"--mock-scoped-files", "\(inputRoot)/Target/SafeDIConfiguration.swift",
			]).run()
			return try JSONDecoder().decode(SafeDIToolManifest.self, from: Data(contentsOf: manifestFile))
		}

		/// Runs `generate` with the manifest `scan` wrote.
		func generate(buildLog: Generate.BuildLog = Generate.BuildLog()) async throws {
			try await Generate.parse([
				swiftFileCSV.path,
				"--swift-manifest", manifestFile.path,
			]).generate(buildLog: buildLog)
		}

		/// Rewrites the root so it instantiates nothing, keeping the modification time `scan` recorded, so only a
		/// `generate` that parses afresh reads the change.
		func rewriteRootKeepingModificationTime() throws {
			let rootFile = projectDirectory.appendingPathComponent("Extra/InnerRoot.swift")
			let scannedModificationTime = try FileModificationTime(ofItemAtPath: rootFile.path)
			try """
			@Instantiable(isRoot: true)
			public struct InnerRoot: Instantiable {
			    public init() {}
			}
			""".write(to: rootFile, atomically: true, encoding: .utf8)
			try scannedModificationTime.apply(toItemAtPath: rootFile.path)
		}

		/// The Swift files `generate` wrote, keyed by file name.
		func generatedFiles() throws -> [String: String] {
			var generatedFiles = [String: String]()
			for fileName in try FileManager.default.contentsOfDirectory(atPath: outputDirectory.path) where fileName.hasSuffix(".swift") {
				generatedFiles[fileName] = try String(contentsOf: outputDirectory.appendingPathComponent(fileName), encoding: .utf8)
			}
			return generatedFiles
		}
	}

	/// A project in a temporary directory, with a symbolic link to it beside it.
	/// - Parameters:
	///   - additionalDirectories: The directories the configuration includes, relative to the working directory. By
	///     default, the project's `Extra` and `Shared` directories, reached without the link.
	///   - rootDependencyType: The type the root instantiates.
	private mutating func makeProject(
		additionalDirectories: (Project) -> [String] = { project in
			["\(project.projectDirectoryFromWorkingDirectory)/Extra", "\(project.projectDirectoryFromWorkingDirectory)/Shared"]
		},
		rootDependencyType: String = "Dependency",
	) throws -> Project {
		let fixtureDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
		let projectDirectory = fixtureDirectory.appendingPathComponent("Project")
		for directory in ["Target", "Shared", "Extra"] {
			try FileManager.default.createDirectory(at: projectDirectory.appendingPathComponent(directory), withIntermediateDirectories: true)
		}
		let outputDirectory = fixtureDirectory.appendingPathComponent("Output")
		try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
		// The link lies deeper than any working directory, so a directory named relative to the working directory names
		// no directory when it is wrongly read relative to the root reported through the link.
		let symbolicLinkDirectory = (0..<32).reduce(fixtureDirectory) { directory, _ in directory.appendingPathComponent("Nested") }
		try FileManager.default.createDirectory(at: symbolicLinkDirectory, withIntermediateDirectories: true)
		let symbolicLink = symbolicLinkDirectory.appendingPathComponent("Link")
		try FileManager.default.createSymbolicLink(at: symbolicLink, withDestinationURL: projectDirectory)
		filesToDelete.append(fixtureDirectory)

		let project = try Project(
			projectDirectory: projectDirectory,
			resolvedDirectory: realPath(of: projectDirectory),
			symbolicLink: symbolicLink.path,
			outputDirectory: outputDirectory,
			manifestFile: fixtureDirectory.appendingPathComponent("SafeDIManifest.json"),
			swiftFileCSV: fixtureDirectory.appendingPathComponent("InputSwiftFiles.csv"),
		)
		try """
		#SafeDIConfiguration(
		    additionalDirectoriesToInclude: [\(additionalDirectories(project).map { "\"\($0)\"" }.joined(separator: ", "))]
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
		    public init(dependency: \(rootDependencyType)) {
		        self.dependency = dependency
		    }
		    @Instantiated let dependency: \(rootDependencyType)
		}
		""".write(to: projectDirectory.appendingPathComponent("Extra/InnerRoot.swift"), atomically: true, encoding: .utf8)
		return project
	}
}
