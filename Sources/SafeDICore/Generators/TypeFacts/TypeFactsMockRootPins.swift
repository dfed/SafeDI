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

/// What a mock root's world pins: the receives only if available that the mock passes `nil`, as production always does,
/// because a required receive of their label pins the one declaration both read to a form they cannot read
/// (`DependencyTreeGenerator.receivesPassedNilInMockTree`, `NearestDeclarations.resolvingPassesNil(to:receivedBy:on:)`).
/// It is the producer of the mock root's pins, which the facts no longer owe, made from the graph's nodes and edges,
/// never from the walk.
///
/// A receive is pinned only where the nearest declaration of its label is the mock root's, and then either wherever its
/// type is built (a required receive on its type, or beneath it back to a declaration of the label, pins it) or in the
/// places beneath a required receive above it that pins it. A pin never keys a variant: a pinned receive is handed `nil`
/// where another place of its type is handed the mock root's value, one optional of the receive's own form, which one
/// parameter carries, so a variant that split on it would grow as two to the power of the pinned labels
/// (`TypeFactsFormDebt`). So the pins are facts of the nodes, folded along a path only for a place: what a place passes
/// `nil` given the path that reaches it (`receivesPassedNil(alongPath:)`).
///
/// It holds, for its owner's lifetime, a few entries per label some required receive can pin a receive of: the receive
/// sets, the types pinned wherever built, and each node's required read sets of such labels.
struct TypeFactsMockRootPins: Sendable {
	/// - Parameters:
	///   - graph: The mock root's world, or a graph that holds it.
	///   - root: The node of `graph` that is the mock root, whose own and promoted children the walk starts from.
	///   - edgeIsFill: Whether each edge, by its position among every node's edges, is a fill, which the walk enters no
	///     tree of.
	init(graph: OrderedGraph<TypeFactsDeclaration>, root: Int, edgeIsFill: [Bool]) {
		let nodes = graph.nodes
		var pinSets = TypeFactsInterner<Set<Property>>()
		// Each node's required receives of a label and its receives of one only if available, as the walk judges them.
		var requiredByNode = [[(label: String, set: Int32)]]()
		var onlyIfAvailableByNode = [[(property: Property, dependency: Dependency)]]()
		var declaredLabelsByNode = [Set<String>]()
		requiredByNode.reserveCapacity(nodes.count)
		for node in nodes {
			guard node.key.leaf == .none else {
				requiredByNode.append([])
				onlyIfAvailableByNode.append([])
				declaredLabelsByNode.append([])
				continue
			}
			requiredByNode.append(DependencyTreeGenerator.propertiesReadByRequiredReceivesFromAbove(of: node.scope.instantiable, publicMockCall: node.scope.publicMockCall).map { ($0.label, pinSets.id(of: $0.propertiesRead)) })
			onlyIfAvailableByNode.append(DependencyTreeGenerator.onlyIfAvailableReceivesFromAbove(of: node.scope))
			declaredLabelsByNode.append(DependencyTreeGenerator.labelsDeclared(by: node.scope))
		}

		// A label is pinnable where some required receive of it in the world pins some receive of it only if available.
		var requiredSetsByLabel = [String: [Int32]]()
		for required in requiredByNode {
			for (label, set) in required where !(requiredSetsByLabel[label]?.contains(set) ?? false) {
				requiredSetsByLabel[label, default: []].append(set)
			}
		}
		var pinnableLabels = Set<String>()
		for onlyIfAvailable in onlyIfAvailableByNode {
			for receive in onlyIfAvailable where !pinnableLabels.contains(receive.property.label) {
				let pins = requiredSetsByLabel[receive.property.label, default: []].contains {
					DependencyTreeGenerator.requiredReceive(reading: pinSets.values[Int($0)], pinsReceiveOf: receive.dependency)
				}
				if pins {
					pinnableLabels.insert(receive.property.label)
				}
			}
		}

		// The root's edges to the children it promotes, whose trees production builds above the mocked type: the walk starts
		// each of them afresh, and the mocked type's own receives pin nothing in them.
		let rootScope = nodes[root].scope
		let ownChildProperties = Set(rootScope.instantiable.dependencies.compactMap { dependency -> Property? in
			switch dependency.source {
			case .instantiated:
				dependency.property
			case .received, .aliased, .forwarded:
				nil
			}
		})
		var promotedEdges = Set<Int>()
		var promotedChildren = Set<Int>()
		for (index, target) in graph.edges(from: root).enumerated() {
			if let property = nodes[Int(target)].property, nodes[Int(target)].key.leaf == .none, !edgeIsFill[index], !ownChildProperties.contains(property) {
				promotedEdges.insert(index)
				promotedChildren.insert(Int(target))
			}
		}
		/// The children of `node` a tree of the walk enters: no fill, no leaf, and at the root only the mocked type's own.
		func children(of node: Int) -> [Int] {
			let offset = graph.edgeOffset(of: node)
			var children = [Int]()
			for (index, target) in graph.edges(from: node).enumerated()
				where !edgeIsFill[offset + index] && nodes[Int(target)].key.leaf == .none && !(node == root && promotedEdges.contains(index))
			{
				children.append(Int(target))
			}
			return children
		}

		// Each pinnable label's receives pinned wherever their type is built, by the type that declares each: the walk
		// starts at the mocked type and at each promoted child, and judges every type it reaches before a declaration of the
		// label against the required receives on it and beneath it, back to a declaration of the label.
		var pinnedWhereverBuilt = [String: [TypeDescription: Set<Property>]]()
		let starts = [root] + graph.edges(from: root).enumerated().compactMap { index, target in
			promotedEdges.contains(index) ? Int(target) : nil
		}
		for label in pinnableLabels.sorted() {
			var reached = Set(starts)
			var pending = starts
			while let node = pending.popLast() {
				let receives = onlyIfAvailableByNode[node].filter { $0.property.label == label }
				if !receives.isEmpty {
					var requiredSets = requiredByNode[node].filter { $0.label == label }.map(\.set)
					var visited: Set = [node]
					var beneath = children(of: node)
					while let child = beneath.popLast() {
						guard visited.insert(child).inserted else { continue }
						requiredSets.append(contentsOf: requiredByNode[child].filter { $0.label == label }.map(\.set))
						if !declaredLabelsByNode[child].contains(label) {
							beneath.append(contentsOf: children(of: child))
						}
					}
					for receive in receives {
						let isPinned = requiredSets.contains {
							DependencyTreeGenerator.requiredReceive(reading: pinSets.values[Int($0)], pinsReceiveOf: receive.dependency)
						}
						if isPinned {
							pinnedWhereverBuilt[label, default: [:]][nodes[node].scope.instantiable.concreteInstantiable, default: []].insert(receive.property)
						}
					}
				}
				guard !declaredLabelsByNode[node].contains(label) else { continue }
				for child in children(of: node) where reached.insert(child).inserted {
					pending.append(child)
				}
			}
		}

		var requiredSetsByNodeAndLabel = [[String: [Int32]]]()
		requiredSetsByNodeAndLabel.reserveCapacity(nodes.count)
		for required in requiredByNode {
			var setsByLabel = [String: [Int32]]()
			for (label, set) in required where pinnableLabels.contains(label) {
				setsByLabel[label, default: []].append(set)
			}
			requiredSetsByNodeAndLabel.append(setsByLabel)
		}
		self.nodes = nodes
		self.pinSets = pinSets.values
		self.pinnableLabels = pinnableLabels
		self.pinnedWhereverBuilt = pinnedWhereverBuilt
		self.requiredSetsByNodeAndLabel = requiredSetsByNodeAndLabel
		self.promotedChildren = promotedChildren
		self.onlyIfAvailableByNode = onlyIfAvailableByNode
		self.declaredLabelsByNode = declaredLabelsByNode
	}

