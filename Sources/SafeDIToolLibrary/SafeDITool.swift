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

/// What the `SafeDITool` executable runs. The tool's commands live in this library rather than in the executable target, so
/// that the targets that test them depend on a library, which every SwiftPM build system builds before what imports it.
public enum SafeDIToolCommandLine {
	/// The command the `SafeDITool` executable parses its arguments into and runs.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	public static var rootCommand: any AsyncParsableCommand.Type {
		SafeDITool.self
	}
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
public struct SafeDITool: AsyncParsableCommand {
	public init() {}

	public static let configuration = CommandConfiguration(
		commandName: "safeditool",
		version: currentVersion,
		subcommands: [Generate.self, Scan.self, Query.self, Dump.self],
		defaultSubcommand: Generate.self,
	)

	static var currentVersion: String {
		"0.0.0-development"
	}

	@TaskLocal public static var fileFinder: FileFinder = FileManager.default

	/// Whether the process ends once the command it runs returns, as the `SafeDITool` executable's does: `generate` then
	/// keeps what it built rather than releasing it, which the process's end does at once. A test that runs a command in
	/// its own process leaves this `false`.
	@TaskLocal public static var processEndsWithCommand = false
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension Data {
	func write(toPath filePath: String, atomically: Bool = false) throws {
		try write(to: filePath.asFileURL, options: atomically ? .atomic : [])
	}

	/// Writes these bytes to `filePath` unless the file there already holds exactly them, so its modification time moves
	/// only when its content does: a build system that compares modification times, as Xcode does for a script phase's
	/// outputs, then reruns what reads the file only when it changed.
	/// - Parameter atomically: Whether to write a temporary file and move it into place, so that a reader never sees
	///   part of the file.
	func writeIfChanged(toPath filePath: String, atomically: Bool = false) throws {
		guard (try? Data(contentsOf: filePath.asFileURL)) != self else { return }
		try write(toPath: filePath, atomically: atomically)
	}
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension [UInt8] {
	/// The UTF-8 bytes of `prefix` followed by `pieces` joined by `separator`: the same bytes as
	/// `Array((prefix + pieces.joined(separator: separator)).utf8)`, written once into an array of their exact size, with
	/// no joined text. A generated file can be tens of megabytes, and each copy of it adds to `generate`'s peak memory.
	init(joining pieces: [String], separator: String, after prefix: String) {
		self.init()
		reserveCapacity(prefix.utf8.count + pieces.reduce(0) { $0 + $1.utf8.count } + separator.utf8.count * Swift.max(pieces.count - 1, 0))
		append(contentsOf: prefix.utf8)
		for (index, piece) in pieces.enumerated() {
			if index > 0 {
				append(contentsOf: separator.utf8)
			}
			append(contentsOf: piece.utf8)
		}
	}

	/// Writes these bytes as `Data.writeIfChanged(toPath:atomically:)` does, without copying them into a `Data` first.
	func writeIfChanged(toPath filePath: String, atomically: Bool = false) throws {
		try withUnsafeBufferPointer { bytes in
			// The `Data` only lends the array's bytes for the write, and is gone before the array can change.
			let data = bytes.baseAddress.map { Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: $0), count: bytes.count, deallocator: .none) } ?? Data()
			try data.writeIfChanged(toPath: filePath, atomically: atomically)
		}
	}
}

extension String {
	/// `pieces` joined by `separator`: the same text as `pieces.joined(separator: separator)`, written once into a string of
	/// its exact size rather than one grown by doubling beside the pieces it copies.
	init(joining pieces: [String], separator: String) {
		var text = ""
		text.reserveCapacity(pieces.reduce(0) { $0 + $1.utf8.count } + separator.utf8.count * Swift.max(pieces.count - 1, 0))
		for (index, piece) in pieces.enumerated() {
			if index > 0 {
				text += separator
			}
			text += piece
		}
		self = text
	}

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

	/// Parses a path-list CSV emitted by a build system, shell script, or
	/// `echo`/`printf`. Splits on commas and newlines, trims surrounding
	/// whitespace from each entry, and drops empty entries — so a trailing
	/// `\n` (as `echo "x" > deps.csv` writes) or CRLF line endings don't
	/// produce a path that includes whitespace.
	func parsedPathListCSV() -> [String] {
		components(separatedBy: CharacterSet(charactersIn: ",\n\r"))
			.map { $0.trimmingCharacters(in: .whitespaces) }
			.filter { !$0.isEmpty }
	}
}

public protocol FileFinder: Sendable {
	func enumerator(
		at url: URL,
		includingPropertiesForKeys keys: [URLResourceKey]?,
		options mask: FileManager.DirectoryEnumerationOptions,
		errorHandler handler: ((URL, any Error) -> Bool)?,
	) -> FileManager.DirectoryEnumerator?
}

extension FileManager: FileFinder {}
