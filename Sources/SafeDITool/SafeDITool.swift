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

import ArgumentParser
import Foundation

@main
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
struct SafeDITool: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "safeditool",
		version: currentVersion,
		subcommands: [Generate.self, Scan.self],
		defaultSubcommand: Generate.self,
	)

	static var currentVersion: String {
		"0.0.0-development"
	}

	@TaskLocal static var fileFinder: FileFinder = FileManager.default
}

extension Data {
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func write(toPath filePath: String) throws {
		try write(to: filePath.asFileURL)
	}
}

extension String {
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func write(toPath filePath: String) throws {
		try Data(utf8).write(toPath: filePath)
	}

	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	var asFileURL: URL {
		#if os(Linux)
			URL(fileURLWithPath: self)
		#else
			URL(filePath: self)
		#endif
	}
}

protocol FileFinder: Sendable {
	func enumerator(
		at url: URL,
		includingPropertiesForKeys keys: [URLResourceKey]?,
		options mask: FileManager.DirectoryEnumerationOptions,
		errorHandler handler: ((URL, any Error) -> Bool)?,
	) -> FileManager.DirectoryEnumerator?
}

extension FileManager: FileFinder {}
extension FileManager: @retroactive @unchecked Sendable {
	// FileManager is thread safe:
	// https://developer.apple.com/documentation/foundation/nsfilemanager#1651181
}
