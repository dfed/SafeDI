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

/// What the type key reads of a plan node alone, whatever root lays it out, computed once for every node several roots
/// share (`MockWorldsTable.sharedRecords`) and handed to each root's layout (`TypeKeyBody.statements(ofRootBody:…)`), which
/// reads a node's facts here rather than working them out again for each root that holds the node.
///
/// It holds each shared node's domain (`TypeKeyLayout.Domain`) for as long as the worlds that share the nodes are held:
/// from the build of the module's mock worlds until its last mock root is lowered.
final class NodeLayoutFacts: Sendable {
	/// The domain of each plan node of the shared records and the nodes beneath them, where every place beneath records
	/// what it builds.
	let domainsByNode: [PlanNode: TypeKeyLayout.Domain]

	/// The facts of `records`' nodes, each computed once.
	init(records: some Sequence<BuiltPlaceRecord>) {
		var layout = TypeKeyLayout()
		// The type key works out the domain of a place that declares a function alone, and a shared record's children are
		// shared records too.
		for record in records where record.hasFunction {
			_ = layout.domain(of: record)
		}
		domainsByNode = layout.domainsByNode
	}

	/// The facts of no node, for a layout that shares none. Made without a layout, whose own facts default to these.
	static let none = NodeLayoutFacts(domainsByNode: [:])

	private init(domainsByNode: [PlanNode: TypeKeyLayout.Domain]) {
		self.domainsByNode = domainsByNode
	}
}
