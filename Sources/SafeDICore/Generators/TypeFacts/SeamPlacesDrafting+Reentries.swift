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

// Where a seam's calls that close cycles re-enter its place graph, read off its facts world: the entry each closing call
// closes on, where a route to it builds that entry in this graph.

extension SeamPlacesDrafts {
	/// Each call that closes a cycle on a build of a route to it, as the level before its edge, with the entry it closes
	/// on: the call's property, built as its type. An edge inside a cycle's component calls a member's builder function;
	/// it closes the cycle only where a route to its caller builds the member already (its cycle identity), and builds the
	/// member anew otherwise. A call that closes on a build above the seam's tree re-enters none of its levels. In facts
	/// order: the variants in order, each one's edges in order.
	func closedOnEntries() -> [(level: SeamPlacesLevelID, entry: SeamSignature.Places.StackEntry)] {
		let variantCount = world.variantCount
		// The identities a call inside a component can close on.
		var memberIdentities = Set<CycleID>()
		for variant in 0..<VariantID(variantCount) {
			let declaration = world.declaration(of: variant)
			for (target, edge) in zip(world.edges(from: declaration), world.edgeFacts(from: declaration)) where edge.isCallEdge {
				memberIdentities.insert(world.cycleIDs[Int(target)])
			}
		}
		/// The identity of the variant's own build, where a call can close on it.
		func ownIdentity(of variant: VariantID) -> Set<CycleID> {
			let identity = world.cycleIDs[Int(world.declaration(of: variant))]
			return memberIdentities.contains(identity) ? [identity] : []
		}
		// Per variant, the member identities some route to it builds and those every route builds, its own included: a fold
		// down the edges that build in line on some route. A call inside a component builds its member anew on a route
		// that does not build the member yet, which some route to the caller does unless every route does; it closes on
		// the member on a route that builds it, which some route does where any does. Over every route at once, never
		// one route at a time, so the fold is linear in the variants and edges, not in the routes.
		let rootVariant = world.rootVariant(0)
		var someRoute = [Set<CycleID>?](repeating: nil, count: variantCount)
		var everyRoute = [Set<CycleID>](repeating: [], count: variantCount)
		someRoute[Int(rootVariant)] = ownIdentity(of: rootVariant)
		everyRoute[Int(rootVariant)] = ownIdentity(of: rootVariant)
		var pending = [rootVariant]
		while let variant = pending.popLast() {
			let declaration = world.declaration(of: variant)
			let some = someRoute[Int(variant)] ?? []
			let every = everyRoute[Int(variant)]
			for ((target, edge), callee) in zip(zip(world.edges(from: declaration), world.edgeFacts(from: declaration)), world.calls(of: variant)) where !(edge.isCallEdge && every.contains(world.cycleIDs[Int(target)])) {
				let own = ownIdentity(of: callee)
				let reachedBySome = some.union(own)
				let reachedByEvery = every.union(own)
				guard let knownBySome = someRoute[Int(callee)] else {
					someRoute[Int(callee)] = reachedBySome
					everyRoute[Int(callee)] = reachedByEvery
					pending.append(callee)
					continue
				}
				let knownByEvery = everyRoute[Int(callee)]
				guard !knownBySome.isSuperset(of: reachedBySome) || !reachedByEvery.isSuperset(of: knownByEvery) else { continue }
				someRoute[Int(callee)] = knownBySome.union(reachedBySome)
				everyRoute[Int(callee)] = knownByEvery.intersection(reachedByEvery)
				pending.append(callee)
			}
		}
		var entries = [(level: SeamPlacesLevelID, entry: SeamSignature.Places.StackEntry)]()
		for variant in 0..<VariantID(variantCount) {
			guard let above = someRoute[Int(variant)] else { continue }
			let declaration = world.declaration(of: variant)
			for (index, (target, edge)) in zip(world.edges(from: declaration), world.edgeFacts(from: declaration)).enumerated() where edge.isCallEdge && above.contains(world.cycleIDs[Int(target)]) {
				guard let property = world.graph.nodes[Int(target)].property else { continue }
				entries.append((SeamPlacesLevelID(variant: variant, edge: Int32(index)), SeamSignature.Places.StackEntry(property: property, concreteType: world.typeTable[Int(world.builtTypes[Int(target)])])))
			}
		}
		return entries
	}

	/// How the closing calls of `closedOnEntries()` differ from the levels of `places`, a seam's stored graph, that close
	/// on an entry: each by the type its scope builds, its next property's label and the entry. The first line is a count
	/// report.
	func closedOnDifferences(from places: SeamSignature.Places) -> [String] {
		func spelled(builtType: TypeDescription?, label: String, entry: SeamSignature.Places.StackEntry) -> String {
			"\(builtType?.asSource ?? "fill") before \(label) closes on \(entry.property.label): \(entry.property.typeDescription.asSource) as \(entry.concreteType.asSource)"
		}
		let entries = closedOnEntries()
		let fromFacts = Set(entries.map { level, entry in
			let node = world.graph.nodes[Int(world.declaration(of: level.variant))]
			return spelled(builtType: node.key.isFill ? nil : node.scope.instantiable.concreteInstantiable, label: entry.property.label, entry: entry)
		})
		let stored = places.levels.compactMap { level in
			level.closesOn.map { spelled(builtType: level.key.builtType, label: level.key.nextProperty?.label ?? "fill", entry: $0) }
		}
		let fromStored = Set(stored)
		return ["report: closes on: \(entries.count) facts levels over \(fromFacts.count) distinct, \(stored.count) stored over \(fromStored.count)"]
			+ fromFacts.subtracting(fromStored).sorted().map { "closes on: only from facts: \($0)" }
			+ fromStored.subtracting(fromFacts).sorted().map { "closes on: only stored: \($0)" }
	}
}
