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

import SafeDICore

/// The places of a seam's holes as a graph of one node per level, in place of one list per place: what each scope on
/// the way to a place binds, keyed by the scope and not by the path it is reached along, with an edge from each level
/// to the levels that can enclose it.
///
/// A level is a fact of the type that binds it, so one node stands for every build of that type at that position. What
/// a build can differ in is kept as a variant: a node's key says which level it is, and two builds that bind otherwise
/// are two nodes of one key (`Node.key`).
///
/// **A case is a node.** Each place is a site beneath one owner level, and a case is that owner node with whether the
/// site is built in a `@Sendable` function of its own. So every place whose owner level is that node is in that case,
/// and the routes from the seam's root to the node are exactly the routes the case's places are built along. That is
/// what makes a query over every route to a node right for the case: it answers neither more nor less than the union
/// of the case's places' own answers, which is what one emitted fill per case binds (`seam-holes.md`).
///
/// It holds one node per level variant and one case per owner, for as long as the holes of one seam are computed; a
/// query's memo lives for the one query (`Query`).
public struct SeamPlaceGraph: Sendable, Hashable {
	/// A level as the graph keys it: which level of which type it is. A build of one type at one position is one key,
	/// however many paths reach it.
	public struct NodeKey: Sendable, Hashable {
		/// The type the scope builds, or `nil` for a fill of a seam the tree calls.
		public let builtType: TypeDescription?
		/// The next property on the way to the place: the next scope's, or the place's.
		public let nextProperty: Property?
		/// Whether the level is the seam's own root, whose declarations are its parameters.
		public let isSeamRoot: Bool
		/// Whether the scope is a fill or in a fill's tree.
		public let isInFill: Bool
		/// For a fill, the type the level before it builds, which the fill fills a place of.
		public let filledType: TypeDescription?

		public init(builtType: TypeDescription?, nextProperty: Property?, isSeamRoot: Bool, isInFill: Bool, filledType: TypeDescription?) {
			self.builtType = builtType
			self.nextProperty = nextProperty
			self.isSeamRoot = isSeamRoot
			self.isInFill = isInFill
			self.filledType = filledType
		}
	}

	/// One entry of the stack a place's owner is built with: a property and the concrete type it is built for.
	public struct StackEntry: Sendable, Hashable {
		public let property: Property
		public let concreteType: TypeDescription

		public init(property: Property, concreteType: TypeDescription) {
			self.property = property
			self.concreteType = concreteType
		}
	}

	/// One level, with what this build of it binds and the levels that can enclose it.
	public struct Node: Sendable, Hashable {
		public let key: NodeKey
		/// The declarations, in the order the scope binds them.
		public let declarations: [SeamPlaceLevels.Level.Declaration]
		/// Whether the scope's builder function, or the fill, is `@Sendable`, enclosing what the level binds.
		public let opensSendableFunction: Bool
		/// Where a cycle-closing scope in the scope's tree calls its builder function, the declarations a scope between
		/// the two binds, first per label: what the cycle hands the type built again
		/// (`SeamSignature.Hole.CycleReentryDeclaration`).
		public let reentryDeclarations: [Property]
		/// For a fill, the stack of the filled seam's path its tree is built beneath, innermost first; empty otherwise.
		public let fillBaseStack: [StackEntry]
		/// The levels that can enclose this one, in the order the places first reach them.
		public let parents: [Int]

		/// The nearest declaration of each label the level binds: within a level, the one it binds later.
		var declarationByLabel: [String: SeamPlaceLevels.Level.Declaration] {
			var declarationByLabel = [String: SeamPlaceLevels.Level.Declaration]()
			for declaration in declarations {
				declarationByLabel[declaration.property.label] = declaration
			}
			return declarationByLabel
		}

