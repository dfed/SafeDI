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
@testable import SafeDIRootScanner

struct RootScannerTests {
	@Test
	func scan_writesExactManifestAndOutputList_forDuplicateBasenamesInDifferentDirectories() throws {
		let fixture = try ScannerFixture()
		defer { fixture.delete() }

		let rootA = try fixture.writeFile(
			relativePath: "Sources/FeatureA/Root.swift",
			content: """
			@Instantiable(isRoot: true)
			struct Root {
			    init(dep: Dep) {
			        self.dep = dep
			    }
			    @Instantiated let dep: Dep
			}
			@Instantiable
			struct Dep {
			    init() {}
			}
			""",
		)
		let rootB = try fixture.writeFile(
			relativePath: "Sources/FeatureB/Root.swift",
			content: """
			@Instantiable(isRoot: true)
			struct Root {
			    init(dep: Dep) {
			        self.dep = dep
			    }
			    @Instantiated let dep: Dep
			}
			@Instantiable
			struct Dep {
			    init() {}
			}
			""",
		)

		let outputDirectory = fixture.rootDirectory.appendingPathComponent("Output")
		let featureAOutputPath = outputDirectory.appendingPathComponent("FeatureA_Root+SafeDI.swift").path
		let featureBOutputPath = outputDirectory.appendingPathComponent("FeatureB_Root+SafeDI.swift").path
		let escapedFeatureAOutputPath = featureAOutputPath.replacingOccurrences(of: "/", with: #"\/"#)
		let escapedFeatureBOutputPath = featureBOutputPath.replacingOccurrences(of: "/", with: #"\/"#)
		let result = try RootScanner().scan(
			swiftFiles: [rootB, rootA],
			relativeTo: fixture.rootDirectory,
			outputDirectory: outputDirectory,
		)

		#expect(result.manifest == RootScanner.Manifest(dependencyTreeGeneration: [
			RootScanner.Manifest.InputOutputMap(
				inputFilePath: "Sources/FeatureA/Root.swift",
				outputFilePath: featureAOutputPath,
			),
			RootScanner.Manifest.InputOutputMap(
				inputFilePath: "Sources/FeatureB/Root.swift",
				outputFilePath: featureBOutputPath,
			),
		]))

		let manifestURL = fixture.rootDirectory.appendingPathComponent("SafeDIManifest.json")
		try result.writeManifest(to: manifestURL)
		#expect(try String(contentsOf: manifestURL, encoding: .utf8) == "{\"dependencyTreeGeneration\":[{\"inputFilePath\":\"Sources\\/FeatureA\\/Root.swift\",\"outputFilePath\":\"\(escapedFeatureAOutputPath)\"},{\"inputFilePath\":\"Sources\\/FeatureB\\/Root.swift\",\"outputFilePath\":\"\(escapedFeatureBOutputPath)\"}]}")

