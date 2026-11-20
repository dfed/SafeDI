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

/// The identity of a `Scope`, which a construction memo keys and keeps alive in place of the scope itself, so that what
/// construction holds is `Sendable` (see `ConstructionMemo.Key`). It holds nothing.
final class ConstructionScopeIdentity: Sendable {}

/// What `Scope.createScopeGenerator` reads of the scopes a tree is built over, taken once, after the scope maps are
/// finished, as values: one node per scope the tree's root reaches through its instantiated children and the fulfilling
/// scopes of its seam calls' fills, each child named by its node's index. Construction reads nothing else of a `Scope`,
/// so a tree can be built from it on any task.
struct ConstructionGraph: Sendable {
	/// The graph of every scope `root` reaches.
	init(rootedAt root: Scope) {
		var indexByScope = [ObjectIdentifier: Int]()
		var scopes = [Scope]()
		func index(of scope: Scope) -> Int {
			if let index = indexByScope[ObjectIdentifier(scope)] {
				return index
			} else {
				let index = scopes.count
				indexByScope[ObjectIdentifier(scope)] = index
				scopes.append(scope)
				return index
			}
		}
		_ = index(of: root)
		var nodes = [Node]()
		// Scopes are appended as they are first reached, so each is turned into a node once, in order.
		while nodes.count < scopes.count {
			let scope = scopes[nodes.count]
			nodes.append(Node(
				identity: scope.constructionIdentity,
				instantiable: scope.instantiable,
				builtInlineSeamComment: scope.builtInlineSeamComment,
				seamCall: scope.seamCall,
				publicMockCall: scope.publicMockCall,
				propertiesToGenerate: scope.propertiesToGenerate.map { propertyToGenerate in
					switch propertyToGenerate {
					case let .instantiated(property, scope, erasedToConcreteExistential):
						.instantiated(property, index(of: scope), erasedToConcreteExistential: erasedToConcreteExistential)
					case let .hole(property, erasedToConcreteExistential, declarationLocation):
						.hole(property, erasedToConcreteExistential: erasedToConcreteExistential, declarationLocation: declarationLocation)
					case let .aliased(property, fulfillingProperty, erasedToConcreteExistential, onlyIfAvailable, declarationReference):
						.aliased(property, fulfilledBy: fulfillingProperty, erasedToConcreteExistential: erasedToConcreteExistential, onlyIfAvailable: onlyIfAvailable, declarationReference: declarationReference)
					}
				},
				holeArguments: scope.holeArguments.map { argument in
					switch argument {
					case let .fill(hole, scope):
						.fill(hole, index(of: scope))
					case let .passUp(hole):
						.passUp(hole)
					}
				},
				fillReceivedProperties: scope.fillReceivedProperties,
				fillLabelsReadOnlyIfAvailable: scope.fillLabelsReadOnlyIfAvailable,
				propertiesToDeclare: scope.propertiesToDeclare,
				instantiatedDependenciesNotGenerated: scope.instantiatedDependenciesNotGenerated,
				declaredLabels: scope.declaredLabels,
				sortedDeclaredPropertyForms: scope.sortedDeclaredPropertyForms,
				declaredLazilyInstantiatedInstanceProperties: scope.declaredLazilyInstantiatedInstanceProperties,
				forwardedLazilyInstantiatedInstanceProperties: scope.forwardedLazilyInstantiatedInstanceProperties,
				createdBindings: scope.createdBindingsByForm,
			))
		}
		self.nodes = nodes
		// A node is at one place of the tree when one reference reaches it, from a node at one place: the root, which the
		// tree's own place references, or a node whose one child it is. Each node is appended when it is first referenced,
		// after the node that references it, so the node that references a node referenced once precedes it, and one pass
		// in node order decides every node. A node on a cycle is referenced by the cycle as well as from outside it, or
		// descends from such a node, so no node on a cycle is at one place.
		var referenceCounts = [Int](repeating: 0, count: nodes.count)
		var lastReferrers = [Int](repeating: 0, count: nodes.count)
		referenceCounts[0] = 1
		for (referrer, node) in nodes.enumerated() {
			for case let .instantiated(_, index, _) in node.propertiesToGenerate {
				referenceCounts[index] += 1
				lastReferrers[index] = referrer
			}
			// A fill place has no key and stores nothing, so counting its reference only keys, with nothing to hit, a scope
			// the tree otherwise builds at one place. The count is kept so that one place means one reference of any kind.
			for case let .fill(_, index) in node.holeArguments {
				referenceCounts[index] += 1
				lastReferrers[index] = referrer
			}
		}
		var isAtOnePlace = [Bool]()
		isAtOnePlace.reserveCapacity(nodes.count)
		for index in nodes.indices {
			isAtOnePlace.append(referenceCounts[index] == 1 && (index == 0 || isAtOnePlace[lastReferrers[index]]))
		}
		self.isAtOnePlace = isAtOnePlace
	}

