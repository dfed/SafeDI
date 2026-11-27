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

/// What the folds of a world's graph compare of its properties, by the world's property ID: each property's label, its
/// unwrapped form, the instance a lazy wrapper creates, whether it is an instantiator of any kind, the forms a receive of
/// it only if available reads (`Property.formsReadByOnlyIfAvailableReceive`) and the forms a declaration of it provides
/// (`CycleParameter.forms(providedBy:)`), each a run in one flat column. Built where the graph is built, from the
/// properties' spellings, so no fold reads one. It holds its columns for as long as its graph does.
struct TypeFactsPropertyFacts: Sendable {
	let labels: [Int32]
	let unwrapped: [Int32]
	let isOptional: [Bool]
	/// The instance a lazily instantiated property creates, which a receive by value reads, or -1.
	let instances: [Int32]
	let isBuilder: [Bool]
	let formsReadOffsets: [Int32]
	let formsRead: [Int32]
	let formsProvidedOffsets: [Int32]
	let formsProvided: [Int32]

	func formsRead(by property: Int32) -> ArraySlice<Int32> {
		formsRead[Int(formsReadOffsets[Int(property)])..<Int(formsReadOffsets[Int(property) + 1])]
	}

	func formsProvided(by property: Int32) -> ArraySlice<Int32> {
		formsProvided[Int(formsProvidedOffsets[Int(property)])..<Int(formsProvidedOffsets[Int(property) + 1])]
	}

	/// `ScopeGenerator.provides(_:aFormReadBy:)`: whether a declaration of `declared` provides a form a receive of
	/// `fulfilling` only if available reads.
	func provides(_ declared: Int32, aFormReadBy fulfilling: Int32) -> Bool {
		let provided = formsProvided(by: declared)
		return formsRead(by: fulfilling).contains(where: provided.contains)
	}

	/// The 32-bit elements the columns hold, booleans counted as one each.
	var columnElementCount: Int {
		labels.count + unwrapped.count + isOptional.count + instances.count + isBuilder.count + formsReadOffsets.count + formsRead.count + formsProvidedOffsets.count + formsProvided.count
	}
}

/// What each node's subtree receives from above it, the union facts the order of a scope's children reads: as
/// `ScopeGenerator`'s `receivedProperties`, `requiredReceivedProperties`, `onlyIfAvailableUnwrappedReceivedProperties` and
/// `requiredAliasFulfillingProperties` hold them, a row of property IDs per node. One fold per row over the world's graph,
/// each a least fixed point per component (`ReadsFromAbove`), so a node on a cycle receives what its cycle receives.
struct TypeFactsReceives: Sendable {
	let received: BitRows
	let required: BitRows
	let onlyIfAvailableUnwrapped: BitRows
	let requiredAliasFulfilling: BitRows

	var wordCount: Int {
		received.wordCount + required.wordCount + onlyIfAvailableUnwrapped.wordCount + requiredAliasFulfilling.wordCount
	}
}

/// The order a scope builds its children in, and the loops of builders among them, as `ScopeGenerator`'s
/// `orderedPropertyToGenerateIndices` and `receivedBuilderLoops` work them out at each place, here once per node from its
/// children's union facts. Works on IDs only.
enum SiblingOrder {
	/// One child of a scope, in the order the scope lists its children.
	struct Child: Sendable {
		/// The world's ID of the property the child is built as.
		let property: Int32
		/// The instance the child's declaration offers by value (`declaredLazilyInstantiatedInstanceProperty`), or -1.
		let instance: Int32
		/// The child's node, whose union facts it reads.
		let node: Int32
		let isAlias: Bool
		let isErasedAlias: Bool
		/// For an alias received only if available, the world's ID of its fulfilling property, or -1.
		let onlyIfAvailableAliasFulfilling: Int32
		/// Whether the child holds a place of the world's holes, and so starts after its siblings that hold none.
		let isCarrier: Bool
	}

