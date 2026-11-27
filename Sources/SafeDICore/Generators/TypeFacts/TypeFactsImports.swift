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

/// What the file generated for a world's root needs imported for the types its tree builds: the union fact of the root
/// (the design's section 3) over every declaration it reaches, each declaration's own being the modules
/// `FulfillerImports.Fulfiller.fulfillers(building:forPropertyOfType:callingHandWrittenMock:)` names for building its
/// type as its property. Read from the declarations alone, never from a generator tree: a node stands for every place
/// of its declaration, so the union over the nodes is the union over the places, however many paths reach them.
///
/// The root reaches every node, so its union is the union of every node's own fact, and no node's set is built. A
/// reader of a subtree's union (the capture check, tier omissions) folds it bottom-up over the components, which are
/// numbered so that every component a node reaches comes before it (`OrderedGraph.componentByNode`).
///
/// Production worlds only: a mock world's own fact also names the module that writes a hand-written mock its tree
/// calls, which reads the mock track's construction column (`TypeFactsConstruction.handWrittenMock`), so mocks keep
/// `ScopeGenerator.fulfillersOfTree(buildingMock:)` until that column is filled. It holds the fulfillers only, for as
/// long as its owner keeps it.
struct TypeFactsImports: Sendable {
	init(root: ConstructionScope) {
		// The declarations the root builds: the properties each instantiates, then the fills it passes. An alias or a hole
		// builds no type, so it imports nothing.
		let graph = OrderedGraph(root: TypeFactsDeclaration(scope: root, property: nil, propertyID: nil, erasedToConcreteExistential: false, isFill: false)) { declaration in
			var targets = [TypeFactsDeclaration]()
			for case let .instantiated(property, child, erasedToConcreteExistential, propertyID) in declaration.scope.propertiesToGenerate {
				targets.append(TypeFactsDeclaration(scope: child, property: property, propertyID: propertyID, erasedToConcreteExistential: erasedToConcreteExistential, isFill: false))
			}
			for case let .fill(hole, child, fillContext) in declaration.scope.holeArguments {
				targets.append(TypeFactsDeclaration(scope: child, property: hole.property, propertyID: fillContext.propertyID, erasedToConcreteExistential: false, isFill: true))
			}
			return targets
		}
		var fulfillers = Set<FulfillerImports.Fulfiller>()
		// The root is built as no property, so it has no fact of its own.
		for declaration in graph.nodes.dropFirst() {
			guard let property = declaration.property else { continue }
			fulfillers.formUnion(FulfillerImports.Fulfiller.fulfillers(
				building: declaration.scope.instantiable,
				forPropertyOfType: property.typeDescription.asInstantiatedType,
				callingHandWrittenMock: false,
			))
		}
		self.fulfillers = fulfillers
		GenerationWork.record(graph.nodes.count, by: .collectingTypesOfATree)
	}

	/// The modules the root's file needs imported for the types its tree builds, each with the type it is needed for.
	let fulfillers: Set<FulfillerImports.Fulfiller>
}

/// The imports of each root the fold finds beside those the walk of its generator tree finds
/// (`ScopeGenerator.fulfillersOfTree(buildingMock:)`), handed to `comparesWalk`, which the tests set, never the tool: the
/// two must be equal on every test and fuzzer graph. The walk runs only where it is set, uncounted by `GenerationWork`.
public enum TypeFactsImportsObservation {
	@TaskLocal public static var comparesWalk: (@Sendable (TypeFactsImportsComparison) -> Void)?
}

/// One root's imports, from the fold and from the walk.
public struct TypeFactsImportsComparison: Sendable {
	/// The root's type.
	public let root: String
	/// What the generated file imports: the fold's.
	public let foldedFulfillers: Set<FulfillerImports.Fulfiller>
	/// What the walk of the root's generator tree finds.
	public let walkedFulfillers: Set<FulfillerImports.Fulfiller>
}
