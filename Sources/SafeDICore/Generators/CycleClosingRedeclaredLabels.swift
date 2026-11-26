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

/// For each declaration a cycle-closing scope in a subtree closes on above the subtree's root, the labels the scopes
/// between it and the root's parent declare – their instantiated, aliased and forwarded properties and their own builder
/// functions' parameters (see `CycleParameter`) – each with the declaration of it that comes first in source order.
/// Empty for nearly every subtree. Only the parent's construction reads a scope's map, so no generator stores it:
/// `ScopeGeneratorUnderConstruction` merges each child's into its parent's as the child's generator is created, and hands
/// the result to the parent's initializer. A map kept on every generator held a copy at each level of a cycle's path for
/// the tree's whole life.
///
/// Each scope adds its own declarations to the map its children's maps make. Kept as a map of labels per declaration,
/// every scope on a cycle's path held its own copy of every label beneath it, and merging the children's copied them
/// again: memory and time that grew with the square of the path. So the map holds, per declaration, the scopes' own
/// declarations as a graph of layers that every map above refers to (`Layer`), and a scope a cycle closes on reads its
/// labels once, from the layers beneath it (`removeRedeclarations(closedOn:)`). Which declaration of a label a reader is
/// handed is the one `CycleParameter.Redeclaration.preceding(_:)` puts first among them all, an order that depends on no
/// walk, so neither the order layers are joined in nor the order they are read in reaches output.
///
/// One copy remains: a scope a cycle closes on while another cycle is still open beneath it adds the labels its own
/// cycle declares to its layer (`ScopeGenerator.cycleParameterSearch`, `redeclarationsOfOwnCycle`), since the type the
/// open cycle builds again is built beneath those declarations too. So a layer of such a scope holds as many labels as
/// its cycle declares, and cycles nested `n` deep merge on the order of `n` cubed labels where they merged `n` squared.
struct CycleClosingRedeclaredLabels: Sendable {
	init() {}

	/// Whether no declaration is closed on in the subtree.
	var isEmpty: Bool {
		layersByClosedOnDeclaration.isEmpty
	}

	/// Starts the map of `closedOnDeclaration` with no label: the scope closes a cycle on it.
	mutating func open(closedOn closedOnDeclaration: ScopeGenerator.BuiltDeclaration) {
		layersByClosedOnDeclaration[closedOnDeclaration] = []
	}

	/// Adds `other`'s layers to this map's: a label both declare keeps the declaration that precedes the other.
	mutating func merge(_ other: Self) {
		for (closedOnDeclaration, otherLayers) in other.layersByClosedOnDeclaration {
			guard var layers = layersByClosedOnDeclaration[closedOnDeclaration] else {
				layersByClosedOnDeclaration[closedOnDeclaration] = otherLayers
				continue
			}
			for layer in otherLayers where !layers.contains(where: { $0 === layer }) {
				layers.append(layer)
			}
			layersByClosedOnDeclaration[closedOnDeclaration] = layers
		}
	}

	/// Adds `redeclarations`, a scope's own, beneath which every declaration of this map is closed on, to each declaration's
	/// labels. Every declaration shares one layer of them.
	mutating func add(_ redeclarations: [String: CycleParameter.Redeclaration]) {
		guard !redeclarations.isEmpty else { return }
		for (closedOnDeclaration, layers) in layersByClosedOnDeclaration {
			layersByClosedOnDeclaration[closedOnDeclaration] = [Layer(redeclarations: redeclarations, beneath: layers)]
		}
	}

	/// Removes `closedOnDeclaration`'s labels from the map and returns them, or `nil` where no cycle closes on it.
	mutating func removeRedeclarations(closedOn closedOnDeclaration: ScopeGenerator.BuiltDeclaration) -> [String: CycleParameter.Redeclaration]? {
		layersByClosedOnDeclaration.removeValue(forKey: closedOnDeclaration).map(Self.redeclarations(in:))
	}

	/// Whether the two hold the same layers for every declaration: equal maps, though two maps that hold other layers of
	/// the same labels can be equal too. `CycleParameterPlan` asks it of a place's results, where comparing the flattened
	/// maps was most of the plan's time. A map built anew of the same labels is counted as found anew, which costs only
	/// searches, never another result: the places above it search again in that round, and the round reports other
	/// results, so one more round runs. That round passes each place the parameters, compared by value, that the round
	/// before found, so where none changed no place searches and it reports none; the plan's parameters are those it
	/// would settle on comparing the maps' labels.
	func holdsSameLayers(as other: Self) -> Bool {
		guard layersByClosedOnDeclaration.count == other.layersByClosedOnDeclaration.count else { return false }
		for (closedOnDeclaration, layers) in layersByClosedOnDeclaration {
			guard let otherLayers = other.layersByClosedOnDeclaration[closedOnDeclaration],
			      layers.count == otherLayers.count,
			      zip(layers, otherLayers).allSatisfy({ $0 === $1 })
			else { return false }
		}
		return true
	}

	/// The labels `layers` and every layer beneath them declare, each with the declaration that precedes the others.
	private static func redeclarations(in layers: [Layer]) -> [String: CycleParameter.Redeclaration] {
		var redeclarations = [String: CycleParameter.Redeclaration]()
		var visited = Set<ObjectIdentifier>()
		// An explicit stack: the layers are as deep as the tree.
		var layersToVisit = layers
		while let layer = layersToVisit.popLast() {
			guard visited.insert(ObjectIdentifier(layer)).inserted else { continue }
			redeclarations.merge(layer.redeclarations) { $0.preceding($1) }
			layersToVisit.append(contentsOf: layer.beneath)
		}
		return redeclarations
	}

	/// One scope's own declarations, and the layers of the scopes beneath it on the paths to the cycle-closing scopes,
	/// which every layer above refers to. Released one level at a time, since the layers are as deep as the tree.
	private final class Layer: Sendable {
		init(redeclarations: [String: CycleParameter.Redeclaration], beneath: [Layer]) {
			self.redeclarations = redeclarations
			beneathSlot = DeferredReleaseSlot(beneath)
		}

		let redeclarations: [String: CycleParameter.Redeclaration]

		var beneath: [Layer] {
			beneathSlot.value
		}

		private let beneathSlot: DeferredReleaseSlot<[Layer]>
	}

	private var layersByClosedOnDeclaration = [ScopeGenerator.BuiltDeclaration: [Layer]]()
}
