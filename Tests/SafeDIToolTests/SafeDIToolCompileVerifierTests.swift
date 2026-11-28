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

/// Which warnings the compile verifier, and the graph fuzzer through it, counts as drawn by generated code.
struct SafeDIToolCompileVerifierTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		directory = TestTemporaryDirectory.root.appendingPathComponent("safedi-compile-verifier-tests-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
	}

	deinit {
		try! FileManager.default.removeItem(at: directory)
	}

	// MARK: Tests – Generated files

	@Test
	func warningsOnlyGeneratedCodeDraws_reportsWarning_whenGeneratedFileDrawsIt() throws {
		let generatedFile = try generatedFile(containing: Self.generatedCode)
		let warning = "\(generatedFile.path):5:13: warning: initialization of immutable value 'third' was never used"

		#expect(warningsOnlyGeneratedCodeDraws(
			inCompilerOutput: warning + "\n",
			generatedFiles: [generatedFile],
			inputFiles: [inputFile],
		) == [warning])
	}

	@Test
	func warningsOnlyGeneratedCodeDraws_omitsWarning_whenInputFileDrawsTheSameMessage() throws {
		let generatedFile = try generatedFile(containing: Self.generatedCode)

		#expect(warningsOnlyGeneratedCodeDraws(
			inCompilerOutput: """
			\(inputFile.path):3:9: warning: will never be executed
			\(generatedFile.path):5:13: warning: will never be executed

			""",
			generatedFiles: [generatedFile],
			inputFiles: [inputFile],
		) == [])
	}

	@Test
	func warningsOnlyGeneratedCodeDraws_reportsWarning_whenOnlyAnotherGraphsInputFileDrawsTheSameMessage() throws {
		// The fuzzer compiles several graphs together and asks about each graph's files in turn, so another graph's
		// fixture excuses nothing.
		let generatedFile = try generatedFile(containing: Self.generatedCode)
		let otherInputFile = directory.appendingPathComponent("input_0_Other.swift")
		let warning = "\(generatedFile.path):5:13: warning: will never be executed"

		#expect(warningsOnlyGeneratedCodeDraws(
			inCompilerOutput: """
			\(otherInputFile.path):3:9: warning: will never be executed
			\(warning)

			""",
			generatedFiles: [generatedFile],
			inputFiles: [inputFile],
		) == [warning])
	}

	@Test
	func warningsOnlyGeneratedCodeDraws_omitsWarning_whenOnlyInputFileDrawsIt() throws {
		let generatedFile = try generatedFile(containing: Self.generatedCode)

		#expect(warningsOnlyGeneratedCodeDraws(
			inCompilerOutput: "\(inputFile.path):3:13: warning: initialization of immutable value 'fixtureOwn' was never used\n",
			generatedFiles: [generatedFile],
			inputFiles: [inputFile],
		) == [])
	}

	// MARK: Tests – Compiling modules

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func verifyModulesCompile_reportsGeneratedCodeWarning_whenGeneratedCodeSpellsProtocolThatFixtureSpellsWithAny() async throws {
		let fixture = directory.appendingPathComponent("Fixture.swift")
		try "public protocol Service {}\n\npublic func use(_ service: any Service) {}\n".write(to: fixture, atomically: true, encoding: .utf8)
		var filesToDelete = [URL]()
		defer {
			for fileToDelete in filesToDelete {
				try? FileManager.default.removeItem(at: fileToDelete)
			}
		}

		let compilation = try #require(try await verifyModulesCompile(
			[ModuleCompileSources(
				moduleName: "Probe",
				packageName: nil,
				dependencyModuleNames: [],
				inputSwiftFiles: [fixture],
				generatedFiles: ["Fixture+SafeDI.swift": "func generated(_ service: Service) {}\n"],
				activeCompilationConditions: [],
				mockConditionalCompilation: nil,
			)],
			recordsIssues: false,
			filesToDelete: &filesToDelete,
		))

		// The compiler may report the warning more than once, as Swift 6.4 does.
		let warnings = try #require(compilation.modules.first).generatedCodeWarnings
		#expect(!warnings.isEmpty, "Unexpected warnings \(warnings)")
		#expect(warnings.allSatisfy { $0.contains("Fixture+SafeDI.swift:") && $0.contains(": warning: use of protocol 'Service' as a type must be written 'any Service'") }, "Unexpected warnings \(warnings)")
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func verifyModulesCompile_omitsGeneratedCodeWarning_whenFixtureOfModuleItImportsDrawsTheSameMessage() async throws {
		// `Feature`'s fixture spells `Service` without `any`, and `App`'s generated code spells it as `Feature` does.
		let featureFixture = directory.appendingPathComponent("Feature.swift")
		try "public protocol Service {}\n\npublic func use(_ service: Service) {}\n".write(to: featureFixture, atomically: true, encoding: .utf8)
		let appFixture = directory.appendingPathComponent("App.swift")
		try "import Feature\n".write(to: appFixture, atomically: true, encoding: .utf8)
		var filesToDelete = [URL]()
		defer {
			for fileToDelete in filesToDelete {
				try? FileManager.default.removeItem(at: fileToDelete)
			}
		}

		let compilation = try #require(try await verifyModulesCompile(
			[
				ModuleCompileSources(
					moduleName: "Feature",
					packageName: nil,
					dependencyModuleNames: [],
					inputSwiftFiles: [featureFixture],
					generatedFiles: [:],
					activeCompilationConditions: [],
					mockConditionalCompilation: nil,
				),
				ModuleCompileSources(
					moduleName: "App",
					packageName: nil,
					dependencyModuleNames: ["Feature"],
					inputSwiftFiles: [appFixture],
					generatedFiles: ["App+SafeDI.swift": "import Feature\n\nfunc generated(_ service: Service) {}\n"],
					activeCompilationConditions: [],
					mockConditionalCompilation: nil,
				),
			],
			recordsIssues: false,
			filesToDelete: &filesToDelete,
		))

		#expect(compilation.modules.map(\.moduleName) == ["Feature", "App"])
		#expect(compilation.modules.map(\.generatedCodeWarnings) == [[], []])
		#expect(compilation.modules.allSatisfy { $0.failure == nil })
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func verifyModulesCompile_reportsGeneratedCodeWarning_whenOnlyFixtureOfModuleImportingItDrawsTheSameMessage() async throws {
		// `Feature`'s generated code spells `Service` without `any`, and only `App`, which imports `Feature`, spells it so in
		// its fixture. `Feature`'s generated code cannot have copied a spelling of a module it cannot see.
		let featureFixture = directory.appendingPathComponent("Feature.swift")
		try "public protocol Service {}\n\npublic func use(_ service: any Service) {}\n".write(to: featureFixture, atomically: true, encoding: .utf8)
		let appFixture = directory.appendingPathComponent("App.swift")
		try "import Feature\n\npublic func useAgain(_ service: Service) {}\n".write(to: appFixture, atomically: true, encoding: .utf8)
		var filesToDelete = [URL]()
		defer {
			for fileToDelete in filesToDelete {
				try? FileManager.default.removeItem(at: fileToDelete)
			}
		}

		let compilation = try #require(try await verifyModulesCompile(
			[
				ModuleCompileSources(
					moduleName: "Feature",
					packageName: nil,
					dependencyModuleNames: [],
					inputSwiftFiles: [featureFixture],
					generatedFiles: ["Feature+SafeDI.swift": "func generated(_ service: Service) {}\n"],
					activeCompilationConditions: [],
					mockConditionalCompilation: nil,
				),
				ModuleCompileSources(
					moduleName: "App",
					packageName: nil,
					dependencyModuleNames: ["Feature"],
					inputSwiftFiles: [appFixture],
					generatedFiles: [:],
					activeCompilationConditions: [],
					mockConditionalCompilation: nil,
				),
			],
			recordsIssues: false,
			filesToDelete: &filesToDelete,
		))

		#expect(compilation.modules.map(\.moduleName) == ["Feature", "App"])
		let featureWarnings: [String] = try #require(compilation.modules.first).generatedCodeWarnings
		// The compiler may report the warning more than once, as Swift 6.4 does.
		#expect(!featureWarnings.isEmpty, "Unexpected warnings \(featureWarnings)")
		#expect(featureWarnings.allSatisfy { $0.contains("Feature+SafeDI.swift:") && $0.contains(": warning: use of protocol 'Service' as a type must be written 'any Service'") }, "Unexpected warnings \(featureWarnings)")
		let appWarnings: [String] = try #require(compilation.modules.last).generatedCodeWarnings
		#expect(appWarnings == [])
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func verifyModulesCompile_reportsGeneratedCodeWarning_whenFixtureOfModuleItImportsDrawsTheSameMessageOutsideExistentialAny() async throws {
		// `Feature`'s fixture calls a deprecated function, and `App`'s generated code calls it too: generated code copies no
		// spelling there, so the warning is generated code's own.
		let featureFixture = directory.appendingPathComponent("Feature.swift")
		try "@available(*, deprecated)\npublic func old() {}\n\npublic func callOld() {\n    old()\n}\n".write(to: featureFixture, atomically: true, encoding: .utf8)
		let appFixture = directory.appendingPathComponent("App.swift")
		try "import Feature\n".write(to: appFixture, atomically: true, encoding: .utf8)
		var filesToDelete = [URL]()
		defer {
			for fileToDelete in filesToDelete {
				try? FileManager.default.removeItem(at: fileToDelete)
			}
		}

		let compilation = try #require(try await verifyModulesCompile(
			[
				ModuleCompileSources(
					moduleName: "Feature",
					packageName: nil,
					dependencyModuleNames: [],
					inputSwiftFiles: [featureFixture],
					generatedFiles: [:],
					activeCompilationConditions: [],
					mockConditionalCompilation: nil,
				),
				ModuleCompileSources(
					moduleName: "App",
					packageName: nil,
					dependencyModuleNames: ["Feature"],
					inputSwiftFiles: [appFixture],
					generatedFiles: ["App+SafeDI.swift": "import Feature\n\nfunc generated() {\n    old()\n}\n"],
					activeCompilationConditions: [],
					mockConditionalCompilation: nil,
				),
			],
			recordsIssues: false,
			filesToDelete: &filesToDelete,
		))

		#expect(compilation.modules.map(\.moduleName) == ["Feature", "App"])
		let featureWarnings: [String] = try #require(compilation.modules.first).generatedCodeWarnings
		#expect(featureWarnings == [])
		let appWarnings: [String] = try #require(compilation.modules.last).generatedCodeWarnings
		// The compiler may report the warning more than once, as Swift 6.4 does.
		#expect(!appWarnings.isEmpty, "Unexpected warnings \(appWarnings)")
		#expect(appWarnings.allSatisfy { $0.contains("App+SafeDI.swift:") && $0.contains(": warning: 'old()' is deprecated") }, "Unexpected warnings \(appWarnings)")
	}

	// MARK: Tests – Running a process

	@Test
	func runProcess_returnsEverythingEachProcessWritesToStandardError_whenManyRunAtOnce() async throws {
		// A compile that passes is read for warnings in what it wrote to standard error, so losing that output now and
		// then would let a graph's warning go unreported. Read through a pipe's `readabilityHandler`, two to six of a
		// thousand runs here lost their output, so a thousand runs catch such a loss on nearly every run.
		let runCount = 1_000
		let line = "Fixture.swift:1:1: warning: initialization of immutable value 'unused' was never used"
		let results = try await withThrowingTaskGroup(of: SwiftCompileResult.self) { group in
			for _ in 0..<runCount {
				group.addTask {
					try await runProcess(URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "echo \"\(line)\" >&2; echo done"])
				}
			}
			return try await group.reduce(into: [SwiftCompileResult]()) { $0.append($1) }
		}

		#expect(results.count == runCount)
		#expect(results.filter { $0.stderr != line + "\n" || $0.stdout != "done\n" || $0.exitCode != 0 }.isEmpty)
	}

	@Test
	func runProcess_returnsExitStatusAndOutput_whenProcessExitsWithNonzeroStatus() async throws {
		let result = try await runProcess(URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "echo out; echo error >&2; exit 3"])

		#expect(result.exitCode == 3)
		#expect(result.stdout == "out\n")
		#expect(result.stderr == "error\n")
	}

	@Test
	func runProcess_returnsSignalNumber_whenSignalEndsProcess() async throws {
		// As `Process.terminationStatus` reports a process a signal ended: the compiler crashing is such a process.
		let result = try await runProcess(URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "kill -9 $$"])

		#expect(result.exitCode == 9)
	}

	@Test
	func runProcess_givesProcessEmptyStandardInput() async throws {
		let result = try await runProcess(URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "cat; echo end"])

		#expect(result.exitCode == 0)
		#expect(result.stdout == "end\n")
	}

	@Test
	func runProcess_throws_whenExecutableDoesNotExist() async throws {
		let missingExecutable = directory.appendingPathComponent("missing-executable")
		await #expect(throws: ProcessSpawnError.self) {
			try await runProcess(missingExecutable, arguments: [])
		}
	}

	// MARK: Private

	private let directory: URL

	private var inputFile: URL {
		directory.appendingPathComponent("input_0_Fixture.swift")
	}

	private func generatedFile(named fileName: String = "Fixture+SafeDI.swift", containing code: String) throws -> URL {
		let file = directory.appendingPathComponent(fileName)
		try code.write(to: file, atomically: true, encoding: .utf8)
		return file
	}

	/// Generated code whose line 5 declares `third`.
	private static let generatedCode = """
	extension Fixture {
	    func generated() {
	        let first = 1
	        let second = 2
	        let third = 3
	    }
	}
	"""
}
