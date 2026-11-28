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
import Testing

/// The memo oracle: every tree the tool creates is created twice more, with the construction memo and without it
/// (`ConstructionMemoOracle`), and the two must hold the same data on every path. A generator the memo shares between
/// places is described at each place it is reached from, so the comparison is per path, as the code generated from it
/// reads it.
enum ConstructionMemoChecks {
	/// An observer that records an issue for each tree whose builds with and without the memo differ, then hands both
	/// builds to `enclosingObserver`.
	/// It also checks the places of the build without the memo against the tree's graph of per-type facts
	/// (`TypeFactsChecks`).
	static func recordingDifferences(
		handingOn enclosingObserver: TaskLocalFunction<@Sendable (any Sendable, any Sendable, TypeFactsReport) -> Void>?,
	) -> TaskLocalFunction<@Sendable (any Sendable, any Sendable, TypeFactsReport) -> Void> {
		TaskLocalFunction { treeBuiltWithMemo, treeBuiltWithoutMemo, typeFacts in
			if let difference = difference(between: treeBuiltWithMemo, and: treeBuiltWithoutMemo) {
				Issue.record(Comment(rawValue: difference))
			}
			TypeFactsChecks.check(typeFacts)
			TypeFactsDOTChecks.check(typeFacts)
			enclosingObserver?(treeBuiltWithMemo, treeBuiltWithoutMemo, typeFacts)
		}
	}

	/// The first line at which the descriptions of the two trees differ, with the line of each, or `nil` when the two
	/// hold the same data on every path.
	static func difference(between treeBuiltWithMemo: Any, and treeBuiltWithoutMemo: Any) -> String? {
		var comparison = Comparison()
		guard !comparison.holdSameData(treeBuiltWithMemo, treeBuiltWithoutMemo) else { return nil }
		let withMemo = Description.text(of: treeBuiltWithMemo).split(separator: "\n", omittingEmptySubsequences: false)
		let withoutMemo = Description.text(of: treeBuiltWithoutMemo).split(separator: "\n", omittingEmptySubsequences: false)
		let index = Array(zip(withMemo, withoutMemo)).firstIndex { !$0.utf8.elementsEqual($1.utf8) } ?? min(withMemo.count, withoutMemo.count)
		let lineWithMemo = index < withMemo.count ? String(withMemo[index]) : "(end)"
		let lineWithoutMemo = index < withoutMemo.count ? String(withoutMemo[index]) : "(end)"
		return """
		The tree built with the construction memo differs from the tree built without it at line \(index + 1) of their descriptions:
		with the memo:    \(lineWithMemo)
		without the memo: \(lineWithoutMemo)
		"""
	}

	/// A value's data through reflection, private stored properties included, read the same way by `Comparison`, `Digests`
	/// and `Description`: a `Scope` by its identity, since both builds read the same scope maps; a set's and a dictionary's
	/// elements in sorted order; and every other class instance by what it holds, each time it is reached.
	private enum Node {
		case scope(ObjectIdentifier)
		case leaf(String)
		case unordered(typeName: String, children: [(label: String?, value: Any)])
		/// - Parameter labelsVary: Whether two values of the type can have children of other labels: an enumeration's case,
		///   whose child's label names the case, and a value that makes its own mirror. Any other value's labels are its
		///   type's stored properties.
		case ordered(typeName: String, children: [(label: String?, value: Any)], labelsVary: Bool)

		/// - Parameter typeName: The name of `value`'s type, `String(reflecting:)` of it, which a caller may keep per type.
		init(_ value: Any, typeName: String) {
			if type(of: value) is AnyClass, typeName == "SafeDICore.Scope" {
				self = .scope(ObjectIdentifier(value as AnyObject))
				return
			}
			let mirror = Mirror(reflecting: value)
			let children = mirror.children.map { (label: $0.label, value: $0.value) }
			if mirror.displayStyle == .set || mirror.displayStyle == .dictionary {
				self = .unordered(typeName: typeName, children: children)
			} else if children.isEmpty {
				self = .leaf("\(typeName)(\(String(reflecting: value)))")
			} else {
				self = .ordered(typeName: typeName, children: children, labelsVary: mirror.displayStyle == .enum || value is CustomReflectable)
			}
		}
	}

