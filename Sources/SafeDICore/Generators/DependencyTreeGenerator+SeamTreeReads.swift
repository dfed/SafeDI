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

extension DependencyTreeGenerator {
	/// What `seamRoot(of:reads:generator:…)` reads of a seam's tree for the seam's parameters, the builder function names
	/// it names them apart from, and the escaping types of its signature. Two producers make it: the seam's root generator
	/// (`init(tree:of:instantiables:)`), which every run reads, and the per-type facts of the pass's root
	/// (`init(facts:answeringOtherFieldsFrom:)`), which only a test observing or selecting it makes (`SeamTreeReadsObservation`), beside
	/// the tree's, so that the two can be compared on every seam of every test and fuzzer graph. Which producer answers
	/// each field of the facts' value is `SeamTreeReadsObservation.FactsField` and `TreeField`: a field moves from the second
	/// to the first in the change that produces it from facts, and once every field has moved, `seamRoot` run on the facts'
	/// value must give the signature it gives on the tree's. Holds what it reads for as long as `seamRoot` runs.
	struct SeamTreeReads {
		/// The properties the tree requires of the seam's caller (`ScopeGenerator.requiredReceivedProperties`), the
		/// receives inside the fills of its seam calls among them.
		let requiredReceivedProperties: Set<Property>
		/// The properties the tree requires through `onlyIfAvailable` aliases
		/// (`ScopeGenerator.requiredAliasFulfillingProperties`).
		var requiredAliasFulfillingProperties: Set<Property>
		/// Every receive that leaves the seam (`receivers(in:of:instantiables:)`).
		let receivers: [SeamReceiver]
		/// The reads of the seam's parameters its tree makes, which decide a by-value pass-through's deferral and whether
		/// it is `@Sendable` (`receivers(in:of:instantiables:)`, or `ParameterReads(facts:)`).
		var parameterReads: ParameterReads
		/// The names the tree's declarations declare `@escaping` (`ScopeGenerator.typesDeclaredEscaping`).
		var typesDeclaredEscaping: Set<TypeDescription>
		/// The tree the builder function names are read from, when `seamRoot` asks for them: a seam that throws, or equals
		/// its own initializer, never asks, so a run walks the tree for them only where it would without this value.
		private let builderFunctionNameTree: ScopeGenerator

		/// What `generator`, the root generator of `seam`'s tree, holds.
		init(tree generator: ScopeGenerator, of seam: Instantiable, instantiables: [TypeDescription: Instantiable]) {
			requiredReceivedProperties = generator.requiredReceivedProperties
			requiredAliasFulfillingProperties = generator.requiredAliasFulfillingProperties
			(receivers, parameterReads) = DependencyTreeGenerator.receivers(in: generator, of: seam, instantiables: instantiables)
			typesDeclaredEscaping = generator.typesDeclaredEscaping
			builderFunctionNameTree = generator
		}

		/// What the facts of the seam's tree, `graph`, hold at its root, for each `FactsField`; every `TreeField` is
		/// `treeReads`'.
		init(facts graph: TypeFactsGraph, answeringOtherFieldsFrom treeReads: SeamTreeReads) {
			// The root is the graph's first node.
			func properties(in rows: BitRows) -> Set<Property> {
				Set(rows.columns(inRow: 0).map { graph.propertyTable[Int($0)] })
			}
			requiredReceivedProperties = treeReads.requiredReceivedProperties
			requiredAliasFulfillingProperties = properties(in: graph.receives.requiredAliasFulfilling)
			typesDeclaredEscaping = Set(graph.typesDeclaredEscaping.columns(inRow: 0).map { graph.typeTable[Int($0)] })
			receivers = treeReads.receivers
			parameterReads = ParameterReads(facts: graph)
			builderFunctionNameTree = treeReads.builderFunctionNameTree
		}

		/// The name of every builder function the tree declares, the functions that build its hole sites' wrappers among
		/// them where `includingHoleSites` holds (`builderFunctionNamesOfProperties(in:includingHoleSites:)`).
		func builderFunctionNames(includingHoleSites: Bool) -> Set<String> {
			DependencyTreeGenerator.builderFunctionNamesOfProperties(in: builderFunctionNameTree, includingHoleSites: includingHoleSites)
		}

