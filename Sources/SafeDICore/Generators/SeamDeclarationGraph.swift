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

/// The graph of the declarations a tree that holds places of holes builds – a seam's, or a public mock's – from which
/// the facts that hold for every build of a type are read, never from the tree's paths.
///
/// A node is a declaration: a property, as cycle validation sees it (`Property.asValidatedForDependencyCycles`), with the
/// concrete type it builds, which is what a scope closes a cycle on (`ScopeGeneratorUnderConstruction`). The tree's root
/// is the entry. There is an edge from a declaration to each child of the type it builds: to the child's declaration, and
/// from a site of a hole to the one node that stands for every place. Every path of the tree is a path of the graph that
/// repeats no declaration, and every such path is one of the tree's, since a scope closes a cycle exactly where its
/// declaration is already being built above it.
///
/// An edge whose target is above its source on every path from the entry – the target dominates the source – closes a
/// cycle on every build, so it is never built: such edges are removed. A type's property holds a place when it is a site
/// of a hole, or when its edge out of any declaration of the type is left and its declaration reaches a place in what is
/// left. That is a fact of the type, the same on every path, a path on which the property closes a cycle included. It
/// holds on every path where the property's subtree holds a site, since every edge of the tree's path to the site is
/// left. On a path where it holds none, the property closes a cycle or reaches a place only through a declaration above
/// it: in a tangle of cycles that no type of it always encloses, or in a type that one declaration builds outside a cycle
/// and another builds inside one, whose edge for the property is removed (`T`, built by `Hub`'s `tBuilder` and by the
/// `otherT` of a `U` that `T`'s `uBuilder` builds: the `T` that `otherT` builds always closes `uBuilder`).
///
/// A fill's tree is built with the stack of the seam whose hole it fills (`SeamSignature.Hole.fillPropertyStack`), not
/// with its path in this tree, so the graph does not enter it: a call whose fill holds a site on its path reaches a place,
/// and the scopes in a fill's tree keep the order by path.
struct SeamDeclarationGraph {
	/// Reads the graph of the tree `root` roots.
	init(treeRootedAt root: ScopeGenerator) {
		var nodeIndexByDeclaration = [Declaration: Int]()
		// The type each node's declaration builds, by node, `nil` for the node of every place, and the edges out of each, in
		// the order the walk meets them.
		var types: [TypeDescription?] = [root.builtInstantiable?.concreteInstantiable, nil]
		var successors: [[Edge]] = [[], []]
		var expandedNodes = Set<Int>()
		// Each node is expanded once, from the first build of its declaration the walk meets that closes no cycle: every
		// build of a declaration has the same children, since its type does. A build that closes a cycle is beneath a build
		// of the same declaration that closes none, so every declaration is expanded.
		var generatorsToVisit = [(generator: root, node: Self.entry)]
		while let (generator, node) = generatorsToVisit.popLast() {
			guard expandedNodes.insert(node).inserted else { continue }
			for child in generator.children {
				if child.holeSite != nil, let property = child.property {
					successors[node].append(Edge(property: property, target: Self.place))
				} else if child.fillHole != nil {
					// A fill holds a site on this path where its tree does, whatever the path above the call: its tree is built
					// with the filled seam's stack.
					if child.containsBuildSite {
						successors[node].append(Edge(property: nil, target: Self.place))
					}
				} else if let property = child.property, let builtType = child.builtInstantiable?.concreteInstantiable {
					let declaration = Declaration(property: property.asValidatedForDependencyCycles, concreteType: builtType)
					let childNode: Int
					if let existingNode = nodeIndexByDeclaration[declaration] {
						childNode = existingNode
					} else {
						childNode = types.count
						nodeIndexByDeclaration[declaration] = childNode
						types.append(builtType)
						successors.append([])
					}
					successors[node].append(Edge(property: property, target: childNode))
					if !child.closesPropertyCycle {
						generatorsToVisit.append((child, childNode))
					}
				}
				// An alias builds nothing.
			}
		}
		let immediateDominators = Self.immediateDominators(successors: successors)
		// An edge whose target dominates its source closes a cycle on every build: it is removed.
		var predecessorsByLeftEdges = Array(repeating: [Int](), count: successors.count)
		var isEdgeLeft = successors.map { Array(repeating: true, count: $0.count) }
		for (source, edges) in successors.enumerated() {
			for (edgeIndex, edge) in edges.enumerated() {
				if edge.target != Self.place, Self.dominates(edge.target, source, immediateDominators: immediateDominators) {
					isEdgeLeft[source][edgeIndex] = false
				} else {
					predecessorsByLeftEdges[edge.target].append(source)
				}
			}
		}
		// The nodes that reach a place in what is left.
		var reachesPlace = Array(repeating: false, count: successors.count)
		reachesPlace[Self.place] = true
		var nodesToVisit = [Self.place]
		while let node = nodesToVisit.popLast() {
			for predecessor in predecessorsByLeftEdges[node] where !reachesPlace[predecessor] {
				reachesPlace[predecessor] = true
				nodesToVisit.append(predecessor)
			}
		}
		var placeHoldingPropertiesByType = [TypeDescription: Set<Property>]()
		for (source, edges) in successors.enumerated() {
			guard let type = types[source] else { continue }
			for (edgeIndex, edge) in edges.enumerated() where isEdgeLeft[source][edgeIndex] && reachesPlace[edge.target] {
				guard let property = edge.property else { continue }
				placeHoldingPropertiesByType[type, default: []].insert(property)
			}
		}
		self.placeHoldingPropertiesByType = placeHoldingPropertiesByType
	}

