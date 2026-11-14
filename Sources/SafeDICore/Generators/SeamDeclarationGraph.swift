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
/// with its path in this tree. The graph enters a fill whose tree holds a site as the declaration of the type it builds,
/// with an edge from the call, so a place inside the fill is a place of that type, and the scopes in a fill's tree start
/// their children in their types' order too.
///
/// A call of an inner seam that passes a place up holds no place in the start order this graph gives (`init(treeRootedAt:)`
/// reads only sites and fills): it is no carrier, so it starts among its type's other children. The enums' graph
/// (`placeHolding(inTreeRootedAt:edges:)`) counts it as a place, so the call has a case, whose payload only a builder a
/// person writes reads in this release: a generated fill reads none of it, and a fill that would read what the passing-up
/// seam binds before the call is reported (`boundByPassingUpSeam`), by ruling for 2.3.0.
struct SeamDeclarationGraph {
	/// Reads the graph of the tree `root` roots, every place of every hole a place.
	init(treeRootedAt root: ScopeGenerator) {
		placeHoldingPropertiesByType = Self.read(treeRootedAt: root) { _, child in
			if child.holeSite != nil {
				.place
			} else if child.fillHole != nil {
				// A fill whose tree holds a site is read as the type it builds: a place inside it is a place of that type, whose
				// builds start their children in its order wherever they are.
				if child.containsBuildSite, let fulfiller = child.children.first {
					.fulfiller(fulfiller)
				} else {
					.skipped
				}
			} else {
				.declaration
			}
		}
	}

	/// What a child of a scope is to a graph: a place, a declaration whose children the graph reads, or neither.
	enum ChildKind {
		case place
		case declaration
		/// A fill whose tree the graph reads, as the declaration of `fulfiller`, the scope the fill builds.
		case fulfiller(ScopeGenerator)
		/// A child the graph leaves out, with its subtree.
		case skipped
	}

	/// What the graph of one hole type's places says of the types of the tree it was read from, for both of its enums: the
	/// plain enum, whose places are built in plain code, and the `@Sendable` enum, whose places are built inside a `@Sendable`
	/// function, each nested by type.
	struct PlaceHolding {
		/// The properties of each type that have a case in its plain enum: a place built in plain code, a call there of an inner
		/// seam that hands up its plain enum, or a property built in plain code whose type has a plain enum. A type none of whose
		/// properties has one is absent.
		let plainCasePropertiesByType: [TypeDescription: Set<Property>]
		/// The properties of each type that have a case of their own label in its `@Sendable` enum: a place held in a `Sendable`
		/// wrapper, a call of an inner seam made in a `@Sendable` function of its own that hands up its plain enum, or a property
		/// built in a `@Sendable` function of its own whose type has a plain enum, which the case holds.
		let sendableOwnCasePropertiesByType: [TypeDescription: Set<Property>]
		/// The properties of each type that have a `<label>_Sendable` case in its `@Sendable` enum: a call of an inner seam that
		/// hands up its `@Sendable` enum, or a property whose type has a `@Sendable` enum, which the case holds.
		let sendableBeneathCasePropertiesByType: [TypeDescription: Set<Property>]
		/// The first build the walk expanded of each type that has a declaration in the graph: every build of a type that
		/// closes no cycle has the same children in the same order, since the order is the type's (`startsAsCarrier(_:)`).
		let firstBuildByType: [TypeDescription: ScopeGenerator]
		/// The type each declaration of a type builds for a property, by the type and the property, for the properties that
		/// are no place.
		let builtTypeByTypeAndProperty: [TypeAndProperty: TypeDescription]
		/// The calls of each type with a case per builder they fill in its plain enum: a fill built in plain code whose type has
		/// a plain enum.
		var plainFillCasesByType = [TypeDescription: Set<FillCase>]()
		/// The calls of each type with such a case of its own label in its `@Sendable` enum: a fill built in a `@Sendable`
		/// function of its own whose type has a plain enum, which the case holds.
		var sendableOwnFillCasesByType = [TypeDescription: Set<FillCase>]()
		/// The calls of each type with a `_Sendable` such case in its `@Sendable` enum: a fill whose type has a `@Sendable` enum.
		var sendableBeneathFillCasesByType = [TypeDescription: Set<FillCase>]()
		/// The type each call's fill of a builder builds, by the type that makes the call and the case.
		var fulfillerTypeByTypeAndFillCase = [TypeAndFillCase: TypeDescription]()
	}