	struct Result {
		/// The children's indices in the order they are built.
		var orderedIndices = [Int]()
		/// For each child, the index of the first member of the loop of builders it is on, or -1.
		var loopByChild = [Int]()
		/// For each child on a loop, the indices of the members its tree receives inside the loop, itself among them where
		/// its tree receives its own property, which its builder function rebinds (`ScopeGenerator`'s
		/// `reboundPropertiesByChildIndex`); empty for every other child.
		var reboundByChild = [[Int]]()
	}

	static func order(of children: [Child], receives: TypeFactsReceives, facts: TypeFactsPropertyFacts) -> Result {
		var result = Result()
		let graph = siblingGraph(of: children, receives: receives, facts: facts)
		let found = loops(of: children, graph: graph, facts: facts)
		let loops = found.loopByChild
		result.loopByChild = loops
		result.reboundByChild = found.reboundByChild
		// One child, or none, has no sibling to order against, but can be a loop of its own.
		guard children.count > 1 else {
			result.orderedIndices = Array(children.indices)
			return result
		}
		// A loop is ordered as one unit, named by its first member, whose members follow in declaration order, renames last.
		let unitByIndex = children.indices.map { loops[$0] >= 0 ? loops[$0] : $0 }
		var membersByUnit = [Int: [Int]]()
		for index in children.indices where loops[index] >= 0 && !children[index].isAlias {
			membersByUnit[unitByIndex[index], default: []].append(index)
		}
		for index in children.indices where loops[index] >= 0 && children[index].isAlias {
			membersByUnit[unitByIndex[index], default: []].append(index)
		}
		var dependencies = graph.dependencies
		if !membersByUnit.isEmpty {
			var unitDependencies = children.indices.map { _ in Set<Int>() }
			for index in children.indices {
				for dependency in dependencies[index] where unitByIndex[dependency] != unitByIndex[index] {
					unitDependencies[unitByIndex[index]].insert(unitByIndex[dependency])
				}
			}
			dependencies = unitDependencies
		}
		var unfulfilled = Set(graph.siblings.map { unitByIndex[$0.index] }).union(children.indices.filter { children[$0].property < 0 })
		let startIndices: [Int] = if children.contains(where: \.isCarrier) {
			{
				let carriers = children.indices.filter { children[$0].isCarrier }.map { unitByIndex[$0] }
				let reachesCarrier = children.indices.map { index in carriers.contains { reaches($0, from: unitByIndex[index], dependencies) } }
				return children.indices.filter { !reachesCarrier[$0] }.map { unitByIndex[$0] } + children.indices.filter { reachesCarrier[$0] }.map { unitByIndex[$0] }
			}()
		} else {
			children.indices.map { unitByIndex[$0] }
		}
		for start in startIndices where unfulfilled.contains(start) {
			unfulfilled.remove(start)
			var path = [(index: start, dependencies: dependencies[start].sorted(), next: 0)]
			while let (index, sortedDependencies, next) = path.last {
				if next < sortedDependencies.count {
					path[path.count - 1].next += 1
					let dependency = sortedDependencies[next]
					if unfulfilled.remove(dependency) != nil {
						path.append((index: dependency, dependencies: dependencies[dependency].sorted(), next: 0))
					}
				} else {
					if let members = membersByUnit[index] {
						result.orderedIndices.append(contentsOf: members)
					} else {
						result.orderedIndices.append(index)
					}
					path.removeLast()
				}
			}
		}
		return result
	}

	/// `ScopeGenerator.SiblingGraph` over IDs.
	struct Graph {
		var siblings = [(property: Int32, instance: Int32, index: Int)]()
		var dependencies = [Set<Int>]()
		var receivesLeftNil = [(receiver: Int, sibling: Int)]()
		var childrenRequiringThemselves = Set<Int>()
	}