		/// The field as the comparison reads it, sorted. The required sets are spelled as `==` reads them, `any P` as `P`:
		/// `seamRoot` asks them only whether they hold a property, and spells each parameter from its receivers. The escaping
		/// types are spelled as declared, since the signature keeps the ones it holds. The parameter reads are spelled as
		/// `seamRoot` asks them, by the two questions, for each label a receive that leaves the seam has, in label order: the
		/// receives are the parameters' candidates, and both values hold the same ones.
		func spelling(of field: SeamTreeReadsObservation.FactsField) -> [String] {
			switch field {
			case .requiredAliasFulfillingProperties:
				requiredAliasFulfillingProperties.map(\.spelledAsEqualityReadsIt).sorted()
			case .typesDeclaredEscaping:
				typesDeclaredEscaping.map(\.asSource).sorted()
			case .parameterReads:
				Set(receivers.map(\.property.label)).sorted().map { label in
					"\(label): read \(parameterReads.reads(label)), inside a @Sendable function \(parameterReads.readsInsideSendableFunction(label))"
				}
			}
		}

		/// `field` emptied, so a test can see the comparison report a difference (`SeamTreeReadsObservation.perturbsFactsField`).
		func emptying(_ field: SeamTreeReadsObservation.FactsField) -> SeamTreeReads {
			var reads = self
			switch field {
			case .requiredAliasFulfillingProperties:
				reads.requiredAliasFulfillingProperties = []
			case .typesDeclaredEscaping:
				reads.typesDeclaredEscaping = []
			case .parameterReads:
				reads.parameterReads = ParameterReads()
			}
			return reads
		}
	}

	/// The reads a signature pass proceeds with for `seam`, whose tree it built rooted at `rootScope`, with `generator`
	/// at its root: the tree's, or, where a test selects `SeamTreeReadsObservation.Producer.facts`, the facts'. The facts'
	/// value is made only where a test selects it or observes the comparison, which is then made with it.
	static func seamTreeReads(of seam: Instantiable, generator: ScopeGenerator, rootScope: ConstructionScope, instantiables: [TypeDescription: Instantiable]) -> SeamTreeReads {
		let treeReads = SeamTreeReads(tree: generator, of: seam, instantiables: instantiables)
		let observer = SeamTreeReadsObservation.comparesFacts
		let producer = SeamTreeReadsObservation.producer
		guard observer != nil || producer == .facts else {
			return treeReads
		}
		// The facts are made only for a test, so they count no work of the run's.
		let factsReads = GenerationWork.$observer.withValue(nil) {
			SeamTreeReads(facts: TypeFactsGraph(root: rootScope, forMockGeneration: false), answeringOtherFieldsFrom: treeReads)
		}
		if let observer {
			observer(comparison(of: seam, treeReads: treeReads, factsReads: factsReads))
		}
		switch producer {
		case .tree:
			return treeReads
		case .facts:
			return factsReads
		}
	}

	/// The facts' `SeamTreeReads` of `seam`'s tree, `factsReads`, compared with the tree's, `treeReads`.
	private static func comparison(of seam: Instantiable, treeReads: SeamTreeReads, factsReads: SeamTreeReads) -> SeamTreeReadsComparison {
		var factsReads = factsReads
		if let perturbedField = SeamTreeReadsObservation.perturbsFactsField {
			factsReads = factsReads.emptying(perturbedField)
		}
		var differences = [SeamTreeReadsComparison.Difference]()
		for field in SeamTreeReadsObservation.FactsField.allCases {
			let tree = treeReads.spelling(of: field)
			let facts = factsReads.spelling(of: field)
			if tree != facts {
				differences.append(SeamTreeReadsComparison.Difference(field: field.rawValue, tree: tree, facts: facts))
			}
		}
		return SeamTreeReadsComparison(seam: seam.concreteInstantiable.asSource, differences: differences)
	}
}

/// What a test observes of a seam's `SeamTreeReads`: on every signature pass of every seam, the fields the facts produce,
/// compared with the tree's.
public enum SeamTreeReadsObservation {
	/// The fields the facts of a seam's tree produce at its root, which the comparison compares.
	public enum FactsField: String, CaseIterable, Sendable {
		case requiredAliasFulfillingProperties
		case typesDeclaredEscaping
		/// For each label, whether the tree reads it where a parameter is its nearest declaration, and whether inside a
		/// `@Sendable` function.
		case parameterReads
	}

	/// The fields still read from the tree in both values, which the comparison cannot tell apart yet. What the facts lack
	/// for each is said in the pull request that moves it to `FactsField`.
	public enum TreeField: String, CaseIterable, Sendable {
		/// What the tree requires of the caller, the receives inside the fills of the seam calls it makes among them. The
		/// facts' `requiredIncludingFills` row lacks two of a fill's per-route facts: the instance a memo the fill is handed
		/// serves, which its struct-bound row does not hide, and the caller's memo a carried route hands, which it hides.
		case requiredReceivedProperties
		/// Each receive's declaring type, alias, module, and the tier facts of the nested seam call that omits it.
		case receivers
		/// The builder function names, with and without the hole sites' wrappers.
		case builderFunctionNames
	}