		/// The first declaration per label a cycle that re-enters the scope's builder function hands it.
		var reentryDeclarationByLabel: [String: Property] {
			var reentryByLabel = [String: Property]()
			for property in reentryDeclarations where reentryByLabel[property.label] == nil {
				reentryByLabel[property.label] = property
			}
			return reentryByLabel
		}
	}

	/// The places that share an owner level: one emitted fill's worth of places (`seam-hole-fills.md`).
	public struct Case: Sendable, Hashable {
		/// The index in `nodes` of the owner level of every place of the case.
		public let ownerNode: Int
		/// Whether the sites are held in a `Sendable` wrapper, built in a `@Sendable` function of their own.
		public let siteOpensSendableFunction: Bool

		public init(ownerNode: Int, siteOpensSendableFunction: Bool) {
			self.ownerNode = ownerNode
			self.siteOpensSendableFunction = siteOpensSendableFunction
		}
	}

	/// What a place reads of a label.
	public struct Answer: Sendable, Hashable {
		public enum Kind: String, Sendable, Hashable {
			/// The place's scope struct carries the value.
			case field
			/// The declaration hides the farther declarations of its label but holds no value there.
			case uncarried
			/// Nothing on the way to the place declares the label: a fill reads its caller's own declaration.
			case none
		}

		public let property: Property?
		public let kind: Kind

		public init(property: Property?, kind: Kind) {
			self.property = property
			self.kind = kind
		}

		/// The answer a level's declaration gives a place, `crossed` saying whether a `@Sendable` function on the way from
		/// the level to the place encloses the place: such a function captures no value bound outside it, and a parameter
		/// of the seam is the caller's own (`seam-holes.md`).
		static func of(_ declaration: SeamPlaceLevels.Level.Declaration, crossedSendableFunction crossed: Bool) -> Answer {
			if !declaration.isBoundBeforeNextProperty {
				Answer(property: declaration.property, kind: .uncarried)
			} else if !crossed {
				Answer(property: declaration.property, kind: .field)
			} else if declaration.isSeamParameter {
				Answer(property: nil, kind: .none)
			} else {
				Answer(property: declaration.property, kind: .uncarried)
			}
		}

		public var description: String {
			switch kind {
			case .none: "none"
			case .field: "field \(property?.asSource ?? "")"
			case .uncarried: "uncarried \(property?.asSource ?? "")"
			}
		}
	}

	public let nodes: [Node]
	/// The cases, in the order the places first reach their owners.
	public let cases: [Case]
	/// The index in `cases` of the case each place of the computation belongs to, in the places' own order: one integer
	/// per place, which is how a reader still holding places finds the case that answers for it, and how a diagnostic
	/// will find the representative route of its place's variant (`tree-walk-once.md`, section 11).
	public let caseIndexByPlace: [Int]

	public init(nodes: [Node], cases: [Case], caseIndexByPlace: [Int]) {
		self.nodes = nodes
		self.cases = cases
		self.caseIndexByPlace = caseIndexByPlace
	}

