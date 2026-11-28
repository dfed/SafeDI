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

/// The concrete types whose `SafeDIMockConfiguration` a mock root's tree reads inside a `Sendable` scope, which takes the
/// `Sendable` form: a type built for a property beneath a `@Sendable` builder function, or beneath what an actor's
/// initializer is handed, whose configuration has a field (a child built for a property, a default-valued parameter of its
/// construction, or a cycle it closes). Read from the declarations of the root's world, never from a generator tree.
///
/// A place's answer follows from what it is built as, the two bits of context it is built in (inside a `Sendable` scope,
/// inside an actor's argument), and its subtree as the tree builds it, which differs between places only where a scope of
/// the subtree closes a cycle on a declaration above it. The tree closes a cycle where a place repeats a declaration on its
/// path by its cycle key, the property as cycle validation sees it and the concrete type, each by its class
/// (`ContextStack.entryClosedOn`). So the keys form a graph of their own, the image of the declarations' graph, and a
/// declaration whose key is in another component than its parent's is a place whose subtree closes on nothing above it: every
/// path to a key above it and back would put the two keys in one component. Such a declaration is folded once per context.
/// A declaration whose key is in its parent's component is laid out per path, as the tree builds it, up to the closers on
/// the path and the declarations of other components, and its sendability is the one cycle closings give it
/// (`ScopeGenerator.cycleClosings`): a closer of a `Sendable` wrapper, or a scope between it and the declaration it closes
/// on that builds in a `@Sendable` function, makes that declaration's builder function `@Sendable`. A component of keys holds
/// a cycle of types, so the paths laid out grow only with the paths through cycles, as the tree's do.
///
/// A fill is no child: the tree's walk leaves them out. It holds the names, for as long as its owner keeps it.
struct TypeFactsSendableConfigurations: Sendable {
	init(root: ConstructionScope, mockedTypeIsActor: Bool) {
		let graph = OrderedGraph(root: TypeFactsDeclaration(scope: root, property: nil, propertyID: nil, erasedToConcreteExistential: false, isFill: false)) { declaration in
			var targets = [TypeFactsDeclaration]()
			for case let .instantiated(property, child, erasedToConcreteExistential, propertyID) in declaration.scope.propertiesToGenerate {
				targets.append(TypeFactsDeclaration(scope: child, property: property, propertyID: propertyID, erasedToConcreteExistential: erasedToConcreteExistential, isFill: false))
			}
			return targets
		}
		// Each declaration's cycle key, numbered in first-reach order; the root, built as no property, has none (-1).
		var cycleKeyIndices = [CycleKey: Int32]()
		var cycleKeyByNode = [Int32](repeating: -1, count: graph.nodes.count)
		for (index, declaration) in graph.nodes.enumerated() {
			guard let propertyID = declaration.propertyID else { continue }
			let interner = declaration.scope.interner
			let cycleKey = CycleKey(
				property: interner.classID(of: interner.asValidatedForDependencyCycles(propertyID)),
				concreteType: interner.classID(of: declaration.scope.concreteTypeID),
			)
			if let existing = cycleKeyIndices[cycleKey] {
				cycleKeyByNode[index] = existing
			} else {
				let new = Int32(cycleKeyIndices.count)
				cycleKeyIndices[cycleKey] = new
				cycleKeyByNode[index] = new
			}
		}
		// The keys' graph: an edge from a key to each key a declaration of it builds as a child.
		var keyTargets = [[Int32]](repeating: [], count: cycleKeyIndices.count + 1)
		var keyEdges = Set<Int64>()
		for index in graph.nodes.indices {
			let source = cycleKeyByNode[index]
			for target in graph.edges(from: index) {
				let targetKey = cycleKeyByNode[Int(target)]
				guard keyEdges.insert(Int64(source) << 32 | Int64(UInt32(bitPattern: targetKey))).inserted else { continue }
				keyTargets[Int(source) + 1].append(targetKey)
			}
		}
		let keyGraph = OrderedGraph(root: Int32(-1)) { keyTargets[Int($0) + 1] }
		var componentByKey = [Int32](repeating: -1, count: cycleKeyIndices.count)
		var keyIsOnCycle = [Bool](repeating: false, count: cycleKeyIndices.count)
		for (index, key) in keyGraph.nodes.enumerated() where key >= 0 {
			componentByKey[Int(key)] = keyGraph.componentByNode[index]
			keyIsOnCycle[Int(key)] = keyGraph.isOnCycle(index)
		}

		// The root is built as no property and is never folded, so each other declaration's property is at its index less one.
		var folding = Folding(graph: graph, builtProperties: graph.nodes.compactMap(\.property), cycleKeyByNode: cycleKeyByNode)
		let rootContext = Context(isInsideSendableScope: false, isInsideActorArgument: mockedTypeIsActor)
		var declarationsToFold = graph.edges(from: 0).map { (node: Int($0), parentContext: rootContext) }
		// The contexts each declaration was folded in, a bit each.
		var foldedContexts = [UInt8](repeating: 0, count: graph.nodes.count)
		while let (node, parentContext) = declarationsToFold.popLast() {
			guard foldedContexts[node] & parentContext.bit == 0 else { continue }
			foldedContexts[node] |= parentContext.bit
			if keyIsOnCycle[Int(cycleKeyByNode[node])] {
				declarationsToFold += folding.foldPaths(from: node, parentContext: parentContext, componentByKey: componentByKey)
			} else {
				// No closer beneath closes on it, so its builder function is `@Sendable` only for its own wrapper.
				let buildsInSendableFunction = folding.isSendableWrapper(node)
				let context = folding.fold(node, parentContext: parentContext, buildsInSendableFunction: buildsInSendableFunction, closesCycle: false)
				declarationsToFold += graph.edges(from: node).map { (node: Int($0), parentContext: context) }
			}
		}
		typeNames = folding.typeNames
	}

