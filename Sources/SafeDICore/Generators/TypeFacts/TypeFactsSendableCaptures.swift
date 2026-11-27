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
/// Every `@Sendable` function in a root's tree that would capture an `Instantiator`, `ErasedInstantiator` or
/// `LazilyInstantiated` declared outside it, read from the root's per-type graph (`TypeFactsGraph`) rather than from a
/// walk of its generator tree (`ScopeGenerator.nonSendableWrapperCaptures(ofTreeRootedAt:)`), which entered every path
/// to a type.
///
/// A receive reads the declaration the received-values fold finds (`TypeFactsReceivedValueSupplies`), and captures it
/// where a `@Sendable` function encloses the receive but not the declaration. That depends on the path, so the fold
/// carries, per label and node, the pairs of the edge whose source binds the label and the first edge beneath that
/// source that opens a `@Sendable` function, which the paths to the node give together, with the path that first gave
/// each pair, which names the chain an error prints. A capture is reported once per receive and declaration it reads,
/// whichever builders and chains reach it (the ruling that a capture is reported once per capturing function).
///
/// A node's function is `@Sendable` where its wrapper is, or where a call of it that closes a cycle is made inside a
/// `@Sendable` function beneath it, or hands it to a `Sendable` wrapper (`ScopeGenerator.cycleClosings`). An edge whose
/// target, or the target's twin, dominates its source closes a cycle on every path, so it builds nothing and hands
/// nothing on.
///
/// Three kinds of tree are refused, by name, and their captures read from the walk: a mock root, whose root binds what
/// `mock()` is passed; a tree with fills, whose trees read the fields of the case each fills; and a tree whose lazy cycle
/// closes on a function that may take parameters (`CycleParameter`), which the graph does not hold. It holds the
/// captures for as long as its owner keeps them; the graph dies with `init`.
struct TypeFactsSendableCaptures: Sendable {
	/// Why the fold leaves a root to the walk.
	enum Refusal: String, CaseIterable, Sendable {
		/// The root is a mock's, whose root binds the values `mock()` is passed and the dependencies it cannot build.
		case mockRoot
		/// The tree passes fills, whose trees read the fields of the cases they fill.
		case treeWithFills
		/// A lazy cycle closes on a function a label it reads from above may be declared again before: the function takes
		/// that label as a parameter, which the graph does not hold yet.
		case cycleFunctionTakesParameters
	}