	/// Which value a signature pass proceeds with.
	public enum Producer: Sendable {
		/// The tree's, as every run reads it.
		case tree
		/// The facts' for each `FactsField`, the tree's for each `TreeField`.
		case facts
	}

	/// The value every signature pass proceeds with. Only a test sets it to anything but `.tree`.
	@TaskLocal public static var producer: Producer = .tree

	/// Handed each comparison, where set. Only a test sets it.
	@TaskLocal public static var comparesFacts: (@Sendable (SeamTreeReadsComparison) -> Void)?

	/// A field the facts' value is handed emptied, so a test sees the comparison fail. Only a test sets it.
	@TaskLocal public static var perturbsFactsField: FactsField?
}

/// One signature pass's `SeamTreeReads` of one seam, from its tree and from its facts.
public struct SeamTreeReadsComparison: Sendable {
	/// A field whose two values differ, each spelled as `SeamTreeReads.spelling(of:)` spells it.
	public struct Difference: Sendable, Equatable {
		public let field: String
		public let tree: [String]
		public let facts: [String]
	}

	/// The seam's concrete type.
	public let seam: String
	/// The fields that differ, in `FactsField` order.
	public let differences: [Difference]
}

extension DependencyTreeGenerator.ParameterReads {
	/// The reads of the seam's parameters the facts of its tree, `graph`, hold, as `receivers(in:of:instantiables:)` finds
	/// them on the tree, for every label the world interns: a label the world does not hold is read by no scope of the tree.
	/// - A receive, an alias's fulfilling label, a nested seam call's parameters and a cycle-closing scope's call, each
	///   where no scope enclosing it declares the label and no fill enclosing it binds the label from its site's struct,
	///   are the labels the root's subtree reads from above it (`ReadsBeneathFills`).
	/// - A hole's site reads every label none of the scopes enclosing it declares and no fill enclosing it binds: a hole
	///   that a route from the root reaches through no node binding the label (`labelsReadAtSites(in:readsBeneathFills:)`).
	/// - A read inside a `@Sendable` function is a label the subtree beneath an edge that opens one reads from above it,
	///   which no node on the route to that edge binds (`labelsReadInsideSendableFunction(in:readsBeneathFills:)`), or a
	///   parameter a nested seam's call takes `@Sendable` (`labelsSeamCallsTakeSendable(in:readsBeneathFills:)`).
	init(facts graph: TypeFactsGraph) {
		self.init()
		let readsBeneathFills = ReadsBeneathFills(graph: graph)
		for label in readsBeneathFills.labels(of: 0) {
			labelsRead.insert(graph.labelTexts[Int(label)])
		}
		labelsRead.formUnion(Self.labelsReadAtSites(in: graph, readsBeneathFills: readsBeneathFills))
		labelsReadInsideSendableFunction = Self.labelsReadInsideSendableFunction(in: graph, readsBeneathFills: readsBeneathFills)
		let labelsSeamCallsTakeSendable = Self.labelsSeamCallsTakeSendable(in: graph, readsBeneathFills: readsBeneathFills)
		labelsRead.formUnion(labelsSeamCallsTakeSendable)
		labelsReadInsideSendableFunction.formUnion(labelsSeamCallsTakeSendable)
	}