	/// `ScopeGenerator.siblingGraph(of:requiredOnlyIfAvailableAliasProperties:)`, from the children's union facts.
	static func siblingGraph(of children: [Child], receives: TypeFactsReceives, facts: TypeFactsPropertyFacts) -> Graph {
		var graph = Graph()
		var listed = Set<Int32>()
		for (index, child) in children.enumerated() where child.property >= 0 && listed.insert(child.property).inserted {
			graph.siblings.append((child.property, child.instance, index))
		}
		var siblingIndexByProperty = [Int32: Int]()
		for sibling in graph.siblings {
			siblingIndexByProperty[sibling.property] = sibling.index
		}
		var lazySiblingsByInstance = [Int32: [Int]]()
		for sibling in graph.siblings where sibling.instance >= 0 && siblingIndexByProperty[sibling.instance] == nil {
			lazySiblingsByInstance[sibling.instance, default: []].append(sibling.index)
		}
		var siblingsByLabel = [Int32: [(property: Int32, index: Int)]]()
		for sibling in graph.siblings {
			siblingsByLabel[facts.labels[Int(sibling.property)], default: []].append((sibling.property, sibling.index))
		}
		graph.dependencies = children.enumerated().map { childIndex, child in
			var dependencies = Set<Int>()
			let node = Int(child.node)
			func waitOn(_ property: Int32) {
				if let sibling = siblingIndexByProperty[property] {
					dependencies.insert(sibling)
				} else if let lazySiblings = lazySiblingsByInstance[property] {
					dependencies.formUnion(lazySiblings)
				}
			}
			for property in receives.received.columns(inRow: node) where !receives.onlyIfAvailableUnwrapped.contains(facts.unwrapped[Int(property)], inRow: node) {
				waitOn(property)
			}
			for property in receives.required.columns(inRow: node) where facts.isOptional[Int(property)] {
				waitOn(facts.unwrapped[Int(property)])
			}
			for property in receives.requiredAliasFulfilling.columns(inRow: node) {
				for sibling in siblingsByLabel[facts.labels[Int(property)], default: []] where sibling.index != childIndex && facts.provides(sibling.property, aFormReadBy: property) {
					dependencies.insert(sibling.index)
				}
			}
			if dependencies.remove(childIndex) != nil {
				graph.childrenRequiringThemselves.insert(childIndex)
			}
			return dependencies
		}
		// An alias received only if available that a child's tree requires is built after the sibling it is bound from.
		func isRequiredByChild(_ property: Int32) -> Bool {
			children.contains { child in
				let node = Int(child.node)
				return receives.required.contains(property, inRow: node)
					|| receives.requiredAliasFulfilling.columns(inRow: node).contains { facts.labels[Int($0)] == facts.labels[Int(property)] && facts.provides(property, aFormReadBy: $0) }
			}
		}
		for (index, child) in children.enumerated() where child.isAlias && child.onlyIfAvailableAliasFulfilling >= 0 && isRequiredByChild(child.property) {
			let fulfilling = child.onlyIfAvailableAliasFulfilling
			for sibling in siblingsByLabel[facts.labels[Int(fulfilling)], default: []] where facts.provides(sibling.property, aFormReadBy: fulfilling) {
				graph.dependencies[index].insert(sibling.index)
			}
		}
		for considersAliases in [true, false] {
			for (index, child) in children.enumerated() where (child.onlyIfAvailableAliasFulfilling >= 0) == considersAliases {
				let node = Int(child.node)
				for sibling in graph.siblings
					where receives.onlyIfAvailableUnwrapped.contains(facts.unwrapped[Int(sibling.property)], inRow: node)
					|| (sibling.instance >= 0 && receives.onlyIfAvailableUnwrapped.contains(sibling.instance, inRow: node))
				{
					if reaches(index, from: sibling.index, graph.dependencies) {
						graph.receivesLeftNil.append((receiver: index, sibling: sibling.index))
					} else {
						graph.dependencies[index].insert(sibling.index)
					}
				}
			}
		}
		return graph
	}

