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

/// One root of a world of several roots (`TypeFactsGraph.init(roots:intern:)`): a root of one validation call, with what
/// the root is given from outside its tree.
struct TypeFactsRoot {
	let scope: ConstructionScope
	/// What the root's tree receives from outside it that the root is handed: a generated seam's parameters, or what a
	/// mock root binds for its tree. In `Property` order, so no `Set` order reaches the world.
	let givenProperties: [Property]
	/// The checks the validation call runs on the root's tree.
	let checks: TypeFactsRootChecks
}

/// The checks a validation call runs on a root's tree, by which its walk judges each node the root reaches.
struct TypeFactsRootChecks: OptionSet {
	let rawValue: UInt8

	/// The tree is validated for dependency cycles: every root's, but that of a type validated only because
	/// `additionalMocksToGenerate` lists it.
	static let cycles = TypeFactsRootChecks(rawValue: 1 << 0)
	/// The tree is validated for received dependencies a closer declaration of their label hides: every root's where
	/// production trees are validated, and where mocks are, the tree of each type whose mock is generated.
	static let hiddenProperties = TypeFactsRootChecks(rawValue: 1 << 1)
}

extension TypeFactsGraph {
	/// One world of every root of a validation call, built before any of them is validated, so nothing in it is an error:
	/// a read nothing answers has the answer `none`, and a read answered by a declaration that provides no property its
	/// receive accepts has that declaration's forms, for the caller to judge. Ordinary generation builds no such world:
	/// only validation over per-type facts reads it.
	///
	/// The graph keeps one root. Node 0 stands for no declaration and has an edge to one frame per root, in the roots'
	/// order; a frame binds exactly what its root is given and has one edge, to its root's declaration. A frame hides
	/// every label, so no answer passes from one root's frame to another root's nodes: a declaration only one root
	/// reaches has that root's answers alone, and one two roots reach has both roots'.
	///
	/// An answer is interned by value: the channel that asks, the forms the nearest declaration provides, and whether
	/// that declaration is still being built at the edge. Validation asks whether any route fails, which is a join over
	/// the routes, so the world holds each read's answers as a set per node (`TypeFactsAnswerSets`,
	/// `answers(ofReadAt:of:)`), never a variant per vector of answers, whose count follows the routes. Every read
	/// therefore keys its variant as a parameter does (`optionalParameterKey`), alike whatever it is answered, and each
	/// node has one variant per family. The forms and the properties that fulfill a receive are named by `intern`'s IDs,
	/// in `Property` order, so no ID's value orders anything.
	///
	/// The world is built before its graph is validated, so it holds what validation reads: the graph, each node's kind,
	/// construction and cycle identity, the reads, the answers and the receives. The columns that state how a validated
	/// tree is generated (the order a scope builds its children in, its bindings in that order, the loops of builders,
	/// the edges' facts, the parents' segments, the fills, the union facts of what a subtree receives and builds, and the
	/// world's own tables of properties, types, modules and locations) are empty here, and their accessors return
	/// nothing: an order of children that require each other, which validation rejects, would be no fact.
	///
	/// It also holds what the validation call says of its roots, which no validated tree has: for each node the checks
	/// of the roots that reach it (`checksOfRootsReaching(_:)`), since a call validates some trees for cycles and others
	/// only for hidden receives, and a node only the second kind reaches closes no cycle the call reports. An edge's
	/// facts are its target's: the property the target is built as, as cycle validation sees it
	/// (`validatedProperty(of:)`), and whether that is an instantiator (`isBuilder(_:)`).
	///
	/// - Parameter intern: The run's ID of a property, given now where the run has none.
	/// - Returns: `nil` when there is no root, and so no world.
	init?(roots: [TypeFactsRoot], intern: (Property) -> PropertyID) {
		guard let firstRoot = roots.first else {
			return nil
		}
		// The edges' entries among their scopes' properties and fills, which only the columns of a validated tree read.
		var edgeEntries = [Int32]()
		var edgeIsFill = [Bool]()
		var fillHoles = [(edge: Int32, hole: SeamSignature.Hole)]()
		let worldRoot = TypeFactsDeclaration(scope: firstRoot.scope, property: nil, propertyID: nil, erasedToConcreteExistential: false, isFill: false, frame: TypeFactsDeclaration.worldRootFrame)
		let graph = OrderedGraph(root: worldRoot) { declaration in
			if declaration.key.frame == TypeFactsDeclaration.worldRootFrame {
				roots.enumerated().map { frame, root in
					TypeFactsDeclaration(scope: root.scope, property: nil, propertyID: nil, erasedToConcreteExistential: false, isFill: false, frame: Int32(frame))
				}
			} else if declaration.key.frame != TypeFactsDeclaration.noFrame {
				[TypeFactsDeclaration(scope: declaration.scope, property: nil, propertyID: nil, erasedToConcreteExistential: false, isFill: false)]
			} else {
				Self.targets(of: declaration, edgeEntries: &edgeEntries, edgeIsFill: &edgeIsFill, fillHoles: &fillHoles)
			}
		}
		let nodes = graph.nodes
		var labels = TypeFactsInterner<String>()
		var readInterner = TypeFactsInterner<Read>()
		var ownReadsByNode = [[Int32]]()
		for node in nodes {
			guard node.key.frame == TypeFactsDeclaration.noFrame else {
				ownReadsByNode.append([])
				continue
			}
			// Validation judges no pin of a mock root, so no node reads one (`ReadChannel.mock`).
			ownReadsByNode.append(Self.ownReads(of: node, forMockGeneration: false, labels: &labels).map { readInterner.id(of: $0) })
		}
		let readTable = readInterner.values
		let own = BitRows(rowCount: nodes.count, columnCount: readTable.count) { index, insert in
			ownReadsByNode[index].forEach(insert)
		}
		var readsByLabel = [[Int32]](repeating: [], count: labels.values.count)
		for (id, read) in readTable.enumerated() where read.channel.asksAboutLabel {
			readsByLabel[Int(read.label)].append(Int32(id))
		}
		let hidden = BitRows(rowCount: nodes.count, columnCount: readTable.count) { index, insert in
			let node = nodes[index]
			if node.key.frame == TypeFactsDeclaration.noFrame {
				// A label no node reads has no ID, and hides nothing.
				for label in node.scope.declaredLabels {
					guard let labelID = labels.existingID(of: label) else { continue }
					readsByLabel[Int(labelID)].forEach(insert)
				}
			} else {
				// Nothing above a frame answers a read: what its root is not given has no answer.
				for read in readTable.indices {
					insert(Int32(read))
				}
			}
		}
		let reads = ReadsFromAbove(graph: graph, own: own, hidden: hidden)
		let readColumns = ReadColumns(of: reads, nodeCount: nodes.count, readTable: readTable, labelCount: labels.values.count)
		let answers = Self.answersByValue(of: graph, roots: roots, reads: reads, readTable: readTable, readColumns: readColumns, labels: labels, intern: intern)
		let receives = Self.receiveColumns(of: graph, readInterner: &readInterner, labels: &labels, intern: intern)
		self.graph = graph
		// The roots of a validation call can be production's and mocks' together, so the world is no one mock root's: its
		// reads and constructions are production's, and it owes every fact a producer has yet to state (`owedFacts(of:)`).
		forMockGeneration = false
		kinds = nodes.map(Self.kind(of:))
		constructions = nodes.map { Self.construction(of: $0, forMockGeneration: false) }
		self.reads = reads
		self.readTable = readTable
		labelTexts = labels.values
		readColumn = readColumns.readColumn
		readOffsets = readColumns.readOffsets
		labelColumn = readColumns.labelColumn
		labelOffsets = readColumns.labelOffsets
		answerIsBeingBuilt = answers.isBeingBuilt
		answerTexts = answers.texts
		answerKeys = Array(0..<Int32(answers.texts.count))
		variants = answers.variants
		outcomes = Self.outcomes(of: answers.variants, isBeingBuilt: answers.isBeingBuilt, readTable: readTable, readColumns: readColumns, graph: graph)
		cycleIDs = Self.cycleIdentities(of: nodes).ids
		// Node 0's one variant calls each frame's, and each frame's one edge calls its root's body.
		rootVariants = answers.variants.callees(of: 0).compactMap { answers.variants.callees(of: Int($0)).first }
		answerForms = answers.forms
		formOffsets = answers.formOffsets
		formColumn = answers.formColumn
		answerSets = answers.sets
		receiveStarts = receives.starts
		receiveEnds = receives.ends
		receiveColumn = receives.receives
		acceptedColumn = receives.accepted
		validatedProperties = nodes.map { node in
			guard node.key.leaf == .none, let propertyID = node.propertyID else { return -1 }
			return node.scope.interner.asValidatedForDependencyCycles(propertyID).raw
		}
		rootChecks = Self.rootChecks(of: graph, roots: roots)
		// What only a validated tree has, or only its generation reads: each offset column still has an entry per node, so
		// a node's run is empty.
		let noRows = BitRows(rowCount: 0, columnCount: 0) { _, _ in }
		nodeProperties = []
		builtTypes = []
		edgeFacts = []
		bindings = []
		bindingOffsets = [Int32](repeating: 0, count: nodes.count + 1)
		twins = []
		self.receives = TypeFactsReceives(received: noRows, required: noRows, onlyIfAvailableUnwrapped: noRows, requiredAliasFulfilling: noRows)
		typesBeneath = noRows
		typesDeclaredEscaping = noRows
		holesBeneath = noRows
		parentOffsets = [Int32](repeating: 0, count: nodes.count + 1)
		parents = []
		fills = []
		fillPathEntries = []
		propertyFacts = TypeFactsPropertyFacts(labels: [], unwrapped: [], isOptional: [], instances: [], isBuilder: [], formsReadOffsets: [], formsRead: [], formsProvidedOffsets: [], formsProvided: [])
		// An answer's declaration is an ID of the world's table of properties, which this world does not hold: its answers
		// name their forms by the run's IDs (`answerForms`).
		answerProperties = []
		propertyTable = []
		typeTable = []
		moduleNames = []
		declarationLocations = []
	}

