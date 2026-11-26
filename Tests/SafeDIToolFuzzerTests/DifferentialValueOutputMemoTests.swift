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
@testable import SafeDIToolTestSupport

/// How the differential value comparator keys a program it compiles and runs, and how it reads and keeps what the
/// program printed.
struct DifferentialValueOutputMemoTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		directory = TestTemporaryDirectory.uniquePath(prefix: "safedi-differential-value-output-memo-tests-")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		filesToDelete = [directory]
	}

	deinit {
		for fileToDelete in filesToDelete {
			try? FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – Keys

	@Test
	func key_isTheSame_whenTheProgramIsDescribedTwice() throws {
		#expect(try key() == key())
	}

	@Test
	func key_isTheSame_whenAFileSpellsAnotherFixtureRootAndOtherUUIDs() throws {
		func path(root: String) -> DifferentialValuePath {
			DifferentialValuePath(fixtureFiles: ["Root.swift": Self.fixture], generatedFiles: [
				"Generated.swift": "#sourceLocation(file: \"\(root)/\(UUID().uuidString)/Root.swift\", line: 1)\n#sourceLocation()\n",
			])
		}
		let first = try DifferentialValueOutputMemo.key(of: path(root: "/first"), main: Self.main, executableModuleName: "Program", harness: "harness", build: "build", fixtureRoots: ["/first"])
		let second = try DifferentialValueOutputMemo.key(of: path(root: "/second/root"), main: Self.main, executableModuleName: "Program", harness: "harness", build: "build", fixtureRoots: ["/second/root"])
		#expect(first == second)
	}

	@Test(arguments: [
		"a fixture file", "a fixture file's name", "a generated file", "main", "the executable's module name", "the module's name",
		"the package name", "a dependency", "a compilation condition", "the mock condition", "the language mode", "the harness",
		"the build",
	])
	func key_changes_whenOneInputOfTheProgramChanges(input: String) throws {
		var fixtureFiles = ["Root.swift": Self.fixture]
		var generatedFiles = ["Generated.swift": "extension Root {}\n"]
		var main = Self.main
		var executableModuleName = "Program"
		var moduleName = "Module"
		var packageName: String?
		var dependencyModuleNames = [String]()
		var activeCompilationConditions = [String]()
		var mockConditionalCompilation: String?
		var swiftLanguageMode = "6"
		var harness = "harness"
		var build = "build"
		switch input {
		case "a fixture file": fixtureFiles["Root.swift"] = Self.fixture + "\n"
		case "a fixture file's name": fixtureFiles = ["Other.swift": Self.fixture]
		case "a generated file": generatedFiles["Generated.swift"] = "extension Root { var one: Int { 1 } }\n"
		case "main": main += "print(2)\n"
		case "the executable's module name": executableModuleName = "OtherProgram"
		case "the module's name": moduleName = "OtherModule"
		case "the package name": packageName = "Package"
		case "a dependency": dependencyModuleNames = ["Other"]
		case "a compilation condition": activeCompilationConditions = ["CUSTOM"]
		case "the mock condition": mockConditionalCompilation = "DEBUG"
		case "the language mode": swiftLanguageMode = "5"
		case "the harness": harness = "another harness"
		case "the build": build = "another build"
		default: Issue.record("No change is written for \(input).")
		}
		let changed = try DifferentialValueOutputMemo.key(
			of: DifferentialValuePath(modules: [DifferentialValueModule(
				name: moduleName,
				packageName: packageName,
				dependencyModuleNames: dependencyModuleNames,
				fixtureFiles: fixtureFiles,
				generatedFiles: generatedFiles,
				activeCompilationConditions: activeCompilationConditions,
				mockConditionalCompilation: mockConditionalCompilation,
				swiftLanguageMode: swiftLanguageMode,
			)]),
			main: main,
			executableModuleName: executableModuleName,
			harness: harness,
			build: build,
		)
		#expect(try changed != key())
	}

	// MARK: Tests – Harness description

	@Test(arguments: [
		"the describer", "a harness source", "a runtime source", "a runtime source's name", "the macros tool", "a macros tool where there was none",
		"LD_LIBRARY_PATH", "LD_PRELOAD", "DYLD_LIBRARY_PATH",
	])
	func harnessDescription_changes_whenOneSourceOfWhatAProgramPrintsChanges(source: String) throws {
		// The hand mutations a key of the program's own files alone would miss. A describer that prints a line
		// differently, or calls an `Instantiator` once where it called it twice, makes every program print another
		// description from the same files: the describer is hashed as text. A judgment that ignores a mark of the
		// description needs no key, since only what a program printed is kept and every run judges it again; its
		// source is a harness source all the same. A probe dropped or a sample changed is another `main.swift`,
		// which `key_changes_whenOneInputOfTheProgramChanges` covers.
		let runtime = directory.appendingPathComponent("runtime")
		try FileManager.default.createDirectory(at: runtime.appendingPathComponent("Nested"), withIntermediateDirectories: true)
		let runtimeSource = runtime.appendingPathComponent("Nested/Instantiator.swift")
		let harnessSource = directory.appendingPathComponent("Harness.swift")
		let macrosTool = directory.appendingPathComponent("SafeDIMacros-tool")
		try "public final class Instantiator {}\n".write(to: runtimeSource, atomically: true, encoding: .utf8)
		try "func compile() {}\n".write(to: harnessSource, atomically: true, encoding: .utf8)
		try Data([1, 2, 3]).write(to: macrosTool)
		var describerSource = "emit(\"<\\(number)> \\(typeName)\")"
		var describedMacrosTool: URL? = source == "a macros tool where there was none" ? nil : macrosTool
		var environment = ["PATH": "/usr/bin", "LD_LIBRARY_PATH": "/first"]
		func description() throws -> String {
			try DifferentialValueOutputMemo.harnessDescription(runtimeSourcesDirectory: runtime, macrosTool: describedMacrosTool, describerSource: describerSource, harnessSources: [harnessSource], environment: environment)
		}
		let before = try description()
		switch source {
		case "the describer": describerSource = "emit(\"[\\(number)] \\(typeName)\")"
		case "a harness source": try "func compile() { link() }\n".write(to: harnessSource, atomically: true, encoding: .utf8)
		case "a runtime source": try "public final class Instantiator { let built = 0 }\n".write(to: runtimeSource, atomically: true, encoding: .utf8)
		case "a runtime source's name": try FileManager.default.moveItem(at: runtimeSource, to: runtime.appendingPathComponent("Instantiator.swift"))
		case "the macros tool": try Data([1, 2, 4]).write(to: macrosTool)
		case "a macros tool where there was none": describedMacrosTool = macrosTool
		case "LD_LIBRARY_PATH": environment["LD_LIBRARY_PATH"] = "/second"
		case "LD_PRELOAD": environment["LD_PRELOAD"] = "/library.so"
		case "DYLD_LIBRARY_PATH": environment["DYLD_LIBRARY_PATH"] = "/first"
		default: Issue.record("No change is written for \(source).")
		}
		#expect(try description() != before)
	}

	@Test
	func harnessDescription_isTheSame_whenAVariableNoLoaderReadsChanges() throws {
		let runtime = directory.appendingPathComponent("empty-runtime")
		try FileManager.default.createDirectory(at: runtime, withIntermediateDirectories: true)
		func description(path: String) throws -> String {
			try DifferentialValueOutputMemo.harnessDescription(runtimeSourcesDirectory: runtime, macrosTool: nil, describerSource: "", harnessSources: [], environment: ["PATH": path, "GITHUB_RUN_ID": path])
		}
		#expect(try description(path: "/first") == description(path: "/second"))
	}

	@Test
	func harnessDescription_namesEachHarnessSourceOfTheTestSupportTarget_whenGivenNone() throws {
		let runtime = directory.appendingPathComponent("empty-runtime")
		try FileManager.default.createDirectory(at: runtime, withIntermediateDirectories: true)
		let description = try DifferentialValueOutputMemo.harnessDescription(runtimeSourcesDirectory: runtime, macrosTool: nil, describerSource: "")
		let names = description.split(separator: "\n").filter { $0.hasPrefix("Harness ") }.map { $0.split(separator: " ")[1] }
		#expect(names == ["DifferentialValueComparator.swift", "DifferentialValueOutputMemo.swift", "PassedCompileCheckCache.swift", "SafeDICompileVerifier.swift"])
	}

	@Test
	func harnessDescription_throws_whenAHarnessSourceCannotBeRead() throws {
		let runtime = directory.appendingPathComponent("empty-runtime")
		try FileManager.default.createDirectory(at: runtime, withIntermediateDirectories: true)
		#expect(throws: (any Error).self) {
			try DifferentialValueOutputMemo.harnessDescription(runtimeSourcesDirectory: runtime, macrosTool: nil, describerSource: "", harnessSources: [directory.appendingPathComponent("Missing.swift")])
		}
	}

	// MARK: Tests – Reading and keeping

	@Test
	func output_returnsWhatWasRecorded_whenAnotherMemoOfTheDirectoryRecordedTheKey() {
		let memoDirectory = directory.appendingPathComponent("not-made-yet/value-outputs")
		let first = DifferentialValueOutputMemo(directory: memoDirectory)
		#expect(first.output(for: "key") == nil)
		first.record("probe a\n<1> Root\n", for: "key")
		let second = DifferentialValueOutputMemo(directory: memoDirectory)
		#expect(second.output(for: "key") == "probe a\n<1> Root\n")
		#expect(second.output(for: "another key") == nil)
		second.countRunWithoutAKey()
		#expect(first.tallyLine == "Value comparison programs: 1 compiled and run, 0 read from an earlier run (\(memoDirectory.path)).")
		#expect(second.tallyLine == "Value comparison programs: 1 compiled and run, 1 read from an earlier run, 1 compiled and run without being looked up or recorded because what they depend on could not be described (\(memoDirectory.path)).")
	}

	@Test
	func record_listsTheKeyAsWrittenAndUsedInThisRun_whenTheProcessIsPartOfARun() throws {
		let memo = DifferentialValueOutputMemo(directory: directory.appendingPathComponent("value-outputs"), run: "4242")
		memo.record("probe a\n", for: "first")
		memo.record("probe b\n", for: "second")
		#expect(try lines(of: "value-outputs-written-in-run-4242.txt") == ["first", "second"])
		#expect(try lines(of: "value-outputs-used-in-run-4242.txt") == ["first", "second"])
	}

	@Test
	func output_listsTheKeyAsUsedAndNotAsWrittenInThisRun_whenAnEarlierRunRecordedIt() throws {
		let memoDirectory = directory.appendingPathComponent("value-outputs")
		DifferentialValueOutputMemo(directory: memoDirectory, run: "1").record("probe a\n", for: "restored")
		let memo = DifferentialValueOutputMemo(directory: memoDirectory, run: "2")
		#expect(memo.output(for: "restored") == "probe a\n")
		#expect(memo.output(for: "never recorded") == nil)
		#expect(try lines(of: "value-outputs-used-in-run-2.txt") == ["restored"])
		#expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("value-outputs-written-in-run-2.txt").path))
	}

	@Test
	func record_listsNothingInThisRun_whenTheOutputIsNotKept() {
		let memo = DifferentialValueOutputMemo(directory: directory.appendingPathComponent("value-outputs"), run: "4242")
		memo.record("probe a\n  file: /run-root/Root.swift\n", for: "key", fixtureRoots: ["/run-root"])
		#expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("value-outputs-written-in-run-4242.txt").path))
		#expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("value-outputs-used-in-run-4242.txt").path))
	}

	@Test(arguments: [nil, "", "../elsewhere"] as [String?])
	func init_namesNoFilesOfTheRun_whenTheRunCannotNameAFile(run: String?) {
		let memo = DifferentialValueOutputMemo(directory: directory.appendingPathComponent("value-outputs"), run: run)
		#expect(memo.fileOfKeysWrittenInThisRun == nil)
		#expect(memo.fileOfKeysUsedInThisRun == nil)
	}

	@Test(arguments: ["a fixture root", "a UUID"])
	func record_keepsNothing_whenTheOutputSpellsWhatTheKeyRewrites(spelled: String) {
		// The key is the same under another fixture root and other UUIDs, so an output that spells this run's would be
		// read as the next run's.
		let memo = DifferentialValueOutputMemo(directory: directory.appendingPathComponent("value-outputs"))
		let output = spelled == "a fixture root" ? "probe a\n  file: /run-root/Root.swift\n" : "probe a\n  identifier: \(UUID().uuidString)\n"
		memo.record(output, for: "key", fixtureRoots: ["/run-root"])
		#expect(memo.output(for: "key") == nil)
		#expect(memo.tallyLine == "Value comparison programs: 1 compiled and run, 0 read from an earlier run, 1 not kept because what they printed spells a path or a UUID of this run or could not be written (\(memo.directory.path)).")
	}

	@Test
	func record_keepsNothingAndThrowsNothing_whenTheDirectoryCannotBeMade() throws {
		// A file stands where the directory would be.
		let blocked = directory.appendingPathComponent("a-file")
		try "".write(to: blocked, atomically: true, encoding: .utf8)
		let memo = DifferentialValueOutputMemo(directory: blocked.appendingPathComponent("value-outputs"))
		memo.record("probe a\n", for: "key")
		#expect(memo.output(for: "key") == nil)
		#expect(memo.tallyLine == "Value comparison programs: 1 compiled and run, 0 read from an earlier run, 1 not kept because what they printed spells a path or a UUID of this run or could not be written (\(memo.directory.path)).")
	}

	// MARK: Tests – The comparator

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func outputOfRunning_readsWhatTheProgramPrintedBefore_whenTheMemoHoldsTheProgram() async throws {
		let memoDirectory = directory.appendingPathComponent("value-outputs")
		let path = DifferentialValuePath(fixtureFiles: ["Root.swift": Self.fixture])
		let main = "print(Root().value)\n"
		let first = DifferentialValueOutputMemo(directory: memoDirectory)
		guard let printed = try await DifferentialValueOracle.output(of: path, running: main, memo: first, filesToDelete: &filesToDelete) else {
			// Compile verification is disabled.
			return
		}
		#expect(printed == "7\n")
		#expect(first.tallyLine == "Value comparison programs: 1 compiled and run, 0 read from an earlier run (\(memoDirectory.path)).")
		// The one file the run kept, rewritten by hand, is what the next run returns: it compiled and ran nothing.
		let kept = try FileManager.default.contentsOfDirectory(at: memoDirectory, includingPropertiesForKeys: nil)
		#expect(kept.count == 1)
		try "kept\n".write(to: #require(kept.first), atomically: true, encoding: .utf8)
		let second = DifferentialValueOutputMemo(directory: memoDirectory)
		#expect(try await DifferentialValueOracle.output(of: path, running: main, memo: second, filesToDelete: &filesToDelete) == "kept\n")
		#expect(second.tallyLine == "Value comparison programs: 0 compiled and run, 1 read from an earlier run (\(memoDirectory.path)).")
		// Another program runs.
		#expect(try await DifferentialValueOracle.output(of: path, running: "print(Root().value + 1)\n", memo: second, filesToDelete: &filesToDelete) == "8\n")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func outputOfRunning_keepsNothing_whenTheProgramDoesNotRunToCompletion() async throws {
		let memoDirectory = directory.appendingPathComponent("value-outputs")
		let memo = DifferentialValueOutputMemo(directory: memoDirectory)
		let path = DifferentialValuePath(fixtureFiles: ["Root.swift": Self.fixture])
		guard compileVerificationIsEnabled else { return }
		await #expect(throws: DifferentialValueOracleError.self) {
			try await DifferentialValueOracle.output(of: path, running: "import Foundation\nprint(Root().value)\nexit(3)\n", memo: memo, filesToDelete: &filesToDelete)
		}
		#expect(!FileManager.default.fileExists(atPath: memoDirectory.path))
	}

	// MARK: Private

	private let directory: URL
	private var filesToDelete: [URL]

	private static let fixture = """
	public final class Root {
		public init() {}
		public let value = 7
	}
	"""

	private static let main = "print(1)\n"

	/// The lines of the file `name` beside the memo's directory.
	private func lines(of name: String) throws -> [String] {
		try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8).split(separator: "\n").map(String.init)
	}

	private func key() throws -> String {
		try DifferentialValueOutputMemo.key(
			of: DifferentialValuePath(modules: [DifferentialValueModule(
				name: "Module",
				fixtureFiles: ["Root.swift": Self.fixture],
				generatedFiles: ["Generated.swift": "extension Root {}\n"],
			)]),
			main: Self.main,
			executableModuleName: "Program",
			harness: "harness",
			build: "build",
		)
	}
}
