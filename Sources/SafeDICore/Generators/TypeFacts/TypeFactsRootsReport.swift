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
			Node(
				description: graph.description(ofNode: index),
				kind: "\(graph.kinds[index])",
				construction: "\(graph.constructions[index])",
				cycleKey: graph.cycleKey(ofNode: index),
				cycleKeyID: Int(graph.cycleIDs[index]),
				edges: graph.graph.edges(from: index).map(Int.init),
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
		for index in graph.graph.nodes.indices where !graph.isFrame(index) {
			let declaration = DeclarationID(index)
			let reads = graph.reads(of: declaration)
			let ownReceives = TypeFactsGraph.ownReceives(of: graph.graph.nodes[index].scope)
			for (receive, ownReceive) in zip(graph.receives(of: declaration), ownReceives) {
				var line = "\(graph.description(ofNode: index)): \(receive.isRequired ? "required" : "only if available") \(graph.readDescription(receive.read))"
				if let alias = ownReceive.alias {
					line += " through \(alias.asSource)"
				}
				line += " accepts [\(TypeFactsGraph.acceptedProperties(of: ownReceive).map(\.asSource).joined(separator: ", "))] ="
				// A node's own reads are among its subtree's reads from above, which its answer sets are parallel to.
				let answers = reads.firstIndex(of: receive.read).map { graph.answers(ofReadAt: $0 - reads.startIndex, of: declaration) } ?? []
				for (position, answer) in zip(answers.indices, answers) {
					let isProvided = graph.acceptedProperties(of: receive).contains { graph.provides(answer, $0) }
					let route = graph.answerSets?.firstRoute(toAnswerAt: position, in: graph.graph).map(graph.description(ofNode:)) ?? []
					line += "\(position == answers.startIndex ? "" : ";") \(answer >= 0 ? graph.answerTexts[Int(answer)] : "none") (\(isProvided ? "provided" : "not provided")) along \(route.joined(separator: " > "))"
				}
				receives.append(line)
			}
		}
		self.receives = receives
		columnElementCount = graph.columnElementCount
		readCount = graph.readColumn.count
		edgeCount = graph.graph.edgeCount
		answerCount = graph.answerSets?.answers.count ?? 0
		largestAnswerSetCount = graph.answerSets.map { sets in sets.offsets.indices.dropLast().map { sets.answers(ofReadAt: $0).count }.max() ?? 0 } ?? 0
		answerStepCount = graph.answerSets?.stepCount ?? 0
		internedForWorldCount = internedCountAfter - internedCountBefore
	}

	/// The graph as text, a line per node (`TypeFactsGraph.projection`): node 0, the frames, and the declarations.
	public let projection: String
	/// The world as every track reads it (`TypeFactsWorld`), a line per declaration, with ` frame` after the position of
	/// each node that stands for no declaration, then a line per variant. It prints the run's IDs, which differ between
	/// runs that intern in different orders.
	public let world: String
	/// What the world holds of one node, named as `TypeFactsReport.Node` names what a validated world holds of it. It
	/// has none of what only a validated tree has: no edge facts, bindings, parents or union facts.
	public struct Node: Sendable {
		public let description: String
		/// The node's kind (`TypeFactsKind`).
		public let kind: String
		/// How the node's type comes to exist (`TypeFactsConstruction`).
		public let construction: String
		/// What a place of the node closes a cycle on, as cycle validation sees its property.
		public let cycleKey: String
		/// The node's cycle identity (A4), which two nodes of one `cycleKey` share. A leaf's is its own, as is that of a
		/// node that stands for no declaration.
		public let cycleKeyID: Int
		/// The positions of the nodes its edges lead to, in edge order.
		public let edges: [Int]
		public let isOnCycle: Bool
		/// What the node's subtree reads from above it, as `Read` descriptions.
		public let readsFromAbove: [String]
		/// The nodes from node 0 to this one on the first route a walk of the edges in order finds.
		public let firstRoute: [Int]
	}

	/// Each node by position: node 0, the frames and the declarations. A frame's one edge leads to its root's
	/// declaration, and nothing above a frame is read.
	public let nodes: [Node]
	/// How many variants each node has, by node position: one per family it is built in, whatever its reads are answered.
	public let variantCountsByNode: [Int]
	/// The variant each root's body is, in the roots' order.
	public let rootVariants: [Int]
	/// Each variant's node.
	public let variantNodes: [Int]
	/// The variant each edge of a variant's node calls, in edge order.
	public let variantCalls: [[Int]]
	/// A line per receive of each node's own type, in node then declaration order: the declaration, the receive's read,
	/// the alias it is read through, the properties that fulfill it, and each answer some route hands the node for it,
	/// with whether that answer provides one of them and the route the world keeps as the answer's witness
	/// (`TypeFactsAnswerSets.firstRoute(toAnswerAt:in:)`). Every name is spelled, so the lines are the same whatever
	/// order the run interns in.
	public let receives: [String]
	/// How many reads from above the world's nodes hold together: a read of each node whose subtree makes it.
	public let readCount: Int
	public let edgeCount: Int
	/// How many answers the world's answer sets hold together: for each read of each node, each answer some route hands
	/// it.
	public let answerCount: Int
	/// How many answers the largest set holds: the most answers the routes to one node hand one of its reads.
	public let largestAnswerSetCount: Int
	/// How many times the answer sets' fold took an answer to an edge.
	public let answerStepCount: Int
	/// The 32-bit elements of the world's columns.
	public let columnElementCount: Int
	/// How many values the world's build interned that the run did not hold: the forms and accepted properties no
	/// declaration spells.
	public let internedForWorldCount: Int
}
