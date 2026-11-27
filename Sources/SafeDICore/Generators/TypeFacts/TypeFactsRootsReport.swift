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

/// The world of every root of one validation call, built before the walk validates any of them
/// (`TypeFactsGraph.init(roots:intern:)`), as text for a test to read. Made only where a test observes it
/// (`ValidationWalkObservation.unvalidatedWorld`), never by the tool.
public struct TypeFactsRootsReport: Sendable {
	init(_ graph: TypeFactsGraph, internedCountBefore: Int, internedCountAfter: Int) {
		projection = graph.projection
		world = TypeFactsReport.projection(of: graph) { graph.isFrame(Int($0)) ? " frame" : "" }
		nodes = graph.graph.nodes.indices.map { index in
			TypeFactsReport.Node(
				description: graph.description(ofNode: index),
				construction: "\(graph.constructions[index])",
				cycleKey: graph.cycleKey(ofNode: index),
				edges: graph.graph.edges(from: index).map(Int.init),
				instantiatedEdgeCount: Int(graph.instantiatedEdgeCounts[index]),
				isOnCycle: graph.graph.isOnCycle(index),
				readsFromAbove: graph.reads.reads(of: index).map(graph.readDescription),
				firstRoute: graph.graph.firstRoute(to: index),
			)
		}
		var variantCounts = [Int](repeating: 0, count: graph.declarationCount)
		for variant in 0..<graph.variantCount {
			variantCounts[Int(graph.declaration(of: VariantID(variant)))] += 1
		}
		variantCountsByNode = variantCounts
		rootVariants = (0..<graph.rootCount).map { Int(graph.rootVariant($0)) }
		variantNodes = (0..<graph.variantCount).map { Int(graph.declaration(of: VariantID($0))) }
		variantCalls = (0..<graph.variantCount).map { graph.calls(of: VariantID($0)).map(Int.init) }
		var receives = [String]()
		for variant in 0..<graph.variantCount {
			let declaration = graph.declaration(of: VariantID(variant))
			let reads = graph.reads(of: declaration)
			let keys = graph.keys(of: VariantID(variant))
			let ownReceives = graph.isFrame(Int(declaration)) ? [] : TypeFactsGraph.ownReceives(of: graph.graph.nodes[Int(declaration)].scope.identity)
			for (receive, ownReceive) in zip(graph.receives(of: declaration), ownReceives) {
				// A node's own reads are among its subtree's reads from above, which its keys are parallel to.
				let answer = reads.firstIndex(of: receive.read).map { keys[keys.startIndex + ($0 - reads.startIndex)] } ?? -1
				var line = "v\(variant) \(graph.description(ofNode: Int(declaration))): \(receive.isRequired ? "required" : "only if available") \(graph.readDescription(receive.read))"
				if let alias = ownReceive.alias {
					line += " through \(alias.asSource)"
				}
				line += " accepts [\(TypeFactsGraph.acceptedProperties(of: ownReceive).map(\.asSource).joined(separator: ", "))]"
				line += " = \(answer >= 0 ? graph.answerTexts[Int(answer)] : "none")"
				line += graph.acceptedProperties(of: receive).contains { graph.provides(answer, $0) } ? ", provided" : ", not provided"
				receives.append(line)
			}
		}
		self.receives = receives
		columnElementCount = graph.columnElementCount
		internedForWorldCount = internedCountAfter - internedCountBefore
	}

	/// The graph as text, a line per node (`TypeFactsGraph.projection`): node 0, the frames, and the declarations.
	public let projection: String
	/// The world as every track reads it (`TypeFactsWorld`), a line per declaration, with ` frame` after the position of
	/// each node that stands for no declaration, then a line per variant. It prints the run's IDs, which differ between
	/// runs that intern in different orders.
	public let world: String
	/// Each node as `TypeFactsReport` describes one, by position: node 0, the frames and the declarations. A frame's
	/// one edge leads to its root's declaration, and nothing above a frame is read.
	public let nodes: [TypeFactsReport.Node]
	/// How many variants each node has, by node position: one per vector of answers its subtree's reads are given.
	public let variantCountsByNode: [Int]
	/// The variant each root's body is, in the roots' order.
	public let rootVariants: [Int]
	/// Each variant's node.
	public let variantNodes: [Int]
	/// The variant each edge of a variant's node calls, in edge order.
	public let variantCalls: [[Int]]
	/// A line per receive of each variant's own type, in variant then declaration order: the variant, its declaration,
	/// the receive's read, the alias it is read through, the properties that fulfill it, its answer, and whether the
	/// answer provides one of them. Every name is spelled, so the lines are the same whatever order the run interns in.
	public let receives: [String]
	/// The 32-bit elements of the world's columns.
	public let columnElementCount: Int
	/// How many values the world's build interned that the run did not hold: the forms and accepted properties no
	/// declaration spells.
	public let internedForWorldCount: Int
}