	/// The scope the graph is rooted at.
	var root: ConstructionScope {
		ConstructionScope(graph: self, index: 0)
	}

	fileprivate struct Node: Sendable {
		let identity: ConstructionScopeIdentity
		let instantiable: Instantiable
		let builtInlineSeamComment: String?
		let seamCall: SeamCall?
		let publicMockCall: PublicMockCall?
		let propertiesToGenerate: [PropertyToGenerate]
		let holeArguments: [HoleArgument]
		let fillReceivedProperties: [SeamSignature.Hole.Site: Set<Property>]
		let fillLabelsReadOnlyIfAvailable: [SeamSignature.Hole.Site: Set<String>]
		let propertiesToDeclare: Set<Property>
		let instantiatedDependenciesNotGenerated: [Dependency]
		let declaredLabels: Set<String>
		let sortedDeclaredPropertyForms: [(property: Property, forms: Set<Property>)]
		let declaredLazilyInstantiatedInstanceProperties: Set<Property>
		let forwardedLazilyInstantiatedInstanceProperties: [Property]
		let createdBindings: [Property: Property]
	}

	/// `Scope.PropertyToGenerate`, with the scope built named by its node's index.
	fileprivate enum PropertyToGenerate: Sendable {
		case instantiated(Property, Int, erasedToConcreteExistential: Bool)
		case hole(Property, erasedToConcreteExistential: Bool, declarationLocation: Dependency.DeclarationLocation?)
		case aliased(
			Property,
			fulfilledBy: Property,
			erasedToConcreteExistential: Bool,
			onlyIfAvailable: Bool,
			declarationReference: AliasDeclarationReferences.Reference?,
		)
	}

	/// `Scope.HoleArgument`, with the fulfilling scope named by its node's index.
	fileprivate enum HoleArgument: Sendable {
		case fill(SeamSignature.Hole, Int)
		case passUp(SeamSignature.Hole)
	}

	fileprivate let nodes: [Node]
	/// Whether the tree reaches each node at one place only (see `ConstructionScope.isAtOnePlaceOfTheTree`).
	fileprivate let isAtOnePlace: [Bool]
}

/// A scope of a `ConstructionGraph`, read as construction reads a `Scope`.
struct ConstructionScope: Sendable {
	fileprivate let graph: ConstructionGraph
	fileprivate let index: Int

	private var node: ConstructionGraph.Node {
		graph.nodes[index]
	}

	/// What a construction memo keys and keeps alive for this scope.
	var identity: ConstructionScopeIdentity {
		node.identity
	}

	/// Whether the tree the graph is rooted at builds this scope at one place only: one reference reaches it, from a scope
	/// at one place, or it is the root and nothing references it. Within one pass of the tree, no other place has a
	/// construction memo key that names this scope, so the place's generator is never reused there (see `ConstructionMemo`).
	/// A place a pass does not build (inside a cycle it closes, say) only makes this `false` where it could be `true`.
	var isAtOnePlaceOfTheTree: Bool {
		graph.isAtOnePlace[index]
	}