	/// The concrete types, as spelled, whose configuration takes the `Sendable` form.
	let typeNames: Set<String>

	/// A declaration's key in the tree's cycle lookup.
	private struct CycleKey: Hashable {
		let property: PropertyClassID
		let concreteType: TypeClassID
	}

	/// What a scope hands the scopes it builds.
	private struct Context {
		let isInsideSendableScope: Bool
		let isInsideActorArgument: Bool

		var bit: UInt8 {
			1 << ((isInsideSendableScope ? 2 : 0) + (isInsideActorArgument ? 1 : 0))
		}
	}

	/// The fold's state: the declarations, the constructions asked of so far, and the names found.
	private struct Folding {
		let graph: OrderedGraph<TypeFactsDeclaration>
		/// The property each declaration but the root is built for, at the declaration's index less one.
		let builtProperties: [Property]
		let cycleKeyByNode: [Int32]
		var constructions = ScopeGenerator.MockConstructions()
		var typeNames = Set<String>()

		func isSendableWrapper(_ node: Int) -> Bool {
			builtProperties[node - 1].propertyType.isSendable
		}

		/// Folds one place of `node`, built in `parentContext`, and returns the context it hands its children, as
		/// `ScopeGenerator.sendableConfigurationTypeNames(ofMockRootOf:)` treats a child.
		mutating func fold(_ node: Int, parentContext: Context, buildsInSendableFunction: Bool, closesCycle: Bool) -> Context {
			let declaration = graph.nodes[node]
			let property = builtProperties[node - 1]
			let instantiable = declaration.scope.instantiable
			let usesMockInitializer = instantiable.mockReturnTypeIsCompatible(withPropertyType: property.typeDescription.asInstantiatedType)
			let isInsideSendableScope = parentContext.isInsideSendableScope || buildsInSendableFunction || parentContext.isInsideActorArgument
			if isInsideSendableScope {
				let needsConfigurationStruct = closesCycle
					|| !graph.edges(from: node).isEmpty
					|| !constructions.construction(
						of: instantiable,
						useMockInitializer: usesMockInitializer,
						builderTypesDeclaredEscaping: declaration.scope.publicMockCall?.typesDeclaredEscaping ?? [],
					).defaultParameters.isEmpty
				if needsConfigurationStruct {
					typeNames.insert(instantiable.concreteInstantiable.asSource)
				}
			}
			return Context(
				isInsideSendableScope: isInsideSendableScope,
				isInsideActorArgument: (instantiable.declarationType == .actorType && !usesMockInitializer) || (parentContext.isInsideActorArgument && property.propertyType.isConstant),
			)
		}

		/// One place of a declaration on the tree's path through a cycle.
		private struct PathPlace {
			let node: Int
			/// The place of the scope that builds it, or -1 for the place folding starts at.
			let parent: Int32
			/// The place on its path it closes a cycle on, or -1.
			let closedOn: Int32
		}

