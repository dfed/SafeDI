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
		location: Dependency.DeclarationLocation?,
		message: String,
		fixIts: [FixIt] = [],
	) {
		self.severity = severity
		self.location = location
		self.message = message
		self.fixIts = fixIts
	}

	/// A replacement the IDE can apply to resolve the diagnostic.
	///
	/// swift-build’s `GenericOutputParser` (`Sources/SWBCore/SpecImplementations/CommandLineToolSpec.swift`)
	/// scrapes build-tool output for `<path>:<line>:<column>-<line>:<column>: fixit: <replacement>` lines and
	/// attaches each one to the diagnostic on the line immediately before it – a fixit line that does not
	/// directly follow its diagnostic is dropped. The range’s end column is exclusive, and the replacement is
	/// read as a JSON string, so `formatted` escapes it. Xcode renders the result as an Apply button on the error.
	public struct FixIt: Hashable, Sendable {
		public init(range: Dependency.SourceRange, replacement: String) {
			self.range = range
			self.replacement = replacement
		}

		/// The source text to replace, in the file the diagnostic points at.
		public let range: Dependency.SourceRange
		/// The text to put in its place.
		public let replacement: String

		/// The fix-it formatted as swift-build reads it, for a range in the file at `filePath`.
		func formatted(inFileAt filePath: String) -> String {
			"\(filePath):\(range.startLine):\(range.startColumn)-\(range.endLine):\(range.endColumn): fixit: \(escapedReplacement)"
		}

		/// `replacement` escaped as the contents of a JSON string literal, which is how swift-build unescapes it.
		private var escapedReplacement: String {
			replacement
				.replacingOccurrences(of: "\\", with: "\\\\")
				.replacingOccurrences(of: "\"", with: "\\\"")
				.replacingOccurrences(of: "\n", with: "\\n")
				.replacingOccurrences(of: "\r", with: "\\r")
				.replacingOccurrences(of: "\t", with: "\\t")
		}
	}

	// MARK: Public

	public enum Severity: String, Hashable, Sendable {
		/// The problem itself. An error fails generation and is the first line printed for it.
		case error
		/// A problem that does not stop generation. `generate` returns warnings rather than throwing them,
		/// and `run()` prints them once generation succeeds.
		case warning
		/// Detail that accompanies an error at a *different* location, such as a cycle member’s declaration.
		/// A note never stands alone, and Xcode does not display notes from build-tool output, so a note must
		/// never carry information the user needs at the error’s own location – fold that into the error line.
		case note
	}

	/// Whether the diagnostic is the error itself or a note that adds detail, possibly at another location.
	public let severity: Severity
	/// Where the diagnostic points. `nil` when the declaration carries no location, which only values
	/// built without a file context (macro expansion) do; the generator never sees those.
	public let location: Dependency.DeclarationLocation?
	/// A single line of text. A newline would break the compiler format, so messages must not contain one.
	public let message: String
	/// Replacements the IDE can offer for this diagnostic, each within the file `location` names.
	/// Printed on the lines directly after it.
	public let fixIts: [FixIt]

	/// The diagnostic formatted as the Swift compiler would print it: `<path>:<line>:<column>: <severity>: <message>`
	/// followed by one `fixit:` line per fix-it, or `<severity>: <message>` without a location, which is the shape
	/// the compiler itself uses for location-less diagnostics. A fix-it edits the file its diagnostic points at,
	/// so a location-less diagnostic prints none.
	public var formatted: String {
		if let location {
			(["\(location.filePath):\(location.line):\(location.column): \(severity.rawValue): \(message)"]
				+ fixIts.map { $0.formatted(inFileAt: location.filePath) })
				.joined(separator: "\n")
		} else {
			"\(severity.rawValue): \(message)"
		}
	}

	/// Returns a copy whose file path, and so its fix-its' too, is `spelling` applied to this one's. Build tools
	/// attribute a diagnostic to a file by its path, so `generate` prints it as the build system spells the file.
	public func respellingFilePath(_ spelling: (String) -> String) -> SourceDiagnostic {
		SourceDiagnostic(
			severity: severity,
			location: location.map { location in
				Dependency.DeclarationLocation(
					filePath: spelling(location.filePath),
					line: location.line,
					column: location.column,
				)
			},
			message: message,
			fixIts: fixIts,
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

extension Dependency.DeclarationLocation: Comparable {
	public static func < (lhs: Dependency.DeclarationLocation, rhs: Dependency.DeclarationLocation) -> Bool {
		(lhs.filePath, lhs.line, lhs.column) < (rhs.filePath, rhs.line, rhs.column)
	}
}

extension SourceDiagnostic {
	/// Orders diagnostics by file, line, and column, with location-less diagnostics last and the message as the
	/// tiebreak, so a group of diagnostics prints in source order and never depends on collection order.
	public static func precedesInSourceOrder(_ lhs: SourceDiagnostic, _ rhs: SourceDiagnostic) -> Bool {
		switch (lhs.location, rhs.location) {
		case let (lhsLocation?, rhsLocation?):
			if lhsLocation == rhsLocation {
				lhs.message < rhs.message
			} else {
				lhsLocation < rhsLocation
			}
		case (.some, .none):
			true
		case (.none, .some):
			false
		case (.none, .none):
			lhs.message < rhs.message
		}
	}
}
