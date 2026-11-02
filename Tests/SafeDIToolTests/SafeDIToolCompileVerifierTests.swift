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

/// Which warnings the compile verifier, and the graph fuzzer through it, counts as drawn by generated code.
struct SafeDIToolCompileVerifierTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		directory = FileManager.default.temporaryDirectory.appendingPathComponent("safedi-compile-verifier-tests-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
	}

	deinit {
		try! FileManager.default.removeItem(at: directory)
	}

	// MARK: Tests – Generated files

	@Test
	func warningsOnlyGeneratedCodeDraws_reportsWarning_whenGeneratedFileDrawsIt() throws {
		let generatedFile = try generatedFile(containing: Self.redirectingGeneratedCode)
		let warning = "\(generatedFile.path):7:13: warning: initialization of immutable value 'third' was never used"

		#expect(try warningsOnlyGeneratedCodeDraws(
			inCompilerOutput: warning + "\n",
			generatedFiles: [generatedFile],
			inputFiles: [inputFile],
		) == [warning])
	}

	@Test
	func warningsOnlyGeneratedCodeDraws_omitsWarning_whenInputFileDrawsTheSameMessage() throws {
		let generatedFile = try generatedFile(containing: Self.redirectingGeneratedCode)

		#expect(try warningsOnlyGeneratedCodeDraws(
			inCompilerOutput: """
			\(inputFile.path):3:9: warning: will never be executed
			\(generatedFile.path):7:13: warning: will never be executed

			""",
			generatedFiles: [generatedFile],
			inputFiles: [inputFile],
		) == [])
	}

	@Test
	func warningsOnlyGeneratedCodeDraws_reportsWarning_whenOnlyAnotherGraphsInputFileDrawsTheSameMessage() throws {
		// The fuzzer compiles several graphs together and asks about each graph's files in turn, so another graph's
		// fixture excuses nothing.
		let generatedFile = try generatedFile(containing: Self.redirectingGeneratedCode)
		let otherInputFile = directory.appendingPathComponent("input_0_Other.swift")
		let warning = "\(generatedFile.path):7:13: warning: will never be executed"

		#expect(try warningsOnlyGeneratedCodeDraws(
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
		let generatedFile = try generatedFile(containing: Self.redirectingGeneratedCode)

		#expect(try warningsOnlyGeneratedCodeDraws(
			inCompilerOutput: "\(inputFile.path):3:13: warning: initialization of immutable value 'fixtureOwn' was never used\n",
			generatedFiles: [generatedFile],
			inputFiles: [inputFile],
		) == [])
	}

	// MARK: Tests – `#sourceLocation` redirections

	@Test
	func warningsOnlyGeneratedCodeDraws_reportsWarning_whenSourceLocationDirectiveAttributesGeneratedLineToDeclaration() throws {
		let generatedFile = try generatedFile(containing: Self.redirectingGeneratedCode)
		let warning = "\(Self.declarationFilePath):8:13: warning: initialization of immutable value 'first' was never used"

		#expect(try warningsOnlyGeneratedCodeDraws(
			inCompilerOutput: warning + "\n",
			generatedFiles: [generatedFile],
			inputFiles: [inputFile],
		) == [warning])
	}

	@Test
	func warningsOnlyGeneratedCodeDraws_reportsWarning_whenLaterLineOfSourceLocationRedirectionDrawsIt() throws {
		let generatedFile = try generatedFile(containing: Self.redirectingGeneratedCode)
		let warning = "\(Self.declarationFilePath):9:13: warning: initialization of immutable value 'second' was never used"

		#expect(try warningsOnlyGeneratedCodeDraws(
			inCompilerOutput: warning + "\n",
			generatedFiles: [generatedFile],
			inputFiles: [inputFile],
		) == [warning])
	}

	@Test
	func warningsOnlyGeneratedCodeDraws_reportsWarning_whenSourceLocationDirectiveNamesRelativePath() throws {
		// The compiler reports the directive's path as spelled, without resolving it.
		let generatedFile = try generatedFile(containing: """
		extension Fixture {
		    func generated() {
		        #sourceLocation(file: "Sources/Fixture.swift", line: 8)
		        let first = 1
		        #sourceLocation()
		    }
		}
		""")
		let warning = "Sources/Fixture.swift:8:13: warning: initialization of immutable value 'first' was never used"

		#expect(try warningsOnlyGeneratedCodeDraws(
			inCompilerOutput: warning + "\n",
			generatedFiles: [generatedFile],
			inputFiles: [inputFile],
		) == [warning])
	}

	@Test
	func warningsOnlyGeneratedCodeDraws_omitsWarning_whenInputFileDrawsTheSameMessageAsRedirectedLine() throws {
		let generatedFile = try generatedFile(containing: Self.redirectingGeneratedCode)

		#expect(try warningsOnlyGeneratedCodeDraws(
			inCompilerOutput: """
			\(inputFile.path):3:9: warning: will never be executed
			\(Self.declarationFilePath):8:13: warning: will never be executed

			""",
			generatedFiles: [generatedFile],
			inputFiles: [inputFile],
		) == [])
	}

	@Test
	func warningsOnlyGeneratedCodeDraws_omitsWarning_whenDeclarationFileDrawsItAfterSourceLocationRedirectionEnds() throws {
		// The redirection covers lines 8 and 9 of the declaration's file; line 10 is the file's own.
		let generatedFile = try generatedFile(containing: Self.redirectingGeneratedCode)

		#expect(try warningsOnlyGeneratedCodeDraws(
			inCompilerOutput: "\(Self.declarationFilePath):10:13: warning: initialization of immutable value 'fixtureOwn' was never used\n",
			generatedFiles: [generatedFile],
			inputFiles: [inputFile],
		) == [])
	}

	@Test
	func warningsOnlyGeneratedCodeDraws_omitsWarning_whenOnlyAnotherGeneratedFileRedirectsTheLine() throws {
		// The fuzzer compiles several graphs together and asks about each graph's generated files in turn.
		_ = try generatedFile(containing: Self.redirectingGeneratedCode)
		let otherGeneratedFile = try generatedFile(named: "Other+SafeDI.swift", containing: "extension Other {}\n")

		#expect(try warningsOnlyGeneratedCodeDraws(
			inCompilerOutput: "\(Self.declarationFilePath):8:13: warning: initialization of immutable value 'first' was never used\n",
			generatedFiles: [otherGeneratedFile],
			inputFiles: [inputFile],
		) == [])
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func verifyModulesCompile_reportsGeneratedCodeWarning_whenSourceLocationDirectiveAttributesItToFixture() throws {
		// The fixture is staged under another name, so the directive names a file the compile is not given, as a
		// directive SafeDITool generates names the fixture `executeSafeDIToolTest` wrote.
		let fixture = directory.appendingPathComponent("Fixture.swift")
		try "public struct Fixture {}\n".write(to: fixture, atomically: true, encoding: .utf8)
		var filesToDelete = [URL]()
		defer {
			for fileToDelete in filesToDelete {
				try? FileManager.default.removeItem(at: fileToDelete)
			}
		}

		let compilation = try #require(try verifyModulesCompile(
			[ModuleCompileSources(
				moduleName: "Probe",
				packageName: nil,
				dependencyModuleNames: [],
				inputSwiftFiles: [fixture],
				generatedFiles: ["Fixture+SafeDI.swift": """
				extension Fixture {
				    func generated() {
				        #sourceLocation(file: "\(fixture.path)", line: 1)
				        let unused = 1
				        #sourceLocation()
				    }
				}
				"""],
				activeCompilationConditions: [],
				mockConditionalCompilation: nil,
			)],
			recordsIssues: false,
			filesToDelete: &filesToDelete,
		))

		let warnings = try #require(compilation.modules.first).generatedCodeWarnings
		#expect(warnings.count == 1, "Unexpected warnings \(warnings)")
		#expect(warnings.allSatisfy { $0.hasPrefix("\(fixture.path):1:13: warning: initialization of immutable value 'unused' was never used") }, "Unexpected warnings \(warnings)")
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
					try runProcess(URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "echo \"\(line)\" >&2; echo done"])
				}
			}
			return try await group.reduce(into: [SwiftCompileResult]()) { $0.append($1) }
		}

		#expect(results.count == runCount)
		#expect(results.filter { $0.stderr != line + "\n" || $0.stdout != "done\n" || $0.exitCode != 0 }.isEmpty)
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

	/// The declaration's file that `redirectingGeneratedCode` names, which no compile is given.
	private static let declarationFilePath = "/fixtures/Fixture.swift"

	/// Generated code whose lines 4 and 5 a `#sourceLocation` directive attributes to lines 8 and 9 of
	/// `declarationFilePath`, and whose line 7 is its own.
	private static let redirectingGeneratedCode = """
	extension Fixture {
	    func generated() {
	        #sourceLocation(file: "\(declarationFilePath)", line: 8)
	        let first = 1
	        let second = 2
	        #sourceLocation()
	        let third = 3
	    }
	}
	"""
}
