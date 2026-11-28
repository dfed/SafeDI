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

/// What each declaration of a world's graph draws of its own in the DOT graph, and the DOT graph unfolded from it, one
/// line per edge of every path, as the tree of places draws it (`ScopeGenerator.generateDOT()`), byte for byte. The DOT
/// graph stays one line per path, and is unfolded from the declarations only when it is asked for: a path's lines are its
/// declaration's, and a path that repeats a declaration of its route closes a cycle there and draws only what its
/// declaration forwards.
///
/// Today the columns are read from a tree of places (`init(graph:tree:)`), the bridge until a declaration's order of
/// children is a fact of the graph; a declaration two places of which draw otherwise is recorded
/// (`declarationsDrawnPerPath`), since no column can stand for it. It holds a column per node until its owner drops it.
struct TypeFactsDOT {
	/// One edge a declaration draws, in the order it draws them.
	enum Item: Equatable {
		/// An edge to the node of another declaration of the graph, drawn with that declaration's lines beneath it: an
		/// instantiated edge, or a fill's (`isFill`), beneath which a path closes cycles only on the fills above it.
		case declaration(node: String, target: Int, isFill: Bool)
		/// An edge to a node no declaration of the graph stands for (an alias, a hole's site, a fill drawn where another
		/// place's stands for it), with the lines of what that node's place draws beneath it, or `nil` where it draws none.
		case leaf(node: String, lines: String?)

		/// Whether the item is a fill's edge.
		var isFill: Bool {
			switch self {
			case let .declaration(_, _, isFill):
				isFill
			case .leaf:
				false
			}
		}
	}

	/// What a declaration draws where a path builds its children.
	struct Column: Equatable {
		/// The declaration's own node.
		let node: String
		let items: [Item]
		/// The nodes of the properties the declaration forwards, sorted.
		let forwarded: [String]
	}

	/// What a declaration draws where a path closes a cycle on it, which builds no children: its node and what it forwards.
	struct ClosingColumn: Equatable {
		let node: String
		let forwarded: [String]
	}

	/// Reads each declaration's column from the places of `tree`, a tree of the world `graph` is the graph of, walking
	/// each place once on an explicit stack.
	init(graph: TypeFactsGraph, tree: ScopeGenerator) {
		self.graph = graph
		var columns = [Column?](repeating: nil, count: graph.graph.nodes.count)
		var closingColumns = [ClosingColumn?](repeating: nil, count: graph.graph.nodes.count)
		var declarationsDrawnPerPath = [String]()
		var places: [(generator: ScopeGenerator, node: Int)] = [(tree, 0)]
		while let (generator, node) = places.popLast() {
			let drawer = Self.drawer(of: generator)
			let drawing = drawer.dotDrawing
			if case let .property(_, _, _, _, isPropertyCycle, _) = drawer.scopeData, isPropertyCycle {
				let closing = ClosingColumn(node: drawing.node, forwarded: drawing.forwarded)
				if let existing = closingColumns[node], existing != closing {
					declarationsDrawnPerPath.append("\(graph.description(ofNode: node)) closing a cycle")
				} else {
					closingColumns[node] = closing
				}
				continue
			}
			let targetsByChild = Self.targetsByChild(of: drawer, node: node, graph: graph)
			var items = [Item]()
			var childPlaces = [(generator: ScopeGenerator, node: Int)]()
			for (drawnNode, drawnGenerator) in drawing.drawn {
				if let drawnGenerator, let target = targetsByChild[ObjectIdentifier(drawnGenerator)] {
					items.append(.declaration(node: drawnNode, target: target.node, isFill: target.isFill))
					childPlaces.append((drawnGenerator, target.node))
				} else {
					let lines = drawnGenerator.map(ScopeGenerator.drawnTree(of:))
					items.append(.leaf(node: drawnNode, lines: lines.flatMap { $0.isEmpty ? nil : $0 }))
				}
			}
			let column = Column(node: drawing.node, items: items, forwarded: drawing.forwarded)
			if let existing = columns[node] {
				if Self.column(existing, isWithoutFillsPassedOnOf: column) {
					columns[node] = column
				} else if existing != column, !Self.column(column, isWithoutFillsPassedOnOf: existing) {
					declarationsDrawnPerPath.append(graph.description(ofNode: node))
				}
			} else {
				columns[node] = column
			}
			places.append(contentsOf: childPlaces.reversed())
		}
		self.columns = columns
		self.closingColumns = closingColumns
		self.declarationsDrawnPerPath = declarationsDrawnPerPath
	}

	/// A fill edge on a path: the type of the call whose hole it fills, which any declaration of that type makes, and the
	/// node of the fill.
	private struct FillEdge: Equatable {
		let callScope: ObjectIdentifier
		let target: Int
	}

	let graph: TypeFactsGraph
	/// Each node's column, `nil` for a node no place builds the children of.
	let columns: [Column?]
	/// Each node's column where a place closes a cycle on it, `nil` for a node no place closes a cycle as.
	let closingColumns: [ClosingColumn?]
	/// The declarations two of whose places draw otherwise, which no one column stands for, in the order the walk met them.
	let declarationsDrawnPerPath: [String]

