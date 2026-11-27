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
import SafeDIToolLibrary
import Testing
@testable import SafeDIToolTestSupport

/// What the generation and assertion helpers record for `.claude/skills/regenerate-expectations/regenerate-expectations.py` when they are given a
/// record directory, and that they record nothing without one.
struct ExpectationRecordingTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		filesToDelete = [URL]()
		recordDirectory = TestTemporaryDirectory.uniquePath(prefix: "expectation-records-")
	}

	deinit {
		// A record directory is listed before the call that writes into it, so a call that fails first leaves a path
		// that was never created; trapping on its removal would hide that failure behind a crash of the whole suite.
		for fileToDelete in filesToDelete {
			try? FileManager.default.removeItem(at: fileToDelete)
		}
		try? FileManager.default.removeItem(at: recordDirectory)
	}

	// MARK: Tests – Generation records

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func executeSafeDIToolTest_writesOneRecordPerGeneratedFile_whenGivenARecordDirectory() async throws {
		let callLine = #line + 1
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.aliasedReceiveFixture,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			skipCompileVerification: true,
			recordDirectory: recordDirectory,
		)

		let expectedContentByOutputName = try #require(output.generatedFiles)
		let records = try Self.records(in: recordDirectory)
		#expect(Dictionary(grouping: records.generation, by: \.outputName).mapValues { $0.map(\.content) } == expectedContentByOutputName.mapValues { [$0] })
		#expect(records.generation.allSatisfy { $0.fileID == #fileID && $0.line == callLine && $0.integration == nil && $0.module == nil && $0.skipsCompileVerification })
		#expect(records.assertion.isEmpty)
		#expect(try String(contentsOf: recordDirectory.appendingPathComponent(ExpectationRecording.headerFileName), encoding: .utf8) == generatedFileHeader)
	}

	/// The marker is what tells the script that tests reading `compileVerificationIsEnabled` recorded nothing for what
	/// that guards. CI runs this test both ways: "Repeat Tests on Linux" sets `SAFEDI_SKIP_COMPILE_CHECK`.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func executeSafeDIToolTest_marksTheRecordDirectory_onlyWhenCompileVerificationIsOff() async throws {
		_ = try await executeSafeDIToolTest(
			swiftFileContent: Self.aliasedReceiveFixture,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			skipCompileVerification: true,
			recordDirectory: recordDirectory,
		)

		let marker = recordDirectory.appendingPathComponent(ExpectationRecording.compileVerificationSkippedFileName)
		if compileVerificationIsEnabled {
			#expect(!FileManager.default.fileExists(atPath: marker.path))
		} else {
			#expect(try String(contentsOf: marker, encoding: .utf8) == ExpectationRecording.compileVerificationSkippedNotice)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func executeSafeDIToolMultiModuleTest_writesOneRecordPerGeneratedFile_whenGivenARecordDirectory(integration: MultiModuleIntegration) async throws {
		let callLine = #line + 1
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [ModuleFixture(name: "App", packageName: "App", swiftFileContent: Self.aliasedReceiveFixture)],
			integration: integration,
			compileVerification: .skipped,
			filesToDelete: &filesToDelete,
			recordDirectory: recordDirectory,
		)

		let expectedContentByOutputName = try #require(output.modules["App"]).generatedFiles
		let records = try Self.records(in: recordDirectory)
		#expect(Dictionary(grouping: records.generation, by: \.outputName).mapValues { $0.map(\.content) } == expectedContentByOutputName.mapValues { [$0] })
		#expect(records.generation.allSatisfy { $0.fileID == #fileID && $0.line == callLine && $0.integration == "\(integration)" && $0.module == "App" && $0.skipsCompileVerification })
		#expect(records.assertion.isEmpty)
	}

	@Test(arguments: [nil, PluginInvocation.scanDuringGenerate(reportsFixtureDirectoryThroughSymbolicLink: false)])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func executeSafeDIToolTest_writesTheSameKeysOnEveryCall_whenGivenATargetGraph(pluginInvocation: PluginInvocation?) async throws {
		// The target graph spells the fixture files, whose directory a UUID names afresh in every call, so its paths must
		// be replaced by placeholders before they reach the key.
		var keysByCall = [Set<String>]()
		for _ in 0..<2 {
			let callRecordDirectory = TestTemporaryDirectory.uniquePath(prefix: "expectation-records-")
			filesToDelete.append(callRecordDirectory)
			_ = try await executeSafeDIToolTest(
				swiftFileContent: Self.aliasedReceiveFixture,
				pluginInvocation: pluginInvocation,
				buildCombinedOutput: pluginInvocation == nil,
				filesToDelete: &filesToDelete,
				skipCompileVerification: true,
				pluginTargetGraph: { inputSwiftFilePaths in
					PluginTargetGraph(
						target: PluginTargetGraph.Target(moduleName: "App", packageID: "application", sourceFilePaths: inputSwiftFilePaths, dependencyModuleNames: []),
						dependencyTargets: [],
					)
				},
				recordDirectory: callRecordDirectory,
			)
			keysByCall.append(try Set(Self.records(in: callRecordDirectory).generation.map(\.key)))
		}

		#expect(!keysByCall[0].isEmpty)
		#expect(keysByCall[0] == keysByCall[1])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func executeSafeDIToolTest_recordsTheCallingTestsLocation_whenCalledThroughAHelperFunction() async throws {
		let callLine = try await generateThroughHelperFunction()

		let records = try Self.records(in: recordDirectory)
		let testLocation = try #require(Test.current?.sourceLocation)
		#expect(!records.generation.isEmpty)
		#expect(records.generation.allSatisfy { $0.line == callLine && $0.testFileID == #fileID && $0.testLine == testLocation.line })
		#expect(testLocation.line != callLine)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func executeSafeDIToolTest_writesNothing_whenGivenNoRecordDirectory() async throws {
		try FileManager.default.createDirectory(at: recordDirectory, withIntermediateDirectories: true)

		_ = try await executeSafeDIToolTest(
			swiftFileContent: Self.aliasedReceiveFixture,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			skipCompileVerification: true,
			recordDirectory: nil,
		)

		#expect(try FileManager.default.contentsOfDirectory(atPath: recordDirectory.path) == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func executeSafeDIToolTest_writesNothingAndRecordsAnIssue_whenRecordDirectoryIsInsideTheCheckout() async throws {
		let refusedDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
			.appendingPathComponent(".build")
			.appendingPathComponent("expectation-records-\(UUID().uuidString)")
		var filesToDelete = [URL]()

		try await withKnownIssue("Recording into the checkout is refused") {
			_ = try await executeSafeDIToolTest(
				swiftFileContent: Self.aliasedReceiveFixture,
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				skipCompileVerification: true,
				recordDirectory: refusedDirectory,
			)
		} matching: { issue in
			issue.comments.contains { $0.rawValue.contains("refuses to record") }
		}
		self.filesToDelete += filesToDelete

		#expect(!FileManager.default.fileExists(atPath: refusedDirectory.path))
	}

	// MARK: Tests – Keys

	@Test
	func key_isTheDigestOfItsComponents_whenGivenFixedComponents() {
		#expect(Self.generationKey() == "052d4609d1ddaf928e897e64c1b266f7e8ce11cb4ba7b3bb6e396f115418c754")
		#expect(ExpectationRecording.key(fileID: "Module/File.swift", line: 12, column: 9, testName: "test()", overload: "plain", module: nil, expectedDigest: "digest") == "23ea8b269782b094cfbe71c3a7adc6cda4b1b66e0d7b8c4d8fce46614d399a37")
	}

	@Test
	func key_changes_whenAnyOneComponentChanges() {
		let variations = [
			Self.generationKey(fileID: "Module/Other.swift"),
			Self.generationKey(line: 13),
			Self.generationKey(column: 10),
			Self.generationKey(testName: "other()"),
			Self.generationKey(inputsDigest: "other"),
			Self.generationKey(integration: "swiftPackagePlugin"),
			Self.generationKey(integration: nil),
			Self.generationKey(module: "Other"),
			Self.generationKey(module: nil),
			Self.generationKey(outputName: "Other+SafeDI.swift"),
		]
		#expect(Set(variations + [Self.generationKey()]).count == variations.count + 1)
	}

	// MARK: Tests – Assertion records

	@Test
	mutating func assertThrowsError_writesOneRecordOfTheExpectedAndActualDescriptions_whenTheyDiffer() async throws {
		let callLine = #line + 2
		await withKnownIssue("The descriptions differ") {
			await assertThrowsError("Expected description.", recordDirectory: recordDirectory) {
				throw DescribedError(description: "Actual description.")
			}
		}

		let records = try Self.records(in: recordDirectory)
		#expect(records.generation.isEmpty)
		#expect(records.assertion.map(\.overload) == ["plain"])
		#expect(records.assertion.map(\.expected) == ["Expected description."])
		#expect(records.assertion.map(\.actual) == ["Actual description."])
		#expect(records.assertion.allSatisfy { $0.fileID == #fileID && $0.line == callLine && $0.module == nil })
	}

	@Test
	mutating func assertThrowsError_writesNothing_whenTheDescriptionsAreEqual() async {
		await assertThrowsError("Actual description.", recordDirectory: recordDirectory) {
			throw DescribedError(description: "Actual description.")
		}

		#expect(!FileManager.default.fileExists(atPath: recordDirectory.path))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func assertThrowsErrorDiagnostics_writesOneRecordWithPlaceholderPaths_whenTheDiagnosticsDiffer() async throws {
		var filesToDelete = [URL]()
		await withKnownIssue("The diagnostics differ") {
			await assertThrowsError(diagnostics: { _ in "Expected diagnostics." }, recordDirectory: recordDirectory) {
				try await executeSafeDIToolTest(swiftFileContent: Self.receivedSessionWithForwardedPropertyFixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
			}
		}
		self.filesToDelete += filesToDelete

		let records = try Self.records(in: recordDirectory)
		#expect(records.generation.isEmpty)
		#expect(records.assertion.map(\.overload) == ["diagnostics"])
		#expect(records.assertion.map(\.expected) == ["Expected diagnostics."])
		#expect(records.assertion.map(\.actual) == ["$TARGET_DIRECTORY/Child.swift:4:5: error: \(Self.receivedSessionWithForwardedPropertyError)"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func assertThrowsErrorDiagnostics_writesNothing_whenTheDiagnosticsAreEqual() async {
		var filesToDelete = [URL]()
		await assertThrowsError(diagnostics: { fixtures in "\(fixtures["Child.swift"]):4:5: error: \(Self.receivedSessionWithForwardedPropertyError)" }, recordDirectory: recordDirectory) {
			try await executeSafeDIToolTest(swiftFileContent: Self.receivedSessionWithForwardedPropertyFixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		self.filesToDelete += filesToDelete

		#expect(!FileManager.default.fileExists(atPath: recordDirectory.path))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func assertThrowsMultiModuleError_writesOneRecordWithPlaceholderPaths_whenTheDiagnosticsDiffer() async throws {
		var filesToDelete = [URL]()
		await withKnownIssue("The diagnostics differ") {
			await assertThrowsMultiModuleError(inModule: "App", diagnostics: { _ in "Expected diagnostics." }, recordDirectory: recordDirectory) {
				try await executeSafeDIToolMultiModuleTest(
					modules: [ModuleFixture(name: "App", packageName: "App", swiftFileContent: Self.receivedSessionWithForwardedPropertyFixture)],
					integration: .moduleInfo,
					compileVerification: .skipped,
					filesToDelete: &filesToDelete,
				)
			}
		}
		self.filesToDelete += filesToDelete

		let records = try Self.records(in: recordDirectory)
		#expect(records.generation.isEmpty)
		#expect(records.assertion.map(\.overload) == ["multiModuleDiagnostics"])
		#expect(records.assertion.map(\.module) == ["App"])
		#expect(records.assertion.map(\.expected) == ["Expected diagnostics."])
		#expect(records.assertion.map(\.actual) == ["$FIXTURE_ROOT/App/Sources/App/Child.swift:4:5: error: \(Self.receivedSessionWithForwardedPropertyError)"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func assertThrowsMultiModuleError_writesNothing_whenTheDiagnosticsAreEqual() async {
		var filesToDelete = [URL]()
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in "\(fixtures["App"]!["Child.swift"]):4:5: error: \(Self.receivedSessionWithForwardedPropertyError)" }, recordDirectory: recordDirectory) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [ModuleFixture(name: "App", packageName: "App", swiftFileContent: Self.receivedSessionWithForwardedPropertyFixture)],
				integration: .moduleInfo,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
		self.filesToDelete += filesToDelete

		#expect(!FileManager.default.fileExists(atPath: recordDirectory.path))
	}

	// MARK: Private

	/// Runs the aliased fixture, recording into `recordDirectory`, from a function that is no test, and returns the
	/// line of that call.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func generateThroughHelperFunction() async throws -> Int {
		let callLine = #line + 1
		_ = try await executeSafeDIToolTest(
			swiftFileContent: Self.aliasedReceiveFixture,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			skipCompileVerification: true,
			recordDirectory: recordDirectory,
		)
		return callLine
	}

	private var filesToDelete: [URL]
	private let recordDirectory: URL

	/// A root whose mock-generating child receives a renamed property, so the generated code names the child's
	/// declaration of it in a comment.
	private static let aliasedReceiveFixture = [
		"""
		@Instantiable(isRoot: true)
		public struct Root: Instantiable {
		    public init(service: Service, consumer: Consumer) {
		        self.service = service
		        self.consumer = consumer
		    }

		    @Instantiated let service: Service
		    @Instantiated let consumer: Consumer
		}
		""",
		"""
		@Instantiable(generateMock: true)
		public struct Consumer: Instantiable {
		    public init(renamedService: Service) {
		        self.renamedService = renamedService
		    }

		    @Received(fulfilledByDependencyNamed: "service", ofType: Service.self) let renamedService: Service
		}
		""",
		"""
		@Instantiable
		public struct Service: Instantiable {
		    public init() {}
		}
		""",
	]

	/// A child that receives a type with a forwarded property, which SafeDI rejects at the child's file.
	private static let receivedSessionWithForwardedPropertyFixture = [
		"""
		@Instantiable(isRoot: true)
		public final class Root: Instantiable {
		    public init(child: Child) { self.child = child }
		    @Instantiated let child: Child
		}
		""",
		"""
		@Instantiable
		public final class Child: Instantiable {
		    public init(session: Session) { self.session = session }
		    @Received let session: Session
		}
		""",
		"""
		@Instantiable
		public final class Session: Instantiable {
		    public init(userID: String) { self.userID = userID }
		    @Forwarded let userID: String
		}
		""",
	]

	private static let receivedSessionWithForwardedPropertyError = "@Received property `session: Session` is not @Instantiated or @Forwarded in chain: Root -> Child. `Session` has @Forwarded properties, so SafeDI builds it only through an `Instantiator`, never as an @Instantiated constant. Declare `@Forwarded let session: Session` on a type below `Root` in the chain, and pass the value to the `Instantiator` that builds that type, to fix."

	private static func generationKey(
		fileID: String = "Module/File.swift",
		line: Int = 12,
		column: Int = 9,
		testName: String = "test()",
		inputsDigest: String = "digest",
		integration: String? = "moduleInfo",
		module: String? = "App",
		outputName: String = "Root+SafeDI.swift",
	) -> String {
		ExpectationRecording.key(fileID: fileID, line: line, column: column, testName: testName, inputsDigest: inputsDigest, integration: integration, module: module, outputName: outputName)
	}

	/// The records in `directory`, by kind.
	private static func records(in directory: URL) throws -> (generation: [ExpectationRecording.GenerationRecord], assertion: [ExpectationRecording.AssertionRecord]) {
		var generation = [ExpectationRecording.GenerationRecord]()
		var assertion = [ExpectationRecording.AssertionRecord]()
		for fileName in try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() where fileName.hasSuffix(".json") {
			let data = try Data(contentsOf: directory.appendingPathComponent(fileName))
			if try JSONDecoder().decode(RecordKind.self, from: data).kind == ExpectationRecording.GenerationRecord.kind {
				try generation.append(JSONDecoder().decode(ExpectationRecording.GenerationRecord.self, from: data))
			} else {
				try assertion.append(JSONDecoder().decode(ExpectationRecording.AssertionRecord.self, from: data))
			}
		}
		return (generation, assertion)
	}

	private struct RecordKind: Decodable {
		let kind: String
	}

	private struct DescribedError: Error, CustomStringConvertible {
		let description: String
	}
}
