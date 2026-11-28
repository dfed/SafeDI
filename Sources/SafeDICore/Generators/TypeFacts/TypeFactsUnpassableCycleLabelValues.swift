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

extension TypeFactsGraph {
	/// The labels no one parameter can pass (`unpassableCycleLabelSolution()`) as the diagnostic reports each
	/// (`UnpassableCycleLabel`), each once, in the order the fold finds them: the type the function builds, the first
	/// receive of the label in the function's body, the forms the body receives, and the declaration between the function
	/// and a call that closes a cycle on it that precedes the others in source order.
	///
	/// Walked only where the fold finds a label, so a world that holds none walks nothing more.
	func unpassableCycleLabelValues() -> [UnpassableCycleLabel] {
		let solution = unpassableCycleLabelSolution()
		var values = [UnpassableCycleLabel]()
		var seen = Set<UnpassableCycleLabel>()
		for placeLabel in solution.labels {
			guard let receiver = firstReceive(of: placeLabel.label, at: placeLabel.place, parameterLabels: solution.parameterLabels, walking: []) else { continue }
			let value = UnpassableCycleLabel(
				builtType: graph.nodes[Int(placeLabel.place.declaration)].scope.instantiable.concreteInstantiable,
				receiver: receiver,
				forms: placeLabel.forms,
				redeclaration: placeLabel.redeclaration,
			)
			if seen.insert(value).inserted {
				values.append(value)
			}
		}
		return values
	}

	/// The first receive of `label` a walk of the body of the function at `place` meets, as
	/// `ScopeGenerator.inOrderTheBodyFirstReceives` meets it: the function's own type's receives, then each declaration it
	/// builds depth first, each type's receives before its children's, in declaration order, each declaration once. A call
	/// that closes a cycle on another function receives that function's parameters, at that function's first receive of
	/// each, reached through the call; a call that closes a cycle on this function receives what this walk meets.
	/// `nil` where the walk meets no receive of the label.
	private func firstReceive(
		of label: String,
		at place: CyclePlace,
		parameterLabels: [CyclePlace: Set<String>],
		walking: Set<CyclePlace>,
	) -> CycleParameter.Receiver? {
		let walking = walking.union([place])
		var visited = Set<Int32>()
		func receive(at declaration: Int32, chain: [TypeDescription]) -> CycleParameter.Receiver? {
			guard graph.nodes[Int(declaration)].key.leaf == .none else { return nil }
			let dependencies = graph.nodes[Int(declaration)].scope.instantiable.dependencies
			return ScopeGenerator.receivesFromAbove(ofOwnDependencies: dependencies)
				.first { $0.property.label == label }
				.map { CycleParameter.Receiver(property: $0.property, declarationLocation: $0.dependency.declarationLocation, chain: chain) }
		}
		func walk(_ declaration: Int32, path: [Int32], chain: [TypeDescription]) -> CycleParameter.Receiver? {
			guard visited.insert(declaration).inserted else { return nil }
			let chain = chain + [graph.nodes[Int(declaration)].scope.instantiable.concreteInstantiable]
			if let receiver = receive(at: declaration, chain: chain) {
				return receiver
			}
			let pathBeneath = path + [declaration]
			for child in edges(from: declaration) {
				if let position = pathBeneath.firstIndex(of: child) {
					let closedOn = CyclePlace(declaration: child, componentMembersAbove: componentMembers(of: child, in: Array(pathBeneath[..<position])))
					if closedOn.declaration != place.declaration, !walking.contains(closedOn), parameterLabels[closedOn]?.contains(label) == true,
					   let receiver = firstReceive(of: label, at: closedOn, parameterLabels: parameterLabels, walking: walking)
					{
						return CycleParameter.Receiver(property: receiver.property, declarationLocation: receiver.declarationLocation, chain: chain + receiver.chain)
					}
				} else if let receiver = walk(child, path: pathBeneath, chain: chain) {
					return receiver
				}
			}
			return nil
		}
		return walk(place.declaration, path: place.componentMembersAbove, chain: [])
	}

	/// The members of `declaration`'s component on `path`, outermost first; none for a declaration on no cycle.
	private func componentMembers(of declaration: Int32, in path: [Int32]) -> [Int32] {
		guard isOnCycle(declaration) else { return [] }
		return path.filter { isOnCycle($0) && component(of: $0) == component(of: declaration) }
	}
}
