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

extension DependencyTreeGenerator {
	/// Decides, from the facts of each type and without walking any route, whether some route of the trees
	/// `validatePropertiesAreFulfillable(onRootScopes:…)` validates may fail one of that validation's judgements.
	///
	/// **The fold errs one way only.** It may answer that some route may fail for trees that pass, which costs the walk
	/// that then judges every route. It never answers that no route fails for trees the walk rejects: each of its
	/// questions is asked of every route the scope graph has, a route no tree takes included, and each is answered "may
	/// fail" wherever the facts it reads do not rule the judgement out. Both test executors hold it to that on every graph
	/// they generate (`ValidationWalkObservation.foldComparison`).
	///
	/// A node is a scope the roots reach through the properties they instantiate, once however many routes reach it. A
	/// read is a node's own receive: a label with the forms that answer it. Each question is one of reach over the nodes,
	/// asked per (node, read) and remembered per read, so its work grows with the scopes between a read and what answers
	/// it, never with the routes:
	///
	/// - A required receive is unfulfillable where a route to its node from a root passes no node that surely provides it,
	///   or leaves the tree built for it without passing one.
	/// - A receive is hidden where a declaration of its label in a form it does not accept reaches its node through nodes
	///   that do not declare the label.
	/// - A receive closes a cycle where a value built above its node reaches it through nodes whose nearest declaration of
	///   the label is not that value, and the node, or a type it requires, requires the value.
	/// - A cycle no instantiator defers is a cycle of the edges that build values.
	/// - A lap a cycle builds again can be judged otherwise than its first build only where a node of the cycle declares,
	///   or makes receivable, a label the cycle's trees read that some judgement can fire for.
	///
	/// "May be being built" is a may-fact: the fold asks whether some route builds a value around a node, never whether
	/// every route does, so it only ever sends trees to the walk.
	///
	/// **Its initializer is its one read of a scope.** With the two functions it calls (`receives(of:)`,
	/// `receivedCycleFoldInput(scopes:…)`), the initializer reads the scopes and the scope map and keeps what the questions
	/// ask as facts by value, and neither a scope nor the map: every question reads those facts alone, as it will read the
	/// columns of the facts core.
	///
	/// It holds one record per node and per edge, and each question's visited sets, for as long as the value lives: one
	/// call of the validation.
	struct FulfillmentFold {
		/// The judgement some route may fail.
		enum RouteThatMayFail: String, CaseIterable, Sendable {
			/// A rename names another type than its own type's property of its label.
			case contradictingRename
			/// A cycle of values no instantiator defers.
			case valueCycle
			/// A required receive nothing above provides, or of a value still being built.
			case unfulfillableReceive
			/// A receive whose nearest declaration of its label provides no form it accepts.
			case hiddenReceive
			/// A receive, or a receive of a type it requires, of a value still being built.
			case receivedCycle
			/// A required receive of a rename whose fulfilling property is still being built.
			case renamedReceive
			/// A lap a cycle builds again beneath a declaration its first build did not see.
			case lapBuiltAgain
		}

		/// A node's own receive: what it reads from above it.
		struct Receive {
			/// The property read from above: the receive's own, or the property a rename is fulfilled by.
			let property: Property
			/// The forms that answer the read.
			let acceptedProperties: Set<Property>
			let isRequired: Bool
			/// Whether the receive is a rename's read of the property it is fulfilled by.
			let isRename: Bool
		}

		/// The receives `scope`'s own type makes, in declaration order, for the initializer: the facts core's `receives(of:)`
		/// answers the same for a declaration, once its world is built before validation.
		static func receives(of scope: Scope) -> [Receive] {
			scope.instantiable.dependencies.compactMap { dependency in
				switch dependency.source {
				case let .received(onlyIfAvailable):
					Receive(
						property: dependency.property,
						acceptedProperties: [dependency.property, dependency.property.asUnwrappedProperty],
						isRequired: !onlyIfAvailable,
						isRename: false,
					)
				case let .aliased(fulfillingProperty, _, onlyIfAvailable):
					Receive(
						property: fulfillingProperty,
						acceptedProperties: onlyIfAvailable
							? Set(fulfillingProperty.formsReadByOnlyIfAvailableReceive)
							: [fulfillingProperty, fulfillingProperty.asUnwrappedProperty],
						isRequired: !onlyIfAvailable,
						isRename: true,
					)
				case .instantiated, .forwarded:
					nil
				}
			}
		}

