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

/// Whether each edge of a world's graph builds its child in line in its parent's own body, with no builder function of
/// the child's own and none opened around it: the outcome of the callee's fold that the outcomes fold reads
/// (`TypeFactsOutcomes.Input`'s `buildsInCallersBody`), decided from the child's declaration and the edge's facts.
///
/// The layout gives a constant no function exactly where its body would hold no statement (`BuilderBody.hasStatements`
/// in `ScopeGenerator`'s constant branch, which `BuiltPlaceRecord.hasFunction` records): its body's statements are the
/// code of its children, aliases and holes included, the member calls of the routes to places beneath it, the guard line
/// of a call of another module's seam, and the bindings of a mock fill's places. A child, an alias or a hole is an edge of
/// the declaration, and a member call or a place's binding is made only for a place beneath it, so a declaration built by
/// its own initializer with no edge has no statement, and one with an edge has one.
///
/// The answer reads only the child's declaration and the edge, so every variant of a node's declaration that calls the
/// child gets the same answer: the variants differ in what their reads are answered by, never in the child's statements.
/// Where the rule decides nothing it answers `owed`, never `inOwnFunction`: a call of a seam or of a public mock, a fill, a
/// construction function, a node beneath a fill (whose places' bindings the rule does not see), every node of a mock's
/// world, and an edge that opens a function, is in a loop of builders, or closes a cycle. Kept by the graph for as long as
/// its owner keeps the graph.
struct TypeFactsBuildsInCallersBody: Sendable {
	/// What the rule decides of one edge.
	enum Answer: UInt8, Sendable {
		/// The child is a constant built in line in the parent's body.
		case inCallersBody
		/// The child is a constant built in a builder function of its own.
		case inOwnFunction
		/// The rule decides nothing: the edge's call is judged as one made into a function of the child's own.
		case owed
	}

	/// Each edge's answer, parallel to the graph's edges.
	let answers: [Answer]

	init(
		graph: OrderedGraph<TypeFactsDeclaration>,
		kinds: [TypeFactsKind],
		constructions: [TypeFactsConstruction],
		edgeFacts: [TypeFactsEdge],
		forMockGeneration: Bool,
	) {
		// The nodes a fill builds, and every node beneath one, whose mock fill places can bind values the rule does not see.
		var isBeneathFill = [Bool](repeating: false, count: graph.nodes.count)
		var pending = [Int]()
		for edge in 0..<graph.edgeCount where edgeFacts[edge].isFill && !isBeneathFill[Int(edgeFacts[edge].child)] {
			isBeneathFill[Int(edgeFacts[edge].child)] = true
			pending.append(Int(edgeFacts[edge].child))
		}
		while let node = pending.popLast() {
			for target in graph.edges(from: node).map(Int.init) where !isBeneathFill[target] {
				isBeneathFill[target] = true
				pending.append(target)
			}
		}

		var answers = [Answer](repeating: .owed, count: graph.edgeCount)
		for edge in 0..<graph.edgeCount where !forMockGeneration {
			let facts = edgeFacts[edge]
			let child = Int(facts.child)
			answers[edge] = if facts.opens != .none || facts.loop >= 0 || facts.isCallEdge || isBeneathFill[child] {
				.owed
			} else {
				Self.answer(kind: kinds[child], construction: constructions[child], hasEdges: !graph.edgeIndices(from: child).isEmpty)
			}
		}
		self.answers = answers
	}

	/// The answer for a child of `kind`, built by `construction`, that has edges of its own where `hasEdges`, along an edge
	/// that opens nothing and closes no cycle.
	private static func answer(kind: TypeFactsKind, construction: TypeFactsConstruction, hasEdges: Bool) -> Answer {
		switch kind {
		case .constant:
			switch construction {
			case .initializer:
				hasEdges ? .inOwnFunction : .inCallersBody
			case .handWrittenMock, .seamCall, .publicMockCall, .constructionFunction, .fill:
				.owed
			}
		case .instantiator, .sendableInstantiator, .erasedInstantiator, .sendableErasedInstantiator, .lazy, .sendableLazy, .alias, .hole:
			.owed
		}
	}
}
