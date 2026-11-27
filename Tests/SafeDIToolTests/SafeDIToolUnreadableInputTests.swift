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

/// The errors `generate` and `query` report for input files they cannot read: each names the file and reads the same on
/// every run, and of several such files read in parallel, the one reported never depends on which read failed first.
struct SafeDIToolUnreadableInputTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Swift files

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorOfFirstPath_whenTwentyFourListedSwiftFilesDoNotExist() async throws {
		// Read in parallel, so the reads finish in any order; listed against their sort order, so neither order picks
		// the first path by chance.
		let directory = try temporaryDirectory()
		let rootPath = try writeRoot(in: directory)
		let missingPaths = (0..<24).reversed().map { directory.appendingPathComponent("Missing\($0).swift").path }

		let message = await generateErrorMessage(listing: [rootPath] + missingPaths, in: directory)

		#expect(message == "Could not read the Swift file at '\(directory.path)/Missing0.swift': No file exists at that path.")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorOfFirstPath_whenTwentyFourListedSwiftFilesAreNotUTF8() async throws {
		let directory = try temporaryDirectory()
		let rootPath = try writeRoot(in: directory)
		var notUTF8Paths = [String]()
		for index in (0..<24).reversed() {
			let url = directory.appendingPathComponent("NotUTF8\(index).swift")
			// A SafeDI marker, so the file is parsed, and a byte that begins no UTF-8 sequence.
			try (Data("import SafeDI\n@Instantiable\n".utf8) + Data([0xFF, 0x0A])).write(to: url)
			notUTF8Paths.append(url.path)
		}

		let message = await generateErrorMessage(listing: [rootPath] + notUTF8Paths, in: directory)

		#expect(message == "Could not read the Swift file at '\(directory.path)/NotUTF80.swift': The file is not UTF-8 text.")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingDirectory_whenListedSwiftFileIsDirectory() async throws {
		let directory = try temporaryDirectory()
		let rootPath = try writeRoot(in: directory)
		let directoryNamedLikeSwiftFile = directory.appendingPathComponent("Folder.swift")
		try FileManager.default.createDirectory(at: directoryNamedLikeSwiftFile, withIntermediateDirectories: true)

		let message = await generateErrorMessage(listing: [rootPath, directoryNamedLikeSwiftFile.path], in: directory)

		#expect(message == "Could not read the Swift file at '\(directoryNamedLikeSwiftFile.path)': The path names a directory, or a file SafeDI may not open.")
	}

	// MARK: Module info files

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorOfFirstPath_whenTwentyFourDependentModuleInfoFilesDoNotExist() async throws {
		let directory = try temporaryDirectory()
		let rootPath = try writeRoot(in: directory)
		let missingPaths = (0..<24).reversed().map { directory.appendingPathComponent("Missing\($0).safedi").path }

		let message = await generateErrorMessage(listing: [rootPath], dependentModuleInfoPaths: missingPaths, in: directory)

		#expect(message == "Could not read the SafeDI module info file at \(directory.path)/Missing0.safedi: No file exists at that path.")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorOfFirstPath_whenTwentyFourDependentModuleInfoFilesAreMalformed() async throws {
		let directory = try temporaryDirectory()
		let rootPath = try writeRoot(in: directory)
		var malformedPaths = [String]()
		for index in (0..<24).reversed() {
			let url = directory.appendingPathComponent("Malformed\(index).safedi")
			try Data("malformed".utf8).write(to: url)
			malformedPaths.append(url.path)
		}

		let message = await generateErrorMessage(listing: [rootPath], dependentModuleInfoPaths: malformedPaths, in: directory)

		#expect(message == "Could not read the SafeDI module info file at \(directory.path)/Malformed0.safedi: The file is 9 bytes long, shorter than a module info file’s header. \(BinaryFile.unreadableFileExplanation)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorOfFirstPath_whenItsFileIsStillBeingReadAsTwentyThreeOthersAreFoundMissing() async throws {
		// `Large.safedi` is listed last and sorts first, which is what “first path” means. It is a quarter of a gigabyte that
		// is no module info, written as a hole so it takes no disk, and the others do not exist, so every other failure
		// arrives while it is being read: a run that reported the failure that arrived first would name a missing file.
		let directory = try temporaryDirectory()
		let rootPath = try writeRoot(in: directory)
		let largeURL = directory.appendingPathComponent("Large.safedi")
		#expect(FileManager.default.createFile(atPath: largeURL.path, contents: nil))
		let largeFile = try FileHandle(forWritingTo: largeURL)
		try largeFile.truncate(atOffset: 256 << 20)
		try largeFile.close()
		let paths = (0..<23).reversed().map { directory.appendingPathComponent("Missing\($0).safedi").path } + [largeURL.path]

		let message = await generateErrorMessage(listing: [rootPath], dependentModuleInfoPaths: paths, in: directory)

		#expect(message == "Could not read the SafeDI module info file at \(directory.path)/Large.safedi: The file is not a module info file: it does not begin with `SDMI`. \(BinaryFile.unreadableFileExplanation)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingDirectory_whenDependentModuleInfoPathIsDirectory() async throws {
		let directory = try temporaryDirectory()
		let rootPath = try writeRoot(in: directory)
		let directoryNamedLikeModuleInfo = directory.appendingPathComponent("Folder.safedi")
		try FileManager.default.createDirectory(at: directoryNamedLikeModuleInfo, withIntermediateDirectories: true)

		let message = await generateErrorMessage(listing: [rootPath], dependentModuleInfoPaths: [directoryNamedLikeModuleInfo.path], in: directory)

		#expect(message == "Could not read the SafeDI module info file at \(directoryNamedLikeModuleInfo.path): The path names a directory, or a file SafeDI may not open.")
	}

	// MARK: Query

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func query_throwsErrorOfFirstModuleByName_whenTwentyFourIncludedModulesHoldFileThatIsNotUTF8() async throws {
		let directory = try temporaryDirectory()
		var includeArguments = [String]()
		for index in (0..<24).reversed() {
			let moduleDirectory = directory.appendingPathComponent("Module\(index)")
			try FileManager.default.createDirectory(at: moduleDirectory, withIntermediateDirectories: true)
			try (Data("import SafeDI\n@Instantiable\n".utf8) + Data([0xFF, 0x0A])).write(to: moduleDirectory.appendingPathComponent("NotUTF8.swift"))
			includeArguments += ["--include", moduleDirectory.path]
		}

		var message: String?
		do {
			_ = try await QueryNeeds.parse(["Root"] + includeArguments).query()
		} catch {
			message = "\(error)"
		}

		#expect(message == "Could not read the Swift file at '\(directory.path)/Module0/NotUTF8.swift': The file is not UTF-8 text.")
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private mutating func temporaryDirectory() throws -> URL {
		let directory = TestTemporaryDirectory.uniquePath(prefix: "UnreadableInput-")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		filesToDelete.append(directory)
		return directory
	}

	/// Writes a root that builds, so that only an unreadable input can fail `generate`, and returns its path.
	private func writeRoot(in directory: URL) throws -> String {
		let url = directory.appendingPathComponent("Root.swift")
		try """
		import SafeDI

		@Instantiable(isRoot: true)
		public final class Root: Instantiable {
		    public init() {}
		}
		""".write(to: url, atomically: true, encoding: .utf8)
		return url.path
	}

	/// The text of the error `generate` throws for a module whose CSV lists `swiftFilePaths` and whose dependencies'
	/// module info files are `dependentModuleInfoPaths`, each CSV and the output written in `directory`; `nil` if it
	/// throws none.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private func generateErrorMessage(listing swiftFilePaths: [String], dependentModuleInfoPaths: [String] = [], in directory: URL) async -> String? {
		let csv = directory.appendingPathComponent("inputs.csv")
		let combinedOutput = directory.appendingPathComponent("Output.generated")
		do {
			try swiftFilePaths.joined(separator: ",").write(to: csv, atomically: true, encoding: .utf8)
			var arguments = [csv.path, "--combined-output", combinedOutput.path, "--module-name", "Feature"]
			if !dependentModuleInfoPaths.isEmpty {
				let dependentModuleInfoCSV = directory.appendingPathComponent("dependencies.csv")
				try dependentModuleInfoPaths.joined(separator: ",").write(to: dependentModuleInfoCSV, atomically: true, encoding: .utf8)
				arguments += ["--dependent-module-info-file-path", dependentModuleInfoCSV.path]
			}
			try await Generate.parse(arguments).run()
			return nil
		} catch {
			return "\(error)"
		}
	}
}
