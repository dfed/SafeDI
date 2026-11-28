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

/// What one node of a world's graph stands for: a scope's record built as one property, erased or not, or as the fill of
/// a hole, or a world's root, built as no property; or a leaf its scope declares, an alias or a hole, which builds no
/// scope. Never a path: every place of one declaration builds the same children, so a world has as many nodes as its
/// types have properties, however many paths reach them. Its position in the world's graph is its declaration ID.
struct TypeFactsDeclaration: Hashable, Sendable {
	/// Whether the declaration builds a scope, or is an alias or a hole its scope declares.
	enum Leaf: UInt8, Hashable, Sendable {
		case none
		case alias
		case hole
	}

	/// Two declarations are equal when they build the same record as the same property, by its exact ID, alike, or are
	/// the same leaf of one record.
	struct Key: Hashable, Sendable {
		/// The record's identity, the declaring record's for a leaf: the declaration keeps the record alive.
		let record: ObjectIdentifier
		/// The raw `PropertyID` of the property built, or -1 for a world's root and a leaf.
		let property: Int32
		let erasedToConcreteExistential: Bool
		/// Whether the declaration is a fill a call passes for a hole, which reads the fields of the case it fills, rather
		/// than a child the record's type instantiates.
		let isFill: Bool
		let leaf: Leaf
		/// A leaf's position among its record's properties to generate, or -1.
		let leafIndex: Int32
	}

	init(scope: ConstructionScope, property: Property?, propertyID: PropertyID?, erasedToConcreteExistential: Bool, isFill: Bool) {
		self.scope = scope
		self.property = property
		self.propertyID = propertyID
		alias = nil
		isOnlyIfAvailableAlias = false
		key = Key(record: ObjectIdentifier(scope.identity), property: propertyID?.raw ?? -1, erasedToConcreteExistential: erasedToConcreteExistential, isFill: isFill, leaf: .none, leafIndex: -1)
	}

	/// A leaf `scope` declares: an alias of `fulfillingProperty`, or a hole where that is `nil`.
	init(leafOf scope: ConstructionScope, property: Property, at index: Int, erasedToConcreteExistential: Bool, aliasOf fulfillingProperty: Property?, onlyIfAvailable: Bool) {
		self.scope = scope
		self.property = property
		propertyID = nil
		alias = fulfillingProperty.map { Alias(property: property, fulfillingProperty: $0) }
		isOnlyIfAvailableAlias = onlyIfAvailable
		key = Key(record: ObjectIdentifier(scope.identity), property: -1, erasedToConcreteExistential: erasedToConcreteExistential, isFill: false, leaf: fulfillingProperty == nil ? .hole : .alias, leafIndex: Int32(index))
	}

	let key: Key
	/// The scope built, or the scope that declares a leaf, which only the graph's build and text read.
	let scope: ConstructionScope
	/// The property built, `nil` for a world's root, which only the graph's build and text read.
	let property: Property?
	/// The run's ID of the property built, `nil` for a world's root and a leaf.
	let propertyID: PropertyID?
	/// For an alias, its own property and the property it is fulfilled by.
	let alias: Alias?
	/// For an alias, the property it is fulfilled by.
	var aliasFulfillingProperty: Property? {
		alias?.fulfillingProperty
	}

	let isOnlyIfAvailableAlias: Bool

	/// An alias leaf's two properties, which every alias has.
	struct Alias {
		let property: Property
		let fulfillingProperty: Property
	}

	static func == (lhs: Self, rhs: Self) -> Bool {
		lhs.key == rhs.key
	}

	func hash(into hasher: inout Hasher) {
		hasher.combine(key)
	}
}

/// How a declaration's type comes to exist, beside its kind (the property's form), which varies apart from it: an
/// `Instantiator<T>` whose `T` a hand-written mock builds is kind `instantiator`, construction `handWrittenMock`. Read
/// from the record: a call of another module's seam or public mock, a fill, or the type's own initializer. In a mock
/// world it is part of the declaration, and the mock writer's column decides `handWrittenMock` and
/// `constructionFunction` per declaration; until it lands no node holds either.
enum TypeFactsConstruction: UInt8, Sendable {
	case initializer
	case handWrittenMock
	case seamCall
	case publicMockCall
	case constructionFunction
	case fill
}

