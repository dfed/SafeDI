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

/// A diagnostic in the format the Swift compiler emits – `<path>:<line>:<column>: <severity>: <message>` –
/// so command-line builds show it as a readable first line and Xcode surfaces it alongside compiler diagnostics.
public struct SourceDiagnostic: Hashable, Sendable {
	// MARK: Initialization

	public init(
		severity: Severity,
		location: Dependency.DeclarationLocation,
		message: String,
	) {
		self.severity = severity
		self.location = location
		self.message = message
	}

	// MARK: Public

	public enum Severity: String, Hashable, Sendable {
		/// The problem itself. An error fails generation and is the first line printed for it.
		case error
		/// Detail that accompanies an error – a related location or a suggested fix. A note never stands alone.
		case note
	}

	/// Whether the diagnostic is the error itself or a note that adds detail, possibly at another location.
	public let severity: Severity
	/// Where the diagnostic points.
	public let location: Dependency.DeclarationLocation
	/// A single line of text. A newline would break the compiler format, so messages must not contain one.
	public let message: String

	/// The diagnostic formatted as the Swift compiler would print it.
	public var formatted: String {
		"\(location.filePath):\(location.line):\(location.column): \(severity.rawValue): \(message)"
	}

	/// Returns a copy whose file path is absolute, resolving a relative path against the directory at `directoryPath`.
	/// Build tools attribute a diagnostic to a file by its path, and the tool is often run from a
	/// directory other than the one the user is looking at, so printed paths must not stay relative.
	public func resolvingFilePath(relativeToDirectory directoryPath: String) -> SourceDiagnostic {
		let directory = URL(fileURLWithPath: directoryPath, isDirectory: true)
		return SourceDiagnostic(
			severity: severity,
			location: Dependency.DeclarationLocation(
				filePath: URL(fileURLWithPath: location.filePath, relativeTo: directory).standardizedFileURL.path,
				line: location.line,
				column: location.column,
			),
			message: message,
		)
	}
}

/// An error that reports itself as compiler-formatted diagnostics located in the user’s source.
/// `SafeDITool` prints `description` to standard error and exits non-zero rather than letting
/// ArgumentParser print the text behind an `Error:` prefix, which would hide the location from build tools.
public protocol SourceLocatedError: Error, CustomStringConvertible {
	/// The diagnostics describing this error, in the order they are printed.
	var sourceDiagnostics: [SourceDiagnostic] { get }
}

extension SourceLocatedError {
	public var description: String {
		sourceDiagnostics.map(\.formatted).joined(separator: "\n")
	}
}