	/// `providesFormRead(by:_:beneath:)` of a world of several roots: whether the forms the answer's declaration provides
	/// hold a property that a receive making `read` accepts, among the receives of the declaration's subtree that read
	/// from above it. A node that declares the read's label answers the reads beneath it itself, so the walk goes no
	/// further there, and it visits a child only where the child's subtree makes the read. Each node is visited once.
	func formsProvideRead(by answer: AnswerID, _ read: ReadID, beneath declaration: DeclarationID) -> Bool {
		let forms = forms(of: answer)
		let label = readTable[Int(read)].label
		var visited = Set<DeclarationID>()
		var unvisited = [declaration]
		while let index = unvisited.popLast() {
			guard visited.insert(index).inserted else { continue }
			for receive in receives(of: index) where receive.read == read {
				guard !acceptedProperties(of: receive).contains(where: forms.contains) else { return true }
			}
			let node = graph.nodes[Int(index)]
			guard node.key.frame == TypeFactsDeclaration.noFrame, label < 0 || !node.scope.declaredLabels.contains(labelTexts[Int(label)]) else { continue }
			for target in edges(from: index) where reads(of: target).contains(read) {
				unvisited.append(target)
			}
		}
		return false
	}

	/// The elements of the columns that state how a validated tree is generated, and what each node's accessors of them
	/// answer: none in a world of several roots, which is built before validation and whose validation reads none of
	/// them. The bit rows of what a subtree receives and holds beneath it are not counted: that world gives them no row.
	var generationSideElementCount: Int {
		var count = nodeProperties.count + builtTypes.count + edgeFacts.count + bindings.count + twins.count
		count += parents.count + fills.count + fillPathEntries.count
		count += propertyFacts.labels.count + propertyFacts.formsRead.count + propertyFacts.formsProvided.count
		count += answerProperties.count
		count += propertyTable.count + typeTable.count + moduleNames.count + declarationLocations.count
		for index in graph.nodes.indices {
			count += edgeFacts(from: index).count + worldBindings(of: index).count + parents(of: index).count
		}
		return count
	}

