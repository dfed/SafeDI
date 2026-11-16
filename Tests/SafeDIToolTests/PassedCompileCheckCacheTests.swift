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
			keys.insert(try PassedCompileCheckCache.key(of: [module], fixtureRoots: Array(roots.map(\.path).rotated(by: index)), build: "Swift 6.2"))
		}

		#expect(keys.count == 1)
	}

	@Test
	func key_differs_whenAGeneratedFileDiffersByOneCharacter() throws {
		let root = try makeRoot(named: "root")
		let first = try stagedModule(in: root, generatedCode: "extension Fixture { func generated() { _ = 1 } }\n")
		let second = try stagedModule(in: root, generatedCode: "extension Fixture { func generated() { _ = 2 } }\n")

		#expect(try PassedCompileCheckCache.key(of: [first], fixtureRoots: [root.path], build: "Swift 6.2") != PassedCompileCheckCache.key(of: [second], fixtureRoots: [root.path], build: "Swift 6.2"))
	}

	@Test
	func key_differs_whenTwoPathsThatWereTheSameDiffer() throws {
		// Renumbering keeps which UUIDs are the same: a check that names one fixture directory twice is not the check
		// that names two.
		let root = try makeRoot(named: "root")
		let uuid = UUID().uuidString
		let same = try stagedModule(in: root, generatedCode: "// \(uuid)\n// \(uuid)\nextension Fixture {}\n")
		let different = try stagedModule(in: root, generatedCode: "// \(uuid)\n// \(UUID().uuidString)\nextension Fixture {}\n")

		#expect(try PassedCompileCheckCache.key(of: [same], fixtureRoots: [root.path], build: "Swift 6.2") != PassedCompileCheckCache.key(of: [different], fixtureRoots: [root.path], build: "Swift 6.2"))
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

		#expect(try PassedCompileCheckCache.key(of: [module], fixtureRoots: [root.path], build: "Swift 6.2") != PassedCompileCheckCache.key(of: [staging], fixtureRoots: [root.path], build: "Swift 6.2"))
	}

	@Test
	func key_differs_whenTheCompileSetsADefaultIsolation() throws {
		let root = try makeRoot(named: "root")
		let module = try stagedModule(in: root, generatedCode: "extension Fixture {}\n")
		let mainActorByDefault = CompileCheckModule(
			sources: ModuleCompileSources(
				moduleName: module.sources.moduleName,
				packageName: nil,
				dependencyModuleNames: [],
				inputSwiftFiles: module.sources.inputSwiftFiles,
				generatedFiles: module.sources.generatedFiles,
				activeCompilationConditions: [],
				mockConditionalCompilation: nil,
				compilerSettings: VerificationCompilerSettings(defaultIsolation: "MainActor"),
			),
			staged: module.staged,
			emitsModule: false,
		)

		#expect(try PassedCompileCheckCache.key(of: [module], fixtureRoots: [root.path], build: "Swift 6.2") != PassedCompileCheckCache.key(of: [mainActorByDefault], fixtureRoots: [root.path], build: "Swift 6.2"))
	}

	@Test
	func key_differs_whenAnotherBuildCompilesTheCheck() throws {
		// A pass under one compiler, SDK or build of SafeDI says nothing about another, so the cache must not hold the
		// check for it.
		let root = try makeRoot(named: "root")
		let module = try stagedModule(in: root, generatedCode: "extension Fixture { func generated() {} }\n")

		#expect(try PassedCompileCheckCache.key(of: [module], fixtureRoots: [root.path], build: "Swift 6.2 SDK 26.0") != PassedCompileCheckCache.key(of: [module], fixtureRoots: [root.path], build: "Swift 6.2 SDK 26.4"))
	}

	// MARK: Tests – Describing what compiles the checks

	@Test(.enabled(if: compileVerificationIsEnabled, "Runs the compiler only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func describe_namesTheCompilersVersionAndTarget() async throws {
		let description = try await CompileCheckBuild.describe(artifacts: #require(SafeDIBuildArtifactLocator.locate()))

		#expect(description.contains("Swift version"))
		#expect(description.contains("\"triple\""))
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Runs the compiler only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func describe_throws_whenTheEnvironmentNamesNoCompiler() async throws {
		// A key made from a compiler's error text would stand for no compiler, so no description is better than one.
		let artifacts = try #require(SafeDIBuildArtifactLocator.locate())

		await #expect(throws: PassedCompileCheckCacheError.self) {
			try await CompileCheckBuild.describe(artifacts: artifacts, environment: ["PATH": "/safedi-no-compiler", "DEVELOPER_DIR": "/safedi-no-compiler"])
		}
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Runs the compiler only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func describe_differs_whenTheBuildResolvedADependencyAtAnotherRevision() async throws {
		// A build that resolves swift-syntax at another revision than `Package.resolved` names makes another macro
		// plugin from the same sources, and a check that passed with one has not passed with the other.
		let build = try buildDirectory(named: "build", resolvingSwiftSyntaxAt: "0000000000000000000000000000000000000001")
		let otherBuild = try buildDirectory(named: "other-build", resolvingSwiftSyntaxAt: "0000000000000000000000000000000000000002")

		let description = try await CompileCheckBuild.describe(artifacts: build)
		let descriptionOfOtherBuild = try await CompileCheckBuild.describe(artifacts: otherBuild)

		#expect(description.contains(#"swift-syntax {"checkoutState":{"revision":"0000000000000000000000000000000000000001","version":"1.0.0"},"name":"sourceControlCheckout"}"#))
		#expect(description != descriptionOfOtherBuild)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Runs the compiler only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func describe_throws_whenNoDirectoryAboveTheMacroPluginRecordsWhatTheBuildResolved() async throws {
		let artifacts = try #require(SafeDIBuildArtifactLocator.locate())
		let plugin = directory.appendingPathComponent("SafeDIMacros-tool")
		try Data().write(to: plugin)

		await #expect(throws: PassedCompileCheckCacheError.self) {
			try await CompileCheckBuild.describe(artifacts: SafeDIBuildArtifacts(swiftModuleSearchPath: artifacts.swiftModuleSearchPath, safeDIMacrosToolPath: plugin))
		}
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Runs the compiler only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func describe_differs_whenTheSafeDIModuleDiffersByOneByte() async throws {
		let artifacts = try #require(SafeDIBuildArtifactLocator.locate())
		let otherModule = directory.appendingPathComponent("SafeDI.swiftmodule")
		try Data([0]).write(to: otherModule)

		let description = try await CompileCheckBuild.describe(artifacts: artifacts)
		let descriptionWithOtherModule = try await CompileCheckBuild.describe(artifacts: SafeDIBuildArtifacts(swiftModuleSearchPath: directory, safeDIMacrosToolPath: artifacts.safeDIMacrosToolPath))

		#expect(description != descriptionWithOtherModule)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Runs the compiler only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func describe_throws_whenThereIsNoSafeDIModule() async throws {
		let artifacts = try #require(SafeDIBuildArtifactLocator.locate())

		await #expect(throws: PassedCompileCheckCacheError.self) {
			try await CompileCheckBuild.describe(artifacts: SafeDIBuildArtifacts(swiftModuleSearchPath: directory, safeDIMacrosToolPath: artifacts.safeDIMacrosToolPath))
		}
	}

	// MARK: Tests – Skipping and recording checks

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func verifyModulesCompile_compilesNothing_whenTheCacheHoldsTheCheckFromAnEarlierPass() async throws {
		var filesToDelete = [URL]()
		defer { deleteAll(filesToDelete) }
		let cacheFile = directory.appendingPathComponent("passed.txt")
		let module = try compilingModule(generatedCode: "extension Fixture { func generated() -> Int { 1 } }\n")

		let firstRun = try await verifyModulesCompile([module], recordsIssues: true, passedCheckCache: PassedCompileCheckCache(file: cacheFile, run: nil), filesToDelete: &filesToDelete)
		let secondRun = try await verifyModulesCompile([module], recordsIssues: true, passedCheckCache: PassedCompileCheckCache(file: cacheFile, run: nil), filesToDelete: &filesToDelete)

		#expect(try #require(firstRun).modules.map(\.exitCode) == [0])
		#expect(try String(contentsOf: cacheFile, encoding: .utf8).split(separator: "\n").count == 1)
		#expect(secondRun == nil)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func verifyModulesCompile_compilesTheCheck_whenTheCacheHoldsItWithOtherGeneratedCode() async throws {
		// CI keeps the cache across changes to the generators (`.github/scripts/compile-check-identity.sh` hashes none
		// of them), so a check whose generated code a generator changed must compile, and fail when that code does not.
		var filesToDelete = [URL]()
		defer { deleteAll(filesToDelete) }
		let cacheFile = directory.appendingPathComponent("passed.txt")
		let module = try compilingModule(generatedCode: "extension Fixture { func generated() -> Int { 1 } }\n")
		let moduleAfterGeneratorChange = ModuleCompileSources(
			moduleName: module.moduleName,
			packageName: module.packageName,
			dependencyModuleNames: module.dependencyModuleNames,
			inputSwiftFiles: module.inputSwiftFiles,
			generatedFiles: ["Fixture+SafeDI.swift": "extension Fixture { func generated() -> Int { undeclared } }\n"],
			activeCompilationConditions: [],
			mockConditionalCompilation: nil,
		)
		_ = try await verifyModulesCompile([module], recordsIssues: true, passedCheckCache: PassedCompileCheckCache(file: cacheFile, run: nil), filesToDelete: &filesToDelete)

		// `withKnownIssue` fails when the call records no issue, as it would if the cache skipped the check.
		await withKnownIssue("Generated code that does not compile records an issue") {
			_ = try await verifyModulesCompile([moduleAfterGeneratorChange], recordsIssues: true, passedCheckCache: PassedCompileCheckCache(file: cacheFile, run: nil), filesToDelete: &filesToDelete)
		}

		#expect(try String(contentsOf: cacheFile, encoding: .utf8).split(separator: "\n").count == 1)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func verifyModulesCompile_recordsNothingInTheCache_whenGeneratedCodeFailsToCompile() async throws {
		var filesToDelete = [URL]()
		defer { deleteAll(filesToDelete) }
		let cacheFile = directory.appendingPathComponent("passed.txt")
		let module = try compilingModule(generatedCode: "extension Fixture { func generated() -> Int { undeclared } }\n")

		await withKnownIssue("Generated code that does not compile records an issue") {
			_ = try await verifyModulesCompile([module], recordsIssues: true, passedCheckCache: PassedCompileCheckCache(file: cacheFile, run: nil), filesToDelete: &filesToDelete)
		}

		#expect(!FileManager.default.fileExists(atPath: cacheFile.path))
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func verifyModulesCompile_recordsNothingInTheCache_whenGeneratedCodeDrawsAWarning() async throws {
		var filesToDelete = [URL]()
		defer { deleteAll(filesToDelete) }
		let cacheFile = directory.appendingPathComponent("passed.txt")
		let module = try compilingModule(generatedCode: "extension Fixture { func generated() { let unused = 1 } }\n")

		await withKnownIssue("A warning in generated code records an issue") {
			_ = try await verifyModulesCompile([module], recordsIssues: true, passedCheckCache: PassedCompileCheckCache(file: cacheFile, run: nil), filesToDelete: &filesToDelete)
		}

		#expect(!FileManager.default.fileExists(atPath: cacheFile.path))
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func verifyModulesCompile_compilesAndRecordsNothing_whenItReturnsTheOutcomeOfACheckTheCacheHolds() async throws {
		// A test that asserts on the outcome needs one, so a call that records no issues always compiles.
		var filesToDelete = [URL]()
		defer { deleteAll(filesToDelete) }
		let cacheFile = directory.appendingPathComponent("passed.txt")
		let module = try compilingModule(generatedCode: "extension Fixture { func generated() -> Int { 1 } }\n")
		_ = try await verifyModulesCompile([module], recordsIssues: true, passedCheckCache: PassedCompileCheckCache(file: cacheFile, run: nil), filesToDelete: &filesToDelete)

		let outcome = try await verifyModulesCompile([module], recordsIssues: false, passedCheckCache: PassedCompileCheckCache(file: cacheFile, run: nil), filesToDelete: &filesToDelete)

		#expect(try #require(outcome).modules.map(\.exitCode) == [0])
		#expect(try String(contentsOf: cacheFile, encoding: .utf8).split(separator: "\n").count == 1)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func verifyModulesCompile_recordsTheKeyOfTheCheckWithWhatCompilesIt() async throws {
		// The key the verifier looks up and records must name this process's compiler and build of SafeDI: with any
		// other text in their place, a pass would be read under a compiler that never compiled the check.
		var filesToDelete = [URL]()
		defer { deleteAll(filesToDelete) }
		let cacheFile = directory.appendingPathComponent("passed.txt")
		let module = try compilingModule(generatedCode: "extension Fixture { func generated() -> Int { 1 } }\n")
		let build = try #require(await CompileCheckBuild.description)

		_ = try await verifyModulesCompile([module], recordsIssues: true, passedCheckCache: PassedCompileCheckCache(file: cacheFile, run: nil), filesToDelete: &filesToDelete)

		let check = try CompileCheckModule(sources: module, staged: stageCompileSources(of: module, filesToDelete: &filesToDelete), emitsModule: true)
		#expect(try String(contentsOf: cacheFile, encoding: .utf8) == PassedCompileCheckCache.key(of: [check], build: build) + "\n")
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func verifyGeneratedCodeCompiles_recordsTheKeyOfTheCheckWithWhatCompilesIt() async throws {
		var filesToDelete = [URL]()
		defer { deleteAll(filesToDelete) }
		let cacheFile = directory.appendingPathComponent("passed.txt")
		let module = try compilingModule(generatedCode: "extension Fixture { func generated() -> Int { 1 } }\n")
		let build = try #require(await CompileCheckBuild.description)

		try await verifyGeneratedCodeCompiles(
			inputSwiftFiles: module.inputSwiftFiles,
			additionalDirectorySwiftFiles: [],
			generatedFiles: module.generatedFiles,
			mockConditionalCompilation: nil,
			passedCheckCache: PassedCompileCheckCache(file: cacheFile, run: nil),
			filesToDelete: &filesToDelete,
		)

		let standaloneModule = ModuleCompileSources(
			moduleName: standaloneVerificationModuleName,
			packageName: nil,
			dependencyModuleNames: [],
			inputSwiftFiles: module.inputSwiftFiles,
			generatedFiles: module.generatedFiles,
			activeCompilationConditions: [],
			mockConditionalCompilation: nil,
		)
		let check = try CompileCheckModule(sources: standaloneModule, staged: stageCompileSources(of: standaloneModule, filesToDelete: &filesToDelete), emitsModule: false)
		#expect(try String(contentsOf: cacheFile, encoding: .utf8) == PassedCompileCheckCache.key(of: [check], build: build) + "\n")
	}

	// MARK: Tests – Listing the passes of this run

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func verifyModulesCompile_listsOnlyTheCheckItCompiledAsPassedInThisRun_whenTheCacheWasRestoredWithOtherChecks() async throws {
		// CI shares the run's own list with every branch, so a line a job restored must never reach it: nothing in
		// this run saw that check compile.
		var filesToDelete = [URL]()
		defer { deleteAll(filesToDelete) }
		let cacheFile = directory.appendingPathComponent("passed.txt")
		let restoredKey = String(repeating: "a", count: 64)
		try (restoredKey + "\n").write(to: cacheFile, atomically: true, encoding: .utf8)
		let cache = PassedCompileCheckCache(file: cacheFile, run: "4242")
		let module = try compilingModule(generatedCode: "extension Fixture { func generated() -> Int { 1 } }\n")

		_ = try await verifyModulesCompile([module], recordsIssues: true, passedCheckCache: cache, filesToDelete: &filesToDelete)

		let passedInThisRun = try String(contentsOf: directory.appendingPathComponent("passed-in-run-4242.txt"), encoding: .utf8).split(separator: "\n").map(String.init)
		let passed = try String(contentsOf: cacheFile, encoding: .utf8).split(separator: "\n").map(String.init)
		#expect(passedInThisRun.count == 1)
		#expect(passed == [restoredKey] + passedInThisRun)
	}

	@Test
	func recordPass_writesNoListOfThisRun_whenTheProcessIsPartOfNoRun() throws {
		let cacheFile = directory.appendingPathComponent("passed.txt")

		try PassedCompileCheckCache(file: cacheFile, run: nil).recordPass(of: "key")

		#expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["passed.txt"])
	}

	@Test
	func recordPass_writesNoListOfThisRun_whenTheRunsNameCouldLeaveTheDirectory() throws {
		let cacheFile = directory.appendingPathComponent("passed.txt")

		try PassedCompileCheckCache(file: cacheFile, run: "../elsewhere").recordPass(of: "key")

		#expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["passed.txt"])
	}

	// MARK: Private

	private let directory: URL

	/// A build directory laid out as SwiftPM lays one out, whose products are this process's SafeDI module and an
	/// empty macro plugin, and whose `workspace-state.json` says the build resolved swift-syntax at `revision`.
	private func buildDirectory(named name: String, resolvingSwiftSyntaxAt revision: String) throws -> SafeDIBuildArtifacts {
		let artifacts = try #require(SafeDIBuildArtifactLocator.locate())
		let products = directory.appendingPathComponent(name).appendingPathComponent("triple").appendingPathComponent("release")
		try FileManager.default.createDirectory(at: products.appendingPathComponent("Modules"), withIntermediateDirectories: true)
		try FileManager.default.copyItem(
			at: artifacts.swiftModuleSearchPath.appendingPathComponent("SafeDI.swiftmodule"),
			to: products.appendingPathComponent("Modules").appendingPathComponent("SafeDI.swiftmodule"),
		)
		let plugin = products.appendingPathComponent("SafeDIMacros-tool")
		try Data().write(to: plugin)
		try """
		{"object":{"artifacts":[],"dependencies":[{"basedOn":null,"packageRef":{"identity":"swift-syntax","kind":"remoteSourceControl","location":"https://github.com/swiftlang/swift-syntax.git","name":"swift-syntax"},"state":{"checkoutState":{"revision":"\(revision)","version":"1.0.0"},"name":"sourceControlCheckout"},"subpath":"swift-syntax"}]},"version":7}
		""".write(to: directory.appendingPathComponent(name).appendingPathComponent("workspace-state.json"), atomically: true, encoding: .utf8)
		return SafeDIBuildArtifacts(swiftModuleSearchPath: products.appendingPathComponent("Modules"), safeDIMacrosToolPath: plugin)
	}

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
