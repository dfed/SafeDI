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


/// The properties being built above a place of a tree, innermost first, each with the concrete type it is built for and
/// the depth of the scope that put it on the stack (see `ConstructionContext`).
///
/// A scope's children share its stack: each pushes onto it without copying it, so a chain of n places holds n entries,
/// where a copy per place held n²/2. Its nodes are released through `DeferredRelease`, since a stack is as deep as the tree.
struct ConstructionStack: Sequence, Sendable {
	/// A property being built.
	struct Entry: Sendable {
		let property: Property
		let concreteType: TypeDescription
		/// The depth in the tree of the scope that put the entry on the stack, or -1 for the path of the seam whose hole the
		/// enclosing fill fills.
		let depth: Int
	}

	/// The empty stack.
	init() {}

	/// The stack of the path of the seam whose hole a fill fills: `properties` and `concreteTypes` innermost first, as
	/// `SeamSignature.Hole.fillPropertyStack` holds them, each with the depth -1.
	init(fillPathProperties properties: [Property], concreteTypes: [TypeDescription]) {
		for (property, concreteType) in zip(properties, concreteTypes).reversed() {
			self = pushing(property, concreteType: concreteType, depth: -1)
		}
	}

	/// How many entries the stack holds.
	var count: Int {
		innermost?.count ?? 0
	}

	/// This stack with `property`, built for `concreteType` by the scope at `depth`, on it, innermost.
	func pushing(_ property: Property, concreteType: TypeDescription, depth: Int) -> Self {
		var stack = Self()
		stack.innermost = Node(entry: Entry(property: property, concreteType: concreteType, depth: depth), outer: innermost)
		return stack
	}

	/// The innermost entry `isIncluded` admits, with its index, innermost first, and the entry just outside it.
	func innermostEntry(where isIncluded: (Entry) -> Bool) -> (entry: Entry, index: Int, outer: Entry?)? {
		var node = innermost
		var index = 0
		while let current = node, !isIncluded(current.entry) {
			node = current.outer
			index += 1
		}
		return node.map { ($0.entry, index, $0.outer?.entry) }
	}

	/// The properties of the entries, innermost first.
	var properties: [Property] {
		map(\.property)
	}

	/// The concrete types of the entries, innermost first.
	var concreteTypes: [TypeDescription] {
		map(\.concreteType)
	}

	func makeIterator() -> Iterator {
		Iterator(node: innermost)
	}

	/// Visits the entries innermost first.
	struct Iterator: IteratorProtocol {
		fileprivate var node: Node?

		mutating func next() -> Entry? {
			guard let node else { return nil }
			self.node = node.outer
			return node.entry
		}
	}

	/// An entry, and the entries outside it, which every stack pushed onto it shares.
	fileprivate final class Node: Sendable {
		init(entry: Entry, outer: Node?) {
			self.entry = entry
			count = (outer?.count ?? 0) + 1
			if count.isMultiple(of: Self.directlyReleasedRunLength) {
				directOuter = nil
				deferredOuter = DeferredReleaseSlot(outer.map { [$0] } ?? [])
			} else {
				directOuter = outer
				deferredOuter = DeferredReleaseSlot([])
			}
		}

		let entry: Entry
		/// How many entries this node and those outside it hold.
		let count: Int

		/// The entry just outside this one.
		var outer: Node? {
			directOuter ?? deferredOuter.value.first
		}

		/// How many nodes in a row release the node outside them directly. Releasing a node releases the run outside it
		/// recursively, so the run's length bounds that recursion; the node that ends a run hands its outer node to
		/// `DeferredRelease` instead, so releasing a chain of any depth never recurses deeper than one run. Deferring every
		/// node's release would cost an allocation and a thread-local lookup per node, which a shallow tree, holding many
		/// short stacks, pays for nothing.
		private static let directlyReleasedRunLength = 64

		/// The node outside this one, unless this node ends a run.
		private let directOuter: Node?
		/// The node outside this one when this node ends a run, and nothing otherwise.
		private let deferredOuter: DeferredReleaseSlot<[Node]>
	}

	private var innermost: Node?
}
