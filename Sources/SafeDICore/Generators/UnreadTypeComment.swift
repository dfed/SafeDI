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

#if canImport(Darwin)
	import Darwin
#elseif canImport(Glibc)
	import Glibc
#elseif canImport(Musl)
	import Musl
#endif

/// The comment a file SafeDI generates carries, in a run that does not read every first-party module, naming the types
/// its `public` declarations name that no declaration SafeDI reads declares, which SafeDI counts as `public`
/// (`TypeAccessProof.unreadTypes(namedBy:mentionedFrom:)`): a `package` type of a first-party module that does not run
/// SafeDI is one of them, and the compiler reports the generated declaration that names it.
///
/// Each `public` declaration's emitter writes a marker above it naming its own such types; the emitter of the whole file
/// replaces the first marker with the one comment, naming every marker's types once, ordered by spelling, and removes
/// the others (`resolvingMarkers(in:)`). The comment is then above the first `public` declaration whose signature names
/// such a type, where the compiler's first error about one lands or comes before.
public struct UnreadTypeComment: Sendable {
	// MARK: Initialization

	/// - Parameters:
	///   - proof: The proof over the declarations the module's generated code is computed from.
	///   - mentioningModule: The module the code is generated in.
	public init(proof: TypeAccessProof, mentioningModule: TypeAccessProof.MentioningModule) {
		self.proof = proof
		self.mentioningModule = mentioningModule
	}

	// MARK: Public

	/// `code`, a generated file's body, with its first marker replaced by the comment naming every marker's types, and
	/// every other marker removed. `code` unchanged when it holds no marker.
	///
	/// Reads `code` as UTF-8 bytes in one pass, since every generated file passes through here and almost none holds a
	/// marker. Each byte a marker is made of, and the line break and indentation around it, is ASCII.
	public static func resolvingMarkers(in code: String) -> String {
		var code = code
		let resolvedCode: String? = code.withUTF8 { bytes in
			let markerLines = markerLines(in: bytes)
			guard let firstMarkerLine = markerLines.first else { return nil }
			var typeNames = Set<String>()
			for markerLine in markerLines {
				for typeName in bytes[markerLine.markerStart + markerPrefixBytes.count..<markerLine.lineEnd].split(separator: markerSeparatorByte) {
					typeNames.insert(String(decoding: typeName, as: UTF8.self))
				}
			}
			var resolvedBytes = [UInt8]()
			resolvedBytes.reserveCapacity(bytes.count)
			// The first marker line keeps its indentation, and the comment takes the marker's place.
			resolvedBytes.append(contentsOf: bytes[..<firstMarkerLine.markerStart])
			resolvedBytes.append(contentsOf: comment(naming: typeNames.sorted()).utf8)
			var copiedEnd = firstMarkerLine.lineEnd
			// Every other marker line goes with the line break before it, which each has, since the first marker line
			// comes before it.
			for markerLine in markerLines.dropFirst() {
				resolvedBytes.append(contentsOf: bytes[copiedEnd..<markerLine.lineStart - 1])
				copiedEnd = markerLine.lineEnd
			}
			resolvedBytes.append(contentsOf: bytes[copiedEnd...])
			return String(decoding: resolvedBytes, as: UTF8.self)
		}
		return resolvedCode ?? code
	}

	// MARK: Internal

	/// The marker line above a `public` declaration whose signature names `types`, indented by `indent`, which names the
	/// types among them that SafeDI counts as `public` because it reads no declaration of them; `nil` when there is none.
	func markerLine(namedBy types: [TypeDescription], indent: String) -> String? {
		let unreadTypes = proof.unreadTypes(namedBy: types, mentionedFrom: mentioningModule)
		guard !unreadTypes.isEmpty else { return nil }
		return indent + Self.markerPrefix + unreadTypes.map(\.asSource).joined(separator: String(Self.markerSeparator))
	}

	// MARK: Private

	private let proof: TypeAccessProof
	private let mentioningModule: TypeAccessProof.MentioningModule

	/// What begins a marker line after its indentation: a control character no generated code holds.
	private static let markerPrefix = "\u{1}UnreadTypes\u{1}"
	/// What separates the type names a marker lists.
	private static let markerSeparator: Character = "\u{1}"
	/// `markerPrefix` as UTF-8 bytes.
	private static let markerPrefixBytes = Array(markerPrefix.utf8)
	/// `markerSeparator` as its one UTF-8 byte, which also begins `markerPrefix`.
	private static let markerSeparatorByte = UInt8(ascii: "\u{1}")
	private static let lineBreak = UInt8(ascii: "\n")
	private static let space = UInt8(ascii: " ")
	private static let tab = UInt8(ascii: "\t")

	/// Where a marker line lies in a generated file's UTF-8 bytes.
	private struct MarkerLine {
		/// The index of the line's first byte.
		let lineStart: Int
		/// The index of the marker's first byte, after the line's indentation.
		let markerStart: Int
		/// The index of the line break that ends the line, or the number of bytes when the line ends the file.
		let lineEnd: Int
	}

	/// The marker lines of `bytes`, a generated file's UTF-8 bytes, in order: each line that begins with `markerPrefix`
	/// after spaces and tabs.
	private static func markerLines(in bytes: UnsafeBufferPointer<UInt8>) -> [MarkerLine] {
		var markerLines = [MarkerLine]()
		var searchStart = 0
		// Only a line that holds the control character `markerPrefix` begins with can be a marker line.
		while let controlCharacterIndex = firstIndex(of: markerSeparatorByte, in: bytes, from: searchStart) {
			let lineStart = bytes[..<controlCharacterIndex].lastIndex(of: lineBreak).map { $0 + 1 } ?? 0
			let lineEnd = bytes[controlCharacterIndex...].firstIndex(of: lineBreak) ?? bytes.count
			// The line's first control character begins its marker when only indentation comes before it.
			if bytes[lineStart..<controlCharacterIndex].allSatisfy({ $0 == space || $0 == tab }),
			   bytes[controlCharacterIndex..<lineEnd].starts(with: markerPrefixBytes)
			{
				markerLines.append(MarkerLine(lineStart: lineStart, markerStart: controlCharacterIndex, lineEnd: lineEnd))
			}
			searchStart = lineEnd
		}
		return markerLines
	}

	/// The index of the first `byte` in `bytes` at or after `start`, found by `memchr(3)`, which reads many bytes at once.
	private static func firstIndex(of byte: UInt8, in bytes: UnsafeBufferPointer<UInt8>, from start: Int) -> Int? {
		guard let baseAddress = bytes.baseAddress,
		      let found = memchr(baseAddress + start, Int32(byte), bytes.count - start)
		else { return nil }
		return UnsafeRawPointer(baseAddress).distance(to: UnsafeRawPointer(found))
	}

	/// The comment naming `typeNames`, each a type's spelling.
	private static func comment(naming typeNames: [String]) -> String {
		let names = typeNames.map { "`\($0)`" }
		return if names.count == 1, let name = names.first {
			"// SafeDI counts \(name) as `public`: no module it reads declares it narrower. If \(name) is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies."
		} else {
			"// SafeDI counts \(names.joinedAsList) as `public`: no module it reads declares them narrower. If one is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies."
		}
	}
}
