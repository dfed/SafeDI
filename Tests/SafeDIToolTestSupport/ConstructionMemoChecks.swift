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
import Testing

/// The memo oracle: every tree the tool creates is created twice more, with the construction memo and without it
/// (`ConstructionMemoOracle`), and the two must hold the same data on every path. A generator the memo shares between
/// places is described at each place it is reached from, so the comparison is per path, as the code generated from it
/// reads it.
enum ConstructionMemoChecks {
	/// An observer that records an issue for each tree whose builds with and without the memo differ, then hands both
	/// builds to `enclosingObserver`.
	static func recordingDifferences(
		handingOn enclosingObserver: (@Sendable (any Sendable, any Sendable) -> Void)?,
	) -> @Sendable (any Sendable, any Sendable) -> Void {
		{ treeBuiltWithMemo, treeBuiltWithoutMemo in
			if let difference = difference(between: treeBuiltWithMemo, and: treeBuiltWithoutMemo) {
				Issue.record(Comment(rawValue: difference))
			}
			enclosingObserver?(treeBuiltWithMemo, treeBuiltWithoutMemo)
		}
	}

	/// The first line at which the descriptions of the two trees differ, with the line of each, or `nil` when the two
	/// hold the same data on every path.
	static func difference(between treeBuiltWithMemo: Any, and treeBuiltWithoutMemo: Any) -> String? {
		var digests = Digests()
		guard digests.digest(of: treeBuiltWithMemo) != digests.digest(of: treeBuiltWithoutMemo) else { return nil }
		let withMemo = Description.text(of: treeBuiltWithMemo).split(separator: "\n", omittingEmptySubsequences: false)
		let withoutMemo = Description.text(of: treeBuiltWithoutMemo).split(separator: "\n", omittingEmptySubsequences: false)
		let index = zip(withMemo, withoutMemo).firstIndex { !$0.utf8.elementsEqual($1.utf8) } ?? min(withMemo.count, withoutMemo.count)
		let lineWithMemo = index < withMemo.count ? String(withMemo[index]) : "(end)"
		let lineWithoutMemo = index < withoutMemo.count ? String(withoutMemo[index]) : "(end)"
		return """
		The tree built with the construction memo differs from the tree built without it at line \(index + 1) of their descriptions:
		with the memo:    \(lineWithMemo)
		without the memo: \(lineWithoutMemo)
		"""
	}

	/// A value's data through reflection, private stored properties included, read the same way by `Digests` and
	/// `Description`: a `Scope` by its identity, since both builds read the same scope maps; a set's and a dictionary's
	/// elements in sorted order; and every other class instance by what it holds, each time it is reached.
	private enum Node {
		case scope(ObjectIdentifier)
		case leaf(String)
		case unordered(typeName: String, children: [(label: String?, value: Any)])
		case ordered(typeName: String, children: [(label: String?, value: Any)])

		init(_ value: Any) {
			if let object = value as? AnyObject, String(describing: type(of: object)) == "Scope" {
				self = .scope(ObjectIdentifier(object))
				return
			}
			let mirror = Mirror(reflecting: value)
			let children = mirror.children.map { (label: $0.label, value: $0.value) }
			let typeName = String(reflecting: type(of: value))
			if mirror.displayStyle == .set || mirror.displayStyle == .dictionary {
				self = .unordered(typeName: typeName, children: children)
			} else if children.isEmpty {
				self = .leaf("\(typeName)(\(String(reflecting: value)))")
			} else {
				self = .ordered(typeName: typeName, children: children)
			}
		}
	}

	/// A 128-bit digest of each value's data, memoized per class instance, which holds the same data wherever it is reached.
	private struct Digests {
		struct Digest: Hashable, Comparable {
			let high: Int
			let low: Int

			static func < (lhs: Self, rhs: Self) -> Bool {
				(lhs.high, lhs.low) < (rhs.high, rhs.low)
			}
		}

		mutating func digest(of value: Any) -> Digest {
			let object = Mirror(reflecting: value).displayStyle == .class ? value as AnyObject : nil
			if let object, let digest = digestsByObject[ObjectIdentifier(object)] {
				return digest
			}
			var high = Hasher()
			var low = Hasher()
			high.combine(0)
			low.combine(1)
			switch Node(value) {
			case let .scope(identifier):
				high.combine(identifier)
				low.combine(identifier)
			case let .leaf(text):
				high.combine(text)
				low.combine(text)
			case let .unordered(typeName, children):
				high.combine(typeName)
				low.combine(typeName)
				for childDigest in children.map({ digest(of: $0.value) }).sorted() {
					high.combine(childDigest)
					low.combine(childDigest)
				}
			case let .ordered(typeName, children):
				high.combine(typeName)
				low.combine(typeName)
				for child in children {
					let childDigest = digest(of: child.value)
					high.combine(child.label)
					low.combine(child.label)
					high.combine(childDigest)
					low.combine(childDigest)
				}
			}
			let digest = Digest(high: high.finalize(), low: low.finalize())
			if let object {
				digestsByObject[ObjectIdentifier(object)] = digest
			}
			return digest
		}

		private var digestsByObject = [ObjectIdentifier: Digest]()
	}

	/// The indented text a failure prints, one value per line, written only for trees whose digests differ.
	private enum Description {
		static func text(of value: Any) -> String {
			var lines = [String]()
			append(value, label: nil, depth: 0, to: &lines)
			return lines.joined(separator: "\n")
		}

		private static func append(_ value: Any, label: String?, depth: Int, to lines: inout [String]) {
			let prefix = String(repeating: "  ", count: depth) + (label.map { "\($0): " } ?? "")
			switch Node(value) {
			case let .scope(identifier):
				lines.append(prefix + "Scope \(identifier)")
			case let .leaf(text):
				lines.append(prefix + text)
			case let .unordered(typeName, children):
				lines.append(prefix + typeName)
				let texts = children.map { child in
					var childLines = [String]()
					append(child.value, label: nil, depth: depth + 1, to: &childLines)
					return childLines.joined(separator: "\n")
				}
				lines.append(contentsOf: texts.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) })
			case let .ordered(typeName, children):
				lines.append(prefix + typeName)
				for child in children {
					append(child.value, label: child.label, depth: depth + 1, to: &lines)
				}
			}
		}
	}
}