	var instantiable: Instantiable {
		node.instantiable
	}

	var builtInlineSeamComment: String? {
		node.builtInlineSeamComment
	}

	var seamCall: SeamCall? {
		node.seamCall
	}

	var publicMockCall: PublicMockCall? {
		node.publicMockCall
	}

	var calledBuilders: CalledBuilders? {
		node.seamCall?.calledBuilders ?? node.publicMockCall?.calledBuilders
	}

	var fillReceivedProperties: [SeamSignature.Hole.Site: Set<Property>] {
		node.fillReceivedProperties
	}

	var fillLabelsReadOnlyIfAvailable: [SeamSignature.Hole.Site: Set<String>] {
		node.fillLabelsReadOnlyIfAvailable
	}

	var propertiesToDeclare: Set<Property> {
		node.propertiesToDeclare
	}

	var instantiatedDependenciesNotGenerated: [Dependency] {
		node.instantiatedDependenciesNotGenerated
	}

	var declaredLabels: Set<String> {
		node.declaredLabels
	}

	var sortedDeclaredPropertyForms: [(property: Property, forms: Set<Property>)] {
		node.sortedDeclaredPropertyForms
	}

	var declaredLazilyInstantiatedInstanceProperties: Set<Property> {
		node.declaredLazilyInstantiatedInstanceProperties
	}

	var forwardedLazilyInstantiatedInstanceProperties: [Property] {
		node.forwardedLazilyInstantiatedInstanceProperties
	}

	/// `Scope.createdBinding(of:)`.
	func createdBinding(of property: Property) -> Property? {
		for form in property.formsReadByOnlyIfAvailableReceive {
			if let binding = node.createdBindings[form] {
				return binding
			}
		}
		return nil
	}

	/// `Scope.PropertyToGenerate`, built over the graph.
	enum PropertyToGenerate: Sendable {
		case instantiated(Property, ConstructionScope, erasedToConcreteExistential: Bool)
		case hole(Property, erasedToConcreteExistential: Bool, declarationLocation: Dependency.DeclarationLocation?)
		case aliased(
			Property,
			fulfilledBy: Property,
			erasedToConcreteExistential: Bool,
			onlyIfAvailable: Bool,
			declarationReference: AliasDeclarationReferences.Reference?,
		)
	}

	var propertiesToGenerate: [PropertyToGenerate] {
		node.propertiesToGenerate.map { propertyToGenerate in
			switch propertyToGenerate {
			case let .instantiated(property, index, erasedToConcreteExistential):
				.instantiated(property, ConstructionScope(graph: graph, index: index), erasedToConcreteExistential: erasedToConcreteExistential)
			case let .hole(property, erasedToConcreteExistential, declarationLocation):
				.hole(property, erasedToConcreteExistential: erasedToConcreteExistential, declarationLocation: declarationLocation)
			case let .aliased(property, fulfillingProperty, erasedToConcreteExistential, onlyIfAvailable, declarationReference):
				.aliased(property, fulfilledBy: fulfillingProperty, erasedToConcreteExistential: erasedToConcreteExistential, onlyIfAvailable: onlyIfAvailable, declarationReference: declarationReference)
			}
		}
	}

	/// `Scope.HoleArgument`, built over the graph.
	enum HoleArgument: Sendable {
		case fill(SeamSignature.Hole, ConstructionScope)
		case passUp(SeamSignature.Hole)
	}

	var holeArguments: [HoleArgument] {
		node.holeArguments.map { argument in
			switch argument {
			case let .fill(hole, index):
				.fill(hole, ConstructionScope(graph: graph, index: index))
			case let .passUp(hole):
				.passUp(hole)
			}
		}
	}
}
