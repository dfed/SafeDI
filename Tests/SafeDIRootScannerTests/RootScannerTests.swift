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

		let outputFilesURL = fixture.rootDirectory.appendingPathComponent("SafeDIOutputFiles.txt")
		try result.writeOutputFiles(to: outputFilesURL)
		#expect(try String(contentsOf: outputFilesURL, encoding: .utf8) == "\(featureAOutputPath)\n\(featureBOutputPath)")
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
}

private final class ScannerFixture {
	init() throws {
		rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
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