	/// The graph of the places `places` describes, each place's levels read nearest first, with one node per level
	/// variant and one case per owner level.
	///
	/// Built from the places the per-site walk computes today, so that both can be compared; once no reader asks a place
	/// for its own lists, the walk builds this directly.
	public init(places: [SeamPlaceLevels.Place]) {
		var indexByVariant = [Variant: Int]()
		var keys = [NodeKey]()
		var declarationsByNode = [[SeamPlaceLevels.Level.Declaration]]()
		var opensSendableFunctionByNode = [Bool]()
		var reentryDeclarationsByNode = [[Property]]()
		var fillBaseStackByNode = [[StackEntry]]()
		var parentsByNode = [[Int]]()
		var parentSetByNode = [Set<Int>]()
		var caseIndexByCase = [Case: Int]()
		var cases = [Case]()
		var caseIndexByPlace = [Int]()
		for place in places {
			var nodesOfPlace = [Int]()
			for (index, level) in place.levels.enumerated() {
				let key = NodeKey(
					builtType: level.builtType,
					nextProperty: level.nextProperty,
					isSeamRoot: index == place.levels.count - 1,
					isInFill: level.isInFill,
					// A fill fills a place of the type the level before it builds, read from the place because a fill's own
					// level builds no type.
					filledType: level.builtType == nil && index > 0 ? place.levels[index - 1].builtType : nil,
				)
				let fillBaseStack = zip(level.fillBaseStack, level.fillBaseConcreteTypes).map { StackEntry(property: $0, concreteType: $1) }
				let variant = Variant(
					key: key,
					declarations: level.declarations,
					opensSendableFunction: level.opensSendableFunction,
					reentryDeclarations: level.reentryDeclarations,
					fillBaseStack: fillBaseStack,
				)
				if let existing = indexByVariant[variant] {
					nodesOfPlace.append(existing)
				} else {
					indexByVariant[variant] = keys.count
					nodesOfPlace.append(keys.count)
					keys.append(key)
					declarationsByNode.append(level.declarations)
					opensSendableFunctionByNode.append(level.opensSendableFunction)
					reentryDeclarationsByNode.append(level.reentryDeclarations)
					fillBaseStackByNode.append(fillBaseStack)
					parentsByNode.append([])
					parentSetByNode.append([])
				}
			}
			// The levels are nearest first, so the level after each one on the path encloses it.
			for (index, node) in nodesOfPlace.enumerated() where index + 1 < nodesOfPlace.count {
				let parent = nodesOfPlace[index + 1]
				if parentSetByNode[node].insert(parent).inserted {
					parentsByNode[node].append(parent)
				}
			}
			guard let owner = nodesOfPlace.first else {
				// A place with no level has no owner to answer for it; it is never asked about.
				caseIndexByPlace.append(-1)
				continue
			}
			let placeCase = Case(ownerNode: owner, siteOpensSendableFunction: place.siteOpensSendableFunction)
			if let known = caseIndexByCase[placeCase] {
				caseIndexByPlace.append(known)
			} else {
				caseIndexByCase[placeCase] = cases.count
				caseIndexByPlace.append(cases.count)
				cases.append(placeCase)
			}
		}
		nodes = keys.indices.map { index in
			Node(
				key: keys[index],
				declarations: declarationsByNode[index],
				opensSendableFunction: opensSendableFunctionByNode[index],
				reentryDeclarations: reentryDeclarationsByNode[index],
				fillBaseStack: fillBaseStackByNode[index],
				parents: parentsByNode[index],
			)
		}
		self.cases = cases
		self.caseIndexByPlace = caseIndexByPlace
	}

	/// A level as built: its key with everything one build of it can bind otherwise than another build of the same type.
	private struct Variant: Hashable {
		let key: NodeKey
		let declarations: [SeamPlaceLevels.Level.Declaration]
		let opensSendableFunction: Bool
		let reentryDeclarations: [Property]
		let fillBaseStack: [StackEntry]
	}

	/// The labels any level on any route to `placeCase` binds, in the order the routes bind them: every label a place of
	/// the case can read of the seam's tree.
	public func labels(reaching placeCase: Case) -> [String] {
		var labels = [String]()
		var seenLabels = Set<String>()
		var visited = Set<Int>()
		var toVisit = [placeCase.ownerNode]
		var order = [Int]()
		while let node = toVisit.popLast() {
			guard visited.insert(node).inserted else { continue }
			order.append(node)
			toVisit += nodes[node].parents
		}
		for node in order {
			for declaration in nodes[node].declarations where seenLabels.insert(declaration.property.label).inserted {
				labels.append(declaration.property.label)
			}
		}
		return labels
	}

