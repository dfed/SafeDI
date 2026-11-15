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
#if canImport(Glibc)
	import Glibc
#endif

/// What the generation and assertion helpers write for `.claude/skills/regenerate-expectations/regenerate-expectations.py`, which rewrites the expected
/// literals of tests whose generated code or diagnostics a change alters.
///
/// A helper records only when it is given a record directory, which by default is the one the
/// `SAFEDI_TEST_RECORD_DIRECTORY` environment variable names; without one it writes nothing and does nothing more than it
/// did before recording existed. Recording never changes what a helper compares, expects or returns: it only adds files.
/// `executeSafeDIToolTest` and `executeSafeDIToolMultiModuleTest` record every output they return, after reading it and
/// before compiling it, since a test compares those in `#expect`s of its own that a helper cannot see fail; the assertion
/// helpers record only a mismatch, with both the expected and the actual description. Each record is a JSON file named
/// after its key, so records of separate calls never share a file, and every run-specific path in a record is replaced by
/// a placeholder that names its role, so two runs over the same commit write the same files.
enum ExpectationRecording {
	/// The environment variable that names the directory to record into.
	static let environmentVariable = "SAFEDI_TEST_RECORD_DIRECTORY"

	/// The directory `environmentVariable` names, or `nil` when it is unset or empty.
	static let directoryFromEnvironment: URL? = {
		guard let path = ProcessInfo.processInfo.environment[environmentVariable], !path.isEmpty else {
			return nil
		}
		return URL(fileURLWithPath: path, isDirectory: true)
	}()

	/// The file every recording call writes `generatedFileHeader` to, so the script can strip it from a record's content
	/// as a test's `generatedFileHeader + """…"""` does.
	static let headerFileName = "generated-file-header.txt"
	/// The output name of a combined output (`--combined-output`).
	static let combinedOutputName = "combined output"
	/// The output name of a DOT tree (`--dot-file-output`).
	static let dotTreeOutputName = "DOT tree"

	/// One output of one generation helper call.
	struct GenerationRecord: Codable, Equatable {
		static let kind = "generation"

		/// Always `GenerationRecord.kind`.
		let kind: String
		let fileID: String
		let line: Int
		let column: Int
		/// The name of the test that made the call, or an empty string outside a test.
		let testName: String
		/// Where the test that made the call is declared (`Test.current`'s source location), or `nil` outside a test. A
		/// call made through a helper function records the helper's line, so this is what ties its output to the literal
		/// the test compares; a file and line name one test, its suite included, where a name alone may not.
		let testFileID: String?
		let testLine: Int?
		/// The multi-module integration, or `nil` for `executeSafeDIToolTest`.
		let integration: String?
		/// The module whose output this is, or `nil` for `executeSafeDIToolTest`.
		let module: String?
		/// A generated file's name, `combinedOutputName` or `dotTreeOutputName`.
		let outputName: String
		/// The output, its run-specific paths replaced by placeholders.
		let content: String
		/// Whether the call opted out of compile verification, so a changed expectation needs reading for compiling.
		let skipsCompileVerification: Bool
		/// The digest of the call's inputs, which tells apart the calls of a parameterized test and repeated calls on one
		/// line.
		let inputsDigest: String
		let key: String
	}

	/// One mismatch an assertion helper found.
	struct AssertionRecord: Codable, Equatable {
		static let kind = "assertion"

		/// Always `AssertionRecord.kind`.
		let kind: String
		let fileID: String
		let line: Int
		let column: Int
		/// The name of the test that made the call, or an empty string outside a test.
		let testName: String
		/// `plain` for `assertThrowsError(_:)`, `diagnostics` for `assertThrowsError(diagnostics:)`, and
		/// `multiModuleDiagnostics` for `assertThrowsMultiModuleError`.
		let overload: String
		/// The module `assertThrowsMultiModuleError` expects to fail, or `nil`.
		let module: String?
		/// The expected description, its run-specific paths replaced by placeholders.
		let expected: String
		/// The actual description, its run-specific paths replaced by placeholders.
		let actual: String
		let key: String
	}

