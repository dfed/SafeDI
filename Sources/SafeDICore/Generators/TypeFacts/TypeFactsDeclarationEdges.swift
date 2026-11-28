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

extension TypeFactsDeclaration {
	/// One edge of a declaration: the declaration it leads to, its entry among its scope's properties to generate (or,
	/// for a fill, among its scope's hole arguments), and the hole a fill fills, `nil` for a child.
	struct Edge {
		let target: TypeFactsDeclaration
		let entry: Int32
		let filledHole: SeamSignature.Hole?
	}

	/// The declaration's edges in the order its scope lists them: each property it instantiates, aliases or holds as a
	/// hole, then each fill it passes. A leaf has none. Every walk over declarations takes them in this order (a world's
	/// graph, `TypeFactsGraph`, and the mock worlds' table, `MockWorldsTable`), so their positions agree. Computed each time
	/// it is asked, and held by no one.
	var edges: [Edge] {
		guard key.leaf == .none else { return [] }
		var edges = [Edge]()
		for (index, propertyToGenerate) in scope.propertiesToGenerate.enumerated() {
			let target = switch propertyToGenerate {
			case let .instantiated(property, child, erasedToConcreteExistential, propertyID):
				TypeFactsDeclaration(scope: child, property: property, propertyID: propertyID, erasedToConcreteExistential: erasedToConcreteExistential, isFill: false)
			case let .aliased(property, fulfillingProperty, erasedToConcreteExistential, onlyIfAvailable, _):
				TypeFactsDeclaration(leafOf: scope, property: property, at: index, erasedToConcreteExistential: erasedToConcreteExistential, aliasOf: fulfillingProperty, onlyIfAvailable: onlyIfAvailable)
			case let .hole(property, erasedToConcreteExistential):
				TypeFactsDeclaration(leafOf: scope, property: property, at: index, erasedToConcreteExistential: erasedToConcreteExistential, aliasOf: nil, onlyIfAvailable: false)
			}
			edges.append(Edge(target: target, entry: Int32(index), filledHole: nil))
		}
		for case let (index, .fill(hole, child, fillContext)) in scope.holeArguments.enumerated() {
			edges.append(Edge(target: TypeFactsDeclaration(scope: child, property: hole.property, propertyID: fillContext.propertyID, erasedToConcreteExistential: false, isFill: true), entry: Int32(index), filledHole: hole))
		}
		return edges
	}
}