	/// A query over the graph, which memoizes its answers per node: one query serves every label of one computation.
	///
	/// Each query walks the graph with an explicit stack, since a seam's tree can be deeper than a concurrency thread's
	/// stack allows a recursive walk to go (`cycle-generation.md`, "Walks"). A node of a cycle of seams can reach itself,
	/// so a node already on the stack contributes nothing and is counted.
	public struct Query {
		public private(set) var graphCycles = 0
		private let graph: SeamPlaceGraph
		private let declarationByLabelByNode: [[String: SeamPlaceLevels.Level.Declaration]]
		private let reentryByLabelByNode: [[String: Property]]
		private var answerMemo = [AnswerKey: Set<Answer>]()
		private var reentryMemo = [LabelKey: Set<Property?>]()
		private var hiddenMemo = [AnswerKey: Set<Property?>]()
		private var stackMemo = [Int: Set<StackEntry>]()

		public init(of graph: SeamPlaceGraph) {
			self.graph = graph
			declarationByLabelByNode = graph.nodes.map(\.declarationByLabel)
			reentryByLabelByNode = graph.nodes.map(\.reentryDeclarationByLabel)
		}

		private struct AnswerKey: Hashable {
			let node: Int
			let label: String
			let crossedSendableFunction: Bool
		}

		private struct LabelKey: Hashable {
			let node: Int
			let label: String
		}

		/// What the places of `placeCase` read of `label`: one answer per distinct answer over the routes to the case's
		/// owner, which are the routes its places are built along.
		public mutating func answers(ofLabel label: String, at placeCase: Case) -> Set<Answer> {
			answers(ofLabel: label, atNode: placeCase.ownerNode, crossedSendableFunction: placeCase.siteOpensSendableFunction)
		}

		private mutating func answers(ofLabel label: String, atNode node: Int, crossedSendableFunction crossed: Bool) -> Set<Answer> {
			let start = AnswerKey(node: node, label: label, crossedSendableFunction: crossed)
			if let known = directAnswers(start) ?? answerMemo[start] {
				return known
			}
			var onStack = Set<AnswerKey>()
			var stack = [(key: start, isExpanded: false)]
			while let (key, isExpanded) = stack.popLast() {
				let parentKeys = parentKeys(of: key)
				if isExpanded {
					var answers = Set<Answer>()
					for parentKey in parentKeys {
						if let known = directAnswers(parentKey) ?? answerMemo[parentKey] {
							answers.formUnion(known)
						} else {
							graphCycles += 1
						}
					}
					onStack.remove(key)
					answerMemo[key] = answers
					continue
				}
				guard answerMemo[key] == nil, onStack.insert(key).inserted else { continue }
				stack.append((key, true))
				for parentKey in parentKeys where directAnswers(parentKey) == nil && answerMemo[parentKey] == nil && !onStack.contains(parentKey) {
					stack.append((parentKey, false))
				}
			}
			return answerMemo[start] ?? []
		}

		/// The answer at `key` where the node settles it: its own declaration of the label, or nothing above it.
		private func directAnswers(_ key: AnswerKey) -> Set<Answer>? {
			if let declaration = declarationByLabelByNode[key.node][key.label] {
				return [Answer.of(declaration, crossedSendableFunction: key.crossedSendableFunction)]
			}
			if graph.nodes[key.node].parents.isEmpty {
				return [Answer(property: nil, kind: .none)]
			}
			return nil
		}

		/// The keys of the levels that can enclose `key`'s, each told whether a `@Sendable` function now lies between it
		/// and the place.
		private func parentKeys(of key: AnswerKey) -> [AnswerKey] {
			let crossed = key.crossedSendableFunction || graph.nodes[key.node].opensSendableFunction
			return graph.nodes[key.node].parents.map { AnswerKey(node: $0, label: key.label, crossedSendableFunction: crossed) }
		}