		/// A property a node instantiates, with the node it builds.
		private struct Edge {
			let parent: Int
			let child: Int
			let declaredProperty: Property
			/// The property as cycle validation sees it.
			let validatedProperty: Property
			let lazilyInstantiatedInstanceProperty: Property?
			let isBuilder: Bool

			/// Whether the tree the edge builds cannot receive `property` from the edge's own declaration.
			func withholds(_ property: Property) -> Bool {
				(!isBuilder && declaredProperty == property) || lazilyInstantiatedInstanceProperty == property
			}
		}

		/// A declaration of a label, as `FulfillmentForms` holds it.
		private typealias Declaration = FulfillmentForms

		private let cyclesOnly: Bool
		private let nodeCount: Int
		private let edges: [Edge]
		private let incomingEdges: [[Int]]
		private let outgoingEdges: [[Int]]
		/// Whether a root whose tree is validated for cycles and unfulfillable receives reaches each node.
		private let isValidatedForCycles: [Bool]
		/// Whether a root whose tree is validated for hidden receives reaches each node.
		private let isValidatedForHiddenReceives: [Bool]
		/// For each node that is such a root, the properties receivable at it as each such root.
		private let rootReceivableProperties: [Int: [Set<Property>]]
		/// What each node makes receivable to the nodes it builds on every route.
		private let surelyProvidedProperties: [Set<Property>]
		/// The declaration each node enters as the closest of each label for the nodes it builds.
		private let declarationsByLabel: [[String: Declaration]]
		private let receives: [[Receive]]
		/// Whether a rename of some node validated for hidden receives names another type than its own type's property of
		/// its label.
		private let someRenameContradictsOwnProperty: Bool
		/// The concrete type each node is built as, numbered in the order the nodes first name it. A cycle repeats a
		/// concrete type, which two nodes can share.
		private let typeIndexByNode: [Int]
		private let typeCount: Int
		/// What each node's own type creates.
		private let createdProperties: [Set<Property>]
		/// What each node makes available to the nodes it builds.
		private let providedProperties: [Set<Property>]
		/// The properties each node requires from above, as declared.
		private let requiredProperties: [[Property]]
		/// What the fold of received properties reads (`ReceivedCycleFold`), or `nil` where a rename is left to the walk.
		private let receivedCycleInput: ReceivedCycleFold.Input?

