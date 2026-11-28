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
	/// Each call that closes a cycle on a build of a route to it (`closesCycle(_:)`), as the level before its edge, with
	/// the entry it closes on: the call's property, built as its type. In facts order: the variants in order, each one's
	/// edges in order.
	func closedOnEntries() -> [(level: SeamPlacesLevelID, entry: SeamSignature.Places.StackEntry)] {
		var entries = [(level: SeamPlacesLevelID, entry: SeamSignature.Places.StackEntry)]()
		for variant in 0..<VariantID(world.variantCount) {
			for (index, target) in world.edges(from: world.declaration(of: variant)).enumerated() {
				let level = SeamPlacesLevelID(variant: variant, edge: Int32(index))
				guard closesCycle(level), let property = world.graph.nodes[Int(target)].property else { continue }
				entries.append((level, SeamSignature.Places.StackEntry(property: property, concreteType: world.typeTable[Int(world.builtTypes[Int(target)])])))
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