	/// The property the node is built as, as cycle validation sees it, by the raw value of the run's ID: what an edge
	/// to the node declares, with a `LazilyInstantiated` as the value it stands for. -1 for a node built as no property
	/// (node 0, a frame, a root's declaration), for a leaf, and in a world of one root, which keeps no such column.
	func validatedProperty(of declaration: DeclarationID) -> Int32 {
		validatedProperties.isEmpty ? -1 : validatedProperties[Int(declaration)]
	}

	/// Whether the node is built as an instantiator of any kind, which builds its type each time it is called
	/// (`ScopeGenerator.isBuilder(_:)`): the hop that defers a cycle. A `LazilyInstantiated` is none, and neither is a
	/// leaf.
	func isBuilder(_ declaration: DeclarationID) -> Bool {
		switch kinds[Int(declaration)] {
		case .instantiator, .sendableInstantiator, .erasedInstantiator, .sendableErasedInstantiator:
			true
		case .constant, .lazy, .sendableLazy, .alias, .hole:
			false
		}
	}

	/// The checks of the roots that reach the node, each of which the validation call runs on it: a node no root
	/// validated for cycles reaches is judged for none. Node 0 is reached by no root, and a world of one root, which is
	/// built once its tree has passed every check, keeps no such column and answers none.
	func checksOfRootsReaching(_ declaration: DeclarationID) -> TypeFactsRootChecks {
		TypeFactsRootChecks(rawValue: rootChecks.isEmpty ? 0 : rootChecks[Int(declaration)])
	}