		init(
			rootScopes: [ValidatedRootScope],
			additionalMockRootScopes: [ValidatedRootScope],
			typeDescriptionToScopeMap: [TypeDescription: Scope],
			cyclesOnly: Bool,
		) {
			self.cyclesOnly = cyclesOnly
			var scopes = [Scope]()
			var indexByScope = [Scope: Int]()
			var edges = [Edge]()
			var incomingEdges = [[Int]]()
			var outgoingEdges = [[Int]]()
			func index(of scope: Scope) -> Int {
				if let index = indexByScope[scope] {
					return index
				} else {
					indexByScope[scope] = scopes.count
					scopes.append(scope)
					incomingEdges.append([])
					outgoingEdges.append([])
					return scopes.count - 1
				}
			}
			var rootReceivableProperties = [Int: [Set<Property>]]()
			var cycleRoots = [Int]()
			var hiddenReceiveRoots = [Int]()
			for rootScope in rootScopes {
				let rootIndex = index(of: rootScope.scope)
				rootReceivableProperties[rootIndex, default: []].append(Set(rootScope.scope.properties).union(rootScope.receivedFromOutside))
				cycleRoots.append(rootIndex)
				if !cyclesOnly || rootScope.scope.instantiable.generatesMock || additionalMockRootScopes.contains(where: { $0.scope == rootScope.scope }) {
					hiddenReceiveRoots.append(rootIndex)
				}
			}
			for rootScope in additionalMockRootScopes {
				hiddenReceiveRoots.append(index(of: rootScope.scope))
			}
			var nextIndex = 0
			while nextIndex < scopes.count {
				let scope = scopes[nextIndex]
				for propertyToGenerate in scope.propertiesToGenerate {
					switch propertyToGenerate {
					case let .instantiated(declaredProperty, childScope, _):
						let childIndex = index(of: childScope)
						incomingEdges[childIndex].append(edges.count)
						outgoingEdges[nextIndex].append(edges.count)
						edges.append(Edge(
							parent: nextIndex,
							child: childIndex,
							declaredProperty: declaredProperty,
							validatedProperty: declaredProperty.asValidatedForDependencyCycles,
							lazilyInstantiatedInstanceProperty: propertyToGenerate.lazilyInstantiatedInstanceProperty,
							isBuilder: ScopeGenerator.isBuilder(declaredProperty),
						))
					case .aliased, .hole:
						continue
					}
				}
				nextIndex += 1
			}
			func nodesReached(from roots: [Int]) -> [Bool] {
				var isReached = [Bool](repeating: false, count: scopes.count)
				var pending = [Int]()
				for root in roots where !isReached[root] {
					isReached[root] = true
					pending.append(root)
				}
				while let reached = pending.popLast() {
					for edgeIndex in outgoingEdges[reached] where !isReached[edges[edgeIndex].child] {
						isReached[edges[edgeIndex].child] = true
						pending.append(edges[edgeIndex].child)
					}
				}
				return isReached
			}
			let isValidatedForCycles = nodesReached(from: cycleRoots)
			let isValidatedForHiddenReceives = nodesReached(from: hiddenReceiveRoots)
			self.isValidatedForCycles = isValidatedForCycles
			self.isValidatedForHiddenReceives = isValidatedForHiddenReceives
			self.rootReceivableProperties = rootReceivableProperties
			surelyProvidedProperties = scopes.map { scope in
				// What `insertProperties` inserts whatever the route: all but a receive only if available.
				var properties = scope.providedProperties
				for dependency in scope.instantiable.dependencies {
					switch dependency.source {
					case let .received(onlyIfAvailable):
						if !onlyIfAvailable {
							properties.insert(dependency.property)
						}
					case .instantiated, .forwarded, .aliased:
						properties.insert(dependency.property)
						if let instanceProperty = dependency.lazilyInstantiatedInstanceProperty {
							properties.insert(instanceProperty)
						}
					}
				}
				return properties
			}
			declarationsByLabel = scopes.map { scope in
				// What `enterDeclarations` enters.
				var declarations = [String: Declaration]()
				for dependency in scope.instantiable.dependencies where scope.createdProperties.contains(dependency.property) {
					declarations[dependency.property.label] = Declaration(
						property: dependency.property,
						lazilyInstantiatedInstanceProperty: dependency.lazilyInstantiatedInstanceProperty,
					)
				}
				return declarations
			}
			receives = scopes.map(Self.receives(of:))
			someRenameContradictsOwnProperty = scopes.indices.contains {
				isValidatedForHiddenReceives[$0] && !DependencyTreeGenerator.renamesContradictingOwnProperties(in: scopes[$0]).isEmpty
			}
			var typeIndexByType = [TypeDescription: Int]()
			typeIndexByNode = scopes.map { scope in
				let type = scope.instantiable.concreteInstantiable
				if let typeIndex = typeIndexByType[type] {
					return typeIndex
				} else {
					typeIndexByType[type] = typeIndexByType.count
					return typeIndexByType.count - 1
				}
			}
			typeCount = typeIndexByType.count
			createdProperties = scopes.map(\.createdProperties)
			providedProperties = scopes.map(\.providedProperties)
			requiredProperties = scopes.map { $0.requiredReceivedProperties.map(\.property) }
			receivedCycleInput = Self.receivedCycleFoldInput(
				scopes: scopes,
				edges: edges,
				outgoingEdges: outgoingEdges,
				isValidatedForCycles: isValidatedForCycles,
				typeDescriptionToScopeMap: typeDescriptionToScopeMap,
				cyclesOnly: cyclesOnly,
			)
			nodeCount = scopes.count
			self.edges = edges
			self.incomingEdges = incomingEdges
			self.outgoingEdges = outgoingEdges
		}

