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

/// The value each receive in a root's tree is handed, and the types the tree constructs, read from the root's per-type
/// graph (`TypeFactsGraph`) rather than from a walk of its generator tree, which entered every path to a type.
///
/// A node stands for every place of its declaration, and an edge for every build of its target there, a call of the
/// function a cycle closes on included. So the declarations a receive of a label can read at a node are, over each edge
/// into it, the edge itself where its source binds the label, or else what its source can read: a union over the
/// graph's paths, solved as a fixed point per label over the components, which are numbered so that every component a
/// node reaches comes before it (`OrderedGraph.componentByNode`). The value an edge hands is then judged by its source's
/// bindings in order (`TypeFactsGraph.worldBindings(of:)`): the first binding of the label that provides the form the
/// receive reads, available where it is bound before the edge's child (`TypeFactsEdge.bindingsBefore`) or the two are
/// members of one loop of builders, whose function binds it again (`TypeFactsEdge.loop`).
///
/// Production trees only, and no fill: a fill's tree reads the fields of the case it fills, which the walk does not
/// enter either. It holds the supplies and the types, for as long as its owner keeps it; the graph dies with `init`.
struct TypeFactsReceivedValueSupplies: Sendable {
	init(root: ConstructionScope) {
		let facts = TypeFactsGraph(root: root, forMockGeneration: false, mockCycleEdges: [])
		let graph = facts.graph
		let nodes = graph.nodes
		let edgeFacts = facts.edgeFacts

		// The nodes the tree builds outside every fill, each edge's source, and each node's edges in from those nodes.
		var isBuiltOutsideFills = [Bool](repeating: false, count: nodes.count)
		isBuiltOutsideFills[0] = true
		var nodesToReach = [0]
		while let index = nodesToReach.popLast() {
			for edge in graph.edgeIndices(from: index) where !edgeFacts[edge].isFill && !isBuiltOutsideFills[Int(graph.edgeTargets[edge])] {
				isBuiltOutsideFills[Int(graph.edgeTargets[edge])] = true
				nodesToReach.append(Int(graph.edgeTargets[edge]))
			}
		}
		var sourceByEdge = [Int32](repeating: 0, count: graph.edgeCount)
		var edgesInto = [[Int32]](repeating: [], count: nodes.count)
		for index in nodes.indices {
			for edge in graph.edgeIndices(from: index) {
				sourceByEdge[edge] = Int32(index)
			}
			for edge in graph.edgeIndices(from: index) where isBuiltOutsideFills[index] && !edgeFacts[edge].isFill {
				edgesInto[Int(graph.edgeTargets[edge])].append(Int32(edge))
			}
		}

		// Each binding's edge, -1 for a forwarded property, which no edge builds.
		var edgeByBinding = [Int32](repeating: -1, count: facts.bindings.count)
		for index in nodes.indices {
			let offset = Int(facts.bindingOffsets[index])
			for edge in graph.edgeIndices(from: index) where !edgeFacts[edge].isFill {
				edgeByBinding[offset + Int(edgeFacts[edge].bindingsBefore)] = Int32(edge)
			}
		}

		// The label IDs the graph names, and one no binding names for any other label.
		var labelIDByText = [String: Int32]()
		for (id, text) in facts.labelTexts.enumerated() {
			labelIDByText[text] = Int32(id)
		}
		func labelID(of text: String) -> Int32 {
			labelIDByText[text] ?? -1
		}

		// The label each node is built as, and whether each edge closes a cycle wherever it is built: its target dominates
		// its source, so every path to the edge holds a build of the target already.
		let labelByNode = nodes.map { node in node.property.map { labelID(of: $0.label) } ?? -1 }
		let dominators = TypeFactsGraph.immediateDominators(of: graph, followsEdge: { !edgeFacts[$0].isFill })
		func dominates(_ dominator: Int, _ node: Int) -> Bool {
			var current = node
			while current != dominator {
				let next = dominators[current]
				guard next >= 0, next != current else { return false }
				current = next
			}
			return true
		}
		func alwaysClosesCycle(_ edge: Int32) -> Bool {
			let target = Int(graph.edgeTargets[Int(edge)])
			let source = Int(sourceByEdge[Int(edge)])
			return graph.componentByNode[target] == graph.componentByNode[source] && dominates(target, source)
		}

		// The nodes of each component, the root's last.
		var nodesByComponent = [[Int]](repeating: [], count: graph.componentCount)
		for index in nodes.indices {
			nodesByComponent[Int(graph.componentByNode[index])].append(index)
		}

		var work = 0
		var contextsByLabel = [Int32: [Set<Int32>]]()
		/// The edges whose source's binding of `label` a receive of it reads at each node, `noDeclaration` where it reads
		/// none: the edge into the node where its source binds the label, else what the source reads.
		func contexts(ofLabel label: Int32) -> [Set<Int32>] {
			if let contexts = contextsByLabel[label] {
				return contexts
			}
			func binds(_ node: Int) -> Bool {
				facts.worldBindings(of: node).contains { $0.label == label }
			}
			let bindsLabel = nodes.indices.map(binds)
			var contexts = [Set<Int32>](repeating: [], count: nodes.count)
			contexts[0] = [Self.noDeclaration]
			// A node no edge has handed anything yet takes its source's set itself, which the two then share until either
			// changes, so a chain beneath the declarations of a label copies none of them. A change of a shared set copies it,
			// which counts as the elements it moves.
			var sharesSourcesSet = [Bool](repeating: false, count: nodes.count)
			for component in nodesByComponent.reversed() {
				// A component of one node that no edge of its own enters takes one pass; any other, passes until none changes.
				let isCycle = component.count > 1 || edgesInto[component[0]].contains { sourceByEdge[Int($0)] == Int32(component[0]) }
				var changed = true
				while changed {
					changed = false
					for node in component {
						for edge in edgesInto[node] {
							work += 1
							let source = Int(sourceByEdge[Int(edge)])
							let before = contexts[node].count
							if bindsLabel[source] {
								// A call of the function a cycle closes on passes no value of the label the function builds: inside
								// it, the label reads what it reads where the function is declared, which an edge before this one
								// hands (`CycleParameter`).
								if labelByNode[node] != label || !alwaysClosesCycle(edge), !contexts[node].contains(edge) {
									if sharesSourcesSet[node] {
										work += contexts[node].count
										sharesSourcesSet[node] = false
									}
									contexts[node].insert(edge)
								}
							} else if contexts[node].isEmpty {
								contexts[node] = contexts[source]
								sharesSourcesSet[node] = true
							} else {
								work += contexts[source].count
								if !contexts[source].isSubset(of: contexts[node]) {
									if sharesSourcesSet[node] {
										work += contexts[node].count
										sharesSourcesSet[node] = false
									}
									contexts[node].formUnion(contexts[source])
								}
							}
							if isCycle, contexts[node].count != before {
								changed = true
							}
						}
					}
				}
			}
			contextsByLabel[label] = contexts
			return contexts
		}

		/// The value the declaration `edge`'s source binds as `label` hands a receive of `receivedProperty`.
		func value(handedBy edge: Int32, label: Int32, receiving receivedProperty: Property) -> ReceivedValueSupply.Value {
			work += 1
			guard edge != Self.noDeclaration else { return .passedNil(.noProvidingDeclaration) }
			let source = Int(sourceByEdge[Int(edge)])
			let offset = Int(facts.bindingOffsets[source])
			let unwrappedProperty = receivedProperty.asUnwrappedProperty
			for (index, binding) in facts.worldBindings(of: source).enumerated() where binding.label == label {
				let property = facts.propertyTable[Int(binding.property)]
				let bindingEdge = edgeByBinding[offset + index]
				let instanceProperty = if bindingEdge >= 0, nodes[Int(graph.edgeTargets[Int(bindingEdge)])].key.leaf != .alias {
					property.asLazilyInstantiatedInstanceProperty
				} else {
					property.asLazilyInstantiatedInstancePropertyOfDeclaredBinding
				}
				guard property.asUnwrappedProperty == unwrappedProperty || instanceProperty?.asUnwrappedProperty == unwrappedProperty else { continue }
				let edgeFact = edgeFacts[Int(edge)]
				let isRebound = edgeFact.loop >= 0 && bindingEdge >= 0 && edgeFacts[Int(bindingEdge)].loop == edgeFact.loop
				guard index < Int(edgeFact.bindingsBefore) || isRebound else {
					return .passedNil(.providerNotYetBuilt)
				}
				return .declaration(ReceivedValueSupply.Supplier(declaringType: facts.typeTable[Int(facts.builtTypes[source])], label: property.label))
			}
			return .passedNil(.noProvidingDeclaration)
		}

		var supplies = [ReceivedValueSupply]()
		var seenSupplies = Set<ReceivedValueSupply>()
		func record(_ supply: ReceivedValueSupply) {
			if seenSupplies.insert(supply).inserted {
				supplies.append(supply)
			}
		}
		/// Records what each declaration among `edges` hands `receivingType`'s receive of `receivedProperty` under `label`.
		func recordSupplies(handedBy edges: Set<Int32>, label: Int32, receivingType: TypeDescription, receivedProperty: Property, labelText: String) {
			for edge in edges.sorted() {
				record(ReceivedValueSupply(receivingType: receivingType, label: labelText, value: value(handedBy: edge, label: label, receiving: receivedProperty)))
			}
		}
		for (index, node) in nodes.enumerated() where isBuiltOutsideFills[index] {
			let receivingType = facts.typeTable[Int(facts.builtTypes[index])]
			if let alias = node.alias {
				// The alias is bound in its declaring scope, where its fulfilling property is read: the scope's own binding
				// of that label, then what the scope reads. One that keeps its label is not in scope where it is read.
				let label = labelID(of: alias.fulfillingProperty.label)
				for edge in edgesInto[index] {
					let source = Int(sourceByEdge[Int(edge)])
					let declaringType = facts.typeTable[Int(facts.builtTypes[source])]
					let edges: Set<Int32> = if alias.fulfillingProperty.label != alias.property.label, facts.worldBindings(of: source).contains(where: { $0.label == label }) {
						[edge]
					} else {
						contexts(ofLabel: label)[source]
					}
					recordSupplies(handedBy: edges, label: label, receivingType: declaringType, receivedProperty: alias.fulfillingProperty, labelText: alias.property.label)
				}
			} else if node.key.leaf == .none {
				for dependency in node.scope.instantiable.dependencies where dependency.source.isReceived {
					let label = labelID(of: dependency.property.label)
					recordSupplies(handedBy: contexts(ofLabel: label)[index], label: label, receivingType: receivingType, receivedProperty: dependency.property, labelText: dependency.property.label)
				}
			}
		}

		// The types the tree constructs, as a walk of it meets them: depth first, each scope's children as it builds them.
		var constructedTypes = [TypeDescription]()
		var seenTypes = Set<Int32>()
		var visited = [Bool](repeating: false, count: nodes.count)
		var nodesToVisit = [0]
		while let index = nodesToVisit.popLast() {
			guard !visited[index] else { continue }
			visited[index] = true
			guard nodes[index].key.leaf == .none else { continue }
			if seenTypes.insert(facts.builtTypes[index]).inserted {
				constructedTypes.append(facts.typeTable[Int(facts.builtTypes[index])])
			}
			let childEdges = graph.edgeIndices(from: index).filter { !edgeFacts[$0].isFill }.sorted { edgeFacts[$0].buildPosition < edgeFacts[$1].buildPosition }
			nodesToVisit.append(contentsOf: childEdges.reversed().map { Int(graph.edgeTargets[$0]) })
		}

		self.supplies = supplies
		self.constructedTypes = constructedTypes
		GenerationWork.record(work, by: .findingReceivedValueSupplies)
	}