/// One world's graph: a node per declaration its root reaches, each with its edges in the order its scope lists them
/// (the properties it instantiates, aliases and holes, then the fills it passes), and its facts in flat columns indexed
/// by node or by edge: its kind, its edges' facts (`TypeFactsEdge`: the order its scope builds them in, the loops of
/// builders, the function each opens, the bindings before each), its bindings in the order its scope binds them, its
/// cycle identity and twin, the union facts of its subtree, its parents and its fills; and the least sets of reads each
/// subtree takes from above it (`ReadsFromAbove`). A world is one tree to generate: a production root, a seam's own tree,
/// or a mock root.
///
/// Its facts are columns of 32-bit IDs, small enums and bit sets, one set per world: declarations by position; labels,
/// properties, types, modules, declaration locations and reads by dense IDs in the order the build first meets them.
/// `Property`, `TypeDescription` and text are read only while the graph is built and for text: each node keeps its scope
/// and property, and the graph its values' spellings, which only text and a lookup read. Built from the frozen table
/// alone, without unfolding a path. Today it is built only where a test observes it (`TypeFactsReport`), beside the tree
/// each path builds, to be compared with it; nothing generates from it yet. It holds its columns, and a record per node,
/// for as long as its owner keeps it; nothing of it is stored between runs or handed to another module's run.
struct TypeFactsGraph: Sendable {
	/// - Parameters:
	///   - forMockGeneration: Whether the world is a mock root's, whose receives only if available read what the mock root
	///     binds or pins (`ReadChannel.mock`), and whose types are built with their hand-written mocks.
	init(root: ConstructionScope, forMockGeneration: Bool) {
		// Building the graph is an edge: it reads each record's properties and labels once per node, and interns them. The
		// walk asks for a node's edges once, when it first reaches the node, so in node order, and each edge's entry among
		// its scope's properties to generate, or among its fills, is appended in edge order.
		var edgeEntries = [Int32]()
		var edgeIsFill = [Bool]()
		var fillHoles = [(edge: Int32, hole: SeamSignature.Hole)]()
		// Each call that passes fills, with what the memos it hands them read (`FillsOfCall`).
		var fillsOfCalls = [FillsOfCall]()
		// Each call that passes fills, with the fills and dispatchers that decide which are `@Sendable`
		// (`TypeFactsFillSendability`), their keys by dense IDs.
		var sendabilityCalls = [TypeFactsFillSendability.Call]()
		var fillKeys = TypeFactsInterner<String>()
		// The walk asks for a node's edges once, in node order, so this counts the nodes.
		var nodeIndex: Int32 = -1
		let graph = OrderedGraph(root: TypeFactsDeclaration(scope: root, property: nil, propertyID: nil, erasedToConcreteExistential: false, isFill: false)) { declaration in
			nodeIndex += 1
			guard declaration.key.leaf == .none else { return [] }
			var targets = [TypeFactsDeclaration]()
			for (index, propertyToGenerate) in declaration.scope.propertiesToGenerate.enumerated() {
				switch propertyToGenerate {
				case let .instantiated(property, child, erasedToConcreteExistential, propertyID):
					targets.append(TypeFactsDeclaration(scope: child, property: property, propertyID: propertyID, erasedToConcreteExistential: erasedToConcreteExistential, isFill: false))
				case let .aliased(property, fulfillingProperty, erasedToConcreteExistential, onlyIfAvailable, _):
					targets.append(TypeFactsDeclaration(leafOf: declaration.scope, property: property, at: index, erasedToConcreteExistential: erasedToConcreteExistential, aliasOf: fulfillingProperty, onlyIfAvailable: onlyIfAvailable))
				case let .hole(property, erasedToConcreteExistential):
					targets.append(TypeFactsDeclaration(leafOf: declaration.scope, property: property, at: index, erasedToConcreteExistential: erasedToConcreteExistential, aliasOf: nil, onlyIfAvailable: false))
				}
				edgeEntries.append(Int32(index))
				edgeIsFill.append(false)
			}
			var fillEdges = [(edge: Int32, hole: SeamSignature.Hole)]()
			for case let (index, .fill(hole, child, fillContext)) in declaration.scope.holeArguments.enumerated() {
				fillEdges.append((Int32(edgeEntries.count), hole))
				targets.append(TypeFactsDeclaration(scope: child, property: hole.property, propertyID: fillContext.propertyID, erasedToConcreteExistential: hole.erasedToConcreteExistential, isFill: true))
				edgeEntries.append(Int32(index))
				edgeIsFill.append(true)
			}
			if !fillEdges.isEmpty {
				fillHoles += fillEdges
				fillsOfCalls.append(FillsOfCall(scope: declaration.scope, fillEdges: fillEdges))
				sendabilityCalls.append(Self.sendabilityCall(of: declaration.scope, at: nodeIndex, fillEdges: fillEdges, keys: &fillKeys))
			}
			return targets
		}
		let nodes = graph.nodes
		var properties = TypeFactsInterner<Property>()
		var types = TypeFactsInterner<TypeDescription>()
		var labels = TypeFactsInterner<String>()
		var modules = TypeFactsInterner<String>()
		var locations = TypeFactsInterner<Dependency.DeclarationLocation>()

		// Per node: the property it is built as, the type it builds, and its kind.
		let nodeProperties = nodes.map { node in node.property.map { properties.id(of: $0) } ?? -1 }
		let builtTypes = nodes.map { node in
			switch node.key.leaf {
			case .none:
				types.id(of: node.scope.instantiable.concreteInstantiable)
			case .alias, .hole:
				types.id(of: (node.property?.typeDescription ?? node.scope.instantiable.concreteInstantiable).asInstantiatedType)
			}
		}
		let kinds = nodes.map(Self.kind(of:))
		let constructions = nodes.map { Self.construction(of: $0, forMockGeneration: forMockGeneration) }

		// The receives of each node, its declarations, and the properties they compare.
		var ownRequired = [[Int32]]()
		var ownOnlyIfAvailable = [[Int32]]()
		var ownOnlyIfAvailableUnwrapped = [[Int32]]()
		var declared = [[Int32]]()
		var ownEscapingTypes = [[Int32]]()
		ownRequired.reserveCapacity(nodes.count)
		for node in nodes {
			var required = [Int32]()
			var onlyIfAvailable = [Int32]()
			var onlyIfAvailableUnwrapped = [Int32]()
			var declaredByNode = [Int32]()
			var escaping = [Int32]()
			switch node.key.leaf {
			case .alias:
				if let fulfillingProperty = node.aliasFulfillingProperty {
					if node.isOnlyIfAvailableAlias {
						onlyIfAvailable.append(properties.id(of: fulfillingProperty))
						onlyIfAvailableUnwrapped.append(properties.id(of: fulfillingProperty.asUnwrappedProperty))
					} else {
						required.append(properties.id(of: fulfillingProperty))
					}
				}
			case .hole:
				break
			case .none:
				let record = node.scope
				// A world's root is handed its forwarded properties by no scope above it, so they hide nothing its tree receives
				// but the instances of the wrappers among them, which its tree reads from those wrappers.
				var forwarded = Set(record.forwardedLazilyInstantiatedInstanceProperties)
				if node.property != nil {
					for dependency in record.instantiable.dependencies where dependency.source == .forwarded {
						forwarded.insert(dependency.property)
					}
				}
				let declaredProperties = record.propertiesToDeclare.union(forwarded)
				for property in declaredProperties.sorted() {
					declaredByNode.append(properties.id(of: property))
				}
				for dependency in record.instantiable.dependencies {
					switch dependency.source {
					case .instantiated, .forwarded:
						continue
					case let .received(isOnlyIfAvailable):
						if isOnlyIfAvailable {
							onlyIfAvailable.append(properties.id(of: dependency.property))
							onlyIfAvailableUnwrapped.append(properties.id(of: dependency.property.asUnwrappedProperty))
						} else {
							required.append(properties.id(of: dependency.property))
						}
					case let .aliased(fulfillingProperty, _, isOnlyIfAvailable):
						let forms = isOnlyIfAvailable ? fulfillingProperty.formsReadByOnlyIfAvailableReceive : [fulfillingProperty]
						guard !forms.contains(where: declaredProperties.contains) else { continue }
						if isOnlyIfAvailable {
							onlyIfAvailable.append(properties.id(of: fulfillingProperty))
							onlyIfAvailableUnwrapped.append(properties.id(of: fulfillingProperty.asUnwrappedProperty))
						} else {
							required.append(properties.id(of: fulfillingProperty))
						}
					}
				}
				let escapingTypes = Self.ownTypesDeclaredEscaping(of: record)
				for type in escapingTypes {
					escaping.append(types.id(of: type))
				}
			}
			ownRequired.append(required)
			ownOnlyIfAvailable.append(onlyIfAvailable)
			ownOnlyIfAvailableUnwrapped.append(onlyIfAvailableUnwrapped)
			declared.append(declaredByNode)
			ownEscapingTypes.append(escaping)
		}
		// A seam call whose tree requires a pass-through through an alias received only if available requires it too.
		var ownRequiredThroughAlias = nodes.map { node -> [Int32] in
			guard node.key.leaf == .none, let seamCall = node.scope.seamCall else { return [] }
			return seamCall.requiredThroughAliasProperties.sorted().map { properties.id(of: $0) }
		}
		// Every child's property, and the fulfilling property of each alias, compared by the folds.
		let childProperties = nodes.map { node -> (instance: Int32, aliasFulfilling: Int32) in
			let instance = node.property.flatMap { property in
				node.key.leaf == .alias ? property.asLazilyInstantiatedInstancePropertyOfDeclaredBinding : property.asLazilyInstantiatedInstanceProperty
			}.map { properties.id(of: $0) } ?? -1
			let aliasFulfilling = node.isOnlyIfAvailableAlias ? node.aliasFulfillingProperty.map { properties.id(of: $0) } ?? -1 : -1
			return (instance, aliasFulfilling)
		}
		let propertyFactsOfNodes = Self.propertyFacts(of: &properties, labels: &labels, extending: .empty)

		// The masks of what each node provides: a property it declares or forwards, the optional form of one, and, for a
		// receive only if available, each form it reads.
		var propertiesByUnwrapped = [Int32: [Int32]]()
		var propertiesByFormRead = [Int32: [Int32]]()
		for property in 0..<Int32(properties.values.count) {
			propertiesByUnwrapped[propertyFactsOfNodes.unwrapped[Int(property)], default: []].append(property)
			for form in propertyFactsOfNodes.formsRead(by: property) {
				propertiesByFormRead[form, default: []].append(property)
			}
		}
		let propertyCount = properties.values.count
		func provided(by node: Int, _ insert: (Int32) -> Void) {
			for property in declared[node] {
				insert(property)
				propertiesByUnwrapped[property]?.forEach(insert)
			}
		}
		func providesAFormRead(by node: Int, _ insert: (Int32) -> Void) {
			for property in declared[node] {
				propertiesByFormRead[property]?.forEach(insert)
			}
		}
		func followsEdge(_ edge: Int) -> Bool {
			!edgeIsFill[edge]
		}
		let requiredRows = ReadsFromAbove(
			graph: graph,
			own: BitRows(rowCount: nodes.count, columnCount: propertyCount) { node, insert in ownRequired[node].forEach(insert) },
			hidden: BitRows(rowCount: nodes.count, columnCount: propertyCount) { node, insert in provided(by: node, insert) },
			followsEdge: followsEdge,
		).rows
		let onlyIfAvailableRows = ReadsFromAbove(
			graph: graph,
			own: BitRows(rowCount: nodes.count, columnCount: propertyCount) { node, insert in ownOnlyIfAvailable[node].forEach(insert) },
			hidden: BitRows(rowCount: nodes.count, columnCount: propertyCount) { node, insert in
				provided(by: node, insert)
				providesAFormRead(by: node, insert)
			},
			followsEdge: followsEdge,
		).rows
		let onlyIfAvailableUnwrappedIncludingRequired = ReadsFromAbove(
			graph: graph,
			own: BitRows(rowCount: nodes.count, columnCount: propertyCount) { node, insert in ownOnlyIfAvailableUnwrapped[node].forEach(insert) },
			hidden: BitRows(rowCount: nodes.count, columnCount: propertyCount) { node, insert in providesAFormRead(by: node, insert) },
			followsEdge: followsEdge,
		).rows
		let received = BitRows(rowCount: nodes.count, columnCount: propertyCount) { node, insert in
			requiredRows.columns(inRow: node).forEach(insert)
			onlyIfAvailableRows.columns(inRow: node).forEach(insert)
		}
		// What a seam's caller is asked for counts the receives inside the fills its tree's seam calls pass
		// (`ScopeGenerator.requiredReceivedProperties`), so a second fold follows every edge. A world without fills
		// shares the first.
		// Along a fill edge, what the fill binds from the site's scope struct hides the fill's reads of it from the caller:
		// the place's fields, but where some route hands the fill a memo, the memo's (`FillsOfCall.structBindings`).
		let requiredIncludingFillsRows: BitRows
		let fillStructRows: (bound: BitRows, hiddenFromCaller: BitRows)?
		// The memo each fill takes of each label some route hands it one of (`TypeFactsFill.handedMemoStart`).
		var handedMemoByLabelByEdge = [Int32: [String: ScopeGenerator.FillDispatcher.HandedMemo]]()
		if fillHoles.isEmpty {
			requiredIncludingFillsRows = requiredRows
			fillStructRows = nil
		} else {
			var fillStructBindingsByEdge = [Int32: ScopeGenerator.FillStructBindings]()
			let propertyValues = properties.values
			for fillsOfCall in fillsOfCalls {
				let (bindingsByEdge, memoByLabelByEdge) = fillsOfCall.structBindings { edge in
					Set(received.columns(inRow: Int(graph.edgeTargets[Int(edge)])).map { propertyValues[Int($0)] })
				}
				fillStructBindingsByEdge.merge(bindingsByEdge) { bindings, _ in bindings }
				handedMemoByLabelByEdge.merge(memoByLabelByEdge) { memoByLabel, _ in memoByLabel }
			}
			// A property no node reads or declares has no ID, and hides nothing.
			func rows(_ selected: (ScopeGenerator.FillStructBindings) -> Set<Property>) -> BitRows {
				BitRows(rowCount: graph.edgeCount, columnCount: propertyCount) { edge, insert in
					for case let id? in (fillStructBindingsByEdge[Int32(edge)].map(selected) ?? []).map(properties.existingID(of:)) {
						insert(id)
						propertiesByUnwrapped[id]?.forEach(insert)
					}
				}
			}
			let hiddenFromCaller = rows(\.hiddenFromCaller)
			requiredIncludingFillsRows = ReadsFromAbove(
				graph: graph,
				own: BitRows(rowCount: nodes.count, columnCount: propertyCount) { node, insert in ownRequired[node].forEach(insert) },
				hidden: BitRows(rowCount: nodes.count, columnCount: propertyCount) { node, insert in provided(by: node, insert) },
				hiddenAtEdge: hiddenFromCaller,
			).rows
			fillStructRows = (rows(\.bound), hiddenFromCaller)
		}
		let onlyIfAvailableUnwrapped = BitRows(rowCount: nodes.count, columnCount: propertyCount) { node, insert in
			let requiredUnwrapped = Set(requiredRows.columns(inRow: node).map { propertyFactsOfNodes.unwrapped[Int($0)] })
			for property in onlyIfAvailableUnwrappedIncludingRequired.columns(inRow: node) where !requiredUnwrapped.contains(property) {
				insert(property)
			}
		}
		// What a subtree requires through an alias received only if available that a scope in it declares: the alias's
		// fulfilling property, where a child's tree requires the alias, or requires through an alias a property of the
		// alias's label that the alias provides a form of, carried up until a scope declares its label. The second reads
		// what the children require through aliases, so the rows are found again until no alias joins them.
		// The rows' columns are only the properties a requirement through an alias can name: a seam call's own, and each
		// alias's fulfilling property, which is all the fixed point adds. A declaration hides the columns of its label, so
		// what a node hides costs the aliases of the labels it declares, never every property that shares a label.
		var aliasColumnProperties = Set(ownRequiredThroughAlias.joined())
		for childProperty in childProperties where childProperty.aliasFulfilling >= 0 {
			aliasColumnProperties.insert(childProperty.aliasFulfilling)
		}
		let propertyByAliasColumn = aliasColumnProperties.sorted()
		var aliasColumnOfProperty = [Int32](repeating: -1, count: propertyCount)
		var aliasColumnsByLabel = [Int32: [Int32]]()
		for (column, property) in propertyByAliasColumn.enumerated() {
			aliasColumnOfProperty[Int(property)] = Int32(column)
			aliasColumnsByLabel[propertyFactsOfNodes.labels[Int(property)], default: []].append(Int32(column))
		}
		var aliasHiddenColumnCount = 0
		let hiddenByDeclaredLabels = BitRows(rowCount: nodes.count, columnCount: propertyByAliasColumn.count) { node, insert in
			for property in declared[node] {
				for column in aliasColumnsByLabel[propertyFactsOfNodes.labels[Int(property)]] ?? [] {
					aliasHiddenColumnCount += 1
					insert(column)
				}
			}
		}
		self.aliasHiddenColumnCount = aliasHiddenColumnCount
		func requiredAliasFulfillingRows() -> BitRows {
			let rows = ReadsFromAbove(
				graph: graph,
				// A requirement stops at the nearest declaration of its label, the scope's own included.
				own: BitRows(rowCount: nodes.count, columnCount: propertyByAliasColumn.count) { node, insert in
					for column in ownRequiredThroughAlias[node].map({ aliasColumnOfProperty[Int($0)] }) where !hiddenByDeclaredLabels.contains(column, inRow: node) {
						insert(column)
					}
				},
				hidden: hiddenByDeclaredLabels,
				followsEdge: followsEdge,
			).rows
			// Back to property IDs, in increasing order, as every other receive row holds them.
			return BitRows(rowCount: nodes.count, columnCount: propertyCount) { node, insert in
				for column in rows.columns(inRow: node) {
					insert(propertyByAliasColumn[Int(column)])
				}
			}
		}
		// By edge: one alias leaf is shared by every declaration of its scope, each of which requires it on its own.
		var aliasEdgesRequired = Set<Int>()
		var requiredAliasFulfilling = requiredAliasFulfillingRows()
		var aliasJoined = true
		while aliasJoined {
			aliasJoined = false
			for (index, node) in nodes.enumerated() where node.key.leaf == .none {
				let childEdges = graph.edgeIndices(from: index).filter(followsEdge)
				let children = childEdges.map { Int(graph.edgeTargets[$0]) }
				for (aliasEdge, alias) in zip(childEdges, children) where nodes[alias].key.leaf == .alias && childProperties[alias].aliasFulfilling >= 0 && !aliasEdgesRequired.contains(aliasEdge) {
					let aliasProperty = nodeProperties[alias]
					let isRequired = children.contains { child in
						requiredRows.contains(aliasProperty, inRow: child)
							|| requiredAliasFulfilling.columns(inRow: child).contains { property in
								propertyFactsOfNodes.labels[Int(property)] == propertyFactsOfNodes.labels[Int(aliasProperty)] && propertyFactsOfNodes.provides(aliasProperty, aFormReadBy: property)
							}
					}
					if isRequired {
						aliasEdgesRequired.insert(aliasEdge)
						ownRequiredThroughAlias[index].append(childProperties[alias].aliasFulfilling)
						aliasJoined = true
					}
				}
			}
			if aliasJoined {
				requiredAliasFulfilling = requiredAliasFulfillingRows()
			}
		}
		let receives = TypeFactsReceives(received: received, required: requiredRows, requiredIncludingFills: requiredIncludingFillsRows, fillStructRows: fillStructRows, onlyIfAvailableUnwrapped: onlyIfAvailableUnwrapped, requiredAliasFulfilling: requiredAliasFulfilling)

		// The other union facts: the types built beneath, the names declared `@escaping` beneath, and whether a hole is.
		let noneHidden = BitRows(rowCount: nodes.count, columnCount: types.values.count) { _, _ in }
		let typesBeneath = ReadsFromAbove(
			graph: graph,
			own: BitRows(rowCount: nodes.count, columnCount: types.values.count) { node, insert in
				if nodes[node].key.leaf == .none {
					insert(builtTypes[node])
				}
			},
			hidden: noneHidden,
			followsEdge: followsEdge,
		).rows
		let typesDeclaredEscaping = ReadsFromAbove(
			graph: graph,
			own: BitRows(rowCount: nodes.count, columnCount: types.values.count) { node, insert in ownEscapingTypes[node].forEach(insert) },
			hidden: noneHidden,
			followsEdge: followsEdge,
		).rows
		let holesBeneath = ReadsFromAbove(
			graph: graph,
			own: BitRows(rowCount: nodes.count, columnCount: 1) { node, insert in
				if nodes[node].key.leaf == .hole {
					insert(0)
				}
			},
			hidden: BitRows(rowCount: nodes.count, columnCount: 1) { _, _ in },
			followsEdge: followsEdge,
		).rows
		// A hole is a place only in a seam's own tree or a public mock's: in any other world it is a property passed `nil`.
		let rootInstantiable = nodes[0].scope.instantiable
		let holesArePlaces = rootInstantiable.generatesDependencyTree || (forMockGeneration && rootInstantiable.generateMock == .public)
		// Whether a hole is beneath each node along every edge, fills included: a body whose subtree reads a case, its own or
		// through a fill it hands a seam it calls, reads it from the carrier of the function that encloses it.
		let casesBeneath = holesArePlaces && !forMockGeneration ? ReadsFromAbove(
			graph: graph,
			own: BitRows(rowCount: nodes.count, columnCount: 1) { node, insert in
				if nodes[node].key.leaf == .hole {
					insert(0)
				}
			},
			hidden: BitRows(rowCount: nodes.count, columnCount: 1) { _, _ in },
		).rows : BitRows(rowCount: nodes.count, columnCount: 1) { _, _ in }
		// A hole inside a fill is a place too, whose siblings in the fill's tree start before it.
		let worldHoldsHoles = holesArePlaces && nodes.contains { $0.key.leaf == .hole }
		let carrierEdges = worldHoldsHoles ? Self.carrierEdges(of: graph, edgeIsFill: edgeIsFill, builtTypes: builtTypes, nodeProperties: nodeProperties) : []

		// The order each scope builds its children in, and the loops of builders among them.
		var positions = [Int32](repeating: -1, count: graph.edgeCount)
		var loops = [Int32](repeating: -1, count: graph.edgeCount)
		// What each node makes again as a member of a loop of builders, under the first parent that builds it, and whether
		// another parent's loop makes other members of it again (or none). Where two parents make the same members again,
		// the first parent's edges stand for both: a node's key holds the property it is built as, so each parent's edge
		// to a member declares that one property, in one wrapper, and so gives the call one family.
		var madeAgainUnderParent = [[LoopTarget]?](repeating: nil, count: nodes.count)
		var loopParentByMember = [Int32](repeating: -1, count: nodes.count)
		var isSharedApart = [Bool](repeating: false, count: nodes.count)
		var hasLoop = false
		for index in nodes.indices {
			let edges = graph.edgeIndices(from: index)
			let childEdges = edges.filter(followsEdge)
			let children = childEdges.map { edge -> SiblingOrder.Child in
				let target = Int(graph.edgeTargets[edge])
				return SiblingOrder.Child(
					property: nodeProperties[target],
					instance: childProperties[target].instance,
					node: Int32(target),
					isAlias: nodes[target].key.leaf == .alias,
					isErasedAlias: nodes[target].key.leaf == .alias && nodes[target].key.erasedToConcreteExistential,
					onlyIfAvailableAliasFulfilling: childProperties[target].aliasFulfilling,
					isCarrier: carrierEdges.contains(edge),
				)
			}
			let order = SiblingOrder.order(of: children, receives: receives, facts: propertyFactsOfNodes)
			for (position, child) in order.orderedIndices.enumerated() {
				positions[childEdges[child]] = Int32(position)
			}
			// A loop is named by its first member's position, which a member ordered before it does not know yet.
			for (child, edge) in childEdges.enumerated() where order.loopByChild[child] >= 0 {
				loops[edge] = positions[childEdges[order.loopByChild[child]]]
			}
			// Each member a child rebinds is a call of that member's node, sorted by property as the rebindings are. A rename
			// has no body and is no node a call reaches: a loop with one is refused where it is written.
			for (child, edge) in childEdges.enumerated() {
				let member = Int(graph.edgeTargets[edge])
				var targets = [(property: Property, target: LoopTarget)]()
				if nodes[member].key.leaf == .none {
					for rebound in order.reboundByChild[child] {
						let reboundEdge = childEdges[rebound]
						let target = Int(graph.edgeTargets[reboundEdge])
						guard nodes[target].key.leaf == .none, let property = nodes[target].property else { continue }
						targets.append((property, LoopTarget(node: Int32(target), label: labels.id(of: property.label), parentEdge: Int32(reboundEdge))))
					}
				}
				// In the order the member's body first receives each, as `ScopeGenerator.reboundProperties` rebinds them.
				let positions = targets.isEmpty ? [:] : Self.firstReceivePositions(of: Set(targets.map(\.property.label)), beneath: member, in: graph)
				let sortedTargets = targets.sorted {
					(positions[$0.property.label] ?? Int.max, $0.property) < (positions[$1.property.label] ?? Int.max, $1.property)
				}.map(\.target)
				hasLoop = hasLoop || !sortedTargets.isEmpty
				if let earlier = madeAgainUnderParent[member] {
					if earlier.map(\.node) != sortedTargets.map(\.node) {
						isSharedApart[member] = true
					}
				} else {
					madeAgainUnderParent[member] = sortedTargets
					if !sortedTargets.isEmpty {
						loopParentByMember[member] = Int32(index)
					}
				}
			}
			// A child that lists a property a sibling before it lists is never built: it follows the children built.
			var unbuiltPosition = Int32(order.orderedIndices.count)
			for edge in childEdges where positions[edge] < 0 {
				positions[edge] = unbuiltPosition
				unbuiltPosition += 1
			}
			var fillPosition = Int32(childEdges.count)
			for edge in edges where !followsEdge(edge) {
				positions[edge] = fillPosition
				fillPosition += 1
			}
		}

		// The bindings of each node, in the order its scope binds them: the forwarded properties, the dependencies a mock is
		// passed, then each child as it is built. A seam's own parameters are read from above its root, as its caller
		// hands them, and are no binding yet.
		var bindings = [TypeFactsWorldBinding]()
		var bindingOffsets = [Int32]()
		bindingOffsets.reserveCapacity(nodes.count + 1)
		var bindingsBefore = [Int32](repeating: 0, count: graph.edgeCount)
		for (index, node) in nodes.enumerated() {
			bindingOffsets.append(Int32(bindings.count))
			guard node.key.leaf == .none else { continue }
			let instantiable = node.scope.instantiable
			let declaringType = builtTypes[index]
			let module = instantiable.moduleName.map { modules.id(of: $0) } ?? -1
			var dependencyByLabel = [String: Dependency]()
			for dependency in instantiable.dependencies where dependencyByLabel[dependency.property.label] == nil {
				dependencyByLabel[dependency.property.label] = dependency
			}
			func append(_ property: Property, isSeamParameter: Bool = false, isForwarded: Bool = false, isReceivedOnlyIfAvailable: Bool = false, isRebound: Bool = false) {
				let location = dependencyByLabel[property.label]?.declarationLocation.map { locations.id(of: $0) } ?? -1
				bindings.append(TypeFactsWorldBinding(
					label: labels.id(of: property.label),
					property: properties.id(of: property),
					declaringType: declaringType,
					declarationLocation: location,
					parameterTakingType: -1,
					declaringModule: module,
					isReceivedOnlyIfAvailable: isReceivedOnlyIfAvailable,
					isSeamParameter: isSeamParameter,
					isCycleParameter: false,
					isReboundByBuilderFunction: isRebound,
					isForwarded: isForwarded,
				))
			}
			for dependency in instantiable.dependencies where dependency.source == .forwarded {
				append(dependency.property, isForwarded: true)
			}
			for dependency in node.scope.instantiatedDependenciesNotGenerated {
				append(dependency.property)
			}
			let edges = graph.edgeIndices(from: index)
			var childEdgesByPosition = [Int](repeating: 0, count: edges.count(where: followsEdge))
			for edge in edges where followsEdge(edge) {
				childEdgesByPosition[Int(positions[edge])] = edge
			}
			for edge in childEdgesByPosition {
				bindingsBefore[edge] = Int32(bindings.count) - bindingOffsets[index]
				let target = Int(graph.edgeTargets[edge])
				if let property = nodes[target].property {
					append(property, isReceivedOnlyIfAvailable: nodes[target].isOnlyIfAvailableAlias, isRebound: loops[edge] >= 0)
				}
			}
			for edge in edges where !followsEdge(edge) {
				bindingsBefore[edge] = Int32(bindings.count) - bindingOffsets[index]
			}
		}
		bindingOffsets.append(Int32(bindings.count))

		// Each node's cycle identity: the property as cycle validation sees it, by the run's ID, and the concrete type
		// built, in first-reach order. A leaf builds no scope and closes no cycle, so its identity is its own.
		var cycleIdentities = TypeFactsInterner<CycleIdentity>()
		let cycleIDs = nodes.enumerated().map { index, node -> Int32 in
			guard node.key.leaf == .none else {
				return cycleIdentities.id(of: CycleIdentity(property: -2 - Int32(index), concreteType: -1))
			}
			let property = node.propertyID.map { node.scope.interner.asValidatedForDependencyCycles($0).raw } ?? -1
			return cycleIdentities.id(of: CycleIdentity(property: property, concreteType: node.scope.concreteTypeID.raw))
		}
		// Twins: the first other node of a node's cycle identity, a constant and a lazy wrapper of one label and type.
		var firstNodeByIdentity = [Int32](repeating: -1, count: cycleIdentities.values.count)
		var secondNodeByIdentity = [Int32](repeating: -1, count: cycleIdentities.values.count)
		for (index, identity) in cycleIDs.enumerated() {
			if firstNodeByIdentity[Int(identity)] < 0 {
				firstNodeByIdentity[Int(identity)] = Int32(index)
			} else if secondNodeByIdentity[Int(identity)] < 0 {
				secondNodeByIdentity[Int(identity)] = Int32(index)
			}
		}
		let twins = cycleIDs.enumerated().map { index, identity -> Int32 in
			let first = firstNodeByIdentity[Int(identity)]
			return first == Int32(index) ? secondNodeByIdentity[Int(identity)] : first
		}

		// The edges' facts.
		var edgeFacts = [TypeFactsEdge]()
		edgeFacts.reserveCapacity(graph.edgeCount)
		var fillHoleByEdge = [Int32: SeamSignature.Hole]()
		for (edge, hole) in fillHoles {
			fillHoleByEdge[edge] = hole
		}
		for index in nodes.indices {
			for edge in graph.edgeIndices(from: index) {
				let target = graph.edgeTargets[edge]
				// A fill opens what its fulfiller's wrapper opens, or, where the place is built in another `@Sendable` function,
				// that function.
				let targetOpens = Self.opens(nodes[Int(target)])
				let opens = fillHoleByEdge[Int32(edge)].map { $0.isSendable && targetOpens != .sendableInstantiatorBuilder && targetOpens != .sendableLazyWrapper ? TypeFactsFunctionOpened.otherSendableFunction : targetOpens } ?? targetOpens
				edgeFacts.append(TypeFactsEdge(
					child: target,
					buildPosition: positions[edge],
					loop: loops[edge],
					opens: opens,
					isFill: edgeIsFill[edge],
					bindingsBefore: bindingsBefore[edge],
					isCallEdge: graph.componentByNode[Int(target)] == graph.componentByNode[index] && graph.isOnCycle(index),
				))
			}
		}

		// The parents of each node, in the order the walk meets each edge, each with the bindings before its edge.
		var parentCounts = [Int32](repeating: 0, count: nodes.count + 1)
		for edge in 0..<graph.edgeCount {
			parentCounts[Int(graph.edgeTargets[edge]) + 1] += 1
		}
		for index in nodes.indices {
			parentCounts[index + 1] += parentCounts[index]
		}
		let parentOffsets = parentCounts
		var parentSlots = parentCounts
		var parents = [TypeFactsParent](repeating: TypeFactsParent(parent: -1, segmentStart: 0, segmentCount: 0), count: graph.edgeCount)
		for index in nodes.indices {
			for edge in graph.edgeIndices(from: index) {
				let target = Int(graph.edgeTargets[edge])
				parents[Int(parentSlots[target])] = TypeFactsParent(parent: Int32(index), segmentStart: bindingOffsets[index], segmentCount: bindingsBefore[edge])
				parentSlots[target] += 1
			}
		}

		// The fills each call passes, with their fill paths and whether each builds in a `@Sendable` function.
		let fillBuildsInSendableFunction = TypeFactsFillSendability.buildsInSendableFunction(
			in: graph,
			edgeIsFill: edgeIsFill,
			opensSendableFunction: nodes.map { node in
				switch Self.opens(node) {
				case .sendableInstantiatorBuilder, .sendableLazyWrapper:
					true
				case .none, .instantiatorBuilder, .otherSendableFunction:
					false
				}
			},
			calls: sendabilityCalls,
			keyCount: fillKeys.values.count,
		)
		var fills = [TypeFactsFill]()
		var fillPathEntries = [TypeFactsFillPathEntry]()
		var fillHandedMemos = [TypeFactsHandedMemo]()
		for (edge, hole) in fillHoles {
			let source = Self.source(ofEdge: Int(edge), in: graph)
			let stackStart = Int32(fillPathEntries.count)
			for (property, concreteType) in zip(hole.fillPropertyStack, hole.fillConcreteTypeStack) {
				fillPathEntries.append(TypeFactsFillPathEntry(property: properties.id(of: property), concreteType: types.id(of: concreteType)))
			}
			// By label, so no dictionary's order reaches the column.
			let handedMemoStart = Int32(fillHandedMemos.count)
			for (label, memo) in (handedMemoByLabelByEdge[edge] ?? [:]).sorted(by: { $0.key < $1.key }) {
				fillHandedMemos.append(TypeFactsHandedMemo(label: labels.id(of: label), property: properties.id(of: memo.property), deferral: memo.deferral))
			}
			fills.append(TypeFactsFill(
				edge: edge,
				calledType: builtTypes[source],
				isPublicMock: nodes[source].scope.publicMockCall != nil,
				holeIndex: edgeEntries[Int(edge)],
				filledHoleOwnerType: types.id(of: hole.ownerType),
				stackStart: stackStart,
				stackCount: Int32(fillPathEntries.count) - stackStart,
				holeIsSendable: hole.isSendable,
				buildsInSendableFunction: fillBuildsInSendableFunction[Int(edge)],
				key: fillKeys.id(of: ScopeGenerator.fillKey(of: hole)),
				handedMemoStart: handedMemoStart,
				handedMemoCount: Int32(fillHandedMemos.count) - handedMemoStart,
			))
		}

		// The bindings and fills intern properties no node holds, whose facts an answer's provided forms read.
		let propertyFacts = Self.propertyFacts(of: &properties, labels: &labels, extending: propertyFactsOfNodes)

		// The reads each node makes itself, and those it hides: each read of a label it binds.
		var readInterner = TypeFactsInterner<Read>()
		// The forms each node's own receives only if available declare, by label and kind, as columns of their own.
		var formInterner = TypeFactsInterner<OnlyIfAvailableForm>()
		var ownFormsByNode = [[Int32]]()
		let ownReadsByNode = nodes.map { node in
			var ownForms = [OnlyIfAvailableForm]()
			let reads = Self.ownReads(of: node, forMockGeneration: forMockGeneration, labels: &labels, formsReadOnlyIfAvailable: &ownForms).map { readInterner.id(of: $0) }
			ownFormsByNode.append(ownForms.map { formInterner.id(of: $0) })
			return reads
		}
		let own = BitRows(rowCount: nodes.count, columnCount: readInterner.values.count) { index, insert in
			ownReadsByNode[index].forEach(insert)
		}
		var readsByLabel = [[Int32]](repeating: [], count: labels.values.count)
		for (id, read) in readInterner.values.enumerated() where read.channel.asksAboutLabel {
			readsByLabel[Int(read.label)].append(Int32(id))
		}
		let hidden = BitRows(rowCount: nodes.count, columnCount: readInterner.values.count) { index, insert in
			for binding in bindings[Int(bindingOffsets[index])..<Int(bindingOffsets[index + 1])] {
				readsByLabel[Int(binding.label)].forEach(insert)
			}
		}
		// A node shared apart makes nothing again, and a stage that writes from nodes refuses its world.
		var madeAgainByNode = [[LoopTarget]]()
		var membersSharedApart = [Int32]()
		if hasLoop {
			for node in nodes.indices {
				if isSharedApart[node] {
					membersSharedApart.append(Int32(node))
					madeAgainByNode.append([])
					loopParentByMember[node] = -1
				} else {
					madeAgainByNode.append(madeAgainUnderParent[node] ?? [])
				}
			}
		}
		loopMembersSharedApart = membersSharedApart
		let madeAgain: MadeAgainEdges?
		let readsOwn: BitRows
		let readsHidden: BitRows
		if hasLoop {
			// A member binds each label it rebinds at the top of its body, before every other statement, so it hides them
			// from the nodes above it, and its made-again calls are edges of the closure.
			func reboundReads(of index: Int, _ insert: (Int32) -> Void) {
				for target in madeAgainByNode[index] {
					readsByLabel[Int(target.label)].forEach(insert)
				}
			}
			readsHidden = BitRows(rowCount: nodes.count, columnCount: readInterner.values.count) { index, insert in
				hidden.columns(inRow: index).forEach(insert)
				reboundReads(of: index, insert)
			}
			// The rebinding shadows the label for the member's own type too: its receive of a member it makes again reads the
			// rebinding, never what is above. Only the read of the label it is built as, `value` of its own label, still
			// reaches above, where its parent's declaration is being built.
			readsOwn = BitRows(rowCount: nodes.count, columnCount: readInterner.values.count) { index, insert in
				let shadowed = Set(madeAgainByNode[index].lazy.filter { $0.node != Int32(index) }.flatMap { readsByLabel[Int($0.label)] })
				for read in own.columns(inRow: index) where !shadowed.contains(read) {
					insert(read)
				}
			}
			madeAgain = MadeAgainEdges(
				graph: graph,
				targetsByNode: madeAgainByNode.map { $0.map(\.node) },
				labelsByNode: madeAgainByNode.map { $0.map(\.label) },
				parentEdgesByNode: madeAgainByNode.map { $0.map(\.parentEdge) },
				rebound: BitRows(rowCount: nodes.count, columnCount: readInterner.values.count, columnsOfRow: reboundReads),
			)
		} else {
			madeAgain = nil
			readsOwn = own
			readsHidden = hidden
		}
		self.madeAgain = madeAgain

		self.graph = graph
		self.forMockGeneration = forMockGeneration
		self.holesArePlaces = holesArePlaces
		self.constructions = constructions
		self.kinds = kinds
		self.nodeProperties = nodeProperties
		self.builtTypes = builtTypes
		self.edgeFacts = edgeFacts
		self.bindings = bindings
		self.bindingOffsets = bindingOffsets
		self.twins = twins
		self.receives = receives
		self.typesBeneath = typesBeneath
		self.typesDeclaredEscaping = typesDeclaredEscaping
		self.holesBeneath = holesBeneath
		self.casesBeneath = casesBeneath
		self.parentOffsets = parentOffsets
		self.parents = parents
		self.fills = fills
		self.fillPathEntries = fillPathEntries
		self.fillHandedMemos = fillHandedMemos
		self.propertyFacts = propertyFacts
		owedFactsByNode = Self.owedFacts(of: graph, forMockGeneration: forMockGeneration)
		propertyTable = properties.values
		typeTable = types.values
		moduleNames = modules.values
		declarationLocations = locations.values
		let reads = ReadsFromAbove(graph: graph, own: readsOwn, hidden: readsHidden, madeAgain: madeAgain)
		self.reads = reads
		// The forms of each label each node's subtree reads only if available from above it, the reads its variants'
		// parameters serve, folded as the reads are.
		var formsByLabel = [[Int32]](repeating: [], count: labels.values.count)
		for (id, form) in formInterner.values.enumerated() {
			formsByLabel[Int(form.label)].append(Int32(id))
		}
		let formsReadFromAbove = ReadsFromAbove(
			graph: graph,
			own: BitRows(rowCount: nodes.count, columnCount: formInterner.values.count) { index, insert in
				ownFormsByNode[index].forEach(insert)
			},
			hidden: BitRows(rowCount: nodes.count, columnCount: formInterner.values.count) { index, insert in
				for binding in bindings[Int(bindingOffsets[index])..<Int(bindingOffsets[index + 1])] {
					formsByLabel[Int(binding.label)].forEach(insert)
				}
			},
		)
		readTable = readInterner.values
		labelTexts = labels.values
		fillKeyTexts = fillKeys.values
		var readColumn = [Int32]()
		var readOffsets = [Int32]()
		var labelColumn = [Int32]()
		var labelOffsets = [Int32]()
		var labelSeen = [Int32](repeating: -1, count: labels.values.count)
		for index in graph.nodes.indices {
			readOffsets.append(Int32(readColumn.count))
			labelOffsets.append(Int32(labelColumn.count))
			reads.rows.forEachColumn(inRow: index) { read, _ in
				readColumn.append(read)
				let label = readInterner.values[Int(read)].label
				if label >= 0, labelSeen[Int(label)] != Int32(index) {
					labelSeen[Int(label)] = Int32(index)
					labelColumn.append(label)
				}
			}
		}
		readOffsets.append(Int32(readColumn.count))
		labelOffsets.append(Int32(labelColumn.count))
		self.readColumn = readColumn
		self.readOffsets = readOffsets
		self.labelColumn = labelColumn
		self.labelOffsets = labelOffsets
		let edgeOpens = edgeFacts.map(\.opens)
		let answers = Self.answers(
			of: graph,
			reads: reads,
			readTable: readInterner.values,
			labels: labels,
			bindings: bindings,
			bindingOffsets: bindingOffsets,
			bindingsBefore: bindingsBefore,
			properties: properties,
			forms: (table: formInterner.values, readFromAbove: formsReadFromAbove),
			// Production bodies have one variant, `@Sendable` a mark folded over call edges (`TypeFactsOutcomes`), so the
			// root's `.plain` reaches every node. A mock's body reads its overrides from a local bound before the `@Sendable`
			// function that encloses it, and its parent's configuration where none does, so a mock keys by its family. In a
			// seam's own tree, a body holding a hole reads its cases from the `@Sendable` carrier inside a `@Sendable`
			// function and from the plain one outside, so it keys by its family too, as does a body that hands such a body to a
			// seam it calls as a fill; a body holding none stays one variant.
			family: Self.familyOfCall(
				forMockGeneration: forMockGeneration,
				holesArePlaces: holesArePlaces,
				casesBeneath: casesBeneath,
				edgeTargets: graph.edgeTargets,
				edgeOpens: edgeOpens,
			),
			madeAgain: madeAgain.map { ($0, madeAgainByNode, loopParentByMember) },
		)
		answerIsBeingBuilt = answers.isBeingBuilt
		answerIsMadeAgain = answers.isMadeAgain
		answerTexts = answers.texts
		answerKeys = answers.keys
		answerProperties = answers.properties
		variants = answers.variants
		let oneFunctionGroups = Self.twinGroups(of: answers.variants, cycleIDs: cycleIDs, twins: twins, isOnCycle: graph.isOnCycle, readColumn: readColumn, readOffsets: readOffsets)
		self.oneFunctionGroups = oneFunctionGroups
		variantBuildsInSendableFunction = Self.sendableMarks(of: answers.variants, graph: graph, edgeOpens: edgeOpens, oneFunctionGroups: oneFunctionGroups)
		let isBeingBuilt = answers.isBeingBuilt
		let variantsOfAnswers = answers.variants
		let readsByID = readInterner.values
		outcomes = TypeFactsOutcomes(.init(
			variants: answers.variants,
			cellRule: { variant, position in
				let node = Int(variantsOfAnswers.node(of: variant))
				return .init(channel: readsByID[Int(readColumn[Int(readOffsets[node]) + position])].channel)
			},
			isBeingBuilt: { isBeingBuilt[Int($0)] },
			// No call builds its callee in its caller's body until the edge facts say which edges open no function and the
			// layout gives the callee none: false costs only a parameter, where true could capture a function's local.
			buildsInCallersBody: { _, _ in false },
			edgeOffset: { graph.edgeOffset(of: $0) },
		))
		self.cycleIDs = cycleIDs
	}