	/// Whether two trees hold the same data on every path, read in step: the same type at each place; for a set or a
	/// dictionary, the same digests of their elements (`Digests`); otherwise the same `Node` with the same labels, whose
	/// children are compared in turn. Text is compared by its UTF-8 bytes, since `String`'s `==` reads canonically
	/// equivalent spellings as one, and generated code spells each as declared.
	///
	/// The walk keeps its own stack of the pairs it has yet to compare, so a tree of any depth takes no deeper a call stack
	/// than a leaf. Two values of one type whose inline bytes are equal are the same data, bit for bit: they hold the same
	/// inline fields and refer to the same storage – a string's, a collection's, an indirect enum's box, a class instance –
	/// which nothing changes while the trees are read and the trees keep alive. So a value both trees copied from one
	/// source, such as a scope's `Instantiable` or a seam's signature, is the same without being read, and one class
	/// instance at both places is too. A pair of class instances is compared once, wherever it is reached: the walk ends at
	/// the first difference, so a pair it has started comparing is the same if the trees are.
	private struct Comparison {
		mutating func holdSameData(_ value: Any, _ otherValue: Any) -> Bool {
			var pairs = [(value, otherValue)]
			while let (value, otherValue) = pairs.popLast() {
				let valueType = type(of: value)
				guard ObjectIdentifier(valueType) == ObjectIdentifier(type(of: otherValue)) else { return false }
				if valueType is AnyClass {
					let object = value as AnyObject
					let otherObject = otherValue as AnyObject
					let pair = ObjectPair(object: ObjectIdentifier(object), otherObject: ObjectIdentifier(otherObject))
					guard object !== otherObject, comparedObjectPairs[pair] == nil else { continue }
					comparedObjectPairs[pair] = (object, otherObject)
				} else {
					guard _openExistential(value, do: inlineBytes(of:)) != _openExistential(otherValue, do: inlineBytes(of:)) else { continue }
				}
				let typeName = digests.typeName(of: valueType)
				switch (Node(value, typeName: typeName), Node(otherValue, typeName: typeName)) {
				case let (.scope(identifier), .scope(otherIdentifier)):
					guard identifier == otherIdentifier else { return false }
				case let (.leaf(text), .leaf(otherText)):
					guard text.utf8.elementsEqual(otherText.utf8) else { return false }
				case let (.unordered(_, children), .unordered(_, otherChildren)):
					guard children.count == otherChildren.count,
					      Self.holdSameElements(children, otherChildren)
					      || children.map({ digests.digest(of: $0.value) }).sorted() == otherChildren.map({ digests.digest(of: $0.value) }).sorted()
					else { return false }
				case let (.ordered(_, children, labelsVary), .ordered(_, otherChildren, _)):
					guard children.count == otherChildren.count else { return false }
					for index in children.indices.reversed() {
						guard !labelsVary || Self.labelsMatch(children[index].label, otherChildren[index].label) else { return false }
						pairs.append((children[index].value, otherChildren[index].value))
					}
				case (.scope, _), (.leaf, _), (.unordered, _), (.ordered, _):
					return false
				}
			}
			return true
		}

		/// Whether each element of a set or a dictionary has an element of the same inline bytes in the other, of as many
		/// elements: no two elements of one hold the same bytes, which would make them equal, so the elements pair off.
		private static func holdSameElements(_ children: [(label: String?, value: Any)], _ otherChildren: [(label: String?, value: Any)]) -> Bool {
			var otherElements = Set<ElementBytes>()
			for otherChild in otherChildren {
				otherElements.insert(ElementBytes(of: otherChild.value))
			}
			for child in children where !otherElements.contains(ElementBytes(of: child.value)) {
				return false
			}
			return true
		}

		/// An element of a set or a dictionary, by its type and inline bytes.
		private struct ElementBytes: Hashable {
			init(of element: Any) {
				type = ObjectIdentifier(Swift.type(of: element))
				bytes = _openExistential(element, do: inlineBytes(of:))
			}