	/// The properties the place at the end of `path` passes `nil` for, of those its type's dependencies receive only if
	/// available: `path` is the place's nodes from the mock root down, the place's own last. A label's receives are pinned
	/// from above only where no node on the path is built as the label and none above the place declares it, so that the
	/// mock root's declaration is the nearest, by the required receives of each node above the place. A child the root
	/// promotes is built above the mocked type in production, so neither the mocked type's declarations nor its required
	/// receives are above the places of its tree.
	func receivesPassedNil(alongPath path: [Int]) -> Set<Property> {
		guard let node = path.last else { return [] }
		let above = path.count > 1 && promotedChildren.contains(path[1]) ? path.dropFirst().dropLast() : path.dropLast()
		let scope = nodes[node].scope
		var passedNil = Set<Property>()
		for receive in onlyIfAvailableByNode[node] where scope.createdBinding(of: receive.property) == nil {
			let label = receive.property.label
			guard pinnableLabels.contains(label),
			      !path.contains(where: { nodes[$0].property?.label == label }),
			      !above.contains(where: { declaredLabelsByNode[$0].contains(label) })
			else { continue }
			let isPinned = pinnedWhereverBuilt[label]?[scope.instantiable.concreteInstantiable]?.contains(receive.property) == true
				|| above.contains { above in
					requiredSetsByNodeAndLabel[above][label]?.contains { DependencyTreeGenerator.requiredReceive(reading: pinSets[Int($0)], pinsReceiveOf: receive.dependency) } == true
				}
			if isPinned {
				passedNil.insert(receive.property)
			}
		}
		return passedNil
	}

	private let nodes: [TypeFactsDeclaration]
	private let pinSets: [Set<Property>]
	private let pinnableLabels: Set<String>
	private let pinnedWhereverBuilt: [String: [TypeDescription: Set<Property>]]
	private let requiredSetsByNodeAndLabel: [[String: [Int32]]]
	/// The root's children it promotes, whose trees production builds above the mocked type.
	private let promotedChildren: Set<Int>
	private let onlyIfAvailableByNode: [[(property: Property, dependency: Dependency)]]
	private let declaredLabelsByNode: [Set<String>]
}