	/// For each node, the checks of the roots that reach it along the graph's edges, a fill's included: a fill no walk
	/// enters is then counted as checked, which sends a graph to the walk and clears none. Each node is taken up again
	/// only when a root brings it a check it lacked, so the pass visits an edge at most once per check.
	private static func rootChecks(of graph: OrderedGraph<TypeFactsDeclaration>, roots: [TypeFactsRoot]) -> [UInt8] {
		var checks = [UInt8](repeating: 0, count: graph.nodes.count)
		var pending = [Int32]()
		// Node 0's edges lead to the frames, in the roots' order.
		for (frame, root) in zip(graph.edges(from: 0), roots) {
			checks[Int(frame)] = root.checks.rawValue
			pending.append(frame)
		}
		while let reached = pending.popLast() {
			for target in graph.edges(from: Int(reached)) where checks[Int(target)] | checks[Int(reached)] != checks[Int(target)] {
				checks[Int(target)] |= checks[Int(reached)]
				pending.append(target)
			}
		}
		return checks
	}

	/// Whether the node stands for no declaration: node 0 of a world of several roots, or a frame.
	func isFrame(_ index: Int) -> Bool {
		graph.nodes[index].key.frame != TypeFactsDeclaration.noFrame
	}

	/// An answer by value: what asks, the forms the nearest declaration provides as an ID of their run, and whether that
	/// declaration is still being built where it answers.
	private struct AnswerValue: Hashable {
		let channel: ReadChannel
		let forms: Int32
		let isBeingBuilt: Bool
	}

	private struct AnswersByValue {
		let variants: TypeFactsVariants
		let sets: TypeFactsAnswerSets
		let isBeingBuilt: [Bool]
		let texts: [String]
		let forms: [Int32]
		let formOffsets: [Int32]
		let formColumn: [PropertyID]
	}