	/// The labels each node's subtree in `graph` reads from above it, as `TypeFactsWorld.labels(of:)` holds them, but with
	/// what each fill binds from its site's struct hidden along the fill's edge (`TypeFactsReceives.boundFromScopeStruct(atEdge:)`),
	/// as `receivers(in:of:instantiables:)` declares a fill's struct-bound labels (`ScopeGenerator.fillStructBoundLabels`).
	/// A fold of the graph's label IDs over the labels each node reads itself, as the graph's own reads take them: an
	/// alias its fulfilling label, a scope its property's label, its receives, and the fulfilling labels of its aliases of
	/// what it does not create. A call's reads of the caller for the fills it passes, which the graph's reads count at the
	/// call, are read here where the tree reads them, beneath the fill's edge, so the fill's struct hides them. Built once
	/// per facts value, it holds a row of label IDs per node and one per edge, and dies with `ParameterReads(facts:)`.
	private struct ReadsBeneathFills {
		init(graph: TypeFactsGraph) {
			var labelIDs = [String: Int32]()
			for (index, label) in graph.labelTexts.enumerated() {
				labelIDs[label] = Int32(index)
			}
			let nodes = graph.graph.nodes
			let labelCount = graph.labelTexts.count
			let own = BitRows(rowCount: nodes.count, columnCount: labelCount) { index, insert in
				for label in Self.ownLabels(of: nodes[index]) {
					labelIDs[label].map(insert)
				}
			}
			let hidden = BitRows(rowCount: nodes.count, columnCount: labelCount) { index, insert in
				for binding in graph.worldBindings(of: index) {
					insert(binding.label)
				}
			}
			let hiddenAtEdge = BitRows(rowCount: graph.graph.edgeCount, columnCount: labelCount) { edge, insert in
				for property in graph.receives.boundFromScopeStruct(atEdge: edge) {
					labelIDs[graph.propertyTable[Int(property)].label].map(insert)
				}
			}
			self.hiddenAtEdge = hiddenAtEdge
			reads = ReadsFromAbove(graph: graph.graph, own: own, hidden: hidden, hiddenAtEdge: hiddenAtEdge)
		}

		/// The label IDs `node`'s subtree reads from above it.
		func labels(of node: Int32) -> [Int32] {
			reads.rows.columns(inRow: Int(node))
		}

		/// Whether the fill along `edge`, by its position among the graph's edges, binds `label` from its site's struct.
		func edge(_ edge: Int, bindsFromScopeStruct label: Int32) -> Bool {
			hiddenAtEdge.contains(label, inRow: edge)
		}

		/// The labels a node's own declaration reads, as `TypeFactsGraph`'s own reads of it name them.
		private static func ownLabels(of node: TypeFactsDeclaration) -> [String] {
			switch node.key.leaf {
			case .alias:
				return node.aliasFulfillingProperty.map { [$0.label] } ?? []
			case .hole:
				return []
			case .none:
				break
			}
			var labels = [String]()
			if let property = node.property {
				labels.append(property.label)
			}
			let dependencies = node.scope.instantiable.dependencies
			var createdLabels = Set<String>()
			for dependency in dependencies {
				switch dependency.source {
				case .instantiated, .forwarded:
					createdLabels.insert(dependency.property.label)
				case .received, .aliased:
					break
				}
			}
			for dependency in dependencies {
				switch dependency.source {
				case .instantiated, .forwarded:
					break
				case .received:
					labels.append(dependency.property.label)
				case let .aliased(fulfillingProperty, _, _):
					if !createdLabels.contains(fulfillingProperty.label) {
						labels.append(fulfillingProperty.label)
					}
				}
			}
			return labels
		}

		private let reads: ReadsFromAbove
		private let hiddenAtEdge: BitRows
	}

	/// Each label a call of a nested seam in `graph`'s tree passes a parameter the called tier takes `@Sendable`
	/// (`SeamSignature.Parameter.deferral`), where no node on the route from the root to the call binds it and no fill on
	/// that route binds it from its site's struct: the called seam reads it inside a `@Sendable` function, wherever the
	/// tree calls it. The call's own bindings are its type's, which its parameters are not read beneath. Every edge is
	/// followed, a fill's and one that opens a function included, as `receivers(in:of:instantiables:)` visits every scope;
	/// a visit is a node with the labels the nodes and fills above it bind, of those its subtree reads from above, and the
	/// visits made die with the walk.
	private static func labelsSeamCallsTakeSendable(in graph: TypeFactsGraph, readsBeneathFills: ReadsBeneathFills) -> Set<String> {
		struct Visit: Hashable {
			let node: Int32
			let boundLabels: Set<Int32>
		}
		var labels = Set<String>()
		var visits = Set<Visit>()
		var pending = [Visit(node: 0, boundLabels: [])]
		while let visit = pending.popLast() {
			guard visits.insert(visit).inserted else { continue }
			let declaration = graph.graph.nodes[Int(visit.node)]
			if declaration.key.leaf == .none, let seamCall = declaration.scope.seamCall {
				let boundLabelTexts = Set(visit.boundLabels.map { graph.labelTexts[Int($0)] })
				for parameter in seamCall.parameters where parameter.deferral == .deferred(isSendable: true) && !boundLabelTexts.contains(parameter.property.label) {
					labels.insert(parameter.property.label)
				}
			}
			var boundLabels = visit.boundLabels
			for binding in graph.worldBindings(of: Int(visit.node)) {
				boundLabels.insert(binding.label)
			}
			for (target, edge) in zip(graph.edges(from: visit.node), graph.graph.edgeIndices(from: Int(visit.node))) {
				let labelsOfTarget = readsBeneathFills.labels(of: target)
				var targetBoundLabels = Set<Int32>()
				for label in labelsOfTarget where boundLabels.contains(label) || readsBeneathFills.edge(edge, bindsFromScopeStruct: label) {
					targetBoundLabels.insert(label)
				}
				pending.append(Visit(node: target, boundLabels: targetBoundLabels))
			}
		}
		return labels
	}