	/// A directory one helper call made, and the placeholder that names its role in a record.
	struct RunDirectory: Sendable {
		init(path: String, placeholder: String, includesCurrentDirectoryRelativeSpelling: Bool = false) {
			self.path = path
			self.placeholder = placeholder
			self.includesCurrentDirectoryRelativeSpelling = includesCurrentDirectoryRelativeSpelling
		}

		let path: String
		let placeholder: String
		/// Whether the directory is also spelled relative to the current directory, as a fixture directory is under
		/// `inputPathsRelativeToCurrentDirectory` and `.scanDuringGenerate`.
		let includesCurrentDirectoryRelativeSpelling: Bool
	}

	/// Replaces each run-specific path in a text with a fixed placeholder: first the call's own directories, then the
	/// directories every call shares, each in every spelling the harness knows, longest first; then any remaining path
	/// that names a UUID-named entry of a run-specific directory, such as a path of an earlier call that a test
	/// interpolates, becomes `$RUN_DIRECTORY`. `RUN_PATH_PLACEHOLDER` in `.claude/skills/regenerate-expectations/regenerate-expectations.py` lists every
	/// placeholder this and the helpers' `RunDirectory` values write; keep the two in step.
	struct PathNormalization {
		init(runDirectories: [RunDirectory]) {
			let currentDirectory = FileManager.default.currentDirectoryPath
			var sharedDirectories = [
				RunDirectory(path: TestTemporaryDirectory.root.path, placeholder: "$TEST_TEMPORARY_DIRECTORY", includesCurrentDirectoryRelativeSpelling: true),
			]
			if let fixtureParentDirectory = TestFixtureLocation.parentDirectory {
				sharedDirectories.append(RunDirectory(path: fixtureParentDirectory.path, placeholder: "$FIXTURE_PARENT_DIRECTORY"))
			}
			sharedDirectories.append(RunDirectory(path: currentDirectory, placeholder: "$CURRENT_DIRECTORY"))
			var placeholderBySpelling = [String: String]()
			var spellingsInOrder = [String]()
			for directory in runDirectories + sharedDirectories {
				for spelling in Self.spellings(of: directory) where placeholderBySpelling[spelling] == nil {
					// The first directory to claim a spelling keeps it: a call's own directories come before shared ones.
					placeholderBySpelling[spelling] = directory.placeholder
					spellingsInOrder.append(spelling)
				}
			}
			// Longest first, so a spelling never replaces part of a longer one; spellings of one length in text order.
			replacements = spellingsInOrder
				.sorted { $0.count != $1.count ? $0.count > $1.count : $0 < $1 }
				.compactMap { spelling in placeholderBySpelling[spelling].map { (spelling, $0) } }
		}

		/// `text` with every run-specific path replaced by its placeholder.
		func normalizing(_ text: String) -> String {
			var normalized = text
			for (spelling, placeholder) in replacements {
				normalized = normalized.replacingOccurrences(of: spelling, with: placeholder)
			}
			return Self.runDirectoryEntryExpression.stringByReplacingMatches(
				in: normalized,
				range: NSRange(normalized.startIndex..., in: normalized),
				withTemplate: "\\$RUN_DIRECTORY",
			)
		}

		private let replacements: [(spelling: String, placeholder: String)]

		/// A UUID-named entry of a run-specific directory, already replaced by its placeholder, or of the fixture
		/// directories `.scanDuringGenerate` makes under the current directory.
		private static let runDirectoryEntryExpression: NSRegularExpression = {
			let uuid = "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"
			let pattern = #"(?:\$TEST_TEMPORARY_DIRECTORY|\$FIXTURE_PARENT_DIRECTORY|\$CURRENT_DIRECTORY/\.build/SafeDIToolTestFixtures|\.build/SafeDIToolTestFixtures)/[^/\s"'`]*"#
				+ uuid
				+ #"[^/\s"'`]*"#
			// The pattern is a constant that compiles.
			return try! NSRegularExpression(pattern: pattern)
		}()