		/// The first judgement some route may fail, cheapest question first, or `nil` when no route fails any.
		func firstRouteThatMayFail() -> RouteThatMayFail? {
			if someRenameContradictsOwnProperty {
				return .contradictingRename
			} else if someCycleBuildsOnlyValues() {
				return .valueCycle
			} else if someRequiredReceiveMayBeUnfulfillable() {
				return .unfulfillableReceive
			} else if someReceiveMayBeHidden() {
				return .hiddenReceive
			} else {
				guard let receivedCycleFold = receivedCycleInput.map(ReceivedCycleFold.init) else {
					return .renamedReceive
				}
				if receivedCycleFold.edgeThatMayCloseCycle != nil {
					return .receivedCycle
				} else if receivedCycleFold.renameThatMayCloseCycle != nil {
					return .renamedReceive
				} else if someLapBuiltAgainMayBeJudgedAnew() {
					return .lapBuiltAgain
				} else {
					return nil
				}
			}
		}

		// MARK: Cycles of values

		/// The component of each node's concrete type in the graph of the types `includedEdges` join, and whether each
		/// component holds a cycle. A cycle repeats a concrete type, which two nodes can share, so the graph is of types.
		private func typeComponents(joinedBy includesEdge: (Edge) -> Bool) -> (componentByScope: [Int], componentHoldsCycle: [Bool]) {
			var arrows = [Set<Int>](repeating: [], count: typeCount)
			for edge in edges where includesEdge(edge) {
				arrows[typeIndexByNode[edge.parent]].insert(typeIndexByNode[edge.child])
			}
			let componentByType = ScopeGenerator.stronglyConnectedComponents(of: arrows)
			var typeCountByComponent = [Int: Int]()
			for component in componentByType {
				typeCountByComponent[component, default: 0] += 1
			}
			var componentHoldsCycle = [Bool](repeating: false, count: (componentByType.max() ?? -1) + 1)
			for typeIndex in arrows.indices {
				let component = componentByType[typeIndex]
				if typeCountByComponent[component, default: 0] > 1 || arrows[typeIndex].contains(typeIndex) {
					componentHoldsCycle[component] = true
				}
			}
			return (typeIndexByNode.map { componentByType[$0] }, componentHoldsCycle)
		}

		/// Whether the edges that build values hold a cycle: every route around it repeats a declaration with no
		/// instantiator between.
		private func someCycleBuildsOnlyValues() -> Bool {
			typeComponents { $0.validatedProperty.propertyType.isConstant }.componentHoldsCycle.contains(true)
		}

		// MARK: Unfulfillable receives

		private func someRequiredReceiveMayBeUnfulfillable() -> Bool {
			var verifiedScopesByProperty = [Property: Set<Int>]()
			for scopeIndex in 0..<nodeCount where isValidatedForCycles[scopeIndex] {
				for property in requiredProperties[scopeIndex] {
					guard !createdProperties[scopeIndex].contains(property),
					      verifiedScopesByProperty[property, default: []].insert(scopeIndex).inserted
					else { continue }
					let mayBeUnfulfillable = cyclesOnly
						? mayBeBuiltAround(property, receivedAt: scopeIndex, verifiedScopes: &verifiedScopesByProperty[property, default: []])
						: mayBeProvidedByNothing(property, receivedAt: scopeIndex, verifiedScopes: &verifiedScopesByProperty[property, default: []])
					guard !mayBeUnfulfillable else { return true }
				}
			}
			return false
		}