			private let type: ObjectIdentifier
			private let bytes: InlineBytes
		}

		private struct ObjectPair: Hashable {
			let object: ObjectIdentifier
			let otherObject: ObjectIdentifier
		}

		private static func labelsMatch(_ label: String?, _ otherLabel: String?) -> Bool {
			switch (label, otherLabel) {
			case let (.some(label), .some(otherLabel)):
				label.utf8.elementsEqual(otherLabel.utf8)
			case (.none, .none):
				true
			case (.some, .none), (.none, .some):
				false
			}
		}

		/// Each compared pair keeps both objects, so neither is freed and its address reused by another object while the
		/// comparison runs.
		private var comparedObjectPairs = [ObjectPair: (object: AnyObject, otherObject: AnyObject)]()
		private var digests = Digests()
	}

	/// A 128-bit digest of each value's data, for the elements of sets and dictionaries, whose order says nothing. Text is
	/// hashed by its UTF-8 bytes, as `Comparison` compares it.
	///
	/// The walk keeps its own stack of the values whose children it is digesting, so a value of any depth takes no deeper a
	/// call stack than a leaf. It digests each value once: a class instance by its identity, and any other value by its
	/// type and the bytes of its inline representation, which name the same data whenever they are equal (see
	/// `Comparison`). Each digested value is kept until the digests are done, so no storage it refers to is freed and its
	/// address reused by other data.
	private struct Digests {
		struct Digest: Hashable, Comparable {
			let high: Int
			let low: Int

			static func < (lhs: Self, rhs: Self) -> Bool {
				(lhs.high, lhs.low) < (rhs.high, rhs.low)
			}
		}

		mutating func digest(of value: Any) -> Digest {
			// The bottom frame holds only `value`, and is never finished: its one child's digest is the answer.
			var frames = [Frame(identity: nil, typeName: "", isUnordered: false, children: [(label: nil, value: value)])]
			while true {
				let index = frames.count - 1
				let childCount = frames[index].childDigests.count
				if childCount < frames[index].children.count {
					switch started(frames[index].children[childCount].value) {
					case let .digested(digest):
						frames[index].childDigests.append(digest)
					case let .frame(frame):
						frames.append(frame)
					}
				} else if index == 0 {
					return frames[0].childDigests[0]
				} else {
					let digest = finished(frames.removeLast())
					frames[index - 1].childDigests.append(digest)
				}
			}
		}

		/// A value whose children are being digested.
		private struct Frame {
			/// `nil` for the bottom frame only.
			let identity: Identity?
			let typeName: String
			let isUnordered: Bool
			let children: [(label: String?, value: Any)]
			var childDigests = [Digest]()
		}

		/// What a digest is kept by, holding what it identifies so that its storage outlives the digests.
		private enum Identity {
			case object(AnyObject)
			case value(ValueKey, Any)
		}

		/// A value that is no class instance, by its type and the bytes of its inline representation.
		private struct ValueKey: Hashable {
			let type: ObjectIdentifier
			let bytes: InlineBytes
		}

		private enum Start {
			case digested(Digest)
			case frame(Frame)
		}

		/// The value's digest when it is known or has no children to digest, or else the frame that digests its children.
		private mutating func started(_ value: Any) -> Start {
			let valueType = type(of: value)
			let identity: Identity
			if valueType is AnyClass {
				let object = value as AnyObject
				if let digest = digestsByObject[ObjectIdentifier(object)]?.digest {
					return .digested(digest)
				}
				identity = .object(object)
			} else {
				let key = ValueKey(type: ObjectIdentifier(valueType), bytes: _openExistential(value, do: inlineBytes(of:)))
				if let digest = digestsByValue[key]?.digest {
					return .digested(digest)
				}
				identity = .value(key, value)
			}
			var hasher = DigestHasher()
			switch Node(value, typeName: typeName(of: valueType)) {
			case let .scope(identifier):
				hasher.combine(identifier)
			case let .leaf(text):
				hasher.combineUTF8(of: text)
			case let .unordered(typeName, children):
				return .frame(Frame(identity: identity, typeName: typeName, isUnordered: true, children: children))
			case let .ordered(typeName, children, _):
				return .frame(Frame(identity: identity, typeName: typeName, isUnordered: false, children: children))
			}
			let digest = hasher.finalize()
			record(digest, for: identity)
			return .digested(digest)
		}