	/// Each node's cycle identity, dense in first-reach order: the property as cycle validation sees it and the
	/// concrete type built, by the run's IDs, so two nodes of one identity close cycles on each other. A leaf's is its own.
	let cycleIDs: [CycleID]

	/// How many columns the declarations hide from the rows of what is required through an alias, over every node: a
	/// declaration hides the aliases of its label, so this grows with declarations and aliases, never with the properties
	/// that share a label. Only tests read it, to count how the rows' cost grows: the rows are built and dropped inside
	/// `init`, so the count a test needs exists only there, and a stored `Int` on the graph a generation already hands
	/// tests costs less than a hook threaded through `GenerationWork` for one number.
	let aliasHiddenColumnCount: Int

	/// Each node's reads from above, in increasing read ID, one run per node at `readOffsets`: what `reads(of:)` slices.
	let readColumn: [Int32]
	let readOffsets: [Int32]

	/// Each node's labels read from above, each once, in read order, one run per node at `labelOffsets`.
	let labelColumn: [Int32]
	let labelOffsets: [Int32]

	/// Each answer ID's key: the answer without what a parameter carries.
	let answerKeys: [Int32]

	/// Each answer ID's declaration, by the world's property ID: what `providesFormRead(by:_:beneath:)` compares.
	let answerProperties: [Int32]