	/// - Parameters:
	///   - root: The root's scope.
	///   - instantiable: The type the root builds.
	///   - seamRoot: The seam the root is, whose parameters its tree reads where nothing above declares their labels.
	init(root: ConstructionScope, instantiable: Instantiable, seamRoot: ScopeGenerator.SeamRoot?) {
		let facts = TypeFactsGraph(root: root, forMockGeneration: false)
		let graph = facts.graph
		let nodes = graph.nodes
		let edgeFacts = facts.edgeFacts
		var work = 0

		var sourceByEdge = [Int32](repeating: 0, count: graph.edgeCount)
		for index in nodes.indices {
			for edge in graph.edgeIndices(from: index) {
				sourceByEdge[edge] = Int32(index)
			}
		}

		// Whether each edge closes a cycle wherever it is built: its target, or the target's twin of one cycle identity,
		// dominates its source, so every path to the edge holds a build of it already. The node it closes on, else -1.
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
		var closedOnByEdge = [Int32](repeating: -1, count: graph.edgeCount)
		for edge in 0..<graph.edgeCount where !edgeFacts[edge].isFill && nodes[Int(graph.edgeTargets[edge])].key.leaf == .none {
			let target = Int(graph.edgeTargets[edge])
			let source = Int(sourceByEdge[edge])
			for candidate in [target, Int(facts.twins[target])] where candidate >= 0 && dominates(candidate, source) {
				closedOnByEdge[edge] = Int32(candidate)
				break
			}
		}

		// The nodes the tree builds, and each node's edges in that build: none through a fill or an edge that closes a cycle.
		var isBuilt = [Bool](repeating: false, count: nodes.count)
		isBuilt[0] = true
		var edgesInto = [[Int32]](repeating: [], count: nodes.count)
		var nodesToReach = [0]
		var holdsFill = false
		while let index = nodesToReach.popLast() {
			if graph.edgeIndices(from: index).contains(where: { edgeFacts[$0].isFill }) {
				holdsFill = true
			}
			for edge in graph.edgeIndices(from: index) where !edgeFacts[edge].isFill && closedOnByEdge[edge] < 0 {
				let target = Int(graph.edgeTargets[edge])
				edgesInto[target].append(Int32(edge))
				if !isBuilt[target] {
					isBuilt[target] = true
					nodesToReach.append(target)
				}
			}
		}
		let closingEdges = (0..<graph.edgeCount).filter { closedOnByEdge[$0] >= 0 && isBuilt[Int(sourceByEdge[$0])] }

		// The label IDs the graph names, and the label each node is built as.
		var labelIDByText = [String: Int32]()
		for (id, text) in facts.labelTexts.enumerated() {
			labelIDByText[text] = Int32(id)
		}
		func labelID(of text: String) -> Int32 {
			labelIDByText[text] ?? -1
		}
		let labelByNode = nodes.map { node in node.property.map { labelID(of: $0.label) } ?? -1 }

		var refusals = [Refusal]()
		if holdsFill {
			refusals.append(.treeWithFills)
		}
		// A label the closed-on node reads from above that a node between it and the call that closes the cycle binds may
		// reach the call through that binding, which the function then takes as a parameter. The closed-on node dominates
		// the call, so the nodes that reach the call without passing it are those between.
		for edge in closingEdges {
			let closedOn = Int(closedOnByEdge[edge])
			let readLabels = Set(facts.labelColumn[Int(facts.labelOffsets[closedOn])..<Int(facts.labelOffsets[closedOn + 1])]).subtracting([labelByNode[closedOn]])
			let source = Int(sourceByEdge[edge])
			var visited: Set = [source]
			var nodesToClimb = source == closedOn ? [] : [source]
			var takesParameters = false
			while !takesParameters, let node = nodesToClimb.popLast() {
				work += 1
				takesParameters = facts.worldBindings(of: node).contains { readLabels.contains($0.label) }
				for inEdge in edgesInto[node] where Int(sourceByEdge[Int(inEdge)]) != closedOn && visited.insert(Int(sourceByEdge[Int(inEdge)])).inserted {
					nodesToClimb.append(Int(sourceByEdge[Int(inEdge)]))
				}
			}
			if takesParameters {
				refusals.append(.cycleFunctionTakesParameters)
				break
			}
		}
		guard refusals.isEmpty else {
			self.refusals = refusals
			captures = []
			return
		}

		// Whether each node's builder function is `@Sendable`: its own wrapper's, or one a cycle's call makes so.
		var buildsInSendableFunction = nodes.indices.map { index in
			isBuilt[index] && nodes[index].key.leaf == .none && nodes[index].property?.propertyType.isSendable == true
		}
		var changed = !closingEdges.isEmpty
		while changed {
			changed = false
			for edge in closingEdges where !buildsInSendableFunction[Int(closedOnByEdge[edge])] {
				let closedOn = Int(closedOnByEdge[edge])
				var isReferencedFromSendableFunction = nodes[Int(graph.edgeTargets[edge])].property?.propertyType.isSendable == true
				// A `@Sendable` function between the closed-on node and the call holds the call. Every path to the call passes
				// the closed-on node, so the nodes that reach the call without passing it are those between.
				var visited: Set = [Int(sourceByEdge[edge])]
				var nodesToClimb = [Int(sourceByEdge[edge])]
				while !isReferencedFromSendableFunction, let node = nodesToClimb.popLast() {
					work += 1
					if buildsInSendableFunction[node] {
						isReferencedFromSendableFunction = true
					}
					for inEdge in edgesInto[node] where Int(sourceByEdge[Int(inEdge)]) != closedOn && visited.insert(Int(sourceByEdge[Int(inEdge)])).inserted {
						nodesToClimb.append(Int(sourceByEdge[Int(inEdge)]))
					}
				}
				if isReferencedFromSendableFunction {
					buildsInSendableFunction[closedOn] = true
					changed = true
				}
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

		// The seam's parameters, which its tree reads where nothing above declares their labels: a deferred one as the
		// `LazilyInstantiated` its body holds it in, but for the one its own alias reads.
		let seamParameters: [Declaration] = if let seamRoot {
			seamRoot.signature.parameters.map { [autoclosureCallByLabel = seamRoot.autoclosureCallByLabel(of: instantiable)] parameter in
				if case let .deferred(isSendable) = parameter.deferral, autoclosureCallByLabel[parameter.property.label] == nil {
					Declaration(
						property: Property(
							label: parameter.property.label,
							typeDescription: .simple(
								name: isSendable ? Dependency.sendableLazilyInstantiatedType : Dependency.lazilyInstantiatedType,
								generics: [parameter.property.typeDescription],
							),
						),
						instanceProperty: parameter.property,
						declaringType: nil,
						declarationLocation: nil,
					)
				} else {
					Declaration(
						property: parameter.property,
						instanceProperty: parameter.property.asLazilyInstantiatedInstancePropertyOfDeclaredBinding,
						declaringType: nil,
						declarationLocation: nil,
					)
				}
			}
		} else {
			[]
		}

		/// The declaration the binding of `label` that `edge`'s source makes hands a receive of `unwrappedProperty`, or `nil`
		/// where it hands none, or hands `nil`: the first binding of the label that provides it, available where it is bound
		/// before the edge's child or the two are members of one loop of builders.
		func provider(handedBy edge: Int32, label: Int32, receiving unwrappedProperty: Property) -> Declaration? {
			work += 1
			guard edge != Self.noDeclaration else {
				return seamParameters.first { $0.property.label == facts.labelTexts[Int(label)] && $0.provides(unwrappedProperty) }
			}
			let source = Int(sourceByEdge[Int(edge)])
			let offset = Int(facts.bindingOffsets[source])
			/// The instance a by-value receive reads of `property`, the binding at `index` of the source's bindings.
			func instanceProperty(of property: Property, boundAt index: Int) -> Property? {
				let bindingEdge = edgeByBinding[offset + index]
				return if bindingEdge >= 0, nodes[Int(graph.edgeTargets[Int(bindingEdge)])].key.leaf != .alias {
					property.asLazilyInstantiatedInstanceProperty
				} else {
					property.asLazilyInstantiatedInstancePropertyOfDeclaredBinding
				}
			}
			guard let match = facts.worldBindings(of: source).enumerated().first(where: { index, binding in
				let property = facts.propertyTable[Int(binding.property)]
				return binding.label == label && (property.asUnwrappedProperty == unwrappedProperty || instanceProperty(of: property, boundAt: index)?.asUnwrappedProperty == unwrappedProperty)
			}) else {
				return nil
			}
			let index = match.offset
			let property = facts.propertyTable[Int(match.element.property)]
			let bindingEdge = edgeByBinding[offset + index]
			let edgeFact = edgeFacts[Int(edge)]
			let isRebound = edgeFact.loop >= 0 && bindingEdge >= 0 && edgeFacts[Int(bindingEdge)].loop == edgeFact.loop
			guard index < Int(edgeFact.bindingsBefore) || isRebound else { return nil }
			let declaringInstantiable = nodes[source].scope.instantiable
			let declarationLocation = declaringInstantiable.dependencies.last { !$0.source.isReceived && $0.property == property }.map(\.declarationLocation)
			return Declaration(
				property: property,
				instanceProperty: instanceProperty(of: property, boundAt: index),
				declaringType: declarationLocation == nil ? nil : declaringInstantiable.concreteInstantiable,
				declarationLocation: declarationLocation ?? nil,
			)
		}

		// The labels whose reads can capture: those a node of the tree, or the seam, declares as a wrapper that is not
		// `Sendable`.
		var capturableLabels = Set<Int32>()
		for index in nodes.indices where isBuilt[index] {
			for binding in facts.worldBindings(of: index) where facts.propertyTable[Int(binding.property)].propertyType.isNonSendableWrapper {
				capturableLabels.insert(binding.label)
			}
		}
		for parameter in seamParameters where parameter.property.propertyType.isNonSendableWrapper {
			capturableLabels.insert(labelID(of: parameter.property.label))
		}

		// The nodes of each component, the root's last.
		var nodesByComponent = [[Int]](repeating: [], count: graph.componentCount)
		for index in nodes.indices where isBuilt[index] {
			nodesByComponent[Int(graph.componentByNode[index])].append(index)
		}

		var pathsByLabel = [Int32: Paths]()
		/// What a receive of `label` reads at each node, with the first `@Sendable` function each path to it opens beneath the
		/// declaration: the edge into the node where its source binds the label, else what the source reads.
		func paths(ofLabel label: Int32) -> Paths {
			if let paths = pathsByLabel[label] {
				return paths
			}
			let bindsLabel = nodes.indices.map { node in facts.worldBindings(of: node).contains { $0.label == label } }
			var paths = Paths(nodeCount: nodes.count)
			paths.insert(Pair(edge: Self.noDeclaration, sendableEdge: Self.noFunction), at: 0, through: Self.noFunction, from: -1)
			for component in nodesByComponent.reversed() {
				// A component of one node that no edge of its own enters takes one pass; any other, passes until none changes.
				let isCycle = component.count > 1 || edgesInto[component[0]].contains { sourceByEdge[Int($0)] == Int32(component[0]) }
				var changed = true
				while changed {
					changed = false
					for node in component {
						for edge in edgesInto[node] {
							let source = Int(sourceByEdge[Int(edge)])
							let opensSendableFunction = buildsInSendableFunction[node]
							if bindsLabel[source] {
								work += 1
								if paths.insert(Pair(edge: edge, sendableEdge: opensSendableFunction ? edge : Self.noFunction), at: node, through: edge, from: -1), isCycle {
									changed = true
								}
							} else {
								for (index, pair) in paths.pairs[source].enumerated() {
									work += 1
									let sendableEdge = pair.sendableEdge != Self.noFunction || !opensSendableFunction ? pair.sendableEdge : edge
									if paths.insert(Pair(edge: pair.edge, sendableEdge: sendableEdge), at: node, through: edge, from: Int32(index)), isCycle {
										changed = true
									}
								}
							}
						}
					}
				}
			}
			pathsByLabel[label] = paths
			return paths
		}

		// The first edge the build meets into each node, for the chains.
		var firstEdgeInto = [Int32](repeating: -1, count: nodes.count)
		for index in nodes.indices where isBuilt[index] {
			for edge in graph.edgeIndices(from: index) where !edgeFacts[edge].isFill && closedOnByEdge[edge] < 0 && firstEdgeInto[Int(graph.edgeTargets[edge])] < 0 && Int(graph.edgeTargets[edge]) != 0 {
				firstEdgeInto[Int(graph.edgeTargets[edge])] = Int32(edge)
			}
		}

		/// The types from the root to `node` along the path that first gave the pair at `index`.
		func chain(to node: Int, pairAt index: Int, in labelPaths: Paths) -> [TypeDescription] {
			var chain = [TypeDescription]()
			var node = node
			var index = index
			while true {
				work += 1
				chain.append(facts.typeTable[Int(facts.builtTypes[node])])
				let origin = labelPaths.origins[node][index]
				guard origin.edge != Self.noFunction else { break }
				let source = Int(sourceByEdge[Int(origin.edge)])
				guard origin.pairIndex >= 0 else {
					// The source binds the label: the path to it is the one the build first meets.
					node = source
					while true {
						work += 1
						chain.append(facts.typeTable[Int(facts.builtTypes[node])])
						guard node != 0 else { break }
						node = Int(sourceByEdge[Int(firstEdgeInto[node])])
					}
					break
				}
				node = source
				index = Int(origin.pairIndex)
			}
			return chain.reversed()
		}

		var captures = [ScopeGenerator.NonSendableWrapperCapture]()
		var reportedKeys = Set<String>()
		/// Records the captures a read of `receivedProperty` under `label`, at `node`'s body, makes. A seam call that defers
		/// the parameter `@Sendable` reads it in a `@Sendable` closure of its own (`deferringSeam`).
		func recordCaptures(of receivedProperty: Property, declaredAt declarationLocation: Dependency.DeclarationLocation?, label: Int32, at node: Int, deferringSeam: (property: Property, type: TypeDescription)?) {
			guard capturableLabels.contains(label) else { return }
			let labelPaths = paths(ofLabel: label)
			let unwrappedProperty = receivedProperty.asUnwrappedProperty
			for (index, pair) in labelPaths.pairs[node].enumerated() {
				// The `@Sendable` function that reads the label: the innermost builder function on the pair's path, else the
				// seam's `@Sendable` autoclosure of a deferred parameter.
				let sendableFunction: (builder: Property, declaringType: TypeDescription, capturingSeamType: TypeDescription?)? = if pair.sendableEdge != Self.noFunction {
					(
						builder: nodes[Int(graph.edgeTargets[Int(pair.sendableEdge)])].property ?? receivedProperty,
						declaringType: facts.typeTable[Int(facts.builtTypes[Int(sourceByEdge[Int(pair.sendableEdge)])])],
						capturingSeamType: nil,
					)
				} else {
					deferringSeam.map { (builder: $0.property, declaringType: $0.type, capturingSeamType: $0.type) }
				}
				if let sendableFunction,
				   let declaration = provider(handedBy: pair.edge, label: label, receiving: unwrappedProperty),
				   declaration.property.propertyType.isNonSendableWrapper
				{
					let capture = ScopeGenerator.NonSendableWrapperCapture(
						receivedProperty: receivedProperty,
						declarationLocation: declarationLocation,
						chain: chain(to: node, pairAt: index, in: labelPaths),
						sendableBuilder: sendableFunction.builder,
						sendableBuilderDeclaringType: sendableFunction.declaringType,
						capturingSeamType: sendableFunction.capturingSeamType,
						capturingFillSeamType: nil,
						capturingFillIsPassedOn: false,
						wrapperProperty: declaration.property,
						wrapperDeclaringType: declaration.declaringType,
						wrapperDeclarationLocation: declaration.declarationLocation,
					)
					if reportedKeys.insert(capture.comparedSpelling).inserted {
						captures.append(capture)
					}
				}
			}
		}

		for (index, node) in nodes.enumerated() where isBuilt[index] {
			if let alias = node.alias {
				// The alias is bound in its declaring scope, where its fulfilling property is read, unless the scope binds that
				// label itself: then the read is of a declaration of its own body. One that keeps its label is not in scope
				// where it is read.
				let label = labelID(of: alias.fulfillingProperty.label)
				for edge in edgesInto[index] where alias.fulfillingProperty.label == alias.property.label || !facts.worldBindings(of: Int(sourceByEdge[Int(edge)])).contains(where: { $0.label == label }) {
					let source = Int(sourceByEdge[Int(edge)])
					let declarationLocation = node.scope.instantiable.dependencies.last { !$0.source.isReceived && $0.property == alias.property }.map(\.declarationLocation) ?? nil
					recordCaptures(of: alias.fulfillingProperty, declaredAt: declarationLocation, label: label, at: source, deferringSeam: nil)
				}
			} else if node.key.leaf == .none {
				let sendableDeferredLabels = Set(node.scope.seamCall?.parameters.filter { $0.deferral == .deferred(isSendable: true) }.map(\.property.label) ?? [])
				for dependency in node.scope.instantiable.dependencies where dependency.source.isReceived {
					let deferringSeam: (property: Property, type: TypeDescription)? = if let property = node.property, sendableDeferredLabels.contains(dependency.property.label) {
						(property, node.scope.instantiable.concreteInstantiable)
					} else {
						nil
					}
					recordCaptures(of: dependency.property, declaredAt: dependency.declarationLocation, label: labelID(of: dependency.property.label), at: index, deferringSeam: deferringSeam)
				}
			}
		}

		self.refusals = []
		self.captures = captures
		GenerationWork.record(work, by: .findingSendableCaptures)
	}

	/// Why the fold leaves the root to the walk, in the order checked; empty where it read the root.
	let refusals: [Refusal]
	/// Each capture the tree makes, once per receive and declaration it reads, in the order the fold finds them.
	let captures: [ScopeGenerator.NonSendableWrapperCapture]

	/// A declaration a receive can read: a node's binding, or a seam's parameter.
	private struct Declaration {
		let property: Property
		/// The by-value property with which receivers read the instance of `property`, when it is lazily instantiated.
		let instanceProperty: Property?
		/// `nil` for a parameter of the seam whose tree this is, and for a binding its type does not declare itself.
		let declaringType: TypeDescription?
		let declarationLocation: Dependency.DeclarationLocation?

		/// Whether a receive of `unwrappedProperty`, or of its optional form, resolves to this declaration.
		func provides(_ unwrappedProperty: Property) -> Bool {
			property.asUnwrappedProperty == unwrappedProperty || instanceProperty?.asUnwrappedProperty == unwrappedProperty
		}
	}

	/// What a receive reads at a node along some path to it: the edge whose source binds the label (`noDeclaration` for
	/// none), and the first edge beneath that source that opens a `@Sendable` function on the path (`noFunction` for none).
	private struct Pair: Hashable {
		let edge: Int32
		let sendableEdge: Int32
	}

	/// The pairs at each node, each with the edge and the pair at the edge's source that first gave it.
	private struct Paths {
		init(nodeCount: Int) {
			pairs = [[Pair]](repeating: [], count: nodeCount)
			origins = [[Origin]](repeating: [], count: nodeCount)
			seen = [Set<Pair>](repeating: [], count: nodeCount)
		}

		/// Adds `pair` at `node`, first given through `edge` from the source's pair at `pairIndex` (-1 where the source binds
		/// the label), and returns whether it is new.
		@discardableResult
		mutating func insert(_ pair: Pair, at node: Int, through edge: Int32, from pairIndex: Int32) -> Bool {
			guard seen[node].insert(pair).inserted else { return false }
			pairs[node].append(pair)
			origins[node].append(Origin(edge: edge, pairIndex: pairIndex))
			return true
		}

		struct Origin {
			let edge: Int32
			let pairIndex: Int32
		}

		private(set) var pairs: [[Pair]]
		private(set) var origins: [[Origin]]
		private var seen: [Set<Pair>]
	}

	/// The element of a node's pairs that stands for no declaration of the label above it.
	private static let noDeclaration: Int32 = -1
	/// The element of a pair that stands for no `@Sendable` function opened beneath the declaration.
	private static let noFunction: Int32 = -1
}

/// The captures of each root the fold finds beside those the walk of its generator tree finds
/// (`ScopeGenerator.nonSendableWrapperCaptures(ofTreeRootedAt:)`), handed to `comparesWalk`, which the tests set, never
/// the tool: the two must be equal, as sets of what an error reports but for the chain and the builder it names, on
/// every root the fold does not refuse. The walk runs for a refused root, and where it is set, uncounted by
/// `GenerationWork`.
public enum TypeFactsSendableCapturesObservation {
	@TaskLocal public static var comparesWalk: (@Sendable (TypeFactsSendableCapturesComparison) -> Void)?
}

/// One root's captures, from the fold and from the walk, each spelled with what its error reports but for the chain and
/// the builder it names.
public struct TypeFactsSendableCapturesComparison: Sendable {
	/// The root's type.
	public let root: String
	/// Why the fold left the root to the walk, by name, the first first; empty where it read the root.
	public let refusals: [String]
	/// What the fold finds, empty where it refused the root.
	public let folded: [String]
	/// What the walk of the root's generator tree finds.
	public let walked: [String]
}

extension ScopeGenerator.NonSendableWrapperCapture {
	/// The capture spelled with every part its error reads but the chain and the builder, which the fold reports once per
	/// receive and declaration whatever builders and chains reach it.
	var comparedSpelling: String {
		"""
		\(receivedProperty.asSource) at \(declarationLocation.map { String(describing: $0) } ?? "nowhere") \
		captures \(wrapperProperty.asSource) of \(wrapperDeclaringType?.asSource ?? "no type") \
		at \(wrapperDeclarationLocation.map { String(describing: $0) } ?? "nowhere")\
		\(capturingSeamType.map { " through \($0.asSource)’s initializer" } ?? "")\
		\(capturingFillSeamType.map { " in a fill of \($0.asSource)\(capturingFillIsPassedOn ? ", passed on" : "")" } ?? "")
		"""
	}
}
