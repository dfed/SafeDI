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

/// Every value a root's tree holds for a parameter a seam tier it calls omits, or no tier takes, read from the root's
/// per-type graph (`TypeFactsGraph`) rather than from a walk of its generator tree, which entered every path to a call.
///
/// A call's leaf declares the seam's whole signature, the parameters its tier omits as receives only if available, so
/// the value it would be handed built inline is the one the received-values fold finds for such a receive
/// (`TypeFactsReceivedValueSupplies`): over each edge into the node, the edge itself where its source binds the label,
/// else what its source can read, judged by the source's bindings in order. Where no declaration above binds the label,
/// a seam's own tree reads the seam's parameter of it. Each finding is also located where the module refers to what
/// leads to the call, should the provider's file be unreadable: the closest dependency on the path that a type in one of
/// the module's own files declares, or the root's declaration. That depends on the path, so the fold carries, per node,
/// the pairs of the declaration a receive reads and that reference, which the paths to the node give together.
///
/// Production trees only, and no fill: a fill's tree reads the fields of the case it fills, which the walk does not
/// enter either. It holds the omissions for as long as its owner keeps them; the graph dies with `init`.
struct TypeFactsSeamTierOmissions: Sendable {
	/// - Parameters:
	///   - root: The root's scope.
	///   - instantiable: The type the root builds.
	///   - seamRoot: The seam the root is, whose parameters its tree reads where nothing above declares their labels.
	///   - isOwnFile: Whether a file a declaration records is one of the module's own files.
	init(root: ConstructionScope, instantiable: Instantiable, seamRoot: ScopeGenerator.SeamRoot?, isOwnFile: (String) -> Bool) {
		let facts = TypeFactsGraph(root: root, forMockGeneration: false)
		let graph = facts.graph
		let nodes = graph.nodes
		let edgeFacts = facts.edgeFacts

		// The nodes the tree builds outside every fill, and each node's edges in from those nodes.
		var isBuiltOutsideFills = [Bool](repeating: false, count: nodes.count)
		isBuiltOutsideFills[0] = true
		var nodesToReach = [0]
		while let index = nodesToReach.popLast() {
			for edge in graph.edgeIndices(from: index) where !edgeFacts[edge].isFill && !isBuiltOutsideFills[Int(graph.edgeTargets[edge])] {
				isBuiltOutsideFills[Int(graph.edgeTargets[edge])] = true
				nodesToReach.append(Int(graph.edgeTargets[edge]))
			}
		}
		// Only a call of a seam tier that omits a parameter, or one no tier takes, reports.
		let omittingCalls = nodes.indices.compactMap { index -> (node: Int, seamCall: SeamCall)? in
			guard isBuiltOutsideFills[index], nodes[index].key.leaf == .none, let seamCall = nodes[index].scope.seamCall, !(seamCall.omittedParameters.isEmpty && seamCall.noTierParameters.isEmpty) else { return nil }
			return (index, seamCall)
		}
		guard !omittingCalls.isEmpty else {
			omissions = []
			return
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

		// Where each declaration a node's type makes is declared, by property, as the walk's scopes find it.
		func declarationLocation(of property: Property, declaredBy node: Int) -> Dependency.DeclarationLocation? {
			let declaringInstantiable = nodes[node].scope.instantiable
			guard let dependency = declaringInstantiable.dependencies.last(where: { !$0.source.isReceived && $0.property == property }) else {
				return declaringInstantiable.declarationLocation
			}
			return dependency.declarationLocation
		}

		// The references to what leads to each node, interned: the root's declaration, and each edge's dependency where a
		// type in one of the module's own files declares it.
		var referenceLocations: [Dependency.DeclarationLocation?] = [instantiable.declarationLocation]
		var referenceByLocation = [Dependency.DeclarationLocation: Int32]()
		var referenceByEdge = [Int32](repeating: Self.inheritedReference, count: graph.edgeCount)
		for index in nodes.indices where isBuiltOutsideFills[index] && nodes[index].key.leaf == .none && nodes[index].scope.instantiable.sourceFilePath.map(isOwnFile) == true {
			for edge in graph.edgeIndices(from: index) where !edgeFacts[edge].isFill {
				let location = nodes[Int(graph.edgeTargets[edge])].property.flatMap { property in
					nodes[index].scope.instantiable.dependencies.last { !$0.source.isReceived && $0.property == property }?.declarationLocation
				}
				if let location {
					let reference = referenceByLocation[location] ?? Int32(referenceLocations.count)
					if reference == Int32(referenceLocations.count) {
						referenceByLocation[location] = reference
						referenceLocations.append(location)
					}
					referenceByEdge[edge] = reference
				}
			}
		}
		func reference(through edge: Int32, from reference: Int32) -> Int32 {
			let edgeReference = referenceByEdge[Int(edge)]
			return edgeReference == Self.inheritedReference ? reference : edgeReference
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

		// The nodes a path to an omitting call passes through: what a receive reads at a node depends only on the nodes
		// above it, so the fold reads no other node.
		var work = 0
		var leadsToCall = [Bool](repeating: false, count: nodes.count)
		var nodesToClimb = omittingCalls.map(\.node)
		for call in nodesToClimb {
			leadsToCall[call] = true
		}
		while let node = nodesToClimb.popLast() {
			for edge in edgesInto[node] where !leadsToCall[Int(sourceByEdge[Int(edge)])] {
				work += 1
				leadsToCall[Int(sourceByEdge[Int(edge)])] = true
				nodesToClimb.append(Int(sourceByEdge[Int(edge)]))
			}
		}

		var readsByLabel = [Int32: [Set<Read>]]()
		/// What a receive of `label` reads at each node, with the reference each path to it gives: the edge into the node
		/// where its source binds the label, else what the source reads.
		func reads(ofLabel label: Int32) -> [Set<Read>] {
			if let reads = readsByLabel[label] {
				return reads
			}
			let bindsLabel = nodes.indices.map { node in facts.worldBindings(of: node).contains { $0.label == label } }
			var reads = [Set<Read>](repeating: [], count: nodes.count)
			reads[0] = [Read(edge: Self.noDeclaration, reference: 0)]
			for component in nodesByComponent.reversed() where component.contains(where: { leadsToCall[$0] }) {
				// A component of one node that no edge of its own enters takes one pass; any other, passes until none changes.
				let isCycle = component.count > 1 || edgesInto[component[0]].contains { sourceByEdge[Int($0)] == Int32(component[0]) }
				var changed = true
				while changed {
					changed = false
					for node in component {
						// A call of the function a cycle closes on passes no value of the label the function builds: inside it, the
						// label reads what it reads where the function is declared, which an edge before this one hands
						// (`CycleParameter`).
						for edge in edgesInto[node] where !bindsLabel[Int(sourceByEdge[Int(edge)])] || labelByNode[node] != label || !alwaysClosesCycle(edge) {
							let source = Int(sourceByEdge[Int(edge)])
							let before = reads[node].count
							for read in reads[source] {
								work += 1
								reads[node].insert(Read(edge: bindsLabel[source] ? edge : read.edge, reference: reference(through: edge, from: read.reference)))
							}
							if isCycle, reads[node].count != before {
								changed = true
							}
						}
					}
				}
			}
			readsByLabel[label] = reads
			return reads
		}

		/// The declaration the binding of `label` that the source of `edge` makes hands a receive of `unwrappedProperty`,
		/// or `nil` where it hands none, or hands `nil`: the first binding of the label that provides it, available where it
		/// is bound before the edge's child or the two are members of one loop of builders.
		func provider(handedBy edge: Int32, label: Int32, labelText: String, receiving unwrappedProperty: Property) -> Provider? {
			work += 1
			guard edge != Self.noDeclaration else {
				// Nothing above declares the label: a seam's own tree reads the seam's parameter of it.
				guard let parameter = seamRoot?.signature.parameters.first(where: { parameter in
					parameter.property.label == labelText
						&& (parameter.property.asUnwrappedProperty == unwrappedProperty || parameter.property.asLazilyInstantiatedInstancePropertyOfDeclaredBinding?.asUnwrappedProperty == unwrappedProperty)
				}) else { return nil }
				let ownDependency = instantiable.dependencies.first { $0.property == parameter.property }
				return Provider(
					property: parameter.property,
					declaringType: ownDependency.map { _ in instantiable.concreteInstantiable },
					declarationLocation: ownDependency?.declarationLocation ?? instantiable.declarationLocation,
				)
			}
			let source = Int(sourceByEdge[Int(edge)])
			let offset = Int(facts.bindingOffsets[source])
			/// Whether the binding at `index` among the source's provides the receive.
			func provides(bindingAt index: Int) -> Bool {
				let binding = facts.bindings[offset + index]
				let property = facts.propertyTable[Int(binding.property)]
				let bindingEdge = edgeByBinding[offset + index]
				let instanceProperty = if bindingEdge >= 0, nodes[Int(graph.edgeTargets[Int(bindingEdge)])].key.leaf != .alias {
					property.asLazilyInstantiatedInstanceProperty
				} else {
					property.asLazilyInstantiatedInstancePropertyOfDeclaredBinding
				}
				return binding.label == label && (property.asUnwrappedProperty == unwrappedProperty || instanceProperty?.asUnwrappedProperty == unwrappedProperty)
			}
			guard let index = facts.worldBindings(of: source).indices.lazy.map({ $0 - offset }).first(where: provides(bindingAt:)) else { return nil }
			let property = facts.propertyTable[Int(facts.bindings[offset + index].property)]
			let bindingEdge = edgeByBinding[offset + index]
			let edgeFact = edgeFacts[Int(edge)]
			let isRebound = edgeFact.loop >= 0 && bindingEdge >= 0 && edgeFacts[Int(bindingEdge)].loop == edgeFact.loop
			guard index < Int(edgeFact.bindingsBefore) || isRebound else { return nil }
			return Provider(
				property: property,
				declaringType: nodes[source].scope.instantiable.concreteInstantiable,
				declarationLocation: declarationLocation(of: property, declaredBy: source),
			)
		}

		var omissions = [ScopeGenerator.SeamTierOmission]()
		for (call, seamCall) in omittingCalls {
			let seam = nodes[call].scope.instantiable
			let omittedParameters = seamCall.omittedParameters.map { ($0, false) } + seamCall.noTierParameters.map { ($0, true) }
			// The leaf declares the whole signature, each parameter its tier omits as a receive only if available of its
			// optional form.
			for (parameter, isNoTierParameter) in omittedParameters {
				let unwrappedProperty = (seam.dependencies.first { $0.property.label == parameter.property.label }?.property ?? parameter.property).asUnwrappedProperty
				let label = labelID(of: parameter.property.label)
				let providers = reads(ofLabel: label)[call].sorted().compactMap { read in
					provider(handedBy: read.edge, label: label, labelText: parameter.property.label, receiving: unwrappedProperty).map { (read, $0) }
				}
				for (read, provider) in providers {
					var omission = ScopeGenerator.SeamTierOmission(
						seam: seam,
						seamCall: seamCall,
						parameter: parameter,
						isNoTierParameter: isNoTierParameter,
						providerProperty: provider.property,
						providerDeclaringType: provider.declaringType,
						providerDeclarationLocation: provider.declarationLocation,
						referenceLocation: referenceLocations[Int(read.reference)],
					)
					// A provider that is a pass-through parameter of this seam is declared by no type: the receives in this
					// seam's tree that make it one say why the seam takes it.
					if provider.declaringType == nil, let seamRoot {
						omission.providerReceivers = seamRoot.signature.parameters.first { $0.property == provider.property }?.receivers ?? []
					}
					omissions.append(omission)
				}
			}
		}
		self.omissions = omissions
		GenerationWork.record(work, by: .findingSeamTierOmissions)
	}

	/// Each value the tree holds for a parameter a tier it calls omits, with each reference to what leads to the call.
	let omissions: [ScopeGenerator.SeamTierOmission]

	/// What a receive reads at a node along some path to it: the edge whose source binds the label (`noDeclaration` for
	/// none), and the reference to what leads to the node on that path.
	private struct Read: Hashable, Comparable {
		let edge: Int32
		let reference: Int32

		static func < (lhs: Read, rhs: Read) -> Bool {
			(lhs.edge, lhs.reference) < (rhs.edge, rhs.reference)
		}
	}

	/// The declaration whose binding a call would read built inline.
	private struct Provider {
		let property: Property
		/// `nil` for a parameter of the seam whose tree this is.
		let declaringType: TypeDescription?
		let declarationLocation: Dependency.DeclarationLocation?
	}

	/// The element of a node's reads that stands for no declaration of the label above it.
	private static let noDeclaration: Int32 = -1
	/// An edge's reference where its source is no type of the module's own files: the reference of the path to it.
	private static let inheritedReference: Int32 = -1
}

/// The omissions of each root the fold finds beside those the walk of its generator tree finds
/// (`ScopeGenerator.seamTierOmissions(ofTreeRootedAt:isOwnFile:)`), handed to `comparesWalk`, which the tests set, never
/// the tool: the two must be equal, as sets, on every test and fuzzer graph. The walk runs only where it is set,
/// uncounted by `GenerationWork`, while `generate` validates each root's tree.
public enum TypeFactsSeamTierOmissionsObservation {
	@TaskLocal public static var comparesWalk: (@Sendable (TypeFactsSeamTierOmissionsComparison) -> Void)?
}

/// One root's omissions, from the fold and from the walk, each spelled with everything its error reports.
public struct TypeFactsSeamTierOmissionsComparison: Sendable {
	/// The root's type.
	public let root: String
	/// What the fold finds.
	public let folded: [String]
	/// What the walk of the root's generator tree finds.
	public let walked: [String]
}

extension ScopeGenerator.SeamTierOmission {
	/// The omission spelled with every part its error reads, for the fold's oracle.
	var comparedSpelling: String {
		"""
		\(seam.concreteInstantiable.asSource) omits \(parameter.property.asSource)\(isNoTierParameter ? " on every tier" : ""), \
		provided by \(providerProperty.asSource) of \(providerDeclaringType?.asSource ?? "the seam’s parameters") \
		at \(providerDeclarationLocation.map { String(describing: $0) } ?? "nowhere"), \
		referred to at \(referenceLocation.map { String(describing: $0) } ?? "nowhere"), \
		receivers \(providerReceivers.map { "\($0.declaringType.asSource).\($0.property.asSource)" })
		"""
	}
}