	/// The DOT lines of the world's tree, unfolded from the columns: a path that reaches a declaration whose cycle key a
	/// declaration of its route has closes a cycle there (`TypeFactsGraph.cycleKey(ofNode:)`), as a place does. A fill's
	/// tree is built with the stack of the seam or mock it fills, not the caller's path, so the route beneath a fill edge
	/// starts again from the fills above it: a place there closes a cycle on a fill of the same hole, or on what the fill's
	/// own tree builds; and a call beneath a fill of a call of its type, whichever declaration makes either, passes on
	/// every fill of the enclosing call rather than filling its holes again, so it draws no fill edges. Walked on an explicit stack, one frame per path.
	var unfolded: String {
		enum Frame {
			case declaration(node: Int, route: [Int], fills: [FillEdge])
			case lines(String)
		}
		var lines = [String]()
		var frames = [Frame.declaration(node: 0, route: [0], fills: [])]
		while let frame = frames.popLast() {
			switch frame {
			case let .lines(text):
				lines.append(text)
			case let .declaration(node, route, fills):
				let routeKeys = route.dropLast().map { graph.cycleKey(ofNode: $0) }
				if route.count > 1, routeKeys.contains(graph.cycleKey(ofNode: node)) {
					if let closing = closingColumns[node] {
						lines.append(contentsOf: closing.forwarded.map { "    \(closing.node) -- \($0)" })
					}
					continue
				}
				guard let column = columns[node] else { continue }
				var childFrames = [Frame]()
				for item in column.items {
					if item.isFill, fills.contains(where: { $0.callScope == graph.graph.nodes[node].key.record }) {
						continue
					}
					lines.append("    \(column.node) -- \(item.node)")
					switch item {
					case let .declaration(_, target, isFill):
						if isFill {
							// The fill's route holds only the fills above it of the same call's holes: a fill of another call's hole
							// of the same property and type closes no cycle on it.
							let callScope = graph.graph.nodes[node].key.record
							let routeOfFills = fills.filter { $0.callScope == callScope }.map(\.target)
							childFrames.append(.declaration(node: target, route: routeOfFills + [target], fills: fills + [FillEdge(callScope: callScope, target: target)]))
						} else {
							childFrames.append(.declaration(node: target, route: route + [target], fills: fills))
						}
					case let .leaf(_, text):
						if let text {
							childFrames.append(.lines(text))
						}
					}
				}
				lines.append(contentsOf: column.forwarded.map { "    \(column.node) -- \($0)" })
				frames.append(contentsOf: childFrames.reversed())
			}
		}
		return lines.joined(separator: "\n")
	}

	/// Whether `column` is `full` but for fill edges, as a call beneath a fill of its own hole draws, which passes that fill
	/// on (`unfolded`).
	private static func column(_ column: Column, isWithoutFillsPassedOnOf full: Column) -> Bool {
		column.node == full.node && column.forwarded == full.forwarded && column.items.count < full.items.count
			&& column.items.elementsEqual(full.items.lazy.filter { !$0.isFill })
	}

	/// The place that draws `generator`'s own edges: a fill draws as its child.
	private static func drawer(of generator: ScopeGenerator) -> ScopeGenerator {
		var drawer = generator
		while case .fill = drawer.scopeData, let child = drawer.propertiesToGenerate.first {
			drawer = child
		}
		return drawer
	}

	/// The node each child of `drawer` that builds a declaration of the graph stands for: its instantiated children, in
	/// order, are the node's instantiated edges, and each fill is the next fill edge for its hole's property.
	private static func targetsByChild(of drawer: ScopeGenerator, node: Int, graph: TypeFactsGraph) -> [ObjectIdentifier: (node: Int, isFill: Bool)] {
		let edges = graph.graph.edges(from: node).map(Int.init)
		let instantiatedEdgeCount = graph.edgeFacts(from: node).count { !$0.isFill }
		var nextInstantiatedEdge = 0
		var nextFillEdge = instantiatedEdgeCount
		var targetsByChild = [ObjectIdentifier: (node: Int, isFill: Bool)]()
		for child in drawer.propertiesToGenerate {
			switch child.scopeData {
			case .property:
				if nextInstantiatedEdge < instantiatedEdgeCount {
					targetsByChild[ObjectIdentifier(child)] = (edges[nextInstantiatedEdge], false)
					nextInstantiatedEdge += 1
				}
			case let .fill(hole, _):
				if let position = edges[nextFillEdge...].firstIndex(where: { graph.graph.nodes[$0].property == hole.property }) {
					targetsByChild[ObjectIdentifier(child)] = (edges[position], true)
					nextFillEdge = position + 1
				}
			case .root, .alias, .hole:
				break
			}
		}
		return targetsByChild
	}
}

extension TypeFactsDOT.Item {
	var node: String {
		switch self {
		case let .declaration(node, _, _), let .leaf(node, _):
			node
		}
	}
}