	/// The value each receive is handed in each place the tree builds its type, each listed once.
	let supplies: [ReceivedValueSupply]
	/// The concrete type of each declaration the tree constructs, each listed once.
	let constructedTypes: [TypeDescription]

	/// The element of a node's contexts that stands for no declaration of the label above it.
	private static let noDeclaration: Int32 = -1

	/// Whether the trees a call builds read their roots' supplies where each is built, set by
	/// `DependencyTreeGenerator.receivedValueSupplies()` around the trees it reads.
	@TaskLocal static var readsWhereTreesAreBuilt = false

	/// The supplies of the tree `root` roots, read where the tree is built, so that the table its scope is frozen into is
	/// freed with the build rather than kept for every root at once; `nil` where nothing reads them. Two readers do:
	/// `DependencyTreeGenerator.receivedValueSupplies()` (`readsWhereTreesAreBuilt`), and the tests' comparison with the
	/// walk (`TypeFactsReceivedValueSuppliesObservation.comparesWalk`), which `GenerationWork` does not count.
	static func whereRead(root: ConstructionScope) -> ReceivedValueSupplies? {
		guard readsWhereTreesAreBuilt || TypeFactsReceivedValueSuppliesObservation.comparesWalk != nil else { return nil }
		let tree = GenerationWork.$observer.withValue(readsWhereTreesAreBuilt ? GenerationWork.observer : nil) {
			TypeFactsReceivedValueSupplies(root: root)
		}
		return ReceivedValueSupplies(supplies: tree.supplies, constructedTypes: tree.constructedTypes)
	}
}

/// The supplies of each root the fold finds beside those the walk of its generator tree finds
/// (`ScopeGenerator.receivedValueSupplies(ofTreeRootedAt:)`), handed to `comparesWalk`, which the tests set, never the
/// tool: the two must be equal, as sets, on every test and fuzzer graph. The fold and the walk run only where it is set,
/// uncounted by `GenerationWork`, while `generate` plans each root's code.
public enum TypeFactsReceivedValueSuppliesObservation {
	@TaskLocal public static var comparesWalk: (@Sendable (TypeFactsReceivedValueSuppliesComparison) -> Void)?
}

/// One root's supplies and constructed types, from the fold and from the walk.
public struct TypeFactsReceivedValueSuppliesComparison: Sendable {
	/// The root's type.
	public let root: String
	/// What the fold finds.
	public let folded: ReceivedValueSupplies
	/// What the walk of the root's generator tree finds, or `nil` where it judges none of the tree.
	public let walked: ReceivedValueSupplies?
}