		/// Whether some route to the node at `scopeIndex` leaves `property` unreceivable there: it comes from a root that
		/// does not hold the property, or out of a tree built for it, through no node that surely provides it.
		private func mayBeProvidedByNothing(_ property: Property, receivedAt scopeIndex: Int, verifiedScopes: inout Set<Int>) -> Bool {
			var pending = [scopeIndex]
			while let reached = pending.popLast() {
				for edgeIndex in incomingEdges[reached] where isValidatedForCycles[edges[edgeIndex].parent] {
					let edge = edges[edgeIndex]
					guard !edge.withholds(property) else { return true }
					guard !surelyProvidedProperties[edge.parent].contains(property) else { continue }
					guard rootReceivableProperties[edge.parent, default: []].allSatisfy({ $0.contains(property) }) else { return true }
					if verifiedScopes.insert(edge.parent).inserted {
						pending.append(edge.parent)
					}
				}
			}
			return false
		}

		/// In a tree whose root binds every receive, whether some route to the node at `scopeIndex` builds the non-optional
		/// form of `property` around it while nothing between provides either form.
		private func mayBeBuiltAround(_ property: Property, receivedAt scopeIndex: Int, verifiedScopes: inout Set<Int>) -> Bool {
			let unwrappedProperty = property.asUnwrappedProperty
			let validatedUnwrappedProperty = unwrappedProperty.asValidatedForDependencyCycles
			var pending = [scopeIndex]
			while let reached = pending.popLast() {
				for edgeIndex in incomingEdges[reached] where isValidatedForCycles[edges[edgeIndex].parent] {
					let edge = edges[edgeIndex]
					let providesItself = edge.isBuilder && (edge.declaredProperty == property || edge.declaredProperty == unwrappedProperty)
					guard edge.validatedProperty != validatedUnwrappedProperty || providesItself,
					      !edge.withholds(property),
					      !edge.withholds(unwrappedProperty)
					else { return true }
					guard !surelyProvidedProperties[edge.parent].contains(property),
					      !surelyProvidedProperties[edge.parent].contains(unwrappedProperty)
					else { continue }
					if verifiedScopes.insert(edge.parent).inserted {
						pending.append(edge.parent)
					}
				}
			}
			return false
		}

		// MARK: Hidden receives

		/// The labels some declaration of which some read of them does not accept: the only labels a declaration can hide
		/// a read of.
		private func labelsSomeDeclarationHidesSomeReadOf() -> Set<String> {
			var declarationsByLabel = [String: [Declaration]]()
			var acceptedPropertiesOfReadsByLabel = [String: [Set<Property>]]()
			for scopeIndex in 0..<nodeCount {
				for (label, declaration) in self.declarationsByLabel[scopeIndex] {
					declarationsByLabel[label, default: []].append(declaration)
				}
				for receive in receives[scopeIndex] {
					acceptedPropertiesOfReadsByLabel[receive.property.label, default: []].append(receive.acceptedProperties)
				}
			}
			var labels = Set<String>()
			for (label, acceptedPropertiesOfReads) in acceptedPropertiesOfReadsByLabel {
				let someDeclarationHidesSomeRead = declarationsByLabel[label, default: []].contains { declaration in
					acceptedPropertiesOfReads.contains { !Self.declaration(declaration, answers: $0) }
				}
				if someDeclarationHidesSomeRead {
					labels.insert(label)
				}
			}
			return labels
		}

		private static func declaration(_ declaration: Declaration, answers acceptedProperties: Set<Property>) -> Bool {
			acceptedProperties.contains(declaration.property) || declaration.lazilyInstantiatedInstanceProperty.map(acceptedProperties.contains) ?? false
		}

