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

/// How the compile verifier keys a compile check, and how it skips and records checks in a cache of passed checks.
struct PassedCompileCheckCacheTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		directory = TestTemporaryDirectory.uniquePath(prefix: "safedi-passed-compile-check-cache-tests-")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
	}

	deinit {
		try? FileManager.default.removeItem(at: directory)
	}

	// MARK: Tests – SHA-256

	@Test(arguments: [
		("", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
		("abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
		// 56 bytes, so the padding takes a second block.
		("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq", "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"),
	])
	func sha256HexDigest_returnsTheStandardsDigest_forTestVector(message: String, digest: String) {
		#expect(sha256HexDigest(of: Data(message.utf8)) == digest)
	}

	// MARK: Tests – Keys

	@Test
	func key_isTheSame_whenTheCheckIsStagedUnderAnotherFixtureRootWithOtherUUIDs() throws {
		// Each run stages a check under its own process directory, with fixture directories named by fresh UUIDs, and
		// generated code spells those paths. Six runs' roots, in each order, give one key.
		let roots = try (0..<6).map { index in
			try makeRoot(named: "test-run-\(1_000 + index)-\(UUID().uuidString)")
		}
		var keys = Set<String>()
		for (index, root) in roots.enumerated() {
			let fixtureDirectory = root.appendingPathComponent(UUID().uuidString)
			let module = try stagedModule(in: root, generatedCode: """
			extension Fixture {
			    // Declared at \(fixtureDirectory.path)/Fixture.swift
			    func generated() {
			        #sourceLocation(file: "\(fixtureDirectory.path)/Fixture.swift", line: 1)
			        let value = 1
			        #sourceLocation()
			        _ = value
			    }
			}
			""")
			keys.insert(try PassedCompileCheckCache.key(of: [module], fixtureRoots: Array(roots.map(\.path).rotated(by: index))))
		}

		#expect(keys.count == 1)
	}

	@Test
	func key_differs_whenAGeneratedFileDiffersByOneCharacter() throws {
		let root = try makeRoot(named: "root")
		let first = try stagedModule(in: root, generatedCode: "extension Fixture { func generated() { _ = 1 } }\n")
		let second = try stagedModule(in: root, generatedCode: "extension Fixture { func generated() { _ = 2 } }\n")

		#expect(try PassedCompileCheckCache.key(of: [first], fixtureRoots: [root.path]) != PassedCompileCheckCache.key(of: [second], fixtureRoots: [root.path]))
	}

	@Test
	func key_differs_whenTwoPathsThatWereTheSameDiffer() throws {
		// Renumbering keeps which UUIDs are the same: a check that names one fixture directory twice is not the check
		// that names two.
		let root = try makeRoot(named: "root")
		let uuid = UUID().uuidString
		let same = try stagedModule(in: root, generatedCode: "// \(uuid)\n// \(uuid)\nextension Fixture {}\n")
		let different = try stagedModule(in: root, generatedCode: "// \(uuid)\n// \(UUID().uuidString)\nextension Fixture {}\n")

		#expect(try PassedCompileCheckCache.key(of: [same], fixtureRoots: [root.path]) != PassedCompileCheckCache.key(of: [different], fixtureRoots: [root.path]))
	}

	@Test
	func key_differs_whenTheCompileDefinesAnotherCondition() throws {
		let root = try makeRoot(named: "root")
		let module = try stagedModule(in: root, generatedCode: "extension Fixture {}\n")
		let staging = CompileCheckModule(
			sources: ModuleCompileSources(
				moduleName: module.sources.moduleName,
				packageName: nil,
				dependencyModuleNames: [],
				inputSwiftFiles: module.sources.inputSwiftFiles,
				generatedFiles: module.sources.generatedFiles,
				activeCompilationConditions: ["STAGING"],
				mockConditionalCompilation: nil,
			),
			staged: module.staged,
			emitsModule: false,
		)

		#expect(try PassedCompileCheckCache.key(of: [module], fixtureRoots: [root.path]) != PassedCompileCheckCache.key(of: [staging], fixtureRoots: [root.path]))
	}

	// MARK: Tests – Skipping and recording checks

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func verifyModulesCompile_compilesNothing_whenTheCacheHoldsTheCheckFromAnEarlierPass() throws {
		var filesToDelete = [URL]()
		defer { deleteAll(filesToDelete) }
		let cacheFile = directory.appendingPathComponent("passed.txt")
		let module = try compilingModule(generatedCode: "extension Fixture { func generated() -> Int { 1 } }\n")

		let firstRun = try verifyModulesCompile([module], recordsIssues: true, passedCheckCache: PassedCompileCheckCache(file: cacheFile), filesToDelete: &filesToDelete)
		let secondRun = try verifyModulesCompile([module], recordsIssues: true, passedCheckCache: PassedCompileCheckCache(file: cacheFile), filesToDelete: &filesToDelete)

		#expect(try #require(firstRun).modules.map(\.exitCode) == [0])
		#expect(try String(contentsOf: cacheFile, encoding: .utf8).split(separator: "\n").count == 1)
		#expect(secondRun == nil)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func verifyModulesCompile_recordsNothingInTheCache_whenGeneratedCodeFailsToCompile() throws {
		var filesToDelete = [URL]()
		defer { deleteAll(filesToDelete) }
		let cacheFile = directory.appendingPathComponent("passed.txt")
		let module = try compilingModule(generatedCode: "extension Fixture { func generated() -> Int { undeclared } }\n")

		withKnownIssue("Generated code that does not compile records an issue") {
			_ = try verifyModulesCompile([module], recordsIssues: true, passedCheckCache: PassedCompileCheckCache(file: cacheFile), filesToDelete: &filesToDelete)
		}

		#expect(!FileManager.default.fileExists(atPath: cacheFile.path))
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func verifyModulesCompile_recordsNothingInTheCache_whenGeneratedCodeDrawsAWarning() throws {
		var filesToDelete = [URL]()
		defer { deleteAll(filesToDelete) }
		let cacheFile = directory.appendingPathComponent("passed.txt")
		let module = try compilingModule(generatedCode: "extension Fixture { func generated() { let unused = 1 } }\n")

		withKnownIssue("A warning in generated code records an issue") {
			_ = try verifyModulesCompile([module], recordsIssues: true, passedCheckCache: PassedCompileCheckCache(file: cacheFile), filesToDelete: &filesToDelete)
		}

		#expect(!FileManager.default.fileExists(atPath: cacheFile.path))
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func verifyModulesCompile_compilesAndRecordsNothing_whenItReturnsTheOutcomeOfACheckTheCacheHolds() throws {
		// A test that asserts on the outcome needs one, so a call that records no issues always compiles.
		var filesToDelete = [URL]()
		defer { deleteAll(filesToDelete) }
		let cacheFile = directory.appendingPathComponent("passed.txt")
		let module = try compilingModule(generatedCode: "extension Fixture { func generated() -> Int { 1 } }\n")
		_ = try verifyModulesCompile([module], recordsIssues: true, passedCheckCache: PassedCompileCheckCache(file: cacheFile), filesToDelete: &filesToDelete)

		let outcome = try verifyModulesCompile([module], recordsIssues: false, passedCheckCache: PassedCompileCheckCache(file: cacheFile), filesToDelete: &filesToDelete)

		#expect(try #require(outcome).modules.map(\.exitCode) == [0])
		#expect(try String(contentsOf: cacheFile, encoding: .utf8).split(separator: "\n").count == 1)
	}

	// MARK: Private

	private let directory: URL

	/// Makes a directory named `name` to stand for a test process's directory.
	private func makeRoot(named name: String) throws -> URL {
		let root = directory.appendingPathComponent(name)
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		return root
	}

	/// A module whose fixture declares `Fixture` and whose one generated file holds `generatedCode`, staged in a
	/// directory under `root` named by a fresh UUID, as `stageCompileSources` stages a check.
	private func stagedModule(in root: URL, generatedCode: String) throws -> CompileCheckModule {
		let fixture = root.appendingPathComponent("Fixture.swift")
		try "public struct Fixture {}\n".write(to: fixture, atomically: true, encoding: .utf8)
		let stagingDirectory = root.appendingPathComponent("safedi-verify-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
		let stagedInput = stagingDirectory.appendingPathComponent("input_0_Fixture.swift")
		try "import SafeDI\npublic struct Fixture {}\n".write(to: stagedInput, atomically: true, encoding: .utf8)
		let stagedGenerated = stagingDirectory.appendingPathComponent("Fixture+SafeDI.swift")
		try ("import SafeDI\n" + generatedCode).write(to: stagedGenerated, atomically: true, encoding: .utf8)
		return CompileCheckModule(
			sources: ModuleCompileSources(
				moduleName: "Probe",
				packageName: nil,
				dependencyModuleNames: [],
				inputSwiftFiles: [fixture],
				generatedFiles: ["Fixture+SafeDI.swift": generatedCode],
				activeCompilationConditions: [],
				mockConditionalCompilation: nil,
			),
			staged: StagedCompileSources(directory: stagingDirectory, inputFiles: [stagedInput], generatedFiles: [stagedGenerated]),
			emitsModule: false,
		)
	}

	/// A module of one fixture file declaring `Fixture`, written under a fresh directory, and one generated file.
	private func compilingModule(generatedCode: String) throws -> ModuleCompileSources {
		let fixtureDirectory = directory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
		let fixture = fixtureDirectory.appendingPathComponent("Fixture.swift")
		try "public struct Fixture {}\n".write(to: fixture, atomically: true, encoding: .utf8)
		return ModuleCompileSources(
			moduleName: "Probe",
			packageName: nil,
			dependencyModuleNames: [],
			inputSwiftFiles: [fixture],
			generatedFiles: ["Fixture+SafeDI.swift": generatedCode],
			activeCompilationConditions: [],
			mockConditionalCompilation: nil,
		)
	}

	private func deleteAll(_ files: [URL]) {
		for file in files {
			try? FileManager.default.removeItem(at: file)
		}
	}
}

extension Array {
	/// The array with its first `count` elements moved to its end.
	fileprivate func rotated(by count: Int) -> [Element] {
		Array(self[(count % Swift.max(1, self.count))...] + self[..<(count % Swift.max(1, self.count))])
	}
}
