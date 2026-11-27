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

/// The labels each node's subtree reads from above it: `ReadsFromAbove` of labels, where a node hides every label it
/// binds from the nodes above it, whichever edge the read comes through. An edge of the fold: it interns the labels it is
/// given as dense IDs in the order it first meets them, and spells the IDs back.
struct LabelsReadFromAbove: Sendable {
	/// `own` gives the labels a node reads itself and `bound` the labels it binds, which hide those labels from the nodes
	/// above it; each is asked once per node.
	init(graph: OrderedGraph<some Hashable & Sendable>, own: (Int) -> [String], bound: (Int) -> Set<String>) {
		var idByLabel = [String: Int32]()
		var labels = [String]()
		func id(of label: String) -> Int32 {
			if let id = idByLabel[label] {
				return id
			}
			let id = Int32(labels.count)
			idByLabel[label] = id
			labels.append(label)
			return id
		}
		let ownByNode = graph.nodes.indices.map { own($0).map(id(of:)) }
		let boundByNode = graph.nodes.indices.map { bound($0).sorted().map(id(of:)) }
		let ownRows = BitRows(rowCount: graph.nodes.count, columnCount: labels.count) { index, insert in
			ownByNode[index].forEach(insert)
		}
		let boundRows = BitRows(rowCount: graph.nodes.count, columnCount: labels.count) { index, insert in
			boundByNode[index].forEach(insert)
		}
		reads = ReadsFromAbove(graph: graph, own: ownRows, hidden: boundRows)
		self.labels = labels
	}

	/// The labels the node's subtree reads from above it, in the order the labels were first given.
	func labels(of index: Int) -> [String] {
		reads.reads(of: index).map { labels[Int($0)] }
	}

	/// The words the fold holds and the words it read, for a test to count how each grows.
	var wordCount: Int {
		reads.rows.wordCount
	}

	var work: Int {
		reads.work
	}

	private let reads: ReadsFromAbove
	private let labels: [String]
}