		private func someReceiveMayBeHidden() -> Bool {
			let hidingLabels = labelsSomeDeclarationHidesSomeReadOf()
			guard !hidingLabels.isEmpty else { return false }
			// Every property some node or root can make receivable: outside a mock's tree, a receive is hidden only where
			// one of the forms it accepts is among them.
			var propertiesSomeNodeProvides = Set<Property>()
			if !cyclesOnly {
				for scopeIndex in 0..<nodeCount {
					// All a node's type declares and all the node provides: what it surely provides, and each property it
					// receives only if available.
					propertiesSomeNodeProvides.formUnion(surelyProvidedProperties[scopeIndex])
					for receive in receives[scopeIndex] where !receive.isRequired && !receive.isRename {
						propertiesSomeNodeProvides.insert(receive.property)
					}
					for rootProperties in rootReceivableProperties[scopeIndex, default: []] {
						propertiesSomeNodeProvides.formUnion(rootProperties)
					}
				}
			}
			var verifiedScopesByRead = [Set<Property>: Set<Int>]()
			for scopeIndex in 0..<nodeCount where isValidatedForHiddenReceives[scopeIndex] {
				for receive in receives[scopeIndex] where hidingLabels.contains(receive.property.label) {
					guard receive.acceptedProperties.isDisjoint(with: createdProperties[scopeIndex]),
					      cyclesOnly || !receive.acceptedProperties.isDisjoint(with: propertiesSomeNodeProvides),
					      verifiedScopesByRead[receive.acceptedProperties, default: []].insert(scopeIndex).inserted
					else { continue }
					var pending = [scopeIndex]
					while let reached = pending.popLast() {
						for edgeIndex in incomingEdges[reached] where isValidatedForHiddenReceives[edges[edgeIndex].parent] {
							let parent = edges[edgeIndex].parent
							if let declaration = declarationsByLabel[parent][receive.property.label] {
								guard Self.declaration(declaration, answers: receive.acceptedProperties) else { return true }
							} else if verifiedScopesByRead[receive.acceptedProperties, default: []].insert(parent).inserted {
								pending.append(parent)
							}
						}
					}
				}
			}
			return false
		}

		// MARK: Received cycles and renamed receives

