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

/// What the programs `DifferentialValueOracle` compiled and ran in earlier runs printed, kept in a directory so that
/// CI compiles and runs only the programs it has not seen run to completion.
///
/// A program is one path's modules, linked with a `main.swift` and run. Each program that exits with status 0 writes
/// what it printed to a file named by its key, and a later program with that key compiles and runs nothing: the
/// comparator reads the file in place of the program's standard output. A program that fails to compile, link or run
/// is never written, so it is compiled, and fails, on every run.
///
/// The key covers everything the output depends on: every file of the program and how each module is compiled
/// (`key(of:main:executableModuleName:harness:build:fixtureRoots:)`), the sources that decide what a program is and
/// what it prints (`DifferentialValueOracle`'s own file with its describer, the compile helper's, this file's and the
/// compile check cache's), the sources of the SafeDI runtime the program links, and what compiles it
/// (`CompileCheckBuild`). The macro plugin of this checkout is covered as it is for a compile check, by the hash CI
/// names the directory's cache with (`.github/scripts/compile-check-identity.sh`).
///
/// What the memo cannot see is a program whose output differs between two runs of the same bytes, such as a race in
/// generated code: once a run printed what the comparator accepts, later runs read that. "Build and Test on Latest
/// Swift" sets no `SAFEDI_COMPILE_CHECK_PASSED_CACHE`, so it compiles and runs every program on every run.
///
/// The directory is `value-outputs`, beside the file `SAFEDI_COMPILE_CHECK_PASSED_CACHE` names, so that the job's
/// cache of that file's directory carries it. When the variable is unset, as it is by default, every program runs.
struct DifferentialValueOutputMemo: Sendable {
	/// The memo beside the file the `SAFEDI_COMPILE_CHECK_PASSED_CACHE` environment variable names, or `nil` when it
	/// names none. A process that uses it prints, when it exits, how many programs it ran and how many it read.
	static let current: DifferentialValueOutputMemo? = {
		guard let path = ProcessInfo.processInfo.environment[PassedCompileCheckCache.environmentVariable], !path.isEmpty else { return nil }
		atexit {
			DifferentialValueOutputMemo.current?.printTally()
		}
		return DifferentialValueOutputMemo(directory: URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("value-outputs"))
	}()

	/// The directory of outputs: one file per key.
	let directory: URL

	/// What the program whose key is `key` printed in an earlier run, or `nil` when no run recorded it. An answer
	/// counts the program as read, and `nil` counts it as run.
	func output(for key: String) -> String? {
		guard let output = try? String(contentsOf: file(for: key), encoding: .utf8) else {
			tally.countRun()
			return nil
		}
		tally.countRead()
		return output
	}

	/// Counts a program that ran without a key, because what it depends on could not be described.
	func countRunWithoutAKey() {
		tally.countRunWithoutAKey()
	}

	/// Writes `output` as what the program whose key is `key` printed, making the directory when it does not exist
	/// yet. The file is written beside its place and moved there, so that a test process never reads half of one.
	///
	/// Keeps nothing, and counts it, when `output` spells one of `fixtureRoots` or a UUID: the key rewrites both, so
	/// the next run of the same key would read this run's paths. Keeps nothing, and counts it, when the file cannot
	/// be written: the memo only saves time, so a full disk or a directory that cannot be written fails no test.
	func record(_ output: String, for key: String, fixtureRoots: [String] = PassedCompileCheckCache.currentFixtureRoots) {
		var normalization = CompileCheckTextNormalization(fixtureRoots: fixtureRoots)
		guard normalization.normalizing(output) == output else {
			tally.countNotKept()
			return
		}
		do {
			try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
			try output.write(to: file(for: key), atomically: true, encoding: .utf8)
		} catch {
			tally.countNotKept()
		}
	}