		/// Folds `start`, which is on a cycle of keys, in `parentContext`, laying its places out per path up to the places
		/// that close a cycle and the declarations of another component of keys, and returns those declarations, each with
		/// the context it is built in.
		mutating func foldPaths(from start: Int, parentContext: Context, componentByKey: [Int32]) -> [(node: Int, parentContext: Context)] {
			let component = componentByKey[Int(cycleKeyByNode[start])]
			var places = [PathPlace(node: start, parent: -1, closedOn: -1)]
			// The declarations of other components each place builds, in edge order.
			var exits = [[Int]()]
			// Places are laid out parents first, so a place's children follow it.
			var next = 0
			while next < places.count {
				let place = places[next]
				if place.closedOn < 0 {
					for target in graph.edges(from: place.node) {
						let targetKey = cycleKeyByNode[Int(target)]
						var ancestor = Int32(next)
						while ancestor >= 0, cycleKeyByNode[places[Int(ancestor)].node] != targetKey {
							ancestor = places[Int(ancestor)].parent
						}
						if ancestor >= 0 || componentByKey[Int(targetKey)] == component {
							places.append(PathPlace(node: Int(target), parent: Int32(next), closedOn: ancestor))
							exits.append([])
						} else {
							exits[next].append(Int(target))
						}
					}
				}
				next += 1
			}
			// What cycle closings give each place, children first: the places above it closed on beneath it, and those referred
			// to from a `@Sendable` builder function beneath it (`ScopeGenerator.cycleClosings`). A declaration of another
			// component closes on nothing above it, so it adds nothing.
			var closedOnBeneath = [Set<Int32>](repeating: [], count: places.count)
			var referencedFromSendableFunction = [Set<Int32>](repeating: [], count: places.count)
			var buildsInSendableFunction = [Bool](repeating: false, count: places.count)
			for index in places.indices.reversed() {
				let place = places[index]
				if place.closedOn >= 0 {
					closedOnBeneath[index] = [place.closedOn]
					if isSendableWrapper(place.node) {
						referencedFromSendableFunction[index] = [place.closedOn]
					}
				} else {
					let builds = isSendableWrapper(place.node) || referencedFromSendableFunction[index].contains(Int32(index))
					buildsInSendableFunction[index] = builds
					if builds {
						referencedFromSendableFunction[index].formUnion(closedOnBeneath[index])
					}
					referencedFromSendableFunction[index].remove(Int32(index))
					closedOnBeneath[index].remove(Int32(index))
				}
				if place.parent >= 0 {
					closedOnBeneath[Int(place.parent)].formUnion(closedOnBeneath[index])
					referencedFromSendableFunction[Int(place.parent)].formUnion(referencedFromSendableFunction[index])
				}
			}
			// Each place's context, parents first.
			var contexts = [Context]()
			contexts.reserveCapacity(places.count)
			var declarationsOfOtherComponents = [(node: Int, parentContext: Context)]()
			for (index, place) in places.enumerated() {
				let context = fold(
					place.node,
					parentContext: place.parent >= 0 ? contexts[Int(place.parent)] : parentContext,
					buildsInSendableFunction: buildsInSendableFunction[index],
					closesCycle: place.closedOn >= 0,
				)
				contexts.append(context)
				declarationsOfOtherComponents += exits[index].map { (node: $0, parentContext: context) }
			}
			return declarationsOfOtherComponents
		}
	}
}

/// The `Sendable` configurations of each mock root the fold finds beside those the walk of its generator tree finds
/// (`ScopeGenerator.sendableConfigurationTypeNames(ofMockRootOf:)`), handed to `comparesWalk`, which the tests set, never
/// the tool: the two must be equal on every test and fuzzer graph. The walk runs only where it is set.
public enum TypeFactsSendableConfigurationsObservation {
	@TaskLocal public static var comparesWalk: (@Sendable (TypeFactsSendableConfigurationsComparison) -> Void)?
}

/// One mock root's `Sendable` configurations, from the fold and from the walk.
public struct TypeFactsSendableConfigurationsComparison: Sendable {
	/// The mocked type.
	public let root: String
	/// What mock generation reads: the fold's.
	public let foldedTypeNames: Set<String>
	/// What the walk of the root's generator tree finds.
	public let walkedTypeNames: Set<String>
}
