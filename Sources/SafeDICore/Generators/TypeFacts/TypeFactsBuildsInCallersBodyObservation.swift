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

/// Where a test compares, for each root `generate` plans, the graph's answer of whether each edge builds its child in
/// its parent's body (`TypeFactsBuildsInCallersBody`) with whether the layout gave the place a function of its own
/// (`BuiltPlaceRecord.hasFunction`). The tool installs none.
public enum TypeFactsBuildsInCallersBodyObservation {
	@TaskLocal public static var comparesLayout: (@Sendable (TypeFactsBuildsInCallersBodyComparison) -> Void)?

	/// Where a root's body is handed to the comparison while a test observes it: set around the plan of one root, and read
	/// where the root writes its body (`ScopeGenerator.rootCode(of:writing:)`), before the type key lays its places out as
	/// text.
	@TaskLocal static var observesRootBody: (@Sendable (GeneratedCode) -> Void)?
}

/// One root's places, each with the graph's answer for the edge it is built along and the layout's record of it: every
/// place the plan records as built whose places above it are each built along an edge of the graph. A seam's root writes
/// its tree as text, so it holds no place. Made only where a test observes it.
public struct TypeFactsBuildsInCallersBodyComparison: Sendable {
	/// One place the plan records as built.
	public struct Place: Sendable {
		/// The declaration the place builds, as the graph spells it.
		public let declaration: String
		/// The graph's answer for the edge the place is built along: `inCallersBody`, `inOwnFunction` or `owed`.
		public let answer: String
		/// Whether the layout gave the place a builder function of its own.
		public let hasFunction: Bool
	}

	public let root: String
	public let places: [Place]
	/// The places recorded as built beneath a place mapped to a declaration whose edges hold none of the property they
	/// build, which no oracle compares.
	public let unmatchedPlaceCount: Int

	/// Maps each place of `plan`, the code of the root `rootScope` builds, to the edge of the root's graph it is built
	/// along: a place recorded as built beneath the place of a node is built along that node's edge whose child is built as
	/// the place's property, erased alike. A place that records nothing, closes a cycle or renames a value, and every place
	/// beneath one, maps to no edge.
	init(root: String, rootScope: ConstructionScope, plan: GeneratedCode) {
		let facts = TypeFactsGraph(root: rootScope, forMockGeneration: false)
		let graph = facts.graph
		var places = [Place]()
		var unmatchedPlaceCount = 0
		// Each level of the plan to visit, with the node of the nearest place above it, or `nil` beneath a place mapped to none.
		var pending: [(code: GeneratedCode, node: Int?)] = [(plan, 0)]
		while let (code, node) = pending.popLast() {
			switch code.node {
			case .text:
				break
			case let .sequence(codes), let .lines(codes):
				pending.append(contentsOf: codes.reversed().map { ($0, node) })
			case let .indented(inner, _), let .rootFunction(_, inner), let .sendableFunction(inner), let .omittingRootFunctions(inner, _):
				pending.append((inner, node))
			case let .place(placePlan):
				let record: BuiltPlaceRecord? = if case let .built(record) = placePlan.record {
					record
				} else {
					nil
				}
				// The edge the place is built along, where its parent's node is known and it is recorded as built.
				let edge = node.flatMap { node in
					record.flatMap { record in
						graph.edgeIndices(from: node).first { edge in
							let child = graph.nodes[Int(facts.edgeFacts[edge].child)]
							return !facts.edgeFacts[edge].isFill && child.key.leaf == .none && child.property == record.property && child.key.erasedToConcreteExistential == record.isErased
						}
					}
				}
				unmatchedPlaceCount += node != nil && record != nil && edge == nil ? 1 : 0
				if let edge, let record {
					places.append(Place(declaration: facts.description(ofNode: Int(facts.edgeFacts[edge].child)), answer: "\(facts.buildsInCallersBody.answers[edge])", hasFunction: record.hasFunction))
				}
				// A call that closes a cycle builds no place beneath it along the graph's edges.
				pending.append((placePlan.code, edge.flatMap { facts.edgeFacts[$0].isCallEdge ? nil : Int(facts.edgeFacts[$0].child) }))
			}
		}
		self.root = root
		self.places = places
		self.unmatchedPlaceCount = unmatchedPlaceCount
	}
}