		/// The declaration a cycle that re-enters a scope on the way to the places of `placeCase` hands the type built
		/// again, for `label`, or `nil` where none does: the outermost re-entered level between the place and the nearest
		/// declaration of the label, since a label bound inside the function is bound again at each level
		/// (`SeamSignature.Hole.cycleReentryDeclarations`).
		public mutating func reentryDeclaration(ofLabel label: String, at placeCase: Case) -> Set<Property?> {
			// The place's own label is never re-entered: every call is made inside a tree that builds a declaration of it.
			guard graph.nodes[placeCase.ownerNode].key.nextProperty?.label != label else { return [nil] }
			return reentryDeclarations(ofLabel: label, atNode: placeCase.ownerNode)
		}

		private mutating func reentryDeclarations(ofLabel label: String, atNode node: Int) -> Set<Property?> {
			let start = LabelKey(node: node, label: label)
			if let known = reentryMemo[start] {
				return known
			}
			var onStack = Set<LabelKey>()
			var stack = [(key: start, isExpanded: false)]
			while let (key, isExpanded) = stack.popLast() {
				guard reentryMemo[key] == nil else { continue }
				// A declaration of the label at this level is the nearest one: nothing farther out is re-entered for it.
				guard declarationByLabelByNode[key.node][key.label] == nil else {
					reentryMemo[key] = [nil]
					continue
				}
				let parentKeys = graph.nodes[key.node].parents.map { LabelKey(node: $0, label: key.label) }
				guard !parentKeys.isEmpty else {
					reentryMemo[key] = [reentryByLabelByNode[key.node][key.label]]
					continue
				}
				if isExpanded {
					var fromAbove = Set<Property?>()
					for parentKey in parentKeys {
						if let known = reentryMemo[parentKey] {
							fromAbove.formUnion(known)
						} else {
							graphCycles += 1
						}
					}
					// The outermost re-entered level wins, so this level's own declaration counts only where none farther out does.
					let own = reentryByLabelByNode[key.node][key.label]
					reentryMemo[key] = Set(fromAbove.map { $0 ?? own })
					onStack.remove(key)
					continue
				}
				guard onStack.insert(key).inserted else { continue }
				stack.append((key, true))
				for parentKey in parentKeys where reentryMemo[parentKey] == nil && !onStack.contains(parentKey) {
					stack.append((parentKey, false))
				}
			}
			return reentryMemo[start] ?? []
		}

		/// The declaration a field bound from a parameter of a filled seam hides, for `label`, or `nil` where none is
		/// hidden: the nearest declaration of another property above that fill, which inline reads there while the struct
		/// carries only the parameter (`SeamSignature.Hole.declarationsHiddenByFields`).
		public mutating func declarationHiddenByField(ofLabel label: String, at placeCase: Case) -> Set<Property?> {
			hiddenDeclarations(ofLabel: label, atNode: placeCase.ownerNode, crossedSendableFunction: placeCase.siteOpensSendableFunction)
		}

		private mutating func hiddenDeclarations(ofLabel label: String, atNode node: Int, crossedSendableFunction crossed: Bool) -> Set<Property?> {
			let start = AnswerKey(node: node, label: label, crossedSendableFunction: crossed)
			if let known = hiddenMemo[start] {
				return known
			}
			var onStack = Set<AnswerKey>()
			var stack = [(key: start, isExpanded: false)]
			while let (key, isExpanded) = stack.popLast() {
				guard hiddenMemo[key] == nil else { continue }
				if let declaration = declarationByLabelByNode[key.node][key.label] {
					hiddenMemo[key] = hiddenDeclarations(behind: declaration, at: key)
					continue
				}
				let parentKeys = parentKeys(of: key)
				guard !parentKeys.isEmpty else {
					hiddenMemo[key] = [nil]
					continue
				}
				if isExpanded {
					var hidden = Set<Property?>()
					for parentKey in parentKeys {
						if let known = hiddenMemo[parentKey] {
							hidden.formUnion(known)
						} else {
							graphCycles += 1
						}
					}
					hiddenMemo[key] = hidden
					onStack.remove(key)
					continue
				}
				guard onStack.insert(key).inserted else { continue }
				stack.append((key, true))
				for parentKey in parentKeys where hiddenMemo[parentKey] == nil && !onStack.contains(parentKey) {
					stack.append((parentKey, false))
				}
			}
			return hiddenMemo[start] ?? []
		}