		/// Each spelling of `directory`: as written, with its symbolic links resolved as `realpath(3)` resolves them, with
		/// and without a leading `/private`, and relative to the current directory when it asks for that.
		private static func spellings(of directory: RunDirectory) -> [String] {
			var spellings = [directory.path, resolvedPath(of: directory.path)]
			for spelling in spellings {
				if spelling.hasPrefix("/private/") {
					spellings.append(String(spelling.dropFirst("/private".count)))
				} else if ["/tmp/", "/var/", "/etc/"].contains(where: spelling.hasPrefix) {
					spellings.append("/private" + spelling)
				}
			}
			if directory.includesCurrentDirectoryRelativeSpelling {
				spellings.append(currentDirectoryRelativePath(to: URL(fileURLWithPath: directory.path)))
			}
			var seen = Set<String>()
			return spellings
				.map { $0.hasSuffix("/") && $0.count > 1 ? String($0.dropLast()) : $0 }
				.filter { !$0.isEmpty && $0 != "/" && seen.insert($0).inserted }
		}
	}

	/// The key of a generation record: the SHA-256 digest of its components, sorted by name, each spelled with its length
	/// so no two sets of components spell the same text. `nil` components are left out.
	static func key(
		fileID: String,
		line: Int,
		column: Int,
		testName: String,
		inputsDigest: String,
		integration: String?,
		module: String?,
		outputName: String,
	) -> String {
		digest(of: [
			("kind", GenerationRecord.kind),
			("fileID", fileID),
			("line", "\(line)"),
			("column", "\(column)"),
			("testName", testName),
			("inputsDigest", inputsDigest),
			("integration", integration),
			("module", module),
			("outputName", outputName),
		])
	}

	/// The key of an assertion record, as `key(fileID:line:column:testName:inputsDigest:integration:module:outputName:)`
	/// makes a generation record's. `expectedDigest` is the digest of the normalized expected description.
	static func key(
		fileID: String,
		line: Int,
		column: Int,
		testName: String,
		overload: String,
		module: String?,
		expectedDigest: String,
	) -> String {
		digest(of: [
			("kind", AssertionRecord.kind),
			("fileID", fileID),
			("line", "\(line)"),
			("column", "\(column)"),
			("testName", testName),
			("overload", overload),
			("module", module),
			("expectedDigest", expectedDigest),
		])
	}

	/// The SHA-256 digest of `components`, sorted by name, each spelled `<name>=<UTF-8 byte count>:<value>` on a line of
	/// its own. `nil` values are left out.
	static func digest(of components: [(name: String, value: String?)]) -> String {
		var encoding = ""
		for (name, value) in components.sorted(by: { $0.name < $1.name }) {
			guard let value else { continue }
			encoding += "\(name)=\(value.utf8.count):\(value)\n"
		}
		return sha256HexDigest(of: Data(encoding.utf8))
	}

	/// One output of a generation helper call.
	struct Output {
		let integration: String?
		let module: String?
		let outputName: String
		let content: String
	}

	/// Writes a record of each of `outputs` into `recordDirectory`, unless recording there is refused, which records an
	/// issue instead. `inputs` are the call's inputs as the test passed them, which are normalized before their digest
	/// is taken.
	static func recordGeneration(
		of outputs: [Output],
		inputs: [(name: String, value: String?)],
		skipsCompileVerification: Bool,
		runDirectories: [RunDirectory],
		into recordDirectory: URL,
		sourceLocation: SourceLocation,
	) {
		guard prepare(recordDirectory, sourceLocation: sourceLocation) else { return }
		let normalization = PathNormalization(runDirectories: runDirectories)
		let inputsDigest = digest(of: inputs.map { ($0.name, $0.value.map(normalization.normalizing)) })
		let testName = Test.current?.name ?? ""
		for output in outputs {
			let key = key(
				fileID: sourceLocation.fileID,
				line: sourceLocation.line,
				column: sourceLocation.column,
				testName: testName,
				inputsDigest: inputsDigest,
				integration: output.integration,
				module: output.module,
				outputName: output.outputName,
			)
			write(
				GenerationRecord(
					kind: GenerationRecord.kind,
					fileID: sourceLocation.fileID,
					line: sourceLocation.line,
					column: sourceLocation.column,
					testName: testName,
					testFileID: Test.current?.sourceLocation.fileID,
					testLine: Test.current?.sourceLocation.line,
					integration: output.integration,
					module: output.module,
					outputName: output.outputName,
					content: normalization.normalizing(output.content),
					skipsCompileVerification: skipsCompileVerification,
					inputsDigest: inputsDigest,
					key: key,
				),
				named: key,
				into: recordDirectory,
				sourceLocation: sourceLocation,
			)
		}
	}