	/// What answers each read at each edge, by value and by ID: a node answers a read of a label it declares with the
	/// forms its declaration provides, being built where the edge builds that declaration, and a frame answers a read of
	/// a label its root is given with the given properties of that label. Each read's answers over every route are a set
	/// per node; no variant keys by an answer.
	private static func answersByValue(
		of graph: OrderedGraph<TypeFactsDeclaration>,
		roots: [TypeFactsRoot],
		reads: ReadsFromAbove,
		readTable: [Read],
		readColumns: ReadColumns,
		labels: TypeFactsInterner<String>,
		intern: (Property) -> PropertyID,
	) -> AnswersByValue {
		var formsIDByProperties = [[PropertyID]: Int32]()
		var formOffsets: [Int32] = [0]
		var formColumn = [PropertyID]()
		var formTexts = [String]()
		/// The ID of the run of `forms`, which are in `Property` order.
		func formsID(of forms: [Property]) -> Int32 {
			let properties = forms.map(intern)
			if let id = formsIDByProperties[properties] {
				return id
			} else {
				let id = Int32(formTexts.count)
				formsIDByProperties[properties] = id
				formColumn.append(contentsOf: properties)
				formOffsets.append(Int32(formColumn.count))
				formTexts.append(forms.map(\.asSource).joined(separator: ", "))
				return id
			}
		}
		// A record's declarations are the same whatever property it is built as, so each record's are interned once.
		var formsByLabelByRecord = [ObjectIdentifier: [Int32: Int32]]()
		var formsByLabelByNode = [[Int32: Int32]]()
		var sourceByEdge = [Int32]()
		var edgeTargets = [Int32]()
		for index in graph.nodes.indices {
			for target in graph.edges(from: index) {
				sourceByEdge.append(Int32(index))
				edgeTargets.append(target)
			}
			let node = graph.nodes[index]
			var formsByLabel = [Int32: Int32]()
			if node.key.frame == TypeFactsDeclaration.noFrame {
				if let known = formsByLabelByRecord[node.key.record] {
					formsByLabel = known
				} else {
					for (property, forms) in node.scope.sortedDeclaredPropertyForms {
						guard let label = labels.existingID(of: property.label) else { continue }
						formsByLabel[label] = formsID(of: forms.sorted())
					}
					formsByLabelByRecord[node.key.record] = formsByLabel
				}
			} else if node.key.frame != TypeFactsDeclaration.worldRootFrame {
				// The given properties are in `Property` order, so those of one label are adjacent.
				var given = [Property]()
				for property in roots[Int(node.key.frame)].givenProperties {
					if let last = given.last, last.label != property.label {
						if let label = labels.existingID(of: last.label) {
							formsByLabel[label] = formsID(of: given)
						}
						given.removeAll(keepingCapacity: true)
					}
					given.append(property)
				}
				if let last = given.last, let label = labels.existingID(of: last.label) {
					formsByLabel[label] = formsID(of: given)
				}
			}
			formsByLabelByNode.append(formsByLabel)
		}
		var answerIDByValue = [AnswerValue: Int32]()
		var answerValues = [AnswerValue]()
		/// The answer the source of `edge` gives the read, or `nil` where it declares nothing of the read's label.
		func answer(atEdge edge: Int, to readID: Int32) -> Int32? {
			let read = readTable[Int(readID)]
			guard let forms = formsByLabelByNode[Int(sourceByEdge[edge])][read.label] else {
				return nil
			}
			let isBeingBuilt = graph.nodes[Int(edgeTargets[edge])].property.map { labels.existingID(of: $0.label) == read.label } ?? false
			let value = AnswerValue(channel: read.channel, forms: forms, isBeingBuilt: isBeingBuilt)
			if let id = answerIDByValue[value] {
				return id
			} else {
				let id = Int32(answerValues.count)
				answerIDByValue[value] = id
				answerValues.append(value)
				return id
			}
		}
		let variants = TypeFactsVariants(
			graph: graph,
			reads: reads,
			rootAnswer: { _ in nil },
			binding: { edge, readID in
				answer(atEdge: edge, to: readID).map { VariantBinding(answer: $0, declaration: sourceByEdge[edge]) }
			},
			family: { _, family in family },
			// Validation judges every answer of a read's set, so no answer picks a body: each read keys as a parameter.
			key: { _, _ in optionalParameterKey },
		)
		let sets = TypeFactsAnswerSets(graph: graph, readOffsets: readColumns.readOffsets, readColumn: readColumns.readColumn, binding: answer)
		return AnswersByValue(
			variants: variants,
			sets: sets,
			isBeingBuilt: answerValues.map(\.isBeingBuilt),
			texts: answerValues.map { "\($0.channel.name) \(formTexts[Int($0.forms)])\($0.isBeingBuilt ? " being built" : "")" },
			forms: answerValues.map(\.forms),
			formOffsets: formOffsets,
			formColumn: formColumn,
		)
	}