	/// `ScopeGenerator.receivedBuilderLoops(of:requiredOnlyIfAvailableAliasProperties:)`: for each child, the first member
	/// of its loop of builders, or -1, and the members it rebinds.
	static func loops(of children: [Child], graph: Graph, facts: TypeFactsPropertyFacts) -> (loopByChild: [Int], reboundByChild: [[Int]]) {
		var loopByChild = [Int](repeating: -1, count: children.count)
		var reboundByChild = [[Int]](repeating: [], count: children.count)
		let isBuilder = children.map { child -> Bool in
			guard child.property >= 0, facts.isBuilder[Int(child.property)] else { return false }
			guard child.isAlias else { return true }
			guard !child.isErasedAlias else { return false }
			guard child.onlyIfAvailableAliasFulfilling >= 0 else { return true }
			let fulfilling = child.onlyIfAvailableAliasFulfilling
			return children.contains { sibling in
				!sibling.isAlias && sibling.property >= 0
					&& facts.labels[Int(sibling.property)] == facts.labels[Int(fulfilling)]
					&& facts.isBuilder[Int(sibling.property)]
					&& facts.provides(sibling.property, aFormReadBy: fulfilling)
			}
		}
		guard isBuilder.contains(true) else { return (loopByChild, reboundByChild) }
		let candidates = graph.receivesLeftNil.filter { isBuilder[$0.receiver] && isBuilder[$0.sibling] }
		guard !candidates.isEmpty || !graph.childrenRequiringThemselves.isEmpty || graph.dependencies.indices.contains(where: { isBuilder[$0] && graph.dependencies[$0].contains { isBuilder[$0] } }) else {
			return (loopByChild, reboundByChild)
		}
		func components(of arrows: [Set<Int>]) -> (componentByIndex: [Int], holdsOnlyBuilders: (Int) -> Bool) {
			let componentByIndex = ScopeGenerator.stronglyConnectedComponents(of: arrows)
			var holdsOnlyBuilders = [Int: Bool]()
			for index in children.indices {
				holdsOnlyBuilders[componentByIndex[index]] = holdsOnlyBuilders[componentByIndex[index], default: true] && isBuilder[index]
			}
			let held = holdsOnlyBuilders
			return (componentByIndex, { held[componentByIndex[$0]] == true })
		}
		var arrowsWithEveryCandidate = graph.dependencies
		for candidate in candidates where candidate.receiver != candidate.sibling {
			arrowsWithEveryCandidate[candidate.receiver].insert(candidate.sibling)
		}
		let candidateComponents = components(of: arrowsWithEveryCandidate)
		var givenArrows = graph.dependencies
		var givenSelfArrows = graph.childrenRequiringThemselves
		for candidate in candidates
			where candidate.receiver == candidate.sibling
			|| (candidateComponents.componentByIndex[candidate.receiver] == candidateComponents.componentByIndex[candidate.sibling]
				&& candidateComponents.holdsOnlyBuilders(candidate.receiver))
		{
			if candidate.receiver == candidate.sibling {
				givenSelfArrows.insert(candidate.receiver)
			} else {
				givenArrows[candidate.receiver].insert(candidate.sibling)
			}
		}
		let (componentByIndex, isOnLoop) = components(of: givenArrows)
		var componentHoldsArrow = Set<Int>()
		for index in children.indices where isOnLoop(index) {
			let rebindsSibling = givenArrows[index].contains { componentByIndex[$0] == componentByIndex[index] && children[$0].property >= 0 }
			if rebindsSibling || (givenSelfArrows.contains(index) && children[index].property >= 0) {
				componentHoldsArrow.insert(componentByIndex[index])
			}
		}
		var firstMemberByComponent = [Int: Int]()
		for index in children.indices where isOnLoop(index) && componentHoldsArrow.contains(componentByIndex[index]) {
			let firstMember = firstMemberByComponent[componentByIndex[index]] ?? index
			firstMemberByComponent[componentByIndex[index]] = firstMember
			loopByChild[index] = firstMember
			var rebound = givenArrows[index].filter { componentByIndex[$0] == componentByIndex[index] && children[$0].property >= 0 }
			if givenSelfArrows.contains(index), children[index].property >= 0 {
				rebound.insert(index)
			}
			reboundByChild[index] = rebound.sorted()
		}
		return (loopByChild, reboundByChild)
	}

	/// Whether `target` is reached from `start` over `arrows`.
	private static func reaches(_ target: Int, from start: Int, _ arrows: [Set<Int>]) -> Bool {
		var visited = Set<Int>()
		var toVisit = [start]
		while let index = toVisit.popLast() {
			guard index != target else { return true }
			for next in arrows[index] where visited.insert(next).inserted {
				toVisit.append(next)
			}
		}
		return false
	}
}