	/// One of an inner seam's builders that a call's fill is passed for, by the key of the inner seam's root enum the builder
	/// is handed, and whether a place inside the fill carries the scope value the fill was handed: not where the fill builds
	/// its type in a `@Sendable` builder function of the type's own – the place it fills is held in a `Sendable` wrapper –
	/// which binds nothing the fill was handed, a value bound outside the innermost `@Sendable` function. Fills that differ in
	/// it are cases of their own, so that each case's payload has one type on every route.
	struct FilledBuilder: Hashable {
		let innerKey: SeamSignature.ScopeEnum.Key
		let carriesInnerScope: Bool

		/// The builder as a case of the `@Sendable` family that holds the `@Sendable` enum of what a `@Sendable` function
		/// beneath it builds, which carries no value bound outside that function.
		var withoutInnerScope: FilledBuilder {
			FilledBuilder(innerKey: innerKey, carriesInnerScope: false)
		}
	}

	/// A call of an inner seam, by its property, and one of its builders that the tree fills with a type whose tree leads to
	/// a place: a case of the calling type's enum.
	struct FillCase: Hashable {
		let property: Property
		let filledBuilder: FilledBuilder
	}

	/// A fill case of a type.
	struct TypeAndFillCase: Hashable {
		let type: TypeDescription
		let fillCase: FillCase
	}

	/// An edge from a call's declaration to the declaration of the type a fill of the call builds, whose tree the graph reads
	/// as any other: the fill builds a type of the seam's tree, nested in the case of the call and the builder filled.
	struct FillEdge: Hashable {
		/// The key of the inner seam's root enum the builder the fill is passed for is handed.
		let innerKey: SeamSignature.ScopeEnum.Key
		/// Whether the fill builds its type in a `@Sendable` function of its own: the fill's, the call's builder function, or
		/// the type's own builder function (`fulfillerBuildsInSendableFunction`).
		let inSendableFunction: Bool
		/// Whether the type's own builder function is `@Sendable`: the place the fill fills is held in a `Sendable` wrapper.
		var fulfillerBuildsInSendableFunction = false

		/// The builder the fill is passed for, as its case of the calling type's enum carries it.
		var filledBuilder: FilledBuilder {
			FilledBuilder(innerKey: innerKey, carriesInnerScope: !fulfillerBuildsInSendableFunction)
		}
	}

	/// A property of a type.
	struct TypeAndProperty: Hashable {
		let type: TypeDescription
		let property: Property
	}

	/// What a child of a scope is to the graph of one hole type's places: each edge it gives its parent's declaration.
	enum PlaceEdge: Hashable {
		/// A declaration whose children the graph reads, built in a `@Sendable` function of its own when `inSendableFunction`.
		case declaration(inSendableFunction: Bool)
		/// A place built in plain code, or a call there of an inner seam that hands up its plain enum.
		case plainPlace
		/// A place held in a `Sendable` wrapper, or a call made in a `@Sendable` function of its own of an inner seam that hands
		/// up its plain enum.
		case sendablePlace
		/// A call of an inner seam that hands up its `@Sendable` enum.
		case sendableBeneathPlace
		/// A call's fill of one of the inner seam's builders (`fillEdges`).
		case fill(FillEdge)
	}