	/// The variants of the world's bodies, answered by what each node binds at its edges (`answers(of:reads:…)`).
	let variants: TypeFactsVariants

	/// The variants one function serves, twins' bodies of one key (`twinGroups(of:cycleIDs:twins:isOnCycle:readColumn:readOffsets:)`).
	let oneFunctionGroups: [[Int]]

	/// Per variant, whether a call builds its body inside a `@Sendable` function (`sendableMarks(of:graph:edgeOpens:oneFunctionGroups:)`).
	let variantBuildsInSendableFunction: [Bool]

	/// What each read of each variant comes to in its body.
	let outcomes: TypeFactsOutcomes

	/// Whether each answer ID's declaration is still being built where it answers.
	let answerIsBeingBuilt: [Bool]

	/// Whether each answer ID is a member of a loop of builders that the node answering makes again at its top.
	let answerIsMadeAgain: [Bool]

	/// The world's made-again calls, `nil` where it has no loop of builders.
	let madeAgain: MadeAgainEdges?

	/// The members of loops of builders whose parents' loops make different members again, in node order: they make
	/// nothing again, and a stage that writes from nodes refuses the world.
	let loopMembersSharedApart: [Int32]

	/// The position at which the body of `member`'s builder function first receives each of `labels`: its own type's
	/// receives, then its tree's, depth first in edge order, each node once, as `ScopeGenerator.reboundProperties` walks
	/// the scope's generators. A rename or a hole is met among the receives of the type that declares it.
	private static func firstReceivePositions(of labels: Set<String>, beneath member: Int, in graph: OrderedGraph<TypeFactsDeclaration>) -> [String: Int] {
		var positions = [String: Int]()
		var visited = Set<Int>()
		var stack = [member]
		while positions.count < labels.count, let node = stack.popLast() {
			guard visited.insert(node).inserted else { continue }
			if graph.nodes[node].key.leaf == .none {
				for (property, _) in ScopeGenerator.receivesFromAbove(ofOwnDependencies: graph.nodes[node].scope.instantiable.dependencies)
					where labels.contains(property.label) && positions[property.label] == nil
				{
					positions[property.label] = positions.count
				}
			}
			stack.append(contentsOf: graph.edges(from: node).reversed().map(Int.init))
		}
		return positions
	}

	/// A member of a loop of builders a node makes again: its node, its label, and the parent's edge that builds it.
	private struct LoopTarget {
		let node: Int32
		let label: Int32
		let parentEdge: Int32
	}

	/// Each answer ID's text, which only a report reads.
	let answerTexts: [String]

	/// The key that keeps a parameter's difference out of the variant: rule 1, a read only if available, whose `nil` or
	/// value is an optional parameter, keys alike whatever it is answered; rule 2, whether a wrapper is still being built,
	/// which is passed and made again at the call, keys as the wrapper alone.
	static let optionalParameterKey: Int32 = -2

	/// Rule 1's keys where the answer is a lazy wrapper, one per kind: a receive of the value only if available that a
	/// wrapper answers reads its instance where the value is read, so the parameter is the wrapper, never the value
	/// (which, made at the call, would move when the value is built). A declaration and one being built key alike within
	/// each; `nil` keys as `optionalParameterKey`, apart from both lazy keys, until rule 3 says whether a `nil` wrapper
	/// parameter may stand for it.
	static let optionalLazilyInstantiatedParameterKey: Int32 = -3
	static let optionalSendableLazilyInstantiatedParameterKey: Int32 = -4

	/// The key rule 1 gives an answer declared with `kind`.
	/// The fills and dispatchers of a call that decide which of its fills are `@Sendable` (`TypeFactsFillSendability.Call`):
	/// each fill edge's place, and the dispatchers the tree declares for the call where no enclosing call declares one of
	/// their enums (`ScopeGenerator.FillDispatcher.dispatchers(of:filledSites:enclosingDispatchers:fillNames:names:innerScopeNameByKey:carriedInnerScopesByKey:enclosingCarriedInnerScopes:decidesPerRoute:)`),
	/// as `FillsOfCall` declares them: their names, which decide nothing here, from an allocator of their own.
	private static func sendabilityCall(of scope: ConstructionScope, at node: Int32, fillEdges: [(edge: Int32, hole: SeamSignature.Hole)], keys: inout TypeFactsInterner<String>) -> TypeFactsFillSendability.Call {
		let fills = fillEdges.map { edge, hole in
			TypeFactsFillSendability.Fill(edge: edge, key: keys.id(of: ScopeGenerator.fillKey(of: hole)), holeIsSendable: hole.isSendable)
		}
		var dispatchers = [TypeFactsFillSendability.Dispatcher]()
		if let calledBuilders = scope.calledBuilders {
			var names = GeneratedNameAllocator(reserving: [])
			for dispatcher in ScopeGenerator.FillDispatcher.dispatchers(
				of: calledBuilders,
				filledSites: Set(fillEdges.map(\.hole.site)),
				enclosingDispatchers: [:],
				fillNames: [:],
				names: &names,
				decidesPerRoute: scope.publicMockCall != nil,
			) {
				dispatchers.append(TypeFactsFillSendability.Dispatcher(
					key: keys.id(of: dispatcher.key),
					isSendableFamily: dispatcher.isSendableFamily,
					targets: dispatcher.cases.compactMap { $0.target.map { keys.id(of: $0.key) } },
				))
			}
		}
		return TypeFactsFillSendability.Call(node: node, fills: fills, dispatchers: dispatchers)
	}

