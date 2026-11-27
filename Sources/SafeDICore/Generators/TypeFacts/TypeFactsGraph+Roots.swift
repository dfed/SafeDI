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
}

extension TypeFactsGraph {
	/// One world of every root of a validation call, built before any of them is validated, so nothing in it is an error:
	/// a read nothing answers has the answer `none`, and a read answered by a declaration that provides no property its
	/// receive accepts has that declaration's forms, for the caller to judge. Ordinary generation builds no such world:
	/// only validation over per-type facts reads it.
	///
	/// The graph keeps one root. Node 0 stands for no declaration and has an edge to one frame per root, in the roots'
	/// order; a frame binds exactly what its root is given and has one edge, to its root's declaration. A frame hides
	/// every label, so no answer passes from one root's frame to another root's nodes: a declaration two roots reach has a
	/// variant per vector of answers, one per root where their answers differ.
	///
	/// An answer is interned by value: the channel that asks, the forms the nearest declaration provides, and whether
	/// that declaration is still being built at the edge. A variant keys by the answers themselves, with neither
	/// parameter rule applied: validation judges an answer, where generation only passes it on. The forms and the
	/// properties that fulfill a receive are named by `intern`'s IDs, in `Property` order, so no ID's value orders
	/// anything.
	///
	/// - Parameter intern: The run's ID of a property, given now where the run has none.
	/// - Returns: `nil` when there is no root, and so no world.
	init?(roots: [TypeFactsRoot], intern: (Property) -> PropertyID) {
		guard let firstRoot = roots.first else {
			return nil
		}
		var instantiatedEdgeCounts = [Int32]()
		let worldRoot = TypeFactsDeclaration(scope: firstRoot.scope, property: nil, propertyID: -1, erasedToConcreteExistential: false, isFill: false, frame: TypeFactsDeclaration.worldRootFrame)
		let graph = OrderedGraph(root: worldRoot) { declaration in
			if declaration.key.frame == TypeFactsDeclaration.worldRootFrame {
				instantiatedEdgeCounts.append(Int32(roots.count))
				return roots.enumerated().map { frame, root in
					TypeFactsDeclaration(scope: root.scope, property: nil, propertyID: -1, erasedToConcreteExistential: false, isFill: false, frame: Int32(frame))
				}
			} else if declaration.key.frame != TypeFactsDeclaration.noFrame {
				instantiatedEdgeCounts.append(1)
				return [TypeFactsDeclaration(scope: declaration.scope, property: nil, propertyID: -1, erasedToConcreteExistential: false, isFill: false)]
			} else {
				return Self.targets(of: declaration, instantiatedEdgeCounts: &instantiatedEdgeCounts)
			}
		}
		var labels = LabelInterner()
		var readInterner = ReadInterner()
		var ownReadsByNode = [[Int32]]()
		for node in graph.nodes {
			guard node.key.frame == TypeFactsDeclaration.noFrame else {
				ownReadsByNode.append([])
				continue
			}
			// Validation judges no pin of a mock root, so no node reads one (`ReadChannel.mock`).
			ownReadsByNode.append(Self.ownReads(of: node.scope.identity, builtAs: node.property, forMockGeneration: false, labels: &labels).map { readInterner.id(of: $0) })
		}
		let readTable = readInterner.reads
		let own = BitRows(rowCount: graph.nodes.count, columnCount: readTable.count) { index, insert in
			ownReadsByNode[index].forEach(insert)
		}
		let readsByLabel = readInterner.readsByLabel(labelCount: labels.labels.count)
		let hidden = BitRows(rowCount: graph.nodes.count, columnCount: readTable.count) { index, insert in
			let node = graph.nodes[index]
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
		let readColumns = ReadColumns(of: reads, nodeCount: graph.nodes.count, readTable: readTable, labelCount: labels.labels.count)
		let answers = Self.answersByValue(of: graph, roots: roots, reads: reads, readTable: readTable, labels: labels, intern: intern)
		let receives = Self.receiveColumns(of: graph, readInterner: &readInterner, labels: &labels, intern: intern)
		self.graph = graph
		self.instantiatedEdgeCounts = instantiatedEdgeCounts
		constructions = graph.nodes.map(\.construction)
		self.reads = reads
		self.readTable = readTable
		labelTexts = labels.labels
		readColumn = readColumns.readColumn
		readOffsets = readColumns.readOffsets
		labelColumn = readColumns.labelColumn
		labelOffsets = readColumns.labelOffsets
		answerIsBeingBuilt = answers.isBeingBuilt
		answerTexts = answers.texts
		answerKeys = Array(0..<Int32(answers.texts.count))
		variants = answers.variants
		outcomes = Self.outcomes(of: answers.variants, isBeingBuilt: answers.isBeingBuilt, readTable: readTable, readColumns: readColumns, graph: graph)
		cycleIDs = Self.cycleIDs(of: graph.nodes)
		// Node 0's one variant calls each frame's, and each frame's one edge calls its root's body.
		rootVariants = answers.variants.callees(of: 0).compactMap { answers.variants.callees(of: Int($0)).first }
		answerForms = answers.forms
		formOffsets = answers.formOffsets
		formColumn = answers.formColumn
		receiveStarts = receives.starts
		receiveEnds = receives.ends
		receiveColumn = receives.receives
		acceptedColumn = receives.accepted
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
		let isBeingBuilt: [Bool]
		let texts: [String]
		let forms: [Int32]
		let formOffsets: [Int32]
		let formColumn: [PropertyID]
	}

	/// What answers each read at each edge, by value and by ID: a node answers a read of a label it declares with the
	/// forms its declaration provides, being built where the edge builds that declaration, and a frame answers a read of
	/// a label its root is given with the given properties of that label. Every variant keys by its answers as they are.
	private static func answersByValue(
		of graph: OrderedGraph<TypeFactsDeclaration>,
		roots: [TypeFactsRoot],
		reads: ReadsFromAbove,
		readTable: [Read],
		labels: LabelInterner,
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
		let variants = TypeFactsVariants(
			graph: graph,
			reads: reads,
			rootAnswer: { _ in nil },
			binding: { edge, readID in
				let read = readTable[Int(readID)]
				let node = sourceByEdge[edge]
				guard let forms = formsByLabelByNode[Int(node)][read.label] else {
					return nil
				}
				let isBeingBuilt = graph.nodes[Int(edgeTargets[edge])].property.map { labels.existingID(of: $0.label) == read.label } ?? false
				let value = AnswerValue(channel: read.channel, forms: forms, isBeingBuilt: isBeingBuilt)
				if let id = answerIDByValue[value] {
					return VariantBinding(answer: id, declaration: node)
				} else {
					let id = Int32(answerValues.count)
					answerIDByValue[value] = id
					answerValues.append(value)
					return VariantBinding(answer: id, declaration: node)
				}
			},
			family: { _, family in family },
			key: { _, answer in answer },
		)
		return AnswersByValue(
			variants: variants,
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
	/// node of one record shares one run.
	private static func receiveColumns(
		of graph: OrderedGraph<TypeFactsDeclaration>,
		readInterner: inout ReadInterner,
		labels: inout LabelInterner,
		intern: (Property) -> PropertyID,
	) -> ReceiveColumns {
		var columns = ReceiveColumns()
		var runByRecord = [ObjectIdentifier: (start: Int32, end: Int32)]()
		for node in graph.nodes {
			guard node.key.frame == TypeFactsDeclaration.noFrame else {
				columns.starts.append(0)
				columns.ends.append(0)
				continue
			}
			if let run = runByRecord[node.key.record] {
				columns.starts.append(run.start)
				columns.ends.append(run.end)
			} else {
				let start = Int32(columns.receives.count)
				for receive in ownReceives(of: node.scope.identity) {
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
