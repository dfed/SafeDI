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

/// The mock worlds' shared graph and its variants as a shared row's kind and record read them (`NodeKindSources`), by
/// the shared graph's positions and the shared variants' IDs: what every world that holds a row would read of its
/// subtree alike, read once for the run. A shareable declaration reaches no cycle (`MockWorldsTable.isShareable(_:)`), so
/// none is on one; a loop of builders it holds is wholly inside the shared graph, whose facts say what each member makes
/// again. It holds nothing of its own, only the two values it reads, for as long as `MockWorlds.build` holds it.
struct MockWorldsSharedSources: NodeKindSources, Sendable {
	let graph: MockWorldsSharedGraph
	let variants: MockWorldsSharedVariants

	func kind(of declaration: DeclarationID) -> TypeFactsKind {
		graph.facts.kinds[Int(declaration)]
	}

	func construction(of declaration: DeclarationID) -> TypeFactsConstruction {
		graph.facts.constructions[Int(declaration)]
	}

	func isOnCycle(_ declaration: DeclarationID) -> Bool {
		graph.graph.isOnCycle(Int(declaration))
	}

	func edges(from declaration: DeclarationID) -> ArraySlice<Int32> {
		graph.graph.edges(from: Int(declaration))
	}

	func edgeFacts(from declaration: DeclarationID) -> ArraySlice<TypeFactsEdge> {
		graph.facts.edgeFacts[graph.graph.edgeIndices(from: Int(declaration))]
	}

	func madeAgain(from declaration: DeclarationID) -> ArraySlice<Int32> {
		graph.facts.madeAgain?.targets(of: Int(declaration)) ?? []
	}

	var loopMembersSharedApart: [Int32] {
		graph.facts.loopMembersSharedApart
	}

	/// The variants `variant` makes again, after its calls, as a world's graph orders them (`madeAgainCalls(of:)`).
	func madeAgainCalls(of variant: VariantID) -> ArraySlice<VariantID> {
		variants.variants.madeAgainCallees(of: Int(variant))
	}

	func declaration(of variant: VariantID) -> DeclarationID {
		variants.variants.node(of: Int(variant))
	}

	func calls(of variant: VariantID) -> ArraySlice<VariantID> {
		variants.variants.callees(of: Int(variant))
	}

	func scope(of declaration: DeclarationID) -> ConstructionScope {
		graph.graph.nodes[Int(declaration)].scope
	}

	func property(of declaration: DeclarationID) -> Property? {
		graph.graph.nodes[Int(declaration)].property
	}

	func isErased(_ declaration: DeclarationID) -> Bool {
		graph.graph.nodes[Int(declaration)].key.erasedToConcreteExistential
	}

	var isMockWorld: Bool {
		true
	}

	/// No world's root is shareable: a shared declaration is always built beneath its world's root.
	func isRoot(_: DeclarationID) -> Bool {
		false
	}
}
