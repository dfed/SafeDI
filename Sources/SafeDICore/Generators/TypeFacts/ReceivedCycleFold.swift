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

/// Decides, once for the trees of a validation and without walking any route, whether the walk of received properties
/// (`validateNoCycleInReceivedProperties`) can find anything at any place: a receive, or a receive of a type it
/// requires, of a value still being built. The walk stays the judge and the reporter wherever this answers that it may.
///
/// **It errs one way only**: it holds at least what the walk visits on every route, since it moves as the walk moves
/// and compares as the walk compares.
/// - The walk moves from a scope to each property it requires, as cycle validation sees it, and from such a property to
///   the scope of its type. Those are the edges from a scope's node and from a property's node here; the caller leaves a
///   property the walk never follows without a scope.
/// - The walk throws only where a property it reaches is the place's own property or an entry of the place's
///   instantiation stack. A stack holds the properties of the edges on one route to the place, so every entry is the
///   property of an edge that reaches the place in the graph, a route no tree takes included.
/// - The walk accepts, and does not follow, an instantiator still being built above the place, and a receive of the
///   place's own instantiator made by the place's own type. So an edge that builds an instantiator is asked only about
///   what its child reaches through a property it requires, or from a property a walk starts at.
/// - The walk that starts at the property a rename only if available is bound from starts at the scope that declares
///   the rename, with that scope's stack: the property is an edge from that place's node.
/// - The walk at a place judges a receive of an entry of its stack against the nearest declaration of the receive's
///   label above the place (`isFulfilledByNearerDeclaration`), which fulfills it where it declares the received property
///   and is nearer than the entry. A place's declarations are the nearest for the places it builds, so a place hides from
///   the places above it what the places it builds read of the properties it declares (`hiddenProperties`), never what
///   its own scope reads, which is judged against the declarations above it.
///
/// The second question is of the same shape: whether a tree an edge builds holds a type that requires a property, for
/// a required receive of a rename built inside the sibling the rename is fulfilled by.
///
/// One graph: a node per place (a scope as the trees build it), per scope as a received property's type, and per
/// property; its rows are `ReadsFromAbove` over a column per property reached and a column per property required as
/// declared, each property reading itself and nothing hidden. Its work grows with the words of the rows its edges
/// reach, never with the routes. It works on IDs only, and holds the graph and its rows until its owner drops it: one
/// call of the validation.
struct ReceivedCycleFold: Sendable {
	/// A property a scope instantiates, with the scope it builds.
	struct Edge: Equatable, Sendable {
		let parent: Int32
		let child: Int32
		/// The property the child is built as, as cycle validation sees it.
		let property: Int32
		/// Whether the property is an instantiator.
		let isBuilder: Bool
		/// Whether a tree validated for cycles reaches the edge's parent.
		let isJudged: Bool
	}

	/// A rename with the edge of its own scope that builds the sibling it may be fulfilled by.
	struct Rename: Equatable, Sendable {
		let edge: Int32
		/// The properties a receive of the rename can be declared as.
		let receivableProperties: [Int32]
	}

	struct Input: Sendable {
		/// How many properties the IDs below name.
		var propertyCount: Int
		/// The scopes the trees start at.
		var roots: [Int32]
		var edges: [Edge]
		/// For each scope, the properties it requires from above, as cycle validation sees them.
		var requiredProperties: [[Int32]]
		/// For each scope, the properties it requires from above as declared, of those a rename can be received as.
		var declaredRequiredProperties: [[Int32]]
		/// For each property, the scope the walk follows it to, or -1 where it follows it to none.
		var scopeOfProperty: [Int32]
		/// For each scope, the properties a walk starts at where the scope is built: what a rename only if available it
		/// declares is bound from.
		var walkStarts: [[Int32]]
		/// For each scope of the trees, the properties whose reads by the places it builds it fulfills for every entry of
		/// their stacks above it: those it declares of labels every declaration and read of which is that one property.
		var hiddenProperties: [[Int32]]
		var renames: [Rename]
	}

