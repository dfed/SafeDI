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
@testable import SafeDITool

/// The `.safedi` module info `generate --module-info-output` writes. Build systems such as Bazel and Tuist
/// hand it to downstream modules and cache on its bytes, so the same input files must always produce the
/// same bytes.
struct SafeDIToolModuleInfoOutputTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_writesModuleInfoWithRelativePaths_whenInputPathsAreRelative() async throws {
		// The file is binary, so its contents are compared as `dump` prints them, with sorted keys.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				import Alpha

				@Instantiable
				public struct Leaf: Instantiable {
				    public init() {}
				}
				""",
			],
			filesToDelete: &filesToDelete,
			inputPathsRelativeToCurrentDirectory: true,
		)

		let leafPath = output.fixtures["Leaf.swift"].replacingOccurrences(of: "/", with: "\\/")
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.sortedKeys]
		let moduleInfo = try ModuleInfo(moduleInfoData: Data(contentsOf: URL(fileURLWithPath: output.moduleInfoOutputPath)))
		#expect(try String(decoding: encoder.encode(moduleInfo), as: UTF8.self) == """
		{"conditionalCompilationDecisions":[],"configurations":[],"imports":[{"attribute":"","kind":"","moduleName":"Alpha","type":""}],"instantiableTypeNamesInAnyClause":["Leaf"],"instantiables":[{"accessLevel":{"public":{}},"accessModifierRange":{"endColumn":7,"endLine":4,"startColumn":1,"startLine":4},"declarationLocation":{"column":1,"filePath":"\(leafPath)","line":3},"declarationStartLocation":{"column":1,"filePath":"\(leafPath)","line":4},"declarationType":{"structType":{}},"dependencies":[],"generateMock":false,"initializer":{"accessLevel":{"public":{}},"accessModifierRange":{"endColumn":11,"endLine":5,"startColumn":5,"startLine":5},"arguments":[],"declarationStartLocation":{"column":5,"filePath":"\(leafPath)","line":5},"doesThrow":false,"hasGenericParameter":false,"hasGenericWhereClause":false,"isAsync":false,"isOptional":false},"instantiableTypes":[{"simple":{"generics":[],"name":"Leaf"}}],"isRoot":false,"mockAttributes":"","mockOnly":false,"sourceFilePath":"\(leafPath)"}],"mockImports":[{"attribute":"","kind":"","moduleName":"Alpha","type":""}]}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_writesIdenticalModuleInfo_whenRunRepeatedlyOverManyFiles() async throws {
		// `generate` reads, parses, and walks files in parallel, so the order in which files finish differs
		// from run to run. Across this many files, two runs practically never finish in the same order, so
		// every list a file contributes to must be ordered by something other than when its file finished.
		let directory = try temporaryDirectory()
		var swiftFilePaths = [String]()
		for index in 1...Self.manyFilesCount {
			let fileURL = directory.appendingPathComponent("Type\(index).swift")
			// Every tenth file has a syntax error, so the files with errors are listed too.
			let body = index.isMultiple(of: 10) ? ":::brokenSyntax" : "public init() {}"
			// `DEBUG` is not active, but mock imports are found as if the mock condition were, so each file's
			// imports and mock imports differ.
			try """
			import Module\(index)
			#if DEBUG
			import MockSupport\(index)
			#endif

			@Instantiable
			public struct Type\(index): Instantiable {
			    \(body)
			}
			""".write(to: fileURL, atomically: true, encoding: .utf8)
			swiftFilePaths.append(fileURL.path)
		}
		let swiftFileCSV = directory.appendingPathComponent("Sources.csv")
		try swiftFilePaths.joined(separator: ",").write(to: swiftFileCSV, atomically: true, encoding: .utf8)

		var moduleInfoOutputs = [Data]()
		for run in 1...Self.repeatedRunCount {
			let moduleInfoOutput = directory.appendingPathComponent("Run\(run).safedi")
			try await Generate.parse([
				swiftFileCSV.path,
				"--module-info-output", moduleInfoOutput.path,
			]).generate()
			try moduleInfoOutputs.append(Data(contentsOf: moduleInfoOutput))
		}

		#expect(Set(moduleInfoOutputs).count == 1)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_ordersModuleInfoByFileFromScanCache_whenOnlySomeFilesConsultConditions() async throws {
		// Scan caches the files whose scans consulted no condition as one module and every other file on its
		// own, and `generate` appends the latter to the former when it assembles a module from the cache.
		// Each file here that consults a condition sorts before one that does not, in every list.
		let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
		let directory = projectRoot
			.appendingPathComponent(".build")
			.appendingPathComponent("SafeDIToolTestFixtures")
			.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		filesToDelete.append(directory)
		// The project root is the current directory, so these paths name the files both to `scan` and in its cache.
		let relativeDirectory = String(directory.path.dropFirst(projectRoot.path.count + 1))
		let fileContentByRelativePath = [
			// Another module's configuration, which reaches this module's input files in a multi-module build.
			"Dependency/SafeDIConfiguration.swift": """
			#if DEBUG
			import DependencyDebugSupport
			#endif

			#SafeDIConfiguration()
			""",
			"Module/SafeDIConfiguration.swift": """
			#SafeDIConfiguration()
			""",
			"Module/Alpha.swift": """
			#if DEBUG
			import AlphaDebugSupport
			#endif
			import AlphaSupport

			@Instantiable
			public struct Alpha: Instantiable {
			    public init() {}
			}
			""",
			"Module/Bravo.swift": """
			import BravoSupport

			@Instantiable
			public struct Bravo: Instantiable {
			    public init() {}
			}
			""",
			"Module/BrokenAlpha.swift": """
			#if DEBUG
			import AlphaDebugSupport
			#endif

			@Instantiable
			public struct BrokenAlpha: Instantiable {
			    :::brokenSyntax
			}
			""",
			"Module/BrokenBravo.swift": """
			@Instantiable
			public struct BrokenBravo: Instantiable {
			    :::brokenSyntax
			}
			""",
		]
		var swiftFilePaths = [String]()
		for (relativePath, content) in fileContentByRelativePath {
			let fileURL = directory.appendingPathComponent(relativePath)
			try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
			try content.write(to: fileURL, atomically: true, encoding: .utf8)
			swiftFilePaths.append("\(relativeDirectory)/\(relativePath)")
		}
		let outputDirectory = try temporaryDirectory()
		let swiftFileCSV = outputDirectory.appendingPathComponent("Sources.csv")
		try swiftFilePaths.joined(separator: ",").write(to: swiftFileCSV, atomically: true, encoding: .utf8)
		let manifestFile = outputDirectory.appendingPathComponent("Manifest.json")
		try await Scan.parse([
			"--input-sources-file", swiftFileCSV.path,
			"--project-root", projectRoot.path,
			"--output-directory", outputDirectory.path,
			"--manifest-file", manifestFile.path,
			"--mock-scoped-files",
		] + swiftFilePaths.filter { $0.hasPrefix("\(relativeDirectory)/Module/") }).run()
		#expect(FileManager.default.fileExists(atPath: scannedModuleInfoURL(forManifestPath: manifestFile.path).path))

		let moduleInfoOutput = outputDirectory.appendingPathComponent("Module.safedi")
		try await Generate.parse([
			swiftFileCSV.path,
			"--swift-manifest", manifestFile.path,
			"--module-info-output", moduleInfoOutput.path,
		]).generate()
		let moduleInfo = try ModuleInfo(moduleInfoData: Data(contentsOf: moduleInfoOutput))

		#expect(moduleInfo.imports == [
			ImportStatement(moduleName: "AlphaSupport"),
			ImportStatement(moduleName: "BravoSupport"),
		])
		// Mock imports are found as if the mock condition, `DEBUG`, were active.
		#expect(moduleInfo.mockImports == [
			ImportStatement(moduleName: "AlphaDebugSupport"),
			ImportStatement(moduleName: "AlphaSupport"),
			ImportStatement(moduleName: "BravoSupport"),
			ImportStatement(moduleName: "DependencyDebugSupport"),
		])
		#expect(moduleInfo.configurations.map(\.sourceFilePath) == [
			"\(relativeDirectory)/Dependency/SafeDIConfiguration.swift",
			"\(relativeDirectory)/Module/SafeDIConfiguration.swift",
		])
		#expect(moduleInfo.filesWithUnexpectedNodes == [
			"\(relativeDirectory)/Module/BrokenAlpha.swift",
			"\(relativeDirectory)/Module/BrokenBravo.swift",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_writesEachImportOnce_whenFilesShareAnImport() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				import Shared

				@Instantiable
				public struct First: Instantiable {
				    public init() {}
				}
				""",
				"""
				import Shared

				@Instantiable
				public struct Second: Instantiable {
				    public init() {}
				}
				""",
			],
			filesToDelete: &filesToDelete,
		)

		#expect(output.moduleInfo.imports == [ImportStatement(moduleName: "Shared")])
		#expect(output.moduleInfo.mockImports == [ImportStatement(moduleName: "Shared")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_writesImportsSorted_whenAdditionalDirectoryFileImportsModuleThatSortsFirst() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				#SafeDIConfiguration(
				    additionalDirectoriesToInclude: ["$ADDITIONAL_DIRECTORY"]
				)
				""",
				"""
				import Zulu

				@Instantiable
				public struct TargetType: Instantiable {
				    public init() {}
				}
				""",
			],
			additionalDirectorySwiftFileContent: [
				"""
				import Alpha

				@Instantiable
				public struct AdditionalType: Instantiable {
				    public init() {}
				}
				""",
			],
			filesToDelete: &filesToDelete,
		)

		#expect(output.moduleInfo.imports == [
			ImportStatement(moduleName: "Alpha"),
			ImportStatement(moduleName: "Zulu"),
		])
		#expect(output.moduleInfo.mockImports == [
			ImportStatement(moduleName: "Alpha"),
			ImportStatement(moduleName: "Zulu"),
		])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// Enough files that parallel parsing finishes them in a different order on practically every run.
	private static let manyFilesCount = 200
	private static let repeatedRunCount = 5

	private mutating func temporaryDirectory() throws -> URL {
		let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		filesToDelete.append(directory)
		return directory
	}
}
