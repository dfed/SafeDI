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

/// The order each node of a world node records make builds its children in, by edge index, from each edge's
/// `TypeFactsEdge.buildPosition` (`TypeFactsWorld.edgeFacts(from:)`). Each child follows the siblings its tree requires, depth first in edge
/// order, as `ScopeGenerator.orderedPropertyToGenerateIndices` orders a scope's children where no child is a loop
/// member, a carrier, lazily instantiated or received only if available, which node records refuse until they make it.
///
/// A node's tree receives what its type receives, and what its children's trees receive that the node neither declares
/// nor forwards (`ScopeGenerator.receives`), made once per node, children first.
struct NodeBuildOrder: Sendable {
	init(world: some NodeRecordSources) throws(NodeRecordRefusal) {
		let declarationCount = world.declarationCount
		var receivedByDeclaration = [Set<Property>?](repeating: nil, count: declarationCount)
		// A child met again on the path closes a cycle of edges, which this order cannot hold: the world is refused as a
		// cycle here, whatever kinds claim its nodes.
		var state = [VisitState](repeating: .unvisited, count: declarationCount)
		var stack: [(declaration: DeclarationID, childrenPushed: Bool)] = [(0, false)]
		while let (declaration, childrenPushed) = stack.popLast() {
			let edges = world.edges(from: declaration)
			guard childrenPushed else {
				guard state[Int(declaration)] == .unvisited else { continue }
				state[Int(declaration)] = .onPath
				stack.append((declaration, true))
				for child in edges.reversed() {
					switch state[Int(child)] {
					case .unvisited:
						stack.append((child, false))
					case .onPath:
						throw .cycle
					case .ordered:
						break
					}
				}
				continue
			}
			state[Int(declaration)] = .ordered
			let scope = world.scope(of: declaration)
			let forwardedProperties = Set(scope.instantiable.dependencies.filter { $0.source == .forwarded }.map(\.property))
			var received = Set<Property>()
			for child in edges {
				for property in receivedByDeclaration[Int(child)] ?? []
					where !ScopeGenerator.provides(property, declaredProperties: scope.propertiesToDeclare, forwardedProperties: forwardedProperties)
				{
					received.insert(property)
				}
			}
			for dependency in scope.instantiable.dependencies where dependency.source == .received(onlyIfAvailable: false) {
				received.insert(dependency.property)
			}
			receivedByDeclaration[Int(declaration)] = received
		}
		var edgeIndicesByDeclaration = [[Int]](repeating: [], count: declarationCount)
		for declaration in 0..<Int32(declarationCount) {
			let children = world.edges(from: declaration).map { child in
				(property: world.property(of: child), received: receivedByDeclaration[Int(child)] ?? [])
			}
			try Self.checkNoBuilderLoop(among: children)
			let edgeFacts = world.edgeFacts(from: declaration)
			// A member of a loop of builders, which the facts find with optional receives too, is rebound in each member's
			// function, which node records do not make yet.
			guard edgeFacts.allSatisfy({ $0.loop < 0 }) else { throw .builderLoop }
			edgeIndicesByDeclaration[Int(declaration)] = Self.edgeIndices(inOrderOf: edgeFacts)
		}
		self.edgeIndicesByDeclaration = edgeIndicesByDeclaration
	}

	/// The indices of `declaration`'s edges, in the order it builds their children.
	func edgeIndices(of declaration: DeclarationID) -> [Int] {
		edgeIndicesByDeclaration[Int(declaration)]
	}

	/// The indices of a node's edges, whose facts are `edgeFacts`, in the order it builds their children: the facts' build
	/// position, which the sibling-order fixed point gives each edge.
	static func edgeIndices(inOrderOf edgeFacts: ArraySlice<TypeFactsEdge>) -> [Int] {
		edgeFacts.enumerated()
			.sorted { $0.element.buildPosition < $1.element.buildPosition }
			.map(\.offset)
	}

	private let edgeIndicesByDeclaration: [[Int]]

	private enum VisitState {
		case unvisited
		case onPath
		case ordered
	}

	/// Refuses `children` where two wait on each other, or a child's tree receives the child's own property.
	private static func checkNoBuilderLoop(among children: [(property: Property?, received: Set<Property>)]) throws(NodeRecordRefusal) {
		// A child's tree that receives the child's own property receives the declaration being built, which the child's
		// builder function rebinds: a loop of builders, however many siblings it has.
		for case let (property?, received) in children where received.contains(property) || received.contains(property.asOptionalProperty) {
			throw .builderLoop
		}
		guard children.count > 1 else { return }
		var indexByProperty = [Property: Int]()
		for (index, child) in children.enumerated() {
			if let property = child.property {
				indexByProperty[property] = index
			}
		}
		var dependencies = [[Int]]()
		for (index, child) in children.enumerated() {
			var childDependencies = Set<Int>()
			for property in child.received {
				// A required optional receive reads a sibling of its non-optional form.
				let siblingIndex = indexByProperty[property] ?? (property.typeDescription.isOptional ? indexByProperty[property.asUnwrappedProperty] : nil)
				if let siblingIndex {
					childDependencies.insert(siblingIndex)
				}
			}
			childDependencies.remove(index)
			dependencies.append(childDependencies.sorted())
		}
		// A sibling met again on the path of a depth-first walk of the siblings each child depends on is a loop.
		var state = [VisitState](repeating: .unvisited, count: children.count)
		for startIndex in children.indices where state[startIndex] == .unvisited {
			state[startIndex] = .onPath
			var path = [(index: startIndex, nextDependencyPosition: 0)]
			while let (index, dependencyPosition) = path.last {
				if dependencyPosition < dependencies[index].count {
					path[path.count - 1].nextDependencyPosition += 1
					let dependencyIndex = dependencies[index][dependencyPosition]
					switch state[dependencyIndex] {
					case .unvisited:
						state[dependencyIndex] = .onPath
						path.append((index: dependencyIndex, nextDependencyPosition: 0))
					case .onPath:
						throw .builderLoop
					case .ordered:
						break
					}
				} else {
					state[index] = .ordered
					path.removeLast()
				}
			}
		}
	}
}