		let manifestData = try JSONEncoder().encode(result.manifest)
		let decodedManifest = try JSONDecoder().decode(SafeDIToolManifest.self, from: manifestData)
		#expect(decodedManifest.dependencyTreeGeneration.map(\.inputFilePath) == [
			"Sources/FeatureA/Root.swift",
			"Sources/FeatureB/Root.swift",
		])
		#expect(decodedManifest.dependencyTreeGeneration.map(\.outputFilePath) == [
			featureAOutputPath,
			featureBOutputPath,
		])
	}

	@Test
	func scan_ignoresRootsThatOnlyAppearInsideCommentsAndStrings() throws {
		let fixture = try ScannerFixture()
		defer { fixture.delete() }

		let actualRoot = try fixture.writeFile(
			relativePath: "Sources/ActualRoot.swift",
			content: """
			@Instantiable(
			    fulfillingAdditionalTypes: [Foo<Bar, Baz>.self],
			    nestedArgument: .factory(makeValue(label: "example", value: 1)),
			    isRoot: true
			)
			struct ActualRoot {
			    init(dep: Dep) {
			        self.dep = dep
			    }
			    @Instantiated let dep: Dep
			}
			@Instantiable
			struct Dep {
			    init() {}
			}
			""",
		)
		_ = try fixture.writeFile(
			relativePath: "Sources/Comment.swift",
			content: """
			// @Instantiable(isRoot: true)
			@Instantiable
			struct CommentOnly {
			    init() {}
			}
			""",
		)
		_ = try fixture.writeFile(
			relativePath: "Sources/BlockComment.swift",
			content: """
			/*
			@Instantiable(isRoot: true)
			*/
			@Instantiable
			struct BlockCommentOnly {
			    init() {}
			}
			""",
		)
		_ = try fixture.writeFile(
			relativePath: "Sources/StringLiteral.swift",
			content: """
			let documentation = "@Instantiable(isRoot: true)"
			@Instantiable
			struct StringLiteralOnly {
			    init() {}
			}
			""",
		)
		_ = try fixture.writeFile(
			relativePath: "Sources/MultilineString.swift",
			content: #"""
			let documentation = """
			@Instantiable(isRoot: true)
			"""
			@Instantiable
			struct MultilineStringOnly {
			    init() {}
			}
			"""#,
		)
		_ = try fixture.writeFile(
			relativePath: "Sources/RawString.swift",
			content: ##"""
			let documentation = #"""
			@Instantiable(isRoot: true)
			"""#
			@Instantiable
			struct RawStringOnly {
			    init() {}
			}
			"""##,
		)

		let outputDirectory = fixture.rootDirectory.appendingPathComponent("Output")
		let result = try RootScanner().scan(
			swiftFiles: fixture.swiftFiles.shuffled(),
			relativeTo: fixture.rootDirectory,
			outputDirectory: outputDirectory,
		)

		#expect(result.manifest == RootScanner.Manifest(dependencyTreeGeneration: [
			RootScanner.Manifest.InputOutputMap(
				inputFilePath: "Sources/ActualRoot.swift",
				outputFilePath: outputDirectory.appendingPathComponent("ActualRoot+SafeDI.swift").path,
			),
		]))
		#expect(result.outputFiles == [
			outputDirectory.appendingPathComponent("ActualRoot+SafeDI.swift"),
		])
		#expect(try RootScanner.fileContainsRoot(at: actualRoot))
	}

	@Test
	func scan_usesCSVInputPaths_forProjectRootFilesAndDeepParentQualification() throws {
		let fixture = try ScannerFixture()
		defer { fixture.delete() }

		_ = try fixture.writeFile(
			relativePath: "Root.swift",
			content: rootSource(typeName: "TopLevelRoot"),
		)
		_ = try fixture.writeFile(
			relativePath: "Features/A/Root.swift",
			content: rootSource(typeName: "FeatureRoot"),
		)
		_ = try fixture.writeFile(
			relativePath: "Modules/A/Root.swift",
			content: rootSource(typeName: "ModuleRoot"),
		)

		let csvURL = fixture.rootDirectory.appendingPathComponent("InputSwiftFiles.csv")
		try "Modules/A/Root.swift,Root.swift,Features/A/Root.swift".write(
			to: csvURL,
			atomically: true,
			encoding: .utf8,
		)

		let outputDirectory = fixture.rootDirectory.appendingPathComponent("Output")
		let inputFilePaths = try RootScanner.inputFilePaths(from: csvURL)
		let result = try RootScanner().scan(
			inputFilePaths: inputFilePaths,
			relativeTo: fixture.rootDirectory,
			outputDirectory: outputDirectory,
		)

		#expect(result.manifest == RootScanner.Manifest(dependencyTreeGeneration: [
			.init(
				inputFilePath: "Features/A/Root.swift",
				outputFilePath: outputDirectory.appendingPathComponent("Features_A_Root+SafeDI.swift").path,
			),
			.init(
				inputFilePath: "Modules/A/Root.swift",
				outputFilePath: outputDirectory.appendingPathComponent("Modules_A_Root+SafeDI.swift").path,
			),
			.init(
				inputFilePath: "Root.swift",
				outputFilePath: outputDirectory.appendingPathComponent("Root+SafeDI.swift").path,
			),
		]))
	}

	@Test
	func containsRoot_handlesMalformedAttributesAndNestedArguments() {
		#expect(!RootScanner.containsRoot(in: """
		@InstantiableFactory(isRoot: true)
		struct NotARoot {}
		"""))
		#expect(!RootScanner.containsRoot(in: """
		@Instantiable
		struct NotARoot {}
		"""))
		#expect(!RootScanner.containsRoot(in: """
		@Instantiable(isRoot true)
		struct NotARoot {}
		"""))
		#expect(!RootScanner.containsRoot(in: """
		@Instantiable(isRooted: true)
		struct NotARoot {}
		"""))
		#expect(!RootScanner.containsRoot(in: """
		@Instantiable(isRoot: trueish)
		struct NotARoot {}
		"""))
		#expect(!RootScanner.containsRoot(in: """
		@Instantiable(isRoot: true
		struct NotARoot {}
		"""))
		#expect(RootScanner.containsRoot(in: """
		@Instantiable(
		    makeDependency: { value in Dependency.make(value) },
		    options: ["primary": { true }],
		    isRoot: true
		)
		struct ActualRoot {}
		"""))
		#expect(RootScanner.containsRoot(in: """
		@Instantiable(
		    isRoot: true,
		    scope: .shared
		)
		struct EarlyRootClause {}
		"""))
	}

	@Test
	func containsRoot_ignoresNestedCommentsAndEscapedStringDelimiters() {
		let source = [
			"/*",
			"    outer comment",
			"    /* @Instantiable(isRoot: true) */",
			"*/",
			#"let singleLine = "escaped quote: \" @Instantiable(isRoot: true)""#,
			##"let rawString = #"quoted " @Instantiable(isRoot: true) " still raw"#"##,
			#"""
			let multiLine = """
			escaped triple quote: \"""
			@Instantiable(isRoot: true)
			"""
			"""#,
			##"""
			let rawMultiline = #"""
			"""
			@Instantiable(isRoot: true)
			"""#
			"""##,
			"@Instantiable(isRoot: true)",
			"struct ActualRoot {}",
		].joined(separator: "\n")

		#expect(RootScanner.containsRoot(in: source))
	}

	@Test
	func scan_relativeToFilesystemRoot_writesAbsolutePathsWithoutLeadingSlash() throws {
		let fixture = try ScannerFixture()
		defer { fixture.delete() }

		let rootFile = try fixture.writeFile(
			relativePath: "Nested/Root.swift",
			content: rootSource(typeName: "NestedRoot"),
		)
		let outputDirectory = fixture.rootDirectory.appendingPathComponent("Output")
		let result = try RootScanner().scan(
			swiftFiles: [rootFile],
			relativeTo: URL(fileURLWithPath: "/"),
			outputDirectory: outputDirectory,
		)

		#expect(result.manifest == RootScanner.Manifest(dependencyTreeGeneration: [
			.init(
				inputFilePath: String(rootFile.path.dropFirst()),
				outputFilePath: outputDirectory.appendingPathComponent("Root+SafeDI.swift").path,
			),
		]))
	}

	@Test
	func scan_relativeToUnrelatedBase_writesAbsoluteInputPath() throws {
		let fixture = try ScannerFixture()
		defer { fixture.delete() }

		let rootFile = try fixture.writeFile(
			relativePath: "Nested/Root.swift",
			content: rootSource(typeName: "NestedRoot"),
		)
		let unrelatedBase = fixture.rootDirectory
			.deletingLastPathComponent()
			.appendingPathComponent("Unrelated")
		let outputDirectory = fixture.rootDirectory.appendingPathComponent("Output")
		let result = try RootScanner().scan(
			swiftFiles: [rootFile],
			relativeTo: unrelatedBase,
			outputDirectory: outputDirectory,
		)

		#expect(result.manifest == RootScanner.Manifest(dependencyTreeGeneration: [
			.init(
				inputFilePath: rootFile.path,
				outputFilePath: outputDirectory.appendingPathComponent("Root+SafeDI.swift").path,
			),
		]))
	}

	@Test
	func command_run_writesManifest_andArgumentsValidateErrors() throws {
		let fixture = try ScannerFixture()
		defer { fixture.delete() }

		_ = try fixture.writeFile(
			relativePath: "Root.swift",
			content: rootSource(typeName: "CommandRoot"),
		)

		let inputSourcesFile = fixture.rootDirectory.appendingPathComponent("InputSwiftFiles.csv")
		try "Root.swift".write(to: inputSourcesFile, atomically: true, encoding: .utf8)
		let outputDirectory = fixture.rootDirectory.appendingPathComponent("Output")
		let manifestFile = fixture.rootDirectory.appendingPathComponent("SafeDIManifest.json")

		try SafeDIRootScannerCommand.run(arguments: [
			"--input-sources-file", inputSourcesFile.path,
			"--project-root", fixture.rootDirectory.path,
			"--output-directory", outputDirectory.path,
			"--manifest-file", manifestFile.path,
		])

		#expect(try String(contentsOf: manifestFile, encoding: .utf8) == """
		{"dependencyTreeGeneration":[{"inputFilePath":"Root.swift","outputFilePath":"\(outputDirectory.appendingPathComponent("Root+SafeDI.swift").path.replacingOccurrences(of: "/", with: #"\/"#))"}]}
		""")

		let parsedArguments = try Arguments(arguments: [
			"--input-sources-file", inputSourcesFile.path,
			"--project-root", fixture.rootDirectory.path,
			"--output-directory", outputDirectory.path,
			"--manifest-file", manifestFile.path,
		])
		#expect(parsedArguments.inputSourcesFile == inputSourcesFile)
		#expect(parsedArguments.projectRoot.standardizedFileURL == fixture.rootDirectory.standardizedFileURL)
		#expect(parsedArguments.outputDirectory == outputDirectory)
		#expect(parsedArguments.manifestFile == manifestFile)

		#expect(throws: Arguments.ParseError.unexpectedArgument("Root.swift"), performing: {
			try Arguments(arguments: ["Root.swift"])
		})
		#expect(throws: Arguments.ParseError.missingValue(flag: "--project-root"), performing: {
			try Arguments(arguments: ["--project-root"])
		})
		#expect(throws: Arguments.ParseError.missingRequiredFlags([
			"--manifest-file",
			"--output-directory",
			"--project-root",
		]), performing: {
			try Arguments(arguments: ["--input-sources-file", inputSourcesFile.path])
		})
	}

	@Test
	func command_main_executesBuiltScannerBinary() throws {
		let fixture = try ScannerFixture()
		defer { fixture.delete() }

		_ = try fixture.writeFile(
			relativePath: "Root.swift",
			content: rootSource(typeName: "ExecutableRoot"),
		)

		let inputSourcesFile = fixture.rootDirectory.appendingPathComponent("InputSwiftFiles.csv")
		try "Root.swift".write(to: inputSourcesFile, atomically: true, encoding: .utf8)
		let outputDirectory = fixture.rootDirectory.appendingPathComponent("Output")
		let manifestFile = fixture.rootDirectory.appendingPathComponent("SafeDIManifest.json")

		let process = Process()
		process.executableURL = try builtRootScannerExecutableURL()
		process.arguments = [
			"--input-sources-file", inputSourcesFile.path,
			"--project-root", fixture.rootDirectory.path,
			"--output-directory", outputDirectory.path,
			"--manifest-file", manifestFile.path,
		]
		let standardError = Pipe()
		process.standardError = standardError
		try process.run()
		process.waitUntilExit()

		let errorOutput = String(
			data: standardError.fileHandleForReading.readDataToEndOfFile(),
			encoding: .utf8,
		) ?? ""
		if process.terminationStatus != 0 {
			Issue.record("Scanner executable failed: \(errorOutput)")
		}
		#expect(process.terminationStatus == 0)
		#expect(FileManager.default.fileExists(atPath: manifestFile.path))
	}
}

private func rootSource(typeName: String) -> String {
	"""
	@Instantiable(isRoot: true)
	struct \(typeName) {
	    init(dep: Dep) {
	        self.dep = dep
	    }
	    @Instantiated let dep: Dep
	}
	@Instantiable
	struct Dep {
	    init() {}
	}
	"""
}

private func builtRootScannerExecutableURL() throws -> URL {
	let buildDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build")
	guard let enumerator = FileManager.default.enumerator(
		at: buildDirectory,
		includingPropertiesForKeys: [.isExecutableKey],
	) else {
		throw BuiltRootScannerNotFoundError()
	}

	for case let fileURL as URL in enumerator where fileURL.lastPathComponent == "SafeDIRootScanner" {
		let resourceValues = try fileURL.resourceValues(forKeys: [.isExecutableKey])
		if resourceValues.isExecutable == true {
			return fileURL
		}
	}

	throw BuiltRootScannerNotFoundError()
}

private struct BuiltRootScannerNotFoundError: Error {}

private final class ScannerFixture {
	init() throws {
		rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
	}

	let rootDirectory: URL
	private(set) var swiftFiles = [URL]()

	@discardableResult
	func writeFile(
		relativePath: String,
		content: String,
	) throws -> URL {
		let fileURL = rootDirectory.appendingPathComponent(relativePath)
		try FileManager.default.createDirectory(
			at: fileURL.deletingLastPathComponent(),
			withIntermediateDirectories: true,
		)
		try content.write(to: fileURL, atomically: true, encoding: .utf8)
		swiftFiles.append(fileURL)
		return fileURL
	}

	func delete() {
		try? FileManager.default.removeItem(at: rootDirectory)
	}
}