	static func optionalParameterKey(of kind: Property.PropertyType?) -> Int32 {
		switch kind {
		case .lazilyInstantiated:
			optionalLazilyInstantiatedParameterKey
		case .sendableLazilyInstantiated:
			optionalSendableLazilyInstantiatedParameterKey
		case nil, .constant, .instantiator, .sendableInstantiator, .erasedInstantiator, .sendableErasedInstantiator:
			optionalParameterKey
		}
	}

	/// A form a receive only if available reads its label in: the label, and the kind of the receive's unwrapped type.
	struct OnlyIfAvailableForm: Hashable, Sendable {
		init(label: Int32, kind: Property.PropertyType) {
			self.label = label
			self.kind = Self.position(of: kind)
		}

		let label: Int32
		/// The kind's position among `Property.PropertyType.allCases`, which is not `Sendable`.
		let kind: Int

		static func position(of kind: Property.PropertyType) -> Int {
			Property.PropertyType.allCases.firstIndex(of: kind) ?? -1
		}
	}

	/// Whether a declaration of this kind is a twin of a cycle identity: a value or a lazy wrapper of its label.
	private static func isTwin(_ kind: Property.PropertyType) -> Bool {
		switch kind {
		case .constant, .lazilyInstantiated, .sendableLazilyInstantiated:
			true
		case .instantiator, .sendableInstantiator, .erasedInstantiator, .sendableErasedInstantiator:
			false
		}
	}

	/// What answers each read at each edge, by value: a node answers a read of a label with the forms of the last of its
	/// bindings of that label bound before the edge (`bindingsBefore`), and the edge's child answers its own label as
	/// the property it is built as, being built. Interned at the edge, where the graph is built from the table; the
	/// worklist sees IDs only.
	///
	/// A member of a loop of builders binds each member it makes again at the top of its body, before every edge and at
	/// each made-again call, with the forms its parent declares that member with, made again: an answer that keys as the
	/// wrapper alone, as one being built does (rule 2), so a member made again keys as its parent's call of it does.
	private static func answers(
		of graph: OrderedGraph<TypeFactsDeclaration>,
		reads: ReadsFromAbove,
		readTable: [Read],
		labels: TypeFactsInterner<String>,
		bindings: [TypeFactsWorldBinding],
		bindingOffsets: [Int32],
		bindingsBefore: [Int32],
		properties: TypeFactsInterner<Property>,
		forms: (table: [OnlyIfAvailableForm], readFromAbove: ReadsFromAbove),
		family: (_ edge: Int, _ callerFamily: VariantFamily) -> VariantFamily,
		madeAgain: (edges: MadeAgainEdges, targetsByNode: [[LoopTarget]], parentByMember: [Int32])?,
	) -> (variants: TypeFactsVariants, isBeingBuilt: [Bool], isMadeAgain: [Bool], texts: [String], keys: [Int32], properties: [Int32]) {
		var answerIDByText = [String: Int32]()
		var texts = [String]()
		var isBeingBuilt = [Bool]()
		var isMadeAgain = [Bool]()
		var keys = [Int32]()
		var kinds = [Property.PropertyType]()
		var answerProperties = [Int32]()
		// Whether a wrapper answering a read only if available is in the one form the callee's subtree reads the label in.
		var isInReadForm = [Bool]()
		func answer(text: String, beingBuilt: Bool, madeAgain: Bool = false, keyText: String, kind: Property.PropertyType, property: Int32, inReadForm: Bool = false) -> Int32 {
			let keyID: Int32
			if let existing = answerIDByText[keyText] {
				keyID = existing
			} else {
				keyID = Int32(texts.count)
				answerIDByText[keyText] = keyID
				texts.append(keyText)
				// A constant's key text is its full text, so this entry is the answer itself where the texts are equal.
				isBeingBuilt.append(text == keyText && beingBuilt)
				isMadeAgain.append(text == keyText && madeAgain)
				kinds.append(kind)
				isInReadForm.append(inReadForm)
				keys.append(keyID)
				answerProperties.append(property)
			}
			guard text != keyText else {
				return keyID
			}
			if let existing = answerIDByText[text] {
				return existing
			}
			let id = Int32(texts.count)
			answerIDByText[text] = id
			texts.append(text)
			isBeingBuilt.append(beingBuilt)
			isMadeAgain.append(madeAgain)
			kinds.append(kind)
			isInReadForm.append(inReadForm)
			keys.append(keyID)
			answerProperties.append(property)
			return id
		}
		var sourceByEdge = [Int32]()
		// Each node's declarations by label, as its scope spells them, with the forms each provides: the world's property IDs
		// compare two spellings of one type alike, and a body is typed as its parent spells it.
		var declarationsByLabelByNode = [[Int32: [(property: Property, forms: String)]]]()
		for index in graph.nodes.indices {
			for _ in graph.edges(from: index) {
				sourceByEdge.append(Int32(index))
			}
			var declarations = [Int32: [(property: Property, forms: String)]]()
			for (property, forms) in graph.nodes[index].scope.sortedDeclaredPropertyForms {
				guard let label = labels.existingID(of: property.label) else { continue }
				declarations[label, default: []].append((property, forms.sorted().map(\.asSource).joined(separator: ", ")))
			}
			declarationsByLabelByNode.append(declarations)
		}
		var edgeTargets = [Int32]()
		for index in graph.nodes.indices {
			edgeTargets.append(contentsOf: graph.edges(from: index))
		}
		// Each member's rebound labels, with the property and forms its parent declares the member's own property with: a
		// mock's root can declare one label in two forms, and the member rebinds the one it is built as.
		var reboundByLabelByNode = [[Int32: (property: Int32, forms: String, kind: Property.PropertyType)]](repeating: [:], count: madeAgain == nil ? 0 : graph.nodes.count)
		if let madeAgain {
			for (index, targets) in madeAgain.targetsByNode.enumerated() where !targets.isEmpty {
				let parentForms = graph.nodes[Int(madeAgain.parentByMember[index])].scope.sortedDeclaredPropertyForms
				for target in targets {
					let property = graph.nodes[Int(target.node)].property
					if let declared = parentForms.first(where: { $0.property == property }), let propertyID = properties.existingID(of: declared.property) {
						reboundByLabelByNode[index][target.label] = (propertyID, declared.forms.sorted().map(\.asSource).joined(separator: ", "), declared.property.propertyType)
					}
				}
			}
		}
		/// The answer `node` binds at its top for a read of a label it rebinds, or `nil` for any other read. A member is a
		/// builder, so the answer keys as the wrapper alone (rule 2).
		func madeAgainAnswer(at node: Int, for read: Read) -> VariantBinding? {
			guard read.channel.asksAboutLabel, !reboundByLabelByNode.isEmpty, let declaration = reboundByLabelByNode[node][read.label] else {
				return nil
			}
			let keyText = "\(read.channel.name) \(declaration.forms)"
			return VariantBinding(answer: answer(text: "\(keyText) made again", beingBuilt: false, madeAgain: true, keyText: keyText, kind: declaration.kind, property: declaration.property), declaration: Int32(node))
		}
		func binding(at edge: Int, of readID: Int32) -> VariantBinding? {
			// Every read the graph interns asks about a label: `ownReads` makes only value, optional and mock reads.
			let read = readTable[Int(readID)]
			let node = Int(sourceByEdge[edge])
			let child = graph.nodes[Int(edgeTargets[edge])]
			// A child answers its own label's read as the declaration being built, by the property it is built as; any
			// other label by the last of its parent's bindings bound before the edge, so a declaration bound after the
			// call does not answer it, and else by the member the node rebinds at its top under the label.
			// Every binding, and every child's property, is a declaration of its node's scope, which the lookup finds by its
			// spelling.
			let bound: Property?
			let beingBuilt: Bool
			if let property = child.property, labels.existingID(of: property.label) == read.label {
				bound = property
				beingBuilt = true
			} else {
				let start = Int(bindingOffsets[node])
				bound = bindings[start..<start + Int(bindingsBefore[edge])].last { $0.label == read.label }.map { properties.values[Int($0.property)] }
				beingBuilt = false
			}
			guard let bound, let declaration = declarationsByLabelByNode[node][read.label]?.first(where: { $0.property == bound }), let property = properties.existingID(of: bound) else {
				return madeAgainAnswer(at: node, for: read)
			}
			let kind = declaration.property.propertyType
			let declarationForms = declaration.forms
			// Rule 1: a wrapper answering a read only if available passes through the optional parameter `nil` passes
			// through where every form the callee's subtree reads the label in, from above it, is the wrapper's.
			let target = Int(edgeTargets[edge])
			var inReadForm = false
			if kind.isLazilyInstantiated, read.channel == .optional || read.channel == .optionalValue {
				inReadForm = true
				forms.readFromAbove.rows.forEachColumn(inRow: target) { form, _ in
					if forms.table[Int(form)].label == read.label, forms.table[Int(form)].kind != OnlyIfAvailableForm.position(of: kind) {
						inReadForm = false
					}
				}
			}
			let text = "\(read.channel.name) \(declarationForms)\(beingBuilt ? " being built" : "")\(inReadForm ? " in the form read" : "")"
			// Rule 3, case 2: a value, `LazilyInstantiated` or `SendableLazilyInstantiated` being built is one cycle
			// identity whichever twin the path entered, which 2.4.0 builds in one function and passes no parameter. The
			// key names the label alone, not the type and label a cycle identity names elsewhere: a node declares a label
			// once, and a being-built answer gives no parameter whose type could tell two keys apart.
			let keyText: String = if beingBuilt, isTwin(kind) {
				"\(read.channel.name) twin \(bound.label) being built"
			} else if kind.isConstant {
				text
			} else {
				// Rule 2: a wrapper still being built is passed and made again at the call, so it keys as the wrapper.
				"\(read.channel.name) \(declarationForms)\(inReadForm ? " in the form read" : "")"
			}
			return VariantBinding(answer: answer(text: text, beingBuilt: beingBuilt, keyText: keyText, kind: kind, property: property, inReadForm: inReadForm), declaration: Int32(node))
		}
		// Rule A's second stage: `nil` passes through an optional wrapper parameter as well as through the declared form's,
		// so where no answer in the declared form reaches a read and a wrapper of its value does, `nil` keys with the
		// wrapper (the lazy one where both kinds reach), and its call shares that wrapper's function. What reaches a read is
		// folded over the reads it passes through to, beneath the call: down from every binding, then up the edges that
		// bind nothing for it, to a fixed point over cycles. Bits: 1 the declared form, 2 a lazy wrapper, 4 a Sendable lazy
		// wrapper, 8 `nil`.
		let isOptionalRead = readTable.map { $0.channel == .optional || $0.channel == .optionalValue }
		// Each node's optional reads from above get a slot; `slotByRank` holds a node's slots by the rank of each of its
		// reads from above, -1 for a read of another channel.
		var rankOffsets = [Int32](repeating: 0, count: graph.nodes.count + 1)
		var slotByRank = [Int32]()
		var slotCount: Int32 = 0
		for node in graph.nodes.indices {
			reads.rows.forEachColumn(inRow: node) { read, _ in
				if isOptionalRead[Int(read)] {
					slotByRank.append(slotCount)
					slotCount += 1
				} else {
					slotByRank.append(-1)
				}
			}
			rankOffsets[node + 1] = Int32(slotByRank.count)
		}
		let rootSlotCount = slotByRank[0..<Int(rankOffsets[1])].count { $0 >= 0 }
		/// The slot of `read` among `node`'s optional reads from above, nil where it reads no such read.
		func optionalSlot(of read: Int32, in node: Int) -> Int? {
			guard isOptionalRead[Int(read)], let rank = reads.rows.rank(of: read, inRow: node) else { return nil }
			return Int(slotByRank[Int(rankOffsets[node]) + rank])
		}
		var reaching = [UInt8](repeating: 0, count: Int(slotCount))
		// What each edge's optional reads are bound to, by slot of the target, and the caller's slot each passes through.
		var edgeClasses = [(target: Int, slot: Int, bound: UInt8, passedFrom: Int?)]()
		var edgeIndex = 0
		for node in graph.nodes.indices {
			for target in graph.edges(from: node) {
				let edge = edgeIndex
				edgeIndex += 1
				reads.rows.forEachColumn(inRow: Int(target)) { read, _ in
					guard isOptionalRead[Int(read)], let slot = optionalSlot(of: read, in: Int(target)) else { return }
					if let bound = binding(at: edge, of: read) {
						let answer = Int(bound.answer)
						let bit: UInt8 = if isBeingBuilt[answer], isTwin(kinds[answer]) {
							8
						} else if isInReadForm[answer] {
							1
						} else {
							switch kinds[answer] {
							case .lazilyInstantiated:
								2
							case .sendableLazilyInstantiated:
								4
							case .constant, .instantiator, .sendableInstantiator, .erasedInstantiator, .sendableErasedInstantiator:
								1
							}
						}
						edgeClasses.append((Int(target), slot, bit, nil))
					} else if let callerSlot = optionalSlot(of: read, in: node) {
						edgeClasses.append((Int(target), slot, 0, callerSlot))
					} else {
						edgeClasses.append((Int(target), slot, 8, nil))
					}
				}
			}
		}
		// The root's slots come first, and nothing answers the root's own reads.
		for root in 0..<rootSlotCount {
			reaching[root] = 8
		}
		var changed = true
		while changed {
			changed = false
			for edge in edgeClasses {
				let joined = reaching[edge.slot] | edge.bound | (edge.passedFrom.map { reaching[$0] } ?? 0)
				if joined != reaching[edge.slot] {
					reaching[edge.slot] = joined
					changed = true
				}
			}
		}
		var beneath = reaching
		changed = true
		while changed {
			changed = false
			for edge in edgeClasses.reversed() {
				guard let callerSlot = edge.passedFrom else { continue }
				let joined = beneath[callerSlot] | beneath[edge.slot]
				if joined != beneath[callerSlot] {
					beneath[callerSlot] = joined
					changed = true
				}
			}
		}
		/// The key `nil` takes at a call of `target` for `read`.
		func nilKey(of read: Int32, at target: Int32) -> Int32 {
			guard let slot = optionalSlot(of: read, in: Int(target)) else { return optionalParameterKey }
			let classes = beneath[slot]
			return if classes & 1 != 0 || classes & 6 == 0 {
				optionalParameterKey
			} else if classes & 2 != 0 {
				optionalLazilyInstantiatedParameterKey
			} else {
				optionalSendableLazilyInstantiatedParameterKey
			}
		}
		let variants = TypeFactsVariants(
			graph: graph,
			reads: reads,
			rootAnswer: { _ in nil },
			binding: { edge, readID in binding(at: edge, of: readID) },
			family: family,
			key: { readID, answer, target in
				switch readTable[Int(readID)].channel {
				case .optional, .optionalValue:
					// Rule 1, where a value or wrapper still being built is passed `nil`, as a read nothing answers is: whichever
					// twin the path entered, and wherever else the label is bound (rule 3, case 2).
					// An answer already in the form every receive of the label declares passes through the one optional
					// parameter `nil` passes through: only a wrapper answering a read of its value keys apart. The form is the
					// read's, never a place's, so which places a type has, and their order, decide nothing.
					if answer >= 0, !(isBeingBuilt[Int(answer)] && isTwin(kinds[Int(answer)])),
					   !isInReadForm[Int(answer)]
					{
						optionalParameterKey(of: kinds[Int(answer)])
					} else if answer >= 0, isInReadForm[Int(answer)] {
						optionalParameterKey(of: nil)
					} else {
						nilKey(of: readID, at: target)
					}
				case .alias:
					// An alias's text follows only the form of the declaration it is bound to: the value itself, or a lazy
					// wrapper's instance.
					answer < 0 ? answer : optionalParameterKey(of: kinds[Int(answer)])
				case .value, .madeAgain, .mock, .carrier, .fill, .family, .override:
					answer < 0 ? answer : keys[Int(answer)]
				}
			},
			madeAgain: madeAgain.map { madeAgain in
				(madeAgain.edges, { node, readID in madeAgainAnswer(at: node, for: readTable[Int(readID)]) })
			},
		)
		return (variants, isBeingBuilt, isMadeAgain, texts, keys, answerProperties)
	}

