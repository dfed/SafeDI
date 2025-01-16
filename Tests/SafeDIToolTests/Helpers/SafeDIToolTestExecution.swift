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
import XCTest

@testable import SafeDITool

@MainActor
func executeSafeDIToolTest(
    swiftFileContent: [String],
    dependentModuleInfoPaths: [String] = [],
    buildDependencyTreeOutput: Bool = false,
    buildDOTFileOutput: Bool = false,
    filesToDelete: inout [URL]
) async throws -> TestOutput {
    let swiftFileCSV = URL.temporaryFile
    let swiftFiles = try swiftFileContent
        .map {
            let location = URL.temporaryFile.appendingPathExtension("swift")
            try $0.write(to: location, atomically: true, encoding: .utf8)
            return location
        }
    try swiftFiles
        .map(\.relativePath)
        .joined(separator: ",")
        .write(to: swiftFileCSV, atomically: true, encoding: .utf8)

    let dependentModuleInfoFileCSV = URL.temporaryFile
    try dependentModuleInfoPaths
        .joined(separator: ",")
        .write(to: dependentModuleInfoFileCSV, atomically: true, encoding: .utf8)

    let moduleInfoOutput = URL.temporaryFile.appendingPathExtension("safedi")
    let dependencyTreeOutput = URL.temporaryFile.appendingPathExtension("swift")
    let dotTreeOutput = URL.temporaryFile.appendingPathExtension("dot")
    fileFinder = StubFileFinder(files: swiftFiles) // Successfully execute the file finder code path.
    var tool = SafeDITool()
    tool.swiftSourcesFilePath = swiftFileCSV.relativePath
    tool.include = ["Fake"]
    tool.includeFilePath = nil
    tool.additionalImportedModules = []
    tool.additionalImportedModulesFilePath = nil
    tool.moduleInfoOutput = moduleInfoOutput.relativePath
    tool.dependentModuleInfoFilePath = dependentModuleInfoPaths.isEmpty ? nil : dependentModuleInfoFileCSV.relativePath
    tool.dependencyTreeOutput = buildDependencyTreeOutput ? dependencyTreeOutput.relativePath : nil
    tool.dotFileOutput = buildDOTFileOutput ? dotTreeOutput.relativePath : nil
    try await tool.run()

    filesToDelete.append(swiftFileCSV)
    filesToDelete += swiftFiles
    filesToDelete.append(moduleInfoOutput)
    if buildDependencyTreeOutput {
        filesToDelete.append(dependencyTreeOutput)
    }
    if buildDOTFileOutput {
        filesToDelete.append(dotTreeOutput)
    }

    return try TestOutput(
        moduleInfo: JSONDecoder().decode(SafeDITool.ModuleInfo.self, from: Data(contentsOf: moduleInfoOutput)),
        moduleInfoOutputPath: moduleInfoOutput.relativePath,
        dependencyTree: buildDependencyTreeOutput ? String(data: Data(contentsOf: dependencyTreeOutput), encoding: .utf8) : nil,
        dotTree: buildDOTFileOutput ? String(data: Data(contentsOf: dotTreeOutput), encoding: .utf8) : nil
    )
}

struct TestOutput {
    let moduleInfo: SafeDITool.ModuleInfo
    let moduleInfoOutputPath: String
    let dependencyTree: String?
    let dotTree: String?
}

extension URL {
    fileprivate static var temporaryFile: URL {
        #if os(Linux)
            return FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #else
            guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
                return FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            }
            return URL.temporaryDirectory.appending(path: UUID().uuidString)
        #endif
    }
}

struct StubFileFinder: FileFinder {
    func enumerator(
        at _: URL,
        includingPropertiesForKeys _: [URLResourceKey]?,
        options _: FileManager.DirectoryEnumerationOptions,
        errorHandler _: ((URL, any Error) -> Bool)?
    ) -> FileManager.DirectoryEnumerator? {
        StubDirectoryEnumerator(files: files)
    }

    final class StubDirectoryEnumerator: FileManager.DirectoryEnumerator {
        init(files: [URL]) {
            self.files = files
                // Also include a random file in the glob.
                + [URL.temporaryFile]
        }

        override func nextObject() -> Any? {
            if files.isEmpty {
                nil
            } else {
                files.removeFirst()
            }
        }

        var files: [URL]
    }

    let files: [URL]
}

func assertThrowsError(
    _ errorDescription: String,
    line: UInt = #line,
    block: @MainActor () async throws -> some Sendable
) async {
    do {
        _ = try await block()
        XCTFail("Did not throw error!", line: line)
    } catch {
        XCTAssertEqual("\(error)", errorDescription, line: line)
    }
}
