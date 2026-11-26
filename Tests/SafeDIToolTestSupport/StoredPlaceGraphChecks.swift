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

import SafeDICore
import SafeDIToolLibrary
import Testing

/// What every run of the multi-module harness checks of the place graphs a module info file holds.
enum StoredPlaceGraphChecks {
	/// A place graph a run computed and the graph a reader of the file it wrote decodes in its place, with what the
	/// two are the graph of, as an issue names it.
	struct Pair {
		let subject: String
		let computed: SeamSignature.Places?
		let read: SeamSignature.Places?
	}

	/// Records an issue for each place graph the module info file of the module named `moduleName` holds that does
	/// not read back as the graph its run computed. The checks that compare a graph's answers with the per-place walk
	/// run on the graph a run computed; this is what lets them stand for the graph a module above decodes too, for
	/// every multi-module test and every graph the fuzzer builds. Nothing turns it off.
	///
	/// Two graphs are compared as values, every stored property of each at every depth
	/// (`firstDifference(between:and:at:)`), not as the bytes a file holds of them: a property the file's layout left
	/// out would be missing from both encodings.
	static func expectGraphsReadBackAsComputed(_ pairs: [Pair], byRunOfModuleNamed moduleName: String, sourceLocation: SourceLocation) {
		for pair in pairs {
			if let difference = firstDifference(between: pair.read as Any, and: pair.computed as Any, at: "the places of \(pair.subject)") {
				Issue.record("A place graph the run of module `\(moduleName)` wrote reads back as another graph than the one it computed: \(difference)", sourceLocation: sourceLocation)
			}
		}
	}

	/// Records an issue for each seam whose place graph `file`, the module info file the run of the module named
	/// `moduleName` wrote, holds as another graph than the one of `computedSignatures`, the signatures that run computed
	/// (`Generate.Output.seamSignaturesWrittenToModuleInfo`), and for a file whose signatures do not decode.
	static func expectGraphsReadBackAsComputed(ofSeamSignatures computedSignatures: [StoredSeamSignature], in file: ModuleInfoFile, writtenByRunOfModuleNamed moduleName: String, sourceLocation: SourceLocation) {
		do {
			let readSignatures = try file.seamSignaturesReadBack
			let readBySeam = Dictionary(readSignatures.map { ($0.seamType, $0.signature?.places) }, uniquingKeysWith: { first, _ in first })
			let computedSeams = Set(computedSignatures.map(\.seamType))
			let pairs = computedSignatures.map { computed in
				Pair(subject: "seam `\(computed.seamType.asSource)`", computed: computed.signature?.places, read: readBySeam[computed.seamType] ?? nil)
			} + readSignatures.filter { !computedSeams.contains($0.seamType) }.map { read in
				Pair(subject: "seam `\(read.seamType.asSource)`", computed: nil, read: read.signature?.places)
			}
			expectGraphsReadBackAsComputed(pairs, byRunOfModuleNamed: moduleName, sourceLocation: sourceLocation)
		} catch {
			Issue.record("The seam signatures the run of module `\(moduleName)` wrote do not decode: \(error)", sourceLocation: sourceLocation)
		}
	}

	/// Records an issue for each public mock whose place graph `file`, the module info file the run of the module named
	/// `moduleName` wrote, holds as another graph than the one of `computedPlans`, the plans that run computed
	/// (`Generate.Output.publicMockPlansWrittenToModuleInfo`), for a plan the file holds that the run did not compute, and
	/// for a file whose plans do not decode. A plan the run computed and the file leaves out is none: a file holds no plan
	/// that nests more deeply than a reader reads (`ModulePublicMockPlans`).
	static func expectGraphsReadBackAsComputed(ofPublicMockPlans computedPlans: [StoredPublicMockPlan], in file: ModuleInfoFile, writtenByRunOfModuleNamed moduleName: String, sourceLocation: SourceLocation) {
		do {
			let computedByMockedType = Dictionary(computedPlans.map { ($0.mockedType, $0.places) }, uniquingKeysWith: { first, _ in first })
			let pairs = try file.publicMockPlansReadBack.map { read in
				Pair(subject: "the public mock of `\(read.mockedType.asSource)`", computed: computedByMockedType[read.mockedType], read: read.places)
			}
			expectGraphsReadBackAsComputed(pairs, byRunOfModuleNamed: moduleName, sourceLocation: sourceLocation)
		} catch {
			Issue.record("The public mock plans the run of module `\(moduleName)` wrote do not decode: \(error)", sourceLocation: sourceLocation)
		}
	}

	/// Where `read` first differs from `computed`, and how, or `nil` where they hold the same values: every stored
	/// property of each, at every depth, in the order they are stored, the members of a set or a dictionary in the order
	/// of their descriptions. A source position counts as absent, as a module info file holds none: `read` came from a
	/// file, and `computed` holds the positions of its module's own declarations.
	static func firstDifference(between read: Any, and computed: Any, at path: String) -> String? {
		switch (withoutPosition(read), withoutPosition(computed)) {
		case (nil, nil):
			return nil
		case let (read?, nil):
			return "\(path) is read as `\(read)`, and was computed as absent"
		case let (nil, computed?):
			return "\(path) is read as absent, and was computed as `\(computed)`"
		case let (read?, computed?):
			guard type(of: read) == type(of: computed) else {
				return "\(path) is read as a `\(type(of: read))`, and was computed as a `\(type(of: computed))`"
			}
			let readMirror = Mirror(reflecting: read)
			var readChildren = Array(readMirror.children)
			var computedChildren = Array(Mirror(reflecting: computed).children)
			guard readChildren.count == computedChildren.count else {
				return "\(path) is read with \(readChildren.count) members, and was computed with \(computedChildren.count)"
			}
			guard !readChildren.isEmpty else {
				return String(describing: read) == String(describing: computed) ? nil : "\(path) is read as `\(read)`, and was computed as `\(computed)`"
			}
			if readMirror.displayStyle == .set || readMirror.displayStyle == .dictionary {
				readChildren.sort { String(describing: $0.value) < String(describing: $1.value) }
				computedChildren.sort { String(describing: $0.value) < String(describing: $1.value) }
			}
			for (index, (readChild, computedChild)) in zip(readChildren, computedChildren).enumerated() {
				guard readChild.label == computedChild.label else {
					return "\(path) is read as `\(readChild.label ?? "")`, and was computed as `\(computedChild.label ?? "")`"
				}
				if let difference = firstDifference(between: readChild.value, and: computedChild.value, at: "\(path).\(readChild.label ?? String(index))") {
					return difference
				}
			}
			return nil
		}
	}

	/// `value` out of every optional that wraps it, or `nil` where an optional holds nothing or `value` is a source
	/// position.
	private static func withoutPosition(_ value: Any) -> Any? {
		var value = value
		while true {
			guard !(value is Dependency.DeclarationLocation), !(value is Dependency.SourceRange) else {
				return nil
			}
			let mirror = Mirror(reflecting: value)
			guard mirror.displayStyle == .optional else {
				return value
			}
			guard let wrapped = mirror.children.first?.value else {
				return nil
			}
			value = wrapped
		}
	}
}