	/// The declarations in the order a walk of the root's edges, depth first, first reaches each. A node keeps its scope
	/// and property only for the graph's build and for text: the folds read its position.
	let graph: OrderedGraph<TypeFactsDeclaration>

	/// Whether the world is a mock root's.
	let forMockGeneration: Bool
	/// Whether the world's holes are places: a seam's own tree, or a public mock's.
	let holesArePlaces: Bool

	/// What each node's subtree reads from above it, by read ID.
	let reads: ReadsFromAbove

	/// Each node's kind: the form of the property it is built as.
	let kinds: [TypeFactsKind]
	/// Whether the world is a mock root's (`forMockGeneration`).
	var isMockWorld: Bool {
		forMockGeneration
	}

	/// How each node's type comes to exist.
	let constructions: [TypeFactsConstruction]
	/// The world's ID of the property each node is built as, or -1 for the root.
	let nodeProperties: [Int32]
	/// The world's ID of the type each node builds: a leaf's, the type its property instantiates.
	let builtTypes: [Int32]
	/// Each edge's facts, parallel to `graph.edgeTargets`.
	let edgeFacts: [TypeFactsEdge]
	/// Every node's bindings, each node's in a run starting at its offset; the last offset is the count.
	let bindings: [TypeFactsWorldBinding]
	let bindingOffsets: [Int32]
	/// Each node's twin, the first other node of its cycle identity, or -1.
	let twins: [Int32]
	/// What each node's subtree receives from above it.
	let receives: TypeFactsReceives
	/// The types each node's subtree builds, the node's own included, by the world's type ID.
	let typesBeneath: BitRows
	/// The names each node's subtree declares `@escaping`, by the world's type ID.
	let typesDeclaredEscaping: BitRows
	/// Whether each node's subtree holds a hole: column 0.
	let holesBeneath: BitRows
	/// In a seam's own tree, whether a hole is beneath each node along every edge, fills included: column 0. Empty in any
	/// other world.
	let casesBeneath: BitRows
	/// Every node's parents, each node's in a run starting at its offset; the last offset is the count.
	let parentOffsets: [Int32]
	let parents: [TypeFactsParent]
	/// The fills of every call, in edge order.
	let fills: [TypeFactsFill]
	/// Every fill's path, each fill's in a run.
	let fillPathEntries: [TypeFactsFillPathEntry]
	/// The memos the fills take of labels some route hands them a memo of (`TypeFactsFill.handedMemoStart`), each fill's
	/// run by label.
	let fillHandedMemos: [TypeFactsHandedMemo]
	let propertyFacts: TypeFactsPropertyFacts

	/// Each read ID's read.
	let readTable: [Read]
	/// Each label ID's text, which only text reads.
	let labelTexts: [String]
	/// The keys of the calls' fills and dispatchers (`ScopeGenerator.fillKey(of:)`, `ScopeGenerator.FillDispatcher.key(of:returnsBuilderStruct:)`),
	/// by their IDs, which only text reads.
	let fillKeyTexts: [String]
	/// Each property ID's property, which only text and a spelling lookup read.
	let propertyTable: [Property]
	/// Each type ID's type, which only text and a spelling lookup read.
	let typeTable: [TypeDescription]
	/// Each module ID's name.
	let moduleNames: [String]
	/// Each declaration location ID's location.
	let declarationLocations: [Dependency.DeclarationLocation]

	/// The facts producers still owe each node's answers (`TypeFactsOwedFacts`), found once for the whole world.
	let owedFactsByNode: [TypeFactsOwedFacts]

	/// The facts producers still owe each node's answers, in one walk down from the fills: a node is beneath a fill where
	/// a fill reaches it. Each node and each node a walk from a fill reaches counts as one visit of `findingOwedFacts`;
	/// asked of each declaration with a walk up its parents, a chain of n declarations walked n² parents.
	private static func owedFacts(of graph: OrderedGraph<TypeFactsDeclaration>, forMockGeneration: Bool) -> [TypeFactsOwedFacts] {
		let everyNode: TypeFactsOwedFacts = forMockGeneration ? [.mockRootPin, .mockRootRecord, .mockRootBinding] : []
		var owed = [TypeFactsOwedFacts](repeating: everyNode, count: graph.nodes.count)
		var visits = graph.nodes.count
		// A declaration is beneath a fill where any of its routes enters one: a walk down from every fill.
		var pending = [Int]()
		for index in graph.nodes.indices where graph.nodes[index].key.isFill {
			owed[index].insert(.fillBeingBuilt)
			pending.append(index)
		}
		while let current = pending.popLast() {
			visits += 1
			for target in graph.edges(from: current) where !owed[Int(target)].contains(.fillBeingBuilt) {
				owed[Int(target)].insert(.fillBeingBuilt)
				pending.append(Int(target))
			}
		}
		GenerationWork.record(visits, by: .findingOwedFacts)
		return owed
	}

	/// The facts of the node's edges, parallel to `graph.edges(from:)`.
	func edgeFacts(from index: Int) -> ArraySlice<TypeFactsEdge> {
		edgeFacts[graph.edgeIndices(from: index)]
	}

	/// The node's bindings, in the order its scope binds them.
	func worldBindings(of index: Int) -> ArraySlice<TypeFactsWorldBinding> {
		bindings[Int(bindingOffsets[index])..<Int(bindingOffsets[index + 1])]
	}

	/// The node's parents, in the order the walk meets their edges to it.
	func parents(of index: Int) -> ArraySlice<TypeFactsParent> {
		parents[Int(parentOffsets[index])..<Int(parentOffsets[index + 1])]
	}

	/// The read as text.
	func readDescription(_ read: Int32) -> String {
		readTable[Int(read)].description(labels: labelTexts)
	}

	/// The declaration as text: the type built, and the property it is built as, `erased`, `fill`, `alias` and `hole`
	/// where they hold.
	func description(ofNode index: Int) -> String {
		let key = graph.nodes[index].key
		var description = switch key.leaf {
		case .none:
			graph.nodes[index].scope.instantiable.concreteInstantiable.asSource
		case .alias:
			"alias"
		case .hole:
			"hole"
		}
		if let property = graph.nodes[index].property {
			description.append(" as \(property.asSource)")
		}
		if key.erasedToConcreteExistential {
			description.append(" erased")
		}
		if key.isFill {
			description.append(" fill")
		}
		return description
	}

	/// The property as cycle validation sees it, with the concrete type built, as text, for reports: two nodes of one key
	/// have one `cycleIDs` entry.
	func cycleKey(ofNode index: Int) -> String {
		Self.cycleKey(of: graph.nodes[index], at: index)
	}

	/// A leaf builds no scope and so closes no cycle: its key is its own.
	private static func cycleKey(of node: TypeFactsDeclaration, at index: Int) -> String {
		guard node.key.leaf == .none else { return "leaf \(index)" }
		return "\(node.property?.asValidatedForDependencyCycles.asSource ?? "root") for \(node.scope.instantiable.concreteInstantiable.asSource)"
	}

	/// What the graph's folds hold, beside the nodes it keeps for text and the spellings it keeps for lookups: the 32-bit
	/// elements of its columns (each 64-bit word of a bit set counts two, each edge's and binding's facts eight, a byte or
	/// a flag one), which a test counts per node and per edge.
	var columnElementCount: Int {
		var count = graph.columnElementCount + kinds.count + constructions.count + nodeProperties.count + builtTypes.count
		count += 8 * edgeFacts.count + 11 * bindings.count + bindingOffsets.count
		count += cycleIDs.count + twins.count + parentOffsets.count + 3 * parents.count
		count += 12 * fills.count + 2 * fillPathEntries.count + 3 * fillHandedMemos.count + propertyFacts.columnElementCount + readTable.count
		count += readColumn.count + readOffsets.count + labelColumn.count + labelOffsets.count + answerKeys.count + variants.columnElementCount
		count += 2 * (reads.rows.wordCount + receives.wordCount + typesBeneath.wordCount + typesDeclaredEscaping.wordCount + holesBeneath.wordCount)
		count += madeAgain?.columnElementCount ?? 0
		return count
	}

	/// The graph as text, a line per node: its position, its declaration, `cycle` where it is on one, what its subtree reads
	/// from above, and the positions of its edges' targets.
	var projection: String {
		var lines = [String]()
		for index in graph.nodes.indices {
			var line = "\(index): \(description(ofNode: index))"
			if graph.isOnCycle(index) {
				line.append(" cycle")
			}
			let reads = reads.reads(of: index)
			if !reads.isEmpty {
				line.append(" reads \(reads.map(readDescription).joined(separator: ", "))")
			}
			for target in graph.edges(from: index) {
				line.append(" -> \(target)")
			}
			for target in madeAgain?.targets(of: index) ?? [] {
				line.append(" again -> \(target)")
			}
			lines.append(line)
		}
		return lines.joined(separator: "\n")
	}

	/// A node's identity as cycle validation sees it: the run's ID of its property as validated for cycles, or -1 for a
	/// root, and the run's ID of its concrete type.
	private struct CycleIdentity: Hashable, Sendable {
		let property: Int32
		let concreteType: Int32
	}

	/// The node an edge leaves.
	static func source(ofEdge edge: Int, in graph: OrderedGraph<TypeFactsDeclaration>) -> Int {
		// Edges are in node order, so the source is the first node whose edges end after the edge: a node with no edges
		// ends where it starts, at or before it.
		var low = 0
		var high = graph.nodes.count - 1
		while low < high {
			let middle = (low + high) / 2
			if graph.edgeIndices(from: middle).upperBound > edge {
				high = middle
			} else {
				low = middle + 1
			}
		}
		return low
	}

	/// The property's form: a leaf's as its leaf, the root's `constant`.
	private static func kind(of node: TypeFactsDeclaration) -> TypeFactsKind {
		switch node.key.leaf {
		case .alias:
			return .alias
		case .hole:
			return .hole
		case .none:
			break
		}
		switch node.property?.propertyType ?? .constant {
		case .constant:
			return .constant
		case .instantiator:
			return .instantiator
		case .sendableInstantiator:
			return .sendableInstantiator
		case .erasedInstantiator:
			return .erasedInstantiator
		case .sendableErasedInstantiator:
			return .sendableErasedInstantiator
		case .lazilyInstantiated:
			return .lazy
		case .sendableLazilyInstantiated:
			return .sendableLazy
		}
	}

	/// How the declaration's type comes to exist: a fill, a call of another module's seam or public mock, in a mock's world
	/// the type's hand-written mock, else its initializer. A leaf builds no type, and reads as `initializer`.
	private static func construction(of node: TypeFactsDeclaration, forMockGeneration: Bool) -> TypeFactsConstruction {
		let scope = node.scope
		if node.key.isFill {
			return .fill
		} else if node.key.leaf != .none {
			return .initializer
		} else if scope.seamCall != nil {
			return .seamCall
		} else if scope.publicMockCall != nil {
			return .publicMockCall
		} else if forMockGeneration, scope.instantiable.mockInitializer != nil, let property = node.property, scope.instantiable.mockReturnTypeIsCompatible(withPropertyType: property.typeDescription.asInstantiatedType) {
			return .handWrittenMock
		} else {
			return .initializer
		}
	}

