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

#if os(Linux)
	import Glibc
#else
	import Darwin
#endif

@testable import SafeDITool

@MainActor // serialized due to changes to stdout
struct SafeDIToolVersionTests {
	@Test
	func run_withVersionFlag_printsCurrentVersion() async throws {
		var tool = SafeDITool()
		tool.swiftSourcesFilePath = nil
		tool.showVersion = true
		tool.include = []
		tool.includeFilePath = nil
		tool.additionalImportedModules = []
		tool.additionalImportedModulesFilePath = nil
		tool.moduleInfoOutput = nil
		tool.dependentModuleInfoFilePath = nil
		tool.dependencyTreeOutput = nil
		tool.dotFileOutput = nil

		let output = try await captureStandardOutput {
			try await tool.run()
		}

		let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
		#expect(trimmedOutput == SafeDITool.currentVersion)
	}

	private func captureStandardOutput(_ block: () async throws -> Void) async throws -> String {
		let pipe = Pipe()
		let originalStdout = dup(STDOUT_FILENO)
		dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)

		try await block()

		pipe.fileHandleForWriting.closeFile()
		dup2(originalStdout, STDOUT_FILENO)
		close(originalStdout)

		return String(data: pipe.fileHandleForReading.availableData, encoding: .utf8) ?? ""
	}
}