		/// The digest of a value whose children are all digested.
		private mutating func finished(_ frame: Frame) -> Digest {
			var hasher = DigestHasher()
			hasher.combineUTF8(of: frame.typeName)
			if frame.isUnordered {
				for childDigest in frame.childDigests.sorted() {
					hasher.combine(childDigest)
				}
			} else {
				for index in frame.children.indices {
					if let label = frame.children[index].label {
						hasher.combine(true)
						hasher.combineUTF8(of: label)
					} else {
						hasher.combine(false)
					}
					hasher.combine(frame.childDigests[index])
				}
			}
			let digest = hasher.finalize()
			record(digest, for: frame.identity)
			return digest
		}

		mutating func typeName(of valueType: Any.Type) -> String {
			let identifier = ObjectIdentifier(valueType)
			if let typeName = typeNames[identifier] {
				return typeName
			}
			let typeName = String(reflecting: valueType)
			typeNames[identifier] = typeName
			return typeName
		}

		private mutating func record(_ digest: Digest, for identity: Identity?) {
			switch identity {
			case let .object(object):
				digestsByObject[ObjectIdentifier(object)] = (digest, object)
			case let .value(key, value):
				digestsByValue[key] = (digest, value)
			case nil:
				break
			}
		}

		/// Two hashers seeded apart, whose results make a 128-bit digest.
		private struct DigestHasher {
			private var high = Hasher()
			private var low = Hasher()

			init() {
				high.combine(0)
				low.combine(1)
			}

			mutating func combine(_ value: some Hashable) {
				high.combine(value)
				low.combine(value)
			}

			/// Combines `text`'s UTF-8 bytes and their count, since `String`'s hash reads canonically equivalent spellings as one.
			mutating func combineUTF8(of text: String) {
				var text = text
				text.withUTF8 { bytes in
					high.combine(bytes.count)
					low.combine(bytes.count)
					high.combine(bytes: UnsafeRawBufferPointer(bytes))
					low.combine(bytes: UnsafeRawBufferPointer(bytes))
				}
			}

			func finalize() -> Digest {
				Digest(high: high.finalize(), low: low.finalize())
			}
		}

		private var digestsByObject = [ObjectIdentifier: (digest: Digest, object: AnyObject)]()
		private var digestsByValue = [ValueKey: (digest: Digest, value: Any)]()
		private var typeNames = [ObjectIdentifier: String]()
	}

	/// The indented text a failure prints, one value per line, written only for trees whose digests differ. Like `Digests`,
	/// it keeps its own stack, so a tree of any depth takes no deeper a call stack than a leaf.
	private enum Description {
		static func text(of value: Any) -> String {
			// The lines being written: the text's, and above it one buffer per element of each set or dictionary being
			// described, whose elements' texts are sorted before they are written.
			var buffers: [[String]] = [[]]
			var elementTexts = [[String]]()
			var steps: [Step] = [.describe(value, label: nil, depth: 0)]
			while let step = steps.popLast() {
				switch step {
				case let .describe(value, label, depth):
					let prefix = String(repeating: "  ", count: depth) + (label.map { "\($0): " } ?? "")
					switch Node(value, typeName: String(reflecting: type(of: value))) {
					case let .scope(identifier):
						buffers[buffers.count - 1].append(prefix + "Scope \(identifier)")
					case let .leaf(text):
						buffers[buffers.count - 1].append(prefix + text)
					case let .unordered(typeName, children):
						buffers[buffers.count - 1].append(prefix + typeName)
						steps.append(.endUnordered)
						for child in children.reversed() {
							steps.append(.endElement)
							steps.append(.describe(child.value, label: nil, depth: depth + 1))
							steps.append(.startElement)
						}
						elementTexts.append([])
					case let .ordered(typeName, children, _):
						buffers[buffers.count - 1].append(prefix + typeName)
						for child in children.reversed() {
							steps.append(.describe(child.value, label: child.label, depth: depth + 1))
						}
					}
				case .startElement:
					buffers.append([])
				case .endElement:
					let elementText = buffers.removeLast().joined(separator: "\n")
					elementTexts[elementTexts.count - 1].append(elementText)
				case .endUnordered:
					let texts = elementTexts.removeLast()
					buffers[buffers.count - 1].append(contentsOf: texts.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) })
				}
			}
			return buffers.joined().joined(separator: "\n")
		}

		private enum Step {
			case describe(Any, label: String?, depth: Int)
			case startElement
			case endElement
			case endUnordered
		}
	}
}