	/// The edges whose children start after their siblings that hold no place (`ScopeGenerator.startsAsCarrier(_:)`), as
	/// `SeamDeclarationGraph` finds them: an edge whose target dominates its source closes a cycle on every build and is
	/// removed; a fill is entered where its tree reaches a hole; and a child holds a place where the edge for its property
	/// out of any declaration of its parent's type is left and reaches a hole along what is left. A fact of the parent's
	/// type, so every declaration of it starts its children in one order.
	private static func carrierEdges(of graph: OrderedGraph<TypeFactsDeclaration>, edgeIsFill: [Bool], builtTypes: [Int32], nodeProperties: [Int32]) -> Set<Int> {
		let nodes = graph.nodes
		// The nodes that reach a hole along every edge: a fill whose tree reaches none is left out, as the generator's graph
		// skips a fill whose tree holds no site.
		var predecessors = [[Int]](repeating: [], count: nodes.count)
		for source in nodes.indices {
			for edge in graph.edgeIndices(from: source) {
				predecessors[Int(graph.edgeTargets[edge])].append(source)
			}
		}
		func reachingHoles(along predecessors: [[Int]]) -> [Bool] {
			var reaches = nodes.map { $0.key.leaf == .hole }
			var nodesToVisit = reaches.indices.filter { reaches[$0] }
			while let node = nodesToVisit.popLast() {
				for predecessor in predecessors[node] where !reaches[predecessor] {
					reaches[predecessor] = true
					nodesToVisit.append(predecessor)
				}
			}
			return reaches
		}
		let reachesHole = reachingHoles(along: predecessors)
		func isInGraph(_ edge: Int) -> Bool {
			!edgeIsFill[edge] || reachesHole[Int(graph.edgeTargets[edge])]
		}
		let dominators = immediateDominators(of: graph, followsEdge: isInGraph)
		func dominates(_ dominator: Int, _ node: Int) -> Bool {
			var current = node
			while current != dominator {
				let next = dominators[current]
				guard next >= 0, next != current else { return false }
				current = next
			}
			return true
		}
		var leftPredecessors = [[Int]](repeating: [], count: nodes.count)
		var isLeft = [Bool](repeating: false, count: graph.edgeCount)
		for source in nodes.indices where dominators[source] >= 0 {
			for edge in graph.edgeIndices(from: source) where isInGraph(edge) {
				let target = Int(graph.edgeTargets[edge])
				guard !dominates(target, source) else { continue }
				isLeft[edge] = true
				leftPredecessors[target].append(source)
			}
		}
		let reachesHoleAlongLeftEdges = reachingHoles(along: leftPredecessors)
		// By the parent's type and the child's property, whether some declaration's edge holds a place.
		struct TypeProperty: Hashable {
			let type: Int32
			let property: Int32
		}
		var holdsPlace = Set<TypeProperty>()
		for source in nodes.indices {
			for edge in graph.edgeIndices(from: source) where isLeft[edge] && !edgeIsFill[edge] && reachesHoleAlongLeftEdges[Int(graph.edgeTargets[edge])] {
				holdsPlace.insert(TypeProperty(type: builtTypes[source], property: nodeProperties[Int(graph.edgeTargets[edge])]))
			}
		}
		var carrierEdges = Set<Int>()
		for source in nodes.indices {
			for edge in graph.edgeIndices(from: source) where !edgeIsFill[edge] && holdsPlace.contains(TypeProperty(type: builtTypes[source], property: nodeProperties[Int(graph.edgeTargets[edge])])) {
				carrierEdges.insert(edge)
			}
		}
		return carrierEdges
	}

	/// Each node's immediate dominator from the root, node 0, along the edges `followsEdge` keeps (Cooper, Harvey and
	/// Kennedy's iteration over reverse postorder): the root's is itself, and a node those edges do not reach has -1.
	static func immediateDominators(of graph: OrderedGraph<TypeFactsDeclaration>, followsEdge: (Int) -> Bool) -> [Int] {
		let count = graph.nodes.count
		// Postorder by an explicit stack, each node's edges in order.
		var postorderNumber = [Int](repeating: -1, count: count)
		var postorder = [Int]()
		var isVisited = [Bool](repeating: false, count: count)
		var frames = [(node: 0, edges: Array(graph.edgeIndices(from: 0)), next: 0)]
		isVisited[0] = true
		var predecessors = [[Int]](repeating: [], count: count)
		while var frame = frames.popLast() {
			if frame.next < frame.edges.count {
				let edge = frame.edges[frame.next]
				frame.next += 1
				frames.append(frame)
				guard followsEdge(edge) else { continue }
				let target = Int(graph.edgeTargets[edge])
				predecessors[target].append(frame.node)
				if !isVisited[target] {
					isVisited[target] = true
					frames.append((target, Array(graph.edgeIndices(from: target)), 0))
				}
			} else {
				postorderNumber[frame.node] = postorder.count
				postorder.append(frame.node)
			}
		}
		var dominators = [Int](repeating: -1, count: count)
		dominators[0] = 0
		func intersect(_ first: Int, _ second: Int) -> Int {
			var first = first
			var second = second
			while first != second {
				while postorderNumber[first] < postorderNumber[second] {
					first = dominators[first]
				}
				while postorderNumber[second] < postorderNumber[first] {
					second = dominators[second]
				}
			}
			return first
		}
		var changed = true
		while changed {
			changed = false
			for node in postorder.reversed() where node != 0 {
				var newDominator = -1
				for predecessor in predecessors[node] where dominators[predecessor] >= 0 {
					newDominator = newDominator < 0 ? predecessor : intersect(predecessor, newDominator)
				}
				if newDominator != dominators[node] {
					dominators[node] = newDominator
					changed = true
				}
			}
		}
		return dominators
	}

	/// The family a call builds its callee in, given the function its edge `opens` and its caller's family: a body inside a
	/// `@Sendable` function is in the `@Sendable` family, and so is every body beneath it.
	/// The family a call at an edge builds its callee in, given the caller's: its own family in a mock, and in a seam's
	/// tree where a hole is beneath the callee along every edge, fills included (`casesBeneath`); the root's `.plain`
	/// everywhere else.
	static func familyOfCall(
		forMockGeneration: Bool,
		holesArePlaces: Bool,
		casesBeneath: BitRows,
		edgeTargets: [Int32],
		edgeOpens: [TypeFactsFunctionOpened],
	) -> (_ edge: Int, _ callerFamily: VariantFamily) -> VariantFamily {
		if forMockGeneration {
			{ edge, callerFamily in familyOfCall(opening: edgeOpens[edge], callerFamily: callerFamily) }
		} else if holesArePlaces {
			{ edge, callerFamily in casesBeneath.contains(0, inRow: Int(edgeTargets[edge])) ? familyOfCall(opening: edgeOpens[edge], callerFamily: callerFamily) : .plain }
		} else {
			{ _, callerFamily in callerFamily }
		}
	}

	/// Per variant, whether a call builds its body inside a `@Sendable` function: the mark a body shared by calls inside
	/// and outside one carries, folded over every call into it, so that its function is `@Sendable` once any call needs
	/// it. A call opens such a function by `familyOfCall(opening:callerFamily:)`'s rule, and a call from a marked body
	/// hands the mark on. Where a world keys a body by family (a mock's, and a seam's that holds a hole), the mark is its
	/// family, except in a group below; elsewhere it is the one fact that tells a body's places inside and outside the
	/// function apart.
	///
	/// `oneFunctionGroups` are the variants one function serves: a body and its twins of one key, the `Sendable`
	/// wrapper's and the constant's (the lead's ruling for one `@Sendable` function), which share the mark, of any
	/// family.
	///
	/// A member a loop makes again (`TypeFactsVariants.madeAgainCallees(of:)`) needs no fold of its own: its call names the
	/// variant its maker's parent calls at an edge (oracle B, check 32), which that edge marks wherever the maker is marked,
	/// since a loop's members are all plain or all `Sendable` (a mixed loop is rejected), and a twin group's `Sendable`
	/// twin requires its type to be `Sendable`, which a plain loop member, holding a plain builder, is not. Check 34 holds
	/// every made-again call to it.
	static func sendableMarks(of variants: TypeFactsVariants, graph: OrderedGraph<TypeFactsDeclaration>, edgeOpens: [TypeFactsFunctionOpened], oneFunctionGroups: [[Int]]) -> [Bool] {
		var marks = [Bool](repeating: false, count: variants.count)
		var groupOfVariant = [Int](repeating: -1, count: variants.count)
		for (group, members) in oneFunctionGroups.enumerated() {
			for member in members {
				groupOfVariant[member] = group
			}
		}
		// Each variant is visited once in order and again only when a call newly marks it: a call that closes a cycle
		// reaches a variant made before its caller.
		var worklist = Array((0..<variants.count).reversed())
		while let variant = worklist.popLast() {
			if marks[variant], groupOfVariant[variant] >= 0 {
				for member in oneFunctionGroups[groupOfVariant[variant]] where !marks[member] {
					marks[member] = true
					worklist.append(member)
				}
			}
			let callerFamily: VariantFamily = marks[variant] ? .sendable : .plain
			let edgeOffset = graph.edgeOffset(of: Int(variants.node(of: variant)))
			for (edgeIndex, callee) in variants.callees(of: variant).enumerated() where !marks[Int(callee)] && familyOfCall(opening: edgeOpens[edgeOffset + edgeIndex], callerFamily: callerFamily) == .sendable {
				marks[Int(callee)] = true
				worklist.append(Int(callee))
			}
		}
		return marks
	}

	/// The variants of twin declarations, one cycle identity's, that read the same values from above and share a key,
	/// each group of two or more in variant order, where a twin of the identity is on a cycle, as one that closes it on
	/// the other is: one function serves each group, in a mock's world as in production's (mocks behave like
	/// production), so the group ignores family. Twins of an identity no cycle runs through are siblings built apart, a
	/// function each.
	static func twinGroups(of variants: TypeFactsVariants, cycleIDs: [CycleID], twins: [Int32], isOnCycle: (Int) -> Bool, readColumn: [Int32], readOffsets: [Int32]) -> [[Int]] {
		var identitiesOnCycles = Set<CycleID>()
		for (node, identity) in cycleIDs.enumerated() where twins[node] >= 0 && isOnCycle(node) {
			identitiesOnCycles.insert(identity)
		}
		var groupByBody = [TwinBody: Int]()
		var groups = [[Int]]()
		for variant in 0..<variants.count where identitiesOnCycles.contains(cycleIDs[Int(variants.node(of: variant))]) {
			let node = Int(variants.node(of: variant))
			let body = TwinBody(identity: cycleIDs[node], reads: Array(readColumn[Int(readOffsets[node])..<Int(readOffsets[node + 1])]), keys: Array(variants.keys(of: variant)))
			if let group = groupByBody[body] {
				groups[group].append(variant)
			} else {
				groupByBody[body] = groups.count
				groups.append([variant])
			}
		}
		return groups.filter { $0.count > 1 }
	}

	/// A body twin declarations share: their cycle identity, the values they read from above, and the variant's key.
	/// A key is positional over its node's reads, so two twins' keys mean the same only over the same reads. Twins of
	/// one identity whose reads differ may be a shape SafeDI cannot build; the reads keep such twins apart rather than
	/// let equal positions merge bodies that differ.
	private struct TwinBody: Hashable {
		let identity: CycleID
		let reads: [Int32]
		let keys: [Int32]
	}

	static func familyOfCall(opening opens: TypeFactsFunctionOpened, callerFamily: VariantFamily) -> VariantFamily {
		switch opens {
		case .sendableInstantiatorBuilder, .sendableLazyWrapper, .otherSendableFunction:
			.sendable
		case .none, .instantiatorBuilder:
			callerFamily
		}
	}

	private static func opens(_ node: TypeFactsDeclaration) -> TypeFactsFunctionOpened {
		guard node.key.leaf == .none, let property = node.property else { return .none }
		switch property.propertyType {
		case .constant:
			return .none
		case .instantiator, .erasedInstantiator:
			return .instantiatorBuilder
		case .sendableInstantiator, .sendableErasedInstantiator:
			return .sendableInstantiatorBuilder
		case .lazilyInstantiated:
			// A plain wrapper's closure is no `@Sendable` function, the only kind the outcomes fold reads, and it may capture.
			return .none
		case .sendableLazilyInstantiated:
			return .sendableLazyWrapper
		}
	}

	/// The names a scope's own declarations declare `@escaping`, as `ScopeGenerator`'s `typesDeclaredEscaping` reads them
	/// before its children's, in a fixed order.
	private static func ownTypesDeclaredEscaping(of scope: ConstructionScope) -> [TypeDescription] {
		let instantiable = scope.instantiable
		var typesDeclaredEscaping = Set(instantiable.initializer?.typesDeclaredEscaping ?? [])
		typesDeclaredEscaping.formUnion(instantiable.mockInitializer?.typesDeclaredEscaping ?? [])
		let initializerTypesDeclaredEscaping = typesDeclaredEscaping
		for dependency in instantiable.dependencies where initializerTypesDeclaredEscaping.contains(dependency.property.typeDescription) {
			if case let .aliased(fulfillingProperty: fulfillingProperty, erasedToConcreteExistential: false, onlyIfAvailable: _) = dependency.source,
			   let fulfillingName = TypeDescription.attributed(fulfillingProperty.typeDescription, specifiers: [], attributes: ["escaping"]).nameDeclaredEscaping
			{
				typesDeclaredEscaping.insert(fulfillingName)
			}
		}
		typesDeclaredEscaping.formUnion(scope.publicMockCall?.typesDeclaredEscaping ?? [])
		typesDeclaredEscaping.formUnion(scope.seamCall?.typesDeclaredEscaping ?? [])
		return typesDeclaredEscaping.sorted()
	}