		/// What `declaration`, the nearest declaration of its label at `key`'s level, hides: nothing unless it is a fill's
		/// field bound from a parameter of the filled seam that the place carries, and then the nearest declaration of
		/// another property, which the fill itself binds before the field or a level above the fill binds.
		private mutating func hiddenDeclarations(behind declaration: SeamPlaceLevels.Level.Declaration, at key: AnswerKey) -> Set<Property?> {
			guard graph.nodes[key.node].key.builtType == nil,
			      declaration.isFieldOfSeamParameter,
			      Answer.of(declaration, crossedSendableFunction: key.crossedSendableFunction).kind == .field
			else { return [nil] }
			// A declaration the fill binds before the field, such as one a passing-up seam binds that the filled seam's
			// struct does not carry, is the nearest above the field.
			if let earlier = graph.nodes[key.node].declarations.prefix(while: { $0 != declaration }).last(where: { $0.property.label == key.label }) {
				return [earlier.property == declaration.property ? nil : earlier.property]
			}
			var hidden = Set<Property?>()
			for parent in graph.nodes[key.node].parents {
				for above in answers(ofLabel: key.label, atNode: parent, crossedSendableFunction: false) {
					hidden.insert(above.property == declaration.property ? nil : above.property)
				}
			}
			return hidden.isEmpty ? [nil] : hidden
		}

		/// The entries of the stacks the places of `placeCase` are built with, over every route: the declarations on the
		/// seam's path a fill's scope can close a cycle on (`SeamSignature.Hole.fillPropertyStack`).
		public mutating func stackEntries(at placeCase: Case) -> Set<StackEntry> {
			stackEntries(atNode: placeCase.ownerNode)
		}

		private mutating func stackEntries(atNode node: Int) -> Set<StackEntry> {
			if let known = stackMemo[node] {
				return known
			}
			var onStack = Set<Int>()
			var stack = [(node: node, isExpanded: false)]
			while let (visited, isExpanded) = stack.popLast() {
				guard stackMemo[visited] == nil else { continue }
				// A fill's tree is built beneath the path of the seam whose place it fills, not beneath its caller's path.
				guard let builtType = graph.nodes[visited].key.builtType else {
					stackMemo[visited] = Set(graph.nodes[visited].fillBaseStack)
					continue
				}
				if isExpanded {
					var entries = Set<StackEntry>()
					for parent in graph.nodes[visited].parents {
						if let property = graph.nodes[parent].key.nextProperty {
							entries.formUnion(Self.entries(of: property, builtAs: builtType))
						}
						if let known = stackMemo[parent] {
							entries.formUnion(known)
						} else {
							graphCycles += 1
						}
					}
					stackMemo[visited] = entries
					onStack.remove(visited)
					continue
				}
				guard onStack.insert(visited).inserted else { continue }
				stack.append((visited, true))
				for parent in graph.nodes[visited].parents where stackMemo[parent] == nil && !onStack.contains(parent) {
					stack.append((parent, false))
				}
			}
			return stackMemo[node] ?? []
		}

		/// The entries `property`, built for `concreteType`, puts on the stack: its instance just outside it where it is
		/// lazily instantiated, as `Scope.createScopeGenerator` stacks them (`ContextStack`).
		static func entries(of property: Property, builtAs concreteType: TypeDescription) -> [StackEntry] {
			var entries = [StackEntry]()
			if let instance = property.asLazilyInstantiatedInstanceProperty {
				entries.append(StackEntry(property: instance, concreteType: concreteType))
			}
			entries.append(StackEntry(property: property, concreteType: concreteType))
			return entries
		}
	}
}