	/// Reads the graph of one hole type's places in the tree `root` roots, in which `edges` says what each child of a scope
	/// gives its parent's declaration: none, for a child the graph leaves out with its subtree, a declaration, or places.
	/// Every build of a declaration is read, since whether a child's builder function is `@Sendable` can differ between them
	/// where a lazy cycle makes it so, and the edges of all of them are joined. An edge whose target dominates its source
	/// closes a cycle on every build and is removed. `fillEdges` says, for a child that is a call, which of its fills the
	/// graph enters: each an edge from the call's declaration to the declaration of the type the fill builds, read as any.
	static func placeHolding(
		inTreeRootedAt root: ScopeGenerator,
		edges: (_ parent: ScopeGenerator, _ child: ScopeGenerator) -> [PlaceEdge],
		fillEdges: (_ parent: ScopeGenerator, _ child: ScopeGenerator) -> [(edge: FillEdge, fulfiller: ScopeGenerator)] = { _, _ in [] },
	) -> PlaceHolding {
		struct KindedEdge: Hashable {
			let property: Property
			let target: Int
			let kind: PlaceEdge
		}
		// The nodes that stand for the places of each kind.
		let plainPlaceNode = 1
		let sendablePlaceNode = 2
		let sendableBeneathPlaceNode = 3
		var nodeIndexByDeclaration = [Declaration: Int]()
		var types: [TypeDescription?] = [root.builtInstantiable?.concreteInstantiable, nil, nil, nil]
		var successors: [[KindedEdge]] = [[], [], [], []]
		var seenEdges: [Set<KindedEdge>] = [[], [], [], []]
		var firstBuildByType = [TypeDescription: ScopeGenerator]()
		var builtTypeByTypeAndProperty = [TypeAndProperty: TypeDescription]()
		var fulfillerTypeByTypeAndFillCase = [TypeAndFillCase: TypeDescription]()
		var generatorsToVisit = [(generator: root, node: Self.entry)]
		/// The node of `declaration`, created when it is new.
		func nodeIndex(of declaration: Declaration) -> Int {
			if let existingNode = nodeIndexByDeclaration[declaration] {
				return existingNode
			}
			let newNode = types.count
			nodeIndexByDeclaration[declaration] = newNode
			types.append(declaration.concreteType)
			successors.append([])
			seenEdges.append([])
			return newNode
		}
		while let (generator, node) = generatorsToVisit.popLast() {
			if let type = types[node], firstBuildByType[type] == nil {
				firstBuildByType[type] = generator
			}
			for child in generator.children {
				guard let property = child.property else { continue }
				// A fill builds its type with the stack of the seam whose hole it fills, so it never closes on this tree's path.
				for (fillEdge, fulfiller) in fillEdges(generator, child) {
					guard let fulfillerProperty = fulfiller.property, let fulfillerType = fulfiller.builtInstantiable?.concreteInstantiable else { continue }
					let target = nodeIndex(of: Declaration(property: fulfillerProperty.asValidatedForDependencyCycles, concreteType: fulfillerType))
					if let type = types[node] {
						// The `@Sendable` family's case that holds what a `@Sendable` function beneath the fill builds carries no inner
						// scope, whatever the fill's.
						for filledBuilder in [fillEdge.filledBuilder, fillEdge.filledBuilder.withoutInnerScope] {
							let typeAndFillCase = TypeAndFillCase(type: type, fillCase: FillCase(property: property, filledBuilder: filledBuilder))
							if fulfillerTypeByTypeAndFillCase[typeAndFillCase] == nil {
								fulfillerTypeByTypeAndFillCase[typeAndFillCase] = fulfillerType
							}
						}
					}
					generatorsToVisit.append((fulfiller, target))
					let edge = KindedEdge(property: property, target: target, kind: .fill(fillEdge))
					if seenEdges[node].insert(edge).inserted {
						successors[node].append(edge)
					}
				}
				for kind in edges(generator, child) {
					let target: Int
					switch kind {
					case .plainPlace:
						target = plainPlaceNode
					case .sendablePlace:
						target = sendablePlaceNode
					case .sendableBeneathPlace:
						target = sendableBeneathPlaceNode
					case .fill:
						// Given by `fillEdges`, with the generator the graph reads.
						continue
					case .declaration:
						guard let builtType = child.builtInstantiable?.concreteInstantiable else { continue }
						if let type = types[node] {
							builtTypeByTypeAndProperty[TypeAndProperty(type: type, property: property)] = builtType
						}
						target = nodeIndex(of: Declaration(property: property.asValidatedForDependencyCycles, concreteType: builtType))
						if !child.closesPropertyCycle {
							generatorsToVisit.append((child, target))
						}
					}
					let edge = KindedEdge(property: property, target: target, kind: kind)
					if seenEdges[node].insert(edge).inserted {
						successors[node].append(edge)
					}
				}
			}
		}
		let immediateDominators = Self.immediateDominators(successors: successors.map { $0.map { Edge(property: $0.property, target: $0.target) } })
		// An edge whose target dominates its source closes a cycle on every build: it is removed.
		var leftEdges = Array(repeating: [KindedEdge](), count: successors.count)
		var predecessorsByLeftEdges = Array(repeating: [(source: Int, kind: PlaceEdge)](), count: successors.count)
		for (source, edges) in successors.enumerated() {
			for edge in edges where edge.target <= sendableBeneathPlaceNode || !Self.dominates(edge.target, source, immediateDominators: immediateDominators) {
				leftEdges[source].append(edge)
				predecessorsByLeftEdges[edge.target].append((source, edge.kind))
			}
		}
		// The nodes whose type has a plain enum: a left edge in plain code reaches a place built in plain code.
		var reachesPlain = Array(repeating: false, count: successors.count)
		reachesPlain[plainPlaceNode] = true
		var nodesToVisit = [plainPlaceNode]
		while let node = nodesToVisit.popLast() {
			for (predecessor, kind) in predecessorsByLeftEdges[node] where !reachesPlain[predecessor] && Self.leadsToPlainEnum(kind) {
				reachesPlain[predecessor] = true
				nodesToVisit.append(predecessor)
			}
		}
		// The nodes whose type has a `@Sendable` enum: a left edge reaches a place built in a `@Sendable` function.
		var reachesSendable = Array(repeating: false, count: successors.count)
		reachesSendable[sendablePlaceNode] = true
		reachesSendable[sendableBeneathPlaceNode] = true
		nodesToVisit = [sendablePlaceNode, sendableBeneathPlaceNode]
		for (source, edges) in leftEdges.enumerated() where edges.contains(where: { Self.buildsInSendableFunction($0.kind) && reachesPlain[$0.target] }) {
			reachesSendable[source] = true
			nodesToVisit.append(source)
		}
		while let node = nodesToVisit.popLast() {
			for (predecessor, kind) in predecessorsByLeftEdges[node] where !reachesSendable[predecessor] && kind != .plainPlace {
				reachesSendable[predecessor] = true
				nodesToVisit.append(predecessor)
			}
		}
		var plainCasePropertiesByType = [TypeDescription: Set<Property>]()
		var sendableOwnCasePropertiesByType = [TypeDescription: Set<Property>]()
		var sendableBeneathCasePropertiesByType = [TypeDescription: Set<Property>]()
		var plainFillCasesByType = [TypeDescription: Set<FillCase>]()
		var sendableOwnFillCasesByType = [TypeDescription: Set<FillCase>]()
		var sendableBeneathFillCasesByType = [TypeDescription: Set<FillCase>]()
		for (source, edges) in leftEdges.enumerated() {
			guard let type = types[source] else { continue }
			for edge in edges {
				switch edge.kind {
				case let .fill(fillEdge):
					let fillCase = FillCase(property: edge.property, filledBuilder: fillEdge.filledBuilder)
					if reachesPlain[edge.target] {
						if fillEdge.inSendableFunction {
							sendableOwnFillCasesByType[type, default: []].insert(fillCase)
						} else {
							plainFillCasesByType[type, default: []].insert(fillCase)
						}
					}
					if reachesSendable[edge.target] {
						sendableBeneathFillCasesByType[type, default: []].insert(FillCase(property: edge.property, filledBuilder: fillEdge.filledBuilder.withoutInnerScope))
					}
				case .plainPlace:
					plainCasePropertiesByType[type, default: []].insert(edge.property)
				case .sendablePlace:
					sendableOwnCasePropertiesByType[type, default: []].insert(edge.property)
				case .sendableBeneathPlace:
					sendableBeneathCasePropertiesByType[type, default: []].insert(edge.property)
				case let .declaration(inSendableFunction):
					if reachesPlain[edge.target] {
						if inSendableFunction {
							sendableOwnCasePropertiesByType[type, default: []].insert(edge.property)
						} else {
							plainCasePropertiesByType[type, default: []].insert(edge.property)
						}
					}
					if reachesSendable[edge.target] {
						sendableBeneathCasePropertiesByType[type, default: []].insert(edge.property)
					}
				}
			}
		}
		return PlaceHolding(
			plainCasePropertiesByType: plainCasePropertiesByType,
			sendableOwnCasePropertiesByType: sendableOwnCasePropertiesByType,
			sendableBeneathCasePropertiesByType: sendableBeneathCasePropertiesByType,
			firstBuildByType: firstBuildByType,
			builtTypeByTypeAndProperty: builtTypeByTypeAndProperty,
			plainFillCasesByType: plainFillCasesByType,
			sendableOwnFillCasesByType: sendableOwnFillCasesByType,
			sendableBeneathFillCasesByType: sendableBeneathFillCasesByType,
			fulfillerTypeByTypeAndFillCase: fulfillerTypeByTypeAndFillCase,
		)
	}