		/// What the fold of received properties reads (`ReceivedCycleFold`), or `nil` where a rename only if available
		/// renames another that some receive requires, which is left to the walk. For the initializer, which reads it from
		/// the scopes: properties become IDs here, in the order they are first met.
		private static func receivedCycleFoldInput(
			scopes: [Scope],
			edges: [Edge],
			outgoingEdges: [[Int]],
			isValidatedForCycles: [Bool],
			typeDescriptionToScopeMap: [TypeDescription: Scope],
			cyclesOnly: Bool,
		) -> ReceivedCycleFold.Input? {
			var propertyIDs = [Property: Int32]()
			var scopeOfProperty = [Int32]()
			var foldScopes = scopes
			var scopeIndices = [Scope: Int]()
			for (index, scope) in scopes.enumerated() {
				scopeIndices[scope] = index
			}
			var propertiesBuiltByAScope = Set<Property>()
			var declaredRequiredProperties = Set<Property>()
			for scope in Set(typeDescriptionToScopeMap.values).union(scopes) {
				for requiredReceivedProperty in scope.requiredReceivedProperties {
					declaredRequiredProperties.insert(requiredReceivedProperty.property)
				}
				for dependency in scope.instantiable.dependencies {
					switch dependency.source {
					case .instantiated, .aliased:
						propertiesBuiltByAScope.insert(dependency.property.asValidatedForDependencyCycles)
					case .received, .forwarded:
						continue
					}
				}
			}
			func id(of property: Property) -> Int32 {
				if let id = propertyIDs[property] {
					return id
				} else {
					let id = Int32(scopeOfProperty.count)
					propertyIDs[property] = id
					// A property every tree is handed is followed to no scope (`isHanded`).
					if let scope = typeDescriptionToScopeMap[property.typeDescription],
					   propertiesBuiltByAScope.contains(property) || cyclesOnly && DependencyTreeGenerator.mockCanBuild(property, from: scope)
					{
						if let index = scopeIndices[scope] {
							scopeOfProperty.append(Int32(index))
						} else {
							scopeIndices[scope] = foldScopes.count
							scopeOfProperty.append(Int32(foldScopes.count))
							foldScopes.append(scope)
						}
					} else {
						scopeOfProperty.append(-1)
					}
					return id
				}
			}
			let foldEdges = edges.map { edge in
				ReceivedCycleFold.Edge(
					parent: Int32(edge.parent),
					child: Int32(edge.child),
					property: id(of: edge.validatedProperty),
					isBuilder: edge.isBuilder,
					isJudged: isValidatedForCycles[edge.parent],
				)
			}
			var walkStarts = [[Int32]](repeating: [], count: scopes.count)
			var renames = [ReceivedCycleFold.Rename]()
			var propertiesOfRenamesOnlyIfAvailable = Set<Property>()
			var propertiesRenamesAreReceivedAs = Set<Property>()
			var fulfillingPropertiesOfRequiredRenamesOnlyIfAvailable = [Property]()
			for scopeIndex in scopes.indices where isValidatedForCycles[scopeIndex] {
				for dependency in scopes[scopeIndex].instantiable.dependencies {
					guard case let .aliased(fulfillingProperty, _, onlyIfAvailable) = dependency.source else { continue }
					if onlyIfAvailable {
						propertiesOfRenamesOnlyIfAvailable.formUnion(dependency.receivableProperties)
					}
					guard dependency.receivableProperties.contains(where: declaredRequiredProperties.contains) else { continue }
					propertiesRenamesAreReceivedAs.formUnion(dependency.receivableProperties)
					// A receive of the rename built inside the sibling the rename is fulfilled by.
					for edgeIndex in outgoingEdges[scopeIndex] where edges[edgeIndex].declaredProperty.label == fulfillingProperty.label {
						renames.append(ReceivedCycleFold.Rename(edge: Int32(edgeIndex), receivableProperties: dependency.receivableProperties.map(id(of:))))
					}
					if onlyIfAvailable {
						fulfillingPropertiesOfRequiredRenamesOnlyIfAvailable.append(fulfillingProperty)
						// The property the rename is bound from is walked from the scope that declares the rename.
						walkStarts[scopeIndex].append(id(of: fulfillingProperty.asValidatedForDependencyCycles))
					}
				}
			}
			// A rename only if available of another, which a receive of the first then requires in turn: left to the walk.
			guard !fulfillingPropertiesOfRequiredRenamesOnlyIfAvailable.contains(where: propertiesOfRenamesOnlyIfAvailable.contains) else {
				return nil
			}
			// Asking a scope for its required properties can name a property, and so a scope, not met before.
			var requiredProperties = [[Int32]]()
			while requiredProperties.count < foldScopes.count {
				requiredProperties.append(foldScopes[requiredProperties.count].requiredReceivedProperties.map { id(of: $0.property.asValidatedForDependencyCycles) })
			}
			var declaredRequirements = [[Int32]](repeating: [], count: foldScopes.count)
			for scopeIndex in scopes.indices {
				for requiredReceivedProperty in scopes[scopeIndex].requiredReceivedProperties where propertiesRenamesAreReceivedAs.contains(requiredReceivedProperty.property) {
					declaredRequirements[scopeIndex].append(id(of: requiredReceivedProperty.property))
				}
			}
			walkStarts.append(contentsOf: [[Int32]](repeating: [], count: foldScopes.count - walkStarts.count))
			return ReceivedCycleFold.Input(
				propertyCount: scopeOfProperty.count,
				// Every scope of the trees, since a root of one tree can be built inside another.
				roots: scopes.indices.map(Int32.init),
				edges: foldEdges,
				requiredProperties: requiredProperties,
				declaredRequiredProperties: declaredRequirements,
				scopeOfProperty: scopeOfProperty,
				walkStarts: walkStarts,
				renames: renames,
			)
		}