	/// The properties that fulfill a receive, as validation accepts them (`recordHiddenReceives`): a receive of an optional
	/// property resolves to its non-optional form too, and an alias only if available reads the optional form of the
	/// property it is fulfilled by too (`Property.formsReadByOnlyIfAvailableReceive`).
	static func acceptedProperties(of receive: OwnReceive) -> [Property] {
		if receive.alias != nil, receive.onlyIfAvailable {
			receive.property.formsReadByOnlyIfAvailableReceive
		} else if receive.property.asUnwrappedProperty == receive.property {
			[receive.property]
		} else {
			[receive.property, receive.property.asUnwrappedProperty]
		}
	}

	private struct ReceiveColumns {
		var starts = [Int32]()
		var ends = [Int32]()
		var receives = [TypeFactsReceive]()
		var accepted = [PropertyID]()
	}

	/// The receives each node's own type makes, in declaration order, each with the read it makes and the properties that
	/// fulfill it (`acceptedProperties(of:)`). A record's receives are the same whatever property it is built as, so every
	/// node of one record shares one run. A frame receives nothing, and neither does a leaf, whose scope's own node
	/// holds the receives (`ownReads(of:forMockGeneration:labels:)`).
	private static func receiveColumns(
		of graph: OrderedGraph<TypeFactsDeclaration>,
		readInterner: inout TypeFactsInterner<Read>,
		labels: inout TypeFactsInterner<String>,
		intern: (Property) -> PropertyID,
	) -> ReceiveColumns {
		var columns = ReceiveColumns()
		var runByRecord = [ObjectIdentifier: (start: Int32, end: Int32)]()
		for node in graph.nodes {
			guard node.key.frame == TypeFactsDeclaration.noFrame, node.key.leaf == .none else {
				columns.starts.append(0)
				columns.ends.append(0)
				continue
			}
			if let run = runByRecord[node.key.record] {
				columns.starts.append(run.start)
				columns.ends.append(run.end)
			} else {
				let start = Int32(columns.receives.count)
				for receive in ownReceives(of: node.scope) {
					let accepted = acceptedProperties(of: receive)
					columns.receives.append(TypeFactsReceive(
						read: readInterner.id(of: Read(receive.onlyIfAvailable ? .optionalValue : .value, label: labels.id(of: receive.property.label))),
						acceptedStart: Int32(columns.accepted.count),
						acceptedCount: Int32(accepted.count),
						isRequired: !receive.onlyIfAvailable,
						alias: receive.alias.map { intern($0).raw } ?? -1,
					))
					columns.accepted.append(contentsOf: accepted.map(intern))
				}
				let end = Int32(columns.receives.count)
				runByRecord[node.key.record] = (start, end)
				columns.starts.append(start)
				columns.ends.append(end)
			}
		}
		return columns
	}
}