	/// The key of the program that links `path`'s modules with `main` into `executableModuleName`: the SHA-256 of a
	/// canonical description of `build` (what compiles it, as `CompileCheckBuild.description` gives it), `harness`
	/// (the sources that decide what a program is and prints, and its runtime's, as
	/// `harnessDescription(runtimeSourcesDirectory:macrosTool:describerSource:)` gives them), each module's name,
	/// package, dependencies and conditions, the name and contents of each of its files in name order, and `main`.
	///
	/// Each of `fixtureRoots` and each UUID is rewritten as a compile check's key rewrites them
	/// (`CompileCheckTextNormalization`), so that a file that spells a path of this run has the same key in the next.
	static func key(
		of path: DifferentialValuePath,
		main: String,
		executableModuleName: String,
		harness: String,
		build: String,
		fixtureRoots: [String] = PassedCompileCheckCache.currentFixtureRoots,
	) throws -> String {
		var normalization = CompileCheckTextNormalization(fixtureRoots: fixtureRoots)
		func files(_ contentsByName: [String: String]) -> [ProgramDescription.File] {
			contentsByName.sorted { $0.key < $1.key }.map { name, contents in
				ProgramDescription.File(name: name, contents: normalization.normalizing(contents))
			}
		}
		var modules = [ProgramDescription.Module]()
		for module in path.modules {
			modules.append(ProgramDescription.Module(
				name: module.name,
				packageName: module.packageName,
				dependencyModuleNames: module.dependencyModuleNames,
				activeCompilationConditions: module.activeCompilationConditions,
				mockConditionalCompilation: module.mockConditionalCompilation,
				fixtureFiles: files(module.fixtureFiles),
				generatedFiles: files(module.generatedFiles),
			))
		}
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.sortedKeys]
		return try sha256HexDigest(of: encoder.encode(ProgramDescription(
			formatVersion: 1,
			build: build,
			harness: harness,
			modules: modules,
			main: normalization.normalizing(main),
			executableModuleName: executableModuleName,
		)))
	}

	/// One line per source that decides what a program is and what it prints, each with the SHA-256 of its bytes:
	/// `describerSource`, the files of the test support target that stage, compile, link and describe a program and
	/// key its output, every Swift file under `runtimeSourcesDirectory`, in path order, and `macrosTool` when the
	/// program compiles against another release's, whose plugin no hash of this checkout's sources covers, and the
	/// variables of `environment` that tell a program's dynamic loader which libraries to load.
	static func harnessDescription(
		runtimeSourcesDirectory: URL,
		macrosTool: URL?,
		describerSource: String,
		harnessSources: [URL] = harnessSources,
		environment: [String: String] = ProcessInfo.processInfo.environment,
	) throws -> String {
		var description = "Describer \(sha256HexDigest(of: Data(describerSource.utf8)))\n"
		// What the dynamic loader of a program reads from the environment it inherits from this process, which decides
		// the libraries the program runs against.
		for (name, value) in environment.sorted(by: { $0.key < $1.key }) where name == "LD_LIBRARY_PATH" || name == "LD_PRELOAD" || name.hasPrefix("DYLD_") {
			description += "Environment \(name)=\(value)\n"
		}
		for source in harnessSources {
			description += try "Harness \(source.lastPathComponent) \(sha256HexDigest(of: Data(contentsOf: source)))\n"
		}
		let runtimeSources = try FileManager.default
			.subpathsOfDirectory(atPath: runtimeSourcesDirectory.path)
			.filter { $0.hasSuffix(".swift") }
			.sorted()
		for source in runtimeSources {
			description += try "Runtime \(source) \(sha256HexDigest(of: Data(contentsOf: runtimeSourcesDirectory.appendingPathComponent(source))))\n"
		}
		if let macrosTool {
			description += try "Macros tool \(sha256HexDigest(of: Data(contentsOf: macrosTool)))\n"
		}
		return description
	}

	/// The files of the test support target that decide what a program is and what it prints, found from this file's
	/// location in the package.
	static var harnessSources: [URL] {
		let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
		return [
			"DifferentialValueComparator.swift",
			"DifferentialValueOutputMemo.swift",
			"PassedCompileCheckCache.swift",
			"SafeDICompileVerifier.swift",
		].map { directory.appendingPathComponent($0) }
	}

	/// What the process prints when it exits: how many programs ran and how many were read, and how many ran without
	/// a key when what they depend on could not be described.
	var tallyLine: String {
		let counts = tally.counts
		var line = "Value comparison programs: \(counts.run) compiled and run, \(counts.read) read from an earlier run"
		if counts.runWithoutAKey > 0 {
			line += ", \(counts.runWithoutAKey) compiled and run without being looked up or recorded because what they depend on could not be described"
		}
		if counts.notKept > 0 {
			line += ", \(counts.notKept) not kept because what they printed spells a path or a UUID of this run or could not be written"
		}
		line += " (\(directory.path))."
		return line
	}

	// MARK: Private

	private let tally = DifferentialValueOutputMemoTally()

	private func file(for key: String) -> URL {
		directory.appendingPathComponent("\(key).txt")
	}

	private func printTally() {
		FileHandle.standardError.write(Data((tallyLine + "\n").utf8))
	}
}

/// What a program's key is the hash of. `JSONEncoder` with sorted keys gives it one spelling.
private struct ProgramDescription: Encodable {
	struct File: Encodable {
		let name: String
		let contents: String
	}

	struct Module: Encodable {
		let name: String
		let packageName: String?
		let dependencyModuleNames: [String]
		let activeCompilationConditions: [String]
		let mockConditionalCompilation: String?
		let fixtureFiles: [File]
		let generatedFiles: [File]
	}

	let formatVersion: Int
	let build: String
	let harness: String
	let modules: [Module]
	let main: String
	let executableModuleName: String
}

/// How many programs a memo ran and read, counted from the tests that run in parallel.
private final class DifferentialValueOutputMemoTally: Sendable {
	var counts: (run: Int, read: Int, runWithoutAKey: Int, notKept: Int) {
		lock.withLock { (run, read, runWithoutAKey, notKept) }
	}

	func countNotKept() {
		lock.withLock { notKept += 1 }
	}

	func countRun() {
		lock.withLock { run += 1 }
	}

	func countRead() {
		lock.withLock { read += 1 }
	}

	func countRunWithoutAKey() {
		lock.withLock { runWithoutAKey += 1 }
	}

	private let lock = NSLock()
	nonisolated(unsafe) private var run = 0
	nonisolated(unsafe) private var read = 0
	nonisolated(unsafe) private var runWithoutAKey = 0
	nonisolated(unsafe) private var notKept = 0
}