	init(_ input: Input) {
		var edgesByParent = [[Int32]](repeating: [], count: input.requiredProperties.count)
		for edge in input.edges {
			edgesByParent[Int(edge.parent)].append(edge.child)
		}
		let graph = OrderedGraph(root: Node.root) { (node: Node) -> [Node] in
			switch node {
			case .root:
				return input.roots.map { .place($0) }
			case let .place(scope):
				var targets = [Node.scope(scope)]
				targets.append(contentsOf: input.walkStarts[Int(scope)].map { .property($0) })
				targets.append(contentsOf: input.declaredRequiredProperties[Int(scope)].map { .declaredRequirement($0) })
				if input.hiddenProperties[Int(scope)].isEmpty {
					targets.append(contentsOf: edgesByParent[Int(scope)].map { .place($0) })
				} else {
					targets.append(.placesBuiltBy(scope))
				}
				return targets
			case let .placesBuiltBy(scope):
				return edgesByParent[Int(scope)].map { .place($0) }
			case let .scope(scope):
				return input.requiredProperties[Int(scope)].map { .property($0) }
			case let .property(property):
				let scope = input.scopeOfProperty[Int(property)]
				return scope >= 0 ? [.scope(scope)] : []
			case .declaredRequirement:
				return []
			}
		}
		let propertyCount = Int32(input.propertyCount)
		let own = BitRows(rowCount: graph.nodes.count, columnCount: input.propertyCount * 2) { index, insert in
			switch graph.nodes[index] {
			case .root, .place, .scope, .placesBuiltBy:
				break
			case let .property(property):
				insert(property)
			case let .declaredRequirement(property):
				insert(propertyCount + property)
			}
		}
		let hidden = BitRows(rowCount: graph.nodes.count, columnCount: input.propertyCount * 2) { index, insert in
			switch graph.nodes[index] {
			case .root, .place, .scope, .property, .declaredRequirement:
				break
			case let .placesBuiltBy(scope):
				for property in input.hiddenProperties[Int(scope)] {
					insert(property)
				}
			}
		}
		let rows = ReadsFromAbove(graph: graph, own: own, hidden: hidden).rows
		func reaches(_ property: Int32, from node: Node) -> Bool {
			graph.index(of: node).map { rows.contains(property, inRow: $0) } ?? false
		}

		edgeThatMayCloseCycle = input.edges.firstIndex { edge in
			guard edge.isJudged else {
				return false
			}
			if edge.isBuilder {
				return input.requiredProperties[Int(edge.child)].contains { requiredProperty in
					requiredProperty != edge.property
						&& input.scopeOfProperty[Int(requiredProperty)] >= 0
						&& reaches(edge.property, from: .scope(input.scopeOfProperty[Int(requiredProperty)]))
				} || input.walkStarts[Int(edge.child)].contains { reaches(edge.property, from: .property($0)) }
			} else {
				return reaches(edge.property, from: .place(edge.child))
			}
		}
		renameThatMayCloseCycle = input.renames.firstIndex { rename in
			let edge = input.edges[Int(rename.edge)]
			return edge.isJudged && rename.receivableProperties.contains { reaches(propertyCount + $0, from: .place(edge.child)) }
		}
	}

	/// The first edge the value or instantiator of which some place may receive while it is still being built, or `nil`
	/// where the walk of received properties can find nothing at any place.
	let edgeThatMayCloseCycle: Int?

	/// The first rename a required receive of which may be built inside the sibling the rename is fulfilled by.
	let renameThatMayCloseCycle: Int?

	private enum Node: Hashable, Sendable {
		case root
		/// A scope as the trees build it: its row holds what every place beneath it reaches.
		case place(Int32)
		/// A scope as the type of a received property: its row holds what a walk of its required properties reaches.
		case scope(Int32)
		case property(Int32)
		/// A property a place's scope requires as declared.
		case declaredRequirement(Int32)
		/// The places a place's scope builds, beneath its declarations: its row holds what they read that it does not hide.
		case placesBuiltBy(Int32)
	}
}
