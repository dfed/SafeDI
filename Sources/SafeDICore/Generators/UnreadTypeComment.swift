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
	public static func resolvingMarkers(in code: String) -> String {
		guard code.contains(markerPrefix) else { return code }
		var lines = [String]()
		var typeNames = [String]()
		var commentLineIndex: Int?
		var commentIndent = ""
		for line in code.split(separator: "\n", omittingEmptySubsequences: false) {
			let trimmed = line.drop { $0 == " " || $0 == "\t" }
			guard trimmed.hasPrefix(markerPrefix) else {
				lines.append(String(line))
				continue
			}
			typeNames += trimmed.dropFirst(markerPrefix.count).split(separator: markerSeparator).map(String.init)
			if commentLineIndex == nil {
				commentLineIndex = lines.count
				commentIndent = String(line.prefix(line.count - trimmed.count))
				lines.append("")
			}
		}
		if let commentLineIndex {
			lines[commentLineIndex] = commentIndent + comment(naming: Array(Set(typeNames)).sorted())
		}
		return lines.joined(separator: "\n")
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

	/// The comment naming `typeNames`, each a type's spelling.
	private static func comment(naming typeNames: [String]) -> String {
		let names = typeNames.map { "`\($0)`" }
		return if names.count == 1, let name = names.first {
			"// SafeDI counts \(name) as `public`: no module it reads declares it narrower. If \(name) is `package` in a first-party module, run SafeDI on that module and list it among this module's SafeDI dependencies."
		} else {
			"// SafeDI counts \(names.joinedAsList) as `public`: no module it reads declares them narrower. If one is `package` in a first-party module, run SafeDI on that module and list it among this module's SafeDI dependencies."
		}
	}
}
