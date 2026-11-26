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

/// For each node of a graph, the labels its subtree reads from above it: the labels the node reads itself, and each
/// label a node it has an edge to reads from above that the node does not bind. The least sets that satisfy that rule,
/// so a node on a cycle reads what every node of its cycle reads and none between binds.
///
/// A node's labels are in a fixed order: its own first, as given, then those of each edge's target, in edge order and the
/// target's order, each label once. Inside a cycle the targets' labels are taken in passes over the cycle's nodes in
/// position order until a pass adds none, so the order follows the graph's order alone.
///
/// Computed once, a component at a time, each after every component it reaches, and never changed. It holds one array of
/// labels per node for as long as its owner keeps it.
struct LabelsReadFromAbove: Sendable {
	/// `own` gives the labels a node reads itself, in the order it reads them, and `bound` the labels it binds, which hide
	/// those labels from the nodes above it; each is asked once per node. `boundAlong` gives the labels a node binds along
	/// one of its edges alone, by the edge's position among the node's edges, which hide those labels from the nodes above
	/// it in what that edge's target reads; it is asked once per edge.
	init(graph: OrderedGraph<some Hashable & Sendable>, own: (Int) -> [String], bound: (Int) -> Set<String>, boundAlong: (_ node: Int, _ edge: Int) -> Set<String> = { _, _ in [] }) {
		var labelsByNode = [[String]](repeating: [], count: graph.nodes.count)
		var labelSetByNode = [Set<String>](repeating: [], count: graph.nodes.count)
		var boundByNode = [Set<String>](repeating: [], count: graph.nodes.count)
		var boundAlongByNode = [[Set<String>]](repeating: [], count: graph.nodes.count)
		var nodesByComponent = [[Int]](repeating: [], count: (graph.componentByNode.max() ?? 0) + 1)
		for index in graph.nodes.indices {
			nodesByComponent[graph.componentByNode[index]].append(index)
			boundByNode[index] = bound(index)
			boundAlongByNode[index] = graph.edges(from: index).indices.map { boundAlong(index, $0) }
			for label in own(index) where labelSetByNode[index].insert(label).inserted {
				labelsByNode[index].append(label)
			}
		}
		// A component's number is lower than that of every component that reaches it, so every target outside the
		// component is complete when the component starts.
		for nodes in nodesByComponent {
			var changed = true
			while changed {
				changed = false
				for index in nodes {
					for (edge, target) in graph.edges(from: index).enumerated() {
						for label in labelsByNode[target] where !boundByNode[index].contains(label) && !boundAlongByNode[index][edge].contains(label) && labelSetByNode[index].insert(label).inserted {
							labelsByNode[index].append(label)
							changed = true
						}
					}
				}
			}
		}
		self.labelsByNode = labelsByNode
	}

	/// The labels the node's subtree reads from above it, in the order the type describes.
	func labels(of index: Int) -> [String] {
		labelsByNode[index]
	}

	private let labelsByNode: [[String]]
}

/// What the tests read of the validation walk's answers to the same question: set by the tests, never by the tool.
public enum LabelsReadFromAboveObservation {
	/// Called once per scope the validation walk asks `labelsReadFromAbove(by:)` of, with the scope's type, the labels the
	/// walk remembered for it, and the least sets the rule has, found a component at a time (`LabelsReadFromAbove`) and by
	/// passes over every scope it reaches until none adds a label, each sorted.
	@TaskLocal public static var observer: (@Sendable (_ type: String, _ remembered: [String], _ byComponent: [String], _ byPasses: [String]) -> Void)?
}