		// MARK: Laps built again

		private func someLapBuiltAgainMayBeJudgedAnew() -> Bool {
			let (componentByScope, componentHoldsCycle) = typeComponents { _ in true }
			let scopesOnCycles = (0..<nodeCount).filter { componentHoldsCycle[componentByScope[$0]] }
			guard !scopesOnCycles.isEmpty else { return false }
			// The labels a node between a scope a cycle closes on and the scope that closes it can declare, or make
			// receivable, for the lap.
			var labelsNewToSomeLap = Set<String>()
			for scopeIndex in scopesOnCycles {
				labelsNewToSomeLap.formUnion(declarationsByLabel[scopeIndex].keys)
				for providedProperty in providedProperties[scopeIndex] {
					labelsNewToSomeLap.insert(providedProperty.label)
				}
				if !cyclesOnly {
					for receive in receives[scopeIndex] where !receive.isRequired && !receive.isRename {
						labelsNewToSomeLap.insert(receive.property.label)
					}
				}
			}
			// The labels the trees of the cycles read.
			var labelsReadOnSomeLap = Set<String>()
			var isReached = [Bool](repeating: false, count: nodeCount)
			var pending = scopesOnCycles
			for scopeIndex in scopesOnCycles {
				isReached[scopeIndex] = true
			}
			while let reached = pending.popLast() {
				for receive in receives[reached] {
					labelsReadOnSomeLap.insert(receive.property.label)
				}
				for edgeIndex in outgoingEdges[reached] where !isReached[edges[edgeIndex].child] {
					isReached[edges[edgeIndex].child] = true
					pending.append(edges[edgeIndex].child)
				}
			}
			let labelsToJudge = labelsNewToSomeLap.intersection(labelsReadOnSomeLap)
			guard !labelsToJudge.isEmpty else { return false }
			guard labelsToJudge.isDisjoint(with: labelsSomeDeclarationHidesSomeReadOf()) else { return true }
			// A required receive closes a cycle on a lap only where its new nearest declaration is still being built around
			// the scope that closes the cycle (`validateTreeBuiltAgainByCycle`). The lap is the tree of a scope of a cycle,
			// entered by an edge of the cycle. The declaration is new only where its label is not that edge's, and still being
			// built only where an edge of its label is on the stack between the two builds of the scope, so that edge joins two
			// scopes of the same cycle. The receive reads that declaration only where no scope from the lap's scope down to
			// it declares the label again.
			var componentsByLabelOfEdgeInside = [String: Set<Int>]()
			for edge in edges where componentByScope[edge.parent] == componentByScope[edge.child] && labelsToJudge.contains(edge.declaredProperty.label) {
				componentsByLabelOfEdgeInside[edge.declaredProperty.label, default: []].insert(componentByScope[edge.parent])
			}
			for (label, components) in componentsByLabelOfEdgeInside {
				var isReached = [Bool](repeating: false, count: nodeCount)
				var pending = [Int]()
				for edge in edges where components.contains(componentByScope[edge.child])
					&& componentByScope[edge.parent] == componentByScope[edge.child]
					&& edge.declaredProperty.label != label
					&& !isReached[edge.child]
				{
					isReached[edge.child] = true
					pending.append(edge.child)
				}
				while let reached = pending.popLast() {
					guard !receives[reached].contains(where: { $0.isRequired && $0.property.label == label }) else { return true }
					guard declarationsByLabel[reached][label] == nil else { continue }
					for edgeIndex in outgoingEdges[reached] where !isReached[edges[edgeIndex].child] {
						isReached[edges[edgeIndex].child] = true
						pending.append(edges[edgeIndex].child)
					}
				}
			}
			return false
		}
	}
}