	/// Writes a record of an assertion helper's mismatch into `recordDirectory`, unless recording there is refused, which
	/// records an issue instead.
	static func recordAssertionMismatch(
		overload: String,
		module: String?,
		expected: String,
		actual: String,
		error: any Error,
		into recordDirectory: URL,
		sourceLocation: SourceLocation,
	) {
		guard prepare(recordDirectory, sourceLocation: sourceLocation) else { return }
		let normalization = PathNormalization(runDirectories: (error as? any RecordingRunDirectoriesCarrying)?.recordingRunDirectories ?? [])
		let normalizedExpected = normalization.normalizing(expected)
		let testName = Test.current?.name ?? ""
		let key = key(
			fileID: sourceLocation.fileID,
			line: sourceLocation.line,
			column: sourceLocation.column,
			testName: testName,
			overload: overload,
			module: module,
			expectedDigest: sha256HexDigest(of: Data(normalizedExpected.utf8)),
		)
		write(
			AssertionRecord(
				kind: AssertionRecord.kind,
				fileID: sourceLocation.fileID,
				line: sourceLocation.line,
				column: sourceLocation.column,
				testName: testName,
				overload: overload,
				module: module,
				expected: normalizedExpected,
				actual: normalization.normalizing(actual),
				key: key,
			),
			named: key,
			into: recordDirectory,
			sourceLocation: sourceLocation,
		)
	}

	/// Why recording into `directory` is refused, or `nil` when it is not: a directory inside the checkout, which
	/// `swift test` makes the current directory, or inside the system temporary directory, compared with their symbolic
	/// links resolved.
	static func refusal(of directory: URL) -> String? {
		let resolvedDirectory = resolvedPath(of: directory.path)
		let refusedDirectories = [
			("the checkout (the current directory)", FileManager.default.currentDirectoryPath),
			("the system temporary directory", NSTemporaryDirectory()),
			("the system temporary directory", "/tmp"),
		]
		for (description, refusedDirectory) in refusedDirectories {
			let resolvedRefusedDirectory = resolvedPath(of: refusedDirectory)
			if resolvedDirectory == resolvedRefusedDirectory || resolvedDirectory.hasPrefix(resolvedRefusedDirectory + "/") {
				return "Expectation recording refuses to record into \(directory.path), which is inside \(description) (\(resolvedRefusedDirectory)). Name a directory outside both in \(environmentVariable)."
			}
		}
		return nil
	}

	// MARK: Private

	/// Creates `recordDirectory` and writes the header file into it, or records an issue and returns `false` when
	/// recording there is refused or fails.
	private static func prepare(_ recordDirectory: URL, sourceLocation: SourceLocation) -> Bool {
		if let refusal = refusal(of: recordDirectory) {
			Issue.record(Comment(rawValue: refusal), sourceLocation: sourceLocation)
			return false
		}
		do {
			try FileManager.default.createDirectory(at: recordDirectory, withIntermediateDirectories: true)
		} catch {
			Issue.record("Expectation recording could not create \(recordDirectory.path): \(error)", sourceLocation: sourceLocation)
			return false
		}
		write(Data(generatedFileHeader.utf8), toFileNamed: headerFileName, in: recordDirectory, sourceLocation: sourceLocation)
		return true
	}

	private static func write(_ record: some Encodable, named key: String, into recordDirectory: URL, sourceLocation: SourceLocation) {
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
		do {
			try write(encoder.encode(record), toFileNamed: "\(key).json", in: recordDirectory, sourceLocation: sourceLocation)
		} catch {
			Issue.record("Expectation recording could not encode the record \(key): \(error)", sourceLocation: sourceLocation)
		}
	}