/// The bytes of a value's inline representation, without a heap allocation for a value of at most four words.
private struct InlineBytes: Hashable {
	/// The bytes, zero after `count`, when `count` is at most 32.
	private let words: (UInt64, UInt64, UInt64, UInt64)
	private let count: Int
	/// The bytes as words, zero after `count`, when `count` is over 32.
	private let longWords: [UInt64]?

	init(of value: some Any) {
		var words: (UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0)
		var longWords: [UInt64]?
		count = withUnsafeBytes(of: value) { bytes in
			if bytes.count <= MemoryLayout.size(ofValue: words) {
				withUnsafeMutableBytes(of: &words) { $0.copyMemory(from: bytes) }
			} else {
				var copiedWords = [UInt64](repeating: 0, count: (bytes.count + 7) / 8)
				copiedWords.withUnsafeMutableBytes { $0.copyMemory(from: bytes) }
				longWords = copiedWords
			}
			return bytes.count
		}
		self.words = words
		self.longWords = longWords
	}

	static func == (lhs: Self, rhs: Self) -> Bool {
		lhs.count == rhs.count && lhs.words == rhs.words && lhs.longWords == rhs.longWords
	}

	func hash(into hasher: inout Hasher) {
		hasher.combine(count)
		withUnsafeBytes(of: words) { hasher.combine(bytes: $0) }
		longWords?.withUnsafeBytes { hasher.combine(bytes: $0) }
	}
}

/// The inline bytes of the value an `Any` holds, for `_openExistential` to call. A free function: Swift 6.4.2 crashes
/// compiling `_openExistential` handed a static method or an initializer ("Fell off the end" in
/// `LocalArchetypeRequirementCollector`).
private func inlineBytes(of value: some Any) -> InlineBytes {
	InlineBytes(of: value)
}

extension ConstructionSharingSchedule {
	/// The schedule the graph fuzzer's second run of a graph follows: of three modes, chosen by the graph's seed so that
	/// every graph is judged by one and the corpus by all three, each place shares the newest alike candidate a discarded
	/// build of the same pass stored, takes a drawn candidate or builds again, or both. Running every graph under several
	/// schedules would cost a run of the tool each; `SAFEDI_SHARING_ORACLE_SCHEDULE=<n>` picks the schedule numbered `n`
	/// instead, so a dispatched run can sweep a corpus under twenty of them.
	public static func sharingOracleSchedule(forGraphSeed graphSeed: UInt64) -> ConstructionSharingSchedule {
		let scheduleNumber = ProcessInfo.processInfo.environment["SAFEDI_SHARING_ORACLE_SCHEDULE"].flatMap(UInt64.init) ?? graphSeed
		let scheduleSeed = mixed(graphSeed &+ scheduleNumber &* 0xD1B54A32D192ED03)
		switch scheduleNumber % 3 {
		case 0:
			return ConstructionSharingSchedule(seed: nil, offersLaterPlacesCandidates: true)
		case 1:
			return ConstructionSharingSchedule(seed: scheduleSeed, offersLaterPlacesCandidates: false)
		default:
			return ConstructionSharingSchedule(seed: scheduleSeed, offersLaterPlacesCandidates: true)
		}
	}
}