	/// Whether an edge of `kind` leads its source to a plain enum where its target has one: it is built in plain code.
	private static func leadsToPlainEnum(_ kind: PlaceEdge) -> Bool {
		switch kind {
		case .plainPlace:
			true
		case let .declaration(inSendableFunction):
			!inSendableFunction
		case let .fill(fillEdge):
			!fillEdge.inSendableFunction
		case .sendablePlace, .sendableBeneathPlace:
			false
		}
	}

	/// Whether an edge of `kind` builds its target in a `@Sendable` function of its own.
	private static func buildsInSendableFunction(_ kind: PlaceEdge) -> Bool {
		switch kind {
		case let .declaration(inSendableFunction):
			inSendableFunction
		case let .fill(fillEdge):
			fillEdge.inSendableFunction
		case .plainPlace, .sendablePlace, .sendableBeneathPlace:
			false
		}
	}

	private static func read(treeRootedAt root: ScopeGenerator, kind: (_ parent: ScopeGenerator, _ child: ScopeGenerator) -> ChildKind) -> [TypeDescription: Set<Property>] {
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
				var child = child
				switch kind(generator, child) {
				case .skipped:
					continue
				case .place:
					successors[node].append(Edge(property: child.property, target: Self.place))
					continue
				case .declaration:
					break
				case let .fulfiller(fulfiller):
					child = fulfiller
				}
				if let property = child.property, let builtType = child.builtInstantiable?.concreteInstantiable {
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
		return placeHoldingPropertiesByType
	}

	/// The properties of each type that hold a place, by type. A type none of whose properties holds one is absent.
	let placeHoldingPropertiesByType: [TypeDescription: Set<Property>]

	/// Whether some build of a type in the tree `root` roots, inside a fill whose code is generated or outside every fill,
	/// has a child that holds a place by its
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
			for child in generator.children {
				// A fill's tree starts in the order of the types it builds too.
				guard child.fillHole == nil else {
					if child.fillEmitsCode {
						generatorsToVisit += child.children
					}
					continue
				}
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