	/// The properties of each type that hold a place, by type. A type none of whose properties holds one is absent.
	let placeHoldingPropertiesByType: [TypeDescription: Set<Property>]

	/// Whether some build of a type in the tree `root` roots, outside every fill, has a child that holds a place by its
	/// type's properties (`placeHoldingPropertiesByType`) but whose subtree holds no site on the build's path, or the
	/// reverse, so that the children of that build would start in another order (`ScopeGenerator.startsAsCarrier(_:)`).
	/// Only a tangle of cycles, or a type that one declaration builds outside a cycle and another builds inside one, makes it
	/// so (see the type's documentation). Every build is visited, since the builds of one declaration differ in which of
	/// their children close a cycle.
	func ordersChildrenOtherwiseThanTheirPaths(inTreeRootedAt root: ScopeGenerator) -> Bool {
		var generatorsToVisit = [root]
		while let generator = generatorsToVisit.popLast() {
			guard let type = generator.builtInstantiable?.concreteInstantiable else { continue }
			let placeHoldingProperties = placeHoldingPropertiesByType[type] ?? []
			for child in generator.children where child.fillHole == nil {
				guard let property = child.property, child.holeSite != nil || child.builtInstantiable != nil else { continue }
				guard placeHoldingProperties.contains(property) == child.containsBuildSite else { return true }
				generatorsToVisit.append(child)
			}
		}
		return false
	}

	// MARK: Private

	/// A node of the graph: a property, as cycle validation sees it, with the concrete type it builds.
	private struct Declaration: Hashable {
		let property: Property
		let concreteType: TypeDescription
	}

	/// An edge of the graph, from a declaration to a child of the type it builds.
	private struct Edge {
		/// The child's property: `nil` for the edge from a call to the place its fill's tree holds.
		let property: Property?
		/// The child's node.
		let target: Int
	}

	/// The node of the tree's root.
	private static let entry = 0
	/// The node that stands for every place.
	private static let place = 1

	/// The immediate dominator of each node, by node, the entry's being itself, found as Cooper, Harvey and Kennedy's "A
	/// Simple, Fast Dominance Algorithm" finds them: over the nodes in reverse postorder until no dominator changes. Every
	/// node but the place's is reached from the entry, the walk that read the graph having started there, and the place's is
	/// reached where any place is; a node reached from none has `unreached`.
	private static func immediateDominators(successors: [[Edge]]) -> [Int] {
		// The postorder, from a depth-first walk with its own stack, since a graph can be as deep as the module has types.
		var postorderIndex = Array(repeating: unreached, count: successors.count)
		var postorder = [Int]()
		var isVisited = Array(repeating: false, count: successors.count)
		isVisited[entry] = true
		var path = [(node: entry, nextEdge: 0)]
		while let (node, nextEdge) = path.last {
			if nextEdge < successors[node].count {
				path[path.count - 1].nextEdge += 1
				let target = successors[node][nextEdge].target
				if !isVisited[target] {
					isVisited[target] = true
					path.append((target, 0))
				}
			} else {
				postorderIndex[node] = postorder.count
				postorder.append(node)
				path.removeLast()
			}
		}
		var predecessors = Array(repeating: [Int](), count: successors.count)
		for (source, edges) in successors.enumerated() {
			for edge in edges {
				predecessors[edge.target].append(source)
			}
		}
		var immediateDominators = Array(repeating: unreached, count: successors.count)
		immediateDominators[entry] = entry
		// The nearest common dominator of two nodes whose dominators are known, walking up from the one later in postorder.
		func intersect(_ first: Int, _ second: Int) -> Int {
			var first = first
			var second = second
			while first != second {
				while postorderIndex[first] < postorderIndex[second] {
					first = immediateDominators[first]
				}
				while postorderIndex[second] < postorderIndex[first] {
					second = immediateDominators[second]
				}
			}
			return first
		}
		// In reverse postorder every node but the entry has a predecessor whose dominator is known: the node the walk reached
		// it from.
		var changed = true
		while changed {
			changed = false
			for node in postorder.reversed() where node != entry {
				var newImmediateDominator = unreached
				for predecessor in predecessors[node] where immediateDominators[predecessor] != unreached {
					newImmediateDominator = newImmediateDominator == unreached ? predecessor : intersect(predecessor, newImmediateDominator)
				}
				if newImmediateDominator != immediateDominators[node] {
					immediateDominators[node] = newImmediateDominator
					changed = true
				}
			}
		}
		return immediateDominators
	}

	/// Whether `dominator` is on every path from the entry to `node`, `node` itself included, `node` being reached from the
	/// entry.
	private static func dominates(_ dominator: Int, _ node: Int, immediateDominators: [Int]) -> Bool {
		var current = node
		while current != dominator {
			guard current != entry else { return false }
			current = immediateDominators[current]
		}
		return true
	}

	/// What `immediateDominators` holds for a node it has not reached.
	private static let unreached = -1
}
