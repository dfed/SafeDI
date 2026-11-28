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
/// It holds each shared node's domain (`TypeKeyLayout.Domain`), structural key facts and declared statements, for as long as the worlds that share the nodes are held:
/// from the build of the module's mock worlds until its last mock root is lowered.
final class NodeLayoutFacts: Sendable {
	/// The domain of each plan node of the shared records and the nodes beneath them, where every place beneath records
	/// what it builds.
	let domainsByNode: [PlanNode: TypeKeyLayout.Domain]
	/// What a body's structural key holds of each shared node's record alone, its statements' parts included, as ids of
	/// `keyParts` (`TypeKeyLayout.structuralKey(of:isInSendableFamily:parts:)`).
	let keyFactsByNode: [PlanNode: NodeKeyFacts]
	/// The ids of the parts `keyFactsByNode` holds, which every root's key reads first.
	let keyParts: FrozenStructuralKeyParts?
	/// What each shared node's body declares of its statements, which every root's walk declares in the node's view
	/// (`TypeKeyLayout.read(_:)`).
	let declaredChildrenByNode: [PlanNode: TypeKeyLayout.DeclaredChildren]

	/// The facts of `records`' nodes, each computed once.
	init(records: some Sequence<BuiltPlaceRecord>) {
		var layout = TypeKeyLayout()
		var parts = StructuralKeyParts()
		var keyFactsByNode = [PlanNode: NodeKeyFacts]()
		var declaredChildrenByNode = [PlanNode: TypeKeyLayout.DeclaredChildren]()
		// The type key lays out a body for a place that declares a function alone, and a shared record's children are shared
		// records too.
		for record in records where record.hasFunction {
			_ = layout.domain(of: record)
			var facts = TypeKeyLayout.keyFacts(of: record, parts: &parts)
			// A body's statements are its children's places, one each (`TypeKeyLayout.read(_:)`), and a body with a child that
			// records nothing is never laid out.
			let statements = TypeKeyLayout.statementCodes(of: record.children)
			declaredChildrenByNode[record.node] = TypeKeyLayout.DeclaredChildren(declaringStatementsOf: statements)
			let statementPartIDs = statements.compactMap(TypeKeyLayout.record(of:)).map { childRecord in
				parts.id(of: TypeKeyLayout.statementPart(of: childRecord, parts: &parts))
			}
			facts.statementPartIDs = statementPartIDs
			keyFactsByNode[record.node] = facts
		}
		domainsByNode = layout.domainsByNode
		self.keyFactsByNode = keyFactsByNode
		self.declaredChildrenByNode = declaredChildrenByNode
		keyParts = parts.frozenIDs
	}

	/// The facts of no node, for a layout that shares none. Made without a layout, whose own facts default to these.
	static let none = NodeLayoutFacts()

	private init() {
		domainsByNode = [:]
		keyFactsByNode = [:]
		declaredChildrenByNode = [:]
		keyParts = nil
	}
}

/// What a body's structural key holds of its place's record alone (`TypeKeyLayout.structuralKey(of:isInSendableFamily:parts:)`):
/// the spellings its header reads, and the ids of the parts after the header, in the key's order.
struct NodeKeyFacts: Sendable {
	let concreteType: String
	let forwardedProperties: [String]
	/// The ids of the leading statement's, the arguments', the construction's and the passed arguments' parts.
	let recordPartIDs: [Int]
	/// The id of each statement's part, in the body's order, where a snapshot holds them; `nil` where the body works them out.
	var statementPartIDs: [Int]?
}
