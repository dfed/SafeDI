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

/// When the `scan` subcommand leaves its manifest as the last run wrote it, verified through the command.
///
/// Each test edits `Other.swift` so that it declares a root, and puts the file's modification time back, so that only a
/// run that scans again lists the root in the manifest. A run that lists only `Root.swift`'s root therefore parsed
/// nothing.
struct SafeDIToolScanInputsRecordTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try? FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func scan_writesNothing_whenNothingItReadChanged() async throws {
		let project = try await scannedProject()
		let manifestTime = try FileModificationTime(ofItemAtPath: project.manifestFile.path)
		try project.declareRootInOtherFileKeepingItsTime()

		try await project.scan()

		#expect(try project.rootFiles() == ["Root.swift"])
		#expect(try FileModificationTime(ofItemAtPath: project.manifestFile.path) == manifestTime)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func scan_scansAgain_whenAnInputsModificationTimeChanges() async throws {
		let project = try await scannedProject()
		try project.declareRootInOtherFileKeepingItsTime()
		try FileModificationTime(seconds: 4_000_000_000, nanoseconds: 0).apply(toItemAtPath: project.otherFile.path)

		try await project.scan()

		#expect(try project.rootFiles() == ["Other.swift", "Root.swift"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func scan_scansAgain_whenAnArgumentChanges() async throws {
		let project = try await scannedProject()
		try project.declareRootInOtherFileKeepingItsTime()

		try await project.scan(activeCompilationConditions: ["FLAG"])

		#expect(try project.rootFiles() == ["Other.swift", "Root.swift"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func scan_scansAgain_whenTheManifestChanged() async throws {
		let project = try await scannedProject()
		try project.declareRootInOtherFileKeepingItsTime()
		try FileModificationTime(seconds: 4_000_000_000, nanoseconds: 0).apply(toItemAtPath: project.manifestFile.path)

		try await project.scan()

		#expect(try project.rootFiles() == ["Other.swift", "Root.swift"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func scan_scansAgain_whenTheScanCacheIsGone() async throws {
		let project = try await scannedProject()
		try project.declareRootInOtherFileKeepingItsTime()
		try FileManager.default.removeItem(at: scannedModuleInfoURL(forManifestPath: project.manifestFile.path))

		try await project.scan()

		#expect(try project.rootFiles() == ["Other.swift", "Root.swift"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func scan_writesNothing_whenNoFileWasAddedToAnAdditionalDirectory() async throws {
		let project = try await scannedProject(includingAdditionalDirectory: true)
		try project.declareRootInOtherFileKeepingItsTime()

		try await project.scan()

		#expect(try project.rootFiles() == ["Root.swift"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func scan_scansAgain_whenAFileIsAddedToAnAdditionalDirectory() async throws {
		let project = try await scannedProject(includingAdditionalDirectory: true)
		try Self.rootContent(named: "Added").write(to: project.additionalDirectory.appendingPathComponent("Added.swift"), atomically: true, encoding: .utf8)

		try await project.scan()

		#expect(try project.rootFiles() == ["Added.swift", "Root.swift"])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private static func rootContent(named name: String) -> String {
		"""
		import SafeDI

		@Instantiable(isRoot: true)
		public final class \(name): Instantiable {
			public init() {}
		}
		"""
	}

	private struct ScannedProject {
		let directory: URL
		let otherFile: URL
		let additionalDirectory: URL
		let swiftFileCSV: URL
		let outputDirectory: URL
		let manifestFile: URL

		@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
		func scan(activeCompilationConditions: [String] = []) async throws {
			try await Scan.parse([
				"--input-sources-file", swiftFileCSV.path,
				"--project-root", directory.path,
				"--output-directory", outputDirectory.path,
				"--manifest-file", manifestFile.path,
			] + (activeCompilationConditions.isEmpty ? [] : ["--active-compilation-conditions"] + activeCompilationConditions)).run()
		}

		/// Makes `Other.swift` declare a root, keeping the modification time it had.
		func declareRootInOtherFileKeepingItsTime() throws {
			let time = try FileModificationTime(ofItemAtPath: otherFile.path)
			try SafeDIToolScanInputsRecordTests.rootContent(named: "Other").write(to: otherFile, atomically: true, encoding: .utf8)
			try time.apply(toItemAtPath: otherFile.path)
		}

		/// The names of the files whose roots the manifest lists.
		func rootFiles() throws -> [String] {
			try JSONDecoder()
				.decode(SafeDIToolManifest.self, from: Data(contentsOf: manifestFile))
				.dependencyTreeGeneration
				.map { ($0.inputFilePath as NSString).lastPathComponent }
				.sorted()
		}
	}

	/// A project whose root is in `Root.swift` and whose `Other.swift` declares nothing, scanned once. With
	/// `includingAdditionalDirectory`, a configuration adds a directory outside the project that holds no file.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func scannedProject(includingAdditionalDirectory: Bool = false) async throws -> ScannedProject {
		let directory = TestTemporaryDirectory.uniquePath()
		let additionalDirectory = TestTemporaryDirectory.uniquePath()
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		try FileManager.default.createDirectory(at: additionalDirectory, withIntermediateDirectories: true)
		let rootFile = directory.appendingPathComponent("Root.swift")
		let otherFile = directory.appendingPathComponent("Other.swift")
		try Self.rootContent(named: "Root").write(to: rootFile, atomically: true, encoding: .utf8)
		try "struct Other {}\n".write(to: otherFile, atomically: true, encoding: .utf8)
		var inputFiles = [rootFile, otherFile]
		if includingAdditionalDirectory {
			let configurationFile = directory.appendingPathComponent("SafeDIConfiguration.swift")
			try """
			import SafeDI

			#SafeDIConfiguration(additionalDirectoriesToInclude: ["\(additionalDirectory.path)"])
			""".write(to: configurationFile, atomically: true, encoding: .utf8)
			inputFiles.append(configurationFile)
		}
		let swiftFileCSV = TestTemporaryDirectory.uniquePath(pathExtension: "csv")
		try inputFiles.map(\.path).joined(separator: ",").write(to: swiftFileCSV, atomically: true, encoding: .utf8)
		let outputDirectory = TestTemporaryDirectory.uniquePath()
		try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
		let manifestFile = TestTemporaryDirectory.uniquePath(pathExtension: "json")
		filesToDelete += [
			directory,
			additionalDirectory,
			swiftFileCSV,
			outputDirectory,
			manifestFile,
			scannedModuleInfoURL(forManifestPath: manifestFile.path),
			ScanInputsRecord.url(besideManifestFile: manifestFile.path),
		]

		let project = ScannedProject(
			directory: directory,
			otherFile: otherFile,
			additionalDirectory: additionalDirectory,
			swiftFileCSV: swiftFileCSV,
			outputDirectory: outputDirectory,
			manifestFile: manifestFile,
		)
		try await project.scan()
		return project
	}
}