	/// Each label some hole's site in `graph` reads: a hole reached from the root along a route on which no node binds the
	/// label and no fill binds it from its site's struct. One walk of the graph per label, each node visited once; it holds
	/// a set of the nodes visited, which dies with the walk.
	private static func labelsReadAtSites(in graph: TypeFactsGraph, readsBeneathFills: ReadsBeneathFills) -> Set<String> {
		var labels = Set<String>()
		guard graph.holesBeneath.contains(0, inRow: 0) else { return labels }
		for label in graph.labelTexts.indices {
			var visited: Set = [0]
			var pending = [0]
			var reachesSite = false
			while !reachesSite, let node = pending.popLast() {
				guard !graph.worldBindings(of: node).contains(where: { $0.label == Int32(label) }) else { continue }
				for (target, edge) in zip(graph.edges(from: Int32(node)).map(Int.init), graph.graph.edgeIndices(from: node)) where !readsBeneathFills.edge(edge, bindsFromScopeStruct: Int32(label)) {
					if graph.kind(of: Int32(target)) == .hole {
						reachesSite = true
					} else if visited.insert(target).inserted {
						pending.append(target)
					}
				}
			}
			if reachesSite {
				labels.insert(graph.labelTexts[label])
			}
		}
		return labels
	}

	/// Each label `graph`'s tree reads inside a `@Sendable` function: one its subtree beneath an edge that opens such a
	/// function (`TypeFactsEdge.opens`) reads from above it, where no node on the route from the root to the edge binds
	/// it and, for a fill's edge, the fill does not bind it from its site's struct. A route is walked only in plain code:
	/// beneath such an edge, what the subtree reads from above it already holds every read beneath. A fill that is no
	/// `@Sendable` function is not entered: the call hands it what its tree reads from the caller's scope where the call
	/// is, in plain code (`ScopeGenerator.FillCallerReads`). A visit is a node with the labels the nodes above it bind, of
	/// those its subtree reads from above, which alone decide a read beneath it; the visits made die with the walk.
	private static func labelsReadInsideSendableFunction(in graph: TypeFactsGraph, readsBeneathFills: ReadsBeneathFills) -> Set<String> {
		struct Visit: Hashable {
			let node: Int32
			let boundLabels: Set<Int32>
		}
		var labels = Set<String>()
		var visits = Set<Visit>()
		var pending = [Visit(node: 0, boundLabels: [])]
		while let visit = pending.popLast() {
			guard visits.insert(visit).inserted else { continue }
			var boundLabels = visit.boundLabels
			for binding in graph.worldBindings(of: Int(visit.node)) {
				boundLabels.insert(binding.label)
			}
			for ((target, edgeFacts), edge) in zip(zip(graph.edges(from: visit.node), graph.edgeFacts(from: visit.node)), graph.graph.edgeIndices(from: Int(visit.node))) {
				let labelsOfTarget = readsBeneathFills.labels(of: target)
				if edgeFacts.opens.isSendableFunction {
					for label in labelsOfTarget where !boundLabels.contains(label) && !readsBeneathFills.edge(edge, bindsFromScopeStruct: label) {
						labels.insert(graph.labelTexts[Int(label)])
					}
				} else if !edgeFacts.isFill {
					pending.append(Visit(node: target, boundLabels: boundLabels.intersection(labelsOfTarget)))
				}
			}
		}
		return labels
	}
}

extension TypeFactsFunctionOpened {
	/// Whether the function the edge opens is `@Sendable`.
	fileprivate var isSendableFunction: Bool {
		switch self {
		case .none, .instantiatorBuilder:
			false
		case .sendableInstantiatorBuilder, .sendableLazyWrapper, .otherSendableFunction:
			true
		}
	}
}

extension Property {
	/// The property as `TypeDescription`'s `==` reads it: `any P` as `P`.
	fileprivate var spelledAsEqualityReadsIt: String {
		Property(label: label, typeDescription: typeDescription.withoutAny).asSource
	}
}