	/// Writes `data` to the file of that name in `directory` atomically, through a hard link that fails rather than
	/// replace a file another call wrote. An existing file of the same bytes is left as it is; one of other bytes is a
	/// determinism defect: two calls of one key produced different records.
	private static func write(_ data: Data, toFileNamed fileName: String, in directory: URL, sourceLocation: SourceLocation) {
		let destination = directory.appendingPathComponent(fileName)
		let partialFile = directory.appendingPathComponent(".\(fileName).\(UUID().uuidString).partial")
		defer {
			try? FileManager.default.removeItem(at: partialFile)
		}
		do {
			if !FileManager.default.fileExists(atPath: destination.path) {
				try data.write(to: partialFile)
				do {
					try FileManager.default.linkItem(at: partialFile, to: destination)
					return
				} catch {
					// Another call wrote the file first: compare what it wrote.
				}
			}
			let existingData = try Data(contentsOf: destination)
			if existingData != data {
				Issue.record("Expectation recording wrote two different records named \(fileName) in \(directory.path): the same call produced different output in one run.", sourceLocation: sourceLocation)
			}
		} catch {
			Issue.record("Expectation recording could not write \(destination.path): \(error)", sourceLocation: sourceLocation)
		}
	}

	/// `path` with every symbolic link resolved as `realpath(3)` resolves it, through its longest existing ancestor
	/// when the path does not exist yet.
	private static func resolvedPath(of path: String) -> String {
		var components = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
		var missingComponents = [String]()
		while !components.isEmpty {
			if let resolved = realpath(NSString.path(withComponents: components), nil) {
				defer { free(resolved) }
				return NSString.path(withComponents: [String(cString: resolved)] + missingComponents.reversed())
			}
			missingComponents.append(components.removeLast())
		}
		return path
	}
}

/// An error that carries the directories the helper call that threw it made, so an assertion helper can replace their
/// paths with placeholders in what it records.
protocol RecordingRunDirectoriesCarrying {
	var recordingRunDirectories: [ExpectationRecording.RunDirectory] { get }
}

extension [String] {
	/// The strings, each spelled with its length on a line of its own, so no two arrays spell the same text: a
	/// component of a record's inputs digest.
	var joinedForRecording: String {
		map { "\($0.utf8.count):\($0)\n" }.joined()
	}
}

extension VerificationCompilerSettings {
	/// The settings as one component of a record's inputs digest.
	var descriptionForRecording: String {
		[
			swiftLanguageMode,
			upcomingFeatures.joinedForRecording,
			defaultIsolation ?? "<none>",
			"\(prependsSafeDIImport)",
		].joinedForRecording
	}
}

extension ModuleFixture {
	/// The fixture as one component of a record's inputs digest: its files as the test passed them, before
	/// `$FIXTURE_ROOT` is resolved, and every setting that can change what the tool generates for it.
	var descriptionForRecording: String {
		var components = [String]()
		components.append(name)
		components.append(packageName)
		components.append(swiftFileContent.joinedForRecording)
		components.append(swiftFileContentByFilePath.sorted { $0.key < $1.key }.flatMap { [$0.key, $0.value] }.joinedForRecording)
		components.append(dependencies.joinedForRecording)
		components.append("\(isCheckoutPackage)")
		components.append(activeCompilationConditions.joinedForRecording)
		components.append(buildSettingArguments?.joinedForRecording ?? "<none>")
		components.append(verificationCompilationConditions?.joinedForRecording ?? "<none>")
		components.append(mockConditionalCompilation ?? "<none>")
		components.append("\(deletesSwiftFilesAfterRunning)")
		components.append("\(omitsModuleName)")
		components.append("\(omitsPackageName)")
		components.append("\(isReleaseConfiguration)")
		components.append("\(runsSafeDI)")
		components.append(compilerSettings.descriptionForRecording)
		return components.joinedForRecording
	}
}
