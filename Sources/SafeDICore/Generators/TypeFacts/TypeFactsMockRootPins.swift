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
/// places beneath a required receive above it that pins it. So a mock read (`ReadChannel.mock`) of a label is answered
/// by a context: a declaration nearer than the root's, or the root's with the read sets of the required receives above the
/// place (`Context`). The root answers its own reads and its edges with its own context, a node that declares or rebinds
/// the label answers its edges with a nearer declaration, and a node that hands the read on adds its own required receives
/// of the label (`TypeFactsVariants`' `refine`). A label no required receive can pin a receive of in the world is
/// answered by nothing, so it never tells two places apart.
///
/// It holds, for the graph's lifetime, a few entries per label some required receive can pin a receive of: the receive
/// sets, the types pinned wherever built, and each node's required read sets of such labels.
struct TypeFactsMockRootPins: Sendable {
	/// What a place's mock read of a label resolves to above it.
	enum Context: Hashable, Sendable {
		/// A declaration of the label nearer than the mock root's, which pins nothing.
		case nearer
		/// The mock root's declaration, with the sets of properties each required receive of the label above the place reads
		/// (`pinSets` IDs, sorted and distinct): each pins a receive it shares no declaration with.
		case root(pinnedAbove: [Int32])
	}

	/// - Parameters:
	///   - graph: The mock root's world, or a graph that holds it.
	///   - root: The node of `graph` that is the mock root, whose own and promoted children the walk starts from.
	///   - edgeIsFill: Whether each edge, by its position among every node's edges, is a fill, which the walk enters no
	///     tree of.
	///   - labels: The world's labels, which every read of a pinnable label names.
	init(graph: OrderedGraph<TypeFactsDeclaration>, root: Int, edgeIsFill: [Bool], labels: TypeFactsInterner<String>) {
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
		for (index, target) in graph.edges(from: root).enumerated() {
			if let property = nodes[Int(target)].property, nodes[Int(target)].key.leaf == .none, !edgeIsFill[index], !ownChildProperties.contains(property) {
				promotedEdges.insert(index)
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

		var requiredSetsByNodeAndLabel = [[Int32: [Int32]]]()
		requiredSetsByNodeAndLabel.reserveCapacity(nodes.count)
		for required in requiredByNode {
			var setsByLabel = [Int32: [Int32]]()
			for (label, set) in required where pinnableLabels.contains(label) {
				guard let labelID = labels.existingID(of: label) else { continue }
				setsByLabel[labelID, default: []].append(set)
			}
			requiredSetsByNodeAndLabel.append(setsByLabel)
		}
		self.pinSets = pinSets.values
		self.pinnableLabels = Set(pinnableLabels.compactMap { labels.existingID(of: $0) })
		self.pinnedWhereverBuilt = pinnedWhereverBuilt
		self.requiredSetsByNodeAndLabel = requiredSetsByNodeAndLabel
		self.root = root
		self.promotedEdges = promotedEdges
		self.onlyIfAvailableByNode = onlyIfAvailableByNode
	}

	/// Whether some required receive of the label in the world can pin a receive of it only if available.
	func isPinnable(_ label: Int32) -> Bool {
		pinnableLabels.contains(label)
	}

	/// The context the root answers a mock read of a pinnable label with at its edge with `index` among its edges: its own
	/// required receives of the label pin the places beneath, but for a child it promotes.
	func rootContext(atEdge index: Int, label: Int32) -> Context {
		promotedEdges.contains(index) ? .root(pinnedAbove: []) : .root(pinnedAbove: (requiredSetsByNodeAndLabel[root][label] ?? []).sortedDistinct)
	}

	/// The context `node` hands on for a mock read of `label` it does not bind, given the one it was handed: its own
	/// required receives of the label added, or `nil` where it adds none.
	func context(handedOnBy node: Int, label: Int32, from context: Context) -> Context? {
		guard case let .root(pinnedAbove) = context, let sets = requiredSetsByNodeAndLabel[node][label] else { return nil }
		let refined = (pinnedAbove + sets).sortedDistinct
		return refined == pinnedAbove ? nil : .root(pinnedAbove: refined)
	}

	/// The properties a place of `node` passes `nil` for, of those its type's dependencies receive only if available, given
	/// the context of each label's mock read above the place: `contextOfLabel` returns `nil` for a label nothing pins.
	func receivesPassedNil(at node: Int, type: TypeDescription, scope: ConstructionScope, contextOfLabel: (String) -> Context?) -> Set<Property> {
		var passedNil = Set<Property>()
		for receive in onlyIfAvailableByNode[node] where scope.createdBinding(of: receive.property) == nil {
			guard case let .root(pinnedAbove) = contextOfLabel(receive.property.label) else { continue }
			let isPinned = pinnedWhereverBuilt[receive.property.label]?[type]?.contains(receive.property) == true
				|| pinnedAbove.contains { DependencyTreeGenerator.requiredReceive(reading: pinSets[Int($0)], pinsReceiveOf: receive.dependency) }
			if isPinned {
				passedNil.insert(receive.property)
			}
		}
		return passedNil
	}

	private let pinSets: [Set<Property>]
	private let pinnableLabels: Set<Int32>
	private let pinnedWhereverBuilt: [String: [TypeDescription: Set<Property>]]
	private let requiredSetsByNodeAndLabel: [[Int32: [Int32]]]
	/// The node that is the mock root.
	private let root: Int
	/// The root's edges, by index among its edges, to the children it promotes.
	private let promotedEdges: Set<Int>
	private let onlyIfAvailableByNode: [[(property: Property, dependency: Dependency)]]
}

extension TypeFactsMockRootPins {
	/// The context each answer ID of a mock read stands for, in flat columns by answer ID, for the graph's lifetime: a kind
	/// per answer and the pinned sets of each root context, a few entries per mock answer.
	struct ContextColumns: Sendable {
		/// - Parameters:
		///   - contexts: The context of each mock answer, by answer ID.
		///   - answerCount: How many answers the world has; IDs are `0..<answerCount`.
		init(contexts: [Int32: Context], answerCount: Int) {
			var kinds = [Kind]()
			var pinnedAboveOffsets = [Int32]()
			var pinnedAbove = [Int32]()
			kinds.reserveCapacity(answerCount)
			pinnedAboveOffsets.reserveCapacity(answerCount + 1)
			for answer in 0..<answerCount {
				pinnedAboveOffsets.append(Int32(pinnedAbove.count))
				switch contexts[Int32(answer)] {
				case .none:
					kinds.append(.none)
				case .nearer:
					kinds.append(.nearer)
				case let .root(pinned):
					kinds.append(.root)
					pinnedAbove.append(contentsOf: pinned)
				}
			}
			pinnedAboveOffsets.append(Int32(pinnedAbove.count))
			self.kinds = kinds
			self.pinnedAboveOffsets = pinnedAboveOffsets
			self.pinnedAbove = pinnedAbove
		}

		/// The context the answer stands for, or `nil` for an answer of no mock read and for -1, the key of a read nothing
		/// answers (a mock read whose label no declaration above binds). Every other answer ID is one of `0..<answerCount`,
		/// as every key and answer of the world is.
		func context(ofAnswer answer: Int32) -> Context? {
			guard answer >= 0 else { return nil }
			let index = Int(answer)
			switch kinds[index] {
			case .none:
				return nil
			case .nearer:
				return .nearer
			case .root:
				return .root(pinnedAbove: Array(pinnedAbove[Int(pinnedAboveOffsets[index])..<Int(pinnedAboveOffsets[index + 1])]))
			}
		}

		private enum Kind: UInt8, Sendable {
			case none
			case nearer
			case root
		}

		/// Each answer's kind of context, by answer ID.
		private let kinds: [Kind]
		/// Where each answer's pinned sets start in `pinnedAbove`, with one more entry for the end.
		private let pinnedAboveOffsets: [Int32]
		/// The pinned sets of every root context, answer after answer.
		private let pinnedAbove: [Int32]
	}
}

extension [Int32] {
	fileprivate var sortedDistinct: [Int32] {
		Array(Set(self)).sorted()
	}
}