	/// The facts of every property `properties` holds, interning the forms they name, each of which gets facts too:
	/// `existing`'s, then those of each property interned since.
	private static func propertyFacts(of properties: inout TypeFactsInterner<Property>, labels: inout TypeFactsInterner<String>, extending existing: TypeFactsPropertyFacts) -> TypeFactsPropertyFacts {
		var labelIDs = existing.labels
		var unwrapped = existing.unwrapped
		var isOptional = existing.isOptional
		var instances = existing.instances
		var isBuilder = existing.isBuilder
		// The last offset ends the last run, and the runs go on past it.
		var formsReadOffsets = existing.formsReadOffsets
		formsReadOffsets.removeLast()
		var formsRead = existing.formsRead
		var formsProvidedOffsets = existing.formsProvidedOffsets
		formsProvidedOffsets.removeLast()
		var formsProvided = existing.formsProvided
		var index = existing.labels.count
		while index < properties.values.count {
			let property = properties.values[index]
			labelIDs.append(labels.id(of: property.label))
			unwrapped.append(properties.id(of: property.asUnwrappedProperty))
			isOptional.append(property.typeDescription.isOptional)
			instances.append(property.asLazilyInstantiatedInstanceProperty.map { properties.id(of: $0) } ?? -1)
			isBuilder.append(ScopeGenerator.isBuilder(property))
			formsReadOffsets.append(Int32(formsRead.count))
			for form in property.formsReadByOnlyIfAvailableReceive {
				formsRead.append(properties.id(of: form))
			}
			formsProvidedOffsets.append(Int32(formsProvided.count))
			for form in CycleParameter.forms(providedBy: property).sorted() {
				formsProvided.append(properties.id(of: form))
			}
			index += 1
		}
		formsReadOffsets.append(Int32(formsRead.count))
		formsProvidedOffsets.append(Int32(formsProvided.count))
		return TypeFactsPropertyFacts(
			labels: labelIDs,
			unwrapped: unwrapped,
			isOptional: isOptional,
			instances: instances,
			isBuilder: isBuilder,
			formsReadOffsets: formsReadOffsets,
			formsRead: formsRead,
			formsProvidedOffsets: formsProvidedOffsets,
			formsProvided: formsProvided,
		)
	}

	/// The reads a declaration makes itself: the label of the property it is built as, whose nearest declaration its
	/// build adds forms being built to; each label its type receives, and, for a receive only if available, whether it is
	/// handed a value, and in a mock's world what the mock root pins of it; and the label an alias is fulfilled by, unless
	/// the type instantiates or forwards a property of that label, which the alias then renames; and, for a call that passes
	/// fills, each label the fills' trees receive, whose declaration the call hands them. A leaf reads nothing of its own:
	/// its scope's own dependencies read for it.
	private static func ownReads(of node: TypeFactsDeclaration, forMockGeneration: Bool, labels: inout TypeFactsInterner<String>, formsReadOnlyIfAvailable: inout [OnlyIfAvailableForm]) -> [Read] {
		var reads = [Read]()
		switch node.key.leaf {
		case .none:
			break
		case .alias:
			// An alias is bound to the nearest declaration of its fulfilling label, whose form decides its text (`x` or
			// `x.instance`), so it reads that label: a required alias on the alias channel, keyed by the answer's form; one
			// only if available as a receive of it does, keyed by rule 1.
			if let fulfillingProperty = node.aliasFulfillingProperty {
				let label = labels.id(of: fulfillingProperty.label)
				if node.isOnlyIfAvailableAlias {
					appendReceiveReads(of: label, onlyIfAvailable: true, forMockGeneration: forMockGeneration, to: &reads)
					formsReadOnlyIfAvailable.append(OnlyIfAvailableForm(label: label, kind: fulfillingProperty.asUnwrappedProperty.propertyType))
				} else {
					reads.append(Read(.alias, label: label))
				}
			}
			return reads
		case .hole:
			return reads
		}
		let record = node.scope
		if let property = node.property {
			reads.append(Read(.value, label: labels.id(of: property.label)))
		}
		let dependencies = record.instantiable.dependencies
		var createdLabels = Set<String>()
		for dependency in dependencies {
			switch dependency.source {
			case .instantiated, .forwarded:
				createdLabels.insert(dependency.property.label)
			case .received, .aliased:
				break
			}
		}
		for dependency in dependencies {
			switch dependency.source {
			case .instantiated, .forwarded:
				break
			case let .received(onlyIfAvailable):
				let label = labels.id(of: dependency.property.label)
				appendReceiveReads(of: label, onlyIfAvailable: onlyIfAvailable, forMockGeneration: forMockGeneration, to: &reads)
				if onlyIfAvailable {
					formsReadOnlyIfAvailable.append(OnlyIfAvailableForm(label: label, kind: dependency.property.asUnwrappedProperty.propertyType))
				}
			case let .aliased(fulfillingProperty, _, onlyIfAvailable):
				if !createdLabels.contains(fulfillingProperty.label) {
					let label = labels.id(of: fulfillingProperty.label)
					appendReceiveReads(of: label, onlyIfAvailable: onlyIfAvailable, forMockGeneration: forMockGeneration, to: &reads)
					if onlyIfAvailable {
						formsReadOnlyIfAvailable.append(OnlyIfAvailableForm(label: label, kind: fulfillingProperty.asUnwrappedProperty.propertyType))
					}
				}
			}
		}
		// A call that passes fills hands each the caller's declaration of what the fill's tree receives, in the form the
		// fill takes (`Scope.callerArgument`), which it reads as a receive only if available reads it.
		if !record.holeArguments.isEmpty {
			for property in Set(record.fillReceivedProperties.values.joined()).sorted() {
				let label = labels.id(of: property.label)
				reads.append(Read(.optionalValue, label: label))
				reads.append(Read(.optional, label: label))
				formsReadOnlyIfAvailable.append(OnlyIfAvailableForm(label: label, kind: property.asUnwrappedProperty.propertyType))
			}
		}
		return reads
	}

	/// A required receive reads the nearest declaration of its label; one only if available reads it as `optionalValue`,
	/// and whether it is handed a value or `nil`, both of which key by rule 1.
	private static func appendReceiveReads(of label: Int32, onlyIfAvailable: Bool, forMockGeneration: Bool, to reads: inout [Read]) {
		guard onlyIfAvailable else {
			reads.append(Read(.value, label: label))
			return
		}
		reads.append(Read(.optionalValue, label: label))
		reads.append(Read(.optional, label: label))
		if forMockGeneration {
			reads.append(Read(.mock, label: label))
		}
	}
}

/// A seam call or a call of another module's public mock that passes fills, as the graph's build reads it to find what
/// each fill binds from its site's scope struct (`ScopeGenerator.structBindings(ofFillOf:passedByPublicMockCall:innerScopeReaders:handedMemoByLabel:)`).
/// Held only while the graph is built.
struct FillsOfCall {
	init(scope: ConstructionScope, fillEdges: [(edge: Int32, hole: SeamSignature.Hole)]) {
		self.fillEdges = fillEdges
		isPublicMockCall = scope.publicMockCall != nil
		calledBuilders = scope.calledBuilders
	}

	/// What each fill edge's fill binds from its site's scope struct, and the memo it takes of each label some route hands
	/// it one of, by the edge's position: `receivedByFillTarget` gives what the subtree of an edge's target reads from above
	/// it, along the edges that are no fills.
	///
	/// Where some route hands a fill a memo, the fill binds the memo's forms of its label in place of the place's field
	/// (`ScopeGenerator.FillDispatcher.memosHanded(toFills:ofPublicMockCall:labelsReadOnlyAsPlaceField:readingSendableWrapper:among:)`,
	/// the tree's own rule, over the call's dispatchers, which the tree's rule declares from the call's builders and
	/// filled places; only their names, which no memo reads, come from an allocator of their own). The tree finds two
	/// inputs of that rule on the pass before, and here the fill's target's reads answer each, the rule run again with what
	/// they find: the labels a fill's tree reads only as the place's field, of which it hands no memo
	/// (`ScopeGenerator.FillDispatcher.readsOnlyAsPlaceField(_:placeFields:reads:carriedBySites:)`), and then the
	/// `SendableLazilyInstantiated` its tree reads beside a label it is handed a memo of, which decides only that memo's
	/// deferral (`ScopeGenerator.FillDispatcher.sendableWrapperReads(ofLabelsHandedAsMemo:labelsReadOnlyAsPlaceField:among:)`),
	/// so it hides nothing but tells which wrapper's memo the fill takes. Three inputs of the tree's are not a record's,
	/// and stay at what they are for a call outside a fill in a tree that is no seam's: the dispatchers enclosing calls
	/// declare (none), the scope values a seam's tree hands its fills (`SeamHoles.innerScope(at:innerKey:)`, none), and the
	/// fields the sites inside a fill carry (none). Each rule runs over the call's dispatchers at most three times, and each
	/// fill edge's received row is read once.
	func structBindings(receivedByFillTarget: (_ edge: Int32) -> Set<Property>) -> (bindingsByEdge: [Int32: ScopeGenerator.FillStructBindings], handedMemoByLabelByEdge: [Int32: [String: ScopeGenerator.FillDispatcher.HandedMemo]]) {
		let innerScopeReaders = calledBuilders.map { InnerScopeReaders(enumsByKey: $0.enumsByKey) }
		var handedMemosByKey = [String: ScopeGenerator.FillDispatcher.HandedMemos]()
		var emittedFills = [(fill: ScopeGenerator.FillDispatcher.EmittedFill, edge: Int32, placeFields: [SeamSignature.Hole.Field])]()
		// A public mock's caller hands values.
		if let calledBuilders, !isPublicMockCall {
			// Every place of a case nested by type is filled by one fill, the first place's, which takes every field any
			// place of the case carries (`ScopeGenerator.caseFields(of:)`).
			var placesByCaseKey = [String: [SeamSignature.Hole]]()
			for (_, hole) in fillEdges where hole.enumPlace != nil {
				placesByCaseKey[ScopeGenerator.fillCaseKey(of: hole), default: []].append(hole)
			}
			var emittedCaseKeys = Set<String>()
			for (edge, hole) in fillEdges {
				let caseKey = ScopeGenerator.fillCaseKey(of: hole)
				guard hole.enumPlace == nil || emittedCaseKeys.insert(caseKey).inserted else { continue }
				let places = placesByCaseKey[caseKey] ?? [hole]
				let fields = hole.enumPlace == nil ? hole.fields : ScopeGenerator.caseFields(of: places).fields
				emittedFills.append((ScopeGenerator.FillDispatcher.EmittedFill(key: ScopeGenerator.fillKey(of: hole), hole: hole, fields: fields), edge, places.flatMap(\.fields)))
			}
			var names = GeneratedNameAllocator(reserving: [])
			let dispatchers = ScopeGenerator.FillDispatcher.dispatchers(
				of: calledBuilders,
				filledSites: Set(fillEdges.map(\.hole.site)),
				enclosingDispatchers: [:],
				fillNames: [:],
				names: &names,
			)
			func memosHanded(leavingOut labelsReadOnlyAsPlaceField: [String: Set<String>], readingSendableWrapper: [String: [String: Property]]) -> [String: ScopeGenerator.FillDispatcher.HandedMemos] {
				ScopeGenerator.FillDispatcher.memosHanded(toFills: emittedFills.map(\.fill), ofPublicMockCall: isPublicMockCall, labelsReadOnlyAsPlaceField: labelsReadOnlyAsPlaceField, readingSendableWrapper: readingSendableWrapper, among: dispatchers)
			}
			handedMemosByKey = memosHanded(leavingOut: [:], readingSendableWrapper: [:])
			// What each fill's target reads from above, found once for a fill some route hands a memo.
			var receivedByEdge = [Int32: Set<Property>]()
			var labelsReadOnlyAsPlaceField = [String: Set<String>]()
			for (fill, edge, placeFields) in emittedFills {
				guard let memoByLabel = handedMemosByKey[fill.key]?.memoByLabel, !memoByLabel.isEmpty else { continue }
				let received = receivedByFillTarget(edge)
				receivedByEdge[edge] = received
				for field in fill.fields {
					guard let memo = memoByLabel[field.property.label],
					      ScopeGenerator.FillDispatcher.readsOnlyAsPlaceField(field.handedAsMemo(memo), placeFields: placeFields, reads: { ScopeGenerator.reads($0, among: received) }, carriedBySites: [])
					else { continue }
					labelsReadOnlyAsPlaceField[fill.key, default: []].insert(field.property.label)
				}
			}
			if !labelsReadOnlyAsPlaceField.isEmpty {
				handedMemosByKey = memosHanded(leavingOut: labelsReadOnlyAsPlaceField, readingSendableWrapper: [:])
			}
			var readingSendableWrapper = [String: [String: Property]]()
			for (fill, edge, _) in emittedFills {
				guard let memoByLabel = handedMemosByKey[fill.key]?.memoByLabel, !memoByLabel.isEmpty, let received = receivedByEdge[edge] else { continue }
				let instancePropertyByLabel = ScopeGenerator.FillDispatcher.sendableWrapperReads(ofLabelsHandedAsMemo: Set(memoByLabel.keys), labelsReadOnlyAsPlaceField: labelsReadOnlyAsPlaceField[fill.key] ?? [], among: received)
				if !instancePropertyByLabel.isEmpty {
					readingSendableWrapper[fill.key] = instancePropertyByLabel
				}
			}
			if !readingSendableWrapper.isEmpty {
				handedMemosByKey = memosHanded(leavingOut: labelsReadOnlyAsPlaceField, readingSendableWrapper: readingSendableWrapper)
			}
		}
		var memoByLabelByEdge = [Int32: [String: ScopeGenerator.FillDispatcher.HandedMemo]]()
		for (fill, edge, _) in emittedFills {
			memoByLabelByEdge[edge] = handedMemosByKey[fill.key]?.memoByLabel
		}
		var bindingsByEdge = [Int32: ScopeGenerator.FillStructBindings]()
		for (edge, hole) in fillEdges {
			bindingsByEdge[edge] = ScopeGenerator.structBindings(ofFillOf: hole, passedByPublicMockCall: isPublicMockCall, innerScopeReaders: innerScopeReaders, handedMemoByLabel: memoByLabelByEdge[edge] ?? [:])
		}
		return (bindingsByEdge, memoByLabelByEdge)
	}

	private let fillEdges: [(edge: Int32, hole: SeamSignature.Hole)]
	private let isPublicMockCall: Bool
	private let calledBuilders: CalledBuilders?
}
